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
import re
import shutil
import signal
import socket
import ssl
import stat
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import time
from types import SimpleNamespace
from unittest.mock import patch
from urllib.error import HTTPError, URLError
from urllib.request import HTTPSHandler, ProxyHandler, Request, build_opener
import warnings
from zipfile import ZipFile, ZipInfo

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
from oip_local_operator import session, stop, until
from oip_opcua_parity import McpClient, api, free_port


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
    if bundle.suffix == ".zip":
        with ZipFile(bundle) as package:
            names = package.namelist()
            manifest = json.loads(package.read("manifest.json"))
            assert set(names) == set(manifest["the_artefacts"]) | {"manifest.json", "signature"}
    else:
        assert sorted(item.name for item in bundle.iterdir()) == sorted(
            ["oip-server", "web", "tools", "manifest.json", "signature", "LICENSE", "THIRD_PARTY_NOTICES.txt"]
            + (["oip-simulated-server"] if options.get("simulator") else [])
        )
    return bundle


def command(instance, bundle, public, *more, updater=UPDATER):
    return [sys.executable, str(updater), "--instance", str(instance), "--bundle",
            str(bundle), "--public-key", str(public), *more]


def run(instance, bundle, public, *more, updater=UPDATER):
    return subprocess.run(command(instance, bundle, public, *more, updater=updater),
                          capture_output=True, text=True, timeout=120)


def assert_refusal(result, explanation, *, exit_code=2):
    assert result.returncode == exit_code and explanation in result.stderr, (
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


def check_zip_refusals(work, instance, bundle, public, wrong_key):
    members = {path.relative_to(bundle).as_posix(): path.read_bytes()
               for path in bundle.rglob("*") if path.is_file()}

    def make_zip(name, fields):
        target = work / f"{name}.zip"
        with ZipFile(target, "w") as archive:
            for entry, contents in fields:
                archive.writestr(entry, contents)
        return target

    verified = make_zip("signed-flat", members.items())
    assert_refusal(run(instance, verified, wrong_key, "--dry-run"), "signature")
    cases = (
        ("mutated", {**members, oip_update.OPCUA_SOURCE: b"altered"}.items(), "digest"),
        ("unsigned", [*members.items(), ("web/unlisted.js", b"extra")], "signed manifest"),
        ("missing", [(name, value) for name, value in members.items() if name != oip_update.ROBOTO_NOTICE],
         "signed manifest"),
        ("unsafe", [*members.items(), ("web/../outside", b"extra")], "unsafe or duplicate entry"),
    )
    for name, fields, explanation in cases:
        assert_refusal(run(instance, make_zip(name, fields), public), explanation)

    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", message="Duplicate name:")
        duplicate = make_zip("duplicate", [*members.items(), ("manifest.json", members["manifest.json"])])
    assert_refusal(run(instance, duplicate, public), "unsafe or duplicate entry")
    link = ZipInfo(oip_update.ROBOTO_NOTICE)
    link.create_system = 3
    link.external_attr = (stat.S_IFLNK | 0o777) << 16
    symlink = make_zip("symlink", [(link if name == link.filename else name, value)
                                  for name, value in members.items()])
    assert_refusal(run(instance, symlink, public), "unsafe or duplicate entry")
    truncated = work / "truncated.zip"
    truncated.write_bytes(verified.read_bytes()[:-22])
    assert_refusal(run(instance, truncated, public), "ZIP package is damaged")
    with patch.object(oip_update, "MAX_ZIP_DIRECTORY", 128):
        try:
            with oip_update.open_package(verified):
                raise AssertionError("The oversized central directory was accepted")
        except oip_update.Refused as error:
            assert "directory exceeds" in str(error)


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
    second = prepare(work / "second.zip", secret, core, web, "fixture-two", "1.10.0", simulator=core)
    unchanged = second.read_bytes()
    refuse_replace = subprocess.run(
        prepare_command(second, secret, core, web, "fixture-two", "1.10.0", simulator=core),
        capture_output=True, text=True, timeout=120,
    )
    assert_refusal(refuse_replace, "output path already exists")
    assert second.read_bytes() == unchanged
    assert run(instance, second, public, "--dry-run").returncode == 0
    assert current.resolve().name == "fixture-one"
    result = run(instance, second, public)
    assert result.returncode == 0, result.stderr
    assert current.resolve().name == "fixture-two"
    assert (instance / "previous").resolve().name == "fixture-one"
    assert_refusal(run(instance, second, public, "--dry-run"), "strictly newer")
    assert database.read_bytes() == initial_database
    assert config.read_bytes() == initial_config
    report["steps"].append("signed ZIP created, verified and installed without unpacking, preserving data and configuration")

    next_bundle = prepare(work / "next", secret, core, web, "fixture-next", "1.10.1", simulator=core)
    wrong_key = work / "wrong.pem"
    wrong_key.write_bytes(Ed25519PrivateKey.generate().public_key().public_bytes(
        Encoding.PEM, PublicFormat.SubjectPublicKeyInfo))
    assert_refusal(run(instance, next_bundle, wrong_key), "signature")
    report["steps"].append("untrusted signer refused")
    check_zip_refusals(work, instance, next_bundle, public, wrong_key)
    assert current.resolve().name == "fixture-two"
    assert not list((instance / "versions").glob(".staged-*"))
    report["steps"].append("ZIP rejects unsigned bytes, bad signatures, duplicate, missing, extra or unsafe entries and damaged archives")

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


def started_core_revision(base, browser):
    code, system = api(base, "/api/v2/support-package?infrastructure=local-infra", opener=browser)
    assert code == 200, system
    expected = subprocess.check_output(
        ["git", "describe", "--always", "--abbrev=40", "--dirty"], cwd=ROOT, text=True,
    ).strip()
    revision = system["build_revision"]
    assert revision == expected, revision
    return revision


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


def refuse_changed_license_setup(work, instance, setup, policy, release_key, wrong_key, report):
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
    result = subprocess.run([*setup[:-1], str(wrong_key)], capture_output=True, text=True,
                            timeout=30, cwd=work)
    assert result.returncode == 1 and "signature" in result.stderr, result.stderr
    assert not any((instance / name).exists() for name in ("setup.json", "core.json", "core.sqlite"))
    report["steps"].append("first setup refuses tampered, ambiguous, and foreign-signed license defaults")


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
    report["steps"].append("existing instance adopts reverified license defaults and serves the exact signed license materials")


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
        with socket.socket() as http, socket.socket() as opcua:
            http.bind(("127.0.0.1", 0))
            opcua.bind(("127.0.0.1", 0))
            port, simulator_port = http.getsockname()[1], opcua.getsockname()[1]
        other_signer = work / "other-signer"
        other_signer.mkdir(mode=0o700)
        _, wrong_key = keys(other_signer)
        with tempfile.TemporaryDirectory(prefix="existing-", dir=work) as existing:
            rehearse_signed_policy_install(Path(existing), bundle, public, wrong_key, port, simulator_port, report)
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
        setup = real_setup_command(work, instance, public, port, simulator_port)
        refuse_changed_license_setup(work, instance, setup, policy, release_key, wrong_key, report)
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
        successor = Ed25519PrivateKey.generate()
        kid, key = public_key(successor)
        rotated_policy = json.loads(json.loads(manifest)[oip_update.LICENSE_SETUP]["license_policy"])
        rotated_policy["keys"] = {kid: key}
        replacement.write_bytes(json_line(rotated_policy))
        second = prepare(work / "real-update.zip", secret, args.core, args.web, "real-update",
                         "1.0.1", simulator=args.simulator, policy=replacement)
        updater = instance / "current/tools/oip_update.py"
        with installed_browser(instance, port, work) as access:
            accepted = install_proof(access, proof_request(PHP_OIP_ARTIFACT), rejected_proof)
            assert_refusal(run(instance, second, public, updater=updater), "local operation")
        report["steps"].append("installed operator confirms the PHP License Center artifact and rejects the update signing key")
        database = instance / "core.sqlite"
        proof_path = instance / "core.license.json"
        initial_database = database.read_bytes()
        initial_configuration = (instance / "core.json").read_bytes()
        assert proof_path.read_bytes() == PHP_OIP_ARTIFACT
        result = run(instance, second, public, "--dry-run", updater=updater)
        assert result.returncode == 0, result.stderr
        assert json.loads(result.stdout)["the_status"] == "VERIFIED"
        result = run(instance, second, public, updater=updater)
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
        report["steps"].append("offline ZIP update with different signed defaults preserves existing proof, issuer trust and operator permission")

        config_path = instance / "core.json"

        def rotate(package_key=public, *options):
            command = [*installed_operator(instance), "rotate-license-keys",
                       "--package-public-key", str(package_key), *options]
            return subprocess.run(command, capture_output=True, text=True, timeout=30, cwd=work)

        assert_refusal(rotate(), "changes the existing commercial license assignments", exit_code=1)
        assert config_path.read_bytes() == initial_configuration
        report["steps"].append("signed package with changed commercial assignments cannot rotate trust")
        second.unlink()
        third = prepare(work / "key-rollover.zip", secret, args.core, args.web, "key-rollover",
                        "1.0.2", simulator=args.simulator, policy=replacement, kinds=("standard",))
        result = run(instance, third, public, updater=updater)
        assert result.returncode == 0, result.stderr
        assert config_path.read_bytes() == initial_configuration
        with installed_browser(instance, port, work) as (base, browser, _):
            assert api(base, "/api/v2/license", opener=browser) == (200, accepted)
            assert_refusal(rotate(), "already running", exit_code=1)

        assert_refusal(rotate(wrong_key), "signature", exit_code=1)
        review = rotate()
        assert review.returncode == 0, review.stderr
        preview = json.loads(review.stdout)
        assert (preview["status"], preview["source"]) == ("review", "verified-installed-package")
        assert preview["added_fingerprints"] == [hashlib.sha256(decode(key)).hexdigest()]
        approval = ("--confirm", preview["confirmation"])
        using_policy_file = subprocess.run(
            [*installed_operator(instance), "rotate-license-keys", "--license-policy", str(replacement), *approval],
            capture_output=True, text=True, timeout=30, cwd=work,
        )
        assert_refusal(using_policy_file, "confirmation is invalid", exit_code=1)
        notice = instance / "current" / oip_update.ROBOTO_NOTICE
        original_notice = notice.read_bytes()
        try:
            notice.write_bytes(original_notice + b"changed during review")
            assert_refusal(rotate(public, *approval), "digest", exit_code=1)
        finally:
            notice.write_bytes(original_notice)
        packaged_core = instance / "current" / "oip-server"
        saved_core = work / "original-core"
        packaged_core.rename(saved_core)
        try:
            packaged_core.write_bytes(b"This is not the signed Core binary.")
            packaged_core.chmod(0o700)
            assert_refusal(rotate(public, *approval), "digest", exit_code=1)
        finally:
            saved_core.replace(packaged_core)
        assert config_path.read_bytes() == initial_configuration
        result = rotate(public, *approval)
        assert result.returncode == 0 and json.loads(result.stdout)["status"] == "applied", result.stderr
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
            code, accepted = api(base, "/api/v2/license/apply", "POST",
                                 {"confirmation": preview["confirmation"]}, headers, browser)
            assert code == 200 and accepted["proof_state"] == "verified" and accepted["commercial"] == "active"
        with installed_browser(instance, port, work) as (base, browser, _):
            assert api(base, "/api/v2/license", opener=browser) == (200, accepted)
            with browser.open(f"{base}/main.dart.js", timeout=10) as asset:
                served_sha256 = hashlib.sha256(asset.read()).hexdigest()
            assert served_sha256 == artefacts["web/main.dart.js"]
            report["the_served_browser_sha256"] = served_sha256
        assert json.loads(rotate().stdout)["status"] == "unchanged"
        report["steps"].append("confirmed offline rotation revalidates the installed package and accepts the successor proof across restart")


def rehearse_issuer_handoff(work, report, args):
    with args.issuer_handoff.open("rb") as source:
        handoff = json.loads(source.read(64 * 1024 + 1))
        assert source.tell() <= 64 * 1024, "The test handoff exceeds 64 KiB"
    assert handoff["schema"] == "oip-license-center-test-handoff-v2"
    assert handoff["issuer_checkout_clean"] is True
    for field in ("issuer_revision", "issuer_tree"):
        assert re.fullmatch(r"[a-f0-9]{40}", handoff[field]), field
        report[field] = handoff[field]
    assert report["the_working_tree_is_clean"], "Build and test a clean OIP checkout"
    registry, proof, renewal, foreign = (
        decode(handoff[name]) for name in ("registry", "oip_proof", "oip_renewal", "odp_proof")
    )
    for name, data in (("registry", registry), ("oip_proof", proof),
                       ("oip_renewal", renewal), ("odp_proof", foreign)):
        report[name + "_sha256"] = hashlib.sha256(data).hexdigest()

    registry_file = work / "issuer-registry.json"
    registry_file.write_bytes(registry)
    policy = work / "license-policy.json"
    policy.write_bytes(subprocess.check_output(
        [sys.executable, "-B", ROOT / "tools/oip_local.py", "prepare-license-policy",
         "--registry", registry_file, "--key-fingerprint", handoff["oip_fingerprint"],
         "--kind", "standard", "--right", "sites=20"],
        cwd=work, timeout=30,
    ))
    trusted_keys = set(json.loads(policy.read_bytes())["keys"])
    assert trusted_keys == {json.loads(proof)["kid"]}
    assert json.loads(foreign)["kid"] not in trusted_keys
    report["steps"].append("approved OIP fingerprint selects only the matching key in the License Center export")

    secret, public = keys(work)
    instance = work / "recipient"
    instance.mkdir(mode=0o700)
    bundle = prepare(work / "recipient.zip", secret, args.core, args.web, report["the_revision"],
                     "1.0.0", simulator=args.simulator, policy=policy, kinds=("standard",))
    with ZipFile(bundle) as archive:
        assets = json.loads(archive.read("manifest.json"))["the_artefacts"]
    report["the_core_sha256"] = assets["oip-server"]
    report["the_browser_sha256"] = assets["web/main.dart.js"]
    checked = run(instance, bundle, public, "--dry-run")
    assert checked.returncode == 0 and json.loads(checked.stdout)["the_status"] == "VERIFIED", checked.stderr
    installed = run(instance, bundle, public)
    assert installed.returncode == 0 and json.loads(installed.stdout)["the_status"] == "UPDATED", installed.stderr
    for path in (registry_file, policy, bundle, secret):
        path.unlink()
    port, simulator_port = free_port(), free_port()
    while simulator_port == port:
        simulator_port = free_port()
    subprocess.run(real_setup_command(work, instance, public, port, simulator_port),
                   check=True, stdout=subprocess.DEVNULL, timeout=120, cwd=work)
    report["steps"].append("fresh offline installation adopts issuer trust from the signed ZIP")

    proof_file = work / "freshly-issued.license.json"
    proof_file.write_bytes(proof)
    license_path = "/api/v2/license"

    def check_license_ui(base, mode, screenshot):
        login = subprocess.check_output(
            [instance / "current" / "oip-server", "--browser-login",
             "--ipc-socket", instance / "ipc.sock", "--ipc-credential", instance / "operator.credential"],
            text=True, timeout=10,
        )
        subprocess.run(
            ["node", ROOT / "apps/flutter/test/browser_license.mjs", base, proof_file,
             args.evidence / screenshot, mode],
            input=json.loads(login)["login_code"], text=True, check=True, timeout=150,
        )

    with installed_browser(instance, port, work) as (base, browser, headers):
        report["the_core_build_revision"] = started_core_revision(base, browser)
        code, before = api(base, license_path, opener=browser)
        assert code == 200 and before["proof_state"] == "missing" and before["can_manage"] is True
        code, denied = api(base, license_path + "/preview", "POST",
                           proof_request(foreign), headers, browser)
        assert code == 400 and denied["code"] == "LICENSE_PROOF_INVALID"
        assert api(base, license_path, opener=browser) == (200, before)
        check_license_ui(base, "import", "issuer-handoff.png")
        code, after = api(base, license_path, opener=browser)
        assert code == 200 and after["proof_state"] == "verified"
        assert after["commercial"] == "active" and after["support"] == "ended"
        assert after["revision"] == 1
        assert (instance / "core.license.json").read_bytes() == proof
        with browser.open(f"{base}/main.dart.js", timeout=10) as asset:
            served = hashlib.sha256(asset.read()).hexdigest()
        assert served == assets["web/main.dart.js"]
        report["the_served_browser_sha256"] = served
    report["steps"].append("REST rejects the issued ODP proof and the compiled UI imports the exact OIP proof after confirmation")

    with installed_browser(instance, port, work) as (base, browser, headers):
        assert api(base, license_path, opener=browser) == (200, after)
        restarted = time.time_ns() // 1_000_000

        def received_after_restart():
            code, values = api(base, "/api/v2/observations?source=local-simulation", opener=browser)
            return code == 200 and any((value["timestamps"]["received"] or 0) > restarted for value in values)

        until(received_after_restart, "No fresh simulator observation with ended support")
        report["steps"].append("the restarted OIP Core receives fresh simulator data with ended support")

        mcp = McpClient(instance / "current" / "oip-server", instance / "ipc.sock",
                        instance / "operator.credential", "operator")
        try:
            assert mcp.call("license_status_read") == after
            preview = mcp.call("license_proof_preview", proof_request(renewal))
            renewed = {**after, "revision": 2, "support": "active"}
            assert preview["status"] == renewed
            assert api(base, license_path, opener=browser) == (200, after)
            assert api(base, license_path + "/apply", "POST", {"confirmation": preview["confirmation"]},
                       headers, browser) == (200, renewed)
            assert mcp.call("license_status_read") == renewed
            assert (instance / "core.license.json").read_bytes() == renewal
        finally:
            mcp.close()
    report["steps"].append("MCP reviews the issued renewal and REST confirms it without changing the commercial entitlement")

    with installed_browser(instance, port, work) as (base, browser, _):
        assert api(base, license_path, opener=browser) == (200, renewed)
        check_license_ui(base, "superseded", "issuer-handoff-superseded.png")
        assert (instance / "core.license.json").read_bytes() == renewal
    report["steps"].append("the compiled UI refuses the old issued file after restart and preserves the renewal unchanged")


def rehearse_publication(work, report, args):
    secret, public = keys(work)
    policy = prepare_issuer_policy(work)
    bundle = prepare(work / "approved.zip", secret, args.core, args.web, report["the_revision"],
                     "1.2.3", simulator=args.simulator, policy=policy, kinds=("standard",))
    with bundle.open("rb") as source:
        approved = oip_update.digest_of(source)
    web_root = work / "public"
    command = [sys.executable, "-B", ROOT / "tools/oip_publication.py",
               "--bundle", bundle, "--output", web_root]

    def stage(key, digest):
        return subprocess.run([*command, "--public-key", key, "--sha256", digest],
                              capture_output=True, text=True, timeout=60)

    other = work / "other"
    other.mkdir(mode=0o700)
    _, wrong_key = keys(other)
    assert_refusal(stage(public, "0" * 64), "does not match the approved SHA-256")
    assert_refusal(stage(wrong_key, approved), "signature does not match")
    assert not web_root.exists()
    result = stage(public, approved)
    assert result.returncode == 0, result.stderr
    staged = json.loads(result.stdout)
    expected_path = "/oip/macos-arm64/1.2.3/oip-local-darwin-arm64.zip"
    assert staged["the_status"] == "STAGED" and staged["the_public_path"] == expected_path
    assert staged["the_zip_sha256"] == approved
    assert_refusal(stage(public, approved), "already exists")
    assert sorted(path.name for path in (web_root / expected_path.lstrip("/")).parent.iterdir()) == [
        ".htaccess", "oip-local-darwin-arm64.zip",
    ]
    report["steps"].append("the private publication stage only accepts the approved ZIP and trusted signer and refuses replacement")

    bootstrap = work / "first-install"
    export = subprocess.run([sys.executable, "-B", ROOT / "tools/oip_publication.py", "--bundle", bundle,
                             "--bootstrap", bootstrap, "--public-key", public, "--sha256", approved],
                            capture_output=True, text=True, timeout=60)
    assert export.returncode == 0, export.stderr
    bootstrap_receipt = json.loads(export.stdout)
    assert bootstrap_receipt["the_status"] == "BOOTSTRAP_READY"
    for field in ("the_zip_sha256", "the_manifest_sha256", "the_license_sha256", "the_revision", "the_version"):
        assert bootstrap_receipt[field] == staged[field]
    bootstrap_files = {"oip_update.py", "oip_ops.py", "update-public.pem", "LICENSE", "THIRD_PARTY_NOTICES.txt"}
    assert {path.name for path in bootstrap.iterdir()} == bootstrap_files | {"SHA256SUMS"}

    certificate, tls_key = work / "tls.crt", work / "tls.key"
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                    "-subj", "/CN=localhost", "-addext", "subjectAltName=IP:127.0.0.1",
                    "-keyout", tls_key, "-out", certificate], capture_output=True, check=True, timeout=15)
    tls_port, http_port = free_port(), free_port()
    while http_port == tls_port:
        http_port = free_port()
    config, log = work / "httpd.conf", work / "apache.log"
    modules = ("mpm_prefork", "unixd", "authz_core", "headers", "ssl")
    config.write_text("\n".join(f"LoadModule {module}_module /usr/libexec/apache2/mod_{module}.so"
                                for module in modules) + f"""
ServerRoot "{work}"
DefaultRuntimeDir "{work}"
Mutex file:{work} default
ServerName localhost
Listen 127.0.0.1:{http_port}
Listen 127.0.0.1:{tls_port} https
PidFile "{work / 'apache.pid'}"
ErrorLog "{log}"
DocumentRoot "{web_root}"
EnableSendfile Off
EnableMMAP Off
<Directory "{web_root}">
    Options None
    AllowOverride AuthConfig FileInfo Options
    Require all granted
</Directory>
<VirtualHost 127.0.0.1:{tls_port}>
    SSLEngine on
    SSLCertificateFile "{certificate}"
    SSLCertificateKeyFile "{tls_key}"
</VirtualHost>
""")
    client = build_opener(ProxyHandler({}), oip_update.LocalProbe(),
                          HTTPSHandler(context=ssl.create_default_context(cafile=str(certificate))))
    base = f"https://127.0.0.1:{tls_port}"
    downloaded = bootstrap / "oip-local-darwin-arm64.zip"
    # Simulate an accidental additional file to verify the directory rule.
    accidental = web_root / expected_path.lstrip("/")
    accidental.with_name("private-fixture.txt").write_text("Generated test data\n")
    with (work / "apache-start.log").open("wb") as startup:
        # Apache signals its process group on shutdown.
        process = subprocess.Popen(["/usr/sbin/httpd", "-f", config, "-DFOREGROUND"],
                                   stdout=startup, stderr=startup, start_new_session=True)
        try:
            def ready():
                assert process.poll() is None, (work / "apache-start.log").read_text()
                try:
                    with client.open(Request(base + expected_path, method="HEAD"), timeout=2) as response:
                        return response.status == 200
                except HTTPError:
                    raise
                except URLError:
                    return False

            until(ready, "Apache HTTPS did not start", timeout=10)
            with client.open(base + expected_path, timeout=15) as download:
                assert download.headers["Content-Type"] == "application/zip"
                assert download.headers["Cache-Control"] == "public, max-age=31536000, immutable"
                assert download.headers["X-Content-Type-Options"] == "nosniff"
                oip_update.write_release_file(downloaded, download,
                                              limit=bundle.stat().st_size)
            for url in (
                base + expected_path + "/extra",
                base + expected_path.rsplit("/", 1)[0] + "/",
                base + expected_path.rsplit("/", 1)[0] + "/.htaccess",
                base + expected_path.rsplit("/", 1)[0] + "/private-fixture.txt",
                f"http://127.0.0.1:{http_port}" + expected_path,
            ):
                try:
                    with client.open(url, timeout=5) as unexpected:
                        raise AssertionError(f"Apache exposed {url} with status {unexpected.status}")
                except HTTPError as response:
                    with response:
                        assert response.code in {403, 404}, (response.code, url)
        finally:
            stop(process)
    with downloaded.open("rb") as received:
        assert oip_update.digest_of(received) == approved
    report["steps"].append("anonymous certificate-validated HTTPS serves the exact approved ZIP with immutable caching and blocks HTTP and other files")

    verify_first_install_files(bootstrap, bootstrap_receipt["the_bootstrap_manifest_sha256"],
                               {"oip_update.py", "oip_ops.py", "update-public.pem", downloaded.name})
    report["the_bootstrap"] = bootstrap_receipt
    report["steps"].append("an independently delivered checksum authenticates both verifier scripts, the key and the exact first-install ZIP before execution")

    instance = work / "recipient"
    instance.mkdir(mode=0o700)
    verifier, key = bootstrap / "oip_update.py", bootstrap / "update-public.pem"
    checked = run(instance, downloaded, key, "--dry-run", updater=verifier)
    assert checked.returncode == 0 and json.loads(checked.stdout)["the_status"] == "VERIFIED", checked.stderr
    installed = run(instance, downloaded, key, updater=verifier)
    assert installed.returncode == 0 and json.loads(installed.stdout)["the_status"] == "UPDATED", installed.stderr
    current = instance / "current"
    assert current.resolve().name == report["the_revision"]
    manifest = json.loads((current / "manifest.json").read_bytes())
    assets = manifest["the_artefacts"]
    core_port, source_port = free_port(), free_port()
    while source_port == core_port:
        source_port = free_port()
    subprocess.run(real_setup_command(work, instance, key, core_port, source_port),
                   check=True, stdout=subprocess.DEVNULL, timeout=120, cwd=work)
    with installed_browser(instance, core_port, work) as (base, browser, _):
        report["the_core_build_revision"] = started_core_revision(base, browser)
        with browser.open(f"{base}/main.dart.js", timeout=10) as asset:
            served = oip_update.digest_of(asset)
        assert served == assets["web/main.dart.js"]
        report["the_served_browser_sha256"] = served
    report["the_core_sha256"] = assets["oip-server"]
    report["the_publication"] = staged
    report["steps"].append("after stopping the HTTPS host, the same updater verifies and installs the downloaded package offline")


def verify_first_install_files(directory, pin, files):
    check = ["/usr/bin/shasum", "-a", "256", "-c", "--strict"]

    def check_pin(value):
        return subprocess.run([*check, "-"], input=f"{value}  SHA256SUMS\n", cwd=directory,
                              text=True, capture_output=True, timeout=10)

    def check_files():
        return subprocess.run([*check, "SHA256SUMS"], cwd=directory, text=True,
                              capture_output=True, timeout=10)

    assert check_pin("0" * 64).returncode == 1
    pinned = check_pin(pin)
    assert pinned.returncode == 0 and "SHA256SUMS: OK" in pinned.stdout, pinned.stderr
    verified = check_files()
    assert verified.returncode == 0 and all(f"{name}: OK" in verified.stdout for name in files), verified.stderr
    for name in sorted(files | {"SHA256SUMS"}):
        path = directory / name
        with path.open("r+b") as handle:
            handle.seek(0, os.SEEK_END)
            length = handle.tell()
            handle.write(b"altered")
            handle.flush()
            try:
                mismatch = check_pin(pin) if name == "SHA256SUMS" else check_files()
                assert mismatch.returncode == 1 and f"{name}: FAILED" in mismatch.stdout, mismatch.stdout
            finally:
                handle.truncate(length)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, default=ROOT / "target" / "oip-update")
    parser.add_argument("--core", type=Path)
    parser.add_argument("--web", type=Path)
    parser.add_argument("--simulator", type=Path)
    parser.add_argument("--real-receipt", type=Path)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--issuer-handoff", type=Path,
                        help="Only rehearse fresh synthetic License Center browser exports")
    action.add_argument("--publication", action="store_true",
                        help="Only rehearse publication on local Apache HTTPS on macOS ARM64")
    args = parser.parse_args()
    if bool(args.core) != bool(args.web):
        parser.error("--core and --web must be passed together")
    if args.issuer_handoff and (not args.core or not args.simulator or args.real_receipt):
        parser.error("--issuer-handoff requires --core, --web and --simulator and excludes --real-receipt")
    if args.publication and (not args.core or not args.simulator or args.real_receipt):
        parser.error("--publication requires --core, --web and --simulator and excludes --real-receipt")
    args.evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-update-v2", "steps": [], "the_problems": [],
              "the_target": oip_update.host_target()}
    for field, value in (("the_revision", "HEAD"), ("the_tree", "HEAD^{tree}")):
        report[field] = subprocess.check_output(["git", "rev-parse", value], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    with tempfile.TemporaryDirectory(prefix="oip-update-test-", dir="/tmp") as temporary:
        work = Path(temporary).resolve()
        try:
            if args.publication:
                report["the_profile"] = "local-apache-https-to-offline-oip"
                rehearse_publication(work, report, args)
            elif args.issuer_handoff:
                report["the_profile"] = "synthetic-issuer-to-installed-oip"
                rehearse_issuer_handoff(work, report, args)
            else:
                rehearse(work, report)
                if args.core:
                    real_candidate(work, report, args)
        except (AssertionError, KeyError, OSError, subprocess.SubprocessError, ValueError) as error:
            report["the_problems"].append(str(error))
    report["the_status"] = "FAIL" if report["the_problems"] else "PASS"
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    receipt = "update.json"
    if args.publication:
        receipt = "publication.json"
    if args.issuer_handoff:
        receipt = "issuer-handoff.json"
    (args.evidence / receipt).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report["the_status"], "the_steps": len(report["steps"]),
                      "the_problems": report["the_problems"]}, indent=2))
    return 0 if report["the_status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
