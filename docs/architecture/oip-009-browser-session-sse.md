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
| Session | 256 bit random, server side hashed index, 30 min absolute expiry, at most 64 sessions | `crates/oip-server/src/browser_session.rs` (`authenticate`, `info`) |
| Invalid codes | bounded rejection accounting that never blocks a valid one-time grant; a full session table does not consume an issued grant | `crates/oip-server/src/browser_session.rs` unit tests |
| Login | `POST /api/v2/browser/login` requires the exact `Origin`; the answer sets a host-only, `HttpOnly`, `SameSite=Strict`, `Path=/`, `Max-Age=1800` cookie | `crates/oip-server/tests/browser_session.rs`; `tests/real_device/acceptance.py` |
| Session query | `GET /api/v2/browser/session` returns only the bound Principal and an ephemeral CSRF value, `Cache-Control: no-store`, and no CSRF value for an unauthenticated caller | `crates/oip-server/tests/browser_session.rs` |
| Cookie authorized writes | every mutating route requires the exact `Origin` **and** `x-oip-csrf`; the value is compared in constant time | `crates/oip-server/src/api.rs` (`Authorized`), `crates/oip-server/tests/browser_session.rs` |
| Revocation | `DELETE /api/v2/browser/session` needs the same boundary and invalidates the session immediately | `crates/oip-server/tests/browser_session.rs` |
| Token hygiene | no cookie value, CSRF value or bearer in a URL, a web asset, `LocalStorage` or `sessionStorage`; the CSRF value exists only in Flutter memory | `apps/flutter/test/onboarding_contract_test.dart`; `apps/flutter/test/browser_onboarding.mjs` |
| Restart | sessions are in memory, so a restart invalidates them; the device and collector configuration persists in storage | `crates/oip-server/src/state.rs`, `crates/oip-storage/src/connection.rs` |

The HTTP cookie boundary is host scoped, not port isolated. It is not a production browser
identity solution: no HTTPS, no remote identity and no isolation against hostile same-UID
processes or browser extensions is claimed.

## 3. The SSE boundary

* The projection stream revalidates the browser session for **every** projection
  (`crates/oip-server/src/api.rs`, `call` re-authenticates the token). A revoked or expired
  session therefore stops the delivery instead of continuing to stream.
* The stream carries only the scoped projection of the session's Principal. A scoped snapshot
  never invents global counts, health, incidents or topology
  (`apps/flutter/test/onboarding_contract_test.dart`).
* API answers are `no-store`; framing is denied with `X-Frame-Options` and a
  `Content-Security-Policy: frame-ancestors 'none'`; referrers are suppressed.
* No public listener, no CORS grant and no anonymous tenant fallback exist.

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
