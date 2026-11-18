# OIP Canonical UI Baseline — Spectrum-2027 Engineering Workstations

**Status:** binding integration contract · **Integration verification:** `OIP_CANONICAL_UI_GATE_PASS` on the isolated candidate · **Visual approval:** `VISUAL_PENDING_OPERATOR_ACCEPTANCE`

This document is the source of truth for the OIP presentation layer. It is not a
reference document: a change that violates it is a regression, even if the
Rust workspace, the Flutter tests or the browser regression are green. A green
backend test run never justifies a UI downgrade.

---

## 1. Why this document exists

The 2027 Engineering Workstations were developed in an isolated UI workstream
and were never integrated into the canonical tree. Meanwhile the canonical tree
kept the OIP/005/006 presentation (the "Command Center" headline, the
decorative gradient KPI row, the `M-01`/`temperature` demo coordinate, the
"Normalbetrieb" selector, the AGENT-FIRST sidebar card, the `OIP / 005 UI`
footer). The visible result was a product regression: the operator saw the old
dashboard while the newer workstations existed.

The regression had **two independent causes**, both proven, not assumed:

1. **Missing UI integration.** The canonical Flutter app contained no
   global infrastructure context, no Settings workstation, no adaptive
   workspaces and no object-centric workstations
   (`git log -S "Einstellungen" -- apps/flutter` → no hit before this
   integration).
2. **Wrong runtime mode.** The demo preview was served by a Core in
   `--demo` mode, whose session answers `mode: explicit_legacy_demo`; the
   client then legitimately used the legacy v1 transport and the legacy
   surfaces.

Both are now closed. The gate below keeps them closed.

---

## 2. Source of authority

| Item | Value |
|---|---|
| UI authority | `/Users/benny/Code/oip-ui-isolated/OIP-UI-ADAPTIVE-WORKSPACES-2027-20261107`, branch `feature/oip-ux-001-adaptive-workspaces` |
| UI payload commit | `6c2d2a280b66b69461d5ee8c821630b4deeed4fe` ("fix: polish adaptive inspector consistency") |
| Frozen baseline commit | `5d50a1d5da558cf1e78515b4c24bad4aded40a92` ("chore: freeze OIP-009 adaptive workspace baseline") |
| Baseline handoff | `oip-ui-infrastructure-context-2027-handoff.tar.gz`, sha256 `c9d894b6139a2752bb781e68417408db56c7531cb1ee07c7a0c03c3129f70190`, independently verified `PASS` |
| Baseline core revision of the payload | `49a86bb0aa9f737fe9392eb2b5421e1ffe2f8c68` (OIP-008.5) |
| Payload test baseline | 291/291 PASS upstream; 301/301 PASS in the final OIP-UX-001 handoff; **335/335 PASS** on the tested integration candidate |
| Tested working-tree hash | `2b06903bbb83ea188bd0841500627b81582ed181` (hashed through a temporary index by the gate, never the real one) |
| Integration candidate branch | `feature/oip-spectrum-2027-ui` (isolated worktree `…/worktrees/spectrum-2027-ui`) |
| Integration snapshot | the committed candidate tree; the pre-commit 128-file snapshot of the source worktree is archived with SHA-256 `8c81ed6fb1ea624a3047a33db284d441d704b2ddd081268826c7922236f2acc3` |
| Verified handoff manifest | `docs/design/OIP_UI_2027_HANDOFF_MANIFEST.json` |
| Canonical web release (canvaskit) | `apps/flutter/build/web/main.dart.js`, local and served SHA-256 `169aaa8257a782ae52d5afe7b9de68b6acedb013cc24c96783e11e054cc22caa` |
| Canonical web release (html) | `apps/flutter/build/web-html/main.dart.js`; separately built for the legacy-renderer regression |
| Contract documents | `docs/architecture/oip-009-browser-session-sse.md`, `oip-0082-diagnostics-flutter-contract.md`, `oip-0084-flutter-settings-contract.md`, `oip-0085-real-inventory-flutter-contract.md` |

Two executions prepared this integration in parallel from the same authority:
this worktree (`feature/oip-spectrum-2027-ui`) and the isolated candidate
`feature/oip-canonical-ui-regression-gate` of the concurrent release loop. Both
derive from the same payload commit and both carry the same gate. They were
reconciled instead of integrated twice: the gate, the visual comparison, the
acceptance-workflow integration and the handoff manifest come from the
concurrent candidate, the product fixes below come from this worktree.

The payload is a Flutter-only application fork with an identical `pubspec.yaml`
(same package `oip_dashboard`, same dependency set, byte-identical fonts and
`analysis_options.yaml`). It was **not** copied blindly: the canonical Core
integration was re-applied on top and is listed in §6.

---

## 3. The approved application shell

* Six workstations, in this order and in this navigation structure:

  | Group | Workstation | Implementation |
  |---|---|---|
  | ARBEITSBEREICH | Übersicht | `lib/features/overview.dart` + `lib/features/overview/*` |
  | ARBEITSBEREICH | Geräte & Dienste | `lib/features/devices.dart` + `lib/features/devices/*` |
  | ARBEITSBEREICH | Netzwerk & VPN | `lib/features/network.dart` + `lib/features/network/*` |
  | DATEN & ANALYSE | OPC-UA-Browser | `lib/features/opcua.dart` |
  | DATEN & ANALYSE | Diagnose & Ereignisse | `lib/features/diagnostics.dart` + `lib/features/diagnostics/*` |
  | SYSTEM | Einstellungen | `lib/features/settings.dart` + `lib/features/settings/*` |

* The **global infrastructure context selector** (`lib/widgets/infrastructure_selector.dart`,
  key `infrastructure-context-selector`) is part of the header and is the only
  global context selection. It names the authorized scope
  ("Alle berechtigten Infrastrukturen", a specific infrastructure, site or
  source) and is shared across all six workstations through
  `controller.infrastructure`.
* **Context-sensitive inspectors**: one inspector per workstation, opened and
  closed by `WorkspaceId.*`, pinned state in `lib/app/workspaces.dart`
  (`AdaptiveWorkspaces`).
* **Object-centred navigation**: explorer → workspace → inspector, with
  progressive disclosure through the expert workspace and the advanced filter
  of `lib/widgets/workstation.dart`.
* **Technical provenance**: every state names its source (API, fixture,
  provenance marker) and unknown states stay unknown.
* Three themes: Spectrum, Graphite, Daylight (`lib/design_system/theme.dart`).
* The application identity in the footer is `OIP · SPECTRUM 2027`.

---

## 4. Explicitly prohibited regressions in the normal, real mode

| # | Prohibited | Proof |
|---|---|---|
| R1 | The OIP/005 dashboard as the default of the real mode | widget gate: `Deine Infrastruktur. Ein Bild.` absent; browser gate: same |
| R2 | Large decorative multicolor gradient KPI cards | widget gate: `Erfasste Geräte`, `Erreichbare Geräte` absent |
| R3 | Hardcoded `M-01` / `temperature` as the primary managed measurement | widget gate: `M-01`, `Temperatur · M-01` absent; the managed metric choice is deterministic (most samples, tie → metric id) |
| R4 | Hardcoded demo inventory (the 17 simulator devices) in the managed projection | widget gate: `LAN`, `Tailnet`, `Remote Site` absent; the managed view shows the authorized counts only |
| R5 | The "Normalbetrieb" scenario selector replacing the infrastructure context | widget gate: `scenario-select` and `Normalbetrieb` absent in the real mode |
| R6 | The decorative AGENT-FIRST card in the sidebar | widget gate and browser gate: `AGENT-FIRST` absent from the shell. The agent-first principle stays architectural and may only appear in the technical capability context of the Settings workstation. |
| R7 | An automatic legacy fallback after an API or authentication error | widget gate: a missing session renders the operator login, never the demo dashboard |
| R8 | Older widgets replacing newer workstations during a merge | the gate asserts the six workstation headers and the global context selector by widget key |
| R9 | The `OIP / 005 UI` footer | widget and browser gate, plus the bundle marker check |
| R10 | Reporting a UI PASS while a stale bundle is served | the gate compares the served bundle with the local build byte by byte and records both hashes |

Historical simulator-specific code may stay in the isolated legacy demo path
(`--demo` mode) and in its own regression tests. It must never be reachable in
the real mode.

---

## 5. The regression gate

```sh
# build provenance + widget gate + browser gate (one receipt)
python3 tests/canonical_ui_gate.py \
    --base-url http://127.0.0.1:<port> \
    --ipc-socket <private socket> --ipc-credential <own credential> \
    --out target/oip-canonical-ui-gate
```

The gate is also registered as the case `oip_canonical_ui_gate` in
`tests/canonical_regression.py`. That case builds and hashes `oip-server` and the
official MCP probe, builds the Flutter web release, runs the **full Flutter
widget/unit suite**, then uses the owned managed real-device acceptance harness
with real browser login, the eight functional phases, the separate real
`browser_onboarding.mjs` journey, all six workstations at 1440/1920 and the
technical visual comparison. A complete PASS may not skip the build, widget suite or browser.
A local partial run, including `--skip-build` or `--skip-widget`, is explicitly `PARTIAL`, even when
`--allow-partial` permits its process to continue as part of the full harness.
The harness `report.json` contains the merged `canonical_ui_gate_receipt`: PASS,
the three sub-receipt paths and SHA-256 values, the machine-bound Flutter and
browser counts, the screenshot count and the unchanged visual-approval state.
The precheck's own receipt remains intentionally `PARTIAL` because it precedes
the managed browser run.

| # | Check | Kind |
|---|---|---|
| 1 | Correct UI build provenance: bundle hash, source revision, tree, required and forbidden markers | provenance |
| 2 | Global infrastructure selector present (`InfrastructureSelector`, key `infrastructure-context-selector`) | widget + browser |
| 3 | The six workstations exist and render their own workspace header | widget + browser |
| 4 | No AGENT-FIRST sidebar card | widget + browser |
| 5 | No legacy dashboard as the real-mode default | widget + browser |
| 6 | No hardcoded demo device or metric in the managed projection | widget + browser |
| 7 | Correct real-mode empty, loading and error states (`Unknown ≠ Offline`, no "wird geladen" as a state) | widget + browser |
| 8 | Responsive geometry: the context selector survives 390/768/1440/1920 px | widget |
| 9 | No regression of browser authentication and of the device onboarding action | widget + browser |
| 10 | Visual comparison against hash-pinned technical references at 1440×900 and 1920×1080 | stable-shell pixel comparison + browser semantic/geometry assertions |

The screenshot comparison protects **structure and layout**, not the dynamic
values: timestamps, counters and identifiers differ between runs. It re-derives
the stable left-shell crops directly from the independent OIP-UX-001 archive and
compares their hashes with `docs/design/OIP_UI_2027_HANDOFF_MANIFEST.json`.
The upstream full images are not operator-approved and contain a historical
footer; that footer and all dynamic work content are outside the crop. The mean
absolute difference and changed-pixel ratio are each capped at **0.01**.
Negative controls cover both a single mutated navigation row and a large
gradient band. Derivation compares pixels rather than encoder-dependent PNG
bytes and records the Pillow version. If the external archive is unavailable,
the receipt explicitly says `SKIPPED_EXTERNAL_ARCHIVE_UNAVAILABLE`; the committed
reference and its pinned SHA-256 remain mandatory. A small antialiasing-tolerant
channel absorbs only subpixel rendering differences. Navigation, selector
behavior, six workstation headers, document geometry and absence of the legacy
surfaces remain mandatory independent assertions. The technical comparison
never implies operator visual acceptance.

---

## 6. Product improvements that the reconciliation preserves

The 2027 payload is a design layer. The following canonical features were
re-applied on top of it and are part of the baseline:

| Feature | Where |
|---|---|
| Browser session, one-use code, CSRF, logout | `lib/services/api.dart` (`DeviceManagementApi`), `lib/app/controller.dart` (`login`, `logout`), `lib/features/operator_login.dart`, gate in `lib/app/app.dart` |
| Authorized multi-infrastructure projection | `lib/models/infrastructure.dart`, `controller.infrastructure` |
| Device registration and SSH onboarding | `lib/features/device_onboarding.dart`, `lib/features/device_connection_panel.dart`, `lib/models/onboarding.dart`, action in `lib/features/devices/devices_workstation.dart` |
| Host monitoring measurements | `lib/features/device_connection_panel.dart` |
| Verified network-neighbor links in managed Network & VPN | only Core-delivered links backed by fresh authenticated neighbor-table evidence; the UI never infers edges from names, address ranges or VPN membership |
| Persisted observation history | `lib/features/device_history.dart`, `lib/models/history.dart`, `api.observationHistory` |
| Managed diagnostics evidence (documented gaps, health transitions, the Core's own diagnosis-history state) | `lib/models/diagnostics.dart`, `api.diagnosticGaps`, `api.healthHistory`, section in `lib/features/diagnostics.dart` |
| Deterministic managed metric choice (no `M-01` preference) | `controller._defaultTelemetry` |
| Keyboard shortcuts, comparison, inspector pinning | `lib/app/workspaces.dart`, `lib/widgets/workstation.dart`, `lib/widgets/adaptive_workspace.dart` |
| The cadence-aware continuity of a measured series (`continuesSeries`, `seriesGapLimit`) | `lib/widgets/trend.dart`, applied in `lib/features/overview/telemetry_chart.dart`; the payload alone would break the line of every real source that publishes slower than 2.5 s |
| The monitoring measurements and the persisted history inside the approved device workspace | `lib/features/devices/device_detail.dart`, `lib/features/devices/devices_workstation.dart` |

Their owning regressions are not replaced by a shallow shell check: the gate runs
the complete Flutter suite, including `adaptive_workspaces_test.dart`,
`infrastructure_context_test.dart`, `devices_workstation_test.dart` and the
managed overview/diagnostics tests. Real browser authentication, monitoring
measurements, persisted history and the onboarding side effect are proven by
`browser_onboarding.mjs` after the design gate. Inspector and compare behavior
also remains covered by the workstation suites.

The Rust workspace is untouched by the UI integration.

---

## 7. Workflow integration

* `AGENTS.md` in the repository root binds every future session to this
  document and to the gate.
* `docs/OIP_RELEASE_PROGRESS.md` lists the canonical UI gate in the gate
  table and the iteration log.
* A future iteration must report the **tested revision and the bundle hash**.
  A UI PASS without the compiled browser assets is not a PASS.

---

## 8. Visual acceptance

The technical gate is green: 335/335 Flutter tests, 175 browser findings with
zero failures, all eight managed acceptance phases and the real onboarding
journey passed. Local and served bundle hashes are identical
(`169aaa8257a782ae52d5afe7b9de68b6acedb013cc24c96783e11e054cc22caa`). The visual
comparison passed at 1440 (`mean=0.0010914`, changed ratio `0.0`) and 1920
(`mean=0.0012635`, changed ratio `0.0`), including single-row and large-band
negative controls and pixel-verified archive derivation.

The **operator visual acceptance is still open**
(`VISUAL_PENDING_OPERATOR_ACCEPTANCE`): the six workstations at 1440 px and
1920 px are produced under
`target/oip-real-device-e2e/browser/`
(`canonical-ui-1440.png`, `canonical-ui-1920.png`, and the other workstation
captures). These screenshots are technical evidence, not operator acceptance.
