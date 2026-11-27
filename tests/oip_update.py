#!/usr/bin/env python3
"""Verify the offline Core package workflow in private temporary directories."""

import argparse
from contextlib import closing, contextmanager
import fcntl
import hashlib
from io import BytesIO
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import time
from types import SimpleNamespace
from unittest.mock import patch
from zipfile import ZipFile

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import (
    Encoding, NoEncryption, PrivateFormat, PublicFormat, load_pem_private_key,
)

ROOT = Path(__file__).resolve().parents[1]
UPDATER = ROOT / "tools" / "oip_update.py"
sys.path.insert(0, str(UPDATER.parent))
import oip_update
from oip_license_issue import (
    ISSUER, PHP_ODP_ARTIFACT, PHP_OIP_ARTIFACT, PHP_OIP_HOLDER, PHP_OIP_LICENSE_ID, PHP_TEST_KEYS,
    decode, json_line, period, proof_request, public_key, sign_fixture,
)
from oip_local_operator import session
from oip_opcua_parity import api


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


def prepare_command(bundle, secret, core, web, revision, version, *, simulator=None, schema=8,
                    target=None, policy=None, kinds=()):
    command = [sys.executable, str(UPDATER), "--prepare", "--bundle", str(bundle),
               "--signing-key", str(secret), "--binary", str(core), "--web", str(web),
               "--revision", revision, "--release-version", version, "--database-schema", str(schema)]
    if simulator:
        command.extend(("--simulator", str(simulator)))
    if target:
        command.extend(("--target", target))
    if policy:
        command.extend(("--license-policy", str(policy)))
    for kind in kinds:
        command.extend(("--commercial-license-kind", kind))
    return command


def prepare(bundle, secret, core, web, revision, version, **options):
    command = prepare_command(bundle, secret, core, web, revision, version, **options)
    result = subprocess.run(command, capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["the_status"] == "PACKAGED"
    assert sorted(item.name for item in bundle.iterdir()) == sorted(
        ["oip-server", "web", "tools", "manifest.json", "signature", "LICENSE", "THIRD_PARTY_NOTICES.txt"]
        + (["oip-simulated-server"] if options.get("simulator") else [])
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


def verify_license_materials(bundle):
    manifest = json.loads((bundle / "manifest.json").read_bytes())
    assert manifest[oip_update.LICENSE_MATERIALS] == 1
    for name in (oip_update.OPCUA_SOURCE, oip_update.ROBOTO_NOTICE):
        assert hashlib.sha256((bundle / name).read_bytes()).hexdigest() == manifest["the_artefacts"][name]
    assert (bundle / oip_update.ROBOTO_NOTICE).read_bytes() == (
        ROOT / "apps/flutter/assets/fonts/Roboto_LICENSE.txt"
    ).read_bytes()
    patches = ["vendor/async-opcua-" + part for part in ("client", "crypto", "server")]
    tracked = subprocess.check_output(["git", "ls-files", "-z", "--", *patches], cwd=ROOT).split(b"\0")[:-1]
    tracked = {name.decode() for name in tracked}
    lockfile = (ROOT / "Cargo.lock").read_text()
    with ZipFile(bundle / oip_update.OPCUA_SOURCE) as archive:
        original = {f"registry/async-opcua{part}-0.19.0.crate"
                    for part in ("", "-core", "-core-namespace", "-macros", "-nodes", "-types")}
        assert set(archive.namelist()) == tracked | original | {"README.md"}
        assert archive.read("README.md") == (ROOT / "vendor/README.md").read_bytes()
        for name in tracked:
            assert archive.read(name) == (ROOT / name).read_bytes()
        for name in original:
            data = archive.read(name)
            assert f'checksum = "{hashlib.sha256(data).hexdigest()}"' in lockfile
            with tarfile.open(fileobj=BytesIO(data), mode="r:gz") as crate:
                assert crate.getmember(f"{Path(name).stem}/Cargo.toml").isfile()


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
    verify_license_materials(first)
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

    missing_notice = work / "missing-license-notice"
    shutil.copytree(next_bundle, missing_notice)
    path = missing_notice / "manifest.json"
    manifest = json.loads(path.read_bytes())
    del manifest["the_artefacts"][oip_update.NOTICE]
    payload = json_line(manifest)
    path.write_bytes(payload)
    signer = load_pem_private_key(secret.read_bytes(), password=None)
    (missing_notice / "signature").write_bytes(signer.sign(payload))
    (missing_notice / oip_update.NOTICE).unlink()
    assert_refusal(run(instance, missing_notice, public), "license files")
    assert current.resolve().name == "fixture-two"
    report["steps"].append("correctly signed package without required license notices refused")

    licence_materials = work / "license-materials"
    shutil.copytree(next_bundle, licence_materials)
    original_archive = (licence_materials / oip_update.OPCUA_SOURCE).read_bytes()
    (licence_materials / oip_update.OPCUA_SOURCE).write_bytes(original_archive + b"extra")
    assert_refusal(run(instance, licence_materials, public, "--dry-run"), "digest")
    (licence_materials / oip_update.OPCUA_SOURCE).write_bytes(original_archive)
    path = licence_materials / "manifest.json"
    manifest = json.loads(path.read_bytes())
    for name in (oip_update.OPCUA_SOURCE, oip_update.ROBOTO_NOTICE):
        del manifest["the_artefacts"][name]
        (licence_materials / name).unlink()
    payload = json_line(manifest)
    path.write_bytes(payload)
    (licence_materials / "signature").write_bytes(signer.sign(payload))
    assert_refusal(run(instance, licence_materials, public, "--dry-run"), "third-party license materials")
    del manifest[oip_update.LICENSE_MATERIALS]
    payload = json_line(manifest)
    path.write_bytes(payload)
    (licence_materials / "signature").write_bytes(signer.sign(payload))
    assert run(instance, licence_materials, public, "--dry-run").returncode == 0
    assert current.resolve().name == "fixture-two"
    report["steps"].append("signed source and font materials verified, edits and omissions denied, legacy packages readable")

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


def installed_operator(instance):
    return [sys.executable, "-B", str(instance / "current" / "tools" / "oip_local.py"),
            "--instance", str(instance)]


@contextmanager
def installed_browser(instance, port, work):
    command = installed_operator(instance)
    base = f"http://127.0.0.1:{port}"
    runner = subprocess.Popen(
        [*command, "run"], cwd=work, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    try:
        browser, csrf = session(command, runner, base)
        yield base, browser, {"Origin": base, "x-oip-csrf": csrf}
    finally:
        if runner.poll() is None:
            runner.terminate()
        try:
            _, error = runner.communicate(timeout=45)
        except subprocess.TimeoutExpired:
            runner.kill()
            runner.communicate()
            raise
        assert runner.returncode == 0, error


def install_proof(access, proof, rejected_proof):
    base, browser, headers = access
    status_path = "/api/v2/license"
    code, before = api(base, status_path, opener=browser)
    assert code == 200 and before["proof_state"] == "missing" and before["can_manage"] is True
    code, error = api(base, status_path + "/preview", "POST", rejected_proof, headers, browser)
    assert code == 400 and error["code"] == "LICENSE_PROOF_INVALID"
    code, preview = api(base, status_path + "/preview", "POST", proof, headers, browser)
    assert code == 200 and preview["status"]["license_id"] == PHP_OIP_LICENSE_ID
    assert preview["status"]["licensee"] == PHP_OIP_HOLDER
    assert api(base, status_path, opener=browser) == (200, before)
    code, after = api(base, status_path + "/apply", "POST",
                      {"confirmation": preview["confirmation"]}, headers, browser)
    assert code == 200 and after["proof_state"] == "verified"
    assert after["commercial"] == "active" and after["support"] == "ended"
    return after


def prepare_issuer_policy(work):
    registry = work / "pruefschluessel.json"
    rows = []
    for product, artifact in (("oip", PHP_OIP_ARTIFACT), ("odp", PHP_ODP_ARTIFACT)):
        key_id = json.loads(artifact)["kid"]
        key = PHP_TEST_KEYS[key_id]
        rows.append({"product_id": product, "kid": key_id, "public_key": key,
                     "fingerprint": hashlib.sha256(decode(key)).hexdigest(), "state": "active"})
    registry.write_bytes(json_line({"issuer": ISSUER, "keys": rows}))
    result = subprocess.run(
        [sys.executable, "-B", str(ROOT / "tools/oip_local.py"), "prepare-license-policy",
         "--registry", str(registry), "--key-fingerprint", rows[0]["fingerprint"],
         "--kind", "standard", "--right", "installations=20"],
        capture_output=True, check=True, timeout=30, cwd=work,
    )
    assert json.loads(result.stdout)["keys"] == {rows[0]["kid"]: rows[0]["public_key"]}
    policy = work / "license-policy.json"
    policy.write_bytes(result.stdout)
    return policy


def refuse_single_signer(work, secret, release_key, args, policy, report):
    content = json.loads(policy.read_bytes())
    kid, key = public_key(release_key)
    content["keys"][kid] = key
    combined = work / "combined-signers.json"
    combined.write_bytes(json_line(content))
    command = prepare_command(work / "combined-bundle", secret, args.core, args.web,
                              "one-signer", "1.0.0", policy=combined, kinds=("standard",))
    result = subprocess.run(command, capture_output=True, text=True, timeout=120)
    assert_refusal(result, "package signing key cannot issue OIP licenses")
    assert not (work / "combined-bundle").exists()
    report["steps"].append("package preparation refuses to trust the package signing key for licensing")


def refuse_invalid_signed_policy(instance, bundle, public, release_key, report):
    manifest_path = bundle / "manifest.json"
    signature_path = bundle / "signature"
    original = manifest_path.read_bytes()
    signature = signature_path.read_bytes()
    manifest = json.loads(original)
    defaults = manifest[oip_update.LICENSE_SETUP]
    policy = json.loads(defaults["license_policy"])
    policy["rights"]["installations"] = -1
    defaults["license_policy"] = json_line(policy).decode("utf-8")
    invalid = json_line(manifest)
    manifest_path.write_bytes(invalid)
    signature_path.write_bytes(release_key.sign(invalid))
    result = run(instance, bundle, public)
    assert_refusal(result, "OIP Core refused the license policy")
    assert not (instance / "current").exists()
    assert not (instance / "core.json").exists()
    manifest_path.write_bytes(original)
    signature_path.write_bytes(signature)
    report["steps"].append("staged Core refuses an invalid policy despite a valid package signature")


def real_setup_command(work, instance, public, port, simulator_port):
    return [*installed_operator(instance), "setup", "--organization", "Fixture organization",
            "--infrastructure", "Fixture infrastructure", "--site", "Fixture site",
            "--backup-directory", str(work / "backups"), "--port", str(port),
            "--simulator-port", str(simulator_port), "--package-public-key", str(public)]


def refuse_changed_license_setup(work, instance, setup, policy, release_key, report):
    manifest_path = instance / "current" / "manifest.json"
    signature_path = instance / "current" / "signature"
    manifest_bytes = manifest_path.read_bytes()
    signature = signature_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    defaults = manifest[oip_update.LICENSE_SETUP]
    assert defaults == {"license_policy": policy.read_text(), "commercial_license_kinds": ["standard"]}
    defaults["commercial_license_kinds"] = []
    manifest_path.write_bytes(json_line(manifest))
    result = subprocess.run(setup, capture_output=True, text=True, timeout=30, cwd=work)
    assert result.returncode == 1 and "signature" in result.stderr, result.stderr

    bad_payload = manifest_bytes.replace(b'{', b'{"the_license_setup": null,', 1)
    manifest_path.write_bytes(bad_payload)
    signature_path.write_bytes(release_key.sign(bad_payload))
    result = subprocess.run(setup, capture_output=True, text=True, timeout=30, cwd=work)
    assert result.returncode == 1 and "not valid JSON" in result.stderr, result.stderr

    manifest_path.write_bytes(manifest_bytes)
    signature_path.write_bytes(signature)
    other_signer = work / "other-signer"
    other_signer.mkdir(mode=0o700)
    _, unrelated_key = keys(other_signer)
    result = subprocess.run([*setup[:-1], str(unrelated_key)], capture_output=True, text=True,
                            timeout=30, cwd=work)
    assert result.returncode == 1 and "signature" in result.stderr, result.stderr
    assert not any((instance / name).exists() for name in ("setup.json", "core.json", "core.sqlite"))
    report["steps"].append("first setup refuses tampered, ambiguous, and foreign-signed license defaults")
    return unrelated_key


def rehearse_signed_policy_install(work, bundle, public, wrong_key, port, simulator_port, report):
    instance = work / "instance"
    instance.mkdir(mode=0o700)
    result = run(instance, bundle, public)
    assert result.returncode == 0, result.stderr
    setup = real_setup_command(work, instance, public, port, simulator_port)
    subprocess.run(setup[:-2], check=True, stdout=subprocess.DEVNULL, timeout=120, cwd=work)
    config = instance / "core.json"
    original = config.read_bytes()
    assert "license_policy" not in json.loads(original)
    install = [*installed_operator(instance), "install-license-policy", "--package-public-key", str(public)]
    result = subprocess.run([*install[:-1], str(wrong_key)], capture_output=True, text=True,
                            timeout=30, cwd=work)
    assert result.returncode == 1 and "signature" in result.stderr, result.stderr
    assert config.read_bytes() == original
    review = json.loads(subprocess.check_output(install, text=True, timeout=30, cwd=work))
    assert (review["status"], review["commercial_license_kinds"]) == ("review", ["standard"])
    assert config.read_bytes() == original
    result = subprocess.check_output([*install, "--confirm", review["confirmation"]],
                                     text=True, timeout=30, cwd=work)
    assert json.loads(result)["status"] == "applied"
    manifest = json.loads((bundle / "manifest.json").read_bytes())
    updated = config.read_bytes()
    assert json.loads(updated) == {**json.loads(original), **manifest[oip_update.LICENSE_SETUP]}
    subprocess.run(setup, check=True, stdout=subprocess.DEVNULL, timeout=120, cwd=work)
    assert config.read_bytes() == updated
    with installed_browser(instance, port, work) as (base, browser, _):
        code, status = api(base, "/api/v2/license", opener=browser)
        assert code == 200 and status["proof_state"] == "missing" and status["can_manage"] is True
        for name in (oip_update.OPCUA_SOURCE, oip_update.ROBOTO_NOTICE):
            with browser.open(f"{base}/{name.removeprefix('web/')}", timeout=10) as asset:
                assert asset.read() == (bundle / name).read_bytes()
    report["steps"].append("existing instance explicitly adopts reverified signed license defaults and preserves them on setup retry")


def real_candidate(work, report, args):
    secret, public = keys(work)
    instance = work / "real"
    instance.mkdir(mode=0o700)
    policy = prepare_issuer_policy(work) if args.simulator else None
    kinds = ("standard",) if policy else ()
    bundle = prepare(work / "real-bundle", secret, args.core, args.web, "real-candidate",
                     "1.0.0", simulator=args.simulator, policy=policy, kinds=kinds)
    manifest = (bundle / "manifest.json").read_text()
    if args.real_receipt:
        args.real_receipt.write_text(manifest)
    artefacts = json.loads(manifest)["the_artefacts"]
    report["the_core_sha256"] = artefacts["oip-server"]
    report["the_browser_sha256"] = artefacts["web/main.dart.js"]
    release_key = load_pem_private_key(secret.read_bytes(), password=None)
    if policy:
        refuse_invalid_signed_policy(instance, bundle, public, release_key, report)
    result = run(instance, bundle, public)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["the_status"] == "UPDATED"
    report["steps"].append("built OIP Core, embedded OPC UA simulation, and provided browser assets")
    if args.simulator:
        expected_tools = {"oip_local.py", "oip_ops.py", "oip_recovery.py", "oip_update.py"}
        for directory in (bundle, instance / "current"):
            assert {path.name for path in (directory / "tools").iterdir()} == expected_tools
        for name in ("LICENSE", "THIRD_PARTY_NOTICES.txt"):
            assert (bundle / name).read_bytes() == (ROOT / name).read_bytes()
            assert (instance / "current" / name).read_bytes() == (ROOT / name).read_bytes()
        verify_license_materials(instance / "current")
        report["steps"].append("installed release contains signed source and font materials and only operator tools")
        refuse_single_signer(work, secret, release_key, args, policy, report)
        now = int(time.time()) - 300
        rejected_proof = proof_request(sign_fixture(
            release_key, "2" * 32, now, usage=period("perpetual", now),
        ))
        with socket.socket() as http, socket.socket() as opcua:
            http.bind(("127.0.0.1", 0))
            opcua.bind(("127.0.0.1", 0))
            port, simulator_port = http.getsockname()[1], opcua.getsockname()[1]
        setup = real_setup_command(work, instance, public, port, simulator_port)
        wrong_key = refuse_changed_license_setup(work, instance, setup, policy, release_key, report)
        with tempfile.TemporaryDirectory(prefix="existing-", dir=work) as existing:
            rehearse_signed_policy_install(Path(existing), bundle, public, wrong_key, port, simulator_port, report)
        shutil.rmtree(bundle)
        policy.unlink()
        (work / "pruefschluessel.json").unlink()
        result = subprocess.run(setup, capture_output=True, text=True, timeout=120, cwd=work)
        assert result.returncode == 0, result.stderr
        report["steps"].append("first setup uses signed defaults without a separate issuer policy, registry or token")
        marker = instance / "setup-complete.json"
        completion = marker.read_bytes()
        credential = (instance / "operator.credential").read_bytes()
        marker.unlink()
        result = subprocess.run(setup, capture_output=True, text=True, timeout=120, cwd=work)
        assert result.returncode == 0, result.stderr
        assert marker.read_bytes() == completion, "Setup rewrote the completion record on resume"
        assert (instance / "operator.credential").read_bytes() == credential, "Setup changed the operator identity"
        report["steps"].append("interrupted first setup preserves the trusted defaults and operator identity")
        replacement = work / "replacement-policy.json"
        updated_policy = json.loads(json.loads(manifest)[oip_update.LICENSE_SETUP]["license_policy"])
        updated_policy["kinds"] = ["personal"]
        replacement.write_bytes(json_line(updated_policy))
        second = prepare(work / "real-update", secret, args.core, args.web, "real-update",
                         "1.0.1", simulator=args.simulator, policy=replacement)
        with installed_browser(instance, port, work) as access:
            accepted = install_proof(access, proof_request(PHP_OIP_ARTIFACT), rejected_proof)
            assert_refusal(run(instance, second, public), "local operation")
        report["steps"].append("installed operator confirms the PHP License Center artifact and rejects the update signing key")
        database = instance / "core.sqlite"
        proof_path = instance / "core.license.json"
        initial_database = database.read_bytes()
        initial_configuration = (instance / "core.json").read_bytes()
        assert proof_path.read_bytes() == PHP_OIP_ARTIFACT
        result = run(instance, second, public)
        assert result.returncode == 0, result.stderr
        assert json.loads(result.stdout)["the_status"] == "UPDATED"
        assert (instance / "current").resolve().name == "real-update"
        assert database.read_bytes() == initial_database
        assert (instance / "core.json").read_bytes() == initial_configuration
        report["steps"].append("signed tools setup and start, active-instance refusal, same-schema offline update")
        assert proof_path.read_bytes() == PHP_OIP_ARTIFACT
        result = subprocess.run(setup, capture_output=True, text=True, timeout=120, cwd=work)
        assert result.returncode == 0 and "bereits eingerichtet" in result.stdout, result.stderr
        assert (instance / "core.json").read_bytes() == initial_configuration
        assert json.loads(initial_configuration)["commercial_license_kinds"] == ["standard"]
        with installed_browser(instance, port, work) as (base, browser, _):
            assert api(base, "/api/v2/license", opener=browser) == (200, accepted)
        report["steps"].append("offline update with different signed defaults preserves existing proof, issuer trust and operator permission")

        successor = Ed25519PrivateKey.generate()
        kid, key = public_key(successor)
        rotated_policy = json.loads(json.loads(initial_configuration)["license_policy"])
        rotated_policy["keys"] = {kid: key}
        replacement.write_bytes(json_line(rotated_policy))
        rotate = [*installed_operator(instance), "rotate-license-keys", "--license-policy", str(replacement)]
        review = subprocess.check_output(rotate, text=True, timeout=30, cwd=work)
        approval = json.loads(review)["confirmation"]
        result = subprocess.check_output([*rotate, "--confirm", approval], text=True, timeout=30, cwd=work)
        assert json.loads(result)["status"] == "applied"
        rotated_config = (instance / "core.json").read_bytes()
        assert json.loads(rotated_config) == {
            **json.loads(initial_configuration), "license_policy": replacement.read_text(),
        }
        subprocess.run(setup, check=True, stdout=subprocess.DEVNULL, timeout=120, cwd=work)
        assert (instance / "core.json").read_bytes() == rotated_config
        assert proof_path.read_bytes() == PHP_OIP_ARTIFACT
        with installed_browser(instance, port, work) as (base, browser, headers):
            code, status = api(base, "/api/v2/license", opener=browser)
            assert code == 200 and status["proof_state"] == "invalid" and status["can_manage"] is True
            proof = proof_request(sign_fixture(successor, "5" * 32, now, usage=period("perpetual", now)))
            code, preview = api(base, "/api/v2/license/preview", "POST", proof, headers, browser)
            assert code == 200 and preview["status"]["commercial"] == "active"
        report["steps"].append("signed operator tools rotate trust and repeated setup keeps the new policy")


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
