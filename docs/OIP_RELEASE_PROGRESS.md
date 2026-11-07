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
| Canonical source revision | `ae4c6bab4fb87ff2c7b15a21b0104b2d5a12af7f` |
| Canonical source tree | `f72cb667c16b6e6a75efd72b725c81031788fd26` |
| Previous canonical source revision | `49a86bb0aa9f737fe9392eb2b5421e1ffe2f8c68` (OIP-008.5) |
| Integration method | real `git merge --ff-only feature/real-device-onboarding-integration`, no merge commit, no rewrite |
| Tracked files in the canonical source revision | 438, source manifest SHA-256 `16b9a815bee276e383aa1ca9e2616ff601ce2026d0629aab40e4f4083ad7ae09` |
| This iteration's commit | documentation only: this file, the verification addendum, two curated evidence files and `.gitignore`. No Rust, Flutter, contract or harness file is modified. |
| Working tree | clean; the loop state directory is ignored |
| Push / deployment | none |
| Real installation | **not activated**; the personal SQLite database is untouched at schema 6 |

The canonical source tree is byte-identical to the previously reviewed candidate
`ae4c6ba` / tree `f72cb66` from the P0 handoff
(`/Users/benny/Documents/OIP-Handoffs/core-real-onboarding-p0-20261107T025455Z/`).
This iteration changed **no runtime code**; it integrated the already reviewed feature and
re-proved it on the canonical tree.

## 2. Acceptance gates and their measured status

Legend: `PROVED` = measured in this run on canonical `main`; `WITHHELD` = deliberately not
claimed; `BLOCKED` = cannot be executed without an explicit external decision.

| Gate | Status | Evidence (this run, canonical `main` = `ae4c6ba`) |
|---|---|---|
| Rust format check | PROVED | `cargo fmt --all -- --check` → exit 0 |
| Rust workspace check | PROVED | `cargo check --locked --workspace --all-targets` → exit 0 |
| Rust clippy, warnings denied | PROVED | `cargo clippy --locked --workspace --all-targets -- -D warnings` → exit 0 |
| Rust workspace tests | PROVED | 167 passed, 0 failed (44 of them Storage) |
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
| Physical Raspberry-Pi acceptance | **WITHHELD** | no endpoint, SSH user or approved identity was supplied; no personal device was contacted |
| Real installation activation (schema 7) | **BLOCKED** | requires a separate operator decision plus a fresh protected backup; forbidden in this loop |
| Native macOS build/test | **OPEN** | the P0 handoff recorded the native build blocked inside SwiftBuild toolchain discovery; not re-attempted yet |
| Productive remote/browser identity | **OPEN** | loopback local operator session only; no HTTPS, no remote identity, no hostile same-UID isolation |
| Durable tamper-proof audit | **OPEN** | audit is append-only in application code, the SQLite file itself stays writable by the daemon user |
| OT / endurance certification | **OPEN** | not claimed; the measurements below are short local observations, not an SLA |
| RUSTSEC-2023-0071 / -0089 / -2024-0449 | **OPEN** | still ignored with the existing documented local-only exceptions in `deny.toml`; no new exception added |

### Short local measurements (not an SLA)

* Official MCP `device_connection_read`: 20 sequential samples with 8 attached clients,
  p50 3.93 ms, p95 4.84 ms.
* One Core sample while the harness ran: 30,768 KiB RSS, 15.2 % CPU.
* Ingestion advanced 140 → 150 observations after all browser and MCP clients disconnected.

## 3. Open items, in execution order

Each item names the next *delimited* step, its gate and its blocker. The loop continues with
item **N1**; the remaining items stay untouched until the preceding one is verified.

### N1 — Close the conformance gaps found by the delegated source review (Core)

A read-only source review against `docs/architecture/real-device-onboarding.md` produced the
findings below. They are contract conformance defects, not new architecture. Fix them on an
isolated feature branch, add Rust-level regression tests, re-run the full gate set above and
integrate with the same controlled fast-forward.

| Id | Severity | Location | Defect | Contract reference |
|---|---|---|---|---|
| F1 | medium | `crates/oip-server/src/ssh.rs:414-424`, `:519` | The server never enforces "RSA keys require at least 2048 bits". `ssh-keygen -lf` already prints the key size, but only the fingerprint is kept; enforcement is delegated to the `RequiredRSASize=2048` client option of the *user* connection. A weak `ssh-rsa` host key can therefore be scanned, shown, trusted and pinned. | `docs/architecture/real-device-onboarding.md:48` |
| F2 | low/medium | `crates/oip-server/src/ssh.rs:316` | `REMOTE HOST IDENTIFICATION HAS CHANGED` **and** `Host key verification failed` are both mapped to `SSH_HOST_KEY_CHANGED`, so an unknown key is reported as a rotation alarm. | `docs/architecture/real-device-onboarding.md:23`, `:66` |
| F3 | low | `crates/oip-server/src/browser_session.rs:93-100` | The invalid-code limiter is evaluated *before* the grant lookup, so 16 malformed codes block the operator's valid single-use code for 60 s. Local-process availability bug inside the session boundary. | `docs/architecture/real-device-onboarding.md:36` |
| F4 | low | `crates/oip-server/src/ssh.rs:733-802` vs `crates/oip-storage/src/connection.rs:5` | The maximal host report the parser can build (up to ~128 KiB of interface/disk text) exceeds the 128 KiB `payload_json` CHECK, so a legal but extreme remote report fails the commit with an opaque storage error instead of a typed fault. | `docs/architecture/real-device-onboarding.md:50`, `:58` |
| F5 | low | `crates/oip-server/src/connection_service.rs:96-134` | The read path requires `DeviceConnectionConfigure`; the contract places `GET /device-connections?plan_id=…` under `DeviceConnectionRead`. Conservative over-restriction, not an escalation. | `docs/architecture/real-device-onboarding.md:15` |
| F6 | low | `crates/oip-server/src/browser_session.rs:97-103` | The session-capacity check runs after the single-use grant was already consumed, so a valid code is destroyed when 64 sessions exist. | `docs/architecture/real-device-onboarding.md:36` |
| F7 | low | `crates/oip-server/src/ssh.rs:323-332` | The SSH work directory is created with the process umask and only afterwards chmod'ed to 0700, leaving a brief world-readable window. | `docs/architecture/real-device-onboarding.md:48` |
| R1 | test gap | `crates/oip-server/tests/` | No Rust-level test covers the browser session/CSRF/Origin flow; those assertions only exist in the external harness `tests/real_device/acceptance.py`. Add: cookie-only POST without `x-oip-csrf` → 403; wrong CSRF → 403; `DELETE /api/v2/browser/session` without CSRF → 403; session revoked mid-SSE stops delivery; `GET /api/v2/browser/session` without a cookie returns `csrf_token: null`. | `docs/architecture/real-device-onboarding.md:37-39` |

Gate for N1: `cargo fmt/check/clippy --locked --workspace --all-targets`, `cargo test --locked
--workspace`, both OPC-UA backend configurations, `cargo deny check`, `flutter analyze`,
`flutter test`, both web release builds and a re-run of `tests/real_device/acceptance.py`.

### N2 — Native macOS build and test (open acceptance item)

The P0 handoff recorded the native build blocked inside SwiftBuild toolchain discovery
(`QNXSDP.findInstallations → LocalFS.listdir → __getattrlist`); Flutter returned zero without
running a test, and the raw exit code was corrected by a hash-bound receipt. No native PASS
is claimed. The next step is a bounded attempt that (a) owns and bounds the process group,
(b) requires a positive test-completion marker instead of an exit code and (c) records the
actual toolchain state. OIP-008.6 already ran one native macOS integration test on an
isolated demo database, so the capability exists; the blocker must be diagnosed, not assumed.
Gate: a real native test result with a completion marker, or a documented blocker.

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

## 5. Evidence index

| Artifact | Content |
|---|---|
| `docs/evidence/oip-real-device/test-summary.json` | machine-readable gate results of iteration 1 |
| `docs/evidence/oip-real-device/review.json` | findings of the delegated read-only source review (F1-F7, R1) |
| `target/oip-real-device-e2e/report.json` | full acceptance report of the SSH/browser/MCP harness (local, not tracked) |
| `target/oip-real-device-e2e/browser/report.json` | browser receipt of the actual Flutter onboarding run (local, not tracked) |
| `target/oip-real-device-e2e/browser/*.png` | screenshots of login, endpoint input, host-key consent, identity confirmation, persisted binding and live monitoring (local, not tracked) |
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
