#!/usr/bin/env python3
"""Local, isolated macOS rehearsal of encrypted recovery with the real OIP daemon."""

import argparse
import http.cookiejar
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError
from urllib.request import HTTPCookieProcessor, Request, build_opener

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools/oip_ops.py"
sys.path.insert(0, str(TOOL.parent))
from oip_recovery import encrypt_files  # noqa: E402


def port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def wait_for(predicate, message, seconds=24):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if result := predicate():
            return result
        time.sleep(0.25)
    raise AssertionError(message)


class Browser:
    def __init__(self, http_port):
        self.origin = f"http://127.0.0.1:{http_port}"
        self.opener = build_opener(HTTPCookieProcessor(http.cookiejar.CookieJar()))
        self.csrf = None

    def call(self, path, body=None, method=None, expected=200):
        headers = {"Origin": self.origin}
        if self.csrf:
            headers["x-oip-csrf"] = self.csrf
        if body is not None:
            headers["Content-Type"] = "application/json"
        req = Request(self.origin + "/api/v2/" + path,
                      data=json.dumps(body).encode() if body is not None else None,
                      method=method, headers=headers)
        try:
            answer = self.opener.open(req, timeout=5)
        except HTTPError as error:
            answer = error
        with answer:
            assert answer.status == expected, (path, answer.status)
            return json.load(answer)

    def login(self, binary, ipc, credential):
        raw = subprocess.check_output(
            [binary, "--browser-login", "--ipc-socket", ipc, "--ipc-credential", credential],
            stderr=subprocess.DEVNULL, timeout=10,
        )
        session = self.call("browser/login", {"code": json.loads(raw)["login_code"]})
        assert session["principal_id"] == "reader-org-a"
        self.csrf = session["csrf_token"]


def count(db):
    result = subprocess.check_output(["/usr/bin/sqlite3", "-batch", db,
                                      "SELECT count(*) FROM observations;"], timeout=5)
    return int(result.strip())


def rehearsal(args, root):
    http_port, opcua_port, restored_port = port(), port(), port()
    while len({http_port, opcua_port, restored_port}) < 3:
        opcua_port, restored_port = port(), port()
    database = root / "core.sqlite"
    config = root / "core.json"
    ipc = root / "ipc.json"
    credential = root / "operator.credential"
    plan = root / "plan.json"
    vault = root / "backup.oip"
    clone = root / "clone"
    secret = secrets.token_urlsafe(36)
    put = lambda path, data: path.write_text(json.dumps(data))
    core_configuration = {"database": str(database), "http_port": http_port, "sources": [
        {"id": "source-a", "name": "Recovery fixture OPC-UA",
         "endpoint": f"opc.tcp://127.0.0.1:{opcua_port}"},
    ]}
    if args.read_only_profile:
        core_configuration["opcua_read_only"] = True
    put(config, core_configuration)
    put(ipc, {"socket": str(root / "s"), "clients": [{
        "uid": os.getuid(), "credential_file": str(credential),
        "policy": {"principal": "reader-org-a"},
    }]})
    plan_data = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
    plan_data["sources"] = plan_data["sources"][:1]
    plan_data["services"] = []
    plan_data["bindings"] = [item for item in plan_data["bindings"] if item["scope"]["kind"] != "source"]
    put(plan, plan_data)

    def tool(*words, expected=0, secured_by=None, binary=args.binary):
        command = [sys.executable, str(TOOL), "--config", str(config),
                   "--ipc-config", str(ipc), "--state-dir", str(root / "state"),
                   "--binary", str(binary), *map(str, words)]
        if secured_by is not None:
            command += ["--passphrase-fd", "0"]
        completed = subprocess.run(
            command, input=(secured_by + "\n") if secured_by else None,
            capture_output=True, text=True, timeout=60,
        )
        assert completed.returncode == expected, (words[0], completed.stderr, completed.stdout)
        return json.loads(completed.stdout) if completed.stdout else completed.stderr

    base_time = time.monotonic()
    simulator = subprocess.Popen(
        [args.simulator, "--port", str(opcua_port), "--tick-ms", "200"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        tool("provision-plan", "--plan", plan)
        tool("start")
        browser = Browser(http_port)
        browser.call("inventory/devices", expected=403)
        browser.login(args.binary, root / "s", credential)
        devices = browser.call("inventory/devices")["items"]
        revoked, active = secrets.token_hex(32), secrets.token_hex(32)
        browser.call("browser/pairing", {"credential": revoked})
        paired_id = browser.call("browser/device-credentials")["items"][0]["id"]
        browser.login(args.binary, root / "s", credential)
        browser.call("browser/pairing", {"credential": active})
        browser.call("browser/device-credentials/" + paired_id, method="DELETE")
        Browser(http_port).call("browser/device-login", {"credential": revoked}, expected=403)
        wait_for(lambda: count(database) >= 5, "Original OIP did not collect simulator values.")
        live_refusal = tool("recovery-backup", "--output", vault, secured_by=secret, expected=2)
        assert "Stop the Core" in live_refusal and not vault.exists()
        tool("stop")
        original_points = count(database)

        original_ipc = json.loads(ipc.read_text())
        ipc_with_multiple_owners = {**original_ipc, "clients": [
            *original_ipc["clients"], {**original_ipc["clients"][0], "uid": os.getuid() + 1},
        ]}
        put(ipc, ipc_with_multiple_owners)
        denial = tool("recovery-backup", "--output", vault, secured_by=secret, expected=2)
        assert "single local IPC owner" in denial and not vault.exists()
        put(ipc, original_ipc)
        backup = tool("recovery-backup", "--output", vault, secured_by=secret)
        assert backup["status"] == "encrypted_backup_created"
        assert backup["database_schema"] == 8 and backup["restore_tested"] is False
        assert vault.stat().st_mode & 0o077 == 0
        for sensitive in (credential.read_bytes(), b"SQLite format 3", b"Recovery fixture OPC-UA"):
            assert sensitive not in vault.read_bytes()
        tool("recovery-backup", "--output", vault, secured_by=secret, expected=2)

        def reject(source, passphrase=secret, binary=args.binary):
            tool("recovery-restore", "--source", source, "--restore-dir", clone,
                 secured_by=passphrase, binary=binary, expected=2)
            assert not clone.exists()

        reject(vault, passphrase=secrets.token_urlsafe(36))
        tampered = root / "tampered.oip"
        data = bytearray(vault.read_bytes())
        data[len(data) // 2] ^= 1
        tampered.write_bytes(data)
        reject(tampered)
        reject(vault, binary=Path("/usr/bin/true"))
        incomplete = root / "incomplete.oip"
        manifest = {
            "format": backup["format"], "database_schema": 8,
            "core_sha256": backup["core_sha256"], "members": {"core.sqlite": 4096},
        }
        encrypt_files({}, json.dumps(manifest).encode(), incomplete, (secret + "\n").encode())
        reject(incomplete)

        restored = tool("recovery-restore", "--source", vault, "--restore-dir", clone, secured_by=secret)
        assert restored["status"] == "restored_inactive"
        restored_db = clone / "instance/core.sqlite"
        recovered_points = count(restored_db)
        assert recovered_points == original_points
        original_bytes = restored_db.read_bytes()
        tool("recovery-restore", "--source", vault, "--restore-dir", clone, secured_by=secret, expected=2)
        assert restored_db.read_bytes() == original_bytes

        assert not (clone / "instance/core.json").exists()
        tool("recovery-start", "--restore-dir", clone, "--port", restored_port,
             "--test-source-port", restored_port, expected=2)
        started = tool("recovery-start", "--restore-dir", clone, "--port", restored_port)
        assert started["mode"] == "isolated_recovery" and started["test_source_port"] is None
        tool("recovery-start", "--restore-dir", clone, "--port", port(), expected=2)
        recovered_dir = clone / "instance"
        recovered_data = json.loads((recovered_dir / "recovery.json").read_text())
        recovered_cred = recovered_dir / recovered_data["ipc"]["clients"][0]["credential_file"]
        assert credential.read_bytes() == recovered_cred.read_bytes()
        again = Browser(restored_port)
        again.call("inventory/devices", expected=403)
        again.login(args.binary, recovered_dir / "oip.sock", recovered_cred)
        assert [row["record"]["device"]["id"] for row in again.call("inventory/devices")["items"]] == [
            row["record"]["device"]["id"] for row in devices
        ]
        paired = again.call("browser/device-credentials")["items"]
        assert len(paired) == 1 and paired[0]["id"] != paired_id
        Browser(restored_port).call("browser/device-login", {"credential": revoked}, expected=403)
        active_session = Browser(restored_port).call("browser/device-login", {"credential": active})
        assert active_session["principal_id"] == "reader-org-a"
        again.call("browser/pairing", {"credential": revoked}, expected=403)
        time.sleep(2.5)
        assert count(restored_db) == original_points
        tool("recovery-stop", "--restore-dir", clone)

        tool("recovery-start", "--restore-dir", clone, "--port", restored_port,
             "--test-source-port", opcua_port)
        new_count = wait_for(lambda: (n if (n := count(restored_db)) > original_points else None),
                             "Approved restored OPC-UA test connection did not collect.")
        tool("recovery-stop", "--restore-dir", clone)
        assert count(database) == original_points

        return {
            "status": "PASS",
            "platform": os.uname().machine + " macOS",
            "core_sha256": backup["core_sha256"],
            "database_schema": 8,
            "encrypted_format": "OpenPGP AES-256/OCB",
            "checks": ["live_backup_refused", "backup_authenticated", "exact_core_match",
                       "wrong_passphrase_refused", "modified_ciphertext_refused",
                       "incomplete_authenticated_archive_refused", "existing_target_preserved",
                       "multi_os_user_backup_refused",
                       "inventory_and_scoped_identity_preserved", "active_pairing_preserved",
                       "revocation_and_repair_denial_preserved",
                       "fresh_clone_outbound_blocked", "only_explicit_loopback_reconnected"],
            "identical_restored_observations": original_points,
            "observations_after_approved_restart": new_count,
            "duration_seconds": round(time.monotonic() - base_time, 2),
        }
    finally:
        try:
            if (clone / "instance/recovery.json").is_file():
                tool("recovery-stop", "--restore-dir", clone)
        finally:
            try:
                tool("stop")
            finally:
                simulator.terminate()
                simulator.wait(timeout=15)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, type=lambda raw: Path(raw).resolve(strict=True))
    parser.add_argument("--simulator", required=True, type=lambda raw: Path(raw).resolve(strict=True))
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--read-only-profile", action="store_true",
                        help="verify the supported Core's OPC-UA read-only configuration")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("This rehearsal verifies the macOS recovery sandbox.")
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="oip-recovery-", dir="/private/tmp") as temporary:
        result = rehearsal(args, Path(temporary))
    output = json.dumps(result, indent=2) + "\n"
    if args.receipt:
        args.receipt.write_text(output)
    print(output, end="")


if __name__ == "__main__":
    main()
