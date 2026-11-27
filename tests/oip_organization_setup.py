#!/usr/bin/env python3
"""Exercise in-app organization creation and OPC-UA registration with an isolated Core."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

from oip_encrypted_recovery import Browser, wait_for
from oip_opcua_parity import McpClient, free_port
from oip_opcua_setup import prepare

ROUTE = "organizations/setup"
ROOT = Path(__file__).resolve().parents[1]


def main(binary, web, directory, screenshot):
    port = free_port()
    command, socket = prepare(binary, directory, port, web, organization_management=True)
    log = directory / "core.log"

    def login(principal):
        session = Browser(port)
        session.login(binary, socket, directory / f"{principal}.credential", principal)
        return session

    def boot():
        with log.open("a") as output:
            core = subprocess.Popen([*command, "--daemon", "--ipc-config", directory / "ipc.json"],
                                    stdout=output, stderr=subprocess.STDOUT)
        try:
            def open_session():
                assert core.poll() is None, log.read_text()
                if socket.exists():
                    try:
                        return login("operator")
                    except (OSError, subprocess.CalledProcessError):
                        pass
            return core, wait_for(open_session, "The isolated Core did not accept a login")
        except BaseException:
            core.terminate()
            core.wait(timeout=20)
            raise

    result = {}
    core, operator = boot()
    clients = []
    try:
        reader = login("reader")
        foreign = login("foreign")
        initial = operator.call("organizations")
        assert [row["id"] for row in initial["items"]] == ["primary"]
        status = {"action": "status"}
        assert operator.call(ROUTE, status) == {"state": "status", "can_create": True}
        assert reader.call(ROUTE, status)["can_create"] is False
        assert foreign.call(ROUTE, status)["can_create"] is False
        request = {"action": "create", "request_id": str(uuid.uuid4()),
                   "organization": "Second organization", "infrastructure": "Workshop", "site": "Test bench"}
        assert Browser(port).call(ROUTE, request, expected=403)["code"] == "PERMISSION_DENIED"
        token, operator.csrf = operator.csrf, None
        operator.call(ROUTE, request, expected=403)
        operator.csrf = token
        assert reader.call(ROUTE, request, expected=403)["code"] == "PERMISSION_DENIED"
        operator.call(ROUTE, {**request, "site": " "}, expected=400)
        operator.call(ROUTE, {**request, "principal": "foreign"}, expected=400)
        assert operator.call("organizations") == initial

        for principal in ("operator", "reader"):
            clients.append(McpClient(binary, socket, directory / f"{principal}.credential", principal))
        manager, readonly = clients
        for client, visible in ((manager, True), (readonly, False)):
            client.process.stdin.write('{"op":"tools"}\n')
            client.process.stdin.flush()
            listed = json.loads(client.process.stdout.readline())
            assert ("oip_organization_setup" in json.dumps(listed)) == visible, listed
        refusal = readonly.denied("organization_setup", request)
        assert refusal["result"]["isError"] and refusal["result"]["structuredContent"]["code"] == "PERMISSION_DENIED", refusal
        assert manager.call("organization_setup", status) == operator.call(ROUTE, status)
        created = manager.call("organization_setup", request)
        org_id = created["organization_id"]
        assert operator.call(ROUTE, request) == created
        assert operator.call(ROUTE, {**request, "organization": "Different"}, expected=400)["code"] == "ORGANIZATION_SETUP_INVALID"
        assert [row["id"] for row in reader.call("organizations")["items"]] == ["primary"]
        assert [row["id"] for row in foreign.call("organizations")["items"]] == ["other"]
        assert operator.call("sites?infrastructure=" + created["infrastructure_id"])["items"][0]["id"] == created["site_id"]
        assert operator.call("inventory/devices")["items"] == []
        result.update(api_mcp="PASS", idempotent_retry="PASS", access_isolation="PASS")

        if web:
            minted = subprocess.check_output([binary, "--browser-login", "--ipc-socket", socket,
                                             "--ipc-credential", directory / "operator.credential"],
                                            text=True, timeout=10)
            digest = hashlib.sha256((web / "main.dart.js").read_bytes()).hexdigest()
            subprocess.run(["node", ROOT / "apps/flutter/test/browser_organization_setup.mjs",
                            operator.origin, screenshot],
                           input=json.dumps({"code": json.loads(minted)["login_code"], "bundleSha256": digest}),
                           text=True, check=True, timeout=240)
            registered, = operator.call("inventory/devices")["items"]
            assert registered["record"]["device"]["display_name"] == "Prüfmaschine"
            assert registered["sources"] == [] and registered["organization_id"] != org_id
            result.update(browser_create_select_register="PASS", browser_bundle_sha256=digest)
        count = subprocess.check_output(
            ["sqlite3", "-readonly", directory / "core.sqlite",
             "SELECT count(*) FROM provisioning_audit WHERE operation='create_organization'"],
            text=True, timeout=5,
        )
        assert int(count) == (2 if web else 1)
    finally:
        for client in clients:
            client.close()
        core.terminate()
        core.wait(timeout=20)

    restarted, operator = boot()
    try:
        assert org_id in {row["id"] for row in operator.call("organizations")["items"]}
        assert operator.call(ROUTE, request) == created
        if web:
            assert len(operator.call("inventory/devices")["items"]) == 1
        result["persisted_after_restart"] = "PASS"
    finally:
        restarted.terminate()
        restarted.wait(timeout=20)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=ROOT / "target/debug/oip-server")
    parser.add_argument("--web", type=Path)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="oip-org-", dir="/private/tmp" if sys.platform == "darwin" else None) as tmp:
        result = main(args.binary.resolve(strict=True), args.web.resolve(strict=True) if args.web else None,
                      Path(tmp), args.evidence.with_suffix(".png").resolve())
    args.evidence.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
