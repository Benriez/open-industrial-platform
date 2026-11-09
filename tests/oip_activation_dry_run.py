#!/usr/bin/env python3
"""The dry run of the activation of the release on the operator's instance.

The activation of the release on the personal installation is an **operator
decision** (N4): the Core refuses to touch the personal installation and the
loop never activates it.

Before that decision the operator needs to know whether the activation would
succeed at all. The migration of the Core verifies the checksum of every
migration that the store already carries: if the SQL of an era changed after
the store was written, the activation is refused.

This rehearsal answers that question **without touching the personal
installation**: it copies the store of the operator into a disposable
directory, lets the release binary migrate the **copy**, and records the
result — the schema before and after, the migration's acceptance or refusal,
the inventory of the instance before and after and the integrity check.

The copy carries the data of the operator; the receipt carries only counts,
the schema versions and the hashes of the store itself. The hash of the
personal installation is measured before and after: it must not change.

Usage:
  python3 tests/oip_activation_dry_run.py [--evidence DIR] [--database PATH]
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
TOOL = ROOT / "tools" / "oip_ops.py"
PERSONAL = pathlib.Path.home() / "Library/Application Support/OIP/real/core.sqlite"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sqlite_value(database, statement):
    result = subprocess.run(["/usr/bin/sqlite3", "-batch", "-noheader", str(database), statement],
                            capture_output=True, text=True, timeout=60)
    return result.stdout.strip()


def inventory(database):
    tables = ["organizations", "infrastructures", "sites", "source_placements",
              "principals", "read_roles", "role_bindings", "inventory_devices",
              "observations", "collection_events", "data_gaps", "source_health_history",
              "settings"]
    counts = {}
    for table in tables:
        value = sqlite_value(database, f"select count(*) from {table};")
        counts[table] = value if value != "" else None
    return counts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-activation-dry-run"))
    parser.add_argument("--database", default=str(PERSONAL))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-activation-dry-run-v1", "steps": []}

    source = pathlib.Path(args.database).expanduser()
    if not source.is_file():
        report["status"] = "BLOCKED"
        report["reason"] = f"the store of the operator is not present: {source}"
        (evidence / "activation-dry-run.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return 2

    # The hash of the personal installation before the rehearsal: it must not
    # change.
    before_hash = sha256(source)
    report["the_store"] = {"the_path_of_the_operator": "the personal installation",
                           "the_sha256_before": before_hash,
                           "the_schema_before": sqlite_value(source, "pragma user_version;")}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-activation-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    try:
        # The copy of the store of the operator. The Core never sees the
        # personal installation.
        copy = work / "core.sqlite"
        shutil.copyfile(source, copy)
        os.chmod(copy, 0o600)
        report["the_copy"] = {"the_sha256": sha256(copy),
                              "the_sha256_equals_the_original": sha256(copy) == before_hash}
        assert report["the_copy"]["the_sha256_equals_the_original"], \
            "the copy of the store differs from the original"

        import socket
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            http_port = probe.getsockname()[1]
        # The runtime sources must exactly match the provisioned registry of
        # the instance. The identifiers come from the copy; the endpoints are
        # closed ports of the loopback: the rehearsal never contacts a private
        # endpoint of the operator.
        source_ids = [line for line in
                      sqlite_value(copy, "select source_id from source_placements order by source_id;").splitlines()
                      if line]
        report["the_sources_of_the_instance"] = len(source_ids)
        closed_port = 1
        (work / "core.json").write_text(json.dumps({
            "database": str(copy), "http_port": http_port,
            "sources": [{"id": source_id, "name": f"source {source_id}",
                         "endpoint": f"opc.tcp://127.0.0.1:{closed_port}", "namespace": 2}
                        for source_id in source_ids],
            "legacy_single_infrastructure": False,
        }, indent=2))
        credential = work / "platform.credential"
        credential.write_bytes(os.urandom(32))
        os.chmod(credential, 0o600)
        # The local IPC binds to a principal that the store of the instance
        # carries and that is enabled. The identifier of the principal of the
        # operator stays in the copy: the receipt carries only the count.
        principals = [line for line in
                      sqlite_value(copy, "select id from principals where enabled=1;").splitlines()
                      if line]
        report["the_principals_of_the_instance"] = len(principals)
        assert principals, "the store of the operator carries no enabled principal"
        (work / "ipc.json").write_text(json.dumps({
            "socket": str(work / "s"), "max_sessions": 4,
            "clients": [{"uid": os.getuid(), "credential_file": str(credential),
                         "policy": {"principal": principals[0]}}],
        }, indent=2))
        os.chmod(work / "ipc.json", 0o600)
        state = work / "state"

        def tool(*arguments, expect_success=True):
            result = subprocess.run([sys.executable, str(TOOL), "--state-dir", str(state),
                                     "--config", str(work / "core.json"),
                                     "--ipc-config", str(work / "ipc.json"),
                                     "--binary", args.binary, *arguments],
                                    capture_output=True, text=True, timeout=600)
            if expect_success and result.returncode != 0:
                raise AssertionError(f"{arguments[0]} failed: "
                                     f"{result.stderr.strip() or result.stdout.strip()}")
            return result

        report["the_inventory_before"] = inventory(copy)
        report["the_migrations_before"] = [
            line.split("|")[0] for line in
            sqlite_value(copy, "select version from schema_migrations order by version;").splitlines()
        ]

        # The release binary opens the copy: the migration runs.
        started = tool("start", expect_success=False)
        report["the_start_exit_code"] = started.returncode
        report["the_start_output"] = (started.stderr.strip() or started.stdout.strip())[-400:]
        report["the_schema_after"] = sqlite_value(copy, "pragma user_version;")
        report["the_inventory_after"] = inventory(copy)
        report["the_integrity"] = sqlite_value(copy, "pragma integrity_check;")
        report["the_migrations_after"] = [
            line.split("|")[0] for line in
            sqlite_value(copy, "select version from schema_migrations order by version;").splitlines()
        ]
        if started.returncode == 0:
            report["the_activation_would_succeed"] = True
            report["steps"].append("the release binary serves the copy of the operator")
            tool("stop", expect_success=False)
            # Nothing of the inventory of the operator may be lost.
            for table, count in report["the_inventory_before"].items():
                if count is None:
                    continue
                after = report["the_inventory_after"].get(table)
                assert after is not None, f"the migration lost the table {table}"
                if table in ("observations", "collection_events", "data_gaps",
                             "source_health_history"):
                    assert int(after) >= int(count), \
                        f"the migration lost {table}: {count} -> {after}"
                    continue
                assert after == count, f"the migration changed {table}: {count} -> {after}"
        else:
            report["the_activation_would_succeed"] = False
            report["steps"].append("the release binary refused the store of the operator")
        report["status"] = "PASS" if report["the_activation_would_succeed"] else "REFUSED"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        # The log of the instance is the proof of what happened: it is kept
        # with the receipt.
        log = work / "state" / "oip.log"
        if log.is_file():
            (evidence / "the-instance.log").write_text(log.read_text(errors="ignore"))
            report["the_log_of_the_instance"] = (evidence / "the-instance.log").name
        if report.get("status") == "PASS":
            shutil.rmtree(work, ignore_errors=True)
        else:
            report["the_work_directory"] = str(work)

    # The personal installation must be untouched.
    report["the_sha256_after"] = sha256(source)
    report["the_personal_installation_is_unchanged"] = \
        report["the_sha256_after"] == before_hash
    report["the_schema_of_the_personal_installation_after"] = \
        sqlite_value(source, "pragma user_version;")
    if not report["the_personal_installation_is_unchanged"]:
        report["status"] = "FAIL"
        report["error"] = "the personal installation changed during the rehearsal"

    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "activation-dry-run.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items()
                      if k not in ("the_inventory_before", "the_inventory_after")}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
