#!/usr/bin/env python3
"""The scope of the operator across a refresh of the projection (G3).

The gate G3 asks for the **Global Infrastructure Context**: the operator
selects an individual infrastructure or sees all the authorized infrastructures
together. The record proves that the scope follows the operator across the six
workstations and that a new session starts in the unified view again — both
against the real Core. The third part, that the scope **survives a refresh of
the authorized projection**, was pinned by a widget test over the contract
fixtures.

This rehearsal proves that part against the **real Core**: the operator
selects a scope, the Core changes (an authorized write), the authorized
projection is delivered again, and the scope of the operator must be the scope
of the operator still.

Nothing of the rehearsal touches the personal installation of the operator, no
private endpoint is contacted and no hardware is invented.

Usage:
  python3 tests/oip_scope_persistence.py [--evidence DIR] [--binary PATH]
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


def the_digest_of(path):
    """The digest of the binary that the rehearsal drove."""
    import hashlib
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


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
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-scope-persistence"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-scope-persistence-rehearsal-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-scope-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    try:
        port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        # The principal administers the inventory, so that the authorized write
        # of the journey is permitted.
        plan["roles"].append({
            "id": "inventory-admin", "name": "Explicit scoped operator",
            "permissions": ["inventory_manage", "devices_read", "telemetry_read"]})
        plan["bindings"].append({
            "principal_id": "reader-org-a", "role_id": "inventory-admin",
            "scope": {"kind": "organization", "id": "org-a"}})
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        # The sources of the plan are declared, so that the hierarchy of the
        # instance holds the devices of the scope. No collector runs: the
        # proof is about the scope of the operator, not about the telemetry.
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": port,
            "sources": [{"id": f"source-{letter}", "name": f"Local simulation {letter}",
                         "endpoint": f"opc.tcp://127.0.0.1:{15860 + index}"}
                        for index, letter in enumerate("abcd")],
            "legacy_single_infrastructure": False,
            "web_dir": str(ROOT / "apps/flutter/build/web")}, indent=2))
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
                                    capture_output=True, text=True, timeout=900)
            if expect_success and result.returncode != 0:
                raise AssertionError(f"{arguments[0]} failed: "
                                     f"{result.stderr.strip() or result.stdout.strip()}")
            return result

        tool("provision-plan", "--plan", str(work / "plan.json"))
        tool("start")
        time.sleep(4)
        report["steps"].append("the instance runs")

        # A **manually registered** device of the scope: the devices of the
        # plan belong to their source and are not administered by the surface.
        minted = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(credential)], text=True))
        import http.cookiejar
        import urllib.error
        import urllib.request
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        login = urllib.request.Request(
            f"http://127.0.0.1:{port}/api/v2/browser/login",
            data=json.dumps({"code": minted["login_code"]}).encode(),
            headers={"Content-Type": "application/json",
                     "Origin": f"http://127.0.0.1:{port}"}, method="POST")
        with opener.open(login, timeout=60) as answer:
            session = json.loads(answer.read().decode())
        write = urllib.request.Request(
            f"http://127.0.0.1:{port}/api/v2/inventory/apply",
            data=json.dumps({"changes": [{"operation": "register", "device": {
                "id": "scope-device", "display_name": "Scope device",
                "device_type": "other", "site_id": "site-a1", "metadata": {}}}]}).encode(),
            headers={"Content-Type": "application/json",
                     "Origin": f"http://127.0.0.1:{port}",
                     "x-oip-csrf": session["csrf_token"]}, method="POST")
        try:
            with opener.open(write, timeout=60) as answer:
                registered = json.loads(answer.read().decode())
        except urllib.error.HTTPError as error:
            raise AssertionError(f"the Core refused the registration: "
                                 f"{error.code} {error.read().decode()[:300]}")
        # The answer of the Core names the action and the revision it
        # expected. The device itself is read back from the Core, so that the
        # receipt carries the record of the Core and not a guess about the
        # shape of its answer.
        report["the_registered_actions"] = registered.get("actions", [])
        with opener.open(urllib.request.Request(
                f"http://127.0.0.1:{port}/api/v2/inventory/devices?q=scope-device",
                headers={"Content-Type": "application/json"}), timeout=60) as answer:
            page = json.loads(answer.read().decode())
        records = [item.get("record", item) for item in page.get("items", [])]
        if not records:
            raise AssertionError(f"the Core holds no device of the scope: {page}")
        device = records[0].get("device", records[0])
        report["the_registered_device"] = {
            "the_id": device.get("id"),
            "the_display_name": device.get("display_name"),
            "the_type": device.get("device_type"),
            "the_site": device.get("site_id"),
            "the_revision": records[0].get("revision"),
        }
        report["steps"].append("a manual device of the scope is registered")

        result = subprocess.run(
            ["node", str(ROOT / "apps/flutter/test/browser_scope_persistence.mjs"),
             f"http://127.0.0.1:{port}", str(evidence)],
            cwd=ROOT, capture_output=True, text=True, timeout=2400,
            env=dict(os.environ,
                     OIP_REVISION=subprocess.check_output(
                         ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                     OIP_IPC_SOCKET=str(work / "s"),
                     OIP_BROWSER_CREDENTIAL=str(credential),
                     OIP_SERVER_BIN=args.binary,
                     PLAYWRIGHT_MODULE=playwright_module()))
        if result.returncode != 0:
            raise AssertionError(f"the browser journey failed: "
                                 f"{result.stderr.strip()[-600:] or result.stdout.strip()[-600:]}")
        receipt = json.loads((evidence / "scope-persistence.json").read_text())
        report["browser_receipt"] = receipt
        assert receipt["errors"] == [], receipt["errors"]
        assert all(item["ok"] for item in receipt["findings"]), receipt["findings"]
        report["the_selected_scope"] = receipt["the_selected_scope"]
        report["the_scope_after_the_refresh"] = receipt["the_scope_after_the_refresh"]
        report["the_scope_of_the_new_session"] = receipt["the_scope_of_the_new_session"]
        report["checks"] = len(receipt["findings"])
        report["steps"].append("the scope of the operator survives the refresh of the projection")
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    except Exception as error:  # noqa: BLE001 - the receipt names every failure
        report["status"] = "FAIL"
        report["error"] = f"{type(error).__name__}: {error}"
    finally:
        try:
            tool("stop", expect_success=False)
        except Exception:
            pass
        shutil.rmtree(work, ignore_errors=True)

    report["the_core_binary"] = {"the_path": str(args.binary),
                                 "the_sha256": the_digest_of(args.binary)}
    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "scope-persistence-rehearsal.json").write_text(
        json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items()
                      if k not in ("browser_receipt", "steps")}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
