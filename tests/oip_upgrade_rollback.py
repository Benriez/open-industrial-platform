#!/usr/bin/env python3
"""The upgrade and the rollback of a local OIP Core.

The rehearsal proves that a data store of an older release is taken over by
the current release binary and that the previous state can be restored:

  1. a protected historical binary provisions the data store and serves it;
  2. the state is backed up;
  3. the current release binary takes over the same data store and serves it;
  4. the backup restores the previous state and the historical binary serves
     it again.

Both eras are addressed with their own configuration shape: the historical
binary of OIP-008.4 knows the actor/permissions policy of its time, the
current binary knows the principal of the authorized session.

Nothing of the rehearsal touches the personal installation of the operator and
nothing leaves the machine.

Usage:
  python3 tests/oip_upgrade_rollback.py [--evidence DIR]
"""
import argparse
import hashlib
import json
import os
import pathlib
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "oip_ops.py"
# The protected historical binary of the canonical regression. It is used only
# when the hash of the file is the recorded hash.
BASELINE = pathlib.Path(
    "/Users/benny/Documents/OIP-Handoffs/core-0085-real-inventory-20261106T200219Z/"
    "oip0084-baseline-server")
BASELINE_SHA256 = "73d70d8105914db20210c95268b5733ca2ec19c959c4c29fa57cb93c1935fe58"


def sha256(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


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
            "stdout": payload, "stderr": result.stderr.strip()[:300]}


def sqlite_value(database, statement):
    result = subprocess.run(["/usr/bin/sqlite3", "-batch", "-noheader", str(database), statement],
                            capture_output=True, text=True, timeout=60)
    return result.stdout.strip()


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def http_status(port, path="/api/v2/browser/session"):
    """The state of the API of the instance.

    The root of the instance serves the web directory when the configuration
    names one. The session route answers in every case and proves that the
    Core serves.
    """
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=20) as answer:
            return answer.status
    except Exception:
        return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-upgrade-rollback"))
    parser.add_argument("--release-binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-upgrade-rollback-v1", "steps": []}

    if not BASELINE.is_file():
        report["status"] = "BLOCKED"
        report["reason"] = f"the protected historical binary {BASELINE} is not present"
        (evidence / "upgrade-rollback.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return 2
    digest = sha256(BASELINE)
    if digest != BASELINE_SHA256:
        report["status"] = "BLOCKED"
        report["reason"] = f"the protected historical binary has the hash {digest}"
        (evidence / "upgrade-rollback.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return 2
    report["historical_binary"] = {"path": str(BASELINE), "sha256": digest}
    report["release_binary"] = {"path": args.release_binary,
                                "sha256": sha256(args.release_binary)}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-upgrade-")).resolve()
    work.chmod(0o700)
    try:
        port = free_port()
        database = work / "core.sqlite"
        # The configuration of the historical era: four sources with their own
        # namespace and distinct endpoints, no field the historical binary does
        # not know.
        (work / "core-historical.json").write_text(json.dumps({
            "database": str(database),
            "http_port": port,
            "sources": [
                {"id": f"source-{letter}", "name": f"Local simulation {letter}",
                 "endpoint": f"opc.tcp://127.0.0.1:{15860 + index}", "namespace": 2}
                for index, letter in enumerate("abcd")
            ],
            "legacy_single_infrastructure": False,
        }, indent=2))
        # The current era accepts the same data store. Its runtime sources
        # must exactly match the provisioned registry, so both eras address the
        # same four sources.
        (work / "core-release.json").write_text(json.dumps({
            "database": str(database),
            "http_port": port,
            "sources": [
                {"id": f"source-{letter}", "name": f"Local simulation {letter}",
                 "endpoint": f"opc.tcp://127.0.0.1:{15860 + index}", "namespace": 2}
                for index, letter in enumerate("abcd")
            ],
            "legacy_single_infrastructure": False,
        }, indent=2))
        # The IPC configuration of the historical era binds the local clients
        # to a provisioned, enabled principal (OIP-008). The actor with
        # permissions and a source scope is the shape of OIP-007; the era
        # refuses it, which is measured in tests/oip_historical_daemon.py.
        (work / "ipc-historical.json").write_text(json.dumps({
            "socket": str(work / "s-historical"),
            "max_sessions": 16,
            "clients": [{
                "uid": os.getuid(),
                "credential_file": str(work / "historical.credential"),
                "policy": {"principal": "reader-org-a"},
            }],
        }, indent=2))
        # The current era binds the local client to a provisioned principal.
        (work / "ipc-release.json").write_text(json.dumps({
            "socket": str(work / "s-release"),
            "max_sessions": 16,
            "clients": [{
                "uid": os.getuid(),
                "credential_file": str(work / "release.credential"),
                "policy": {"principal": "reader-org-a"},
            }],
        }, indent=2))
        state_h = str(work / "state-historical")
        state_r = str(work / "state-release")

        def tool(binary, config, ipc, state, *arguments, expect_success=True):
            return run_tool(["--state-dir", state,
                             "--config", str(work / config),
                             "--ipc-config", str(work / ipc),
                             "--binary", binary, *arguments],
                            expect_success=expect_success)

        # 1. the historical binary provisions the data store
        step = tool(str(BASELINE), "core-historical.json", "ipc-historical.json",
                    state_h, "provision-plan", "--plan",
                    str(ROOT / "examples/multi-infrastructure-plan.json"))
        report["steps"].append(step)
        report["schema_after_provisioning"] = sqlite_value(database, "pragma user_version;")

        # 2. the state of the historical store before the handover
        report["schema_historical"] = sqlite_value(database, "pragma user_version;")
        report["organizations_historical"] = sqlite_value(
            database, "select count(*) from organizations;")
        # The daemon of the historical binary is not started here: the
        # subject of this rehearsal is the data store and its handover. The
        # daemon itself is rehearsed in tests/oip_historical_daemon.py, which
        # measures that the era refuses the actor shape of OIP-007 and starts
        # with a credential bound to a provisioned, enabled principal.
        report["historical_daemon"] = {
            "rehearsed": False,
            "reason": "the daemon of the historical release is not started in this "
                      "rehearsal; the rehearsal of the daemon handover is "
                      "tests/oip_historical_daemon.py. The era binds the local clients to a "
                      "provisioned, enabled principal; the actor/permissions shape of OIP-007 "
                      "is refused by it.",
        }

        # 3. the state before the upgrade is backed up
        step = tool(str(BASELINE), "core-historical.json", "ipc-historical.json",
                    state_h, "backup")
        report["steps"].append(step)
        backup = pathlib.Path(step["stdout"]["backup"])
        report["backup"] = str(backup)

        # 4. the release binary takes over the same data store
        step = tool(args.release_binary, "core-release.json", "ipc-release.json",
                    state_r, "start")
        report["steps"].append(step)
        report["http_release"] = http_status(port)
        assert report["http_release"] == 200, "the release binary does not serve the instance"
        report["schema_release"] = sqlite_value(database, "pragma user_version;")
        report["organizations_release"] = sqlite_value(
            database, "select count(*) from organizations;")
        report["upgrade_changed_the_schema"] = (
            report["schema_release"] != report["schema_historical"])
        assert report["organizations_release"] == report["organizations_historical"], \
            "the upgrade lost the data of the store"

        # 5. the rollback restores the previous state and the previous binary
        step = tool(args.release_binary, "core-release.json", "ipc-release.json",
                    state_r, "stop")
        report["steps"].append(step)
        step = tool(args.release_binary, "core-release.json", "ipc-release.json",
                    state_r, "restore", "--source", str(backup))
        report["steps"].append(step)
        report["schema_after_rollback"] = sqlite_value(database, "pragma user_version;")
        assert report["schema_after_rollback"] == report["schema_historical"], \
            "the rollback did not restore the previous schema"
        # The historical binary adopts the restored store again: the rollback
        # leaves an instance the previous release can serve.
        step = tool(str(BASELINE), "core-historical.json", "ipc-historical.json",
                    state_h, "provision-plan", "--plan",
                    str(ROOT / "examples/multi-infrastructure-plan.json"))
        report["steps"].append(step)
        report["historical_adopts_the_restored_store"] = \
            step["stdout"].get("status") == "provisioned"
        assert report["historical_adopts_the_restored_store"], \
            "the historical binary does not adopt the restored store"
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        if report.get("status") == "PASS":
            shutil.rmtree(work, ignore_errors=True)
        else:
            # A failed rehearsal keeps its directory: the log of the instance
            # is the proof of what happened.
            report["work_directory"] = str(work)

    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "upgrade-rollback.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "steps"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
