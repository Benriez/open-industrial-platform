#!/usr/bin/env python3
"""The reconnect and the recovery of the application (G6, G11, G12).

The operator restarts the instance routinely. The application must never show
stale data as live, and it must tell the operator what happened.

This rehearsal runs the real Core and the delivered web release in a browser
and restarts the instance in the middle of the session:

  1. the operator authorizes the session and sees the authorized projection;
  2. the instance is restarted by the rehearsal;
  3. the surface stops claiming a live connection, asks the operator for a new
     code and names the restart as a cause of the end of the session;
  4. a new code restores the authorized projection with a fresh moment.

The restart is carried out by a small control server of the rehearsal, so the
browser journey can trigger it without knowing anything about the instance.

Nothing of the rehearsal touches the personal installation of the operator and
nothing leaves the machine.

Usage:
  python3 tests/oip_reconnect_recovery.py [--evidence DIR]
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
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "oip_ops.py"
SIMULATOR = ROOT / "target/debug/oip-simulated-server"


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


class Control:
    """The control server of the rehearsal.

    It issues the one-time codes of the operator and restarts the instance.
    """

    def __init__(self, binary, state, work, port):
        self.binary = binary
        self.state = state
        self.work = work
        self.port = port
        self.restarts = 0

    def code(self):
        """A fresh one-time code of the operator.

        The code is never written into a receipt: it is handed to the browser
        journey and forgotten.
        """
        answer = subprocess.check_output(
            [self.binary, "--browser-login", "--ipc-socket", str(self.work / "s"),
             "--ipc-credential", str(self.work / "platform.credential")],
            text=True)
        return json.loads(answer)["login_code"]

    def restart(self):
        self.restarts += 1
        subprocess.run([sys.executable, str(TOOL), "--state-dir", str(self.state),
                        "--config", str(self.work / "core.json"),
                        "--ipc-config", str(self.work / "ipc.json"),
                        "--binary", self.binary, "stop"], capture_output=True, text=True)
        time.sleep(2)
        subprocess.run([sys.executable, str(TOOL), "--state-dir", str(self.state),
                        "--config", str(self.work / "core.json"),
                        "--ipc-config", str(self.work / "ipc.json"),
                        "--binary", self.binary, "start"], capture_output=True, text=True)
        time.sleep(3)
        return self.restarts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-reconnect-recovery"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-reconnect-recovery-rehearsal-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-reconnect-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    simulators = []
    control_server = None
    try:
        source_ports = [free_port() for _ in range(4)]
        port = free_port()
        control_port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": port,
            "sources": [{"id": f"source-{letter}", "name": f"Local simulation {letter}",
                         "endpoint": f"opc.tcp://127.0.0.1:{source_ports[index]}",
                         "namespace": 2}
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

        for index, simulator_port in enumerate(source_ports):
            simulators.append(subprocess.Popen(
                [str(SIMULATOR), "--port", str(simulator_port), "--seed", str(42 + index * 7),
                 "--tick-ms", "250"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        time.sleep(2)
        tool("provision-plan", "--plan", str(work / "plan.json"))
        tool("start")
        time.sleep(3)
        report["steps"].append("the instance runs")

        control = Control(args.binary, state, work, control_port)

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *arguments):
                return

            def _answer(self, status, body, content_type="text/plain"):
                payload = body.encode()
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def do_GET(self):
                if self.path == "/code":
                    self._answer(200, control.code())
                    return
                self._answer(404, "unknown")

            def do_POST(self):
                if self.path == "/restart":
                    self._answer(200, json.dumps({"restarts": control.restart()}),
                                 "application/json")
                    return
                self._answer(404, "unknown")

        control_server = http.server.ThreadingHTTPServer(("127.0.0.1", control_port), Handler)
        threading.Thread(target=control_server.serve_forever, daemon=True).start()

        result = subprocess.run(
            ["node", str(ROOT / "apps/flutter/test/browser_reconnect_recovery.mjs"),
             f"http://127.0.0.1:{port}", f"http://127.0.0.1:{control_port}", str(evidence)],
            cwd=ROOT, capture_output=True, text=True, timeout=2400,
            env=dict(os.environ,
                     OIP_REVISION=subprocess.check_output(
                         ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                     PLAYWRIGHT_MODULE=(os.environ.get("PLAYWRIGHT_MODULE")
                                        or str(ROOT / "apps/flutter/test/node_modules/playwright/index.mjs"))))
        if result.returncode != 0:
            raise AssertionError(f"the browser journey failed: "
                                 f"{result.stderr.strip()[-600:] or result.stdout.strip()[-600:]}")
        receipt = json.loads((evidence / "reconnect-recovery.json").read_text())
        report["browser_receipt"] = receipt
        assert receipt["errors"] == [], receipt["errors"]
        assert all(item["ok"] for item in receipt["findings"]), receipt["findings"]
        report["checks"] = len(receipt["findings"])
        report["the_restarts"] = control.restarts
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        if control_server is not None:
            control_server.shutdown()
        for simulator in simulators:
            if simulator.poll() is None:
                simulator.terminate()
                try:
                    simulator.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    simulator.kill()
        try:
            subprocess.run([sys.executable, str(TOOL), "--state-dir", str(work / "state"),
                            "--config", str(work / "core.json"),
                            "--ipc-config", str(work / "ipc.json"),
                            "--binary", args.binary, "stop"], capture_output=True, text=True)
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
    (evidence / "reconnect-recovery-rehearsal.json").write_text(
        json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items()
                      if k not in ("browser_receipt", "steps")}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
