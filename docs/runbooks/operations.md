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

## 7. The archive of a device

The archive of a device is an **offline operation** of the Core. The managed session refuses it
with `OFFLINE_ARCHIVE_REQUIRED` ("Archive remains an explicit offline operation"), because an
archive changes the registry while the Core is serving. The supported path applies the archive
with the Core stopped:

```sh
# 1. the device is registered and known to the operator
# 2. the Core is stopped
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" stop

# 3. the archive is written as the offline plan of the Core
cat > "$STATE/archive.json" <<'JSON'
{
  "principal": "reader-org-a",
  "changes": [
    { "operation": "archive", "id": "<device-id>", "expected_revision": 1 }
  ]
}
JSON

# 4. the plan is applied with the explicit flag of the Core
oip-server --config "$CORE_CONFIG" --inventory-plan "$STATE/archive.json" --inventory-apply

# 5. the Core starts again
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" \
    --ipc-config "$IPC_CONFIG" --binary target/release/oip-server start
```

The Core answers with the plan it applied: `{"applied": true, "apply_mode":
"offline_requires_restart"}` and the action `{"outcome": "archive"}`. The revision of the device
is the guard of the write, exactly as in the online update.

**What the archive means.** The record of the device, its identity and its metadata stay intact —
the archive is not a deletion — and the device collects no measurements anymore. An archived device
is not part of the active inventory: the read only shows it when the archived ones are asked for
(`include_archived=true`). The measurements of the device that were collected before the archive
remain in the history.

The rehearsal is `tests/oip_offline_archive.py`; its receipt is
`docs/evidence/oip-offline-archive/offline-archive.json`. It proves the refusal of the managed
session, the application of the offline plan, the hiding of the archived device from the active
inventory and the survival of its identity and its metadata.

## 8. The personal installation is never touched

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
backup procedure (see §11 and `docs/OIP_RELEASE_PROGRESS.md`, N4). This
runbook does not perform it.

## 9. The macOS application bundle

The desktop client is a Flutter application bundle. It is built reproducibly
from the same Dart code as the web release:

```sh
cd apps/flutter
flutter build macos --release \
    --dart-define=OIP_API_URL=http://127.0.0.1:<port-of-the-instance>
# -> apps/flutter/build/macos/Build/Products/Release/oip_dashboard.app
```

The bundle needs the address of the instance as a compile-time definition
(`OIP_API_URL`). Without it the bundle starts and asks the Core for the
authorized projection of the principal, the Core refuses it with 403, and the
bundle shows the operator login of the approved shell. That is the designed
behaviour of the real mode: the bundle never shows data of a session it does
not have.

**What the operator does with the bundle.**

```sh
BUNDLE="apps/flutter/build/macos/Build/Products/Release/oip_dashboard.app"

# 1. the one-time code of the operator session
target/release/oip-server --browser-login \
    --ipc-socket "$STATE/s" --ipc-credential "$STATE/platform.credential"

# 2. the bundle
open "$BUNDLE"
# the code of the session is entered in the window of the bundle

# 3. the bundle is stopped with the signal of the operator
pkill -TERM -f oip_dashboard.app
```

The window of the bundle is placed by the system; the bundle reports the
placement in its log (`OIP-WINDOW …`). When the frame of the storyboard
touches no visible screen — it belongs to the screen the bundle was generated
for — the runner places the window in the centre of the main screen.

**The launch agent is not part of this runbook.** Installing the application
as a launch agent is a system service and needs an explicit operator
authorization. The procedure above keeps the instance under the control of the
operator, without OpenCode, with a reproducible start, stop, restart, backup
and restore.

## 10. The daemon of a historical release

A local instance of an older release is a daemon of its own era. Its protected
local IPC binds the clients to a **provisioned, enabled principal** of the era
(`docs/architecture/oip-008-identity-authorization.md`); the actor with
permissions and a source scope is the shape of OIP-007 and the era refuses it
with `invalid protected local IPC configuration/path`. A daemon that is bound
to a principal that does not exist in its store refuses the start with
`IPC binding requires a provisioned enabled principal or explicit legacy mode`.

The handover of a *running* historical instance is rehearsed by
`tests/oip_historical_daemon.py`: the era starts, collects, answers the
authorized reads of its principals, the release binary takes over the same
store, and the historical binary serves the restored store again.

## 11. The activation of the release on the personal installation

This section is the procedure for the **operator**. The loop never performs
it: the tool refuses every operation whose target is the personal
installation, and the decision with its backup belongs to the operator.

**What is measured.** The rehearsal `tests/oip_activation_dry_run.py` copies
the store of the operator into a disposable directory and lets the release
binary migrate the **copy**
(`docs/evidence/oip-activation-dry-run/activation-dry-run.json`): the
migration of the schema 6 to the schema 7 is **accepted**, the inventory of
the instance survives it unchanged (the organizations, the infrastructures,
the sites, the principals, the roles, the bindings and the devices), the
integrity check answers `ok` and the daemon serves the migrated copy. The
personal installation itself was not touched: the same sha256, still schema 6.

**The procedure.**

```sh
# 1. the fresh backup of the personal store. The tool refuses the personal
#    installation, so the operator copies the store with the backup of
#    SQLite itself. The copy is owner-private.
STORE="$HOME/Library/Application Support/OIP/real/core.sqlite"
BACKUP="$HOME/Library/Application Support/OIP/real/backups/core-$(date -u +%Y%m%dT%H%M%SZ).sqlite"
mkdir -p "$(dirname "$BACKUP")" && chmod 700 "$(dirname "$BACKUP")"
/usr/bin/sqlite3 -readonly "$STORE" ".backup '$BACKUP'"
chmod 600 "$BACKUP"
shasum -a 256 "$STORE" "$BACKUP"

# 2. the dry run: the release binary migrates a COPY of the store. The
#    configuration of the instance names the sources of the registry and the
#    local IPC binds to a principal that the store carries and that is
#    enabled — the Core refuses the start otherwise.
cp "$STORE" "$STORE.dry-run" && chmod 600 "$STORE.dry-run"
#    ... run the release binary against the copy, then check:
/usr/bin/sqlite3 -readonly "$STORE.dry-run" "pragma user_version; pragma integrity_check;"

# 3. the activation itself, with the same configuration, now against the
#    real store. The operator stops the instance first.
/usr/bin/sqlite3 -readonly "$STORE" "pragma user_version;"
target/release/oip-server --config "$HOME/Library/Application Support/OIP/real/core.json"

# 4. the check after the activation
/usr/bin/sqlite3 -readonly "$STORE" "pragma user_version; pragma integrity_check;"
shasum -a 256 "$STORE"   # the store changed: the migration wrote to it
```

**The rollback.** The backup of the first step restores the previous state:
stop the instance, copy the backup over the store, and start the previous
release again. The rehearsal `tests/oip_upgrade_rollback.py` proves exactly
that path with a protected historical binary
(`docs/evidence/oip-upgrade-rollback/upgrade-rollback.json`).

**Two properties of the rehearsal that the procedure keeps.** The copy declares
the sources of the instance with closed loopback ports, so no private endpoint
is contacted; and the local IPC binds to the enabled principal of the store,
because a principal that the store does not carry is refused by the Core.

## 12. What the receipts prove

`docs/evidence/oip-operations/operations.json` records the measured result of
the sequence above against a disposable instance, and
`docs/evidence/oip-upgrade-rollback/upgrade-rollback.json` the result of the
upgrade and the rollback: the provisioning, the start,
the status, the backup with its integrity check, the refused restore of a
running instance, the stop, the restore, the start again, the restart, the
stop and the three refusals of the personal installation together with the
unchanged hash of the personal database.

`docs/evidence/oip-macos-app/macos-app.json` records the measured result of the
application bundle: the build, the start, the requests of the bundle, the
refusal of the Core, the termination without an orphan and the start again.
`docs/evidence/oip-historical-daemon/historical-daemon.json` records the
measured result of the daemon handover: the refused shape of OIP-007, the
started daemon of the era, the scoped reads of its principals, the collection,
the takeover of the release binary and the restored store served by the era
again.
