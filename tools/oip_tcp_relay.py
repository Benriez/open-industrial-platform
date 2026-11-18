#!/usr/bin/env python3
"""OIP byte-preserving TCP relay, bound to an explicit private interface.

Preserves HTTP Host/Origin, cookies, streaming and half closes. Each connection
has its own upstream socket; no shared SSH channels or authentication storage.
"""
import argparse
import socket
import socketserver
import threading


def keepalive(sock):
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
    for name, value in [('TCP_KEEPIDLE', 30), ('TCP_KEEPINTVL', 10), ('TCP_KEEPCNT', 3)]:
        option = getattr(socket, name, None)
        if option is not None:
            sock.setsockopt(socket.IPPROTO_TCP, option, value)


class Relay(socketserver.BaseRequestHandler):
    def handle(self):
        self.relay_to(self.server.target)

    def relay_to(self, target):
        try:
            upstream = socket.create_connection(target, timeout=5)
        except OSError:
            return
        upstream.settimeout(None)
        keepalive(upstream)
        keepalive(self.request)

        def pump(source, destination):
            try:
                while True:
                    data = source.recv(65536)
                    if not data:
                        break
                    destination.sendall(data)
            except OSError:
                # Wake the other direction on a broken connection.
                try:
                    source.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
            finally:
                try:
                    destination.shutdown(socket.SHUT_WR)
                except OSError:
                    pass

        worker = threading.Thread(target=pump, args=(self.request, upstream), daemon=True)
        worker.start()
        try:
            pump(upstream, self.request)
        finally:
            upstream.close()
            worker.join(timeout=2)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True
    request_queue_size = 128


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--listen-host', required=True)
    parser.add_argument('--listen-port', type=int, required=True)
    parser.add_argument('--target-host', required=True)
    parser.add_argument('--target-port', type=int, required=True)
    args = parser.parse_args()
    with Server((args.listen_host, args.listen_port), Relay) as server:
        server.target = (args.target_host, args.target_port)
        server.serve_forever(poll_interval=.5)


if __name__ == '__main__':
    main()
