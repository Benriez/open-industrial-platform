# OIP app completion: current acceptance state

## Latest snapshot — 2026-11-18, v0.3.38+41 installed

[OIP 0.3.38](https://github.com/Benriez/open-industrial-platform/releases/tag/v0.3.38)
was published as a signed OTA and installed on this Mac. The published asset
digests matched the installed package. The archive SHA-256 is
`74fae7e33389e9c160ed81b00a5967388ec158ea3b557586fd34cfd54260ae6f`.
Strict app signature verification passed, the running app connected to the
relay at `127.0.0.1:18856`, and the LaunchAgent configurations matched their
backups. The previous app is saved in
`/private/tmp/oip-rollout-0.3.38.qufXdq`.

An authenticated `device-operator` session successfully read the live
snapshot while the platform Settings and Management reads returned HTTP 403.
Settings now starts with local preferences. Core settings retain their
authorization checks and a separate entry. The local Versions & Updates
section works independently of Management. An in-app check after a fresh
operator sign-in remains pending.

The full canonical gate passed on revision
`3a80fa8abd8039c8c45da91ae4c86dc2bcb9a50b`, tree
`3b9b87cd800b0bc2aa3007167338958a8e0cc089`. Local and served
`main.dart.js` match at SHA-256
`22094b895425ea542bc13a2a8fa25b3410c62358639afb67ea6a261a1ed684b7`.
The gate recorded 412 Flutter passes, one skip, 191 browser checks without
failure, two visual comparisons and eight acceptance phases. The measured
report is `target/oip-0.3.38-release-gate/oip_canonical_ui_gate/report.json`
in the `fix/oip-local-updates-in-settings` worktree.

## Previous snapshot — 2026-11-18, v0.3.37+40 published

[OIP 0.3.37](https://github.com/Benriez/open-industrial-platform/releases/tag/v0.3.37)
is available as a signed OTA. The local release script built and verified the
package. After a GitHub upload timeout, the missing assets were uploaded to
the existing draft and all three GitHub digests matched before publication.
The archive SHA-256 is
`5cfe3317705cd555eb58dde50488b3a3170f890622d6bbec18531339ea38567e`.
The installed Mac app was still on build 39.

The macOS window frame continues to follow the drag. The Flutter surface keeps
its previous size until the AppKit event tracking loop ends, then resizes
once on the default run loop. An AppKit test verified 20 size changes,
back-to-back drags, a no-op drag, and subsequent immediate resizing. An
isolated native release app launched and reached the loopback relay. Repeated
physical drags and authenticated views on installed build 40 await verification.

The full canonical gate passed on revision
`80851a710c6437472dd0607b26f1d06e76491211`, tree
`f411bf542be98e32cc83f8c4adeeda7212d40cc7`. The local and served
`main.dart.js` match at SHA-256
`23c01ec883d587b3106c5d262515c81f38c02e939bff68bb29bf6f10e4882eb3`.
The gate recorded 409 Flutter passes, one skip, 191 browser checks without
failure, 13 screenshots, two visual comparisons and eight acceptance phases.
The receipt is `target/oip-0.3.37-canonical/oip_canonical_ui_gate/report.json`
in the `fix/oip-macos-deferred-live-resize` worktree.

## Previous snapshot — 2026-11-18, v0.3.36+39 installed

[OIP 0.3.36](https://github.com/Benriez/open-industrial-platform/releases/tag/v0.3.36)
was published from the Mac as a signed OTA. GitHub's archive digest matched the local hash
`c2913660268f174d323fb0b9c5e256b8247bb6a322ba4e7860f91915832368ac`.
The authorized rollout verified the downloaded manifest against the installed
app's pinned signing key and used the matching local archive after the archive
download timed out. The previous app and LaunchAgent configuration are saved
in `/private/tmp/oip-rollout-0.3.36.t6b5DB`. Strict signature verification passed
for installed build 39. The new process connects to the existing local API
relay at `127.0.0.1:18856`. Both LaunchAgent configurations match their backups.

An authorized API check after installation returned 38 fresh metrics, three
LAN topology links and 18 OPC UA nodes on each host. It received 25 snapshots
in 34.2 seconds, with zero errors and a longest gap of 2.536 seconds. This was
a separate API session. A new Touch ID sign-in and the authenticated native
views still await verification.

The authenticated installed app reproduced the stale OPC UA view and empty
source selector during an intermittent connection. An independent native API
check on the same local relay read 38 observations and received 25 live
snapshots in 47.3 seconds, with a longest gap of 3.8 seconds. The new build retries
failed authorized source and node reads after a fresh snapshot. The macOS
transport also polls an authorized snapshot when the live stream returns an
error event. Regression tests cover both cases.

The full canonical gate passed on revision
`d44cf21783cf9b53375626d3357ccc518467b8fe`, tree
`81ec3e1f4adf1672f371b0a65d0060c311aa9e7d`. The local and served
`main.dart.js` match at SHA-256
`acf45179ac24b5901c95b9a789ff8d08858ca5e5df33b77c00886993077ce73b`.
The gate recorded 409 Flutter passes, one skip, 191 browser checks with no
failures, 13 screenshots, two visual comparisons and eight acceptance phases.
The receipt is in `target/oip-0.3.36-canonical/oip_canonical_ui_gate/report.json`
in the `fix/oip-live-opcua-source-recovery` worktree.

A separate build 38 crash recurred while dragging the window edge. The
macOS report records `EXC_BAD_ACCESS` at `0x50` during AppKit live resize.
The matching FlutterMacOS binary places frame 2 inside
`-[FlutterViewController updateSemantics:]`. Native resize remains open.

## Previous snapshot — 2026-11-18, v0.3.35+38 installed

The installed app completed the GitHub OTA update to build 38. The updater
verified the manifest and archive, and strict code-signature verification
passed on the installed bundle. The running app connects to the OIP relay at
`127.0.0.1:18856`. The operator reported that login works again. A fresh
biometric sign-in and the native workstation views still need verification.

An authenticated live check returned 38 fresh metrics across bodi-pc, bodi-pi
and OpenWrt, three LAN topology links, and 18 OPC UA nodes on each host with
successful temperature reads. A follow-up stream check delivered 62 snapshots
over 114.2 seconds with zero errors and a longest gap of 8.138 seconds. The
Hue Bridge is registered. From bodi-pi its public configuration returned
HTTP 200 over TLS with the pinned certificate. Hue telemetry awaits physical
pairing.

The Mac App Store export tool now creates a separate directory for each run
inside the build tree, preserves earlier builds and rejects upload execution.
The export rehearsal passed nine checks. The local 0.3.35+38 Store bundle
passed the package preflight for signing structure, sandbox, privacy metadata,
listing assets and disabling GitHub OTA in that bundle. The hardened ad-hoc
archive passed strict code-signature verification and preserved a previous
archive in the rehearsal. The hardened archive launch was outside this
preflight. A signed Store export remains pending. The Mac reported no Apple
Distribution signing identity.

## Previous snapshot — 2026-11-18, v0.3.35+38 published

[OIP 0.3.35](https://github.com/Benriez/open-industrial-platform/releases/tag/v0.3.35)
was built, signed and published from the Mac. GitHub Actions did not run.
The archive SHA-256 is
`b0ee7c73a1cd1eaae97ecee5fdae80e25f3f4345f7aa6064c5d7bd7ce06cd68f`.
The installed bundle was still `0.3.33+36` when the release was published.
The local OTA check timestamp was backed up and cleared so OIP can show
the update when the operator next opens the application.

macOS logged `UI lost focus` during a biometric attempt in the installed
OIP process. An OTA check was running at the same time. Version 0.3.35
defers the update offer during biometric authentication and presents it
as a sheet attached to the OIP window. Touch ID requires the focused OIP
window, and the biometric dialog hides the password fallback that returned
a cancellation. An OIP one-time code restored the real operator session.
The versions dialog now offers the signed update check independently of
the Core settings permission, which returned HTTP 403 for this operator.
Physical Touch ID acceptance is still pending.

The full canonical gate passed on revision
`c92328d9c0914558902ded90f1fec4430693b69e`, tree
`39ac79cc953448da744f97a40f585cb3e52534e2`.
Local and served `main.dart.js` match at SHA-256
`6cff2ec4299e36bed68e7a205e10379dc3ddbbe70155993a99ce46ae602ae2e7`.
The gate recorded 407 Flutter passes, one skip, 191 browser checks without
failure, two visual comparisons and all eight functional phases.
See `target/oip-0.3.35-final-gate/oip_canonical_ui_gate/report.json`.

## Previous snapshot — 2026-11-18, v0.3.34+37 published

The signed macOS OTA is published as [v0.3.34](https://github.com/Benriez/open-industrial-platform/releases/tag/v0.3.34).
The measured installed bundle is still `0.3.33+36`. Install using the in-app
update check. The full canonical UI gate passed on revision
`1512bca161fd9e036a8c99984b326dc1e8ba6854`, tree
`58154da6b783f9674de5df865b1a5cc380d72873`. The served and local
`main.dart.js` match at SHA-256
`dcbfaea58f3fe7e1879ab13445324d15a1eb6e9d667dc717a7a67bcac46772e8`.
The gate recorded 406 Flutter passes, one skip, 191 browser checks with no
failures, 13 screenshots, both visual comparisons and eight functional phases.
The operator visual acceptance remains pending. See
`target/oip-0.3.34-complete-gate/oip_canonical_ui_gate/report.json`.
Verified OTA archive SHA-256
`5c084ecb13db4015f690f3f6a3b387a3cb1c009230504fa9dbd9e18b21f227bc`.
The release used the local publishing tool. GitHub Actions did not run.

- The Pi Core preserves healthy SSH sources across routine polls and
  compresses snapshots and the live stream when the client accepts gzip.
  The Mac relay prefers a private forward through bodi-pc, falls back to the
  direct Pi route, and replaces a failed forward without cutting active
  streams on that forward. Version 0.3.34 falls back to authenticated
  snapshot requests when its stream stalls. A focused native test verifies
  that a context change does not cancel the global snapshot.
- The live authenticated API returned 15 fresh metrics for bodi-pc, 12 for
  bodi-pi, 11 for OpenWrt and three observed LAN links among those devices.
  The router inventory note now reflects its active SSH source. The Philips
  Hue Bridge is registered at the same site. Its collector is still unpaired.
- The live OPC-UA API browsed 18 nodes on each host, read CPU temperature,
  and accepted an idempotent operator write followed by successful readback
  on both hosts. The host endpoints now timestamp accepted operator writes.
- The one-time code restored the Mac session. macOS reported a lost-focus
  cancellation and then a password-fallback cancellation during Touch ID.
  The OIP keychain item exists. Successful biometric sign-in, an installed
  0.3.34 session, and operator visual acceptance still need confirmation.
  No Apple Distribution identity was available in the signing preflight.

## Previous snapshot — 2026-11-18, v0.3.33+36

The false `API STALE / RECONNECT` warning is fixed and the signed OTA is
installed at `/Applications/Open Industrial Platform.app`. Full canonical gate
passed on source `80b5666134cca03d7bb811828b7055f7f29ce49e` (tree
`8a9f53a73812120f40cedef56f0ea8bf63735a74`): 405 Flutter tests passed, 0
failed, 1 skipped; browser 191/191; 13 captures; visual comparisons passed;
local/served `main.dart.js` SHA-256
`08353417420d73e46d25dea9f229f8952143eb4475351036868ba6d03bddecf9`. OTA
`v0.3.33` was published directly without GitHub Actions and installed as build
36; strict code-signature verification passed. The relay returned 90/90 HTTP
200 session responses over three minutes while signed out. The app correctly
shows `ANMELDUNG ERFORDERLICH` instead of a false stale-API warning.

**Touch ID diagnosis:** the Core has one persisted device credential for `device-operator`; the Mac login Keychain contains the OIP credential item, and its ACL includes the installed app descriptor. This proves the pairing objects exist, but not that their secret values match or that biometric-backed read and Core redemption succeed. No credential was read or printed.

**Still open:** authenticated Touch ID/session proof and the installed-app
telemetry, OPC-UA and topology views; router inventory wording; Hue Bridge
identity registration; operator visual acceptance and native resize/crash
acceptance. App Store preparation is not a verified upload artifact: the
ad-hoc hardened archive launch probe reports a missing framework path although
the framework binary is present, and an Apple Distribution identity is not
available in the current preflight. The checker receipt is
`docs/evidence/oip-mas-package/mas-package.json`. No GitHub Actions run, personal
database migration or schema 7 activation occurred.

## Prior snapshot — 2026-11-18

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
- A live recheck found the Core, private API relay, and Pi OPC-UA daemon active
  as `systemd --user` services on the Pi (all report zero restarts); the PC
  OPC-UA daemon is active as a user service there. System-wide `systemctl`
  reports them inactive because they are user units; `systemctl --user` is the
  authoritative check.
- The live Core database has an enabled SSH connection and source placement
  for each of `bodi-pi`, `bodi-pc`, and `OpenWrt Router`, all at site `pi-site`.
  Their most recent verified connection records were about 30, 30, and 3
  seconds old in the check. Applying the Core's freshness, site, address-match,
  and neighbor-state rules to those saved records yields three LAN links:
  Pi–PC, Pi–router, and PC–router. This proves the Core has qualifying link
  evidence; the authenticated app projection still needs an end-to-end check.
- Direct OPC-UA browsing over the loopback-only services succeeded on Pi port
  4842 and PC port 4840. Pi returned live CPU/memory, CPU and SoC temperature,
  and `vc4-drm` GPU identity; PC returned live CPU/memory, CPU temperature,
  `amdgpu` identity, and GPU temperature. Telemetry variable `AccessLevel=1`
  is read-only; `operator.maintenance` and `operator.note` report
  `AccessLevel=3` (read/write). No device values were written.
- The router's source placement and telemetry connection exist, but its stored
  inventory description still says “SSH monitoring connection not configured
  yet.” That stale text should be corrected through the authorized inventory
  workflow after the installed app session is restored; no database row was
  edited directly.
- A live read-only request to `http://192.168.1.131/api/config` returned a Hue
  Bridge (`BSB002`, bridge ID `001788FFFE48E917`, software `1978688000`, API
  `1.78.0`). The bridge is not yet registered in OIP. Inventory registration
  can use the measured identity; reading lights requires a Hue API token
  created by pressing the bridge button, which has not been done.
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
- A longer anonymous relay check completed 90/90 HTTP 200 requests over 3m07s
  (median 90.2 ms, maximum 102.4 ms). This argues against a persistent relay
  stall during that window, but it did not browse OPC-UA through the
  authenticated app session.
- Current App Store preflight for `0.3.32+35` passed the repository package
  checker: direct OTA disabled, sandbox and network-client entitlements
  present, six valid listing screenshots, no quarantined files, and every
  bundled executable signed. Its local archive carries the hardened runtime
  but cannot launch under the ad-hoc placeholder signature. The final Apple
  Distribution signed archive is still unverified and needs the operator's
  certificate/profile. Persistent receipt:
  `docs/evidence/oip-mas-package/mas-package.json`. It records source
  `ae7dcb19dc83288ab529bc9bd9d176717a8e8e4c`, tree
  `905742124c5d2127bc1a797c8a5e2a33a112ceb3`, App Store build `0.3.32+35`,
  and a clean source tree at measurement time. The archive uses an ad-hoc
  placeholder identity and its hardened launch result is not final
  Apple-signing acceptance.
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
- [x] Correct the router inventory description and confirm its live SSH source.
- [x] Register the verified Hue Bridge in OIP inventory.
- [ ] Pair and verify the Hue Bridge with its physical link button before
  enabling real Hue telemetry.
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
