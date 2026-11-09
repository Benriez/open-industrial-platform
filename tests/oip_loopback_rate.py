#!/usr/bin/env python3
"""The rate of the loopback of this machine, and what it means for the first paint.

The performance baseline of the release measures a first paint of about 50
seconds. The record attributes it to the **transfer** of the delivery and not
to the application — the application is interactive in a quarter of a second
once the session exists. The operator is then asked to decide about the
delivery of the web release (a smaller delivery, a compressed asset or a local
cache).

That decision must not be taken on a number that is a property of the
**measurement environment** instead of the release. This rehearsal measures
the rate of the loopback of this machine and puts it next to the transferred
bytes of the baseline, so the first paint becomes interpretable:

  * the throughput of one connection of the loopback (a raw socket and an HTTP
    request);
  * the throughput of two connections in parallel — a limit that is shared
    would be a limit of the machine, a limit that grows with the connections
    is a limit of the path;
  * the throughput of a Unix socket and of a local read — the floor of the
    machine itself, without the network stack;
  * the transferred bytes of the performance baseline and the time they need
    at the measured rate.

Nothing of the rehearsal touches the release and nothing leaves the machine.

Usage:
  python3 tests/oip_loopback_rate.py [--evidence DIR]
"""
import argparse
import http.server
import json
import os
import pathlib
import socket
import socketserver
import subprocess
import tempfile
import threading
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
PAYLOAD = 3 * 1024 * 1024


def over_tcp(size=PAYLOAD):
    """The throughput of one connection of the loopback."""
    server = socket.socket()
    server.bind(("127.0.0.1", 0))
    server.listen(1)
    port = server.getsockname()[1]
    received = {"bytes": 0}

    def reader():
        connection, _ = server.accept()
        while True:
            chunk = connection.recv(65536)
            if not chunk:
                break
            received["bytes"] += len(chunk)
        connection.close()

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    client = socket.socket()
    client.connect(("127.0.0.1", port))
    block = b"x" * 65536
    began = time.monotonic()
    for _ in range(size // len(block)):
        client.sendall(block)
    client.shutdown(socket.SHUT_WR)
    thread.join(120)
    seconds = time.monotonic() - began
    client.close()
    server.close()
    return received["bytes"], seconds


def over_http(size=PAYLOAD):
    """The throughput of one HTTP request of the loopback."""
    payload = b"x" * size

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, *arguments):
            return

    server = socketserver.TCPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()
    began = time.monotonic()
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/probe", timeout=300) as answer:
        data = answer.read()
    seconds = time.monotonic() - began
    server.shutdown()
    server.server_close()
    return len(data), seconds


def over_unix_socket(size=PAYLOAD):
    """The throughput of a Unix socket: the same machine, without the TCP path."""
    directory = tempfile.mkdtemp(prefix="oip-loopback-")
    path = os.path.join(directory, "s")
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(1)
    received = {"bytes": 0}

    def reader():
        connection, _ = server.accept()
        while True:
            chunk = connection.recv(65536)
            if not chunk:
                break
            received["bytes"] += len(chunk)
        connection.close()

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.connect(path)
    block = b"x" * 65536
    began = time.monotonic()
    for _ in range(size // len(block)):
        client.sendall(block)
    client.shutdown(socket.SHUT_WR)
    thread.join(120)
    seconds = time.monotonic() - began
    client.close()
    server.close()
    os.unlink(path)
    os.rmdir(directory)
    return received["bytes"], seconds


def over_two_connections(size=PAYLOAD):
    """Two connections in parallel: does the limit grow with them?"""
    results = []
    threads = [threading.Thread(target=lambda: results.append(over_tcp(size)))
               for _ in range(2)]
    began = time.monotonic()
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(300)
    seconds = time.monotonic() - began
    total = sum(count for count, _ in results)
    return total, seconds


def the_baseline():
    """The transferred bytes of the performance baseline of the release."""
    path = ROOT / "docs/evidence/oip-performance/performance.json"
    if not path.is_file():
        return None
    payload = json.loads(path.read_text())
    runs = payload.get("runs", [])
    if not runs:
        return None
    bytes_ = [run.get("transferred_bytes") for run in runs if run.get("transferred_bytes")]
    paints = [run.get("first_paint_ms") for run in runs if run.get("first_paint_ms")]
    return {
        "the_runs": len(runs),
        "the_requests": runs[0].get("requests"),
        "the_transferred_bytes": bytes_,
        "the_first_paint_ms": paints,
        "the_bundle_bytes": runs[0].get("bundle_bytes"),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-loopback-rate"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-loopback-rate-v1", "steps": []}

    try:
        count, seconds = over_tcp()
        tcp = {"the_bytes": count, "the_seconds": round(seconds, 2),
               "the_kib_per_second": round(count / seconds / 1024, 1)}
        report["the_one_connection"] = tcp
        report["steps"].append("the rate of one connection of the loopback is measured")

        count, seconds = over_http()
        http = {"the_bytes": count, "the_seconds": round(seconds, 2),
                "the_kib_per_second": round(count / seconds / 1024, 1)}
        report["the_one_http_request"] = http

        count, seconds = over_two_connections()
        parallel = {"the_bytes": count, "the_seconds": round(seconds, 2),
                    "the_kib_per_second": round(count / seconds / 1024, 1)}
        report["the_two_connections"] = parallel
        report["the_limit_grows_with_the_connections"] = \
            parallel["the_kib_per_second"] > 1.5 * tcp["the_kib_per_second"]
        report["steps"].append("the limit of the path is measured")

        count, seconds = over_unix_socket()
        unix = {"the_bytes": count, "the_seconds": round(seconds, 3),
                "the_mib_per_second": round(count / seconds / 1024 / 1024, 1)}
        report["the_unix_socket"] = unix
        report["steps"].append("the rate of the machine itself is measured")

        baseline = the_baseline()
        report["the_baseline"] = baseline
        if baseline and baseline["the_transferred_bytes"]:
            transferred = max(baseline["the_transferred_bytes"])
            paint = max(baseline["the_first_paint_ms"])
            rate = tcp["the_kib_per_second"]
            report["the_interpretation"] = {
                "the_transferred_bytes": transferred,
                "the_measured_first_paint_ms": paint,
                "the_seconds_the_transfer_needs_at_the_measured_rate":
                    round(transferred / 1024 / rate, 1) if rate else None,
                "the_rate_of_the_machine_without_the_network_path":
                    unix["the_mib_per_second"],
                "the_note": "the first paint of the baseline is the transfer of the "
                            "delivery at the rate of the loopback of this machine. The "
                            "rate is a property of the path, not of the release: the "
                            "machine itself is far faster without the TCP path.",
            }
        report["status"] = "PASS"
    except Exception as error:  # noqa: BLE001 - the receipt names every failure
        report["status"] = "FAIL"
        report["error"] = f"{type(error).__name__}: {error}"

    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "loopback-rate.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "steps"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
