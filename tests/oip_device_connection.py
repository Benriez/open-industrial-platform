#!/usr/bin/env python3
"""The verified connection of a device in the operator surface (G4).

The device workspace shows the association of a device with its connection.
This rehearsal proves that association against the real Core and an **owned
loopback SSH fixture** with a real host key:

  1. the device is registered through the authorized managed session;
  2. the connection is started, the host key of the fixture is presented and
     the operator confirms it, the identity of the host is verified and the
     identity confirmation enables the read-only monitoring;
  3. the browser journey shows the device with that connection: the state,
     the confirmed host key, the endpoint, the really verified identity, the
     read-only monitoring and the measurements that were really read.

The fixture is an owned OpenSSH server on the loopback of the machine. No
system service, no personal endpoint, no private key in a receipt.

Usage:
  python3 tests/oip_device_connection.py [--evidence DIR]
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
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests" / "real_device"))
from ssh_fixture import SshFixture  # noqa: E402

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


def request(base, path, body=None, headers=None, opener=None, method=None):
    headers = dict(headers or {})
    data = json.dumps(body).encode() if body is not None else None
    if data is not None:
        headers["Content-Type"] = "application/json"
    call = urllib.request.Request(base + path, data=data, headers=headers,
                                   method=method or ("POST" if data else "GET"))
    try:
        with (opener.open(call, timeout=30) if opener
              else urllib.request.urlopen(call, timeout=30)) as answer:
            return answer.status, json.loads(answer.read().decode() or "{}")
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode() or "{}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-device-connection"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-device-connection-rehearsal-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-device-connection-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    fixture = None
    try:
        fixture = SshFixture()
        report["ssh_fixture"] = {"port": fixture.port, "user": fixture.user,
                                 "loopback_only": True}
        http_port = free_port()
        config = json.loads((ROOT / "examples/multi-infrastructure-core.json").read_text())
        config.update(database=str(work / "core.sqlite"), http_port=http_port,
                      sources=[], stale_after_ms=2000, shutdown_timeout_ms=6000,
                      web_dir=str(ROOT / "apps/flutter/build/web"))
        config["ssh"] = {"profiles": [{
            "id": "fixture", "label": "Owned loopback SSH fixture",
            "principals": ["reader-org-a"], "allowed_hosts": ["127.0.0.1"],
            "allowed_ports": [fixture.port],
            "identity_file": str(pathlib.Path(fixture.directory) / "client"),
            "agent_socket": None, "known_hosts_file": None, "aliases": {}}]}
        (work / "core.json").write_text(json.dumps(config, indent=2))
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        plan["sources"] = []
        plan["bindings"] = [item for item in plan["bindings"]
                            if item["scope"]["kind"] != "source"]
        plan["roles"].append({"id": "inventory-admin", "name": "Explicit scoped operator",
                               "permissions": ["inventory_manage", "devices_read",
                                               "telemetry_read"]})
        plan["bindings"].append({"principal_id": "reader-org-a",
                                 "role_id": "inventory-admin",
                                 "scope": {"kind": "organization", "id": "org-a"}})
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
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
        base = f"http://127.0.0.1:{http_port}"

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

        # The operator session of the managed instance.
        minted = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(credential)], text=True))
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        status, session = request(base, "/api/v2/browser/login", {"code": minted["login_code"]},
                                  {"Origin": base}, opener)
        assert status == 200, session
        headers = {"Origin": base, "x-oip-csrf": session["csrf_token"]}

        # 1. the device of the authorized inventory
        status, _ = request(base, "/api/v2/inventory/apply", {"changes": [{
            "operation": "register",
            "device": {"id": "existing-pi", "display_name": "Existing inventory identity",
                       "device_type": "single_board_computer", "site_id": "site-a1",
                       "metadata": {}}}]}, headers, opener)
        assert status == 200, "the device was not registered"
        report["steps"].append("the device is registered")

        # 2. the connection with the confirmed host key
        endpoint = {"host": "127.0.0.1", "port": fixture.port, "user": fixture.user,
                    "identity_profile": "fixture"}
        target = {"kind": "existing", "id": "existing-pi", "expected_revision": 1}
        status, answer = request(base, "/api/v2/device-connections", {
            "operation": "start", "target": target, "endpoint": endpoint}, headers, opener)
        assert status == 200, answer
        plan_id = answer["plan"]["plan_id"]

        def wait_stage(stage, timeout=60):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                _, value = request(base, f"/api/v2/device-connections?plan_id={plan_id}",
                                   opener=opener)
                if value["plan"]["stage"] == stage:
                    return value["plan"]
                if value["plan"]["stage"] == "failed":
                    raise AssertionError(f"the connection failed: {value['plan']['error']}")
                time.sleep(0.5)
            raise AssertionError(f"the connection did not reach the stage {stage}")

        awaiting = wait_stage("awaiting_host_key")
        fingerprint = awaiting["host_key_fingerprint"]
        assert fingerprint.startswith("SHA256:"), fingerprint
        report["host_key_fingerprint"] = fingerprint
        status, _ = request(base, "/api/v2/device-connections", {
            "operation": "trust_host_key", "plan_id": plan_id, "fingerprint": fingerprint},
            headers, opener)
        assert status == 200, "the host key was not accepted"
        status, _ = request(base, "/api/v2/device-connections", {
            "operation": "verify", "plan_id": plan_id}, headers, opener)
        assert status == 200, "the verification failed"
        verified = wait_stage("verification_complete")
        identity = verified["identity"]
        report["verified_identity"] = {
            "hostname": identity.get("hostname"),
            "operating_system": identity.get("operating_system"),
            "memory_total_bytes": identity.get("memory_total_bytes"),
        }
        status, answer = request(base, "/api/v2/device-connections", {
            "operation": "confirm", "plan_id": plan_id, "identity_confirmed": True,
            "enable_monitoring": True, "poll_seconds": 10}, headers, opener)
        assert status == 200, answer
        report["connection"] = answer["connection"]
        report["steps"].append("the connection is verified and confirmed")

        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            _, value = request(base, "/api/v2/device-connections?device_id=existing-pi",
                               opener=opener)
            if value.get("connection", {}).get("status") == "collecting":
                break
            time.sleep(0.5)
        report["connection_status"] = value.get("connection", {}).get("status")
        assert report["connection_status"] == "collecting", report["connection_status"]
        report["steps"].append("the device collects")

        # 3. the surface shows the association
        result = subprocess.run(
            ["node", str(ROOT / "apps/flutter/test/browser_device_connection.mjs"),
             base, str(evidence)],
            cwd=ROOT, capture_output=True, text=True, timeout=2400,
            env=dict(os.environ,
                     OIP_REVISION=subprocess.check_output(
                         ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                     OIP_IPC_SOCKET=str(work / "s"),
                     OIP_BROWSER_CREDENTIAL=str(credential),
                     OIP_SERVER_BIN=args.binary,
                     OIP_EXPECTED_FINGERPRINT=fingerprint,
                     OIP_EXPECTED_CONNECTION_STATUS=report["connection_status"],
                     PLAYWRIGHT_MODULE=playwright_module()))
        if result.returncode != 0:
            raise AssertionError(f"the browser journey failed: "
                                 f"{result.stderr.strip()[-600:] or result.stdout.strip()[-600:]}")
        receipt = json.loads((evidence / "device-connection.json").read_text())
        report["browser_receipt"] = receipt
        assert receipt["errors"] == [], receipt["errors"]
        assert all(item["ok"] for item in receipt["findings"]), receipt["findings"]
        report["checks"] = len(receipt["findings"])
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        if fixture is not None:
            try:
                fixture.stop()
            except Exception:
                pass
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
    (evidence / "device-connection-rehearsal.json").write_text(
        json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items()
                      if k not in ("browser_receipt", "steps")}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
