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
| Canonical source revision | `e9036ef` (`feat(flutter): show the authorized placement in the managed network view`) |
| Canonical source tree | `665a9a566779534c6646a4e53acf8955be1839fc` |
| Previous canonical source revision | `1e6b743` (iteration 10, managed overview of the authorized infrastructure) |
| Integration method | real `git merge --ff-only`, no merge commit, no rewrite, in eleven controlled steps |
| Tracked files in the canonical source revision | 451, source manifest SHA-256 `cfd9fc247352cbcd457a0fed3b59d7b2a60e1413ee41831f35db458df15f39eb` |
| Documentation commit on top | changes only `docs/OIP_RELEASE_PROGRESS.md`, `docs/evidence/oip-real-device/*.json` and `docs/real-device-onboarding-verification.md`; no source, contract, harness or test file is touched, so the manifest above stays the manifest of the source revision |
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

## 2. Acceptance gates and their measured status

Legend: `PROVED` = measured in this run on canonical `main`; `WITHHELD` = deliberately not
claimed; `BLOCKED` = cannot be executed without an explicit external decision.

| Gate | Status | Evidence (this run, canonical `main` = `e9036ef`) |
|---|---|---|
| Rust format check | PROVED | `cargo fmt --all -- --check` → exit 0 |
| Rust workspace check | PROVED | `cargo check --locked --workspace --all-targets` → exit 0 |
| Rust clippy, warnings denied | PROVED | `cargo clippy --locked --workspace --all-targets -- -D warnings` → exit 0 |
| Rust workspace tests | PROVED | 181 passed, 0 failed (45 of them Storage); no Rust source changed in iteration 10, so the result of iteration 9 stays valid for this tree |
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
| N11 canonical Spectrum-2027 UI baseline and design regression gate | **DONE, closed in iteration 12** | the two parallel executions of the same integration were reconciled into one candidate, the full gate is PASS on `{REV}` and the candidate is integrated into canonical `main` with `git merge --ff-only`; operator visual approval remains `VISUAL_PENDING_OPERATOR_ACCEPTANCE` |

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
| first paint of the delivered web release | 48 216 ms | 47 992 ms | 52 241 ms |
| the operator login of the anonymous state | 48 508 ms | 48 357 ms | 52 495 ms |
| the interactive shell with the six workstations | 245 ms | 233 ms | 277 ms |
| the authorized projection of the infrastructure | 101 ms | 97 ms | 276 ms |

The Core rests at 17 200 KiB of resident memory and 0.0 % CPU without clients. The delivered
bundle is `b09bb5ff4a16825ddf350f9278aa94a378f42222bbb5e23af0f76ed7bef2b844` — the same asset the
canonical gate proves.

**What the baseline says.** The first paint is **not** bound to the application: it is bound to the
transfer of the 3 MB web release over the loopback of this machine. Once the session exists, the
shell with all six workstations is interactive in a quarter of a second and the authorized
projection follows 101 ms later. A smaller delivery — or a local cache of the release — is a
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
| the collection of the daemon | the sources of the scope become fresh, 131 observations are persisted |
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
  `org.openindustrial.oipDashboard`, version 0.3.0) in 59 s; the receipt names the sha256 of the
  executable.
* The bundle starts and asks the Core for the authorized projection of the principal within
  **0.8 s**.
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
| the resident memory | between 17 280 and 19 728 KiB, **−1 184 KiB** from the first to the last sample |
| the CPU | 2.12 % on average, 4.8 % at most |
| the collection | 41 549 observations, 1 396 per minute, constant over the run |
| the growth of the store | 536 KiB to 78 MiB under the load of the collectors |
| the log | 16 KiB to 137 KiB — no runaway |
| the death of a collector | noticed and recorded as a documented gap, the collection resumed 3 s later |
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
real collection, 45 cycles in this run — and the browser journey
(`apps/flutter/test/browser_diagnostic_continuation.mjs`) then follows the evidence in the
approved shell. Measured (`docs/evidence/oip-diagnostic-continuation/diagnostic-continuation.json`):

* the Core answers the first page with 50 entries, `truncated: true` and a cursor;
* the surface offers the continuation for the gaps and for the health history;
* the continuation asks the same authorized route with the opaque cursor of the Core
  (`4240ab50…`, `4a564390…`, `7c8d8702…`);
* the pages are disjoint: 51 rows of gaps, 51 distinct — no row is repeated and no row is lost;
* the health history needed three continuations (50 + 50 + 50 + 9 transitions) and ends
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
change can repeat a node at the boundary — measured once, while the collector was connecting.
Every other paginated surface of the Core (the diagnostic pages, the observation history) uses an
opaque cursor and is therefore stable; the Core makes no such promise for the address space, so
no claim is broken. Giving the address space the same cursor would change the query of the REST
and MCP surface of the Core: that is a **contract decision of the operator** and is named as such
in the ledger.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 26 — the final acceptance of the release candidate, bound to the tree

**Status: PROVED on canonical `main` (`4458d34`), tree `09f4cad`.**
The canonical acceptance was run once more on the clean tree after every change of this
iteration, with the **release** binary and the delivered web bundle
(`target/oip-canonical-regression-final/`). The receipt names the tested artefacts:

| Artefact | Value |
|---|---|
| the tested revision | `4458d347a203d6038ced5dc63dc0f0c40c8bfe51` |
| the tested tree | `09f4cad5fc737cfd4fba28bf7d8005715eff491f` |
| the tree during the run | clean (`source_dirty: false`) |
| the release binary (`target/release/oip-server`) | `835ed0a197f41d8dbc9460f9cdf5a997ae54417647012d161b612606f9cd24bc` |
| the official MCP probe | `029bf9f4505dd483d62196992d0443498a3e5a242f35a3192a4ef125227cfb08` |
| the served `main.dart.js` | `b09bb5ff4a16825ddf350f9278aa94a378f42222bbb5e23af0f76ed7bef2b844`, 3 031 151 bytes |
| the served bundle equals the local build | **yes**, byte by byte |
| the Flutter tests | 344 passed, 0 failed |
| the browser gate | 175 findings, 0 failed, 13 captures, no console error, no external request |
| the visual comparison | **PASS** |
| the eight functional phases | 8 of 8 **PASS** |
| the verdict of the gate receipt | **PASS** |
| the operator visual approval | `VISUAL_PENDING_OPERATOR_ACCEPTANCE` |
| the own processes | stopped |

The visual acceptance of the operator stays **pending**: the gate proves that the rendered
surface is the approved Spectrum-2027 shell and that it matches the committed technical
references, but only the operator can accept it.

**One honest remark about the binaries.** The web bundle is byte-identical between the builds
(`b09bb5ff…`), the Rust release binary is not: the gate rebuilds it and its sha256 differs from
the build of the earlier rehearsals (`76d18b6e…`, `6afee854…`). Every receipt names the binary
it actually executed, and no receipt claims a hash of a binary it did not run.

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

Two findings of the rehearsal are part of the receipt: the settings of the instance are read in
the scope of the selected source (the application section reads the platform scope, which this
principal is **not** allowed to read — deny by default), and the operator reaches the scoped
section through the category `Diagnostics` of the settings navigation.

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
   consent of the operator (`SHA256:PVA1Yx1uOkaKGQyK39dmqfCRdLnWxdNgOARfm1G1IHA`);
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

## 5. Evidence index

| Artifact | Content |
|---|---|
| `target/oip-canonical-regression-final/` | the final canonical acceptance on the clean tree `4458d34` / `09f4cad`: the widget gate, the browser gate, the visual comparison, the eight functional phases and the gate receipt (iteration 26, local, not tracked) |
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
| `docs/evidence/oip-canonical-ui/*.png` | the 13 actual captures of the six workstations at 1440 px and 1920 px of iteration 12 (local, per the evidence policy) |
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
