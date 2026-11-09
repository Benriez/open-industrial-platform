#!/usr/bin/env python3
"""The offline change of a setting of the instance (G9, G12).

The Core has **no** HTTP and no MCP write path for the settings: the change
is an offline operation of the local operator with the exclusive local CLI
(`--settings-change`). The settings navigation of the application says so, and
the runbook of the operations did not name the procedure.

This rehearsal proves the procedure against the **release** binary:

  1. the change of a setting of the instance is applied offline;
  2. the value becomes effective at the next validated start of the Core;
  3. a wrong revision is refused — the guard of the write;
  4. a principal without the permission is refused;
  5. a value outside the validation of the key is refused.

Nothing of the rehearsal touches the personal installation of the operator and
nothing leaves the machine.

Usage:
  python3 tests/oip_settings_offline.py [--evidence DIR]
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
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-settings-offline"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-settings-offline-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-settings-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    try:
        port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        # The operator of the instance needs the scoped permission for the
        # settings; the reader role of the plan may only read them.
        plan["roles"].append({"id": "settings-admin", "name": "Explicit scoped operator",
                               "permissions": ["settings_read", "settings_write"]})
        plan["bindings"].append({"principal_id": "reader-org-a",
                                 "role_id": "settings-admin",
                                 "scope": {"kind": "platform"}})
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
            "socket": str(work / "s"), "max_sessions": 8,
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

        def change(payload, expect_success=True):
            path = work / "setting.json"
            path.write_text(json.dumps(payload, indent=2))
            result = subprocess.run(
                [args.binary, "--config", str(work / "core.json"),
                 "--settings-change", str(path)],
                capture_output=True, text=True, timeout=120)
            if expect_success and result.returncode != 0:
                raise AssertionError(f"the settings change failed: "
                                     f"{result.stderr.strip() or result.stdout.strip()}")
            answer = {}
            if result.stdout.strip():
                try:
                    answer = json.loads(result.stdout)
                except json.JSONDecodeError:
                    answer = {"raw": result.stdout.strip()[:300]}
            return result.returncode, answer, (result.stderr.strip() or result.stdout.strip())[:300]

        tool("provision-plan", "--plan", str(work / "plan.json"))
        report["steps"].append("the instance is provisioned")

        # 1. the change of a setting of the instance
        code, answer, output = change({
            "principal": "reader-org-a", "scope": {"kind": "platform"},
            "key": "instance_name",
            "value": {"type": "text", "value": "Meine Instanz"},
            "expected_revision": 0,
        })
        report["the_change"] = {"exit_code": code, "answer": answer, "output": output}
        assert code == 0, output
        report["the_revision_of_the_setting"] = answer.get("record", {}).get("revision")
        report["the_value_of_the_setting"] = answer.get("record", {}).get("value")
        report["steps"].append("the setting is changed offline")

        # 2. the guard of the write: a wrong revision is refused
        code, answer, output = change({
            "principal": "reader-org-a", "scope": {"kind": "platform"},
            "key": "instance_name",
            "value": {"type": "text", "value": "Ein anderer Name"},
            "expected_revision": 0,
        }, expect_success=False)
        report["the_wrong_revision"] = {"exit_code": code, "output": output}
        assert code != 0, "the wrong revision was accepted"
        report["steps"].append("the wrong revision is refused")

        # 3. a principal without the permission is refused
        code, answer, output = change({
            "principal": "reader-org-b", "scope": {"kind": "platform"},
            "key": "instance_name",
            "value": {"type": "text", "value": "Nicht erlaubt"},
            "expected_revision": 1,
        }, expect_success=False)
        report["the_unauthorized_principal"] = {"exit_code": code, "output": output}
        assert code != 0, "the principal without the permission was accepted"
        report["steps"].append("the principal without the permission is refused")

        # 4. a value outside the validation of the key is refused
        code, answer, output = change({
            "principal": "reader-org-a", "scope": {"kind": "platform"},
            "key": "history_page_size",
            "value": {"type": "integer", "value": 9999},
            "expected_revision": 0,
        }, expect_success=False)
        report["the_invalid_value"] = {"exit_code": code, "output": output}
        assert code != 0, "the invalid value was accepted"
        report["steps"].append("the invalid value is refused")

        # 5. the value becomes effective at the next validated start
        tool("start")
        time.sleep(3)
        minted = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(credential)], text=True))
        import http.cookiejar
        import urllib.request
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        request = urllib.request.Request(
            f"http://127.0.0.1:{port}/api/v2/browser/login",
            data=json.dumps({"code": minted["login_code"]}).encode(),
            headers={"Content-Type": "application/json",
                     "Origin": f"http://127.0.0.1:{port}"}, method="POST")
        opener.open(request, timeout=30).read()
        with opener.open(urllib.request.Request(
                f"http://127.0.0.1:{port}/api/v2/settings?scope=platform&key=instance_name"),
                timeout=30) as answer:
            snapshot = json.loads(answer.read().decode())
        effective = [item for item in snapshot.get("settings", [])
                     if item.get("key") == "instance_name"]
        report["the_effective_setting"] = effective[0] if effective else None
        assert effective, snapshot
        assert effective[0].get("effective", {}).get("value") == "Meine Instanz", effective[0]
        report["the_value_is_effective"] = True
        report["steps"].append("the value is effective at the next start")
        tool("stop")

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
    # The revision the receipt was measured on: a reader of the evidence must

    # be able to tell whether it is current.

    report["the_revision"] = subprocess.check_output(

        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()

    report["the_tree"] = subprocess.check_output(

        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()

    report["the_working_tree_is_clean"] = not subprocess.check_output(

        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()

    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "settings-offline.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "steps"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
