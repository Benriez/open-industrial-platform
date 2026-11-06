# OIP-008.5 — Tested local operator onboarding

Use the isolated feature binary until separately integrated. This work does not alter main or install a system service. Commands below are local development, not production OT authorization. Normal default startup has no sources, demo, webassets or generated hierarchy.

```sh
cd /Users/benny/Code/open-industrial-platform-worktrees/oip-0085
cargo build --locked --workspace
# A fresh empty instance, own free loopback port and new DB:
target/debug/oip-server --database /private/tmp/oip-empty.sqlite --port 18885 --no-web
# GET http://127.0.0.1:18885/api/v2/installation/status → No infrastructure configured
# Ctrl+C for controlled shutdown. Never target an existing operator DB accidentally.
```

The actual helper creates only a **new** private directory. All four display names are explicit operator input; Organization/Infrastructure/Site/Principal/Role IDs are generated UUIDs. No device or source is seeded. The explicit operator role is Organization-scoped; it receives no global Platform/MCP-management grant. Credentials stay in a private file and are never printed. Without --apply it only prepares files; with --apply it invokes offline provisioning and the separate authorized inventory-initialize migration.

```sh
python3 tests/oip0085/onboard.py init \
  --directory /private/tmp/oip-personal \
  --organization-name 'Meine Organisation' \
  --infrastructure-name 'Meine Infrastruktur' \
  --site-name 'Mein Standort' \
  --operator-name 'Lokaler Operator' --port 18885 --apply
```

Copy the actual principal_id and site_id from the JSON summary. They are not hardcoded defaults. Stop a running daemon before offline changes; ownership conflicts fail without applying a second writer.

```sh
python3 tests/oip0085/onboard.py add \
  --config /private/tmp/oip-personal/core.json --principal PRINCIPAL_ID \
  --site SITE_ID --name 'Mein Raspberry Pi' --type single_board_computer --apply
python3 tests/oip0085/onboard.py list \
  --config /private/tmp/oip-personal/core.json --principal PRINCIPAL_ID
python3 tests/oip0085/onboard.py show \
  --config /private/tmp/oip-personal/core.json --principal PRINCIPAL_ID --id DEVICE_ID
python3 tests/oip0085/onboard.py update \
  --config /private/tmp/oip-personal/core.json --principal PRINCIPAL_ID \
  --id DEVICE_ID --revision 1 --name 'Neuer Anzeigename' --apply
```

Add assigns a UUID if --id is absent. Its dry-run UUID is a proposal, not reserved: reuse it with --id when applying that proposal, or apply the exact normalized inner plan through Rust. Update reads the current authorized record, checks the supplied revision, merges only requested name/type/site/description/--metadata fields, and sends a complete replacement under CAS. Rename-only preserves manufacturer/IP/tags/notes and other metadata. No network request is inferred from hostname/IP. Site changes currently fail explicitly; physical_location may be updated using a metadata JSON patch. Archive is supported with --id/--revision/--apply; delete/restore are not.

```sh
# Standalone Rust interface; bounded, typed JSON file, dry-run unless apply is explicit:
target/debug/oip-server --config /private/tmp/oip-personal/core.json --inventory-plan plan.json
target/debug/oip-server --config /private/tmp/oip-personal/core.json --inventory-plan plan.json --inventory-apply
# Actual ongoing runtime, independent of clients:
target/debug/oip-server --daemon --config /private/tmp/oip-personal/core.json --ipc-config /private/tmp/oip-personal/ipc.json
```

The plan envelope is `{principal: PRINCIPAL_ID, changes:[{operation:register, device:{id:DEVICE_ID, display_name:NAME, device_type:server, site_id:SITE_ID, metadata:{}}}]}` with valid JSON quoting. Updates add expected_revision and require complete metadata; archive uses id/expected_revision. A separate `--inventory-query` file is `{principal:...,query:{id:...}}`. These are trusted local OS-operator requests, not remote identity assertions. Reads/dry-runs use read-only schema6; missing/older DBs require explicit initialization, never hidden migration. Active daemon ownership denies offline commands; use authorized REST/MCP for live reads.

## JSON/CSV import

JSON accepts a changes array or `{changes:[...]}`; CSV requires id,display_name,device_type,site_id and permits known metadata columns. Unknown/duplicate headers, malformed rows, duplicate IDs, invalid enums/parents, oversized files or conflicts fail. Tags use a JSON array inside the quoted CSV cell. No principal/source/credential columns are accepted. Reusing identical IDs/data is idempotent; different existing data requires explicit update, never overwrite.

```sh
python3 tests/oip0085/onboard.py import --config /private/tmp/oip-personal/core.json --principal PRINCIPAL_ID --file inventory.csv
python3 tests/oip0085/onboard.py import --config /private/tmp/oip-personal/core.json --principal PRINCIPAL_ID --file inventory.csv --apply
```

Example (replace SITE_ID with a genuinely authorized Site; fictional data only):

```csv
id,display_name,device_type,site_id,description
11111111-1111-4111-8111-111111111111,Example registered host,server,SITE_ID,Operator assertion without monitoring
```

Each apply validates the entire batch and commits inventory+audit atomically. No partial success or historical data deletion. `cleanup-plan` is Platform-privileged read-only classification, not removal; a normal Organization operator cannot inspect the whole installation. It performs no backup or migration and reports that explicitly.
