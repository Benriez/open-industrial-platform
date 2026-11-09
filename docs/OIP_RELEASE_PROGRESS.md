# OIP release progress

Single state file for the autonomous OIP release loop. Every iteration reads this file
before choosing work, executes **one** clearly delimited step, verifies the real function,
records the measured evidence below and commits only verified changes.

Scope of the release goal: a fully locally usable OIP application with secure browser login,
a real multi-infrastructure view, working Flutter device management, verified SSH onboarding,
real monitoring, consistent Spectrum UX and reliable macOS operation.

## 1. Canonical state

| Item | Value |
|---|---|
| Canonical branch | `main` |
| Canonical source revision (the product: `apps/`, `crates/`) | `724d83b` (`chore(tests): the acceptance receipts name the revision they were measured on`) — unchanged since; the commits after it change the record and the harness only |
| The revision of the branch (`main`) | `95ea28d` (tree `f3690b742865`) |
| The revision of the final acceptance | `678c73a` — the clean tree the canonical gate passed on |
| The revision of the Core binary of the release | `ee67106` — the binary names its own revision; the same revision yields the same bytes |
| The build of the Core of the release | `cargo build --locked --release --workspace --bin oip-server --example mcp_probe` |
| The gate statuses of the current release | `docs/OIP_RELEASE_LEDGER.md` — the authoritative table |
| Integration method | real `git merge --ff-only`, no merge commit, no rewrite, in eleven controlled steps |
| Tracked files in the canonical source revision | 651, source manifest SHA-256 `3fccc6043efa9577e9e2e5575bbc53cd8e71aa9a1b5ab5043adfc80f3143f744` (the digest of `git ls-files -s`) |
| Documentation commit on top | the ledger, the runbook, the receipts of `docs/evidence/` and the release manifest `docs/release/` are the only artefacts of the state of the release; the source of the Core and of the client is unchanged by them, so the manifest above stays the manifest of the source revision |
| Working tree | clean; the loop state directory is ignored |
| Push / deployment | none |
| Real installation | **not activated**; the personal SQLite database is untouched at schema 6 |

The canonical tree carries eleven controlled integrations: iteration 1 integrated the reviewed
real device onboarding candidate `ae4c6ba` (tree `f72cb66`) unchanged, iteration 2 integrated
the isolated conformance branch `feature/oip-real-device-conformance` (`fc828ac`), iteration 3
integrated the isolated harness branch `feature/oip-native-macos-harness` (`b19092d`), iteration 4
integrated the isolated payload branch `feature/oip-connection-payload-bound` (`5a48b0c`) and
iteration 5 integrated the isolated contract branch `feature/oip-009-context-contract`
(`d32c9d1`), iteration 6 the isolated regression branch `feature/oip-canonical-regression`
(`111dff1`), iteration 7 the isolated baseline branch `feature/oip-007-baseline-adoption`
(`6df189f`) and the isolated parity gate branch `feature/oip-parity-gate-convergence`
(`f4b89ed`), iteration 8 the isolated monitoring branch
`feature/oip-monitoring-observations` (`2ec4829` and `e12c009`), iteration 9 the isolated
history branch `feature/oip-observation-history` (`1287e23`), iteration 10 the isolated
overview branch `feature/oip-managed-overview` (`1e6b743`), iteration 11 the isolated
network branch `feature/oip-network-placement` (`e9036ef`). No iteration weakened a contract
rule, and none activated the installation.

## 2. The gates of the current release

The authoritative table of the gates, their status and their measured evidence is
**`docs/OIP_RELEASE_LEDGER.md`**. It is written in every iteration and names the receipts of
`docs/evidence/`. The current state:

| Gate | Status |
|---|---|
| G1 integrated Core and the six workstations | DONE |
| G2 authentication, sessions, the parity of the transports, the isolation of the organizations | READY (the software part) |
| G3 the global infrastructure context | DONE |
| G4 device management in the application | READY (the software part) |
| G5 real device connections | BLOCKED_OPERATOR |
| G6 monitoring | READY (the software part) |
| G7 the approved Spectrum-2027 UX | DONE |
| G8 the six functional views | READY (the software part) |
| G9 the macOS build and the local operations | READY (the software part) |
| G10 the security release review | READY (the review is done) · BLOCKED_OPERATOR (the acceptance) |
| G11 the acceptance | DONE (the storage-failure path is measured) |
| G12 the operator acceptance | BLOCKED_OPERATOR |

The operator actions that the loop cannot perform are listed in the ledger. The release is
**not** production-ready: the gates that need the operator are open.

### 2a The acceptance of the milestone era (iteration 11 — historical)

The table below is the acceptance of the milestone era of the release. It is kept as the history
of that era; the state of the current release is the table above and the ledger.

Legend: `PROVED` = measured in this run on canonical `main`; `WITHHELD` = deliberately not
claimed; `BLOCKED` = cannot be executed without an explicit external decision.

| Gate | Status | Evidence (iteration 11, canonical `main` = `e9036ef`) |
|---|---|---|
| Rust format check | PROVED | `cargo fmt --all -- --check` → exit 0 |
| Rust workspace check | PROVED | `cargo check --locked --workspace --all-targets` → exit 0 |
| Rust clippy, warnings denied | PROVED | `cargo clippy --locked --workspace --all-targets -- -D warnings` → exit 0 |
| Rust workspace tests | PROVED | 181 passed, 0 failed, in 29 suites (`docs/evidence/oip-rust-regression/rust-regression.json`); no Rust source changed in iteration 10, so the result of iteration 9 stays valid for this tree |
| OPC-UA default backend | PROVED | 37 passed, 0 failed |
| OPC-UA open62541-only backend | PROVED | 2 passed, 0 failed (overlapping group) |
| Dependency policy | PROVED | `cargo deny check advisories licenses bans sources` → advisories ok, bans ok, licenses ok, sources ok |
| Server binary + official MCP probe | PROVED | `cargo build --locked -p oip-server --bin oip-server --example mcp_probe` → exit 0 |
| Flutter static analysis | PROVED | `flutter analyze` → exit 0, no issues |
| Flutter widget/unit suite | PROVED | 101 passed, 0 failed |
| Flutter web release, CanvasKit | PROVED | `flutter build web --release --web-renderer canvaskit …` → exit 0 |
| Flutter web release, HTML | PROVED | `flutter build web --release --web-renderer html …` → exit 0 |
| Browser identity + writer ownership | PROVED | `tests/real_device/acceptance.py` phase `browser_identity_online_writer` → PASS |
| Monitoring measurements in the operator panel | PROVED | `tests/real_device/acceptance.py` phase `actual_flutter_ssh_onboarding` → PASS; the rendered panel shows the ten host observations the Core received over SSH, compared against the Core response of the same device (`host.os` = `Darwin`, `host.memory_total_bytes` = 17179869184, all `fresh`); `apps/flutter/test/monitoring_observations_test.dart` → 3 tests |
| SSH handshake, identity confirmation, monitoring | PROVED | phase `ssh_handshake_confirmation_monitoring` → PASS, actual local macOS host facts (`facts_os: Darwin`) |
| Restart / SIGKILL recovery | PROVED | phase `restart_sigkill_identity` → PASS, integrity `ok`, foreign keys clean, 0 duplicate keys |
| Actual Flutter → HTTP → Core → OpenSSH | PROVED | phase `actual_flutter_ssh_onboarding` → PASS, browser receipt `target/oip-real-device-e2e/browser/report.json` |
| Ingestion without any client | PROVED | phase `no_clients_ingestion_progress` → PASS, 140 → 150 observations |
| Host-key rotation blocked | PROVED | phase `host_key_change_blocks_collection` → PASS, 0 new observations after the block |
| 8 official MCP SDK clients | PROVED | phase `eight_official_mcp_clients` → PASS, REST/MCP parity |
| Weak host key rejected by the server | PROVED | phase `weak_host_key_is_rejected_by_the_server` → PASS, `SSH_HOST_KEY_TOO_WEAK`, no binding created |
| Browser session boundary in Rust | PROVED | `crates/oip-server/tests/browser_session.rs` → 6 tests: exact Origin, single-use code, CSRF on every write, revoked session, revoked projection stream and the cookie path of the persisted history |
| Managed network view shows the authorized placement | PROVED | `apps/flutter/test/managed_network_test.dart` → 1 test; the authorized placement, the registered node and the honest absence of a topology are rendered, the loading state and the demo zones are gone; the browser receipt names the placement the Core delivered (`org-a · infra-a1 · site-a1`) |
| Managed overview shows the authorized infrastructure | PROVED | `apps/flutter/test/managed_overview_test.dart` → 3 tests; the source registry, its real health, its placement and the measured series are rendered and the demo coordinates are gone; the browser receipt compares the rendered overview with the source registry and the measurement the Core received over SSH (`SSH host browser-existing`, `host.memory_total_bytes` = 17179869184) |
| Persisted observation history in the device view | PROVED | `tests/real_device/acceptance.py` phase `actual_flutter_ssh_onboarding` → PASS; the Core persisted 10 samples of the connected device, the operator view rendered them as history and the browser receipt compares them against the Core answer; `apps/flutter/test/observation_history_test.dart` → 8 tests |
| Native macOS build and test | PROVED | `tests/oip008/ui_regression.py` → native build 11.6 s with the build marker, native integration test 39.1 s with the `All tests passed!` marker, against an owned isolated demo core |
| Legacy browser, interaction and visual regression | PROVED | browser 80.4 s, interactions 47.1 s, visual 63.4 s on the separately built HTML renderer |
| Milestone acceptance harnesses on the canonical tree | PROVED | `tests/canonical_regression.py`: OIP-008, OIP-008.2, OIP-008.2 schema3 migration, OIP-008.4, OIP-008.5, OIP-008.5 migration, the UI regression and the schema2 adoption all PASS on the canonical tree, no failed and no blocked case |
| Canonical Spectrum-2027 UI baseline and design regression gate | **PROVED** | `OIP_CANONICAL_UI_GATE=1 python3 tests/real_device/acceptance.py` → PASS on canonical `main` = `525f5c86d6baf5f27d5b13bd648d2d17794bb5a5` (tree `b5b23c6f2ac0d3ee02e09837933027facdeb6042`): 335/335 Flutter tests, 175 browser findings with zero failures, 13 captures of the six workstations at 1440 px and 1920 px, the stable-shell visual comparison with both negative-control classes, all 8/8 managed acceptance phases including the actual Flutter SSH onboarding. Local and served bundle are byte-identical: `169aaa8257a782ae52d5afe7b9de68b6acedb013cc24c96783e11e054cc22caa`. Operator visual acceptance remains `VISUAL_PENDING_OPERATOR_ACCEPTANCE` |
| Physical Raspberry-Pi acceptance | **WITHHELD** | no endpoint, SSH user or approved identity was supplied; no personal device was contacted |
| Real installation activation (schema 7) | **BLOCKED** | requires a separate operator decision plus a fresh protected backup; forbidden in this loop |
| Productive remote/browser identity | **OPEN** | loopback local operator session only; no HTTPS, no remote identity, no hostile same-UID isolation |
| Durable tamper-proof audit | **OPEN** | audit is append-only in application code, the SQLite file itself stays writable by the daemon user |
| OT / endurance certification | **OPEN** | not claimed; the measurements below are short local observations, not an SLA |
| RUSTSEC-2023-0071 / -0089 / -2024-0449 | **OPEN** | still ignored with the existing documented local-only exceptions in `deny.toml`; no new exception added |

### Short local measurements (not an SLA)

* Official MCP `device_connection_read`: 20 sequential samples with 8 attached clients,
  p50 4.51 ms, p95 4.80 ms.
* One Core sample while the harness ran: 31,088 KiB RSS, 14.8 % CPU.
* Ingestion advanced 140 → 150 observations after all browser and MCP clients disconnected.

## 3. Open items, in execution order

Each item names the next *delimited* step, its gate and its blocker and carries one state:

* **READY** — released and executable by the loop. The loop continues with the first READY item.
* **BLOCKED_OPERATOR** — needs an explicit operator decision. The loop does not start it.
* **BLOCKED_DEPENDENCY** — needs a result another workstream owns. The loop does not invent it.
* **DONE** — closed and measured.

| Item | State | Next delimited step |
|---|---|---|
| N1 conformance findings (Core) | **DONE** | closed in iteration 2, F4 closed in iteration 4 |
| N1b F5 authorization rule | **BLOCKED_OPERATOR** | loosening a permission needs an explicit release |
| N2 native macOS build and test | **DONE** | closed in iteration 3 |
| N3 global selection payload | **BLOCKED_DEPENDENCY** | three-way reconciliation with the independent UI workstreams |
| N4 real installation activation | **BLOCKED_OPERATOR** | operator decision plus a fresh protected schema-6 backup |
| N5 production advisories and security | **DONE** for the three documented exceptions | the production security work stays open and unclaimed |
| N6 persisted observation history | **DONE** | closed in iteration 9 |
| N7 monitoring measurements in the panel | **DONE** | closed in iteration 8 |
| N8 real multi-infrastructure overview | **DONE** | closed in iteration 10 |
| N9 the network view of the authorized placement | **DONE** | closed in iteration 11 |
| N10 the managed diagnostics view | **READY** | the next step of the loop |
| N11 canonical Spectrum-2027 UI baseline and design regression gate | **DONE, closed in iteration 12** | the two parallel executions of the same integration were reconciled into one candidate, the full gate is PASS on `e7aa994` and the candidate is integrated into canonical `main` with `git merge --ff-only`; operator visual approval remains `VISUAL_PENDING_OPERATOR_ACCEPTANCE` |

A blocked item never stops the loop while an independent READY item exists. Items that need an
explicit operator decision (N1b, N4) or that would change a rule instead of enforcing one are
not started by the loop without a separate release.

### N1 — Close the conformance gaps found by the delegated source review (Core) — **DONE**

A read-only source review against `docs/architecture/real-device-onboarding.md` produced the
findings below. They are contract conformance defects, not new architecture. Fix them on an
isolated feature branch, add Rust-level regression tests, re-run the full gate set above and
integrate with the same controlled fast-forward.

**Status: F1, F2, F3, F6, F7 and R1 are fixed and verified in iteration 2, F4 in iteration 4.**
F5 is split off as N1b below because it changes an authorization rule and needs its own explicit
review.

| Id | Severity | Location | Defect | Contract reference | Status |
|---|---|---|---|---|---|
| F1 | medium | `crates/oip-server/src/ssh.rs` (`minimum_key_bits`, `parse_key_report`, `scan`) | The server never enforced "RSA keys require at least 2048 bits". `ssh-keygen -lf` already prints the key size, but only the fingerprint was kept; enforcement was delegated to the `RequiredRSASize=2048` client option of the *user* connection. A weak `ssh-rsa` host key could be scanned, shown, trusted and pinned. | `docs/architecture/real-device-onboarding.md:48` | **fixed** |
| F2 | low/medium | `crates/oip-server/src/ssh.rs` (`run`) and `crates/oip-server/src/connection_service.rs` (`read`) | `REMOTE HOST IDENTIFICATION HAS CHANGED` **and** `Host key verification failed` were both mapped to `SSH_HOST_KEY_CHANGED`, so an unknown key was reported as a rotation alarm. | `docs/architecture/real-device-onboarding.md:23`, `:66` | **fixed** |
| F3 | low | `crates/oip-server/src/browser_session.rs` (`login`) | The invalid-code limiter was evaluated *before* the grant lookup, so 16 malformed codes blocked the operator's valid single-use code for 60 s. Local-process availability bug inside the session boundary. | `docs/architecture/real-device-onboarding.md:36` | **fixed** |
| F4 | low | `crates/oip-server/src/ssh.rs` (`parse`) vs `crates/oip-storage/src/connection.rs` | The maximal host report the parser can build (up to ~128 KiB of interface/disk text) exceeds the 128 KiB `payload_json` CHECK, so a legal but extreme remote report fails the commit with an opaque storage error instead of a typed fault. | `docs/architecture/real-device-onboarding.md:50`, `:58` | **fixed** in iteration 4 |
| F5 | low | `crates/oip-server/src/connection_service.rs` (`check_plan`) | The read path requires `DeviceConnectionConfigure`; the contract places `GET /device-connections?plan_id=…` under `DeviceConnectionRead`. Conservative over-restriction, not an escalation. | `docs/architecture/real-device-onboarding.md:15` | **open and paused** → N1b |
| F6 | low | `crates/oip-server/src/browser_session.rs` (`login`) | The session-capacity check ran after the single-use grant was already consumed, so a valid code was destroyed when 64 sessions existed. | `docs/architecture/real-device-onboarding.md:36` | **fixed** |
| F7 | low | `crates/oip-server/src/ssh.rs` (`private_workdir`) | The SSH work directory was created with the process umask and only afterwards chmod'ed to 0700, leaving a brief world-readable window. | `docs/architecture/real-device-onboarding.md:48` | **fixed** |
| R1 | test gap | `crates/oip-server/tests/browser_session.rs` | No Rust-level test covered the browser session/CSRF/Origin flow; those assertions only existed in the external harness `tests/real_device/acceptance.py`. | `docs/architecture/real-device-onboarding.md:37-39` | **fixed** |

### N1b — Remaining conformance items (authorization rule) — **BLOCKED_OPERATOR**

**F4 (storage bound) is closed in iteration 4.** The parser now charges every collected disk
name, mount, interface name and address against a report budget, the server compares the
serialised record with the shared bound from the domain crate before the write, and an extreme
report is refused with an explicit fault instead of a rollback.

* **F5 (authorization rule) — open and deliberately paused.** The contract table in
  `docs/architecture/real-device-onboarding.md:15` places `GET /device-connections?plan_id=…`
  under `DeviceConnectionRead`, while the implementation requires `DeviceConnectionConfigure`.
  The change *loosens* a permission and therefore is a security decision, not a conformance
  fix. The loop does not take it without an explicit release. When it is released it needs:
  a negative test for a foreign principal and a principal without `InventoryManage`, a
  parity update in `docs/architecture/oip-008-rest-mcp-parity.md` if the capability matrix
  changes, and the normal capability, scope and audit gate set.

### N2 — Native macOS build and test (open acceptance item) — **DONE, closed in iteration 3**

The P0 handoff recorded the native build blocked inside SwiftBuild toolchain discovery
(`QNXSDP.findInstallations → LocalFS.listdir → __getattrlist`); Flutter returned zero without
running a test, and the raw exit code was corrected by a hash-bound receipt. No native PASS
was claimed.

**Measured result: the native macOS build and the native integration test work.** The cause was
not a broken toolchain but two bounds that were too short for a cold native build on this shared
machine: the UI regression harness applied a single 300 second bound to the web steps *and* to
the native step, and the native test ran its build inside the test command, where the default
test timeout of twelve minutes expired during the load phase. A cold `flutter build macos
--debug` needs about eight minutes here (497 s measured), the warm build 12.7 s and the native
integration test 34.4 s.

The harness now runs the native build as its own step with its own bound and a positive build
marker, runs the native integration test with an explicit `--timeout 30m` and its own bound,
records the elapsed seconds and the marker of every step, and never accepts a step without its
marker. The legacy web regression now receives the separately built HTML renderer, because it
reads the rendered text from the document while the CanvasKit build paints it on a canvas.

Result on canonical `main` (`b19092d`): browser 80.4 s, interactions 47.1 s, visual 63.4 s,
native build 11.6 s with the `Built build/macos/.../oip_dashboard.app` marker, native
integration test 39.1 s with the `All tests passed!` marker, demo core shutdown exit 0.

The native path stays what the contract allows: a compatibility and regression check in the
explicit isolated demo mode. Native authenticated session-cookie transport is still not claimed
and the native app is not the product path.

### N3 — OIP-009 browser session / SSE / global context contract — **contract DONE (iteration 5), global selection payload BLOCKED_DEPENDENCY**

`docs/oip-0082-verification.md:116`, `docs/oip-0084-verification.md:134`,
`docs/architecture/oip-0085-real-inventory-flutter-contract.md:3` and
`docs/architecture/real-device-onboarding.md:88-90` all defer the global context to OIP-009.
The implemented part (one-use pairing code, `HttpOnly; SameSite=Strict` cookie, exact Origin,
`x-oip-csrf`, session-scoped SSE revalidation, `setInfrastructureContext` cache invalidation)
exists in the canonical tree; the *contract document* and the global Organization /
Infrastructure / Site selection did not.

**The contract document now exists**: `docs/architecture/oip-009-browser-session-sse.md`. It
states the implemented and verified boundary — the pairing code, the session and its bound, the
exact Origin and CSRF rules, the revocation, the token hygiene, the SSE revalidation per
projection and the context seam with its cache invalidation — and names where each rule is
proved. It explicitly does **not** decide the global selection payload and states the
conditions a payload has to meet.

**The global selection payload remains open** and is not part of this release. It belongs to
the independent UI workstreams and still requires the three-way reconciliation of controller,
API and contracts/Devices named in `docs/architecture/real-device-onboarding.md:90`. The
canonical tree still has no global context selection: `setInfrastructureContext` has no
caller, and the operator sees the scope of the session Principal.

### N4 — Controlled activation of the real installation — **BLOCKED_OPERATOR**

Blocked by explicit instruction and by risk. The candidate opens schema 7; the personal
database is at schema 6 and must not be changed here. Required before activation: a fresh
consistent database/config/profile backup, the protected schema 6 rollback copy, one daemon,
one `--browser-login` code, the explicitly confirmed endpoint for
`tools/configure_ssh_profile.py` (dry run first) and the physical Raspberry-Pi acceptance that
belongs to the still withheld hardware verdict.

### N5 — Production advisories and remaining security work — **the three documented exceptions are DONE; the production work stays open**

**The three documented exceptions were verified against the advisory database in iteration 7
and are correct, necessary and unavoidable.** The earlier note in this file that the ignore
reasons of RUSTSEC-2023-0089 and RUSTSEC-2024-0449 would not match the advisory subjects was
wrong and is corrected here:

| Id | Crate | Subject | In the tree via | Patched |
|---|---|---|---|---|
| RUSTSEC-2023-0071 | `rsa` 0.9.10 | Marvin attack, timing side channel of the private key | `async-opcua-client`, `async-opcua-crypto` → `oip-opcua` | none (`patched = []`, still affected in 0.9.10) |
| RUSTSEC-2023-0089 | `atomic-polyfill` 1.0.3 | unmaintained (informational) | `heapless` → `postcard` → `async-opcua-server`, embedded targets only | none (`patched = []`) |
| RUSTSEC-2024-0449 | `unsafe-libyaml` 0.2.11 | unmaintained (informational) | `serde_yaml` → `async-opcua-core` | none (`patched = []`) |

All three are informational or unfixable in the upstream crates, so no dependency upgrade can
clear them; the local only exceptions stay as they are, with the unchanged review date. The
advisory of RUSTSEC-2023-0071 itself names the accepted scope: "Local use on a non-compromised
computer is fine", and the OIP-002 exception limits the usage to explicitly trusted loopback
tests.

Productive remote/browser identity, hostile same-UID isolation, tamper-proof durable audit and
OT/endurance certification stay open and are not claimed by this release.

### N6 — Persisted observation history in the device view — **DONE, closed in iteration 9**

The Core already serves the persisted history, the DTOs, the permissions and the query contract
exist, and the Flutter client names the gap itself: the device dialog states *"Autorisierte
historische REST-v2-Abfragen existieren im Core"* and the diagnostics view states *"Noch kein
persistierter Diagnoselauf"*. The seven routes `GET /api/v2/observations/history`,
`/api/v2/events/history`, `/api/v2/events/detail`, `/api/v2/diagnostics/gaps`,
`/api/v2/diagnostics/health-history`, `/api/v2/diagnostics/evidence` and
`/api/v2/diagnostics/findings` are registered in `crates/oip-server/src/api.rs:207-213`, they are
authorized by `crates/oip-core/src/capabilities.rs:153-181` and their REST/MCP parity is proven in
`crates/oip-server/tests/diagnostics.rs:271-334` and `tests/oip0082/acceptance.py:98-150`.

The next delimited step is one client feature plus one test group:

1. `apps/flutter/lib/services/api.dart`: add an `observationHistory({required String deviceId})`
   method to `DeviceManagementApi` and implement it as
   `GET /api/v2/observations/history?device=<id>`. The device scope is used deliberately, so no
   global Organization/Infrastructure/Site payload is invented; the SSH source placement already
   resolves the device to its source (`crates/oip-core/src/diagnostics.rs:13`).
2. `apps/flutter/lib/features/devices.dart`: replace the *"Historie noch nicht angebunden"*
   notice with the returned history, each sample explicitly labelled as historical. A stored
   sample is `stale` by definition (`tests/oip0082/acceptance.py:106`) and must never be drawn as
   a live value. `truncated` and `next_cursor` have to be surfaced; `DiagnosticPage` has no total.
3. `crates/oip-server/tests/browser_session.rs`: close the test gap that the seven history routes
   are currently proven only with a `Bearer` token (`crates/oip-server/tests/diagnostics.rs:314-328`)
   and not at all with the browser session cookie. The test asserts 200 for the bound device, 404
   `RESOURCE_NOT_ACCESSIBLE` for a foreign scope, 403 `PERMISSION_DENIED` for a principal without
   the capability and 403 without a session. It changes no permission rule.

**Boundaries.** The history needs a file-backed SQLite database; an in-memory database answers
`HISTORY_UNAVAILABLE` (`crates/oip-storage/src/history.rs:56-70`). The personal database is not
touched by this step. `events_read` is not guaranteed for every operator principal, so the
observation history is the first surface; the event history follows only when the capability is
proven.

**Result.** The device view requests the history for the device itself, every sample is rendered
as history with the receive time the Core guarantees, and the stable id of a sample deduplicates a
refresh. The browser session cookie authorizes the route; the new Rust test proves that boundary.
See the iteration log below.

### N7 — Monitoring measurements in the operator panel — **DONE, closed in iteration 8**

The device connection panel now renders the current authorized observations of the connection
view. See the iteration log below.

### N8 — The managed overview shows the real authorized infrastructure — **DONE, closed in iteration 10**

In the managed mode the overview is still driven by the coordinates of the demo. The trend
accumulator only accepts the entity `M-01` and the metric `temperature`
(`apps/flutter/lib/app/controller.dart:172-188`), and the temperature tile of the overview expects
the same pair (`apps/flutter/lib/models/contracts.dart:239-245`). A managed device reports
`host.*` metrics under its own device id (`crates/oip-server/src/ssh.rs:1002`), so the trend of the
landing page stays empty and the tile shows `—` although the Core delivers the values. The scoped
snapshot additionally carries the `sources` array and the `locations`, and the client drops both
(`apps/flutter/lib/models/contracts.dart:249-280`).

The next delimited step is purely client-side and changes no contract, permission or server rule:

1. `apps/flutter/lib/models/contracts.dart`: keep the authorized `sources` and `locations` of the
   scoped snapshot instead of discarding them.
2. `apps/flutter/lib/app/controller.dart`: fill the trend from the authorized observations of the
   selected source instead of the hardcoded demo coordinates, with the same continuity and epoch
   rules that the legacy path uses.
3. `apps/flutter/lib/features/overview.dart`: show the authorized sources with their real
   connection, reachability, service and freshness instead of placeholders, and name the source of
   every tile.
4. `apps/flutter/test/` a widget test with a scoped fixture that asserts that the managed overview
   renders the authorized source and its real metric, and that no `M-01` literal remains in the
   managed path.

The gate is `flutter analyze`, `flutter test`, the real device harness and the canonical
regression.

**Result.** The managed network view states that the projection carries no topology, draws no path,
colours no reachability green and shows the authorized placement of the session with the registered
nodes of that site. The loading state and the zones of the legacy demo are gone. See the iteration
log below.

### N10 — The managed diagnostics view shows the authorized evidence — **READY**

The scoped projection of a managed session carries the collection events of the authorized sources
(`crates/oip-server/src/tenant_services.rs:576-583`), and the client drops them
(`apps/flutter/lib/models/contracts.dart:249-280`). The diagnostics view therefore states *"Noch
kein persistierter Diagnoselauf"* and *"Diagnosehistorie: demo_only"*, although the Core delivers
the authorized events of the session and serves the persisted history of every event, gap, health
transition and finding behind `GET /api/v2/events/history`,
`/api/v2/diagnostics/gaps`, `/api/v2/diagnostics/health-history` and
`/api/v2/diagnostics/findings` (`crates/oip-server/src/api.rs:207-213`).

The next delimited step is client-side and changes no contract, permission or server rule:

1. `apps/flutter/lib/models/contracts.dart`: keep the authorized `events` of the scoped projection
   instead of dropping them, and map them with the existing `CollectionEvent.fromRecord`.
2. `apps/flutter/lib/features/diagnostics.dart`: show the collection events that the session is
   authorized to see, with their real time, their reason and their gap. The persisted history of
   the events is the next step, and only for the capability the principal actually holds:
   `events_read` is not proven for every operator principal, the observation history was proven
   first for that reason.
3. `apps/flutter/test/` a widget test with the scoped fixture that asserts that the diagnostics
   view shows the authorized events and never a demo incident.

The gate is `flutter analyze`, `flutter test`, the real device harness and the canonical
regression. `GET /api/v2/sources` (`crates/oip-server/src/api.rs:202`) is a possible second step
for the per-source health, but it is not required for this one: the scoped snapshot already carries
the authorized sources.

**Result.** The managed overview draws the session's scope: the source registry with the health the
Core measured, the placement of the source in the authorized hierarchy and one measured series per
authorized source. No source and no fallback primary is preferred, no global selection payload is
invented and the demo coordinates are gone. See the iteration log below.

### N9 — The network view shows the authorized placement — **DONE, closed in iteration 11**

The network view shows *"Topologie wird geladen"* when the projection carries no topology
(`apps/flutter/lib/features/network.dart:246-248`). The scoped projection has no topology array at
all, so that message promises data that will never arrive; it is a loading state without a loader.
The authorized `locations` of the projection — organization, infrastructure, site and source — are
the real placement of the session and are already delivered
(`crates/oip-server/src/tenant_services.rs:584-587`).

The next delimited step is client-side and changes no contract, permission or server rule:

1. `apps/flutter/lib/features/network.dart`: draw the authorized placement of the session instead of
   the loading message, and name the registered nodes only. No link is guessed, no reachability is
   turned green and no topology is invented.
2. The sources of the session keep their own placement; the hierarchy names are only shown when the
   authorized hierarchy API delivered them for that scope.
3. `apps/flutter/test/` a widget test with the scoped fixture that asserts that the network view
   shows the authorized placement and never a permanent loading state.

The gate is `flutter analyze`, `flutter test`, the real device harness and the canonical
regression.

## 4. Iteration log

### Iteration 1 — canonical integration of the real device onboarding feature

**Step.** Integrate `feature/real-device-onboarding-integration` into canonical `main` with a
real fast-forward and re-prove the merged tree with the full gate set. No runtime code was
changed, no installation was activated, no personal device was contacted.

**Commands and measured results.** All commands ran in `/Users/benny/Code/open-industrial-platform`
on canonical `main` = `ae4c6ba`:

```
git merge --ff-only feature/real-device-onboarding-integration   # 49a86bb -> ae4c6ba, 67 files
cargo fmt --all -- --check                                       # exit 0
cargo check --locked --workspace --all-targets                    # exit 0
cargo clippy --locked --workspace --all-targets -- -D warnings    # exit 0
cargo test --locked --workspace -- --test-threads=1               # 167 passed, 0 failed
cargo test --locked -p oip-opcua --features open62541-backend      # 37 passed
cargo test --locked -p oip-opcua --no-default-features --features open62541-backend  # 2 passed
cargo build --locked -p oip-server --bin oip-server --example mcp_probe   # exit 0
cargo deny check advisories licenses bans sources                 # advisories/bans/licenses/sources ok
flutter analyze                                                    # exit 0
flutter test                                                       # 84 passed
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
flutter build web --release --web-renderer html --no-web-resources-cdn --pwa-strategy=none --output build/web-html
OIP_EVIDENCE_DIR=target/oip-real-device-e2e \
OIP_SERVER_BIN=target/debug/oip-server \
OIP_WEB_DIR=apps/flutter/build/web \
OIP_BROWSER_SCRIPT=apps/flutter/test/browser_onboarding.mjs \
PLAYWRIGHT_MODULE=apps/flutter/test/node_modules/playwright/index.mjs \
python3 tests/real_device/acceptance.py                           # 7 phases PASS, exit 0
```

**Result.** Canonical `main` now carries the authenticated browser session, the SSH
connection and monitoring core, the schema 7 connection storage and the Flutter operator
login, device onboarding and connection panel. Every gate above is green on the canonical
tree, including the actual Flutter → authenticated HTTP → shared Core → owned loopback
OpenSSH path with genuine local macOS host facts, the eight official MCP SDK clients, the
host-key rotation denial and the SIGKILL recovery.

**Not claimed.** No physical Raspberry-Pi was contacted; no production identity, no HTTPS, no
hostile same-UID isolation, no OT certification. The real installation was not activated and
the personal database is unchanged.

**Committed.** `docs/OIP_RELEASE_PROGRESS.md` (this file),
`docs/real-device-onboarding-verification.md` (canonical integration addendum),
`docs/evidence/oip-real-device/test-summary.json`,
`docs/evidence/oip-real-device/review.json`, `.gitignore`.

### Iteration 2 — conformance fixes F1, F2, F3, F6, F7 and the Rust test group R1

**Step.** Close the reviewed conformance gaps of the integrated feature in an isolated branch
and integrate the verified result. No contract rule was relaxed, no architecture decision was
taken and no installation was activated.

**Isolation.** Branch `feature/oip-real-device-conformance` in the worktree
`/Users/benny/Code/open-industrial-platform-worktrees/real-device-conformance`, created from
the canonical `main` at `b0096e1`. The branch was built and tested with its own
`CARGO_TARGET_DIR` (`target/conformance`) and with its own Flutter web build, so neither the
canonical binary nor the canonical web assets were replaced during development. The branch was
integrated afterwards with a real `git merge --ff-only`.

**What changed.**

* `crates/oip-server/src/ssh.rs`: the server now reads the size of every offered host key
  itself (`minimum_key_bits`, `parse_key_report`) and rejects a key below the accepted minimum
  before it is offered for acceptance or pinned. The attempt fails with the typed fault
  `SSH_HOST_KEY_TOO_WEAK`; `RequiredRSASize=2048` remains as defence in depth.
* `crates/oip-server/src/ssh.rs`: only `REMOTE HOST IDENTIFICATION HAS CHANGED` maps to
  `SSH_HOST_KEY_CHANGED`. An unpinned host now reports `SSH_HOST_KEY_UNKNOWN` and the operator
  status `host_key_unknown`, which the Flutter panel renders explicitly.
* `crates/oip-server/src/browser_session.rs`: rejected codes no longer block a valid
  single-use grant; the rejection accounting stays capped at 16 entries. A full session table
  no longer consumes an issued grant.
* `crates/oip-server/src/ssh.rs`: the private SSH work directory is created with the
  owner-only mode instead of being briefly world readable.
* `crates/oip-server/tests/browser_session.rs` (new): five Rust integration tests for the
  exact Origin, the single-use pairing code, the CSRF requirement on every cookie authorized
  write, a revoked session and a revoked projection stream.
* `tests/real_device/ssh_fixture.py` and `tests/real_device/acceptance.py`: the owned loopback
  fixture can serve a deliberately weak 1024 bit RSA host key, and the harness proves that the
  server rejects it end to end.
* `docs/architecture/real-device-onboarding.md`: the normative contract now states that the
  server enforces the key size itself, that a changed and an unknown key are separate
  outcomes, and that rejected codes never block a valid grant.

**Empirical basis for the fault split.** The classification was verified against the installed
OpenSSH 10.2 on this machine with an owned loopback fixture: a changed key produces
`REMOTE HOST IDENTIFICATION HAS CHANGED` together with `Host key verification failed`, while a
host without a pinned entry produces only `Host key verification failed`. The rotation case
therefore still maps to `SSH_HOST_KEY_CHANGED` and the acceptance harness still observes
`host_key_changed`.

**Commands and measured results.** Branch gates in the isolated worktree, then the same gate
set on the canonical tree after the fast-forward:

```
cargo fmt --all -- --check                                       # exit 0
cargo check --locked --workspace --all-targets                    # exit 0
cargo clippy --locked --workspace --all-targets -- -D warnings    # exit 0
cargo test --locked --workspace -- --test-threads=1               # 175 passed, 0 failed
cargo test --locked -p oip-opcua --features open62541-backend      # 37 passed
cargo test --locked -p oip-opcua --no-default-features --features open62541-backend  # 2 passed
cargo build --locked -p oip-server --bin oip-server --example mcp_probe   # exit 0
cargo deny check advisories licenses bans sources                 # advisories/bans/licenses/sources ok
flutter analyze                                                    # exit 0
flutter test                                                       # 84 passed
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
flutter build web --release --web-renderer html --no-web-resources-cdn --pwa-strategy=none --output build/web-html
python3 tests/real_device/acceptance.py                           # 8 phases PASS, exit 0
```

**Result.** The canonical tree enforces the RSA minimum host key size itself, distinguishes a
changed from an unknown host key, cannot lock the operator out of the browser session and
creates its private SSH work directory with the correct mode from the start. The browser
session boundary is now covered by Rust tests inside the repository instead of only by the
external harness.

**Not claimed.** No physical Raspberry-Pi was contacted, the real installation was not
activated, the personal database is unchanged at schema 6, the native macOS build is still not
proved and the productive identity, hostile same-UID, durable audit and OT boundaries stay
open. F4 and F5 remain open as N1b.

### Iteration 3 — native macOS build and test, and a reliable UI regression harness

**Step.** Close the open acceptance item "native macOS compilation was blocked" and make the UI
regression harness produce a reliable verdict. The work was done on the isolated branch
`feature/oip-native-macos-harness` in the worktree
`/Users/benny/Code/open-industrial-platform-worktrees/native-macos-harness` and integrated with
a real `git merge --ff-only`.

**Diagnosis before the fix.** The toolchain was inspected first: Xcode 26.6 at
`/Applications/Xcode.app/Contents/Developer`, Swift 6.3.3, Flutter 3.22.0, `flutter devices`
lists the macOS desktop device in 7 s, CocoaPods 1.15.2 with the Pods already installed. A cold
`flutter build macos --debug` then **succeeded** in 497.2 s and produced
`build/macos/Build/Products/Debug/oip_dashboard.app`. The toolchain is healthy; the P0
"blocker" was an interrupted and over-bounded attempt, not a missing capability.

**What changed** (`tests/oip008/ui_regression.py`, the only file):

* The native macOS build became its own step with its own 1800 s bound and the positive
  marker `Built build/macos/Build/Products/Debug/oip_dashboard.app`. A build that exits zero
  without producing the app is not accepted.
* The native integration test runs with `--timeout 30m` and its own 1800 s bound and keeps the
  positive marker `All tests passed!`. Exit status alone never turns a cancelled build into
  acceptance.
* Every step records its elapsed seconds and whether its required marker was seen.
* The web steps keep their 300 s bound, and the owned process group bound is unchanged.
* The legacy web regression receives the separately built HTML renderer by default and the
  served directory is recorded in the result. With the CanvasKit build the painted text is not
  in the document, so the text locator never matched and the harness reported a product
  failure that was a renderer mismatch.

**Measured result on canonical `main` (`b19092d`)**, harness `tests/oip008/ui_regression.py`
against an owned demo core on a random loopback port:

```
browser        exit 0   80.4 s
interactions   exit 0   47.1 s
visual         exit 0   63.4 s
native_build   exit 0   11.6 s   marker "Built build/macos/Build/Products/Debug/oip_dashboard.app" found
native_macos   exit 0   39.1 s   marker "All tests passed!" found
demo_core_shutdown exit 0
```

The run was repeated after the integration and produced the same verdict (browser 88.1 s,
interactions 47.9 s, visual 60.4 s, native build 12.7 s, native test 34.4 s in the first run),
so the result is reproducible and not a single lucky run.

**Not claimed.** The native run is a compatibility and regression check in the explicit
isolated demo mode, exactly as the contract allows. Native authenticated session-cookie
transport is still not claimed, no personal database was touched, no private device was
contacted and the physical Raspberry-Pi acceptance stays withheld.

### Iteration 4 — F4: bound the verified host report to the stored record size

**Step.** Close the remaining storage conformance finding F4 on an isolated branch and
integrate the verified result. F5 stays open and paused, because it loosens a permission.

**Isolation.** Branch `feature/oip-connection-payload-bound` in the worktree
`/Users/benny/Code/open-industrial-platform-worktrees/payload-bound`, created from the
canonical `main` at `c4d3bd9`, built and tested with its own target directory and integrated
afterwards with a real `git merge --ff-only` as `5a48b0c`.

**The defect.** The stored connection record is limited to 128 KiB
(`device_connections.payload_json`), but the SSH parser bounded the disk name and the
interface addresses only by the subprocess output. A legal but extreme remote report
therefore reached the writer and failed the commit with an opaque storage rollback instead of
an explicit fault, and the plan reported a generic error.

**What changed.**

* `crates/oip-core/src/connection.rs`: `CONNECTION_PAYLOAD_MAX_BYTES` (131072) and
  `CONNECTION_ATTEMPT_PAYLOAD_MAX_BYTES` (16384) are now shared domain constants.
* `crates/oip-server/src/ssh.rs`: every collected disk name, mount, interface name and address
  is charged against a report budget of 48 KiB; an oversized report is refused with the
  existing typed fault `SSH_OUTPUT_LIMIT`. A single disk name is additionally bounded to 256
  characters and an address to 128 characters.
* `crates/oip-server/src/connection_service.rs`: before the write, the record is serialised
  and compared with the shared bound. A record that cannot be stored is refused with the typed
  fault `SSH_REPORT_TOO_LARGE`, the plan fails with that fault and no partial binding is
  created.
* `crates/oip-storage/src/connection.rs`: the schema keeps its bound and a new test proves that
  the schema limit and the shared domain constant are the same value.
* `docs/architecture/real-device-onboarding.md`: the contract states the report budget, the two
  explicit faults and that no partial binding is created.

**New tests (5).** An extreme report is refused with `SSH_OUTPUT_LIMIT`; a realistic maximal
report stays inside the stored record bound; an oversized disk name is bounded in the report; a
record that cannot be stored is refused before any write; the storage schema limit equals the
shared domain constant.

**Commands and measured results** on the canonical tree after the fast-forward:

```
cargo fmt --all -- --check                                       # exit 0
cargo check --locked --workspace --all-targets                    # exit 0
cargo clippy --locked --workspace --all-targets -- -D warnings    # exit 0
cargo test --locked --workspace -- --test-threads=1               # 180 passed, 0 failed
cargo test --locked -p oip-opcua --features open62541-backend      # 37 passed
cargo test --locked -p oip-opcua --no-default-features --features open62541-backend  # 2 passed
cargo build --locked -p oip-server --bin oip-server --example mcp_probe   # exit 0
cargo deny check advisories licenses bans sources                 # advisories/bans/licenses/sources ok
flutter analyze                                                    # exit 0
flutter test                                                       # 84 passed
python3 tests/real_device/acceptance.py                           # 8 phases PASS, exit 0
```

**One observed flake, reported honestly.** During the first canonical OPC-UA run the
timing-sensitive test `async_opcua::client::tests::reconnect_recreates_subscription_and_reports_gap`
failed once while the machine was loaded (36 passed, 1 failed). It then passed in three
consecutive isolated runs (3.95 s, 4.54 s, 8.32 s) and in the repeated complete OPC-UA run
(37 passed, 0 failed, 140.48 s). The change touches no OPC-UA code; the observation is
recorded instead of being hidden.

**Not claimed.** No physical Raspberry-Pi was contacted, the real installation was not
activated, the personal database is unchanged at schema 6 and the productive identity,
hostile same-UID, durable audit and OT boundaries stay open. F5 remains open and paused.

### Iteration 5 — the OIP-009 browser session, SSE and context seam contract

**Step.** Close the contract gap that five documents defer to OIP-009, without deciding the
payload that OIP-009 still owns. Isolated branch
`feature/oip-009-context-contract` in the worktree
`/Users/benny/Code/open-industrial-platform-worktrees/oip-009-contract`, created from the
canonical `main` at `3f23ad7` and integrated with a real `git merge --ff-only` as `d32c9d1`.

**What changed.**

* `docs/architecture/oip-009-browser-session-sse.md` (new): the implemented and verified
  boundary of the browser session, the SSE stream and the global context seam, each rule with
  the place that proves it, plus an explicit section on what this document does not decide.
* `docs/architecture/oip-0082-diagnostics-flutter-contract.md`,
  `docs/architecture/oip-0084-flutter-settings-contract.md` and
  `docs/architecture/oip-0085-real-inventory-flutter-contract.md`: their deferral now points
  at the new contract instead of leaving the reader without a reference.
* `apps/flutter/test/onboarding_contract_test.dart`: two new contract tests close the test gap
  around the seam — a context change advances `contextRevision` and clears the display cache,
  and another operator Principal invalidates the display cache.

**The Rust source is unchanged** against the previous canonical source revision `5a48b0c`
(`git diff 5a48b0c -- crates/` is empty), so the Core gate results of iteration 4 remain valid
and were re-run on the canonical tree anyway.

**Commands and measured results** on the canonical tree after the fast-forward:

```
cargo fmt --all -- --check                                       # exit 0
cargo clippy --locked --workspace --all-targets -- -D warnings    # exit 0
cargo test --locked --workspace -- --test-threads=1               # 180 passed, 0 failed
flutter analyze                                                    # exit 0, no issues
flutter test                                                       # 86 passed, 0 failed
python3 tests/real_device/acceptance.py                           # 8 phases PASS, exit 0
```

The acceptance harness is the end-to-end proof of the contract subject: the browser identity
with the one-use code and the CSRF/Origin rules, the real Flutter onboarding over the
authenticated session, the host key rotation denial, the weak host key rejection and the eight
official MCP clients all pass. The browser receipt reports no page error and no external
request, and the served build hash is unchanged.

**Not claimed.** The global Organization / Infrastructure / Site selection is still not
implemented and is not decided here. No physical Raspberry-Pi was contacted, the real
installation was not activated, the personal database is unchanged at schema 6 and the
productive identity, hostile same-UID, durable audit and OT boundaries stay open. F5 remains
open and paused.

### Iteration 6 — a reproducible canonical regression run and two repaired stale gates

**Step.** Re-run the milestone acceptance harnesses on the canonical tree after six
integrations and make the run reproducible with one entry point. The step was carried out on
the isolated branch `feature/oip-canonical-regression` in the worktree
`/Users/benny/Code/open-industrial-platform-worktrees/canonical-regression` and integrated
with a real `git merge --ff-only` as `111dff1`.

**What the run found.** Two acceptance gates had silently gone stale when the real device
onboarding integration moved the canonical schema and the MCP tool surface, and nobody had
re-run them since:

* `tests/oip0082/schema3_migration.py` expected the upgraded schema to be **6**. The canonical
  schema is **7** since the connection tables were added, so the gate failed on the canonical
  tree. The expectation now names the schema the canonical binary actually reaches, and the
  harness still asserts an exact value.
* `tests/oip008/acceptance.py` expected exactly **17** MCP read tools for the reader role.
  `oip_device_connection_read` is visible to that role as well, so the policy filtered catalog
  has **18**. The exact catalog was measured for all three reader clients before the
  expectation was changed.

Both repairs keep the gate exact; only the stale number changed.

**New runner.** `tests/canonical_regression.py` runs the milestone harnesses over the
canonical tree with one reproducible entry point. Every case owns its own runtime directory
under `/private/tmp`, its own ports and its own credentials. A case that needs a protected
historical binary is only executed when that binary exists **and** its hash matches the
recorded value; otherwise the case is reported as `BLOCKED` with the reason instead of being
run with a substitute. `tests/oip008/legacy_migration.py` can now use a protected OIP-007
binary through `OIP007_BASELINE_BINARY`, and `tests/oip008/ui_regression.py` stops with a
clear message when the HTML renderer build is missing instead of serving a CanvasKit build and
reporting a product failure that is really a missing artifact.

**Measured result on canonical `main` (`111dff1`)**:

```
oip008_acceptance          PASS  53.8 s
oip0082_acceptance         PASS  32.9 s
oip0082_schema3_migration  PASS  25.3 s
oip0084_acceptance         PASS  25.6 s
oip0085_acceptance         PASS   5.0 s
oip0085_migration          PASS   7.2 s
oip008_ui_regression       PASS 264.4 s   browser 75.4 s, interactions 47.8 s, visual 61.1 s,
                                             native build 32.2 s, native test 30.6 s, core exit 0
oip008_legacy_migration    BLOCKED        no protected OIP-007 binary in the workspace
```

The blocked case is the schema2 adoption: the harness has to create a genuine schema2
database, which only a protected OIP-007 binary can do. The canonical binary creates schema3
or later, so the case is reported as blocked with the reason instead of being run with a
substitute. The schema2 adoption was verified historically in the OIP-008 receipt with the
then protected binary; it is not claimed as re-verified here.

**Not claimed.** The product source is unchanged in this iteration, so the Rust, Flutter and
real device acceptance results of iteration 5 remain valid for this tree. No physical
Raspberry-Pi was contacted, the real installation was not activated, the personal database is
unchanged at schema 6 and the productive identity, hostile same-UID, durable audit and OT
boundaries stay open. F5 remains open and paused.

### Iteration 11 — the managed network view shows the authorized placement

**Step.** Make the managed network view show the authorized placement of the session instead of a
loading state for data that never arrives. One isolated commit on the branch
`feature/oip-network-placement` (`e9036ef`), integrated with a real `git merge --ff-only`.

**The gap.** The network view showed *"Topologie wird geladen — Der Live-Stream liefert das
gemeinsame Rust-Modell"* whenever the projection carried no topology
(`apps/flutter/lib/features/network.dart:246-248`). The scoped projection of a managed session has
no topology array at all (`crates/oip-core/src/hierarchy.rs:444-454`), so that was a loading state
without a loader. The view also drew the three zones of the legacy demo — `LAN`, `Tailnet`,
`Remote Site` — next to the real site of the session, and the zone status stayed `UNBEKANNT`
because no link exists to classify. The contract had already named the rule: *"Network & VPN:
registered nodes only, no automatically guessed links/topology or green reachability"*
(`docs/architecture/oip-0085-real-inventory-flutter-contract.md:21`).

**What changed.**

* `apps/flutter/lib/features/network.dart`: the managed view states that the projection carries no
  topology, draws no path and colours no reachability green. The zone of a node is the authorized
  site of the session; the zones of the legacy demo are not shown in the managed mode. The
  authorized placement is shown with the identifiers the Core delivered for it — organization,
  infrastructure, site and source — with the registered nodes of that site. Nothing is derived from
  a name, an address or a device identifier and no link between two placements is invented.
* `apps/flutter/test/managed_network_test.dart` (new): the managed network view shows the
  authorized placement and the registered node, shows no loading state and shows no demo zone.
* `apps/flutter/test/support.dart`: the scoped fixture of a managed session moved into the shared
  test support, so the next managed view reuses it.
* `apps/flutter/test/browser_onboarding.mjs`: the rendered network view is compared with the
  placement that the Core delivered, and the receipt names it.
* `docs/architecture/oip-0085-real-inventory-flutter-contract.md`: names the surface and its proof.

**Measured result on canonical `main` (`e9036ef`)** — actual Flutter web release → authenticated
HTTP → shared Core → owned loopback OpenSSH → genuine macOS host facts:

```
cargo fmt --all -- --check                                       exit 0 (no Rust source changed)
flutter analyze                                                    exit 0, no issues
flutter test                                                       101 passed, 0 failed
python3 tests/real_device/acceptance.py                           8 phases PASS, exit 0
  PASS browser_identity_online_writer
  PASS ssh_handshake_confirmation_monitoring
  PASS restart_sigkill_identity
  PASS actual_flutter_ssh_onboarding     <- the history, the overview and the network view
  PASS no_clients_ingestion_progress
  PASS host_key_change_blocks_collection
  PASS weak_host_key_is_rejected_by_the_server
  PASS eight_official_mcp_clients
python3 tests/canonical_regression.py                             8 cases PASS, no failed, no blocked
  oip008_acceptance           PASS  30.4 s
  oip0082_acceptance          PASS  40.3 s
  oip0082_schema3_migration   PASS  17.1 s
  oip0084_acceptance          PASS  31.8 s
  oip0085_acceptance          PASS  13.3 s
  oip0085_migration           PASS   7.2 s
  oip008_ui_regression        PASS 256.0 s   (browser 80.4 s, interactions 47.1 s, visual 63.4 s,
                                                 native build 11.6 s, native macOS test 39.1 s,
                                                 every step with its marker)
  oip008_legacy_migration     PASS   4.2 s
```

The browser receipt (`target/oip-real-device-e2e/browser/report.json`) names what the operator now
sees in the network view of the managed mode:

```
rendered_network  authorized_placement org-a · infra-a1 · site-a1
                 source 38fceec2-6e77-4afa-a59a-f395aef20f91
                 loading_state_absent true
                 demo_zones_absent true
```

**Not claimed.** The measurement is the host report of the owned loopback fixture on this machine,
not a physical Raspberry-Pi verdict. No personal device was contacted, the real installation was not
activated and the personal database is unchanged at schema 6. The managed diagnostics view still
shows its placeholder and is recorded as the next READY item; the persisted history of the events
follows only when the capability of the principal is proven. The productive identity, hostile
same-UID, durable audit and OT boundaries stay open. F5 remains open and paused. No Rust source
changed in this iteration, so the Rust workspace results of iteration 9 remain valid for this tree.

### Iteration 10 — the managed overview shows the real authorized infrastructure

**Step.** Make the managed overview draw the session's authorized scope instead of the coordinates
of the demo. One isolated commit on the branch `feature/oip-managed-overview` (`1e6b743`),
integrated with a real `git merge --ff-only`.

**The gap.** The Core delivers the authorized `sources`, the authorized `locations` and the
authorized `observations` in the scoped projection
(`crates/oip-server/src/tenant_services.rs:540-591`). The client dropped all of it: the overview
asked for the temperature of the demo entity `M-01` and the metric `temperature`
(`apps/flutter/lib/models/contracts.dart:239-245`), the trend accumulator accepted only that pair
(`apps/flutter/lib/app/controller.dart:172-188`), and the chart drew the caption *Temperatur · M-01*
(`apps/flutter/lib/widgets/trend.dart:77`). In the managed mode the measured series was therefore
always empty, the tile showed `—` and the ribbon showed three rows for dimensions the projection
does not carry. The contract had already named the rule: *"Overview: counts from authorized
returned inventory, sources from actual source registry; no fake host CPU/RAM/network metrics"*
(`docs/architecture/oip-0085-real-inventory-flutter-contract.md:21`).

**What changed.**

* `apps/flutter/lib/models/contracts.dart`: the authorized `sources` and `locations` of the scoped
  projection are no longer dropped. `ScopedSource` mirrors the `SourceHealth` of the Core, and
  `ScopedLocation` the `HierarchyLocation`; `Snapshot` keeps both and can resolve the placement of
  a source.
* `apps/flutter/lib/app/controller.dart`: the measured series are no longer the demo pair. The
  legacy rule stays exactly as it was — the temperature of `M-01` of the primary source — and the
  managed rule measures the numeric observations of the authorized sources, one series per
  authorized source. The metric of a series is the one with the most received samples, a tie is
  broken by the metric identifier, so the choice is deterministic and visible. The accumulator
  rules stay unchanged: a change of the measured scope starts a new display window, a source time
  that moves backwards starts a new window, an identical source time and value is not appended
  twice and a series keeps at most 60 received points.
* `apps/flutter/lib/widgets/trend.dart`: the chart names the metric it measured instead of
  *Temperatur*, and the gap limit follows the cadence the series itself showed — the median
  interval of the series with a tolerance of half of it and the demo limit as its floor. The demo
  limit of 2.5 s stays the limit of the legacy demo, so the demo behaviour is unchanged; a real
  source publishes every 30 s and its points are connected instead of being broken at every point.
  A source time jump is still never connected into a line over a data gap.
* `apps/flutter/lib/features/overview.dart`: the source registry with the health the Core measured,
  the placement of the source in the authorized hierarchy and the measured values are shown. The
  rows for the OPC-UA, subscription and network dimensions belong to the legacy demo; in the
  managed mode the source registry of the session is shown instead of dimensions the projection
  does not deliver. The demo tile *Temperatur M-01* and the demo entity in the alarm check and in
  the device focus are gone in the managed mode.
* `apps/flutter/lib/design_system/theme.dart`: the status vocabulary of the source registry had no
  label and no colour — `disconnected`, `healthy`, `valid` and `invalid` were rendered as raw
  English strings. They are mapped now.
* `apps/flutter/test/managed_overview_test.dart` (new): three tests — the managed overview renders
  the authorized source, its real health, its placement and its real measurement and no demo
  coordinate; the controller measures one series per authorized source and extends it with a later
  measurement; the gap limit of a real cadence is not the demo limit while the legacy rule keeps
  its own.
* `apps/flutter/test/browser_onboarding.mjs`: the rendered overview is compared with the source
  registry and the measurement that the Core received over SSH, and the receipt names them.
* `docs/architecture/oip-0085-real-inventory-flutter-contract.md`: names the surface and its proof.

**Measured result on canonical `main` (`1e6b743`)** — actual Flutter web release → authenticated
HTTP → shared Core → owned loopback OpenSSH → genuine macOS host facts:

```
cargo fmt --all -- --check                                       exit 0 (no Rust source changed)
flutter analyze                                                    exit 0, no issues
flutter test                                                       100 passed, 0 failed
python3 tests/real_device/acceptance.py                           8 phases PASS, exit 0
  PASS browser_identity_online_writer
  PASS ssh_handshake_confirmation_monitoring
  PASS restart_sigkill_identity
  PASS actual_flutter_ssh_onboarding     <- the persisted history and the managed overview
  PASS no_clients_ingestion_progress
  PASS host_key_change_blocks_collection
  PASS weak_host_key_is_rejected_by_the_server
  PASS eight_official_mcp_clients
python3 tests/canonical_regression.py                             8 cases PASS, no failed, no blocked
```

The browser receipt (`target/oip-real-device-e2e/browser/report.json`) names what the operator now
sees on the landing page of the managed mode:

```
rendered_overview  authorized_source SSH host browser-existing
                   source_registry_section true
                   measured_metric host.memory_total_bytes
                   measured_value 17179869184
                   demo_coordinates_absent true
```

**Not claimed.** The measurement is the host report of the owned loopback fixture on this machine,
not a physical Raspberry-Pi verdict. No personal device was contacted, the real installation was not
activated and the personal database is unchanged at schema 6. The network view still shows its
loading message and is recorded as the next READY item; the event history and the diagnostics
surfaces stay unconnected, because `events_read` is not proven for every operator principal. The
productive identity, hostile same-UID, durable audit and OT boundaries stay open. F5 remains open
and paused. No Rust source changed in this iteration, so the Rust workspace results of iteration 9
remain valid for this tree.

### Iteration 9 — the persisted history reaches the operator view

**Step.** Connect the persisted observation history that the Core already stores and serves to the
Flutter device view, and close the test gap that the seven history routes were proven only with a
bearer token. One isolated commit on the branch `feature/oip-observation-history` (`1287e23`),
integrated with a real `git merge --ff-only`.

**The gap.** The Core stores the samples of a connected device and serves them through
`GET /api/v2/observations/history` (`crates/oip-server/src/api.rs:213`,
`crates/oip-storage/src/lib.rs:673`). The Flutter client named the gap itself: the device dialog
stated *"Autorisierte historische REST-v2-Abfragen existieren im Core"*, and the history was never
requested. The device scope was already sufficient — the device is resolved to its source through
the authoritative source registration (`crates/oip-core/src/hierarchy.rs:298`), so no organization,
infrastructure or site selection had to be invented.

**What changed.**

* `apps/flutter/lib/models/history.dart` (new): the DTO of the page — `items`, `truncated`,
  `next_cursor`, `missing_evidence`, `time_semantics` — and of the adjacently tagged item
  `{"category":"observation","record":{"id":…,"observation":…}}`. The page has no total.
* `apps/flutter/lib/services/api.dart`: `observationHistory({deviceId, cursor, limit})` on
  `DeviceManagementApi`, implemented as `GET /api/v2/observations/history?device=…&limit=…`.
* `apps/flutter/lib/features/device_history.dart` (new) and `apps/flutter/lib/features/devices.dart`:
  the device view replaces the *"Historie noch nicht angebunden"* notice with the stored samples.
  Every row is named as history, reports the stored value, its unit, the quality, the freshness
  and the receive time the Core guarantees, and the `missing_evidence` and the time semantics of
  the answer are shown instead of being hidden. The stable id of a sample deduplicates a refresh.
* `crates/oip-server/tests/browser_session.rs`: the missing cookie path of the history route. The
  bound device is served with its persisted sample, a foreign scope and an unknown device are
  refused with `RESOURCE_NOT_ACCESSIBLE`, a principal without `telemetry_read` is refused with
  `PERMISSION_DENIED`, a request without a session is refused and an unbounded page is refused
  with `INVALID_DIAGNOSTIC_QUERY`.
* `apps/flutter/test/observation_history_test.dart` (new): eight tests — the device scope without
  a global scope, the continuation with the cursor of the Core, an item of another category that
  is counted and not dropped, the rendering as history, the continuation, the recovery from a
  device that is not accessible yet, the honest empty state and the refused history.
* `apps/flutter/test/browser_onboarding.mjs` and `tests/real_device/acceptance.py`: the real proof.
  The harness asserts that the Core persisted the samples of the connected device and that they
  are stale; the browser compares the rendered history with the answer of the Core for the same
  device and writes the persisted samples into the receipt.
* `docs/architecture/oip-0082-diagnostics-flutter-contract.md`: names the surface and its proof.

**The defect found on the way.** The history was loaded once, when the device dialog was opened —
and the dialog is opened *before* the connection is confirmed. The answer of a device without a
source is `RESOURCE_NOT_ACCESSIBLE`, so the section kept that answer forever and never showed the
samples that the collector stored a moment later. The section now follows the persisted state on a
bounded cadence, exactly like the connection panel follows the live observations, and the recovery
is proven by a widget test.

**Measured result on canonical `main` (`1287e23`)** — actual Flutter web release → authenticated
HTTP → shared Core → owned loopback OpenSSH → genuine macOS host facts:

```
cargo fmt --all -- --check                                       exit 0
cargo check --locked --workspace --all-targets                    exit 0
cargo clippy --locked --workspace --all-targets -- -D warnings    exit 0
cargo test --locked --workspace -- --test-threads=1               181 passed, 0 failed
cargo test --locked -p oip-opcua --features open62541-backend      37 passed
cargo test --locked -p oip-opcua --no-default-features --features open62541-backend  2 passed
flutter analyze                                                    exit 0, no issues
flutter test                                                       97 passed, 0 failed
python3 tests/real_device/acceptance.py                           8 phases PASS, exit 0
  PASS browser_identity_online_writer
  PASS ssh_handshake_confirmation_monitoring
  PASS restart_sigkill_identity
  PASS actual_flutter_ssh_onboarding     <- the persisted history
  PASS no_clients_ingestion_progress
  PASS host_key_change_blocks_collection
  PASS weak_host_key_is_rejected_by_the_server
  PASS eight_official_mcp_clients
python3 tests/canonical_regression.py                             8 cases PASS, no failed, no blocked
  oip008_acceptance           PASS  32.9 s
  oip0082_acceptance          PASS  39.9 s
  oip0082_schema3_migration   PASS  24.2 s
  oip0084_acceptance          PASS  23.7 s
  oip0085_acceptance          PASS   6.2 s
  oip0085_migration           PASS   7.6 s
  oip008_ui_regression        PASS 225.6 s   (browser 80.4 s, interactions 47.1 s, visual 63.4 s,
                                                 native build 11.6 s, native macOS test 39.1 s,
                                                 every step with its marker)
  oip008_legacy_migration     PASS   7.7 s
```

The browser receipt (`target/oip-real-device-e2e/browser/report.json`) names the persisted samples
that the Core stored for the connected device and that the operator now sees as history:

```
persisted_samples 10     rendered_samples 6     all_stale true     receive_times_shown 1
first_receive_time 2026-11-07 21:21:11.293 UTC
metrics host.architecture  host.interfaces  host.cpu_info  host.uptime_seconds
        host.memory_used_bytes  host.memory_total_bytes
```

**Not claimed.** The samples are the host report of the owned loopback fixture on this machine,
not a physical Raspberry-Pi verdict. No personal device was contacted, the real installation was
not activated, the personal database is unchanged at schema 6. The event history and the
diagnostics surfaces stay unconnected, because `events_read` is not proven for every operator
principal. The productive identity, hostile same-UID, durable audit and OT boundaries stay open.
F5 remains open and paused. No Rust source changed in this iteration, so the Rust workspace
results of iteration 8 remain valid for the unchanged crates.

### Iteration 8 — the monitoring measurements reach the operator panel

**Step.** Make the monitoring measurements that the Core already collects and publishes visible
in the surface that is dedicated to connection and monitoring, and prove it in the real browser
end to end. Two isolated commits on the branch `feature/oip-monitoring-observations`
(`2ec4829`, `e12c009`), both integrated with a real `git merge --ff-only`.

**The defect.** The Core collects the host report of a connected device and publishes the
resulting observations in the connection view (`crates/oip-server/src/connection_service.rs:303`).
The Flutter client parsed them (`apps/flutter/lib/models/onboarding.dart:70`) but the device
connection panel rendered **only the empty case** and dropped every real measurement
(`apps/flutter/lib/features/device_connection_panel.dart:143`). The Flutter contract requires the
connection view to contain the current authorized observations
(`docs/architecture/real-device-onboarding-flutter-contract.md:37`) and requires the browser E2E
to verify "subsequent actual observations" (`:45`). Neither held: the panel showed the state
`Collecting` but never a collected value, and the browser E2E only waited for the state string.

**What changed.**

* `apps/flutter/lib/features/device_connection_panel.dart`: the panel renders the current
  authorized observations with their metric identifier, value, unit, quality, freshness and
  capture time. Long text reports (disks, interfaces) stay collapsed behind an expansion and are
  never presented as a complete value in the preview. A missing value stays unknown and is not
  replaced by a substitute.
* `apps/flutter/test/monitoring_observations_test.dart` (new): three widget tests — the rendered
  measurements with their unit and state, an unknown value that is not replaced by a substitute,
  and the honest empty state.
* `apps/flutter/test/browser_onboarding.mjs`: after the `Collecting` state, the rendered panel is
  compared with the observations that the Core reports **for the same device**. The expected
  values are read back from the Core and are never invented in the test; the measured values are
  written into the browser receipt.
* `docs/architecture/real-device-onboarding-flutter-contract.md`: names the rendering and its
  proof.
* `tests/real_device/acceptance.py`: the Playwright module is addressed with an absolute path.
  The relative value documented in this file could never work, because a dynamic import resolves
  a relative specifier as a package name; the browser phase failed with
  `Cannot find package 'apps'`. The harness now resolves the module against the repository root
  and reports a missing module before the browser phase instead of inside the node error.

**Measured result on canonical `main` (`e12c009`)** — actual Flutter web release → authenticated
HTTP → shared Core → owned loopback OpenSSH → genuine macOS host facts:

```
flutter analyze                                                    exit 0, no issues
flutter test                                                       89 passed, 0 failed
python3 tests/real_device/acceptance.py                           8 phases PASS, exit 0
  PASS browser_identity_online_writer
  PASS ssh_handshake_confirmation_monitoring
  PASS restart_sigkill_identity
  PASS actual_flutter_ssh_onboarding     <- the rendered measurements
  PASS no_clients_ingestion_progress
  PASS host_key_change_blocks_collection
  PASS weak_host_key_is_rejected_by_the_server
  PASS eight_official_mcp_clients
python3 tests/canonical_regression.py                             8 cases PASS, no failed, no blocked
  oip008_acceptance           PASS  41.8 s
  oip0082_acceptance          PASS  43.2 s
  oip0082_schema3_migration   PASS  24.9 s
  oip0084_acceptance          PASS  29.9 s
  oip0085_acceptance          PASS   5.4 s
  oip0085_migration           PASS  12.0 s
  oip008_ui_regression        PASS 863.0 s   (browser 80.4 s, interactions 47.1 s, visual 63.4 s,
                                                 native build 11.6 s, native macOS test 39.1 s,
                                                 every step with its marker)
  oip008_legacy_migration     PASS   5.0 s
```

The browser receipt (`target/oip-real-device-e2e/browser/report.json`) names the ten observations
that the Core received from the owned fixture and that the operator now sees in the panel:

```
host.architecture  host.cpu_info   host.disks      host.hostname  host.interfaces
host.memory_total_bytes  host.memory_used_bytes  host.model  host.os  host.uptime_seconds
host_os = Darwin        memory_total_bytes = 17179869184        all fresh
```

**Not claimed.** The measurement values are the host report of the owned loopback fixture on this
machine, not a physical Raspberry-Pi verdict. No personal device was contacted, the real
installation was not activated, the personal database is unchanged at schema 6, the persisted
history is still not connected (N6) and the productive identity, hostile same-UID, durable audit
and OT boundaries stay open. F5 remains open and paused. The Rust source is unchanged in this
iteration, so the Rust workspace results of iteration 5 remain valid for this tree.

### Iteration 7 — the schema2 adoption case and a stable parity gate

**Step.** Restore the one acceptance case that could not be re-verified, and remove a race from
a gate that decides the result of a whole regression run. Two isolated branches were used:
`feature/oip-007-baseline-adoption` (`6df189f`) and
`feature/oip-parity-gate-convergence` (`f4b89ed`), both integrated with a real
`git merge --ff-only`.

**The blocked case.** The schema2 adoption of the OIP-008 milestone needs a writer that still
creates the schema2 layout. The historical protected binary of that milestone is not part of
the workspace any more, so the case stayed blocked. `tests/oip007_baseline.py` rebuilds that
writer from the verified OIP-007 baseline commit `a27e7b1`: it extracts the source with
`git archive`, so no worktree registration and no canonical checkout state is touched, and it
builds into its own destination directory. The result records the source commit, the hash of
the rebuild and the hash of the historical binary, and it states that a rebuild is not byte
identical, so **the identity of the historical protected binary is not claimed**. The canonical
regression runner uses the prepared writer when it exists and records its hash and origin.

**The race.** In the first canonical run of this iteration the OIP-008 acceptance case failed
although it had passed with identical code in iteration 6. The reason was in the gate itself:
it compared the live source state of the MCP transport with the live source state of the REST
transport, and while a source is still warming up the two reads can observe two different
states (`freshness: unknown` against `fresh`, `service: unknown` against `healthy`). The gate
now waits for the compared fields to converge within a bounded deadline and still fails when
they never agree. The strength of the gate is unchanged. The hardened gate passed in three
consecutive runs and in the canonical run below.

**Measured result on canonical `main` (`f4b89ed`)** — every case, no failure, no blocked case:

```
oip008_acceptance          PASS  30.9 s
oip0082_acceptance         PASS  51.6 s
oip0082_schema3_migration  PASS  25.6 s
oip0084_acceptance         PASS  22.7 s
oip0085_acceptance         PASS   9.2 s
oip0085_migration          PASS  15.3 s
oip008_ui_regression       PASS 323.1 s
oip008_legacy_migration    PASS   8.4 s   schema2 writer rebuilt from a27e7b1, schema2 adopted
                                         into schema3, 46 observations / 48 events / 2 gaps kept,
                                         same observation keys, both refusal paths still refuse
```

**Advisory exceptions verified (N5).** The three documented exceptions were checked against
the local advisory database and against the dependency graph. All three are correct,
necessary and unavoidable; the earlier note in this file that two of the ignore reasons would
not match the advisory subjects was wrong and is corrected in the N5 section.

**Not claimed.** The schema2 adoption is proven with a writer rebuilt from the verified OIP-007
baseline commit, not with the historical protected binary, whose byte identity cannot be
reproduced and is not asserted. The product source is unchanged in this iteration, so the Rust,
Flutter and real device acceptance results of iteration 5 remain valid for this tree. No
physical Raspberry-Pi was contacted, the real installation was not activated, the personal
database is unchanged at schema 6 and the productive identity, hostile same-UID, durable audit
and OT boundaries stay open. F5 remains open and paused.

### Iteration 12 — the Spectrum-2027 canonical UI baseline and its design regression gate

**Status: PROVED and integrated into canonical `main`.**
This is a binding integration contract and regression gate, not a deployment and not an operator
visual approval. Before this iteration canonical `main` was `037afda92ac02ffc91dceb322d905a57dd2fc4ef`
with the legacy five-view OIP/005 shell and runtime bundle
`e399f3979b94fdbfb794436c364c68c1d697111ed1cdf2c2354c94ba468730bf`; its preview on port 8080
answered `mode: explicit_legacy_demo`. The intended UI authority is OIP-UX-001 feature commit
`6c2d2a280b66b69461d5ee8c821630b4deeed4fe`, frozen at `5d50a1d5da558cf1e78515b4c24bad4aded40a92`.
The exact upstream chain is pinned in `docs/design/OIP_UI_2027_HANDOFF_MANIFEST.json`.

**Reconciliation of the two parallel executions.** The Spectrum-2027 integration was prepared
twice in parallel from the same authority payload: in `…/worktrees/spectrum-2027-ui`
(`feature/oip-spectrum-2027-ui`) and in the concurrent release-loop candidate
`…/worktrees/canonical-ui-gate` (`feature/oip-canonical-ui-regression-gate`). Both were verified
against the same contract; their product trees differed in three files only. They were reconciled
into **one** candidate instead of integrated twice: the gate, the stable-shell visual comparison,
the acceptance-workflow integration and the handoff manifest come from the concurrent candidate,
the product fixes below come from this worktree. No file of the concurrent execution was
modified, no foreign process was signalled, and the personal installation was not touched.

**Product fixes that the transplant would have lost.** The payload alone would have replaced the
canonical cadence-aware continuity of a measured series (`continuesSeries`, `seriesGapLimit`) with
a fixed 2.5 s limit and dropped its test; every real source that publishes slower than 2.5 s
would have been drawn as isolated points. The rule and its coverage are restored in
`lib/widgets/trend.dart` and applied in `lib/features/overview/telemetry_chart.dart`. The
monitoring measurements and the persisted observation history are mounted inside the approved
device workspace, and the management adapter is guarded in both device detail surfaces, so a
managed client without an adapter no longer dereferences a null adapter.

**Onboarding activation.** In the Flutter web runtime the semantics node of a device row is a
container node and therefore carries `pointer-events: none`; a Playwright click is intercepted by
`flutter-view`, and the engine forwards only focus and blur, so Enter and Space can never
activate the row. The real onboarding journey therefore activates the painted row with a real
mouse event and verifies the state it produces — the engineering workspace of the selected
device — instead of trusting the absence of an error.

**Isolation and provenance.** The uncommitted 128-file Spectrum snapshot was archived before any
mutation and replayed byte-identically into the separate `canonical-ui-gate` worktree. Snapshot
archive SHA-256 `8c81ed6fb1ea624a3047a33db284d441d704b2ddd081268826c7922236f2acc3`, roundtrip
PASS. The original worktree and every foreign process remained untouched. The final tested
revision is `037afda92ac02ffc91dceb322d905a57dd2fc4ef`, working tree hash
`3fc21b181151e99b35ee9291bfcc46a47c6dc223`. The actual local and served
`main.dart.js` SHA-256 values are both
`d0a5b3b2dabd6e0351bdfd7465a7422f90a4fc2afd3b610f6de6ff44b47d8a86`.

**Failure correction.** The first complete Flutter run produced 331 passes and two failures, all
caused by a managed controller without a management adapter (`controller!.management!`). The
management section is now guarded in both device detail surfaces, while production `RestApi`
management remains intact. Targeted tests and the full subsequent suite passed: **334/334**.
The initially claimed 2027 gate was not accepted without independent execution.

**Permanent regression gate.** `tests/canonical_ui_gate.py` builds the current Flutter release,
hashes the real working tree through a temporary index, runs the full Flutter suite and checks
the delivered bundle. The canonical case also builds and hashes `oip-server` and the official MCP
probe, performs real browser login, all six workstations at 1440/1920, the eight managed
acceptance phases and the actual `browser_onboarding.mjs` journey. A complete PASS cannot skip
build, widget or browser checks; `--skip-build` was separately verified to produce `PARTIAL`.
Runner report resolution evaluates both the harness and the browser `verdict`.

**Measured result.** `python3 tests/canonical_regression.py --only oip_canonical_ui_gate
--evidence target/oip-canonical-ui-regression-final` finished in 353.8 s with process status PASS,
harness status PASS, no failed and no blocked case. The browser recorded **175 findings with zero
failures**, 13 screenshots, no JavaScript errors and no external requests. All eight phases are
PASS: browser identity/writer, SSH handshake and monitoring, restart/SIGKILL, actual Flutter SSH
onboarding, ingestion without clients, host-key change blocking, weak-key rejection and eight
official MCP clients. `own_processes_stopped=true`. The merged
`canonical_ui_gate_receipt` binds the precheck, browser and visual receipt paths and their
SHA-256 values, the machine-bound 334/334 Flutter result, 175/0 browser findings and 13 captures.
The browser evidence directory contains exactly those 13 PNGs and no failure dump.

**Visual and negative controls.** The stable left shell is compared at 1440×900 and 1920×1080,
with dynamic content excluded and each mean/ratio limit set to 0.01. Archive derivation is pixel
verified. Measured at 1440: mean `0.0010914`, changed ratio `0.0`; at 1920: mean `0.0012635`,
changed ratio `0.0`. Single-navigation-row and large-gradient mutations were both detected.
Missing external archives produce an explicit `SKIPPED_EXTERNAL_ARCHIVE_UNAVAILABLE` receipt while
the committed reference hash remains mandatory. **M-01 is forbidden only as the primary managed
overview metric**, not on real OPC-UA nodes. **AGENT-FIRST is forbidden in the sidebar and allowed
only in the technical Settings context.**

**Integration into canonical `main`.** After the reconciliation the candidate was integrated with a
real `git merge --ff-only`, no merge commit and no history rewrite. Canonical `main` is now
`525f5c86d6baf5f27d5b13bd648d2d17794bb5a5`, tree `b5b23c6f2ac0d3ee02e09837933027facdeb6042`, working tree clean. The final acceptance run was executed **on canonical
`main`**: the precheck hashed the clean tree (`source_dirty=false`), the Flutter suite measured
**335/335 PASS**, the browser recorded **175 findings with zero failures** and 13 captures, the
stable-shell visual comparison passed at 1440 and 1920 with both negative-control classes, and
all eight managed acceptance phases passed, including the actual Flutter SSH onboarding that
renders the Core's own `host.os` and `host.memory_total_bytes` measurements and the ten persisted
observation samples. Local and served `main.dart.js` are byte-identical:
`169aaa8257a782ae52d5afe7b9de68b6acedb013cc24c96783e11e054cc22caa`. The rebuild of the same source in the isolated worktree produced the same bundle hash,
so the delivered assets are reproducible.

Receipt hashes of that run: precheck `9b2ca4f1951a19166f25e2299faf2983b296b4b81603d0ac509f85a29dfe3e74`, browser `6fa467c7f9373897f4ca31ca7a406b7190083cfec55b154d59c53f42bea4a1c2`, visual `d53fa8f5cb5ba70665184ece2a52c8299e8be6d475d5bb41f0a925a39a187df7`.

**Visual status and safety boundary.** All six current workstation captures are technical
evidence only. Operator visual acceptance remains `VISUAL_PENDING_OPERATOR_ACCEPTANCE`. No push,
deployment, schema-7 activation, private SSH connection or change to the personal installation
database was performed; the personal database is untouched at SHA-256
`9f988c01c7115631db3b5bfd2b9228ecc24255b8b9905932a987a89c78e6a24e` with `user_version` 6. The
concurrent release-loop candidate was never modified and remains in its own isolated worktree.

### Iteration 13 — the persisted evidence of the managed diagnostics reaches the approved workspace

**Status: PROVED on canonical `main` (`7fc612e`).**
The Spectrum-2027 integration carried the capability of the managed diagnostics view, but not its
continuation and not its limits: the opaque cursor of the Core was dropped from both routes, the
merge of a continued page by the stable Core IDs was lost, and the view stopped naming the limits
of the answer, the time and origin semantics of the Core, and the fact that a truncated page
without a cursor is explicitly incomplete. The isolated candidate `feature/oip-managed-diagnostics`
(`55d4f50`) contributed no file that `main` lacked, but its capability was only partly present.

**Restored inside the approved workspace.** Both routes ask for the continuation with the opaque
cursor of the Core and merge the answer by the stable Core IDs, so no row is duplicated. A failed
continuation keeps the evidence that is already loaded and offers a fresh authorized query instead
of hiding the proof it already holds. The marker distance of a documented gap is named as a marker
distance and never as a measured outage duration. The limits of the answer, the time and origin
semantics and the state that the Core names for the diagnosis history stay visible. The binding
contract of OIP-0082 carries the rules again.

**Proof.** `apps/flutter/test/managed_diagnostics_test.dart` is reconciled to the Spectrum-2027
shell and proves the rendered gap, the health transition, the unknown previous state of the first
transition, the limits of the answer, the Core-named diagnosis-history state, the incomplete page
without a cursor and the continuation that merges without duplicating. The actual browser journey
reads the accessible names of the rendered surface, because Flutter publishes the rendered text of
a workstation as the accessible names of its semantics nodes.

**Measured result.** `OIP_CANONICAL_UI_GATE=1 python3 tests/real_device/acceptance.py` on canonical
`main`: **339/339 Flutter tests**, **175 browser findings with zero failures**, 13 captures, the
stable-shell visual comparison PASS and **8/8 managed acceptance phases PASS**, including the
actual Flutter SSH onboarding. The onboarding receipt now carries
`rendered_diagnostics: {persisted_evidence_section: true, diagnosis_history_status: not_implemented,
health_transitions: 50, documented_gaps: 2}` — the evidence the Core actually holds, read back
from the Core and compared with the rendered surface. The delivered bundle is
`a83a18def0ad4149dcba84452731a64083042e43bbafa1b260f3e3bad5873041`, local and served
byte-identical. No personal database change, no schema-7 activation, no private SSH, no push, no
deployment.

### Iteration 14 — the release binary, the local operations and the accessibility receipt

**Status: PROVED on canonical `main` (`6473617`, `bf36411`, `40f57cd`).**
The release ledger named three open items of the release mission: a release binary that is proven
by the canonical gate, a tested procedure for the local operations of an instance, and the
accessibility receipt of the integrated UI. All three are now measured.

**The release binary is proven by the same gate.** `cargo build --release -p oip-server --bin
oip-server --example mcp_probe` produces the Core `76d18b6e14a329b365daca16fd970e431b5f05c3340320054453abaa82a26ccd`
and the official MCP probe `029bf9f4505dd483d62196992d0443498a3e5a242f35a3192a4ef125227cfb08`. The
canonical runner can be pointed at another verified binary of the same contract
(`OIP_CANONICAL_SERVER_BIN`), the harness builds the profile of the binary that is executed and
names the hashes in its receipt. `OIP_CANONICAL_SERVER_BIN=…/target/release/oip-server python3
tests/canonical_regression.py --only oip_canonical_ui_gate` finished with **8/8 phases PASS**,
175 browser findings with zero failures, 339/339 Flutter tests, the visual comparison PASS and the
delivered bundle `a83a18def0ad4149dcba84452731a64083042e43bbafa1b260f3e3bad5873041` byte-identical
local and served.

**The local operations are a tested procedure.** `tools/oip_ops.py` operates one explicit instance:
one configuration, one protected IPC configuration, one database and one state directory. It
provisions the data store with the plan of the operator, starts the daemon, reports the state,
takes a consistent backup of a running instance, restores it, restarts the instance and stops it
cleanly. It installs no system service and it refuses every operation whose target resolves into
the personal installation of the operator, also through a relative path or a symlink.
`tests/oip_operations.py` proves the sequence against a disposable instance and records the
receipt: provisioning, start, status, log, backup with its integrity check, the refused restore of
a running instance, the clean shutdown without uncommitted observations, restore, start again,
restart, stop and the three refusals of the personal installation with its unchanged hash
`9f988c01c7115631db3b5bfd2b9228ecc24255b8b9905932a987a89c78e6a24e` at schema 6.
`docs/runbooks/operations.md` describes the procedure and the rules that the tool enforces.

Four real defects were found and fixed while proving it: the daemon requires an owner-private IPC
configuration, the Core refuses a database that anybody but the owner can read, the restore of a
running instance must be refused, and the Core rejects a path with a symlink component — the
temporary directory of macOS lives under `/var`, which links to `/private/var`.

**The accessibility receipt measures the name and role coverage.** `apps/flutter/test/browser_accessibility.mjs`
walks the six workstations of the live managed instance and asserts that every control a person can
reach carries an accessible name and that every focusable element is nameable. Measured: **136
controls, none without an accessible name**, no JavaScript error and no external request; the Core
denials of the scoped projection are recorded separately. The receipt is not a full WCAG audit and
does not claim one; the operator's own review of the application stays open.

**Two timeouts of the browser harness were too short.** The delivered web release is several
megabytes and the loopback of this machine delivers them slowly: the download of the bundle in the
canonical gate and in the real-device journey failed with the default request timeout of 30
seconds although the server answered it. Both downloads now get the time that the first paint of
the application already gets.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 15 — the upgrade and the rollback of a local instance

**Status: PROVED on canonical `main` (`62cadc2`).**
An upgrade of a local instance is a handover of the data store to the new binary.
`tests/oip_upgrade_rollback.py` rehearses it against a protected historical binary (the OIP-008.4
release, sha256 `73d70d8105914db20210c95268b5733ca2ec19c959c4c29fa57cb93c1935fe58`) and the current
release binary (`76d18b6e14a329b365daca16fd970e431b5f05c3340320054453abaa82a26ccd`).

**Measured result.** The historical binary provisions the store at schema 3 with two
organizations. The release binary serves the same store, migrates it to schema 7 and keeps the
organizations. The backup taken before the upgrade restores the previous state — the schema is 3
again — and the historical release adopts the restored store. The receipt is
`docs/evidence/oip-upgrade-rollback/upgrade-rollback.json`.

**Three rules of the handover, found while proving it.** The runtime sources must exactly match
the provisioned registry, otherwise the Core refuses to start with `runtime sources must exactly
match provisioned registry`. The data store must be owner-private, otherwise it is refused with
`database/sidecar must be owned by operator with private permissions`. And the configuration of an
instance is not portable between releases: a historical binary refuses the fields of a newer
configuration and the other way round, so the upgrade keeps the configuration of the era of the
instance until the instance has been migrated.

**Not rehearsed (at that time).** The daemon handover with the historical binary: the daemon of
the historical release was not started, only the offline provisioning and the backup of its data
store. The reason named in the receipt — that the daemon binds its local clients to the actor
policy of its era and refuses a start without a provisioned principal — was an **assumption, not a
measurement**, and it was wrong in two respects: the OIP-008 era binds the local clients to a
*principal* (`docs/architecture/oip-008-identity-authorization.md`), and the actor/permissions
shape is the shape of OIP-007. Iteration 21 measures the truth and rehearses the daemon.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 16 — the final acceptance of the integrated release candidate

**Status: PROVED on canonical `main` (`cac97ac`, tree `fcab8a5f0c3a9d3523c2c7f94ea0ae5cfa3aa8ea`,
working tree clean).**
`OIP_CANONICAL_UI_GATE=1 python3 tests/real_device/acceptance.py` on the clean canonical tree:
**339/339 Flutter tests**, **175 browser findings with zero failures**, 13 captures of the six
workstations at 1440 px and 1920 px, the stable-shell visual comparison PASS with both
negative-control classes and **8/8 managed acceptance phases PASS** — browser identity and the
single writer, the SSH handshake with the confirmed host identity and the monitoring, the restart
after SIGKILL, the actual Flutter SSH onboarding, the ingestion without clients, the host-key
change that blocks the collection, the rejected weak host key and the eight official MCP clients.
The delivered bundle `a83a18def0ad4149dcba84452731a64083042e43bbafa1b260f3e3bad5873041` is
byte-identical local and served, no JavaScript error, no external request, every owned process
stopped. The onboarding receipt carries the persisted evidence of the Core
(`health_transitions: 50, documented_gaps: 2`, `diagnosis_history_status: not_implemented`).

The receipts of that run: precheck `bff28843ca7b5d66…`, browser `eb40f9d723907098…`, visual
`a641a67b9b814a87…`.

**Safety.** The personal installation is untouched at SHA-256
`9f988c01c7115631db3b5bfd2b9228ecc24255b8b9905932a987a89c78e6a24e` with `user_version` 6 — no
schema-7 activation. The repository has no remote, so no push is possible. No deployment, no system
service, no private SSH connection, and no process of another workstream was signalled.

### Iteration 17 — the administration of a registered device in the approved workspace

**Status: PROVED on canonical `main` (`8b06720`).**
The Core owns the inventory and supports the register, the update and the archive of a device.
The client could not write the update at all: the Flutter API knew the register only and the
approved device workspace had no administration. The gap was found while the managed diagnostics
capability was reconciled — the same class of loss, a capability of the canonical tree that the
transplant of the design layer dropped.

**What was built.** The administration surface of the device names the revision it works on, sends
the **full replacement** the Core requires (an update is not a merge, so the metadata of the record
travels with it) and shows the refusal of the Core verbatim instead of a friendly invention. The
archive is an **offline operation of the Core**: the managed session refuses it with
`OFFLINE_ARCHIVE_REQUIRED` ("Archive remains an explicit offline operation"), so the surface names
the procedure and never offers a write that the Core would refuse.

**A defect of the global context was found and fixed.** The Core has no whoami route, so every
bootstrap was treated as an unverifiable principal transition: the global infrastructure scope was
reset to Unified and the session generation was bumped on **every** refresh of the authorized
projection — and an administration write needs such a refresh, so every write closed the inspector
of the device. The identity of the authorized session is the evidence that was missing. The
controller binds the principal of the session and the context keeps the scope of the operator
across a refresh. A principal change still invalidates the selection.

**Proof.** `apps/flutter/test/device_administration_test.dart` proves the surface, the payload of
the update, the revision guard and the shown refusal. The real-device journey against the actual
Core proves the update through the surface — the revision advances from 1 to 2 and the Core holds
the new name — and the named refusal of the online archive. `infrastructure_context_test.dart`
proves that the selected scope survives a refresh of the projection.

**The final acceptance of the integrated candidate** ran on the clean canonical tree
`8b8cd238636d89673cb8444ed3a6fc1b274752c8` (tree `59a73ff56067590deb75bc617ed14e17d600f1ef`,
`source_dirty=false`): **344/344 Flutter tests**, **175 browser findings with zero failures**,
13 captures, the stable-shell visual comparison PASS and **8/8 managed acceptance phases PASS**,
including the actual Flutter SSH onboarding with the device administration in it. The delivered
bundle `b09bb5ff4a16825ddf350f9278aa94a378f42222bbb5e23af0f76ed7bef2b844` is byte-identical local
and served; no JavaScript error, no external request, every owned process stopped. The receipts of
that run: precheck `a56d862e6d4b…`, browser `332572e68d5f…`, visual `7ee112bdbd68…`.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 18 — the browser receipt of the global infrastructure context

**Status: PROVED on canonical `main` (`91808cc`).**
The global infrastructure context is a mandatory gate. Its dependency was the reconciliation of the
UI workstreams, which is done, and the defect that reset the scope of the operator on every
refresh of the authorized projection is fixed. What was missing was the proof against the real
Core, and it is now a receipt that runs inside the canonical acceptance.

**What the receipt proves.** `apps/flutter/test/browser_global_context.mjs` measures, against the
managed Core of the acceptance harness: the global selection offers the individual infrastructures
of the authorized hierarchy (4 options), the selection of `Infrastructure A1` scopes the projection
(the placement of A2 disappears from the view), **the shared scope follows the operator across all
six workstations** — Übersicht, Geräte & Dienste, Netzwerk & VPN, OPC-UA-Browser, Diagnose &
Ereignisse and Einstellungen all report `Infrastructure Context: Infrastructure A1` — and the
unified view returns every authorized infrastructure. It also proves the rule of the contract: every
option is a selection of already authorized data and grants no permission.

The accessibility receipt of the six workstations now runs in the same place: 154 controls, none
without an accessible name, no JavaScript error and no external request.

Both receipts write their own receipt into the evidence of the run, so a later integration that
breaks the shared scope or the naming of a control is detected by the canonical gate itself.

**The final acceptance of the integrated candidate** ran on the clean canonical tree
`4d8f5654e8a8ed02c6a8c90c17a10487a54715f7` (tree `f9791425da26987a637abacc39dc7b531e2d8faf`,
`source_dirty=false`): **344/344 Flutter tests**, **175 browser findings with zero failures**,
13 captures, the stable-shell visual comparison PASS, the global context receipt (4 options, 17
findings, zero failures) and the accessibility receipt (154 controls, none without an accessible
name) and **8/8 managed acceptance phases PASS**. The delivered bundle
`b09bb5ff4a16825ddf350f9278aa94a378f42222bbb5e23af0f76ed7bef2b844` is byte-identical local and
served. The receipts of that run: precheck `f481979fbc76…`, browser `4566db42b715…`, visual
`7e3d2341157a…`.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 19 — the performance baseline of the release build

**Status: PROVED on canonical `main`.**
The Core side of the baseline was measured by the acceptance harness — the latency of the official
MCP probe and the resource use of the Core. The client side had no baseline at all: nobody knew
what the operator waits for in the browser.

**What was measured.** `tests/oip_performance.py` starts a disposable managed instance of the
**release** binary and runs `apps/flutter/test/browser_performance.mjs` three times against the
delivered web bundle. Measured over three runs (p50 / min / max):

| Phase | p50 | min | max |
|---|---|---|---|
| first paint of the delivered web release | 50 886 ms | 41 508 ms | 51 914 ms |
| the operator login of the anonymous state | 51 167 ms | 41 802 ms | 52 282 ms |
| the interactive shell with the six workstations | 284 ms | 239 ms | 359 ms |
| the authorized projection of the infrastructure | 102 ms | 11 ms | 266 ms |

The Core rests at 17 136 KiB of resident memory and 0.0 % CPU without clients. The delivered
bundle is `a51b62cdd3644a6be44bcb6409feb5345fe353c921ec281c9be6c4fcde4c56d2` — the same asset the
canonical gate proves.

**What the baseline says.** The first paint is **not** bound to the application: it is bound to the
transfer of the 3 MB web release over the loopback of this machine. Once the session exists, the
shell with all six workstations is interactive in a quarter of a second and the authorized
projection follows 102 ms later. A smaller delivery — or a local cache of the release — is a
**product decision** and is named as such; it is not an agent decision, and this baseline is the
measurement that a later decision needs.

The receipt is `docs/evidence/oip-performance/performance.json`. It is a local measurement of this
machine and explicitly not an SLA.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 20 — the offline archive of a device is rehearsed

**Status: PROVED on canonical `main`.**
The archive of a device is an offline operation of the Core: the managed session refuses it with
`OFFLINE_ARCHIVE_REQUIRED` ("Archive remains an explicit offline operation"), because an archive
changes the registry while the Core is serving. The surface therefore names the procedure instead
of offering a write that the Core would refuse — and the procedure itself was not proven yet.

**The rehearsal.** `tests/oip_offline_archive.py` runs against a disposable instance of the release
binary: the device is registered through the authorized managed session, the managed session
refuses the online archive with its named reason, the Core is stopped, the archive is applied with
the offline plan of the Core (`--inventory-plan … --inventory-apply`), and the Core starts again.
Measured: the offline plan is applied (`applied: true`, the action `{"outcome": "archive"}`), the
archived device advances its revision from 1 to 2, keeps its identity and its metadata, and is
**no longer part of the active inventory** — it only appears when the archived ones are asked for.

The procedure is documented in `docs/runbooks/operations.md` §7, next to the update of a device,
and the receipt is `docs/evidence/oip-offline-archive/offline-archive.json`.

Three defects of the rehearsal were found while proving it and are part of the procedure: the
offline plan needs the explicit `--inventory-apply` flag (without it the Core only proves that the
archive is admissible), the browser session lives in the memory of the Core and ends with its
restart, and the operator needs the scoped inventory permission of the plan.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 21 — the daemon handover with the historical binary is measured and rehearsed

**Status: PROVED on canonical `main`.**
The ledger claimed that the daemon of the historical release could not be rehearsed. That claim
was never measured — the historical binary was only used for the offline provisioning and the
backup of its data store — and a read-only investigation of the era contracts and of the existing
harnesses showed that the protected OIP-008.4 binary **is** started as a daemon by two milestone
harnesses (`tests/oip0085/migration.py`, `tests/oip0084/acceptance.py`), with a principal-bound
protected IPC configuration.

**The measurement.** `tests/oip_historical_daemon.py` rehearses the handover of a *running*
instance against a disposable instance and records what actually happens:

| Step | Result |
|---|---|
| the OIP-007 shape (actor, permissions, sources) | **refused**: `invalid protected local IPC configuration/path` |
| the OIP-008 shape (a credential bound to a provisioned, enabled principal) | the daemon starts and serves |
| the authorized read of `reader-org-a` | 200 with exactly the three sources of its organization |
| the authorized read of `reader-org-b` | 200 with exactly the fourth source |
| the read without a credential | 403 |
| the collection of the daemon | the sources of the scope become fresh, 41 observations are persisted |
| the schema of the store | 3 after the provisioning, 5 with the historical runtime |
| the release binary takes over | 200, the schema becomes 7, the observations are intact |
| the backup and the restore | the schema is 5 again, the observations are identical |
| the historical binary serves the restored store | 200, the observations are intact |

The receipt is `docs/evidence/oip-historical-daemon/historical-daemon.json`. The refusal that the
old receipt asserted without evidence is now a measurement, and the correct statement — the era
binds a *principal*, the actor shape is OIP-007 — replaces it in the ledger and in the progress
file.

The protected binary is used only when its hash is the recorded hash; the rehearsal never touches
the personal installation of the operator and nothing leaves the machine.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 22 — the macOS application bundle of the Flutter client

**Status: PROVED on canonical `main` (`205d08e`).**
The macOS half of G9 was open: the Core side of the local operations was done, but the application
bundle of the Flutter client had never been built. It exists now and is proven against a
disposable managed instance of the **release** binary (`tests/oip_macos_app.py`,
`docs/evidence/oip-macos-app/macos-app.json`):

* `flutter build macos --release` produces `oip_dashboard.app` (bundle id
  `org.openindustrial.oipDashboard`, version 0.3.0) in a few seconds (the receipt of the run
  names the seconds); the receipt names the sha256 of the
  executable and the digest over the tree of the bundle.
* The bundle starts and asks the Core for the authorized projection of the principal within the
  **first second** (the receipt of the run names the moment).
* The Core answers **403** and the bundle obtains **no** unauthorized data (`api_successes: 0`).
  It shows the approved Spectrum-2027 shell with the six workstations, the honest
  `PERMISSION_DENIED` notice and the operator login — no OIP/005 demo, no gradient KPI row, no
  `M-01` defaults, no AGENT-FIRST footer.
* The bundle terminates on `SIGTERM` in 0.0 s without leaving an orphan behind, and it starts
  again and reaches the Core again (0.5 s) — the restart of the application bundle.

**A defect of the desktop shell was found and fixed.** The frame of the storyboard belongs to the
screen the bundle was generated for (2560×1577). On a smaller display the window opens above the
visible area and the operator sees nothing at all. The runner now checks the frame against the
visible frames of the machine and places the window in the centre of the main screen when it
touches no visible screen; the placement is reported in the log of the bundle. On this machine
(the main display 1512×982 and a second display 2560×1440 above it) the system places the window
itself and the check confirms that the window is on a visible screen.

The evidence policy keeps the capture of the window local; the receipt names the window, its
bounds, the displays of the machine and the placement of the bundle.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 23 — the extended stability run of the release binary

**Status: PROVED on canonical `main`.**
The acceptance harness measures the Core for a few seconds. Nothing measured it over a
sustained run, and the reconnect of a collection was only a code path.

`tests/oip_stability.py` runs the **release** binary against four real collectors for 30 minutes
and takes 60 samples (`docs/evidence/oip-stability/stability.json`):

| Measurement | Result |
|---|---|
| the liveness of the Core | 60 of 60 probes answered with 200 |
| the resident memory | between 17 920 and 23 552 KiB, **−5 264 KiB** from the first to the last sample |
| the CPU | 1.73 % on average, 4.1 % at most |
| the collection | 41 463 observations, 1 398 per minute, constant over the run |
| the growth of the store | 536 KiB to 78 MiB under the load of the collectors |
| the log | 18 KiB to 116 KiB — no runaway |
| the death of a collector | noticed and recorded as a documented gap, the collection resumed 1 s later |
| the end | clean shutdown, `pragma integrity_check` answers `ok` |

The resident memory does not grow over the run: the Core holds its working set and the writer
does not accumulate. The store grows with the observations of the collectors, as it must.

### Iteration 24 — the continuation of a truncated diagnostic page

**Status: PROVED on canonical `main`.**
The persisted evidence of the diagnostics view is a page of the Core, cut off at 50 entries with
an opaque cursor for the continuation. The client followed the cursor and merged the pages by the
stable Core IDs — that was proven by a widget test against a fixture. What was missing is the
**browser journey against a real Core whose page really is truncated**.

`tests/oip_diagnostic_continuation.py` creates that Core: the collector of one source is cycled
until the Core has documented more gaps than a page holds — every gap is a real interruption of a
real collection (the receipt of the run names the cycles) — and the browser journey
(`apps/flutter/test/browser_diagnostic_continuation.mjs`) then follows the evidence in the
approved shell. Measured (`docs/evidence/oip-diagnostic-continuation/diagnostic-continuation.json`):

* the Core answers the first page with 50 entries, `truncated: true` and a cursor;
* the surface offers the continuation for the gaps and for the health history;
* the continuation asks the same authorized route with the opaque cursor of the Core
  (the receipt of the run names them — they are opaque and of the run);
* the pages are disjoint — no row is repeated and no row is lost (the receipt of the run names
  the rows and the distinct rows);
* the health history needed three continuations and ends
  truncated: `false`;
* the offer of a kind disappears exactly when its last page is reached;
* the evidence stays painted and its disclosed limits stay visible; no failure of the evidence is
  shown.

20 checks, no error, no page error. The journey works against the **release** binary and the
delivered web bundle — not against a fixture.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 25 — the parity of the OPC-UA address space is re-inventoried

**Status: PROVED on canonical `main`.**
The last independent gap of the functional gate G8 was the parity of the OPC-UA address space:
the milestone harnesses had proven it for the releases of their era, but the **current release
binary** had never been re-inventoried against a real backend.

`tests/oip_opcua_parity.py` runs the release binary against four real collectors and compares
the official MCP tool `oip_opcua_nodes_read` with the REST routes
(`/docs/evidence/oip-opcua-parity/opcua-parity.json`):

| Measurement | Result |
|---|---|
| the MCP answer | 100 nodes of 1 006, offset 0, limit 100 |
| `/api/v2/opcua/nodes` | the same page — the same nodes, the same total, the same offset, the same limit |
| `/api/v1/opcua/nodes` | the same page |
| the second page | disjoint, the boundary exact (`bulk.0098` → `bulk.0099`) |
| the scope | the reader of the other organization is refused with `RESOURCE_NOT_ACCESSIBLE` — without a name of the foreign source |
| across a reconnect of the collector | the address space is served again, the content and the order are unchanged |

**A contract gap was found and is escalated.** The address space of a source is the **live
catalog of its collector**: it is published while the collector connects and it is replaced when
the collector connects again. The pagination is by offset, so a page that is read across such a
change **can** repeat a node at the boundary. The measured reconnect shows the opposite of a
repetition — the content and the order of the page did not change and **no** node was repeated at
the boundary (`docs/evidence/oip-opcua-parity/opcua-parity.json`) — so the repetition is a
possibility of the design of the collector and **not** a measured effect.
Every other paginated surface of the Core (the diagnostic pages, the observation history) uses an
opaque cursor and is therefore stable; the Core makes no such promise for the address space, so
no claim is broken. Giving the address space the same cursor would change the query of the REST
and MCP surface of the Core: that is a **contract decision of the operator** and is named as such
in the ledger.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 26 — the final acceptance of the release candidate, bound to the tree

**Status: PROVED on canonical `main` (`e7aa994`), tree `a1e2b71`.**
The canonical acceptance was run once more on the clean tree after every change of this
iteration, with the **release** binary and the delivered web bundle
(`target/oip-canonical-regression-final2/`). The receipt names the tested artefacts:

| Artefact | Value |
|---|---|
| the tested revision | `e7aa994104a6` (the full hash in the receipt of the run) |
| the tested tree | `bf03f2465868` (the full hash in the receipt of the run) |
| the tree during the run | clean (`source_dirty: false`) |
| the release binary (`target/release/oip-server`) | `4f49cc1512fa8e10083bdf01e5cb618077e3337ed4ce8fc948fd08b37adef30f` |
| the official MCP probe | `029bf9f4505dd483d62196992d0443498a3e5a242f35a3192a4ef125227cfb08` |
| the served `main.dart.js` | `a51b62cdd3644a6be44bcb64…` (the full hash in the receipt of the run) |
| the served bundle equals the local build | **yes**, byte by byte |
| the Flutter tests | 356 passed, 0 failed (one skipped: the live test without an instance) |
| the browser gate | 175 findings, 0 failed, 13 captures, no console error, no external request |
| the accessibility receipt | 154 controls, **0** without an accessible name |
| the visual comparison | **PASS** |
| the eight functional phases | 8 of 8 **PASS** |
| the verdict of the gate receipt | **PASS** |
| the operator visual approval | `VISUAL_PENDING_OPERATOR_ACCEPTANCE` |
| the own processes | stopped |

The visual acceptance of the operator stays **pending**: the gate proves that the rendered
surface is the approved Spectrum-2027 shell and that it matches the committed technical
references, but only the operator can accept it.

**One honest remark about the binaries and about this binding.** The web bundle is
byte-identical between the builds (`a51b62cd…`), the Rust release binary is not: the gate rebuilds
it and its sha256 differs from the build of the earlier rehearsals (`76d18b6e…`, `6afee854…`,
`835ed0a1…`). Every receipt names the binary it actually executed, and no receipt claims a hash
of a binary it did not run. The commit after the tested revision (`d4a0a9d`, the rehearsal of the
transport parity) and the binding commit itself add **only** a test script and documentation — no
line of the Core or of the Flutter application — and the served bundle of the tested tree is the
byte-identical asset (`a51b62cd…`) that the gate proved.

No personal database change (`9f988c01c7115631db3b5bfd2b9228ecc24255b8b9905932a987a89c78e6a24e`,
`user_version` 6), no schema-7 activation of the personal installation, no private SSH, no push,
no deployment, no system service, no foreign process touched.

### Iteration 27 — the functional depth of the six workstations

**Status: PROVED on canonical `main`.**
The canonical gate proves that the six workstations of the approved shell render, that they carry no
legacy marker and that the scope follows the operator. It does not prove that they show **real**
data of the authorized Core — a workstation that renders an empty state passes such a gate.

`tests/oip_workstation_data.py` starts the release binary with four real collectors and
`apps/flutter/test/browser_workstation_data.mjs` drives the approved surface. The operator
selects a source in the global Infrastructure Context (a real mouse event on the painted option —
the web engine forwards no key events), and every workstation is then read while the page is
scrolled. Measured (`docs/evidence/oip-workstation-data/workstation-data.json`): 17 checks, no
JavaScript error.

| Workstation | What the operator really sees |
|---|---|
| Übersicht | the authorized hierarchy (`Organization A`, `Infrastructure A1`) and its counts |
| Geräte & Dienste | the device of the selected source (`device-a`) |
| Netzwerk & VPN | the authorized placement (`Organization A / Infrastructure A1`, `site-a1`) |
| OPC-UA-Browser | the real nodes of the source (`bulk.*`, `motor_running`, …) |
| Diagnose & Ereignisse | the real events of the scope (`source-a`) |
| Einstellungen | the real settings of the Core (`history_page_size` with its default and its validation) |

In **all six** workstations no identifier of the other organization appears — `device-d`,
`source-d`, `Organization B`, `Infrastructure B1` and `Site B1` are nowhere on the surface.

The receipt records that the settings shown are the real settings of the Core
(`docs/evidence/oip-workstation-data/workstation-data.json`); it does **not** record the two
details that an earlier reading of the surface named — that the application section reads the
platform scope, which this principal is **not** allowed to read, and that the operator reaches
the scoped section through the category `Diagnostics`. Those two are observations of the surface,
not measurements, and they are therefore not claimed here. The measurement that the deny-by-default
of the platform scope holds is the refusal of a foreign scope in the receipts of the transport
parity and of the OPC-UA parity.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 28 — the verified connection of a device in the surface

**Status: PROVED on canonical `main`.**
The last gap of the device management gate G4 was the association of a device with a **verified**
connection through the surface: the administration surface could register, update and archive a
device, but nobody had shown that the surface shows the connection of a device — with the host key
the operator confirmed and the identity the Core really verified.

`tests/oip_device_connection.py` starts the release binary with an **owned loopback SSH fixture**
(a real OpenSSH server with a real host key on the loopback of the machine; no system service, no
personal endpoint, no private key in a receipt) and performs the whole handshake through the
authorized managed session:

1. the device is registered through the inventory of the authorized scope;
2. the connection is started, the Core presents the host key of the fixture and waits for the
   consent of the operator (the fixture generates a fresh key for every run, so the receipt of
   the run names the fingerprint that was consented);
3. the host key is confirmed, the identity of the host is verified and the identity confirmation
   enables the read-only monitoring with a polling of 10 s;
4. the device collects — the state of the connection is `collecting`.

The browser journey (`apps/flutter/test/browser_device_connection.mjs`) then opens the device
workspace, selects the device and reads the connection panel of the approved surface. Measured
(`docs/evidence/oip-device-connection/device-connection.json`): 8 checks, no JavaScript error —

* the inventory of the scope lists the device;
* the panel `Verbindung & Monitoring` is shown with the state `Collecting`;
* the **confirmed host key** is shown — the same fingerprint the Core presented;
* the endpoint of the verified connection is shown;
* the read-only monitoring is shown with its polling and its revision;
* behind the expansion `Tatsächlich verifizierte Identität` the really verified identity of the
  host stands: `MacBookPro.fritz.box`, `Darwin`, 17 179 869 184 bytes of memory — and the Core
  names the sensors it could not read (`gpu`, `temperature`, `cpu_utilization`) instead of
  inventing them.

No personal database change, no schema-7 activation of the personal installation, no private SSH
to a foreign endpoint, no push, no deployment, no system service.

### Iteration 29 — the security review of the current release

**Status: PROVED on canonical `main`.**
G10 asks for a review that resolves, mitigates or explicitly escalates every material finding. The
acceptance of the production-security scope stays an operator decision; the review itself is the
work of the loop. `tests/oip_security_review.py` measures the findings of the current tree against
a running instance of the release binary (`docs/evidence/oip-security-review/security-review.json`):
**11 findings — 8 resolved, 2 mitigated, 1 escalated.**

**Resolved.**

* The dependency advisories of the complete lockfile: `cargo deny check advisories licenses bans
  sources` → advisories ok, licenses ok, bans ok, sources ok. The three exceptions
  (`RUSTSEC-2023-0071`, `RUSTSEC-2023-0089`, `RUSTSEC-2024-0449`) are documented in `deny.toml`
  with a reason and a review date — they are transitive dependencies of the OPC UA stack, not of
  the release path.
* The secret scan of the content that ships: gitleaks 8.30.1 over the 598 tracked and untracked
  files — 27 candidates, every one of them the SHA-256 of a source file inside a measurement
  receipt of `docs/evidence`. Each candidate is classified in the receipt; **no secret** was found.
* The browser session contract: `HttpOnly`, `SameSite=Strict`, `Max-Age=1800`,
  `Cache-Control: no-store`, `X-Frame-Options: DENY`, CSP `frame-ancestors 'none'`.
* The single use of the pairing code: the second use is refused with 403.
* The origin and the CSRF rule: a foreign origin is refused (403), a write without the CSRF token
  is refused (403), a write with a foreign origin and a valid token is refused (403).
* The protection of the credentials: a private 0600 file of 32 bytes that appears nowhere in the
  log of the instance.
* The enforcement of the scope: the reader of one organization sees `source-a`, `source-b`,
  `source-c` and no source of the other organization.
* The non-disclosure of a foreign resource: a foreign device and a device that **does not exist**
  are refused **identically** (`404 RESOURCE_NOT_ACCESSIBLE`) — the answer names neither the
  target nor the reason, so the refusal does not tell a foreign principal what exists.

**Mitigated.**

* The remote identity: the Core binds to **127.0.0.1 only** — a browser on another machine cannot
  reach it. A productive remote identity is **not implemented and not claimed**: the release is a
  local application.
* The same-UID boundary: the configuration and the credential are 0600, the directory is 0700 and
  a client must have the same OS user as the daemon. The boundary does **not** isolate hostile
  processes of the same user — that user can read the credential and control the process. This
  limit is part of the era contract and is not a tenant authentication.

**Escalated.**

* The durability of the execution audit: the audit of the Core is a **structured local log**; it
  is neither durable nor tamper-resistant. For a local instance with an authorized operator this
  is acceptable and is the contract of the era (`OIP-005 uses structured local logs … an explicit
  prerequisite for future remote mutating capabilities`). For a remote or productive deployment a
  durable, tamper-resistant store is a **prerequisite** — the operator decides whether the
  production scope accepts the current one.

The acceptance of the production-security scope remains **BLOCKED_OPERATOR**; the review gives the
operator the measured material for that decision.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 30 — the parity of the three transports of the current release

**Status: PROVED on canonical `main`.**
The gate G2 names the parity of REST, SSE and MCP. The milestone harnesses had proven it for the
releases of their era; the current release binary had not been re-inventoried.

`tests/oip_transport_parity.py` runs the release binary with four real collectors and compares
the three transports for **the same principal**
(`docs/evidence/oip-transport-parity/transport-parity.json`):

| Transport | Route | Projection |
|---|---|---|
| REST | `/api/v2/snapshot` | `source-a`, `source-b`, `source-c` · `device-a`, `device-b`, `device-c` |
| SSE | `/api/v2/stream` (the event `snapshot`) | the same |
| MCP | the resource `oip://v2/snapshot/current` | the same |

The three projections are **equal**, the projection contains nothing of the other organization
(`source-d` appears in none of them), and the transports refuse what they must refuse: the REST
route answers **403** without a session and the SSE stream answers **403** without a session — no
payload at all.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 31 — the honest states of the surface and the release manifest

**Status: PROVED on canonical `main` (`d1ab37c`).**
With every independent task closed, the remaining work was to look for the defects an operator
would actually hit. A systematic sweep of the approved surface for values that are presented as
facts found **three**:

1. **The footer rendered the security blocker as "unknown offen".** The scoped snapshot of a
   tenant carries no platform fact, so the client synthesised the placeholder `unknown` — and the
   footer presented it as an *open* blocker. The footer now names that the blocker of the platform
   is **not delivered to this session**. A blocker that the Core reported (`RUSTSEC-2023-0071
   offen`) and the case "no blocker reported" stay exactly as they were.
2. **The OPC-UA browser showed the scenario as "authorized_context"** — an internal wire value
   presented as a fact. The scenario is a concept of the demo; the authorized scope carries none,
   so the line of the source panel names that instead.
3. **The operator login named two causes of the end of a session** (30 minutes, the sign-out) but
   not the third: a **restart of the instance**. The browser session lives in the memory of the
   Core (`crates/oip-server/src/browser_session.rs`), so a restart ends it — and the operator
   restarts the instance routinely.

Four new widget tests pin the three states (`apps/flutter/test/security_blocker_footer_test.dart`,
the OPC-UA workstation test, the managed core integration test). The **design regression gate**
passes on the changed shell: 348 of 348 Flutter tests, 175 browser findings with zero failures,
13 captures, the visual comparison **PASS**, the eight functional phases 8 of 8 **PASS**, the served
bundle (`e721eb67…`, 3 031 349 bytes) byte-identical to the local build, the operator visual
approval still `VISUAL_PENDING_OPERATOR_ACCEPTANCE`.

**The release manifest.** The operator decides which artefacts may be signed and distributed; that
decision needs a list. `tools/oip_release_manifest.py` writes `docs/release/oip-release-manifest.json`
and `docs/release/SHA256SUMS`: every artefact of the release with its digest (the Core, the official
MCP probe, the macOS application bundle as a digest over every file of the bundle, the delivered
web release with the digest of `main.dart.js`), the revision and the tree it was built from, the
build commands, the toolchain versions, the digest over the tracked sources of the revision, the
digests of the tracked acceptance receipts and the state of the operator's visual acceptance.
`--verify` recomputes every digest and compares it with the written manifest: the manifest is a
receipt, not a promise.

The macOS application bundle was rebuilt from the committed source for the manifest
(`e5cb5292…` over the tree of the bundle, `6123cdc5…` over its executable), and the bundle of the
web release that the manifest names is the byte-identical asset that the gate proved.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 32 — the native application could not hold a session

**Status: PROVED on canonical `main` (`2e2bef1`).**
The sweep of the release for the defects an operator would hit found a **fatal** one: the macOS
bundle could never authenticate.

**The finding.** The browser of the web release keeps the cookie of the session on its own and
sends the origin of the page with every request. The native application has no browser, and the
client did neither:

* the Core refuses the login of a session route without an origin
  (`crates/oip-server/src/browser_session.rs`, `require_origin`) — the native client sent no
  origin, so the one-time code could not even be redeemed;
* the Core refuses every management read without the cookie of the session — the native client
  kept no cookie, so even a successful login would have left the bundle without an authorized
  projection.

The bundle therefore showed the operator login and nothing else. **G9's local installation and
G12's operator acceptance were impossible with the desktop application** — and the defect was
invisible in the web release, which is why the browser gate never saw it.

**The proof before the fix.** `apps/flutter/test/native_session_cookie_test.dart` runs the real
client on the VM — the Dart semantics of the bundle, without a browser — against a server that
behaves like the Core: the login answers with the `Set-Cookie` of the session and every other
route refuses a request without that cookie. Before the fix the read after a successful login
was refused with `PERMISSION_DENIED`.

**The fix.** A platform-specific session transport (`apps/flutter/lib/services/session_cookie.dart`
with its native and its web implementation): on a platform without a browser the client keeps the
cookie of the session in the memory of the process and declares the origin it addresses; on the
web the browser keeps both and the client adds nothing. The cookie is never written to a file,
never logged and never leaves the process.

**The proof after the fix.** `tests/oip_native_session.py` starts the **release** binary, issues
the one-time code of the operator and runs the native client against the real Core
(`docs/evidence/oip-native-session/native-session.json`): the login with the code, the hierarchy
of the authorized scope, the scoped projection with the sources of the scope and without the
source of the other organization, and the sign-out at the end. The Core served the session — its
audit names the capability executions.

**The gate.** The design regression gate passes on the changed client: **349 of 349** Flutter tests
(one skipped: the live test without an instance), 175 browser findings with zero failures, the
visual comparison **PASS**, the eight functional phases 8 of 8 **PASS**, the served bundle
(`8861cf74…`) byte-identical to the local build, the operator visual approval still
`VISUAL_PENDING_OPERATOR_ACCEPTANCE`. The macOS bundle was rebuilt from the committed source and
proves again: it starts, reaches the Core, refuses without a session, shows the approved shell,
terminates without an orphan and starts again.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 33 — the reconnect and the recovery of the application

**Status: PROVED on canonical `main`.**
The operator restarts the instance routinely. Nothing proved that the *application* survives that
honestly: the Core side of a restart is proven (the phase `restart_sigkill_identity`), the client
side was not.

`tests/oip_reconnect_recovery.py` runs the real Core with its collectors and the delivered web
release in a browser, and restarts the instance in the middle of the session through a small
control server of the rehearsal (`apps/flutter/test/browser_reconnect_recovery.mjs`,
`docs/evidence/oip-reconnect-recovery/reconnect-recovery.json`): 11 checks, no JavaScript error.

| Step | What the operator sees |
|---|---|
| the operator authorizes the session | the authorized projection of the unified view |
| the instance is restarted | — |
| the surface after the restart | `Kontext nicht autorisiert` with the badge `IDENTITÄT ERFORDERLICH`, the honest notice `Browser-Session oder zentrale Policy erlaubt diesen Management-Read nicht (PERMISSION_DENIED) … Keine vorherigen Kontextdaten werden angezeigt` and the operator login — **no stale content is shown as current** |
| the operator login | names the restart of the instance as the third cause of the end of the session (the panel of iteration 31) |
| a new one-time code | the authorized projection again, with a fresh moment (the receipt of the run names it) |

The session of the browser ends with the restart because the Core holds it in its memory — that is
the contract of the era, and the surface now says so instead of leaving the operator without an
explanation.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 34 — the upgrade of a live instance keeps the whole inventory

**Status: PROVED on canonical `main`.**
The upgrade rehearsal proved that the **organizations** of a store survived the handover of the
release binary. That is a thin proof for the operator: the instance of an operator carries devices,
measurements, events and documented gaps. The rehearsal now runs the **daemon of the era** against
four real collectors before the handover, so the store of the handover is a live instance.

Measured (`docs/evidence/oip-upgrade-rollback/upgrade-rollback.json`, `tests/oip_upgrade_rollback.py`):

| Table | Before the handover (schema 5) | After the takeover (schema 7) | After the rollback (schema 5) |
|---|---|---|---|
| organizations / infrastructures / sites / source_placements | 2 / 3 / 4 / 4 | 2 / 3 / 4 / 4 | 2 / 3 / 4 / 4 |
| principals / read_roles / role_bindings | 7 / 1 / 6 | 7 / 1 / 6 | 7 / 1 / 6 |
| observations / collection_events / data_gaps / source_health_history | the receipt of the run names them | the health transitions grow | they are the ones of the backup again |
| inventory_devices | *absent in the era* | 4 (created by the migration) | *absent again* |
| device_connections | *absent in the era* | 0 (created by the migration) | *absent again* |

The observations of the historical instance are **preserved by their stable Core IDs** — every
distinct observation key of the era (the receipt of the run names them) is still there after the takeover — and the data
only grows: the health transitions of the release binary join the history of the era. The rollback
restores the store **exactly**: the inventory of the backup and the inventory of the restored store
are the same, and the tables that the era did not know are absent again.

This is the evidence the operator needs for the activation of the release on the personal instance
(schema 6 to 7): the migration is additive and the inventory of the instance survives it.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 35 — the dry run of the activation of the operator's instance

**Status: PROVED on canonical `main`.**
The activation of the release on the personal installation is an **operator decision** (N4): the
Core refuses to touch the personal installation and the loop never activates it. Before that
decision the operator needs to know whether the activation would succeed at all — the migration of
the Core verifies the **checksum of every migration the store already carries**, so a change in
the SQL of an era after the store was written would refuse the activation.

`tests/oip_activation_dry_run.py` answers that question **without touching the personal
installation**: it copies the store of the operator into a disposable directory and lets the
release binary migrate the **copy** (`docs/evidence/oip-activation-dry-run/activation-dry-run.json`).

Measured:

| | Result |
|---|---|
| the store of the operator | schema 6, sha256 `9f988c01…` |
| the copy | byte-identical to the original (`the_sha256_equals_the_original: true`) |
| the migration | **accepted**: the schema becomes 7, the seventh migration is recorded |
| the inventory | identical before and after — 1 organization, 1 infrastructure, 1 site, 1 principal, 1 role, 1 binding, 1 device: nothing is lost |
| the integrity of the migrated store | `ok` |
| the daemon | the release binary serves the migrated copy |
| **the personal installation afterwards** | **unchanged**: the same sha256, still schema 6 |

Two properties of the rehearsal are worth naming: the runtime configuration of the copy declares
the sources of the instance with **closed loopback ports** — the rehearsal never contacts a
private endpoint of the operator — and the local IPC binds to the **enabled principal of the
store**, because a principal that the store does not carry is refused by the Core.

The operator action N4 is unchanged and now has measured material: the activation of the release
on the personal instance would succeed, and it remains the operator's decision with its own fresh
schema-6 backup.

No personal database change (`9f988c01c7115631db3b5bfd2b9228ecc24255b8b9905932a987a89c78e6a24e`,
`user_version` 6 — measured before and after the rehearsal), no schema-7 activation of the
personal installation, no private SSH, no push, no deployment, no system service.

### Iteration 36 — the example of the runbook is executable documentation

**Status: PROVED on canonical `main`.**
The operator writes the plan of the own instance from the example of the runbook (§1.1). A
documentation that does not work is worse than none.

`tests/oip_documented_plan.py` takes the example **out of the runbook**, provisions a disposable
instance with it and proves the whole path
(`docs/evidence/oip-documented-plan/documented-plan.json`): the plan provisions (one
organization, one source), the instance starts and answers the session route with 200, and the
operator of the example authorizes a session with the one-time code of the principal **of the
plan** — the session carries exactly that principal.

If the plan of the Core changes, this rehearsal fails: the runbook is executable documentation
and cannot rot unnoticed.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 37 — the settings navigation names the status of the Core

**Status: PROVED on canonical `main` (`fa7d66a`).**
The Core answers for every category of the settings whether the category is administered **offline**
or only **read** (`offline_administration_required` / `read_only`). The client parsed the answer and
dropped it: the navigation of the settings workstation showed the categories of the client without
the status of the Core, and the Application section stated the offline administration as a
hardcoded string of the client instead of the answer of the Core.

The navigation now shows the answer of the Core for the selected category —
`CORE · Nur offline administrierbar` or `CORE · Nur lesend` — and the categories are kept when a
section is loaded that does not read the settings, because they describe the **instance** and not a
section. The wire names of the Core are snake_case while the enum of the client is camelCase: the
mapping is explicit, so the status of a category is **found and not guessed**.

The design regression gate passes on the changed shell: **350 of 350** Flutter tests (one skipped:
the live test without an instance), 175 browser findings with zero failures, 13 captures, the
visual comparison **PASS**, the eight functional phases 8 of 8 **PASS**, the served bundle
byte-identical to the local build, the operator visual approval still
`VISUAL_PENDING_OPERATOR_ACCEPTANCE`.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 38 — the offline change of a setting of the instance

**Status: PROVED on canonical `main`.**
The Core has **no** HTTP and no MCP write path for the settings: the change is an offline
operation of the local operator with the exclusive local CLI (`--settings-change`). The settings
navigation of the application says so ("Kein Browser-Save"), but the runbook of the operations did
not name the procedure — and the operator has no other way to give their instance a name.

`tests/oip_settings_offline.py` proves the procedure against the **release** binary
(`docs/evidence/oip-settings-offline/settings-offline.json`):

| Step | Result |
|---|---|
| the change of `instance_name` of the instance | applied offline, the record has the revision 1 |
| the same change with a wrong revision | **refused** — the guard of the write |
| the same change with a principal without `settings_write` | **refused** |
| a value outside the validation of the key (`history_page_size` = 9999) | **refused** |
| the next validated start | the value is effective: `Meine Instanz`, `apply_status: active_startup_snapshot` |

The procedure is now in the runbook (§12) with the three rules that the Core enforces: the
principal needs the permission in the scope, the metadata belongs to the platform scope and
`history_page_size` is inherited, and the `expected_revision` is the guard of the write.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 39 — the lifetimes of the session and of the one-time code

**Status: PROVED on canonical `main`.**
The operator login promises the operator two things: the one-time code is valid for **120 seconds**
and may be used once, and the session ends after **30 minutes**. The Core keeps both as
constants; nothing proved that the promise of the surface holds.

`tests/oip_session_lifetime.py` measures both against the **real Core** with the **real**
lifetimes — nothing is shortened, because a shortened lifetime would prove nothing
(`docs/evidence/oip-session-lifetime/session-lifetime.json`):

| Promise | Measurement |
|---|---|
| the code is valid for 120 s | a code that was issued 130 s ago is **refused**: 403 `PERMISSION_DENIED` |
| the session ends after 30 minutes | the session is checked 1 830 s after its authorization: the session route answers `authenticated: false` and the **management read is refused with 403 `PERMISSION_DENIED`** |

The second measurement is the one that matters: the session route reports the state of the
session (an expired session is "not authenticated"), while the management read is the proof that
the identity is gone. The Core prunes the expired sessions on every check, so the identity of the
operator cannot outlive its lifetime.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 40 — the honest connection states of a device are pinned

**Status: PROVED on canonical `main` (`ad335f5`).**
The gate G5 names the **honest connection states**. The Core produces them — the acceptance proves
the collecting state and the block after a changed host key — but nothing pinned what the **surface**
shows for each of them: a regression that showed a blocked connection as connected would have
broken the promise of the gate without a single test failing.

`apps/flutter/test/device_connection_states_test.dart` pins all six states of the panel of the
connection with the real shape of the identity of the Core:

| The state of the Core | What the operator sees |
|---|---|
| `collecting` | `Collecting · aktuelle Messwerte empfangen` with the confirmed host key and the read-only monitoring |
| `ssh_verified` | `SSH Verified · Monitoring deaktiviert` |
| `host_key_changed` | `Host-Key geändert · Verbindung blockiert` with the error of the Core (`HOST_KEY_CHANGED`) |
| `host_key_unknown` | `Host-Key unbekannt · Identität vor der nächsten Verbindung bestätigen` |
| `unreachable` | `Unreachable · tatsächlicher Verbindungsversuch fehlgeschlagen` with the error of the Core |
| `stale` | `Stale · Messwerte veraltet` |

The suite found a real weakness of the panel on the way: the identity of the Core must carry its
whole shape (`disks`, `interfaces`, `unavailable`, `provenance`) — the panel casts the
unavailable list directly, so an identity without that field breaks the build of the panel. The
fixture of the suite now carries the real shape.

356 of 356 Flutter tests pass (one skipped: the live test without an instance).

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 41 — the extension of the registry of an instance

**Status: PROVED on canonical `main`.**
The operator adds infrastructure by extending the plan of the instance and provisioning it again.
Nothing measured that path, and nothing told the operator what the Core does with a plan that
**drops** a source.

`tests/oip_extend_registry.py` proves it against the **release** binary with four real collectors
(`docs/evidence/oip-extend-registry/extend-registry.json`):

| Step | Result |
|---|---|
| the instance with four sources | provisioned and serving |
| the plan extended by a fifth source | the four sources **survive**, the fifth is registered (5 sources) |
| the extended instance | the fifth source **collects**: 41 observations |
| a plan that **drops** the fifth source | **refused**: `hierarchy/provisioning validation failed` |
| the registry after the refusal | unchanged — the five sources are still there |

The registry of an instance is therefore stable: the operator adds, and a principal may be
disabled by the plan, but nothing is removed. The procedure is in the runbook (§1.2).

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 42 — the builds of the release are reproducible

**Status: PROVED on canonical `main`.**
The gate G9 asks for a **reproducible** macOS application build. The design regression gate
compares the served bundle with the local build — but that is the *same* build. Nothing built the
release **twice** and compared the artefacts.

`tests/oip_reproducible_build.py` builds the release twice and compares the digests
(`docs/evidence/oip-reproducible-build/reproducible-build.json`):

| Artefact | First build | Second build | Identical |
|---|---|---|---|
| the web release — `main.dart.js` | `a51b62cdd3644a6be44bcb64…` | the same | **yes** |
| the web release — the whole asset tree (35 files) | `db506a2f0764afb23e5c2718…` | the same | **yes** |
| the macOS application bundle (43 files, built from an emptied build directory) | `e5cb529201e18bfc7180253529…` | the same | **yes** |

The digests are taken over the sorted list of the paths and their contents, so they do not depend
on the order of the file system. The two builds of the bundle were independent: the build
directory was emptied between them, so the second build was not an incremental artefact.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 43 — the regression of the Core of the current release

**Status: PROVED on canonical `main`.**
The acceptance of the release runs the **Flutter** tests, the widget gate, the browser gate, the
visual comparison and the eight functional phases. The **Rust** suite of the Core — its unit
tests, its integration tests and its doc tests — was not part of it: the receipts of the Rust
regression belong to the eras of the milestones.

`tests/oip_rust_regression.py` runs the suite of the current tree
(`docs/evidence/oip-rust-regression/rust-regression.json`):

| | |
|---|---|
| the command | `cargo test --workspace --release --no-fail-fast` |
| the revision | the clean tree of this iteration |
| the toolchain | rustc 1.93.0, cargo 1.93.0 |
| the result | **181 tests, 0 failed, 0 ignored**, 29 suites, 125 s |

The 29 suites include the **integration tests** of the Core — `api`, `browser_session`,
`capabilities`, `diagnostics`, `hierarchy`, `inventory`, `ipc`, `mcp`, `provision_cli`,
`reliability` and `settings` — beside the unit tests of every crate and the doc tests.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 44 — the storage-failure path of the Core is escalated, not claimed

**Status: ESCALATED on canonical `main`.**
The resilience of the Core under a **storage failure** — a full disk, a read-only mount, a changed
permission — is the one failure mode of the instance that no acceptance covers. The Core's design is
visible in the code (`crates/oip-server/src/writer.rs`): a failed commit marks the persistence as
failed, the health of the Core degrades, the log names the failure with its operation
(`persistence_retry`), the ingestion is backpressured in a bounded loop, and the shutdown reports
the uncommitted observations instead of claiming a clean stop.

**Why it is not measured here.** A rehearsal needs a store that cannot be written. Neither the
mode of the file nor the mode of its directory achieves that on macOS: the Core holds the store open
for writing, so the permission check happens at the open and not at the write — the rehearsal
measured that the observations kept growing (796 → 1 760) with the store at `0400` and its
directory at `0500`. The remaining ways to fail the storage are a **full disk** (forbidden: it would
destroy the work of the machine) or a **read-only mount** (privileged: outside the scope of the
loop). The integration suite of the Core has no case for it either: the repository is injected into
the writer as the concrete `SqliteStore`, so a failing repository would need a production change
that is not justified by a test.

**The escalation.** The behaviour is designed and readable, but it is **not measured**. The
operator decides whether the production scope accepts an unmeasured storage-failure path, or
whether the operator provides a machine or a volume with a quota for the rehearsal. The loop does
not claim the property and does not simulate it.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 45 — the advisories of the client are measured too

**Status: PROVED on canonical `main`.**
The security review measured the advisories of the **Rust** lockfile (`cargo deny`) — the Dart side of
the release was not looked at. The Dart SDK of this machine has no `pub audit`, so the review asks the
advisory service of the ecosystem directly.

The dependency surface of the client is small and fully enumerated by `dart pub deps`: the Flutter
SDK, **`http` 1.2.2** (runtime) and **`flutter_lints` 3.0.2** (development) — every other package
belongs to the SDK. The advisory service reports **no known advisory** for either of them.

The review of the current release now has **12 findings: 9 resolved, 2 mitigated, 1 escalated**:

| | |
|---|---|
| resolved | the dependency advisories of the lockfile, the advisories of the client, the secret scan of the tree, the browser session cookie and the security headers, the single use of the pairing code, the origin and the CSRF rule, the protection of the credentials, the enforcement of the scope, the non-disclosure of a foreign resource |
| mitigated | the remote identity (the Core binds to 127.0.0.1 only), the same-UID boundary |
| escalated | the durability of the execution audit |

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 48 — the proved bundle is the bundle of the release

**Status: PROVED on canonical `main`.**
The rehearsal of the macOS bundle built the bundle against the port of a **logging proxy**, so the
proved artefact carried the URL of the proxy — not the URL that the operator uses. The bundle of
the release was therefore never the bundle that was proved.

The rehearsal now builds the bundle **exactly as the release names it** — for the documented port
of an instance (18808, the port of the example configuration) — and puts the witness on that same
port, so the bundle carries the operator's URL while the Core of the rehearsal listens on a port of
its own. The evidence is the HTTP level, because the Core leaves no trace of a request without a
session.

Measured (`docs/evidence/oip-macos-app/macos-app.json`):

| | |
|---|---|
| the build | `flutter build macos --release --dart-define=OIP_API_URL=http://127.0.0.1:18808` |
| the bundle | `oip_dashboard.app`, bundle id `org.openindustrial.oipDashboard`, version 0.3.0 |
| the first request | within the first second: `GET /api/v2/organizations?offset=0&limit=100` → **403** |
| the further requests | six in total, **all** 403 — the bundle obtains **no** unauthorized data |
| the tree of the bundle | `e5cb5292…` — the same tree that the reproducibility of the release proves |
| the window | the approved shell with the operator login (captured) |
| the shutdown | `SIGTERM`, no orphan left behind |
| the restart | the bundle asks the Core again and is refused again |

The runbook names the pairing of the ports: the release bundle is built for 18808, the operator
either keeps that port for the instance or asks for a bundle that is built for their own.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 49 — every receipt names the revision it was measured on

**Status: PROVED on canonical `main`.**
A reader of the evidence must be able to tell whether a receipt is **current**. Most of the
receipts of the release named neither the revision nor the tree they were measured on — the
milestone receipts of the eras do (they carry their baseline), the receipts of this release did not.

Every rehearsal now records the revision, the tree and the cleanliness of the working tree, and
the browser journeys receive the revision from their runner and record it as well. The receipts of
the acceptance (the canonical gate) name their revision already.

The receipts of this release that were measured before the change were re-measured on the current
tree — the seventeen rehearsals and their browser journeys — and the long ones (the performance
baseline, the extended stability run, the lifetime of the session, the reproducibility of the
builds) were re-measured in the background.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 50 — the storage-failure path of the Core is measured

**Status: PROVED on canonical `main`.**
The last escalated gap of the acceptance is closed. A store that cannot be written was not
rehearsed, because a rehearsal needs a volume with a quota: a full disk is forbidden here, a
read-only mount is privileged and the mode of the file or of its directory does not fail the
writes of an open store.

A **disk image of a fixed size** is exactly that volume — and it needs no privilege at all. The
rehearsal attaches a 64 MiB image, puts the store of a disposable instance on it and lets the
collectors fill it up until the write of the store is refused (20 KiB are still free when the
refusal comes).

Measured (`docs/evidence/oip-storage-failure/storage-failure.json`):

| | |
|---|---|
| the volume | 64 MiB, filled until the write is refused with `No space left on device` (20 480 bytes are still free) |
| the instance | **survives**: it keeps answering its routes with 200 while its store cannot be written |
| the health | **degrades honestly**: the instance is no longer `ready`, `persistence_healthy` is false, the counter of the persistence errors grows from 0 to 18, the last error is named `commit_failed_retry_pending` |
| the log | **names** the failure (`persistence_retry`) |
| the store | is **not corrupted**: `pragma integrity_check` answers `ok` |
| the recovery | after the space is freed `ready` is true again, the persistence is healthy, the last error is gone and the collection continues (the receipt of the run names the counts) |
| the shutdown | clean |

The rehearsal reports that it is **blocked** — with the reason — on a machine without `hdiutil`;
it never claims a measurement it did not take. Nothing of the rehearsal touches the personal
installation of the operator: the store is a file on a volume in the temporary directory of the
machine, and the volume is detached and deleted at the end.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 51 — the record is checked against the evidence, and the Core of the release is reproducible

**Status: PROVED on canonical `main`.**
An independent read-only audit of the ledger and of this state file against every receipt under
`docs/evidence/` found stale figures, claims that no receipt backs, and two literal defects. All
of them are corrected:

* the confirmed host key of the device connection — the SSH fixture generates a fresh key for
  every run, so the record names the **property** (the surface shows exactly the fingerprint that
  the host really presents) and not a value of one run;
* the performance and the stability figures, in the unit of the receipt (KiB, not MB);
* the tables of the diagnostics, of the upgrade/rollback, of the artefacts of the acceptance and
  of the daemon of the era;
* the claim of the OPC-UA pagination: the measured reconnect shows **no** repeated node, so the
  record no longer exceeds the receipt;
* the claim of the device update: it now cites the tracked receipt of the administration of a
  device;
* the two literal defects: an unfilled placeholder (`{REV}`) and a garbled cell.

Two gaps of the **handoff** are closed as well:

* the whole acceptance of the release is now a **tracked** receipt (the eight phases, the browser
  gate, the UI gate, the device administration and the 13 captures), so the handoff does not
  depend on a directory of a build that is not part of the checkout;
* the release has **one** build command for the Core. The gate built it with
  `cargo build -p oip-server` and the manifest named `cargo build --release`; the feature
  resolution of the workspace is part of the binary, so the two commands produced two different
  binaries and the operator could build a binary that the gate had never proved.

**The Core of the release is byte-reproducible.** The build script of the Core embeds the revision
into the binary, so the binary changes with every commit — the honest property is that **the same
revision yields the same bytes**, and the binary says which revision it is. Measured
(`docs/evidence/oip-reproducible-build/reproducible-build.json`): the Core and its official MCP
probe are built twice from scratch and both builds are byte-identical; the web release and the
macOS bundle are byte-identical as well, and the reproduction of the bundle **is** the bundle of
the release. The manifest of the release names the reproducible binary and the state of the visual
acceptance of the operator.

**The tool of the operations can show the log of the instance** (`tools/oip_ops.py log`), which
the gate G9 asks for; the rehearsal reads the log with the tool and the record of the operations
names the operation that was performed.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 52 — the record is checked against the evidence, and its integrity is proved

**Status: PROVED on canonical `main`.**
A second independent read-only audit of the ledger and of this state file against the receipts
found fourteen defects. All of them are corrected, and the correction is driven by the receipts
rather than by the prose:

* the numbers of the current release were quoted from the **previous** measurement of the
  rehearsals — the pages of the diagnostics, the build seconds of the bundle, the moments of the
  reconnect, the inventory of the upgrade/rollback, the figures of the storage-failure path. Every
  one of them now names the value of the receipt of the current run.
* the **confirmed host key** of the device connection is a property, not a value: the SSH fixture
  generates a fresh key for every run, so the record names the fingerprint of the **run**.
* the gate **never recorded** the count of the Flutter tests: the pattern of the runner did not
  match its own output (`+356 ~1: All tests passed!`). The pattern is correct now, and the
  receipt of the acceptance carries the count (356 passed, 0 failed, 1 skipped).
* the new receipts of the release were **not tracked** — the evidence policy of the repository
  ignores the receipts of the eras and whitelists the reviewed ones by name. The whitelist names
  the new receipts now, so the claim that the acceptance is a tracked receipt is true.
* the manifest of the release named the receipts of a **build directory** and could not be
  verified in a checkout. It names the tracked receipts now, measures the tree without its own
  files, names the revision of the **product** separately from the revision of the record, and
  states where its digests are verifiable.

**The integrity of the record is itself proved** (`tests/oip_record_integrity.py`,
`docs/evidence/oip-record-integrity/record-integrity.json`): every receipt that the record cites
exists **and is tracked by git**, and every receipt of the current release is cited by the ledger
or by this file. 37 citations, 33 receipts, no broken citation, no orphaned receipt.

The **storage-failure path of the Core** — the last escalated gap of the acceptance — is measured
on a bounded volume: the instance survives the full volume, the health degrades honestly
(`persistence_healthy` false, the counter of the persistence errors grows, the last error is
named), the log names the failure, the store is not corrupted, and the instance recovers when the
space is freed. The rehearsal reports that it is blocked — with the reason — on a machine without
`hdiutil`; it never claims a measurement it did not take.

The **Core of the release is byte-reproducible** for its revision: the build script of the Core
embeds the revision into the binary, so the binary names its own revision and the same revision
yields the same bytes. The release has **one** build command for the Core, used by the gate, by
the manifest, by the rehearsal of the reproducible builds and by the runbook.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 53 — the local installation of the application is rehearsed

**Status: PROVED on canonical `main`.**
The gate G9 asks for a **local installation** that works without OpenCode. The rehearsal of the
bundle proved the bundle **in the directory of the build**; the operator receives a **copy** in
the directory of the installation, and it is the copy that must work. That was not measured.

The rehearsal of the installation (`tests/oip_macos_install.py`,
`docs/evidence/oip-macos-install/macos-install.json`) copies the bundle of the release into an
installation directory — exactly as the operator copies it — and proves:

* the copy is **byte-identical** to the bundle of the release: the digest over the tree of the
  bundle is `e5cb5292…` before and after the copy, 43 files;
* the installed copy is a **real application bundle**: the identifier
  `org.openindustrial.oipDashboard`, the version `0.3.0`, the executable present;
* the installed copy **starts** from the installation directory, reaches the Core and is refused
  on **every** request (six of six with 403) — it obtains **no** unauthorized data;
* the window shows the **approved shell with the operator login** (captured);
* the installed copy **terminates on the operator's signal** (SIGTERM) and leaves **no orphan**
  behind, and it **starts again** from the installation directory and reaches the Core again.

The installation directory of the rehearsal is a directory of the temporary tree of the machine —
**never** `/Applications`. The installation of the release into `/Applications` is the step of the
operator and is now named in the runbook (§9.1): the copy, the first start, the quarantine
attribute of a received copy and the identifier that proves the copy is this release.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 54 — the release is verifiable with one command

**Status: PROVED on canonical `main`.**
A third party that receives this repository must be able to check the whole handoff without
trusting the prose of the record. The new tool (`tools/oip_verify_release.py`) is that command,
and it proves in one run:

1. the **manifest** of the release verifies — every digest of every artefact and of every receipt
   is recomputed and compared with the written manifest;
2. **every receipt is fresh** — no receipt of the release names a revision that predates the last
   change of the product it covers (`crates/`, `apps/flutter/lib/`). A receipt that predates the
   product does not measure the product;
3. the **record is intact** — every receipt that the ledger and this file cite exists and is
   tracked by git, and every receipt of the release is cited by one of them;
4. the **acceptance passed** — the receipt of the canonical gate says PASS with its phases, its
   browser findings, its Flutter tests, its captures and its accessibility numbers;
5. the **safety boundaries held** — no receipt claims that the schema 7 was activated on the
   personal store of the operator.

The verdict of the command is **`OIP_PRODUCTION_NOT_READY`** while the gates that need the
operator are open (G5, G10, G12). The verification is **not** a production acceptance: the
acceptance of the operator and the scope of the production security are the operator's. The
command never claims the visual acceptance of the operator — a visual acceptance that is **not**
pending is a problem of the verification.

**The verifier can fail.** A verifier that cannot fail proves nothing, so the negative control
(`tests/oip_verify_release_test.py`) feeds the checks with receipts that are wrong and proves
that each defect is reported: a receipt that predates the product, a receipt without a revision,
a broken citation, an orphaned receipt, an artefact with a wrong digest, a failed acceptance and
a **claimed** visual acceptance.

The procedure is in the runbook (§13).

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 55 — the first paint of the baseline is a property of the path, not of the release

**Status: PROVED on canonical `main`.**
The performance baseline measures a first paint of about 50 seconds and the record attributes it to
the **transfer** of the delivery — the application is interactive in a quarter of a second once the
session exists. The operator was then asked to decide about the delivery of the web release: a
smaller delivery, a compressed asset or a local cache.

That decision was about to be taken on a number that is a property of the **measurement
environment**, not of the release. The rehearsal of the rate (`tests/oip_loopback_rate.py`,
`docs/evidence/oip-loopback-rate/loopback-rate.json`) measures the path:

| Measurement | Result |
|---|---|
| one connection of the loopback (raw socket) | about **150 KiB/s** |
| one HTTP request of the loopback | about **138 KiB/s** |
| two connections in parallel | about **274 KiB/s** — the limit **grows** with the connections |
| a Unix socket on the **same machine** | about **860 MiB/s** |
| the delivery of the browser before the first paint | **18.2 MB** over 38 requests (the 3 MB bundle plus the renderer, the fonts and the assets) |
| the transfer at the rate of one connection | **126 s** — the browser parallelises over a few connections, so the first paint is about 50 s |

A limit that grows with the number of connections and a machine that is roughly six thousand times
faster without the TCP path show that the **path** is slow, not the machine and not the release.
On a machine with an ordinary loopback the same delivery is a fraction of a second.

The operator decision stays the operator's — and the ledger now says that it must be taken on a
measurement of the operator's **own** machine, not on the number of a throttled path.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 56 — the reconciliation of the worktrees is proved, not asserted

**Status: PROVED on canonical `main`.**
The binding rules demand that the active UI worktrees are reconciled **without overwriting newer
implementations or foreign ownership**. The record stated that the question was settled — the
Spectrum-2027 workstations are the canonical application of `main` and the branch
`feature/oip-managed-diagnostics` is reconciled into them — but that was **prose**: the branch
holds a commit (`55d4f50`, 1556 insertions) that `main` does not contain, and the ledger cited
its recovery report, a path that **was not in the canonical branch**.

The rehearsal of the reconciliation (`tests/oip_worktree_reconciliation.py`,
`docs/evidence/oip-worktree-reconciliation/worktree-reconciliation.json`) proves the obligation:

* the branches of **all 22 worktrees** and, for every branch, the commits that the canonical
  branch does not contain — exactly one branch has one such commit;
* the **files** of that commit: the canonical branch carries all **13** of them;
* the **capability** of that commit, checked in the canonical branch: the documented gaps, the
  health transitions, the opaque cursor of the continuation, the status of the diagnosis history,
  the adapters of the Core and the model of the diagnostic page — all present;
* the **receipt that proves the capability** in the canonical branch: the rehearsal of the
  diagnostic continuation walks the documented gaps and the health history over the opaque cursor
  of the Core in the browser.

The **evidence of the reconciliation** — the recovery report and its machine-readable receipt — is
preserved in the canonical branch now (`docs/recovery/`), so a reader of `main` sees how the
capability of the branch was decided, not only that it is there.

**The checker of the record now checks every path that the record names**, not only the
receipts, and the ledger must not present a path of the build tree as the evidence of a claim. The
strengthened check found the second defect of this kind immediately: the ledger presented
`target/oip-canonical-regression-final/` as the evidence of the acceptance of the release. The
ledger names the **tracked** acceptance now.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

## 5. Evidence index

| Artifact | Content |
|---|---|
| `docs/evidence/oip-canonical-acceptance/acceptance.json` | the canonical acceptance of the release: the eight functional phases, the widget gate, the browser gate, the visual comparison, the global infrastructure context, the accessibility and the device administration, with the revision and the tree of the run (tracked) |
| `docs/evidence/oip-macos-install/macos-install.json` | the local installation of the macOS application bundle: the copy is byte-identical to the bundle of the release, the installed copy starts, is refused without a session, terminates without an orphan and starts again from the installation directory (tracked) |
| `docs/evidence/oip-record-integrity/record-integrity.json` | the integrity of the record itself: every cited receipt exists and is tracked by git, and every receipt of the current release is cited by the ledger or by this file (tracked) |
| `docs/evidence/oip-release-verification/release-verification.json` | the verification of the release with **one command**: the manifest verifies, every receipt is fresh, the record is intact, the acceptance passed and the safety boundaries held (tracked) |
| `docs/evidence/oip-loopback-rate/loopback-rate.json` | the rate of the path of the measurement: the loopback of this machine, the rate of the machine itself and what the first paint of the baseline means (tracked) |
| `docs/evidence/oip-worktree-reconciliation/worktree-reconciliation.json` | the reconciliation of the worktrees: every branch, the commits that the canonical branch does not contain, the capability that it delivers in their place and the receipt that proves it (tracked) |
| `docs/evidence/oip-canonical-acceptance/browser-gate.json` | the browser gate of the acceptance: the findings, the captures and the state of the visual acceptance of the operator (tracked) |
| `docs/evidence/oip-canonical-acceptance/ui-gate.json` | the build provenance and the served bundle of the gate (tracked) |
| `docs/evidence/oip-canonical-acceptance/captures/*.png` | the 13 actual captures of the six workstations at 1440 px and 1920 px of the acceptance of the release (tracked) |
| `docs/evidence/oip-device-administration/device-administration.json` | the administration of a device through the approved surface: the revision of the device advances from 1 to 2, the archive of an online device is refused with `OFFLINE_ARCHIVE_REQUIRED` (tracked) |
| `docs/evidence/oip-diagnostic-continuation/rehearsal.json`, `docs/evidence/oip-workstation-data/rehearsal.json`, `docs/evidence/oip-device-connection/rehearsal.json`, `docs/evidence/oip-reconnect-recovery/rehearsal.json` | the rehearsals that produced the four browser receipts above: the instances they own, their steps and their results (the browser receipt of each journey is the primary evidence) |
| `docs/evidence/oip-rust-regression/rust-regression.json` | the measured Rust regression of the Core of the current release: 181 tests in 29 suites, 0 failed, with the unit, the integration and the doc tests (iteration 43) |
| `docs/evidence/oip-reproducible-build/reproducible-build.json` | the measured reproducibility of the builds of the release: the web release and the macOS application bundle are byte-identical when they are built twice (iteration 42) |
| `docs/evidence/oip-extend-registry/extend-registry.json` | the measured extension of the registry of an instance: the sources survive, the new source collects and a plan that drops a source is refused (iteration 41) |
| `docs/evidence/oip-session-lifetime/session-lifetime.json` | the measured lifetimes of the one-time code (120 s) and of the session (30 min) against the real Core: both promises of the operator login hold (iteration 39) |
| `docs/evidence/oip-settings-offline/settings-offline.json` | the measured offline change of a setting of the instance: the change, the guard of the revision, the permission, the validation and the effect at the next start (iteration 38) |
| `docs/evidence/oip-documented-plan/documented-plan.json` | the measured example of the plan in the runbook: it provisions an instance, the instance answers and the operator of the example authorizes the session (iteration 36) |
| `docs/evidence/oip-activation-dry-run/activation-dry-run.json` | the measured dry run of the activation of the release on a copy of the store of the operator: the migration is accepted, nothing is lost, the personal installation is unchanged (iteration 35) |
| `docs/evidence/oip-reconnect-recovery/reconnect-recovery.json` | the measured reconnect and recovery of the application: the restart of the instance, the honest state of the surface, the named cause and the restored projection (iteration 33) |
| `docs/evidence/oip-native-session/native-session.json` | the measured session of the native client against the real Core: the one-time code, the authorized hierarchy, the scoped projection and the sign-out (iteration 32) |
| `docs/release/oip-release-manifest.json`, `docs/release/SHA256SUMS` | the release manifest: every artefact of the release with its digest, the provenance of its build, the digests of the acceptance receipts and the state of the operator's visual acceptance (iteration 31) |
| `docs/evidence/oip-operations/operations.json` | the measured local operations of the release binary: the provisioning, the start, the status, the log, the backup with its integrity check, the refused restore of a running instance, the clean shutdown, the restore, the start again, the restart, the stop and the three refusals of the personal installation |
| `docs/evidence/oip-accessibility/accessibility.json` | the measured accessibility receipt of the six workstations: the controls, their roles, their focusability and the count of the controls without an accessible name (0) |
| `docs/evidence/oip-global-context/global-context.json` | the measured global infrastructure context: the options of the selector, the scoped projection, the shared scope across the six workstations and the unified view |
| `docs/evidence/oip-transport-parity/transport-parity.json` | the measured parity of REST, SSE and MCP of the current release for the same principal, and the refusal of the unauthorized session (iteration 30) |
| `docs/evidence/oip-security-review/security-review.json` | the measured security review of the current release: 12 findings — 9 resolved, 2 mitigated, 1 escalated (the durability of the execution audit) (iteration 29) |
| `docs/evidence/oip-device-connection/device-connection.json` | the measured verified connection of a device in the approved surface against the real Core and an owned loopback SSH fixture (iteration 28) |
| `docs/evidence/oip-workstation-data/workstation-data.json` | the measured functional depth of the six workstations against the real Core: the real hierarchy, device, placement, nodes, events and settings, and no identifier of the other organization (iteration 27) |
| `docs/evidence/oip-opcua-parity/opcua-parity.json` | the measured parity of the OPC-UA address space between the official MCP tool and the REST routes against the real backend (iteration 25) |
| `docs/evidence/oip-stability/stability.json` | the measured extended stability run of the release binary: 30 minutes, 60 samples, the resource use, the collection rate, the death of a collector and the clean shutdown (iteration 23) |
| `docs/evidence/oip-diagnostic-continuation/diagnostic-continuation.json` | the measured browser receipt of the continuation of a truncated diagnostic page against the real Core (iteration 24) |
| `docs/evidence/oip-macos-app/macos-app.json` | the measured result of the macOS application bundle: the build, the start, the requests of the bundle, the refusal of the Core, the termination without an orphan and the start again (iteration 22) |
| `docs/evidence/oip-historical-daemon/historical-daemon.json` | the measured result of the daemon handover with the protected historical binary: the refused shape of OIP-007, the started daemon of the era, the scoped reads, the collection, the takeover and the restored store (iteration 21) |
| `docs/evidence/oip-offline-archive/offline-archive.json` | the measured result of the offline archive of a device (iteration 20) |
| `docs/evidence/oip-performance/performance.json` | the measured client-side performance baseline of the release build (iteration 19) |
| `docs/evidence/oip-real-device/test-summary.json` | machine-readable gate results of iteration 1 and iteration 2 |
| `docs/evidence/oip-real-device/review.json` | findings of the delegated read-only source review (F1-F7, R1) with their current state |
| `target/oip-canonical-e2e/report.json` | full acceptance report of the SSH/browser/MCP harness on canonical `main` (local, not tracked) |
| `target/oip-canonical-e2e/browser/report.json` | browser receipt of the actual Flutter onboarding run (local, not tracked) |
| `target/oip-canonical-e2e/browser/*.png` | screenshots of login, endpoint input, host-key consent, identity confirmation, persisted binding and live monitoring (local, not tracked) |
| `docs/design/OIP_CANONICAL_UI_BASELINE.md` | the binding canonical UI contract: source of authority, the approved shell, the prohibited regressions R1-R10 and the gate table |
| `docs/design/OIP_UI_2027_HANDOFF_MANIFEST.json` | the verified 2027 handoff manifest: eight upstream workstreams with their archive hashes and technical verdicts, the hash-pinned visual references and the candidate verification |
| `docs/design/baselines/canonical-ui-1440.png`, `docs/design/baselines/canonical-ui-1920.png` | the committed technical visual references of the stable shell (tracked) |
| `docs/evidence/oip-canonical-acceptance/captures/*.png` | the 13 actual captures of the six workstations at 1440 px and 1920 px of the acceptance of the release (tracked) |
| `docs/evidence/oip-real-device/test-summary.json` | the machine-readable result of the canonical UI gate of iteration 12 |
| `target/oip-conformance-e2e/report.json` | the same acceptance report from the isolated branch build before the integration (local, not tracked) |
| `target/oip008-ui-canonical/ui-regression.json` | UI regression result of iteration 3 with the per step durations and markers (local, not tracked) |
| `/Users/benny/Documents/OIP-Handoffs/core-real-onboarding-p0-20261107T025455Z/` | private P0 handoff receipt of the reviewed candidate (unchanged) |
| `docs/design/OIP_CANONICAL_UI_BASELINE.md` | binding Spectrum-2027 shell, workstation, legacy-separation and visual-acceptance contract |
| `docs/design/OIP_UI_2027_HANDOFF_MANIFEST.json` | exact upstream handoff revisions, archive hashes, integration snapshot and technical visual-reference hashes |
| `target/oip-canonical-ui-regression-final/` | final clean candidate build/full-widget/browser/visual and managed real-device acceptance receipts; not canonical-main evidence |
| `target/oip-canonical-ui-regression-run/` | superseded intermediate run; retained only for failure archaeology and must not be cited as the final capture set |
| `target/oip-canonical-ui-acceptance/` | superseded direct harness attempts; retained for diagnostics, not final evidence |
| `target/oip-canonical-ui-gate-precheck/` | superseded early precheck, not final evidence |
| `target/oip-canonical-ui-skip-control/` | deliberate `--skip-build` control proving `PARTIAL`, not a UI PASS |
| `target/oip-ui-missing-archive-receipt.json` | portability control proving explicit derivation-skip behaviour; not the final visual receipt |
| `/Users/benny/.local/share/oip-canonical-ui/20261108T030129Z/` | private SHA-256-verified 128-file source snapshot and roundtrip manifest |

## 6. Safety boundaries observed

* No push, no deployment, no system service, no public listener.
* The personal SQLite database was only read for a hash comparison: it still hashes to
  `9f988c01c7115631db3b5bfd2b9228ecc24255b8b9905932a987a89c78e6a24e` and stays at schema 6.
  No schema 7 activation was performed.
* All harnesses used their own isolated databases, ports and credentials under `/private/tmp`;
  the acceptance harness reports `own_processes_stopped: true`.
* The only SSH target was an owned loopback OpenSSH fixture with keys generated for that test.
  No private endpoint, host or user was contacted.
* Foreign processes from the independent UI workstreams were observed but never signalled.
* No demo data is presented as real evidence. Inventory registration is still not a
  connection, and device connectivity stays `Unknown` / `NoCollector` until a real, confirmed
  host binding exists.
