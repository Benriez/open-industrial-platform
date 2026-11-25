#!/usr/bin/env python3
"""OIP byte-preserving TCP relay, bound to an explicit private interface.

Preserves HTTP Host/Origin, cookies, streaming and half closes. Each connection
has its own upstream socket; no shared SSH channels or authentication storage.
"""
import argparse
import collections
import selectors
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
        client = self.request
        try:
            # A connection without a request cannot consume an upstream socket.
            client.settimeout(self.server.request_start_timeout)
            first = client.recv(65536)
            if not first:
                return
            with socket.create_connection(target, timeout=5) as upstream:
                self.forward(client, upstream, first)
        except OSError:
            return

    def forward(self, client, upstream, first):
        for sock in (client, upstream):
            sock.settimeout(self.server.write_timeout)
            keepalive(sock)
        upstream.sendall(first)

        with selectors.DefaultSelector() as active:
            active.register(client, selectors.EVENT_READ, upstream)
            active.register(upstream, selectors.EVENT_READ, client)
            while active.get_map():
                readable = active.select(self.server.idle_timeout)
                if not readable:
                    return
                for entry, _ in readable:
                    data = entry.fileobj.recv(65536)
                    if data:
                        entry.data.sendall(data)
                    else:
                        active.unregister(entry.fileobj)
                        entry.data.shutdown(socket.SHUT_WR)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True
    request_queue_size = 128
    connection_limit = 64
    peer_limit = 12
    request_start_timeout = 10
    idle_timeout = 300
    write_timeout = 15

    def __init__(self, address, handler):
        self._admission = threading.Lock()
        self._connections = 0
        self._peers = collections.Counter()
        super().__init__(address, handler)

    def process_request(self, request, client_address):
        peer = client_address[0]
        with self._admission:
            allowed = (self._connections < self.connection_limit
                       and self._peers[peer] < self.peer_limit)
            if allowed:
                self._connections += 1
                self._peers[peer] += 1
        if not allowed:
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self._release(peer)
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self._release(client_address[0])

    def _release(self, peer):
        with self._admission:
            self._connections -= 1
            self._peers[peer] -= 1
            if not self._peers[peer]:
                del self._peers[peer]


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
