# OIP release acceptance ledger (N12 offline inventory)

Inventory taken 2026-11-08 on `main` = `037afda`, updated 2026-11-08 after the integration of the
Spectrum-2027 canonical UI. Statuses: DONE, READY, BLOCKED_OPERATOR, BLOCKED_DEPENDENCY, FAILED.
Overall verdict: **OIP_PRODUCTION_NOT_READY**. No gate below is accepted for production.

`AGENTS.md` now exists in this repository and binds every session that changes the Flutter
application. The binding rules come from `AGENTS.md`,
`docs/design/OIP_CANONICAL_UI_BASELINE.md` (the binding canonical UI contract),
`docs/OIP_RELEASE_PROGRESS.md`, `docs/decisions/*` and `docs/architecture/*`.

| Gate | Status | Basis and gap |
|---|---|---|
| G1 integrated Core + six workstations | DONE | The Spectrum-2027 Engineering Workstations are the canonical application of `main` since `ddb446e` (contract `docs/design/OIP_CANONICAL_UI_BASELINE.md`). The managed diagnostics capability of `feature/oip-managed-diagnostics` (`55d4f50`) is reconciled into the approved workspace: the capability was carried over, the opaque continuation and the limits of the answer were restored in `7fc612e`. All six workstations render against the real authorized backend; the browser gate proves 175 findings with zero failures over them. |
| G2 auth, sessions, REST/SSE/MCP parity, org isolation | READY (partial) | Browser session contract and parity gate recorded as passing; hostile same-UID and productive identity remain open (see G10). |
| G3 global infrastructure context | BLOCKED_DEPENDENCY | N3: global selection payload needs three-way reconciliation with UI workstreams. Not invented here. |
| G4 device management in Flutter | READY (partial) | Create/onboard proven on the loopback SSH fixture; update/archive coverage not inventoried as evidence. |
| G5 real device connections | BLOCKED_OPERATOR | Fixture only. No physical device contacted; needs operator-approved target. F5 permission rule (N1b) is also BLOCKED_OPERATOR. |
| G6 monitoring | READY (partial) | Measurements and history proven against the fixture. Long-run stability and reconnect on real hardware not evidenced. |
| G7 Spectrum-2027 UX preserved | DONE | Integrated into canonical `main` with a real `git merge --ff-only` after the two parallel executions were reconciled into one candidate. The binding contract is `docs/design/OIP_CANONICAL_UI_BASELINE.md` with the prohibited regressions R1-R10; the permanent gate is `tests/canonical_ui_gate.py` (build provenance, widget gate, browser gate, stable-shell visual comparison with negative controls) and runs inside the canonical acceptance workflow. The OIP/005 dashboard, the gradient KPI cards, the `M-01` defaults, the "Normalbetrieb" context and the AGENT-FIRST sidebar footer are prohibited regressions and are proven absent. Operator visual acceptance stays `VISUAL_PENDING_OPERATOR_ACCEPTANCE`. |
| G8 six functional views | READY (partial) | Overview, Devices & Services, Network & VPN, Diagnostics & Events, Settings and the OPC-UA Browser all render in the browser gate at 1440 px and 1920 px against the authorized backend, and the diagnostics view now shows the persisted evidence of the Core (documented gaps, health transitions, the named diagnosis-history state). Unsupported protocols stay labelled; the OPC-UA parity of the real backend is not yet re-inventoried. |
| G9 macOS build, install, start/stop, logging, backup/restore | READY (partial) | The release build exists and is proven: `target/release/oip-server` and the official MCP probe are executed by the canonical gate, which passes with the release binary (8/8 phases, 175 browser findings with zero failures, 339/339 Flutter tests). `docs/runbooks/operations.md` describes the local operations and `tools/oip_ops.py` performs them; `tests/oip_operations.py` proves the sequence against a disposable instance: provisioning, start, status, log, backup with an integrity check, the refused restore of a running instance, the clean shutdown without uncommitted observations, restore, start, restart and stop, plus the three refusals of the personal installation. Remaining: the local installation as a launch agent needs operator authorization, and the macOS application bundle is not built. |
| G10 security release review | BLOCKED_OPERATOR | Three advisory exceptions documented (N5). Open: productive browser/remote identity, same-UID isolation, durable audit, credential protection, scope enforcement review. Production-security scope needs explicit operator acceptance. |
| G11 acceptance, a11y, perf, resilience, upgrade/rollback | READY (partial) | The canonical regression passes with the **release** binary and the release web bundle (measured receipt in `target/oip-release-binary/`). The accessibility receipt of the six workstations measures the name and role coverage of the rendered surface: 136 controls, none without an accessible name, no JavaScript error, no external request (`docs/evidence/oip-accessibility/accessibility.json`); it is not a full WCAG audit. The upgrade and the rollback of a local instance are rehearsed against a protected historical binary and the current release binary: the store is migrated from schema 3 to 7 with the data intact and the backup restores the previous state (`docs/evidence/oip-upgrade-rollback/upgrade-rollback.json`). Missing: extended stability run and the performance baseline of the release build. |
| G12 operator acceptance | BLOCKED_OPERATOR | Requires the operator to launch, authenticate, configure and connect real devices. |

## Next READY tasks (independent of blockers)

1. **N17 (G9, G11)**: build the macOS application bundle of the Flutter client and prove that it
   starts, shows the approved shell and shuts down cleanly. The Core side of the local operations
   is DONE; the application bundle is the remaining half of G9.
2. **N18 (G11)**: the upgrade and the rollback of a local instance are rehearsed and documented
   (`docs/runbooks/operations.md` §6, `tests/oip_upgrade_rollback.py`). The remaining part is the
   rehearsal of the **daemon** handover with the historical binary: it binds its local clients to
   the actor policy of its era and refuses a start without a provisioned principal of that era.
   The data store and its handover are proven; the daemon of the historical release is not.
3. **N19 (G11)**: the performance baseline of the release build: first paint of the delivered
   bundle, the time to the interactive shell and the measured resource use of the Core under the
   managed acceptance load. The harness already measures the Core's RSS and CPU; the client side
   has no baseline yet.
4. **N16 (G6, G8)**: the persisted evidence of the diagnostics view now reaches the operator
   surface, proven against the Core that stores the documented gaps and the health transitions.
   The remaining gap is the diagnostic continuation in the browser journey against a Core whose
   page is truncated.

## Operator actions required (nothing here is executed by the loop)

* Decide F5 permission rule (N1b) and protected schema-7 activation with a fresh schema-6 backup (N4).
* Name an approved physical device and credentials path for G5/G12.
* Accept or reject the production-security scope (G10).
* Authorize the local installation of the application as a launch agent (G9/N17) and name the
  release artifacts that may be signed and distributed.
* The UI ownership question is settled: the Spectrum-2027 workstations are the canonical
  application of `main` and `feature/oip-managed-diagnostics` is reconciled into them. The
  recovery review command of that branch (`docs/recovery/oip-loop-20261108.md`) is no longer
  required for the integration.
