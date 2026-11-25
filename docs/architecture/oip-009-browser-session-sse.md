# OIP-009 browser session, SSE and global context seam

Status: **contract for the implemented and verified boundary.** This document describes what
the canonical tree implements and proves today. It does **not** define the final OIP-009
payload, and it does not replace the independent UI workstreams.

Baseline: `3f23ad7` (canonical `main`, after the real device onboarding integration, its
conformance fixes, the native macOS harness and the bounded host report).

## 1. Why this document exists

Five places in the tree defer the same decision to OIP-009:

* `docs/oip-0082-verification.md:116` — "Sichere Browser-Session/SSE-Anbindung und UI-Caches
  bleiben OIP-009."
* `docs/oip-0084-verification.md:134` — "danach OIP-009 Browser-/Session-/SSE-Sicherheitsvertrag
  und spätere Settings-UI-Anbindung."
* `docs/architecture/oip-0082-diagnostics-flutter-contract.md:3` and
  `docs/architecture/oip-0084-flutter-settings-contract.md:3` — the browser session, SSE and
  context integration remain OIP-009.
* `docs/architecture/oip-0085-real-inventory-flutter-contract.md:3` — "Browser
  identity/session/SSE integration remains OIP-009."
* `docs/architecture/real-device-onboarding.md:88-90` — the seam exists, but "the final OIP-009
  payload must still be reconciled three ways; this work does not overwrite it."

The browser session, the SSE boundary and the context seam are now implemented and verified in
the canonical tree. What is still missing is the global Organization / Infrastructure / Site
selection that a multi-infrastructure operator needs. This document fixes the boundary that such
a payload has to satisfy, so the payload can be built and reconciled without inventing a second
security model.

## 2. The browser session boundary

Normative implementation: `crates/oip-server/src/browser_session.rs`, the routes in
`crates/oip-server/src/api.rs`, the Flutter client in `apps/flutter/lib/services/api.dart` and
the login view in `apps/flutter/lib/features/operator_login.dart`.

| Rule | Value | Where it is proved |
|---|---|---|
| Pairing code | 256 bit random, 120 s, single use, at most 32 pending grants | `crates/oip-server/src/browser_session.rs` (`issue`, `login`); `tests/real_device/acceptance.py` phase `browser_identity_online_writer` |
| Code issuance | only through the existing authenticated local IPC path (`--browser-login`); no SQLite access, no grant creation | `crates/oip-server/src/mcp/ipc.rs`; `docs/architecture/real-device-onboarding.md:27-33` |
| Session | 256 bit random, server-side hashed index, 30 minutes idle or 12 hours absolute, at most eight sessions per principal and 64 overall. A valid sign-in can replace its own principal's least recently used session. Status checks and SSE are passive. | `crates/oip-server/src/browser_session.rs` unit tests and `tests/oip_session_lifetime.py` |
| Invalid codes | bounded rejection accounting that never blocks a valid one-time grant; a full session table does not consume an issued grant | `crates/oip-server/src/browser_session.rs` unit tests |
| Login | `POST /api/v2/browser/login` requires the exact `Origin`. The answer sets a host-only, `HttpOnly`, `SameSite=Strict` session cookie with `Path=/`. | `crates/oip-server/tests/browser_session.rs`, `tests/real_device/acceptance.py` |
| Session query | `GET /api/v2/browser/session` returns only the bound Principal and an ephemeral CSRF value, `Cache-Control: no-store`, and no CSRF value for an unauthenticated caller | `crates/oip-server/tests/browser_session.rs` |
| Cookie authorized writes | every mutating route requires the exact `Origin` **and** `x-oip-csrf`; the value is compared in constant time | `crates/oip-server/src/api.rs` (`Authorized`), `crates/oip-server/tests/browser_session.rs` |
| Revocation | `DELETE /api/v2/browser/session` needs the same boundary and invalidates the session immediately | `crates/oip-server/tests/browser_session.rs` |
| Token hygiene | no cookie value, CSRF value or bearer in a URL, a web asset, `LocalStorage` or `sessionStorage`; the CSRF value exists only in Flutter memory | `apps/flutter/test/onboarding_contract_test.dart`; `apps/flutter/test/browser_onboarding.mjs` |
| Restart | sessions are in memory, so a restart invalidates them; the device and collector configuration persists in storage | `crates/oip-server/src/state.rs`, `crates/oip-storage/src/connection.rs` |
| macOS Touch ID | The Core accepts one new device credential within 120 seconds of a successful single-use code login. The store retains only a digest and an authorized principal. New registrations are limited to eight per principal and 32 in total. Existing credentials remain usable until revoked. | `crates/oip-server/src/browser_session.rs` and `tests/oip_session_lifetime.py` |
| Touch ID session | Biometric unlock submits the paired credential to `POST /api/v2/browser/device-login`, issuing the same cookie and CSRF token as code login. A device-authenticated session cannot pair another device. | `crates/oip-server/tests/browser_session.rs` and `tests/oip_session_lifetime.py` |
| Device sign-in management | Authenticated operators can list and name their own sign-ins under Settings → Security & Access → Current Identity. Revocation denies the credential and all sessions issued from it. Re-enrollment uses a fresh code and a new credential. Mutations require matching Origin and CSRF. | `tests/oip_session_lifetime.py` and `apps/flutter/test/paired_device_sign_ins_test.dart` |
| Restart and recovery | The Core drops sessions on restart and retains active and revoked device credentials separately. The sibling `.revocations` file is authoritative over an older credential snapshot. Standard Core backup and restore operate on SQLite and leave both sidecars in place. If restoring an entire machine, retain the newest revocation file from protected state before starting Core. | `crates/oip-server/src/browser_session.rs`, `tools/oip_ops.py` and the restart test in `tests/oip_session_lifetime.py` |
| Apple Keychain | A notarized direct package with the matching OIP provisioning profile requires the data protection Keychain and `biometryCurrentSet`. An explicitly authorized internal ad-hoc package uses the existing executable-bound file Keychain fallback where needed. | `tools/oip_github_ota_package.py`, `apps/flutter/macos/Runner/MainFlutterWindow.swift` and `tests/oip_github_ota_package.py` for the ad-hoc path |

The HTTP cookie boundary is host scoped, not port isolated. It is not a production browser
identity solution: no HTTPS, no remote identity and no isolation against hostile same-UID
processes or browser extensions is claimed.

## 3. The SSE boundary

* The projection stream revalidates the browser session for **every** projection
  (`crates/oip-server/src/api.rs`, `call` re-authenticates the token). A revoked or expired
  session therefore stops delivery. An authorization failure emits one error event and
  closes the stream. Stream traffic does not reset the session idle timer.
* The stream carries only the scoped projection of the session's Principal. A scoped snapshot
  never invents global counts, health, incidents or topology
  (`apps/flutter/test/onboarding_contract_test.dart`).
* API answers are `no-store`; framing is denied with `X-Frame-Options` and a
  `Content-Security-Policy: frame-ancestors 'none'`; referrers are suppressed.
* No public listener, no CORS grant and no anonymous tenant fallback exist.

### Security journal and release control

Core stores online mutation records in the database's sibling `.security-audit`
directory. Each record carries an HMAC linked to the previous record. A separate
seal records the last confirmed append. Startup verifies the chain, rejects a
changed or truncated committed log, and can recover an unsealed tail. Keep the
journal, key and seal together when backing up security state. The local Core
account is within this trust boundary. An independent destination is required
to detect replacement of all three by that account or its administrator.

External writes record a start before dispatch and a result with the same
correlation ID. A start without a recorded result has an unknown outcome.
Check the actual target before retrying. The local journal is capped at 32 MiB.
An unavailable audit blocks new writes that require evidence. Revocation remains
available and retains the principal and timestamp in its own private store.

The macOS release script checks the locked Rust dependencies before building or
publishing. Developer ID distribution requires the signing identity, matching
Keychain provisioning profile and an Apple notarization profile. Publication
also retains the existing Ed25519 verification of the final archive. The
remaining OPC UA dependency migration and real transport acceptance are tracked
in the security remediation record.

## 4. The global context seam as implemented

Normative implementation: `apps/flutter/lib/app/controller.dart`,
`apps/flutter/lib/models/onboarding.dart`, `apps/flutter/lib/features/devices.dart` and
`apps/flutter/lib/features/device_onboarding.dart`.

* `OnboardingScope` carries an optional Organization, Infrastructure and Site id. It is the
  only context type in the product; there is no second global switcher.
* `OipController.setInfrastructureContext(scope)` stores the scope, advances
  `contextRevision`, clears the display caches (`snapshot` and `history`) and reconnects.
* The same invalidation happens when the session's Principal changes and when the session
  expires or is revoked. The controller never keeps the display state of a previous context.
* Open inspectors and dialogs observe `contextRevision` and close themselves when it advances,
  so no stale detail view of a previous context stays open.
* The hierarchy that a scope is built from is read from `/api/v2/organizations`,
  `/api/v2/infrastructures` and `/api/v2/sites`. The onboarding wizard only offers authorized
  descendants and locks the placement of an existing device.

The canonical tree contains **no global context selection**: `setInfrastructureContext` has no
caller. The data the operator sees is the scope of the session's Principal. That is the state
in which the payload has to be designed, and it is the reason the payload is not decided here.

## 5. What this document does not decide

The final OIP-009 payload — the global Organization / Infrastructure / Site selection and how it
changes the session scope — is **not** defined in this document. It stays with the independent
UI workstreams and must be reconciled three ways before an integration, exactly as
`docs/architecture/real-device-onboarding.md:90` requires:

1. controller (`OipController`, `OnboardingScope`, `contextRevision`),
2. API (the scoped read routes, the session and the SSE projection),
3. contracts and the Devices view (`docs/architecture/oip-0085-real-inventory-flutter-contract.md`).

A payload is acceptable when it keeps every rule of sections 2 and 3, uses the existing
`OnboardingScope` type instead of a second context object, advances `contextRevision` on every
context change, never displays data of a context that the Principal may not see, and stores no
token, bearer or context identity in a URL, a web asset or browser storage.

## 6. Related documents

* `docs/architecture/real-device-onboarding.md` — the normative connection, session and SSH
  contract this seam belongs to.
* `docs/architecture/real-device-onboarding-flutter-contract.md` — the five phase Flutter
  workflow and the context seam.
* `docs/architecture/oip-008-rest-mcp-parity.md` — the capability matrix behind the scoped
  reads.
* `docs/oip-0082-diagnostics-flutter-contract.md`, `docs/architecture/oip-0084-flutter-settings-contract.md`,
  `docs/architecture/oip-0085-real-inventory-flutter-contract.md` — the per domain contracts
  that defer to OIP-009.
* `docs/OIP_RELEASE_PROGRESS.md` — the release state, the measured evidence and the open items.
