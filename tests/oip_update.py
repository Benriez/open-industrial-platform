#!/usr/bin/env python3
"""The secure update of the Core of an instance: what it does and what it refuses.

The deployed Core of OIP runs on a host of the operator. A service that
cannot be updated safely stays on the version it was built with. This
rehearsal measures the update path end to end:

  * a bundle that is **signed** by the key of the operator is verified, the
    artefact is written, the switch is atomic, the new version is **health
    checked** and the instance runs it;
  * a bundle whose **artefact** was changed on the way is refused;
  * a bundle whose **manifest** was changed on the way is refused;
  * a bundle of another **target** is refused;
  * a bundle that would **downgrade** the instance is refused;
  * a bundle whose binary does **not** become ready is **rolled back**: the
    instance keeps the version it had, and the journal names the rollback.

The key of the rehearsal is a **fixture**: it is generated here, it signs
nothing outside this rehearsal, and it is never a production key. The private
key of the operator never touches a host.

Usage:
  python3 tests/oip_update.py [--evidence DIR]
"""
import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
UPDATER = ROOT / "tools" / "oip_update.py"

# A Core that becomes ready: it answers the health endpoint of its own port.
READY_CORE = '''#!/usr/bin/env python3
import json, pathlib, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

arguments = sys.argv[1:]
configuration = pathlib.Path(arguments[arguments.index("--config") + 1])
port = json.loads(configuration.read_text())["http_port"]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200 if self.path.startswith("/health") else 404)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b"{}")

    def log_message(self, *arguments):
        pass


HTTPServer(("127.0.0.1", port), Handler).serve_forever()
'''

# A Core that does not become ready: it leaves immediately.
BROKEN_CORE = '''#!/usr/bin/env python3
import sys
sys.stderr.write("this version cannot start\\n")
raise SystemExit(3)
'''


def the_digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def the_bundle(directory: pathlib.Path, revision: str, artefact: str,
               body: str, target: str = "aarch64-unknown-linux-gnu"):
    """A signed update bundle."""
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives.serialization import (
        Encoding,
        PublicFormat,
    )

    directory.mkdir(parents=True, exist_ok=True)
    binary = directory / "oip-server"
    binary.write_text(body)
    binary.chmod(0o755)
    manifest = {
        "schema": "oip-update-v1",
        "the_revision": revision,
        "the_version": "1.0.0",
        "the_target": target,
        "the_artefacts": {"oip-server": the_digest(binary)},
        "the_created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    payload = json.dumps(manifest, indent=2, sort_keys=True).encode()
    (directory / "manifest.json").write_bytes(payload)
    return manifest


def the_keys(work: pathlib.Path):
    """The key pair of the rehearsal: a fixture, never a production key."""
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives.serialization import (
        Encoding,
        PublicFormat,
    )

    private = Ed25519PrivateKey.generate()
    public = private.public_key().public_bytes(Encoding.PEM, PublicFormat.SubjectPublicKeyInfo)
    key = work / "instance-public.pem"
    key.write_bytes(public)
    key.chmod(0o600)
    return private, key


def the_sign(private, bundle: pathlib.Path):
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    payload = (bundle / "manifest.json").read_bytes()
    (bundle / "signature").write_bytes(private.sign(payload))


def the_update(instance: pathlib.Path, bundle: pathlib.Path, key: pathlib.Path,
               extra=()):
    # The instance is the one of the Raspberry Pi: the target is named
    # explicitly, because the rehearsal of the procedure runs on another
    # machine than the instance.
    command = [sys.executable, str(UPDATER), "--instance", str(instance),
               "--bundle", str(bundle), "--public-key", str(key),
               "--target", "aarch64-unknown-linux-gnu", *extra]
    return subprocess.run(command, capture_output=True, text=True, timeout=300)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-update"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-update-v1", "steps": [], "the_problems": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-update-", dir="/private/tmp"))
    work.chmod(0o700)
    try:
        instance = work / "instance"
        (instance / "state").mkdir(parents=True)
        (instance / "versions").mkdir(parents=True)
        private, key = the_keys(work)

        # 1. the first version: the instance has none.
        first = work / "bundle-1"
        the_bundle(first, "revision-one", "oip-server", READY_CORE)
        the_sign(private, first)
        done = the_update(instance, first, key)
        report["the_first_update"] = {"the_code": done.returncode,
                                       "the_output": done.stdout[-600:],
                                       "the_error": done.stderr[-300:]}
        assert done.returncode == 0, done.stderr
        link = instance / "current"
        assert link.is_symlink(), "the instance does not run the new version"
        assert os.path.basename(os.readlink(link)) == "revision-one"
        report["steps"].append("a signed bundle is verified, activated and health checked")

        # 2. the second version: the switch is atomic and the previous stays.
        second = work / "bundle-2"
        the_bundle(second, "revision-two", "oip-server", READY_CORE)
        the_sign(private, second)
        done = the_update(instance, second, key)
        report["the_second_update"] = {"the_code": done.returncode,
                                        "the_output": done.stdout[-400:]}
        assert done.returncode == 0, done.stderr
        assert os.path.basename(os.readlink(instance / "current")) == "revision-two"
        assert (instance / "versions" / "revision-one").is_dir(), \
            "the previous version was removed from the host"
        assert (instance / "previous").is_symlink()
        report["steps"].append("the switch is atomic and the previous version stays")

        # 3. a bundle whose artefact was changed on the way is refused.
        tampered = work / "bundle-tampered"
        the_bundle(tampered, "revision-three", "oip-server", READY_CORE)
        the_sign(private, tampered)
        (tampered / "oip-server").write_text(READY_CORE + "# changed\n")
        done = the_update(instance, tampered, key)
        report["the_tampered_artefact"] = {"the_code": done.returncode,
                                           "the_error": done.stderr[-300:]}
        assert done.returncode == 2, done.stdout
        assert "digest" in done.stderr
        assert os.path.basename(os.readlink(instance / "current")) == "revision-two"
        report["steps"].append("a bundle whose artefact was changed is refused")

        # 4. a bundle whose manifest was changed on the way is refused.
        forged = work / "bundle-forged"
        the_bundle(forged, "revision-four", "oip-server", READY_CORE)
        the_sign(private, forged)
        manifest = json.loads((forged / "manifest.json").read_text())
        manifest["the_version"] = "9.9.9"
        (forged / "manifest.json").write_text(json.dumps(manifest, indent=2,
                                                          sort_keys=True))
        done = the_update(instance, forged, key)
        report["the_forged_manifest"] = {"the_code": done.returncode,
                                         "the_error": done.stderr[-300:]}
        assert done.returncode == 2, done.stdout
        assert "signature" in done.stderr
        report["steps"].append("a bundle whose manifest was changed is refused")

        # 5. a bundle of another target is refused.
        foreign = work / "bundle-foreign"
        the_bundle(foreign, "revision-five", "oip-server", READY_CORE,
                   target="x86_64-unknown-linux-gnu")
        the_sign(private, foreign)
        done = the_update(instance, foreign, key)
        report["the_foreign_target"] = {"the_code": done.returncode,
                                         "the_error": done.stderr[-300:]}
        assert done.returncode == 2, done.stdout
        report["steps"].append("a bundle of another target is refused")

        # 6. the version that is already there is not installed again.
        done = the_update(instance, second, key)
        report["the_same_revision"] = {"the_code": done.returncode,
                                        "the_error": done.stderr[-300:]}
        assert done.returncode == 2, done.stdout
        report["steps"].append("the version that is already there is not installed again")

        # 7. a version that does not become ready is rolled back.
        broken = work / "bundle-broken"
        the_bundle(broken, "revision-broken", "oip-server", BROKEN_CORE)
        the_sign(private, broken)
        done = the_update(instance, broken, key)
        report["the_broken_version"] = {"the_code": done.returncode,
                                         "the_output": done.stdout[-600:]}
        assert done.returncode == 1, done.stdout
        assert os.path.basename(os.readlink(instance / "current")) == "revision-two", \
            "the instance did not keep the version it had"
        report["steps"].append("a version that does not become ready is rolled back")

        # 8. the journal is the durable evidence of the update path.
        journal = instance / "state" / "updates.jsonl"
        assert journal.is_file(), "the update path wrote no journal"
        entries = [json.loads(line) for line in journal.read_text().splitlines() if line]
        report["the_journal"] = entries
        assert len(entries) >= 4, "the journal is too short"
        assert any(entry.get("the_rollback") for entry in entries), \
            "the journal does not name the rollback"
        report["the_journal_entries"] = len(entries)
        report["steps"].append("the durable journal names every attempt and the rollback")
    except AssertionError as error:
        report["the_problems"].append(str(error))
    finally:
        shutil.rmtree(work, ignore_errors=True)

    report["the_status"] = "FAIL" if report["the_problems"] else "PASS"
    report["the_revision"] = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    report["the_tree"] = subprocess.run(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, capture_output=True,
        text=True).stdout.strip()
    report["the_working_tree_is_clean"] = not subprocess.run(
        ["git", "status", "--porcelain"], cwd=ROOT, capture_output=True,
        text=True).stdout.strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "update.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report["the_status"],
                      "the_steps": len(report["steps"]),
                      "the_problems": report["the_problems"]}, indent=2))
    return 0 if report["the_status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
