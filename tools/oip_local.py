#!/usr/bin/env python3
"""Set up and run one owner-private, loopback-only OIP installation."""

import argparse
import base64
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import signal
import socket
import stat
import subprocess
import tempfile
import time
import urllib.request

from oip_ops import is_personal
from oip_update import (
    LICENSE_SETUP, MAX_LICENSE_POLICY, Refused, check_license_policy,
    host_target, installed, public_key, verify_assets,
)


READ_PERMISSIONS = [
    "hierarchy_read", "core_read", "sources_read", "devices_read",
    "telemetry_read", "events_read", "opcua_read", "settings_read",
]

MAX_KEY_REGISTRY = 1024 * 1024
LICENSE_ISSUER = "code-server.de"
LICENSE_PRODUCT = "oip"
LICENSE_IDENTIFIER = re.compile(r"[a-z][a-z0-9_-]{0,31}")
KEY_FINGERPRINT = re.compile(r"[a-f0-9]{64}")
REGISTRY_KEY_FIELDS = {"product_id", "kid", "public_key", "fingerprint", "state"}


def private_dir(path):
    path.mkdir(mode=0o700, exist_ok=True)
    info = path.stat(follow_symlinks=False)
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid()
            or info.st_mode & 0o077):
        raise ValueError("Instance and backup directories must belong to you and have mode 0700.")


def absolute_path(value):
    path = Path(value).expanduser()
    if not path.is_absolute() or path.resolve() != path or is_personal(path):
        raise ValueError("Use an absolute canonical path outside the existing personal installation.")
    return path


def read_private(path):
    info = path.stat(follow_symlinks=False)
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
            or info.st_mode & 0o077 or info.st_nlink != 1):
        raise ValueError("Installation files must be regular, private files owned by you.")
    return path.read_bytes()


def private_json(path):
    return json.loads(read_private(path))


def publish_once(path, content):
    # Setup owns the instance lock. Rename the fully written file without
    # disturbing existing configuration or leaving a second live hardlink.
    if os.path.lexists(path):
        return
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".setup-", delete=False) as pending:
        staged = Path(pending.name)
        try:
            pending.write(content)
            pending.flush()
            os.fsync(pending.fileno())
            os.replace(staged, path)
        finally:
            staged.unlink(missing_ok=True)


def ensure_json(path, data):
    publish_once(path, (json.dumps(data, indent=2, ensure_ascii=False) + "\n").encode())
    if private_json(path) != data:
        raise ValueError(f"Existing {path.name} differs. Use its original setup or a fresh instance directory.")


@contextlib.contextmanager
def owning_instance(root):
    fd = os.open(root / ".local-operation.lock",
                 os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "r+b") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError("OIP is already running or another operation is in progress here.") from error
        yield


def runtime_paths(root, args):
    package = root / "current"
    core = Path(args.core).resolve(strict=True) if args.core else package / "oip-server"
    web = Path(args.web).resolve(strict=True) if args.web else package / "web"
    simulator = (Path(args.simulator).resolve(strict=True) if args.simulator
                 else package / "oip-simulated-server")
    if not core.is_file() or not os.access(core, os.X_OK) or not (web / "main.dart.js").is_file():
        raise ValueError("Install a verified OIP package with the Core and browser assets first.")
    return core, web, simulator


def bounded_file(path, limit, label):
    with open(path, "rb") as source:
        data = source.read(limit + 1)
    if len(data) > limit:
        raise ValueError(f"{label} is too large.")
    return data


def unique_json_object(pairs):
    result = dict(pairs)
    if len(result) != len(pairs):
        raise ValueError("The key registry contains duplicate JSON fields.")
    return result


def registry_key(entry):
    if entry["product_id"] != LICENSE_PRODUCT:
        raise ValueError("The selected key belongs to another product.")
    if entry["state"] not in {"pending", "active", "retired"}:
        raise ValueError("The selected key is compromised or has an unknown state.")
    encoded = entry["public_key"]
    if not re.fullmatch(r"[a-zA-Z0-9_-]{43}", encoded):
        raise ValueError("The selected Ed25519 key is malformed.")
    public = base64.urlsafe_b64decode(encoded + "=")
    fingerprint = hashlib.sha256(public).hexdigest()
    if (base64.urlsafe_b64encode(public).decode("ascii") != encoded + "="
            or fingerprint != entry["fingerprint"] or fingerprint[:32] != entry["kid"]):
        raise ValueError("The selected key does not match its fingerprint and key ID.")
    return entry["kid"], encoded


def prepare_license_policy(args):
    fingerprints = set(args.key_fingerprint)
    if (len(fingerprints) != len(args.key_fingerprint)
            or not all(KEY_FINGERPRINT.fullmatch(value) for value in fingerprints)):
        raise ValueError("Provide a distinct 64-character lowercase SHA-256 fingerprint for each approved key.")
    kinds = set(args.kind)
    if len(kinds) != len(args.kind) or not all(LICENSE_IDENTIFIER.fullmatch(kind) for kind in kinds):
        raise ValueError("Provide distinct, valid License Center kinds.")
    rights = {}
    for entry in args.right:
        name, _, limit = entry.partition("=")
        if (not LICENSE_IDENTIFIER.fullmatch(name) or name in rights
                or not re.fullmatch(r"[1-9][0-9]{0,5}", limit)):
            raise ValueError("Provide distinct rights as NAME=MAX with limits from 1 to 999999.")
        rights[name] = int(limit)

    data = bounded_file(args.registry, MAX_KEY_REGISTRY, "The key registry")
    try:
        registry = json.loads(data.decode("utf-8"), object_pairs_hook=unique_json_object)
    except RecursionError as error:
        raise ValueError("The key registry is too deeply nested.") from error
    if (not isinstance(registry, dict) or set(registry) != {"issuer", "keys"}
            or registry["issuer"] != LICENSE_ISSUER or not isinstance(registry["keys"], list)):
        raise ValueError("Choose the public key registry exported by the License Center.")
    keys = {}
    seen = set()
    for entry in registry["keys"]:
        if (not isinstance(entry, dict) or set(entry) != REGISTRY_KEY_FIELDS
                or not all(isinstance(value, str) for value in entry.values())):
            raise ValueError("The public key registry has a malformed entry.")
        fingerprint = entry["fingerprint"]
        if not KEY_FINGERPRINT.fullmatch(fingerprint) or fingerprint in seen:
            raise ValueError("The public key registry has an invalid or repeated fingerprint.")
        seen.add(fingerprint)
        if fingerprint in fingerprints:
            kid, encoded = registry_key(entry)
            if kid in keys:
                raise ValueError("The selected public keys have the same key ID.")
            keys[kid] = encoded
    if not fingerprints.issubset(seen):
        raise ValueError("An approved fingerprint is missing from the key registry.")
    policy = {"issuer": LICENSE_ISSUER, "product_id": LICENSE_PRODUCT,
              "keys": keys, "kinds": sorted(kinds), "rights": rights}
    output = json.dumps(policy, indent=2, sort_keys=True)
    if len(output) + 1 > MAX_LICENSE_POLICY:
        raise ValueError("The license policy is too large.")
    print(output)


def package_license_setup(root, args):
    if args.core or args.web or args.simulator or args.commercial_license_kind:
        raise ValueError("Use the installed package without development overrides or separate license kinds.")
    manifest = installed(root, public_key(Path(args.package_public_key).absolute()), host_target())
    if manifest is None:
        raise ValueError("Install a verified OIP package before configuring its license policy.")
    verify_assets((root / "current").resolve(strict=True), manifest["the_artefacts"])
    previous_setup = root / "setup.json"
    if os.path.lexists(previous_setup):
        existing = private_json(previous_setup)
        if not isinstance(existing, dict):
            raise ValueError("The existing setup record is invalid. Use the Recovery procedure.")
        return {name: existing[name] for name in ("license_policy", "commercial_license_kinds")
                if name in existing}
    return manifest.get(LICENSE_SETUP, {})


def license_setup(root, args, core):
    if args.package_public_key:
        config = package_license_setup(root, args)
        if config:
            text = config.get("license_policy")
            if not isinstance(text, str):
                raise ValueError("The existing license setup record is invalid.")
            check_license_policy(core, text.encode("utf-8"))
        return config
    if not args.license_policy:
        if args.commercial_license_kind:
            raise ValueError("A commercial license kind requires the trusted OIP license policy.")
        return {}
    data = bounded_file(args.license_policy, MAX_LICENSE_POLICY, "The license policy")
    check_license_policy(core, data)
    policy_text = data.decode("utf-8")
    policy = json.loads(policy_text)
    kinds = sorted(set(args.commercial_license_kind))
    if any(kind not in policy["kinds"] for kind in kinds):
        raise ValueError("Each commercial license kind must be approved by the trusted policy.")
    return {"license_policy": policy_text, "commercial_license_kinds": kinds}


def prepare(root, args, core):
    if not all(1024 <= value <= 65535 for value in (args.port, args.simulator_port)):
        raise ValueError("Choose local ports between 1024 and 65535.")
    if args.port == args.simulator_port:
        raise ValueError("Choose different Core and simulator ports.")
    labels = [v.strip() for v in (args.organization, args.infrastructure, args.site)]
    if any(not v or len(v) > 96 or not v.isprintable() for v in labels):
        raise ValueError("Enter an organization, infrastructure and site name with 1 to 96 characters.")
    license_config = license_setup(root, args, core)
    backup = absolute_path(args.backup_directory)
    if backup == root or root in backup.parents:
        raise ValueError("Choose a backup directory outside this OIP instance.")
    private_dir(backup)
    with tempfile.TemporaryFile(dir=backup) as probe:
        probe.write(b"OIP")
        probe.flush()
        os.fsync(probe.fileno())
    if len(os.fsencode(root / "ipc.sock")) > 100:
        raise ValueError("The instance path is too long for local IPC. Choose a shorter directory.")
    organization, infrastructure, site = labels
    setup = {
        "format_version": 1, "backup_directory": str(backup),
        "simulator_port": args.simulator_port, "http_port": args.port,
        "organization": organization, "infrastructure": infrastructure, "site": site,
        **license_config,
    }
    complete = root / "setup-complete.json"
    if complete.exists():
        if private_json(complete) != setup:
            raise ValueError("This instance is already set up with different settings.")
        private_json(root / "core.json")
        private_json(root / "ipc.json")
        if not (root / "core.sqlite").is_file():
            raise ValueError("The existing database is missing. Use the Recovery procedure.")
        print("OIP ist bereits eingerichtet. Vorhandene Daten bleiben erhalten.")
        return
    if not (root / "setup.json").exists():
        for name in ("core.json", "ipc.json", "plan.json", "core.sqlite",
                     "core.sqlite-shm", "core.sqlite-wal", "operator.credential"):
            if os.path.lexists(root / name):
                raise ValueError("This directory contains existing OIP data. Use a fresh directory.")
    ensure_json(root / "setup.json", setup)
    source = {"id": "local-simulation", "entity_id": "simulation-machine",
              "name": "OPC-UA-Simulation", "endpoint": f"opc.tcp://127.0.0.1:{args.simulator_port}"}
    config = {"database": str(root / "core.sqlite"), "http_port": args.port,
              "opcua_read_only": True, "sources": [source], **license_config}
    plan = {
        "organizations": [{"id": "local-org", "name": organization}],
        "infrastructures": [{"id": "local-infra", "organization_id": "local-org", "name": infrastructure}],
        "sites": [{"id": "local-site", "infrastructure_id": "local-infra", "name": site}],
        "sources": [{"source_id": source["id"], "site_id": "local-site",
                     "device_id": "simulation-device", "entity_id": source["entity_id"]}],
        "principals": [{"id": "operator", "name": "Lokaler Betreiber", "enabled": True}],
        "roles": [{"id": "local-operator", "name": "Lokaler Betreiber",
                   "permissions": READ_PERMISSIONS + ["inventory_manage", "settings_write"]},
                  {"id": "installation-licensing", "name": "OIP-Lizenzverwaltung",
                   "permissions": ["license_read", "license_manage"]}],
        "bindings": [{"principal_id": "operator", "role_id": "local-operator",
                      "scope": {"kind": "organization", "id": "local-org"}},
                     {"principal_id": "operator", "role_id": "installation-licensing",
                      "scope": {"kind": "platform"}}],
        "legacy_single_infrastructure": False,
    }
    ipc = {"socket": str(root / "ipc.sock"),
           "clients": [{"uid": os.getuid(), "credential_file": str(root / "operator.credential"),
                        "policy": {"principal": "operator"}}]}
    ensure_json(root / "core.json", config)
    ensure_json(root / "plan.json", plan)
    ensure_json(root / "ipc.json", ipc)
    credential = root / "operator.credential"
    publish_once(credential, secrets.token_bytes(32))
    if len(read_private(credential)) != 32:
        raise ValueError("Invalid existing local credential. Use the Recovery procedure.")
    subprocess.run([core, "--config", root / "core.json", "--provision", root / "plan.json"],
                   stdout=subprocess.DEVNULL, check=True, timeout=90)
    ensure_json(complete, setup)
    print("OIP eingerichtet. Starte die lokale Instanz mit dem Befehl run.")


def issue_login(root, core):
    result = subprocess.run(
        [core, "--browser-login", "--ipc-socket", root / "ipc.sock",
         "--ipc-credential", root / "operator.credential"],
        stdout=subprocess.PIPE, check=True, text=True, timeout=8,
    )
    return json.loads(result.stdout)["login_code"]


def require_available(port):
    with socket.socket() as probe:
        # A previous OIP connection may still be in TIME_WAIT after shutdown.
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind(("127.0.0.1", port))
        probe.listen(1)


def wait_for_ready(url, children):
    local = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if any(child.poll() is not None for child in children):
            break
        try:
            with local.open(url + "/api/v2/browser/session", timeout=1) as response:
                if json.load(response).get("mode") == "login_required":
                    return
        except OSError:
            time.sleep(0.2)
    raise ValueError("OIP could not start. Check available space, ports and the private oip.log.")


def run(root, args, core, web, simulator):
    setup = private_json(root / "setup-complete.json")
    config = private_json(root / "core.json")
    port = config["http_port"]
    sim_port = setup["simulator_port"]
    require_available(port)
    if config["database"] != str(root / "core.sqlite") or not (root / "core.sqlite").is_file():
        raise ValueError("The configured OIP database is missing or outside this installation.")
    if config.get("opcua_read_only") is not True or config.get("legacy_single_infrastructure", False):
        raise ValueError("This profile requires read-only OPC UA and authenticated access.")
    use_simulator = any(s["id"] == "local-simulation" for s in config["sources"])
    if use_simulator:
        require_available(sim_port)
        if not simulator.is_file() or not os.access(simulator, os.X_OK):
            raise ValueError("The OIP package is missing its local simulator.")
        source = next(s for s in config["sources"] if s["id"] == "local-simulation")
        if source["endpoint"] != f"opc.tcp://127.0.0.1:{sim_port}" or source.get("opcua") is not None:
            raise ValueError("The setup's simulation source must remain on its own loopback port.")
    url = f"http://127.0.0.1:{port}"
    children = []
    # Only this foreground process owns its children. An interrupted launch can
    # be restarted through the same entry point without rebuilding the database.
    def interrupted(signum, _frame):
        raise KeyboardInterrupt

    previous = signal.signal(signal.SIGTERM, interrupted)
    try:
        fd = os.open(root / "oip.log", os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "ab") as log:
            info = os.fstat(log.fileno())
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                    or info.st_mode & 0o077 or info.st_nlink != 1):
                raise ValueError("The log file must be private.")
            if use_simulator:
                children.append(subprocess.Popen(
                    [simulator, "--port", str(sim_port)], stdout=log, stderr=log,
                ))
            children.append(subprocess.Popen(
                [core, "--daemon", "--config", root / "core.json",
                 "--ipc-config", root / "ipc.json", "--web-dir", web],
                stdout=log, stderr=log,
            ))
            wait_for_ready(url, children)
            code = issue_login(root, core)
            print(f"OIP läuft unter {url}\nEinmalcode für die Anmeldung: {code}", flush=True)
            if args.open:
                subprocess.run(["/usr/bin/open", url], check=False)
            if children[-1].wait():
                raise ValueError("The Core exited unexpectedly. See the private oip.log.")
    except KeyboardInterrupt:
        pass
    finally:
        signal.signal(signal.SIGTERM, previous)
        for child in reversed(children):
            if child.poll() is not None:
                continue
            child.send_signal(signal.SIGTERM if child is children[-1] else signal.SIGINT)
            try:
                child.wait(timeout=20)
            except subprocess.TimeoutExpired:
                print("OIP shutdown timed out. Wait for the process to stop before restarting.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--instance", help="Absolute instance directory for setup, run and login")
    parser.add_argument("--core", help="Explicit development Core binary")
    parser.add_argument("--web", help="Explicit development browser assets")
    parser.add_argument("--simulator", help="Explicit development simulator binary")
    commands = parser.add_subparsers(dest="command", required=True)
    init = commands.add_parser("setup")
    init.add_argument("--organization", required=True)
    init.add_argument("--infrastructure", required=True)
    init.add_argument("--site", required=True)
    init.add_argument("--backup-directory", required=True)
    policy_source = init.add_mutually_exclusive_group()
    policy_source.add_argument("--license-policy", help="Approved License Center policy for OIP (JSON file)")
    policy_source.add_argument("--package-public-key", help="Provision license policy from the reverified installed package (PEM)")
    init.add_argument("--commercial-license-kind", action="append", default=[],
                      help="Approved policy kind that grants commercial usage; repeat as needed")
    init.add_argument("--port", type=int, default=18870)
    init.add_argument("--simulator-port", type=int, default=14870)
    launch = commands.add_parser("run")
    launch.add_argument("--open", action="store_true")
    commands.add_parser("login")
    policy = commands.add_parser("prepare-license-policy", help="Prepare an OIP policy from approved public keys")
    policy.add_argument("--registry", required=True)
    policy.add_argument("--key-fingerprint", action="append", required=True)
    policy.add_argument("--kind", action="append", required=True)
    policy.add_argument("--right", action="append", default=[])
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if args.command == "prepare-license-policy":
            prepare_license_policy(args)
            return
        if not args.instance:
            parser.error("--instance is required for this command")
        root = absolute_path(args.instance)
        if args.command != "setup" and not root.is_dir():
            raise ValueError("Set up this OIP instance first.")
        private_dir(root)
        core, web, simulator = runtime_paths(root, args)
        if args.command == "login":
            private_json(root / "setup-complete.json")
            print(issue_login(root, core))
            return
        with owning_instance(root):
            if args.command == "setup":
                prepare(root, args, core)
            else:
                run(root, args, core, web, simulator)
    except ImportError:
        parser.exit(1, "OIP: Package verification requires Python cryptography with Ed25519 support.\n")
    except (Refused, ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f"OIP: {error}\n")


if __name__ == "__main__":
    main()
