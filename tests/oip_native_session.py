#!/usr/bin/env python3
"""The session of the native client against the real Core (G9, G12).

The browser of the web release keeps the cookie of the session on its own.
The native application has no browser: the client itself must keep the cookie
and send it with every request.

This rehearsal proves that the **native** client of the release build holds a
session of the **real** Core: the test runs on the VM of the Flutter test —
the same Dart semantics as the macOS bundle, without a browser — and performs
the whole path of the operator: the one-time code, the authorized session, the
hierarchy of the authorized scope and the scoped projection.

Nothing of the rehearsal touches the personal installation of the operator and
nothing leaves the machine.

Usage:
  python3 tests/oip_native_session.py [--evidence DIR]
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


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-native-session"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-native-session-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-native-session-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    try:
        port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": port,
            "sources": [{"id": f"source-{letter}", "name": f"Local simulation {letter}",
                         "endpoint": f"opc.tcp://127.0.0.1:{15860 + index}", "namespace": 2}
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

        tool("provision-plan", "--plan", str(work / "plan.json"))
        tool("start")
        time.sleep(3)
        report["steps"].append("the instance runs")

        minted = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(credential)], text=True))
        report["steps"].append("the one-time code is issued")

        result = subprocess.run(
            ["flutter", "test", "test/native_session_live_test.dart", "--reporter", "expanded"],
            cwd=ROOT / "apps/flutter", capture_output=True, text=True, timeout=1800,
            env=dict(os.environ,
                     OIP_LIVE_CORE_URL=f"http://127.0.0.1:{port}",
                     OIP_LIVE_SESSION_CODE=minted["login_code"],
                     OIP_LIVE_PRINCIPAL="reader-org-a"))
        output = result.stdout + result.stderr
        (evidence / "the-native-client.log").write_text(output)
        if result.returncode != 0:
            raise AssertionError(f"the native client failed: {output[-600:]}")
        report["steps"].append("the native client holds the session of the Core")
        report["the_output"] = output.strip().splitlines()[-6:]

        # The session of the client really existed in the Core: the audit of
        # the instance names the capability executions of the session.
        log = (state / "oip.log").read_text(errors="ignore")
        report["the_core_served_the_session"] = "capability_execution" in log
        assert report["the_core_served_the_session"], "the Core served no capability"
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        try:
            tool("stop", expect_success=False)
        except Exception:
            pass
        if report.get("status") == "PASS":
            shutil.rmtree(work, ignore_errors=True)
        else:
            report["work_directory"] = str(work)

    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "native-session.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "steps"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
