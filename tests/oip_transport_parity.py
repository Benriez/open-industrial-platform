#!/usr/bin/env python3
"""The parity of the three transports of the current release (G2).

The gate G2 names the parity of REST, SSE and MCP. The milestone harnesses
proved it for the releases of their era; the current release binary had not
been re-inventoried.

This rehearsal proves it against the **release** binary and real collectors:
the same authorized projection of the same principal is delivered by

  * the REST route `/api/v2/snapshot`,
  * the SSE stream `/api/v2/stream`,
  * the MCP resource `oip://v2/snapshot/current`,

and the transports refuse what they must refuse: an unauthorized session gets
nothing, and the projection of a principal contains nothing of the other
organization.

Usage:
  python3 tests/oip_transport_parity.py [--evidence DIR]
"""
import argparse
import http.cookiejar
import hashlib
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


class McpClient:
    """The official SDK against the protected local IPC of the Core."""

    def __init__(self, binary, socket_path, credential):
        self.process = subprocess.Popen(
            [str(PROBE), "modern", str(binary), "--mcp-bridge",
             "--ipc-socket", str(socket_path), "--ipc-credential", str(credential)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, bufsize=1)
        self.ready = json.loads(self.process.stdout.readline())
        assert self.ready.get("ready"), self.ready

    def resource(self, uri):
        self.process.stdin.write(json.dumps({"op": "resource", "uri": uri}) + "\n")
        self.process.stdin.flush()
        answer = json.loads(self.process.stdout.readline())
        assert answer.get("ok"), answer
        return json.loads(answer["result"]["contents"][0]["text"])["value"]

    def close(self):
        if self.process.poll() is not None:
            return
        self.process.stdin.close()
        self.process.wait(timeout=20)


def read_sse(base, path, opener=None, seconds=25):
    """The first event of an SSE stream."""
    request = urllib.request.Request(base + path)
    try:
        stream = (opener.open(request, timeout=seconds) if opener
                  else urllib.request.urlopen(request, timeout=seconds))
    except urllib.error.HTTPError as error:
        # The refusal of the transport is a measured fact, not an error of
        # the rehearsal.
        return None, None, error.code
    try:
        deadline = time.monotonic() + seconds
        buffer = ""
        while time.monotonic() < deadline:
            chunk = stream.read(4096)
            if not chunk:
                break
            buffer += chunk.decode("utf-8", "ignore")
            if "\n\n" in buffer:
                break
    finally:
        stream.close()
    # Only the first event of the stream is compared; the stream continues
    # with further updates.
    buffer = buffer.split("\n\n", 1)[0]
    event = None
    data = []
    for line in buffer.splitlines():
        if line.startswith("event:"):
            event = line.split(":", 1)[1].strip()
        elif line.startswith("data:"):
            data.append(line.split(":", 1)[1].strip())
    if not data:
        return event, None, 200
    payload = "\n".join(data)
    try:
        return event, json.loads(payload), 200
    except json.JSONDecodeError:
        return event, payload, 200


def projection(snapshot):
    """The comparable part of a snapshot."""
    if not isinstance(snapshot, dict):
        return None
    return {
        "revision": (snapshot.get("core") or {}).get("revision"),
        "run_id": (snapshot.get("core") or {}).get("run_id"),
        "sources": sorted(item.get("id") for item in snapshot.get("sources", [])
                          if isinstance(item, dict)),
        "devices": sorted(item.get("id") for item in snapshot.get("devices", [])
                          if isinstance(item, dict)),
        "organizations": sorted(item.get("id") for item in snapshot.get("organizations", [])
                                if isinstance(item, dict)),
    }



def the_digest_of_the_binary(path):
    """The digest of the binary that the rehearsal drives.

    A receipt that claims to measure the **release** Core must name the
    binary it measured: the path alone is an inference, the digest is a
    fact.
    """
    digest = hashlib.sha256()
    with pathlib.Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-transport-parity"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-transport-parity-v1", "steps": []}

    if not PROBE.is_file():
        report["status"] = "BLOCKED"
        report["reason"] = f"the official MCP probe is not built: {PROBE}"
        (evidence / "transport-parity.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return 2

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-parity-", dir="/private/tmp")).resolve()
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
                {"uid": os.getuid(), "credential_file": str(work / "reader-org-a.credential"),
                 "policy": {"principal": "reader-org-a"}},
                {"uid": os.getuid(), "credential_file": str(work / "reader-org-b.credential"),
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
        report["steps"].append("the instance runs with its collectors")

        # the session of the operator of the first organization
        minted = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(work / "reader-org-a.credential")], text=True))
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        request = urllib.request.Request(
            base + "/api/v2/browser/login",
            data=json.dumps({"code": minted["login_code"]}).encode(),
            headers={"Content-Type": "application/json", "Origin": base}, method="POST")
        with opener.open(request, timeout=30) as answer:
            assert answer.status == 200
        report["steps"].append("the operator session is authorized")

        # REST
        with opener.open(urllib.request.Request(base + "/api/v2/snapshot"), timeout=30) as answer:
            rest = json.loads(answer.read().decode())
        # SSE
        event, streamed, sse_status = read_sse(base, "/api/v2/stream", opener)
        # MCP
        # The same principal in all three transports: the parity is about the
        # transports, not about the principals.
        client = McpClient(args.binary, work / "s", work / "reader-org-a.credential")
        clients.append(client)
        mcp = client.resource("oip://v2/snapshot/current")

        projections = {"rest": projection(rest), "sse": projection(streamed),
                       "mcp": projection(mcp)}
        report["projections"] = projections
        report["the_sse_event"] = event
        assert projections["rest"], "the REST projection is empty"
        assert projections["sse"], "the SSE projection is empty"
        assert projections["mcp"], "the MCP projection is empty"
        assert projections["rest"] == projections["sse"], \
            f"REST and SSE differ: {projections['rest']} {projections['sse']}"
        assert projections["rest"] == projections["mcp"], \
            f"REST and MCP differ: {projections['rest']} {projections['mcp']}"
        report["the_three_transports_agree"] = True
        report["steps"].append("the three transports deliver the same projection")

        # the scope: the projection contains nothing of the other organization
        foreign = [item for item in projections["rest"]["sources"]
                   if item not in ("source-a", "source-b", "source-c")]
        assert not foreign, f"the projection contains {foreign}"
        assert "source-d" not in projections["rest"]["sources"], projections["rest"]
        report["the_projection_is_scoped"] = True
        report["steps"].append("the projection carries nothing of the other organization")

        # the transports refuse what they must refuse
        status = None
        try:
            urllib.request.urlopen(base + "/api/v2/snapshot", timeout=15)
        except urllib.error.HTTPError as error:
            status = error.code
        report["rest_without_a_session"] = status
        event, streamed, sse_status = read_sse(base, "/api/v2/stream")
        report["sse_without_a_session"] = {"event": event, "status": sse_status,
                                           "payload": streamed}
        assert status in (401, 403), f"the REST route served an unauthorized read: {status}"
        assert sse_status in (401, 403), \
            f"the SSE stream served an unauthorized projection: {sse_status}"
        report["the_transports_refuse_an_unauthorized_session"] = True
        report["steps"].append("the transports refuse an unauthorized session")

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

    report["the_core_binary"] = {"the_path": str(args.binary),
                                 "the_sha256": the_digest_of_the_binary(args.binary)}
    report["the_revision"] = subprocess.check_output(

        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()

    report["the_tree"] = subprocess.check_output(

        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()

    report["the_working_tree_is_clean"] = not subprocess.check_output(

        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()

    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "transport-parity.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "steps"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
