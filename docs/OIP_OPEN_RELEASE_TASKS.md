# OIP app completion: current acceptance state

## Current snapshot — 2026-11-18

This section supersedes the older version and topology counts below. Those
entries are retained as dated evidence and are not current-state claims.

### Verified on this iteration

- The source checkout is `main` at `77697c430c76162d75dbc77776a1af392fdc6142`.
  The changelog source now covers published OTA builds `0.3.20+23` through
  `0.3.31+34` and declares the pending release `0.3.32+35`.
- The full canonical regression passed for this change. Receipt:
  `target/oip-changelog-0.3.32-canonical-gate/oip_canonical_ui_gate/report.json`.
  It includes the authenticated managed browser, all eight acceptance phases,
  and Flutter tests (405 passed, 0 failed, 1 skipped). Browser checks passed
  189/189 with 13 screenshots and no console errors. Visual comparisons passed.
  The served `main.dart.js` matches the local build byte for byte; SHA-256:
  `3f3cb71e3d7954bd0ba477792028f7ff5452c4594565c959112b187a6d226057`.
  Source revision: `77697c430c76162d75dbc77776a1af392fdc6142`.
  The pre-commit source tree recorded by the gate is
  `efe2c0988cd38a887bf4e5436e59482a15201912`; it includes the product source
  in this release. Commit `0c086dcfbe5ab341ed67903d392d72beabb1720d` contains
  that source plus the final acceptance checklist.
- Focused Settings/About tests passed 3/3. The version page now has entries
  through the installed 0.3.31 release, including the topology, dashboard,
  telemetry, OPC-UA, Touch ID, and manual OTA work.
- On the live Pi Core, read-only DB inspection showed fresh observations for
  `bodi-pi`, `bodi-pc`, and the OpenWrt router. SSH host telemetry includes CPU,
  memory, disk, network, temperature, and GPU fields where the host exports
  them; the Pi reported SoC temperature and GPU identity but not a separate GPU
  temperature. Physical OPC-UA services on both hosts responded, with live
  telemetry variables marked read-only and designated operator variables
  writable. These direct service/DB checks do not prove the current installed
  app's authenticated screens.
- `v0.3.32` was published from this Mac with `tools/oip_ota_release.sh`; no
  GitHub Actions workflow was used. OTA manifest signature and archive digest
  verified (`f41b9eb63261499dc72898f49f48427e1200e53793cc04c518c41d46851f8418`).
  The app is installed and running at `/Applications/Open Industrial Platform.app`
  as `0.3.32+35`; strict bundle verification passed. Its app bundle signature
  is ad-hoc with no Team ID, so this does not establish App Store distribution
  signing. The previous `0.3.31+34` app and LaunchAgent are preserved at
  `~/Library/Application Support/OIP/rollbacks/0.3.31-build34-20261118`.
- After restart, ten consecutive local relay requests to
  `127.0.0.1:18856/api/v2/browser/session` returned HTTP 200 (12.7–204.2 ms).
  The response is `login_required`; transport is healthy, but this does not
  establish authenticated access from the installed app.
- The biometric keychain item exists and macOS reports biometric capability.
  An end-to-end Touch ID sign-in after the Core restart has not been observed.
  The current local browser session is `login_required`; protected app data
  still requires an authenticated session.
- No GitHub Actions workflow was started. No personal database or schema was
  changed.

### Remaining acceptance

- [x] Publish and install the `0.3.32+35` OTA through the local release tool;
  verify installed version, signature, and live relay after restart.
- [ ] Confirm actual Touch ID sign-in in the app and protected session state.
- [ ] Confirm physical Pi/PC telemetry and live OPC-UA browsing in the
  authenticated installed app.
- [ ] Operator visual acceptance and repeated native window resize/crash check.
- [ ] App Store upload readiness is prepared in source/docs, but cannot be
  proven for distribution until an Apple Distribution identity and required
  store credentials are available. The keychain currently has no such signing
  identity.
- [ ] Goal remains open until the product acceptance items above are verified.

---

## Prior snapshots (historical; do not treat as current)

This checklist tracks the installed macOS application against the active goal
to finish OIP. Read `AGENTS.md` and `docs/OIP_RELEASE_PROGRESS.md` before the
next iteration.

## Verified

- [x] Installed `/Applications/Open Industrial Platform.app` is version
  `0.3.30+33`; its executable SHA-256 is
  `d9d027dbe418f472bb5fe65db3032464fcc0c274cfb0259547f2a74e91fc4bf0`.
  Strict bundle signature verification passed. Previous app and OIP
  LaunchAgent are preserved in `/private/tmp/oip-v0330-rollout-backup/`; the
  LaunchAgent hash is unchanged.
- [x] Source commit `7b046e6b3f83716f747f9d4b6129b778e8783f61` is pushed to
  `origin/main`; `v0.3.30` is published as a signed OTA release without
  GitHub Actions. The full canonical gate passes on that exact commit/tree
  (`565e2edc99df7c65292834656cde4cdf2338f4d0`): 403 Flutter tests passed,
  0 failed, 1 skipped; browser 189/189; 13 screenshots; visual comparisons
  passed; local and served `main.dart.js` SHA-256 is
  `738fc2805322223bad7625318863cde8b21d908549ad607cbdb6791b3bccd466`.
  Receipt:
  `target/oip-ota-manual-check-gate-2026-11-18/commit-7b046e6/canonical-ui-gate.json`.
- [x] Current local relay on `127.0.0.1:18856` answered ten consecutive
  anonymous `/api/v2/browser/session` requests with HTTP 200 in 11.2–107.1 ms.
  The response is `login_required`; this checks transport only and does not
  establish the app's own session or access to protected data.
- [x] The canonical UI, widget, authenticated managed-browser, functional and
  visual gate passed on source `b0ad5754e369ea5019ed0f630df6075863973fa2`,
  tree hash `f960a5d21ca312f11f41ef56ca4c8a7f1e0ebecc`. Flutter tests: 401
  passed, 0 failed, 1 skipped. The authenticated browser gate passed 189 checks;
  the served `main.dart.js` matches the local build (SHA-256
  `d4b4626728290b68501eee93c5c8f9295cc78a2d19912b5160116caa03788537`). Visual
  comparison passed at both sizes with negative controls. Receipt:
  `target/oip-canonical-gate-current-b0ad575-complete/oip_canonical_ui_gate/report.json`.
  Its SSH onboarding used an owned loopback fixture, not the physical devices.
- [x] Removed a duplicate first-page request when opening OPC-UA in an
  authenticated context. The full OPC-UA workstation suite passes 31/31, and
  its new regression asserts one initial node-page request. The full canonical
  gate passes on the changed source tree (`fc11cbdd4ede775f08f5bbb53888dc1e9c46a74f`):
  402 Flutter tests passed, 0 failed, 1 skipped; browser 189/189; served bundle
  SHA-256 `10f06e9fbb637bea85f5e9896d7a930a83ef1c532bb7fa0b0631177d9bd7590d`,
  equal to the local build. Receipt:
  `target/oip-canonical-gate-opcua-single-load-2026-11-18/oip_canonical_ui_gate/report.json`.
- [x] Hardened the macOS main window against undersized resize states: startup
  now clamps the minimum to the hosting display and immediately expands an
  existing frame below that minimum. The app's strict signed release build
  succeeds. The full canonical gate passed: 402 Flutter tests, 189 authenticated
  browser checks, both visual comparisons, all six accessibility scans, global
  context and eight managed acceptance phases. Source `ab9212a`, tested tree
  `6ad88dc85cd4658c2e34d91c86a18dbe49d4b8c9`, served bundle SHA-256
  `10f06e9fbb637bea85f5e9896d7a930a83ef1c532bb7fa0b0631177d9bd7590d`.
  Receipt:
  `target/oip-window-min-size-final-gate-2026-11-18/oip_canonical_ui_gate/report.json`.
  This is not yet live resize/crash acceptance; the installed app remains
  `0.3.28+31` until a new build is rolled out and exercised.
- [x] Added a manual update check to Settings → About for direct macOS OTA
  builds. The updater bypasses its six-hour automatic check window on manual
  requests. Unit/widget coverage passes. A live tap is still unverified because
  the installed app reports that management access is not authorized after
  restart.

- [x] Live installed UI showed 3 registered devices and 3 connected sources.
  The Network & VPN workstation showed 0 topology links and 3 unknown
  relations. These counts do not prove fresh telemetry metrics.
- [x] Ten consecutive loopback `/api/v2/browser/session` requests returned
  HTTP 200. This proves the local transport responds; the session was
  unauthenticated and does not prove protected telemetry or OPC-UA access.

## Still open

- [ ] **Authentication after restart:** restore the existing management
  session with the configured Touch ID flow, without requiring a new one-time
  code; the installed Settings screen currently reports unauthorized access.
- [ ] **Manual OTA control live check:** authenticate, tap Settings → About →
  “Nach Updates suchen”, and verify the current-version result. The widget and
  updater logic pass tests; the protected Settings screen prevented this live
  click.

- [ ] **Authenticated physical-device acceptance:** verify fresh telemetry for
  `bodi-pi` and `bodi-pc` in the installed app, including metric names, values
  and observation timestamps. Current unauthenticated local probes cannot
  verify this.
- [ ] **Authenticated OPC-UA acceptance:** browse a live authorized source,
  read a selected node and confirm its value and timestamp in the installed
  app. The live Core's configured browse bindings and prior node probes do not
  prove the current app view works.
- [ ] **Infrastructure topology:** connect the three registered devices to
  their correct source/network relationships. The live view currently reports
  zero topology links and three unknown relations.
- [ ] **Operator visual acceptance:** technical comparison passed; the
  canonical baseline still requires operator acceptance.
- [ ] **Distribution readiness:** the installed app has no Developer ID Team ID
  in its code signature. App Store or outside-Mac distribution readiness is
  therefore not proven.
- [ ] **Live resize/crash acceptance:** install the hardened build, resize its
  native window repeatedly, and verify the app stays responsive and does not
  crash. The supplied crash stack is inside FlutterMacOS and does not identify
  the root cause; the minimum-size guard is a defensive fix, not a proven
  engine-level diagnosis.

## Diagnosis and constraints

- SSH host telemetry collection is supervised from persisted device connection
  records in `connection_service::supervise`; it is separate from
  `CoreConfig.sources`, which configures the OPC-UA simulation collector.
  `opcua_browse_sources` separately binds browse clients to registered
  sources. Therefore an empty simulation `sources` list alone does not explain
  missing Pi/PC telemetry.
- The OPC-UA workstation previously launched its initial node-page request from
  both `_loadSources()` and its caller, causing duplicate browse and selected
  value-read traffic on entry. The two callers now own sequencing and issue one
  page request. This removes unnecessary load but does not yet prove it was the
  only cause of the reported live API staleness.
- SSH checks on `bodi-pi` and `bodi-pc` found the `oip-server` process on the Pi;
  the three guessed systemd unit names were inactive on both devices. This does
  not establish whether their OIP collectors are configured under other unit
  names.
- No personal installation database or schema was changed. GitHub Actions was
  not started.
- Keep the goal open until installed-app telemetry and OPC-UA are verified
  against the physical infrastructure and all remaining release requirements
  are satisfied.
