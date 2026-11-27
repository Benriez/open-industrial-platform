#!/usr/bin/env python3
"""Verify the offline Core package workflow in private temporary directories."""

import argparse
from contextlib import closing
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
from unittest.mock import patch
import urllib.error
import urllib.request

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, NoEncryption, PrivateFormat, PublicFormat

ROOT = Path(__file__).resolve().parents[1]
UPDATER = ROOT / "tools" / "oip_update.py"
sys.path.insert(0, str(UPDATER.parent))
import oip_update


READY_CORE = """
import json
from pathlib import Path
import sqlite3
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

config = json.loads(Path(sys.argv[sys.argv.index("--config") + 1]).read_text())
connection = sqlite3.connect(config["database"])
connection.execute("PRAGMA user_version=8")
connection.close()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        name = self.path.removeprefix("/")
        if name == "health/ready":
            body = b'{"ready": true}'
        elif name in ("index.html", "main.dart.js"):
            body = (Path(config["web_dir"]) / name).read_bytes()
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", config["http_port"]), Handler).serve_forever()
"""


def keys(work):
    signer = Ed25519PrivateKey.generate()
    secret = work / "signing.pem"
    secret.touch(mode=0o600)
    secret.write_bytes(signer.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, NoEncryption()))
    public = work / "update-public.pem"
    public.write_bytes(signer.public_key().public_bytes(Encoding.PEM, PublicFormat.SubjectPublicKeyInfo))
    return secret, public


def prepare(bundle, secret, core, web, revision, version, *, simulator=None, schema=8, target=None):
    command = [sys.executable, str(UPDATER), "--prepare", "--bundle", str(bundle),
               "--signing-key", str(secret), "--binary", str(core), "--web", str(web),
               "--revision", revision, "--release-version", version, "--database-schema", str(schema)]
    if simulator:
        command.extend(("--simulator", str(simulator)))
    if target:
        command.extend(("--target", target))
    result = subprocess.run(command, capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["the_status"] == "PACKAGED"
    assert sorted(item.name for item in bundle.iterdir()) == sorted(
        ["oip-server", "web", "tools", "manifest.json", "signature", "LICENSE"]
        + (["oip-simulated-server"] if simulator else [])
    )
    return bundle


def command(instance, bundle, public, *more):
    return [sys.executable, str(UPDATER), "--instance", str(instance), "--bundle",
            str(bundle), "--public-key", str(public), *more]


def run(instance, bundle, public, *more):
    return subprocess.run(command(instance, bundle, public, *more),
                          capture_output=True, text=True, timeout=120)


def assert_refusal(result, explanation):
    assert result.returncode == 2 and explanation in result.stderr, (
        f"Expected refusal containing {explanation!r}. Received {result.returncode}: {result.stderr}"
    )


def fake_core(path, body):
    path.write_text(f"#!{sys.executable}\n" + body)
    path.chmod(0o700)
    return path


def rehearse(work, report):
    instance = work / "instance"
    instance.mkdir(mode=0o700)
    database = instance / "core.sqlite"
    current = instance / "current"
    web = work / "web"
    web.mkdir()
    (web / "index.html").write_text("<title>Private package fixture</title>")
    (web / "main.dart.js").write_text("window.fixture = true;")
    core = fake_core(work / "test-core", READY_CORE)
    secret, public = keys(work)

    first = prepare(work / "first", secret, core, web, "fixture-one", "1.9.2", simulator=core)
    verified = run(instance, first, public, "--dry-run")
    assert verified.returncode == 0, verified.stderr
    assert json.loads(verified.stdout)["the_status"] == "VERIFIED"
    assert not list(instance.iterdir()), "Verification changed the empty instance"
    report["steps"].append("offline verification without activation")

    result = run(instance, first, public)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["the_status"] == "UPDATED"
    assert current.resolve().name == "fixture-one"
    assert os.access(current / "oip-simulated-server", os.X_OK)
    assert all((current / path).is_file() for path in oip_update.OPERATOR_TOOLS)
    assert not database.exists(), "Candidate started against intended production storage"
    report["steps"].append("signed first installation including optional simulator")

    config = instance / "core.json"
    config.write_text(json.dumps({"database": str(database), "sources": [{"id": "local-simulation"}]}))
    config.chmod(0o600)
    database.touch(mode=0o600)
    with closing(sqlite3.connect(database)) as connection:
        connection.execute("PRAGMA user_version=8")
        connection.execute("CREATE TABLE preserved (entry BLOB)")
        connection.execute("INSERT INTO preserved VALUES ('old data')")
        connection.commit()
    initial_database = database.read_bytes()
    initial_config = config.read_bytes()
    second = prepare(work / "second", secret, core, web, "fixture-two", "1.10.0", simulator=core)
    result = run(instance, second, public)
    assert result.returncode == 0, result.stderr
    assert current.resolve().name == "fixture-two"
    assert (instance / "previous").resolve().name == "fixture-one"
    assert database.read_bytes() == initial_database
    assert config.read_bytes() == initial_config
    report["steps"].append("numeric update, same schema, preserved data and configuration")

    next_bundle = prepare(work / "next", secret, core, web, "fixture-next", "1.10.1", simulator=core)
    wrong_key = work / "wrong.pem"
    wrong_key.write_bytes(Ed25519PrivateKey.generate().public_key().public_bytes(
        Encoding.PEM, PublicFormat.SubjectPublicKeyInfo))
    assert_refusal(run(instance, next_bundle, wrong_key), "signature")
    report["steps"].append("untrusted signer refused")

    tampered = work / "changed-file"
    shutil.copytree(next_bundle, tampered)
    (tampered / "web" / "main.dart.js").write_text("changed after signing")
    assert_refusal(run(instance, tampered, public), "digest")
    (tampered / "web" / "main.dart.js").unlink()
    (tampered / "web" / "main.dart.js").symlink_to(next_bundle / "web" / "main.dart.js")
    assert_refusal(run(instance, tampered, public), "symbolic")
    report["steps"].append("changed and symlinked browser bytes refused")

    forged = work / "changed-manifest"
    shutil.copytree(next_bundle, forged)
    path = forged / "manifest.json"
    manifest = json.loads(path.read_bytes())
    manifest["the_version"] = "9.9.9"
    path.write_text(json.dumps(manifest))
    assert_refusal(run(instance, forged, public), "signature")
    report["steps"].append("modified signed manifest refused")

    target = oip_update.host_target()
    arch, platform = target.split("-", 1)
    alternate = ("x86_64" if arch == "aarch64" else "aarch64") + "-" + platform
    foreign = prepare(work / "foreign", secret, core, web, "fixture-foreign", "1.10.1",
                      simulator=core, target=alternate)
    assert_refusal(run(instance, foreign, public), "different operating system or architecture")
    report["steps"].append("wrong host architecture refused")

    for version, revision in (("1.9.99", "fixture-older"), ("1.10.0", "fixture-reissue")):
        downgrade = prepare(work / revision, secret, core, web, revision, version, simulator=core)
        assert_refusal(run(instance, downgrade, public), "strictly newer")
    report["steps"].append("older and equal versions refused despite new revisions")

    changed_schema = prepare(work / "changed-schema", secret, core, web, "fixture-migration",
                             "1.10.1", simulator=core, schema=9)
    assert_refusal(run(instance, changed_schema, public), "tested database migration")
    missing_sim = prepare(work / "no-sim", secret, core, web, "fixture-no-sim", "1.10.1")
    assert_refusal(run(instance, missing_sim, public), "missing the simulator")
    report["steps"].append("incompatible saved-instance schema and simulator component refused")

    for file, description in ((".local-operation.lock", "local operation"),
                              ("core.sqlite.oip-lock", "database is in use")):
        with (instance / file).open("rb") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            assert_refusal(run(instance, next_bundle, public), description)
    report["steps"].append("concurrent updater and active Core ownership refused")

    opts = SimpleNamespace(instance=instance, bundle=next_bundle, public_key=public,
                           config=None, target=None, dry_run=False)
    with patch.object(oip_update.shutil, "disk_usage", return_value=SimpleNamespace(free=0)):
        try:
            oip_update.update(opts)
        except oip_update.Refused as error:
            assert "insufficient space" in str(error)
        else:
            raise AssertionError("An update staged despite insufficient free space")
    assert not (instance / "versions" / "fixture-next").exists()
    report["steps"].append("space preflight refuses staging and preserves the selected release")

    broken_core = fake_core(work / "broken-core", "raise SystemExit(3)\n")
    broken = prepare(work / "broken", secret, broken_core, web, "fixture-broken", "1.10.1",
                     simulator=core)
    assert_refusal(run(instance, broken, public), "failed the isolated Core")
    wrong_web_core = fake_core(work / "wrong-web-core", READY_CORE.replace(
        'body = (Path(config["web_dir"]) / name).read_bytes()', 'body = b""'))
    wrong_web = prepare(work / "wrong-web", secret, wrong_web_core, web, "fixture-wrong-web",
                        "1.10.1", simulator=core)
    assert_refusal(run(instance, wrong_web, public), "did not serve the signed browser files")
    report["steps"].append("candidate exit and mismatched served browser refused before activation")

    marker = work / "candidate-started"
    slow_core = fake_core(work / "slow-core", f"import os, time\nfrom pathlib import Path\n"
                         f"Path({str(marker)!r}).write_text(str(os.getpid()))\ntime.sleep(30)\n")
    interrupted = prepare(work / "interrupted", secret, slow_core, web, "fixture-interrupted",
                          "1.10.1", simulator=core)
    process = subprocess.Popen(command(instance, interrupted, public), stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
    try:
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and not marker.exists() and process.poll() is None:
            time.sleep(0.05)
        assert marker.exists(), "The candidate did not reach staging before the interruption test"
        process.send_signal(signal.SIGTERM)
        output, error = process.communicate(timeout=12)
        assert process.returncode == 130, output + error
        try:
            os.kill(int(marker.read_text()), 0)
        except ProcessLookupError:
            pass
        else:
            raise AssertionError("The disposable candidate was left running")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
    assert current.resolve().name == "fixture-two"
    assert not list((instance / "versions").glob(".staged-*"))
    assert not (instance / "versions" / "fixture-interrupted").exists()
    report["steps"].append("interrupted staged update leaves active release and no candidate process")

    journal = instance / "state" / "updates.jsonl"
    entries = [json.loads(line) for line in journal.read_text().splitlines()]
    assert [entry.get("the_status", entry.get("the_result")) for entry in entries] == [
        "PREPARED", "UPDATED", "PREPARED", "UPDATED"
    ]
    assert database.read_bytes() == initial_database and config.read_bytes() == initial_config
    report["steps"].append("durable journal distinguishes preparation from activation")


def real_candidate(work, report, args):
    secret, public = keys(work)
    instance = work / "real"
    instance.mkdir(mode=0o700)
    bundle = prepare(work / "real-bundle", secret, args.core, args.web, "real-candidate",
                     "1.0.0", simulator=args.simulator)
    if args.real_receipt:
        args.real_receipt.write_text((bundle / "manifest.json").read_text())
    result = run(instance, bundle, public)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["the_status"] == "UPDATED"
    report["steps"].append("built OIP Core, embedded OPC UA simulation, and provided browser assets")
    if args.simulator:
        shutil.rmtree(bundle)
        installed = instance / "current" / "tools" / "oip_local.py"
        with socket.socket() as http, socket.socket() as opcua:
            http.bind(("127.0.0.1", 0))
            opcua.bind(("127.0.0.1", 0))
            port, simulator_port = http.getsockname()[1], opcua.getsockname()[1]
        result = subprocess.run(
            [sys.executable, "-B", str(installed), "--instance", str(instance), "setup",
             "--organization", "Fixture organization", "--infrastructure", "Fixture infrastructure",
             "--site", "Fixture site", "--backup-directory", str(work / "backups"),
             "--port", str(port), "--simulator-port", str(simulator_port)],
            capture_output=True, text=True, timeout=120, cwd=work,
        )
        assert result.returncode == 0, result.stderr
        second = prepare(work / "real-update", secret, args.core, args.web, "real-update",
                         "1.0.1", simulator=args.simulator)
        runner = subprocess.Popen(
            [sys.executable, "-B", str(installed), "--instance", str(instance), "run"],
            cwd=work, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
        )
        try:
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline and runner.poll() is None:
                try:
                    url = f"http://127.0.0.1:{port}/api/v2/browser/session"
                    with opener.open(url, timeout=1) as reply:
                        if json.load(reply).get("mode") == "login_required":
                            break
                except urllib.error.URLError:
                    time.sleep(0.2)
            else:
                raise AssertionError("The installed local runner did not start the authenticated browser service")
            assert_refusal(run(instance, second, public), "local operation")
        finally:
            if runner.poll() is None:
                runner.terminate()
            _, error = runner.communicate(timeout=45)
        assert runner.returncode == 0, error
        database = instance / "core.sqlite"
        initial_database = database.read_bytes()
        initial_configuration = (instance / "core.json").read_bytes()
        result = run(instance, second, public)
        assert result.returncode == 0, result.stderr
        assert json.loads(result.stdout)["the_status"] == "UPDATED"
        assert (instance / "current").resolve().name == "real-update"
        assert database.read_bytes() == initial_database
        assert (instance / "core.json").read_bytes() == initial_configuration
        report["steps"].append("signed tools setup and start, active-instance refusal, same-schema offline update")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, default=ROOT / "target" / "oip-update")
    parser.add_argument("--core", type=Path)
    parser.add_argument("--web", type=Path)
    parser.add_argument("--simulator", type=Path)
    parser.add_argument("--real-receipt", type=Path)
    args = parser.parse_args()
    if bool(args.core) != bool(args.web):
        parser.error("--core and --web must be passed together")
    args.evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-update-v2", "steps": [], "the_problems": [],
              "the_target": oip_update.host_target()}
    with tempfile.TemporaryDirectory(prefix="oip-update-test-", dir="/tmp") as temporary:
        work = Path(temporary).resolve()
        try:
            rehearse(work, report)
            if args.core:
                real_candidate(work, report, args)
        except (AssertionError, OSError, subprocess.SubprocessError, ValueError) as error:
            report["the_problems"].append(str(error))
    report["the_status"] = "FAIL" if report["the_problems"] else "PASS"
    for field, value in (("the_revision", "HEAD"), ("the_tree", "HEAD^{tree}")):
        report[field] = subprocess.check_output(["git", "rev-parse", value], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (args.evidence / "update.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report["the_status"], "the_steps": len(report["steps"]),
                      "the_problems": report["the_problems"]}, indent=2))
    return 0 if report["the_status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
