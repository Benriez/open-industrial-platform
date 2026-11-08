# OIP release acceptance ledger (N12 offline inventory)

Inventory taken 2026-11-08 on `main` = `037afda`, read-only: no build, no deployment, no schema
activation, no private endpoint. Statuses: DONE, READY, BLOCKED_OPERATOR, BLOCKED_DEPENDENCY, FAILED.
Overall verdict: **OIP_PRODUCTION_NOT_READY**. No gate below is accepted for production.

`AGENTS.md` does not exist in this repository (no substitute policy was invented). Binding rules
come from `docs/OIP_RELEASE_PROGRESS.md`, `docs/decisions/*` and `docs/architecture/*`.

| Gate | Status | Basis and gap |
|---|---|---|
| G1 integrated Core + six workstations | READY (partial) | Core and Flutter gates pass on `e9036ef` per the progress file. Diagnostics view (N10) exists only on `feature/oip-managed-diagnostics` (`55d4f50`); integration N11 is BLOCKED_DEPENDENCY on the active Spectrum-2027 owner. Settings and OPC-UA browser parity with the real backend not re-verified in this inventory. |
| G2 auth, sessions, REST/SSE/MCP parity, org isolation | READY (partial) | Browser session contract and parity gate recorded as passing; hostile same-UID and productive identity remain open (see G10). |
| G3 global infrastructure context | BLOCKED_DEPENDENCY | N3: global selection payload needs three-way reconciliation with UI workstreams. Not invented here. |
| G4 device management in Flutter | READY (partial) | Create/onboard proven on the loopback SSH fixture; update/archive coverage not inventoried as evidence. |
| G5 real device connections | BLOCKED_OPERATOR | Fixture only. No physical device contacted; needs operator-approved target. F5 permission rule (N1b) is also BLOCKED_OPERATOR. |
| G6 monitoring | READY (partial) | Measurements and history proven against the fixture. Long-run stability and reconnect on real hardware not evidenced. |
| G7 Spectrum-2027 UX preserved | BLOCKED_DEPENDENCY | Owned by the active UI worktree (`spectrum-2027-ui`, test processes running now in `canonical-ui-gate`). Never overwrite. |
| G8 six functional views | READY (partial) | Overview, Network done; Diagnostics isolated (N10/N11); Devices, OPC-UA, Settings not re-inventoried. Unsupported protocols must stay labelled. |
| G9 macOS build, install, start/stop, logging, backup/restore | READY | Gaps found: no `target/release` Core binary exists (debug only); `docs/runbooks/` is empty; no start/stop/restart script, no log policy, no backup/restore tool in the tree (only `docs/evidence/oip008/backup.json`). `deployment/systemd` is Linux-only. Installing a launch agent needs operator authorization. |
| G10 security release review | BLOCKED_OPERATOR | Three advisory exceptions documented (N5). Open: productive browser/remote identity, same-UID isolation, durable audit, credential protection, scope enforcement review. Production-security scope needs explicit operator acceptance. |
| G11 acceptance, a11y, perf, resilience, upgrade/rollback | READY (partial) | Canonical regression (8 cases) passes on fixtures. Missing: release-binary run, accessibility audit, upgrade/rollback, extended stability. |
| G12 operator acceptance | BLOCKED_OPERATOR | Requires the operator to launch, authenticate, configure and connect real devices. |

## Next READY tasks (independent of blockers)

1. **N13 (G9, G11)**: build `oip-server` with `--release`, run the canonical regression against that
   binary, record evidence.
2. **N14 (G9)**: write `docs/runbooks/` for start, stop, restart, logging, backup and restore of a
   copy of the SQLite database (never the personal database), with a tested script.
3. **N15 (G11)**: accessibility and performance receipts for the integrated UI, after N11.

## Operator actions required (nothing here is executed by the loop)

* Decide F5 permission rule (N1b) and protected schema-7 activation with a fresh schema-6 backup (N4).
* Name an approved physical device and credentials path for G5/G12.
* Accept or reject the production-security scope (G10).
* After the UI owner is idle: reconcile `feature/oip-managed-diagnostics` (N11) and, if wanted, run
  the recovery review command documented in that branch's `docs/recovery/oip-loop-20261108.md`.
