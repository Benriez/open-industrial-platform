#!/usr/bin/env python3
"""Exercise the read-only OIP profile against an independent local asyncua server."""

import argparse
import asyncio
from datetime import datetime, timezone
import hashlib
import http.cookiejar
import ipaddress
import json
import os
from pathlib import Path
import secrets
import signal
import subprocess
import sys
import tempfile
import urllib.request

from asyncua import Server, ua
from asyncua.crypto.cert_gen import generate_self_signed_app_certificate
from asyncua.crypto.truststore import TrustStore
from asyncua.crypto.validator import CertificateValidator, CertificateValidatorOptions
from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.rsa import generate_private_key
from cryptography.x509.oid import ExtendedKeyUsageOID

from oip_opcua_parity import api, free_port, McpClient


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from oip_ops import sqlite_query

SERVER_URI = "urn:oip-test:independent-server"
CLIENT_URI = "urn:oip:local-test-client"
NAMESPACE = "urn:oip-test:selected-points"
POINT_TIME = datetime(2025, 5, 1, tzinfo=timezone.utc)


def write_private(path, data):
    with os.fdopen(
        os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb"
    ) as file:
        file.write(data)


def identity(directory, uri, usage, name):
    directory.mkdir(mode=0o700)
    key = generate_private_key(public_exponent=65537, key_size=2048)
    cert = generate_self_signed_app_certificate(
        key, name, {}, [
            x509.UniformResourceIdentifier(uri),
            x509.IPAddress(ipaddress.ip_address("127.0.0.1")),
        ],
        [usage],
        days=1,
    )
    cert_path, key_path = directory / "cert.der", directory / "key.pem"
    write_private(cert_path, cert.public_bytes(serialization.Encoding.DER))
    write_private(key_path, key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL,
        serialization.NoEncryption(),
    ))
    return cert_path, key_path


async def source(endpoint, cert, key, trust_store, shifted=False):
    server = Server()
    await server.init()
    server.set_endpoint(endpoint)
    await server.set_application_uri(SERVER_URI)
    await server.load_certificate(str(cert))
    await server.load_private_key(key)
    server.set_security_policy([ua.SecurityPolicyType.Basic256Sha256_SignAndEncrypt])
    server.set_security_IDs(["Anonymous"])
    server.set_certificate_validator(CertificateValidator(
        CertificateValidatorOptions.EXT_VALIDATION
        | CertificateValidatorOptions.PEER_CLIENT
        | CertificateValidatorOptions.TRUSTED,
        trust_store,
    ))
    if shifted:
        await server.register_namespace("urn:oip-test:other-namespace")
    index = await server.register_namespace(NAMESPACE)
    point = await server.nodes.objects.add_variable(ua.NodeId("Temperature", index), "Temperature", 22.5)
    await point.write_value(ua.DataValue(
        ua.Variant(22.5, ua.VariantType.Double),
        ua.StatusCode(ua.StatusCodes.Good),
        SourceTimestamp=POINT_TIME,
    ))
    # asyncua leaves AccessLevel and UserAccessLevel read-only by default.
    assert not (await point.get_user_access_level()) & {ua.AccessLevel.CurrentWrite}
    return server, point, index


async def until(predicate, label, timeout=55):
    deadline = asyncio.get_running_loop().time() + timeout
    while asyncio.get_running_loop().time() < deadline:
        result = await predicate()
        if result:
            return result
        await asyncio.sleep(0.2)
    raise AssertionError(label)


async def stop(process):
    if process.poll() is None:
        process.send_signal(signal.SIGINT)
        try:
            await asyncio.to_thread(process.wait, 25)
        except subprocess.TimeoutExpired:
            process.kill()
            await asyncio.to_thread(process.wait, 10)
            raise


async def scenario(binary, evidence, work):
    cert, key = identity(work / "server", SERVER_URI, ExtendedKeyUsageOID.SERVER_AUTH, "OIP independent fixture")
    client_cert, client_key = identity(work / "pki", CLIENT_URI, ExtendedKeyUsageOID.CLIENT_AUTH, "OIP fixture client")
    trusted = client_cert.parent / "trusted"
    rejected = client_cert.parent / "rejected"
    trusted.mkdir(mode=0o700)
    rejected.mkdir(mode=0o700)
    server_trusted = cert.parent / "trusted"
    server_trusted.mkdir(mode=0o700)
    write_private(server_trusted / "client.der", client_cert.read_bytes())
    trust_store = TrustStore([server_trusted], [])
    await trust_store.load()
    port, source_port = free_port(), free_port()
    while source_port == port:
        source_port = free_port()
    endpoint = f"opc.tcp://127.0.0.1:{source_port}/"
    base = f"http://127.0.0.1:{port}"
    config = {
        "database": str(work / "core.sqlite"), "http_port": port,
        "opcua_read_only": True,
        "sources": [{
            "id": "test-source", "name": "Independent test source", "endpoint": endpoint,
            "entity_id": "test-device",
            "opcua": {
                "namespace_uri": NAMESPACE, "server_application_uri": SERVER_URI,
                "poll_ms": 5000, "pki_dir": str(client_cert.parent),
                "certificate_path": client_cert.name, "private_key_path": client_key.name,
                "points": [{"metric": "temperature", "node_id": "s=Temperature", "value_kind": "float"}],
            },
        }],
    }
    plan = {
        "organizations": [{"id": "test-org", "name": "Test organization"},
                          {"id": "other-org", "name": "Other organization"}],
        "infrastructures": [{"id": "test-infra", "name": "Test installation", "organization_id": "test-org"}],
        "sites": [{"id": "test-site", "name": "Test site", "infrastructure_id": "test-infra"}],
        "sources": [{"source_id": "test-source", "site_id": "test-site",
                     "device_id": "test-device", "entity_id": "test-device"}],
        "principals": [{"id": "test-operator", "name": "Test operator", "enabled": True},
                       {"id": "other-operator", "name": "Other operator", "enabled": True}],
        "roles": [{"id": "test-role", "name": "Test role", "permissions": [
            "hierarchy_read", "core_read", "sources_read", "devices_read",
            "telemetry_read", "events_read", "opcua_read", "inventory_manage",
        ]}],
        "bindings": [{"principal_id": principal, "role_id": "test-role",
                      "scope": {"kind": "organization", "id": org}}
                     for principal, org in [("test-operator", "test-org"), ("other-operator", "other-org")]],
        "legacy_single_infrastructure": False,
    }
    socket, credential = work / "ipc.sock", work / "operator.credential"
    other_credential = work / "other.credential"
    ipc = {"socket": str(socket), "clients": [
        {"uid": os.getuid(), "credential_file": str(file), "policy": {"principal": principal}}
        for file, principal in [(credential, "test-operator"), (other_credential, "other-operator")]
    ]}
    for name, data in [("core.json", config), ("plan.json", plan), ("ipc.json", ipc)]:
        write_private(work / name, json.dumps(data).encode())
    write_private(credential, secrets.token_bytes(32))
    write_private(other_credential, secrets.token_bytes(32))
    command = [binary, "--config", work / "core.json"]
    provision = [*command, "--provision", work / "plan.json"]
    await asyncio.to_thread(subprocess.run, provision, check=True, timeout=20, stdout=subprocess.DEVNULL)

    async def boot():
        process = subprocess.Popen([*command, "--daemon", "--ipc-config", work / "ipc.json"],
                                   stdout=log, stderr=log)
        try:
            async def issue_code():
                assert process.poll() is None, "Core stopped before authenticating"
                if not socket.exists():
                    return None
                grant = await asyncio.to_thread(subprocess.run, [
                    binary, "--browser-login", "--ipc-socket", socket, "--ipc-credential", credential,
                ], capture_output=True, timeout=10)
                return json.loads(grant.stdout)["login_code"] if grant.returncode == 0 else None
            code = await until(issue_code, "Login service did not start")
            browser = urllib.request.build_opener(
                urllib.request.ProxyHandler({}), urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
            )
            status, login = await asyncio.to_thread(
                api, base, "/api/v2/browser/login", "POST", {"code": code}, {"Origin": base}, browser,
            )
            assert status == 200, status
            return process, browser, login["csrf_token"]
        except BaseException:
            await stop(process)
            raise

    async def get(path):
        status, model = await asyncio.to_thread(api, base, path, opener=browser)
        assert status == 200, status
        return model

    async def health():
        return (await get("/api/v2/sources"))[0]

    async def node():
        page = await get("/api/v2/opcua/nodes?source=test-source&limit=1&q=temperature")
        return next(iter(page["items"]), {})

    async def fresh():
        value = (await node()).get("observation")
        return value if value and value["freshness"] == "fresh" else None

    def checked_observation(observation):
        assert observation["data_source_id"] == "test-source"
        assert observation["entity_id"] == "test-device"
        assert observation["unit"] == "none"
        assert observation.get("simulation_origin") is None
        assert observation["value"] == {"float": 22.5}

    process = None
    log = (work / "core.log").open("w")
    try:
        server, point, namespace = await source(endpoint, cert, key, trust_store)
        async with server:
            process, browser, csrf = await boot()

            async def refused():
                item = await health()
                return (list(rejected.glob("*.der")) and item["connection"] != "connected"
                        and item["last_error"] == "opcua_certificate_untrusted")
            await until(refused, "Peer without published trust was not rejected")
            assert not list(trusted.iterdir())
            request = next(rejected.glob("*.der"))
            # Out-of-band comparison with the fixture operator's original DER.
            assert hashlib.sha256(request.read_bytes()).digest() == hashlib.sha256(cert.read_bytes()).digest()
            request.replace(trusted / request.name)
            initial = await until(fresh, "Trusted point not available")
            checked_observation(initial)
            assert (await node())["node_id"] == f"ns={namespace};s=Temperature"
            assert (await health())["simulated"] is False

            query = {"source": "test-source", "limit": 1, "q": "temperature"}
            mcp = await asyncio.to_thread(McpClient, binary, socket, credential, "test-operator")
            try:
                page = await asyncio.to_thread(mcp.call, "opcua_nodes_read", query)
                checked_observation(page["items"][0]["observation"])
                assert page["items"][0]["node_id"] == (await node())["node_id"]
            finally:
                await asyncio.to_thread(mcp.close)
            other = await asyncio.to_thread(McpClient, binary, socket, other_credential, "other-operator")
            try:
                denial = await asyncio.to_thread(other.denied, "opcua_nodes_read", query)
                assert not denial.get("ok") or denial.get("result", {}).get("isError"), denial
            finally:
                await asyncio.to_thread(other.close)

            async def unchanged():
                current = await fresh()
                if current and current["timestamps"]["received"] != initial["timestamps"]["received"]:
                    return current
            next_sample = await until(unchanged, "Unused source timestamp blocked fresh receipt")
            assert next_sample["timestamps"]["source"] == initial["timestamps"]["source"]

            status, denial = await asyncio.to_thread(
                api, base, "/api/v2/opcua/write", "POST",
                {"source": "test-source", "node_id": f"ns={namespace};s=Temperature",
                 "value": {"float": 31.0}},
                {"Origin": base, "x-oip-csrf": csrf}, browser,
            )
            assert status == 409 and "OPCUA_READ_ONLY_PROFILE" in json.dumps(denial), (status, denial)
            assert await point.read_value() == 22.5

            await point.write_value(ua.DataValue(
                ua.Variant(22.5, ua.VariantType.Double),
                ua.StatusCode(ua.StatusCodes.Uncertain),
                SourceTimestamp=POINT_TIME,
            ))

            async def uncertain():
                value = (await node()).get("observation")
                return value and value["quality"] == "uncertain" and value["status_code"] == ua.StatusCodes.Uncertain
            await until(uncertain, "The same-timestamp Uncertain status was not shown")

        async def disconnected():
            item = await health()
            return item["connection"] != "connected" and item["freshness"] != "fresh"
        await until(disconnected, "Stopped server still appears connected")
        server, _, shifted = await source(endpoint, cert, key, trust_store, shifted=True)
        assert shifted != namespace
        async with server:
            checked_observation(await until(fresh, "Namespace remap did not reconnect"))
            assert (await node())["node_id"] == f"ns={shifted};s=Temperature"
            await stop(process)
            process = None
            provisioned = await asyncio.to_thread(
                subprocess.check_output, provision, text=True, timeout=20,
            )
            assert json.loads(provisioned)["idempotent"] is True
            process, browser, _ = await boot()
            checked_observation(await until(fresh, "Point did not return after Core restart"))
        await stop(process)
        database = Path(config["database"])
        assert database.is_file()
        assert sqlite_query(database, "PRAGMA integrity_check") == "ok"
        assert sqlite_query(database, "SELECT DISTINCT origin_class FROM observations") == "external"
        assert int(sqlite_query(database, "SELECT count(*) FROM data_gaps")) >= 1
    finally:
        if process is not None:
            await stop(process)
        log.close()

    report = {
        "status": "PASS", "profile": "Basic256Sha256 / SignAndEncrypt / Anonymous",
        "core_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "tested": ["explicit_trust", "scoped_selected_value", "mcp_scope", "unchanged_timestamp", "uncertain_status",
                   "read_only_denial", "outage", "namespace_remap", "reprovision", "core_restart", "stored_gap"],
    }
    evidence.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=ROOT / "target/release/oip-server")
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    temp_root = "/private/tmp" if sys.platform == "darwin" else None
    with tempfile.TemporaryDirectory(prefix="oip-ua-", dir=temp_root) as directory:
        work = Path(directory).resolve()
        try:
            asyncio.run(scenario(args.binary.resolve(strict=True), args.evidence, work))
        except Exception:
            log = work / "core.log"
            if log.is_file():
                print(log.read_text()[-12_000:], file=sys.stderr)
            raise
