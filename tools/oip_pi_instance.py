#!/usr/bin/env python3
"""Prepare the files of a disposable OIP instance on a host of its own.

The instance is **self-contained**: its configuration, its plan, its IPC
configuration and its data store live inside one directory, and every path in
those files is **absolute** — the Core resolves a relative database path
against the working directory of its process, and a working directory is not a
contract.

The script is run **on the host that carries the instance** (the Raspberry
Pi), because two of the values cannot be known on another machine: the
absolute path of the instance and the numeric uid of the user that runs it
(the IPC configuration binds every client to the uid of the process).

Safety rules that are enforced, not documented:
  * the directory of the instance must be **absolute** and must not be a
    symlink to somewhere else;
  * the directory of the instance must be **private** (mode 0700): the IPC
    configuration and the credential of the operator live in it;
  * the **personal installation of the operator** is refused — also when it is
    reached through a symlink or a relative path;
  * an instance that is already prepared is **never overwritten**: the
    preparation is a step, not a synchronisation;
  * every file that is written stays **inside** the directory of the
    instance; nothing outside is touched.

The script writes no service, installs nothing, starts nothing and contacts
no endpoint outside the host.

Usage:
    python3 tools/oip_pi_instance.py --instance /home/<user>/oip-instance \
        [--http-port 18808] [--source-port 18809] [--source-id pi-simulation]
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import socket
import sys

# The personal installation of the operator. The instance of a foreign host is
# disposable and owns its own data; the personal installation stays where it
# is.
PERSONAL_ROOTS = (
    pathlib.Path.home() / "Library" / "Application Support" / "OIP",
    pathlib.Path.home() / ".local" / "share" / "OIP",
    pathlib.Path("/etc/oip"),
    pathlib.Path("/var/lib/oip"),
)

# The permissions of a reader. The same set that the local preparation of the
# operator uses (examples/prepare-local-ipc.py).
PERMISSIONS = [
    "core_read",
    "sources_read",
    "devices_read",
    "telemetry_read",
    "events_read",
    "opcua_read",
    "hierarchy_read",
]

# The principals of the instance. Every one of them is a client of the local
# IPC: the client of the operator session is the principal with the platform
# scope.
PRINCIPALS = ["platform-reader", "reader-org-a"]

# The maximum length of a Unix socket path. A path that is too long is
# refused by the kernel with an error that names neither the cause nor the
# remedy.
MAX_SOCKET_PATH = 100


def fail(message: str) -> "NoReturn":  # type: ignore[name-defined]
    print("error: " + message, file=sys.stderr)
    raise SystemExit(2)


def resolve(path: pathlib.Path) -> pathlib.Path:
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


def write_json(path: pathlib.Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")
    os.chmod(path, 0o600)


def the_core_config(instance: pathlib.Path, http_port: int, source: dict) -> dict:
    """The configuration of the Core of the instance.

    The Core binds the loopback of the host it runs on: the instance is
    reached through a forward of the loopback of the client, and no port of
    the host is published.
    """
    return {
        "database": str(instance / "state" / "oip-core.sqlite"),
        "http_port": http_port,
        "sources": [source],
        "queue_capacity": 64,
        "stale_after_ms": 5000,
        "shutdown_timeout_ms": 10000,
        "web_dir": None,
        "legacy_single_infrastructure": False,
    }


def the_plan(source_id: str) -> dict:
    """The plan of the instance: one organization, one infrastructure, one
    site, one source — the simulation of the host itself."""
    return {
        "organizations": [{"id": "pi-org", "name": "Operator on the host"}],
        "infrastructures": [
            {"id": "pi-infra", "organization_id": "pi-org", "name": "The host"}
        ],
        "sites": [
            {"id": "pi-site", "infrastructure_id": "pi-infra", "name": "the host"}
        ],
        "sources": [
            {
                "source_id": source_id,
                "site_id": "pi-site",
                "device_id": "pi-device",
                "entity_id": "pi-simulation",
            }
        ],
        "principals": [
            {"id": principal, "name": principal, "enabled": True}
            for principal in PRINCIPALS
        ],
        "roles": [
            {
                "id": "reader",
                "name": "Read only capabilities",
                "permissions": PERMISSIONS,
            }
        ],
        "bindings": [
            {
                "principal_id": "platform-reader",
                "role_id": "reader",
                "scope": {"kind": "platform"},
            },
            {
                "principal_id": "reader-org-a",
                "role_id": "reader",
                "scope": {"kind": "organization", "id": "pi-org"},
            },
        ],
        "legacy_single_infrastructure": False,
    }


def the_ipc_config(instance: pathlib.Path, principals: list) -> dict:
    """The protected local IPC configuration of the instance.

    The configuration is in the **principal mode**: every client names the
    principal it acts as, and the configuration carries no legacy actor, no
    legacy grants and no legacy scope. The mode is not a choice of taste:
    the code of the operator session (`--browser-login`) is only minted for a
    client of the principal mode — a configuration with an actor and a
    `rest_policy` cannot mint a session at all.

    The credential of a client is **not** written by this script: the tool of
    the instance writes it with 32 random bytes and the mode 0600 when it
    starts the Core (tools/oip_ops.py).
    """
    socket_path = instance / "state" / "ipc.sock"
    clients = []
    for principal in principals:
        clients.append({
            "uid": os.geteuid(),
            "credential_file": str(instance / "state" / f"{principal}.credential"),
            "policy": {"principal": principal},
        })
    return {
        "socket": str(socket_path),
        "max_sessions": 16,
        "clients": clients,
    }


def has_no_symlink(path: pathlib.Path) -> bool:
    """True when no component of the path is a symlink.

    The Core refuses a socket or a credential whose path contains a symlink
    (`plain_path`): the check happens here, before the instance is prepared,
    so that the operator gets a message that names the cause instead of a
    refusal of the Core.
    """
    current = pathlib.Path(path.anchor)
    for part in path.parts[1:]:
        current = current / part
        if current.is_symlink():
            return False
    return True


def prepare(instance: pathlib.Path, http_port: int, source_port: int,
            source_id: str) -> dict:
    if not instance.is_absolute():
        fail("the directory of the instance must be an absolute path")
    if is_personal(instance):
        fail(f"refusing to prepare the personal installation: {instance}")
    if not has_no_symlink(instance):
        fail(f"the path of the instance contains a symlink: {instance}")
    if instance.exists():
        if not instance.is_dir():
            fail(f"{instance} is not a directory")
        prepared = instance / "etc" / "core.json"
        if prepared.is_file():
            fail(f"the instance at {instance} is already prepared")
    else:
        instance.mkdir(parents=True, mode=0o700)
    os.chmod(instance, 0o700)
    (instance / "etc").mkdir(parents=True, exist_ok=True)
    (instance / "state").mkdir(parents=True, exist_ok=True)
    os.chmod(instance / "state", 0o700)

    socket_path = instance / "state" / "ipc.sock"
    if len(str(socket_path).encode()) > MAX_SOCKET_PATH:
        fail(f"the socket path is too long for this host: {socket_path}")

    source = {
        "id": source_id,
        "name": "The simulation of this host",
        "endpoint": f"opc.tcp://127.0.0.1:{source_port}",
        "namespace": 2,
    }
    write_json(instance / "etc" / "core.json",
               the_core_config(instance, http_port, source))
    write_json(instance / "etc" / "plan.json", the_plan(source_id))
    write_json(instance / "etc" / "ipc.json", the_ipc_config(instance, PRINCIPALS))
    return {
        "status": "prepared",
        "the_instance": str(instance),
        "the_core_configuration": str(instance / "etc" / "core.json"),
        "the_plan": str(instance / "etc" / "plan.json"),
        "the_ipc_configuration": str(instance / "etc" / "ipc.json"),
        "the_database": str(instance / "state" / "oip-core.sqlite"),
        "the_socket": str(socket_path),
        "the_credential_of_the_operator":
            str(instance / "state" / "platform-reader.credential"),
        "the_http_port": http_port,
        "the_source_port": source_port,
        "the_source_id": source_id,
        "the_uid": os.geteuid(),
        "the_host": socket.gethostname(),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prepare the files of a disposable OIP instance.")
    parser.add_argument("--instance", required=True,
                        help="the absolute directory of the instance")
    parser.add_argument("--http-port", type=int, default=18808,
                        help="the port of the Core on the loopback of the host")
    parser.add_argument("--source-port", type=int, default=18809,
                        help="the port of the simulation on the loopback of the host")
    parser.add_argument("--source-id", default="pi-simulation",
                        help="the identifier of the source of the instance")
    args = parser.parse_args()
    if not 1024 <= args.http_port <= 65535:
        fail("the port of the Core must be in the range of the unprivileged ports")
    if not 1024 <= args.source_port <= 65535:
        fail("the port of the simulation must be in the range of the unprivileged ports")
    if args.http_port == args.source_port:
        fail("the Core and the simulation must not use the same port")
    report = prepare(pathlib.Path(args.instance), args.http_port,
                     args.source_port, args.source_id)
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
