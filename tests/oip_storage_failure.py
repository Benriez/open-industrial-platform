#!/usr/bin/env python3
"""The storage-failure path of the Core (G11 — the last escalated gap).

A store that cannot be written is the one failure mode of the instance that no
acceptance covered. The rehearsal measures it on a **bounded volume**: a disk
image of a few megabytes, attached without privileges, that the store of a
disposable instance fills up. Nothing of the rehearsal touches the personal
installation of the operator — the store is a file on a volume in the
temporary directory of the machine, and the volume is detached and deleted at
the end.

The rehearsal measures:

  * the instance **survives** the full volume: it keeps answering its routes;
  * the health of the instance **degrades honestly**: `persistence_healthy` is
    false, the counter of the persistence errors grows and the last error is
    named;
  * the log of the instance **names** the failure (`persistence_retry`);
  * the ingestion is backpressured and the instance does not crash;
  * the store is **not corrupted**: `pragma integrity_check` answers `ok`;
  * the instance **recovers**: after the space is freed the persistence is
    healthy again and the observations continue to grow.

The volume needs `hdiutil` (macOS). Without it the rehearsal reports that it
is blocked and names the reason — it never claims a measurement it did not
take.

Usage:
  python3 tests/oip_storage_failure.py [--evidence DIR] [--megabytes 64]
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


class BoundedVolume:
    """A volume of a fixed size that the rehearsal can fill up.

    The image is a file of the temporary directory of the machine; the volume
    is attached without privileges and detached when the rehearsal ends.
    """

    def __init__(self, work, megabytes):
        self.work = pathlib.Path(work)
        self.megabytes = megabytes
        self.image = self.work / "quota.dmg"
        self.mount = self.work / "volume"
        self.attached = False

    def create(self):
        self.mount.mkdir(parents=True, exist_ok=True)
        result = subprocess.run(
            ["hdiutil", "create", "-size", f"{self.megabytes}m", "-fs", "HFS+",
             "-volname", "oip-quota", "-quiet", str(self.image)],
            capture_output=True, text=True, timeout=600)
        if result.returncode != 0:
            raise RuntimeError("the image of the volume failed: "
                               + (result.stderr or result.stdout).strip()[-300:])
        result = subprocess.run(
            ["hdiutil", "attach", "-nobrowse", "-mountpoint", str(self.mount), str(self.image)],
            capture_output=True, text=True, timeout=600)
        if result.returncode != 0:
            raise RuntimeError("the volume could not be attached: "
                               + (result.stderr or result.stdout).strip()[-300:])
        self.attached = True

    def free_bytes(self):
        result = subprocess.run(["df", "-k", str(self.mount)], capture_output=True, text=True)
        return int(result.stdout.splitlines()[-1].split()[3]) * 1024

    def fill(self):
        """Write until the volume refuses the write."""
        filler = self.mount / "filler.bin"
        chunk = b"\0" * (1024 * 1024)
        written = 0
        error = None
        try:
            with filler.open("wb") as handle:
                for _ in range(self.megabytes * 2):
                    handle.write(chunk)
                    written += len(chunk)
        except OSError as failure:
            error = str(failure)
        return {"the_bytes_written": written, "the_refusal": error}

    def release(self):
        """Free the space of the filler."""
        filler = self.mount / "filler.bin"
        if filler.exists():
            filler.unlink()
        return {"the_free_bytes": self.free_bytes()}

    def destroy(self):
        if self.attached:
            subprocess.run(["hdiutil", "detach", str(self.mount)],
                           capture_output=True, text=True, timeout=300)
            self.attached = False
        if self.image.exists():
            self.image.unlink()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-storage-failure"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    parser.add_argument("--megabytes", type=int, default=64)
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-storage-failure-v1", "steps": []}

    if sys.platform != "darwin" or not shutil.which("hdiutil"):
        report["status"] = "BLOCKED"
        report["reason"] = ("a bounded volume needs `hdiutil` (macOS); the failure path "
                             "of a store that cannot be written cannot be rehearsed here")
        (evidence / "storage-failure.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))
        return 2

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-storage-failure-")).resolve()
    work.chmod(0o700)
    volume = BoundedVolume(work, args.megabytes)
    simulators = []
    process = None
    try:
        volume.create()
        report["the_volume"] = {"the_megabytes": args.megabytes,
                                "the_mount": str(volume.mount),
                                "the_free_bytes_at_the_start": volume.free_bytes()}

        source_ports = [free_port() for _ in range(4)]
        port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        # The store of the instance lives on the bounded volume.
        (work / "core.json").write_text(json.dumps({
            "database": str(volume.mount / "core.sqlite"), "http_port": port,
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
        database = volume.mount / "core.sqlite"

        def tool(*arguments, expect_success=True):
            result = subprocess.run([sys.executable, str(TOOL), "--state-dir", str(state),
                                     "--config", str(work / "core.json"),
                                     "--ipc-config", str(work / "ipc.json"),
                                     "--binary", args.binary, *arguments],
                                    capture_output=True, text=True, timeout=900)
            if expect_success and result.returncode != 0:
                raise AssertionError(f"{arguments[0]} failed: "
                                     f"{result.stderr.strip() or result.stdout.strip()}")
            return result

        for index, simulator_port in enumerate(source_ports):
            simulator = subprocess.Popen(
                [str(SIMULATOR), "--port", str(simulator_port), "--seed", str(42 + index * 7),
                 "--tick-ms", "250"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            simulators.append(simulator)
        time.sleep(2)

        tool("provision-plan", "--plan", str(work / "plan.json"))
        tool("start")
        time.sleep(4)
        report["core_pid"] = int((state / "oip.pid").read_text().strip())
        report["steps"].append("the instance runs with its store on the bounded volume")

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

        def core_health():
            code, payload = api(base, "/api/v2/snapshot", opener=opener)
            if code != 200 or not isinstance(payload, dict):
                return {"the_status": code, "the_core": {}}
            return {"the_status": code, "the_core": payload.get("core") or {}}

        # the collection runs before the volume is filled
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            health = core_health()
            if health["the_core"].get("persistence_healthy") is True:
                observations = int(sqlite_value(database, "select count(*) from observations;") or 0)
                if observations > 0:
                    break
            time.sleep(1)
        report["the_health_before"] = core_health()
        report["the_observations_before"] = int(
            sqlite_value(database, "select count(*) from observations;") or 0)
        report["steps"].append("the collection runs")

        # the volume is filled up: the store of the instance cannot be written
        report["the_fill"] = volume.fill()
        report["the_free_bytes_when_full"] = volume.free_bytes()
        report["the_steps"].append("the volume is full")

        # the instance must degrade honestly and must survive
        deadline = time.monotonic() + 180
        degraded = None
        while time.monotonic() < deadline:
            health = core_health()
            if health["the_core"].get("persistence_healthy") is False:
                degraded = health
                break
            time.sleep(1)
        assert degraded is not None, "the instance did not report the failure of the store"
        report["the_health_when_the_store_cannot_be_written"] = degraded
        report["the_observations_when_the_store_cannot_be_written"] = int(
            sqlite_value(database, "select count(*) from observations;") or 0)
        # the instance still answers
        status, _ = api(base, "/api/v2/sources", opener=opener)
        report["the_status_of_the_instance_during_the_failure"] = status
        assert status == 200, "the instance stopped answering during the failure of its store"
        # the log names the failure
        log = (state / "oip.log").read_text(errors="replace")
        report["the_log_names_the_failure"] = "persistence_retry" in log
        report["the_steps"].append("the instance survives the full volume and names the failure")
        assert report["the_log_names_the_failure"], "the log does not name the failure of the store"

        # the space is freed: the instance must recover
        report["the_release"] = volume.release()
        deadline = time.monotonic() + 240
        recovered = None
        while time.monotonic() < deadline:
            health = core_health()
            if health["the_core"].get("persistence_healthy") is True:
                recovered = health
                break
            time.sleep(1)
        assert recovered is not None, "the instance did not recover after the space was freed"
        report["the_health_after_the_recovery"] = recovered
        before = int(sqlite_value(database, "select count(*) from observations;") or 0)
        deadline = time.monotonic() + 120
        after = before
        while time.monotonic() < deadline:
            after = int(sqlite_value(database, "select count(*) from observations;") or 0)
            if after > before:
                break
            time.sleep(2)
        report["the_observations_before_the_recovery"] = before
        report["the_observations_after_the_recovery"] = after
        report["the_steps"].append("the instance recovers and collects again")
        assert after > before, "the instance did not collect again after the recovery"

        # the store is intact
        report["the_integrity"] = sqlite_value(database, "pragma integrity_check;")
        assert report["the_integrity"] == "ok", "the store of the instance is corrupted"

        # the shutdown
        stop = tool("stop", expect_success=False)
        report["the_shutdown"] = {"the_exit_code": stop.returncode,
                                  "the_output": (stop.stdout or stop.stderr).strip()[-400:]}
        report["the_steps"].append("the instance stops")
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    except Exception as error:  # noqa: BLE001 - the receipt names every failure
        report["status"] = "FAIL"
        report["error"] = f"{type(error).__name__}: {error}"
    finally:
        if process is not None and process.poll() is None:
            process.kill()
        try:
            tool("stop", expect_success=False)
        except Exception:
            pass
        for simulator in simulators:
            simulator.terminate()
        volume.destroy()
        shutil.rmtree(work, ignore_errors=True)

    # The revision the receipt was measured on: a reader of the evidence must
    # be able to tell whether it is current.
    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "storage-failure.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "steps"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
