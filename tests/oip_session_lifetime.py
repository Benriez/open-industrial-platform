#!/usr/bin/env python3
"""Check one-time-code expiry and session revocation against a disposable Core.

The optional timed probe verifies that an idle session expires. The device test
covers revocation across a complete restart and an older credential snapshot.

Usage:
  python3 tests/oip_session_lifetime.py [--evidence DIR] [--skip-session-wait] [--device-sign-ins-only]
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
GRANT_TTL = 120
SESSION_IDLE_TTL = 1800


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def request(base, path, method="GET", body=None, headers=None, opener=None):
    data = json.dumps(body).encode() if body is not None else None
    call = urllib.request.Request(base + path, data=data, method=method)
    call.add_header("Content-Type", "application/json")
    for key, value in (headers or {}).items():
        call.add_header(key, value)
    send = opener.open if opener else urllib.request.urlopen
    try:
        with send(call, timeout=30) as answer:
            return answer.status, json.loads(answer.read().decode() or "{}")
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode() or "{}")



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

def verify_device_sign_ins(base, issue, tool, credential_file, report):
    def client():
        jar = http.cookiejar.CookieJar()
        return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

    def login(opener, code):
        status, info = request(base, "/api/v2/browser/login", "POST",
                               {"code": code}, {"Origin": base}, opener)
        assert status == 200, info
        return {"Origin": base, "x-oip-csrf": info["csrf_token"]}

    def paired(opener):
        status, result = request(base, "/api/v2/browser/device-credentials", opener=opener)
        assert status == 200, result
        return result["items"]

    def pair(opener, headers, key):
        return request(base, "/api/v2/browser/pairing", "POST",
                       {"credential": key}, headers, opener)[0]

    def device_login(opener, key):
        return request(base, "/api/v2/browser/device-login", "POST",
                       {"credential": key}, {"Origin": base}, opener)

    owner, other = client(), client()
    first, second, foreign = (secrets.token_hex(32) for _ in range(3))
    owner_headers = login(owner, issue())
    assert pair(owner, owner_headers, first) == 200
    assert pair(owner, owner_headers, second) == 403
    first_row, = paired(owner)
    assert not first_row["current"]
    owner_headers = login(owner, issue())
    assert pair(owner, owner_headers, second) == 200
    other_headers = login(other, issue("reader-org-b"))
    assert pair(other, other_headers, foreign) == 200
    assert len(paired(other)) == 1 and paired(other)[0]["id"] != first_row["id"]
    assert len(paired(owner)) == 2

    path = "/api/v2/browser/device-credentials/" + first_row["id"]
    assert request(base, path, "PATCH", {"label": "Office Mac"},
                   owner_headers, owner)[0] == 200
    assert any(item["label"] == "Office Mac" for item in paired(owner))
    assert request(base, path, "DELETE", headers=other_headers, opener=other)[0] == 404
    assert request(base, path, "DELETE", headers={"Origin": base}, opener=owner)[0] == 403
    assert request(base, path, "DELETE", headers={**owner_headers, "Origin": "http://localhost"},
                   opener=owner)[0] == 403
    assert request(base, "/api/v2/browser/device-credentials")[0] == 403
    original_credentials = credential_file.read_bytes()
    old_backup = credential_file.parent / "before-revocation.sqlite"
    tool("backup", "--output", str(old_backup))

    device, second_session = client(), client()
    status, info = device_login(device, first)
    assert status == 200 and info["principal_id"] == "reader-org-a"
    assert any(row["id"] == first_row["id"] and row["current"] for row in paired(device))
    assert pair(device, {"Origin": base, "x-oip-csrf": info["csrf_token"]},
                secrets.token_hex(32)) == 403
    assert device_login(second_session, second)[0] == 200
    assert request(base, "/api/v2/organizations", opener=device)[0] == 200
    report["steps"].append("fresh one-use proof, scoped names, and ownership checks passed")

    # Keep the same authorized data stream open across the revocation.
    with device.open(base + "/api/v2/stream", timeout=10) as stream:
        assert stream.readline().strip() == b"event: snapshot"
        while stream.readline().strip():
            pass
        status, result = request(base, path, "DELETE", headers=owner_headers, opener=owner)
        assert status == 200 and result == {"revoked": True, "current_session_revoked": False}
        assert stream.readline().strip() == b"event: error"
        assert b"event: snapshot" not in stream.read()
        assert request(base, "/api/v2/organizations", opener=device)[0] == 403
        assert device_login(client(), first)[0] == 403
        assert request(base, "/api/v2/organizations", opener=second_session)[0] == 200
    assert request(base, path, "DELETE", headers=owner_headers, opener=owner)[0] == 200
    assert pair(owner, login(owner, issue()), first) == 403
    report["steps"].append("revocation denies the key, its active session, and its existing stream")

    tool("restart")
    assert device_login(client(), first)[0] == 403
    assert device_login(client(), second)[0] == 200
    assert device_login(client(), foreign)[0] == 200
    report["steps"].append("revocation survives a full Core restart and other devices still sign in")

    tool("stop")
    tool("restore", "--source", str(old_backup))
    credential_file.write_bytes(original_credentials)
    tool("start")
    assert device_login(client(), first)[0] == 403
    assert device_login(client(), foreign)[0] == 200
    current = client()
    status, info = device_login(current, second)
    assert status == 200, info
    row, = paired(current)
    headers = {"Origin": base, "x-oip-csrf": info["csrf_token"]}
    status, result = request(base, "/api/v2/browser/device-credentials/" + row["id"],
                             "DELETE", headers=headers, opener=current)
    assert status == 200 and result == {"revoked": True, "current_session_revoked": True}
    assert request(base, "/api/v2/organizations", opener=current)[0] == 403
    report["steps"].append("restoring an old database and credential snapshot cannot undo revocation")
    report["steps"].append("self-revocation signs out and leaves other principals active")

    journal = credential_file.parent / "core.sqlite.security-audit" / "events.jsonl"
    records = [json.loads(line)["event"] for line in journal.read_text().splitlines()]
    for action in ("pair", "rename", "revoke"):
        group = {row["outcome"]: row for row in records
                 if row.get("action") == action and row.get("target") == first_row["id"]}
        assert group["started"]["principal"] == "reader-org-a"
        assert group["succeeded"]["principal"] == "reader-org-a"
    assert not any(secret in journal.read_text() for secret in (first, second, foreign))
    assert journal.stat().st_mode & 0o777 == 0o600
    report["steps"].append("pairing, naming and revocation leave durable audit events without secrets")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-session-lifetime"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    parser.add_argument("--skip-session-wait", action="store_true")
    parser.add_argument("--device-sign-ins-only", action="store_true")
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-session-lifetime-v1", "steps": [],
              "device_sign_ins_only": args.device_sign_ins_only}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-lifetime-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    try:
        port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        credential_file = work / "device-credentials.json"
        (work / "core.json").write_text(json.dumps({
            "browser_credentials_file": str(credential_file),
            "database": str(work / "core.sqlite"), "http_port": port,
            "sources": [{"id": f"source-{letter}", "name": f"Local simulation {letter}",
                         "endpoint": f"opc.tcp://127.0.0.1:{15860 + index}", "namespace": 2}
                        for index, letter in enumerate("abcd")],
            "legacy_single_infrastructure": False,
        }, indent=2))
        credentials = {}
        for principal in ("reader-org-a", "reader-org-b"):
            credential = work / (principal + ".credential")
            credential.write_bytes(secrets.token_bytes(32))
            credential.chmod(0o600)
            credentials[principal] = credential
        (work / "ipc.json").write_text(json.dumps({
            "socket": str(work / "s"), "max_sessions": 16,
            "clients": [{"uid": os.getuid(), "credential_file": str(credential),
                         "policy": {"principal": principal}}
                        for principal, credential in credentials.items()],
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
        time.sleep(3)
        report["steps"].append("the instance runs")

        def issue(principal="reader-org-a"):
            return json.loads(subprocess.check_output(
                [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
                 "--ipc-credential", str(credentials[principal])], text=True))["login_code"]

        base = f"http://127.0.0.1:{port}"
        verify_device_sign_ins(base, issue, tool, credential_file, report)
        if not args.device_sign_ins_only:
            # 1. the lifetime of the one-time code
            expired_code = issue()
            report["the_code_issued_at"] = time.time()
            print("the code is issued; the rehearsal waits for its lifetime "
                  f"({GRANT_TTL} s)", flush=True)
            time.sleep(GRANT_TTL + 10)
            status, answer = request(base,
                                     "/api/v2/browser/login", "POST", {"code": expired_code},
                                     {"Origin": base})
            report["the_expired_code"] = {"status": status, "code": answer.get("code"),
                                          "waited_seconds": GRANT_TTL + 10}
            assert status == 403, f"the expired code was accepted: {status}"
            report["steps"].append("the expired one-time code is refused")

            # 2. the lifetime of the session
            fresh_code = issue()
            jar = http.cookiejar.CookieJar()
            opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
            status, session = request(base, "/api/v2/browser/login", "POST",
                                      {"code": fresh_code}, {"Origin": base}, opener)
            assert status == 200, session
            cookie, = jar
            assert cookie.discard and cookie.expires is None
            report["the_session_authorized_at"] = time.time()
            status, answer = request(base, "/api/v2/browser/session", opener=opener)
            report["the_session_before"] = {"status": status,
                                            "authenticated": answer.get("authenticated")}
            assert status == 200 and answer.get("authenticated") is True, answer
            report["steps"].append("the session of the operator is authorized")

            if args.skip_session_wait:
                report["the_session_lifetime"] = {"measured": False,
                                                  "reason": "the measurement was skipped"}
            else:
                print(f"checking session idle expiry after {SESSION_IDLE_TTL} s", flush=True)
                time.sleep(SESSION_IDLE_TTL + 30)
                status, answer = request(base, "/api/v2/browser/session", opener=opener)
                read_status, read_answer = request(base, "/api/v2/organizations",
                                                   opener=opener)
                report["the_session_after"] = {"status": status,
                                               "authenticated": answer.get("authenticated"),
                                               "code": answer.get("code")}
                report["the_management_read_after"] = {"status": read_status,
                                                        "code": read_answer.get("code")}
                report["the_session_lifetime"] = {
                    "measured": True, "idle_limit_seconds": SESSION_IDLE_TTL,
                    "the_checked_after_seconds": SESSION_IDLE_TTL + 30,
                    "the_session_is_authenticated": answer.get("authenticated"),
                    "the_management_read": read_status,
                    "the_refusal": read_answer.get("code"),
                }
                assert status == 200 and answer.get("authenticated") is False
                assert read_status == 403, read_answer
                report["steps"].append("the idle session expires and releases its access")
                status, session = request(base, "/api/v2/browser/login", "POST",
                                          {"code": issue()}, {"Origin": base}, opener)
                assert status == 200
                cookie, = jar

            status, reply = request(base, "/api/v2/browser/session", "DELETE", {},
                                    {"Origin": base, "x-oip-csrf": session["csrf_token"]}, opener)
            assert status == 200 and reply.get("logged_out") is True
            status, answer = request(base, "/api/v2/browser/session",
                                     headers={"Cookie": f"{cookie.name}={cookie.value}"})
            assert status == 200 and answer.get("authenticated") is False
            report["steps"].append("logout revokes the previous session token")

        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        try:
            tool("stop", expect_success=False)
        except Exception:
            pass
        shutil.rmtree(work, ignore_errors=True)
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
    (evidence / "session-lifetime.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "steps"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
