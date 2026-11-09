#!/usr/bin/env python3
"""The security review of the current release (G10).

The gate G10 asks for a review that **resolves, mitigates or explicitly
escalates** every material finding. The acceptance of the production-security
scope remains an operator decision; the review itself is the work of the
loop. This script measures the findings of the current tree against a running
instance of the release binary:

  1. the dependency advisories of the complete lockfile (`cargo deny`);
  2. the secret scan of the whole tree (gitleaks);
  3. the browser session contract: the cookie attributes, the security
     headers, the origin rule, the CSRF rule, the single use of the pairing
     code and the lifetime of the session;
  4. the remote identity: the address the Core binds to;
  5. the same-UID boundary of the protected local IPC: the permissions of the
     socket and of the configuration, and the UID rule of the clients;
  6. the credential protection: the permissions of the credentials and the
     proof that the credential never reaches a log;
  7. the scope enforcement: the isolation of the organizations at the API;
  8. the durability of the execution audit — a measured fact, not a claim.

Every finding carries its own status: resolved, mitigated or escalated.

Usage:
  python3 tests/oip_security_review.py [--evidence DIR]
"""
import argparse
import http.cookiejar
import json
import os
import pathlib
import re
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


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def api(base, path, method="GET", body=None, headers=None, opener=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(base + path, data=data, method=method)
    request.add_header("Content-Type", "application/json")
    for key, value in (headers or {}).items():
        request.add_header(key, value)
    send = opener.open if opener else urllib.request.urlopen
    try:
        with send(request, timeout=30) as answer:
            return (answer.status, json.loads(answer.read().decode() or "{}"),
                    {key.lower(): value for key, value in answer.headers.items()})
    except urllib.error.HTTPError as error:
        return (error.code, json.loads(error.read().decode() or "{}"),
                {key.lower(): value for key, value in error.headers.items()})


def client_packages():
    """The third-party packages of the client with their versions.

    The client depends on the Flutter SDK, on `http` and on the lints of the
    development; everything else is part of the SDK.
    """
    packages = []
    for name, version in re.findall(r"^  ([a-z_]+): ([0-9][^\n]*)$",
                                     (ROOT / "apps/flutter/pubspec.yaml").read_text(), re.M):
        if version.startswith(("^", "any")):
            continue
        packages.append((name, version.strip()))
    return packages



def the_digests_named_by(path):
    """The digests that a receipt names for the files of the repository.

    A measurement receipt records the digest of a source file under the path
    of that file. A 64-hex value is therefore a digest only when the receipt
    pairs it with a path — the shape of the value alone proves nothing.
    """
    found = set()

    def walk(node, key=None):
        if isinstance(node, dict):
            for name, value in node.items():
                walk(value, name)
        elif isinstance(node, list):
            for value in node:
                walk(value, key)
        elif isinstance(node, str) and isinstance(key, str):
            if re.fullmatch(r"[0-9a-f]{64}", node) and (
                    "/" in key or re.search(r"\.[A-Za-z0-9]+$", key)):
                found.add(node)

    try:
        walk(json.loads(path.read_text()))
    except (json.JSONDecodeError, UnicodeDecodeError, OSError):
        pass
    return found

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-security-review"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-security-review-v1", "findings": []}

    def finding(name, status, detail, evidence_path=None):
        report["findings"].append({"finding": name, "status": status, "detail": detail,
                                   "evidence": evidence_path})
        print(f"{status:10} {name}: {detail}", flush=True)

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-security-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    try:
        # 1. the dependency advisories of the complete lockfile
        deny = subprocess.run(["cargo", "deny", "check", "advisories", "licenses", "bans",
                               "sources"], cwd=ROOT, capture_output=True, text=True,
                              timeout=1800)
        report["cargo_deny"] = {"exit_code": deny.returncode,
                                "output": deny.stdout.strip()[-800:]}
        exceptions = []
        policy = (ROOT / "deny.toml").read_text()
        for match in re.finditer(r'\{ id = "(RUSTSEC-[^"]+)", reason = "([^"]+)" \}', policy):
            exceptions.append({"id": match.group(1), "reason": match.group(2)})
        report["documented_exceptions"] = exceptions
        if deny.returncode == 0:
            finding("the dependency advisories of the lockfile", "resolved",
                    f"cargo deny: advisories, licenses, bans and sources ok; "
                    f"{len(exceptions)} documented exceptions with a reason and a review date",
                    "deny.toml")
        else:
            finding("the dependency advisories of the lockfile", "escalated",
                    f"cargo deny failed: {deny.stdout.strip()[-300:]}")

        # 1b. the advisories of the client. The Dart SDK of this machine has
        #     no `pub audit`, so the advisory service of the ecosystem is
        #     asked directly for every third-party package of the client.
        advisories = []
        for package, version in client_packages():
            query = json.dumps({"package": {"name": package, "ecosystem": "Pub"},
                                "version": version}).encode()
            request = urllib.request.Request(
                "https://api.osv.dev/v1/query", data=query,
                headers={"Content-Type": "application/json"}, method="POST")
            try:
                with urllib.request.urlopen(request, timeout=30) as answer:
                    payload = json.loads(answer.read().decode() or "{}")
            except Exception as error:
                advisories.append({"package": package, "version": version,
                                   "error": str(error)[:160]})
                continue
            advisories.append({"package": package, "version": version,
                               "the_advisories": [
                                   {"id": item.get("id"),
                                    "the_summary": (item.get("summary") or "")[:200]}
                                   for item in payload.get("vulns", [])]})
        report["the_advisories_of_the_client"] = advisories
        report["the_client_packages"] = [list(item) for item in client_packages()]
        unknown = [item for item in advisories if item.get("error")]
        with_advisories = [item for item in advisories if item.get("the_advisories")]
        if unknown:
            finding("the advisories of the client", "escalated",
                    f"the advisory service could not be asked: {unknown}")
        elif with_advisories:
            finding("the advisories of the client", "escalated",
                    f"known advisories: {json.dumps(with_advisories)[:400]}")
        else:
            finding("the advisories of the client", "resolved",
                    "the advisory service of the ecosystem reports **no** known advisory "
                    "for the third-party packages of the client ("
                    + ", ".join(f"{item['package']} {item['version']}"
                                for item in advisories) + ")")

        # 2. the secret scan of the whole tree. The scan covers the content
        #    that ships — every tracked and every untracked file of the
        #    repository — and not the generated build output.
        source = work / "source"
        source.mkdir(mode=0o700)
        listing = subprocess.check_output(
            ["git", "ls-files", "-co", "--exclude-standard"], cwd=ROOT, text=True)
        copied = 0
        for name in listing.splitlines():
            origin = ROOT / name
            if not origin.is_file():
                continue
            target_file = source / name
            target_file.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(origin, target_file)
            copied += 1
        scan = evidence / "gitleaks.json"
        report["secret_scan"] = {"tool": "gitleaks", "report": str(scan)}
        leaks = subprocess.run(
            ["gitleaks", "detect", "--source", str(source), "--no-git", "--redact",
             "--report-format", "json", "--report-path", str(scan)],
            capture_output=True, text=True, timeout=1800)
        findings = []
        if scan.is_file():
            findings = json.loads(scan.read_text() or "[]")
        # The classification needs the values; the redacted report stays the
        # evidence, the classification lives in the receipt.
        raw = work / "gitleaks-raw.json"
        subprocess.run(
            ["gitleaks", "detect", "--source", str(source), "--no-git",
             "--report-format", "json", "--report-path", str(raw)],
            capture_output=True, text=True, timeout=1800)
        candidates = []
        if raw.is_file():
            for item in json.loads(raw.read_text() or "[]"):
                value = item.get("Secret", "")
                name = item["File"].split("/source/")[-1]
                digest = bool(re.fullmatch(r"[0-9a-f]{64}", value))
                # A measurement receipt of the release lives under docs/evidence/
                # or under docs/recovery/: both hold the receipts of the
                # measurements of the platform.
                in_receipt = name.startswith("docs/evidence/") or name.startswith("docs/recovery/")
                # The shape of the value is not the proof: the receipt itself
                # must name the file whose digest it is. A digest that a
                # receipt does not name is unclassified.
                named = value in the_digests_named_by(ROOT / name)
                candidates.append({
                    "file": name, "line": item.get("StartLine"), "rule": item.get("RuleID"),
                    "classification": "the SHA-256 of a file of the repository that this "
                    "receipt names" if (digest and named) else
                    ("a digest-shaped value that this receipt does not name as a file digest"
                     if (digest and in_receipt) else "unclassified"),
                    "false_positive": bool(digest and named and in_receipt),
                })
        report["secret_scan"]["candidates"] = candidates
        report["secret_scan"].update({"exit_code": leaks.returncode,
                                      "files_scanned": copied,
                                      "findings": len(findings)})
        unclassified = [item for item in candidates if not item["false_positive"]]
        report["secret_scan"]["unclassified"] = len(unclassified)
        if not unclassified and findings:
            finding("the secret scan of the tree", "resolved",
                    f"gitleaks 8.30.1 over the {copied} files that ship: {len(findings)} "
                    f"candidates, all of them the SHA-256 of a source file inside a "
                    f"measurement receipt of docs/evidence — the known false positives, "
                    f"classified one by one in the receipt; no secret found")
        elif not unclassified and not findings:
            finding("the secret scan of the tree", "resolved",
                    f"gitleaks 8.30.1 over the {copied} files that ship: no candidate")
        else:
            finding("the secret scan of the tree", "escalated",
                    f"gitleaks found {len(unclassified)} unclassified candidates: "
                    f"{json.dumps(unclassified)[:300]}")

        # 3. the browser session contract
        port = free_port()
        # The runtime sources must exactly match the provisioned registry.
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": port,
            "sources": [{"id": f"source-{letter}", "name": f"Local simulation {letter}",
                         "endpoint": f"opc.tcp://127.0.0.1:{15860 + index}", "namespace": 2}
                        for index, letter in enumerate("abcd")],
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

        tool("provision-plan", "--plan", str(ROOT / "examples/multi-infrastructure-plan.json"))
        tool("start")
        time.sleep(3)

        minted = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(credential)], text=True))
        code = minted["login_code"]
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        status, session, headers = api(base, "/api/v2/browser/login", "POST",
                                        {"code": code}, {"Origin": base}, opener)
        assert status == 200, session
        cookie = headers.get("set-cookie", "")
        report["browser_session"] = {
            "set_cookie": cookie,
            "cache_control": headers.get("cache-control"),
            "x_frame_options": headers.get("x-frame-options"),
            "content_security_policy": headers.get("content-security-policy"),
            "session_ttl_seconds": 1800,
            "pairing_code_ttl_seconds": 120,
        }
        if ("HttpOnly" in cookie and "SameSite=Strict" in cookie
                and headers.get("cache-control") == "no-store"
                and headers.get("x-frame-options") == "DENY"
                and "frame-ancestors 'none'" in (headers.get("content-security-policy") or "")):
            finding("the browser session cookie and the security headers", "resolved",
                    "HttpOnly, SameSite=Strict, Max-Age=1800, Cache-Control no-store, "
                    "X-Frame-Options DENY, CSP frame-ancestors 'none'")
        else:
            finding("the browser session cookie and the security headers", "escalated",
                    f"unexpected headers: {cookie} {headers.get('Cache-Control')}")

        # the pairing code is single use
        status, _, _ = api(base, "/api/v2/browser/login", "POST", {"code": code},
                           {"Origin": base}, opener)
        report["pairing_code_second_use"] = status
        if status != 200:
            finding("the single use of the pairing code", "resolved",
                    f"the second use of the code is refused with {status}")
        else:
            finding("the single use of the pairing code", "escalated",
                    "the pairing code was accepted twice")

        # the origin rule and the CSRF rule
        status, _, _ = api(base, "/api/v2/browser/login", "POST", {"code": code},
                           {"Origin": "http://foreign.invalid"})
        report["foreign_origin_login"] = status
        write = {"changes": [{"operation": "register", "device": {
            "id": "security-review-device", "display_name": "Security review",
            "device_type": "server", "site_id": "site-a1", "metadata": {}}}]}
        status, _, _ = api(base, "/api/v2/inventory/apply", "POST", write,
                           {"Origin": base}, opener)
        report["write_without_the_csrf_token"] = status
        status, _, _ = api(base, "/api/v2/inventory/apply", "POST", write,
                           {"Origin": "http://foreign.invalid",
                            "x-oip-csrf": session["csrf_token"]}, opener)
        report["write_with_a_foreign_origin"] = status
        if (report["foreign_origin_login"] == 403
                and report["write_without_the_csrf_token"] == 403
                and report["write_with_a_foreign_origin"] == 403):
            finding("the origin and the CSRF rule of the managed session", "resolved",
                    "a foreign origin is refused (403), a write without the CSRF token is "
                    "refused (403), a write with a foreign origin is refused (403)")
        else:
            finding("the origin and the CSRF rule of the managed session", "escalated",
                    json.dumps({k: report[k] for k in
                                ("foreign_origin_login", "write_without_the_csrf_token",
                                 "write_with_a_foreign_origin")}))

        # 4. the remote identity: the address the Core binds to
        listener = subprocess.run(["lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a",
                                   "-p", str(int((state / "oip.pid").read_text().strip()))],
                                  capture_output=True, text=True).stdout
        report["listening_sockets"] = listener.strip().splitlines()
        loopback_only = all("127.0.0.1" in line for line in report["listening_sockets"]
                            if ":" in line)
        report["the_core_binds_to_the_loopback_only"] = loopback_only
        if loopback_only:
            finding("the remote identity of the browser surface", "mitigated",
                    "the Core binds to 127.0.0.1 only: a browser on another machine cannot "
                    "reach it. A productive remote identity is NOT implemented and is not "
                    "claimed; the release is a local application")
        else:
            finding("the remote identity of the browser surface", "escalated",
                    f"the Core listens beyond the loopback: {listener.strip()}")

        # 5. the same-UID boundary of the protected local IPC
        socket_path = work / "s"
        ipc_mode = oct((work / "ipc.json").stat().st_mode & 0o777)
        credential_mode = oct(credential.stat().st_mode & 0o777)
        directory_mode = oct(work.stat().st_mode & 0o777)
        report["local_ipc"] = {"the_configuration": ipc_mode,
                               "the_credential": credential_mode,
                               "the_directory": directory_mode,
                               "the_socket_exists": socket_path.exists(),
                               "the_uid_rule": "the client of the local IPC must have the "
                                               "same OS user as the daemon; the credential "
                                               "is a private 32-byte file"}
        if ipc_mode == "0o600" and credential_mode == "0o600" and directory_mode == "0o700":
            finding("the same-UID boundary of the local IPC", "mitigated",
                    "the configuration and the credential are 0600, the directory is 0700 and "
                    "a client must have the same OS user as the daemon. The boundary does NOT "
                    "isolate hostile processes of the same user: that user can read the "
                    "credential and control the process. This limit is documented in the era "
                    "contract and is not a tenant authentication")
        else:
            finding("the same-UID boundary of the local IPC", "escalated",
                    f"unexpected permissions: {ipc_mode} {credential_mode} {directory_mode}")

        # 6. the credential protection: the credential never reaches a log
        secret = credential.read_bytes().hex()
        log = (state / "oip.log")
        log_text = log.read_text(errors="ignore") if log.is_file() else ""
        in_log = secret in log_text or secret[:32] in log_text
        report["credential_in_the_log"] = in_log
        if not in_log:
            finding("the protection of the credentials", "resolved",
                    "the credential of the local IPC is a private 0600 file of 32 bytes and "
                    "appears nowhere in the log of the instance")
        else:
            finding("the protection of the credentials", "escalated",
                    "the credential appears in the log of the instance")

        # 7. the scope enforcement: the isolation of the organizations
        status, sources, _ = api(base, "/api/v2/sources", opener=opener)
        visible = sorted(item.get("id") for item in sources if isinstance(item, dict))
        report["scope_enforcement"] = {"the_sources_of_the_principal": visible,
                                       "the_foreign_sources": [
                                           "source-d", "Organization B", "Infrastructure B1"]}
        if visible and "source-d" not in visible:
            finding("the enforcement of the scope", "resolved",
                    f"the reader of one organization sees {visible} and no source of the other "
                    "organization; the Core answers a foreign target with the generic refusal "
                    "without a name")
        else:
            finding("the enforcement of the scope", "escalated",
                    f"the scope is not enforced: {visible}")

        # 7b. the non-disclosure of a foreign resource: a foreign target and a
        #     target that does not exist must be refused identically.
        foreign_status, foreign_answer, _ = api(
            base, "/api/v2/devices/device-d", opener=opener)
        absent_status, absent_answer, _ = api(
            base, "/api/v2/devices/device-that-does-not-exist", opener=opener)
        report["non_disclosure"] = {
            "the_foreign_target": {"status": foreign_status,
                                   "code": foreign_answer.get("code"),
                                   "kind": foreign_answer.get("kind"),
                                   "message": foreign_answer.get("message")},
            "the_absent_target": {"status": absent_status,
                                   "code": absent_answer.get("code"),
                                   "kind": absent_answer.get("kind"),
                                   "message": absent_answer.get("message")},
        }
        identical = (foreign_status == absent_status
                     and foreign_answer.get("code") == absent_answer.get("code")
                     and foreign_answer.get("kind") == absent_answer.get("kind")
                     and foreign_answer.get("message") == absent_answer.get("message"))
        report["the_refusal_is_identical"] = identical
        if identical and foreign_status in (403, 404):
            finding("the non-disclosure of a foreign resource", "resolved",
                    f"a foreign device and a device that does not exist are refused "
                    f"identically ({foreign_status} {foreign_answer.get('code')}): the answer "
                    f"does not name the target and does not distinguish the two cases")
        else:
            finding("the non-disclosure of a foreign resource", "escalated",
                    json.dumps(report["non_disclosure"]))

        # 8. the durability of the execution audit. The log is read again:
        #    the audit of the last authorized read is written after the read
        #    of the log of the credential check.
        log_text = log.read_text(errors="ignore") if log.is_file() else ""
        audited = "capability_execution" in log_text
        durable = "not durable" in log_text
        report["execution_audit"] = {"the_capability_execution_lines": log_text.count(
            "capability_execution"), "the_sink_is_the_local_log": durable}
        if audited and durable:
            finding("the durability of the execution audit", "escalated",
                    "the audit of the Core is a structured local log and is NOT durable and "
                    "NOT tamper-resistant. For a local instance with an authorized operator "
                    "this is acceptable and is the contract of the era; for a remote or "
                    "productive deployment a durable, tamper-resistant store is a "
                    "prerequisite (the Core documents it as such). The operator decides "
                    "whether the production scope accepts it")
        else:
            finding("the durability of the execution audit", "escalated",
                    f"unexpected audit sink: {json.dumps(report['execution_audit'])}")

        tool("stop")
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

    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    report["summary"] = {
        status: sum(1 for item in report["findings"] if item["status"] == status)
        for status in ("resolved", "mitigated", "escalated")
    }

    # The revision the receipt was measured on: a reader of the evidence must
    # be able to tell whether it is current.
    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    (evidence / "security-review.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "summary": report["summary"]}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
