#!/usr/bin/env python3
"""The lifetimes of the session and of the one-time code (G2, G12).

The operator login tells the operator two things: the one-time code is valid
for 120 seconds and may be used once, and the session ends after 30 minutes.
The Core keeps both lifetimes as constants; nothing proved that the promise
of the surface holds.

This rehearsal measures both against the real Core:

  1. a code that was issued more than 120 seconds ago is refused;
  2. a session that was authorized more than 30 minutes ago is refused, and
     the Core answers the refusal with the generic identity refusal.

The measurement of the session waits for the real lifetime of the Core — it is
not shortened, because a shortened lifetime would prove nothing about the
promise of the surface.

Usage:
  python3 tests/oip_session_lifetime.py [--evidence DIR] [--skip-session-wait]
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
SESSION_TTL = 1800


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

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-session-lifetime"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    parser.add_argument("--skip-session-wait", action="store_true")
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-session-lifetime-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-lifetime-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    try:
        port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": port,
            "sources": [{"id": f"source-{letter}", "name": f"Local simulation {letter}",
                         "endpoint": f"opc.tcp://127.0.0.1:{15860 + index}", "namespace": 2}
                        for index, letter in enumerate("abcd")],
            "legacy_single_infrastructure": False,
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
        time.sleep(3)
        report["steps"].append("the instance runs")

        def issue():
            return json.loads(subprocess.check_output(
                [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
                 "--ipc-credential", str(credential)], text=True))["login_code"]

        # 1. the lifetime of the one-time code
        expired_code = issue()
        report["the_code_issued_at"] = time.time()
        print("the code is issued; the rehearsal waits for its lifetime "
              f"({GRANT_TTL} s)", flush=True)
        time.sleep(GRANT_TTL + 10)
        status, answer = request(base := f"http://127.0.0.1:{port}",
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
            print(f"the session is authorized; the rehearsal waits for its lifetime "
                  f"({SESSION_TTL} s)", flush=True)
            time.sleep(SESSION_TTL + 30)
            status, answer = request(base, "/api/v2/browser/session", opener=opener)
            # The session route answers the state of the session: an expired
            # session is reported as not authenticated. The management read
            # is the proof that the identity is gone.
            read_status, read_answer = request(base, "/api/v2/organizations",
                                               opener=opener)
            report["the_session_after"] = {"status": status,
                                           "authenticated": answer.get("authenticated"),
                                           "code": answer.get("code")}
            report["the_management_read_after"] = {"status": read_status,
                                                    "code": read_answer.get("code")}
            report["the_session_lifetime"] = {
                "measured": True, "the_promised_seconds": SESSION_TTL,
                "the_checked_after_seconds": SESSION_TTL + 30,
                "the_session_is_authenticated": answer.get("authenticated"),
                "the_management_read": read_status,
                "the_refusal": read_answer.get("code"),
            }
            assert answer.get("authenticated") is False, \
                f"the expired session is still authenticated: {answer}"
            assert read_status == 403, \
                f"the expired session still authorizes a management read: {read_status}"
            report["steps"].append("the expired session is refused")

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
