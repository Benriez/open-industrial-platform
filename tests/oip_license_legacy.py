#!/usr/bin/env python3
"""Upgrade the original managed local profile using the current shipped tools."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import (
    Encoding, NoEncryption, PrivateFormat, PublicFormat,
)

from oip_license_e2e import assert_mcp_denied, login
from oip_license_issue import PHP_OIP_ARTIFACT, PHP_TEST_KEYS, proof_request, write_policy
from oip_local_operator import RELEASE, ROOT, WEB, session, stop, until
from oip_opcua_parity import McpClient, api, free_port
from oip_ops import sqlite_query

OLD_SETUP = "b1474c414dbd73809fde10d413dd4d9996fcd740:tools/oip_local.py"
ROLE = "installation-licensing"


def sql_state(database):
    changed_tables = {"read_roles", "role_bindings", "provision_meta", "provisioning_audit"}
    preserved = [
        line for line in sqlite_query(database, ".dump").splitlines()
        if not (line.startswith("INSERT INTO ")
                and line.split()[2].strip('"') in changed_tables)
    ]

    def rows(statement):
        return [tuple(line.split("|")) for line in sqlite_query(database, statement).splitlines()]

    roles = rows("SELECT * FROM read_roles ORDER BY id")
    bindings = rows("SELECT * FROM role_bindings ORDER BY principal_id,role_id,scope_kind,scope_id")
    audit = rows("SELECT operation,outcome FROM provisioning_audit ORDER BY sequence")
    revision = int(sqlite_query(database, "SELECT revision FROM provision_meta WHERE id=1"))
    return preserved, roles, bindings, audit, revision


def exercise(args, temporary):
    root = temporary / "instance"
    old_tool = temporary / "legacy-operator.py"
    old_tool.write_bytes(subprocess.check_output(["git", "show", OLD_SETUP], cwd=ROOT, timeout=20))
    flags = ["--instance", str(root), "--core", str(args.core), "--web", str(args.web),
             "--simulator", str(args.simulator)]
    command = [sys.executable, "-B", ROOT / "tools/oip_local.py", *flags]
    port, sim_port = free_port(), free_port()
    while port == sim_port:
        sim_port = free_port()
    setup = ["setup", "--organization", "Testbetrieb", "--infrastructure", "Halle",
             "--site", "Teststand", "--backup-directory", str(temporary / "backup"),
             "--port", str(port), "--simulator-port", str(sim_port)]
    subprocess.run([sys.executable, "-B", old_tool, *flags, *setup], check=True, timeout=60,
                   env={**os.environ, "PYTHONPATH": str(ROOT / "tools")}, stdout=subprocess.DEVNULL)

    def provision(plan):
        effective = temporary / "effective-plan.json"
        effective.write_text(json.dumps(plan))
        subprocess.run([args.core, "--config", root / "core.json", "--provision", effective],
                       check=True, timeout=40, stdout=subprocess.DEVNULL)

    def grant(*options):
        return subprocess.run([*command, "enable-license-management", *options],
                              capture_output=True, text=True, timeout=40)

    def review():
        result = grant()
        assert result.returncode == 0, result.stderr
        body = json.loads(result.stdout)
        assert body["status"] == "review" and body["instance"] == str(root)
        assert body["principal_id"] == "operator" and body["role_id"] == ROLE
        assert body["scope"] == {"kind": "platform"}
        assert set(body["permissions"]) == {"license_read", "license_manage"}
        return body["confirmation"]

    def state_error(result, text):
        assert result.returncode != 0 and text in result.stderr, result.stderr

    plan = json.loads((root / "plan.json").read_bytes())
    assert all(role["id"] != ROLE for role in plan["roles"])
    database = root / "core.sqlite"
    base = f"http://127.0.0.1:{port}"
    path = "/api/v2/license"
    runner = subprocess.Popen([*command, "run"], stdout=subprocess.PIPE, text=True)
    try:
        browser, _ = session(command, runner, base)
        assert api(base, path, opener=browser)[0] == 403
        until(lambda: api(base, "/api/v2/observations?source=local-simulation", opener=browser)[1],
              "legacy profile did not collect observations")
        state_error(grant(), "already running")
    finally:
        stop(runner)

    policy = temporary / "policy.json"
    write_policy(policy, PHP_TEST_KEYS)
    signer = Ed25519PrivateKey.generate()
    secret = temporary / "signing.pem"
    secret.touch(mode=0o600)
    secret.write_bytes(signer.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, NoEncryption()))
    public = temporary / "update.pem"
    public.write_bytes(signer.public_key().public_bytes(Encoding.PEM, PublicFormat.SubjectPublicKeyInfo))
    bundle = temporary / "current.zip"
    update = [sys.executable, "-B", ROOT / "tools/oip_update.py", "--bundle", bundle]
    subprocess.run([*update, "--prepare", "--signing-key", secret,
                    "--binary", args.core, "--web", args.web, "--simulator", args.simulator,
                    "--revision", "legacy-upgrade", "--release-version", "1.0.0",
                    "--database-schema", "8", "--license-policy", policy,
                    "--commercial-license-kind", "standard"],
                   check=True, timeout=120, stdout=subprocess.DEVNULL)
    legacy_state = sql_state(database)
    install = subprocess.check_output([*update, "--instance", root, "--public-key", public],
                                      text=True, timeout=120)
    assert json.loads(install)["the_status"] == "UPDATED"
    assert sql_state(database) == legacy_state
    command = [sys.executable, "-B", root / "current/tools/oip_local.py", "--instance", str(root)]
    command_policy = [*command, "install-license-policy", "--package-public-key", public]
    outcome = json.loads(subprocess.check_output(command_policy, text=True, timeout=45))
    subprocess.run([*command_policy, "--confirm", outcome["confirmation"]], check=True,
                   timeout=45, stdout=subprocess.DEVNULL)

    protected_files = ("setup.json", "setup-complete.json", "core.json", "ipc.json",
                       "plan.json", "operator.credential")
    protected = {name: (root / name).read_bytes() for name in protected_files}
    before_review = sql_state(database)
    original_token = review()
    config = root / "core.json"
    config.write_bytes(protected["core.json"] + b"\n")
    state_error(grant("--confirm", original_token), "installation changed")
    config.write_bytes(protected["core.json"])
    assert sql_state(database) == before_review

    # The current hierarchy can differ from the original setup file.
    plan["organizations"].append({"id": "other-org", "name": "Andere Organisation"})
    plan["principals"].append({"id": "other-operator", "name": "Anderer Betreiber", "enabled": True})
    plan["bindings"].append({
        "principal_id": "other-operator", "role_id": "local-operator",
        "scope": {"kind": "organization", "id": "other-org"},
    })
    provision(plan)
    current = sql_state(database)
    state_error(grant("--confirm", original_token), "installation changed")
    assert sql_state(database) == current
    token = review()
    assert token != original_token and sql_state(database) == current
    result = grant("--confirm", token)
    assert result.returncode == 0 and json.loads(result.stdout)["status"] == "applied", result.stderr
    after = sql_state(database)
    assert after[0] == current[0]
    assert set(after[1]) - set(current[1]) == {(ROLE, "OIP-Lizenzverwaltung", '["license_read","license_manage"]')}
    assert set(after[2]) - set(current[2]) == {("operator", ROLE, "platform", "")}
    assert set(current[1]).issubset(after[1]) and set(current[2]).issubset(after[2])
    assert after[3] == current[3] + [("provision_local_license_role", "committed")]
    assert after[4] == current[4] + 1
    assert {name: (root / name).read_bytes() for name in protected_files} == protected
    assert json.loads(grant("--confirm", token).stdout)["status"] == "unchanged"
    assert sql_state(database) == after

    ipc_file = root / "ipc.json"
    ipc = json.loads(ipc_file.read_bytes())
    credential = root / "other-operator.credential"
    with os.fdopen(os.open(credential, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as output:
        output.write(os.urandom(32))
    ipc["clients"].append({"uid": os.getuid(), "credential_file": str(credential),
                           "policy": {"principal": "other-operator"}})
    ipc_file.write_text(json.dumps(ipc))
    clients = []
    runner = subprocess.Popen([*command, "run"], stdout=subprocess.PIPE, text=True)
    try:
        browser, csrf = session(command, runner, base)
        operator_status = api(base, path, opener=browser)
        assert operator_status[0] == 200 and operator_status[1]["can_manage"] is True
        assert operator_status[1]["proof_state"] == "missing"
        for principal in ("operator", "other-operator"):
            clients.append(McpClient(args.core, root / "ipc.sock", root / f"{principal}.credential", principal))
        assert clients[0].call("license_status_read") == operator_status[1]
        other, _ = login(args.core, root, base, "other-operator")
        proof = proof_request(PHP_OIP_ARTIFACT)
        assert api(base, path, opener=other)[0] == 403
        assert_mcp_denied(clients[1], "license_proof_preview", proof, "PERMISSION_DENIED")
        headers = {"Origin": base, "x-oip-csrf": csrf}
        status, preview = api(base, path + "/preview", "POST", proof, headers, browser)
        assert status == 200
        status, applied = api(base, path + "/apply", "POST",
                              {"confirmation": preview["confirmation"]}, headers, browser)
        assert status == 200 and applied["commercial"] == "active"
        since = time.time_ns() // 1_000_000

        def new_values():
            code, values = api(base, "/api/v2/observations?source=local-simulation", opener=browser)
            return code == 200 and any((item["timestamps"]["received"] or 0) > since for item in values)

        until(new_values, "upgraded profile did not continue collecting observations")
    finally:
        for client in clients:
            client.close()
        stop(runner)

    # The targeted upgrade must not restore a subsequently revoked permission.
    plan["roles"].append({"id": ROLE, "name": "OIP-Lizenzverwaltung",
                          "permissions": ["license_read", "license_manage"]})
    provision(plan)
    state_error(grant(), "already exists with other assignments")
    return [
        "original historical setup creates managed state without license rights",
        "current signed ZIP installs offline while preserving the pre-license database",
        "running Core and stale config or hierarchy confirmations are rejected",
        "only the original operator receives license rights; exact role and revision are audited once",
        "old setup files, identity, data and other tenants are preserved",
        "license proof works through REST and MCP authorization stays separated after restart",
        "data collection continues and a subsequently removed binding stays removed",
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core", type=Path, default=RELEASE / "oip-server")
    parser.add_argument("--simulator", type=Path, default=RELEASE / "oip-simulated-server")
    parser.add_argument("--web", type=Path, default=WEB)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="oip-legacy-role-", dir="/private/tmp") as directory:
        steps = exercise(args, Path(directory))
    receipt = {
        "status": "PASS", "revision": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "tree": subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip(),
        "core_sha256": hashlib.sha256(args.core.read_bytes()).hexdigest(),
        "legacy_setup": OLD_SETUP, "cases": steps,
    }
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(json.dumps(receipt, indent=2) + "\n")
    print(args.evidence)


if __name__ == "__main__":
    main()
