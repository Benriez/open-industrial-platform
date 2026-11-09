#!/usr/bin/env python3
"""The local operations of an OIP Core: provision, start, status, backup,
restore, restart and stop, plus the refusal of the personal installation.

The script owns a disposable instance in a private temporary directory. It
never touches the personal installation of the operator and it never contacts
an endpoint outside the machine.

Usage:
  python3 tests/oip_operations.py [--evidence DIR] [--binary PATH]
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
PERSONAL = pathlib.Path.home() / "Library" / "Application Support/OIP/real/core.sqlite"


def run_tool(arguments, expect_success=True):
    result = subprocess.run([sys.executable, str(TOOL), *arguments],
                            capture_output=True, text=True, timeout=300)
    payload = {}
    if result.stdout.strip():
        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError:
            try:
                payload = json.loads(result.stdout.strip().splitlines()[-1])
            except json.JSONDecodeError:
                payload = {"raw": result.stdout.strip()}
    if expect_success and result.returncode != 0:
        raise AssertionError(
            f"{arguments[0]} failed: {result.stderr.strip() or result.stdout.strip()}")
    return {
        "command": arguments[0],
        "arguments": [a for a in arguments[1:] if not a.startswith("/private/tmp")],
        "exit_code": result.returncode,
        "stdout": payload,
        "stderr": result.stderr.strip()[:400],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence",
                        default=str(ROOT / "target" / "oip-operations"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)

    personal_hash_before = hashlib.sha256(PERSONAL.read_bytes()).hexdigest() \
        if PERSONAL.is_file() else None

    # The Core refuses a path with a symlink component; the temporary
    # directory of macOS lives under /var, which links to /private/var.
    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-operations-")).resolve()
    work.chmod(0o700)
    report = {"schema": "oip-operations-v1", "steps": []}
    try:
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        plan["sources"] = []
        plan["bindings"] = [b for b in plan["bindings"]
                            if b["scope"]["kind"] != "source"]
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        # A free port of this machine: the test never collides with an
        # instance that is already running.
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"),
            "http_port": port,
            "sources": [],
            "web_dir": str(ROOT / "apps/flutter/build/web"),
        }, indent=2))
        (work / "ipc.json").write_text(json.dumps({
            "socket": str(work / "s"),
            "clients": [{
                "uid": os.getuid(),
                "credential_file": str(work / "platform.credential"),
                "policy": {"principal": "reader-org-a"},
            }],
        }, indent=2))
        state = str(work / "state")

        def tool(*arguments, expect_success=True):
            return run_tool(["--state-dir", state,
                             "--config", str(work / "core.json"),
                             "--ipc-config", str(work / "ipc.json"),
                             "--binary", args.binary, *arguments],
                            expect_success=expect_success)

        # 1. the offline provisioning of the data store
        step = tool("provision-plan", "--plan", str(work / "plan.json"))
        assert step["stdout"].get("status") == "provisioned", step
        report["steps"].append(step)

        # 2. the instance starts and answers
        step = tool("start")
        assert step["stdout"].get("status") == "started", step
        report["steps"].append(step)
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=30) as answer:
            assert answer.status == 200, answer.status
        report["http_status"] = 200

        # 3. the status names the running instance
        step = tool("status")
        assert step["stdout"].get("status") == "running", step
        assert step["stdout"].get("port_open") is True, step
        report["steps"].append(step)

        # 4. the log of the instance is written
        log = pathlib.Path(state) / "oip.log"
        assert log.is_file() and log.stat().st_size > 0, "the instance wrote no log"
        report["log_bytes"] = log.stat().st_size

        # 5. the backup of the running instance is consistent
        step = tool("backup")
        assert step["stdout"].get("integrity") == "ok", step
        backup = pathlib.Path(step["stdout"]["backup"])
        assert backup.is_file(), step
        assert backup.stat().st_mode & 0o077 == 0, "the backup is not owner-private"
        report["steps"].append(step)
        report["backup"] = {"path": str(backup), "bytes": backup.stat().st_size}

        # 6. a restore of a running instance is refused
        step = tool("restore", "--source", str(backup), expect_success=False)
        assert step["exit_code"] != 0, step
        assert "running" in step["stderr"], step
        report["steps"].append(step)

        # 7. the instance stops cleanly
        step = tool("stop")
        assert step["stdout"].get("status") == "stopped", step
        report["steps"].append(step)
        shutdown = [line for line in log.read_text(errors="ignore").splitlines()
                    if '"clean"' in line]
        assert shutdown, "the instance did not report its shutdown"
        clean = json.loads(shutdown[-1])
        assert clean.get("clean") is True, clean
        assert clean.get("uncommitted") == 0, clean
        report["clean_shutdown"] = clean

        # 8. the backup is restored
        step = tool("restore", "--source", str(backup))
        assert step["stdout"].get("integrity") == "ok", step
        report["steps"].append(step)

        # 9. the instance runs again after the restore
        step = tool("start")
        assert step["stdout"].get("status") == "started", step
        report["steps"].append(step)

        # 10. the restart keeps the instance available
        step = tool("restart")
        assert step["stdout"].get("status") == "started", step
        report["steps"].append(step)
        step = tool("status")
        assert step["stdout"].get("status") == "running", step
        report["steps"].append(step)

        # 11. the instance stops again
        step = tool("stop")
        assert step["stdout"].get("status") == "stopped", step
        report["steps"].append(step)

        # 12. the personal installation is refused for every operation
        personal_config = json.loads((work / "core.json").read_text())
        personal_config["database"] = str(PERSONAL)
        (work / "personal.json").write_text(json.dumps(personal_config, indent=2))
        for command in (["backup"], ["restore", "--source", str(backup)],
                        ["start"]):
            step = run_tool(["--state-dir", state,
                             "--config", str(work / "personal.json"),
                             "--ipc-config", str(work / "ipc.json"),
                             "--binary", args.binary, *command],
                            expect_success=False)
            assert step["exit_code"] != 0, step
            assert "personal installation" in step["stderr"], step
            report["steps"].append(step)
        report["personal_installation_refused"] = True

        personal_hash_after = hashlib.sha256(PERSONAL.read_bytes()).hexdigest() \
            if PERSONAL.is_file() else None
        assert personal_hash_after == personal_hash_before, "the personal database changed"
        report["personal_database_sha256"] = personal_hash_after
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        if report.get("status") == "PASS":
            shutil.rmtree(work, ignore_errors=True)
        else:
            # A failed run keeps its directory: the log of the instance is the
            # proof of what happened.
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
    (evidence / "operations.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({
        "status": report["status"],
        "steps": len(report["steps"]),
        "evidence": str(evidence / "operations.json"),
        "error": report.get("error"),
    }, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
