#!/usr/bin/env python3
"""Exercise certificate approval over REST/MCP against an independent loopback source."""

import argparse
import asyncio
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile

from asyncua.crypto.truststore import TrustStore
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.rsa import generate_private_key
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

from oip_encrypted_recovery import Browser
from oip_license_e2e import login
from oip_opcua_local_profile import NAMESPACE, SERVER_URI, identity, source, stop, until, write_private
from oip_opcua_parity import McpClient, api, free_port

ROOT = Path(__file__).resolve().parents[1]
SETUP_PATH = "/api/v2/opcua/setup"
SOURCE = "managed-opcua"


def certificate_pem(path):
    return x509.load_der_x509_certificate(path.read_bytes()).public_bytes(
        serialization.Encoding.PEM,
    ).decode()


def expired_certificate(template):
    original = x509.load_der_x509_certificate(template.read_bytes())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Expired synthetic source")])
    key = generate_private_key(public_exponent=65537, key_size=2048)
    now = datetime.now(timezone.utc)
    builder = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
               .public_key(key.public_key()).serial_number(x509.random_serial_number())
               .not_valid_before(now - timedelta(days=2)).not_valid_after(now - timedelta(days=1)))
    for extension in original.extensions:
        builder = builder.add_extension(extension.value, extension.critical)
    return builder.sign(key, hashes.SHA256()).public_bytes(serialization.Encoding.PEM).decode()

def prepare(binary, directory, port, web=None):
    config = {"database": str(directory / "core.sqlite"), "http_port": port, "sources": []}
    if web:
        config["web_dir"] = str(web)
    principals = ("operator", "peer", "reader", "foreign")
    role_permissions = ["hierarchy_read", "core_read", "sources_read", "devices_read", "opcua_read", "telemetry_read"]
    plan = {
        "organizations": [{"id": org, "name": org} for org in ("primary", "other")],
        "infrastructures": [
            {"id": f"{org}-infra", "organization_id": org, "name": "Isolation test"}
            for org in ("primary", "other")
        ],
        "sites": [
            {"id": f"{org}-site", "infrastructure_id": f"{org}-infra", "name": "Test stand"}
            for org in ("primary", "other")
        ],
        "sources": [],
        "principals": [{"id": p, "name": p, "enabled": True} for p in principals],
        "roles": [
            {"id": "operator-role", "name": "Site manager", "permissions": role_permissions + ["inventory_manage"]},
            {"id": "reader-role", "name": "Read access", "permissions": role_permissions},
        ],
        "bindings": [
            {"principal_id": p, "role_id": "reader-role" if p == "reader" else "operator-role",
             "scope": {"kind": "site", "id": f"{'other' if p == 'foreign' else 'primary'}-site"}}
            for p in principals
        ],
        "legacy_single_infrastructure": False,
    }
    socket = directory / "ipc.sock"
    ipc = {"socket": str(socket), "clients": []}
    for principal in principals:
        credential = directory / f"{principal}.credential"
        write_private(credential, secrets.token_bytes(32))
        ipc["clients"].append({"uid": os.getuid(), "credential_file": str(credential),
                               "policy": {"principal": principal}})
    for name, contents in (("core.json", config), ("plan.json", plan), ("ipc.json", ipc)):
        write_private(directory / name, json.dumps(contents).encode())
    command = [binary, "--config", directory / "core.json"]
    subprocess.run([*command, "--provision", directory / "plan.json"], check=True,
                   stdout=subprocess.DEVNULL, timeout=25)
    return command, socket


def request(operation, device="ua-device", site="primary-site"):
    return {"site": site, "device": device, "operation": operation}


def need(response, status, code=None):
    assert response[0] == status, response
    if code is not None:
        assert response[1]["code"] == code, response
    return response[1]


async def check_recovery(binary, directory, pki, saved, original_cert, status):
    clone = directory / "restore"
    archive = directory / "backup.oip"
    port = free_port()
    browser = Browser(port)
    passphrase = secrets.token_urlsafe(36)
    command = [
        sys.executable, ROOT / "tools/oip_ops.py", "--config", directory / "core.json",
        "--ipc-config", directory / "ipc.json", "--state-dir", directory / "ops-state",
        "--binary", binary,
    ]

    async def recovery(*words, encrypted=False):
        arguments = ["--passphrase-fd", "0"] if encrypted else []
        result = await asyncio.to_thread(
            subprocess.run, [*command, *words, *arguments],
            input=(passphrase + "\n") if encrypted else None,
            capture_output=True, text=True, timeout=70,
        )
        assert result.returncode == 0, (words[0], result.stderr, result.stdout)
        return json.loads(result.stdout)

    backup = await recovery("recovery-backup", "--output", archive, encrypted=True)
    assert backup["status"] == "encrypted_backup_created"
    assert (pki / "client.pem").read_bytes() not in archive.read_bytes()
    restored = await recovery("recovery-restore", "--source", archive, "--restore-dir", clone, encrypted=True)
    assert restored["status"] == "restored_inactive"
    recovered = clone / "instance"
    recovered_pki = recovered / pki.name
    for name in ("client.der", "client.pem", "trusted/server.der"):
        path = recovered_pki / name
        assert path.read_bytes() == (pki / name).read_bytes() and path.stat().st_mode & 0o077 == 0
    started = await recovery("recovery-start", "--restore-dir", clone, "--port", str(port))
    assert started["mode"] == "isolated_recovery"
    try:
        manifest = json.loads((recovered / "recovery.json").read_text())
        credential = recovered / manifest["ipc"]["clients"][0]["credential_file"]
        await asyncio.to_thread(browser.login, binary, recovered / "oip.sock", credential, "operator")
        current = await asyncio.to_thread(browser.call, "opcua/setup", status)
        assert current == {**saved, "collector_enabled": False}
        disabled = request({"action": "preview", "configuration": None,
                            "server_certificate_pem": certificate_pem(original_cert)})
        blocked = await asyncio.to_thread(browser.call, "opcua/setup", disabled, expected=503)
        assert blocked["code"] == "OPCUA_SETUP_DISABLED"
        sources = await asyncio.to_thread(browser.call, "sources")
        assert all(item["connection"] != "connected" for item in sources)
    finally:
        await recovery("recovery-stop", "--restore-dir", clone)


async def exercise(binary, directory, web=None, screenshot=None):
    port, source_port = free_port(), free_port()
    while port == source_port:
        source_port = free_port()
    base = f"http://127.0.0.1:{port}"
    endpoint = f"opc.tcp://127.0.0.1:{source_port}/"
    command, socket = prepare(binary, directory, port, web)
    log = (directory / "core.log").open("w")
    process, managers, ua_server = None, [], None
    configuration = {
        "endpoint": endpoint, "server_application_uri": SERVER_URI, "namespace_uri": NAMESPACE,
        "poll_seconds": 5,
        "points": [{"metric": "temperature", "node_id": "s=Temperature", "value_kind": "float"}],
    }
    cert, key = identity(directory / "server", SERVER_URI, ExtendedKeyUsageOID.SERVER_AUTH, "Independent OPC UA")
    replacement, replacement_key = identity(directory / "replacement", SERVER_URI, ExtendedKeyUsageOID.SERVER_AUTH, "Replacement OPC UA")
    wrong, _ = identity(directory / "wrong", "urn:wrong", ExtendedKeyUsageOID.SERVER_AUTH, "Wrong application")
    cert_hash = hashlib.sha256(cert.read_bytes()).hexdigest()
    replacement_hash = hashlib.sha256(replacement.read_bytes()).hexdigest()
    pki = directory / "core.sqlite.managed-opcua"
    trust_dir = directory / "server-trust"
    trust_dir.mkdir(mode=0o700)
    store = TrustStore([trust_dir], [])
    await store.load()

    async def boot():
        nonlocal process
        process = subprocess.Popen([*command, "--daemon", "--ipc-config", directory / "ipc.json"],
                                   stdout=log, stderr=log)
        async def open_session():
            assert process.poll() is None, "Core stopped before login"
            if socket.exists():
                try:
                    return await asyncio.to_thread(login, binary, directory, base, "operator")
                except (subprocess.CalledProcessError, OSError):
                    pass
        return await until(open_session, "Core did not accept login", timeout=25)

    async def mcp(principal):
        client = await asyncio.to_thread(McpClient, binary, socket, directory / f"{principal}.credential", principal)
        managers.append(client)
        return client

    async def shutdown():
        nonlocal process
        while managers:
            await asyncio.to_thread(managers.pop().close)
        if process:
            await stop(process)
            process = None

    async def rest(path, body=None, session=None, csrf=True):
        opener, token = session or operator
        headers = {"Origin": base}
        if csrf:
            headers["x-oip-csrf"] = token
        return await asyncio.to_thread(api, base, path, "POST" if body is not None else "GET",
                                       body, headers, opener)

    async def tools(client):
        client.process.stdin.write('{"op":"tools"}\n')
        client.process.stdin.flush()
        return json.loads(await asyncio.to_thread(client.process.stdout.readline))

    async def health():
        return next((item for item in need(await rest("/api/v2/sources"), 200)
                     if item["id"] == SOURCE), {})

    async def observed():
        page = need(await rest("/api/v2/opcua/nodes?source=managed-opcua&limit=1&q=temperature"), 200)
        for item in page["items"]:
            value = item.get("observation")
            if value and value["freshness"] == "fresh" and (await health())["connection"] == "connected":
                assert item["access"] == "Read"
                assert value["value"] == {"float": 22.5}
                assert value.get("simulation_origin") is None
                return item

    try:
        operator = await boot()
        peer = await mcp("peer")
        reader = await mcp("reader")
        foreign_session = await asyncio.to_thread(login, binary, directory, base, "foreign")
        manager = await mcp("operator")
        status = request({"action": "status"})
        need(await rest("/api/v2/inventory/apply", {"changes": [{
            "operation": "register",
            "device": {"id": "ua-device", "display_name": "Prüfmaschine", "device_type": "industrial_device", "site_id": "primary-site"},
        }]}), 200)
        assert need(await rest(SETUP_PATH, status), 200) == {"state": "unconfigured"}
        assert await asyncio.to_thread(manager.call, "opcua_setup", status) == {"state": "unconfigured"}
        assert "oip_opcua_setup" in json.dumps(await tools(manager))
        assert "oip_opcua_setup" not in json.dumps(await tools(reader))
        assert (await rest(SETUP_PATH, status, csrf=False))[0] in (401, 403)
        need(await rest(SETUP_PATH, status, session=foreign_session), 403, "OPCUA_SETUP_DENIED")
        denied = await asyncio.to_thread(reader.denied, "opcua_setup", status)
        assert denied["result"]["structuredContent"]["code"] == "OPCUA_SETUP_DENIED", denied

        def preview(pem, settings=configuration):
            return request({"action": "preview", "configuration": settings, "server_certificate_pem": pem})

        need(await rest(SETUP_PATH, preview("malformed")), 400, "OPCUA_CERT_INVALID")
        need(await rest(SETUP_PATH, preview(expired_certificate(cert))), 400, "OPCUA_CERT_TIME")
        need(await rest(SETUP_PATH, preview(certificate_pem(wrong))), 400, "OPCUA_CERT_IDENTITY")
        mismatch_ip = {**configuration, "endpoint": endpoint.replace("127.0.0.1", "127.0.0.2")}
        need(await rest(SETUP_PATH, preview(certificate_pem(cert), mismatch_ip)), 400, "OPCUA_CERT_IDENTITY")
        unsigned = {**configuration, "security_mode": "None"}
        need(await rest(SETUP_PATH, preview(certificate_pem(cert), unsigned)), 400, "OPCUA_SETUP_ARGUMENTS")
        reviewed = need(await rest(SETUP_PATH, preview(certificate_pem(cert))), 200)
        assert reviewed["configuration"] == configuration and reviewed["certificate"]["sha256"] == cert_hash
        assert not pki.exists() and not await health()
        confirm = request({"action": "apply", "confirmation": reviewed["confirmation"], "verified_sha256": cert_hash})
        denied = await asyncio.to_thread(peer.denied, "opcua_setup", confirm)
        assert denied["result"]["structuredContent"]["code"] == "OPCUA_CONFIRMATION_INVALID", denied
        need(await rest(SETUP_PATH, {**confirm, "operation": {**confirm["operation"], "verified_sha256": "0" * 64}}),
             400, "OPCUA_FINGERPRINT_MISMATCH")

        if web:
            receipt = await asyncio.to_thread(subprocess.check_output, [
                binary, "--browser-login", "--ipc-socket", socket,
                "--ipc-credential", directory / "operator.credential",
            ], text=True, timeout=10)
            fixture = {**configuration, "code": json.loads(receipt)["login_code"],
                       "certificate": str(cert), "sha256": cert_hash}
            await asyncio.to_thread(subprocess.run, [
                "node", ROOT / "apps/flutter/test/browser_opcua_setup.mjs", base, screenshot,
            ], input=json.dumps(fixture), text=True, check=True, timeout=180)
            saved = await asyncio.to_thread(manager.call, "opcua_setup", status)
        else:
            saved = await asyncio.to_thread(manager.call, "opcua_setup", confirm)
        assert saved["state"] == "configured" and saved["server_sha256"] == cert_hash
        assert saved == need(await rest(SETUP_PATH, status), 200)
        need(await rest(SETUP_PATH, confirm), 400, "OPCUA_CONFIRMATION_INVALID")
        assert (pki / "client.pem").stat().st_mode & 0o077 == 0
        assert "PRIVATE KEY" not in json.dumps(saved)
        public_client = x509.load_pem_x509_certificate(saved["client_certificate_pem"].encode())
        write_private(trust_dir / "client.der", public_client.public_bytes(serialization.Encoding.DER))
        await store.load()
        ua_server, point, _ = await source(endpoint, cert, key, store)
        await ua_server.start()
        sample = await until(observed, "Approved source did not deliver a value")
        write = await rest("/api/v2/opcua/write", {
            "source": SOURCE, "node_id": sample["node_id"], "value": {"float": 31.0},
        })
        assert 400 <= write[0] < 500 and await point.read_value() == 22.5, write

        await ua_server.stop()
        ua_server, _, _ = await source(endpoint, replacement, replacement_key, store, shifted=True)
        await ua_server.start()
        async def changed():
            return (await health()).get("last_error") == "opcua_certificate_changed"
        await until(changed, "A changed peer certificate was not rejected")
        reviewed = await asyncio.to_thread(manager.call, "opcua_setup", preview(certificate_pem(replacement), None))
        assert reviewed["previous_sha256"] == cert_hash
        rotated = need(await rest(SETUP_PATH, request({
            "action": "apply", "confirmation": reviewed["confirmation"], "verified_sha256": replacement_hash,
        })), 200)
        assert rotated["client_certificate_pem"] == saved["client_certificate_pem"]
        reindexed = await until(observed, "Updated trust did not reconnect")
        assert reindexed["node_id"] != sample["node_id"]
        await shutdown()
        operator = await boot()
        assert need(await rest(SETUP_PATH, status), 200) == rotated
        await until(observed, "Managed configuration did not resume after restart")
        await shutdown()

        await check_recovery(binary, directory, pki, rotated, cert, status)
    finally:
        await shutdown()
        if ua_server:
            await ua_server.stop()
        log.close()
    return {"status": "PASS", "core_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
            "server": "independent asyncua loopback, Basic256Sha256/SignAndEncrypt",
            "checks": ["site_and_role_denial", "csrf", "invalid_expired_wrong_identity", "no_preapproval_collector",
                       "fingerprint_mismatch", "foreign_confirmation", "single_use_confirmation",
                       ("browser_approval_and_client_download" if web else "rest_preview_mcp_apply"),
                       "mcp_preview_rest_rotation", "server_trust",
                       "selected_value", "read_only", "changed_certificate_rejected", "namespace_reindex",
                       "restart", "encrypted_managed_pki_restore", "recovery_collector_inhibited"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=ROOT / "target/debug/oip-server")
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--web", type=Path)
    args = parser.parse_args()
    screenshot = args.evidence.with_suffix(".png").resolve()
    with tempfile.TemporaryDirectory(prefix="oip-ua-setup-", dir="/private/tmp" if sys.platform == "darwin" else None) as folder:
        directory = Path(folder).resolve()
        try:
            evidence = asyncio.run(exercise(args.binary.resolve(strict=True), directory, args.web.resolve(strict=True) if args.web else None, screenshot))
        except BaseException:
            path = directory / "core.log"
            if path.is_file():
                print(path.read_text()[-8000:], file=sys.stderr)
            raise
    args.evidence.write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps(evidence, indent=2))
