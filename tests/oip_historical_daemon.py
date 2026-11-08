#!/usr/bin/env python3
"""The daemon handover with the historical binary.

The rehearsal proves the handover of a **running** instance, not only of a
data store:

  1. the protected historical binary provisions a data store;
  2. the OIP-007 shape of the local IPC policy (actor, permissions, sources)
     is **measured** against the historical daemon: it refuses the start;
  3. the OIP-008 shape of its era (a credential bound to a provisioned,
     enabled principal) starts the daemon, which collects the observations of
     its sources and answers the authorized reads of its principals — each of
     them only in its own scope;
  4. the daemon stops cleanly and the state is backed up;
  5. the current release binary takes over the same data store, migrates it
     and serves the observations of the historical daemon;
  6. the backup restores the state of the historical daemon, and the
     historical binary adopts the restored store **and serves it again**.

The historical binary is used only when the hash of the file is the recorded
hash. Nothing of the rehearsal touches the personal installation of the
operator and nothing leaves the machine.

Usage:
  python3 tests/oip_historical_daemon.py [--evidence DIR]
"""
import argparse
import hashlib
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
# The protected historical binary of the canonical regression. It is used only
# when the hash of the file is the recorded hash.
BASELINE = pathlib.Path(
    "/Users/benny/Documents/OIP-Handoffs/core-0085-real-inventory-20261106T200219Z/"
    "oip0084-baseline-server")
BASELINE_SHA256 = "73d70d8105914db20210c95268b5733ca2ec19c959c4c29fa57cb93c1935fe58"


def sha256(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def sqlite_value(database, statement):
    result = subprocess.run(["/usr/bin/sqlite3", "-batch", "-noheader", str(database), statement],
                            capture_output=True, text=True, timeout=60)
    return result.stdout.strip()


def run_tool(arguments, expect_success=True):
    result = subprocess.run([sys.executable, str(TOOL), *arguments],
                            capture_output=True, text=True, timeout=300)
    payload = {}
    if result.stdout.strip():
        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError:
            payload = {"raw": result.stdout.strip()}
    if expect_success and result.returncode != 0:
        raise AssertionError(
            f"{arguments[0]} failed: {result.stderr.strip() or result.stdout.strip()}")
    return {"command": arguments[0], "exit_code": result.returncode,
            "stdout": payload, "stderr": result.stderr.strip()[:400]}


def http_get(port, path, token=None):
    """The answer of the era REST surface.

    The era binds the loopback REST to the same credential as the local IPC:
    `Authorization: Bearer <64 hex characters>`.
    """
    headers = {"Authorization": "Bearer " + token} if token else {}
    request = urllib.request.Request(f"http://127.0.0.1:{port}{path}", headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=20) as answer:
            return answer.status, json.loads(answer.read().decode() or "{}")
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode() or "{}")
    except Exception as error:
        return None, {"error": str(error)}


def source_items(payload):
    """The sources of the answer of the era.

    The surface answers with a list; a later era wraps it in an object.
    """
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict):
        items = payload.get("items")
        if isinstance(items, list):
            return [item for item in items if isinstance(item, dict)]
    return []


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-historical-daemon"))
    parser.add_argument("--release-binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-historical-daemon-v1", "steps": []}

    if not BASELINE.is_file():
        report["status"] = "BLOCKED"
        report["reason"] = f"the protected historical binary {BASELINE} is not present"
        (evidence / "historical-daemon.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return 2
    digest = sha256(BASELINE)
    if digest != BASELINE_SHA256:
        report["status"] = "BLOCKED"
        report["reason"] = f"the protected historical binary has the hash {digest}"
        (evidence / "historical-daemon.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return 2
    report["historical_binary"] = {"path": str(BASELINE), "sha256": digest}
    report["release_binary"] = {"path": args.release_binary,
                                "sha256": sha256(args.release_binary)}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-historical-daemon-",
                                          dir="/private/tmp")).resolve()
    work.chmod(0o700)
    simulators = []
    state_h = str(work / "state-historical")
    state_r = str(work / "state-release")
    try:
        # The four sources of the plan answer on their own simulator, so the
        # historical daemon really collects instead of waiting on a dead
        # endpoint.
        source_ports = [free_port() for _ in range(4)]
        http_port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        sources = [{"id": f"source-{letter}", "name": f"Local simulation {letter}",
                    "endpoint": f"opc.tcp://127.0.0.1:{source_ports[index]}", "namespace": 2}
                   for index, letter in enumerate("abcd")]
        core_historical = {"database": str(work / "core.sqlite"),
                           "http_port": http_port, "sources": sources,
                           "legacy_single_infrastructure": False}
        (work / "core-historical.json").write_text(json.dumps(core_historical, indent=2))
        (work / "core-release.json").write_text(json.dumps(core_historical, indent=2))

        # The OIP-008 shape of the era: the protected local IPC binds a
        # credential to a provisioned, enabled principal.
        (work / "ipc-era.json").write_text(json.dumps({
            "socket": str(work / "s-era"), "max_sessions": 16,
            "clients": [
                {"uid": os.getuid(), "credential_file": str(work / "era-a.credential"),
                 "policy": {"principal": "reader-org-a"}},
                {"uid": os.getuid(), "credential_file": str(work / "era-b.credential"),
                 "policy": {"principal": "reader-org-b"}},
            ],
        }, indent=2))
        # The OIP-007 shape: an actor with permissions and a source scope.
        (work / "ipc-actor.json").write_text(json.dumps({
            "socket": str(work / "s-actor"), "max_sessions": 16,
            "clients": [{"uid": os.getuid(),
                         "credential_file": str(work / "actor.credential"),
                         "policy": {"actor": "local-historical-reader",
                                    "permissions": ["inventory_read", "telemetry_read"],
                                    "sources": {"kind": "all"}}}],
            "rest_policy": {"actor": "local-rest-operator",
                            "permissions": ["inventory_read", "telemetry_read"],
                            "sources": {"kind": "all"}},
        }, indent=2))

        # The era binds the local clients to a private 32-byte credential of
        # the owner of the instance.
        for name in ("era-a.credential", "era-b.credential", "actor.credential"):
            credential_file = work / name
            credential_file.write_bytes(secrets.token_bytes(32))
            credential_file.chmod(0o600)
        token_a = (work / "era-a.credential").read_bytes().hex()
        token_b = (work / "era-b.credential").read_bytes().hex()

        def tool(binary, config, ipc, state, *arguments, expect_success=True):
            return run_tool(["--state-dir", state,
                             "--config", str(work / config),
                             "--ipc-config", str(work / ipc),
                             "--binary", binary, *arguments],
                            expect_success=expect_success)

        # 1. the historical binary provisions the data store (offline)
        step = tool(str(BASELINE), "core-historical.json", "ipc-era.json",
                    state_h, "provision-plan", "--plan", str(work / "plan.json"))
        report["steps"].append({"step": "provisioning", "exit_code": step["exit_code"]})
        assert step["stdout"].get("status") == "provisioned", step
        report["schema_after_provisioning"] = sqlite_value(work / "core.sqlite",
                                                           "pragma user_version;")

        # 2. the OIP-007 shape is measured against the historical daemon
        refusal = tool(str(BASELINE), "core-historical.json", "ipc-actor.json",
                       str(work / "state-actor"), "start", expect_success=False)
        actor_log = pathlib.Path(work / "state-actor" / "oip.log")
        text = actor_log.read_text(errors="ignore") if actor_log.is_file() else ""
        report["oip007_shape_refused"] = {
            "exit_code": refusal["exit_code"],
            "stderr": refusal["stderr"][-300:],
            "log_excerpt": "\n".join(text.splitlines()[-4:])[-600:],
            "started": refusal["exit_code"] == 0,
        }
        report["steps"].append({"step": "the OIP-007 shape", "exit_code": refusal["exit_code"]})
        assert refusal["exit_code"] != 0, "the historical daemon accepted the OIP-007 shape"

        # 3. the era shape starts the daemon
        if SIMULATOR.is_file():
            for index, port in enumerate(source_ports):
                simulator = subprocess.Popen(
                    [str(SIMULATOR), "--port", str(port), "--seed", str(42 + index * 7),
                     "--tick-ms", "250"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                simulators.append(simulator)
            time.sleep(2)
            report["simulators"] = len(simulators)
        step = tool(str(BASELINE), "core-historical.json", "ipc-era.json",
                    state_h, "start")
        report["steps"].append({"step": "the era daemon", **step})
        report["historical_daemon_pid"] = step["stdout"].get("pid")

        # the daemon serves the authorized read of its principal — and only
        # the sources of the scope of that principal
        status, payload = http_get(http_port, "/api/v2/sources", token_a)
        visible_a = sorted(item.get("id") for item in source_items(payload)
                           if item.get("id"))
        report["era_authorized_read"] = {"principal": "reader-org-a", "status": status,
                                         "sources": visible_a}
        assert status == 200, f"the historical daemon does not serve its principal: {payload}"
        assert visible_a == ["source-a", "source-b", "source-c"], visible_a
        status, payload = http_get(http_port, "/api/v2/sources", token_b)
        visible_b = sorted(item.get("id") for item in source_items(payload)
                           if item.get("id"))
        report["era_authorized_read_of_the_other_organization"] = {
            "principal": "reader-org-b", "status": status, "sources": visible_b}
        assert status == 200 and visible_b == ["source-d"], visible_b
        # the era denies the read without a credential
        status, _ = http_get(http_port, "/api/v2/sources")
        report["era_read_without_credential"] = status
        assert status in (401, 403), f"the era served an unauthorized read: {status}"

        # the daemon collects: the sources of the scope become fresh
        fresh = False
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            status, payload = http_get(http_port, "/api/v2/sources", token_a)
            items = source_items(payload)
            if status == 200 and len(items) == 3 and all(
                    item.get("freshness") == "fresh" for item in items):
                fresh = True
                break
            time.sleep(1)
        report["historical_daemon_collects"] = fresh
        observations = sqlite_value(work / "core.sqlite",
                                    "select count(*) from observations;")
        report["observations_collected_by_the_historical_daemon"] = observations
        assert observations != "0", "the historical daemon collected nothing"
        report["schema_with_the_historical_daemon"] = sqlite_value(
            work / "core.sqlite", "pragma user_version;")

        # 4. the daemon stops cleanly and its state is backed up
        step = tool(str(BASELINE), "core-historical.json", "ipc-era.json", state_h, "stop")
        report["steps"].append({"step": "the stop of the era daemon", **step})
        assert step["stdout"].get("status") == "stopped", step
        step = tool(str(BASELINE), "core-historical.json", "ipc-era.json",
                    state_h, "backup")
        report["steps"].append({"step": "the backup of the era", **step})
        backup = pathlib.Path(step["stdout"]["backup"])
        report["backup"] = str(backup)
        report["schema_of_the_backup"] = sqlite_value(backup, "pragma user_version;")
        report["observations_in_the_backup"] = sqlite_value(
            backup, "select count(*) from observations;")

        # 5. the release binary takes over the same data store
        step = tool(args.release_binary, "core-release.json", "ipc-era.json",
                    state_r, "start")
        report["steps"].append({"step": "the release takeover", **step})
        status, _ = http_get(http_port, "/api/v2/browser/session")
        report["release_serves_the_handover"] = status
        assert status == 200, "the release binary does not serve the handed-over store"
        report["schema_after_the_handover"] = sqlite_value(work / "core.sqlite",
                                                           "pragma user_version;")
        report["observations_after_the_handover"] = sqlite_value(
            work / "core.sqlite", "select count(*) from observations;")
        # The release daemon collects on its own, so the count grows. The
        # handover must not lose the observations of the historical daemon.
        assert int(report["observations_after_the_handover"]) >= int(observations), \
            "the handover lost the observations of the historical daemon"
        tool(args.release_binary, "core-release.json", "ipc-era.json", state_r, "stop")

        # 6. the backup restores the state of the historical daemon and the
        #    historical binary serves the restored store again
        step = tool(args.release_binary, "core-release.json", "ipc-era.json",
                    state_r, "restore", "--source", str(backup))
        report["steps"].append({"step": "the restore", **step})
        report["schema_after_the_restore"] = sqlite_value(work / "core.sqlite",
                                                          "pragma user_version;")
        assert report["schema_after_the_restore"] == report["schema_with_the_historical_daemon"], \
            "the restore did not bring back the schema of the historical daemon"
        report["observations_after_the_restore"] = sqlite_value(
            work / "core.sqlite", "select count(*) from observations;")
        assert report["observations_after_the_restore"] == report["observations_in_the_backup"], \
            "the restore did not bring back the observations of the historical daemon"
        step = tool(str(BASELINE), "core-historical.json", "ipc-era.json",
                    state_h, "start")
        report["steps"].append({"step": "the era daemon serves the restored store", **step})
        status, payload = http_get(http_port, "/api/v2/sources", token_a)
        assert status == 200, f"the historical daemon does not serve the restored store: {payload}"
        report["observations_after_the_restored_daemon"] = sqlite_value(
            work / "core.sqlite", "select count(*) from observations;")
        assert int(report["observations_after_the_restored_daemon"]) >= \
            int(report["observations_in_the_backup"]), \
            "the restored daemon lost the observations of the historical daemon"
        step = tool(str(BASELINE), "core-historical.json", "ipc-era.json", state_h, "stop")
        report["steps"].append({"step": "the stop of the restored era daemon", **step})
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
        for state in (state_h, state_r, str(work / "state-actor")):
            try:
                run_tool(["--state-dir", state,
                          "--config", str(work / "core-historical.json"),
                          "--ipc-config", str(work / "ipc-era.json"),
                          "--binary", str(BASELINE), "stop"], expect_success=False)
            except Exception:
                pass
        if report.get("status") == "PASS":
            shutil.rmtree(work, ignore_errors=True)
        else:
            # A failed rehearsal keeps its directory: the log of the instance
            # is the proof of what happened.
            report["work_directory"] = str(work)

    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "historical-daemon.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "steps"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
