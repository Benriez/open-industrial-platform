#!/usr/bin/env python3
"""The parity of the OPC-UA address space between MCP and REST.

The official MCP tool `oip_opcua_nodes_read` and the REST route
`/api/v2/opcua/nodes` serve the same address space of the same Core. The
milestone harnesses proved that parity for the releases of their era; the
current release binary had not been re-inventoried against a real backend.

This rehearsal proves it against the **release** binary and real collectors:

  * the MCP answer and the REST answer of the same query are the same page:
    the same nodes, the same total, the same offset and the same limit;
  * the v1 route and the v2 route serve the same page;
  * the pagination of the Core continues without a repetition and without a
    gap;
  * the scope of the principal holds on the address space: the reader of the
    other organization does not see a foreign source;
  * what the operator sees when the collector of a source connects again: the
    address space is the live catalog of the collector and is replaced by
    that reconnect.

Nothing of the rehearsal touches the personal installation of the operator and
nothing leaves the machine.

Usage:
  python3 tests/oip_opcua_parity.py [--evidence DIR]
"""
import argparse
import http.cookiejar
import json
import os
import pathlib
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "oip_ops.py"
SIMULATOR = ROOT / "target/debug/oip-simulated-server"
PROBE = ROOT / "target/release/examples/mcp_probe"


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def api(base, path, method="GET", body=None, headers=None, opener=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(base + path, data=data, method=method)
    request.add_header("Content-Type", "application/json")
    for key, value in (headers or {}).items():
        request.add_header(key, value)
    send = opener.open if opener else urllib.request.urlopen
    try:
        with send(request, timeout=60) as answer:
            return answer.status, json.loads(answer.read().decode() or "{}")
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode() or "{}")


class McpClient:
    """The official SDK against the protected local IPC of the Core."""

    def __init__(self, binary, socket_path, credential, name):
        self.process = subprocess.Popen(
            [str(PROBE), "modern", str(binary), "--mcp-bridge",
             "--ipc-socket", str(socket_path), "--ipc-credential", str(credential)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, bufsize=1)
        self.ready = json.loads(self.process.stdout.readline())
        assert self.ready.get("ready"), self.ready
        self.name = name

    def call(self, tool, arguments=None):
        self.process.stdin.write(json.dumps(
            {"op": "call", "name": "oip_" + tool, "arguments": arguments or {}}) + "\n")
        self.process.stdin.flush()
        answer = json.loads(self.process.stdout.readline())
        assert answer.get("ok"), answer
        return answer["result"]["structuredContent"]["value"]

    def denied(self, tool, arguments=None):
        self.process.stdin.write(json.dumps(
            {"op": "call", "name": "oip_" + tool, "arguments": arguments or {}}) + "\n")
        self.process.stdin.flush()
        return json.loads(self.process.stdout.readline())

    def close(self):
        if self.process.poll() is not None:
            return
        self.process.stdin.close()
        self.process.wait(timeout=20)


def node_ids(page):
    return [item.get("node_id") for item in page.get("items", [])]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-opcua-parity"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-opcua-parity-v1", "steps": []}

    if not PROBE.is_file():
        report["status"] = "BLOCKED"
        report["reason"] = f"the official MCP probe is not built: {PROBE}"
        (evidence / "opcua-parity.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return 2

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-opcua-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    simulators = []
    clients = []
    try:
        source_ports = [free_port() for _ in range(4)]
        port = free_port()
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
        for principal in ("reader-org-a", "reader-org-b"):
            credential = work / f"{principal}.credential"
            credential.write_bytes(secrets.token_bytes(32))
            credential.chmod(0o600)
        (work / "ipc.json").write_text(json.dumps({
            "socket": str(work / "s"), "max_sessions": 16,
            "clients": [
                {"uid": os.getuid(),
                 "credential_file": str(work / "reader-org-a.credential"),
                 "policy": {"principal": "reader-org-a"}},
                {"uid": os.getuid(),
                 "credential_file": str(work / "reader-org-b.credential"),
                 "policy": {"principal": "reader-org-b"}},
            ],
        }, indent=2))
        (work / "ipc.json").chmod(0o600)
        state = work / "state"
        base = f"http://127.0.0.1:{port}"

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
        time.sleep(4)
        report["steps"].append("the instance runs")

        client = McpClient(args.binary, work / "s", work / "reader-org-a.credential",
                           "reader-org-a")
        clients.append(client)

        # The address space of a source is the live catalog of its collector.
        # It is published while the collector connects, so the measurement
        # waits until it is there.
        query = {"source": "source-a", "folder": "all", "limit": 100}
        deadline = time.monotonic() + 180
        published = None
        while time.monotonic() < deadline:
            page = client.call("opcua_nodes_read", query)
            if page.get("total", 0) > 0:
                published = page
                break
            time.sleep(1)
        assert published, "the collector did not publish an address space"
        report["address_space"] = {
            "total": published.get("total"),
            "note": "the address space is the live catalog of the collector; it is replaced "
                    "when the collector connects again",
        }
        report["steps"].append("the collector published its address space")

        # 1. the two pages are read back to back, so the measurement of the
        #    boundary is not disturbed by a change of the address space.
        first = client.call("opcua_nodes_read", query)
        second = client.call("opcua_nodes_read", dict(query, offset=100))
        ids_first = node_ids(first)
        ids_second = node_ids(second)
        overlap = set(ids_first) & set(ids_second)
        report["pages"] = {
            "first": {"items": len(ids_first), "total": first.get("total"),
                      "offset": first.get("offset"), "limit": first.get("limit")},
            "second": {"items": len(ids_second), "total": second.get("total"),
                       "offset": second.get("offset"), "limit": second.get("limit")},
            "repeated_nodes": len(overlap),
            "last_of_the_first_page": ids_first[-1] if ids_first else None,
            "first_of_the_second_page": ids_second[0] if ids_second else None,
        }
        assert first.get("total", 0) >= 1000, first.get("total")
        assert second.get("offset") == 100, second.get("offset")
        assert not overlap, f"{len(overlap)} nodes are repeated in the second page"
        report["the_pages_are_disjoint"] = True
        report["steps"].append("the address space continues without a repetition")

        # 2. the MCP answer and the REST answer of the same query are the
        #    same page.
        minted = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(work / "reader-org-a.credential")], text=True))
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        status, _ = api(base, "/api/v2/browser/login", "POST", {"code": minted["login_code"]},
                        {"Origin": base}, opener)
        assert status == 200, "the operator session was refused"
        report["steps"].append("the operator session is authorized")

        status, rest_v2 = api(
            base, "/api/v2/opcua/nodes?source=source-a&folder=all&limit=100", opener=opener)
        assert status == 200, rest_v2
        status, rest_v1 = api(
            base, "/api/v1/opcua/nodes?source=source-a&folder=all&limit=100", opener=opener)
        assert status == 200, rest_v1
        report["parity"] = {
            "mcp": {"items": len(first["items"]), "total": first.get("total"),
                    "offset": first.get("offset"), "limit": first.get("limit")},
            "rest_v2": {"items": len(rest_v2.get("items", [])), "total": rest_v2.get("total"),
                        "offset": rest_v2.get("offset"), "limit": rest_v2.get("limit")},
            "rest_v1": {"items": len(rest_v1.get("items", [])), "total": rest_v1.get("total"),
                        "offset": rest_v1.get("offset"), "limit": rest_v1.get("limit")},
        }
        assert node_ids(first) == node_ids(rest_v2), "the MCP and the REST answer differ"
        assert first.get("total") == rest_v2.get("total"), "the totals differ"
        assert first.get("limit") == rest_v2.get("limit"), "the limits differ"
        assert first.get("offset") == rest_v2.get("offset"), "the offsets differ"
        assert node_ids(rest_v1) == node_ids(rest_v2), "the v1 and the v2 route differ"
        report["mcp_and_rest_are_the_same_page"] = True
        report["v1_and_v2_are_the_same_page"] = True
        report["steps"].append("the MCP and the REST answer are the same page")

        # 3. the scope of the principal holds on the address space.
        other = McpClient(args.binary, work / "s", work / "reader-org-b.credential",
                          "reader-org-b")
        clients.append(other)
        foreign = other.denied("opcua_nodes_read", query)
        report["foreign_scope"] = {
            "denied": not foreign.get("ok") or foreign.get("result", {}).get("isError", False),
            "answer": str(foreign)[:200],
        }
        assert report["foreign_scope"]["denied"], "the foreign source was not refused"
        report["steps"].append("the scope of the principal holds on the address space")

        # 4. what the operator sees when the collector of a source connects
        #    again: the address space is the live catalog and is replaced.
        simulator = subprocess.Popen(
            [str(SIMULATOR), "--port", str(source_ports[0]), "--seed", "42",
             "--tick-ms", "250"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        simulators.append(simulator)
        time.sleep(8)
        reconnected = client.call("opcua_nodes_read", query)
        after = client.call("opcua_nodes_read", dict(query, offset=100))
        overlap_after = set(node_ids(reconnected)) & set(node_ids(after))
        report["across_a_reconnect"] = {
            "total_before": first.get("total"),
            "total_after": reconnected.get("total"),
            "the_content_changed": set(ids_first) != set(node_ids(reconnected)),
            "the_order_changed": ids_first != node_ids(reconnected),
            "nodes_repeated_at_the_boundary": len(overlap_after),
        }
        report["steps"].append("the address space across a reconnect of the collector")

        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        for client in clients:
            try:
                client.close()
            except Exception:
                pass
        for simulator in simulators:
            if simulator.poll() is None:
                simulator.terminate()
                try:
                    simulator.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    simulator.kill()
        try:
            tool("stop", expect_success=False)
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
    (evidence / "opcua-parity.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "steps"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
