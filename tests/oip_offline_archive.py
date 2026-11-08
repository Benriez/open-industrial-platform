#!/usr/bin/env python3
"""The offline archive of a device.

The managed session of the Core refuses an archive with
OFFLINE_ARCHIVE_REQUIRED: the archive is an explicit offline operation. This
rehearsal proves the supported path against a disposable instance:

  1. the device is registered through the authorized managed session;
  2. the Core is stopped;
  3. the archive is applied with the offline plan of the Core;
  4. the Core starts again and the device is archived, with its record and its
     history intact.

Nothing touches the personal installation of the operator.

Usage:
  python3 tests/oip_offline_archive.py [--evidence DIR]
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


def tool(state, config, ipc, binary, *arguments, expect_success=True):
    result = subprocess.run([sys.executable, str(TOOL), "--state-dir", str(state),
                             "--config", str(config), "--ipc-config", str(ipc),
                             "--binary", str(binary), *arguments],
                            capture_output=True, text=True, timeout=300)
    if expect_success and result.returncode != 0:
        raise AssertionError(f"{arguments[0]} failed: "
                             f"{result.stderr.strip() or result.stdout.strip()}")
    return result


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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-offline-archive"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-offline-archive-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-archive-")).resolve()
    work.chmod(0o700)
    try:
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        # The rehearsal needs one source that really answers: the writer of
        # the Core expires with unreachable collectors, and an expired writer
        # refuses every authorized write.
        plan["sources"] = [item for item in plan["sources"]
                           if item["source_id"] == "source-a"]
        plan["bindings"] = [item for item in plan["bindings"]
                            if item["scope"]["kind"] != "source"]
        # The operator needs the scoped permission of the inventory, exactly
        # as the acceptance harness grants it.
        plan["roles"].append({
            "id": "inventory-admin",
            "name": "Explicit scoped operator",
            "permissions": ["inventory_manage", "devices_read", "telemetry_read"],
        })
        plan["bindings"].append({
            "principal_id": "reader-org-a",
            "role_id": "inventory-admin",
            "scope": {"kind": "organization", "id": "org-a"},
        })
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        port = free_port()
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"),
            "http_port": port,
            "sources": [
                {"id": "source-a", "name": "Local simulation a",
                 "endpoint": "opc.tcp://127.0.0.1:4840", "namespace": 2},
            ],
            "legacy_single_infrastructure": False,
            "web_dir": str(ROOT / "apps/flutter/build/web"),
        }, indent=2))
        credential = work / "platform.credential"
        credential.write_bytes(secrets.token_bytes(32))
        credential.chmod(0o600)
        (work / "ipc.json").write_text(json.dumps({
            "socket": str(work / "s"),
            "max_sessions": 16,
            "clients": [{"uid": os.getuid(), "credential_file": str(credential),
                         "policy": {"principal": "reader-org-a"}}],
        }, indent=2))
        (work / "ipc.json").chmod(0o600)
        state = work / "state"
        base = f"http://127.0.0.1:{port}"

        tool(state, work / "core.json", work / "ipc.json", args.binary,
             "provision-plan", "--plan", str(work / "plan.json"))
        tool(state, work / "core.json", work / "ipc.json", args.binary, "start")
        time.sleep(2)
        report["steps"].append("the instance runs")

        # 1. the device is registered through the authorized managed session
        minted = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(credential)], text=True))
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        status, session = api(base, "/api/v2/browser/login", "POST",
                              {"code": minted["login_code"]},
                              {"Origin": base}, opener)
        assert status == 200, session
        headers = {"Origin": base, "x-oip-csrf": session["csrf_token"]}
        status, response = api(base, "/api/v2/inventory/apply", "POST", {
            "changes": [{"operation": "register", "device": {
                "id": "offline-archive-device",
                "display_name": "Offline archive fixture",
                "device_type": "server",
                "site_id": "site-a1",
                "metadata": {"serial_number": "OFFLINE-ARCHIVE-1"},
            }}]}, headers, opener)
        assert status == 200, response
        report["steps"].append("the device is registered through the managed session")

        # 2. the managed session refuses the online archive
        status, response = api(base, "/api/v2/inventory/apply", "POST", {
            "changes": [{"operation": "archive", "id": "offline-archive-device",
                         "expected_revision": 1}]}, headers, opener)
        assert status == 409, (status, response)
        assert response.get("code") == "OFFLINE_ARCHIVE_REQUIRED", response
        report["online_archive_refused"] = response.get("code")

        # 3. the Core is stopped and the archive is applied offline
        tool(state, work / "core.json", work / "ipc.json", args.binary, "stop")
        report["steps"].append("the Core is stopped")
        offline = work / "archive.json"
        offline.write_text(json.dumps({
            "principal": "reader-org-a",
            "changes": [{"operation": "archive", "id": "offline-archive-device",
                         "expected_revision": 1}],
        }, indent=2))
        # The offline plan is applied with the explicit flag of the Core; the
        # plan without it only proves that the archive is admissible.
        result = subprocess.run([args.binary, "--config", str(work / "core.json"),
                                 "--inventory-plan", str(offline),
                                 "--inventory-apply"],
                                capture_output=True, text=True, timeout=300)
        assert result.returncode == 0, result.stderr
        report["offline_apply"] = json.loads(result.stdout or "{}")
        report["steps"].append("the archive is applied with the offline plan")

        # 4. the Core starts again and the device is archived
        tool(state, work / "core.json", work / "ipc.json", args.binary, "start")
        time.sleep(3)
        # The browser session lives in the memory of the Core: the restart
        # ends it, so the operator authorizes a new one.
        minted = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(credential)], text=True))
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        status, session = api(base, "/api/v2/browser/login", "POST",
                              {"code": minted["login_code"]},
                              {"Origin": base}, opener)
        assert status == 200, session
        # An archived device is not part of the active inventory: the read
        # only shows it when the archived ones are asked for.
        status, active = api(base, "/api/v2/inventory/devices?limit=100",
                             opener=opener)
        assert status == 200, active
        assert all(item["record"]["device"]["id"] != "offline-archive-device"
                   for item in active["items"]), \
            "the archived device is still part of the active inventory"
        report["archived_device_hidden_from_the_active_inventory"] = True
        status, inventory = api(
            base, "/api/v2/inventory/devices?limit=100&include_archived=true",
            opener=opener)
        assert status == 200, inventory
        device = next((item for item in inventory["items"]
                       if item["record"]["device"]["id"] == "offline-archive-device"), None)
        assert device is not None, "the archived device disappeared from the inventory"
        assert device["record"]["registration"] == "archived", device["record"]
        assert device["record"]["revision"] == 2, device["record"]
        assert report["offline_apply"].get("applied") is True, report["offline_apply"]
        # The record and its identity survive the archive.
        assert device["record"]["device"]["display_name"] == "Offline archive fixture"
        assert device["record"]["device"]["metadata"]["serial_number"] == "OFFLINE-ARCHIVE-1"
        report["archived_device"] = {
            "id": device["record"]["device"]["id"],
            "registration": device["record"]["registration"],
            "revision": device["record"]["revision"],
            "identity_preserved": True,
            "metadata_preserved": True,
        }
        report["steps"].append("the Core serves the archived device again")
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        try:
            tool(state, work / "core.json", work / "ipc.json", args.binary, "stop",
                 expect_success=False)
        except Exception:
            pass
        shutil.rmtree(work, ignore_errors=True)

    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "offline-archive.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "steps"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
