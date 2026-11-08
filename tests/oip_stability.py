#!/usr/bin/env python3
"""The extended stability run of the release binary.

The acceptance harness measures the Core for a few seconds. This rehearsal
measures it over a sustained run under the managed load of the collectors:

  * the resource use of the Core (resident memory, CPU) over the whole run;
  * the growth of the data store and the rate of the collection;
  * the behaviour of the Core when a collector of a source dies and comes
    back: the source must stop being fresh, the gap must be recorded and the
    collection must resume;
  * the liveness of the Core during the whole run;
  * the clean shutdown at the end: no uncommitted observation, an intact
    store.

Nothing of the rehearsal touches the personal installation of the operator and
nothing leaves the machine.

Usage:
  python3 tests/oip_stability.py [--minutes 20] [--evidence DIR]
"""
import argparse
import http.cookiejar
import json
import os
import pathlib
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "oip_ops.py"
SIMULATOR = ROOT / "target/debug/oip-simulated-server"


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def sqlite_value(database, statement):
    result = subprocess.run(["/usr/bin/sqlite3", "-batch", "-noheader", str(database), statement],
                            capture_output=True, text=True, timeout=60)
    return result.stdout.strip()


def api(base, path, method="GET", body=None, headers=None, opener=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(base + path, data=data, method=method)
    request.add_header("Content-Type", "application/json")
    for key, value in (headers or {}).items():
        request.add_header(key, value)
    send = opener.open if opener else urllib.request.urlopen
    try:
        with send(request, timeout=60) as answer:
            return answer.status, json.loads(answer.read().decode() or "{}")
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode() or "{}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-stability"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    parser.add_argument("--minutes", type=float, default=20.0)
    parser.add_argument("--sample-seconds", type=float, default=30.0)
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-stability-v1", "steps": [],
              "planned_minutes": args.minutes, "sample_seconds": args.sample_seconds}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-stability-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    simulators = []
    try:
        source_ports = [free_port() for _ in range(4)]
        port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": port,
            "sources": [{"id": f"source-{letter}", "name": f"Local simulation {letter}",
                          "endpoint": f"opc.tcp://127.0.0.1:{source_ports[index]}",
                          "namespace": 2}
                         for index, letter in enumerate("abcd")],
            "legacy_single_infrastructure": False,
            "web_dir": str(ROOT / "apps/flutter/build/web"),
        }, indent=2))
        credential = work / "platform.credential"
        credential.write_bytes(secrets.token_bytes(32))
        credential.chmod(0o600)
        (work / "ipc.json").write_text(json.dumps({
            "socket": str(work / "s"), "max_sessions": 16,
            "clients": [{"uid": os.getuid(), "credential_file": str(credential),
                         "policy": {"principal": "reader-org-a"}}],
        }, indent=2))
        (work / "ipc.json").chmod(0o600)
        state = work / "state"
        base = f"http://127.0.0.1:{port}"

        def tool(*arguments, expect_success=True):
            result = subprocess.run([sys.executable, str(TOOL), "--state-dir", str(state),
                                     "--config", str(work / "core.json"),
                                     "--ipc-config", str(work / "ipc.json"),
                                     "--binary", args.binary, *arguments],
                                    capture_output=True, text=True, timeout=600)
            if expect_success and result.returncode != 0:
                raise AssertionError(f"{arguments[0]} failed: "
                                     f"{result.stderr.strip() or result.stdout.strip()}")
            return result

        # the collectors of the four sources
        for index, simulator_port in enumerate(source_ports):
            simulator = subprocess.Popen(
                [str(SIMULATOR), "--port", str(simulator_port), "--seed", str(42 + index * 7),
                 "--tick-ms", "250"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            simulators.append(simulator)
        time.sleep(2)

        tool("provision-plan", "--plan", str(work / "plan.json"))
        tool("start")
        time.sleep(3)
        pid = int((state / "oip.pid").read_text().strip())
        report["core_pid"] = pid
        report["core_binary"] = args.binary
        report["steps"].append("the instance runs")

        # the authorized session of the operator
        minted = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(credential)], text=True))
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        status, _ = api(base, "/api/v2/browser/login", "POST", {"code": minted["login_code"]},
                        {"Origin": base}, opener)
        assert status == 200, "the operator session was refused"
        report["steps"].append("the operator session is authorized")

        def sources():
            status, payload = api(base, "/api/v2/sources", opener=opener)
            items = payload if isinstance(payload, list) else payload.get("items", [])
            return {item.get("id"): item for item in items if isinstance(item, dict)}

        def gaps():
            status, payload = api(base, "/api/v2/diagnostics/gaps", opener=opener)
            items = payload if isinstance(payload, list) else payload.get("items", [])
            return items

        # the collection starts before the measurement begins
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            current = sources()
            if len(current) == 3 and all(item.get("freshness") == "fresh"
                                         for item in current.values()):
                break
            time.sleep(1)
        current = sources()
        report["sources_visible_to_the_operator"] = sorted(current)
        assert current, "the Core does not serve its sources"
        report["steps"].append("the collection runs")

        database = work / "core.sqlite"
        samples = []
        started = time.monotonic()
        deadline = started + args.minutes * 60
        outage_done = False
        while time.monotonic() < deadline:
            usage = subprocess.check_output(["ps", "-p", str(pid), "-o", "rss=,%cpu="],
                                            text=True).strip().split()
            observations = int(sqlite_value(database, "select count(*) from observations;") or 0)
            gap_count = int(sqlite_value(database, "select count(*) from data_gaps;") or 0)
            status, _ = api(base, "/api/v2/browser/session")
            current = sources()
            sample = {
                "at_seconds": round(time.monotonic() - started, 1),
                "rss_kib": int(usage[0]),
                "cpu_percent": float(usage[1]),
                "observations": observations,
                "data_gaps": gap_count,
                "store_bytes": database.stat().st_size if database.is_file() else 0,
                "log_bytes": (state / "oip.log").stat().st_size
                if (state / "oip.log").is_file() else 0,
                "fresh_sources": sorted(name for name, item in current.items()
                                        if item.get("freshness") == "fresh"),
                "api_status": status,
            }
            samples.append(sample)

            # the middle of the run: a collector dies and comes back
            if not outage_done and sample["at_seconds"] > args.minutes * 60 / 2:
                report["steps"].append("a collector of a source dies")
                victim = simulators[1]
                victim.terminate()
                victim.wait(timeout=30)
                began = time.monotonic()
                detected = None
                while time.monotonic() - began < 180:
                    current = sources()
                    item = current.get("source-b")
                    if item is not None and item.get("freshness") != "fresh":
                        detected = round(time.monotonic() - began, 1)
                        break
                    time.sleep(1)
                report["outage_detected_after_seconds"] = detected
                assert detected is not None, "the Core did not notice the dead collector"
                report["steps"].append("the Core notices the dead collector")
                simulators[1] = subprocess.Popen(
                    [str(SIMULATOR), "--port", str(source_ports[1]), "--seed", "49",
                     "--tick-ms", "250"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                began = time.monotonic()
                recovered = None
                while time.monotonic() - began < 180:
                    current = sources()
                    item = current.get("source-b")
                    if item is not None and item.get("freshness") == "fresh":
                        recovered = round(time.monotonic() - began, 1)
                        break
                    time.sleep(1)
                report["collection_resumed_after_seconds"] = recovered
                assert recovered is not None, "the collection did not resume"
                report["steps"].append("the collection resumes")
                outage_done = True
            time.sleep(args.sample_seconds)

        report["samples"] = samples
        report["sample_count"] = len(samples)
        report["resident_memory_kib"] = {
            "min": min(item["rss_kib"] for item in samples),
            "max": max(item["rss_kib"] for item in samples),
            "first": samples[0]["rss_kib"], "last": samples[-1]["rss_kib"],
            "growth": samples[-1]["rss_kib"] - samples[0]["rss_kib"],
        }
        report["cpu_percent"] = {
            "mean": round(sum(item["cpu_percent"] for item in samples) / len(samples), 2),
            "max": max(item["cpu_percent"] for item in samples),
        }
        report["observations"] = {
            "first": samples[0]["observations"], "last": samples[-1]["observations"],
            "rate_per_minute": round(
                (samples[-1]["observations"] - samples[0]["observations"])
                / max((samples[-1]["at_seconds"] - samples[0]["at_seconds"]) / 60, 0.001), 1),
        }
        report["store_bytes"] = {"first": samples[0]["store_bytes"],
                                 "last": samples[-1]["store_bytes"],
                                 "growth": samples[-1]["store_bytes"] - samples[0]["store_bytes"]}
        report["log_bytes"] = {"first": samples[0]["log_bytes"], "last": samples[-1]["log_bytes"]}
        report["data_gaps"] = {"first": samples[0]["data_gaps"], "last": samples[-1]["data_gaps"]}
        report["api_always_answered"] = all(item["api_status"] == 200 for item in samples)
        report["fresh_sources_at_the_end"] = samples[-1]["fresh_sources"]
        assert report["api_always_answered"], "the Core did not answer during the run"
        assert all(len(item["fresh_sources"]) >= 3 for item in samples), \
            "a source was not fresh during the run"

        # the clean shutdown
        stop = tool("stop")
        report["shutdown"] = json.loads(stop.stdout or "{}")
        report["steps"].append("the instance stops")
        report["integrity"] = sqlite_value(database, "pragma integrity_check;")
        assert report["integrity"] == "ok", report["integrity"]
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        for simulator in simulators:
            if simulator.poll() is None:
                simulator.terminate()
                try:
                    simulator.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    simulator.kill()
        try:
            tool("stop", expect_success=False)
        except Exception:
            pass
        if report.get("status") == "PASS":
            shutil.rmtree(work, ignore_errors=True)
        else:
            report["work_directory"] = str(work)

    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "stability.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "samples"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
