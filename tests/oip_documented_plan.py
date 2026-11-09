#!/usr/bin/env python3
"""The example of the runbook must work.

The operator writes the plan of the own instance from the example of the
runbook (`docs/runbooks/operations.md`, §1.1). A documentation that does not
work is worse than none: this rehearsal takes the example **out of the
runbook**, provisions a disposable instance with it and proves that the
instance starts and answers.

The runbook is therefore executable documentation: if the plan of the Core
changes, this rehearsal fails.

Usage:
  python3 tests/oip_documented_plan.py [--evidence DIR]
"""
import argparse
import http.cookiejar
import json
import pathlib
import re
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "oip_ops.py"
RUNBOOK = ROOT / "docs" / "runbooks" / "operations.md"


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def the_documented_plan():
    """The plan of the runbook, exactly as it stands there."""
    text = RUNBOOK.read_text()
    start = text.index("### 1.1 The parts of a plan")
    match = re.search(r"```json\n(.*?)\n```", text[start:], re.S)
    assert match, "the runbook carries no example of a plan"
    return json.loads(match.group(1))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-documented-plan"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-documented-plan-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-documented-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    try:
        plan = the_documented_plan()
        report["the_plan"] = {"the_parts": sorted(plan.keys()),
                              "the_organizations": len(plan.get("organizations", [])),
                              "the_sources": len(plan.get("sources", [])),
                              "the_principals": len(plan.get("principals", []))}
        report["steps"].append("the example of the runbook is read")

        # The configuration of the instance: the sources of the plan with a
        # closed loopback port. No endpoint of the operator is contacted.
        http_port = free_port()
        sources = [{"id": item["source_id"], "name": f"Source {item['source_id']}",
                     "endpoint": "opc.tcp://127.0.0.1:1", "namespace": 2}
                    for item in plan.get("sources", [])]
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": http_port,
            "sources": sources, "legacy_single_infrastructure": False,
        }, indent=2))
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        credential = work / "platform.credential"
        credential.write_bytes(secrets.token_bytes(32))
        credential.chmod(0o600)
        principal = plan["principals"][0]["id"]
        (work / "ipc.json").write_text(json.dumps({
            "socket": str(work / "s"), "max_sessions": 4,
            "clients": [{"uid": __import__("os").getuid(),
                         "credential_file": str(credential),
                         "policy": {"principal": principal}}],
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

        step = tool("provision-plan", "--plan", str(work / "plan.json"))
        report["the_provisioning"] = json.loads(step.stdout).get("result", "{}")
        report["steps"].append("the instance is provisioned with the example")

        tool("start")
        time.sleep(2)
        with urllib.request.urlopen(f"http://127.0.0.1:{http_port}/api/v2/browser/session",
                                    timeout=20) as answer:
            report["the_session_route"] = answer.status
        assert report["the_session_route"] == 200, "the instance does not answer"

        # The operator of the example authorizes the session with the
        # one-time code of the principal of the plan.
        minted = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(credential)], text=True))
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        request = urllib.request.Request(
            f"http://127.0.0.1:{http_port}/api/v2/browser/login",
            data=json.dumps({"code": minted["login_code"]}).encode(),
            headers={"Content-Type": "application/json",
                     "Origin": f"http://127.0.0.1:{http_port}"}, method="POST")
        with opener.open(request, timeout=30) as answer:
            session = json.loads(answer.read().decode())
            report["the_login"] = answer.status
        assert report["the_login"] == 200, "the operator session was refused"
        report["the_principal_of_the_session"] = session.get("principal_id") == principal
        assert report["the_principal_of_the_session"], session

        tool("stop")
        report["steps"].append("the instance of the example starts and answers")
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
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
    (evidence / "documented-plan.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "steps"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
