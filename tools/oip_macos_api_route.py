#!/usr/bin/env python3
"""Keep the OIP loopback API on a preferred SSH route with a direct fallback."""
import argparse
import http.client
import signal
import socket
import subprocess
import threading

from oip_tcp_relay import Relay, Server


def start_forward(alias, upstream, local_host):
    with socket.socket() as reservation:
        reservation.bind((local_host, 0))
        destination = reservation.getsockname()
    specification = f"{local_host}:{destination[1]}:{upstream[0]}:{upstream[1]}"
    process = subprocess.Popen([
        "/usr/bin/ssh", "-S", "none", "-N", "-T",
        "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
        "-o", "ExitOnForwardFailure=yes", "-o", "ConnectTimeout=5",
        "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=3",
        "-L", specification, "--", alias,
    ])
    return process, destination


def api_replies(destination):
    client = http.client.HTTPConnection(*destination, timeout=3)
    try:
        client.request("GET", "/api/v2/browser/session")
        response = client.getresponse()
        return response.status == 200
    except (OSError, http.client.HTTPException):
        return False
    finally:
        client.close()


def supervise(server, stop, alias, direct):
    process = None
    preferred = None
    good = bad = 0
    try:
        while not stop.is_set():
            if process is None or process.poll() is not None:
                server.target = direct
                process, preferred = start_forward(alias, direct, server.server_address[0])
                good = bad = 0
                if stop.wait(1):
                    break
            if api_replies(preferred):
                good += 1
                bad = 0
                if good >= 2 and server.target != preferred:
                    server.target = preferred
                    print("OIP API using the preferred SSH route", flush=True)
            else:
                good = 0
                bad += 1
                if bad >= 2 and server.target != direct:
                    server.target = direct
                    print("OIP API using the direct fallback", flush=True)
            stop.wait(4)
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--listen-port", type=int, required=True)
    parser.add_argument("--target-host", required=True)
    parser.add_argument("--target-port", type=int, required=True)
    parser.add_argument("--ssh-alias", required=True)
    args = parser.parse_args()

    stop = threading.Event()
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    direct = (args.target_host, args.target_port)
    with Server(("127.0.0.1", args.listen_port), Relay) as server:
        server.target = direct
        server.timeout = 0.5
        monitor = threading.Thread(target=supervise, args=(server, stop, args.ssh_alias, direct))
        monitor.start()
        try:
            while not stop.is_set():
                server.handle_request()
        finally:
            stop.set()
            monitor.join()


if __name__ == "__main__":
    main()
