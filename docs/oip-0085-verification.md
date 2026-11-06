# OIP-008.5 — Real infrastructure and independent device inventory

2026-11-06–07. **OIP IS AGENT-FIRST BY DESIGN.** Local development acceptance; no production or OT release.

## Provenance and authority

Canonical `main` remains `0e20f7283a8815242aaa71a2066a9944cb8cafc8`. OIP-008.4 is not integrated: this feature is explicitly stacked on `f9969f0a21f2885a8b6c4695b3c105ad28708d33`, in `/Users/benny/Code/open-industrial-platform-worktrees/oip-0085`, branch `feature/oip-0085-real-infrastructure`. A later integration must include and verify that dependency. No merge, push, remote change or deployment occurs here.

The Core session owns only this feature worktree, its external backup/receipt and isolated test artifacts. Independent reviewers `/root/review_inventory_0085` and `/root/review_auth_0085` operated read-only. OpenCode's available active-session response was empty; that is not a global write lock. Known UI worktrees, previews and operator databases were inventoried and left untouched. No existing operator database was opened. All new process tests used private directories, their own databases and loopback ports. All owned test processes were stopped.

The external receipt is `/Users/benny/Documents/OIP-Handoffs/core-0085-real-inventory-20261106T200219Z/`. Its `preflight.json`, `inventory.json` and independently reread `baseline.tar` preserve all 400 parent tracked files. Baseline archive SHA-256: `009258976ddd4af6bec8043d61a21ce62678e180f6a7ad7194d9ae568cbe4f3d`. Protected actual OIP-008.4 server SHA-256: `73d70d8105914db20210c95268b5733ca2ec19c959c4c29fa57cb93c1935fe58`; binary-reported Git revision was checked against the parent and its earlier postcommit evidence. It is used only to create a real schema5 migration fixture.

This report is included in the feature commit. The actual commit/tree/status and final independently verified receipt hashes are recorded afterward in external `git-final.json` and `SHA256SUMS`; they do not require amending this report. The curated [test summary](evidence/oip0085/test-summary.json) describes precommit verification, and final Git/receipt acceptance is certified externally.

## Implemented behavior

Normal configuration now has zero sources, database `oip.sqlite` and no default webassets. It never starts a simulator, fabricates a hierarchy or falls back to demo. An actual empty runtime returns `No infrastructure configured`, empty devices/sources/observations/events, no simulated status or topology. After explicit provisioning it returns `No devices registered`; registered unmonitored devices return `Devices registered · Telemetry unavailable`. Explicit isolated demo/legacy tests remain supported and require an explicit database/configuration selection. Existing demo datasets are neither adopted nor deleted.

The typed registry separates Device identity and Site placement from an optional Source association. Manual registration needs only an ID, name, category and authorized Site. The helper assigns UUIDs when IDs are omitted. Optional metadata is bounded and validated; names/IPs are operator assertions and cause no network probes. A device named `AMD EVO-X2` was registered as manual evidence that names do not determine provenance. Source-derived legacy identities retain their exact IDs and source provenance; their unknown physical category is `Other`, and unknown original registration time/actor remain null.

Registration, update, archive and import are real offline operations under exclusive SQLite ownership and central `InventoryManage` policy. OS-owner authority is recorded separately from the selected on-behalf Principal. An arbitrary tool parameter cannot create this authority. The helper creates a private initial profile with generated hierarchy/principal/role IDs, an explicit Organization-scoped operator grant and protected credential files. It grants no Platform access. Local same-UID trust remains a documented limitation.

Updates use expected revisions. The Python operator helper reads the authorized record and merges supplied changes, preserving metadata on rename. Raw Update contracts require explicit complete metadata. Site/ownership moves are rejected; archive retains the row and all historical data and does not stop an associated collector. JSON/CSV imports validate the entire bounded batch, reject unknown fields/duplicate IDs/conflicts and apply atomically with audit. Reapplying identical registrations is idempotent. Rejected unknown credential fields are validated before normalized input is printed; a runtime random-sentinel test verifies no echo to stdout/stderr.

Device connectivity is **Unknown** without device-specific evidence, even when an associated OPC-UA endpoint works. No collector means `NoCollector`, no measurements, and `NotEvaluated` health. Source telemetry may be configured/receiving/stale only from actual Source state. `monitoring_simulated` is null when offline association provenance cannot establish it; an actual test simulator association is explicitly true. Source-only readers see only specifically associated devices, not other manual records in the same Site.

## Domain, persistence and parity

New modules: `oip-core/inventory.rs`, `oip-storage/inventory.rs`, `oip-server/inventory_services.rs`; existing ApplicationServices, runtime initialization, configuration, Settings infrastructure section and transport adapters were extended. The eight-crate workspace, Cargo manifests/lock and the existing MCP SDK remain unchanged. One CoreRuntime, one writer and existing source-worker/session ownership are retained.

Schema6 adds typed inventory persistence, bounded metadata, Site/Principal foreign keys, revisions, source-reference/immutable-ownership guards, a Site index and minimal value-free inventory audit. Migrations1–5 and their checksums remain unchanged. Source projections synchronize in the existing atomic provisioning transaction; projection errors roll back the whole operation. Old malformed/oversized source names fail migration atomically rather than being silently renamed. Reads and dry-runs never create or migrate a database. Explicit inventory initialization is a separately authorized operation. Offline commands fail while a daemon owns the database.

| Operation | Central Capability | REST v2 | MCP |
|---|---|---|---|
| Inventory query/detail/metadata/monitoring/associations | InventoryRead | GET `/api/v2/inventory/devices` | `oip_inventory_read` |
| Typed register/update/archive/import plan validation | InventoryPlanRead | POST `/api/v2/inventory/plan`, read-only | `oip_inventory_plan_read` |
| Atomic register/update/archive/import apply | InventoryChange, offline-only | unavailable | unavailable |
| Constant first-run status before hierarchy | existing inventory projection | GET `/api/v2/installation/status` | no anonymous profile created |

The full catalog now declares **30 contracts, 27 reads and three mutation contracts** (legacy simulation, offline SettingsChange, offline InventoryChange). **20 MCP read tools** are registered; each Principal discovers only permitted tools. Existing read roles gain no new write grants. Existing seven historical diagnostics reads and Settings remain available. The Settings profile in its inherited test discovers 19 tools, its scoped reader 18; a full inventory-management test operator can discover all20. No mutating MCP tool exists.

ApplicationServices is the common authorization and projection boundary for REST/MCP. Offline reads use the same inventory projection, and mutations use the common typed plan validator. Lists filter authorization before pagination. Unknown/foreign details use generic inaccessible errors without foreign names; successful detail/plan audit contains only authorized targets. Parent filters never expand scope. Installation status stops being publicly accessible after hierarchy provisioning. No browser-admin write or anonymous multi-tenant fallback was added.

## Newly executed verification

The parent OIP-008.4 suite contains144 workspace tests, above the earlier canonical135. This feature passes **155**: eight additional storage tests and three new inventory server tests; no existing tests were removed. Storage43 and OPC-UA groups overlap the workspace and are not added into a false unique total.

| Check | Result / external evidence |
|---|---|
| Rust fmt/check/clippy, warnings denied, workspace build/examples | PASS; `rust/results.json`, final check/clippy/build logs |
| Workspace | **155 PASS**, `workspace-final.log` |
| Storage incl. revision/audit/rollback/no-create/name-preservation | **43 PASS**, storage logs and workspace suite |
| OPC-UA both backends | **37 PASS**; open62541-only **2 PASS** |
| No-default/open-only/both-backend check and clippy | PASS, `rust/` logs |
| cargo-deny | PASS under unchanged three Advisory exceptions; not risk remediation |
| Inventory real-runtime E2E | PASS, `inventory-e2e-final-acceptance/report.json` |
| Real schema5→6 fixture | PASS, `migration/report.json` |
| Actual operator init/add/show/update workflow | PASS, `operator-workflow.json` |
| Prior multi-organization diagnostics/MCP/headless/migrations/legacy/performance | all PASS, `harness-results-final.json` and `regression-*` |
| Settings migration/reads/writes/revisions/8clients/restart/SIGKILL | PASS, `settings-e2e-final/report.json` |
| Flutter analyze/tests/external release build | 0 issues, **80 PASS**, `flutter-results.json` |
| Existing browser functional suite | **16 PASS**, `ui/ui-regression.json` |
| Spectrum interactions/themes/responsive captures | PASS, 30 new external captures on explicit isolated demo |
| Native macOS integration | **1 PASS**, `ui/` logs |

The inventory E2E starts truly empty, provisions two Organizations/multiple Infrastructures/Sites without Sources, registers the first device, compares REST with a real official-SDK MCP client, then verifies full restart with the same ID, Unknown connectivity and NoCollector. It tests multiple types/Sites, CSV dry-run/apply/idempotence, rejected foreign mutations, whole-batch rollback, CAS, metadata-preserving rename, archive, scoped lists, eight parallel clients, forged inputs, abrupt bridge loss, continued core availability, Settings persistence, orderly restart, actual SIGKILL, FKs and SQLite integrity. No fabricated events/observations appear in the unmonitored installation.

A **separate** database tests real OPC-UA simulator reception and association to an existing manual device while preserving its ID/metadata/origin. Only actual received samples change telemetry to Receiving. A second same-Site manual device remains invisible to the source-only reader. The normal onboarding database still contains zero Sources. These test samples are labelled simulation and are never adopted into the operator's new inventory.

The genuine parent schema5 fixture preserves two Organizations, three Infrastructures, four Sites/Sources, seven Principals/bindings, Settings/audit and all historical payloads/IDs. The captured fixture had30 observations,41 events,4gaps and28 health transitions. Source-origin projection, unchanged migration ledger entries1–5, new6, re-open/idempotence, dry-run byte identity, FKs/integrity all pass. Previous schema2/3/4 migrations are rerun using protected real baseline binaries. Failed migration/new-source projection tests prove atomic rollback.

Development failures were investigated and retained externally, not hidden: the first inherited Settings E2E expected19 globally registered tools, while the two new inventory tools make20. Its per-Principal expectations were updated to actual19/18 and the entire Settings E2E passed. No feature was weakened or test removed to achieve counts. Earlier intermediate test/build logs remain alongside final successful results.

## Performance, reviews and security

Inventory is deliberately bounded:2048 installation records,100 plan actions,100 maximum page size, bounded metadata/search and inherited request/output/session limits. Records are loaded at startup and offline changes require restart; there is no database-wide polling loop or second writer. Existing 100,000-event query-plan/REST/MCP performance harnesses passed with ongoing ingestion. Settings benchmark25 samples/query reports REST/MCP p95: catalog3.02/3.06ms, effective1.79/4.81ms, MCP status3.77/2.81ms. Six offline saves p95 49.08ms include process startup/ownership/CAS/audit. One process sample was33,968KiB RSS/8.5%CPU, with observations74→93 during reads. These are short local measurements, not a throughput/enterprise/SLA claim; inventory-specific long-duration stress was not run.

Both independent read-only reviewers inspected concrete code and parent-produced evidence. They did not independently rerun tests. Fixed findings include hidden migration in dry-run, fabricated legacy physical type, name-preservation/atomic failure, conflict-specific source sync, raw update metadata omission, unvalidated helper echo, audit target leakage and offline unknown simulation provenance. Final follow-up on the helper/sentinel E2E found zero open blockers; [source-bound review summary](evidence/oip0085/reviews.json).

Gitleaks8.30.1 scans the full candidate source tree without disabling rules. The27 findings are exactly the prior unchanged-file/line/rule false positives: source SHA-256 manifests and deterministic simulated gap content hashes. No unresolved secret. Final scan and reviewed classifications are external, with curated [security summary](evidence/oip0085/security.json). No runtime credential/DB/raw capture enters Git. Cleanup assessment is read-only, preserves every row and states backup is not performed; it has no deletion/apply path. Unknown/real data cannot be automatically removed.

Open production blockers remain **RUSTSEC-2023-0071, RUSTSEC-2023-0089, RUSTSEC-2024-0449**; productive remote/browser identity, hostile same-UID isolation, tamper-proof durable audit and industrial endurance/OT safety are not complete. No production connection, host probe, SSH login, public listener or cloud service was introduced.

## Isolation, limits and operator handoff

83 tracked Flutter files are byteidentical to the parent. Design reference SHA-256 remains `bd9f9d8696ed48676055ee9a2cd0afb29e6c3d59e0945e662d925306f73c753e`. Cargo.lock and all workspace members remain unchanged. Existing OPC-UA/Network/Diagnostics/Overview/Devices UI handoffs and previews stay separate; Flutter builds/captures use external output. A verified feature source archive, local Git bundle and final receipt manifest preserve reproducibility without integrating into main.

The [real-inventory Flutter contract](architecture/oip-0085-real-inventory-flutter-contract.md) defines first-run, Devices, Overview, Network, Diagnostics and Settings empty/status/scope behavior. Current Flutter has no secure real browser onboarding; the tested legacy demo remains explicit. No frontend change or security bypass is claimed.

Unsupported: device Site/ownership moves, permanent deletion/restore, automatic cleanup, live source reconfiguration, multiple collector associations per device, secure browser administration, remote MCP, session disconnect administration, retention cleanup, SNMP/SSH/host agent/OS/VPN/MQTT/Modbus collectors and network discovery. Existing OPC-UA remains the available adapter, tested only against owned local simulators.

## Reproduce

Use the feature worktree; never point example commands at an existing operator database. Exact first-device/init/add/list/show/update/import/start instructions are in the [operator guide](architecture/oip-0085-operator-onboarding.md). Minimal actual workflow:

```sh
cd /Users/benny/Code/open-industrial-platform-worktrees/oip-0085
cargo build --locked --workspace
python3 tests/oip0085/onboard.py init --directory /private/tmp/NEW-oip-instance --organization-name 'Meine Organisation' --infrastructure-name 'Meine Infrastruktur' --site-name 'Mein Standort' --operator-name 'Lokaler Operator' --port 18885 --apply
# Use the actual generated principal_id and site_id from init:
python3 tests/oip0085/onboard.py add --config /private/tmp/NEW-oip-instance/core.json --principal PRINCIPAL_ID --site SITE_ID --name 'Mein Raspberry Pi' --type single_board_computer --apply
python3 tests/oip0085/onboard.py list --config /private/tmp/NEW-oip-instance/core.json --principal PRINCIPAL_ID
target/debug/oip-server --daemon --config /private/tmp/NEW-oip-instance/core.json --ipc-config /private/tmp/NEW-oip-instance/ipc.json
```

No collector is required. Stop that owned daemon before offline changes. A bridge uses the generated protected profile and actual credential file path; config preview creates no grants. Generic MCP bridge invocation: `oip-server --mcp-bridge --ipc-socket SOCKET --ipc-credential CREDENTIAL_FILE`.

```sh
cargo fmt --all -- --check
cargo check --locked --workspace --all-targets
cargo clippy --locked --workspace --all-targets -- -D warnings
cargo test --locked --workspace -- --test-threads=1
cargo test --locked -p oip-opcua --features open62541-backend -- --test-threads=1
cargo test --locked -p oip-opcua --no-default-features --features open62541-backend -- --test-threads=1
target/oip-002-tools/bin/cargo-deny check advisories licenses bans sources
OIP_EVIDENCE_DIR=/private/tmp/NEW-oip0085-evidence python3 tests/oip0085/acceptance.py
OIP_EVIDENCE_DIR=/private/tmp/NEW-oip0085-migration OIP0084_BASELINE_BINARY=/Users/benny/Documents/OIP-Handoffs/core-0085-real-inventory-20261106T200219Z/oip0084-baseline-server OIP0084_BASELINE_SHA256=73d70d8105914db20210c95268b5733ca2ec19c959c4c29fa57cb93c1935fe58 python3 tests/oip0085/migration.py
```

The external receipt records exact inherited harness invocations, protected older binaries, Flutter commands and environment. Use a fresh external output directory and own ports for every repeat. Do not substitute the new binary for a legacy binary. The acceptance/migration scripts take the shown environment variables, not command-line flags; only the onboarding helper has an argparse `--help`. Build `cargo build --locked -p oip-server --examples` first for the real SDK probe. These host-local harnesses use the existing current SQLite CLI at `/opt/homebrew/opt/sqlite/bin/sqlite3`.

Acceptance G1–G17 is demonstrated by the linked summaries and external evidence. G18 is completed only by the real local feature commit and independently reread receipt manifest, recorded in external `git-final.json`/`manifest-verification.json`. The next step is separate canonical integration of OIP-008.4 plus this stacked feature, followed by secured browser/onboarding integration; neither is performed here.
