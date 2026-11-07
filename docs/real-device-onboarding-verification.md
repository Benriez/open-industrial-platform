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
