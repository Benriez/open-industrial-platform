#!/usr/bin/env python3
"""The performance of the Overview workstation of the managed surface (G7, G8).

The Overview is the workstation the operator opens first and returns to. A
surface that freezes it for a second is a surface that cannot be operated, so
the rehearsal measures what the operator feels while the Overview works on the
**real** Core: the latency of every interaction, the frames of the browser, the
long tasks of the main thread, the memory the surface retains and the frames
the compositor presents.

The rehearsal starts a disposable Core with four live collectors, waits until
the Core has recorded the collection events that the Overview lists, and then
drives the real surface in the browser
(`apps/flutter/test/browser_overview_performance_2027.mjs`) with the session of
the operator. The numbers of the surface are the numbers of the Core: the
counts of the status strip, the records of the activity list and the kind of
the event filter are read from the authorized API and compared with the
surface.

The budgets are the claim of the journey, the numbers are the measurement, and
the scope is the client of this machine on its loopback — a **local
measurement, not an SLA**. The instance is disposable and owns its store:
nothing of the installation of the operator is touched, no private endpoint is
contacted and no hardware is invented.

Usage:
  python3 tests/oip_overview_performance_2027.py [--evidence DIR]
"""
import argparse
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

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "oip_ops.py"
SIMULATOR = ROOT / "target/debug/oip-simulated-server"


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def playwright_module():
    """The Playwright module of the browser scripts."""
    module = os.environ.get("PLAYWRIGHT_MODULE")
    if module:
        return module
    candidate = ROOT / "apps/flutter/test/node_modules/playwright/index.mjs"
    if not candidate.is_file():
        raise AssertionError(f"the Playwright module is missing: {candidate}")
    return str(candidate)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-overview-performance"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-overview-performance-rehearsal-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-overview-performance-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    simulators = []
    try:
        if not SIMULATOR.is_file():
            raise AssertionError(f"the simulated collector is missing: {SIMULATOR}")
        # The Overview lists the sources, the devices and the collection events
        # of the Core: the rehearsal needs collectors that really deliver them.
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
        credential = work / "reader-org-a.credential"
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

        def start_the_collectors():
            for index, simulator_port in enumerate(source_ports):
                log = open(work / f"simulator-{simulator_port}.log", "ab")
                simulators.append(subprocess.Popen(
                    [str(SIMULATOR), "--port", str(simulator_port),
                     "--seed", str(42 + index * 7), "--tick-ms", "250"],
                    stdout=log, stderr=log))
            time.sleep(3)

        SESSION = {}

        def the_reader():
            """One authorized session for the reads of the rehearsal.

            The one-time code may be used **once**: a second login with the
            same code is refused. The rehearsal therefore opens one session
            and reads every route with it.
            """
            import http.cookiejar
            import urllib.request
            if "opener" not in SESSION:
                jar = http.cookiejar.CookieJar()
                opener = urllib.request.build_opener(
                    urllib.request.HTTPCookieProcessor(jar))
                login = urllib.request.Request(
                    f"{base}/api/v2/browser/login",
                    data=json.dumps({"code": MINTED["login_code"]}).encode(),
                    headers={"Content-Type": "application/json", "Origin": base},
                    method="POST")
                with opener.open(login, timeout=60) as answer:
                    assert json.loads(answer.read().decode()).get("authenticated") is True
                SESSION["opener"] = opener
            return SESSION["opener"]

        def a_get(path):
            import urllib.request
            request = urllib.request.Request(f"{base}{path}", headers={"Origin": base})
            with the_reader().open(request, timeout=60) as answer:
                return json.loads(answer.read().decode())

        def wait_for_the_collection_events(timeout=180):
            """The Core has recorded the events that the Overview lists.

            The Overview reads the limited API window of the Core; a window
            without an event would render an empty list and the journey would
            measure an empty surface. The rehearsal therefore waits for the
            event of the first connection of a collector.
            """
            deadline = time.time() + timeout
            last = None
            while time.time() < deadline:
                try:
                    payload = a_get("/api/v2/events")
                except Exception:  # noqa: BLE001 - the instance may still boot
                    payload = {}
                last = payload
                if payload.get("collection_events") or payload.get("records"):
                    return payload
                time.sleep(2)
            raise AssertionError(
                f"the Core recorded no collection event in {timeout} seconds: "
                f"{json.dumps(last)[:400]}")

        start_the_collectors()
        tool("provision-plan", "--plan", str(work / "plan.json"))
        tool("start")
        time.sleep(5)
        report["steps"].append("the instance runs with its live collectors")

        MINTED = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(credential)], text=True))
        events = wait_for_the_collection_events()
        kinds = sorted({key for record in events.get("collection_events", [])
                        for key in record})
        sources = a_get("/api/v2/sources")
        devices = a_get("/api/v2/devices")
        report["the_events_of_the_core"] = {
            "the_kinds": kinds,
            "the_collection_events": len(events.get("collection_events", [])),
            "the_records": len(events.get("records", [])),
        }
        report["the_sources_of_the_core"] = len(sources)
        report["the_devices_of_the_core"] = len(devices)
        assert kinds, "the Core delivered an event without a kind"
        report["steps"].append("the Core recorded the collection events of the collectors")

        result = subprocess.run(
            ["node", str(ROOT / "apps/flutter/test/browser_overview_performance_2027.mjs")],
            cwd=ROOT, capture_output=True, text=True, timeout=2400,
            env=dict(os.environ,
                     OIP_URL=base,
                     OIP_EVIDENCE_DIR=str(evidence),
                     OIP_REVISION=subprocess.check_output(
                         ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                     OIP_IPC_SOCKET=str(work / "s"),
                     OIP_BROWSER_CREDENTIAL=str(credential),
                     OIP_SERVER_BIN=args.binary,
                     PLAYWRIGHT_MODULE=playwright_module()))
        report["the_output_of_the_journey"] = result.stdout[-4000:]
        if result.returncode != 0:
            report["the_error_of_the_journey"] = result.stderr[-4000:]
            raise AssertionError(f"the browser journey failed: "
                                 f"{result.stderr.strip()[-800:] or result.stdout.strip()[-800:]}")
        receipt = json.loads((evidence / "overview-performance.json").read_text())
        assert receipt.get("status") == "PASS", receipt
        assert not receipt.get("errors"), receipt.get("errors")
        assert not receipt.get("external"), receipt.get("external")
        report["browser_receipt"] = receipt
        report["the_interactions"] = receipt["the_interactions"]
        report["the_frames"] = receipt["the_frames"]
        report["the_heap"] = receipt["the_heap"]
        report["the_trace"] = receipt["the_trace"]
        report["the_core_facts"] = receipt["the_core_facts"]
        report["the_refusals_of_the_core"] = receipt.get("the_refusals_of_the_core", [])
        report["checks"] = len(receipt["the_checks"])
        report["steps"].append("the surface performs inside its budgets on the real Core")
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    except Exception as error:  # noqa: BLE001 - the receipt names every failure
        report["status"] = "FAIL"
        report["error"] = f"{type(error).__name__}: {error}"
    finally:
        for simulator in simulators:
            try:
                simulator.terminate()
            except Exception:  # noqa: BLE001 - a dead collector is no problem
                pass
        try:
            tool("stop", expect_success=False)
        except Exception:  # noqa: BLE001 - a stopped instance is no problem
            pass
        if report.get("status") == "PASS":
            shutil.rmtree(work, ignore_errors=True)
        else:
            report["work_directory"] = str(work)

    # The revision the receipt was measured on: a reader of the evidence must
    # be able to tell whether it is current.
    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "overview-performance-rehearsal.json").write_text(
        json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report.get("status"),
                      "the_checks": report.get("checks"),
                      "the_error": report.get("error")}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
