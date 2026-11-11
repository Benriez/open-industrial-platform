#!/usr/bin/env python3
"""Operate a local OIP Core: start, stop, restart, status, backup and restore.

The script owns one explicit instance: one configuration file, one IPC
configuration, one database and one state directory. It never installs a system
service, it never touches the personal installation of the operator and it
never contacts an endpoint outside the machine.

Safety rules that are enforced, not documented:
  * the personal installation database of the operator is refused, also when it
    is reached through a symlink or a relative path;
  * a backup is a consistent SQLite snapshot of the managed instance, taken
    while the Core may run;
  * a restore is refused when the source file is not a readable SQLite
    database, and it never writes outside the managed instance.

Usage:
  tools/oip_ops.py --state-dir DIR --config FILE [--ipc-config FILE]
                    [--binary PATH] <start|stop|restart|status|backup|restore>
  tools/oip_ops.py ... backup --output FILE
  tools/oip_ops.py ... restore --source FILE
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import shutil
import signal
import secrets
import socket
import sqlite3
import subprocess
import sys
import time

# The personal installation of the operator. It is never written by this
# script: the activation of the real installation is an operator decision.
PERSONAL_ROOTS = (
    pathlib.Path.home() / "Library" / "Application Support" / "OIP",
    pathlib.Path.home() / ".local" / "share" / "OIP",
    pathlib.Path("/etc/oip"),
    pathlib.Path("/var/lib/oip"),
)


def fail(message: str) -> "NoReturn":  # type: ignore[name-defined]
    print("error: " + message, file=sys.stderr)
    raise SystemExit(2)


def resolve(path: pathlib.Path) -> pathlib.Path:
    """The real path of a target, following every symlink."""
    try:
        return path.expanduser().resolve()
    except OSError as error:
        fail(f"{path} cannot be resolved: {error}")
    return path


def is_personal(path: pathlib.Path) -> bool:
    target = resolve(path)
    for root in PERSONAL_ROOTS:
        root = resolve(root)
        if target == root or root in target.parents:
            return True
    return False


def read_config(path: pathlib.Path) -> dict:
    try:
        config = json.loads(path.read_text())
    except FileNotFoundError:
        fail(f"the configuration {path} does not exist")
    except json.JSONDecodeError as error:
        fail(f"the configuration {path} is not valid JSON: {error}")
    if not isinstance(config, dict):
        fail(f"the configuration {path} is not an object")
    return config


def database_of(config: dict, config_path: pathlib.Path) -> pathlib.Path:
    """The data store of the instance.

    A relative path in the configuration is resolved against the directory of
    the configuration. The Core resolves a relative path against the working
    directory of its process — a working directory is not a contract — so the
    tool hands the resolved path to the Core explicitly (see
    `the_database_argument`). The tool and the Core therefore always address
    the same file.
    """
    raw = config.get("database")
    if not raw:
        fail("the configuration names no database")
    candidate = pathlib.Path(raw)
    if not candidate.is_absolute():
        candidate = (config_path.parent / candidate).resolve()
    return candidate


def the_database_argument(database: pathlib.Path) -> list[str]:
    """The argument that names the data store to the Core.

    The daemon of the Core refuses a relative database path, and the
    provisioning step writes to the path that the configuration names. Both
    must be the same file, so the resolved path is passed explicitly.
    """
    return ["--database", str(database)]


def port_of(config: dict) -> int:
    port = config.get("http_port")
    if not isinstance(port, int) or port <= 0:
        fail("the configuration names no usable http_port")
    return port


def provision_ipc(ipc_path: pathlib.Path) -> list[str]:
    """The local IPC credentials of the managed instance.

    The Core rejects a client whose credential file is missing, so the local
    instance is provisioned with one: 32 random bytes, readable by the owner
    only. The value is never printed and never written into a log.
    """
    try:
        ipc = json.loads(ipc_path.read_text())
    except FileNotFoundError:
        fail(f"the IPC configuration {ipc_path} does not exist")
    except json.JSONDecodeError as error:
        fail(f"the IPC configuration {ipc_path} is not valid JSON: {error}")
    # The Core reads the IPC configuration as a protected file: it must not be
    # readable by anybody but the owner of the instance.
    mode = ipc_path.stat().st_mode & 0o777
    if mode & 0o077:
        os.chmod(ipc_path, 0o600)
    socket_path = ipc.get("socket")
    if socket_path:
        parent = pathlib.Path(socket_path).parent
        parent.mkdir(parents=True, exist_ok=True)
        os.chmod(parent, 0o700)
    created = []
    for client in ipc.get("clients", []):
        raw = client.get("credential_file")
        if not raw:
            continue
        credential = pathlib.Path(raw)
        if credential.is_file():
            continue
        credential.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(credential, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(secrets.token_bytes(32))
        os.chmod(credential, 0o600)
        created.append(str(credential))
    return created


def command_provision_plan(args, config_path, paths, config) -> int:
    """The offline provisioning step of the operator.

    The Core creates its data store with the hierarchy and the enabled
    principals of the plan. It is a separate operator step and never runs
    while an instance is running.
    """
    if not args.plan:
        fail("provision needs --plan")
    plan = pathlib.Path(args.plan)
    if not plan.is_file():
        fail(f"the plan {plan} does not exist")
    database = database_of(config, config_path)
    if is_personal(database):
        fail(f"refusing to provision the personal installation: {database}")
    if alive(read_pid(paths)):
        fail("the instance is running; stop it before the provisioning step")
    result = subprocess.run([args.binary, "--config", str(config_path),
                              *the_database_argument(database),
                              "--provision", str(plan)],
                             capture_output=True, text=True, timeout=300)
    if result.returncode != 0:
        fail("the provisioning step failed: " + (result.stderr or result.stdout)[-400:])
    print(json.dumps({
        "status": "provisioned",
        "plan": str(plan),
        "database": str(database),
        "result": result.stdout.strip()[-400:],
    }))
    return 0


def state_paths(state_dir: pathlib.Path) -> dict:
    return {
        "pid": state_dir / "oip.pid",
        "log": state_dir / "oip.log",
        "state": state_dir / "oip.state.json",
    }


def read_pid(paths: dict) -> int | None:
    try:
        return int(paths["pid"].read_text().strip())
    except (FileNotFoundError, ValueError):
        return None


def alive(pid: int | None) -> bool:
    if pid is None:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def port_open(port: int, timeout: float = 0.4) -> bool:
    with socket.socket() as probe:
        probe.settimeout(timeout)
        return probe.connect_ex(("127.0.0.1", port)) == 0


def wait_for(predicate, seconds: float, interval: float = 0.2) -> bool:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return predicate()


def command_start(args, config_path, paths, config) -> int:
    state_dir = pathlib.Path(args.state_dir)
    state_dir.mkdir(parents=True, exist_ok=True)
    pid = read_pid(paths)
    if alive(pid):
        fail(f"the instance is already running with the pid {pid}")
    database = database_of(config, config_path)
    if is_personal(database):
        fail(f"refusing to start against the personal installation: {database}")
    ipc_path = pathlib.Path(args.ipc_config).resolve() if args.ipc_config else None
    if not ipc_path:
        fail("start needs --ipc-config: the daemon always runs with its protected local IPC")
    command = [args.binary, "--daemon", "--config", str(config_path),
               *the_database_argument(database)]
    provisioned = provision_ipc(ipc_path)
    command += ["--ipc-config", str(ipc_path)]
    log = paths["log"].open("ab")
    try:
        process = subprocess.Popen(
            command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    finally:
        log.close()
    paths["pid"].write_text(str(process.pid))
    paths["state"].write_text(json.dumps({
        "pid": process.pid,
        "database": str(database),
        "http_port": port_of(config),
        "config": str(config_path),
        "binary": str(args.binary),
        "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }, indent=2) + "\n")
    port = port_of(config)
    if not wait_for(lambda: alive(process.pid) and port_open(port), 30):
        fail("the Core did not answer on its port within 30 seconds")
    print(json.dumps({
        "status": "started",
        "pid": process.pid,
        "http_port": port,
        "database": str(database),
        "log": str(paths["log"]),
        "ipc_credentials_provisioned": len(provisioned),
    }))
    return 0


def command_stop(args, config_path, paths, config) -> int:
    pid = read_pid(paths)
    if not alive(pid):
        print(json.dumps({"status": "not running"}))
        return 0
    os.kill(pid, signal.SIGTERM)
    if not wait_for(lambda: not alive(pid), 30):
        fail("the Core did not stop within 30 seconds; no signal was forced")
    paths["pid"].unlink(missing_ok=True)
    print(json.dumps({"status": "stopped", "pid": pid}))
    return 0


def command_status(args, config_path, paths, config) -> int:
    pid = read_pid(paths)
    port = port_of(config)
    database = database_of(config, config_path)
    schema = None
    if database.is_file():
        try:
            schema = sqlite_query(database, "pragma user_version;")
        except SystemExit:
            schema = "unreadable"
    report = {
        "status": "running" if alive(pid) else "stopped",
        "pid": pid,
        "http_port": port,
        "port_open": port_open(port),
        "database": str(database),
        "database_exists": database.is_file(),
        "schema_version": schema,
        "log": str(paths["log"]),
    }
    print(json.dumps(report, indent=2))
    return 0 if report["status"] == "running" else 1


SQLITE_CLI = "/usr/bin/sqlite3"


def sqlite_query(database: pathlib.Path, statement: str) -> str:
    """One statement against a Core database.

    The Core writes its schema with STRICT tables. The SQLite of the system
    Python can be older than the release that knows STRICT, so the operator
    tool of the machine is used when it is available.
    """
    if os.path.exists(SQLITE_CLI):
        result = subprocess.run([SQLITE_CLI, "-batch", "-noheader", str(database), statement],
                                capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            fail(f"the database {database} cannot be read: {result.stderr.strip()[-200:]}")
        return result.stdout.strip()
    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    try:
        rows = connection.execute(statement).fetchall()
    finally:
        connection.close()
    return "\n".join("|".join(str(value) for value in row) for row in rows)


def sqlite_backup(source: pathlib.Path, target: pathlib.Path) -> None:
    """A consistent snapshot of a running Core database."""
    if os.path.exists(SQLITE_CLI):
        result = subprocess.run(
            [SQLITE_CLI, "-batch", str(source), f".backup '{target}'"],
            capture_output=True, text=True, timeout=600)
        if result.returncode != 0:
            fail(f"the backup failed: {result.stderr.strip()[-200:]}")
        return
    connection = sqlite3.connect(f"file:{source}?mode=ro", uri=True)
    try:
        destination = sqlite3.connect(target)
        try:
            connection.backup(destination)
        finally:
            destination.close()
    finally:
        connection.close()


def command_backup(args, config_path, paths, config) -> int:
    database = database_of(config, config_path)
    if is_personal(database):
        fail(f"refusing to back up the personal installation: {database}")
    if not database.is_file():
        fail(f"the database {database} does not exist")
    target = pathlib.Path(args.output) if args.output else (
        pathlib.Path(args.state_dir) / "backups" /
        (time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + ".sqlite"))
    target.parent.mkdir(parents=True, exist_ok=True)
    # The backup API takes a consistent snapshot while the Core runs.
    sqlite_backup(database, target)
    integrity = sqlite_query(target, "pragma integrity_check;")
    if integrity != "ok":
        fail(f"the backup {target} failed its integrity check: {integrity}")
    # The backup holds the data of the instance: it stays owner-private.
    os.chmod(target, 0o600)
    print(json.dumps({
        "status": "backed up",
        "source": str(database),
        "backup": str(target),
        "bytes": target.stat().st_size,
        "integrity": integrity,
    }))
    return 0


def command_restore(args, config_path, paths, config) -> int:
    database = database_of(config, config_path)
    if is_personal(database):
        fail(f"refusing to restore the personal installation: {database}")
    source = pathlib.Path(args.source)
    if not source.is_file():
        fail(f"the backup {source} does not exist")
    if alive(read_pid(paths)):
        fail("the instance is running; stop it before a restore")
    integrity = sqlite_query(source, "pragma integrity_check;")
    schema = sqlite_query(source, "pragma user_version;")
    if integrity != "ok":
        fail(f"the backup {source} failed its integrity check: {integrity}")
    database.parent.mkdir(parents=True, exist_ok=True)
    staging = database.with_suffix(database.suffix + ".restore")
    shutil.copyfile(source, staging)
    # The Core refuses a database that anybody but the owner can read.
    os.chmod(staging, 0o600)
    os.replace(staging, database)
    print(json.dumps({
        "status": "restored",
        "backup": str(source),
        "database": str(database),
        "schema_version": schema,
        "integrity": integrity,
    }))
    return 0


def command_provision(args, config_path, paths, config) -> int:
    if not args.ipc_config:
        fail("provision needs --ipc-config")
    created = provision_ipc(pathlib.Path(args.ipc_config).resolve())
    print(json.dumps({"status": "provisioned", "credentials_created": created}))
    return 0


def command_log(args, config_path, paths, config) -> int:
    """The log of the instance, as the operator reads it.

    The Core writes JSON lines into the log of the state directory. The
    command prints the last lines of it; the operator can therefore see what
    the instance did without an editor and without OpenCode.
    """
    log = paths["log"]
    if not log.is_file():
        fail(f"the instance wrote no log: {log}")
    lines = log.read_text(errors="replace").splitlines()
    tail = args.lines if args.lines and args.lines > 0 else len(lines)
    print("\n".join(lines[-tail:]))
    return 0


COMMANDS = {
    "start": command_start,
    "provision": command_provision,
    "provision-plan": command_provision_plan,
    "stop": command_stop,
    "restart": None,
    "status": command_status,
    "log": command_log,
    "backup": command_backup,
    "restore": command_restore,
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=sorted(COMMANDS))
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--ipc-config", default=None)
    parser.add_argument("--binary", default="target/release/oip-server")
    parser.add_argument("--output", default=None)
    parser.add_argument("--source", default=None)
    parser.add_argument("--plan", default=None)
    parser.add_argument("--lines", type=int, default=50,
                        help="the number of the last lines of the log (0: all)")
    args = parser.parse_args()

    config_path = pathlib.Path(args.config).resolve()
    state_dir = pathlib.Path(args.state_dir).resolve()
    ipc_path = pathlib.Path(args.ipc_config).resolve() if args.ipc_config else None
    paths = state_paths(state_dir)
    config = read_config(config_path)

    if args.command == "restart":
        if not ipc_path:
            fail("restart needs --ipc-config: the daemon always runs with its protected local IPC")
        command_stop(args, config_path, paths, config)
        return command_start(args, config_path, paths, config)
    if args.command == "backup" and not args.output:
        pass
    if args.command == "restore" and not args.source:
        fail("restore needs --source")
    return COMMANDS[args.command](args, config_path, paths, config)


if __name__ == "__main__":
    raise SystemExit(main())
