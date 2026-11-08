# Real device onboarding — verification and handoff

Baseline: `49a86bb0aa9f737fe9392eb2b5421e1ffe2f8c68`.
Core: `feature/real-device-connection-core`, isolated `real-device-core` worktree.
Flutter: `feature/real-device-connection-ui`, isolated `real-device-ui` worktree.
Canonical main, existing real installation and foreign UI workstreams are unchanged. No push, merge, deployment or service installation.

## Meaning of the result

Inventory registration is not a connection. This change adds an actual authenticated Flutter/HTTP/Core/OpenSSH workflow, explicit public-host-key trust, operator confirmation of measured identity, one writer-owned persistent binding and separate optional monitoring activation. It does not install remote software or add mutating MCP tools.

The private Raspberry Pi has **not** been contacted. Its endpoint, SSH user and approved local identity have not been supplied. The existing real UUID `ca9b19c0-7b97-4867-9ad9-920e9f575778` remains unchanged at revision1, without a collector. Owned loopback OpenSSH acceptance reads actual local macOS host facts; these facts are not presented as Raspberry-Pi measurements. Physical Linux/Raspberry-Pi acceptance and final live installation cutover remain pending.

Receipt: `/Users/benny/Documents/OIP-Handoffs/core-real-onboarding-p0-20261107T025455Z/` (private). Raw development failures are preserved there; only the final test manifest identifies accepted runs. Test private keys/credentials remain in private isolated test directories and are not committed or included in the receipt. The consistent real-before SQLite backup is private and never used as an active runtime.

## Architecture and compatibility

- Core adds typed device-connection contracts, two central Capabilities, trusted profile configuration, a bounded connection-plan service, a read-only system-OpenSSH adapter, owned collector tasks and a browser-session boundary.
- SQLite7 adds connection bindings, latest attempts and transactional connection audit. Migrations1–6 and historical identifiers remain unchanged. Online registration/confirmation/control use the existing writer queue, not another SqliteStore.
- Shared registry snapshots refresh from committed storage. Existing devices retain their UUID, metadata and placement; CAS rejects conflicting revisions. Prospective hierarchy validation preserves the existing total32-source limit.
-32 capability contracts:28 reads,4 mutations. Up to21 policy-filtered MCP read tools. `oip_device_connection_read` is the only new MCP tool; configuration and inventory mutations remain blocked via MCP.
- REST adds `/api/v2/browser/session`, `/browser/login`, `/device-connections`, and `/inventory/apply`. Central services own authorization; the adapter cannot supply a Principal, grants, private-key path or fabricated facts.
- Flutter adds local operator login, Add Device, an inventory-only path, existing-device connection setup, five explicit phases and an inspector with actual endpoint/identity/attempts/measurements. The OIP-009 context seam invalidates caches/dialogs on Principal or scope changes, without adding a competing global switcher.

## Tests

Current accepted runs: **167 workspace tests, including44 Storage tests;37 OPC-UA both-backend tests plus2 overlapping open62541-only tests;84 Flutter tests;16 legacy browser checks;4 theme/interaction checks;30 responsive captures**. Do not add overlapping groups. Format/check/clippy (warnings denied), analyze, both web release builds, cargo-deny and the profile-helper test pass. The actual SSH/Flutter/REST/MCP E2E, inventory E2E, settings E2E and four-source diagnostics E2E pass. Local SSH read MCP p50/p95:3.518/3.877ms,20 sequential samples with8 clients attached; a single Core resource sample was25,696KiB RSS/16.3% CPU. Ingestion advanced140→150 observations after browser/MCP clients closed. These short local measurements are not an SLA or hardware endurance evidence.

Native macOS was **attempted but blocked before compilation**: the owned Xcode SwiftBuild service remained in toolchain discovery (`QNXSDP.findInstallations → LocalFS.listdir → __getattrlist`) with no build products. Two process samples are preserved; the owned attempt was interrupted. No native PASS is claimed. Flutter returned zero after interruption without running the test, so the raw orchestrator exit-code report is corrected by a hash-bound receipt; the harness now also requires a positive test-completion marker and bounds each owned test process group. One owned SwiftBuild process and its diagnostic lsof reads were observed stuck in uninterruptible filesystem calls; termination signals were sent, and residual OS state is recorded rather than claimed clean. No system directory, HOME environment or foreign service was changed. The [upstream SwiftBuild implementation](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBQNXPlatform/QNXSDP.swift) supports the diagnosis as an inference, not proof of the installed binary's exact source revision.

The legacy visual performance report had a historical hardcoded “CanvasKit” method label although the controlled harness served HTML. The raw report is retained, with a hash-bound renderer correction; the test source now records the served Flutter build configuration. The real SSH onboarding run used CanvasKit and checked the loaded main.dart.js SHA.

Final machine-readable test results and exact source/build hashes are recorded in the external receipt. Development runs that failed remain distinguishable from final runs.

- Workspace, format/check/clippy, storage/migration/authorization/IPC/MCP and OPC-UA backend checks are rerun.
- Flutter analyze, full widget suite, CanvasKit and HTML web builds are rerun. The real SSH onboarding browser test uses CanvasKit and verifies the actually served main.dart.js hash. Legacy browser regression uses a separately built HTML renderer; visible-text filters disambiguate painted paragraphs from accessibility proxies. This renderer distinction is explicit, not a claim of identical browser assets.
- Real multi-organization inventory, settings and historical diagnostics harnesses run against the candidate binary with isolated DBs/ports. Historical protected baseline binaries are hash-checked before migration; no new binary is represented as a legacy binary.
- The real SSH/browser harness covers unknown-key consent, failed endpoints/authentication, plan cancellation, identity confirmation, same-ID preservation, writer-owned registration, CAS, owner-bound collector enablement, scope denials, CSRF/Origin, cookie revocation during SSE, fresh measurements, stale restart, actual SIGKILL recovery, eight official SDK clients, client abort, continued ingestion without clients, changed-host-key rejection and SQLite integrity/duplicate keys.
- An offline helper test covers dry run, exclusive ownership denial, unsafe file permissions, atomic apply/backup and no-overwrite behavior. A widget unit fixture verifies entered registration data and mandatory consent; it is not substituted for the real browser test.

## Security review passes

Both passes below were performed by the implementing session. **No independent reviewer is claimed.**

A — Storage/runtime/data integrity: inspected connection transactions, deferred FK validation, inventory/connection CAS, writer ownership, startup definition union, per-device task replacement/cancellation and stale restore. Findings fixed: prospective source-capacity validation before SQL; source-specific poll freshness applied to both samples and source health; bounded cleanup of flooded OPC-UA callbacks; task Drop guards and joined shutdown. Positive/negative capacity controls, cadence/restore and reliability tests cover these fixes.

B — Browser/SSH/authorization: inspected trusted Principal binding, exact Origin/CSRF checks, cookie/session expiry, SSE revalidation, profile visibility/path validation, host-key trust and pinning, subprocess limits, credential reuse and MCP mutation denial. Findings fixed: repeated local identity-reference validation with ownership/symlink/mode checks; only the verified Principal can re-enable that credential-backed collector; UID0/unverifiable remote users are rejected before fact queries; unsafe filesystem userinfo is redacted; oversized output and missing metrics fail honestly. Core unit fixtures and real loopback denials cover these boundaries.

No private keys, long-term credentials or token-bearing URLs/assets/browser storage are introduced. Local loopback HTTP cookies are host-scoped rather than port-isolated. Hostile same-UID processes, remote/browser production identity, tamper-proof audit and OT/endurance certification remain unresolved. RUSTSEC-2023-0071, RUSTSEC-2023-0089 and RUSTSEC-2024-0449 remain documented; no exception was added to suppress them.

## Reproduction

Run commands from the corresponding worktree; use a separate build target so the canonical binary is not replaced:

```sh
export CARGO_TARGET_DIR=/Users/benny/Code/open-industrial-platform/target/real-device-core
export CARGO_BUILD_JOBS=2 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0
cargo fmt --all -- --check
cargo check --locked --workspace --all-targets
cargo clippy --locked --workspace --all-targets -- -D warnings
cargo test --locked --workspace -- --test-threads=1
cargo test --locked -p oip-opcua --features open62541-backend -- --test-threads=1
cargo test --locked -p oip-opcua --no-default-features --features open62541-backend -- --test-threads=1
cargo build --locked -p oip-server --bin oip-server --example mcp_probe
python3 tests/real_device/profile_helper_test.py
```

Flutter worktree:

```sh
flutter analyze
flutter test
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
flutter build web --release --web-renderer html --no-web-resources-cdn --pwa-strategy=none --output build/web-html
```

Actual local SSH/Flutter acceptance, from the Core worktree (new private output directory):

```sh
OIP_EVIDENCE_DIR=/absolute/private/new-test-receipt \
OIP_SERVER_BIN="$CARGO_TARGET_DIR/debug/oip-server" \
OIP_WEB_DIR=/Users/benny/Code/open-industrial-platform-worktrees/real-device-ui/apps/flutter/build/web \
OIP_BROWSER_SCRIPT=/Users/benny/Code/open-industrial-platform-worktrees/real-device-ui/apps/flutter/test/browser_onboarding.mjs \
PLAYWRIGHT_MODULE=/Users/benny/Code/open-industrial-platform/apps/flutter/test/node_modules/playwright/index.mjs \
python3 tests/real_device/acceptance.py
```

This starts only an owned loopback SSH fixture, a candidate daemon and official SDK bridge clients. It never reads the private Raspberry-Pi endpoint. Fixture keys are generated for this test and kept outside source/receipt. The test stops its own processes.

## Operator completion

After separately controlled integration/runtime activation, stop the Core cleanly, back up the real SQLite/config/profile, and configure an explicitly approved SSH profile using `tools/configure_ssh_profile.py` (dry run first). The helper neither connects nor grants permissions. Use the existing authorized Principal and existing private IPC profile. Start exactly one candidate daemon with the selected web build, issue a one-use login code using `--browser-login`, then select the existing Raspberry-Pi UUID and choose **Verbindung für dieses Gerät einrichten**. Verify the public host-key fingerprint independently, compare actual host identity and confirm. Enable monitoring separately only after identity confirmation. Never run offline SQLite administration beside the daemon.

See `docs/architecture/real-device-onboarding.md` and the Flutter worktree's `docs/architecture/real-device-onboarding-flutter-contract.md`. SNMP, Windows/Android agents, VPN telemetry, scans and remote installation remain unsupported. Native authenticated browser-cookie transport is not claimed; native compatibility is tested only in explicit isolated legacy-demo mode.

## Addendum — canonical integration into `main`

The feature above was integrated into the canonical branch on 2026-11-07 as a real `git merge --ff-only feature/real-device-onboarding-integration`: `main` moved from `49a86bb0aa9f737fe9392eb2b5421e1ffe2f8c68` to `ae4c6bab4fb87ff2c7b15a21b0104b2d5a12af7f`, tree `f72cb667c16b6e6a75efd72b725c81031788fd26`, 438 tracked files. No merge commit, no history rewrite, no push and no deployment were produced. The canonical tree is byte-identical to the reviewed candidate, so every statement above remains valid for canonical `main`; the sections above are not rewritten.

The merged tree was re-proved on the canonical branch: format, check, clippy with denied warnings, 167 workspace tests, both OPC-UA backend configurations, the dependency policy check, the server and official MCP probe build, Flutter analysis, 84 Flutter tests, both web release renderers and the actual SSH/browser/MCP acceptance harness with seven passing phases including the real Flutter onboarding run. The machine-readable result is `docs/evidence/oip-real-device/test-summary.json`; the run-by-run state and the open items are in `docs/OIP_RELEASE_PROGRESS.md`.

An additional read-only source review against this contract is recorded in `docs/evidence/oip-real-device/review.json`. It is an automated review pass and not an independent human review. It found seven conformance gaps (F1-F7) and one missing Rust-level test group (R1); none of them is fixed in this integration. They are the first open item in `docs/OIP_RELEASE_PROGRESS.md`.

Nothing in this addendum changes the acceptance boundaries above: the private Raspberry Pi was not contacted, the real installation was not activated, the personal SQLite database is unchanged at schema 6, the native macOS build is still not proved and the productive identity, hostile same-UID, durable audit and OT boundaries stay open.

## Addendum — conformance fixes after the canonical integration

An automated read-only source review against `docs/architecture/real-device-onboarding.md` found seven conformance gaps in the integrated feature and one missing Rust test group. Six of the eight were fixed in the isolated branch `feature/oip-real-device-conformance` and integrated into canonical `main` with a real `git merge --ff-only` as `fc828ac4a0afd2020fef646b4630eb0ab90f99cc`, tree `2c7e72bd0882ab9fa4324216183c628600fa64dc`.

- The server now reads the size of every offered host key itself and rejects a key below the accepted minimum before it is offered for acceptance or pinned. The attempt fails with the typed fault `SSH_HOST_KEY_TOO_WEAK` and creates no binding. The `RequiredRSASize=2048` client option stays as defence in depth.
- A changed host key and an unknown host key are separate outcomes. Only `REMOTE HOST IDENTIFICATION HAS CHANGED` maps to `SSH_HOST_KEY_CHANGED`; an unpinned host reports `SSH_HOST_KEY_UNKNOWN` and the operator status `host_key_unknown`. The split was verified against the installed OpenSSH 10.2 with an owned loopback fixture: a changed key produces the rotation banner, a host without a pinned entry does not.
- Rejected pairing codes no longer block a valid single-use grant, the rejection accounting stays capped, and a full session table no longer consumes an issued grant.
- The private SSH work directory is created with the owner-only mode instead of being briefly world readable.
- `crates/oip-server/tests/browser_session.rs` adds five Rust integration tests for the exact Origin, the single-use pairing code, the CSRF requirement on every cookie authorized write, a revoked session and a revoked projection stream. The browser session boundary is therefore covered inside the repository and not only by the external harness.
- The owned loopback fixture can serve a deliberately weak 1024 bit RSA host key, and the acceptance harness proves that the server rejects it end to end.

Verified on the canonical tree after the integration: format, check, clippy with denied warnings, **175** workspace tests, both OPC-UA backend configurations, the dependency policy check, the server and official MCP probe build, Flutter analysis, **84** Flutter tests, both web release renderers and the acceptance harness with **eight** passing phases including the new weak host key rejection. The machine-readable result is `docs/evidence/oip-real-device/test-summary.json`.

The remaining findings F4 (the maximal host report the parser can build exceeds the stored payload bound) and F5 (the plan read path requires the configure capability while the contract lists it under the read capability) are deliberately not mixed into this fix, because both change a rule instead of enforcing the existing one. They are tracked as N1b in `docs/OIP_RELEASE_PROGRESS.md`.

The review itself was an automated pass, not an independent human reviewer, and the fixes were implemented and verified by the implementing session.

## Addendum — native macOS build and test

The P0 handoff recorded the native macOS build as blocked inside SwiftBuild toolchain discovery and explicitly withheld a native verdict. That item is now closed by a real result.

The toolchain was inspected first and is healthy: Xcode 26.6 at `/Applications/Xcode.app/Contents/Developer`, Swift 6.3.3, Flutter 3.22.0, CocoaPods 1.15.2, and `flutter devices` lists the macOS desktop device in 7 s. A cold `flutter build macos --debug` succeeds in 497.2 s and produces `build/macos/Build/Products/Debug/oip_dashboard.app`.

The cause of the previous "blocker" was two bounds that were too short for a cold native build on this shared machine, not a missing capability: the UI regression harness applied one 300 second bound to the web steps and to the native step, and the native test ran its build inside the test command where the default twelve minute test timeout expired during the load phase. The harness now runs the native build as its own step with its own bound and a positive build marker, runs the native integration test with an explicit `--timeout 30m` and its own bound, records the elapsed seconds and the marker of every step, and never accepts a step without its marker. The legacy web regression additionally receives the separately built HTML renderer, because it reads the rendered text from the document while the CanvasKit build paints it on a canvas.

Measured on canonical `main` (`b19092d`), against an owned demo core on a random loopback port: browser 88.1 s, interactions 47.9 s, visual 60.4 s, native build 12.7 s with the `Built build/macos/Build/Products/Debug/oip_dashboard.app` marker, native integration test 34.4 s with the `All tests passed!` marker, demo core shutdown exit 0.

The native result stays inside the boundary of this document: it is a compatibility and regression check in the explicit isolated demo mode. Native authenticated session-cookie transport is still not claimed, the private Raspberry Pi was not contacted, the real installation was not activated and the personal SQLite database is unchanged at schema 6.

## Addendum — the verified host report is bounded to the stored record size

The stored connection record is limited to 128 KiB, but the SSH parser bounded the disk name and the interface addresses only by the subprocess output. A legal but extreme remote report could therefore reach the writer and fail the commit with an opaque storage rollback instead of an explicit fault, and the plan reported a generic error.

The parser now charges every collected disk name, mount, interface name and address against a report budget and refuses an oversized report with the existing typed fault `SSH_OUTPUT_LIMIT`; a single disk name is bounded to 256 characters and an address to 128 characters. Before the write, the server serialises the record and compares it with the bound that the domain crate and the storage schema share; a record that cannot be stored is refused with the typed fault `SSH_REPORT_TOO_LARGE`, the plan fails with that fault and no partial binding is created. The storage schema keeps its limit, and a test proves that the schema limit and the shared domain constant are the same value.

Five new tests cover the behaviour: an extreme report is refused with `SSH_OUTPUT_LIMIT`, a realistic maximal report stays inside the stored bound, an oversized disk name is bounded, a record that cannot be stored is refused before any write, and the schema limit equals the shared constant.

Verified on canonical `main` (`5a48b0c`): format, check, clippy with denied warnings, **180** workspace tests, both OPC-UA backend configurations, the dependency policy check, the server and official MCP probe build, Flutter analysis, **84** Flutter tests and the acceptance harness with **eight** passing phases, including the actual Flutter onboarding and the weak host key rejection.

One honest observation: during the first canonical OPC-UA run the timing-sensitive test `async_opcua::client::tests::reconnect_recreates_subscription_and_reports_gap` failed once under machine load. It then passed in three consecutive isolated runs and in the repeated complete suite (37 passed, 0 failed). The change touches no OPC-UA code, and the observation is recorded rather than hidden.

The review finding F5 remains open and deliberately paused: it would loosen a permission, which is a security decision rather than a conformance fix, and it is not taken without an explicit release. The physical Raspberry Pi acceptance and the controlled activation of the real installation remain outstanding, and the personal SQLite database is unchanged at schema 6.

## Addendum — the milestone acceptance gates on the canonical tree

The milestone acceptance harnesses had not been re-run after the real device onboarding integration, and two of them had silently gone stale: the schema3 migration harness still expected the upgraded schema to be 6 instead of 7, and the OIP-008 acceptance harness still expected exactly 17 MCP read tools for the reader role instead of 18, because the device connection read tool is visible to that role as well. Both gates failed on the canonical tree until the expectations were corrected to the measured reality; the gates stay exact.

`tests/canonical_regression.py` now runs the milestone harnesses over the canonical tree with one reproducible entry point. Every case owns its own runtime directory, ports and credentials. A case that needs a protected historical binary is only executed when that binary exists and its hash matches the recorded value; otherwise it is reported as BLOCKED with the reason instead of being run with a substitute.

Measured on canonical `main` (`111dff1`): OIP-008 acceptance PASS, OIP-008.2 acceptance PASS, OIP-008.2 schema3 migration PASS, OIP-008.4 acceptance PASS, OIP-008.5 acceptance PASS, OIP-008.5 migration PASS and the UI regression PASS with its browser, interaction, visual, native build and native test steps. The schema2 adoption case is BLOCKED because the workspace holds no protected OIP-007 binary; that migration was verified historically in the OIP-008 receipt and is not claimed as re-verified here.

The product source is unchanged in this iteration, so the Rust, Flutter and real device acceptance results of the previous iteration remain valid for this tree.

## Addendum — the monitoring measurements in the operator panel

The Core collected the host report of a connected device and published the resulting observations in the connection view, and the Flutter client parsed them, but the device connection panel rendered only the empty case and dropped every real measurement. The surface dedicated to connection and monitoring therefore showed the state `Collecting` but never a collected value, although the Flutter contract requires the connection view to contain the current authorized observations and requires the browser E2E to verify subsequent actual observations.

The panel now renders the current authorized observations with their metric identifier, value, unit, quality, freshness and capture time. Long text reports stay collapsed behind an expansion and are never presented as a complete value in the preview; a missing value stays unknown and is not replaced by a substitute.

Measured on canonical `main` (`e12c009`): `flutter analyze` exits 0 with no issue, `flutter test` passes 89 tests, the real device harness passes all eight phases and the canonical regression passes all eight cases with no failed and no blocked case. The browser receipt names the ten observations that the Core received from the owned loopback fixture and that the operator now sees in the panel — `host.architecture`, `host.cpu_info`, `host.disks`, `host.hostname`, `host.interfaces`, `host.memory_total_bytes`, `host.memory_used_bytes`, `host.model`, `host.os`, `host.uptime_seconds` — with `host.os` = `Darwin` and `host.memory_total_bytes` = 17179869184, all `fresh`. The browser E2E compares the rendered panel with the observations that the Core reports for the same device, so a rendered measurement is never a value invented in the test.

The harness defect found on the way: the browser script imports the Playwright module with a dynamic import, and a relative specifier is resolved as a package name by Node, so the relative value documented in the progress file failed with `Cannot find package 'apps'` and the browser phase could not run. The harness now resolves the module against the repository root, hands an absolute path to the browser script and reports a missing module before the browser phase.

These values are the host report of the owned loopback fixture on this machine. No physical Raspberry-Pi was contacted, the real installation was not activated and the personal database is unchanged at schema 6. The persisted observation history is connected in iteration 9; it was the next READY item of the previous iteration.

## Addendum — the persisted observation history in the device view

The Core already stored the samples of a connected device and served them through `GET /api/v2/observations/history`. The Flutter client named the gap itself: the device dialog stated that the authorized historical REST v2 queries exist in the Core, and the history was never requested. The device scope was already sufficient, because the device is resolved to its source through the authoritative source registration; no organization, infrastructure or site selection had to be invented.

The device view now requests the history for the device itself. Every row is named as history, reports the stored value, its unit, the quality, the freshness and the receive time the Core guarantees, and the `missing_evidence` and the time semantics of the answer are shown instead of being hidden. The stable id of a sample deduplicates a refresh, the cursor that the Core hands out walks forward to the newer entries, and the surface states that there is no total.

The browser session cookie authorizes this route, and that boundary was proven only with a bearer token. The new test in `crates/oip-server/tests/browser_session.rs` proves it with the cookie: the bound device is served with its persisted sample, a foreign scope and an unknown device are refused with `RESOURCE_NOT_ACCESSIBLE`, a principal without `telemetry_read` is refused with `PERMISSION_DENIED`, a request without a session is refused and an unbounded page is refused with `INVALID_DIAGNOSTIC_QUERY`. No permission rule, contract rule, storage layout or server behaviour is changed.

The defect found on the way: the history was loaded once, when the device dialog was opened, and the dialog is opened before the connection is confirmed. The answer of a device without a source is `RESOURCE_NOT_ACCESSIBLE`, so the section kept that answer forever and never showed the samples the collector stored a moment later. The section now follows the persisted state on a bounded cadence, exactly like the connection panel follows the live observations, and the recovery is proven by a widget test.

Measured on canonical `main` (`1287e23`): `cargo fmt`, `cargo check` and `cargo clippy` exit 0, the Rust workspace passes 181 tests, `flutter analyze` exits 0 with no issue, `flutter test` passes 97 tests, the real device harness passes all eight phases and the canonical regression passes all eight cases with no failed and no blocked case. The browser receipt names the persisted samples that the Core stored for the connected device and that the operator now sees as history — ten persisted samples, all `stale`, with the receive time of the first sample `2026-11-07 21:21:11.293 UTC`.

These samples are the host report of the owned loopback fixture on this machine. No physical Raspberry-Pi was contacted, the real installation was not activated and the personal database is unchanged at schema 6. The event history and the diagnostics surfaces stay unconnected, because `events_read` is not proven for every operator principal.

## Addendum — the managed overview shows the real authorized infrastructure

The Core delivers the authorized source registry, the authorized placement and the authorized observations in the scoped projection. The client dropped all of it: the overview asked for the temperature of the demo entity `M-01` and the metric `temperature`, the trend accumulator accepted only that pair, and the chart drew the caption *Temperatur · M-01*. In the managed mode the measured series was therefore always empty, the tile showed `—`, and the ribbon showed three rows for dimensions the projection does not carry. The contract had already named the rule: *"Overview: counts from authorized returned inventory, sources from actual source registry; no fake host CPU/RAM/network metrics"*.

The managed overview now draws the session's scope and nothing else. The source registry is shown with the health the Core measured, the placement of the source in the authorized hierarchy and the measured values. The measured series are taken from the authorized observations, one series per authorized source, so no source and no fallback primary is preferred and no global selection payload is invented. The metric of a series is named in the chart and in the source card, and the rule that picks it is deterministic.

The accumulator rules of the demo stay unchanged: a change of the measured scope and a source time that moves backwards start a new display window, an identical source time and value is not appended twice, and a series keeps at most 60 received points. The gap limit of a measured series now follows the cadence the series itself showed, with the demo limit as its floor, so a real source that publishes every 30 seconds is not broken at every point while the demo behaviour stays exactly as it was.

The status vocabulary of the source registry had no label and no colour: `disconnected`, `healthy`, `valid` and `invalid` were rendered as raw English strings. They are mapped now.

Measured on canonical `main` (`1e6b743`): `flutter analyze` exits 0 with no issue, `flutter test` passes 100 tests, the real device harness passes all eight phases and the canonical regression passes all eight cases with no failed and no blocked case. The browser receipt names what the operator now sees on the landing page of the managed mode: the authorized source `SSH host browser-existing`, the source registry section, the measured metric `host.memory_total_bytes` with the value 17179869184, and no demo coordinate.

No Rust source changed in this iteration, so the Rust workspace results of iteration 9 remain valid for this tree. No physical Raspberry-Pi was contacted, the real installation was not activated and the personal database is unchanged at schema 6. The network view still shows its loading message; it is recorded as the next READY item.

## Addendum — the managed network view shows the authorized placement

The network view showed *"Topologie wird geladen — Der Live-Stream liefert das gemeinsame Rust-Modell"* whenever the projection carried no topology. The scoped projection of a managed session has no topology array at all, so that was a loading state without a loader: it promised data that never arrives. The view also drew the three zones of the legacy demo — `LAN`, `Tailnet`, `Remote Site` — next to the real site of the session.

The managed network view now states the fact, draws no path and colours no reachability green. The zone of a node is the authorized site of the session, and the authorized placement is shown with the identifiers the Core delivered for it: organization, infrastructure, site and source, with the registered nodes of that site. Nothing is derived from a name, an address or a device identifier, and no link between two placements is invented.

Measured on canonical `main` (`e9036ef`): `flutter analyze` exits 0 with no issue, `flutter test` passes 101 tests, the real device harness passes all eight phases and the canonical regression passes all eight cases with no failed and no blocked case. The browser receipt names the placement the Core delivered — `org-a · infra-a1 · site-a1` with the source of the connected device — and records that the loading state and the demo zones are gone.

No Rust source changed in this iteration, so the Rust workspace results of iteration 9 remain valid for this tree. No physical Raspberry-Pi was contacted, the real installation was not activated and the personal database is unchanged at schema 6. The managed diagnostics view still shows its placeholder; it is recorded as the next READY item.

## Addendum — the schema2 adoption case and the parity gate

The schema2 adoption of the OIP-008 milestone could not be re-verified because the historical protected binary of that milestone is not part of the workspace any more. `tests/oip007_baseline.py` rebuilds that writer from the verified OIP-007 baseline commit `a27e7b1`; it extracts the source with `git archive`, so no worktree registration and no canonical checkout state is touched. The result records the source commit, the hash of the rebuild and the hash of the historical binary, and it states that a rebuild is not byte identical, so the identity of the historical protected binary is not claimed.

In the first canonical run of this iteration the OIP-008 acceptance case failed although it had passed with identical code before. The gate itself compared the live source state of the MCP transport with the live source state of the REST transport; while a source is still warming up, the two reads can observe two different states. The gate now waits for the compared fields to converge within a bounded deadline and still fails when they never agree.

Measured on canonical `main` (`f4b89ed`): all eight milestone acceptance cases pass with no failed and no blocked case — OIP-008 acceptance, OIP-008.2 acceptance, OIP-008.2 schema3 migration, OIP-008.4 acceptance, OIP-008.5 acceptance, OIP-008.5 migration, the UI regression with its browser, interaction, visual, native build and native test steps, and the schema2 adoption with 46 observations, 48 events and 2 gaps kept, the same observation keys, both refusal paths still refusing and the adoption into schema3 reported.

The three documented advisory exceptions were checked against the local advisory database and against the dependency graph: RUSTSEC-2023-0071 is `rsa` 0.9.10 (Marvin attack, `patched = []`), RUSTSEC-2023-0089 is `atomic-polyfill` 1.0.3 (unmaintained, `patched = []`) and RUSTSEC-2024-0449 is `unsafe-libyaml` 0.2.11 (unmaintained, `patched = []`). All three are present in the tree through the paths named in `deny.toml`, none of them has an upstream fix, and the existing local only exceptions stay unchanged and unwidened.

## Addendum — the OIP-009 browser session, SSE and context seam contract

Five places in the tree defer the browser session, the SSE boundary and the global context to OIP-009, and this document states that the final OIP-009 payload must be reconciled three ways. The implemented part now exists and is verified, so it is written down as the boundary any payload has to satisfy: `docs/architecture/oip-009-browser-session-sse.md`.

It describes the one-use pairing code, the session and its bound, the exact Origin and CSRF rules, the revocation, the token hygiene, the SSE revalidation per projection and the context seam with its cache invalidation, and names the place that proves each rule. Two Flutter contract tests close the test gap around the seam: a context change advances `contextRevision` and clears the display cache, and another operator Principal invalidates the display cache.

The document explicitly does not decide the global Organization / Infrastructure / Site selection. That payload stays with the independent UI workstreams, still needs the three-way reconciliation of controller, API and contracts/Devices, and may not introduce a second context object or a second security model. The canonical tree still has no global context selection; `setInfrastructureContext` has no caller and the operator sees the scope of the session Principal.

Verified on canonical `main` (`d32c9d1`): format and clippy with denied warnings, **180** workspace tests, Flutter analysis without issues, **86** Flutter tests and the acceptance harness with **eight** passing phases, including the browser identity and the real Flutter onboarding over the authenticated session.
