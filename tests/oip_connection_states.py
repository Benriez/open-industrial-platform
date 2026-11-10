#!/usr/bin/env python3
"""The honest connection states of the surface, against the real Core (G5, G6).

The gate G5 asks for the **honest connection states**, and the gate G6 for the
reconnect and the failure recovery. The record pinned the six states of the
surface with a **widget test over fixture DTOs**: collecting, verified without
monitoring, a changed host key, an unknown host key, an unreachable host and
stale measurements. A fixture proves that the client maps a state to a word —
it does not prove that the **Core** produces that state and that the surface
shows the truth about it.

This rehearsal drives the **real Core** and an owned loopback SSH fixture
through the states that the Core can really produce, and the browser journey
reads the word of the surface in every one of them:

  * the device is verified without the monitoring — the Core answers
    `ssh_verified`;
  * the monitoring is enabled — the Core answers `collecting`;
  * the measurements age past the threshold of the Core — the Core answers
    `stale`;
  * the host disappears — the Core answers `unreachable`;
  * the host comes back — the Core collects again (`collecting`): the recovery;
  * the host comes back with **another** host key — the Core blocks the
    connection (`host_key_changed`).

Nothing of the rehearsal touches the personal installation of the operator, no
private endpoint is contacted and no hardware is invented: the host is an owned
SSH fixture on the loopback.

Usage:
  python3 tests/oip_connection_states.py [--evidence DIR] [--binary PATH]
"""
import argparse
import http.cookiejar
import http.server
import json
import os
import pathlib
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests" / "real_device"))
sys.path.insert(0, str(ROOT / "tests"))

from ssh_fixture import SshFixture  # noqa: E402

TOOL = ROOT / "tools" / "oip_ops.py"
THE_DEVICE = "state-device"


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def request(base, path, body=None, headers=None, opener=None, method=None):
    """The request helper of the proven rehearsals (the same signature)."""
    headers = dict(headers or {})
    data = json.dumps(body).encode() if body is not None else None
    if data is not None:
        headers["Content-Type"] = "application/json"
    call = urllib.request.Request(base + path, data=data, headers=headers,
                                  method=method or ("POST" if data else "GET"))
    try:
        with (opener.open(call, timeout=60) if opener
              else urllib.request.urlopen(call, timeout=60)) as answer:
            return answer.status, json.loads(answer.read().decode() or "{}")
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode() or "{}")


class Control(http.server.BaseHTTPRequestHandler):
    """The control of the host of the rehearsal.

    The journey asks the control to change the state of the **host** — the
    host disappears, comes back or comes back with another key — and the
    rehearsal answers with what it did. The Core is never touched.
    """

    fixture = None
    actions = []

    def do_POST(self):
        action = self.path.strip("/")
        try:
            if action == "stop":
                self.fixture.stop()
                outcome = "the host is stopped"
            elif action == "start":
                self.fixture.start()
                outcome = "the host runs again"
            elif action == "rotate":
                self.fixture.rotate()
                outcome = "the host has another key"
            else:
                self._answer(404, json.dumps({"error": "unknown action"}))
                return
        except Exception as error:  # noqa: BLE001 - the answer names the failure
            self._answer(500, json.dumps({"error": str(error)[:200]}))
            return
        Control.actions.append({"the_action": action, "the_outcome": outcome})
        self._answer(200, json.dumps({"the_action": action, "the_outcome": outcome,
                                      "the_actions": len(Control.actions)}))

    def _answer(self, status, payload):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        # The journey asks the control from the page of the application: the
        # answer must be readable for the browser.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(payload.encode())

    def do_OPTIONS(self):
        self._answer(204, b"")

    def log_message(self, *arguments):
        return


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
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-connection-states"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-connection-states-rehearsal-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-states-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    fixture = None
    control = None
    try:
        fixture = SshFixture()
        report["ssh_fixture"] = {"port": fixture.port, "user": fixture.user,
                                 "loopback_only": True}
        port = free_port()
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
        # The measurements of the device age quickly, so the state of the Core
        # changes within the run: the state `stale` is one of the states that
        # the surface must show.
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": port, "sources": [],
            "legacy_single_infrastructure": False,
            "stale_after_ms": 8000, "shutdown_timeout_ms": 6000,
            "web_dir": str(ROOT / "apps/flutter/build/web"),
            "ssh": {"profiles": [{
                "id": "fixture", "label": "Owned loopback SSH fixture",
                "principals": ["reader-org-a"], "allowed_hosts": ["127.0.0.1"],
                "allowed_ports": [fixture.port],
                "identity_file": str(pathlib.Path(fixture.directory) / "client"),
                "agent_socket": None, "known_hosts_file": None, "aliases": {}}]}}, indent=2))
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
        base = f"http://127.0.0.1:{port}"

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
        time.sleep(3)
        report["steps"].append("the instance runs")

        # The control of the host of the rehearsal.
        Control.fixture = fixture
        control_port = free_port()
        control = http.server.ThreadingHTTPServer(("127.0.0.1", control_port), Control)
        threading.Thread(target=control.serve_forever, daemon=True).start()
        report["the_control"] = {"the_port": control_port,
                                 "the_note": "the journey asks the control to change the "
                                             "state of the host; the Core is never touched"}

        minted = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(credential)], text=True))
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        status, session = request(base, "/api/v2/browser/login",
                                  {"code": minted["login_code"]}, {"Origin": base}, opener)
        assert status == 200, session
        headers = {"Origin": base, "x-oip-csrf": session["csrf_token"]}

        status, answer = request(base, "/api/v2/inventory/apply", {"changes": [{
            "operation": "register",
            "device": {"id": THE_DEVICE, "display_name": "State device",
                       "device_type": "single_board_computer", "site_id": "site-a1",
                       "metadata": {}}}]}, headers, opener)
        assert status == 200, f"the device was not registered: {answer}"

        # The connection with the confirmed host key, verified **without** the
        # monitoring: the Core answers `ssh_verified`.
        endpoint = {"host": "127.0.0.1", "port": fixture.port, "user": fixture.user,
                    "identity_profile": "fixture"}
        target = {"kind": "existing", "id": THE_DEVICE, "expected_revision": 1}
        status, answer = request(base, "/api/v2/device-connections", {
            "operation": "start", "target": target, "endpoint": endpoint}, headers, opener)
        assert status == 200, answer
        plan_id = answer["plan"]["plan_id"]

        def wait_stage(stage, timeout=90):
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
        status, answer = request(base, "/api/v2/device-connections", {
            "operation": "trust_host_key", "plan_id": plan_id, "fingerprint": fingerprint},
            headers, opener)
        assert status == 200, f"the host key was not accepted: {answer}"
        status, answer = request(base, "/api/v2/device-connections", {
            "operation": "verify", "plan_id": plan_id}, headers, opener)
        assert status == 200, f"the verification failed: {answer}"
        wait_stage("verification_complete")
        status, answer = request(base, "/api/v2/device-connections", {
            "operation": "confirm", "plan_id": plan_id, "identity_confirmed": True,
            "enable_monitoring": False, "poll_seconds": 30}, headers, opener)
        assert status == 200, f"the confirmation failed: {answer}"
        report["the_host_key_fingerprint"] = fingerprint
        report["steps"].append("the device is verified without the monitoring")

        # The journey drives the surface through the states of the Core.
        result = subprocess.run(
            ["node", str(ROOT / "apps/flutter/test/browser_connection_states.mjs"),
             base, str(evidence), THE_DEVICE],
            cwd=ROOT, capture_output=True, text=True, timeout=3600,
            env=dict(os.environ,
                     OIP_REVISION=subprocess.check_output(
                         ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                     OIP_IPC_SOCKET=str(work / "s"),
                     OIP_BROWSER_CREDENTIAL=str(credential),
                     OIP_SERVER_BIN=args.binary,
                     OIP_CONTROL_URL=f"http://127.0.0.1:{control_port}",
                     OIP_EXPECTED_FINGERPRINT=fingerprint,
                     PLAYWRIGHT_MODULE=playwright_module()))
        if result.returncode != 0:
            raise AssertionError(f"the browser journey failed: "
                                 f"{result.stderr.strip()[-800:] or result.stdout.strip()[-800:]}")
        receipt = json.loads((evidence / "connection-states.json").read_text())
        report["browser_receipt"] = receipt
        assert receipt["errors"] == [], receipt["errors"]
        assert all(item["ok"] for item in receipt["findings"]), receipt["findings"]
        report["the_states"] = receipt["the_states"]
        report["the_states_of_the_surface"] = [item["the_line"] for item in receipt["the_states"]]
        report["the_actions_of_the_control"] = Control.actions
        report["checks"] = len(receipt["findings"])
        report["steps"].append("the surface shows the truth in every state of the Core")
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
        if control is not None:
            try:
                control.shutdown()
            except Exception:
                pass
        if fixture is not None:
            try:
                fixture.stop()
            except Exception:
                pass
        shutil.rmtree(work, ignore_errors=True)

    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "connection-states-rehearsal.json").write_text(
        json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items()
                      if k not in ("browser_receipt", "steps")}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
