# OIP app completion: current acceptance state

This file tracks completion of the app against the current source and the installed
macOS app. It replaces the obsolete `0.3.10+13` / port `18858` loop. Read
`AGENTS.md` and `docs/OIP_RELEASE_PROGRESS.md` before the next run.

## Verified

- [x] The canonical UI build, widget, authenticated browser, functional, and visual
  gate passes on source revision `b15053b64f728e6b182758ec686b8870fd9ec71c`.
  Receipt: `target/oip-canonical-regression-final-20261117/oip_canonical_ui_gate/report.json`.
  Flutter tests: 401 passed, 0 failed, 1 skipped. Served browser bundle matches the
  local build (SHA-256 `60ed7cc13a822d7fccc234b31bd16858fdeff7c999f8d8b03ed05a8fdff6a254`).
- [x] Network topology now lays out isolated registered devices without inventing
  network links. The UI gate passed after integration.
- [x] A local macOS OTA candidate `0.3.27+30` was packaged from the verified source;
  universal architecture, bundle ID, updater flags, strict bundle signature check,
  manifest signature, and archive digest were verified. Archive SHA-256:
  `17d3c418014fab7253bea39e16f4c3693bc0f937f5448b2d0e323fb30f1586e1`.

## Still open

- [ ] **Live installation acceptance:** the installed app was observed as `0.3.26+29`.
  Candidate `0.3.27+30` is local only and has not been installed or offered through
  the in-app update dialog. No deployment or personal installation change is
  authorized by the repository instructions for this run.
- [ ] **Physical-device acceptance on the current app:** observe fresh `bodi-pi` and
  `bodi-pc` telemetry in the installed UI and record metric names, values, and
  observation timestamps. Earlier source/probe results do not prove the current
  installed build's UI behavior.
- [ ] **OPC-UA acceptance on the current app:** browse an authorized live source,
  read a selected node, and verify its live value and timestamp. The canonical UI
  gate uses an owned managed acceptance Core, not the user's physical devices.
- [ ] **Operator visual acceptance:** the technical visual comparison passes, but
  the baseline still does not record operator acceptance.
- [ ] **Release distribution readiness:** the local candidate uses an ad-hoc app
  signature and no Developer ID Team ID was available. A distributable signed
  release and user-visible OTA rollout have not been demonstrated.

## Constraints and next safe work

- Do not use GitHub Actions; use the local OTA tooling only if a release is
  authorized.
- Do not push, deploy, install over the personal app, change its database, perform
  private SSH, or activate schema 7 under the current repository instructions.
- Do not label the app complete based on the local candidate or managed fixture.
- The next local work should close product defects found by source review or add
  repeatable acceptance coverage without touching the personal installation. The
  remaining live-device and rollout checks require a permitted operator-run
  acceptance window.
