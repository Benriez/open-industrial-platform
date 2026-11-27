"""Encrypted recovery for one locally managed OIP instance."""

from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import getpass
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
from urllib.parse import urlsplit
import warnings

FORMAT = "oip-recovery-1"
CORE_SCHEMA = 8
CONTROL = "recovery.json"
DATABASE = "core.sqlite"
BROWSER = DATABASE + ".browser-credentials.json"
LICENSE = Path(DATABASE).with_suffix(".license.json").name
AUDIT = DATABASE + ".security-audit"
AUDIT_FILES = ("key.json", "seal.json", "events.jsonl")
MAX_DB = 16 * 1024**3
MAX_RESOURCE = 256 * 1024**2
MAX_MEMBERS = 512
MAX_JSON = 1024**2
SANDBOX = "/usr/bin/sandbox-exec"
MEMBER = re.compile(r"[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*")


class RecoveryError(Exception):
    """An operator-facing recovery failure without secret values."""


def checked_name(name):
    if (
        not isinstance(name, str)
        or len(name) > 240
        or not MEMBER.fullmatch(name)
        or any(part in (".", "..") for part in name.split("/"))
    ):
        raise RecoveryError("Invalid recovery resource name.")
    return name


def put_json(path, value):
    with path.open("xb") as file:
        file.write((json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode())
        file.flush()
        os.fsync(file.fileno())


def load_json(path):
    with path.open("rb") as file:
        value = file.read(MAX_JSON + 1)
    if len(value) > MAX_JSON:
        raise RecoveryError("Recovery configuration exceeds the size limit.")
    result = json.loads(value)
    if not isinstance(result, dict):
        raise RecoveryError("Recovery configuration is not a JSON object.")
    return result


def checked_file(path, private=True):
    if path != path.resolve():
        raise RecoveryError("Recovery does not follow symlinks in instance data paths.")
    entry = path.lstat()
    if not stat.S_ISREG(entry.st_mode) or entry.st_nlink != 1:
        raise RecoveryError("Recovery needs a regular file with no additional hard links.")
    if private and (entry.st_uid != os.getuid() or entry.st_mode & 0o077):
        raise RecoveryError("Recovery config, database and secrets must be operator-owned and private.")
    return entry.st_size


def resource_path(raw, base):
    path = Path(raw)
    return path if path.is_absolute() else base / path


def normalize_core_paths(config, file_ref, tree_ref):
    """Follow only Core configuration's defined file references."""
    for profile in (config.get("ssh") or {}).get("profiles", []):
        for field in ("identity_file", "known_hosts_file"):
            if profile.get(field):
                profile[field] = file_ref(
                    profile[field], private=(field == "identity_file")
                )
        if profile.get("agent_socket"):
            if not profile.get("identity_file"):
                raise RecoveryError(
                    "An SSH profile depends on an external agent. "
                    "Provide its own recoverable key before backing up this instance."
                )
            profile["agent_socket"] = None
    for profile in (config.get("hue") or {}).get("profiles", []):
        profile["pin_file"] = file_ref(profile["pin_file"], private=False)
        if profile.get("token_file"):
            profile["token_file"] = file_ref(profile["token_file"])
    for source in config.get("sources", []):
        if (opcua := source.get("opcua")) is not None:
            opcua["pki_dir"] = tree_ref(
                opcua["pki_dir"], certificate=opcua["certificate_path"],
                private_key=opcua["private_key_path"],
            )


@contextmanager
def exclusive_lock(lock, busy_message):
    descriptor = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "r+b") as file:
        checked_file(lock)
        try:
            fcntl.flock(file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RecoveryError(busy_message) from None
        yield


def stopped_database(database):
    return exclusive_lock(Path(str(database) + ".oip-lock"), "Stop the Core before saving recovery data.")


def sqlite_checks(ops, database):
    if (
        ops.sqlite_query(database, "pragma integrity_check;") != "ok"
        or ops.sqlite_query(database, "pragma foreign_key_check;")
        or ops.sqlite_query(database, "pragma user_version;") != str(CORE_SCHEMA)
    ):
        raise RecoveryError(f"Recovery requires an intact schema {CORE_SCHEMA} database.")


def passphrase(args, confirm):
    if args.passphrase_fd is None:
        with warnings.catch_warnings():
            warnings.simplefilter("error", getpass.GetPassWarning)
            try:
                value = getpass.getpass("Recovery passphrase: ").encode()
                if confirm and value != getpass.getpass("Repeat recovery passphrase: ").encode():
                    raise RecoveryError("Recovery passphrases do not match.")
            except getpass.GetPassWarning:
                raise RecoveryError("Use a terminal or a private --passphrase-fd.") from None
    else:
        # Read a single line from an operator-owned pipe or an inherited FD.
        # Secrets are never put in argv, an environment variable or a file here.
        with os.fdopen(os.dup(args.passphrase_fd), "rb") as stream:
            value = stream.readline(1026).removesuffix(b"\n")
    if not 20 <= len(value) <= 1024 or any(char in value for char in (b"\0", b"\r", b"\n")):
        raise RecoveryError("Use a strong recovery passphrase of at least 20 characters.")
    return value + b"\n"


@contextmanager
def gpg_command(secret):
    binary = shutil.which("gpg")
    if binary is None:
        raise RecoveryError("GnuPG with AES-256/OCB support is required.")
    socket_root = "/private/tmp" if sys.platform == "darwin" else None
    with tempfile.TemporaryDirectory(prefix="oip-gpg-", dir=socket_root) as home:
        read_fd, write_fd = os.pipe()
        try:
            with os.fdopen(write_fd, "wb") as channel:
                channel.write(secret)
            options = [
                str(binary), "--no-options", "--batch", "--homedir", home,
                "--no-keyring", "--no-auto-key-retrieve", "--auto-key-locate", "clear",
                "--pinentry-mode", "loopback", "--no-symkey-cache",
                "--passphrase-fd", str(read_fd),
            ]
            yield options, (read_fd,)
        finally:
            os.close(read_fd)
            gpgconf = Path(binary).with_name("gpgconf")
            if gpgconf.is_file():
                subprocess.run(
                    [gpgconf, "--homedir", home, "--kill", "gpg-agent"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    timeout=10, check=False,
                )


def insert_file(archive, name, path):
    with path.open("rb") as file:
        member = tarfile.TarInfo(name)
        member.size = os.fstat(file.fileno()).st_size
        member.mode = 0o600
        archive.addfile(member, file)


def encrypt_files(files, control, output, secret):
    with gpg_command(secret) as (command, fds):
        process = subprocess.Popen(
            [*command, "--cipher-algo", "AES256", "--s2k-mode", "3",
             "--s2k-digest-algo", "SHA512", "--s2k-count", "65011712",
             "--compress-algo", "none", "--force-aead", "--aead-algo", "OCB",
             "--symmetric", "--output", str(output)],
            stdin=subprocess.PIPE, stderr=subprocess.DEVNULL, pass_fds=fds,
        )
        try:
            with process.stdin, tarfile.open(fileobj=process.stdin, mode="w|") as archive:
                entry = tarfile.TarInfo(CONTROL)
                entry.size = len(control)
                entry.mode = 0o600
                archive.addfile(entry, io.BytesIO(control))
                for name, path in files.items():
                    insert_file(archive, name, path)
            if process.wait(timeout=600) != 0:
                raise RecoveryError("GnuPG could not create the encrypted recovery file.")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


def backup(args, ops):
    config_path = Path(args.config).absolute()
    ipc_path = Path(args.ipc_config).absolute()
    checked_file(config_path)
    checked_file(ipc_path)
    config = load_json(config_path)
    ipc = load_json(ipc_path)
    database = ops.database_of(config, config_path).resolve()
    if ops.is_personal(database) or ops.is_personal(config_path) or ops.is_personal(ipc_path):
        raise RecoveryError("Recovery only operates on an explicitly managed instance.")
    target = Path(args.output).absolute()
    if target.exists() or target.is_symlink():
        raise RecoveryError("Choose a new recovery file. The existing file was preserved.")
    if ops.is_personal(target):
        raise RecoveryError("Choose a recovery destination outside the personal installation.")
    if target.parent.resolve() != target.parent:
        raise RecoveryError("Select a recovery destination without symlink path components.")
    base = config_path.parent
    files = {}
    sizes = {}
    resource_size = 0

    def include(name, path, private=True):
        nonlocal resource_size
        checked_name(name)
        if name in files or len(files) + 2 > MAX_MEMBERS:
            raise RecoveryError("Recovery file inventory exceeds the supported limit.")
        sizes[name] = checked_file(path, private)
        if name != DATABASE:
            resource_size += sizes[name]
            if resource_size > MAX_RESOURCE:
                raise RecoveryError("Recovery configuration and key files exceed the size limit.")
        files[name] = path
        return name

    def include_file(raw, private=True):
        return include(f"resources/{len(files):04d}", resource_path(raw, base), private)

    def include_tree(raw, certificate, private_key):
        directory = resource_path(raw, base)
        if directory.resolve() != directory or not directory.is_dir():
            raise RecoveryError("OPC-UA PKI directory must be a regular directory.")
        prefix = f"pki/{len(files):04d}"
        key_name = checked_name(private_key)
        # Only configured identity and trust material. Rejected probe residue,
        # unrelated files and transient client state are excluded.
        cert_name = checked_name(certificate)
        include(f"{prefix}/{cert_name}", directory / cert_name, private=False)
        include(f"{prefix}/{key_name}", directory / key_name)
        for subdirectory in ("trusted", "issuer", "issuers", "crl"):
            parent = directory / subdirectory
            if not parent.exists() and not parent.is_symlink():
                continue
            if parent.resolve() != parent or not parent.is_dir():
                raise RecoveryError("Invalid OPC-UA trust directory.")
            for root, directories, names in os.walk(parent, onerror=walk_error):
                root = Path(root)
                for dirname in directories:
                    child = root / dirname
                    if child.resolve() != child:
                        raise RecoveryError("Recovery does not follow symlinks in trust directories.")
                    checked_name(child.relative_to(directory).as_posix())
                for filename in names:
                    path = root / filename
                    include(f"{prefix}/{path.relative_to(directory).as_posix()}", path, private=False)
        return prefix

    with (
        stopped_database(database),
        tempfile.TemporaryDirectory(prefix=".oip-snapshot-", dir=database.parent) as snapshot_dir,
        tempfile.TemporaryDirectory(prefix=".oip-backup-", dir=target.parent) as output_dir,
    ):
        if checked_file(database) > MAX_DB:
            raise RecoveryError("Database exceeds the recovery profile's size limit.")
        # Read config again after acquiring the Core's ownership lock.
        if config != load_json(config_path) or ipc != load_json(ipc_path):
            raise RecoveryError("Instance configuration changed; restart the backup.")
        browser = resource_path(
            config.get("browser_credentials_file") or str(database) + ".browser-credentials.json",
            base,
        )
        for path, name in (
            (browser, BROWSER),
            (Path(str(browser) + ".revocations"), BROWSER + ".revocations"),
            (database.with_suffix(".license.json"), LICENSE),
        ):
            if path.exists() or path.is_symlink():
                include(name, path)
        audit = Path(str(database) + ".security-audit")
        if audit.exists():
            for name in AUDIT_FILES:
                include(f"{AUDIT}/{name}", audit / name)
        normalize_core_paths(config, include_file, include_tree)
        config.update(database=DATABASE, browser_credentials_file=BROWSER, web_dir=None)
        if ipc_owner(ipc) != os.getuid():
            raise RecoveryError("The managed recovery profile requires a single local IPC owner.")
        for client in ipc["clients"]:
            credential = resource_path(client["credential_file"], ipc_path.parent)
            client["credential_file"] = include(f"resources/{len(files):04d}", credential)
        ipc["socket"] = "oip.sock"
        snapshot = Path(snapshot_dir) / DATABASE
        snapshot.touch(mode=0o600, exist_ok=False)
        ops.sqlite_backup(database, snapshot)
        sqlite_checks(ops, snapshot)
        include(DATABASE, snapshot)
        if sizes[DATABASE] > MAX_DB:
            raise RecoveryError("Database exceeds the recovery profile's size limit.")
        manifest = {
            "format": FORMAT,
            "database_schema": CORE_SCHEMA,
            "core_sha256": binary_hash(args.binary),
            "created_utc": datetime.now(timezone.utc).isoformat(),
            "core": config,
            "ipc": ipc,
            "members": sizes,
        }
        metadata = json.dumps(manifest, ensure_ascii=False).encode()
        if len(metadata) > MAX_JSON:
            raise RecoveryError("Recovery configuration exceeds the size limit.")
        encrypted = Path(output_dir) / "recovery.gpg"
        encrypt_files(files, metadata, encrypted, passphrase(args, confirm=True))
        with encrypted.open("rb") as handle:
            os.fsync(handle.fileno())
        # Publish without replacing or truncating any pre-existing target.
        os.link(encrypted, target)
    print(json.dumps({
        "status": "encrypted_backup_created",
        "format": FORMAT,
        "integrity": "sqlite_integrity_and_foreign_keys_ok",
        "restore_tested": False,
        "created_utc": manifest["created_utc"],
        "database_schema": CORE_SCHEMA,
        "core_sha256": manifest["core_sha256"],
        "backup": str(target),
    }))


def binary_hash(binary):
    digest = hashlib.sha256()
    with Path(binary).open("rb") as file:
        for chunk in iter(lambda: file.read(1024**2), b""):
            digest.update(chunk)
    return digest.hexdigest()


def walk_error(error):
    raise error


def ipc_owner(ipc):
    owners = {client["uid"] for client in ipc["clients"]}
    if len(owners) != 1 or any(type(uid) is not int or uid < 0 for uid in owners):
        raise RecoveryError("The managed recovery profile requires a single local IPC owner.")
    return owners.pop()


def decrypt(source, tar_path, secret):
    if source.stat().st_size > MAX_DB + MAX_RESOURCE + 32 * 1024**2:
        raise RecoveryError("Recovery file exceeds the supported size.")
    with gpg_command(secret) as (command, fds):
        result = subprocess.run(
            [*command, "--status-fd", "1", "--max-output", str(MAX_DB + MAX_RESOURCE + MAX_JSON + 1048576),
             "--output", str(tar_path), "--decrypt", str(source)],
            pass_fds=fds, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=600,
        )
    statuses = result.stdout.splitlines()
    if (
        result.returncode
        or b"[GNUPG:] DECRYPTION_INFO 0 9 2" not in statuses
        or b"[GNUPG:] DECRYPTION_OKAY" not in statuses
        or b"[GNUPG:] GOODMDC" not in statuses
    ):
        raise RecoveryError("Unable to authenticate the recovery file. Check the passphrase and file.")


def read_manifest(path, binary):
    manifest = load_json(path)
    if (
        manifest["format"] != FORMAT
        or manifest["database_schema"] != CORE_SCHEMA
        or manifest["core_sha256"] != binary_hash(binary)
    ):
        raise RecoveryError("Use the same trusted OIP Core binary and schema as the backup.")
    sizes = manifest["members"]
    if (
        not isinstance(sizes, dict)
        or not 1 <= len(sizes) < MAX_MEMBERS
        or not 0 < sizes.get(DATABASE, 0) <= MAX_DB
        or any(type(size) is not int or size < 0 for size in sizes.values())
        or sum(sizes.values()) - sizes[DATABASE] > MAX_RESOURCE
    ):
        raise RecoveryError("Invalid or incomplete recovery file inventory.")
    audit = {f"{AUDIT}/{name}" for name in AUDIT_FILES}
    audit_members = audit.intersection(sizes)
    if audit_members and audit_members != audit:
        raise RecoveryError("Incomplete security audit state.")
    fixed = {DATABASE, BROWSER, BROWSER + ".revocations", LICENSE} | audit
    for name in sizes:
        checked_name(name)
        if name not in fixed and not (
            re.fullmatch(r"resources/[0-9]{4}", name)
            or re.fullmatch(r"pki/[0-9]{4}/.+", name)
        ):
            raise RecoveryError("Unexpected recovery file inventory.")
    return manifest


def unpack(tar_path, destination, binary):
    with tarfile.open(tar_path, mode="r:") as archive:
        first = archive.next()
        if not first or first.name != CONTROL or not first.isreg() or first.size > MAX_JSON:
            raise RecoveryError("Recovery metadata is missing.")
        (destination / CONTROL).write_bytes(archive.extractfile(first).read())
        manifest = read_manifest(destination / CONTROL, binary)
        pending = dict(manifest["members"])
        while (member := archive.next()) is not None:
            name = checked_name(member.name)
            if not member.isreg() or pending.pop(name, None) != member.size:
                raise RecoveryError("Unexpected or duplicate recovery contents.")
            target = destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open("xb") as handle:
                shutil.copyfileobj(archive.extractfile(member), handle)
                handle.flush()
                os.fsync(handle.fileno())
        if pending:
            raise RecoveryError("The authenticated recovery file is incomplete.")
    return manifest


def recovery_paths(directory, manifest, http_port, web_dir=None):
    """Resolve only paths contained in the restored installation."""
    core = manifest["core"]
    ipc = manifest["ipc"]

    def file_ref(raw, private=True):
        name = checked_name(raw)
        if name not in manifest["members"]:
            raise RecoveryError("A necessary restored file is missing.")
        path = directory / name
        checked_file(path, private)
        return str(path)

    def tree_ref(raw, certificate, private_key):
        name = checked_name(raw)
        file_ref(f"{name}/{checked_name(certificate)}", private=False)
        file_ref(f"{name}/{checked_name(private_key)}")
        root = directory / name
        trust = root / "trusted"
        if trust.is_symlink():
            raise RecoveryError("The OPC-UA trust directory cannot be a symlink.")
        trust.mkdir(mode=0o700, exist_ok=True)
        return str(root)

    normalize_core_paths(core, file_ref, tree_ref)
    if LICENSE in manifest["members"]:
        file_ref(LICENSE)
    core.update(
        database=file_ref(DATABASE),
        browser_credentials_file=str(directory / BROWSER),
        http_port=http_port,
        web_dir=web_dir,
        tailscale_peer_status=False,
    )
    if "opcua_read_only" in core:
        core["opcua_read_only"] = True
    for profile in (core.get("hue") or {}).get("profiles", []):
        profile["control_enabled"] = False
    ipc["socket"] = str(directory / "oip.sock")
    ipc_owner(ipc)
    for client in ipc["clients"]:
        client.update(uid=os.getuid(), credential_file=file_ref(client["credential_file"]))
    return core, ipc


def restore(args, ops):
    source = Path(args.source).absolute()
    target = Path(args.restore_dir).absolute()
    if target.exists() or target.is_symlink() or ops.is_personal(target):
        raise RecoveryError("Select a new recovery directory outside the personal installation.")
    if target.parent.resolve() != target.parent:
        raise RecoveryError("Select the recovery directory without symlink path components.")
    if len(os.fsencode(target / "instance" / "oip.sock")) >= 103:
        raise RecoveryError("Choose a shorter recovery directory path for the local socket.")
    with tempfile.TemporaryDirectory(prefix=".oip-restore-", dir=target.parent) as temporary:
        stage = Path(temporary)
        plaintext = stage / "recovery.tar"
        recovered = stage / "instance"
        recovered.mkdir(mode=0o700)
        decrypt(source, plaintext, passphrase(args, confirm=False))
        manifest = unpack(plaintext, recovered, args.binary)
        plaintext.unlink()
        sqlite_checks(ops, recovered / DATABASE)
        recovery_paths(recovered, manifest, http_port=0)
        target.mkdir(mode=0o700)
        try:
            os.rename(recovered, target / "instance")
        except BaseException:
            target.rmdir()
            raise
    print(json.dumps({
        "status": "restored_inactive",
        "directory": str(target),
        "integrity": "authenticated_recovery_and_sqlite_verified",
        "database_schema": CORE_SCHEMA,
        "restore_tested": False,
        "source_connections": "blocked_until_isolated_start",
    }))


def isolated_start(args, ops):
    if not Path(SANDBOX).is_file():
        raise RecoveryError("This recovery runner requires the verified macOS sandbox.")
    directory = Path(args.restore_dir).absolute() / "instance"
    paths = ops.state_paths(directory / "state")
    Path(args.binary).resolve(strict=True)
    if ops.is_personal(directory) or directory.resolve() != directory:
        raise RecoveryError("Select a restored installation outside the personal installation.")
    manifest = read_manifest(directory / CONTROL, args.binary)
    if not 1 <= args.port <= 65535 or ops.port_open(args.port):
        raise RecoveryError("Choose a free local HTTP port for the isolated instance.")
    if ops.alive(ops.read_pid(paths)):
        raise RecoveryError("The isolated instance is already running.")
    core, ipc = recovery_paths(directory, manifest, args.port, args.web_dir)
    sandbox = "(version 1) (allow default) (deny network-outbound)"
    if (port := args.test_source_port) is not None:
        if not 1 <= port <= 65535 or port == args.port:
            raise RecoveryError("Choose the independent, locally approved OPC-UA test port.")
        endpoints = (urlsplit(source["endpoint"]) for source in core.get("sources", []))
        if not any(
            endpoint.scheme == "opc.tcp" and endpoint.hostname == "127.0.0.1" and endpoint.port == port
            for endpoint in endpoints
        ):
            raise RecoveryError("That port does not match a restored literal-loopback test source.")
        sandbox += f' (allow network-outbound (remote ip "localhost:{port}"))'
    # A normal start cannot read the recovery envelope. Runnable configs only
    # exist for this sandboxed launch and are removed after startup.
    with exclusive_lock(directory / ".recovery-launch.lock", "Recovery operation already in progress."), tempfile.TemporaryDirectory(
        prefix=".launch-", dir=directory
    ) as launch:
        launch = Path(launch)
        put_json(launch / "core.json", core)
        put_json(launch / "ipc.json", ipc)
        args.config = str(launch / "core.json")
        args.ipc_config = str(launch / "ipc.json")
        args.state_dir = str(directory / "state")
        return ops.command_start(
            args, launch / "core.json", paths, core,
            launcher=[SANDBOX, "-p", sandbox],
            context={"mode": "isolated_recovery", "test_source_port": port},
        )


def isolated_stop(directory, args, ops):
    checked_file(directory / CONTROL)
    paths = ops.state_paths(directory / "state")
    with exclusive_lock(directory / ".recovery-launch.lock", "Recovery operation already in progress."):
        pid = ops.read_pid(paths)
        if ops.alive(pid):
            invocation = subprocess.run(
                ["/bin/ps", "-ww", "-p", str(pid), "-o", "command="], capture_output=True,
                text=True, timeout=5,
            )
            if invocation.returncode or not invocation.stdout.rstrip().endswith(
                "--ipc-config " + invocation_path(directory, paths["state"])
            ):
                raise RecoveryError("The recorded process is not the isolated OIP instance.")
        return ops.command_stop(args, None, paths, None)


def invocation_path(directory, state):
    checked_file(state)
    config = Path(load_json(state)["config"])
    if config.parent.parent != directory or not config.parent.name.startswith(".launch-"):
        raise RecoveryError("The recorded recovery configuration is invalid.")
    return str(config.with_name("ipc.json"))


def dispatch(args, ops):
    """Only this optional profile needs private staging and GnuPG."""
    os.umask(0o077)
    try:
        if args.command == "recovery-backup":
            if not all((args.config, args.ipc_config, args.output)):
                raise RecoveryError("Specify --config, --ipc-config and a new --output.")
            return backup(args, ops)
        if args.command == "recovery-restore":
            if not all((args.source, args.restore_dir)):
                raise RecoveryError("Specify --source and a new --restore-dir.")
            return restore(args, ops)
        if not args.restore_dir or (args.command == "recovery-start" and args.port is None):
            raise RecoveryError("Specify --restore-dir and, to start, --port.")
        directory = Path(args.restore_dir).absolute() / "instance"
        if ops.is_personal(directory) or directory.resolve() != directory:
            raise RecoveryError("Select a restored installation outside the personal installation.")
        if args.command == "recovery-start":
            return isolated_start(args, ops)
        return isolated_stop(directory, args, ops)
    except RecoveryError as error:
        ops.fail(str(error))
    except BrokenPipeError:
        ops.fail("Unable to write the encrypted recovery file. Check GnuPG and available storage.")
    except OSError as error:
        ops.fail(f"Recovery could not read or write the required files (OS error {error.errno}).")
    except (KeyError, TypeError, ValueError, tarfile.TarError):
        ops.fail("Recovery file or instance configuration does not match the supported format.")
    except subprocess.TimeoutExpired:
        ops.fail("Recovery did not complete within the operation's time limit.")
