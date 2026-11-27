#!/usr/bin/env python3
"""Verify offline OIP entitlements through production REST and protected IPC/MCP."""
import argparse
import fcntl
import hashlib
import http.cookiejar
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.request

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from oip_license_issue import (
    PHP_ODP_ARTIFACT, PHP_OIP_ARTIFACT, PHP_OIP_HOLDER, PHP_OIP_LICENSE_ID, PHP_TEST_KEYS,
    decode, encode, json_line, period, proof_request, public_key, sign_fixture, write_policy,
)
from oip_local_operator import RELEASE, ROOT, WEB, session, stop, until
from oip_opcua_parity import McpClient, api, free_port


def login(binary, directory, base, principal):
    code = subprocess.check_output([
        binary, "--browser-login", "--ipc-socket", directory / "ipc.sock",
        "--ipc-credential", directory / f"{principal}.credential",
    ], text=True, timeout=10)
    browser = urllib.request.build_opener(
        urllib.request.ProxyHandler({}), urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
    )
    status, model = api(base, "/api/v2/browser/login", "POST",
                        {"code": json.loads(code)["login_code"]}, {"Origin": base}, browser)
    assert status == 200 and model["principal_id"] == principal
    return browser, model["csrf_token"]


def license_roles(binary, root):
    plan_file, ipc_file = root / "plan.json", root / "ipc.json"
    plan = json.loads(plan_file.read_text())
    ipc = json.loads(ipc_file.read_text())
    plan["roles"].append({
        "id": "entitlement-reader", "name": "Entitlement reader", "permissions": ["license_read"],
    })
    for principal, role, scope in (
        ("auditor", "entitlement-reader", {"kind": "platform"}),
        ("alternate-admin", "installation-licensing", {"kind": "platform"}),
        ("tenant-operator", "installation-licensing", {"kind": "organization", "id": "local-org"}),
    ):
        plan["principals"].append({"id": principal, "name": principal, "enabled": True})
        plan["bindings"].append({"principal_id": principal, "role_id": role, "scope": scope})
        credential = root / f"{principal}.credential"
        with os.fdopen(os.open(credential, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as stream:
            stream.write(secrets.token_bytes(32))
        ipc["clients"].append({
            "uid": os.getuid(), "credential_file": str(credential), "policy": {"principal": principal},
        })
    plan_file.write_text(json.dumps(plan))
    ipc_file.write_text(json.dumps(ipc))
    subprocess.run([binary, "--config", root / "core.json", "--provision", plan_file],
                   check=True, timeout=45, stdout=subprocess.DEVNULL)


def assert_mcp_denied(client, tool, args, code):
    answer = client.denied(tool, args)
    assert answer.get("ok"), answer
    result = answer["result"]
    assert result["isError"] is True and result["structuredContent"]["code"] == code, result


def exercise(args, directory):
    root = directory / "instance"
    private = Ed25519PrivateKey.generate()
    policy = directory / "license-policy.json"
    keys = dict(PHP_TEST_KEYS)
    kid, encoded_key = public_key(private)
    keys[kid] = encoded_key
    write_policy(policy, keys)
    now = int(time.time())
    active_usage = period("perpetual", now - 300)
    artifact_file = directory / "license-center-oip.json"
    artifact_file.write_bytes(PHP_OIP_ARTIFACT)
    proof = proof_request(PHP_OIP_ARTIFACT)
    support_only = proof_request(sign_fixture(
        private, "1" * 32, now - 300, kind="personal", usage=active_usage,
        support=period("fixed", now - 300, now + 3600),
    ))
    foreign = proof_request(sign_fixture(
        Ed25519PrivateKey.generate(), "2" * 32, now - 300, usage=active_usage,
    ))
    time_states = proof_request(sign_fixture(
        private, "3" * 32, now - 300, usage=period("fixed", now - 7200, now - 3600),
        support=period("fixed", now + 3600, now + 7200),
    ))
    no_support = proof_request(sign_fixture(
        private, "4" * 32, now - 300, usage=active_usage,
    ))
    tampered = json.loads(PHP_OIP_ARTIFACT)
    tampered["payload"] = encode(decode(tampered["payload"]).replace(
        PHP_OIP_HOLDER.encode("utf-8"), b"AndereFirma",
    ))
    changed_artifact = json_line(tampered)
    changed = proof_request(changed_artifact)
    port, sim_port = free_port(), free_port()
    while port == sim_port:
        sim_port = free_port()
    base = f"http://127.0.0.1:{port}"
    command = [sys.executable, str(ROOT / "tools/oip_local.py"), "--instance", str(root),
               "--core", str(args.core), "--simulator", str(args.simulator), "--web", str(args.web)]
    subprocess.run([*command, "setup", "--organization", "Testbetrieb", "--infrastructure", "Halle",
                    "--site", "Teststand", "--backup-directory", str(directory / "backup"),
                    "--port", str(port), "--simulator-port", str(sim_port),
                    "--license-policy", str(policy), "--commercial-license-kind", "standard"],
                   check=True, timeout=45, stdout=subprocess.DEVNULL)
    license_roles(args.core, root)
    saved = root / "core.license.json"
    clients = []
    runner = None
    tested = []

    def start():
        nonlocal runner
        runner = subprocess.Popen([*command, "run"], stdout=subprocess.PIPE, text=True)
        return session(command, runner, base)

    def mcp(principal):
        client = McpClient(args.core, root / "ipc.sock", root / f"{principal}.credential", principal)
        clients.append(client)
        return client

    def request(path="", data=None, account=None, csrf=True):
        browser, token = account or operator
        headers = {"Origin": base}
        if csrf:
            headers["x-oip-csrf"] = token
        return api(base, "/api/v2/license" + path, "POST" if data is not None else "GET",
                   data, headers, browser)

    def rotate(candidate, *confirmation):
        selection = ["--license-policy", candidate] if candidate else ["--suspend-trust"]
        return subprocess.run(
            [*command, "rotate-license-keys", *selection, *confirmation],
            capture_output=True, timeout=25,
        )

    def check_browser(screenshot, mode):
        code_grant = subprocess.check_output([
            args.core, "--browser-login", "--ipc-socket", root / "ipc.sock",
            "--ipc-credential", root / "operator.credential",
        ], text=True, timeout=10)
        subprocess.run([
            "node", ROOT / "apps/flutter/test/browser_license.mjs", base, artifact_file, screenshot, mode,
        ], input=json.loads(code_grant)["login_code"], text=True, check=True, timeout=150)

    try:
        operator = start()
        tenant = login(args.core, root, base, "tenant-operator")
        auditor = login(args.core, root, base, "auditor")
        alternate = login(args.core, root, base, "alternate-admin")
        operator_mcp, auditor_mcp, tenant_mcp = (mcp(p) for p in ("operator", "auditor", "tenant-operator"))

        def continues_after(label):
            # An existing good value alone is insufficient evidence of collection.
            started = time.time_ns() // 1_000_000

            def received():
                status, values = api(base, "/api/v2/observations?source=local-simulation",
                                     opener=operator[0])
                return status == 200 and any(
                    (item["timestamps"]["received"] or 0) > started for item in values
                )

            until(received, label)

        continues_after("Simulator did not deliver data without a license")
        tested.append("missing_proof_allows_data_collection")
        status, missing = request()
        assert status == 200 and missing["proof_state"] == "missing"
        assert missing["support"] == "unconfirmed"
        assert api(base, "/api/v2/license")[0] == 403
        assert request(account=tenant)[0] == 403
        assert request("/preview", proof, tenant)[0] == 403
        assert request(account=auditor)[1]["can_manage"] is False
        assert request("/preview", proof, auditor)[0] == 403
        assert_mcp_denied(tenant_mcp, "license_status_read", {}, "PERMISSION_DENIED")
        assert_mcp_denied(auditor_mcp, "license_proof_preview", proof, "PERMISSION_DENIED")
        tested.append("authentication_and_installation_scope_rest_mcp")
        assert request("/preview", proof, csrf=False)[0] == 403
        for bad in (changed, foreign, proof_request(PHP_ODP_ARTIFACT)):
            status, result = request("/preview", bad)
            assert status == 400 and result["code"] == "LICENSE_PROOF_INVALID"
            assert_mcp_denied(operator_mcp, "license_proof_preview", bad, "LICENSE_PROOF_INVALID")
        tested.append("csrf_changed_payload_untrusted_issuer_and_center_odp_artifact_denied")
        assert request("/apply", {"confirmation": "0" * 64})[1]["code"] == "LICENSE_CONFIRMATION_REQUIRED"
        status, preview = request("/preview", proof)
        assert status == 200 and preview["status"]["commercial"] == "active"
        assert preview["status"]["support"] == "ended"
        assert not saved.exists()
        token = {"confirmation": preview["confirmation"]}
        assert request("/apply", token, alternate)[1]["code"] == "LICENSE_CONFIRMATION_REQUIRED"
        competing = request("/preview", support_only, alternate)[1]["confirmation"]
        verified = operator_mcp.call("license_proof_apply", token)
        assert verified == request()[1]
        assert verified["license_id"] == PHP_OIP_LICENSE_ID
        assert verified["licensee"] == PHP_OIP_HOLDER
        assert verified["organization"] is None
        assert_mcp_denied(operator_mcp, "license_proof_apply", token, "LICENSE_CONFIRMATION_REQUIRED")
        assert request("/apply", {"confirmation": competing}, alternate)[0] == 400
        assert auditor_mcp.call("license_status_read") == request(account=auditor)[1]
        assert saved.read_bytes() == PHP_OIP_ARTIFACT and saved.stat().st_mode & 0o077 == 0
        tested.append("center_oip_artifact_preview_principal_binding_one_use_concurrency_and_status_parity")
        continues_after("Support expiration interrupted active data collection")
        tested.append("ended_support_allows_data_collection")
        for client in clients:
            client.close()
        clients.clear()
        stop(runner)
        operator = start()
        assert request()[1] == verified
        tested.append("verified_proof_survives_restart")
        saved.write_bytes(changed_artifact)
        assert request()[1]["proof_state"] == "invalid"
        continues_after("Invalid persisted license interrupted active data collection")
        repaired = mcp("operator").call("license_proof_preview", support_only)
        status, result = request("/apply", {"confirmation": repaired["confirmation"]})
        assert status == 200 and result["support"] == "active" and result["commercial"] == "unconfirmed"
        tested.append("damaged_proof_allows_data_collection_and_replacement")
        status, date_preview = request("/preview", time_states)
        assert status == 200 and date_preview["status"]["commercial"] == "ended"
        assert date_preview["status"]["support"] == "not_yet_active"
        assert request("/apply", {"confirmation": date_preview["confirmation"]})[0] == 200
        continues_after("Commercial entitlement ending interrupted active data collection")
        tested.append("future_and_ended_grants_do_not_stop_collection")
        status, preview = request("/preview", no_support)
        assert status == 200 and preview["status"]["support"] == "not_granted"
        status, result = request("/apply", {"confirmation": preview["confirmation"]})
        assert status == 200 and result["commercial"] == "active" and result["support"] == "not_granted"
        assert mcp("operator").call("license_status_read") == request()[1] == result
        continues_after("A verified license without support interrupted active data collection")
        tested.append("explicit_no_support_is_distinct_from_unconfirmed_and_preserves_collection")
        if args.browser:
            bundle_sha256 = hashlib.sha256((args.web / "main.dart.js").read_bytes()).hexdigest()
            with urllib.request.urlopen(base + "/main.dart.js", timeout=60) as bundle:
                assert bundle.status == 200
                assert hashlib.sha256(bundle.read()).hexdigest() == bundle_sha256
            check_browser(args.evidence.with_suffix(".png"), "import")
            tested.append("served_browser_file_picker_preview_and_explicit_confirmation")

        next_key = Ed25519PrivateKey.generate()
        next_kid, next_encoded_key = public_key(next_key)
        next_artifact = sign_fixture(next_key, "5" * 32, now - 300, usage=active_usage)
        next_proof = proof_request(next_artifact)
        next_fingerprint = hashlib.sha256(decode(next_encoded_key)).hexdigest()
        old_kid = json.loads(PHP_OIP_ARTIFACT)["kid"]
        old_fingerprint = hashlib.sha256(decode(keys[old_kid])).hexdigest()
        overlap = directory / "overlap.json"
        write_policy(overlap, {**keys, next_kid: next_encoded_key})
        status, preview = request("/preview", proof)
        assert status == 200 and request("/apply", {"confirmation": preview["confirmation"]})[0] == 200
        assert request("/preview", next_proof)[1]["code"] == "LICENSE_PROOF_INVALID"
        assert b"already running" in rotate(overlap).stderr
        stop(runner)

        config_file = root / "core.json"
        original = config_file.read_bytes()
        prior_setup = (root / "setup-complete.json").read_bytes()
        with (root / "core.sqlite.oip-lock").open("rb") as database_lock:
            fcntl.flock(database_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            assert b"Stop the Core" in rotate(overlap).stderr
        review = rotate(overlap)
        assert review.returncode == 0, review.stderr
        proposal = json.loads(review.stdout)
        assert proposal["status"] == "review" and proposal["instance"] == str(root)
        assert proposal["added_fingerprints"] == [next_fingerprint]
        assert proposal["removed_fingerprints"] == [] and old_fingerprint in proposal["retained_fingerprints"]
        assert config_file.read_bytes() == original
        assert rotate(overlap, "--confirm", "0" * 64).returncode != 0
        config_file.write_bytes(original + b"\n")
        assert rotate(overlap, "--confirm", proposal["confirmation"]).returncode != 0
        assert config_file.read_bytes() == original + b"\n"
        config_file.write_bytes(original)
        original_policy = overlap.read_bytes()
        overlap.write_bytes(original_policy + b"\n")
        assert rotate(overlap, "--confirm", proposal["confirmation"]).returncode != 0
        overlap.write_bytes(original_policy)
        invalid = directory / "changed-rights.json"
        invalid.write_bytes(json_line({**json.loads(overlap.read_bytes()), "rights": {}}))
        assert b"existing license kinds, rights" in rotate(invalid).stderr
        assert config_file.read_bytes() == original and saved.read_bytes() == PHP_OIP_ARTIFACT
        applied = rotate(overlap, "--confirm", proposal["confirmation"])
        assert applied.returncode == 0 and json.loads(applied.stdout)["status"] == "applied", applied.stderr
        assert config_file.stat().st_mode & 0o077 == 0
        assert json.loads(config_file.read_bytes()) == {
            **json.loads(original), "license_policy": overlap.read_text(),
        }
        assert (root / "setup-complete.json").read_bytes() == prior_setup
        assert json.loads(rotate(overlap).stdout)["status"] == "unchanged"
        operator = start()
        assert request()[1] == verified
        status, preview = request("/preview", next_proof)
        assert status == 200 and preview["status"]["commercial"] == "active"
        assert request("/apply", {"confirmation": preview["confirmation"]})[0] == 200
        assert saved.read_bytes() == next_artifact
        tested.append("offline_key_rotation_requires_stopped_instance_and_current_confirmation")
        tested.append("overlapping_keys_verify_existing_and_reissued_proofs")

        status, preview = request("/preview", proof)
        assert status == 200 and request("/apply", {"confirmation": preview["confirmation"]})[0] == 200
        stop(runner)
        successor = directory / "successor.json"
        write_policy(successor, {next_kid: next_encoded_key})
        retirement = json.loads(rotate(successor).stdout)
        assert old_fingerprint in retirement["removed_fingerprints"]
        assert retirement["added_fingerprints"] == []
        assert retirement["retained_fingerprints"] == [next_fingerprint]
        applied = rotate(successor, "--confirm", retirement["confirmation"])
        assert applied.returncode == 0 and json.loads(applied.stdout)["status"] == "applied", applied.stderr
        assert saved.read_bytes() == PHP_OIP_ARTIFACT
        operator = start()
        assert request()[1]["proof_state"] == "invalid"
        assert mcp("operator").call("license_status_read") == request()[1]
        assert request("/preview", proof)[1]["code"] == "LICENSE_PROOF_INVALID"
        continues_after("Retiring a key interrupted data collection")
        status, preview = request("/preview", next_proof)
        assert status == 200 and request("/apply", {"confirmation": preview["confirmation"]})[0] == 200
        assert request()[1]["license_id"] == "5" * 32
        assert mcp("operator").call("license_status_read") == request()[1]
        tested.append("removing_key_rejects_its_proof_without_stopping_collection")

        assert b"already running" in rotate(None).stderr
        stop(runner)
        suspended_policy = directory / "suspended.json"
        write_policy(suspended_policy, {})
        assert b"requires at least one trusted key" in rotate(suspended_policy).stderr
        suspension = json.loads(rotate(None).stdout)
        assert suspension["trust_suspended"] is True
        assert suspension["removed_fingerprints"] == [next_fingerprint]
        assert suspension["added_fingerprints"] == suspension["retained_fingerprints"] == []
        applied = rotate(None, "--confirm", suspension["confirmation"])
        assert applied.returncode == 0 and json.loads(applied.stdout)["status"] == "applied", applied.stderr
        assert json.loads(json.loads(config_file.read_bytes())["license_policy"]) == json.loads(
            suspended_policy.read_bytes()
        )
        assert saved.read_bytes() == next_artifact
        operator = start()
        status, suspended = request()
        assert status == 200 and suspended == {
            "proof_state": "suspended", "commercial": "unconfirmed", "support": "unconfirmed",
            "can_manage": False, "licensee": None, "license_id": None, "organization": None,
        }
        suspension_mcp = mcp("operator")
        assert suspension_mcp.call("license_status_read") == suspended
        assert request("/preview", next_proof)[1]["code"] == "LICENSE_UNAVAILABLE"
        assert_mcp_denied(suspension_mcp, "license_proof_preview", next_proof, "LICENSE_UNAVAILABLE")
        continues_after("Suspended issuer trust interrupted data collection")
        tested.append("suspending_the_last_issuer_key_preserves_data_and_denies_proofs")
        if args.browser:
            check_browser(args.evidence.with_name(args.evidence.stem + "-suspended.png"), "suspended")
            tested.append("served_browser_distinguishes_suspended_trust_and_disables_import")

        stop(runner)
        replacement_key = Ed25519PrivateKey.generate()
        replacement_policy = directory / "replacement.json"
        write_policy(replacement_policy, dict([public_key(replacement_key)]))
        reenable = json.loads(rotate(replacement_policy).stdout)
        assert reenable["trust_suspended"] is False
        assert reenable["removed_fingerprints"] == [] and len(reenable["added_fingerprints"]) == 1
        applied = rotate(replacement_policy, "--confirm", reenable["confirmation"])
        assert applied.returncode == 0 and json.loads(applied.stdout)["status"] == "applied", applied.stderr
        operator = start()
        assert request()[1]["proof_state"] == "invalid"
        assert request("/preview", next_proof)[1]["code"] == "LICENSE_PROOF_INVALID"
        replacement = proof_request(sign_fixture(replacement_key, "6" * 32, now - 300, usage=active_usage))
        status, preview = request("/preview", replacement)
        assert status == 200 and request("/apply", {"confirmation": preview["confirmation"]})[0] == 200
        assert request()[1]["license_id"] == "6" * 32
        tested.append("approved_replacement_recovers_verification_without_retrusting_the_removed_key")
    finally:
        for client in clients:
            client.close()
        stop(runner)
    return tested


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core", type=Path, default=RELEASE / "oip-server")
    parser.add_argument("--simulator", type=Path, default=RELEASE / "oip-simulated-server")
    parser.add_argument("--web", type=Path, default=WEB)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--browser", action="store_true",
                        help="Also exercise the compiled browser UI with Playwright")
    args = parser.parse_args()
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="oip-license-", dir="/private/tmp") as work:
        tested = exercise(args, Path(work))
    receipt = {
        "status": "PASS", "platform": sys.platform, "architecture": os.uname().machine,
        "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_tree": subprocess.check_output(
            ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True,
        ).strip(),
        "core_sha256": hashlib.sha256(args.core.read_bytes()).hexdigest(),
        "main_dart_js_sha256": hashlib.sha256((args.web / "main.dart.js").read_bytes()).hexdigest()
        if args.browser else None,
        "license_center_oip_fixture_sha256": hashlib.sha256(PHP_OIP_ARTIFACT).hexdigest(),
        "license_center_odp_fixture_sha256": hashlib.sha256(PHP_ODP_ARTIFACT).hexdigest(),
        "tested": tested,
    }
    args.evidence.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
