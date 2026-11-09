#!/usr/bin/env python3
"""The measurement of the delivery of the web release **on the operator's machine**.

The performance baseline of the release is measured on the machine of the
development loop, and its first paint is bound by the **transfer** of the
delivery. The rate of the loopback of that machine is not the rate of an
ordinary machine, so the number of the baseline must not be the basis of the
decision about the delivery.

This tool gives the operator the measurement **on their own machine**:

  * the **size of the delivery** — the web release that the Core serves, the
    bytes of the bundle and the whole tree;
  * the **rate of the path** — one connection of the loopback and two
    connections in parallel;
  * the **rate of the machine** — a Unix socket, without the TCP path;
  * the **time the delivery needs** at the measured rate and at the rate of
    the machine itself.

The tool reads the release and measures the machine. It writes nothing and
contacts nothing.

Usage:
  python3 tools/oip_measure_delivery.py [--web-dir DIR] [--json]
"""
import argparse
import json
import os
import pathlib
import socket
import tempfile
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
WEB = ROOT / "apps/flutter/build/web"
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


def over_two_connections(size=PAYLOAD):
    results = []
    threads = [threading.Thread(target=lambda: results.append(over_tcp(size)))
               for _ in range(2)]
    began = time.monotonic()
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(300)
    seconds = time.monotonic() - began
    return sum(count for count, _ in results), seconds


def over_unix_socket(size=PAYLOAD):
    """The throughput of the machine itself, without the TCP path."""
    directory = tempfile.mkdtemp(prefix="oip-delivery-")
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


def the_delivery(web_dir):
    """The size of the delivery that the Core serves."""
    if not web_dir.is_dir():
        return None
    files = []
    total = 0
    for path in sorted(web_dir.rglob("*")):
        if path.is_file():
            size = path.stat().st_size
            total += size
            files.append({"the_path": path.relative_to(web_dir).as_posix(),
                          "the_bytes": size})
    main = web_dir / "main.dart.js"
    return {
        "the_directory": str(web_dir),
        "the_files": len(files),
        "the_bytes": total,
        "the_mib": round(total / 1024 / 1024, 1),
        "the_main_bundle_bytes": main.stat().st_size if main.is_file() else None,
        "the_largest": sorted(files, key=lambda item: -item["the_bytes"])[:5],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--web-dir", default=str(WEB))
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    web_dir = pathlib.Path(args.web_dir)

    report = {"schema": "oip-delivery-measurement-v1"}
    report["the_delivery"] = the_delivery(web_dir)

    count, seconds = over_tcp()
    report["the_one_connection"] = {
        "the_bytes": count, "the_seconds": round(seconds, 2),
        "the_kib_per_second": round(count / seconds / 1024, 1)}
    count, seconds = over_two_connections()
    report["the_two_connections"] = {
        "the_bytes": count, "the_seconds": round(seconds, 2),
        "the_kib_per_second": round(count / seconds / 1024, 1)}
    count, seconds = over_unix_socket()
    report["the_machine_without_the_tcp_path"] = {
        "the_bytes": count, "the_seconds": round(seconds, 3),
        "the_mib_per_second": round(count / seconds / 1024 / 1024, 1)}

    delivery = report["the_delivery"]
    if delivery and delivery["the_bytes"]:
        rate = report["the_one_connection"]["the_kib_per_second"]
        machine = report["the_machine_without_the_tcp_path"]["the_mib_per_second"]
        report["the_times"] = {
            "the_seconds_at_the_rate_of_the_path":
                round(delivery["the_bytes"] / 1024 / rate, 1) if rate else None,
            "the_seconds_at_the_rate_of_the_machine":
                round(delivery["the_bytes"] / 1024 / 1024 / machine, 2) if machine else None,
            "the_note": "the first paint of the baseline of the release was measured on "
                        "the machine of the development loop; these are the numbers of "
                        "this machine",
        }
    report["the_advice"] = (
        "the delivery is the size of the web release; the first paint is bound by "
        "the transfer of it over the loopback of this machine. Compare the seconds "
        "at the rate of the path with the seconds at the rate of the machine: a "
        "large difference means the path of this machine is the limit, not the "
        "delivery. The decision about a smaller delivery, a compressed asset or a "
        "local cache belongs to the operator and is named in "
        "docs/OIP_RELEASE_LEDGER.md.")

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
