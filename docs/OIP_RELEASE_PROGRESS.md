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
| Canonical source revision | `e12c009` (`test(core): address the browser module of the real device harness by an absolute path`) |
| Canonical source tree | `56307de71e612563e38cf2657d7bf1cd34a0ce35` |
| Previous canonical source revision | `f4b89ed` (iteration 7, schema2 adoption and parity gate) |
| Integration method | real `git merge --ff-only`, no merge commit, no rewrite, in eight controlled steps |
| Tracked files in the canonical source revision | 446, source manifest SHA-256 `23277ea50a08d9b9cc874dabc1482e59eece54706f86e0b87c55a3c28adf95de` |
| Documentation commit on top | changes only `docs/OIP_RELEASE_PROGRESS.md`, `docs/evidence/oip-real-device/*.json` and `docs/real-device-onboarding-verification.md`; no source, contract, harness or test file is touched, so the manifest above stays the manifest of the source revision |
| Working tree | clean; the loop state directory is ignored |
| Push / deployment | none |
| Real installation | **not activated**; the personal SQLite database is untouched at schema 6 |

The canonical tree carries eight controlled integrations: iteration 1 integrated the reviewed
real device onboarding candidate `ae4c6ba` (tree `f72cb66`) unchanged, iteration 2 integrated
the isolated conformance branch `feature/oip-real-device-conformance` (`fc828ac`), iteration 3
integrated the isolated harness branch `feature/oip-native-macos-harness` (`b19092d`), iteration 4
integrated the isolated payload branch `feature/oip-connection-payload-bound` (`5a48b0c`) and
iteration 5 integrated the isolated contract branch `feature/oip-009-context-contract`
(`d32c9d1`), iteration 6 the isolated regression branch `feature/oip-canonical-regression`
(`111dff1`), iteration 7 the isolated baseline branch `feature/oip-007-baseline-adoption`
(`6df189f`) and the isolated parity gate branch `feature/oip-parity-gate-convergence`
(`f4b89ed`), iteration 8 the isolated monitoring branch
`feature/oip-monitoring-observations` (`2ec4829` and `e12c009`). No iteration weakened a contract
rule, and none activated the installation.

## 2. Acceptance gates and their measured status

Legend: `PROVED` = measured in this run on canonical `main`; `WITHHELD` = deliberately not
claimed; `BLOCKED` = cannot be executed without an explicit external decision.

| Gate | Status | Evidence (this run, canonical `main` = `ae4c6ba`) |
|---|---|---|
| Rust format check | PROVED | `cargo fmt --all -- --check` → exit 0 |
| Rust workspace check | PROVED | `cargo check --locked --workspace --all-targets` → exit 0 |
| Rust clippy, warnings denied | PROVED | `cargo clippy --locked --workspace --all-targets -- -D warnings` → exit 0 |
| Rust workspace tests | PROVED | 180 passed, 0 failed (45 of them Storage) |
| OPC-UA default backend | PROVED | 37 passed, 0 failed |
| OPC-UA open62541-only backend | PROVED | 2 passed, 0 failed (overlapping group) |
| Dependency policy | PROVED | `cargo deny check advisories licenses bans sources` → advisories ok, bans ok, licenses ok, sources ok |
| Server binary + official MCP probe | PROVED | `cargo build --locked -p oip-server --bin oip-server --example mcp_probe` → exit 0 |
| Flutter static analysis | PROVED | `flutter analyze` → exit 0, no issues |
| Flutter widget/unit suite | PROVED | 89 passed, 0 failed |
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
| Browser session boundary in Rust | PROVED | `crates/oip-server/tests/browser_session.rs` → 5 tests: exact Origin, single-use code, CSRF on every write, revoked session, revoked projection stream |
| Native macOS build and test | PROVED | `tests/oip008/ui_regression.py` → native build 11.6 s with the build marker, native integration test 39.1 s with the `All tests passed!` marker, against an owned isolated demo core |
| Legacy browser, interaction and visual regression | PROVED | browser 80.4 s, interactions 47.1 s, visual 63.4 s on the separately built HTML renderer |
| Milestone acceptance harnesses on the canonical tree | PROVED | `tests/canonical_regression.py`: OIP-008, OIP-008.2, OIP-008.2 schema3 migration, OIP-008.4, OIP-008.5, OIP-008.5 migration, the UI regression and the schema2 adoption all PASS on the canonical tree, no failed and no blocked case |
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
| N6 persisted observation history | **READY** | the next step of the loop |
| N7 monitoring measurements in the panel | **DONE** | closed in iteration 8 |

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

### N6 — Persisted observation history in the device view — **READY**

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

### N7 — Monitoring measurements in the operator panel — **DONE, closed in iteration 8**

The device connection panel now renders the current authorized observations of the connection
view. See the iteration log below.

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

## 5. Evidence index

| Artifact | Content |
|---|---|
| `docs/evidence/oip-real-device/test-summary.json` | machine-readable gate results of iteration 1 and iteration 2 |
| `docs/evidence/oip-real-device/review.json` | findings of the delegated read-only source review (F1-F7, R1) with their current state |
| `target/oip-canonical-e2e/report.json` | full acceptance report of the SSH/browser/MCP harness on canonical `main` (local, not tracked) |
| `target/oip-canonical-e2e/browser/report.json` | browser receipt of the actual Flutter onboarding run (local, not tracked) |
| `target/oip-canonical-e2e/browser/*.png` | screenshots of login, endpoint input, host-key consent, identity confirmation, persisted binding and live monitoring (local, not tracked) |
| `target/oip-conformance-e2e/report.json` | the same acceptance report from the isolated branch build before the integration (local, not tracked) |
| `target/oip008-ui-canonical/ui-regression.json` | UI regression result of iteration 3 with the per step durations and markers (local, not tracked) |
| `/Users/benny/Documents/OIP-Handoffs/core-real-onboarding-p0-20261107T025455Z/` | private P0 handoff receipt of the reviewed candidate (unchanged) |

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
