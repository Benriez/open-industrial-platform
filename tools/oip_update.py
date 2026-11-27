#!/usr/bin/env python3
"""Build, verify and install a signed Core and browser package from a directory.

The same verifier handles a copied package and the files delivered by HTTPS.
Installation changes the version pointer only after an isolated health check.
The existing Core must be stopped. This path does not migrate its database.
"""
from __future__ import annotations

import argparse
import base64
from contextlib import closing, contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
from io import BytesIO
import json
import os
import pathlib
import re
import shutil
import signal
import socket
import sqlite3
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile

from oip_ops import is_personal

SCHEMA = "oip-update-v2"
OPERATOR_TOOLS = {"tools/oip_local.py", "tools/oip_ops.py", "tools/oip_recovery.py", "tools/oip_update.py"}
NOTICE = "THIRD_PARTY_NOTICES.txt"
OPCUA_SOURCE = "web/licenses/async-opcua-source.zip"
ROBOTO_NOTICE = "web/licenses/Roboto_LICENSE.txt"
LICENSE_MATERIALS = "the_license_materials"
REQUIRED_ASSETS = {"oip-server", "web/index.html", "web/main.dart.js", "LICENSE", NOTICE} | OPERATOR_TOOLS
EXECUTABLES = {"oip-server", "oip-simulated-server"}
MAX_MANIFEST = 1024 * 1024
MAX_LICENSE_POLICY = 16 * 1024
LICENSE_SETUP = "the_license_setup"
MAX_ASSET_BYTES = 2 * 1024 * 1024 * 1024


class Refused(Exception):
    """An update cannot safely proceed."""


class LocalProbe(urllib.request.HTTPRedirectHandler):
    """Keep the isolated update check on its own loopback endpoint."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def digest_of(handle, limit: int = MAX_ASSET_BYTES) -> str:
    digest = hashlib.sha256()
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        limit -= len(chunk)
        if limit < 0:
            raise Refused("the package file exceeds its allowed size")
        digest.update(chunk)
    return digest.hexdigest()


def version_tuple(version):
    if not isinstance(version, str) or not re.fullmatch(
        r"(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})", version
    ):
        raise Refused("the package requires a numeric major.minor.patch version")
    return tuple(map(int, version.split(".")))


def host_target() -> str:
    system = {"Darwin": "apple-darwin", "Linux": "unknown-linux-gnu"}.get(os.uname().sysname)
    architecture = {"arm64": "aarch64", "aarch64": "aarch64", "x86_64": "x86_64"}.get(os.uname().machine)
    if not system or not architecture:
        raise Refused("this host platform is unsupported")
    return f"{architecture}-{system}"


def release_name(name: str) -> bool:
    if name in EXECUTABLES or name in OPERATOR_TOOLS or name in {"LICENSE", NOTICE}:
        return True
    return name.startswith("web/") and all(
        re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]{0,127}", component)
        for component in name.split("/")
    )


@contextmanager
def open_asset(root: pathlib.Path, name: str):
    path = root / name
    for parent in path.parents:
        if parent == root:
            break
        if parent.is_symlink() or not parent.is_dir():
            raise Refused(f"unsafe directory for package file {name}")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as handle:
        if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
            raise Refused(f"package file is not a regular file: {name}")
        yield handle


def bounded_asset(bundle: pathlib.Path, name: str, limit: int) -> bytes:
    with open_asset(bundle, name) as handle:
        data = handle.read(limit + 1)
    if len(data) > limit:
        raise Refused(f"package file is too large: {name}")
    return data


def public_key(path: pathlib.Path):
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    from cryptography.hazmat.primitives.serialization import load_pem_public_key

    key = load_pem_public_key(bounded_asset(path.parent, path.name, 8192))
    if not isinstance(key, Ed25519PublicKey):
        raise Refused("the provisioned update key is not Ed25519")
    return key


def unique_manifest_fields(pairs):
    fields = dict(pairs)
    if len(fields) != len(pairs):
        raise ValueError("Duplicate JSON fields.")
    return fields


def check_license_policy(core: pathlib.Path, data: bytes, *, allow_no_trusted_keys=False):
    command = [core, "--check-license-policy"]
    if allow_no_trusted_keys:
        command.append("--allow-no-trusted-keys")
    result = subprocess.run(command, input=data,
                            capture_output=True, timeout=10)
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise Refused(f"the OIP Core refused the license policy. {detail}")


def verify_license_setup(setup, package_key):
    from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

    if (not isinstance(setup, dict) or set(setup) != {"license_policy", "commercial_license_kinds"}
            or not isinstance(setup["license_policy"], str)):
        raise Refused("the signed package has invalid license setup fields")
    try:
        data = setup["license_policy"].encode("utf-8")
        if len(data) > MAX_LICENSE_POLICY:
            raise ValueError("Policy exceeds the size limit.")
        policy = json.loads(data, object_pairs_hook=unique_manifest_fields)
    except (ValueError, RecursionError) as error:
        raise Refused("the signed package has an invalid license policy") from error
    if (not isinstance(policy, dict) or set(policy) != {"issuer", "product_id", "keys", "kinds", "rights"}
            or policy["issuer"] != "code-server.de" or policy["product_id"] != "oip"
            or not isinstance(policy["keys"], dict) or not policy["keys"]
            or not isinstance(policy["kinds"], list) or not policy["kinds"]):
        raise Refused("the signed package must contain an OIP License Center policy")
    kinds = setup["commercial_license_kinds"]
    if (not isinstance(kinds, list)
            or not all(isinstance(kind, str) and kind in policy["kinds"] for kind in kinds)
            or len(set(kinds)) != len(kinds)):
        raise Refused("each commercial license kind must be unique and approved by the signed policy")
    raw_key = package_key.public_bytes(Encoding.Raw, PublicFormat.Raw)
    signer = base64.urlsafe_b64encode(raw_key).rstrip(b"=").decode("ascii")
    if signer in policy["keys"].values():
        raise Refused("the package signing key cannot issue OIP licenses")


def verify_manifest(bundle: pathlib.Path, key, expected_target: str):
    from cryptography.exceptions import InvalidSignature

    payload = bounded_asset(bundle, "manifest.json", MAX_MANIFEST)
    signature = bounded_asset(bundle, "signature", 64)
    try:
        key.verify(signature, payload)
    except InvalidSignature as error:
        raise Refused("the update signature does not match the provisioned key") from error
    try:
        manifest = json.loads(payload, object_pairs_hook=unique_manifest_fields)
    except (ValueError, RecursionError) as error:
        raise Refused("the signed update manifest is not valid JSON") from error
    if not isinstance(manifest, dict) or manifest.get("schema") != SCHEMA:
        raise Refused("unsupported signed update format")
    revision = manifest.get("the_revision")
    if not isinstance(revision, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,79}", revision):
        raise Refused("invalid update revision")
    version_tuple(manifest.get("the_version"))
    if manifest.get("the_target") != expected_target:
        raise Refused("the update package is for a different operating system or architecture")
    schema = manifest.get("the_database_schema")
    if type(schema) is not int or not 1 <= schema <= 65535:
        raise Refused("the signed update does not declare a supported database schema")
    assets = manifest.get("the_artefacts")
    if not isinstance(assets, dict) or not REQUIRED_ASSETS <= assets.keys() or len(assets) > 4096:
        raise Refused("the update package does not declare all required Core, browser and license files")
    if LICENSE_MATERIALS in manifest:
        version = manifest[LICENSE_MATERIALS]
        if type(version) is not int or version != 1 or not {OPCUA_SOURCE, ROBOTO_NOTICE} <= assets.keys():
            raise Refused("the update package does not declare the required third-party license materials")
    for name, digest in assets.items():
        if not release_name(name) or not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest):
            raise Refused("the update manifest contains an invalid file name or digest")
    if LICENSE_SETUP in manifest:
        verify_license_setup(manifest[LICENSE_SETUP], key)
    return manifest, payload, signature


def verify_assets(bundle: pathlib.Path, assets: dict) -> int:
    total = 0
    for name, expected in assets.items():
        with open_asset(bundle, name) as handle:
            size = os.fstat(handle.fileno()).st_size
            total += size
            if total > MAX_ASSET_BYTES:
                raise Refused("the update package exceeds the supported size")
            if digest_of(handle, size) != expected:
                raise Refused(f"the package digest does not match for {name}")
    return total


def private_directory(path: pathlib.Path):
    path.mkdir(mode=0o700, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077:
        raise Refused("the instance directory must be private and owned by the local operator")


@contextmanager
def ownership(path: pathlib.Path, busy_message: str):
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    with os.fdopen(fd, "rb") as handle:
        info = os.fstat(handle.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_nlink != 1 or info.st_mode & 0o077:
            raise Refused("the update or database ownership file is unsafe")
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise Refused(busy_message) from error
        yield


def installed(instance: pathlib.Path, key, target: str):
    current = instance / "current"
    if not current.is_symlink():
        if current.exists():
            raise Refused("the current release pointer is not a symlink")
        return None
    directory = current.resolve(strict=True)
    if directory.parent != instance / "versions":
        raise Refused("the current release points outside the instance version directory")
    if not (directory / "manifest.json").is_file():
        raise Refused("the installed release has no signed version metadata. Use a separately verified migration")
    manifest, _, _ = verify_manifest(directory, key, target)
    if manifest["the_revision"] != directory.name:
        raise Refused("the saved release revision does not match its version directory")
    return manifest


def database_path(instance: pathlib.Path, config: pathlib.Path, current, manifest) -> pathlib.Path:
    if not config.exists() and not config.is_symlink():
        database = instance / "core.sqlite"
        if current or database.exists() or database.is_symlink() or (instance / "setup-complete.json").exists():
            raise Refused("the setup configuration of the existing instance is missing")
        return database
    if instance not in config.resolve(strict=True).parents:
        raise Refused("the instance configuration must be inside the selected OIP directory")
    settings = json.loads(bounded_asset(config.parent, config.name, 1024 * 1024))
    if not isinstance(settings, dict) or not isinstance(settings.get("database"), str):
        raise Refused("the instance configuration does not name a database")
    database = pathlib.Path(settings["database"])
    if not database.is_absolute():
        raise Refused("the instance configuration must name an absolute database path")
    database = database.resolve()
    if instance not in database.parents or is_personal(database):
        raise Refused("the database must belong to the selected isolated OIP instance")
    if settings.get("web_dir") not in (None, str(instance / "current" / "web")):
        raise Refused("the instance browser files must use the current release directory")
    sources = settings.get("sources", [])
    if not isinstance(sources, list):
        raise Refused("the instance configuration does not contain a source list")
    if any(
        isinstance(source, dict) and source.get("id") == "local-simulation"
        for source in sources
    ) and "oip-simulated-server" not in manifest["the_artefacts"]:
        raise Refused("the package is missing the simulator required by this installation")
    return database


def database_schema(database: pathlib.Path) -> int:
    with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True, timeout=2)) as conn:
        return conn.execute("PRAGMA user_version").fetchone()[0]


def check_compatibility(instance: pathlib.Path, database: pathlib.Path, manifest, current):
    if current and version_tuple(manifest["the_version"]) <= version_tuple(current["the_version"]):
        raise Refused("the package version is not strictly newer than the installed version")
    if (instance / "versions" / manifest["the_revision"]).exists():
        raise Refused("the package revision was already staged or installed")
    if database.exists():
        if database_schema(database) != manifest["the_database_schema"]:
            raise Refused("the package requires a separate, tested database migration")
    elif current:
        raise Refused("the configured database of the installed instance is missing")


def flush_directory(path: pathlib.Path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def write_release_file(destination: pathlib.Path, source, executable: bool = False, limit=MAX_ASSET_BYTES):
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    written = 0
    with destination.open("xb") as handle:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            written += len(chunk)
            if written > limit:
                raise Refused("the package exceeds its allowed size")
            handle.write(chunk)
        os.fchmod(handle.fileno(), 0o700 if executable else 0o600)
        handle.flush()
        os.fsync(handle.fileno())
    return written


def check_in_isolation(directory: pathlib.Path, manifest, timeout=30):
    """Probe the embedded simulator and signed browser without saved sources or credentials."""
    with tempfile.TemporaryDirectory(prefix="oip-update-check-", dir="/tmp") as temp:
        work = pathlib.Path(temp).resolve()
        with socket.socket() as probe, socket.socket() as simulator:
            probe.bind(("127.0.0.1", 0))
            simulator.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
            simulator_port = simulator.getsockname()[1]
        conf = work / "core.json"
        database = work / "check.sqlite"
        conf.write_text(json.dumps({
            "database": str(database), "http_port": port, "sources": [],
            "web_dir": str(directory / "web"), "legacy_single_infrastructure": True,
        }))
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), LocalProbe())
        ready = False
        with (work / "check.log").open("wb") as log:
            process = None
            try:
                process = subprocess.Popen(
                    [str(directory / "oip-server"), "--config", str(conf),
                     "--demo", "--opcua-port", str(simulator_port)],
                    cwd=work, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                    env={"PATH": "/usr/bin:/bin", "HOME": str(work)}, start_new_session=True,
                )
                deadline = time.monotonic() + timeout
                url = f"http://127.0.0.1:{port}"
                assets = manifest["the_artefacts"]
                while time.monotonic() < deadline and process.poll() is None:
                    try:
                        with opener.open(url + "/health/ready", timeout=1) as reply:
                            health = json.loads(reply.read(64 * 1024))
                        if isinstance(health, dict) and health.get("ready") is True:
                            for name in ("index.html", "main.dart.js"):
                                size = (directory / "web" / name).stat().st_size
                                with opener.open(url + "/" + name, timeout=1) as reply:
                                    if digest_of(reply, size) != assets["web/" + name]:
                                        raise Refused("the isolated Core did not serve the signed browser files")
                            ready = process.poll() is None
                            break
                    except (urllib.error.URLError, OSError, ValueError):
                        pass
                    time.sleep(0.2)
            finally:
                if process is not None and process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
        if not ready or not database.is_file() or database_schema(database) != manifest["the_database_schema"]:
            raise Refused("the candidate failed the isolated Core, browser or database schema check")


def append_journal(instance: pathlib.Path, entry: dict):
    path = instance / "state"
    private_directory(path)
    fd = os.open(path / "updates.jsonl",
                 os.O_APPEND | os.O_CREAT | os.O_WRONLY | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    with os.fdopen(fd, "a") as handle:
        info = os.fstat(handle.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_nlink != 1 or info.st_mode & 0o077:
            raise Refused("the update journal must be a private regular file")
        recorded = {"the_recorded_utc": datetime.now(timezone.utc).isoformat(), **entry}
        handle.write(json.dumps(recorded, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def install(instance, bundle, manifest, payload, signature, current, total):
    versions = instance / "versions"
    private_directory(versions)
    if shutil.disk_usage(versions).free < total + 16 * 1024 * 1024:
        raise Refused("insufficient space to stage the update while retaining the installed version")
    revision = manifest["the_revision"]
    destination = versions / revision
    with tempfile.TemporaryDirectory(prefix=".staged-", dir=versions) as temp:
        work = pathlib.Path(temp)
        staged = work / revision
        staged.mkdir(mode=0o700)
        remaining = total
        for name in manifest["the_artefacts"]:
            with open_asset(bundle, name) as source:
                remaining -= write_release_file(staged / name, source, name in EXECUTABLES, remaining)
        write_release_file(staged / "manifest.json", BytesIO(payload))
        write_release_file(staged / "signature", BytesIO(signature))
        verify_assets(staged, manifest["the_artefacts"])
        if LICENSE_SETUP in manifest:
            policy = manifest[LICENSE_SETUP]["license_policy"].encode("utf-8")
            check_license_policy(staged / "oip-server", policy)
        check_in_isolation(staged, manifest)
        for directory, _, _ in os.walk(staged, topdown=False):
            flush_directory(directory)
        entry = {"the_revision": revision, "the_version": manifest["the_version"]}
        try:
            os.rename(staged, destination)
            flush_directory(versions)
            append_journal(instance, {**entry, "the_result": "PREPARED"})
            if current:
                (work / "previous").symlink_to(pathlib.Path("versions") / current["the_revision"])
                os.replace(work / "previous", instance / "previous")
            (work / "current").symlink_to(pathlib.Path("versions") / revision)
            os.replace(work / "current", instance / "current")
        finally:
            # A failed switch must never delete the installed release.
            if destination.is_dir() and (instance / "current").resolve() != destination:
                shutil.rmtree(destination)
        try:
            flush_directory(instance)
        except OSError:
            return "the release is selected but the version pointer could not be flushed to disk"


def opcua_source_archive(distribution, target):
    metadata = json.loads(subprocess.check_output(
        ["cargo", "metadata", "--offline", "--locked", "--format-version", "1", "--filter-platform", target],
        cwd=distribution, timeout=60,
    ))
    packages = sorted((package for package in metadata["packages"]
                       if package["name"].startswith("async-opcua") and package["license"] == "MPL-2.0"),
                      key=lambda package: package["name"])
    if not packages:
        raise Refused("the locked build did not identify the async-opcua license sources")
    lockfile = (distribution / "Cargo.lock").read_text(encoding="utf-8")
    # Cargo.lock lists the exact registry archive SHA-256 beside each package identity.
    registry_checksums = {(name, version, source): checksum for name, version, source, checksum in re.findall(
        r'\n\[\[package\]\]\nname = "([^"]+)"\nversion = "([^"]+)"\n'
        r'source = "([^"]+)"\nchecksum = "([0-9a-f]{64})"\n', lockfile,
    )}
    output = BytesIO()
    with ZipFile(output, "w", ZIP_DEFLATED) as archive:
        archive.writestr("README.md", bounded_asset(distribution, "vendor/README.md", MAX_ASSET_BYTES))
        for package in packages:
            name, version, source = package["name"], package["version"], package["source"]
            directory = pathlib.Path(package["manifest_path"]).parent
            if source is not None:
                filename = f"{name}-{version}.crate"
                cache = directory.parents[2] / "cache" / directory.parent.name
                data = bounded_asset(cache, filename, MAX_ASSET_BYTES)
                if hashlib.sha256(data).hexdigest() != registry_checksums.get((name, version, source)):
                    raise Refused(f"the registry source for {name} does not match Cargo.lock")
                archive.writestr(f"registry/{filename}", data, compress_type=ZIP_STORED)
                continue
            if directory != distribution / "vendor" / name:
                raise Refused(f"the patched source for {name} is outside the release source tree")
            tracked = subprocess.check_output(
                ["git", "ls-files", "-z", "--", f"vendor/{name}"], cwd=distribution, timeout=30,
            ).decode("utf-8").split("\0")[:-1]
            if f"vendor/{name}/LICENSE.md" not in tracked:
                raise Refused(f"the patched source for {name} is missing its license")
            for path in tracked:
                relative = pathlib.PurePosixPath(path).relative_to("vendor", name)
                if not ((relative.parts[0] == "src" and relative.suffix == ".rs") or
                        relative.as_posix() in {"Cargo.toml", "Cargo.toml.orig", "Cargo.lock", "LICENSE.md", "README.md"}):
                    raise Refused(f"the patched source for {name} contains an undeclared distribution file")
                archive.writestr(path, bounded_asset(distribution, path, MAX_ASSET_BYTES))
    return output.getvalue()


def package(args):
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives.serialization import load_pem_private_key

    if not all((args.binary, args.web, args.signing_key, args.release_version, args.revision, args.database_schema)):
        raise Refused("--prepare needs --binary, --web, --signing-key, --release-version, --revision and --database-schema")
    signing_key = args.signing_key.absolute()
    secret = load_pem_private_key(bounded_asset(signing_key.parent, signing_key.name, 8192), password=None)
    if not isinstance(secret, Ed25519PrivateKey):
        raise Refused("the release signer must be an Ed25519 key")
    version_tuple(args.release_version)
    target = args.target or host_target()
    license_setup = None
    if args.license_policy:
        path = args.license_policy.absolute()
        data = bounded_asset(path.parent, path.name, MAX_LICENSE_POLICY)
        license_setup = {"license_policy": data.decode("utf-8"),
                         "commercial_license_kinds": sorted(args.commercial_license_kind)}
        verify_license_setup(license_setup, secret.public_key())
    elif args.commercial_license_kind:
        raise Refused("a commercial license kind requires --license-policy")
    distribution = pathlib.Path(__file__).resolve().parents[1]
    files = {name: distribution / name for name in {"LICENSE", NOTICE} | OPERATOR_TOOLS}
    files[ROBOTO_NOTICE] = distribution / "apps/flutter/assets/fonts/Roboto_LICENSE.txt"
    files["oip-server"] = args.binary
    if args.simulator:
        files["oip-simulated-server"] = args.simulator
    for source in sorted(args.web.rglob("*")):
        relative = source.relative_to(args.web)
        if any(part.startswith(".") for part in relative.parts):
            continue
        name = "web/" + relative.as_posix()
        if source.is_symlink() or not release_name(name):
            raise Refused("the browser build contains an unsupported path")
        if source.is_file():
            if name in {OPCUA_SOURCE, ROBOTO_NOTICE}:
                raise Refused("the browser build contains a reserved third-party license path")
            files[name] = source
    if not REQUIRED_ASSETS <= files.keys():
        raise Refused("the release must include built browser files, the Core and license notice")
    bundle = args.bundle.resolve()
    if bundle.exists():
        raise Refused("the output directory already exists")
    with tempfile.TemporaryDirectory(prefix=".oip-package-", dir=bundle.parent) as temp:
        staged = pathlib.Path(temp) / "package"
        staged.mkdir(mode=0o700)
        assets = {}
        remaining = MAX_ASSET_BYTES
        for name, path in files.items():
            with open_asset(path.parent, path.name) as source:
                remaining -= write_release_file(staged / name, source, name in EXECUTABLES, remaining)
            with (staged / name).open("rb") as source:
                assets[name] = digest_of(source)
        source_archive = opcua_source_archive(distribution, target)
        write_release_file(staged / OPCUA_SOURCE, BytesIO(source_archive), limit=remaining)
        assets[OPCUA_SOURCE] = hashlib.sha256(source_archive).hexdigest()
        manifest = {
            "schema": SCHEMA, "the_revision": args.revision, "the_version": args.release_version,
            "the_target": target, "the_database_schema": args.database_schema, "the_artefacts": assets,
            LICENSE_MATERIALS: 1,
        }
        if license_setup is not None:
            if target == host_target():
                check_license_policy(staged / "oip-server", data)
            manifest[LICENSE_SETUP] = license_setup
        payload = (json.dumps(manifest, sort_keys=True, indent=2) + "\n").encode()
        write_release_file(staged / "manifest.json", BytesIO(payload))
        write_release_file(staged / "signature", BytesIO(secret.sign(payload)))
        verify_manifest(staged, secret.public_key(), target)
        verify_assets(staged, assets)
        os.rename(staged, bundle)
    print(json.dumps({"the_status": "PACKAGED", "the_revision": args.revision}))


def update(args):
    if not args.instance or not args.public_key:
        raise Refused("verification and installation require --instance and --public-key")
    instance = args.instance.resolve(strict=True)
    if is_personal(instance):
        raise Refused("the selected instance is a personal or system installation")
    config = (args.config or instance / "core.json").absolute()
    if instance not in config.resolve().parents:
        raise Refused("the instance configuration must be inside the selected OIP directory")
    bundle = args.bundle.resolve(strict=True)
    target = host_target()
    if args.target and args.target != target:
        raise Refused("the requested update target does not match this host")
    key = public_key(args.public_key.absolute())
    manifest, payload, signature = verify_manifest(bundle, key, target)
    total = verify_assets(bundle, manifest["the_artefacts"])
    if args.dry_run:
        current = installed(instance, key, target)
        database = database_path(instance, config, current, manifest)
        check_compatibility(instance, database, manifest, current)
        print(json.dumps({"the_status": "VERIFIED", "the_revision": manifest["the_revision"]}))
        return
    private_directory(instance)
    with ownership(instance / ".local-operation.lock", "OIP or another local operation is already running"):
        current = installed(instance, key, target)
        database = database_path(instance, config, current, manifest)
        with ownership(pathlib.Path(str(database) + ".oip-lock"), "the Core is running or the database is in use"):
            check_compatibility(instance, database, manifest, current)
            warning = install(instance, bundle, manifest, payload, signature, current, total)
        entry = {"the_status": "UPDATED", "the_revision": manifest["the_revision"],
                 "the_version": manifest["the_version"], "the_target": target}
        if warning:
            entry["the_storage_warning"] = warning
        try:
            append_journal(instance, entry)
        except (OSError, Refused):
            entry["the_journal_warning"] = "the release is switched but the final journal entry could not be saved"
        print(json.dumps(entry))


def interrupted(_number, _frame):
    raise KeyboardInterrupt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--instance", type=pathlib.Path)
    parser.add_argument("--config", type=pathlib.Path)
    parser.add_argument("--bundle", type=pathlib.Path, required=True)
    parser.add_argument("--public-key", type=pathlib.Path)
    parser.add_argument("--target")
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--dry-run", action="store_true", help="verify without staging or installing")
    action.add_argument("--prepare", action="store_true", help="create a signed bundle on the release machine")
    parser.add_argument("--binary", type=pathlib.Path)
    parser.add_argument("--web", type=pathlib.Path)
    parser.add_argument("--simulator", type=pathlib.Path)
    parser.add_argument("--signing-key", type=pathlib.Path)
    parser.add_argument("--release-version")
    parser.add_argument("--revision")
    parser.add_argument("--database-schema", type=int)
    parser.add_argument("--license-policy", type=pathlib.Path, help="approved public OIP license policy for first setup")
    parser.add_argument("--commercial-license-kind", action="append", default=[],
                        help="approved kind granting commercial usage (repeat as needed)")
    args = parser.parse_args()
    if not args.prepare and (args.license_policy or args.commercial_license_kind):
        parser.error("license setup options require --prepare")
    signal.signal(signal.SIGTERM, interrupted)
    try:
        (package if args.prepare else update)(args)
    except KeyboardInterrupt:
        print("error: update interrupted. Check the selected release before restart.", file=sys.stderr)
        return 130
    except ImportError:
        print("error: the updater requires Python cryptography with Ed25519 support", file=sys.stderr)
        return 2
    except (Refused, OSError, ValueError, sqlite3.Error, subprocess.SubprocessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
