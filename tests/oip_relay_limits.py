#!/usr/bin/env python3
"""Check private relay admission, timeouts and streaming on local fixtures."""
import contextlib
import http.client
import http.server
import pathlib
import socket
import sys
import threading
import time
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "tools"))
from oip_tcp_relay import Relay, Server


class CoreFixture(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path == "/api/v2/stream":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Connection", "close")
            self.end_headers()
            for i in range(3):
                self.wfile.write(f"event: snapshot\ndata: {i}\n\n".encode())
                self.wfile.flush()
                time.sleep(0.08)
            self.close_connection = True
        else:
            body = b'{"authenticated":true}'
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    do_POST = do_GET

    def log_message(self, *_):
        pass


class TestRelay(Server):
    connection_limit = 3
    peer_limit = 1
    request_start_timeout = 0.8
    idle_timeout = 0.5
    write_timeout = 0.3

    def __init__(self, *args):
        self.peer_by_port = {}
        super().__init__(*args)

    def process_request(self, request, client_address):
        # macOS only binds one loopback address without changing its network
        # configuration. Map test sockets to separate peers at admission.
        ip, port = client_address
        super().process_request(request, (self.peer_by_port.get(port, ip), port))


@contextlib.contextmanager
def serving(server):
    with server:
        worker = threading.Thread(target=server.serve_forever,
                                  kwargs={"poll_interval": 0.02}, daemon=True)
        worker.start()
        try:
            yield server
        finally:
            server.shutdown()
            worker.join()


class RelayLimitsTest(unittest.TestCase):
    def test_ordinary_login_and_stream_have_room_while_one_peer_is_full(self):
        with serving(http.server.ThreadingHTTPServer(("127.0.0.1", 0), CoreFixture)) as core:
            with serving(TestRelay(("127.0.0.1", 0), Relay)) as relay:
                relay.target = core.server_address
                with contextlib.ExitStack() as cleanup:
                    def connect(peer):
                        client = cleanup.enter_context(socket.socket())
                        client.bind(("127.0.0.1", 0))
                        relay.peer_by_port[client.getsockname()[1]] = peer
                        client.settimeout(2)
                        client.connect(relay.server_address)
                        return client

                    waiting = connect("peer-a")
                    self.wait_for_connections(relay, 1)
                    extra = connect("peer-a")
                    self.assert_closed(extra)

                    stream = http.client.HTTPConnection(*relay.server_address, timeout=2)
                    cleanup.callback(stream.close)
                    stream.request("GET", "/api/v2/stream")
                    response = stream.getresponse()
                    self.assertEqual(response.status, 200)
                    self.assertEqual(response.readline(), b"event: snapshot\n")

                    login = connect("peer-b")
                    login.sendall(b"POST /api/v2/browser/login HTTP/1.1\r\n"
                                  b"Host: core\r\nContent-Length: 0\r\n\r\n")
                    answer = http.client.HTTPResponse(login)
                    answer.begin()
                    self.assertEqual(answer.status, 200)
                    self.assertEqual(answer.read(), b'{"authenticated":true}')
                    self.wait_for_connections(relay, 3)

                    self.assert_closed(connect("peer-c"))
                    self.assertIn(b"data: 2", response.read())
                    self.assert_closed(waiting)
                    self.assert_closed(login)  # idle keep-alive is reaped
                    self.wait_for_connections(relay, 0)

                    retry = connect("peer-a")
                    retry.sendall(b"GET / HTTP/1.1\r\nHost: core\r\nConnection: close\r\n\r\n")
                    retry.shutdown(socket.SHUT_WR)
                    answer = http.client.HTTPResponse(retry)
                    answer.begin()
                    self.assertEqual(answer.read(), b'{"authenticated":true}')

    def wait_for_connections(self, server, count):
        until = time.monotonic() + 2
        while time.monotonic() < until:
            with server._admission:
                if server._connections == count:
                    return
            time.sleep(0.01)
        self.fail(f"relay did not settle at {count} admitted clients")

    def assert_closed(self, connection):
        try:
            self.assertEqual(connection.recv(1), b"")
        except ConnectionResetError:
            pass


if __name__ == "__main__":
    unittest.main()
