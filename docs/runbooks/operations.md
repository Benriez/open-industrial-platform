# OIP operations runbook (local instance)

The runbook describes how an operator runs a **local OIP Core** on a macOS
machine without OpenCode: how it is provisioned, started, stopped, restarted,
how its log is read and how its data is backed up and restored.

It is a description of an existing, tested procedure. Every command in it was
executed against a disposable instance; the receipts are in
`docs/evidence/oip-operations/`.

The tool is `tools/oip_ops.py`. It operates **one** explicit instance: one
configuration file, one IPC configuration, one database and one state
directory. It installs no system service, it contacts no endpoint outside the
machine and it refuses to touch the personal installation of the operator.

---

## 0. What the instance consists of

| Item | Meaning |
|---|---|
| `--config FILE` | the Core configuration: the database path, the HTTP port, the sources and the web directory |
| `--ipc-config FILE` | the protected local IPC configuration: the Unix socket and the credentials of the local clients |
| `--state-dir DIR` | the state of the tool: the pid file, the log file and the backups |
| the database | the SQLite data store of the instance; the Core writes its schema with STRICT tables and refuses a file that anybody but the owner can read |

Two files must be owner-private (`0600`) and one directory (`0700`):

* the IPC configuration — the Core reads it as a protected file;
* every credential file of the IPC configuration — 32 random bytes, never logged;
* the directory that holds the Unix socket — macOS authorizes the socket through this directory.

The tool creates a missing credential and tightens the permissions of the IPC
configuration. It never prints a credential.

## 1. Provision the data store (once, offline)

The Core creates its data store with the hierarchy and the enabled principals
of a plan. This is a separate operator step and never runs while an instance
is running.

```sh
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" \
    provision-plan --plan examples/multi-infrastructure-plan.json
```

The sources of the plan must match the sources of the configuration. The
example plan carries an OPC UA source; an instance without that source uses a
plan without it.

The plan names the principals. The IPC configuration must bind to a principal
that the plan enables, otherwise the Core refuses to start with
`IPC binding requires a provisioned enabled principal or explicit legacy mode`.

## 2. Start, status, stop, restart

```sh
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" \
    --ipc-config "$IPC_CONFIG" --binary target/release/oip-server start
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" status
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" \
    --ipc-config "$IPC_CONFIG" --binary target/release/oip-server restart
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" stop
```

* `start` launches the daemon in its own session, writes the pid file and
  waits until the HTTP port answers. It fails when the Core does not answer
  within 30 seconds.
* `stop` sends `SIGTERM` and waits for the clean shutdown of the Core. It
  never forces a signal: an instance that does not stop within 30 seconds is
  reported as such.
* `restart` is `stop` followed by `start`.
* `status` reports the pid, the port, the port state, the database, its
  schema version and the log file.

The daemon always runs with its protected IPC configuration; the tool refuses
a `start` without it.

## 3. The log

The Core writes JSON lines to stderr. The tool redirects them into
`$STATE/oip.log`. The daemon uses the filter `warn,oip_server=info,rmcp=off`,
so a more specific `RUST_LOG` cannot lift the redaction of the SDK traces.

```sh
tail -f "$STATE/oip.log" | python3 -m json.tool --json-lines
```

A clean shutdown ends with a line that names the state of the shutdown:

```json
{"clean":true,"uncommitted":0,"adapter_failures":0,"persistence_thread_joined":true,"http_drained":true,"http_forced_close":false}
```

`uncommitted` is the number of observations that were not persisted when the
Core stopped. It must be `0` for a clean shutdown.

## 4. Backup

```sh
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" backup
```

The backup is a consistent snapshot of the running instance (the SQLite backup
API), it is verified with an integrity check, it is a single file and it stays
owner-private. The default target is
`$STATE/backups/<timestamp>.sqlite`; `--output FILE` names another target.

The Core writes its schema with STRICT tables. The SQLite of a system Python
can be older than the release that knows STRICT, so the tool uses the SQLite
of the machine (`/usr/bin/sqlite3`) when it is available.

## 5. Restore

```sh
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" \
    restore --source "$STATE/backups/20261108T143554Z.sqlite"
```

A restore is refused while the instance is running. The source is verified
with an integrity check before it replaces the database, and the restored file
is owner-private, because the Core refuses a database that anybody but the
owner can read. The replacement is atomic: the copy is written next to the
database and renamed over it.

After a restore, start the instance again and check the log.

## 6. Upgrade and rollback

An upgrade of a local instance is a handover of the data store to the new
binary. It is rehearsed by `tests/oip_upgrade_rollback.py` against a protected
historical binary and the current release binary:

```sh
python3 tests/oip_upgrade_rollback.py --evidence target/oip-upgrade-rollback
```

The rehearsal proves that the release binary takes over the data store of the
previous release, that the schema is migrated and that the data of the store
survives, and that the backup taken before the upgrade restores the previous
state, which the previous release adopts again.

The measured result: the historical binary provisions the store at schema 3
with two organizations; the release binary serves the same store, migrates it
to schema 7 and keeps the organizations; the restore brings the schema back to
3 and the historical binary adopts the restored store.

Three rules of the handover were found while proving it and are part of the
procedure:

* **The runtime sources must exactly match the provisioned registry.** A
  configuration whose sources differ from the provisioned ones is refused with
  `runtime sources must exactly match provisioned registry`.
* **The data store must be owner-private.** A store that anybody but the owner
  can read is refused with `database/sidecar must be owned by operator with
  private permissions`.
* **The configuration of an instance is not portable between releases.** A
  historical binary refuses the fields of a newer configuration and vice
  versa. The upgrade therefore keeps the configuration of the era of the
  instance until the instance has been migrated.

## 7. The personal installation is never touched

The personal installation of the operator lives in
`~/Library/Application Support/OIP/real/core.sqlite`. The tool refuses every
operation whose target resolves into the personal installation, a system
directory or the per-user data directory of OIP — also when the path is
reached through a relative path or a symlink:

```
error: refusing to back up the personal installation: /Users/<operator>/Library/Application Support/OIP/real/core.sqlite
error: refusing to restore the personal installation: ...
error: refusing to start against the personal installation: ...
```

The activation of the real installation is an operator decision with its own
backup procedure (see `docs/OIP_RELEASE_PROGRESS.md`, N4). This runbook does
not perform it.

## 8. Installation on macOS

Installing the application as a launch agent is **not** part of this runbook:
installing a system service needs an explicit operator authorization. The
procedure above keeps the instance under the control of the operator, without
OpenCode, with a reproducible start, stop, restart, backup and restore.

## 9. What the receipts prove

`docs/evidence/oip-operations/operations.json` records the measured result of
the sequence above against a disposable instance, and
`docs/evidence/oip-upgrade-rollback/upgrade-rollback.json` the result of the
upgrade and the rollback: the provisioning, the start,
the status, the backup with its integrity check, the refused restore of a
running instance, the stop, the restore, the start again, the restart, the
stop and the three refusals of the personal installation together with the
unchanged hash of the personal database.
