#!/usr/bin/env python3
"""The authorized service registry of the Core (G8).

The Core measures no service and holds no credential for one: the registry
holds what the **operator declared** in the plan of the instance. This
rehearsal proves against the real Core that

  1. the registry is delivered with the provenance `declared`,
  2. the scope of the read is the scope of the inventory — the reader of one
     organization never sees the service of the other,
  3. a foreign identifier is refused **identically** to an identifier that does
     not exist (the answer discloses neither),
  4. the MCP tool answers the same registry as the route, and
  5. a plan that declares a service for a site that does not exist is refused
     instead of losing the declaration.

The instance is disposable and owns its store; the personal installation of the
operator is never touched.

Usage:
  python3 tests/oip_service_registry.py [--evidence DIR]
"""
import argparse
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

    def call(self, name, arguments=None):
        self.process.stdin.write(json.dumps(
            {"op": "call", "name": name, "arguments": arguments or {}}) + "\n")
        self.process.stdin.flush()
        answer = json.loads(self.process.stdout.readline())
        assert answer.get("ok"), answer
        return answer["result"]

    def close(self):
        if self.process.poll() is not None:
            return
        self.process.stdin.close()
        self.process.wait(timeout=20)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-service-registry"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-service-registry-rehearsal-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-services-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    try:
        port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        # The sources of the plan need their definitions; the registry does
        # not read them, so the collectors of the instance stay silent.
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": port,
            "sources": [{"id": f"source-{letter}",
                          "name": f"Local simulation {letter}",
                          "endpoint": f"opc.tcp://127.0.0.1:{free_port()}",
                          "namespace": 2}
                         for letter in "abcd"],
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

        tool("provision-plan", "--plan", str(work / "plan.json"))
        tool("start")
        time.sleep(4)
        report["steps"].append("the instance runs with the declared services")

        # The authorized session of the reader of the first organization.
        minted = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(credential)], text=True))
        import http.cookiejar
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        login = urllib.request.Request(
            f"http://127.0.0.1:{port}/api/v2/browser/login",
            data=json.dumps({"code": minted["login_code"]}).encode(),
            headers={"Content-Type": "application/json",
                     "Origin": f"http://127.0.0.1:{port}"}, method="POST")
        with opener.open(login, timeout=60) as answer:
            session = json.loads(answer.read().decode())
        report["the_session"] = {"the_principal": session.get("principal_id")}

        def read(path):
            request = urllib.request.Request(
                f"http://127.0.0.1:{port}{path}",
                headers={"Origin": f"http://127.0.0.1:{port}"})
            try:
                with opener.open(request, timeout=60) as answer:
                    return json.loads(answer.read().decode()), answer.status
            except urllib.error.HTTPError as error:
                return json.loads(error.read().decode()), error.code

        page, status = read("/api/v2/services?limit=100")
        report["the_registry"] = page
        assert status == 200, (status, page)
        ids = [item["service"]["id"] for item in page["items"]]
        report["the_service_ids"] = ids
        # The reader of the first organization sees the services of its own
        # sites and never the service of the other organization.
        assert "svc-a1-opcua" in ids, ids
        assert "svc-a1-https" in ids, ids
        assert "svc-b1-ssh" not in ids, ids
        # Every record carries the provenance **declared**: the Core measures no
        # service.
        assert all(item["origin"] == "declared" for item in page["items"]), page
        # The device of a record is resolved against the inventory; the
        # declaration without a device names that honestly.
        by_id = {item["service"]["id"]: item for item in page["items"]}
        assert by_id["svc-a1-opcua"]["device_id"] == "device-a", by_id
        assert by_id["svc-a1-https"]["device_id"] is None, by_id
        report["steps"].append("the registry holds the declared services of the scope")

        # A foreign identifier is refused like an identifier that does not
        # exist: the answer discloses neither.
        foreign, foreign_status = read("/api/v2/services?id=svc-b1-ssh")
        unknown, unknown_status = read("/api/v2/services?id=svc-absent")
        report["the_refusal_of_a_foreign_service"] = {
            "the_code": foreign_status, "the_body": foreign}
        assert foreign_status == unknown_status == 404, (foreign_status, unknown_status)
        assert foreign.get("code") == unknown.get("code") == "RESOURCE_NOT_ACCESSIBLE", \
            (foreign, unknown)
        report["steps"].append("a foreign service is refused like an unknown one")

        # The MCP tool answers the same registry as the route.
        client = McpClient(args.binary, work / "s", credential)
        try:
            answer = client.call("oip_services_read", {"limit": 100})
            value = answer.get("structuredContent") or answer.get("structured_content") or {}
            mcp_items = (value.get("value") or value).get("items", [])
            mcp_ids = [item["service"]["id"] for item in mcp_items]
            report["the_mcp_ids"] = mcp_ids
            assert mcp_ids == ids, (mcp_ids, ids)
        finally:
            client.close()
        report["steps"].append("the MCP tool answers the same registry as the route")

        # A plan that declares a service for a site that does not exist is
        # refused: the scope of a record must exist before the record exists.
        broken = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        broken["services"][0]["site_id"] = "site-that-does-not-exist"
        (work / "broken-plan.json").write_text(json.dumps(broken, indent=2))
        refused = tool("provision-plan", "--plan", str(work / "broken-plan.json"),
                       expect_success=False)
        report["the_refusal_of_a_broken_plan"] = {
            "the_code": refused.returncode,
            "the_error": (refused.stderr or refused.stdout).strip()[-300:]}
        assert refused.returncode != 0, "the Core accepted a service of a site that does not exist"
        report["steps"].append("a plan with a service of an unknown site is refused")

        report["the_status"] = "PASS"
    except AssertionError as error:
        report["the_status"] = "FAIL"
        report["the_problems"] = [str(error)]
    except Exception as error:  # noqa: BLE001 - a fact of the machine
        report["the_status"] = "FAIL"
        report["the_problems"] = [f"{type(error).__name__}: {error}"]
    finally:
        try:
            tool("stop", expect_success=False)
        except Exception:
            pass
        if report.get("the_status") == "PASS":
            shutil.rmtree(work, ignore_errors=True)
        else:
            report["the_work_directory"] = str(work)

    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "service-registry.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report.get("the_status"),
                      "the_steps": len(report["steps"]),
                      "the_problems": report.get("the_problems")}, indent=2))
    return 0 if report.get("the_status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
