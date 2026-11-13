#!/usr/bin/env python3
"""The geometry of the Devices workspace in the browser (G7, G12).

The layout of the workspace is a claim of the release: the operator accepts
the visible result (G12), and the numbers of the layout are the evidence that
the acceptance can look at. The rehearsal starts a disposable Core with the
plan of the operator, registers the devices **through the authorized route**
(so the rows of the inventory are the devices that the Core delivered) and
drives the real surface in the browser
(`apps/flutter/test/browser_devices_geometry.mjs`): the four states of the
workspace — no selection, a device selected, the secondary filters open and
the comparison — at 1440 px and 1920 px.

The instance is disposable and owns its store, so the inventory of the
operator is real.

Usage:
  python3 tests/oip_devices_geometry.py [--evidence DIR]
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

DEVICES = [
    {"id": "geometry-device-a1", "display_name": "Geometrie Messung A1",
     "device_type": "server", "site_id": "site-a1", "metadata": {}},
    {"id": "geometry-device-a2", "display_name": "Geometrie Messung A2",
     "device_type": "sensor", "site_id": "site-a1", "metadata": {}},
]


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
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-devices-geometry"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-devices-geometry-rehearsal-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-devices-geometry-", dir="/private/tmp")).resolve()
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
        # The sources of the plan need their definitions: the collectors of the
        # instance are the ones of the plan (the rehearsal measures the layout
        # of the workspace, not the collectors).
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

        apply = urllib.request.Request(
            f"{base}/api/v2/inventory/apply",
            data=json.dumps({"changes": [{"operation": "register", "device": device}
                                         for device in DEVICES]}).encode(),
            headers={"Content-Type": "application/json", "Origin": base,
                     "x-oip-csrf": session.get("csrf_token") or ""}, method="POST")
        with opener.open(apply, timeout=60) as answer:
            applied = json.loads(answer.read().decode())
        assert applied.get("applied") is True, applied
        report["the_devices"] = [device["id"] for device in DEVICES]
        report["steps"].append("the devices are registered through the authorized route")

        result = subprocess.run(
            ["node", str(ROOT / "apps/flutter/test/browser_devices_geometry.mjs")],
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
        receipt = json.loads((evidence / "devices-geometry.json").read_text())
        report["browser_receipt"] = receipt
        assert receipt.get("status") == "PASS", receipt
        assert not receipt.get("the_page_errors"), receipt.get("the_page_errors")
        assert not receipt.get("the_overflow_errors"), receipt.get("the_overflow_errors")
        report["checks"] = len(receipt["the_checks"])
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
    (evidence / "devices-geometry-rehearsal.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report.get("status"),
                      "the_checks": report.get("checks"),
                      "the_error": report.get("error")}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
