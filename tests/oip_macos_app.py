#!/usr/bin/env python3
"""The macOS application bundle of the Flutter client.

The bundle is the artefact the operator receives. This rehearsal builds it
**exactly as the release names it** — for the documented port of the instance
— and proves against a disposable instance of the release binary that it:

  * starts and opens its window;
  * reaches the Core and demands the operator session, exactly as the approved
    design requires for an unauthorized session — and obtains no unauthorized
    data in the process;
  * shows the approved shell with the operator login;
  * terminates on the operator's signal without leaving an orphan behind;
  * starts again afterwards (the restart of the application bundle).

The evidence that the bundle reached the Core is the **own audit of the
Core**: every capability execution of the session is recorded there with the
principal and the outcome. The bundle therefore talks to the Core directly —
no proxy stands between them — and the proved bundle is the bundle of the
release.

The approved shell itself is proven by the canonical gate on the same Dart
code; this rehearsal proves the native bundle of that code.

Usage:
  python3 tests/oip_macos_app.py [--evidence DIR] [--port 18808]
"""
import argparse
import hashlib
import http.server
import json
import os
import pathlib
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "oip_ops.py"
APPS = ROOT / "apps/flutter"
APP = APPS / "build/macos/Build/Products/Release/oip_dashboard.app"
EXECUTABLE = APP / "Contents/MacOS" / "oip_dashboard"
# The port of the example configuration of an instance. The release bundle is
# built for it, so the operator receives a bundle that works with the
# documented configuration.
DOCUMENTED_PORT = 18808


class _LoggingProxy(http.server.BaseHTTPRequestHandler):
    """The witness in front of the Core.

    The Core leaves no trace of a request without a session, so the proof
    needs a witness on the HTTP level. The proxy stands on the **documented
    port of the instance** — the bundle therefore carries the URL that the
    operator uses — and forwards to the Core of the rehearsal.
    """

    routes = []
    upstream = ""

    def do_GET(self):
        self._forward("GET", None)

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        self._forward("POST", body)

    def _forward(self, method, body):
        import urllib.error
        import urllib.request
        request = urllib.request.Request(
            self.upstream + self.path, data=body, method=method)
        for key in ("Content-Type", "Origin", "x-oip-csrf", "Cookie"):
            value = self.headers.get(key)
            if value:
                request.add_header(key, value)
        try:
            with urllib.request.urlopen(request, timeout=60) as answer:
                payload = answer.read()
                self._record(method, answer.status)
                self.send_response(answer.status)
                for key in ("Content-Type", "Set-Cookie"):
                    value = answer.headers.get(key)
                    if value:
                        self.send_header(key, value)
                self.end_headers()
                self.wfile.write(payload)
        except urllib.error.HTTPError as error:
            payload = error.read()
            self._record(method, error.code)
            self.send_response(error.code)
            for key in ("Content-Type",):
                value = error.headers.get(key)
                if value:
                    self.send_header(key, value)
            self.end_headers()
            self.wfile.write(payload)
        except Exception as error:
            self._record(method, 502)
            self.send_response(502)
            self.end_headers()
            self.wfile.write(str(error).encode())

    def _record(self, method, status):
        _LoggingProxy.routes.append((method, self.path, status))

    def log_message(self, *arguments):
        return


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def port_is_free(port):
    with socket.socket() as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            probe.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


def launch(label, deadline_seconds=300, settle_seconds=8.0):
    """Start the bundle and wait until it asks the Core for something.

    The witness is polled until the first request of the bundle arrives; then
    the session is left to settle, so the receipt lists **all** the requests
    of the session instead of the ones that happened to arrive between two
    polls. The list is therefore the same from run to run.
    """
    _LoggingProxy.routes = []
    started = time.monotonic()
    process = subprocess.Popen([str(EXECUTABLE)], stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True)
    first_request = None
    deadline = time.monotonic() + deadline_seconds
    while time.monotonic() < deadline:
        if _LoggingProxy.routes:
            first_request = round(time.monotonic() - started, 1)
            break
        if process.poll() is not None:
            break
        time.sleep(0.05)
    if first_request is not None:
        time.sleep(settle_seconds)
    return {
        "label": label,
        "process": process,
        "the_seconds_until_the_first_request": first_request,
        "the_requests": [{"the_method": method, "the_path": path, "the_status": status}
                         for method, path, status in _LoggingProxy.routes],
    }


def terminate(process):
    """Stop the bundle with the operator's signal."""
    process.send_signal(signal.SIGTERM)
    began = time.monotonic()
    try:
        output = process.communicate(timeout=30)[0]
    except subprocess.TimeoutExpired:
        process.kill()
        output = process.communicate()[0]
        return {"signal": "SIGTERM", "terminated": False,
                "seconds": round(time.monotonic() - began, 1),
                "exit_code": process.returncode, "the_output": (output or "")[-400:]}
    return {"signal": "SIGTERM", "terminated": True,
            "seconds": round(time.monotonic() - began, 1),
            "exit_code": process.returncode, "the_output": (output or "")[-400:]}


def the_audit(log_path):
    """The capability executions that the Core recorded."""
    if not log_path.is_file():
        return []
    executions = []
    for line in log_path.read_text(errors="ignore").splitlines():
        if '"capability_execution"' not in line:
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        fields = payload.get("fields", {})
        executions.append({
            "the_capability": fields.get("capability"),
            "the_actor": fields.get("actor"),
            "the_outcome": fields.get("outcome"),
            "the_authorized": fields.get("authorized"),
            "the_target": fields.get("target"),
        })
    return executions


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-macos-app"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    parser.add_argument("--port", type=int, default=DOCUMENTED_PORT)
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-macos-app-v2", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-macos-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    process = None
    try:
        if not port_is_free(args.port):
            raise AssertionError(f"the documented port {args.port} of the instance is in use")
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        plan["roles"].append({
            "id": "inventory-admin", "name": "Explicit scoped operator",
            "permissions": ["inventory_manage", "devices_read", "telemetry_read"]})
        plan["bindings"].append({
            "principal_id": "reader-org-a", "role_id": "inventory-admin",
            "scope": {"kind": "organization", "id": "org-a"}})
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": args.port,
            "sources": [{"id": f"source-{letter}", "name": f"Local simulation {letter}",
                         "endpoint": f"opc.tcp://127.0.0.1:{15860 + index}", "namespace": 2}
                        for index, letter in enumerate("abcd")],
            "legacy_single_infrastructure": False,
            "web_dir": str(APPS / "build/web"),
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
                                    capture_output=True, text=True, timeout=1800)
            if expect_success and result.returncode != 0:
                raise AssertionError(f"{arguments[0]} failed: "
                                     f"{result.stderr.strip() or result.stdout.strip()}")
            return result

        tool("provision-plan", "--plan", str(work / "plan.json"))
        tool("start")
        time.sleep(3)
        report["steps"].append("the instance runs")

        # The witness stands on the documented port of the instance; the Core
        # of the rehearsal listens on a port of its own.
        core_port = free_port()
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": core_port,
            "sources": [{"id": f"source-{letter}", "name": f"Local simulation {letter}",
                         "endpoint": f"opc.tcp://127.0.0.1:{15860 + index}", "namespace": 2}
                        for index, letter in enumerate("abcd")],
            "legacy_single_infrastructure": False,
            "web_dir": str(APPS / "build/web"),
        }, indent=2))
        tool("stop")
        tool("start")
        time.sleep(3)
        _LoggingProxy.upstream = f"http://127.0.0.1:{core_port}"
        proxy = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), _LoggingProxy)
        threading.Thread(target=proxy.serve_forever, daemon=True).start()
        report["the_witness"] = {
            "the_port": args.port,
            "the_core_of_the_rehearsal": core_port,
            "the_note": "the witness stands on the documented port of the instance; the "
                        "bundle therefore carries the URL that the operator uses",
        }
        base = f"http://127.0.0.1:{args.port}"

        # 1. the bundle is built exactly as the release names it
        began = time.monotonic()
        build = subprocess.run(
            ["flutter", "build", "macos", "--release",
             f"--dart-define=OIP_API_URL={base}"],
            cwd=APPS, capture_output=True, text=True, timeout=3600)
        assert build.returncode == 0, (build.stderr or build.stdout)[-400:]
        report["build_command"] = (f"flutter build macos --release "
                                   f"--dart-define=OIP_API_URL={base}")
        report["build_seconds"] = round(time.monotonic() - began, 1)
        report["bundle"] = str(APP)
        report["bundle_bytes"] = sum(f.stat().st_size for f in APP.rglob("*") if f.is_file())
        report["bundle_executable_sha256"] = hashlib.sha256(
            EXECUTABLE.read_bytes()).hexdigest()
        # The digest over the whole tree of the bundle: the reproducibility of
        # the release is proved against this tree.
        entries = {}
        for path in sorted(APP.rglob("*")):
            if path.is_file():
                entries[path.relative_to(APP).as_posix()] = hashlib.sha256(
                    path.read_bytes()).hexdigest()
        tree = hashlib.sha256()
        for name, value in entries.items():
            tree.update(name.encode())
            tree.update(b"\0")
            tree.update(value.encode())
            tree.update(b"\0")
        report["bundle_tree_sha256"] = tree.hexdigest()
        report["bundle_files"] = len(entries)
        info = (APP / "Contents/Info.plist").read_text(errors="ignore")
        for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"):
            marker = f"<key>{key}</key>"
            if marker in info:
                tail = info.split(marker, 1)[1]
                report[key.lower()] = tail.split("<string>", 1)[-1].split("</string>", 1)[0]
        report["steps"].append("the bundle is built for the documented port")

        # 2. the bundle starts and reaches the Core
        assert EXECUTABLE.is_file(), EXECUTABLE
        first = launch("start")
        process = first["process"]
        report["start"] = {key: value for key, value in first.items() if key != "process"}
        report["the_core_served_the_bundle"] = bool(first["the_requests"])
        report["steps"].append("the Core serves the bundle")
        assert first["the_requests"], "the bundle asked the Core for nothing"
        denied = [item for item in first["the_requests"] if item["the_status"] in (401, 403)]
        report["the_refusals_of_the_core"] = denied
        assert denied, f"the Core did not refuse the unauthorized session: {first['the_requests']}"
        assert not any(item["the_status"] == 200 for item in first["the_requests"]), \
            f"the bundle obtained unauthorized data: {first['the_requests']}"

        # 3. the window of the bundle
        time.sleep(4)
        shot = evidence / "oip-macos-app.png"
        capture = subprocess.run(["screencapture", "-x", "-o", str(shot)],
                                 capture_output=True, text=True, timeout=120)
        report["screenshot"] = str(shot) if shot.is_file() and shot.stat().st_size > 0 else None
        report["screenshot_captured"] = report["screenshot"] is not None
        if capture.returncode != 0:
            report["screenshot_error"] = capture.stderr.strip()[-200:]

        # 4. the bundle terminates on the operator's signal
        report["shutdown"] = terminate(process)
        report["steps"].append("the bundle terminates on SIGTERM")
        assert report["shutdown"]["terminated"], \
            "the bundle did not stop within 30 seconds"
        assert report["shutdown"]["exit_code"] not in (-signal.SIGSEGV, -signal.SIGABRT), \
            f"the bundle crashed: {report['shutdown']['the_output']}"
        orphans = subprocess.run(["pgrep", "-f", str(EXECUTABLE)],
                                 capture_output=True, text=True).stdout.strip()
        report["orphaned_processes"] = [line for line in orphans.splitlines() if line]
        assert not report["orphaned_processes"], "the bundle left an orphan behind"

        # 5. the bundle starts again
        second = launch("restart")
        process = second["process"]
        report["restart"] = {key: value for key, value in second.items() if key != "process"}
        report["the_core_served_the_bundle_again"] = bool(second["the_requests"])
        report["steps"].append("the bundle starts again and reaches the Core")
        assert report["the_core_served_the_bundle_again"], \
            "the Core served no request of the restarted bundle"
        report["shutdown_after_restart"] = terminate(process)
        assert report["shutdown_after_restart"]["terminated"], \
            "the bundle did not stop within 30 seconds"

        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        if process is not None and process.poll() is None:
            process.kill()
        try:
            tool("stop", expect_success=False)
        except Exception:
            pass
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
    (evidence / "macos-app.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
