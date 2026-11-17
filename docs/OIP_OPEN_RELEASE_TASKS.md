# OIP app completion: current acceptance state

This checklist tracks the installed macOS application against the active goal
to finish OIP. Read `AGENTS.md` and `docs/OIP_RELEASE_PROGRESS.md` before the
next iteration.

## Verified

- [x] Installed `/Applications/Open Industrial Platform.app` is version
  `0.3.28+31`; its executable SHA-256 is
  `5285535a29e4ff138e595ed39bb0e67b5bbbb987c02c2960df837ab4f8e3915c`.
- [x] Installed source revision is `b0ad575` (`v0.3.28`). The current repo
  worktree is clean at that revision.
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

## Still open

- [ ] **Authenticated physical-device acceptance:** verify fresh telemetry for
  `bodi-pi` and `bodi-pc` in the installed app, including metric names, values
  and observation timestamps. Current unauthenticated local probes cannot
  verify this.
- [ ] **Authenticated OPC-UA acceptance:** browse a live authorized source,
  read a selected node and confirm its value and timestamp in the installed
  app. The live Core's configured browse bindings and prior node probes do not
  prove the current app view works.
- [ ] **Operator visual acceptance:** technical comparison passed; the
  canonical baseline still requires operator acceptance.
- [ ] **Distribution readiness:** the installed app has no Developer ID Team ID
  in its code signature. App Store or outside-Mac distribution readiness is
  therefore not proven.

## Diagnosis and constraints

- SSH host telemetry collection is supervised from persisted device connection
  records in `connection_service::supervise`; it is separate from
  `CoreConfig.sources`, which configures the OPC-UA simulation collector.
  `opcua_browse_sources` separately binds browse clients to registered
  sources. Therefore an empty simulation `sources` list alone does not explain
  missing Pi/PC telemetry.
- The running app's Flutter window could not be inspected: the available
  accessibility snapshot was only 90×97 pixels and contained no Flutter
  content. Do not infer whether the app itself is authenticated from a separate
  anonymous session request.
- No private SSH, deployment, personal database change or GitHub Actions run
  was performed during this acceptance check.
- Keep the goal open until installed-app telemetry and OPC-UA are verified
  against the physical infrastructure and all remaining release requirements
  are satisfied.
