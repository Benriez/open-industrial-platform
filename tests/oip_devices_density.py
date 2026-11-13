#!/usr/bin/env python3
"""The density of the Devices workspace in the browser (G7, G8).

The workspace of the devices must stay usable at every width: the document
may never scroll horizontally and no control of the filter toolbar may be
clipped outside the viewport — at 320, 390, 768, 1024, 1440 and 1920 px and
in every theme. The rehearsal drives the **real** surface against a real Core
with an authorized session and registers the devices through the authorized
route, so the rows of the inventory are the devices that the Core delivered.

The instance is disposable and owns its store, so the inventory of the
operator is real.

Usage:
  python3 tests/oip_devices_density.py [--evidence DIR]
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
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "oip_ops.py"


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
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-devices-density"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-devices-density-rehearsal-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-devices-density-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    try:
        port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        # The reader of the inventory writes the inventory: the devices of the
        # rehearsal are registered through the authorized route.
        plan["roles"].append({
            "id": "inventory-writer", "name": "Explicit scoped inventory writer",
            "permissions": ["inventory_manage", "devices_read"],
        })
        plan["bindings"].append({
            "principal_id": "reader-org-a", "role_id": "inventory-writer",
            "scope": {"kind": "organization", "id": "org-a"},
        })
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        # The sources of the plan need their definitions: the collectors of
        # the instance are the ones of the plan (the rehearsal measures the
        # layout of the workspace, not the collectors).
        source_ports = [free_port() for _ in range(4)]
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

        tool("provision-plan", "--plan", str(work / "plan.json"))
        tool("start")
        time.sleep(4)
        report["steps"].append("the instance runs with its authorized session")

        # The authorized session of the operator: the devices of the rehearsal
        # are registered through the route that the surface uses.
        minted = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(credential)], text=True))
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        login = urllib.request.Request(
            f"{base}/api/v2/browser/login",
            data=json.dumps({"code": minted["login_code"]}).encode(),
            headers={"Content-Type": "application/json", "Origin": base}, method="POST")
        with opener.open(login, timeout=60) as answer:
            session = json.loads(answer.read().decode())
        assert session.get("authenticated") is True, session

        devices = [
            {"id": "density-device-a1", "display_name": "Dichte Messung A1",
             "device_type": "server", "site_id": "site-a1", "metadata": {}},
            {"id": "density-device-a2", "display_name": "Dichte Messung A2",
             "device_type": "sensor", "site_id": "site-a1", "metadata": {}},
        ]
        apply = urllib.request.Request(
            f"{base}/api/v2/inventory/apply",
            data=json.dumps({"changes": [{"operation": "register", "device": device}
                                         for device in devices]}).encode(),
            headers={"Content-Type": "application/json", "Origin": base,
                     "x-oip-csrf": session.get("csrf_token") or ""}, method="POST")
        with opener.open(apply, timeout=60) as answer:
            applied = json.loads(answer.read().decode())
        assert applied.get("applied") is True, applied
        report["the_devices"] = [device["id"] for device in devices]
        report["steps"].append("the devices are registered through the authorized route")

        result = subprocess.run(
            ["node", str(ROOT / "apps/flutter/test/browser_devices_density.mjs")],
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
            report["the_error_of_the_journey"] = result.stderr[-2000:]
            raise AssertionError(f"the browser journey failed: "
                                 f"{result.stderr.strip()[-600:] or result.stdout.strip()[-600:]}")
        receipt = json.loads((evidence / "responsive-report.json").read_text())
        report["browser_receipt"] = receipt
        assert receipt.get("verdict") == "PASS", receipt
        assert not receipt.get("pageErrors"), receipt.get("pageErrors")
        assert not receipt.get("overflowErrors"), receipt.get("overflowErrors")
        report["checks"] = len(receipt["checks"])
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

    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "devices-density.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report.get("status"),
                      "the_checks": report.get("checks"),
                      "the_error": report.get("error")}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
