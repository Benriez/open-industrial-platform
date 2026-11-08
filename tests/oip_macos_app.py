#!/usr/bin/env python3
"""The macOS application bundle of the Flutter client.

The bundle is built reproducibly and proved to:

  * start and open its window;
  * reach the Core and demand the operator session, exactly as the approved
    design requires for an unauthorized session — and to obtain no
    unauthorized data in the process;
  * terminate on the operator's signal without leaving an orphan behind;
  * start again afterwards (the restart of the application bundle).

The approved shell itself is proven by the canonical gate on the same Dart
code; this rehearsal proves the native bundle of that code.

The Core does not log the routes of its authorized reads, so a logging proxy
stands in front of it and the receipt names the exact requests of the bundle.

Usage:
  python3 tests/oip_macos_app.py [--evidence DIR]
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
import socketserver
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "oip_ops.py"
APP = ROOT / "apps/flutter/build/macos/Build/Products/Release/oip_dashboard.app"
EXECUTABLE = APP / "Contents/MacOS" / "oip_dashboard"


class _LoggingProxy(http.server.BaseHTTPRequestHandler):
    """The proxy in front of the Core.

    It records the requests of the native bundle with the status the Core
    answered, so the receipt can name them.
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
            _LoggingProxy.upstream + self.path, data=body, method=method)
        for key in ("Content-Type", "Origin", "x-oip-csrf", "Cookie"):
            value = self.headers.get(key)
            if value:
                request.add_header(key, value)
        try:
            with urllib.request.urlopen(request, timeout=60) as answer:
                payload = answer.read()
                _LoggingProxy.routes.append(("GET " if method == "GET" else "POST ",
                                             self.path, answer.status))
                self.send_response(answer.status)
                for key in ("Content-Type", "Set-Cookie"):
                    value = answer.headers.get(key)
                    if value:
                        self.send_header(key, value)
                self.end_headers()
                self.wfile.write(payload)
        except urllib.error.HTTPError as error:
            payload = error.read()
            _LoggingProxy.routes.append(("POST " if method == "POST" else "GET ",
                                         self.path, error.code))
            self.send_response(error.code)
            for key in ("Content-Type",):
                value = error.headers.get(key)
                if value:
                    self.send_header(key, value)
            self.end_headers()
            self.wfile.write(payload)
        except Exception as error:  # the receipt names the failure
            _LoggingProxy.routes.append(("POST " if method == "POST" else "GET ",
                                         self.path, 502))
            self.send_response(502)
            self.end_headers()
            self.wfile.write(str(error).encode())

    def log_message(self, *arguments):
        return


def free_port():
    import socket
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def tool(state, config, ipc, binary, *arguments, expect_success=True):
    result = subprocess.run([sys.executable, str(TOOL), "--state-dir", str(state),
                             "--config", str(config), "--ipc-config", str(ipc),
                             "--binary", str(binary), *arguments],
                            capture_output=True, text=True, timeout=1800)
    if expect_success and result.returncode != 0:
        raise AssertionError(f"{arguments[0]} failed: "
                             f"{result.stderr.strip() or result.stdout.strip()}")
    return result


def display_bounds():
    """The visible frames of the machine.

    The window of the bundle has to touch one of them, otherwise the
    operator launches the application and sees nothing.
    """
    import ctypes
    import Quartz
    # The display identifiers are only filled when the array is supplied.
    identifiers = (ctypes.c_uint32 * 16)()
    result = Quartz.CGGetActiveDisplayList(16, identifiers, None)
    frames = []
    for identifier in list(result[1]):
        bounds = Quartz.CGDisplayBounds(identifier)
        frames.append({"x": bounds.origin.x, "y": bounds.origin.y,
                        "width": bounds.size.width, "height": bounds.size.height})
    return frames


def on_screen(window, frames):
    for frame in frames:
        if (window["x"] < frame["x"] + frame["width"]
                and window["x"] + window["width"] > frame["x"]
                and window["y"] < frame["y"] + frame["height"]
                and window["y"] + window["height"] > frame["y"]):
            return True
    return False


def capture_window(owner, path):
    """The window of the bundle, and nothing else.

    A capture of the whole desktop would carry foreign windows into the
    evidence. The window of the bundle itself is captured with its own
    window number.
    """
    import Quartz
    options = (Quartz.kCGWindowListOptionOnScreenOnly
               | Quartz.kCGWindowListExcludeDesktopElements)
    windows = Quartz.CGWindowListCopyWindowInfo(options, Quartz.kCGNullWindowID)
    for window in windows:
        if window.get("kCGWindowOwnerName") != owner:
            continue
        number = window.get("kCGWindowNumber")
        bounds = window.get("kCGWindowBounds") or {}
        capture = subprocess.run(["screencapture", "-x", "-o", "-l", str(number), str(path)],
                                 capture_output=True, text=True, timeout=120)
        if capture.returncode != 0:
            return None, {"error": capture.stderr.strip()[-200:]}
        if not path.is_file() or path.stat().st_size < 4096:
            return None, {"error": "the capture of the window is empty"}
        rectangle = {"x": bounds.get("X"), "y": bounds.get("Y"),
                      "width": bounds.get("Width"), "height": bounds.get("Height")}
        frames = display_bounds()
        return {"window_id": number,
                "owner": window.get("kCGWindowOwnerName"),
                "title": window.get("kCGWindowName"),
                "bounds": rectangle,
                "displays": frames,
                "on_screen": on_screen(rectangle, frames),
                "bytes": path.stat().st_size}, None
    return None, {"error": f"no window of {owner} is on screen"}


def launch(label, log_path, deadline_seconds=300):
    """Start the bundle and wait until it asks the Core for something.

    The receipt names the requests, the statuses and the time the bundle
    needed for its first request.
    """
    _LoggingProxy.routes = []
    started = time.monotonic()
    # The bundle writes its own log: the receipt keeps it (the logging of the
    # application is part of the gate of the local operations).
    handle = log_path.open("ab")
    process = subprocess.Popen([str(EXECUTABLE)],
                               stdout=handle, stderr=subprocess.STDOUT, text=True)
    handle.close()
    first_request = None
    deadline = time.monotonic() + deadline_seconds
    while time.monotonic() < deadline:
        if _LoggingProxy.routes:
            first_request = time.monotonic() - started
            break
        if process.poll() is not None:
            break
        time.sleep(0.25)
    routes = list(_LoggingProxy.routes)
    placement = []
    if log_path.is_file():
        for line in log_path.read_text(errors="ignore").splitlines():
            if line.startswith("OIP-WINDOW"):
                placement.append(line[len("OIP-WINDOW "):])
    return {
        "log": str(log_path),
        "window_placement": placement,
        "label": label,
        "first_request_seconds": round(first_request, 1) if first_request else None,
        "requests": [{"method": method.strip(), "path": path, "status": status}
                     for method, path, status in routes],
        "request_count": len(routes),
        "api_successes": sum(1 for _, path, status in routes
                             if path.startswith("/api/") and 200 <= status < 300),
        "answer_statuses": sorted({status for _, _, status in routes}),
    }, process


def terminate(process, log_path):
    """Stop the bundle with the operator's signal."""
    process.send_signal(signal.SIGTERM)
    began = time.monotonic()
    try:
        process.communicate(timeout=30)
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate()
        return {"signal": "SIGTERM", "terminated": False,
                "seconds": round(time.monotonic() - began, 1),
                "exit_code": process.returncode}
    output = ""
    if log_path.is_file():
        output = log_path.read_text(errors="ignore")
    return {"signal": "SIGTERM", "terminated": True,
            "seconds": round(time.monotonic() - began, 1),
            "exit_code": process.returncode, "log_tail": output[-1200:]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-macos-app"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-macos-app-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-macos-")).resolve()
    work.chmod(0o700)
    process = None
    proxy = None
    try:
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        plan["sources"] = [item for item in plan["sources"]
                           if item["source_id"] == "source-a"]
        plan["bindings"] = [item for item in plan["bindings"]
                            if item["scope"]["kind"] != "source"]
        plan["roles"].append({
            "id": "inventory-admin", "name": "Explicit scoped operator",
            "permissions": ["inventory_manage", "devices_read", "telemetry_read"]})
        plan["bindings"].append({
            "principal_id": "reader-org-a", "role_id": "inventory-admin",
            "scope": {"kind": "organization", "id": "org-a"}})
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        port = free_port()
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": port,
            "sources": [{"id": "source-a", "name": "Local simulation a",
                          "endpoint": "opc.tcp://127.0.0.1:4840", "namespace": 2}],
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
        tool(state, work / "core.json", work / "ipc.json", args.binary,
             "provision-plan", "--plan", str(work / "plan.json"))
        tool(state, work / "core.json", work / "ipc.json", args.binary, "start")
        time.sleep(2)
        report["steps"].append("the Core serves the instance")

        # 1. the bundle is built reproducibly. The logging proxy stands in
        #    front of the Core, so the receipt names the requests of the
        #    native bundle.
        proxy_port = free_port()
        _LoggingProxy.upstream = f"http://127.0.0.1:{port}"
        proxy = socketserver.ThreadingTCPServer(("127.0.0.1", proxy_port),
                                                _LoggingProxy)
        thread = __import__("threading").Thread(target=proxy.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{proxy_port}"
        began = time.monotonic()
        build = subprocess.run(
            ["flutter", "build", "macos", "--release",
             f"--dart-define=OIP_API_URL={base}"],
            cwd=ROOT / "apps/flutter", capture_output=True, text=True, timeout=3600)
        assert build.returncode == 0, build.stderr[-400:]
        report["build_command"] = f"flutter build macos --release --dart-define=OIP_API_URL={base}"
        report["build_seconds"] = round(time.monotonic() - began, 1)
        report["bundle"] = str(APP)
        report["bundle_bytes"] = sum(f.stat().st_size for f in APP.rglob("*") if f.is_file())
        report["bundle_executable_sha256"] = hashlib.sha256(
            EXECUTABLE.read_bytes()).hexdigest()
        info = (APP / "Contents/Info.plist").read_text(errors="ignore")
        for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"):
            marker = f"<key>{key}</key>"
            if marker in info:
                tail = info.split(marker, 1)[1]
                value = tail.split("<string>", 1)[-1].split("</string>", 1)[0]
                report[key.lower()] = value
        report["steps"].append("the macOS bundle is built")

        # 2. the bundle starts and reaches the Core
        assert EXECUTABLE.is_file(), EXECUTABLE
        first, process = launch("start", evidence / "oip-macos-app.log")
        report["start"] = first
        report["steps"].append("the bundle asks the Core for the session")
        assert first["first_request_seconds"] is not None, \
            "the bundle did not reach the Core within 300 seconds"
        # The bundle asks the Core for the authorized projection of the
        # principal. Without a session the Core refuses it, and the bundle
        # demands the operator session instead of inventing data.
        assert any("/api/v2/organizations" in item["path"] for item in first["requests"]), \
            "the bundle did not ask the Core for the authorized projection"
        assert 403 in first["answer_statuses"], \
            f"the Core did not refuse the unauthorized read: {first['answer_statuses']}"
        assert first["api_successes"] == 0, \
            f"the bundle obtained unauthorized data: {first['requests']}"

        # 3. the window of the bundle — and only the window of the bundle
        time.sleep(6)
        shot = evidence / "oip-macos-app.png"
        window, error = capture_window("oip_dashboard", shot)
        report["screenshot"] = str(shot) if window else None
        report["screenshot_captured"] = window is not None
        if window:
            report["window"] = window
            report["window_placement_of_the_bundle"] = first["window_placement"]
            report["steps"].append("the window of the bundle is visible on a screen")
            assert window["on_screen"], \
                f"the window of the bundle is not on a visible screen: {window}"
        else:
            report["screenshot_error"] = error

        # 4. the bundle terminates on the operator's signal
        report["shutdown"] = terminate(process, evidence / "oip-macos-app.log")
        report["steps"].append("the bundle terminates on SIGTERM")
        assert report["shutdown"]["terminated"], \
            "the bundle did not stop within 30 seconds"
        assert report["shutdown"]["exit_code"] not in (-signal.SIGSEGV, -signal.SIGABRT), \
            f"the bundle crashed: {report['shutdown']['output']}"
        orphans = subprocess.run(["pgrep", "-f", str(EXECUTABLE)],
                                 capture_output=True, text=True).stdout.strip()
        report["orphaned_processes"] = [line for line in orphans.splitlines() if line]
        assert not report["orphaned_processes"], "the bundle left an orphan behind"

        # 5. the bundle starts again (the restart of the application bundle)
        second, process = launch("restart", evidence / "oip-macos-app.log")
        report["restart"] = second
        report["steps"].append("the bundle starts again and reaches the Core")
        assert second["first_request_seconds"] is not None, \
            "the bundle did not reach the Core again"
        assert second["api_successes"] == 0, \
            f"the bundle obtained unauthorized data: {second['requests']}"
        report["shutdown_after_restart"] = terminate(
            process, evidence / "oip-macos-app.log")
        assert report["shutdown_after_restart"]["terminated"], \
            "the bundle did not stop within 30 seconds"
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        if process is not None and process.poll() is None:
            process.kill()
        if proxy is not None:
            try:
                proxy.shutdown()
            except Exception:
                pass
        try:
            tool(state, work / "core.json", work / "ipc.json", args.binary, "stop",
                 expect_success=False)
        except Exception:
            pass
        shutil.rmtree(work, ignore_errors=True)

    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "macos-app.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
