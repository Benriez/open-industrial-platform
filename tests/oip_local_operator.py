#!/usr/bin/env python3
"""Exercise a fresh OIP local installation without touching the installed app."""
import argparse
import hashlib
import http.cookiejar
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import tempfile
import time
import urllib.request

from oip_opcua_parity import api, free_port

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from oip_ops import sqlite_query

RELEASE = ROOT / "target/release"
WEB = ROOT / "apps/flutter/build/web"


def until(predicate, label, timeout=35):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(0.25)
    raise AssertionError(label)


def stop(process, sig=signal.SIGTERM):
    if process is None or process.poll() is not None:
        return
    process.send_signal(sig)
    try:
        process.wait(timeout=30)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
        raise


def session(command, process, base):
    with selectors.DefaultSelector() as reader:
        reader.register(process.stdout, selectors.EVENT_READ)
        assert reader.select(35), "Local OIP start took too long"
        assert process.stdout.readline().startswith("OIP läuft unter "), "Local OIP failed to start"
        assert process.stdout.readline().startswith("Einmalcode für die Anmeldung: ")
    code = subprocess.check_output([*command, "login"], text=True, timeout=15).strip()
    assert re.fullmatch(r"[A-Za-z0-9-]+", code), "Missing local login code"
    browser = urllib.request.build_opener(
        urllib.request.ProxyHandler({}), urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
    )
    status, model = api(base, "/api/v2/browser/login", "POST",
                        {"code": code}, {"Origin": base}, browser)
    assert status == 200 and model["principal_id"] == "operator"
    return browser, model["csrf_token"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core", type=Path, default=RELEASE / "oip-server")
    parser.add_argument("--simulator", type=Path, default=RELEASE / "oip-simulated-server")
    parser.add_argument("--web", type=Path, default=WEB)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    evidence = args.evidence.absolute()
    evidence.mkdir(parents=True, exist_ok=True)
    begin = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="oip-local-test-", dir="/private/tmp") as temp:
        root = Path(temp) / "instance"
        backup = Path(temp) / "backup"
        port, sim_port = free_port(), free_port()
        while port == sim_port:
            sim_port = free_port()
        command = [sys.executable, str(ROOT / "tools/oip_local.py"), "--instance", str(root),
                   "--core", str(args.core), "--simulator", str(args.simulator), "--web", str(args.web)]
        setup = [*command, "setup", "--organization", "Testbetrieb",
                 "--infrastructure", "Testhalle", "--site", "Teststand",
                 "--backup-directory", str(backup),
                 "--port", str(port), "--simulator-port", str(sim_port)]
        subprocess.run(setup, check=True, timeout=45)
        setup_s = round(time.monotonic() - begin, 2)
        credential = hashlib.sha256((root / "operator.credential").read_bytes()).digest()
        # Rehearse an interruption after provisioning and before the commit marker.
        (root / "setup-complete.json").unlink()
        subprocess.run(setup, check=True, timeout=45)
        subprocess.run(setup, check=True, timeout=45)
        assert hashlib.sha256((root / "operator.credential").read_bytes()).digest() == credential
        assert root.stat().st_mode & 0o077 == 0 and backup.stat().st_mode & 0o077 == 0
        denied = subprocess.run([*setup, "--site", "Anderer Standort"], capture_output=True, timeout=20)
        assert denied.returncode != 0 and json.loads((root / "setup-complete.json").read_text())["site"] == "Teststand"

        base = f"http://127.0.0.1:{port}"
        runner = replacement = None
        try:
            runner = subprocess.Popen([*command, "run"], stdout=subprocess.PIPE, text=True)
            browser, csrf = session(command, runner, base)
            path = "/api/v2/support-package?infrastructure=local-infra"
            assert api(base, path, opener=urllib.request.build_opener(urllib.request.ProxyHandler({})))[0] == 403

            def get(path):
                status, data = api(base, path, opener=browser)
                assert status == 200, status
                return data

            def source():
                return next(s for s in get("/api/v2/sources") if s["id"] == "local-simulation")

            until(lambda: source()["freshness"] == "fresh", "Simulator did not deliver fresh values")
            values = get("/api/v2/observations?source=local-simulation")
            assert values and all(v["data_source_id"] == "local-simulation" for v in values)
            assert source()["simulated"] is True, "Simulated values must remain labelled"
            assert get(path)["sources"]["simulated"] == 1
            write_status, refusal = api(base, "/api/v2/opcua/write", "POST",
                                  {"source": "local-simulation", "node_id": "ns=2;s=Machine.Temperature",
                                   "value": {"float": 15.0}},
                                  {"Origin": base, "x-oip-csrf": csrf}, browser)
            assert write_status == 409 and refusal["code"] == "OPCUA_READ_ONLY_PROFILE", refusal
            with browser.open(base + "/main.dart.js", timeout=10) as bundle:
                served_digest = hashlib.sha256(bundle.read()).hexdigest()
            assert served_digest == hashlib.sha256((args.web / "main.dart.js").read_bytes()).hexdigest()

            child = subprocess.check_output(["/usr/bin/pgrep", "-P", str(runner.pid), "-f",
                                             "oip-simulated-server"], text=True).strip()
            os.kill(int(child), signal.SIGINT)
            until(lambda: source()["connection"] == "disconnected", "Source outage not reported")
            assert source()["freshness"] != "fresh"
            replacement = subprocess.Popen([args.simulator, "--port", str(sim_port), "--seed", "42"],
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            until(lambda: source()["freshness"] == "fresh", "Simulator reconnect failed", 60)
            assert get("/api/v2/observations?source=local-simulation")
            stop(replacement, signal.SIGINT)
            stop(runner)

            runner = subprocess.Popen([*command, "run"], stdout=subprocess.PIPE, text=True)
            browser, _ = session(command, runner, base)
            until(lambda: source()["freshness"] == "fresh", "No new data after Core restart")
            assert get(path)["sources"]["total"] == 1
            stop(runner)
            database = root / "core.sqlite"
            assert sqlite_query(database, "PRAGMA integrity_check") == "ok"
            assert sqlite_query(database, "SELECT id FROM infrastructures") == "local-infra"
            history_rows = int(sqlite_query(database, "SELECT count(*) FROM observations"))
            assert history_rows > 0
        finally:
            stop(replacement, signal.SIGINT)
            stop(runner)

    receipt = {"status": "PASS", "platform": sys.platform, "architecture": os.uname().machine,
               "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
               "core_sha256": hashlib.sha256(args.core.read_bytes()).hexdigest(),
               "main_dart_js_sha256": served_digest, "setup_command_seconds": setup_s,
               "history_rows": history_rows, "elapsed_seconds": round(time.monotonic() - begin, 2),
               "tested": ["fresh_setup", "resume_after_provision", "auth", "scope", "write_denied",
                          "external_loopback_simulator", "outage", "reconnect", "core_restart",
                          "history_integrity", "served_bundle_matches"]}
    (evidence / "local-operator.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt))


if __name__ == "__main__":
    main()
