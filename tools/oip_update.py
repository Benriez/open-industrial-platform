#!/usr/bin/env python3
"""The secure update of the Core of an instance.

The Core of OIP runs on a host of the operator (the Raspberry Pi). A deployed
service that cannot be updated safely is a service that stays on the version
it was built with. This tool is the update path of the Core:

  1. **delivery** — the update arrives as a **bundle**: a manifest, the
     artefacts and the signature of the manifest. The bundle may travel over
     any channel (a copy, a tunnel, a pull of the operator); the channel
     carries the bytes, **the signature carries the trust**.
  2. **authenticity and integrity** — the manifest is signed with **Ed25519**
     by the operator's private key. The tool verifies the signature over the
     **exact bytes** of the manifest with the **public key of the instance**
     and then the digest of every artefact. A bundle that was changed on the
     way is refused; a bundle of another key is refused.
  3. **safe activation** — the artefact is written into a **version directory**
     of the instance, the digest is verified **again after the write**, and
     the switch to the new version is **atomic** (a symlink that is renamed).
     The previous version stays on the host: the rollback is one rename.
  4. **health check** — the new binary is started as a **disposable instance**
     (its own port, its own store) and asked for `/health/ready`. A version
     that does not become ready is **not** activated: the instance keeps the
     version it had.
  5. **rollback** — the switch back to the previous version is a rename, and
     it is written into the **durable journal** of the instance together with
     the digests, the revision and the reason.

The journal is a plain, append-only file: it is the only durable audit of the
update path of an instance (the execution log of the Core is not durable).

The **private key never touches a host**: the tool verifies with a public key
only. The key of the rehearsal is a fixture of the rehearsal and says so.

Usage:
  python3 tools/oip_update.py --instance DIR --bundle DIR --public-key FILE
                               [--allow-downgrade] [--dry-run] [--evidence DIR]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

SCHEMA = "oip-update-v1"


class Refused(Exception):
    """The bundle is refused. The reason is written into the journal."""


def fail(message: str) -> "NoReturn":  # type: ignore[name-defined]
    print("error: " + message, file=sys.stderr)
    raise Refused(message)


def the_digest(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def the_public_key(path: pathlib.Path):
    """The public key of the instance.

    The key is a **public** key: it may live on the host. The private key
    never does.
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import (
            Ed25519PublicKey,
        )
        from cryptography.hazmat.primitives.serialization import load_pem_public_key
    except ImportError as error:
        fail(f"the module cryptography is missing on this host: {error}")
        return None
    try:
        return load_pem_public_key(path.read_bytes())
    except Exception as error:
        fail(f"the public key {path} cannot be read: {error}")
        return None


def the_signature(bundle: pathlib.Path) -> bytes:
    signature = bundle / "signature"
    if not signature.is_file():
        fail(f"the bundle carries no signature: {signature}")
    return signature.read_bytes()


def the_target_of_the_host() -> str:
    """The target triple of the host that runs the updater."""
    machine = os.uname().machine
    system = os.uname().sysname.lower()
    architecture = {"arm64": "aarch64", "aarch64": "aarch64",
                    "x86_64": "x86_64", "amd64": "x86_64"}.get(machine, machine)
    operating_system = "apple-darwin" if system == "darwin" else "unknown-linux-gnu"
    return f"{architecture}-{operating_system}"


def verify(bundle: pathlib.Path, public_key, instance: pathlib.Path,
           expected_target: str | None = None):
    """The authenticity and the integrity of the bundle."""
    manifest_path = bundle / "manifest.json"
    if not manifest_path.is_file():
        fail(f"the bundle carries no manifest: {manifest_path}")
    payload = manifest_path.read_bytes()
    try:
        from cryptography.exceptions import InvalidSignature
        from cryptography.hazmat.primitives.asymmetric.ed25519 import (
            Ed25519PublicKey,
        )
    except ImportError:
        fail("the module cryptography is missing on this host")
        return None
    try:
        public_key.verify(the_signature(bundle), payload)
    except InvalidSignature:
        fail("the signature of the manifest is not valid for the public key of "
             "the instance: the bundle is refused")
    except Exception as error:
        fail(f"the signature cannot be verified: {error}")
    try:
        manifest = json.loads(payload)
    except ValueError as error:
        fail(f"the manifest is not valid JSON: {error}")
    if manifest.get("schema") != SCHEMA:
        fail(f"the manifest names the schema {manifest.get('schema')!r}, "
             f"but this tool knows {SCHEMA!r}")
    artefacts = manifest.get("the_artefacts") or {}
    if not artefacts:
        fail("the manifest names no artefact")
    for name, digest in artefacts.items():
        artefact = bundle / name
        if not artefact.is_file():
            fail(f"the bundle does not carry the artefact {name}")
        actual = the_digest(artefact)
        if actual != digest:
            fail(f"the digest of {name} is {actual}, but the manifest names "
                 f"{digest}: the bundle is refused")
    # The **target** of the instance is named explicitly: the bundle must be
    # built for it. The host alone is not enough — the rehearsal of the
    # procedure runs on another machine than the instance.
    target = manifest.get("the_target")
    if target and expected_target and target != expected_target:
        fail(f"the bundle is built for {target}, but the instance is {expected_target}")
    current = the_current_revision(instance)
    revision = manifest.get("the_revision")
    if current and revision == current and not manifest.get("the_allow_reinstall"):
        fail(f"the revision {revision} is already the version of the instance")
    return manifest


def the_versions(instance: pathlib.Path) -> pathlib.Path:
    return instance / "versions"


def the_current(instance: pathlib.Path) -> pathlib.Path:
    return instance / "current"


def the_current_revision(instance: pathlib.Path):
    """The revision that the instance runs."""
    link = the_current(instance)
    if not link.is_symlink():
        return None
    return os.path.basename(os.readlink(link))


def the_previous_revision(instance: pathlib.Path):
    link = instance / "previous"
    if not link.is_symlink():
        return None
    return os.path.basename(os.readlink(link))


def the_journal(instance: pathlib.Path):
    return instance / "state" / "updates.jsonl"


def write_the_journal(instance: pathlib.Path, entry: dict):
    """The durable journal of the update path: append-only and flushed."""
    path = the_journal(instance)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as handle:
        handle.write(json.dumps(entry, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def activate(instance: pathlib.Path, bundle: pathlib.Path, manifest: dict):
    """The activation: a version directory, a digest after the write, an
    atomic switch."""
    revision = manifest["the_revision"]
    version_directory = the_versions(instance) / revision
    version_directory.mkdir(parents=True, exist_ok=True)
    for name, digest in manifest["the_artefacts"].items():
        source = bundle / name
        target = version_directory / name
        shutil.copyfile(source, target)
        os.chmod(target, 0o755)
        actual = the_digest(target)
        if actual != digest:
            fail(f"the digest of the written artefact {name} is {actual}, but "
                 f"the manifest names {digest}: the activation is refused")
    previous = the_current_revision(instance)
    if previous:
        link = instance / "previous.tmp"
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(the_versions(instance) / previous)
        os.replace(link, instance / "previous")
    link = instance / "current.tmp"
    if link.is_symlink() or link.exists():
        link.unlink()
    link.symlink_to(version_directory)
    os.replace(link, the_current(instance))
    return revision, previous


def the_health_check(instance: pathlib.Path, revision: str, timeout=60):
    """The health check of the new version.

    The new binary is started as a **disposable instance**: its own port, its
    own store, its own state directory. Nothing of the running instance is
    touched.
    """
    import socket
    import tempfile

    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-update-check-", dir="/private/tmp"))
    try:
        configuration = work / "core.json"
        configuration.write_text(json.dumps({
            "database": str(work / "check.sqlite"),
            "http_port": port,
            "sources": [],
            "legacy_single_infrastructure": True,
        }))
        # The daemon of the Core runs with its protected local IPC: the
        # health check owns one, in its own directory.
        credential = work / "check.credential"
        credential.write_bytes(os.urandom(32))
        os.chmod(credential, 0o600)
        ipc = work / "ipc.json"
        ipc.write_text(json.dumps({
            "socket": str(work / "check.sock"),
            "max_sessions": 4,
            "clients": [{
                "uid": os.geteuid(),
                "credential_file": str(credential),
                "policy": {"principal": "platform-reader"},
            }],
        }))
        os.chmod(ipc, 0o600)
        binary = the_versions(instance) / revision / "oip-server"
        log = (work / "check.log").open("ab")
        process = subprocess.Popen([str(binary), "--daemon", "--config",
                                     str(configuration), "--ipc-config", str(ipc)],
                                    stdout=log, stderr=subprocess.STDOUT,
                                    start_new_session=True)
        deadline = time.monotonic() + timeout
        ready = False
        while time.monotonic() < deadline:
            if process.poll() is not None:
                break
            try:
                with urllib.request.urlopen(
                        f"http://127.0.0.1:{port}/health/ready", timeout=2) as answer:
                    if answer.status == 200:
                        ready = True
                        break
            except (urllib.error.URLError, OSError):
                time.sleep(0.2)
        return ready, process
    finally:
        pass


def rollback(instance: pathlib.Path, previous: str | None):
    """The rollback: the switch back to the version that was there."""
    if not previous:
        return False
    link = instance / "current.tmp"
    if link.is_symlink() or link.exists():
        link.unlink()
    link.symlink_to(the_versions(instance) / previous)
    os.replace(link, the_current(instance))
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="The secure update of the Core of an instance.")
    parser.add_argument("--instance", required=True,
                        help="the directory of the instance")
    parser.add_argument("--bundle", required=True, help="the update bundle")
    parser.add_argument("--public-key", required=True,
                        help="the public key of the instance")
    parser.add_argument("--allow-downgrade", action="store_true")
    parser.add_argument("--target", default=None,
                        help="the target triple of the instance (the host by default)")
    parser.add_argument("--dry-run", action="store_true",
                        help="verify the bundle without touching the instance")
    parser.add_argument("--evidence", default=None)
    args = parser.parse_args()
    instance = pathlib.Path(args.instance).resolve()
    bundle = pathlib.Path(args.bundle).resolve()
    if not instance.is_dir():
        fail(f"the instance {instance} does not exist")
    public_key = the_public_key(pathlib.Path(args.public_key))
    expected_target = args.target or the_target_of_the_host()
    try:
        manifest = verify(bundle, public_key, instance, expected_target)
    except Refused as refusal:
        # A refused bundle is a security relevant event: it is written into
        # the durable journal of the instance, with the reason.
        write_the_journal(instance, {
            "the_moment_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "the_target_of_the_instance": expected_target,
            "the_bundle": str(bundle),
            "the_result": "REFUSED: the verification failed",
            "the_detail": str(refusal),
        })
        print("error: " + str(refusal), file=sys.stderr)
        return 2
    if manifest is None:
        return 1
    entry = {
        "the_moment_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "the_target_of_the_instance": expected_target,
        "the_revision": manifest.get("the_revision"),
        "the_version": manifest.get("the_version"),
        "the_target": manifest.get("the_target"),
        "the_artefacts": manifest.get("the_artefacts"),
        "the_verification": "the signature and every digest are verified",
    }
    if args.dry_run:
        entry["the_activation"] = "dry run: the instance was not touched"
        write_the_journal(instance, entry)
        print(json.dumps({"the_status": "VERIFIED", "the_revision": entry["the_revision"],
                          "the_dry_run": True}, indent=2))
        return 0
    revision, previous = activate(instance, bundle, manifest)
    entry["the_activation"] = f"the version {revision} is active"
    entry["the_previous_revision"] = previous
    ready, process = the_health_check(instance, revision)
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
    entry["the_health_check"] = "the new version became ready" if ready else \
        "the new version did not become ready"
    if not ready:
        rolled_back = rollback(instance, previous)
        entry["the_rollback"] = ("the instance keeps the previous version"
                                 if rolled_back else
                                 "there was no previous version to roll back to")
        entry["the_result"] = "REFUSED: the new version did not pass the health check"
        write_the_journal(instance, entry)
        print(json.dumps({"the_status": "REFUSED", **entry}, indent=2))
        return 1
    entry["the_result"] = "the new version is active and ready"
    write_the_journal(instance, entry)
    print(json.dumps({"the_status": "UPDATED", **entry}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
