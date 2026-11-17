# OIP — Repository Agent Instructions

These instructions bind every session that works in this repository.

## 1. The presentation layer is contract-bound

Before changing anything under `apps/flutter`, read
[`docs/design/OIP_CANONICAL_UI_BASELINE.md`](docs/design/OIP_CANONICAL_UI_BASELINE.md).
It is a **binding integration contract**, not a reference:

* The approved application shell is the **Spectrum-2027 Engineering
  Workstations** (six workstations, global infrastructure context selector,
  context-sensitive inspectors, object-centred navigation).
* The OIP/005 dashboard is **not** an acceptable fallback. Its gradient KPI
  row, its `M-01`/`temperature` demo coordinate, its 17 demo devices, its
  "Normalbetrieb" selector, its AGENT-FIRST sidebar card and its `OIP / 005 UI`
  footer are prohibited regressions in the normal real mode (§4 of the
  baseline).
* The source of authority for the UI is recorded in §2 of the baseline
  (payload commit, frozen baseline commit, bundle hash). The exact upstream
  handoffs and visual-reference hashes are pinned in
  [`docs/design/OIP_UI_2027_HANDOFF_MANIFEST.json`](docs/design/OIP_UI_2027_HANDOFF_MANIFEST.json).
  Do not substitute a different UI source without recording the provenance
  change in both documents.

## 2. Reconcile explicitly, never blindly

* A UI change is a **three-way reconciliation**: the approved design, the
  canonical Core integration and the current branch. Never copy an older
  feature branch over newer files.
* Preserve the canonical product features listed in §6 of the baseline:
  browser authentication, authorized multi-infrastructure projections, device
  registration and SSH onboarding, host monitoring measurements, persisted
  observation history, managed diagnostics evidence, the deterministic managed
  metric choice, and the keyboard/compare/inspector functions.
* A Core contract may be amended only to *name* a proof, never to weaken a
  rule. The same holds for the UI baseline.

## 3. Run the design regression gate

```sh
# provenance + widget gate + browser gate (one receipt)
python3 tests/canonical_ui_gate.py --base-url http://127.0.0.1:<port> \
    --ipc-socket <private socket> --ipc-credential <own credential> \
    --out target/oip-canonical-ui-gate
```

The gate is also the case `oip_canonical_ui_gate` in
`tests/canonical_regression.py`. That case builds the current source, runs the
widget gate and uses the owned managed acceptance Core for the authenticated
browser gate, the eight functional acceptance phases and the visual comparison.
A complete UI PASS may never use `--skip-build`, `--skip-widget` or
`--skip-browser`; every deliberately partial local run must remain labelled
`PARTIAL`.

## 4. Report the tested artefacts, not the intention

* A UI PASS requires the **compiled browser assets**: report the tested source
  revision, the tree hash and the sha256 of the served `main.dart.js`.
* The served bundle must equal the local build byte by byte; the gate proves
  it.
* A green test run without the correct visible UI build is **not** a PASS.
* Never label an unapproved screenshot as operator-accepted. The visual
  acceptance state lives in §8 of the baseline.

## 5. Authorized OIP operations and rollout

* When the operator explicitly asks to fix, verify, or roll out this OIP
  application, that request authorizes the required OIP-scoped operations:
  fast-forwarding the isolated, verified change to `main`, pushing `main`,
  publishing its signed macOS OTA release, and validating the live OIP API.
* Publish OTA releases from this Mac with `tools/oip_ota_release.sh`. Do not
  start or rely on GitHub Actions; local builds and direct GitHub release
  uploads are the release path.
* For that requested live OIP work, SSH to the configured `bodi-pi` and
  `bodi-pc` aliases is authorized. Limit remote changes to OIP-owned services
  and files. Preserve the current service binary/configuration before replacing
  it, and verify service health and API responses after a restart.
* A requested app rollout authorizes updating `/Applications/Open Industrial
  Platform.app` and its OIP-owned LaunchAgents. Preserve the previous app and
  OIP LaunchAgent configuration before replacement, and verify the installed
  version, signature and running API path after rollout.
* Never start paid GitHub Actions workflows. Do not modify unrelated hosts,
  worktrees, services or processes. Do not migrate the personal installation
  database or activate schema 7 unless the operator explicitly requests it.
