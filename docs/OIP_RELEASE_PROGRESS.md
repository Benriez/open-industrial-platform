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
| Canonical source revision | `b19092d` (`fix(harness): split the native macOS build from the native test`) |
| Canonical source tree | `a45555428c165365ab14f7248a20c3382379e648` |
| Previous canonical source revision | `fc828ac4a0afd2020fef646b4630eb0ab90f99cc` (iteration 2, conformance fixes) |
| Integration method | real `git merge --ff-only`, no merge commit, no rewrite, in three controlled steps |
| Tracked files in the canonical source revision | 442, source manifest SHA-256 `32373b5375a3898f5c49747bfef83a833320a13066d98402de731799ef113c36` |
| Documentation commit on top | changes only `docs/OIP_RELEASE_PROGRESS.md`, `docs/evidence/oip-real-device/*.json` and `docs/real-device-onboarding-verification.md`; no source, contract, harness or test file is touched, so the manifest above stays the manifest of the source revision |
| Working tree | clean; the loop state directory is ignored |
| Push / deployment | none |
| Real installation | **not activated**; the personal SQLite database is untouched at schema 6 |

The canonical tree carries three controlled integrations: iteration 1 integrated the reviewed
real device onboarding candidate `ae4c6ba` (tree `f72cb66`) unchanged, iteration 2 integrated
the isolated conformance branch `feature/oip-real-device-conformance` (`fc828ac`), iteration 3
integrated the isolated harness branch `feature/oip-native-macos-harness` (`b19092d`). No
iteration weakened a contract rule, and none activated the installation.

## 2. Acceptance gates and their measured status

Legend: `PROVED` = measured in this run on canonical `main`; `WITHHELD` = deliberately not
claimed; `BLOCKED` = cannot be executed without an explicit external decision.

| Gate | Status | Evidence (this run, canonical `main` = `ae4c6ba`) |
|---|---|---|
| Rust format check | PROVED | `cargo fmt --all -- --check` → exit 0 |
| Rust workspace check | PROVED | `cargo check --locked --workspace --all-targets` → exit 0 |
| Rust clippy, warnings denied | PROVED | `cargo clippy --locked --workspace --all-targets -- -D warnings` → exit 0 |
| Rust workspace tests | PROVED | 175 passed, 0 failed (44 of them Storage) |
| OPC-UA default backend | PROVED | 37 passed, 0 failed |
| OPC-UA open62541-only backend | PROVED | 2 passed, 0 failed (overlapping group) |
| Dependency policy | PROVED | `cargo deny check advisories licenses bans sources` → advisories ok, bans ok, licenses ok, sources ok |
| Server binary + official MCP probe | PROVED | `cargo build --locked -p oip-server --bin oip-server --example mcp_probe` → exit 0 |
| Flutter static analysis | PROVED | `flutter analyze` → exit 0, no issues |
| Flutter widget/unit suite | PROVED | 84 passed, 0 failed |
| Flutter web release, CanvasKit | PROVED | `flutter build web --release --web-renderer canvaskit …` → exit 0 |
| Flutter web release, HTML | PROVED | `flutter build web --release --web-renderer html …` → exit 0 |
| Browser identity + writer ownership | PROVED | `tests/real_device/acceptance.py` phase `browser_identity_online_writer` → PASS |
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

Each item names the next *delimited* step, its gate and its blocker. N1 and N2 are closed. The
loop continues with item **N1b**; the remaining items stay untouched until the preceding one is
verified. Items that need an explicit operator decision (N4) or that would change a rule instead
of enforcing one (F5 inside N1b) are not started by the loop without a separate release.

### N1 — Close the conformance gaps found by the delegated source review (Core)

A read-only source review against `docs/architecture/real-device-onboarding.md` produced the
findings below. They are contract conformance defects, not new architecture. Fix them on an
isolated feature branch, add Rust-level regression tests, re-run the full gate set above and
integrate with the same controlled fast-forward.

**Status: F1, F2, F3, F6, F7 and R1 are fixed and verified in iteration 2.** F4 and F5 remain
open and are split off as N1b below because they change a storage bound and an authorization
rule and need their own explicit review.

| Id | Severity | Location | Defect | Contract reference | Status |
|---|---|---|---|---|---|
| F1 | medium | `crates/oip-server/src/ssh.rs` (`minimum_key_bits`, `parse_key_report`, `scan`) | The server never enforced "RSA keys require at least 2048 bits". `ssh-keygen -lf` already prints the key size, but only the fingerprint was kept; enforcement was delegated to the `RequiredRSASize=2048` client option of the *user* connection. A weak `ssh-rsa` host key could be scanned, shown, trusted and pinned. | `docs/architecture/real-device-onboarding.md:48` | **fixed** |
| F2 | low/medium | `crates/oip-server/src/ssh.rs` (`run`) and `crates/oip-server/src/connection_service.rs` (`read`) | `REMOTE HOST IDENTIFICATION HAS CHANGED` **and** `Host key verification failed` were both mapped to `SSH_HOST_KEY_CHANGED`, so an unknown key was reported as a rotation alarm. | `docs/architecture/real-device-onboarding.md:23`, `:66` | **fixed** |
| F3 | low | `crates/oip-server/src/browser_session.rs` (`login`) | The invalid-code limiter was evaluated *before* the grant lookup, so 16 malformed codes blocked the operator's valid single-use code for 60 s. Local-process availability bug inside the session boundary. | `docs/architecture/real-device-onboarding.md:36` | **fixed** |
| F4 | low | `crates/oip-server/src/ssh.rs` (`parse`) vs `crates/oip-storage/src/connection.rs` | The maximal host report the parser can build (up to ~128 KiB of interface/disk text) exceeds the 128 KiB `payload_json` CHECK, so a legal but extreme remote report fails the commit with an opaque storage error instead of a typed fault. | `docs/architecture/real-device-onboarding.md:50`, `:58` | open → N1b |
| F5 | low | `crates/oip-server/src/connection_service.rs` (`check_plan`) | The read path requires `DeviceConnectionConfigure`; the contract places `GET /device-connections?plan_id=…` under `DeviceConnectionRead`. Conservative over-restriction, not an escalation. | `docs/architecture/real-device-onboarding.md:15` | open → N1b |
| F6 | low | `crates/oip-server/src/browser_session.rs` (`login`) | The session-capacity check ran after the single-use grant was already consumed, so a valid code was destroyed when 64 sessions existed. | `docs/architecture/real-device-onboarding.md:36` | **fixed** |
| F7 | low | `crates/oip-server/src/ssh.rs` (`private_workdir`) | The SSH work directory was created with the process umask and only afterwards chmod'ed to 0700, leaving a brief world-readable window. | `docs/architecture/real-device-onboarding.md:48` | **fixed** |
| R1 | test gap | `crates/oip-server/tests/browser_session.rs` | No Rust-level test covered the browser session/CSRF/Origin flow; those assertions only existed in the external harness `tests/real_device/acceptance.py`. | `docs/architecture/real-device-onboarding.md:37-39` | **fixed** |

### N1b — Remaining conformance items (storage bound and authorization rule)

Two findings are deliberately *not* mixed into the security fix, because both change a rule
instead of enforcing the existing one and need their own review and evidence:

* **F4 (storage bound).** Reconcile the maximal host report the SSH parser can build with the
  128 KiB `device_connections.payload_json` CHECK, and length check the serialised record
  before the transaction so an extreme report fails with a typed fault instead of a rollback.
  Gate: a regression test that commits a maximal report and one that proves a typed failure.
* **F5 (authorization rule).** Decide, against the contract table in
  `docs/architecture/real-device-onboarding.md:15`, whether `GET /api/v2/device-connections?plan_id=…`
  is governed by `DeviceConnectionRead`. The change loosens a permission and therefore needs an
  explicit authorization review, a negative test for a foreign principal and a parity update in
  `docs/architecture/oip-008-rest-mcp-parity.md` if the capability matrix changes.

### N2 — Native macOS build and test (open acceptance item) — **closed in iteration 3**

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

### N3 — OIP-009 browser session / SSE / global context contract (contract gap)

`docs/oip-0082-verification.md:116`, `docs/oip-0084-verification.md:134`,
`docs/architecture/oip-0085-real-inventory-flutter-contract.md:3` and
`docs/architecture/real-device-onboarding.md:88-90` all defer the global context to OIP-009.
The implemented part (one-use pairing code, `HttpOnly; SameSite=Strict` cookie, exact Origin,
`x-oip-csrf`, session-scoped SSE revalidation, `setInfrastructureContext` cache invalidation)
exists in the canonical tree; the *contract document* and the global Organization /
Infrastructure / Site selection do not. The contract document may only describe what is
implemented and must not invent a second global switcher; the final OIP-009 payload still
requires the three-way reconciliation of controller, API, contracts and the independent UI
workstreams. No architecture decision is taken in this file.

### N4 — Controlled activation of the real installation (operator decision required)

Blocked by explicit instruction and by risk. The candidate opens schema 7; the personal
database is at schema 6 and must not be changed here. Required before activation: a fresh
consistent database/config/profile backup, the protected schema 6 rollback copy, one daemon,
one `--browser-login` code, the explicitly confirmed endpoint for
`tools/configure_ssh_profile.py` (dry run first) and the physical Raspberry-Pi acceptance that
belongs to the still withheld hardware verdict.

### N5 — Production advisories and remaining security work

RUSTSEC-2023-0071, RUSTSEC-2023-0089 and RUSTSEC-2024-0449 remain documented and ignored
with the existing local-only exceptions; no exception was added or widened. The `deny.toml`
ignore reasons for RUSTSEC-2023-0089 and RUSTSEC-2024-0449 do not match the actual advisory
subjects and should be corrected against the advisory database. Productive remote/browser
identity, hostile same-UID isolation, tamper-proof durable audit and OT/endurance certification
stay open and are not claimed by this release.

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
