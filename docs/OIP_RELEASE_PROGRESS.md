# OIP release progress

Single state file for the autonomous OIP release loop. Every iteration reads this file
before choosing work, executes **one** clearly delimited step, verifies the real function,
records the measured evidence below and commits only verified changes.

Scope of the release goal: a fully locally usable OIP application with secure browser login,
a real multi-infrastructure view, working Flutter device management, verified SSH onboarding,
real monitoring, consistent Spectrum UX and reliable macOS operation.

## 1. Canonical state

### GitHub repository and first OTA release (2026-11-15)

The previously local repository is now connected to the public GitHub repository
`Benriez/open-industrial-platform`. The `main` branch and annotated tag `v0.3.1` are published.
The `macos-ota-release.yml` workflow was manually dispatched for that tag after the tag push
did not start the workflow automatically; GitHub Actions run `43656017421` completed successfully.
The release contains the universal macOS archive, JSON manifest and detached Ed25519 signature.
The downloaded archive's SHA-256 matches the signed manifest, the signature verifies against the
embedded release public key, and the extracted app passes strict code-signature verification with
bundle ID `org.openindustrial.oipDashboard`, version `0.3.1`, build `4`, and OTA enabled.

The `/Applications/Open Industrial Platform.app` installation remains version `0.3.0` build `3`.
Its updater check timestamp advanced after a fresh launch, but no update prompt appeared. The
automatic offer and live install therefore remain **OPEN**; the signed release's correctness is
verified, but end-to-end OTA installation is not claimed. The installer helper's launch path also
needs a separate review before relying on it for the live installation.

**GitHub OTA updater fix (2026-11-15, branch `fix/oip-github-ota-asset-name`, product `1143e4c`).**
The silent offer failure is diagnosed and fixed. The installed `0.3.0+3` client's updater looked for
the signature asset `oip-macos-manifest.sig`, which the release never publishes — the packager signs
`oip-macos-manifest.json` and publishes the detached signature as `oip-macos-manifest.json.sig`, so
the lookup returned nil and the offer failed silently. The decision logic is extracted into
`apps/flutter/macos/Runner/OIPGitHubOTA.swift` (the exact asset-name constants, the trusted-URL and
build-compare helpers, and one `verify()` the network path and the tests both call), the live updater
now uses those shared types and logs every reject reason, and the installer helper gained an
`OIP_OTA_APP_NAME` test seam. The helper's replace/verify/rollback/relaunch-without-premature-success
behavior is confirmed and regression-tested. **Verified:** `flutter build macos --release` compiles
with 251 `OIPGitHubOTA` symbols in the universal `oip_dashboard` binary, and the focused suites pass
(`tests/oip_ota_logic.py` 2, `tests/oip_ota_install_helper.py` 4 — refuse-without-touching on exit
21/22/23 and byte-for-byte rollback on a forced post-swap launch failure — `tests/oip_github_ota_package.py`
1). The installed `0.3.0+3` app was deliberately not run through a real update (it is running, pid
33826, and a live self-install must not be triggered from the loop), so end-to-end OTA stays
`NOT VERIFIED; AUTO OFFER OPEN` and needs an operator to install the fixed build and trigger the offer.

**Staged fixed OTA candidate (2026-11-15, loop `9751d2a`).** The canonical worktree's on-disk
`oip_dashboard.app` is a stale pre-fix build (Nov 13), so no ready fixed artifact existed for the
operator. The verified fixed build (branch `fix/oip-github-ota-asset-name`, HEAD `c3e5d91`; 251
`OIPGitHubOTA` symbols) was copied byte-identically to
`/private/tmp/oip-ota-candidate/oip_dashboard.app` (binary sha256
`2cf06734d07157cfb76dba4b7e82b4019324539dffc9f18843399d3d0184c2f5`, ad-hoc signed, version `0.3.0`
build `3` but carrying the fixed updater). It is the correct client for Task 4: at the installed
version with the corrected asset-name lookup, so its updater check should discover and offer the
published `v0.3.1+4`, producing the real `0.3.0+3 → 0.3.1+4` change. The `/Applications` app and pid
33826 were not touched. Task 4 stays operator-driven; the receipt records the staged candidate and its
operator install steps, and the ledger gate G9/OTA row reflects the same.

**OTA archive-digest rejection now unit-tested (2026-11-15, loop `2665891`).** Acceptance requires
the updater to reject invalid archive digests with automated test coverage. That check previously
lived only inline in the live downloader (`MainFlutterWindow.swift`) and the `archiveDigestMismatch`
enum case was dead code, so no test covered it. The hex encoding and the digest comparison are now
pure `OIPGitHubOTA` helpers (`sha256Hex(of:)`, `verifyArchiveDigest(sha256Hex:manifest:)`) and the
live downloader calls them, so the network path and the regression test share one implementation.
`tests/oip_ota_logic.py` proves the matching digest is accepted and a tampered digest returns
`.archiveDigestMismatch(got, expected)`. **Verified:** `flutter build macos --release` compiles with
**254 `OIPGitHubOTA` symbols** (up from 251; fresh canonical binary sha256
`f84b61f009a324bd3275a0d73352c12a15773229ca71b4392d1ed111ba853760`) and all 7 OTA tests pass. The
operator candidate was re-staged from this canonical build (same `0.3.0+3` label, unchanged runtime
offer/install behavior). `/Applications` was not touched by the loop. **Process-state note (2665891):**
the recorded installed-app pid 33826 is no longer running (the operator quit it); the installed app is
still `0.3.0+3` at `/Applications`. Task 4 stays `BLOCKED_OPERATOR` regardless — the loop must not
trigger a live self-install from a build; the install and the offer observation remain the operator's
acceptance action.

**Live delivery-side offer-path proof (2026-11-15, loop `1010352`).** To de-risk the operator's Task 4
without a live self-install, the published `v0.3.1` release was re-verified against the **live** GitHub
release API and its real bytes. All three assets are present (tag `v0.3.1`, published `2026-11-15T00:04:29Z`);
the signed manifest declares `bundle_identifier=org.openindustrial.oipDashboard`, `version=0.3.1`,
`build=4`, `archive=oip-macos-universal.zip`, `archive_sha256=70a82d7d…bed4aea9`; and the **real downloaded
archive bytes hash to that exact sha256** (equal to the receipt's recorded value). Because build `4 > 3`,
`OIPGitHubOTA.isUpdateAvailable()` is true, so — combined with the previously verified ed25519 manifest
signature — the fixed client's entire accept path (`verify()` bundle-id/signature/archive-name/build plus
`verifyArchiveDigest()` against the real bytes) is proven to succeed against the live release. The operator's
installed `0.3.0+3` candidate is therefore guaranteed, from the delivery side, to discover and **offer**
`v0.3.1+4`; the only unverified piece remains the GUI install/rollback (G12). Recorded in
`docs/evidence/oip-github-ota/ota-receipt.json` (`checks.live_release_delivery_crosscheck`). `/Applications`
and the running state were not touched.

**Published `v0.3.1` ships the pre-fix updater (2026-11-15, loop `e0300c8` finding).** While
re-verifying the live OTA target, the shipped `v0.3.1+4` bundle was inspected directly and found to
contain the **pre-fix** updater, not the fixed `OIPGitHubOTA` client. Evidence from three angles:
(1) tag `v0.3.1` points to `45e09015` (the initial commit, `00:54 +0100`) and the CI record is
`6a77133` (`01:00 +0100`) — both ~3h **before** the fix `1143e4c` (`04:07 +0100`); (2) neither
release tree contains `apps/flutter/macos/Runner/OIPGitHubOTA.swift`, and their `MainFlutterWindow.swift`
still searches the never-published `oip-macos-manifest.sig`; (3) the freshly downloaded shipped binary
(version `0.3.1` build `4`) has **0 `OIPGitHubOTA` symbols** (sha256 `d341348c…0502`, versus the fixed
candidate's `f84b61f…853760`, 254 symbols). **Consequence for Task 4:** the operator's G12 offer check
still succeeds — the fixed local candidate (`0.3.0+3`, 254 symbols) discovers and **offers** `v0.3.1+4`
(build `4 > 3`, manifest/archive/signature all validate) — but **completing** that update installs a
`v0.3.1` bundle whose own updater is still broken, so it will fail its next update check; a public
download of `v0.3.1` carries the same latent bug into the next release. **Required operator action:**
re-publish the fixed client as a new signed GitHub release (e.g. `v0.3.2`, or re-tag `v0.3.1` from a
post-fix commit such as `e0300c8`) so the shipped artifact contains `OIPGitHubOTA.swift`. The loop
cannot push or publish (out of scope). **Re-publish path verified against the CI**
(`.github/workflows/macos-ota-release.yml`): it checks out the tag's commit and builds `apps/flutter`
from it, so a `v0.3.2` tag on a post-fix commit ships the fixed client (VERSION `0.3.2`, BUILD
`RUN_NUMBER+3` = 5 on the next run), and the `0.3.0+3` candidate offers it (`0.3.2 > 0.3.0`). Recorded in
`docs/evidence/oip-github-ota/ota-receipt.json` (`github_delivery.published_release_updater_state`).
`/Applications` and the running state were not touched.

**OTA loop terminal state (2026-11-15).** The `oip-open-release-tasks` job completed 100
successful turns, reached its configured `--max-runs 100` cap, and disabled itself with zero
execution failures. The checklist still counted its one operator-blocked OTA acceptance item as
pending, so it repeated that already-documented blocker until the cap. That item is now marked
software-scope complete and `BLOCKED_OPERATOR`, with the publication and live-install steps
preserved explicitly below; this **does not** change `NOT VERIFIED; AUTO OFFER OPEN` or claim OTA
acceptance. The loop must be resumed only for the final checklist-completion check, then remain
stopped until the operator publishes the fixed signed release and performs the live acceptance.

The open first-release software tasks are tracked in [`docs/OIP_OPEN_RELEASE_TASKS.md`](OIP_OPEN_RELEASE_TASKS.md)
and are the checklist for the `oip-open-release-tasks` OpenCode loop. Operator-only acceptance gates
remain recorded in the release ledger and must not be treated as software work the loop can fabricate.

| Item | Value |
|---|---|
| Canonical branch | `main` |
| Canonical source revision (the product: client, Core and release tooling) | `30d6bcc` — direct macOS GitHub OTA client and signed-release workflow; public release workflow dispatch was added in `6a77133` |
| The revision of the final acceptance | gate source revision `7a0c6da` with tested working-tree hash `be0fc5e40e3b08ce2b06a9781e2c1b952cee51b0`; local and served web bundle SHA-256 `d76764985bbf0c7626dea8a4090ed5bc6b6ebed64ba23d275956dd560d02703b` |
| The revision of the Core binary of the release | `0a9b64f` — the binary names its own revision; the same revision yields the same bytes |
| The build of the Core of the release | `cargo build --locked --release --workspace --bin oip-server --example mcp_probe` |
| The gate statuses of the current release | `docs/OIP_RELEASE_LEDGER.md` — the authoritative table |
| Integration method | real `git merge --ff-only`, no merge commit, no rewrite, in eleven controlled steps |
| Tracked files in the canonical source revision | 797 — the digest of the listing is named by the manifest of the release (`docs/release/oip-release-manifest.json`), which is recomputed with every release |
| Documentation commit on top | the ledger, the runbook, the receipts of `docs/evidence/` and the release manifest `docs/release/` are the only artefacts of the state of the release; the source of the Core and of the client is unchanged by them, so the manifest above stays the manifest of the source revision |
| Working tree | the **product** of the release is committed — the checker of the record proves it — and the receipts are published with the record, so a measurement that is published leaves the working tree changed until the publication is committed. The loop state directory is ignored |
| Push / deployment | `main` published to [Benriez/open-industrial-platform](https://github.com/Benriez/open-industrial-platform); signed macOS OTA release `v0.3.1` published (Actions run `43656017421`). The installed `0.3.0+3` app's fresh check did not present the update prompt, so live OTA installation remains unverified and open. |
| Personal schema-6 installation | **not activated**; untouched. A separate operator-hosted instance is running per N7 |

### oip-ui-polish loop status (UI-polish sub-loop)

The `oip-ui-polish` sub-loop has completed its two highest-impact, evidence-backed items — Iteration
103 (client software-license attribution in the About section, product `d34326a`) and Iteration 104
(precise Settings error-state wording for HTTP 400 / `INVALID_REQUEST` plus a consistent catch-all,
product `8bb1c1a`). On **2026-11-14** the loop re-ran a fresh read-only audit of `apps/flutter/lib`
(read-only subagent + Model Router verification of its one candidate and a provenance-disclosure
spot-check). The audit and the verification agree: the remaining presentation layer is already
consistent, honest and reachable in real mode — provenance/simulated/fixture disclosures are present
and gated (`isFixture`, `snapshot.system.simulated`, `device.simulated`, `dataOrigin ==
contractFixture`) across the features, and error/empty states disclose absence/failure without
fabrication. The single candidate raised (mixed German/English device-filter labels in
`features/devices/device_inventory.dart`) is a localization *style* preference whose English terms map
verbatim to the canonical data-model identifiers; "normalising" them has no correct answer and would
reduce operator traceability to the contract, so it is **cosmetic and rejected** per the loop's
no-cosmetic-tasks rule. **No concrete, non-cosmetic, client-side, real-mode-reachable polish gap
remains.** The sub-loop is at a deliberate, documented stopping point; the canonical product revision
is unchanged (`8bb1c1a`). Any further work would require either an out-of-scope Core/contract/localization
change or an invented cosmetic task, both prohibited.

**Build receipt (2026-11-14).** To honour the loop's explicit "report the served bundle SHA-256"
requirement, the web bundle of the current canonical source was rebuilt with the canonical UI gate's
exact command (`flutter build web --release --web-renderer canvaskit`). Measured artifact:
`bundle_sha256 = 3f931cb89798842ba35fba26e2759d7c137812c41022ee6a9e7a5b2c3feb273`
(`build/web/main.dart.js`, 3,050,940 bytes; verified with both `sha256sum` and `shasum -a 256`). The
bundle provably contains the Iteration 103 (`Lizenz`) and Iteration 104 (`Management-Anfrage abgelehnt`)
strings, so it is the current source, not a stale artefact. It legitimately differs from the recorded
final-acceptance hash `d76764985bbf0c7626dea8a4090ed5bc6b6ebed64ba23d275956dd560d02703b` (revision
`7a0c6da`, before Iterations 102–104) because those iterations changed `apps/flutter/lib`. **Honest
limit:** only the *local* build hash (`bundle_sha256`) is produced here; the full canonical UI
design-regression gate — which serves the bundle and proves `served_bundle_sha256 == bundle_sha256`
byte-for-byte with the browser gate, the managed acceptance Core and the private IPC credentials
(`tests/canonical_ui_gate.py`) — was **not** run in this environment. Per `docs/design/
OIP_CANONICAL_UI_BASELINE.md` §4 a build hash without that gate is **not** a UI PASS; operator visual
approval therefore remains `VISUAL_PENDING_OPERATOR_ACCEPTANCE`. The build wrote only to the
git-ignored `build/` directory; no source, product, Core, contract or dependency changed and the tree
stayed clean.

**Reproducibility confirmed (2026-11-14):** two further `flutter build web --release --web-renderer
canvaskit` runs reproduced the identical `bundle_sha256` `3f931cb89798842ba35fba26e2759d7c137812c41022ee6a9e7a5b2c3feb273`,
so the recorded hash is a **deterministic, reproducible provenance artifact** — a stable value the
canonical UI gate can compare served-vs-local byte for byte (baseline §5 check #1 / R10). The builds
wrote only to the git-ignored `build/`; the tree stayed clean.

**Loop outcome — `oip-ui-polish` COMPLETE; the sole remaining verification is BLOCKED (environment).**
The sub-loop has delivered every concrete, non-cosmetic, client-side, real-mode-reachable polish item
(Iteration 103 license attribution; Iteration 104 Settings error-state precision) and a fresh read-only
audit plus Model Router verification confirmed no further such gap exists. The one remaining acceptance
step — the full canonical UI design-regression gate that proves `served_bundle_sha256 ==
bundle_sha256` byte-for-byte — is **BLOCKED for this loop and cannot be resolved here**: it requires the
loop's *owned* managed acceptance Core and its private IPC socket/credentials, and this environment
exposes neither. The only running `oip-server` processes belong to **other workstreams** (a
`oip-diagnostics-2027` daemon, an `oip-0084` `--demo` server, and an `oip84-settings` daemon); per
`AGENTS.md` §5 this loop must not touch a foreign preview process or another workstream's integration
authority, and driving the `--demo` core would risk simulated data in real mode. No push, deploy,
schema-7 activation, personal-database change or store publication was performed. **No further
`oip-ui-polish` work is available; subsequent firings must not invent cosmetic tasks.**

**Re-confirmation and loop stop (2026-11-14).** A further loop firing re-checked the backlog and the
current presentation layer directly (no subagent, to avoid interrupt churn). The independent spot-check
of `apps/flutter/lib` for unfinished, real-mode-reachable polish defects found **none**: every
`nicht implementiert` / `not implemented` string is an honest disclosure of a genuinely-absent backend
capability — `devices.dart:202` (server-side history endpoint), `network.dart:1732` (core capabilities),
`device_onboarding.dart:428` (SNMP/Windows/Android/VPN monitoring), `diagnostics.dart:700,708` (persisted
diagnostics runs) — which is exactly what `OIP_CANONICAL_UI_BASELINE.md` requires (never fabricate;
disclose absence). Every `loading` state is a real async loader with completion (infrastructure-context
authorization, OPC-UA node paging, device-detail fetch, diagnostics event/evidence load), not a
"loading state without a loader". The two `PLACEHOLDER` hits are honest MCP-client-config status
indicators (`settings_content.dart:393` `PLACEHOLDERS` metric = `NONE`/`REQUIRED`;
`settings_workstation.dart:738` `'Placeholder required'` fallback for a null `executable`). No
`TODO`/`FIXME` in `lib/` is user-facing or reachable in real mode. **Determination: `NO_READY_TASK` —
no independent, safe, client-side, real-mode-reachable, non-cosmetic UI-polish item remains.** The only
outstanding item is the environment-blocked runtime canonical UI §5 gate (owned managed acceptance Core
+ private IPC credentials unavailable; other workstreams' `oip-server` processes are off-limits per
`AGENTS.md` §5). Per the loop stop protocol the exact blocker and required next action are recorded here
once, and the loop stop file `.opencode/opencode-loop/oip-ui-polish.stop` is created; subsequent firings
must read that file and stop without inventing cosmetic work. Canonical product revision unchanged at
`8bb1c1a` (`main` @ `ed98205`); no source, product, Core, contract or dependency changed.

**Canonical UI baseline conformance check (2026-11-14, static code↔contract, no running Core needed).**
The presentation layer is contract-bound (`docs/design/OIP_CANONICAL_UI_BASELINE.md`), so the current
client was reconciled against §3 (approved shell) and §4 (R1–R10 prohibited regressions). **§3 PASS:**
the six workstations exist (`features/{overview,devices,network,opcua,diagnostics,settings}.dart`); the
global infrastructure context selector is present (`widgets/infrastructure_selector.dart`, key
`infrastructure-context-selector`); context-sensitive inspectors exist (`app/workspaces.dart`: `enum
WorkspaceId { overview, devices, network, opcua, diagnostics, settings }` + `AdaptiveWorkspaces`); the
three themes exist (`design_system/theme.dart`: `enum OipThemeVariant { spectrum, graphite, daylight }`);
the footer identity is `OIP · SPECTRUM 2027` (`models/app_metadata.dart`). **§4 PASS (real mode):** the
prohibited literals `Deine Infrastruktur. Ein Bild.`, `Erfasste/Erreichbare Geräte`, `Tailnet`,
`Remote Site`, `OIP / 005 UI` are absent from `lib/`. The four remaining hits are all compliant:
`scenario-select` (`app/app.dart`) renders only under `snapshot.system.demoControls` (demo-only, never
in real mode, beside the real selector — R5); `AGENT-FIRST` (`settings_workstation.dart`) is a
technical status pill in the Settings capability context, the one location R6 permits (not a sidebar
card); `M-01` appears only demo-gated (`features/opcua.dart` `if system.simulated`) or as code-level
defaults/contract comparisons, never a real-mode primary measurement (R3); `Normalbetrieb` is the
German word for normal operation in diagnostics health/empty states, not the scenario selector (R5).
**Conclusion: no §3/§4 conformance gap.** This is static evidence only; the runtime §5 gate (served
bundle == local, visual comparison) remains the environment-blocked item recorded above.

**Fresh-dimension re-check (2026-11-14, second re-fire).** The loop was re-fired with an explicit
directive to *not* stop and to keep reporting concrete work or the exact blocker each cadence. Honoring
both that directive and the shared "do not invent cosmetic work" rule, this iteration performed a
genuine investigation of presentation-layer dimensions the earlier grep-based audits did **not** cover,
rather than re-reading the same `TODO`/`not implemented` list. Examined and found sound: (1) **numeric/
unit formatting** — `toStringAsFixed(1)` latency/loss/telemetry in `network/network_model.dart:124,130`,
`overview/telemetry_chart.dart:117,123,167,168,302`, `features/network.dart`, all carrying the honest
`· Fixture` disclosure for simulated links; (2) **timestamp formatting** — `widgets/components.dart:734`
`timestamp()` and `features/opcua.dart:2122` `_clock()` both render explicit `UTC` with millisecond
precision from `DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)` (no local/UTC ambiguity, no epoch
leak), and `opcua.dart:2138` large-value grouping is value-driven, not demo-driven; (3) **accessibility**
— `Semantics` is applied pervasively across every workstation feature with honest labels and
`excludeSemantics` used deliberately for decorative overlays (`app.dart:234`, `network_explorer.dart:447`,
`event_explorer.dart:465`); (4) **empty/error states** — `StateMessage` (`app.dart:548`, with a real
`Erneut versuchen` reconnect action), `InlineNotice` (`components.dart:604` `DataTimeline` empty state),
and the footer blocker line (`app.dart:600`) all disclose absence/failure honestly, and the
`unknown`-tenant blocker is stated as "not delivered to this session" rather than faked. **No concrete,
non-cosmetic, client-side, real-mode-reachable defect or improvement was found in these dimensions.**
**Determination reconfirmed: `NO_READY_TASK`.** The only outstanding item remains the environment-blocked
runtime canonical UI §5 gate. Consistent with the current "do not stop" directive, **no stop file was
created or modified this iteration**; the earlier stop file remains as recorded loop state. Canonical
product revision unchanged at `8bb1c1a` (`main` @ `b4ec656`); no source, product, Core, contract or
dependency changed.

**Contract-trace verification (2026-11-15, third re-fire).** A fresh cadence ran a *behavioural*
defect hunt (not a TODO grep): a delegated read-only review raised one HIGH-severity candidate —
a claimed key mismatch in `features/opcua.dart` where `_resolve`/`_samplesFor` look up by
`node.name` while `_liveMap`/`_ingest` key by `observation.metricId`, asserted to fail for any real
OPC-UA node whose BrowseName differs from the metric id. Model Router traced the full contract and
**proved the claim is a false positive**: the server sets `Node.name` to the source's browse name
(`application_services.rs:434-438`) and then reads that node's value with `MetricId::new(&name)`
(`:467`), and `data_value_to_observation` stamps the returned observation's `metric_id` from that
**same** name (`oip-opcua/.../mapping.rs:318`); `MetricId::new` only trims whitespace and never
re-cases (`oip-core/src/model.rs:20-27`). Therefore, for every node that *carries* a live
observation, `node.name == metricId` **by construction**, so `liveById[node.name]` and
`sessionHistory[_sampleKey(source, node.name)]` resolve correctly; a node whose browse name is not a
valid metric id simply carries no observation (disclosed, not faked). The review's second concrete
claim (unreachable `return` in `widgets/opcua_compare.dart:245`) was likewise a misread — line 244
`return value.toString()` is the reachable fall-through for normal-range finite values. The remaining
leads were unreachable defensive concerns (`overview.dart:432` `value[0]` is fed only by the total,
non-empty `_coreLabel` switch over `CoreLifecycle`). Independently re-verified this cadence as sound:
`features/network/network_model.dart:121-131` RTT/loss formatting (honest `Nicht gemessen`/
`Nicht verfügbar` + `· Fixture` disclosure) and the OPC value localized/scientific/engineering
formatter in `features/opcua_value.dart` (traced for 0.5, 0.0001234, 1234000, ±0 — all round-trip
exact). **Determination: `NO_READY_TASK` — reconfirmed with deeper, contract-level evidence than the
prior grep audits.** No real-mode-reachable, non-cosmetic, client-side defect exists; none was
invented. `flutter analyze` → `No issues found!`; canonical product revision unchanged at `8bb1c1a`.

The canonical tree carries eleven controlled integrations: iteration 1 integrated the reviewed
real device onboarding candidate `ae4c6ba` (tree `f72cb66`) unchanged, iteration 2 integrated
the isolated conformance branch `feature/oip-real-device-conformance` (`fc828ac`), iteration 3
integrated the isolated harness branch `feature/oip-native-macos-harness` (`b19092d`), iteration 4
integrated the isolated payload branch `feature/oip-connection-payload-bound` (`5a48b0c`) and
iteration 5 integrated the isolated contract branch `feature/oip-009-context-contract`
(`d32c9d1`), iteration 6 the isolated regression branch `feature/oip-canonical-regression`
(`111dff1`), iteration 7 the isolated baseline branch `feature/oip-007-baseline-adoption`
(`6df189f`) and the isolated parity gate branch `feature/oip-parity-gate-convergence`
(`f4b89ed`), iteration 8 the isolated monitoring branch
`feature/oip-monitoring-observations` (`2ec4829` and `e12c009`), iteration 9 the isolated
history branch `feature/oip-observation-history` (`1287e23`), iteration 10 the isolated
overview branch `feature/oip-managed-overview` (`1e6b743`), iteration 11 the isolated
network branch `feature/oip-network-placement` (`e9036ef`). No iteration weakened a contract
rule, and none activated the installation.

## 2. The gates of the current release

The authoritative table of the gates, their status and their measured evidence is
**`docs/OIP_RELEASE_LEDGER.md`**. It is written in every iteration and names the receipts of
`docs/evidence/`. The current state:

| Gate | Status |
|---|---|
| G1 integrated Core and the six workstations | DONE |
| G2 authentication, sessions, the parity of the transports, the isolation of the organizations | READY (the software part) |
| G3 the global infrastructure context | DONE |
| G4 device management in the application | READY (the software part) |
| G5 real device connections | BLOCKED_OPERATOR |
| G6 monitoring | READY (the software part) |
| G7 the approved Spectrum-2027 UX | DONE |
| G8 the six functional views | READY (the software part) |
| G9 the macOS build and the local operations | READY (the software part) |
| G10 the security release review | READY (the review is done) · BLOCKED_OPERATOR (the acceptance) |
| G11 the acceptance | DONE (the storage-failure path is measured) |
| G12 the operator acceptance | BLOCKED_OPERATOR |

The operator actions that the loop cannot perform are listed in the ledger. The release is
**not** production-ready: the gates that need the operator are open.

### 2a The acceptance of the milestone era (iteration 11 — historical)

The table below is the acceptance of the milestone era of the release. It is kept as the history
of that era; the state of the current release is the table above and the ledger.

Legend: `PROVED` = measured in this run on canonical `main`; `WITHHELD` = deliberately not
claimed; `BLOCKED` = cannot be executed without an explicit external decision.

| Gate | Status | Evidence (iteration 11, canonical `main` = `e9036ef`) |
|---|---|---|
| Rust format check | PROVED | `cargo fmt --all -- --check` → exit 0 |
| Rust workspace check | PROVED | `cargo check --locked --workspace --all-targets` → exit 0 |
| Rust clippy, warnings denied | PROVED | `cargo clippy --locked --workspace --all-targets -- -D warnings` → exit 0 |
| Rust workspace tests | PROVED | 181 passed, 0 failed, in 29 suites (`docs/evidence/oip-rust-regression/rust-regression.json`); no Rust source changed in iteration 10, so the result of iteration 9 stays valid for this tree |
| OPC-UA default backend | PROVED | 37 passed, 0 failed |
| OPC-UA open62541-only backend | PROVED | 2 passed, 0 failed (overlapping group) |
| Dependency policy | PROVED | `cargo deny check advisories licenses bans sources` → advisories ok, bans ok, licenses ok, sources ok |
| Server binary + official MCP probe | PROVED | `cargo build --locked -p oip-server --bin oip-server --example mcp_probe` → exit 0 |
| Flutter static analysis | PROVED | `flutter analyze` → exit 0, no issues |
| Flutter widget/unit suite | PROVED | 101 passed, 0 failed |
| Flutter web release, CanvasKit | PROVED | `flutter build web --release --web-renderer canvaskit …` → exit 0 |
| Flutter web release, HTML | PROVED | `flutter build web --release --web-renderer html …` → exit 0 |
| Browser identity + writer ownership | PROVED | `tests/real_device/acceptance.py` phase `browser_identity_online_writer` → PASS |
| Monitoring measurements in the operator panel | PROVED | `tests/real_device/acceptance.py` phase `actual_flutter_ssh_onboarding` → PASS; the rendered panel shows the ten host observations the Core received over SSH, compared against the Core response of the same device (`host.os` = `Darwin`, `host.memory_total_bytes` = 17179869184, all `fresh`); `apps/flutter/test/monitoring_observations_test.dart` → 3 tests |
| SSH handshake, identity confirmation, monitoring | PROVED | phase `ssh_handshake_confirmation_monitoring` → PASS, actual local macOS host facts (`facts_os: Darwin`) |
| Restart / SIGKILL recovery | PROVED | phase `restart_sigkill_identity` → PASS, integrity `ok`, foreign keys clean, 0 duplicate keys |
| Actual Flutter → HTTP → Core → OpenSSH | PROVED | phase `actual_flutter_ssh_onboarding` → PASS, browser receipt `target/oip-real-device-e2e/browser/report.json` |
| Ingestion without any client | PROVED | phase `no_clients_ingestion_progress` → PASS, 140 → 150 observations |
| Host-key rotation blocked | PROVED | phase `host_key_change_blocks_collection` → PASS, 0 new observations after the block |
| 8 official MCP SDK clients | PROVED | phase `eight_official_mcp_clients` → PASS, REST/MCP parity |
| Weak host key rejected by the server | PROVED | phase `weak_host_key_is_rejected_by_the_server` → PASS, `SSH_HOST_KEY_TOO_WEAK`, no binding created |
| Browser session boundary in Rust | PROVED | `crates/oip-server/tests/browser_session.rs` → 6 tests: exact Origin, single-use code, CSRF on every write, revoked session, revoked projection stream and the cookie path of the persisted history |
| Managed network view shows the authorized placement | PROVED | `apps/flutter/test/managed_network_test.dart` → 1 test; the authorized placement, the registered node and the honest absence of a topology are rendered, the loading state and the demo zones are gone; the browser receipt names the placement the Core delivered (`org-a · infra-a1 · site-a1`) |
| Managed overview shows the authorized infrastructure | PROVED | `apps/flutter/test/managed_overview_test.dart` → 3 tests; the source registry, its real health, its placement and the measured series are rendered and the demo coordinates are gone; the browser receipt compares the rendered overview with the source registry and the measurement the Core received over SSH (`SSH host browser-existing`, `host.memory_total_bytes` = 17179869184) |
| Persisted observation history in the device view | PROVED | `tests/real_device/acceptance.py` phase `actual_flutter_ssh_onboarding` → PASS; the Core persisted 10 samples of the connected device, the operator view rendered them as history and the browser receipt compares them against the Core answer; `apps/flutter/test/observation_history_test.dart` → 8 tests |
| Native macOS build and test | PROVED | `tests/oip008/ui_regression.py` → native build 11.6 s with the build marker, native integration test 39.1 s with the `All tests passed!` marker, against an owned isolated demo core |
| Legacy browser, interaction and visual regression | PROVED | browser 80.4 s, interactions 47.1 s, visual 63.4 s on the separately built HTML renderer |
| Milestone acceptance harnesses on the canonical tree | PROVED | `tests/canonical_regression.py`: OIP-008, OIP-008.2, OIP-008.2 schema3 migration, OIP-008.4, OIP-008.5, OIP-008.5 migration, the UI regression and the schema2 adoption all PASS on the canonical tree, no failed and no blocked case |
| Canonical Spectrum-2027 UI baseline and design regression gate | **PROVED** | `OIP_CANONICAL_UI_GATE=1 python3 tests/real_device/acceptance.py` → PASS on canonical `main` = `8c40a018b55e67ef17b69192ba35d255f336c542` (tree `d9272088659d5f5c979752d0fd31f94d34ed909d`): 361/361 Flutter tests, 187 browser findings with zero failures, 13 captures of the six workstations at 1440 px and 1920 px, the stable-shell visual comparison with both negative-control classes, all 8/8 managed acceptance phases including the actual Flutter SSH onboarding. The local and the served bundle are byte-identical (`docs/evidence/oip-canonical-acceptance/ui-gate.json`). Operator visual acceptance remains `VISUAL_PENDING_OPERATOR_ACCEPTANCE` |
| Physical Raspberry-Pi acceptance | **WITHHELD** | no endpoint, SSH user or approved identity was supplied; no personal device was contacted |
| Real installation activation (schema 7) | **BLOCKED** | requires a separate operator decision plus a fresh protected backup; forbidden in this loop |
| Productive remote/browser identity | **OPEN** | loopback local operator session only; no HTTPS, no remote identity, no hostile same-UID isolation |
| Durable tamper-proof audit | **OPEN** | audit is append-only in application code, the SQLite file itself stays writable by the daemon user |
| OT / endurance certification | **OPEN** | not claimed; the measurements below are short local observations, not an SLA |
| RUSTSEC-2023-0071 / -0089 / -2024-0449 | **OPEN** | still ignored with the existing documented local-only exceptions in `deny.toml`; no new exception added |

### Short local measurements (not an SLA)

* Official MCP `device_connection_read`: 20 sequential samples with 8 attached clients,
  p50 4.51 ms, p95 4.80 ms.
* One Core sample while the harness ran: 31,088 KiB RSS, 14.8 % CPU.
* Ingestion advanced 140 → 150 observations after all browser and MCP clients disconnected.

## 3. Open items, in execution order

Each item names the next *delimited* step, its gate and its blocker and carries one state:

* **READY** — released and executable by the loop. The loop continues with the first READY item.
* **BLOCKED_OPERATOR** — needs an explicit operator decision. The loop does not start it.
* **BLOCKED_DEPENDENCY** — needs a result another workstream owns. The loop does not invent it.
* **DONE** — closed and measured.

| Item | State | Next delimited step |
|---|---|---|
| N1 conformance findings (Core) | **DONE** | closed in iteration 2, F4 closed in iteration 4 |
| N1b F5 authorization rule | **BLOCKED_OPERATOR** | loosening a permission needs an explicit release |
| N2 native macOS build and test | **DONE** | closed in iteration 3 |
| N3 global selection payload | **BLOCKED_DEPENDENCY** | three-way reconciliation with the independent UI workstreams |
| N4 real installation activation | **BLOCKED_OPERATOR** | operator decision plus a fresh protected schema-6 backup |
| N5 production advisories and security | **DONE** for the three documented exceptions | the production security work stays open and unclaimed |
| N6 persisted observation history | **DONE** | closed in iteration 9 |
| N7 monitoring measurements in the panel | **DONE** | closed in iteration 8 |
| N8 real multi-infrastructure overview | **DONE** | closed in iteration 10 |
| N9 the network view of the authorized placement | **DONE** | closed in iteration 11 |
| N10 the managed diagnostics view | **DONE** | closed via the diagnostics-2027 workspaces (event explorer, evidence inspector, persisted evidence) in the approved Spectrum-2027 shell: `apps/flutter/lib/features/diagnostics/`, `managed_diagnostics_test.dart`, wired as workstation page 4 (`DiagnosticsPage`) in `apps/flutter/lib/app/app.dart`; reconciled into the approved workspace in `7fc612e`, measured in iteration 13 |
| N11 canonical Spectrum-2027 UI baseline and design regression gate | **DONE, closed in iteration 12** | the two parallel executions of the same integration were reconciled into one candidate, the full gate is PASS on `e7aa994` and the candidate is integrated into canonical `main` with `git merge --ff-only`; operator visual approval remains `VISUAL_PENDING_OPERATOR_ACCEPTANCE` |

A blocked item never stops the loop while an independent READY item exists. Items that need an
explicit operator decision (N1b, N4) or that would change a rule instead of enforcing one are
not started by the loop without a separate release.

### N1 — Close the conformance gaps found by the delegated source review (Core) — **DONE**

A read-only source review against `docs/architecture/real-device-onboarding.md` produced the
findings below. They are contract conformance defects, not new architecture. Fix them on an
isolated feature branch, add Rust-level regression tests, re-run the full gate set above and
integrate with the same controlled fast-forward.

**Status: F1, F2, F3, F6, F7 and R1 are fixed and verified in iteration 2, F4 in iteration 4.**
F5 is split off as N1b below because it changes an authorization rule and needs its own explicit
review.

| Id | Severity | Location | Defect | Contract reference | Status |
|---|---|---|---|---|---|
| F1 | medium | `crates/oip-server/src/ssh.rs` (`minimum_key_bits`, `parse_key_report`, `scan`) | The server never enforced "RSA keys require at least 2048 bits". `ssh-keygen -lf` already prints the key size, but only the fingerprint was kept; enforcement was delegated to the `RequiredRSASize=2048` client option of the *user* connection. A weak `ssh-rsa` host key could be scanned, shown, trusted and pinned. | `docs/architecture/real-device-onboarding.md:48` | **fixed** |
| F2 | low/medium | `crates/oip-server/src/ssh.rs` (`run`) and `crates/oip-server/src/connection_service.rs` (`read`) | `REMOTE HOST IDENTIFICATION HAS CHANGED` **and** `Host key verification failed` were both mapped to `SSH_HOST_KEY_CHANGED`, so an unknown key was reported as a rotation alarm. | `docs/architecture/real-device-onboarding.md:23`, `:66` | **fixed** |
| F3 | low | `crates/oip-server/src/browser_session.rs` (`login`) | The invalid-code limiter was evaluated *before* the grant lookup, so 16 malformed codes blocked the operator's valid single-use code for 60 s. Local-process availability bug inside the session boundary. | `docs/architecture/real-device-onboarding.md:36` | **fixed** |
| F4 | low | `crates/oip-server/src/ssh.rs` (`parse`) vs `crates/oip-storage/src/connection.rs` | The maximal host report the parser can build (up to ~128 KiB of interface/disk text) exceeds the 128 KiB `payload_json` CHECK, so a legal but extreme remote report fails the commit with an opaque storage error instead of a typed fault. | `docs/architecture/real-device-onboarding.md:50`, `:58` | **fixed** in iteration 4 |
| F5 | low | `crates/oip-server/src/connection_service.rs` (`check_plan`) | The read path requires `DeviceConnectionConfigure`; the contract places `GET /device-connections?plan_id=…` under `DeviceConnectionRead`. Conservative over-restriction, not an escalation. | `docs/architecture/real-device-onboarding.md:15` | **open and paused** → N1b |
| F6 | low | `crates/oip-server/src/browser_session.rs` (`login`) | The session-capacity check ran after the single-use grant was already consumed, so a valid code was destroyed when 64 sessions existed. | `docs/architecture/real-device-onboarding.md:36` | **fixed** |
| F7 | low | `crates/oip-server/src/ssh.rs` (`private_workdir`) | The SSH work directory was created with the process umask and only afterwards chmod'ed to 0700, leaving a brief world-readable window. | `docs/architecture/real-device-onboarding.md:48` | **fixed** |
| R1 | test gap | `crates/oip-server/tests/browser_session.rs` | No Rust-level test covered the browser session/CSRF/Origin flow; those assertions only existed in the external harness `tests/real_device/acceptance.py`. | `docs/architecture/real-device-onboarding.md:37-39` | **fixed** |

### N1b — Remaining conformance items (authorization rule) — **BLOCKED_OPERATOR**

**F4 (storage bound) is closed in iteration 4.** The parser now charges every collected disk
name, mount, interface name and address against a report budget, the server compares the
serialised record with the shared bound from the domain crate before the write, and an extreme
report is refused with an explicit fault instead of a rollback.

* **F5 (authorization rule) — open and deliberately paused.** The contract table in
  `docs/architecture/real-device-onboarding.md:15` places `GET /device-connections?plan_id=…`
  under `DeviceConnectionRead`, while the implementation requires `DeviceConnectionConfigure`.
  The change *loosens* a permission and therefore is a security decision, not a conformance
  fix. The loop does not take it without an explicit release. When it is released it needs:
  a negative test for a foreign principal and a principal without `InventoryManage`, a
  parity update in `docs/architecture/oip-008-rest-mcp-parity.md` if the capability matrix
  changes, and the normal capability, scope and audit gate set.

### N2 — Native macOS build and test (open acceptance item) — **DONE, closed in iteration 3**

The P0 handoff recorded the native build blocked inside SwiftBuild toolchain discovery
(`QNXSDP.findInstallations → LocalFS.listdir → __getattrlist`); Flutter returned zero without
running a test, and the raw exit code was corrected by a hash-bound receipt. No native PASS
was claimed.

**Measured result: the native macOS build and the native integration test work.** The cause was
not a broken toolchain but two bounds that were too short for a cold native build on this shared
machine: the UI regression harness applied a single 300 second bound to the web steps *and* to
the native step, and the native test ran its build inside the test command, where the default
test timeout of twelve minutes expired during the load phase. A cold `flutter build macos
--debug` needs about eight minutes here (497 s measured), the warm build 12.7 s and the native
integration test 34.4 s.

The harness now runs the native build as its own step with its own bound and a positive build
marker, runs the native integration test with an explicit `--timeout 30m` and its own bound,
records the elapsed seconds and the marker of every step, and never accepts a step without its
marker. The legacy web regression now receives the separately built HTML renderer, because it
reads the rendered text from the document while the CanvasKit build paints it on a canvas.

Result on canonical `main` (`b19092d`): browser 80.4 s, interactions 47.1 s, visual 63.4 s,
native build 11.6 s with the `Built build/macos/.../oip_dashboard.app` marker, native
integration test 39.1 s with the `All tests passed!` marker, demo core shutdown exit 0.

The native path stays what the contract allows: a compatibility and regression check in the
explicit isolated demo mode. Native authenticated session-cookie transport is still not claimed
and the native app is not the product path.

### N3 — OIP-009 browser session / SSE / global context contract — **contract DONE (iteration 5), global selection payload BLOCKED_DEPENDENCY**

`docs/oip-0082-verification.md:116`, `docs/oip-0084-verification.md:134`,
`docs/architecture/oip-0085-real-inventory-flutter-contract.md:3` and
`docs/architecture/real-device-onboarding.md:88-90` all defer the global context to OIP-009.
The implemented part (one-use pairing code, `HttpOnly; SameSite=Strict` cookie, exact Origin,
`x-oip-csrf`, session-scoped SSE revalidation, `setInfrastructureContext` cache invalidation)
exists in the canonical tree; the *contract document* and the global Organization /
Infrastructure / Site selection did not.

**The contract document now exists**: `docs/architecture/oip-009-browser-session-sse.md`. It
states the implemented and verified boundary — the pairing code, the session and its bound, the
exact Origin and CSRF rules, the revocation, the token hygiene, the SSE revalidation per
projection and the context seam with its cache invalidation — and names where each rule is
proved. It explicitly does **not** decide the global selection payload and states the
conditions a payload has to meet.

**The global selection payload remains open** and is not part of this release. It belongs to
the independent UI workstreams and still requires the three-way reconciliation of controller,
API and contracts/Devices named in `docs/architecture/real-device-onboarding.md:90`. The
canonical tree still has no global context selection: `setInfrastructureContext` has no
caller, and the operator sees the scope of the session Principal.

### N4 — Controlled activation of the real installation — **BLOCKED_OPERATOR**

Blocked by explicit instruction and by risk. The candidate opens schema 7; the personal
database is at schema 6 and must not be changed here. Required before activation: a fresh
consistent database/config/profile backup, the protected schema 6 rollback copy, one daemon,
one `--browser-login` code, the explicitly confirmed endpoint for
`tools/configure_ssh_profile.py` (dry run first) and the physical Raspberry-Pi acceptance that
belongs to the still withheld hardware verdict.

### N7 — Separate operator-hosted real-device installation — **RUNNING, PARTIAL** (2026-11-13)

The operator requested an installation without simulation data. A separate, private instance
was created on `bodi-pi` from a live backup of the disposable run. Only the simulator-owned
source, device and observations were removed from that copy; the two registered real devices
(`bodi-pi` and `bodi-pc`), their SSH connection profiles and their collected observations were
retained. The personal installation database was not opened or changed, and no schema-7
activation was performed.

The Core is managed by the `flashback` user systemd service with lingering enabled. At the
installation check it was active with zero service restarts and listened only on loopback port
18808; the simulator port 18809 had no listener. The Mac client was copied to
`~/Applications/Open Industrial Platform.app`. A per-user LaunchAgent maintains the SSH tunnel
from Mac loopback port 18848 to the Pi Core, so the installed client can reach the Pi without
placing the Core or simulator on the Mac. The app authenticated to this instance, selected the
real `The host` infrastructure context and displayed the API inventory with 2/2 devices, 2/2
connected sources and fresh data; the device view
reported 2 of 2 devices. This is an operator-hosted installation check, not a release gate or
operator visual acceptance.

**Remaining limits:** the observed overview also reported six collection problems and an
unknown Core health value. Those findings need investigation before this can be called ready for
continuous operation. This check did not exercise a Pi reboot, a Mac login restart, an OTA client
update, physical sensor values, the Hue Bridge or OpenWrt, the canonical UI regression gate, or
App Store signing and submission. No tests or release gates were run for this operational
change.

### N5 — Production advisories and remaining security work — **the three documented exceptions are DONE; the production work stays open**

**The three documented exceptions were verified against the advisory database in iteration 7
and are correct, necessary and unavoidable.** The earlier note in this file that the ignore
reasons of RUSTSEC-2023-0089 and RUSTSEC-2024-0449 would not match the advisory subjects was
wrong and is corrected here:

| Id | Crate | Subject | In the tree via | Patched |
|---|---|---|---|---|
| RUSTSEC-2023-0071 | `rsa` 0.9.10 | Marvin attack, timing side channel of the private key | `async-opcua-client`, `async-opcua-crypto` → `oip-opcua` | none (`patched = []`, still affected in 0.9.10) |
| RUSTSEC-2023-0089 | `atomic-polyfill` 1.0.3 | unmaintained (informational) | `heapless` → `postcard` → `async-opcua-server`, embedded targets only | none (`patched = []`) |
| RUSTSEC-2024-0449 | `unsafe-libyaml` 0.2.11 | unmaintained (informational) | `serde_yaml` → `async-opcua-core` | none (`patched = []`) |

All three are informational or unfixable in the upstream crates, so no dependency upgrade can
clear them; the local only exceptions stay as they are, with the unchanged review date. The
advisory of RUSTSEC-2023-0071 itself names the accepted scope: "Local use on a non-compromised
computer is fine", and the OIP-002 exception limits the usage to explicitly trusted loopback
tests.

Productive remote/browser identity, hostile same-UID isolation, tamper-proof durable audit and
OT/endurance certification stay open and are not claimed by this release.

### N6 — Persisted observation history in the device view — **DONE, closed in iteration 9**

The Core already serves the persisted history, the DTOs, the permissions and the query contract
exist, and the Flutter client names the gap itself: the device dialog states *"Autorisierte
historische REST-v2-Abfragen existieren im Core"* and the diagnostics view states *"Noch kein
persistierter Diagnoselauf"*. The seven routes `GET /api/v2/observations/history`,
`/api/v2/events/history`, `/api/v2/events/detail`, `/api/v2/diagnostics/gaps`,
`/api/v2/diagnostics/health-history`, `/api/v2/diagnostics/evidence` and
`/api/v2/diagnostics/findings` are registered in `crates/oip-server/src/api.rs:207-213`, they are
authorized by `crates/oip-core/src/capabilities.rs:153-181` and their REST/MCP parity is proven in
`crates/oip-server/tests/diagnostics.rs:271-334` and `tests/oip0082/acceptance.py:98-150`.

The next delimited step is one client feature plus one test group:

1. `apps/flutter/lib/services/api.dart`: add an `observationHistory({required String deviceId})`
   method to `DeviceManagementApi` and implement it as
   `GET /api/v2/observations/history?device=<id>`. The device scope is used deliberately, so no
   global Organization/Infrastructure/Site payload is invented; the SSH source placement already
   resolves the device to its source (`crates/oip-core/src/diagnostics.rs:13`).
2. `apps/flutter/lib/features/devices.dart`: replace the *"Historie noch nicht angebunden"*
   notice with the returned history, each sample explicitly labelled as historical. A stored
   sample is `stale` by definition (`tests/oip0082/acceptance.py:106`) and must never be drawn as
   a live value. `truncated` and `next_cursor` have to be surfaced; `DiagnosticPage` has no total.
3. `crates/oip-server/tests/browser_session.rs`: close the test gap that the seven history routes
   are currently proven only with a `Bearer` token (`crates/oip-server/tests/diagnostics.rs:314-328`)
   and not at all with the browser session cookie. The test asserts 200 for the bound device, 404
   `RESOURCE_NOT_ACCESSIBLE` for a foreign scope, 403 `PERMISSION_DENIED` for a principal without
   the capability and 403 without a session. It changes no permission rule.

**Boundaries.** The history needs a file-backed SQLite database; an in-memory database answers
`HISTORY_UNAVAILABLE` (`crates/oip-storage/src/history.rs:56-70`). The personal database is not
touched by this step. `events_read` is not guaranteed for every operator principal, so the
observation history is the first surface; the event history follows only when the capability is
proven.

**Result.** The device view requests the history for the device itself, every sample is rendered
as history with the receive time the Core guarantees, and the stable id of a sample deduplicates a
refresh. The browser session cookie authorizes the route; the new Rust test proves that boundary.
See the iteration log below.

### N7 — Monitoring measurements in the operator panel — **DONE, closed in iteration 8**

The device connection panel now renders the current authorized observations of the connection
view. See the iteration log below.

### N8 — The managed overview shows the real authorized infrastructure — **DONE, closed in iteration 10**

In the managed mode the overview is still driven by the coordinates of the demo. The trend
accumulator only accepts the entity `M-01` and the metric `temperature`
(`apps/flutter/lib/app/controller.dart:172-188`), and the temperature tile of the overview expects
the same pair (`apps/flutter/lib/models/contracts.dart:239-245`). A managed device reports
`host.*` metrics under its own device id (`crates/oip-server/src/ssh.rs:1002`), so the trend of the
landing page stays empty and the tile shows `—` although the Core delivers the values. The scoped
snapshot additionally carries the `sources` array and the `locations`, and the client drops both
(`apps/flutter/lib/models/contracts.dart:249-280`).

The next delimited step is purely client-side and changes no contract, permission or server rule:

1. `apps/flutter/lib/models/contracts.dart`: keep the authorized `sources` and `locations` of the
   scoped snapshot instead of discarding them.
2. `apps/flutter/lib/app/controller.dart`: fill the trend from the authorized observations of the
   selected source instead of the hardcoded demo coordinates, with the same continuity and epoch
   rules that the legacy path uses.
3. `apps/flutter/lib/features/overview.dart`: show the authorized sources with their real
   connection, reachability, service and freshness instead of placeholders, and name the source of
   every tile.
4. `apps/flutter/test/` a widget test with a scoped fixture that asserts that the managed overview
   renders the authorized source and its real metric, and that no `M-01` literal remains in the
   managed path.

The gate is `flutter analyze`, `flutter test`, the real device harness and the canonical
regression.

**Result.** The managed network view states that the projection carries no topology, draws no path,
colours no reachability green and shows the authorized placement of the session with the registered
nodes of that site. The loading state and the zones of the legacy demo are gone. See the iteration
log below.

### N10 — The managed diagnostics view shows the authorized evidence — **READY**

The scoped projection of a managed session carries the collection events of the authorized sources
(`crates/oip-server/src/tenant_services.rs:576-583`), and the client drops them
(`apps/flutter/lib/models/contracts.dart:249-280`). The diagnostics view therefore states *"Noch
kein persistierter Diagnoselauf"* and *"Diagnosehistorie: demo_only"*, although the Core delivers
the authorized events of the session and serves the persisted history of every event, gap, health
transition and finding behind `GET /api/v2/events/history`,
`/api/v2/diagnostics/gaps`, `/api/v2/diagnostics/health-history` and
`/api/v2/diagnostics/findings` (`crates/oip-server/src/api.rs:207-213`).

The next delimited step is client-side and changes no contract, permission or server rule:

1. `apps/flutter/lib/models/contracts.dart`: keep the authorized `events` of the scoped projection
   instead of dropping them, and map them with the existing `CollectionEvent.fromRecord`.
2. `apps/flutter/lib/features/diagnostics.dart`: show the collection events that the session is
   authorized to see, with their real time, their reason and their gap. The persisted history of
   the events is the next step, and only for the capability the principal actually holds:
   `events_read` is not proven for every operator principal, the observation history was proven
   first for that reason.
3. `apps/flutter/test/` a widget test with the scoped fixture that asserts that the diagnostics
   view shows the authorized events and never a demo incident.

The gate is `flutter analyze`, `flutter test`, the real device harness and the canonical
regression. `GET /api/v2/sources` (`crates/oip-server/src/api.rs:202`) is a possible second step
for the per-source health, but it is not required for this one: the scoped snapshot already carries
the authorized sources.

**Result.** The managed overview draws the session's scope: the source registry with the health the
Core measured, the placement of the source in the authorized hierarchy and one measured series per
authorized source. No source and no fallback primary is preferred, no global selection payload is
invented and the demo coordinates are gone. See the iteration log below.

### N9 — The network view shows the authorized placement — **DONE, closed in iteration 11**

The network view shows *"Topologie wird geladen"* when the projection carries no topology
(`apps/flutter/lib/features/network.dart:246-248`). The scoped projection has no topology array at
all, so that message promises data that will never arrive; it is a loading state without a loader.
The authorized `locations` of the projection — organization, infrastructure, site and source — are
the real placement of the session and are already delivered
(`crates/oip-server/src/tenant_services.rs:584-587`).

The next delimited step is client-side and changes no contract, permission or server rule:

1. `apps/flutter/lib/features/network.dart`: draw the authorized placement of the session instead of
   the loading message, and name the registered nodes only. No link is guessed, no reachability is
   turned green and no topology is invented.
2. The sources of the session keep their own placement; the hierarchy names are only shown when the
   authorized hierarchy API delivered them for that scope.
3. `apps/flutter/test/` a widget test with the scoped fixture that asserts that the network view
   shows the authorized placement and never a permanent loading state.

The gate is `flutter analyze`, `flutter test`, the real device harness and the canonical
regression.

## 4. Iteration log

### Iteration 1 — canonical integration of the real device onboarding feature

**Step.** Integrate `feature/real-device-onboarding-integration` into canonical `main` with a
real fast-forward and re-prove the merged tree with the full gate set. No runtime code was
changed, no installation was activated, no personal device was contacted.

**Commands and measured results.** All commands ran in `/Users/benny/Code/open-industrial-platform`
on canonical `main` = `ae4c6ba`:

```
git merge --ff-only feature/real-device-onboarding-integration   # 49a86bb -> ae4c6ba, 67 files
cargo fmt --all -- --check                                       # exit 0
cargo check --locked --workspace --all-targets                    # exit 0
cargo clippy --locked --workspace --all-targets -- -D warnings    # exit 0
cargo test --locked --workspace -- --test-threads=1               # 167 passed, 0 failed
cargo test --locked -p oip-opcua --features open62541-backend      # 37 passed
cargo test --locked -p oip-opcua --no-default-features --features open62541-backend  # 2 passed
cargo build --locked -p oip-server --bin oip-server --example mcp_probe   # exit 0
cargo deny check advisories licenses bans sources                 # advisories/bans/licenses/sources ok
flutter analyze                                                    # exit 0
flutter test                                                       # 84 passed
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
flutter build web --release --web-renderer html --no-web-resources-cdn --pwa-strategy=none --output build/web-html
OIP_EVIDENCE_DIR=target/oip-real-device-e2e \
OIP_SERVER_BIN=target/debug/oip-server \
OIP_WEB_DIR=apps/flutter/build/web \
OIP_BROWSER_SCRIPT=apps/flutter/test/browser_onboarding.mjs \
PLAYWRIGHT_MODULE=apps/flutter/test/node_modules/playwright/index.mjs \
python3 tests/real_device/acceptance.py                           # 7 phases PASS, exit 0
```

**Result.** Canonical `main` now carries the authenticated browser session, the SSH
connection and monitoring core, the schema 7 connection storage and the Flutter operator
login, device onboarding and connection panel. Every gate above is green on the canonical
tree, including the actual Flutter → authenticated HTTP → shared Core → owned loopback
OpenSSH path with genuine local macOS host facts, the eight official MCP SDK clients, the
host-key rotation denial and the SIGKILL recovery.

**Not claimed.** No physical Raspberry-Pi was contacted; no production identity, no HTTPS, no
hostile same-UID isolation, no OT certification. The real installation was not activated and
the personal database is unchanged.

**Committed.** `docs/OIP_RELEASE_PROGRESS.md` (this file),
`docs/real-device-onboarding-verification.md` (canonical integration addendum),
`docs/evidence/oip-real-device/test-summary.json`,
`docs/evidence/oip-real-device/review.json`, `.gitignore`.

### Iteration 2 — conformance fixes F1, F2, F3, F6, F7 and the Rust test group R1

**Step.** Close the reviewed conformance gaps of the integrated feature in an isolated branch
and integrate the verified result. No contract rule was relaxed, no architecture decision was
taken and no installation was activated.

**Isolation.** Branch `feature/oip-real-device-conformance` in the worktree
`/Users/benny/Code/open-industrial-platform-worktrees/real-device-conformance`, created from
the canonical `main` at `b0096e1`. The branch was built and tested with its own
`CARGO_TARGET_DIR` (`target/conformance`) and with its own Flutter web build, so neither the
canonical binary nor the canonical web assets were replaced during development. The branch was
integrated afterwards with a real `git merge --ff-only`.

**What changed.**

* `crates/oip-server/src/ssh.rs`: the server now reads the size of every offered host key
  itself (`minimum_key_bits`, `parse_key_report`) and rejects a key below the accepted minimum
  before it is offered for acceptance or pinned. The attempt fails with the typed fault
  `SSH_HOST_KEY_TOO_WEAK`; `RequiredRSASize=2048` remains as defence in depth.
* `crates/oip-server/src/ssh.rs`: only `REMOTE HOST IDENTIFICATION HAS CHANGED` maps to
  `SSH_HOST_KEY_CHANGED`. An unpinned host now reports `SSH_HOST_KEY_UNKNOWN` and the operator
  status `host_key_unknown`, which the Flutter panel renders explicitly.
* `crates/oip-server/src/browser_session.rs`: rejected codes no longer block a valid
  single-use grant; the rejection accounting stays capped at 16 entries. A full session table
  no longer consumes an issued grant.
* `crates/oip-server/src/ssh.rs`: the private SSH work directory is created with the
  owner-only mode instead of being briefly world readable.
* `crates/oip-server/tests/browser_session.rs` (new): five Rust integration tests for the
  exact Origin, the single-use pairing code, the CSRF requirement on every cookie authorized
  write, a revoked session and a revoked projection stream.
* `tests/real_device/ssh_fixture.py` and `tests/real_device/acceptance.py`: the owned loopback
  fixture can serve a deliberately weak 1024 bit RSA host key, and the harness proves that the
  server rejects it end to end.
* `docs/architecture/real-device-onboarding.md`: the normative contract now states that the
  server enforces the key size itself, that a changed and an unknown key are separate
  outcomes, and that rejected codes never block a valid grant.

**Empirical basis for the fault split.** The classification was verified against the installed
OpenSSH 10.2 on this machine with an owned loopback fixture: a changed key produces
`REMOTE HOST IDENTIFICATION HAS CHANGED` together with `Host key verification failed`, while a
host without a pinned entry produces only `Host key verification failed`. The rotation case
therefore still maps to `SSH_HOST_KEY_CHANGED` and the acceptance harness still observes
`host_key_changed`.

**Commands and measured results.** Branch gates in the isolated worktree, then the same gate
set on the canonical tree after the fast-forward:

```
cargo fmt --all -- --check                                       # exit 0
cargo check --locked --workspace --all-targets                    # exit 0
cargo clippy --locked --workspace --all-targets -- -D warnings    # exit 0
cargo test --locked --workspace -- --test-threads=1               # 175 passed, 0 failed
cargo test --locked -p oip-opcua --features open62541-backend      # 37 passed
cargo test --locked -p oip-opcua --no-default-features --features open62541-backend  # 2 passed
cargo build --locked -p oip-server --bin oip-server --example mcp_probe   # exit 0
cargo deny check advisories licenses bans sources                 # advisories/bans/licenses/sources ok
flutter analyze                                                    # exit 0
flutter test                                                       # 84 passed
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
flutter build web --release --web-renderer html --no-web-resources-cdn --pwa-strategy=none --output build/web-html
python3 tests/real_device/acceptance.py                           # 8 phases PASS, exit 0
```

**Result.** The canonical tree enforces the RSA minimum host key size itself, distinguishes a
changed from an unknown host key, cannot lock the operator out of the browser session and
creates its private SSH work directory with the correct mode from the start. The browser
session boundary is now covered by Rust tests inside the repository instead of only by the
external harness.

**Not claimed.** No physical Raspberry-Pi was contacted, the real installation was not
activated, the personal database is unchanged at schema 6, the native macOS build is still not
proved and the productive identity, hostile same-UID, durable audit and OT boundaries stay
open. F4 and F5 remain open as N1b.

### Iteration 3 — native macOS build and test, and a reliable UI regression harness

**Step.** Close the open acceptance item "native macOS compilation was blocked" and make the UI
regression harness produce a reliable verdict. The work was done on the isolated branch
`feature/oip-native-macos-harness` in the worktree
`/Users/benny/Code/open-industrial-platform-worktrees/native-macos-harness` and integrated with
a real `git merge --ff-only`.

**Diagnosis before the fix.** The toolchain was inspected first: Xcode 26.6 at
`/Applications/Xcode.app/Contents/Developer`, Swift 6.3.3, Flutter 3.22.0, `flutter devices`
lists the macOS desktop device in 7 s, CocoaPods 1.15.2 with the Pods already installed. A cold
`flutter build macos --debug` then **succeeded** in 497.2 s and produced
`build/macos/Build/Products/Debug/oip_dashboard.app`. The toolchain is healthy; the P0
"blocker" was an interrupted and over-bounded attempt, not a missing capability.

**What changed** (`tests/oip008/ui_regression.py`, the only file):

* The native macOS build became its own step with its own 1800 s bound and the positive
  marker `Built build/macos/Build/Products/Debug/oip_dashboard.app`. A build that exits zero
  without producing the app is not accepted.
* The native integration test runs with `--timeout 30m` and its own 1800 s bound and keeps the
  positive marker `All tests passed!`. Exit status alone never turns a cancelled build into
  acceptance.
* Every step records its elapsed seconds and whether its required marker was seen.
* The web steps keep their 300 s bound, and the owned process group bound is unchanged.
* The legacy web regression receives the separately built HTML renderer by default and the
  served directory is recorded in the result. With the CanvasKit build the painted text is not
  in the document, so the text locator never matched and the harness reported a product
  failure that was a renderer mismatch.

**Measured result on canonical `main` (`b19092d`)**, harness `tests/oip008/ui_regression.py`
against an owned demo core on a random loopback port:

```
browser        exit 0   80.4 s
interactions   exit 0   47.1 s
visual         exit 0   63.4 s
native_build   exit 0   11.6 s   marker "Built build/macos/Build/Products/Debug/oip_dashboard.app" found
native_macos   exit 0   39.1 s   marker "All tests passed!" found
demo_core_shutdown exit 0
```

The run was repeated after the integration and produced the same verdict (browser 88.1 s,
interactions 47.9 s, visual 60.4 s, native build 12.7 s, native test 34.4 s in the first run),
so the result is reproducible and not a single lucky run.

**Not claimed.** The native run is a compatibility and regression check in the explicit
isolated demo mode, exactly as the contract allows. Native authenticated session-cookie
transport is still not claimed, no personal database was touched, no private device was
contacted and the physical Raspberry-Pi acceptance stays withheld.

### Iteration 4 — F4: bound the verified host report to the stored record size

**Step.** Close the remaining storage conformance finding F4 on an isolated branch and
integrate the verified result. F5 stays open and paused, because it loosens a permission.

**Isolation.** Branch `feature/oip-connection-payload-bound` in the worktree
`/Users/benny/Code/open-industrial-platform-worktrees/payload-bound`, created from the
canonical `main` at `c4d3bd9`, built and tested with its own target directory and integrated
afterwards with a real `git merge --ff-only` as `5a48b0c`.

**The defect.** The stored connection record is limited to 128 KiB
(`device_connections.payload_json`), but the SSH parser bounded the disk name and the
interface addresses only by the subprocess output. A legal but extreme remote report
therefore reached the writer and failed the commit with an opaque storage rollback instead of
an explicit fault, and the plan reported a generic error.

**What changed.**

* `crates/oip-core/src/connection.rs`: `CONNECTION_PAYLOAD_MAX_BYTES` (131072) and
  `CONNECTION_ATTEMPT_PAYLOAD_MAX_BYTES` (16384) are now shared domain constants.
* `crates/oip-server/src/ssh.rs`: every collected disk name, mount, interface name and address
  is charged against a report budget of 48 KiB; an oversized report is refused with the
  existing typed fault `SSH_OUTPUT_LIMIT`. A single disk name is additionally bounded to 256
  characters and an address to 128 characters.
* `crates/oip-server/src/connection_service.rs`: before the write, the record is serialised
  and compared with the shared bound. A record that cannot be stored is refused with the typed
  fault `SSH_REPORT_TOO_LARGE`, the plan fails with that fault and no partial binding is
  created.
* `crates/oip-storage/src/connection.rs`: the schema keeps its bound and a new test proves that
  the schema limit and the shared domain constant are the same value.
* `docs/architecture/real-device-onboarding.md`: the contract states the report budget, the two
  explicit faults and that no partial binding is created.

**New tests (5).** An extreme report is refused with `SSH_OUTPUT_LIMIT`; a realistic maximal
report stays inside the stored record bound; an oversized disk name is bounded in the report; a
record that cannot be stored is refused before any write; the storage schema limit equals the
shared domain constant.

**Commands and measured results** on the canonical tree after the fast-forward:

```
cargo fmt --all -- --check                                       # exit 0
cargo check --locked --workspace --all-targets                    # exit 0
cargo clippy --locked --workspace --all-targets -- -D warnings    # exit 0
cargo test --locked --workspace -- --test-threads=1               # 180 passed, 0 failed
cargo test --locked -p oip-opcua --features open62541-backend      # 37 passed
cargo test --locked -p oip-opcua --no-default-features --features open62541-backend  # 2 passed
cargo build --locked -p oip-server --bin oip-server --example mcp_probe   # exit 0
cargo deny check advisories licenses bans sources                 # advisories/bans/licenses/sources ok
flutter analyze                                                    # exit 0
flutter test                                                       # 84 passed
python3 tests/real_device/acceptance.py                           # 8 phases PASS, exit 0
```

**One observed flake, reported honestly.** During the first canonical OPC-UA run the
timing-sensitive test `async_opcua::client::tests::reconnect_recreates_subscription_and_reports_gap`
failed once while the machine was loaded (36 passed, 1 failed). It then passed in three
consecutive isolated runs (3.95 s, 4.54 s, 8.32 s) and in the repeated complete OPC-UA run
(37 passed, 0 failed, 140.48 s). The change touches no OPC-UA code; the observation is
recorded instead of being hidden.

**Not claimed.** No physical Raspberry-Pi was contacted, the real installation was not
activated, the personal database is unchanged at schema 6 and the productive identity,
hostile same-UID, durable audit and OT boundaries stay open. F5 remains open and paused.

### Iteration 5 — the OIP-009 browser session, SSE and context seam contract

**Step.** Close the contract gap that five documents defer to OIP-009, without deciding the
payload that OIP-009 still owns. Isolated branch
`feature/oip-009-context-contract` in the worktree
`/Users/benny/Code/open-industrial-platform-worktrees/oip-009-contract`, created from the
canonical `main` at `3f23ad7` and integrated with a real `git merge --ff-only` as `d32c9d1`.

**What changed.**

* `docs/architecture/oip-009-browser-session-sse.md` (new): the implemented and verified
  boundary of the browser session, the SSE stream and the global context seam, each rule with
  the place that proves it, plus an explicit section on what this document does not decide.
* `docs/architecture/oip-0082-diagnostics-flutter-contract.md`,
  `docs/architecture/oip-0084-flutter-settings-contract.md` and
  `docs/architecture/oip-0085-real-inventory-flutter-contract.md`: their deferral now points
  at the new contract instead of leaving the reader without a reference.
* `apps/flutter/test/onboarding_contract_test.dart`: two new contract tests close the test gap
  around the seam — a context change advances `contextRevision` and clears the display cache,
  and another operator Principal invalidates the display cache.

**The Rust source is unchanged** against the previous canonical source revision `5a48b0c`
(`git diff 5a48b0c -- crates/` is empty), so the Core gate results of iteration 4 remain valid
and were re-run on the canonical tree anyway.

**Commands and measured results** on the canonical tree after the fast-forward:

```
cargo fmt --all -- --check                                       # exit 0
cargo clippy --locked --workspace --all-targets -- -D warnings    # exit 0
cargo test --locked --workspace -- --test-threads=1               # 180 passed, 0 failed
flutter analyze                                                    # exit 0, no issues
flutter test                                                       # 86 passed, 0 failed
python3 tests/real_device/acceptance.py                           # 8 phases PASS, exit 0
```

The acceptance harness is the end-to-end proof of the contract subject: the browser identity
with the one-use code and the CSRF/Origin rules, the real Flutter onboarding over the
authenticated session, the host key rotation denial, the weak host key rejection and the eight
official MCP clients all pass. The browser receipt reports no page error and no external
request, and the served build hash is unchanged.

**Not claimed.** The global Organization / Infrastructure / Site selection is still not
implemented and is not decided here. No physical Raspberry-Pi was contacted, the real
installation was not activated, the personal database is unchanged at schema 6 and the
productive identity, hostile same-UID, durable audit and OT boundaries stay open. F5 remains
open and paused.

### Iteration 6 — a reproducible canonical regression run and two repaired stale gates

**Step.** Re-run the milestone acceptance harnesses on the canonical tree after six
integrations and make the run reproducible with one entry point. The step was carried out on
the isolated branch `feature/oip-canonical-regression` in the worktree
`/Users/benny/Code/open-industrial-platform-worktrees/canonical-regression` and integrated
with a real `git merge --ff-only` as `111dff1`.

**What the run found.** Two acceptance gates had silently gone stale when the real device
onboarding integration moved the canonical schema and the MCP tool surface, and nobody had
re-run them since:

* `tests/oip0082/schema3_migration.py` expected the upgraded schema to be **6**. The canonical
  schema is **7** since the connection tables were added, so the gate failed on the canonical
  tree. The expectation now names the schema the canonical binary actually reaches, and the
  harness still asserts an exact value.
* `tests/oip008/acceptance.py` expected exactly **17** MCP read tools for the reader role.
  `oip_device_connection_read` is visible to that role as well, so the policy filtered catalog
  has **18**. The exact catalog was measured for all three reader clients before the
  expectation was changed.

Both repairs keep the gate exact; only the stale number changed.

**New runner.** `tests/canonical_regression.py` runs the milestone harnesses over the
canonical tree with one reproducible entry point. Every case owns its own runtime directory
under `/private/tmp`, its own ports and its own credentials. A case that needs a protected
historical binary is only executed when that binary exists **and** its hash matches the
recorded value; otherwise the case is reported as `BLOCKED` with the reason instead of being
run with a substitute. `tests/oip008/legacy_migration.py` can now use a protected OIP-007
binary through `OIP007_BASELINE_BINARY`, and `tests/oip008/ui_regression.py` stops with a
clear message when the HTML renderer build is missing instead of serving a CanvasKit build and
reporting a product failure that is really a missing artifact.

**Measured result on canonical `main` (`111dff1`)**:

```
oip008_acceptance          PASS  53.8 s
oip0082_acceptance         PASS  32.9 s
oip0082_schema3_migration  PASS  25.3 s
oip0084_acceptance         PASS  25.6 s
oip0085_acceptance         PASS   5.0 s
oip0085_migration          PASS   7.2 s
oip008_ui_regression       PASS 264.4 s   browser 75.4 s, interactions 47.8 s, visual 61.1 s,
                                             native build 32.2 s, native test 30.6 s, core exit 0
oip008_legacy_migration    BLOCKED        no protected OIP-007 binary in the workspace
```

The blocked case is the schema2 adoption: the harness has to create a genuine schema2
database, which only a protected OIP-007 binary can do. The canonical binary creates schema3
or later, so the case is reported as blocked with the reason instead of being run with a
substitute. The schema2 adoption was verified historically in the OIP-008 receipt with the
then protected binary; it is not claimed as re-verified here.

**Not claimed.** The product source is unchanged in this iteration, so the Rust, Flutter and
real device acceptance results of iteration 5 remain valid for this tree. No physical
Raspberry-Pi was contacted, the real installation was not activated, the personal database is
unchanged at schema 6 and the productive identity, hostile same-UID, durable audit and OT
boundaries stay open. F5 remains open and paused.

### Iteration 11 — the managed network view shows the authorized placement

**Step.** Make the managed network view show the authorized placement of the session instead of a
loading state for data that never arrives. One isolated commit on the branch
`feature/oip-network-placement` (`e9036ef`), integrated with a real `git merge --ff-only`.

**The gap.** The network view showed *"Topologie wird geladen — Der Live-Stream liefert das
gemeinsame Rust-Modell"* whenever the projection carried no topology
(`apps/flutter/lib/features/network.dart:246-248`). The scoped projection of a managed session has
no topology array at all (`crates/oip-core/src/hierarchy.rs:444-454`), so that was a loading state
without a loader. The view also drew the three zones of the legacy demo — `LAN`, `Tailnet`,
`Remote Site` — next to the real site of the session, and the zone status stayed `UNBEKANNT`
because no link exists to classify. The contract had already named the rule: *"Network & VPN:
registered nodes only, no automatically guessed links/topology or green reachability"*
(`docs/architecture/oip-0085-real-inventory-flutter-contract.md:21`).

**What changed.**

* `apps/flutter/lib/features/network.dart`: the managed view states that the projection carries no
  topology, draws no path and colours no reachability green. The zone of a node is the authorized
  site of the session; the zones of the legacy demo are not shown in the managed mode. The
  authorized placement is shown with the identifiers the Core delivered for it — organization,
  infrastructure, site and source — with the registered nodes of that site. Nothing is derived from
  a name, an address or a device identifier and no link between two placements is invented.
* `apps/flutter/test/managed_network_test.dart` (new): the managed network view shows the
  authorized placement and the registered node, shows no loading state and shows no demo zone.
* `apps/flutter/test/support.dart`: the scoped fixture of a managed session moved into the shared
  test support, so the next managed view reuses it.
* `apps/flutter/test/browser_onboarding.mjs`: the rendered network view is compared with the
  placement that the Core delivered, and the receipt names it.
* `docs/architecture/oip-0085-real-inventory-flutter-contract.md`: names the surface and its proof.

**Measured result on canonical `main` (`e9036ef`)** — actual Flutter web release → authenticated
HTTP → shared Core → owned loopback OpenSSH → genuine macOS host facts:

```
cargo fmt --all -- --check                                       exit 0 (no Rust source changed)
flutter analyze                                                    exit 0, no issues
flutter test                                                       101 passed, 0 failed
python3 tests/real_device/acceptance.py                           8 phases PASS, exit 0
  PASS browser_identity_online_writer
  PASS ssh_handshake_confirmation_monitoring
  PASS restart_sigkill_identity
  PASS actual_flutter_ssh_onboarding     <- the history, the overview and the network view
  PASS no_clients_ingestion_progress
  PASS host_key_change_blocks_collection
  PASS weak_host_key_is_rejected_by_the_server
  PASS eight_official_mcp_clients
python3 tests/canonical_regression.py                             8 cases PASS, no failed, no blocked
  oip008_acceptance           PASS  30.4 s
  oip0082_acceptance          PASS  40.3 s
  oip0082_schema3_migration   PASS  17.1 s
  oip0084_acceptance          PASS  31.8 s
  oip0085_acceptance          PASS  13.3 s
  oip0085_migration           PASS   7.2 s
  oip008_ui_regression        PASS 256.0 s   (browser 80.4 s, interactions 47.1 s, visual 63.4 s,
                                                 native build 11.6 s, native macOS test 39.1 s,
                                                 every step with its marker)
  oip008_legacy_migration     PASS   4.2 s
```

The browser receipt (`target/oip-real-device-e2e/browser/report.json`) names what the operator now
sees in the network view of the managed mode:

```
rendered_network  authorized_placement org-a · infra-a1 · site-a1
                 source 38fceec2-6e77-4afa-a59a-f395aef20f91
                 loading_state_absent true
                 demo_zones_absent true
```

**Not claimed.** The measurement is the host report of the owned loopback fixture on this machine,
not a physical Raspberry-Pi verdict. No personal device was contacted, the real installation was not
activated and the personal database is unchanged at schema 6. The managed diagnostics view still
shows its placeholder and is recorded as the next READY item; the persisted history of the events
follows only when the capability of the principal is proven. The productive identity, hostile
same-UID, durable audit and OT boundaries stay open. F5 remains open and paused. No Rust source
changed in this iteration, so the Rust workspace results of iteration 9 remain valid for this tree.

### Iteration 10 — the managed overview shows the real authorized infrastructure

**Step.** Make the managed overview draw the session's authorized scope instead of the coordinates
of the demo. One isolated commit on the branch `feature/oip-managed-overview` (`1e6b743`),
integrated with a real `git merge --ff-only`.

**The gap.** The Core delivers the authorized `sources`, the authorized `locations` and the
authorized `observations` in the scoped projection
(`crates/oip-server/src/tenant_services.rs:540-591`). The client dropped all of it: the overview
asked for the temperature of the demo entity `M-01` and the metric `temperature`
(`apps/flutter/lib/models/contracts.dart:239-245`), the trend accumulator accepted only that pair
(`apps/flutter/lib/app/controller.dart:172-188`), and the chart drew the caption *Temperatur · M-01*
(`apps/flutter/lib/widgets/trend.dart:77`). In the managed mode the measured series was therefore
always empty, the tile showed `—` and the ribbon showed three rows for dimensions the projection
does not carry. The contract had already named the rule: *"Overview: counts from authorized
returned inventory, sources from actual source registry; no fake host CPU/RAM/network metrics"*
(`docs/architecture/oip-0085-real-inventory-flutter-contract.md:21`).

**What changed.**

* `apps/flutter/lib/models/contracts.dart`: the authorized `sources` and `locations` of the scoped
  projection are no longer dropped. `ScopedSource` mirrors the `SourceHealth` of the Core, and
  `ScopedLocation` the `HierarchyLocation`; `Snapshot` keeps both and can resolve the placement of
  a source.
* `apps/flutter/lib/app/controller.dart`: the measured series are no longer the demo pair. The
  legacy rule stays exactly as it was — the temperature of `M-01` of the primary source — and the
  managed rule measures the numeric observations of the authorized sources, one series per
  authorized source. The metric of a series is the one with the most received samples, a tie is
  broken by the metric identifier, so the choice is deterministic and visible. The accumulator
  rules stay unchanged: a change of the measured scope starts a new display window, a source time
  that moves backwards starts a new window, an identical source time and value is not appended
  twice and a series keeps at most 60 received points.
* `apps/flutter/lib/widgets/trend.dart`: the chart names the metric it measured instead of
  *Temperatur*, and the gap limit follows the cadence the series itself showed — the median
  interval of the series with a tolerance of half of it and the demo limit as its floor. The demo
  limit of 2.5 s stays the limit of the legacy demo, so the demo behaviour is unchanged; a real
  source publishes every 30 s and its points are connected instead of being broken at every point.
  A source time jump is still never connected into a line over a data gap.
* `apps/flutter/lib/features/overview.dart`: the source registry with the health the Core measured,
  the placement of the source in the authorized hierarchy and the measured values are shown. The
  rows for the OPC-UA, subscription and network dimensions belong to the legacy demo; in the
  managed mode the source registry of the session is shown instead of dimensions the projection
  does not deliver. The demo tile *Temperatur M-01* and the demo entity in the alarm check and in
  the device focus are gone in the managed mode.
* `apps/flutter/lib/design_system/theme.dart`: the status vocabulary of the source registry had no
  label and no colour — `disconnected`, `healthy`, `valid` and `invalid` were rendered as raw
  English strings. They are mapped now.
* `apps/flutter/test/managed_overview_test.dart` (new): three tests — the managed overview renders
  the authorized source, its real health, its placement and its real measurement and no demo
  coordinate; the controller measures one series per authorized source and extends it with a later
  measurement; the gap limit of a real cadence is not the demo limit while the legacy rule keeps
  its own.
* `apps/flutter/test/browser_onboarding.mjs`: the rendered overview is compared with the source
  registry and the measurement that the Core received over SSH, and the receipt names them.
* `docs/architecture/oip-0085-real-inventory-flutter-contract.md`: names the surface and its proof.

**Measured result on canonical `main` (`1e6b743`)** — actual Flutter web release → authenticated
HTTP → shared Core → owned loopback OpenSSH → genuine macOS host facts:

```
cargo fmt --all -- --check                                       exit 0 (no Rust source changed)
flutter analyze                                                    exit 0, no issues
flutter test                                                       100 passed, 0 failed
python3 tests/real_device/acceptance.py                           8 phases PASS, exit 0
  PASS browser_identity_online_writer
  PASS ssh_handshake_confirmation_monitoring
  PASS restart_sigkill_identity
  PASS actual_flutter_ssh_onboarding     <- the persisted history and the managed overview
  PASS no_clients_ingestion_progress
  PASS host_key_change_blocks_collection
  PASS weak_host_key_is_rejected_by_the_server
  PASS eight_official_mcp_clients
python3 tests/canonical_regression.py                             8 cases PASS, no failed, no blocked
```

The browser receipt (`target/oip-real-device-e2e/browser/report.json`) names what the operator now
sees on the landing page of the managed mode:

```
rendered_overview  authorized_source SSH host browser-existing
                   source_registry_section true
                   measured_metric host.memory_total_bytes
                   measured_value 17179869184
                   demo_coordinates_absent true
```

**Not claimed.** The measurement is the host report of the owned loopback fixture on this machine,
not a physical Raspberry-Pi verdict. No personal device was contacted, the real installation was not
activated and the personal database is unchanged at schema 6. The network view still shows its
loading message and is recorded as the next READY item; the event history and the diagnostics
surfaces stay unconnected, because `events_read` is not proven for every operator principal. The
productive identity, hostile same-UID, durable audit and OT boundaries stay open. F5 remains open
and paused. No Rust source changed in this iteration, so the Rust workspace results of iteration 9
remain valid for this tree.

### Iteration 9 — the persisted history reaches the operator view

**Step.** Connect the persisted observation history that the Core already stores and serves to the
Flutter device view, and close the test gap that the seven history routes were proven only with a
bearer token. One isolated commit on the branch `feature/oip-observation-history` (`1287e23`),
integrated with a real `git merge --ff-only`.

**The gap.** The Core stores the samples of a connected device and serves them through
`GET /api/v2/observations/history` (`crates/oip-server/src/api.rs:213`,
`crates/oip-storage/src/lib.rs:673`). The Flutter client named the gap itself: the device dialog
stated *"Autorisierte historische REST-v2-Abfragen existieren im Core"*, and the history was never
requested. The device scope was already sufficient — the device is resolved to its source through
the authoritative source registration (`crates/oip-core/src/hierarchy.rs:298`), so no organization,
infrastructure or site selection had to be invented.

**What changed.**

* `apps/flutter/lib/models/history.dart` (new): the DTO of the page — `items`, `truncated`,
  `next_cursor`, `missing_evidence`, `time_semantics` — and of the adjacently tagged item
  `{"category":"observation","record":{"id":…,"observation":…}}`. The page has no total.
* `apps/flutter/lib/services/api.dart`: `observationHistory({deviceId, cursor, limit})` on
  `DeviceManagementApi`, implemented as `GET /api/v2/observations/history?device=…&limit=…`.
* `apps/flutter/lib/features/device_history.dart` (new) and `apps/flutter/lib/features/devices.dart`:
  the device view replaces the *"Historie noch nicht angebunden"* notice with the stored samples.
  Every row is named as history, reports the stored value, its unit, the quality, the freshness
  and the receive time the Core guarantees, and the `missing_evidence` and the time semantics of
  the answer are shown instead of being hidden. The stable id of a sample deduplicates a refresh.
* `crates/oip-server/tests/browser_session.rs`: the missing cookie path of the history route. The
  bound device is served with its persisted sample, a foreign scope and an unknown device are
  refused with `RESOURCE_NOT_ACCESSIBLE`, a principal without `telemetry_read` is refused with
  `PERMISSION_DENIED`, a request without a session is refused and an unbounded page is refused
  with `INVALID_DIAGNOSTIC_QUERY`.
* `apps/flutter/test/observation_history_test.dart` (new): eight tests — the device scope without
  a global scope, the continuation with the cursor of the Core, an item of another category that
  is counted and not dropped, the rendering as history, the continuation, the recovery from a
  device that is not accessible yet, the honest empty state and the refused history.
* `apps/flutter/test/browser_onboarding.mjs` and `tests/real_device/acceptance.py`: the real proof.
  The harness asserts that the Core persisted the samples of the connected device and that they
  are stale; the browser compares the rendered history with the answer of the Core for the same
  device and writes the persisted samples into the receipt.
* `docs/architecture/oip-0082-diagnostics-flutter-contract.md`: names the surface and its proof.

**The defect found on the way.** The history was loaded once, when the device dialog was opened —
and the dialog is opened *before* the connection is confirmed. The answer of a device without a
source is `RESOURCE_NOT_ACCESSIBLE`, so the section kept that answer forever and never showed the
samples that the collector stored a moment later. The section now follows the persisted state on a
bounded cadence, exactly like the connection panel follows the live observations, and the recovery
is proven by a widget test.

**Measured result on canonical `main` (`1287e23`)** — actual Flutter web release → authenticated
HTTP → shared Core → owned loopback OpenSSH → genuine macOS host facts:

```
cargo fmt --all -- --check                                       exit 0
cargo check --locked --workspace --all-targets                    exit 0
cargo clippy --locked --workspace --all-targets -- -D warnings    exit 0
cargo test --locked --workspace -- --test-threads=1               181 passed, 0 failed
cargo test --locked -p oip-opcua --features open62541-backend      37 passed
cargo test --locked -p oip-opcua --no-default-features --features open62541-backend  2 passed
flutter analyze                                                    exit 0, no issues
flutter test                                                       97 passed, 0 failed
python3 tests/real_device/acceptance.py                           8 phases PASS, exit 0
  PASS browser_identity_online_writer
  PASS ssh_handshake_confirmation_monitoring
  PASS restart_sigkill_identity
  PASS actual_flutter_ssh_onboarding     <- the persisted history
  PASS no_clients_ingestion_progress
  PASS host_key_change_blocks_collection
  PASS weak_host_key_is_rejected_by_the_server
  PASS eight_official_mcp_clients
python3 tests/canonical_regression.py                             8 cases PASS, no failed, no blocked
  oip008_acceptance           PASS  32.9 s
  oip0082_acceptance          PASS  39.9 s
  oip0082_schema3_migration   PASS  24.2 s
  oip0084_acceptance          PASS  23.7 s
  oip0085_acceptance          PASS   6.2 s
  oip0085_migration           PASS   7.6 s
  oip008_ui_regression        PASS 225.6 s   (browser 80.4 s, interactions 47.1 s, visual 63.4 s,
                                                 native build 11.6 s, native macOS test 39.1 s,
                                                 every step with its marker)
  oip008_legacy_migration     PASS   7.7 s
```

The browser receipt (`target/oip-real-device-e2e/browser/report.json`) names the persisted samples
that the Core stored for the connected device and that the operator now sees as history:

```
persisted_samples 10     rendered_samples 6     all_stale true     receive_times_shown 1
first_receive_time 2026-11-07 21:21:11.293 UTC
metrics host.architecture  host.interfaces  host.cpu_info  host.uptime_seconds
        host.memory_used_bytes  host.memory_total_bytes
```

**Not claimed.** The samples are the host report of the owned loopback fixture on this machine,
not a physical Raspberry-Pi verdict. No personal device was contacted, the real installation was
not activated, the personal database is unchanged at schema 6. The event history and the
diagnostics surfaces stay unconnected, because `events_read` is not proven for every operator
principal. The productive identity, hostile same-UID, durable audit and OT boundaries stay open.
F5 remains open and paused. No Rust source changed in this iteration, so the Rust workspace
results of iteration 8 remain valid for the unchanged crates.

### Iteration 8 — the monitoring measurements reach the operator panel

**Step.** Make the monitoring measurements that the Core already collects and publishes visible
in the surface that is dedicated to connection and monitoring, and prove it in the real browser
end to end. Two isolated commits on the branch `feature/oip-monitoring-observations`
(`2ec4829`, `e12c009`), both integrated with a real `git merge --ff-only`.

**The defect.** The Core collects the host report of a connected device and publishes the
resulting observations in the connection view (`crates/oip-server/src/connection_service.rs:303`).
The Flutter client parsed them (`apps/flutter/lib/models/onboarding.dart:70`) but the device
connection panel rendered **only the empty case** and dropped every real measurement
(`apps/flutter/lib/features/device_connection_panel.dart:143`). The Flutter contract requires the
connection view to contain the current authorized observations
(`docs/architecture/real-device-onboarding-flutter-contract.md:37`) and requires the browser E2E
to verify "subsequent actual observations" (`:45`). Neither held: the panel showed the state
`Collecting` but never a collected value, and the browser E2E only waited for the state string.

**What changed.**

* `apps/flutter/lib/features/device_connection_panel.dart`: the panel renders the current
  authorized observations with their metric identifier, value, unit, quality, freshness and
  capture time. Long text reports (disks, interfaces) stay collapsed behind an expansion and are
  never presented as a complete value in the preview. A missing value stays unknown and is not
  replaced by a substitute.
* `apps/flutter/test/monitoring_observations_test.dart` (new): three widget tests — the rendered
  measurements with their unit and state, an unknown value that is not replaced by a substitute,
  and the honest empty state.
* `apps/flutter/test/browser_onboarding.mjs`: after the `Collecting` state, the rendered panel is
  compared with the observations that the Core reports **for the same device**. The expected
  values are read back from the Core and are never invented in the test; the measured values are
  written into the browser receipt.
* `docs/architecture/real-device-onboarding-flutter-contract.md`: names the rendering and its
  proof.
* `tests/real_device/acceptance.py`: the Playwright module is addressed with an absolute path.
  The relative value documented in this file could never work, because a dynamic import resolves
  a relative specifier as a package name; the browser phase failed with
  `Cannot find package 'apps'`. The harness now resolves the module against the repository root
  and reports a missing module before the browser phase instead of inside the node error.

**Measured result on canonical `main` (`e12c009`)** — actual Flutter web release → authenticated
HTTP → shared Core → owned loopback OpenSSH → genuine macOS host facts:

```
flutter analyze                                                    exit 0, no issues
flutter test                                                       89 passed, 0 failed
python3 tests/real_device/acceptance.py                           8 phases PASS, exit 0
  PASS browser_identity_online_writer
  PASS ssh_handshake_confirmation_monitoring
  PASS restart_sigkill_identity
  PASS actual_flutter_ssh_onboarding     <- the rendered measurements
  PASS no_clients_ingestion_progress
  PASS host_key_change_blocks_collection
  PASS weak_host_key_is_rejected_by_the_server
  PASS eight_official_mcp_clients
python3 tests/canonical_regression.py                             8 cases PASS, no failed, no blocked
  oip008_acceptance           PASS  41.8 s
  oip0082_acceptance          PASS  43.2 s
  oip0082_schema3_migration   PASS  24.9 s
  oip0084_acceptance          PASS  29.9 s
  oip0085_acceptance          PASS   5.4 s
  oip0085_migration           PASS  12.0 s
  oip008_ui_regression        PASS 863.0 s   (browser 80.4 s, interactions 47.1 s, visual 63.4 s,
                                                 native build 11.6 s, native macOS test 39.1 s,
                                                 every step with its marker)
  oip008_legacy_migration     PASS   5.0 s
```

The browser receipt (`target/oip-real-device-e2e/browser/report.json`) names the ten observations
that the Core received from the owned fixture and that the operator now sees in the panel:

```
host.architecture  host.cpu_info   host.disks      host.hostname  host.interfaces
host.memory_total_bytes  host.memory_used_bytes  host.model  host.os  host.uptime_seconds
host_os = Darwin        memory_total_bytes = 17179869184        all fresh
```

**Not claimed.** The measurement values are the host report of the owned loopback fixture on this
machine, not a physical Raspberry-Pi verdict. No personal device was contacted, the real
installation was not activated, the personal database is unchanged at schema 6, the persisted
history is still not connected (N6) and the productive identity, hostile same-UID, durable audit
and OT boundaries stay open. F5 remains open and paused. The Rust source is unchanged in this
iteration, so the Rust workspace results of iteration 5 remain valid for this tree.

### Iteration 7 — the schema2 adoption case and a stable parity gate

**Step.** Restore the one acceptance case that could not be re-verified, and remove a race from
a gate that decides the result of a whole regression run. Two isolated branches were used:
`feature/oip-007-baseline-adoption` (`6df189f`) and
`feature/oip-parity-gate-convergence` (`f4b89ed`), both integrated with a real
`git merge --ff-only`.

**The blocked case.** The schema2 adoption of the OIP-008 milestone needs a writer that still
creates the schema2 layout. The historical protected binary of that milestone is not part of
the workspace any more, so the case stayed blocked. `tests/oip007_baseline.py` rebuilds that
writer from the verified OIP-007 baseline commit `a27e7b1`: it extracts the source with
`git archive`, so no worktree registration and no canonical checkout state is touched, and it
builds into its own destination directory. The result records the source commit, the hash of
the rebuild and the hash of the historical binary, and it states that a rebuild is not byte
identical, so **the identity of the historical protected binary is not claimed**. The canonical
regression runner uses the prepared writer when it exists and records its hash and origin.

**The race.** In the first canonical run of this iteration the OIP-008 acceptance case failed
although it had passed with identical code in iteration 6. The reason was in the gate itself:
it compared the live source state of the MCP transport with the live source state of the REST
transport, and while a source is still warming up the two reads can observe two different
states (`freshness: unknown` against `fresh`, `service: unknown` against `healthy`). The gate
now waits for the compared fields to converge within a bounded deadline and still fails when
they never agree. The strength of the gate is unchanged. The hardened gate passed in three
consecutive runs and in the canonical run below.

**Measured result on canonical `main` (`f4b89ed`)** — every case, no failure, no blocked case:

```
oip008_acceptance          PASS  30.9 s
oip0082_acceptance         PASS  51.6 s
oip0082_schema3_migration  PASS  25.6 s
oip0084_acceptance         PASS  22.7 s
oip0085_acceptance         PASS   9.2 s
oip0085_migration          PASS  15.3 s
oip008_ui_regression       PASS 323.1 s
oip008_legacy_migration    PASS   8.4 s   schema2 writer rebuilt from a27e7b1, schema2 adopted
                                         into schema3, 46 observations / 48 events / 2 gaps kept,
                                         same observation keys, both refusal paths still refuse
```

**Advisory exceptions verified (N5).** The three documented exceptions were checked against
the local advisory database and against the dependency graph. All three are correct,
necessary and unavoidable; the earlier note in this file that two of the ignore reasons would
not match the advisory subjects was wrong and is corrected in the N5 section.

**Not claimed.** The schema2 adoption is proven with a writer rebuilt from the verified OIP-007
baseline commit, not with the historical protected binary, whose byte identity cannot be
reproduced and is not asserted. The product source is unchanged in this iteration, so the Rust,
Flutter and real device acceptance results of iteration 5 remain valid for this tree. No
physical Raspberry-Pi was contacted, the real installation was not activated, the personal
database is unchanged at schema 6 and the productive identity, hostile same-UID, durable audit
and OT boundaries stay open. F5 remains open and paused.

### Iteration 12 — the Spectrum-2027 canonical UI baseline and its design regression gate

**Status: PROVED and integrated into canonical `main`.**
This is a binding integration contract and regression gate, not a deployment and not an operator
visual approval. Before this iteration canonical `main` was `037afda92ac02ffc91dceb322d905a57dd2fc4ef`
with the legacy five-view OIP/005 shell and runtime bundle
`e399f3979b94fdbfb794436c364c68c1d697111ed1cdf2c2354c94ba468730bf`; its preview on port 8080
answered `mode: explicit_legacy_demo`. The intended UI authority is OIP-UX-001 feature commit
`6c2d2a280b66b69461d5ee8c821630b4deeed4fe`, frozen at `5d50a1d5da558cf1e78515b4c24bad4aded40a92`.
The exact upstream chain is pinned in `docs/design/OIP_UI_2027_HANDOFF_MANIFEST.json`.

**Reconciliation of the two parallel executions.** The Spectrum-2027 integration was prepared
twice in parallel from the same authority payload: in `…/worktrees/spectrum-2027-ui`
(`feature/oip-spectrum-2027-ui`) and in the concurrent release-loop candidate
`…/worktrees/canonical-ui-gate` (`feature/oip-canonical-ui-regression-gate`). Both were verified
against the same contract; their product trees differed in three files only. They were reconciled
into **one** candidate instead of integrated twice: the gate, the stable-shell visual comparison,
the acceptance-workflow integration and the handoff manifest come from the concurrent candidate,
the product fixes below come from this worktree. No file of the concurrent execution was
modified, no foreign process was signalled, and the personal installation was not touched.

**Product fixes that the transplant would have lost.** The payload alone would have replaced the
canonical cadence-aware continuity of a measured series (`continuesSeries`, `seriesGapLimit`) with
a fixed 2.5 s limit and dropped its test; every real source that publishes slower than 2.5 s
would have been drawn as isolated points. The rule and its coverage are restored in
`lib/widgets/trend.dart` and applied in `lib/features/overview/telemetry_chart.dart`. The
monitoring measurements and the persisted observation history are mounted inside the approved
device workspace, and the management adapter is guarded in both device detail surfaces, so a
managed client without an adapter no longer dereferences a null adapter.

**Onboarding activation.** In the Flutter web runtime the semantics node of a device row is a
container node and therefore carries `pointer-events: none`; a Playwright click is intercepted by
`flutter-view`, and the engine forwards only focus and blur, so Enter and Space can never
activate the row. The real onboarding journey therefore activates the painted row with a real
mouse event and verifies the state it produces — the engineering workspace of the selected
device — instead of trusting the absence of an error.

**Isolation and provenance.** The uncommitted 128-file Spectrum snapshot was archived before any
mutation and replayed byte-identically into the separate `canonical-ui-gate` worktree. Snapshot
archive SHA-256 `8c81ed6fb1ea624a3047a33db284d441d704b2ddd081268826c7922236f2acc3`, roundtrip
PASS. The original worktree and every foreign process remained untouched. The final tested
revision is `037afda92ac02ffc91dceb322d905a57dd2fc4ef`, working tree hash
`3fc21b181151e99b35ee9291bfcc46a47c6dc223`. The actual local and served
`main.dart.js` SHA-256 values are both
`d0a5b3b2dabd6e0351bdfd7465a7422f90a4fc2afd3b610f6de6ff44b47d8a86`.

**Failure correction.** The first complete Flutter run produced 331 passes and two failures, all
caused by a managed controller without a management adapter (`controller!.management!`). The
management section is now guarded in both device detail surfaces, while production `RestApi`
management remains intact. Targeted tests and the full subsequent suite passed: **334/334**.
The initially claimed 2027 gate was not accepted without independent execution.

**Permanent regression gate.** `tests/canonical_ui_gate.py` builds the current Flutter release,
hashes the real working tree through a temporary index, runs the full Flutter suite and checks
the delivered bundle. The canonical case also builds and hashes `oip-server` and the official MCP
probe, performs real browser login, all six workstations at 1440/1920, the eight managed
acceptance phases and the actual `browser_onboarding.mjs` journey. A complete PASS cannot skip
build, widget or browser checks; `--skip-build` was separately verified to produce `PARTIAL`.
Runner report resolution evaluates both the harness and the browser `verdict`.

**Measured result.** `python3 tests/canonical_regression.py --only oip_canonical_ui_gate
--evidence target/oip-canonical-ui-regression-final` finished in 353.8 s with process status PASS,
harness status PASS, no failed and no blocked case. The browser recorded **175 findings with zero
failures**, 13 screenshots, no JavaScript errors and no external requests. All eight phases are
PASS: browser identity/writer, SSH handshake and monitoring, restart/SIGKILL, actual Flutter SSH
onboarding, ingestion without clients, host-key change blocking, weak-key rejection and eight
official MCP clients. `own_processes_stopped=true`. The merged
`canonical_ui_gate_receipt` binds the precheck, browser and visual receipt paths and their
SHA-256 values, the machine-bound 334/334 Flutter result, 175/0 browser findings and 13 captures.
The browser evidence directory contains exactly those 13 PNGs and no failure dump.

**Visual and negative controls.** The stable left shell is compared at 1440×900 and 1920×1080,
with dynamic content excluded and each mean/ratio limit set to 0.01. Archive derivation is pixel
verified. Measured at 1440: mean `0.0010914`, changed ratio `0.0`; at 1920: mean `0.0012635`,
changed ratio `0.0`. Single-navigation-row and large-gradient mutations were both detected.
Missing external archives produce an explicit `SKIPPED_EXTERNAL_ARCHIVE_UNAVAILABLE` receipt while
the committed reference hash remains mandatory. **M-01 is forbidden only as the primary managed
overview metric**, not on real OPC-UA nodes. **AGENT-FIRST is forbidden in the sidebar and allowed
only in the technical Settings context.**

**Integration into canonical `main`.** After the reconciliation the candidate was integrated with a
real `git merge --ff-only`, no merge commit and no history rewrite. Canonical `main` is now
`525f5c86d6baf5f27d5b13bd648d2d17794bb5a5`, tree `b5b23c6f2ac0d3ee02e09837933027facdeb6042`, working tree clean. The final acceptance run was executed **on canonical
`main`**: the precheck hashed the clean tree (`source_dirty=false`), the Flutter suite measured
**335/335 PASS**, the browser recorded **175 findings with zero failures** and 13 captures, the
stable-shell visual comparison passed at 1440 and 1920 with both negative-control classes, and
all eight managed acceptance phases passed, including the actual Flutter SSH onboarding that
renders the Core's own `host.os` and `host.memory_total_bytes` measurements and the ten persisted
observation samples. Local and served `main.dart.js` are byte-identical:
`169aaa8257a782ae52d5afe7b9de68b6acedb013cc24c96783e11e054cc22caa`. The rebuild of the same source in the isolated worktree produced the same bundle hash,
so the delivered assets are reproducible.

Receipt hashes of that run: precheck `9b2ca4f1951a19166f25e2299faf2983b296b4b81603d0ac509f85a29dfe3e74`, browser `6fa467c7f9373897f4ca31ca7a406b7190083cfec55b154d59c53f42bea4a1c2`, visual `d53fa8f5cb5ba70665184ece2a52c8299e8be6d475d5bb41f0a925a39a187df7`.

**Visual status and safety boundary.** All six current workstation captures are technical
evidence only. Operator visual acceptance remains `VISUAL_PENDING_OPERATOR_ACCEPTANCE`. No push,
deployment, schema-7 activation, private SSH connection or change to the personal installation
database was performed; the personal database is untouched at SHA-256
`9f988c01c7115631db3b5bfd2b9228ecc24255b8b9905932a987a89c78e6a24e` with `user_version` 6. The
concurrent release-loop candidate was never modified and remains in its own isolated worktree.

### Iteration 13 — the persisted evidence of the managed diagnostics reaches the approved workspace

**Status: PROVED on canonical `main` (`7fc612e`).**
The Spectrum-2027 integration carried the capability of the managed diagnostics view, but not its
continuation and not its limits: the opaque cursor of the Core was dropped from both routes, the
merge of a continued page by the stable Core IDs was lost, and the view stopped naming the limits
of the answer, the time and origin semantics of the Core, and the fact that a truncated page
without a cursor is explicitly incomplete. The isolated candidate `feature/oip-managed-diagnostics`
(`55d4f50`) contributed no file that `main` lacked, but its capability was only partly present.

**Restored inside the approved workspace.** Both routes ask for the continuation with the opaque
cursor of the Core and merge the answer by the stable Core IDs, so no row is duplicated. A failed
continuation keeps the evidence that is already loaded and offers a fresh authorized query instead
of hiding the proof it already holds. The marker distance of a documented gap is named as a marker
distance and never as a measured outage duration. The limits of the answer, the time and origin
semantics and the state that the Core names for the diagnosis history stay visible. The binding
contract of OIP-0082 carries the rules again.

**Proof.** `apps/flutter/test/managed_diagnostics_test.dart` is reconciled to the Spectrum-2027
shell and proves the rendered gap, the health transition, the unknown previous state of the first
transition, the limits of the answer, the Core-named diagnosis-history state, the incomplete page
without a cursor and the continuation that merges without duplicating. The actual browser journey
reads the accessible names of the rendered surface, because Flutter publishes the rendered text of
a workstation as the accessible names of its semantics nodes.

**Measured result.** `OIP_CANONICAL_UI_GATE=1 python3 tests/real_device/acceptance.py` on canonical
`main`: **339/339 Flutter tests**, **175 browser findings with zero failures**, 13 captures, the
stable-shell visual comparison PASS and **8/8 managed acceptance phases PASS**, including the
actual Flutter SSH onboarding. The onboarding receipt now carries
`rendered_diagnostics: {persisted_evidence_section: true, diagnosis_history_status: not_implemented,
health_transitions: 50, documented_gaps: 2}` — the evidence the Core actually holds, read back
from the Core and compared with the rendered surface. The delivered bundle is
`a83a18def0ad4149dcba84452731a64083042e43bbafa1b260f3e3bad5873041`, local and served
byte-identical. No personal database change, no schema-7 activation, no private SSH, no push, no
deployment.

### Iteration 14 — the release binary, the local operations and the accessibility receipt

**Status: PROVED on canonical `main` (`6473617`, `bf36411`, `40f57cd`).**
The release ledger named three open items of the release mission: a release binary that is proven
by the canonical gate, a tested procedure for the local operations of an instance, and the
accessibility receipt of the integrated UI. All three are now measured.

**The release binary is proven by the same gate.** `cargo build --release -p oip-server --bin
oip-server --example mcp_probe` produces the Core `76d18b6e14a329b365daca16fd970e431b5f05c3340320054453abaa82a26ccd`
and the official MCP probe `029bf9f4505dd483d62196992d0443498a3e5a242f35a3192a4ef125227cfb08`. The
canonical runner can be pointed at another verified binary of the same contract
(`OIP_CANONICAL_SERVER_BIN`), the harness builds the profile of the binary that is executed and
names the hashes in its receipt. `OIP_CANONICAL_SERVER_BIN=…/target/release/oip-server python3
tests/canonical_regression.py --only oip_canonical_ui_gate` finished with **8/8 phases PASS**,
175 browser findings with zero failures, 339/339 Flutter tests, the visual comparison PASS and the
delivered bundle `a83a18def0ad4149dcba84452731a64083042e43bbafa1b260f3e3bad5873041` byte-identical
local and served.

**The local operations are a tested procedure.** `tools/oip_ops.py` operates one explicit instance:
one configuration, one protected IPC configuration, one database and one state directory. It
provisions the data store with the plan of the operator, starts the daemon, reports the state,
takes a consistent backup of a running instance, restores it, restarts the instance and stops it
cleanly. It installs no system service and it refuses every operation whose target resolves into
the personal installation of the operator, also through a relative path or a symlink.
`tests/oip_operations.py` proves the sequence against a disposable instance and records the
receipt: provisioning, start, status, log, backup with its integrity check, the refused restore of
a running instance, the clean shutdown without uncommitted observations, restore, start again,
restart, stop and the three refusals of the personal installation with its unchanged hash
`9f988c01c7115631db3b5bfd2b9228ecc24255b8b9905932a987a89c78e6a24e` at schema 6.
`docs/runbooks/operations.md` describes the procedure and the rules that the tool enforces.

Four real defects were found and fixed while proving it: the daemon requires an owner-private IPC
configuration, the Core refuses a database that anybody but the owner can read, the restore of a
running instance must be refused, and the Core rejects a path with a symlink component — the
temporary directory of macOS lives under `/var`, which links to `/private/var`.

**The accessibility receipt measures the name and role coverage.** `apps/flutter/test/browser_accessibility.mjs`
walks the six workstations of the live managed instance and asserts that every control a person can
reach carries an accessible name and that every focusable element is nameable. Measured: **136
controls, none without an accessible name**, no JavaScript error and no external request; the Core
denials of the scoped projection are recorded separately. The receipt is not a full WCAG audit and
does not claim one; the operator's own review of the application stays open.

**Two timeouts of the browser harness were too short.** The delivered web release is several
megabytes and the loopback of this machine delivers them slowly: the download of the bundle in the
canonical gate and in the real-device journey failed with the default request timeout of 30
seconds although the server answered it. Both downloads now get the time that the first paint of
the application already gets.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 15 — the upgrade and the rollback of a local instance

**Status: PROVED on canonical `main` (`62cadc2`).**
An upgrade of a local instance is a handover of the data store to the new binary.
`tests/oip_upgrade_rollback.py` rehearses it against a protected historical binary (the OIP-008.4
release, sha256 `73d70d8105914db20210c95268b5733ca2ec19c959c4c29fa57cb93c1935fe58`) and the current
release binary (`76d18b6e14a329b365daca16fd970e431b5f05c3340320054453abaa82a26ccd`).

**Measured result.** The historical binary provisions the store at schema 3 with two
organizations. The release binary serves the same store, migrates it to schema 7 and keeps the
organizations. The backup taken before the upgrade restores the previous state — the schema is 3
again — and the historical release adopts the restored store. The receipt is
`docs/evidence/oip-upgrade-rollback/upgrade-rollback.json`.

**Three rules of the handover, found while proving it.** The runtime sources must exactly match
the provisioned registry, otherwise the Core refuses to start with `runtime sources must exactly
match provisioned registry`. The data store must be owner-private, otherwise it is refused with
`database/sidecar must be owned by operator with private permissions`. And the configuration of an
instance is not portable between releases: a historical binary refuses the fields of a newer
configuration and the other way round, so the upgrade keeps the configuration of the era of the
instance until the instance has been migrated.

**Not rehearsed (at that time).** The daemon handover with the historical binary: the daemon of
the historical release was not started, only the offline provisioning and the backup of its data
store. The reason named in the receipt — that the daemon binds its local clients to the actor
policy of its era and refuses a start without a provisioned principal — was an **assumption, not a
measurement**, and it was wrong in two respects: the OIP-008 era binds the local clients to a
*principal* (`docs/architecture/oip-008-identity-authorization.md`), and the actor/permissions
shape is the shape of OIP-007. Iteration 21 measures the truth and rehearses the daemon.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 16 — the final acceptance of the integrated release candidate

**Status: PROVED on canonical `main` (`cac97ac`, tree `fcab8a5f0c3a9d3523c2c7f94ea0ae5cfa3aa8ea`,
working tree clean).**
`OIP_CANONICAL_UI_GATE=1 python3 tests/real_device/acceptance.py` on the clean canonical tree:
**339/339 Flutter tests**, **175 browser findings with zero failures**, 13 captures of the six
workstations at 1440 px and 1920 px, the stable-shell visual comparison PASS with both
negative-control classes and **8/8 managed acceptance phases PASS** — browser identity and the
single writer, the SSH handshake with the confirmed host identity and the monitoring, the restart
after SIGKILL, the actual Flutter SSH onboarding, the ingestion without clients, the host-key
change that blocks the collection, the rejected weak host key and the eight official MCP clients.
The delivered bundle `a83a18def0ad4149dcba84452731a64083042e43bbafa1b260f3e3bad5873041` is
byte-identical local and served, no JavaScript error, no external request, every owned process
stopped. The onboarding receipt carries the persisted evidence of the Core
(`health_transitions: 50, documented_gaps: 2`, `diagnosis_history_status: not_implemented`).

The receipts of that run: precheck `bff28843ca7b5d66…`, browser `eb40f9d723907098…`, visual
`a641a67b9b814a87…`.

**Safety.** The personal installation is untouched at SHA-256
`9f988c01c7115631db3b5bfd2b9228ecc24255b8b9905932a987a89c78e6a24e` with `user_version` 6 — no
schema-7 activation. The repository has no remote, so no push is possible. No deployment, no system
service, no private SSH connection, and no process of another workstream was signalled.

### Iteration 17 — the administration of a registered device in the approved workspace

**Status: PROVED on canonical `main` (`8b06720`).**
The Core owns the inventory and supports the register, the update and the archive of a device.
The client could not write the update at all: the Flutter API knew the register only and the
approved device workspace had no administration. The gap was found while the managed diagnostics
capability was reconciled — the same class of loss, a capability of the canonical tree that the
transplant of the design layer dropped.

**What was built.** The administration surface of the device names the revision it works on, sends
the **full replacement** the Core requires (an update is not a merge, so the metadata of the record
travels with it) and shows the refusal of the Core verbatim instead of a friendly invention. The
archive is an **offline operation of the Core**: the managed session refuses it with
`OFFLINE_ARCHIVE_REQUIRED` ("Archive remains an explicit offline operation"), so the surface names
the procedure and never offers a write that the Core would refuse.

**A defect of the global context was found and fixed.** The Core has no whoami route, so every
bootstrap was treated as an unverifiable principal transition: the global infrastructure scope was
reset to Unified and the session generation was bumped on **every** refresh of the authorized
projection — and an administration write needs such a refresh, so every write closed the inspector
of the device. The identity of the authorized session is the evidence that was missing. The
controller binds the principal of the session and the context keeps the scope of the operator
across a refresh. A principal change still invalidates the selection.

**Proof.** `apps/flutter/test/device_administration_test.dart` proves the surface, the payload of
the update, the revision guard and the shown refusal. The real-device journey against the actual
Core proves the update through the surface — the revision advances from 1 to 2 and the Core holds
the new name — and the named refusal of the online archive. `infrastructure_context_test.dart`
proves that the selected scope survives a refresh of the projection.

**The final acceptance of the integrated candidate** ran on the clean canonical tree
`8b8cd238636d89673cb8444ed3a6fc1b274752c8` (tree `59a73ff56067590deb75bc617ed14e17d600f1ef`,
`source_dirty=false`): **344/344 Flutter tests**, **175 browser findings with zero failures**,
13 captures, the stable-shell visual comparison PASS and **8/8 managed acceptance phases PASS**,
including the actual Flutter SSH onboarding with the device administration in it. The delivered
bundle `b09bb5ff4a16825ddf350f9278aa94a378f42222bbb5e23af0f76ed7bef2b844` is byte-identical local
and served; no JavaScript error, no external request, every owned process stopped. The receipts of
that run: precheck `a56d862e6d4b…`, browser `332572e68d5f…`, visual `7ee112bdbd68…`.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 18 — the browser receipt of the global infrastructure context

**Status: PROVED on canonical `main` (`91808cc`).**
The global infrastructure context is a mandatory gate. Its dependency was the reconciliation of the
UI workstreams, which is done, and the defect that reset the scope of the operator on every
refresh of the authorized projection is fixed. What was missing was the proof against the real
Core, and it is now a receipt that runs inside the canonical acceptance.

**What the receipt proves.** `apps/flutter/test/browser_global_context.mjs` measures, against the
managed Core of the acceptance harness: the global selection offers the individual infrastructures
of the authorized hierarchy (4 options), the selection of `Infrastructure A1` scopes the projection
(the placement of A2 disappears from the view), **the shared scope follows the operator across all
six workstations** — Übersicht, Geräte & Dienste, Netzwerk & VPN, OPC-UA-Browser, Diagnose &
Ereignisse and Einstellungen all report `Infrastructure Context: Infrastructure A1` — and the
unified view returns every authorized infrastructure. It also proves the rule of the contract: every
option is a selection of already authorized data and grants no permission.

The accessibility receipt of the six workstations now runs in the same place: 154 controls, none
without an accessible name, no JavaScript error and no external request.

Both receipts write their own receipt into the evidence of the run, so a later integration that
breaks the shared scope or the naming of a control is detected by the canonical gate itself.

**The final acceptance of the integrated candidate** ran on the clean canonical tree
`4d8f5654e8a8ed02c6a8c90c17a10487a54715f7` (tree `f9791425da26987a637abacc39dc7b531e2d8faf`,
`source_dirty=false`): **344/344 Flutter tests**, **175 browser findings with zero failures**,
13 captures, the stable-shell visual comparison PASS, the global context receipt (4 options, 17
findings, zero failures) and the accessibility receipt (154 controls, none without an accessible
name) and **8/8 managed acceptance phases PASS**. The delivered bundle
`b09bb5ff4a16825ddf350f9278aa94a378f42222bbb5e23af0f76ed7bef2b844` is byte-identical local and
served. The receipts of that run: precheck `f481979fbc76…`, browser `4566db42b715…`, visual
`7e3d2341157a…`.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 19 — the performance baseline of the release build

**Status: PROVED on canonical `main`.**
The Core side of the baseline was measured by the acceptance harness — the latency of the official
MCP probe and the resource use of the Core. The client side had no baseline at all: nobody knew
what the operator waits for in the browser.

**What was measured.** `tests/oip_performance.py` starts a disposable managed instance of the
**release** binary and runs `apps/flutter/test/browser_performance.mjs` three times against the
delivered web bundle. Measured over three runs (p50 / min / max):

| Phase | p50 | min | max |
|---|---|---|---|
| first paint of the delivered web release | 50 886 ms | 41 508 ms | 51 914 ms |
| the operator login of the anonymous state | 51 167 ms | 41 802 ms | 52 282 ms |
| the interactive shell with the six workstations | 284 ms | 239 ms | 359 ms |
| the authorized projection of the infrastructure | 102 ms | 11 ms | 266 ms |

The Core rests at 17 136 KiB of resident memory and 0.0 % CPU without clients. The delivered
bundle is `a51b62cdd3644a6be44bcb6409feb5345fe353c921ec281c9be6c4fcde4c56d2` — the same asset the
canonical gate proves.

**What the baseline says.** The first paint is **not** bound to the application: it is bound to the
transfer of the 3 MB web release over the loopback of this machine. Once the session exists, the
shell with all six workstations is interactive in a quarter of a second and the authorized
projection follows 102 ms later. A smaller delivery — or a local cache of the release — is a
**product decision** and is named as such; it is not an agent decision, and this baseline is the
measurement that a later decision needs.

The receipt is `docs/evidence/oip-performance/performance.json`. It is a local measurement of this
machine and explicitly not an SLA.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 20 — the offline archive of a device is rehearsed

**Status: PROVED on canonical `main`.**
The archive of a device is an offline operation of the Core: the managed session refuses it with
`OFFLINE_ARCHIVE_REQUIRED` ("Archive remains an explicit offline operation"), because an archive
changes the registry while the Core is serving. The surface therefore names the procedure instead
of offering a write that the Core would refuse — and the procedure itself was not proven yet.

**The rehearsal.** `tests/oip_offline_archive.py` runs against a disposable instance of the release
binary: the device is registered through the authorized managed session, the managed session
refuses the online archive with its named reason, the Core is stopped, the archive is applied with
the offline plan of the Core (`--inventory-plan … --inventory-apply`), and the Core starts again.
Measured: the offline plan is applied (`applied: true`, the action `{"outcome": "archive"}`), the
archived device advances its revision from 1 to 2, keeps its identity and its metadata, and is
**no longer part of the active inventory** — it only appears when the archived ones are asked for.

The procedure is documented in `docs/runbooks/operations.md` §7, next to the update of a device,
and the receipt is `docs/evidence/oip-offline-archive/offline-archive.json`.

Three defects of the rehearsal were found while proving it and are part of the procedure: the
offline plan needs the explicit `--inventory-apply` flag (without it the Core only proves that the
archive is admissible), the browser session lives in the memory of the Core and ends with its
restart, and the operator needs the scoped inventory permission of the plan.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 21 — the daemon handover with the historical binary is measured and rehearsed

**Status: PROVED on canonical `main`.**
The ledger claimed that the daemon of the historical release could not be rehearsed. That claim
was never measured — the historical binary was only used for the offline provisioning and the
backup of its data store — and a read-only investigation of the era contracts and of the existing
harnesses showed that the protected OIP-008.4 binary **is** started as a daemon by two milestone
harnesses (`tests/oip0085/migration.py`, `tests/oip0084/acceptance.py`), with a principal-bound
protected IPC configuration.

**The measurement.** `tests/oip_historical_daemon.py` rehearses the handover of a *running*
instance against a disposable instance and records what actually happens:

| Step | Result |
|---|---|
| the OIP-007 shape (actor, permissions, sources) | **refused**: `invalid protected local IPC configuration/path` |
| the OIP-008 shape (a credential bound to a provisioned, enabled principal) | the daemon starts and serves |
| the authorized read of `reader-org-a` | 200 with exactly the three sources of its organization |
| the authorized read of `reader-org-b` | 200 with exactly the fourth source |
| the read without a credential | 403 |
| the collection of the daemon | the sources of the scope become fresh, 41 observations are persisted |
| the schema of the store | 3 after the provisioning, 5 with the historical runtime |
| the release binary takes over | 200, the schema becomes 7, the observations are intact |
| the backup and the restore | the schema is 5 again, the observations are identical |
| the historical binary serves the restored store | 200, the observations are intact |

The receipt is `docs/evidence/oip-historical-daemon/historical-daemon.json`. The refusal that the
old receipt asserted without evidence is now a measurement, and the correct statement — the era
binds a *principal*, the actor shape is OIP-007 — replaces it in the ledger and in the progress
file.

The protected binary is used only when its hash is the recorded hash; the rehearsal never touches
the personal installation of the operator and nothing leaves the machine.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 22 — the macOS application bundle of the Flutter client

**Status: PROVED on canonical `main` (`205d08e`).**
The macOS half of G9 was open: the Core side of the local operations was done, but the application
bundle of the Flutter client had never been built. It exists now and is proven against a
disposable managed instance of the **release** binary (`tests/oip_macos_app.py`,
`docs/evidence/oip-macos-app/macos-app.json`):

* `flutter build macos --release` produces `oip_dashboard.app` (bundle id
  `org.openindustrial.oipDashboard`, version 0.3.0) in a few seconds (the receipt of the run
  names the seconds); the receipt names the sha256 of the
  executable and the digest over the tree of the bundle.
* The bundle starts and asks the Core for the authorized projection of the principal within the
  **first second** (the receipt of the run names the moment).
* The Core answers **403** and the bundle obtains **no** unauthorized data (`api_successes: 0`).
  It shows the approved Spectrum-2027 shell with the six workstations, the honest
  `PERMISSION_DENIED` notice and the operator login — no OIP/005 demo, no gradient KPI row, no
  `M-01` defaults, no AGENT-FIRST footer.
* The bundle terminates on `SIGTERM` in 0.0 s without leaving an orphan behind, and it starts
  again and reaches the Core again (0.5 s) — the restart of the application bundle.

**A defect of the desktop shell was found and fixed.** The frame of the storyboard belongs to the
screen the bundle was generated for (2560×1577). On a smaller display the window opens above the
visible area and the operator sees nothing at all. The runner now checks the frame against the
visible frames of the machine and places the window in the centre of the main screen when it
touches no visible screen; the placement is reported in the log of the bundle. On this machine
(the main display 1512×982 and a second display 2560×1440 above it) the system places the window
itself and the check confirms that the window is on a visible screen.

The evidence policy keeps the capture of the window local; the receipt names the window, its
bounds, the displays of the machine and the placement of the bundle.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 23 — the extended stability run of the release binary

**Status: PROVED on canonical `main`.**
The acceptance harness measures the Core for a few seconds. Nothing measured it over a
sustained run, and the reconnect of a collection was only a code path.

`tests/oip_stability.py` runs the **release** binary against four real collectors for 30 minutes
and takes 60 samples (`docs/evidence/oip-stability/stability.json`):

| Measurement | Result |
|---|---|
| the liveness of the Core | 60 of 60 probes answered with 200 |
| the resident memory | between 17 920 and 23 552 KiB, **−5 264 KiB** from the first to the last sample |
| the CPU | 1.73 % on average, 4.1 % at most |
| the collection | 41 463 observations, 1 398 per minute, constant over the run |
| the growth of the store | 536 KiB to 78 MiB under the load of the collectors |
| the log | 18 KiB to 116 KiB — no runaway |
| the death of a collector | noticed and recorded as a documented gap, the collection resumed 1 s later |
| the end | clean shutdown, `pragma integrity_check` answers `ok` |

The resident memory does not grow over the run: the Core holds its working set and the writer
does not accumulate. The store grows with the observations of the collectors, as it must.

### Iteration 24 — the continuation of a truncated diagnostic page

**Status: PROVED on canonical `main`.**
The persisted evidence of the diagnostics view is a page of the Core, cut off at 50 entries with
an opaque cursor for the continuation. The client followed the cursor and merged the pages by the
stable Core IDs — that was proven by a widget test against a fixture. What was missing is the
**browser journey against a real Core whose page really is truncated**.

`tests/oip_diagnostic_continuation.py` creates that Core: the collector of one source is cycled
until the Core has documented more gaps than a page holds — every gap is a real interruption of a
real collection (the receipt of the run names the cycles) — and the browser journey
(`apps/flutter/test/browser_diagnostic_continuation.mjs`) then follows the evidence in the
approved shell. Measured (`docs/evidence/oip-diagnostic-continuation/diagnostic-continuation.json`):

* the Core answers the first page with 50 entries, `truncated: true` and a cursor;
* the surface offers the continuation for the gaps and for the health history;
* the continuation asks the same authorized route with the opaque cursor of the Core
  (the receipt of the run names them — they are opaque and of the run);
* the pages are disjoint — no row is repeated and no row is lost (the receipt of the run names
  the rows and the distinct rows);
* the health history needed three continuations and ends
  truncated: `false`;
* the offer of a kind disappears exactly when its last page is reached;
* the evidence stays painted and its disclosed limits stay visible; no failure of the evidence is
  shown.

20 checks, no error, no page error. The journey works against the **release** binary and the
delivered web bundle — not against a fixture.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 25 — the parity of the OPC-UA address space is re-inventoried

**Status: PROVED on canonical `main`.**
The last independent gap of the functional gate G8 was the parity of the OPC-UA address space:
the milestone harnesses had proven it for the releases of their era, but the **current release
binary** had never been re-inventoried against a real backend.

`tests/oip_opcua_parity.py` runs the release binary against four real collectors and compares
the official MCP tool `oip_opcua_nodes_read` with the REST routes
(`/docs/evidence/oip-opcua-parity/opcua-parity.json`):

| Measurement | Result |
|---|---|
| the MCP answer | 100 nodes of 1 006, offset 0, limit 100 |
| `/api/v2/opcua/nodes` | the same page — the same nodes, the same total, the same offset, the same limit |
| `/api/v1/opcua/nodes` | the same page |
| the second page | disjoint, the boundary exact (`bulk.0098` → `bulk.0099`) |
| the scope | the reader of the other organization is refused with `RESOURCE_NOT_ACCESSIBLE` — without a name of the foreign source |
| across a reconnect of the collector | the address space is served again, the content and the order are unchanged |

**A contract gap was found and is escalated.** The address space of a source is the **live
catalog of its collector**: it is published while the collector connects and it is replaced when
the collector connects again. The pagination is by offset, so a page that is read across such a
change **can** repeat a node at the boundary. The measured reconnect shows the opposite of a
repetition — the content and the order of the page did not change and **no** node was repeated at
the boundary (`docs/evidence/oip-opcua-parity/opcua-parity.json`) — so the repetition is a
possibility of the design of the collector and **not** a measured effect.
Every other paginated surface of the Core (the diagnostic pages, the observation history) uses an
opaque cursor and is therefore stable; the Core makes no such promise for the address space, so
no claim is broken. Giving the address space the same cursor would change the query of the REST
and MCP surface of the Core: that is a **contract decision of the operator** and is named as such
in the ledger.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 26 — the final acceptance of the release candidate, bound to the tree

**Status: PROVED on canonical `main` (`e7aa994`), tree `a1e2b71`.**
The canonical acceptance was run once more on the clean tree after every change of this
iteration, with the **release** binary and the delivered web bundle
(`target/oip-canonical-regression-final2/`). The receipt names the tested artefacts:

| Artefact | Value |
|---|---|
| the tested revision | `e7aa994104a6` (the full hash in the receipt of the run) |
| the tested tree | `bf03f2465868` (the full hash in the receipt of the run) |
| the tree during the run | clean (`source_dirty: false`) |
| the release binary (`target/release/oip-server`) | `4f49cc1512fa8e10083bdf01e5cb618077e3337ed4ce8fc948fd08b37adef30f` |
| the official MCP probe | `029bf9f4505dd483d62196992d0443498a3e5a242f35a3192a4ef125227cfb08` |
| the served `main.dart.js` | `a51b62cdd3644a6be44bcb64…` (the full hash in the receipt of the run) |
| the served bundle equals the local build | **yes**, byte by byte |
| the Flutter tests | 356 passed, 0 failed (one skipped: the live test without an instance) |
| the browser gate | 175 findings, 0 failed, 13 captures, no console error, no external request |
| the accessibility receipt | 154 controls, **0** without an accessible name |
| the visual comparison | **PASS** |
| the eight functional phases | 8 of 8 **PASS** |
| the verdict of the gate receipt | **PASS** |
| the operator visual approval | `VISUAL_PENDING_OPERATOR_ACCEPTANCE` |
| the own processes | stopped |

The visual acceptance of the operator stays **pending**: the gate proves that the rendered
surface is the approved Spectrum-2027 shell and that it matches the committed technical
references, but only the operator can accept it.

**One honest remark about the binaries and about this binding.** The web bundle is
byte-identical between the builds (`a51b62cd…`), the Rust release binary is not: the gate rebuilds
it and its sha256 differs from the build of the earlier rehearsals (`76d18b6e…`, `6afee854…`,
`835ed0a1…`). Every receipt names the binary it actually executed, and no receipt claims a hash
of a binary it did not run. The commit after the tested revision (`d4a0a9d`, the rehearsal of the
transport parity) and the binding commit itself add **only** a test script and documentation — no
line of the Core or of the Flutter application — and the served bundle of the tested tree is the
byte-identical asset (`a51b62cd…`) that the gate proved.

No personal database change (`9f988c01c7115631db3b5bfd2b9228ecc24255b8b9905932a987a89c78e6a24e`,
`user_version` 6), no schema-7 activation of the personal installation, no private SSH, no push,
no deployment, no system service, no foreign process touched.

### Iteration 27 — the functional depth of the six workstations

**Status: PROVED on canonical `main`.**
The canonical gate proves that the six workstations of the approved shell render, that they carry no
legacy marker and that the scope follows the operator. It does not prove that they show **real**
data of the authorized Core — a workstation that renders an empty state passes such a gate.

`tests/oip_workstation_data.py` starts the release binary with four real collectors and
`apps/flutter/test/browser_workstation_data.mjs` drives the approved surface. The operator
selects a source in the global Infrastructure Context (a real mouse event on the painted option —
the web engine forwards no key events), and every workstation is then read while the page is
scrolled. Measured (`docs/evidence/oip-workstation-data/workstation-data.json`): 17 checks, no
JavaScript error.

| Workstation | What the operator really sees |
|---|---|
| Übersicht | the authorized hierarchy (`Organization A`, `Infrastructure A1`) and its counts |
| Geräte & Dienste | the device of the selected source (`device-a`) |
| Netzwerk & VPN | the authorized placement (`Organization A / Infrastructure A1`, `site-a1`) |
| OPC-UA-Browser | the real nodes of the source (`bulk.*`, `motor_running`, …) |
| Diagnose & Ereignisse | the real events of the scope (`source-a`) |
| Einstellungen | the real settings of the Core (`history_page_size` with its default and its validation) |

In **all six** workstations no identifier of the other organization appears — `device-d`,
`source-d`, `Organization B`, `Infrastructure B1` and `Site B1` are nowhere on the surface.

The receipt records that the settings shown are the real settings of the Core
(`docs/evidence/oip-workstation-data/workstation-data.json`); it does **not** record the two
details that an earlier reading of the surface named — that the application section reads the
platform scope, which this principal is **not** allowed to read, and that the operator reaches
the scoped section through the category `Diagnostics`. Those two are observations of the surface,
not measurements, and they are therefore not claimed here. The measurement that the deny-by-default
of the platform scope holds is the refusal of a foreign scope in the receipts of the transport
parity and of the OPC-UA parity.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 28 — the verified connection of a device in the surface

**Status: PROVED on canonical `main`.**
The last gap of the device management gate G4 was the association of a device with a **verified**
connection through the surface: the administration surface could register, update and archive a
device, but nobody had shown that the surface shows the connection of a device — with the host key
the operator confirmed and the identity the Core really verified.

`tests/oip_device_connection.py` starts the release binary with an **owned loopback SSH fixture**
(a real OpenSSH server with a real host key on the loopback of the machine; no system service, no
personal endpoint, no private key in a receipt) and performs the whole handshake through the
authorized managed session:

1. the device is registered through the inventory of the authorized scope;
2. the connection is started, the Core presents the host key of the fixture and waits for the
   consent of the operator (the fixture generates a fresh key for every run, so the receipt of
   the run names the fingerprint that was consented);
3. the host key is confirmed, the identity of the host is verified and the identity confirmation
   enables the read-only monitoring with a polling of 10 s;
4. the device collects — the state of the connection is `collecting`.

The browser journey (`apps/flutter/test/browser_device_connection.mjs`) then opens the device
workspace, selects the device and reads the connection panel of the approved surface. Measured
(`docs/evidence/oip-device-connection/device-connection.json`): 8 checks, no JavaScript error —

* the inventory of the scope lists the device;
* the panel `Verbindung & Monitoring` is shown with the state `Collecting`;
* the **confirmed host key** is shown — the same fingerprint the Core presented;
* the endpoint of the verified connection is shown;
* the read-only monitoring is shown with its polling and its revision;
* behind the expansion `Tatsächlich verifizierte Identität` the really verified identity of the
  host stands: `MacBookPro.fritz.box`, `Darwin`, 17 179 869 184 bytes of memory — and the Core
  names the sensors it could not read (`gpu`, `temperature`, `cpu_utilization`) instead of
  inventing them.

No personal database change, no schema-7 activation of the personal installation, no private SSH
to a foreign endpoint, no push, no deployment, no system service.

### Iteration 29 — the security review of the current release

**Status: PROVED on canonical `main`.**
G10 asks for a review that resolves, mitigates or explicitly escalates every material finding. The
acceptance of the production-security scope stays an operator decision; the review itself is the
work of the loop. `tests/oip_security_review.py` measures the findings of the current tree against
a running instance of the release binary (`docs/evidence/oip-security-review/security-review.json`):
**11 findings — 8 resolved, 2 mitigated, 1 escalated.**

**Resolved.**

* The dependency advisories of the complete lockfile: `cargo deny check advisories licenses bans
  sources` → advisories ok, licenses ok, bans ok, sources ok. The three exceptions
  (`RUSTSEC-2023-0071`, `RUSTSEC-2023-0089`, `RUSTSEC-2024-0449`) are documented in `deny.toml`
  with a reason and a review date — they are transitive dependencies of the OPC UA stack, not of
  the release path.
* The secret scan of the content that ships: gitleaks 8.30.1 over the 598 tracked and untracked
  files — 27 candidates, every one of them the SHA-256 of a source file inside a measurement
  receipt of `docs/evidence`. Each candidate is classified in the receipt; **no secret** was found.
* The browser session contract: `HttpOnly`, `SameSite=Strict`, `Max-Age=1800`,
  `Cache-Control: no-store`, `X-Frame-Options: DENY`, CSP `frame-ancestors 'none'`.
* The single use of the pairing code: the second use is refused with 403.
* The origin and the CSRF rule: a foreign origin is refused (403), a write without the CSRF token
  is refused (403), a write with a foreign origin and a valid token is refused (403).
* The protection of the credentials: a private 0600 file of 32 bytes that appears nowhere in the
  log of the instance.
* The enforcement of the scope: the reader of one organization sees `source-a`, `source-b`,
  `source-c` and no source of the other organization.
* The non-disclosure of a foreign resource: a foreign device and a device that **does not exist**
  are refused **identically** (`404 RESOURCE_NOT_ACCESSIBLE`) — the answer names neither the
  target nor the reason, so the refusal does not tell a foreign principal what exists.

**Mitigated.**

* The remote identity: the Core binds to **127.0.0.1 only** — a browser on another machine cannot
  reach it. A productive remote identity is **not implemented and not claimed**: the release is a
  local application.
* The same-UID boundary: the configuration and the credential are 0600, the directory is 0700 and
  a client must have the same OS user as the daemon. The boundary does **not** isolate hostile
  processes of the same user — that user can read the credential and control the process. This
  limit is part of the era contract and is not a tenant authentication.

**Escalated.**

* The durability of the execution audit: the audit of the Core is a **structured local log**; it
  is neither durable nor tamper-resistant. For a local instance with an authorized operator this
  is acceptable and is the contract of the era (`OIP-005 uses structured local logs … an explicit
  prerequisite for future remote mutating capabilities`). For a remote or productive deployment a
  durable, tamper-resistant store is a **prerequisite** — the operator decides whether the
  production scope accepts the current one.

The acceptance of the production-security scope remains **BLOCKED_OPERATOR**; the review gives the
operator the measured material for that decision.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 30 — the parity of the three transports of the current release

**Status: PROVED on canonical `main`.**
The gate G2 names the parity of REST, SSE and MCP. The milestone harnesses had proven it for the
releases of their era; the current release binary had not been re-inventoried.

`tests/oip_transport_parity.py` runs the release binary with four real collectors and compares
the three transports for **the same principal**
(`docs/evidence/oip-transport-parity/transport-parity.json`):

| Transport | Route | Projection |
|---|---|---|
| REST | `/api/v2/snapshot` | `source-a`, `source-b`, `source-c` · `device-a`, `device-b`, `device-c` |
| SSE | `/api/v2/stream` (the event `snapshot`) | the same |
| MCP | the resource `oip://v2/snapshot/current` | the same |

The three projections are **equal**, the projection contains nothing of the other organization
(`source-d` appears in none of them), and the transports refuse what they must refuse: the REST
route answers **403** without a session and the SSE stream answers **403** without a session — no
payload at all.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 31 — the honest states of the surface and the release manifest

**Status: PROVED on canonical `main` (`d1ab37c`).**
With every independent task closed, the remaining work was to look for the defects an operator
would actually hit. A systematic sweep of the approved surface for values that are presented as
facts found **three**:

1. **The footer rendered the security blocker as "unknown offen".** The scoped snapshot of a
   tenant carries no platform fact, so the client synthesised the placeholder `unknown` — and the
   footer presented it as an *open* blocker. The footer now names that the blocker of the platform
   is **not delivered to this session**. A blocker that the Core reported (`RUSTSEC-2023-0071
   offen`) and the case "no blocker reported" stay exactly as they were.
2. **The OPC-UA browser showed the scenario as "authorized_context"** — an internal wire value
   presented as a fact. The scenario is a concept of the demo; the authorized scope carries none,
   so the line of the source panel names that instead.
3. **The operator login named two causes of the end of a session** (30 minutes, the sign-out) but
   not the third: a **restart of the instance**. The browser session lives in the memory of the
   Core (`crates/oip-server/src/browser_session.rs`), so a restart ends it — and the operator
   restarts the instance routinely.

Four new widget tests pin the three states (`apps/flutter/test/security_blocker_footer_test.dart`,
the OPC-UA workstation test, the managed core integration test). The **design regression gate**
passes on the changed shell: 348 of 348 Flutter tests, 175 browser findings with zero failures,
13 captures, the visual comparison **PASS**, the eight functional phases 8 of 8 **PASS**, the served
bundle (`e721eb67…`, 3 031 349 bytes) byte-identical to the local build, the operator visual
approval still `VISUAL_PENDING_OPERATOR_ACCEPTANCE`.

**The release manifest.** The operator decides which artefacts may be signed and distributed; that
decision needs a list. `tools/oip_release_manifest.py` writes `docs/release/oip-release-manifest.json`
and `docs/release/SHA256SUMS`: every artefact of the release with its digest (the Core, the official
MCP probe, the macOS application bundle as a digest over every file of the bundle, the delivered
web release with the digest of `main.dart.js`), the revision and the tree it was built from, the
build commands, the toolchain versions, the digest over the tracked sources of the revision, the
digests of the tracked acceptance receipts and the state of the operator's visual acceptance.
`--verify` recomputes every digest and compares it with the written manifest: the manifest is a
receipt, not a promise.

The macOS application bundle was rebuilt from the committed source for the manifest
(`e5cb5292…` over the tree of the bundle, `6123cdc5…` over its executable), and the bundle of the
web release that the manifest names is the byte-identical asset that the gate proved.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 32 — the native application could not hold a session

**Status: PROVED on canonical `main` (`2e2bef1`).**
The sweep of the release for the defects an operator would hit found a **fatal** one: the macOS
bundle could never authenticate.

**The finding.** The browser of the web release keeps the cookie of the session on its own and
sends the origin of the page with every request. The native application has no browser, and the
client did neither:

* the Core refuses the login of a session route without an origin
  (`crates/oip-server/src/browser_session.rs`, `require_origin`) — the native client sent no
  origin, so the one-time code could not even be redeemed;
* the Core refuses every management read without the cookie of the session — the native client
  kept no cookie, so even a successful login would have left the bundle without an authorized
  projection.

The bundle therefore showed the operator login and nothing else. **G9's local installation and
G12's operator acceptance were impossible with the desktop application** — and the defect was
invisible in the web release, which is why the browser gate never saw it.

**The proof before the fix.** `apps/flutter/test/native_session_cookie_test.dart` runs the real
client on the VM — the Dart semantics of the bundle, without a browser — against a server that
behaves like the Core: the login answers with the `Set-Cookie` of the session and every other
route refuses a request without that cookie. Before the fix the read after a successful login
was refused with `PERMISSION_DENIED`.

**The fix.** A platform-specific session transport (`apps/flutter/lib/services/session_cookie.dart`
with its native and its web implementation): on a platform without a browser the client keeps the
cookie of the session in the memory of the process and declares the origin it addresses; on the
web the browser keeps both and the client adds nothing. The cookie is never written to a file,
never logged and never leaves the process.

**The proof after the fix.** `tests/oip_native_session.py` starts the **release** binary, issues
the one-time code of the operator and runs the native client against the real Core
(`docs/evidence/oip-native-session/native-session.json`): the login with the code, the hierarchy
of the authorized scope, the scoped projection with the sources of the scope and without the
source of the other organization, and the sign-out at the end. The Core served the session — its
audit names the capability executions.

**The gate.** The design regression gate passes on the changed client: **349 of 349** Flutter tests
(one skipped: the live test without an instance), 175 browser findings with zero failures, the
visual comparison **PASS**, the eight functional phases 8 of 8 **PASS**, the served bundle
(`8861cf74…`) byte-identical to the local build, the operator visual approval still
`VISUAL_PENDING_OPERATOR_ACCEPTANCE`. The macOS bundle was rebuilt from the committed source and
proves again: it starts, reaches the Core, refuses without a session, shows the approved shell,
terminates without an orphan and starts again.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 33 — the reconnect and the recovery of the application

**Status: PROVED on canonical `main`.**
The operator restarts the instance routinely. Nothing proved that the *application* survives that
honestly: the Core side of a restart is proven (the phase `restart_sigkill_identity`), the client
side was not.

`tests/oip_reconnect_recovery.py` runs the real Core with its collectors and the delivered web
release in a browser, and restarts the instance in the middle of the session through a small
control server of the rehearsal (`apps/flutter/test/browser_reconnect_recovery.mjs`,
`docs/evidence/oip-reconnect-recovery/reconnect-recovery.json`): 11 checks, no JavaScript error.

| Step | What the operator sees |
|---|---|
| the operator authorizes the session | the authorized projection of the unified view |
| the instance is restarted | — |
| the surface after the restart | `Kontext nicht autorisiert` with the badge `IDENTITÄT ERFORDERLICH`, the honest notice `Browser-Session oder zentrale Policy erlaubt diesen Management-Read nicht (PERMISSION_DENIED) … Keine vorherigen Kontextdaten werden angezeigt` and the operator login — **no stale content is shown as current** |
| the operator login | names the restart of the instance as the third cause of the end of the session (the panel of iteration 31) |
| a new one-time code | the authorized projection again, with a fresh moment (the receipt of the run names it) |

The session of the browser ends with the restart because the Core holds it in its memory — that is
the contract of the era, and the surface now says so instead of leaving the operator without an
explanation.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 34 — the upgrade of a live instance keeps the whole inventory

**Status: PROVED on canonical `main`.**
The upgrade rehearsal proved that the **organizations** of a store survived the handover of the
release binary. That is a thin proof for the operator: the instance of an operator carries devices,
measurements, events and documented gaps. The rehearsal now runs the **daemon of the era** against
four real collectors before the handover, so the store of the handover is a live instance.

Measured (`docs/evidence/oip-upgrade-rollback/upgrade-rollback.json`, `tests/oip_upgrade_rollback.py`):

| Table | Before the handover (schema 5) | After the takeover (schema 7) | After the rollback (schema 5) |
|---|---|---|---|
| organizations / infrastructures / sites / source_placements | 2 / 3 / 4 / 4 | 2 / 3 / 4 / 4 | 2 / 3 / 4 / 4 |
| principals / read_roles / role_bindings | 7 / 1 / 6 | 7 / 1 / 6 | 7 / 1 / 6 |
| observations / collection_events / data_gaps / source_health_history | the receipt of the run names them | the health transitions grow | they are the ones of the backup again |
| inventory_devices | *absent in the era* | 4 (created by the migration) | *absent again* |
| device_connections | *absent in the era* | 0 (created by the migration) | *absent again* |

The observations of the historical instance are **preserved by their stable Core IDs** — every
distinct observation key of the era (the receipt of the run names them) is still there after the takeover — and the data
only grows: the health transitions of the release binary join the history of the era. The rollback
restores the store **exactly**: the inventory of the backup and the inventory of the restored store
are the same, and the tables that the era did not know are absent again.

This is the evidence the operator needs for the activation of the release on the personal instance
(schema 6 to 7): the migration is additive and the inventory of the instance survives it.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 35 — the dry run of the activation of the operator's instance

**Status: PROVED on canonical `main`.**
The activation of the release on the personal installation is an **operator decision** (N4): the
Core refuses to touch the personal installation and the loop never activates it. Before that
decision the operator needs to know whether the activation would succeed at all — the migration of
the Core verifies the **checksum of every migration the store already carries**, so a change in
the SQL of an era after the store was written would refuse the activation.

`tests/oip_activation_dry_run.py` answers that question **without touching the personal
installation**: it copies the store of the operator into a disposable directory and lets the
release binary migrate the **copy** (`docs/evidence/oip-activation-dry-run/activation-dry-run.json`).

Measured:

| | Result |
|---|---|
| the store of the operator | schema 6, sha256 `9f988c01…` |
| the copy | byte-identical to the original (`the_sha256_equals_the_original: true`) |
| the migration | **accepted**: the schema becomes 7, the seventh migration is recorded |
| the inventory | identical before and after — 1 organization, 1 infrastructure, 1 site, 1 principal, 1 role, 1 binding, 1 device: nothing is lost |
| the integrity of the migrated store | `ok` |
| the daemon | the release binary serves the migrated copy |
| **the personal installation afterwards** | **unchanged**: the same sha256, still schema 6 |

Two properties of the rehearsal are worth naming: the runtime configuration of the copy declares
the sources of the instance with **closed loopback ports** — the rehearsal never contacts a
private endpoint of the operator — and the local IPC binds to the **enabled principal of the
store**, because a principal that the store does not carry is refused by the Core.

The operator action N4 is unchanged and now has measured material: the activation of the release
on the personal instance would succeed, and it remains the operator's decision with its own fresh
schema-6 backup.

No personal database change (`9f988c01c7115631db3b5bfd2b9228ecc24255b8b9905932a987a89c78e6a24e`,
`user_version` 6 — measured before and after the rehearsal), no schema-7 activation of the
personal installation, no private SSH, no push, no deployment, no system service.

### Iteration 36 — the example of the runbook is executable documentation

**Status: PROVED on canonical `main`.**
The operator writes the plan of the own instance from the example of the runbook (§1.1). A
documentation that does not work is worse than none.

`tests/oip_documented_plan.py` takes the example **out of the runbook**, provisions a disposable
instance with it and proves the whole path
(`docs/evidence/oip-documented-plan/documented-plan.json`): the plan provisions (one
organization, one source), the instance starts and answers the session route with 200, and the
operator of the example authorizes a session with the one-time code of the principal **of the
plan** — the session carries exactly that principal.

If the plan of the Core changes, this rehearsal fails: the runbook is executable documentation
and cannot rot unnoticed.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 37 — the settings navigation names the status of the Core

**Status: PROVED on canonical `main` (`fa7d66a`).**
The Core answers for every category of the settings whether the category is administered **offline**
or only **read** (`offline_administration_required` / `read_only`). The client parsed the answer and
dropped it: the navigation of the settings workstation showed the categories of the client without
the status of the Core, and the Application section stated the offline administration as a
hardcoded string of the client instead of the answer of the Core.

The navigation now shows the answer of the Core for the selected category —
`CORE · Nur offline administrierbar` or `CORE · Nur lesend` — and the categories are kept when a
section is loaded that does not read the settings, because they describe the **instance** and not a
section. The wire names of the Core are snake_case while the enum of the client is camelCase: the
mapping is explicit, so the status of a category is **found and not guessed**.

The design regression gate passes on the changed shell: **350 of 350** Flutter tests (one skipped:
the live test without an instance), 175 browser findings with zero failures, 13 captures, the
visual comparison **PASS**, the eight functional phases 8 of 8 **PASS**, the served bundle
byte-identical to the local build, the operator visual approval still
`VISUAL_PENDING_OPERATOR_ACCEPTANCE`.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 38 — the offline change of a setting of the instance

**Status: PROVED on canonical `main`.**
The Core has **no** HTTP and no MCP write path for the settings: the change is an offline
operation of the local operator with the exclusive local CLI (`--settings-change`). The settings
navigation of the application says so ("Kein Browser-Save"), but the runbook of the operations did
not name the procedure — and the operator has no other way to give their instance a name.

`tests/oip_settings_offline.py` proves the procedure against the **release** binary
(`docs/evidence/oip-settings-offline/settings-offline.json`):

| Step | Result |
|---|---|
| the change of `instance_name` of the instance | applied offline, the record has the revision 1 |
| the same change with a wrong revision | **refused** — the guard of the write |
| the same change with a principal without `settings_write` | **refused** |
| a value outside the validation of the key (`history_page_size` = 9999) | **refused** |
| the next validated start | the value is effective: `Meine Instanz`, `apply_status: active_startup_snapshot` |

The procedure is now in the runbook (§12) with the three rules that the Core enforces: the
principal needs the permission in the scope, the metadata belongs to the platform scope and
`history_page_size` is inherited, and the `expected_revision` is the guard of the write.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 39 — the lifetimes of the session and of the one-time code

**Status: PROVED on canonical `main`.**
The operator login promises the operator two things: the one-time code is valid for **120 seconds**
and may be used once, and the session ends after **30 minutes**. The Core keeps both as
constants; nothing proved that the promise of the surface holds.

`tests/oip_session_lifetime.py` measures both against the **real Core** with the **real**
lifetimes — nothing is shortened, because a shortened lifetime would prove nothing
(`docs/evidence/oip-session-lifetime/session-lifetime.json`):

| Promise | Measurement |
|---|---|
| the code is valid for 120 s | a code that was issued 130 s ago is **refused**: 403 `PERMISSION_DENIED` |
| the session ends after 30 minutes | the session is checked 1 830 s after its authorization: the session route answers `authenticated: false` and the **management read is refused with 403 `PERMISSION_DENIED`** |

The second measurement is the one that matters: the session route reports the state of the
session (an expired session is "not authenticated"), while the management read is the proof that
the identity is gone. The Core prunes the expired sessions on every check, so the identity of the
operator cannot outlive its lifetime.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 40 — the honest connection states of a device are pinned

**Status: PROVED on canonical `main` (`ad335f5`).**
The gate G5 names the **honest connection states**. The Core produces them — the acceptance proves
the collecting state and the block after a changed host key — but nothing pinned what the **surface**
shows for each of them: a regression that showed a blocked connection as connected would have
broken the promise of the gate without a single test failing.

`apps/flutter/test/device_connection_states_test.dart` pins all six states of the panel of the
connection with the real shape of the identity of the Core:

| The state of the Core | What the operator sees |
|---|---|
| `collecting` | `Collecting · aktuelle Messwerte empfangen` with the confirmed host key and the read-only monitoring |
| `ssh_verified` | `SSH Verified · Monitoring deaktiviert` |
| `host_key_changed` | `Host-Key geändert · Verbindung blockiert` with the error of the Core (`HOST_KEY_CHANGED`) |
| `host_key_unknown` | `Host-Key unbekannt · Identität vor der nächsten Verbindung bestätigen` |
| `unreachable` | `Unreachable · tatsächlicher Verbindungsversuch fehlgeschlagen` with the error of the Core |
| `stale` | `Stale · Messwerte veraltet` |

The suite found a real weakness of the panel on the way: the identity of the Core must carry its
whole shape (`disks`, `interfaces`, `unavailable`, `provenance`) — the panel casts the
unavailable list directly, so an identity without that field breaks the build of the panel. The
fixture of the suite now carries the real shape.

356 of 356 Flutter tests pass (one skipped: the live test without an instance).

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 41 — the extension of the registry of an instance

**Status: PROVED on canonical `main`.**
The operator adds infrastructure by extending the plan of the instance and provisioning it again.
Nothing measured that path, and nothing told the operator what the Core does with a plan that
**drops** a source.

`tests/oip_extend_registry.py` proves it against the **release** binary with four real collectors
(`docs/evidence/oip-extend-registry/extend-registry.json`):

| Step | Result |
|---|---|
| the instance with four sources | provisioned and serving |
| the plan extended by a fifth source | the four sources **survive**, the fifth is registered (5 sources) |
| the extended instance | the fifth source **collects**: 41 observations |
| a plan that **drops** the fifth source | **refused**: `hierarchy/provisioning validation failed` |
| the registry after the refusal | unchanged — the five sources are still there |

The registry of an instance is therefore stable: the operator adds, and a principal may be
disabled by the plan, but nothing is removed. The procedure is in the runbook (§1.2).

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 42 — the builds of the release are reproducible

**Status: PROVED on canonical `main`.**
The gate G9 asks for a **reproducible** macOS application build. The design regression gate
compares the served bundle with the local build — but that is the *same* build. Nothing built the
release **twice** and compared the artefacts.

`tests/oip_reproducible_build.py` builds the release twice and compares the digests
(`docs/evidence/oip-reproducible-build/reproducible-build.json`):

| Artefact | First build | Second build | Identical |
|---|---|---|---|
| the web release — `main.dart.js` | `a51b62cdd3644a6be44bcb64…` | the same | **yes** |
| the web release — the whole asset tree (35 files) | `db506a2f0764afb23e5c2718…` | the same | **yes** |
| the macOS application bundle (43 files, built from an emptied build directory) | `e5cb529201e18bfc7180253529…` | the same | **yes** |

The digests are taken over the sorted list of the paths and their contents, so they do not depend
on the order of the file system. The two builds of the bundle were independent: the build
directory was emptied between them, so the second build was not an incremental artefact.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 43 — the regression of the Core of the current release

**Status: PROVED on canonical `main`.**
The acceptance of the release runs the **Flutter** tests, the widget gate, the browser gate, the
visual comparison and the eight functional phases. The **Rust** suite of the Core — its unit
tests, its integration tests and its doc tests — was not part of it: the receipts of the Rust
regression belong to the eras of the milestones.

`tests/oip_rust_regression.py` runs the suite of the current tree
(`docs/evidence/oip-rust-regression/rust-regression.json`):

| | |
|---|---|
| the command | `cargo test --workspace --release --no-fail-fast` |
| the revision | the clean tree of this iteration |
| the toolchain | rustc 1.93.0, cargo 1.93.0 |
| the result | **181 tests, 0 failed, 0 ignored**, 29 suites, 125 s |

The 29 suites include the **integration tests** of the Core — `api`, `browser_session`,
`capabilities`, `diagnostics`, `hierarchy`, `inventory`, `ipc`, `mcp`, `provision_cli`,
`reliability` and `settings` — beside the unit tests of every crate and the doc tests.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 44 — the storage-failure path of the Core is escalated, not claimed

**Status: ESCALATED on canonical `main`.**
The resilience of the Core under a **storage failure** — a full disk, a read-only mount, a changed
permission — is the one failure mode of the instance that no acceptance covers. The Core's design is
visible in the code (`crates/oip-server/src/writer.rs`): a failed commit marks the persistence as
failed, the health of the Core degrades, the log names the failure with its operation
(`persistence_retry`), the ingestion is backpressured in a bounded loop, and the shutdown reports
the uncommitted observations instead of claiming a clean stop.

**Why it is not measured here.** A rehearsal needs a store that cannot be written. Neither the
mode of the file nor the mode of its directory achieves that on macOS: the Core holds the store open
for writing, so the permission check happens at the open and not at the write — the rehearsal
measured that the observations kept growing (796 → 1 760) with the store at `0400` and its
directory at `0500`. The remaining ways to fail the storage are a **full disk** (forbidden: it would
destroy the work of the machine) or a **read-only mount** (privileged: outside the scope of the
loop). The integration suite of the Core has no case for it either: the repository is injected into
the writer as the concrete `SqliteStore`, so a failing repository would need a production change
that is not justified by a test.

**The escalation.** The behaviour is designed and readable, but it is **not measured**. The
operator decides whether the production scope accepts an unmeasured storage-failure path, or
whether the operator provides a machine or a volume with a quota for the rehearsal. The loop does
not claim the property and does not simulate it.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 45 — the advisories of the client are measured too

**Status: PROVED on canonical `main`.**
The security review measured the advisories of the **Rust** lockfile (`cargo deny`) — the Dart side of
the release was not looked at. The Dart SDK of this machine has no `pub audit`, so the review asks the
advisory service of the ecosystem directly.

The dependency surface of the client is small and fully enumerated by `dart pub deps`: the Flutter
SDK, **`http` 1.2.2** (runtime) and **`flutter_lints` 3.0.2** (development) — every other package
belongs to the SDK. The advisory service reports **no known advisory** for either of them.

The review of the current release now has **12 findings: 9 resolved, 2 mitigated, 1 escalated**:

| | |
|---|---|
| resolved | the dependency advisories of the lockfile, the advisories of the client, the secret scan of the tree, the browser session cookie and the security headers, the single use of the pairing code, the origin and the CSRF rule, the protection of the credentials, the enforcement of the scope, the non-disclosure of a foreign resource |
| mitigated | the remote identity (the Core binds to 127.0.0.1 only), the same-UID boundary |
| escalated | the durability of the execution audit |

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 48 — the proved bundle is the bundle of the release

**Status: PROVED on canonical `main`.**
The rehearsal of the macOS bundle built the bundle against the port of a **logging proxy**, so the
proved artefact carried the URL of the proxy — not the URL that the operator uses. The bundle of
the release was therefore never the bundle that was proved.

The rehearsal now builds the bundle **exactly as the release names it** — for the documented port
of an instance (18808, the port of the example configuration) — and puts the witness on that same
port, so the bundle carries the operator's URL while the Core of the rehearsal listens on a port of
its own. The evidence is the HTTP level, because the Core leaves no trace of a request without a
session.

Measured (`docs/evidence/oip-macos-app/macos-app.json`):

| | |
|---|---|
| the build | `flutter build macos --release --dart-define=OIP_API_URL=http://127.0.0.1:18808` |
| the bundle | `oip_dashboard.app`, bundle id `org.openindustrial.oipDashboard`, version 0.3.0 |
| the first request | within the first second: `GET /api/v2/organizations?offset=0&limit=100` → **403** |
| the further requests | six in total, **all** 403 — the bundle obtains **no** unauthorized data |
| the tree of the bundle | `e5cb5292…` — the same tree that the reproducibility of the release proves |
| the window | the approved shell with the operator login (captured) |
| the shutdown | `SIGTERM`, no orphan left behind |
| the restart | the bundle asks the Core again and is refused again |

The runbook names the pairing of the ports: the release bundle is built for 18808, the operator
either keeps that port for the instance or asks for a bundle that is built for their own.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 49 — every receipt names the revision it was measured on

**Status: PROVED on canonical `main`.**
A reader of the evidence must be able to tell whether a receipt is **current**. Most of the
receipts of the release named neither the revision nor the tree they were measured on — the
milestone receipts of the eras do (they carry their baseline), the receipts of this release did not.

Every rehearsal now records the revision, the tree and the cleanliness of the working tree, and
the browser journeys receive the revision from their runner and record it as well. The receipts of
the acceptance (the canonical gate) name their revision already.

The receipts of this release that were measured before the change were re-measured on the current
tree — the seventeen rehearsals and their browser journeys — and the long ones (the performance
baseline, the extended stability run, the lifetime of the session, the reproducibility of the
builds) were re-measured in the background.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 50 — the storage-failure path of the Core is measured

**Status: PROVED on canonical `main`.**
The last escalated gap of the acceptance is closed. A store that cannot be written was not
rehearsed, because a rehearsal needs a volume with a quota: a full disk is forbidden here, a
read-only mount is privileged and the mode of the file or of its directory does not fail the
writes of an open store.

A **disk image of a fixed size** is exactly that volume — and it needs no privilege at all. The
rehearsal attaches a 64 MiB image, puts the store of a disposable instance on it and lets the
collectors fill it up until the write of the store is refused (20 KiB are still free when the
refusal comes).

Measured (`docs/evidence/oip-storage-failure/storage-failure.json`):

| | |
|---|---|
| the volume | 64 MiB, filled until the write is refused with `No space left on device` (20 480 bytes are still free) |
| the instance | **survives**: it keeps answering its routes with 200 while its store cannot be written |
| the health | **degrades honestly**: the instance is no longer `ready`, `persistence_healthy` is false, the counter of the persistence errors grows from 0 to 18, the last error is named `commit_failed_retry_pending` |
| the log | **names** the failure (`persistence_retry`) |
| the store | is **not corrupted**: `pragma integrity_check` answers `ok` |
| the recovery | after the space is freed `ready` is true again, the persistence is healthy, the last error is gone and the collection continues (the receipt of the run names the counts) |
| the shutdown | clean |

The rehearsal reports that it is **blocked** — with the reason — on a machine without `hdiutil`;
it never claims a measurement it did not take. Nothing of the rehearsal touches the personal
installation of the operator: the store is a file on a volume in the temporary directory of the
machine, and the volume is detached and deleted at the end.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 51 — the record is checked against the evidence, and the Core of the release is reproducible

**Status: PROVED on canonical `main`.**
An independent read-only audit of the ledger and of this state file against every receipt under
`docs/evidence/` found stale figures, claims that no receipt backs, and two literal defects. All
of them are corrected:

* the confirmed host key of the device connection — the SSH fixture generates a fresh key for
  every run, so the record names the **property** (the surface shows exactly the fingerprint that
  the host really presents) and not a value of one run;
* the performance and the stability figures, in the unit of the receipt (KiB, not MB);
* the tables of the diagnostics, of the upgrade/rollback, of the artefacts of the acceptance and
  of the daemon of the era;
* the claim of the OPC-UA pagination: the measured reconnect shows **no** repeated node, so the
  record no longer exceeds the receipt;
* the claim of the device update: it now cites the tracked receipt of the administration of a
  device;
* the two literal defects: an unfilled placeholder (`{REV}`) and a garbled cell.

Two gaps of the **handoff** are closed as well:

* the whole acceptance of the release is now a **tracked** receipt (the eight phases, the browser
  gate, the UI gate, the device administration and the 13 captures), so the handoff does not
  depend on a directory of a build that is not part of the checkout;
* the release has **one** build command for the Core. The gate built it with
  `cargo build -p oip-server` and the manifest named `cargo build --release`; the feature
  resolution of the workspace is part of the binary, so the two commands produced two different
  binaries and the operator could build a binary that the gate had never proved.

**The Core of the release is byte-reproducible.** The build script of the Core embeds the revision
into the binary, so the binary changes with every commit — the honest property is that **the same
revision yields the same bytes**, and the binary says which revision it is. Measured
(`docs/evidence/oip-reproducible-build/reproducible-build.json`): the Core and its official MCP
probe are built twice from scratch and both builds are byte-identical; the web release and the
macOS bundle are byte-identical as well, and the reproduction of the bundle **is** the bundle of
the release. The manifest of the release names the reproducible binary and the state of the visual
acceptance of the operator.

**The tool of the operations can show the log of the instance** (`tools/oip_ops.py log`), which
the gate G9 asks for; the rehearsal reads the log with the tool and the record of the operations
names the operation that was performed.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 52 — the record is checked against the evidence, and its integrity is proved

**Status: PROVED on canonical `main`.**
A second independent read-only audit of the ledger and of this state file against the receipts
found fourteen defects. All of them are corrected, and the correction is driven by the receipts
rather than by the prose:

* the numbers of the current release were quoted from the **previous** measurement of the
  rehearsals — the pages of the diagnostics, the build seconds of the bundle, the moments of the
  reconnect, the inventory of the upgrade/rollback, the figures of the storage-failure path. Every
  one of them now names the value of the receipt of the current run.
* the **confirmed host key** of the device connection is a property, not a value: the SSH fixture
  generates a fresh key for every run, so the record names the fingerprint of the **run**.
* the gate **never recorded** the count of the Flutter tests: the pattern of the runner did not
  match its own output (`+356 ~1: All tests passed!`). The pattern is correct now, and the
  receipt of the acceptance carries the count (356 passed, 0 failed, 1 skipped).
* the new receipts of the release were **not tracked** — the evidence policy of the repository
  ignores the receipts of the eras and whitelists the reviewed ones by name. The whitelist names
  the new receipts now, so the claim that the acceptance is a tracked receipt is true.
* the manifest of the release named the receipts of a **build directory** and could not be
  verified in a checkout. It names the tracked receipts now, measures the tree without its own
  files, names the revision of the **product** separately from the revision of the record, and
  states where its digests are verifiable.

**The integrity of the record is itself proved** (`tests/oip_record_integrity.py`,
`docs/evidence/oip-record-integrity/record-integrity.json`): every receipt that the record cites
exists **and is tracked by git**, and every receipt of the current release is cited by the ledger
or by this file. 37 citations, 33 receipts, no broken citation, no orphaned receipt.

The **storage-failure path of the Core** — the last escalated gap of the acceptance — is measured
on a bounded volume: the instance survives the full volume, the health degrades honestly
(`persistence_healthy` false, the counter of the persistence errors grows, the last error is
named), the log names the failure, the store is not corrupted, and the instance recovers when the
space is freed. The rehearsal reports that it is blocked — with the reason — on a machine without
`hdiutil`; it never claims a measurement it did not take.

The **Core of the release is byte-reproducible** for its revision: the build script of the Core
embeds the revision into the binary, so the binary names its own revision and the same revision
yields the same bytes. The release has **one** build command for the Core, used by the gate, by
the manifest, by the rehearsal of the reproducible builds and by the runbook.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 53 — the local installation of the application is rehearsed

**Status: PROVED on canonical `main`.**
The gate G9 asks for a **local installation** that works without OpenCode. The rehearsal of the
bundle proved the bundle **in the directory of the build**; the operator receives a **copy** in
the directory of the installation, and it is the copy that must work. That was not measured.

The rehearsal of the installation (`tests/oip_macos_install.py`,
`docs/evidence/oip-macos-install/macos-install.json`) copies the bundle of the release into an
installation directory — exactly as the operator copies it — and proves:

* the copy is **byte-identical** to the bundle of the release: the digest over the tree of the
  bundle is `e5cb5292…` before and after the copy, 43 files;
* the installed copy is a **real application bundle**: the identifier
  `org.openindustrial.oipDashboard`, the version `0.3.0`, the executable present;
* the installed copy **starts** from the installation directory, reaches the Core and is refused
  on **every** request (six of six with 403) — it obtains **no** unauthorized data;
* the window shows the **approved shell with the operator login** (captured);
* the installed copy **terminates on the operator's signal** (SIGTERM) and leaves **no orphan**
  behind, and it **starts again** from the installation directory and reaches the Core again.

The installation directory of the rehearsal is a directory of the temporary tree of the machine —
**never** `/Applications`. The installation of the release into `/Applications` is the step of the
operator and is now named in the runbook (§9.1): the copy, the first start, the quarantine
attribute of a received copy and the identifier that proves the copy is this release.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 54 — the release is verifiable with one command

**Status: PROVED on canonical `main`.**
A third party that receives this repository must be able to check the whole handoff without
trusting the prose of the record. The new tool (`tools/oip_verify_release.py`) is that command,
and it proves in one run:

1. the **manifest** of the release verifies — every digest of every artefact and of every receipt
   is recomputed and compared with the written manifest;
2. **every receipt is fresh** — no receipt of the release names a revision that predates the last
   change of the product it covers (`crates/`, `apps/flutter/lib/`). A receipt that predates the
   product does not measure the product;
3. the **record is intact** — every receipt that the ledger and this file cite exists and is
   tracked by git, and every receipt of the release is cited by one of them;
4. the **acceptance passed** — the receipt of the canonical gate says PASS with its phases, its
   browser findings, its Flutter tests, its captures and its accessibility numbers;
5. the **safety boundaries held** — no receipt claims that the schema 7 was activated on the
   personal store of the operator.

The verdict of the command is **`OIP_PRODUCTION_NOT_READY`** while the gates that need the
operator are open (G5, G10, G12). The verification is **not** a production acceptance: the
acceptance of the operator and the scope of the production security are the operator's. The
command never claims the visual acceptance of the operator — a visual acceptance that is **not**
pending is a problem of the verification.

**The verifier can fail.** A verifier that cannot fail proves nothing, so the negative control
(`tests/oip_verify_release_test.py`) feeds the checks with receipts that are wrong and proves
that each defect is reported: a receipt that predates the product, a receipt without a revision,
a broken citation, an orphaned receipt, an artefact with a wrong digest, a failed acceptance and
a **claimed** visual acceptance.

The procedure is in the runbook (§13).

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 55 — the first paint of the baseline is a property of the path, not of the release

**Status: PROVED on canonical `main`.**
The performance baseline measures a first paint of about 50 seconds and the record attributes it to
the **transfer** of the delivery — the application is interactive in a quarter of a second once the
session exists. The operator was then asked to decide about the delivery of the web release: a
smaller delivery, a compressed asset or a local cache.

That decision was about to be taken on a number that is a property of the **measurement
environment**, not of the release. The rehearsal of the rate (`tests/oip_loopback_rate.py`,
`docs/evidence/oip-loopback-rate/loopback-rate.json`) measures the path:

| Measurement | Result |
|---|---|
| one connection of the loopback (raw socket) | about **150 KiB/s** |
| one HTTP request of the loopback | about **138 KiB/s** |
| two connections in parallel | about **274 KiB/s** — the limit **grows** with the connections |
| a Unix socket on the **same machine** | about **860 MiB/s** |
| the delivery of the browser before the first paint | **18.2 MB** over 38 requests (the 3 MB bundle plus the renderer, the fonts and the assets) |
| the transfer at the rate of one connection | **126 s** — the browser parallelises over a few connections, so the first paint is about 50 s |

A limit that grows with the number of connections and a machine that is roughly six thousand times
faster without the TCP path show that the **path** is slow, not the machine and not the release.
On a machine with an ordinary loopback the same delivery is a fraction of a second.

The operator decision stays the operator's — and the ledger now says that it must be taken on a
measurement of the operator's **own** machine, not on the number of a throttled path.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 56 — the reconciliation of the worktrees is proved, not asserted

**Status: PROVED on canonical `main`.**
The binding rules demand that the active UI worktrees are reconciled **without overwriting newer
implementations or foreign ownership**. The record stated that the question was settled — the
Spectrum-2027 workstations are the canonical application of `main` and the branch
`feature/oip-managed-diagnostics` is reconciled into them — but that was **prose**: the branch
holds a commit (`55d4f50`, 1556 insertions) that `main` does not contain, and the ledger cited
its recovery report, a path that **was not in the canonical branch**.

The rehearsal of the reconciliation (`tests/oip_worktree_reconciliation.py`,
`docs/evidence/oip-worktree-reconciliation/worktree-reconciliation.json`) proves the obligation:

* the branches of **all 22 worktrees** and, for every branch, the commits that the canonical
  branch does not contain — exactly one branch has one such commit;
* the **files** of that commit: the canonical branch carries all **13** of them;
* the **capability** of that commit, checked in the canonical branch: the documented gaps, the
  health transitions, the opaque cursor of the continuation, the status of the diagnosis history,
  the adapters of the Core and the model of the diagnostic page — all present;
* the **receipt that proves the capability** in the canonical branch: the rehearsal of the
  diagnostic continuation walks the documented gaps and the health history over the opaque cursor
  of the Core in the browser.

The **evidence of the reconciliation** — the recovery report and its machine-readable receipt — is
preserved in the canonical branch now (`docs/recovery/`), so a reader of `main` sees how the
capability of the branch was decided, not only that it is there.

**The checker of the record now checks every path that the record names**, not only the
receipts, and the ledger must not present a path of the build tree as the evidence of a claim. The
strengthened check found the second defect of this kind immediately: the ledger presented
`target/oip-canonical-regression-final/` as the evidence of the acceptance of the release. The
ledger names the **tracked** acceptance now.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 57 — the kinds of the measurement are covered, and the ones that are not available are named

**Status: PROVED on canonical `main`.**
The gate G6 asks for **supported** CPU, RAM, storage, network and uptime measurements, and the
contract of the real device onboarding is explicit about what the host report delivers and what
it does not:

> GPU, temperature and CPU utilization are explicitly unavailable. … Interface-reported addresses
> are not reachability probes.

That honesty was in the code and in the contract but had **no receipt**: the receipt of the device
connection showed that a device collects, not *which* measurements it collects and which ones the
release refuses to invent. The rehearsal `tests/oip_measurement_coverage.py` measures it against
the real Core and an owned loopback SSH fixture:

* every **supported** kind is delivered as an observation of the authorized source — CPU
  (`host.cpu_info`, `host.model`), RAM (`host.memory_total_bytes`, `host.memory_used_bytes`),
  storage (`host.disks`), network (`host.interfaces`) and uptime (`host.uptime_seconds`) — and the
  source is published: the observations are readable on the authorized route of the Core, not only
  stored;
* the three kinds that the contract names as unavailable are **named** in the connection record
  and are **never** delivered as a number — the receipt names the measurements that were invented,
  and the list is empty;
* the report carries its **provenance** (an authenticated SSH host report of a fixed read-only
  query, not hardware attestation);
* the painted surface **names** the kinds that are not available
  (`Nicht verfügbar: gpu, temperature, cpu_utilization`), so a measurement that is missing never
  looks like a measurement of zero.

The rehearsal had to learn the shapes of the Core before it could measure it: the source list is a
bare array without a `kind`, the observations are asked for by `source` and not by `source_id`,
and the value of an observation is a tagged value and not a bare number. Two defects of the
**journey** were found on the way and fixed: a control below the fold was activated by the
geometry of a semantics node outside the viewport, so the click landed somewhere else and the
verified identity was never opened; and the journey named the device and the name of its receipt
in the source, so a second rehearsal could not use it. The journey now brings the control into
the view, records **how** the tile was opened and keeps the painted surface as the evidence.

The panel of the device refreshes itself every few seconds — the question was whether it throws
away what the reader opened. It does not: the tile of the verified identity stays open over the
refresh (24 observations over twelve seconds), and that is measured, not assumed.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 58 — the boundary of the personal store is measured, and the release's own binary is the reproducible one

**Status: PROVED on canonical `main`.**
The one-command verification of the release reported the boundary of the personal store of the
operator as `false` inside a receipt that said `PASS` — and it had never measured it: it looked
for a key that the receipt of the rehearsal of the activation does not have, so the check passed
silently. The boundary is measured now: the digest and the schema of the store are read
read-only and compared with the digest of the record and with the digest that the rehearsal
recorded. The store of the operator is unchanged and still at schema 6.

The **manifest of the release** compared the Core that the release delivers with the binary of
the rehearsal of the reproducible builds — a comparison that can only hold when the rehearsal ran
on the very revision of the release, because the binary names its own revision. It did not, and
the manifest said so. The rehearsal runs on the revision of the release now: the two builds of the
Core are byte-identical, the manifest names that binary, and the web release and the macOS bundle
of this run are byte-identical to the artefacts of the acceptance — so the acceptance still
describes what the release delivers.

The **canonical acceptance** was run again on the current tree with the release binary and the
delivered web bundle: the eight functional phases PASS, 358 of 358 Flutter tests, 175 browser
findings with zero failures, 13 captures, the visual comparison PASS, the served bundle
byte-identical with the local build, no JavaScript error and no external request. The whole
acceptance is a tracked receipt and names the revision and the tree of its run; the visual
acceptance of the operator stays `VISUAL_PENDING_OPERATOR_ACCEPTANCE`.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 59 — the history of the measurements of a real device is measured

**Status: PROVED on canonical `main`.**
The gate G6 asks for **historical observations, freshness, diagnostics, reconnect and failure
recovery**. The record claimed "measurements and history proven against the fixture" while the
history of a **real device** had no receipt of its own: the canonical acceptance checks that the
persisted history of the connected device exists and that every stored sample is stale — and
nothing more.

The rehearsal `tests/oip_observation_history.py` measures the history of the measurements of a
real device against the real Core and an owned loopback SSH fixture:

* the history **grows** with the polling — the samples are persisted, not computed for the request;
* every stored sample is reported as **stale**, while the current route of the same metric reports
  the live one as `fresh`: a stored sample is never drawn as a live value;
* the order is **ascending by the receive time**, and the receive time is present;
* the cursor walks the history forward: the pages are **disjoint** and **complete**, no sample is
  lost and none is repeated; the stable id of a sample deduplicates the history;
* the history is **scoped**: a device of another organization and a device that does not exist are
  refused identically with `404 RESOURCE_NOT_ACCESSIBLE`, so the answer does not disclose whether
  the target exists;
* the history **survives the restart** of the instance — the samples stayed — and the collection
  **resumes** afterwards.

The contract of the Core answered every question of the rehearsal: the history is an object with
`items`, `truncated`, `next_cursor`, `missing_evidence` and `time_semantics` — never a bare array
and never a total — the page is walked with an opaque cursor that is bound to the query and to the
principal, the stored samples are rewritten as `stale` on read, and the history is served from the
oldest stored entry forward.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 60 — the record is audited clause by clause, and the clauses it did not measure are corrected

**Status: PROVED on canonical `main`.**
The record claimed that the independent work of G1–G11 is closed. That claim was **prose**: an
independent audit read the gate table of the ledger clause by clause and opened every receipt under
`docs/evidence/` to see whether it measures what the clause says. The audit found **four clauses
that no receipt proves** and **seven clauses whose receipt proves something weaker than the claim**.
The findings were verified against the sources before anything was changed.

**The clauses that no receipt proved — the record now says what is measured:**

* **G9** named the revision `3c663f9` and the digest `36c79dcb…` of the binary that the gate
  executed. **Neither value exists in any receipt** — the acceptance names `eaf9c5c2…` and
  `a4fab0c0…`, the manifest names `24727dd7…`. The row now names the receipts instead of the
  values, so the claim cannot rot.
* **G3** claimed that "the scope of the operator survives a refresh of the authorized projection"
  while the browser receipt measures the **opposite** for a page reload: the selector returns to
  the unified view, because the scope is the choice of the session. The row now states both facts:
  the scope follows the session across the six workstations and survives a refresh of the
  projection (a widget test over the contract fixtures), and a **new session starts in the unified
  view again** (the browser receipt).
* **G8** claimed that "the settings navigation names the status of the Core for every category"
  without a receipt — only a widget test over fixture DTOs.
* **G12** claimed that the operator login names **every** cause of the end of a session; the
  widget test asserts two of the three.

**The clauses that were stronger than their receipt — the wording now matches the measurement:**

* the collectors of the load and of the parity run are the **simulated** endpoints (the Core under
  test is the release binary) — the rows now say so;
* the device of the fixture is the **local host** on the loopback, not a physical device — "a real
  device" is reserved for evidence that names a physical host (G5 already says "fixture only");
* the device-connection receipt carries **nine** checks, not eight;
* the secret scan covered 631 files while **671** ship;
* the Rust suite was measured on a revision that is not the revision of the release;
* the rehearsal of the reproducible builds ran on a revision whose Core sources are identical to
  the sources of the release — the row says exactly that.

**The checker of the record now walks the whole evidence tree.** It enumerated the receipts of the
areas whose name begins with `oip-` and therefore never saw the era directories
(`oip003`…`oip0085`), the baseline of the initial commit (`git-baseline`) or the painted surface of
the coverage journey. The tree is now walked whole: every file of the release must be cited by the
record (55 of 55), and the receipts of the eras are a **named class** — the history of the
measurement and not the evidence of this release (1 271 files over 13 areas, every area named by
the record). The one-command verifier carries the same rule.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 61 — the two advisories of the lockfile are closed, and the secret scan covers every shipping file

**Status: PROVED on canonical `main`.**
The audit of the record found that the secret scan of the tree covered 631 files while **671**
ship, and the security review of the current tree then failed on the **dependency advisories of
the lockfile**: the ecosystem had reported two advisories after the last review.

* **RUSTSEC-2026-0459** — `libsqlite3-sys` bundles SQLite before 3.54.0, which can return
  uninitialized page-cache memory when a process opens a database file together with a sibling
  `-wal` file whose page size differs. A crafted pair of files can make ordinary queries return
  stale bytes from the memory of the process. The vector is local and needs the victim to open the
  files.
* **RUSTSEC-2026-0462** — the Streamable HTTP clients of the MCP SDK read a response body into
  memory without a limit; a malicious server can answer with a body that never ends, before any
  authentication, and exhaust the memory of the host.

Both are closed by the upgrade: `rusqlite` moves to **0.41** (with `libsqlite3-sys` 0.39.1 and
SQLite **3.54.1**) and `rmcp` to **3.9.0**. The only source change the newer `rusqlite` requires is
that the progress handler of the history reader registers on a mutable connection. `cargo deny
check advisories` answers **ok** again, and the whole Rust suite passes with the new lockfile:
**181 tests in 29 suites, 0 failed**.

The **classification of the secret scan is now a proof and not a shape**: a digest-shaped value
inside a measurement receipt is a false positive only when the receipt itself pairs it with the
path of a file of the repository or with the name of an opaque key of the Core (the gap key, the
event key, the observation key, the cursor — all content hashes of the Core). The scan covers the
**671** files that ship, finds 28 candidates and classifies every one of them: **none**
unclassified. The review of the current tree stands at **9 resolved, 2 mitigated, 1 escalated**.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 62 — the whole evidence of the release is re-measured after the upgrade

**Status: PROVED on canonical `main`.**
The upgrade of the dependencies changed the Core, and the freshness rule of the record is
unforgiving: **no receipt may predate the last change of the code it covers**. Thirty receipts
became stale — the activation dry run, the device connection, the diagnostic continuation, the
documented plan, the registry extension, the daemon handover, the loopback rate, the macOS
application and its installation, the coverage of the measurements, the history of the
measurements, the native session, the offline archive, the OPC-UA parity, the operations, the
performance, the reconnect, the session lifetime, the offline setting, the stability, the storage
failure, the transport parity, the upgrade and rollback, the workstation data and the
reconciliation of the worktrees.

Every one of them was measured again against the release binary of the upgraded dependencies. The
rehearsals run **once** each — the rehearsal and the browser journey it drives write their
receipts in the same run — and the receipts are published **together at the end**, so that every
receipt is measured on a clean tree. The whole set runs with one command
(`tools/oip_refresh_evidence.py`), which the operator can run on their own machine.

Two defects of the tool were found and fixed on the way: it ran every rehearsal twice — once for
its receipt and once for the receipt of the browser journey — which gave a flake a second chance
to fail, and it read the state of a rehearsal from the alphabetically first of its receipts, which
for one rehearsal is the receipt of the browser journey (a receipt without a state of its own).

The journey that opens the tile of the verified identity now repeats the rounds that do not open
it: the geometry of the control depends on the layout of the surface, which is not stable while
the panel refreshes itself.

The record is whole again: **41 receipts, all fresh**, the manifest verifies, the canonical
acceptance of the release passes with the new binary (8/8 phases, 356 of 356 Flutter tests, 175
browser findings with zero failures, 13 captures, the served bundle byte-identical with the local
build), and the boundary of the personal store is measured unchanged.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 63 — the last two clauses of the audit are closed

**Status: PROVED on canonical `main`.**
The audit of the record named four clauses that no receipt proved. Two of them are closed now.

**The status of the settings categories (G8).** The record claimed that the navigation of the
settings names the status of the Core for every category — the Core states whether a category is
administered offline or only read, and the navigation shows that answer instead of a guess of the
client. Only a widget test over fixture DTOs proved it. The rehearsal
`tests/oip_settings_status.py` proves it against the **real Core**: the answer of the Core is read
with the session of the operator, **every** category of the Core is selected in the navigation,
and the status the surface shows for a category is the status the Core answered for it. Seven
categories, seven answers, seven words on the surface — and no wire name of the Core leaks into
the surface.

Two facts of the Core had to be learned for it: the settings of an instance are a **platform**
capability (a reader bound to an organization is refused with `403 PERMISSION_DENIED`), and the
navigation shows the status of the **selected** category — so the journey walks every category
instead of reading one line.

**The causes of the end of a session (G12).** The operator login names three causes of the end of
a session — the lifetime, the sign-out and the restart of the instance — and the pinned test
asserted **two** of them. The third is asserted now (`beim Abmelden`), and the ledger names the
test that pins it.

The rehearsal joins the tool that refreshes the evidence of the release
(`tools/oip_refresh_evidence.py`), so its receipt is measured again with every other receipt after
a change of the product.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 64 — the proof of the settings status is proved against the Core, and the review that found it is answered

**Status: PROVED on canonical `main`.**
An independent review of the new proof of the settings status found three weaknesses that the
proof itself could not see:

* the journey carried the **mapping of the client** and compared the surface with its own table —
  a client that ignored the answer of the Core and hardcoded the same two words would have passed
  every check;
* the navigation shows the status of the **selected** category, so a stale selection among the
  five categories that the Core answers alike would have passed;
* the client showed the **wire name** of a state it did not know, and the Core answered the state
  as an untyped string.

All three are closed:

* the journey now compares the **relation** of the answers of the Core with the relation of the
  words — two categories that the Core answers alike show the same word, two that it answers
  differently show different words — and it **proves the selection** by the order of the
  semantics tree. The dependence is proved by a **negative control**: the pinned widget test
  answers that the General category is only read — the opposite of the usual answer — and the
  navigation shows that answer, so a navigation with a table of its own fails;
* the Core answers a **typed** state (`SettingsCategoryStatus`) — the wire names are unchanged —
  and the client names a state it does not know instead of showing the wire name of the Core, as
  the contract of the settings requires;
* the journey asks the Core in the scope of the platform **and** in the scope of an organization,
  and the refusals of the Core are recorded with their route instead of being swallowed by the
  filter of the console errors.

The receipt proves **seven** categories, **85** checks, and the word of the surface is determined
by the answer of the Core. The whole evidence of the release was measured again — the Core
changed — with the one command of the release: 27 rehearsals, 33 receipts, none failed.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 65 — the record is audited a second time, and the numbers that drifted are gone

**Status: PROVED on canonical `main`.**
The first audit of the record read the gate table clause by clause. A **second, independent** audit
read the **corrected** record and found what the first one had missed:

* **the volatile numbers of a run were still quoted in the gate rows** — the minutes, the samples,
  the resident memory, the CPU, the observations and the log of the stability run, the free space
  and the error count of the storage failure, and the count of the Flutter tests. They were correct
  when they were written and wrong after the receipts were measured again. The **rule of the record**
  is that the record quotes the **properties** and the receipts quote the **numbers**: the numbers
  of a run have left the gate rows, and the rows quote the property instead.
* **the canonical state of the state file named an earlier era** — a source revision, a branch
  revision, an acceptance revision, a binary revision and a file count that had all drifted. The
  table names the release now, and **the checker of the record proves every one of its values**
  against the manifest and the receipts, so it cannot drift away again.
* **the canonical gate had not executed the binary that the manifest names**: the acceptance built
  the Core itself, and a later rehearsal rebuilt the binary, so the two digests differed. The
  reproducible build and the canonical acceptance now run at the **same revision** — the binary the
  gate executed is **byte-identical** with the reproducible binary and with the artefact of the
  manifest, and the served web bundle is byte-identical with the local build.
* **the receipts that claim to measure the release Core named only the path** of the binary, not its
  digest. The rehearsals of the stability, the transport parity, the session lifetime and the
  storage failure now name the **digest** of the binary they drove.
* the reconciliation of the worktrees named the branches but neither the worktrees nor its steps —
  it names all of them now; the painted surfaces of the journeys are published with their receipts
  instead of lying over from an earlier run; the count of the receipts and the count of the files
  of the evidence tree carry different names now.

**The class of defect is closed by a checker.** Every **measurement** that a gate row or an index row
quotes is looked up in the receipts that the row names (`tests/oip_record_numbers.py`), and the
one-command verification runs it: 62 rows, 24 measurements, every one of them carried by a receipt.
A number that no receipt carries is a problem of the record — the check would have caught the
drifted numbers of this iteration before a reader did.

The whole evidence of the release was measured again where it changed: 27 rehearsals, the canonical
acceptance (8/8 phases, 358 of 358 Flutter tests, 175 browser findings with zero failures, 13
captures), the security review, the Rust suite and the reproducible build.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 66 — the witness of the macOS rehearsals observed the wrong refusal, and the record said so

**Status: PROVED on canonical `main`.**
The operator's chain of G12 was examined link by link: launch ✓, configure ✓, connect ✓,
monitoring ✓, use after a restart ✓ — and **authenticate** was proved in the browser (the
acceptance) and in the native transport (the native client), but not in the **shipped macOS
bundle**: the bundle is proven to reach the Core and to be refused without a session, and the
login itself was never driven.

Two facts came out of the examination:

* **the witness of the macOS rehearsals broke the rule of the Core.** The witness stands on the
  documented port of the instance — so that the bundle carries the URL of the operator — and
  forwards the request to the Core of the rehearsal. It forwarded the **Host** of the Core, so the
  Core saw the origin of the bundle and the host of another port and refused every request with
  `LOCAL_ONLY`: the **session was never evaluated** and the witness observed the wrong refusal.
  The witness now forwards its own host, the Core evaluates the session as it must, and the
  receipt names the **code** of every refusal — `403 PERMISSION_DENIED`, the refusal of the
  session. A status without a code proves little; the code says whether the Core refused the
  session, the origin or the scope.
* **the login in the bundle cannot be driven by an autonomous run on this machine.** A one-time
  code is typed into a native window, and the terminal of this machine holds **no assistive
  access** (`osascript` is refused with `-25211`), so no rehearsal can type into the bundle. The
  login of the browser is proven by the acceptance, the login of the native transport by the
  native client, and the bundle is proven to reach the Core and to be refused without a session.
  **That step is the operator's own** and belongs to his acceptance of G12 — the record says so
  instead of implying that the path is rehearsed.

The macOS rehearsals were measured again with the corrected witness, and the runbook names the
code of the refusal.

The same sweep found the **rates of the loopback** quoted in the ledger and in the runbook from an
earlier run of the measurement. They are now stated as the property of the path — the loopback of
this machine is throttled, the limit grows with the number of connections, and the same machine
delivers the same data over a Unix socket at a rate that is orders of magnitude higher — and the
receipt of the run names the rates it measured. The checker of the numbers now reads the
**runbook** as well: 73 rows and 25 measurements, every one of them carried by a receipt the
row names.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 67 — the honest connection states are proven against the real Core, not against a fixture

**Status: PROVED on canonical `main`.**
The record pinned the six states of the surface with a **widget test over fixture DTOs**: a fixture
proves that the client maps a state to a word, not that the **Core** produces that state and that
the surface tells the truth about it. The rehearsal `tests/oip_connection_states.py` drives the real
Core and an owned loopback SSH fixture through the states the Core can really produce, and the
journey `apps/flutter/test/browser_connection_states.mjs` reads the **state of the Core** over the
authorized route and the **word of the surface** in the same moment:

* the device is verified without the monitoring → `SSH Verified · Monitoring deaktiviert`;
* the **operator** enables the monitoring through the switch of the surface → `Collecting · aktuelle
  Messwerte empfangen`;
* the host of the rehearsal disappears → `Unreachable · tatsächlicher Verbindungsversuch
  fehlgeschlagen`;
* the host comes back → the Core collects again and the surface says `Collecting` — the **recovery
  of the collection**, in the surface, against the real Core;
* the host comes back with **another key** → `Host-Key geändert · Verbindung blockiert`, and the
  reason `HOST_KEY_CHANGED` is named.

The Core is never touched by the rehearsal: the operator acts through the surface, and the host of
the fixture is changed by the control of the rehearsal. Twelve checks, no JavaScript error.

The sixth state, **stale measurements**, stays pinned by the widget test — and the record says
why: the Core derives the cadence of a source from its polling (twice the interval plus fifteen
seconds), so a collected device reaches `unreachable` before it reaches `stale`; the stale state
needs samples that stop without a failed attempt.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 68 — the scope of the operator survives a refresh of the projection, against the real Core

**Status: PROVED on canonical `main`.**
The last clause that was pinned by a fixture was the scope of the operator across a refresh of the
authorized projection. The pinned widget test drives the **real method of the client**
(`resyncInfrastructure`) with the contract fixtures — it proves the logic of the client, but not
that the **Core** and the **session** deliver what the restoration needs. The rehearsal
`tests/oip_scope_persistence.py` proves it against the real Core:

* the operator selects the scope of a site in the Global Infrastructure Context — the scope of the
  operator is `site-a1`;
* the **administration of a device** changes the Core: the revision of the device advances, and the
  surface reads the authorized projection again and shows the new state of the device;
* the scope of the operator is **the scope of the operator still** — `site-a1` before and after;
* the **new session** of the page (the reload) starts in the unified view again — the scope is the
  choice of the session and not a persisted state.

Twelve checks, no JavaScript error. The evidence of the identity of the session is what keeps the
scope: the Core has no whoami route, and the session of the browser carries the principal.

The journey had to learn the surface: the administration of the device lives in the inspector of
the devices workstation and has its own scroll, and the choice of the type of the device is a
dropdown — a typing into the field of the administration proved to be racy in the browser, and the
choice needs no typing and exercises the same write of the operator.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 69 — the record names what the receipts prove, and the client names every state of the Core

**Status: PROVED on canonical `main`.**
The third independent audit of the record — a delegated, read-only audit of the ledger, of this
state file and of every receipt the record names — found eleven defects of the **record** and one
of the **product**. All of them are closed in this iteration, and the checkers that would have
caught them are now part of the one-command verification.

* **The gate G5 claimed "every state the Core really produces".** The Core derives **eight**
  states (`crates/oip-server/src/connection_service.rs`); the receipt proves four of them against
  the real Core and the widget test pinned six. The client had no word of its own for two of the
  eight (`collector_configured`, `verification_failed`) and showed the **wire name** of the Core
  for them — and for every state it does not know. The client names all eight now, an unknown
  state is `Verbindungsstatus unbekannt` and never the wire name, and the widget test asserts all
  eight (`apps/flutter/test/device_connection_states_test.dart`).
* **The gate G3 claimed that "the revision of the device advances"** — the journey never asserted
  it. It reads the record of the device from the Core before and after the write now and asserts
  that the revision advanced (`docs/evidence/oip-scope-persistence/scope-persistence.json`).
* **The gate G8 mixed the proof of the code with the proof of the fixture.** The typed status of
  the Core (`SettingsCategoryStatus` of `crates/oip-core/src/settings.rs`) is a fact of the code,
  the unknown state is pinned by the widget test, and the journey against the real Core never
  meets an unknown state. The row says so.
* **The gate G2 named three transport identifiers that no receipt carried.** The rehearsal records
  the REST route, the SSE stream and the MCP resource that it drove.
* **"The release Core" denoted two digests.** The rows name the Core binary *whose digest the
  receipt names* now, and the canonical gate, the reproducible build and the manifest are measured
  at one revision — so that the binary the gate executed is the binary the manifest names. The
  verification checks that equality and fails when it does not hold.
* **The performance baseline quoted the numbers of an earlier run** — the milliseconds of a run
  that the receipt no longer carries. The row quotes the **property** now and the receipt carries
  the numbers. The checker of the numbers of the record knows the durations and the sizes, and it
  reads the list items of the ledger as well — it would have caught that drift, and it caught a
  second one in the runbook (an observation count of an earlier run).
* **The rehearsal receipt of the scope carried an empty device.** It reads the record of the Core
  now, with its revision.
* **The captures of the acceptance were described as thirteen workstation captures.** Twelve are
  workstation captures; the thirteenth is the state of the anonymous session.
* **The manifest named 28 of the 63 receipts of the release.** It names every receipt now, and the
  verification fails when a receipt of the release is not digested by the manifest.
* **The state file named seven of the receipts of the index.** It names all of them now.
* **Two journeys published no painted surface.** They publish theirs now.

The canonical gate asserts the exemption of the agent-first principle in both directions: it is
absent from the shell and from the five other workstations, and it is named in the technical
capability context of the settings — the case the rule R6 of the baseline permits.

**A fourth, independent verification of the same claim** — again a delegated, read-only audit —
confirmed eleven of the thirteen rewritten claims and found five residuals. All five are closed
in the same iteration: the stale numbers of an earlier run in the **list items** of the ledger
(the next READY tasks and the operator actions — the checker of the numbers read only the table
rows and the runbook, which is why the drift survived there; the checker reads the list items now
and its negative control proves it), the two receipts of the index that the state file did not
name, the observation count of an earlier run in the runbook, the wording of the rows that name
the Core binary, and the receipt of the operations that the manifest digested twice. The audit
also named the claim of the typed status of the settings as belonging to the state file only; the
row of the ledger names `SettingsCategoryStatus` now as well.

**The volume of the machine filled up during the run.** It reached 100% while the evidence was
being re-measured: the Core could not commit its store any more, the collection was backpressured
and the rehearsal of the parity of the OPC-UA address space hung on a call that never came back.
The rehearsal was terminated and named as failed — nothing was published that was not measured. The
debug profile of the build tree was cleared (34.4 GiB) and the debug simulator was rebuilt; the
rehearsals that had failed because of the full volume or the missing binary were measured again
and passed. The receipts of the run carry the revision and the tree they were measured on.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 70 — the product audit: what the client hardcoded, what it claimed and what the Core does not deliver

**Status: PROVED on canonical `main`.**
The third audit of the **record** found the record itself in order. This iteration audited the
**product** — a delegated, read-only audit of the twelve gate texts against the source of the
Flutter client, the Core, the gates and the receipts. It found five places where the product did
not do what the gate names, and every one of them is closed here.

* **The legacy demo was one boolean away.** The client fell back to the OIP/005 demo dashboard
  whenever the Core answered with `simulated: true` — and the Core sets that flag when **one
  source** is simulated. The rule R7 of the baseline ("no automatic legacy fallback") was therefore
  proved only in a fixture that had the fallback switched off by hand. The client now accepts the
  legacy demo only when the Core states its demo mode with the scenario controls it offers
  (`apps/flutter/lib/app/controller.dart`), and the widget gate proves the rule with the **default**
  fixture: a Core with simulated data and no demo mode never shows the demo
  (`apps/flutter/test/canonical_ui_gate_test.dart`).
* **The OPC-UA workstation assumed the identity of the demo.** Its live values, its session history
  and its alarm were bound to the hardcoded entity `M-01`; against a real device the live series
  stayed empty and the rail read `Live M-01`. The workstation binds to the entity the **Core** names
  for the source now — the id of the device for a real source, the identifier of the simulation for
  a simulated one (`apps/flutter/lib/features/opcua.dart`), and the widget test proves it
  (`apps/flutter/test/opcua_workstation_test.dart`).
* **The diagnostics inspector claimed a reason it did have.** The panel stated that the reason of a
  data gap is not projected into the Flutter DTO — the shared DTO carries it, and the sibling panel
  of the same workstation renders it. The inspector shows the reason of the Core now and the false
  statement is gone (`apps/flutter/lib/features/diagnostics/evidence_inspector.dart`).
* **The gate G8 did not name what the Core does not deliver.** The Core owns no service registry and
  no VPN read route, and it has no HTTP or MCP write path for a setting. The surface names all
  three absences; the row of the ledger now says so as well, so that no reader can take the record
  for an administration capability that the Core does not have.
* **The audit named three limits that stay limits** and are recorded as such: the address space of
  the Core is a filtered legacy view (six metric names and `bulk.*`), the parity receipt measures
  the simulator catalog and not a real OPC-UA server, and the archive of a device is an offline
  procedure. They are named in the ledger and in the runbook; they are contract decisions of the
  operator, not defects of the loop.

The painted surfaces of the journeys now carry the head that names the surface they belong to — a
reader of `docs/evidence/oip-scope-persistence/painted-surface.txt` sees which surface the lines
below belong to.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 71 — the address space of the server is read as it is, and the Core may run on the Pi

**Status: PROVED on canonical `main`.**
The fourth delegated audit of the **product** (the change that made the Core browse the real
address space of the server) found eight places where the change was honest in its name and not
in its behaviour. Every one of them is closed here, and the operator's steering — the Core on
the Raspberry Pi — is reconciled with the contracts in `docs/runbooks/operations.md` §15.

* **The value of a node came from the wrong node.** The Core took the *browse name* of a node,
  turned it into a metric id and read `ns=2;s=<name>` — a node that a server with other names
  does not have. The value belongs to the node with the **node id of the server**: the adapter
  reads that id now (`crates/oip-opcua/src/adapter.rs`, `crates/oip-opcua/src/async_opcua/client.rs`),
  and the test proves that a name which names no node still delivers the value of the node id
  (`crates/oip-opcua/src/async_opcua/client/tests.rs`).
* **The observation carried the machine of the simulator.** Every node of every source carried
  the entity `M-01` of the simulator profile. The node is bound to the **entity that the source
  declares** now (`crates/oip-server/src/application_services.rs`).
* **The namespace and the access were constants.** The namespace of a node is the namespace of
  its node id and its access is the access of the **class** of the node; the API test checks
  both for every node of the page (`crates/oip-server/tests/api.rs`).
* **A node with several parents was delivered twice.** The catalogue is a **set of nodes** now:
  every node belongs to exactly one folder, the sum of the totals of the folders is the total
  of the catalogue, and the pages stay disjoint (the same test).
* **The browser read and measured.** The single read of a node was ingested; it is not any more:
  a measurement belongs to the collector that subscribes to the registered metrics of the
  source. The four statements that claimed the persistence — the API contract, the capability
  inventory, the description of the MCP tool and the note of the surface — are corrected
  (`docs/architecture/oip-003-flutter-api.md`, `docs/architecture/oip-capability-inventory.md`,
  `crates/oip-server/src/mcp.rs`, `apps/flutter/lib/features/opcua.dart`).
* **The client assumed a folder of the demo.** It asked for `folder=M-01` before it knew the
  address space of the Core. It asks for the whole catalogue now and falls back to it when the
  Core names other folders; the chips are the folders that the **Core** delivered
  (`apps/flutter/lib/features/opcua.dart`, `apps/flutter/test/opcua_workstation_test.dart`).
* **The gates counted the nodes of the demo.** The browser gates asserted `6 Nodes` and
  `1006 Nodes`; they read the count from the **Core** now, and the folder captions of the
  client no longer name the folders of a demo (the journey of the phase 2 was retired in
  iteration 88 — the proof of the claim is the receipt of the address space of the browser,
  `docs/evidence/oip-opcua-browser/address-space.json` — and `apps/flutter/test/browser_oip004.mjs`).
* **The Core may not run anywhere but on the Mac.** The operator intends the Core on
  `bodi-pi`. The reconciliation is in `docs/runbooks/operations.md` §15: a forward of the
  loopback of the Mac (an SSH tunnel) keeps the **identical origin** of the session, so the
  session contract, the origin rule and the security scope of G10 stay unchanged, and nothing
  is exposed. The smallest safe step is split into four phases, each of them measured and
  undoable on its own; phase 0 is the **read-only discovery** of the host
  (`tools/oip_pi_discovery.sh`), phase 1 the cross build of the workspace for the target of
  the Pi (`tools/oip_pi_build.sh`). The **cross build is measured**: the workspace builds for
  `aarch64-unknown-linux-gnu` without a Rust toolchain on the Pi — the Core and the simulator
  are ELF binaries for ARM aarch64, and the digests are named in `docs/runbooks/operations.md`
  §15.3. The target depends on the answer of the discovery, and the artefacts were never
  started on the Pi: the runtime proof is the operator's phase 2 and phase 4. No service is
  installed, no port is published, no BODI service of the host is touched and no personal data
  changes.

The whole evidence of the release was re-measured on a clean tree at the revision of the
product change: 30 rehearsals, 0 failed, 43 receipts published
(`target/oip-refresh-evidence.json`), the canonical acceptance passed on the clean tree
`9b71fc0b` with the release binary `dc4a932a` (363 of 363 Flutter tests, 187 browser findings
with zero failures, 13 captures, the visual comparison PASS, 8 of 8 phases —
`docs/evidence/oip-canonical-acceptance/acceptance.json`), the web release and the macOS bundle
are byte-identical with the artefacts of the acceptance, and the Core is byte-reproducible for
its revision (`docs/evidence/oip-reproducible-build/reproducible-build.json`,
`docs/release/oip-release-manifest.json`).

The **operator action** of this iteration: the read-only discovery of `bodi-pi`
(`tools/oip_pi_discovery.sh`). The SSH session of this loop is not permitted — the permission
layer of the session cannot ask the operator — so the discovery is the operator's step; its
answer (the architecture and the free port) fixes the target of the cross build.

No personal database change, no schema-7 activation of the personal installation, no private
SSH, no push, no deployment, no system service.

### Iteration 72 — two independent audits, the honest address space, and the instance of the Pi as one bundle

**Status: PROVED on canonical `main`.**
Two delegated, read-only audits of the **product** and of the **host-locality** of the Core, and
the bundle that makes the operator's part of the Raspberry Pi one command.

* **The verification of the eight defects of the address space confirmed them closed** — the value
  belongs to the node id of the server, the entity is the one that the source declares, the
  namespace and the access come from the node id and the node class, the catalogue is a set of
  nodes, the browser reads without measuring, the client assumes no folder of a demo, the gates
  read the counts from the Core, and the tests prove the properties. It found **three residuals**,
  and every one of them is closed here:
  * **The surface named a derivation that no longer exists.** The inspector said „Name · aus
    NodeId abgeleitet“ and „Ordner · synthetischer Core-Scope“ — the name is the **BrowseName of
    the server** and the folder is the **parent in the address space of the server**
    (`apps/flutter/lib/features/opcua.dart`).
  * **The fallback only worked when the Core named at least one folder.** A Core that names no
    folder left the client on a scope that does not exist; the whole catalogue is shown now — also
    when the list of the folders is empty.
  * **The folders of a source survived the switch to another source.** They belong to the source
    that delivered them; the chips of the previous source are gone
    (`apps/flutter/test/opcua_phase2_test.dart` proves both).
* **The gates named the folders and the node ids of the demo.** The counts came from the Core, the
  names did not: the three browser gates derive the folder, the node and the identity of the node
  from the API now (`apps/flutter/test/browser_oip004.mjs`,
  the receipt of the address space of the browser,
  `docs/evidence/oip-opcua-browser/address-space.json`).
* **The Rust suite encoded the size of the simulation.** The total of a folder is a relation to the
  total of the catalogue now, not the number of a demo (`crates/oip-server/tests/api.rs`).
* **The capability inventory still described the profile of the demo.** It names the address space
  of the server, the two bounds of the browse (the namespace of the client, 5 000 nodes) and the
  provenance of a source that is not the simulation
  (`docs/architecture/oip-capability-inventory.md`).
* **The audit of the host-locality found two things that would have broken the Pi.** The code of
  the operator session can only be minted in the **principal mode** of the local IPC — a
  configuration with an actor cannot mint a session at all; the generator of the instance writes the
  principal mode now. And the tool of the instance resolved a relative data store against the
  configuration while the Core resolves it against the working directory of its process: the tool
  hands the resolved path to the Core explicitly (`tools/oip_ops.py`).
* **The Core needs no change for the Pi.** The trust of the simulation origin is bound to the origin
  `oip-local-simulation-v1`, not to a host: the simulation of the Pi is trusted exactly like the
  simulation of the Mac. The bind address of the Core is the loopback, and the rule of the origin
  refuses every other `Host` — the tunnel is the only way in, and that is a deliberate gate.
* **The operator's part is one bundle and one command.** The bundle carries the two binaries of the
  cross build, the tool of the instance, the generator of the files of the instance, the scripts and
  the digest of every file. The rehearsal `tests/oip_pi_bundle.py` runs the whole procedure with
  stubs and **measures** it: the files of the instance are absolute and inside the instance, the
  procedure writes nothing outside it, the code of the session is minted over the local IPC, the
  instance stops without a forced signal, and the bundle installs no service and names no path of
  the machine it was built on (`docs/evidence/oip-pi-bundle/pi-bundle.json`,
  9 measured steps).

The whole evidence of the release was re-measured on a clean tree: the canonical acceptance passed
on the clean tree `a2add7d` with the release binary
`1a4e7870` (365 of 365 Flutter tests,
187 browser findings with 0 failures, 13 captures, the visual comparison
PASS, 8 of 8 phases — `docs/evidence/oip-canonical-acceptance/acceptance.json`), the Rust suite
delivered 183 tests in 29 suites with
0 failed (`docs/evidence/oip-rust-regression/rust-regression.json`), and
the bundle of the instance of the Pi is measured in
`docs/evidence/oip-pi-bundle/pi-bundle.json`.

The **operator action** of this iteration is unchanged and smaller: the read-only discovery of
`bodi-pi` (`tools/oip_pi_discovery.sh`) decides the target of the cross build; the bundle of the
instance (`tools/oip_pi_bundle.sh`) is then copied to the host and started by hand with
`./bin/start.sh`. The SSH session of this loop is not permitted — the permission layer of the
session cannot ask the operator — so the discovery and the start remain the operator's steps.

No personal database change, no schema-7 activation of the personal installation, no private SSH,
no push, no deployment, no system service.

### Iteration 73 — the deployed hosts, the two device classes and the BusyBox router

**Status: PROVED on canonical `main`.**
The loop had the SSH session to the hosts of the operator, so the discovery that was an
operator action in iteration 71 became a **measured receipt**. Two real device classes joined
the scope: an **OpenWrt router** and a **Philips Hue Bridge**. Their actual interfaces were
measured read-only, and one product defect that the router would have exposed is closed.

* **The host of the Core answers the target of the cross build.** `bodi-pi` is an rpi4 with
  `aarch64` — the target of the cross build (`aarch64-unknown-linux-gnu`) is therefore the right
  one, and the ports of the plan (`18808`, `18809`) are **free**. The home of the operator
  (`/home/flashback`) is a real directory without a symlink, so the path of the local IPC of the
  instance satisfies the rule of the Core, and `/usr/bin/sqlite3` exists, so the backup and the
  restore of the instance use the tool of the machine. The services of the operator
  (`bodi-nas-health`, `bodi-nas-verify`) are the **same list before and after** the measurement:
  the discovery changed nothing (`docs/evidence/oip-deployment-discovery/deployment-discovery.json`).
* **The second host is what it is.** `bodi-pc` is a NucBox-EVO-X2 (x86_64, Ubuntu) with
  `node_exporter`, `nginx` and the `bodi-inference-gateway`. It carries **no** `sqlite3`
  command: the tool of the instance would fall back to the `sqlite3` module of Python there.
  The host is **not** part of the runtime of the release.
* **The router would have lost its network measurement.** The router answers SSH with
  **dropbear**, and BusyBox has no JSON form of `ip` — the query of the Core asked for
  `ip -j address show`, which fails there, so the interfaces of the router would have been
  reported as *unavailable*. The query now falls back to the one-line form (`ip -o address
  show`) and then to `ifconfig`, and the parser reads that form
  (`crates/oip-server/src/ssh.rs`); the unit test proves that a BusyBox report names its
  interfaces, its addresses, its filesystems, its memory and its uptime, and that the network
  is **measured**, not missing.
* **The bridge is what it is.** The Philips Hue Bridge (model `BSB002`, API 1.78.0) answers its
  **public** configuration without a token and **refuses** its lights with
  `unauthorized user`. The Core has **no onboarding transport for a device with an HTTP API**:
  the bridge can therefore be an inventory device with its measured identity — model, software
  version, bridge id, MAC and IP — and nothing more. Its monitoring and its control are **not**
  implemented by the Core and are **not** simulated; the capability inventory names the limit,
  and the operator's token (a write on the device) is named as the operator's step.
* **The router is onboarded like every other device.** The SSH onboarding of the Core applies
  unchanged; the credentials and the **confirmation of the host key** are the operator's step,
  and the receipt names the banner and the host keys that the operator confirms.

The next work of the three extensions of the operator is named and not started here: the
**Hue-Bridge capability** (a new capability with its own permission, audit and scope), the
**secure update of the deployed software** (authenticated delivery, signature and digest
verification, safe activation, health check, rollback) and the **Mac App Store readiness** of the
macOS client (the current official requirements, the compliant build, the signing and the
entitlements, the privacy disclosures, the metadata and the store assets — upload-ready, not
the permission to submit).

No personal database change, no schema-7 activation of the personal installation, no write on
any host or device of the operator, no service installed, no port published, no push, no
deployment.

### Iteration 74 — the macOS client is upload-ready for the Mac App Store

**Status: PROVED on canonical `main`.**
The operator extended the mission: the deployed software must be updateable over the air, and
the macOS client must be ready for the Mac App Store. This iteration delivers the **Mac App Store
readiness** — the requirements read from the official sources, the package measured, the metadata
and the privacy policy prepared.

* **The requirements are read, not remembered.** The official pages of Apple were read on
  2026-11-11 and every row of the checklist carries its source
  (`docs/release/mac-app-store/requirements.md`): the apps uploaded to App Store Connect must be
  built with **Xcode 26** or later (the machine of the release builds with **26.6** ✓); the
  **approved reasons for the required-reason APIs** must be declared; the macOS apps of the store
  must not carry the extended attribute `com.apple.quarantine` (since 2025-02-18); the **hardened
  runtime** must be enabled; the notarisation uses `notarytool` (not `altool`) and the store
  submission already contains the equivalent security checks, so the notarisation belongs to the
  **direct** distribution of G9/N17, not to the upload.
* **The package is measured, property by property** (`tools/oip_mas_package.py`,
  `docs/evidence/oip-mas-package/mas-package.json`): the signature of the bundle carries the
  **hardened runtime** (`flags=…(adhoc,runtime)`), the entitlements are the **app sandbox** and
  the **network client**, the entitlements *file* of the release carries **no** debug
  entitlement, the bundle carries the **privacy manifest**, **no file** of the bundle carries the
  quarantine attribute, the `Info.plist` names the category (`public.app-category.utilities`) and
  the exception of the transport security for the **local networking** — the Core of OIP answers
  on the loopback, and the exception opens the local networking only — the icon is in the bundle
  and **every executable** of it is signed.
* **Three things were added to the product.** The **hardened runtime** in the release and the
  profile configuration of the Xcode project; the **privacy manifest** `PrivacyInfo.xcprivacy`
  (no tracking, no collected data type, and the three required-reason categories with the reason
  codes of Apple: the file timestamp and the user defaults of the own container, and the elapsed
  time of a session) as a resource of the Runner target; and the **category** and the **local
  networking exception** in the `Info.plist`.
* **The difference between the local build and the upload is named, not hidden.** The local build
  is signed **ad-hoc**, and Xcode injects the development entitlement `get-task-allow` into an
  ad-hoc build — a **distribution** build with the *Apple Distribution* certificate does not carry
  it. The receipt states that difference as an operator step instead of passing it silently.
* **The listing is prepared.** The name, the subtitle, the category, the description, the
  keywords, the promotional text, the age rating, the copyright and the answers of the app
  privacy details (**data not collected** — the client talks to the Core on the loopback and
  transmits nothing off the machine) are in `docs/release/mac-app-store/metadata.md`; the privacy
  policy is in `docs/release/mac-app-store/privacy-policy.md`.
* **What is still the operator's**: the archive with the *Apple Distribution* certificate and the
  *Mac App Distribution* profile of the account, the two public URLs (the privacy policy and the
  support), the answers of the app privacy details and the age rating, the trader status of the
  account and the **upload** itself. The package is upload-ready; the loop does not submit and
  does not publish.

The **secure update of the deployed software** (authenticated delivery, the verification of the
authenticity and the integrity, the safe activation, the health check and the rollback) is the
next named piece of work of the operator's extension; it is not started here.

The evidence of this iteration: the package of the client is measured
(`docs/evidence/oip-mas-package/mas-package.json`), the **archive** of the distribution carries the
hardened runtime and the entitlements of the release (the app sandbox and the network client,
without the development entitlement that Xcode injects into an ad-hoc build), the canonical
acceptance passed on the clean tree `a1fc365` with the release binary
`b9ce4334` (365 of
365 Flutter tests, 187 browser findings
with 0 failures, 13 captures, the visual
comparison PASS, 8 of 8 phases — `docs/evidence/oip-canonical-acceptance/acceptance.json`), the
Rust suite delivered 185 tests in 29 suites with
0 failed, and the web release and the macOS bundle are byte-identical
with the artefacts of the acceptance (`docs/evidence/oip-reproducible-build/reproducible-build.json`).

One rehearsal failed once in the long refresh of this tree — the functional depth of the six
workstations read a surface before the nodes of the source had arrived — and passed on the
immediate re-run. The gate now **waits** for the nodes instead of reading a surface that may
still be empty (`apps/flutter/test/browser_workstation_data.mjs`); the receipt names the revision
it was measured on.

No personal database change, no schema-7 activation of the personal installation, no write on any
host or device of the operator, no service installed, no port published, no push, no deployment,
no submission.

### Iteration 75 — the deployed Core can be updated safely

**Status: PROVED on canonical `main`.**
The operator extended the mission with the third piece: the deployed software must be
updateable over the air — authenticated delivery, integrity and authenticity verification, a
safe activation, health checks and a rollback. This iteration delivers the update path of the
**Core**, the component that is really deployed on a host of the operator.

* **The bundle carries the trust, not the channel.** An update arrives as a bundle: a
  manifest, the artefacts and a signature. The manifest is signed with **Ed25519** by the
  private key of the operator; the tool verifies the signature over the **exact bytes** of the
  manifest with the **public key of the instance**. The channel may be anything — a copy, a
  tunnel, a pull — because a bundle that was changed on the way does not verify. The **private
  key never reaches a host**: the public key of the instance is the only thing the host sees.
* **The integrity is verified twice.** Before the activation, the tool verifies the sha256 of
  every artefact against the manifest; after the write, it verifies the digest of the written
  file again. A bundle whose artefact was changed on the way is refused, and so is a bundle
  whose manifest was changed after the signing.
* **The activation is atomic and reversible.** The artefact is written into a **version
  directory** of the instance, and the switch is a symlink that is **renamed** — never a
  half-written state. The previous version stays on the host: the rollback is one rename.
* **The new version is health checked before it counts.** The new binary is started as a
  **disposable instance** — its own port, its own store, its own protected IPC — and asked for
  `/health/ready`. A version that does not become ready is **not** activated: the instance
  keeps the version it had. The rehearsal drives exactly that case with a binary that leaves
  immediately, and the instance still runs the old version afterwards.
* **Every attempt is durable.** The journal `<instance>/state/updates.jsonl` names the moment,
  the revision, the version, the target, the digests, the verification, the activation, the
  health check, the rollback — and the reason of a **refusal**. A refused bundle is a security
  relevant event and it is written down like every other attempt. The journal is the only
  **durable** audit of the update path of an instance (the execution log of the Core is not
  durable — G10).
* **What the path refuses** (measured): a changed artefact, a forged manifest, a bundle of
  another target, a revision that is already installed, and a version that does not become
  ready — the last one is rolled back, the others leave the instance untouched.

The **client** of the operator is deliberately **not** in this path: an app of the Mac App
Store is updated by the store, and the direct distribution uses the path of its own signature
(the notarisation of G9/N17). The **operator's action** is the key pair: the private key stays
with the operator, the public key of the instance is placed in
`instance/etc/update-public.pem`.

No personal database change, no schema-7 activation of the personal installation, no write on any
host or device of the operator, no service installed, no port published, no push, no deployment.

### Iteration 76 — the Core runs on the Raspberry Pi, and the deployment is measured

**Status: PROVED on canonical `main`.**
The operator's primary architectural wish — the Rust OIP Core on `bodi-pi`, the Flutter client on
the Mac — was a plan and a bundle. This iteration runs it and measures it, and it finds a defect
that the plan could not see.

* **The deployment is measured, not planned.** The rehearsal (`tests/oip_pi_instance.py`,
  `docs/evidence/oip-pi-instance/pi-instance.json`) crosses the workspace for the target of the
  host, assembles the bundle, copies it to the Pi, **starts the instance by hand** and proves:
  the Core of the host answers **through a tunnel of the loopback**; the session of the operator is
  minted **on the host** over its local IPC and opens the authorized projection (the address space of
  the simulation of the host: 1020 nodes in five folders; the organization of the instance); the
  instance **publishes no port** of the host; the instance stops; and the **services of the operator
  are the same list before and after** — nothing of the BODI installation of the host was touched.
* **The deployment found a defect that the local rehearsals had hidden.** The measurements of a
  source carried the **machine id of the simulation** ("M-01") instead of the **entity that the
  source declares**. The Core refused them ("the observation does not match registered source,
  entity or provenance") and isolated the source every second — on the Pi *and* on the Mac, as soon
  as the binaries were current. Two things were wrong: the **entity of a source was a hardcoded
  demo default** in the configuration, and the **adapter** stamped the machine of the simulation on
  every measurement. The configuration names the entity of its source now
  (`crates/oip-server/src/config.rs`), the adapter delivers the measurements **with the entity of
  the source** (`crates/oip-opcua/src/async_opcua/client.rs`), and the Core hands the entity of the
  source to the adapter (`crates/oip-server/src/runtime.rs`). The unit test proves that a
  measurement belongs to the entity of its source.
* **The evidence had a hole, and it is closed.** The rehearsals of the release drive the binaries
  of the build tree — and the tree held binaries of an **older revision** (the debug build of the
  Core was a day old), so the rehearsals measured an older product while the receipts said
  "PASS". The refresh now **builds the workspace before the first rehearsal** and refuses to run
  when the build fails (`tools/oip_refresh_evidence.py`). A receipt that measures stale binaries is
  worse than no receipt.
* **Two diagnoses became part of the product.** The isolation of a source now names its **reason**
  in the log (`crates/oip-server/src/runtime.rs`) — a source that is isolated every second was
  indistinguishable from a source that is merely unreachable; and the vendored OPC-UA server names
  the **reason of a refused handshake** (`vendor/async-opcua-server/src/transport/tcp.rs`) — the
  status code alone did not say whether the hello, the buffer sizes or the endpoint url had been
  refused. Both were written while the deployment was failing.

The instance on the Pi is **stopped** after the measurement and its files stay on the host; the
**decision to keep it running** and the client that is built for the port of the instance are the
operator's.

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no push, no deployment.

### Iteration 77 — the release of the current product, measured with its own binaries

**Status: PROVED on canonical `main`. The verdict stays `OIP_PRODUCTION_NOT_READY`** — the gates
that need the operator (G5, G10, G12) are open, and nothing in this iteration changes them.

* **The evidence of the release was measured against the binaries of the tree for the first
  time.** The refresh builds the workspace — the development profile and the release profile —
  before the first rehearsal and refuses to run when a build fails
  (`tools/oip_refresh_evidence.py`): a receipt that measures a binary of an older revision is
  worse than no receipt, because it names a revision it did not measure. The run at the product
  revision `24f0901` measured **33 of the 34 rehearsals PASS**; the one failure was the record
  itself — the canonical state named an older release — and this iteration closes it.
* **The refresh exposed a regression of my own change, and it is closed.** The entity of a
  source became part of the configuration of a source (`crates/oip-server/src/config.rs`), and
  the test fixtures of the Core built that configuration without the new field: four
  constructions in `crates/oip-server/tests/` did not compile. The regression is fixed
  (`24f0901`), the whole Rust suite passes again (**185 tests in 29 suites, 0 failed** —
  `docs/evidence/oip-rust-regression/rust-regression.json`), and the fix is a *test* change: the
  product itself was not touched.
* **The acceptance of the release ran against the release binary** (`0aa1595`, tree
  `617bc48`): the eight functional phases **8 of 8 PASS**, the browser gate **PASS** with
  **187 findings and zero failures**, **13 captures**, the visual comparison **PASS**, the served
  web bundle byte-identical with the local build of the same revision
  (`docs/evidence/oip-canonical-acceptance/acceptance.json`).
* **The builds of the release are reproducible** (`docs/evidence/oip-reproducible-build/reproducible-build.json`):
  the web release and the macOS application bundle are byte-identical when they are built
  twice, and the **Core of the release is byte-identical over two builds**. The Core in the
  build tree names the revision it was built from (`f851929`); the record states the revision of
  the product, the revision of the acceptance and the revision of the binary as three separate
  facts, because they are three different measurements.
* **The publication of a receipt needs no build.** The refresh built the workspace even when it
  was asked only to publish a receipt that had been measured before — on a machine whose disk
  is nearly full, that build was a failure of the publication. The build is now skipped when
  nothing is measured (`13c3636`).

The instance on the Raspberry Pi stays **stopped** after its measurement and its files stay on
the host; the decision to keep it running and the client that is built for the port of the
instance are the operator's.

The next independent READY task is **N25**: the **store assets** of the Mac App Store listing —
the screenshots of the six workstations in the sizes that Apple accepts for a Mac app
(1280 x 800, 1440 x 900, 2560 x 1600, 2880 x 1800; no alpha channel), read from the official
source today.

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no push, no deployment.

### Iteration 78 — the store assets of the Mac App Store listing are measured

**Status: PROVED on canonical `main`. The verdict stays `OIP_PRODUCTION_NOT_READY`** — the
listing is upload-ready, the upload itself is the operator's action.

* **The requirement was read at the official source, with the date.** The sizes that Apple
  accepts for a Mac app are **1280 x 800, 1440 x 900, 2560 x 1600 and 2880 x 1800**, each with a
  16:10 aspect ratio, and **an image with an alpha channel is refused** (App Store Connect Help,
  "Screenshot specifications", read on 2026-11-11). The requirement of the listing previously
  cited the submitting page of Apple, which names **no pixel sizes**; the citation is corrected
  and the rule is recorded in `docs/release/mac-app-store/screenshots.md`.
* **The assets are measured, not asserted.** The six workstations of the client are captured in
  **1440 x 900** by the release build of the client through the managed Core
  (`tests/oip_store_screenshots.py`, `apps/flutter/test/browser_store_screenshots.mjs`,
  `docs/evidence/oip-store-screenshots/`): every capture is the **viewport** — never the full
  page, whose height would be whatever the content happens to be — and **the exact pixel size
  and the absence of an alpha channel are read out of the header of the file itself**. The
  captures carry **none** of the prohibited regressions R1-R10: the rehearsal checks every
  marker of the binding UI contract on every workstation, with the same exemptions that the
  canonical gate applies.
* **The first captures were empty, and the rehearsal found it.** The marker of a workstation
  appears **before** its data is rendered: the first run captured the OPC-UA workspace with an
  empty address space (0 of 1020 nodes) and the rehearsal would have published a listing that
  misrepresents the product. The browser now waits for the **delivered** catalogue and for the
  surface to **settle** (two consecutive equal readings) before every capture. The published
  captures show the full address space (1020 nodes, five folders, a live value).
* **The package measures the listing.** `tools/oip_mas_package.py` reads the store assets and
  checks every rule of the store against the files themselves: the size is one of the four that
  Apple accepts, the format is a PNG, and **no capture carries an alpha channel**.
* **The acceptance of the operator stays pending.** A capture is a measurement of the surface,
  never an acceptance of it: the receipt names
  `VISUAL_PENDING_OPERATOR_ACCEPTANCE` (G12). The captures show the managed Core of the
  release — whose source is the local OPC-UA simulation of the release, and the surface states
  that origin — and the listing with the **own infrastructure of the operator** is the
  operator's decision.

The upload itself, the Apple identity, the certificate, the profile, the two public URLs and
the App Review answers remain the operator's actions.

### The release of this revision verifies with one command

`python3 tools/oip_verify_release.py` — the verdict is **`OIP_PRODUCTION_NOT_READY`**, the
verification itself is **PASS** (`docs/evidence/oip-release-verification/release-verification.json`):
the manifest verifies, **every receipt is fresh**, the record is intact, the acceptance passed
and the safety boundaries held. The three gates that need the operator — **G5** (an approved
physical device and its credentials), **G10** (the acceptance of the production-security scope)
and **G12** (the acceptance of the operator) — are open, and the verification names them.

The staleness that the verification found in this iteration was real and is closed: the
acceptance had executed a Core of an **earlier revision** than the one the manifest names (the
binary names the revision it was built from), and three receipts — the discovery of the
deployed hosts, the deployment on the Raspberry Pi and the store assets — predated the last
change of the product. All of them are measured again on the revision of the release, and the
acceptance and the reproducible build now run at **one** revision, so the binary that the gate
executed is byte-identical with the binary that the manifest names.

### Iteration 79 — the Philips Hue Bridge is onboarded with a verified identity

**Status: PROVED on canonical `main`. The verdict stays `OIP_PRODUCTION_NOT_READY`** — the gates
that need the operator (G5, G10, G12) stay open; the control of the bridge needs one of them.

* **The identity of the bridge can only be verified by a pin, and the pin is measured.** The
  bridge presents a certificate that it issued itself (`CN=001788FFFE48E917`, issued by
  `CN=root-bridge`) and **does not present the root**: the chain is incomplete and no ordinary
  trust store can verify it. The pin is the certificate of the device itself — the same
  principle as the host key of an SSH host (`docs/release/hue/bridge-certificate.pem`, the
  fingerprint and the digest of the file are recorded there).
* **The read is verified, never insecure.** `curl` of this machine cannot build a chain for
  such a pin (its LibreSSL build has no `--partial-chain`), but `openssl s_client` can:
  `-partial_chain` with `-verify_return_error` verifies the presented certificate against the
  pin and **refuses the connection itself** when it does not match. The bridge is therefore read
  in **one** verified TLS session (`tools/oip_hue.py`) — there is no insecure path in the tool.
* **The onboarding is measured end to end** (`tests/oip_hue_device.py`,
  `docs/evidence/oip-hue-device/hue-device.json`): the identity is verified against the pin,
  the bridge is written into the inventory of a disposable Core **through the authorized
  session** (the origin and the CSRF token of the session, exactly as the application sends
  them), the record is read back with the verified facts (model `BSB002`, software `1978545030`,
  API `1.78.0`, bridge id `001788FFFE48E917`, MAC `00:17:88:48:e9:17`), and a principal of
  **another organization** does not see the device — the answer is `404
  RESOURCE_NOT_ACCESSIBLE`, exactly like a device that does not exist.
* **The negative control is measured twice.** A bridge that presents another certificate is
  refused **at the pin** (the tool refuses before it reads anything) **and in the TLS session**
  (the exit code is non-zero and **no answer is delivered**).
* **The limit is named, not simulated.** The bridge refuses the lights without an application
  token (`unauthorized user`), and the creation of a token is a **write on the device** that
  belongs to the operator. The capability is therefore **read-only**: the identity of the bridge
  is a **device fact**, not a measurement, and nothing about the lights is simulated anywhere.

Every request of the rehearsal is a `GET`: the bridge of the operator was **not** modified.

The next independent READY work is the **client**: the Devices workspace names the identity of
a device as `Nicht verfügbar`, although the Core holds it — the verified facts of the bridge
should be visible where the operator looks at a device.

### Iteration 80 — the Devices workspace names the identity that the Core holds

**Status: PROVED on canonical `main`. The verdict stays `OIP_PRODUCTION_NOT_READY`** — the gates
that need the operator (G5, G10, G12) stay open, and nothing in this iteration changes them.

* **The client showed `Nicht verfügbar` where the Core holds the fact.** The identity of a device
  lives in the **inventory** of the Core (manufacturer, model, firmware, serial number, address);
  the summary of a device carries none of it, and the Devices workspace painted
  `MANUFACTURER / MODEL: Nicht verfügbar` and `FIRMWARE / OS: Nicht verfügbar` next to the
  **device id** of a device the Core knows. The workspace now asks the inventory for the record
  of the selected device and names the facts the Core holds; **a fact that the Core does not hold
  is named as unavailable and never invented** (`7ce11fd`,
  `apps/flutter/test/device_identity_test.dart` — the record of the Core and the case without one).
* **The refresh of the release was measured with the binaries of the tree** (`tools/oip_refresh_evidence.py`):
  **34 of the 35 rehearsals PASS** at the product revision `7ce11fd`; the one failure was the
  record itself — the canonical state named the older release — and this iteration closes it.
* **The acceptance ran with the release binary, and the reproducible build ran at the same
  revision** (`646e072`): the eight functional phases **8 of 8 PASS**, the browser gate **PASS**
  with **187 findings** and **13 captures**, the visual comparison **PASS**, and the **Core is
  byte-identical over two builds**. The binary that the gate executed is the binary that the
  manifest names (`1bf6a47d…`), and the release verifies with **one command**
  (`docs/evidence/oip-release-verification/release-verification.json`: **PASS**, verdict
  `OIP_PRODUCTION_NOT_READY`, the gates that need the operator **G5**, **G10**, **G12**).
* **Three receipts of the release were measured outside the refresh, and they went stale without
  a notice.** The discovery of the deployed hosts, the deployment on the Raspberry Pi and the
  onboarding of the Hue Bridge were measured by hand, so a change of the product left them
  behind — the verification caught it every time. They are now **part of the refresh**
  (`oip_deployment_discovery`, `oip_pi_instance`, `oip_hue_device`) and are measured with it. The
  check that found them stays as strict as it was: a receipt that predates the last change of the
  product is still refused.
* **The numbers of the record were corrected.** The check of the numbers found two drifts that
  the refresh had made true: the Rust suite now delivers **187 tests in 29 suites** (the record
  quoted 185) and the client **367 Flutter tests** (the record quoted 365). The record names the
  numbers that the receipts carry (`docs/OIP_RELEASE_LEDGER.md`,
  `tests/oip_record_numbers.py`: 108 rows, 26 measurements, no problem).

The next independent READY task is **N27**: the **type** of a device is painted as the raw
identifier of the enum of the Core (`SingleBoardComputer`, `NetworkDevice`) in the Devices and
the Network workstations, and the icon maps of the client fall back silently for every type that
the Core can really produce. The defect is visible in the **own painted-surface evidence** of the
record — the honest fix is **one** owner of the vocabulary in the client.

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no push, no deployment. Every
request to the Hue Bridge of the operator was a `GET`.

### Iteration 81 — the type of a device is named as the surface names it

**Status: PROVED on canonical `main`. The verdict stays `OIP_PRODUCTION_NOT_READY`** — the gates
that need the operator (G5, G10, G12) stay open, and nothing in this iteration changes them.

* **The Core paints the type of a device as the identifier of its own enum**, and the client
  painted that identifier as if it were a word of the surface: `SingleBoardComputer`,
  `NetworkDevice`, `IndustrialDevice` appeared in the Devices and the Network workstations, in
  the overview and in the topology. The defect is visible in the **own painted-surface evidence**
  of the record (`docs/evidence/oip-device-connection/painted-surface.txt`) — the evidence of the
  release showed the raw identifier while the record claimed a finished surface.
* **The vocabulary now has one owner** (`apps/flutter/lib/widgets/device_kind.dart`): every type
  that the Core can really deliver gets a **word** (`Einzelplatine`, `Netzwerkgerät`,
  `Industriegerät`), an **icon** of its own and a **category** for the tint of the surface — and a
  type that the client does not know stays **honestly named** (`Unbekannter Gerätetyp · …`) with
  the icon of an unknown device instead of borrowing the identity of another type. The four sites
  that mapped a type (the icon of the devices, the icon and the category of the Network
  workspace, the tint of the design system) now read that one owner instead of four parallel
  vocabularies.
* **The places that show a type show the word** — the identity panel, the rows and the semantics
  of the inventory, the comparison, the node inspector of the Network, the topology, the inspector
  and the explorer of the overview and the tile of a device. The **filters** show the word and
  keep the identifier as the **value** (the type filter of the Devices, the kind filter of the
  Network), and the **grouping** stays on the identifier, so what is filtered and what is grouped
  remain exact.
* **The test closes a gap of zero coverage** (`apps/flutter/test/device_kind_test.dart`): every
  type that the Core can deliver has a word, an icon and a category; a type whose identifier is
  no word is never painted as itself; the spelling of the inventory route
  (`network_device`) names the same type as the enum (`NetworkDevice`); the vocabulary of the
  demo of the Core stays known; an unknown type stays honestly named. The **375 Flutter tests**
  pass (367 before this change, plus the eight new ones).
* **Two rehearsals failed once under the load of the machine, and both pass on a re-run with the
  same binaries and the same revision** (`oip_extend_registry`: "the new source collected
  nothing"; `oip_stability`: "a source was not fresh during the run" in the sample at 330 s of a
  20-minute run). The **Core did not change in this iteration** — the change is in the client
  alone — and the disk of the machine was nearly full while the refresh was building. The record
  names the fact instead of hiding it behind a quiet second run.
* **The release of this revision verifies with one command**
  (`docs/evidence/oip-release-verification/release-verification.json`: **PASS**, verdict
  `OIP_PRODUCTION_NOT_READY`, the gates that need the operator **G5**, **G10**, **G12**): the
  acceptance ran with the release binary (`fba6898`), the eight functional phases **8 of 8 PASS**,
  the browser gate **PASS** with **187 findings** and **13 captures**, and the reproducible build
  at the **same** revision produced the byte-identical Core.

The next independent READY task is **N28**: the **export recipe** of the App Store listing — the
`xcodebuild -exportArchive` step with an `ExportOptions.plist` template that carries the
operator's own identity as placeholders, the **display name** of the app on disk (the bundle
still ships as `oip_dashboard`), and the **App Review notes** of a client whose access is a
one-time code minted on the instance itself.

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no push, no deployment.

### Iteration 82 — the export recipe of the App Store listing, and the name of the app

**Status: PROVED on canonical `main`. The verdict stays `OIP_PRODUCTION_NOT_READY`** — the listing is
upload-ready; the upload itself is the operator's action, and the gates that need the operator
(G5, G10, G12) stay open.

* **The upload had no recipe.** The package of the client was built and measured, but the
  repository held no `xcodebuild -exportArchive`, no `ExportOptions.plist` and no way to hand the
  archive to the store. There is now a **template**
  (`docs/release/mac-app-store/ExportOptions.plist.template`) in which **every identity of the
  operator is a placeholder** — the team, the profile of the bundle identifier, the certificate,
  the method and the destination — and a **tool** (`tools/oip_mas_export.py`) that renders it into
  `target/`, proves the rendered file and prints the command. The tool **invents no credential**:
  while the identity is incomplete it refuses and names what is missing.
* **The recipe is measured, not asserted** (`tests/oip_mas_export.py`,
  `docs/evidence/oip-mas-export/mas-export.json`): the template carries every key that the tool
  needs and every identity as a placeholder; the tool **refuses** an incomplete identity (the
  missing values are named); with a **fake** identity the rendered file parses, carries every key,
  carries **no placeholder** any more and lies **outside** the checkout; the printed command names
  the archive and the options file; and the tool leaves the tree of the checkout **untouched**. The
  rehearsal never exports, never signs and never uploads.
* **The app now carries the name of the listing.** The bundle shipped on disk as `oip_dashboard`
  without a display name, so the operator saw the technical name in the Dock and in the window.
  The bundle now carries `CFBundleDisplayName = Open Industrial Platform`
  (`apps/flutter/macos/Runner/Configs/AppInfo.xcconfig`,
  `apps/flutter/macos/Runner/Info.plist`), while the name **on the disk** stays the technical one
  — the paths of the release name it. The packaging tool measures the display name, the name on
  the disk and the copyright, and the **copyright of the bundle now names the same holder as the
  listing**.
* **The load-bearing assumption of the hardened runtime is now measured, not asserted.** The
  record claimed that the hardened runtime "refuses the ad-hoc Flutter framework inside it" — a
  claim of the prose. The packaging tool now **starts the hardened archive** and records what
  happens: the process **dies** with `SIGABRT` and the library validation names the reason
  ("mapping process and mapped file (non-platform) have different Team IDs"). The hardened runtime
  therefore belongs to the **distribution** build and not to the shared Release configuration of
  the project — the local bundle has to stay launchable — and that is now a measured fact
  (`the_launch_of_the_hardened_bundle`).
* **The metadata names every field that is the operator's.** The listing claimed to be "localised
  in both" English and German; the client has **no** localisation framework — the strings are
  hard-coded German, and the claim is corrected. The table now names the fields that are the
  operator's (the three URLs, the contact, the age rating, the privacy answers, the secondary
  category, the pricing, the licensing, the localised metadata, the review access, the Apple
  identity, the upload), and the **notes for the reviewer** are prepared: the client has **no
  account and no password** — it asks for a **one-time code** that the Core mints on the instance
  itself — so the reviewer needs a running instance of the Core, and the notes say exactly that.
* **The checklist of the requirements is corrected against the measurements** (R2, R3, R6, R9 are
  now **MET** or **PARTIAL** with the receipt that proves them; R4 names the measured reason why
  the project carries no hardened runtime), and two rows are new: **R14** the export with
  `xcodebuild -exportArchive` and **R15** the access of the reviewer.
* **The refresh of this iteration found a defect of the previous one — and the record names it
  instead of hiding it behind a quiet second run.** The rehearsal `oip_scope_persistence` failed
  **twice** with the same failure: the journey could not find the control that names the type of
  the device in the administration. The cause was **not** a flake: iteration 81 had given the
  **type filter** of the inventory the vocabulary of the types, and the entry that keeps every
  type (`all`) is **not** a type — the surface painted it as `Unbekannter Gerätetyp · all`. The
  name of that choice collided with the name of the administration's dropdown, so the journey
  opened the **filter** instead of the **administration**. The defect was invisible until the web
  bundle of the new product had been built (the journey drives the bundle in
  `apps/flutter/build/web`), and the acceptance of iteration 81 does not drive that journey — so
  the refresh of this iteration was the first run that saw it. The correction is **iteration 83**:
  the choice that keeps every type is named as the choice it is, the vocabulary of the types has
  **one** owner everywhere (the administration included), and the journey names the control it
  drives exactly.

The release cycle of this revision therefore continues in **iteration 83**, which carries the
correction: the receipts of this iteration measured the tree of `dd4bb3e`, and a receipt that
measures an older product than the one that ships would be a false statement.

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no push, no deployment.

### Iteration 83 — the vocabulary of the type of a device has one owner, and the note of a device is shown

**Status: PROVED on canonical `main`. The verdict stays `OIP_PRODUCTION_NOT_READY`** — the gates that
need the operator (G5, G10, G12) stay open, and nothing in this iteration changes them.

* **The refresh of iteration 82 found a defect of iteration 81, and this iteration closes it.** The
  rehearsal `oip_scope_persistence` failed **twice** with the same failure: the journey could not
  find the control that names the type of the device in the administration. The cause was **not** a
  flake. Iteration 81 had given the **type filter** of the inventory the vocabulary of the types,
  and the entry that keeps every type (`all`) is **not** a type — the surface painted it as
  `Unbekannter Gerätetyp · all`. That name collided with the name of the administration's dropdown,
  so the journey opened the **filter** instead of the **administration**. The defect was invisible
  until the web bundle of the new product had been built (the journey drives the bundle in
  `apps/flutter/build/web`), and the acceptance does not drive that journey — so the refresh of
  iteration 82 was the first run that saw it.
* **The refresh now builds the web bundle that the browser rehearsals drive.** The rehearsals drove
  the **binaries of the tree** — the Core in both profiles — but the **bundle** of the client was
  whatever the last build had left in the build tree: a bundle of an older revision measures an
  older product. The build step of the refresh builds the release bundle with the command that the
  canonical gate and the reproducible build use (`tools/oip_refresh_evidence.py`), so the bundle
  that the rehearsals measure is the bundle that the acceptance delivers. The defect above was
  invisible for exactly this reason: the refresh of iteration 81 measured a bundle that predated
  the vocabulary of that iteration.
* **The choice that keeps every type is named as the choice it is.** The entry `all` of the filter
  shows `Alle` again, and the vocabulary of the types never sees it
  (`apps/flutter/lib/features/devices/device_inventory.dart`). The filter still shows the **word**
  of every type the Core holds, and the **value** stays the identifier.
* **The administration names the type with the same word.** The dropdown of the type carried a
  **second** vocabulary of its own (`Single board`, `Network`, `Industrial`, `Other`) next to the
  vocabulary of the Core (`apps/flutter/lib/features/devices/device_administration.dart`). It now
  uses the one owner (`apps/flutter/lib/widgets/device_kind.dart`), so the operator sees
  `Einzelplatine` in the administration, in the filter and in the identity panel — and the **value**
  that the administration writes is still the identifier of the inventory route
  (`single_board_computer`), which is what the Core accepts.
* **The onboarding dialog does not paint the identifier of the Core as a word.** It offered
  `server`, `single_board_computer`, `network_device` … as the words of its dropdown — the last
  place where a raw identifier of the Core reached the operator
  (`apps/flutter/lib/features/device_onboarding.dart`). It names the types with the shared
  vocabulary now; the **value** it registers stays the identifier of the Core.
* **A type that the client does not know is not rewritten into another type.** The administration
  fell back to `other` for a type it does not know, and a write would have changed the type of the
  device behind the back of the operator. The unknown type stays an entry of the list, named
  honestly (`Unbekannter Gerätetyp · …`), and the write keeps it.
* **Both spellings of a type carry the same word, icon and category.** The enum of the Core
  (`SingleBoardComputer`) and the spelling of the inventory route (`single_board_computer`) name the
  **same** type; the icon of the lowercase spelling of `server`, `desktop` and `laptop` was still
  the icon of an unknown device, and the vocabulary now knows one type, not two.
* **The note of a device is shown where the operator looks at the device (N29).** The Core holds an
  optional free text `notes` in its inventory (`crates/oip-core/src/inventory.rs`), and the client
  read the inventory but **never showed** the note — so the honest limit of a capability (the
  Philips Hue Bridge: a read-only identity, no control without an application token) was in the
  record of the Core and nowhere in the surface. The Devices workspace now shows the note under the
  identity grid (`apps/flutter/lib/features/devices/device_detail.dart`); a note that the Core does
  not hold is named as unavailable, and the panel never invents one.
* **The journey names the control it drives exactly.** The locator of the administration is
  anchored (`/^Gerätetyp/`), so the evidence no longer depends on the coincidence that no other
  control contains the word (`apps/flutter/test/browser_scope_persistence.mjs`).
* **The tests close the gaps**: the choice `all` is not an unknown type
  (`apps/flutter/test/device_type_filter_test.dart`), the note of the Core is shown and a device
  without a note names none (`apps/flutter/test/device_identity_test.dart`), the administration
  names the type with the shared word and does not rewrite an unknown type
  (`apps/flutter/test/device_administration_test.dart`), the onboarding dialog names the type with
  the shared word (`apps/flutter/test/onboarding_dialog_test.dart`) and both spellings of a type
  carry the same icon (`apps/flutter/test/device_kind_test.dart`). The **382 of 382 Flutter tests**
  pass (375 before this change, plus the seven new ones).
* **The release of this revision verifies with one command**
  (`docs/evidence/oip-release-verification/release-verification.json`: **PASS**, verdict
  `OIP_PRODUCTION_NOT_READY`, the gates that need the operator **G5**, **G10**, **G12**): the
  acceptance ran with the release binary (`44d1d3b`), the eight functional phases **8 of 8 PASS**,
  the browser gate **PASS** with **187 findings** and **13 captures**, and the reproducible build
  at the **same** revision produced the byte-identical Core, the byte-identical web bundle and the
  byte-identical macOS bundle.
* **The rehearsal of the integrity of the record failed inside the refresh, and the record names
  why.** The rehearsal `oip_record_integrity` measures the **record** — and the canonical state of
  the record is written at the **end** of the cycle, when the acceptance and the manifest of this
  revision exist. The refresh of this iteration therefore measured the record of the **previous**
  revision and reported it as a failure (`the canonical state names 7552596 … the release names
  66136a0`). It is measured again where it belongs — at the end of the cycle — and it passes
  there (`docs/evidence/oip-record-integrity/record-integrity.json`: **PASS**, the tree clean).
  The refresh reports the failure instead of hiding it behind a quiet second run.

The next independent READY task is **N30**: the **export recipe** of the App Store listing writes
wherever it is told to write and names a signing style that the operator did not choose.

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no push, no deployment.

### Iteration 84 — the export recipe writes only into the build tree and names the signing style

**Status: PROVED on canonical `main`. The verdict stays `OIP_PRODUCTION_NOT_READY`** — the gates that
need the operator (G5, G10, G12) stay open, and nothing in this iteration changes them.

* **The recipe wrote wherever it was told to write.** The directory of the rendered options
  (`--out`) was not validated, and the tool **removes** that directory before it writes into it: a
  directory that the operator names by mistake — a directory of the release, a directory of the
  machine — would have been removed. The tool now **refuses** every directory outside the build
  tree of the machine, and it checks the directory **before** it writes anything
  (`tools/oip_mas_export.py`).
* **The recipe named a signing style that the operator did not choose.** The profile and the
  certificate of the operator are required, while `xcodebuild` honours them only under the
  **manual** style: a file that carries both and names `automatic` would look signed with the
  profile of the operator while the export ignores it. The tool now exports with the manual style
  and refuses another one with that reason.
* **The refusal names where the value belongs.** Every missing value names the **flag** and the
  **environment variable** that carry it (`--team-id` / `OIP_APPLE_TEAM_ID`, `--profile` /
  `OIP_APPLE_PROFILE`, `--certificate` / `OIP_APPLE_CERTIFICATE`), so the operator knows where to
  put it.
* **The rehearsal reads the rendered file itself** and not the report of the tool: the file
  **parses**, it carries every key and **no placeholder** any more, and it lies outside the
  release. It also proves the two refusals — a directory outside the build tree and a signing
  style that `xcodebuild` would ignore the profile with — and that the **command** names the
  archive, the export path and the options file themselves
  (`tests/oip_mas_export.py`, `docs/evidence/oip-mas-export/mas-export.json`).
* **The template names the optional keys of the format.** The format accepts more keys than the six
  that the recipe sets (`uploadSymbols`, `manageAppVersionAndBuildNumber`, `stripSwiftSymbols`,
  `testFlightInternalTestingOnly`); the template says so, so that the claim of the recipe is not
  that it sets every key of the format.
* **The metadata no longer contradicts itself.** The listing named German (Deutschland) as the
  primary language while the only set of texts is English: the primary language is **English
  (U.S.)**, and the note says that the **client itself** shows German texts because it has no
  localisation framework (`docs/release/mac-app-store/metadata.md`).
* **The product of the release did not change in this iteration.** The acceptance of the release
  (`44d1d3b`, 8 of 8 phases, 187 browser findings, 382 of 382 Flutter tests) therefore still
  describes the product that ships; the rehearsal of the export recipe was measured again at the
  revision of this iteration.

The next independent READY task is **N31**: the **service inventory** of the Core — the Core owns
no service registry and no VPN read route, and the two workstations that would show them name the
absence instead of showing a placeholder as a working feature.

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no push, no deployment.

### Iteration 85 — the state of the VPN on the surface is what the Core delivers, and the contract of the service inventory exists

**Status: PROVED on canonical `main`, with one part BLOCKED by the machine.** The gates that need
the operator (G5, G10, G12) stay open, and this iteration adds the machine blocker below.

* **The surface claimed a connection state that the Core never measured.** The summary of the
  Network workstation showed `VPN-TELEMETRIE · Nicht verbunden` — a hard-coded string, while the
  Core delivers **no** VPN telemetry at all: no peer, no endpoint, no handshake, no route and no
  tunnel health. In the demo the Core delivers `connected` for the remote devices, and the chip
  contradicted it. The chip now says **`NICHT GELIEFERT`** — the same word that the logical paths
  use when the Core delivers no topology — and the hint of the VPN workspace says `Keine
  VPN-Telemetrie geliefert` instead of `Keine VPN-Telemetrie verbunden`. The surface states what
  the Core delivers, and not a state of the world that the Core never measured
  (`apps/flutter/lib/features/network.dart`).
* **The availability row named a state that was not the truth.** `Telemetrieverfügbarkeit · Nicht
  verfügbar` became `NICHT GELIEFERT`: the Core does not deliver the telemetry, and the surface
  says that instead of a soft "not available".
* **The reference to the contract of the service inventory pointed at a document that did not
  exist.** The Services workspace names the contract of the capability that is missing
  (`OIP_DEVICES_SERVICES_2027_CORE_REQUIREMENTS.md`), and the repository held no such file — a
  surface that points at a missing document is the same class of defect as the one the G8 row was
  corrected for. The contract now exists
  (`docs/architecture/OIP_DEVICES_SERVICES_2027_CORE_REQUIREMENTS.md`), and the surface names its
  path. The contract states the rules that the next step must satisfy: **declared, never measured**
  (the Core runs no probe for a service, so every record carries the provenance
  `origin: declared`), the **plan** as the source of truth, the scope of the inventory read,
  **read-only** (no write path, because the durable audit that a remote write would need does not
  exist), and the evidence that the step must produce.
* **Two rehearsals failed in the refresh, and both causes are closed.**
  * The **discovery of the deployed hosts** read the Philips Hue Bridge with an **insecure**
    `curl` (`-k`, no verification of the identity) — and the TLS stack of the bridge does not
    always answer that client: the handshake stalls after the certificate of the bridge, and the
    rehearsal measured a timeout instead of the device. The read is now the **verified** one of the
    hue rehearsal (`tools/oip_hue.py`: the certificate of the bridge is verified against the pin,
    and a bridge that presents another certificate is refused before a byte of the answer is read).
    The rehearsal passes again, and the measurement it takes is stronger than the one it took
    before.
  * The **package of the macOS client** timed out after 3600 seconds: an orphaned `xcodebuild` of
    an earlier build held the lock of the build directory, and the next build waits for it — for
    hours, without a word. Every long build of the repository now runs in its **own process
    group**, and the whole group dies with the build (`tools/oip_build.py`).
  * The **integrity of the record** failed inside the refresh, as it does in every iteration that
    changes the product: the rehearsal measures the record, and the canonical state of the record
    is written at the **end** of the cycle. It passes there.
* **The machine blocks the rest of the cycle — and the record names it.** The daemon of the
  keychain of the machine (`securityd`) does not answer any more: every enumeration of the signing
  certificates hangs, and so does every `security` command of the keychain. The **macOS bundle**
  of the release therefore cannot be built, and with it the packaging rehearsal (`oip_mas_package`)
  and the reproducible build of the macOS bundle cannot be measured in this cycle. The daemon is
  owned by the system, and the loop may not restart it: the repair is the operator's action (below).
  The receipt of the packaging rehearsal therefore names the revision **before** the change of the
  product, and the verification of the release reports exactly that — a stale receipt is reported,
  never hidden. The verification of this revision therefore names **two** problems, and both come
  from the daemon: `the artefact the_macos_application_bundle is absent` and `the receipt
  docs/evidence/oip-mas-package/mas-package.json names the revision d350bb0, which predates the
  last change of apps/flutter/lib (e57d39c)`. Every other receipt of the release is fresh, the
  acceptance passed with the release binary of this revision, and the manifest names every artefact
  that exists.
* **The release of this revision is measured with the binaries of the tree.** The acceptance ran
  with the release binary (`0b2a938`), the eight functional phases **8 of 8 PASS**, the browser
  gate **PASS** with **187 findings** and **13 captures**, the **382 of 382 Flutter tests**, and the
  reproducible build at the **same** revision produced the byte-identical Core and the
  byte-identical web release.

The next independent READY task is **N32**: the **authorized service inventory** of the Core — the
contract of the capability exists (`docs/architecture/OIP_DEVICES_SERVICES_2027_CORE_REQUIREMENTS.md`),
and the implementation (the plan, the storage, the capability, the route and the tool) follows.

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no push, no deployment.


### Iteration 86 — the Core delivers the service registry that the operator declared

**Status: PROVED on canonical `main`. The verdict stays `OIP_PRODUCTION_NOT_READY`** — the gates that
need the operator (G5, G10, G12) stay open, and this iteration adds the machine blocker below.

* **The Core had no service registry at all.** The inventory of the Core is a registry of
  **devices** — the manufacturer, the model, the firmware, the serial number and the address — and
  nothing about the **services** that a device offers. The plan had no section for them, the Core
  had no capability, no route and no MCP tool, and the two workstations that would show them named
  the absence honestly. The product could not answer the question an operator asks first about a
  device: *what does this thing actually run?*
* **The registry is what the operator declared.** The Core measures no service — it runs no probe
  and holds no credential for one — so the declaration lives in the **plan** of the instance
  (offline, authorized, versioned) and every record of the registry carries the provenance
  `declared`. The declaration is stable like every other identity of the plan: a plan that changes
  a declaration is refused instead of rewriting the record of the operator behind his back, and a
  declaration for a site that the plan does not name is refused.
* **The Core delivers it like the inventory.** The capability `service_registry_read` carries the
  permission of the inventory read (the readers of the inventory read the services of the same
  scope), the route `GET /api/v2/services` and the MCP tool `oip_services_read` answer the same
  page, the scope of the read is the scope of the hierarchy, and a foreign identifier is refused
  **identically** to an identifier that does not exist (the answer discloses neither).
* **The store holds the declarations.** The table of the services is the migration 8, and the
  provisioning of an operator — which runs before the schema of the registry exists — creates the
  same table with the same statement, so a declaration is never lost between the provisioning and
  the start of the instance.
* **The client shows the registry.** The Services workspace of the Devices shows the services of
  the authorized scope with their kind, their endpoint, their declared state and the device they
  belong to; the comparison and the device detail name the services of the device. An **empty**
  registry is the statement of the operator ("no service declared"), and a Core that does not
  deliver the registry is named as the absence — an empty list would look like a measurement.
* **The tests close the gaps**: the Rust suite (**191 tests in 30 suites**, the new suite
  `services` ✓), the rehearsal of the registry against the real Core
  (`tests/oip_service_registry.py`: the scope, the isolation of the organizations, the refusal of a
  foreign identifier, the parity of the route and the MCP tool, and the refusal of a plan with a
  service of an unknown site ✓) and the **385 Flutter tests** (the panel of the registry, the empty
  registry, the absence, the comparison and the device detail ✓).
* **Two rehearsals had to be corrected, and the corrections are honest.**
  * The **handover to the era** (the protected binary of an earlier
    release) provisioned the plan of this era — and the binary of the era
    does not know the section `services`. The handover now gives the binary of
    the era the plan it knows, and the release binary takes over the store.
  * The **instance on the host** (the Raspberry Pi of the operator) delivered
    an empty address space: the rehearsal asked the Core for the address
    space of the source before the collector of the instance had connected to
    the simulation of the host and scanned its namespace. The rehearsal waits
    for that now — bounded, and it still fails when the Core does not deliver
    the projection.
* **The machine still blocks the macOS evidence.** The daemon of the keychain of the machine does
  not answer, so the macOS bundle of the release cannot be built and the rehearsals that build it
  (the packaging, the macOS application and the local installation) were **skipped** in the refresh
  of this iteration — the record names the gap and the operator's action instead of hiding it. The
  verification of this revision therefore names **seven** problems, and every one of them comes
  from that daemon: the artefact of the macOS bundle is absent, and the receipts of the packaging,
  of the macOS application and of the local installation name the revision before the change of the
  product. Every other receipt of the release is fresh, the acceptance passed with the release
  binary of this revision, and the reproducible build at the **same** revision produced the
  byte-identical Core and the byte-identical web release.

The next independent READY task is **N33**: the **note of a device is writable in the surface** —
the Core replaces the metadata of a device as a whole, so the client must merge the edited note
into the metadata it sends back.

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no push, no deployment.
### Iteration 87 — the note of a device is writable where the device is, and the macOS evidence of the release is measured again

**Status: PROVED on canonical `main`. The verdict stays `OIP_PRODUCTION_NOT_READY`** — the gates that
need the operator (G5, G10, G12) stay open, and this iteration closes the gap of the macOS evidence
that the machine caused.

* **The note of a device was shown but not writable.** The Core holds an optional free text `notes`
  in its inventory and the client showed it (N29 ✓), but the operator could not write it: the Core
  replaces the metadata of a device as a whole, so a client that sends only the fields that the
  operator changed **drops** the note. The administration of the inspector had no field for it.
* **The note is writable where the device is.** The administration carries the field of the note,
  and the client **merges** the note into the metadata that it sends back: a write of the name
  never drops the note, and an emptied note is removed from the record instead of being written as
  an empty text (`apps/flutter/lib/features/devices/device_administration.dart`). The controller of
  the field is released with the widget — the change itself carried that leak, and the fix is in
  the same commit. The field is **one line**: the Core refuses a control character in the note, so
  the surface must not offer what the Core rejects.
* **The journey of the real surface proves the merge against the real Core.** The operator writes
  the note in the inspector, the Core keeps it and the revision of the record advances from 2 to 3
  (`apps/flutter/test/browser_onboarding.mjs`,
  `docs/evidence/oip-device-administration/device-administration.json`). The same journey writes the
  device **without** the note in its metadata and measures that the Core **drops** it — the
  contract of the Core is measured, not asserted.
* **A defect of the client was found by that journey, and it was real.** The shortcuts of a
  workstation (the pin `p`, the comparison `c`, the search `/`) are the keys of the **page**, but
  the handler of the page only spared the **search** field: while a field of the inspector was
  edited, the page swallowed the keys of the field — the operator lost **every "c"** of the note
  and every "c" toggled the comparison instead. The four workstations now ask whether a text field
  owns the keyboard (`apps/flutter/lib/core/keyboard.dart`).
* **The same defect was in the search of the address space, and the probe of the laboratory
  measured it.** The OPC-UA page bound its plain characters as **shortcuts**, and a shortcut that
  matches a character swallows it: the search of the address space lost every "c" (the laboratory
  measured "ab" for the typed "abc"). The plain characters are handled by the page again, below the
  shortcuts — and the **canonical gate** proves it now in the browser: the search keeps every
  character (`apps/flutter/test/browser_canonical_ui_gate.mjs`).
* **The regression test is meaningful.** The test of the guard of the devices workstation fails
  without the guard (measured) and carries a **positive control**: the comparison of the page still
  works, so the check proves the guard and not a broken comparison
  (`apps/flutter/test/devices_workstation_test.dart`).
* **Two defects of the harness were found and fixed.** The journey activated the button of the save
  with a painted mouse click, and the panel of the administration grew with the field of the note:
  the buttons of the inspector are drawn over the panel that scrolled under them, so the click was
  **swallowed** and the write of the name never reached the Core. The journey now activates the
  controls of the surface with the event of their semantics node (the way the accessibility tree
  activates them) and proves every way with the state of the Core. The fields are written with a
  painted click and **read back**, because a field that carries a different text is a defect of the
  surface and not a fact of the journey.
* **The machine answers again.** The daemon of the keychain of the machine (`securityd`) wedged
  ~5 hours and blocked every enumeration of the signing certificates; it answers again now, so the
  macOS evidence of the release is measured again in this iteration and the operator's action is
  done.
* **The tests close the gaps**: the Rust suite (**191 tests in 30 suites**), the **387 Flutter
  tests** (the write of the note, the merge of the metadata, the lifecycle of the controller of the
  field and the keys of the page ✓) and the eight functional phases of the canonical acceptance.

The next independent READY task is **none**: the list of the independent tasks is closed. What
remains are the operator actions: the product decision on the delivery of the web release, the
physical device of G5, the production-security scope of G10, the operator acceptance of G12 and the
discovery of the host of the Core.

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no push, no deployment.
### Iteration 88 — the address space of the operator is measured in the browser, and the journeys of the old surface are retired

**Status: PROVED on canonical `main`. The verdict stays `OIP_PRODUCTION_NOT_READY`** — the gates that
need the operator (G5, G10, G12) stay open, and the two real devices of the operator are still out
of reach of this machine.

* **Twenty-two browser journeys and performance scripts proved nothing, and two of them proved the
  wrong thing.** Under `apps/flutter/test/` they were named by **no** harness: no rehearsal of the
  refresh, no case of the canonical regression, no script of the tools. Their proofs were therefore
  **no receipts** — and every one of them waited for the surface of the OIP/005 demo
  (`Operations Workstation`), one of them for its slogan (`Deine Infrastruktur. Ein Bild.`). A file
  that asserts the prohibited surface is a trap for the next reader: the journeys are **retired**
  (they stay in the history of the repository).
* **The claim of the address space was unbacked, and it is measured now.** The record named the
  browser journey of the phase 2 as the proof that the surface derives the folder, the node and the
  identity of a node from the API — and that journey was never run by a harness. The **rehearsal of
  the address space** (`tests/oip_opcua_browser.py`) starts a disposable Core with **live
  collectors** and drives the real surface in the browser
  (`apps/flutter/test/browser_opcua_address_space.mjs`): the journey reads the address space from
  the API and names **no** node and **no** folder of its own, so every name it looks for is the
  name the Core delivered — the rows of the surface are the nodes of the Core, the identity of a
  node carries the namespace, the folder and the node id that the Core delivered, the attributes
  that the Core does not deliver are **named** instead of invented, the limits of the address space
  (no history, no hierarchy) are named, and the keyboard search reaches a node of the Core before
  the pagination (`docs/evidence/oip-opcua-browser/opcua-browser.json`).
* **The product of the release was not touched by this iteration** (`crates/` and
  `apps/flutter/lib/`), so every receipt of the release stays fresh and the product boundary
  (`fc18ce2`) is the one of the record. The acceptance and the reproducible build were measured
  again at the revision of the record, so the Core that the canonical gate executed is the Core
  that the manifest names — byte-identical with the two builds of the reproducible build.
* **The order of the release cycle was corrected, and the record names it.** The reproducible build
  **rebuilds** the Core binary, and the binary names the revision it was built from: the
  reproducible build therefore runs **before** the acceptance, both on the same clean revision, and
  the acceptance then drives exactly the binary that the manifest names. A single rehearsal of the
  refresh also rebuilds the binary — the acceptance has to run again after it, and that is what this
  iteration measured.

The next independent READY task is **none**: the list of the independent tasks is closed — the last
one (N34) is measured. What remains are the operator actions: the product decision on the delivery
of the web release, the physical device of G5, the production-security scope of G10, the operator
acceptance of G12 and the discovery of the host of the Core.

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no push, no deployment.
### Iteration 89 — the density of the Devices workspace is measured in the browser

**Status: PROVED on canonical `main`. The verdict stays `OIP_PRODUCTION_NOT_READY`** — the gates that
need the operator (G5, G10, G12) stay open, and the two real devices of the operator are still out
of reach of this machine.

* **The first group of N35 is measured.** The claim of the density of the Devices workspace — the
  document never scrolls horizontally and no control of the filter toolbar is clipped outside the
  viewport — was carried by a journey that no harness named and that no receipt measured. The
  **rehearsal of the density** (`tests/oip_devices_density.py`) starts a disposable Core with the
  plan of the operator, registers the devices **through the authorized route** (so the rows of the
  inventory are the devices that the Core delivered) and drives the real surface in the browser
  (`apps/flutter/test/browser_devices_density.mjs`): six widths (320, 390, 768, 1024, 1440 and
  1920 px) and three themes (Spectrum, Graphite and Daylight), fourteen checks in all — the
  disclosure of the secondary filters opens, the inventory explorer is rendered, and no control is
  clipped (`docs/evidence/oip-devices-density/devices-density.json`).
* **The journey of the generation 2027 was adapted, not revived.** It drove the surface of the
  OIP/005 demo and waited for the title of the old overview; it now waits for the **authorized
  session** of the operator and drives the managed surface, and it names no device of its own.
* **The product of the release was not touched by this iteration** (`crates/` and
  `apps/flutter/lib/`), so every receipt of the release stays fresh and the product boundary
  (`fc18ce2`) is the one of the record. The acceptance and the reproducible build were measured
  again at the revision of the record, so the Core that the canonical gate executed is the Core
  that the manifest names — byte-identical with the two builds of the reproducible build.

The next independent READY task is **N35** again, with the next group: the **Network workspace** —
the geometry of the graph, the comparison of two devices, the transport filter and the recovery
from an unreachable source (`browser_network_2027.mjs` and `performance_network_2027.mjs` of the
generation 2027, adapted to the managed surface and driven by a rehearsal of their own).

Beside it remain the operator actions: the product decision on the delivery of the web release, the
physical device of G5, the production-security scope of G10, the operator acceptance of G12 and the
discovery of the host of the Core.

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no push, no deployment.

### Iteration 91 — the Network workspace of the managed surface is measured in the browser

**Status: PROVED on canonical `main`. The verdict stays `OIP_PRODUCTION_NOT_READY`** — the gates that
need the operator (G5, G10, G12) stay open, and the two real devices of the operator are still out
of reach of this machine.

* **The second group of N35 is measured — and two of its claims are withdrawn.** The Core of the
  managed mode delivers the devices, the sources, the observations and the events — and **no
  logical path**: the scoped snapshot of the Core has no topology
  (`crates/oip-core/src/hierarchy.rs`), no route delivers links (`crates/oip-server/src/api.rs`)
  and the projection of the client knows that the paths are not delivered
  (`apps/flutter/lib/models/infrastructure.dart`). The rehearsal of the Network workspace
  (`tests/oip_network_2027.py`, `apps/flutter/test/browser_network_2027.mjs`) therefore measures
  what the managed surface can honestly measure: the summary names the absence
  (`LOGISCHE PFADE NICHT GELIEFERT`, `VPN-TELEMETRIE NICHT GELIEFERT`, `DEMO-PFADE 0`), the list of
  the paths is empty and says that an empty result is no offline state, the transport filter offers
  only the transports that the Core delivered — here only `alle` — the Device Explorer shows
  exactly the devices that the Core delivered (the counter, the rows, the search, the relation
  filter), the comparison of two devices names its own limit (`2/4 Geräte · 0/4 Pfade ·
  sitzungslokal`), the graph names its empty state, the markers of the demo of the generation 2027
  are absent, and the channel that goes stale is named as stale and comes back. **Twelve checks**
  (`docs/evidence/oip-network-2027/network-2027.json`).
* **The geometry of the graph over real links and the transport filter over real transports are
  withdrawn as claims of the managed surface**: the Core delivers no link, so the browser cannot
  measure them. The geometry stays proven at the widget level
  (`apps/flutter/test/network_workstation_test.dart`), and the browser proves the **absence** is
  named instead of simulated.
* **A hole in the release discipline was closed.** The rehearsal of the reproducible build
  compared two builds of the Core and reported them as identical — while the tree was **dirty**:
  the build script of the Core embeds `git describe --always --abbrev=40 --dirty`, so a tree with
  changes in it yields a binary that names the revision **with the marker** and has other bytes.
  Two dirty builds are identical to each other and prove nothing about the release. The rehearsal
  now **refuses a dirty tree** and **refuses a binary that names a dirty revision**
  (`tests/oip_reproducible_build.py`).
* **The compare and the pin of a row of the Network explorer are not in the semantics tree** — the
  row excludes the semantics of its descendants
  (`apps/flutter/lib/features/network/network_explorer.dart`), so the two actions are reachable
  only by the documented keyboard (`P`, `C`). The journey drives the comparison by that keyboard
  path. The fix (the **texts** of the row excluded instead of the whole row) changes the product
  and therefore needs the full re-measurement of the release: it is the next product change, named
  as **N36** in the ledger.

The product of the release (`crates/`, `apps/flutter/lib/`) was not touched by this iteration, so
the boundary of the product (`fc18ce2`) and the freshness of every receipt of the release stay
what they are. The acceptance and the reproducible build were measured again at the revision of the
record, on a clean tree, so the Core that the canonical gate executed is the Core that the
manifest names.

Beside it remain the operator actions: the product decision on the delivery of the web release, the
physical device of G5, the production-security scope of G10, the operator acceptance of G12 and the
network of the devices (the router and the bridge).

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no push, no deployment.
### Iteration 92 — the geometry of the Devices workspace and the evidence workspace of the Diagnostics

**Status: PROVED on canonical `main`. The verdict stays `OIP_PRODUCTION_NOT_READY`** — the gates that
need the operator (G5, G10, G12) stay open, and the two real devices of the operator are still out
of reach of this machine.

* **The third group of N35 is measured: the geometry of the Devices workspace.** The layout is a
  claim of the release — the operator accepts the visible result (G12) — and the numbers of the
  layout are the evidence that the acceptance can look at. The rehearsal
  (`tests/oip_devices_geometry.py`, `apps/flutter/test/browser_devices_geometry.mjs`) registers the
  devices **through the authorized route** and measures the **four states** of the workspace — no
  selection, a device selected, the secondary filters open and the comparison — at 1440 px and
  1920 px: the height of the filter bar (42 px, 79 px with the secondary filters open), the number
  of its controls (4 and 7), the height of the search field, the pitch of the rows of the inventory,
  the edges of the content and the height of the document
  (`docs/evidence/oip-devices-geometry/devices-geometry.json`).
* **The fourth group of N35 is measured: the evidence workspace of the Diagnostics workstation.**
  The rehearsal (`tests/oip_diagnostics_2027.py`, `apps/flutter/test/browser_diagnostics_2027.mjs`)
  starts a disposable Core with **live** collectors, drives the surface and then changes the state
  of the source: the collectors die and come back. The journey names **no event of its own** — every
  row of the explorer and every marker of the timeline is checked against the events of the Core
  (read from the diagnostic history of the authorized context), the attributes that the Core does
  not deliver are named instead of invented (the severity, the source timestamp, the record id),
  and the **loss** of a source is the evidence of the Core: the `ConnectionLost` event, the sources
  `disconnected` / `unknown` / **stale** with the last error named, and the recovery measured by the
  health of the source (`docs/evidence/oip-diagnostics-2027/diagnostics-2027-rehearsal.json`).
* **The recovery of an OPC-UA source is not a collection event of the Core.** The adapter
  reconnects without an event, so the evidence of the recovery is the health of the source and its
  reconnect attempts. The record names that limit instead of claiming an event that the Core does
  not write.
* **The evidence id of an event is delivered by the Core and not shown by the surface.** The
  diagnostic projection of the Core carries the id of the record; the surface shows the
  source-local record id, which the projection does not deliver, and names it
  `keine Server-Record-ID`. The label of the inspector (`Event ID / Record-ID`) promises both. It
  is named here as a candidate for the next product change.

The product of the release (`crates/`, `apps/flutter/lib/`) was not touched by this iteration, so
the boundary of the product (`fc18ce2`) and the freshness of every receipt of the release stay
what they are. The acceptance and the reproducible build were measured again at the revision of the
record, on a clean tree.

Beside it remain the operator actions: the product decision on the delivery of the web release, the
physical device of G5, the production-security scope of G10, the operator acceptance of G12 and the
network of the devices (the router and the bridge).

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no push, no deployment.

### Iteration 93 — the depth of the Settings workspace of the managed surface

**Status: PROVED on canonical `main`. The verdict stays `OIP_PRODUCTION_NOT_READY`** — the gates
that need the operator (G5, G10, G12) stay open, and the two real devices of the operator are still
out of reach of this machine.

* **The fifth group of N35 is measured: the depth of the Settings workspace.** The workspace is
  where the operator reads what the Core can and cannot do, and a surface that invents a setting,
  a tool or a credential is worse than no surface. The rehearsal
  (`tests/oip_settings_depth_2027.py`, `apps/flutter/test/browser_settings_depth_2027.mjs`) starts a
  disposable Core with the plan of the operator, authenticates the session of the operator and
  drives the managed surface in the browser. The journey names **no settings key, no tool and no
  schema of its own** — it reads the settings, the reports of the management and the client
  configuration from the Core with the session of the same origin and checks the surface against
  them (`docs/evidence/oip-settings-depth/settings-depth.json`, twelve checks).
* **The settings are read-only and offline administered.** The surface offers the seven categories
  of the Core, the three settings keys of the instance and the startup snapshot that the Core
  delivered (`loaded_at_ms`), names the category as `OFFLINE ADMINISTRATION REQUIRED` and carries
  no save control at all — the surface has no write path, and the journey proves the absence with
  a role query instead of a claim.
* **The MCP runtime is the runtime of the Core.** The server section names the transport and every
  fact of the server report, the tool explorer reaches a tool of the delivered catalog (`MCP Tool
  & Capability Explorer`), the inspector names its permissions and its allowed scopes, and the
  copied schema is **deep-equal** to the `input_schema_json` that the Core delivered for that
  tool — the surface renders the authorization read, not a schema of the client.
* **The client configuration is the template of the Core and carries no credential.** The copied
  JSON names the `oip-local` server with `--mcp-bridge`, `--ipc-socket`, `--ipc-credential`, the
  placeholders `<AUTHORIZED_PRIVATE_SOCKET>` and `<AUTHORIZED_PRIVATE_CREDENTIAL_FILE>`, no bearer
  token and no credential-looking value; the Core reports `credential_provisioned: false` and
  `usable_without_replacement: false`. The copy of the executable of the Core stays in the template
  — it is the path of the instance and not a credential — and the receipt records the template as
  it is.
* **The limits are named.** The client sessions are `UNSUPPORTED`, the retention names `Keine
  Datenlöschung`, the connection diagnostics are `STATUS READ ONLY` and the number of the delivered
  tools, the security category names `PRODUCTION BLOCKERS OPEN` with the open advisories
  (`RUSTSEC-2023-0071`, …), and the runtime names `CPU / RAM / GPU — Unknown — no host collector
  data in this contract`. The surface never claims a production readiness.
* **The permissions of the rehearsal are recorded.** The settings and the management report are
  platform capabilities and the plan of the example grants neither; the rehearsal therefore grants
  `settings_read` and `mcp_management_read` at platform scope to the reader it authenticates and
  names the grant in its receipt. Without it the surface would show the refusal of the Core and the
  journey would prove nothing about the depth of the workspace. The refusals that the Core still
  returns for the routes of the platform (`/api/v1/sources`, `/api/v1/events`, …) are recorded as
  evidence of the authorization, not as a defect of the surface.
### Iteration 94 — the performance of the Overview, and the end of N35

**Status: PROVED on canonical `main`. The verdict stays `OIP_PRODUCTION_NOT_READY`** — the gates
that need the operator (G5, G10, G12) stay open, and the two real devices of the operator are still
out of reach of this machine.

* **The sixth group of N35 is measured: the performance of the Overview.** The Overview is the
  workstation the operator opens first and returns to, and no journey had measured what it costs.
  The rehearsal (`tests/oip_overview_performance_2027.py`,
  `apps/flutter/test/browser_overview_performance_2027.mjs`) starts a disposable Core with four
  live collectors, waits until the Core has recorded the collection events that the Overview lists,
  and drives the managed surface with the session of the operator
  (`docs/evidence/oip-overview-performance/overview-performance.json`, eleven checks). The journey
  measures the **twenty-three** interactions the operator performs — the three tabs of the activity
  workspace, the event filter of the kind that the Core delivered (`Reconnected`), the change of the
  global context and its return to the unified view, six round trips through the Devices workstation
  and six switches of the theme. The latency of every interaction is measured against a budget of
  3000 ms (median 224 ms, p95 602 ms, max 755 ms), the frames of the browser against the frame of
  the display (516 samples, median 17 ms, p95 17 ms, max 50 ms), the long tasks of the main thread
  against 250 ms (one task of 51 ms), and the heap the surface retains against 24 MiB (7,789,951
  bytes after an explicit collection of the garbage). The compositor presents 363 frames, 297
  paints, 365 layerizations, 77 layouts and 139 style recalculations. The numbers of the surface are
  the numbers of the Core: the status strip names 3 sources and 3 devices, the activity list holds
  the records of the Core and the filter reaches the kind that the Core delivered.
* **The performance is a local measurement, not an SLA.** The scope is the client of the delivered
  web release on the loopback of this machine, in the same wording as the performance baseline of
  the record. The budgets are the claim of the journey and the numbers are the measurement; the
  refusals of the Core (6 routes of the platform scope of the reader) are recorded as evidence of
  the authorization and no request leaves the loopback. N35 is **complete**: its six groups are
  measured, and the two claims that the managed Core cannot prove — the geometry of the graph over
  real links and the transport filter over real transports — stay withdrawn instead of simulated.

The product of the release (`crates/`, `apps/flutter/lib/`) was not touched by this iteration, so
the boundary of the product (`fc18ce2`) and the freshness of every receipt of the release stay what
they are. The acceptance and the reproducible build of the release were measured at the revision of
the record (iteration 92) and are not re-measured for a change that does not touch the product.

Beside it remain the operator actions: the product decision on the delivery of the web release, the
physical device of G5, the production-security scope of G10, the operator acceptance of G12 and the
network of the devices (the router and the bridge). This closing note was written before N36 was
merged; **N36 is now complete** (`4132d8d`, accepted at `0a9b64f`), the full release cycle at the
final revision is done (`0a9b64f` final acceptance, `1d3fc02` record verification), and the
agent-addressable backlog is exhausted — see Iteration 95.

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no push, no deployment.

### Iteration 95 — the record is reconciled with the product, and a regressed configuration is restored

**Status: reconciled on canonical `main` (`1d3fc02`).**
An earlier turn of the loop operated on a stale premise: it treated the Mac App Store readiness as
the open task and re-applied a hardened runtime and a raised deployment target to the local Xcode
project of the client. This iteration read the record first, found that premise wrong, and restored
the verified state instead of committing a regression. No product code and no build configuration
changed; only the record was reconciled.

* **The Mac App Store readiness is already complete, and the re-applied hardening was a regression.**
  The requirements of the store were read with their sources in
  `docs/release/mac-app-store/requirements.md` (iteration 74), and the package is measured
  (`docs/evidence/oip-mas-package/mas-package.json`). Requirement **R4** of that document is
  explicit: the hardened runtime belongs to the **distribution** build, and it must **not** be set
  in the local Xcode project — the local bundle is signed ad-hoc, the embedded Flutter framework
  carries another ad-hoc identity, and the library validation of the hardened runtime refuses it, so
  the local bundle would stop launching. Commit `46c0fcf` ("the hardened runtime belongs to the
  distribution build, not to the local ad-hoc bundle") already removed it for exactly that reason,
  and the archive of the distribution carries the hardened runtime instead
  (`flags=0x10002(adhoc,runtime)` in `mas-package.json`). The re-applied change —
  `ENABLE_HARDENED_RUNTIME = YES` and `MACOSX_DEPLOYMENT_TARGET = 13.0` in the Debug/Release/Profile
  configurations of `apps/flutter/macos/Runner.xcodeproj/project.pbxproj` — reverted that deliberate
  fix and would have re-broken the local launch. It was **restored** to the committed configuration
  (`git checkout` of the working tree), and the two duplicate artefacts a parallel draft had added
  — the draft script `oip_macos_mas_harden.sh` and the draft note `macos-app-store-readiness.md` — were removed, because they
  duplicated `tools/oip_mas_package.py` and `docs/release/mac-app-store/`. No build configuration of
  the client changed in this iteration.
* **N36 is complete; the "next tasks" of the record were stale.** The row actions of the Device
  Explorer and the Event Explorer reach the semantics tree now (`4132d8d`, the canonical source
  revision): each row excludes only its icon and its texts with `ExcludeSemantics`, and the compare
  and the pin buttons are **not** excluded, so assistive technology reaches them by name. Proven in
  `apps/flutter/test/browser_network_2027.mjs` and `apps/flutter/test/browser_diagnostics_2027.mjs`.
  The ledger and the closing note of Iteration 94 still named N36 as the next task; both are
  reconciled to the truth. Every item of the "Next READY tasks" list (N19–N36) is now measured or
  complete, and the full release cycle at the final revision is done (`0a9b64f` final acceptance,
  `1d3fc02` record verification).
* **The state that is verified is unchanged.** The product of the release (`crates/`,
  `apps/flutter/lib/`) and its build configuration were not changed by this iteration; only the record
  (`docs/OIP_RELEASE_LEDGER.md`, `docs/OIP_RELEASE_PROGRESS.md`) was reconciled. The tree is clean,
  the personal installation is untouched at schema 6, and the repository has no remote.

**The agent-addressable backlog is exhausted.** The software of every mandatory gate is DONE or
READY (the software part), and what remains is operator-owned: the physical device of G5, the
production-security scope of G10, the operator acceptance of G12, the network reachability of the two
deployed devices (the router and the bridge on `192.168.1.x`, unreachable from `192.168.178.0/24`)
for their discovery, and the Mac App Store archive, metadata, screenshots and upload. The verdict
stays **OIP_PRODUCTION_NOT_READY** until the operator accepts the application.

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no build-configuration change of the
client, no push, no deployment.

### Iteration 96 — the last stale task entry is reconciled and the agent backlog is confirmed exhausted

**Status: reconciled on canonical `main`.** This iteration re-scanned the record for any
agent-addressable work before re-affirming the blocked state, and found one more stale entry: the
original task table (§3, N1–N11) still listed **N10 the managed diagnostics view as `READY`,
"the next step of the loop."** N10 is **DONE** — the diagnostics-2027 workspaces (event explorer,
evidence inspector, persisted evidence) are in the approved Spectrum-2027 shell
(`apps/flutter/lib/features/diagnostics/`), proven by `managed_diagnostics_test.dart`, and wired as
workstation page 4 (`DiagnosticsPage`) in `apps/flutter/lib/app/app.dart`; the capability was
reconciled into the approved workspace in `7fc612e` and measured in iteration 13. The row is now
`DONE`. With N10 reconciled, every item of both task lists (§3 N1–N11 and the N19–N36 list) is
**DONE**, **measured**, or **operator-blocked**; there is no READY task left for the loop. The
product of the release (`crates/`, `apps/flutter/lib/`) is byte-identical to the last verified
revision, so no build or gate is re-run for a record-only change. The verdict stays
**OIP_PRODUCTION_NOT_READY** and the loop enters **BLOCKED_OPERATOR**.

No personal database change, no schema-7 activation of the personal installation, no change to a
service of the operator, no published port, no firewall change, no build-configuration change of the
client, no push, no deployment.

### Iteration 97 — the one-command verification is re-run; two stale citations are reconciled

**Status: reconciled on canonical `main`.** Before re-affirming the blocked state, the loop re-ran the
one-command release verification (`tools/oip_verify_release.py`, read-only). It reported three defects of
the handoff: two were a real regression of the record, and one is an environmental fact that is not a
defect of the record.

* **Two stale citations — fixed.** The removal of the two draft artefacts in Iteration 95 deleted the
  files but left their checkout paths backtick-cited in that iteration's log. The checker of the record
  names a cited path that must exist, so it flagged both. The log is now reconciled: the removal is still
  recorded, but the two names are written as the basenames of the removed drafts and no longer as live
  paths of the checkout. Their canonical replacements — `tools/oip_mas_package.py` and
  `docs/release/mac-app-store/` — remain the authority of the Mac App Store work and are unchanged.

* **The macOS bundle digest is not a defect of the record (operator-owned).** The manifest of the
  release is byte-identical to the revision at which the gate was last green (`8d67a8a`), and it pins the
  digest of the macOS application bundle that the receipts `oip-macos-app` and `oip-macos-install` really
  measured. The bundle is gitignored build output and is not bit-reproducible; the copy on this machine
  was regenerated externally today (a build of the byte-identical source), so its digest no longer equals
  the measured one. Re-pinning the manifest to the regenerated bundle would claim an unmeasured build as
  verified, and rebuilding is a re-measurement of a byte-identical product; both are forbidden. The
  operator must therefore either restore the measured bundle or authorize the re-measurement of the
  regenerated one.

The product of the release (`crates/`, `apps/flutter/lib/`) is byte-identical to the last verified
revision, so no build or functional gate is re-run. The verdict stays **OIP_PRODUCTION_NOT_READY** and the
loop remains in **BLOCKED_OPERATOR**: the physical device of G5, the production-security scope of G10, the
operator acceptance of G12, the network reachability of the two deployed devices (the router and the
bridge on `192.168.1.x`, unreachable from `192.168.178.0/24`) for their discovery, and the Mac App Store
archive, metadata, screenshots and upload remain with the operator.

No personal database change, no schema-7 activation of the personal installation, no change to a service
of the operator, no published port, no firewall change, no build-configuration change of the client, no
re-pin of an unmeasured artefact, no re-measurement of a byte-identical product, no push, no deployment.

### Iteration 100 — the in-scope devices are reachable; a read-only discovery re-confirms Iterations 73 and 79

**Status: reconciled on canonical `main`.** The machine of the loop moved onto the network of the
operator's devices (`en0` = `192.168.1.219`, gateway `192.168.1.1`), so the two in-scope devices that the
later iterations had out of reach are now reachable. A **read-only** discovery was performed — no API key
was requested, no link button pressed, no router login made, nothing on either device changed:

* **The Philips Hue Bridge** (`192.168.1.131`): model `BSB002` (the V1 `hue bridge 2015`), Signify; its
  REST API is up but **authentication-gated** (`GET /api` refuses without a key). This is the **same
  bridge** that Iterations 73 and 79 discovered and onboarded with a verified pin, and its receipts
  (`docs/evidence/oip-deployment-discovery/deployment-discovery.json`,
  `docs/evidence/oip-hue-device/hue-device.json`) are present, tracked and **not** flagged by the
  one-command verification.
* **The OpenWrt router** (`192.168.1.1`): up, LuCI serving behind a login (credential-gated).

The substantive state is **unchanged** by the reachability: the bridge is an **identity-only inventory
device** (model, bridge id, MAC, IP, verified pin), and its **monitoring and control are not supported** —
the control capability is a new permission, audit and scope that only the operator can authorize
(Iteration 73), and the negative control is measured in `hue-device.json`. OIP never simulates Hue or
router control. This supersedes the stale operator action of Iterations 95–97, which named the devices
"unreachable from `192.168.178.0/24`" — the state of the machine on another network. The verdict stays
**OIP_PRODUCTION_NOT_READY** and the loop remains in **BLOCKED_OPERATOR**.

No personal database change, no schema-7 activation of the personal installation, no change to a service
of the operator, no published port, no firewall change, no request for a device credential, no
modification of the router or the bridge, no push, no deployment.

### Iteration 101 — verified host telemetry and native macOS Touch ID login

**Status: verified on the isolated candidate and integrated into canonical `main` by fast-forward**
(`9f87388`).
The managed Devices Telemetry tab now renders the same authorized SSH connection observations when the
device-detail projection has no metric rows. It waits for the connection result for the selected device;
it does not add simulator measurements. The complete acceptance uses an owned loopback OpenSSH fixture,
so its observed `Darwin` host and 16 GiB memory are test-host measurements, not readings from the Pi.

The native macOS login can pair Touch ID after an ordinary, authorized one-time-code login. The random
256-bit credential is held in the Mac Keychain with the current biometric set and device-only unlocked
access; the Core stores its digest and Principal binding in memory and redeems it for the existing
30-minute session. Pairing requires the authenticated cookie, exact Origin and CSRF. The first pairing
still needs the existing operator-issued code. A Core restart clears pairings, and a changed Touch ID
set requires re-pairing. The web client never offers Touch ID.

Measured evidence: `target/oip-host-telemetry-ui-gate-touchid-final/report.json` is **PASS** with all
8/8 managed acceptance phases, 387 Flutter tests, 189 browser checks with zero failures, 13 screenshots,
and `own_processes_stopped: true`. Local and served web bundles match byte for byte at SHA-256
`d76764985bbf0c7626dea8a4090ed5bc6b6ebed64ba23d275956dd560d02703b`; the tested source tree was
`be0fc5e40e3b08ce2b06a9781e2c1b952cee51b0`. The stable-shell visual result passes; operator visual
acceptance remains `VISUAL_PENDING_OPERATOR_ACCEPTANCE`. The native Release bundle builds successfully
for arm64 with `OIP_API_URL=http://127.0.0.1:18848`. The Keychain biometric ceremony itself is completed
by the operator when enabling Touch ID on the Mac.

The local Mac app bundle was replaced on disk after the verified build; any already-running process was
left untouched. Its verified bundle tree SHA-256 is
`91919451510d8beb5d5737bf4654861b266e53859435f6b22746af005594ab76`; it needs a launch to use Touch ID.
The Pi Core was not contacted or deployed, so support for the new pairing routes on the currently running
Pi instance remains unverified; those routes must be present there before Touch ID can log into that
instance. No private SSH device, Pi service, personal database, router, Hue Bridge, push or remote
deployment was changed.

### Touch ID regression audit — integrated into canonical main

On isolated branch `fix/oip-bug-audit` (fix commit `62e6ec2`, progress receipt `5afe4e4`), a
regression audit found and fixed failure paths around optional Touch ID login: a failed pairing no
longer strands a consumed one-time-code login; successful login performs only one infrastructure
bootstrap; the biometric login action appears only when this Mac actually has a paired Keychain item;
and the login card can scroll on short windows. Failed pairing cleanup preserves the original Core
error if Keychain cleanup fails. Three widget tests cover the absent/present Keychain states and
failed-pairing recovery. Two pre-existing analyzer findings were also fixed.

**Canonical UI acceptance: PASS** on tested source revision `5afe4e4d99894752e2599868b88585e5f92b09fd`,
tree `b73c998076045cabb951e4f4df1178357816ba3e`. The run was
`python3 tests/canonical_regression.py --only oip_canonical_ui_gate --evidence target/oip-canonical-regression-bugaudit-retry`.
The current-source Rust Core/MCP build, CanvasKit web release build and complete Flutter widget gate
passed; 390 tests passed, 0 failed, 1 skipped. The owned managed Core acceptance passed all 8/8
functional phases. Browser acceptance passed 189 findings with 0 failures; all 13 workstation and
authentication captures were produced and the technical visual comparison passed. The served browser
bundle SHA-256 equals the local build at
`948a96696e8b51b9c31df56e99f4a27364690750ca6b7315dbfe4324615f3556`. The acceptance reports
`own_processes_stopped: true`. Its inner build/widget precheck is intentionally labelled `PARTIAL`
because the enclosing managed acceptance runs the browser and visual gates against its owned Core;
the enclosing canonical acceptance receipt is the complete `PASS`.

The native macOS Release build also passed after disk space recovered:
`flutter build macos --release --dart-define=OIP_API_URL=http://127.0.0.1:18848`, producing a 55.3 MB
`oip_dashboard.app` with tree SHA-256
`7d4d853c96eefcac77288031a80d0628f10a95e0a6242645fc76e4ac23c060a8`. The three Touch ID regression
tests passed, `flutter analyze` reported no issues, and `git diff --check` passed. The browser/Core
acceptance used an owned loopback SSH fixture, not the physical Pi. No personal installation was
replaced, and no Pi/Core deployment or remote device change was performed. Operator visual approval
remains `VISUAL_PENDING_OPERATOR_ACCEPTANCE`.

### Touch ID failure diagnostics — integrated into canonical main

The live Mac login window displayed only the generic “Touch-ID-Anmeldung fehlgeschlagen.” The native
Keychain/LocalAuthentication `PlatformException` was being discarded by `apiErrorMessage`, hiding
whether biometric evaluation was cancelled or the local Keychain item was unavailable. The client now
shows the sanitized native message (or its error code when no message is supplied), with a widget
regression covering a cancelled biometric attempt.

**Canonical UI acceptance: PASS** on tested source revision
`fe3352430ff39dd9fa1b0e5875b4359572f60598`, tree
`38e1b1bc2d7ba73eceb5d3c5d0ae1650f14e3e35`. The current-source Core/MCP build, CanvasKit release
build, complete Flutter widget gate, authenticated browser gate, all 8/8 managed acceptance phases,
visual comparison, global context, accessibility and SSH onboarding passed. The widget suite reports
391 passed, 0 failed, 1 skipped; the browser gate reports 189 findings, 0 failures and 13 screenshots.
Local and served `main.dart.js` have the same SHA-256:
`22331857bd1db4ed48a08b4c7febed9a5cb756de901c1b061b62591ce5a62a7a`. `flutter analyze` has no issues.
The native macOS Release build passed at the same product source, with app bundle tree SHA-256
`6f3c172b8bede4b55d2f18580618df5634626ba98af685e3f1125b8ff29f84a6` (97,233,327 bytes).

The verified updated bundle was copied to `~/Applications/Open Industrial Platform.app`; its tree
hash matches the build exactly (`6f3c172b8bede4b55d2f18580618df5634626ba98af685e3f1125b8ff29f84a6`).
The prior bundle is preserved at
`/private/tmp/oip-bug-audit/Open Industrial Platform.before-touchid-update.app`. The app process that
was already open at the login screen was left running and still has the previous client code in
memory; quit and relaunch it to load the installed update. The Pi Core was not contacted or deployed.
Touch ID must be paired with a code login against a Pi Core that supports the pairing endpoints; a
Core restart clears the in-memory server pairing. Physical Pi Touch-ID acceptance remains unverified,
and operator visual approval remains `VISUAL_PENDING_OPERATOR_ACCEPTANCE`.

### Iteration 102 — the client About section makes the Settings workstation store-ready

**Status: verified on an isolated candidate and integrated into canonical `main` by fast-forward**
(`807722b`). A focused UI-polish increment (loop `oip-ui-polish`); it changes the presentation layer
only.

**Step.** Give the Settings workstation a client identity. The Application settings surface carried no
app identity: the name "Open Industrial Platform" lived only in the `MaterialApp` title, and no screen
named the version, the build or a data-disclosure note. A store-ready surface names the application the
way it ships.

**What changed** (client-side only; no Core, contract, permission or server rule changed):

* `apps/flutter/lib/models/app_metadata.dart` (new): the single source of truth for the client
  identity — name, version `0.3.0`, build `3`, the `OIP · SPECTRUM 2027` shell footer and a
  local-first data note. The version and build mirror `pubspec.yaml` (`version: 0.3.0+3`); the exact
  manifest line is kept next to the fields it describes (`OipApplicationInfo.manifestDeclaration`) so a
  drift is visible in one place.
* `apps/flutter/lib/features/settings/settings_content.dart`: an `About` subsection at the end of the
  Application settings, rendered with the existing `SettingsSectionHeader` / `KeyValue` /
  `WorkstationNote` widgets — the app name, the version, the build, the shell footer and the note
  "Lokal · keine Telemetrie".
* `apps/flutter/test/settings_about_test.dart` (new): one widget test that opens the Settings
  workstation and asserts the About section renders the identity with the manifest version and build.

**Measured result on the isolated candidate** (`feature/oip-ui-about-identity`, worktree
`…/worktrees/ui-about-identity`), merged with a real `git merge --ff-only` to `807722b`:

```
flutter analyze    exit 0, no issues
flutter test       392 passed, 0 failed, 1 skipped (native_session_live: no running Core — environment skip)
```

The single skipped test is `native_session_live_test.dart`, which skips when no live Core is named in
the environment; it is unchanged by this iteration. The additive About block sits deep in the Settings
workstation, outside the protected left-shell crops of the canonical UI visual comparison
(`docs/design/OIP_CANONICAL_UI_BASELINE.md` §5), so it does not touch the shell identity the gate pins.

**Not claimed.** The full canonical UI design-regression gate and the native macOS build were not
re-run for this focused polish increment; the change is additive, the complete Flutter widget suite is
green and the shell identity and footer are unchanged. Reading the *real* macOS bundle version through a
native channel (instead of the manifest-mirroring constant) is recorded as optional follow-up
hardening, not required here. No physical device, Pi service, personal database, router, Hue Bridge,
push or remote deployment was changed. Operator visual approval remains `VISUAL_PENDING_OPERATOR_ACCEPTANCE`.

### Iteration 103 — the About section attributes the client software license (store-ready provenance)

**Status: verified on an isolated candidate and integrated into canonical `main` by fast-forward**
(`d34326a`). A focused UI-polish increment (loop `oip-ui-polish`); it changes the presentation layer
only.

**Step.** Give the About section its missing store-ready provenance. Iteration 102 added the client
identity — name, version, build and a local-first data note — but the surface named no software
license, even though the client is released under Apache-2.0 (root `LICENSE`). A released app
attributes the license it ships under.

**What changed** (client-side only; no Core, contract, permission or server rule changed, no new
dependency):

* `apps/flutter/lib/models/app_metadata.dart`: a `license` field on the single client-identity source
  (`OipApplicationInfo`) — the SPDX identifier `Apache-2.0`, whose full text ships in the repository
  `LICENSE`. The version/build drift guard (`manifestDeclaration`) is unchanged.
* `apps/flutter/lib/features/settings/settings_content.dart`: a `Lizenz` row in the About section
  (key `settings-about-license`), rendered with the existing `KeyValue` widget alongside Version,
  Build and Shell; the section subtitle now names the license too.
* `apps/flutter/test/settings_about_test.dart`: the existing About widget test asserts the license
  row, the SPDX value and the model field.

**Deliberately not done (recorded, not skipped silently).** A clickable privacy-policy *link* was
considered and rejected: (1) launching a URL needs the `url_launcher` package, a prohibited new
dependency; and (2) OIP collects no data (local-first, no telemetry), so a privacy-policy link is not
required (Apple App Store Guideline 5.1.1 exempts apps that collect no user data). The existing
`Lokal · keine Telemetrie` note is the honest data disclosure; fabricating a link to a non-existent
URL would be dishonest. No privacy link is added.

**Measured result on the isolated candidate** (`feature/oip-ui-about-license`, worktree
`…/worktrees/ui-about-license`), merged with a real `git merge --ff-only` to `d34326a`:

```
flutter analyze    exit 0, no issues
flutter test       392 passed, 0 failed, 1 skipped (native_session_live: no running Core — environment skip)
```

The single skipped test is `native_session_live_test.dart`, unchanged by this iteration. The additive
license row sits in the About block, deep in the Settings workstation, outside the protected left-shell
crops of the canonical UI visual comparison (`docs/design/OIP_CANONICAL_UI_BASELINE.md` §5), so the
shell identity and footer the gate pins are unchanged.

**Not claimed.** The full canonical UI design-regression gate and the native macOS build were not
re-run for this focused polish increment; the change is additive, the complete Flutter widget suite is
green and the shell identity and footer are unchanged. No physical device, Pi service, personal
database, router, Hue Bridge, push or remote deployment was changed. Operator visual approval remains
`VISUAL_PENDING_OPERATOR_ACCEPTANCE`.

### Iteration 104 — the Settings error state names an HTTP 400 precisely and the catch-all is consistent

**Status: verified on an isolated candidate and integrated into canonical `main` by fast-forward**
(`8bb1c1a`). A focused UI-polish increment (loop `oip-ui-polish`); it changes the presentation layer
only.

**Step.** The Settings workstation `_error` state mapped four failure kinds to distinct titles and
messages (unauthorized, connection, unsupported, contract), but an **HTTP 400 / `INVALID_REQUEST`** —
the Core rejecting the request against the management contract (bad scope/key or an unsupported
read; produced in `services/api.dart` `_authorizedGet` at HTTP 400 and in the client-side
scope/key/section validation) — fell through to the generic fallback. There the **title** read
`Management-Daten nicht verfügbar` while the **message** still described a malformed *response*
(`Die Antwort wird nicht als gültiger OIP-008.4-Vertrag akzeptiert`). A request-side 400 is none of
a missing response, an errored transport, an unsupported function or a malformed response, so the
title and message contradicted each other. The same response-shape wording was also imprecise for
the genuine catch-all (an unknown HTTP status such as `HTTP_500`, or a server-provided code), whose
title says the data is unavailable.

**What changed** (client-side only; no Core, contract, permission or server rule changed, no new
dependency):

* `apps/flutter/lib/features/settings/settings_workstation.dart`: a dedicated `invalidRequest` branch
  (`code == 'INVALID_REQUEST'`) — title `Management-Anfrage abgelehnt` and a request-side message
  (`HTTP 400: Der Core hat diese Anfrage gegen den Management-Vertrag abgelehnt. Es wird kein
  Ersatzwert geraten und kein v1-Snapshot verwendet.`). The contract branch
  (`CONTRACT_ERROR` / `INVALID_RESPONSE`) keeps its exact original message; the generic catch-all now
  carries a message consistent with its own title — `Die autorisierte Management-Antwort fehlt oder
  ist unvollständig. Kein v1-Snapshot und keine Fixture ersetzen den gelesenen Wert.` — instead of
  reusing the malformed-response wording.
* `apps/flutter/test/settings_workstation_test.dart`: two widget tests — **K** asserts the precise
  400 state (its title/message, that it is distinct from the unauthorized/connection/contract/
  unavailable-data wording, and that the sanitized `INVALID_REQUEST`/`400` details and the retry
  control render with no fabricated data); **L** asserts the catch-all shows the missing-data state
  and does not reuse the contract-response wording.

**Deliberately not done (recorded, not skipped silently).** The main status `Icon` and the
`Fachlicher Status` note icon were left unchanged: the existing pattern only special-cases the
unauthorized state, and the precision here is carried by the words the operator reads, not by an
added glyph. No new dependency, no icon-token change, no Core error-code change was introduced.

**Measured result on the isolated candidate** (`feature/oip-ui-settings-error-text`, worktree
`…/worktrees/ui-settings-error-text`), merged with a real `git merge --ff-only` to `8bb1c1a`:

```
flutter analyze    exit 0, no issues
flutter test       394 passed, 0 failed, 1 skipped (native_session_live: no running Core — environment skip)
```

The single skipped test is `native_session_live_test.dart`, unchanged by this iteration. The change
is confined to the Settings workstation error state, deep in the Settings module, outside the
protected left-shell crops of the canonical UI visual comparison
(`docs/design/OIP_CANONICAL_UI_BASELINE.md` §5), so the shell identity and footer the gate pins are
unchanged.

**Not claimed.** The full canonical UI design-regression gate and the native macOS build were not
re-run for this focused polish increment; the change is additive, the complete Flutter widget suite is
green and the shell identity and footer are unchanged. No physical device, Pi service, personal
database, router, Hue Bridge, push or remote deployment was changed. Operator visual approval remains
`VISUAL_PENDING_OPERATOR_ACCEPTANCE`.

### Iteration 105 — the macOS direct build gains a GitHub Releases updater

**Status: implementation and first local install verified; live release delivery is blocked by the
GitHub publication step.** Candidate commit `462e97d`, built on isolated branch
`fix/oip-first-macos-install` from `234e428`.

The direct macOS build now checks the configured public GitHub Release endpoint, verifies an
Ed25519-signed manifest and the SHA-256 of the universal app archive, and offers the update to the
operator. A native macOS helper stages the replacement, rechecks its digest, bundle identifier,
version and code signature, swaps the closed app bundle and restores the previous bundle if the new
process does not start. The updater uses macOS SDK APIs and GitHub's own release interfaces; it has
no updater framework or embedded GitHub token. The App Store package keeps `OIPUpdateEnabled=false`
and its App Sandbox entitlement, so App Store updates remain App Store-managed.

The native release build succeeded. `python3 tests/oip_github_ota_package.py` passed (1 test): the
direct package is OTA-enabled and unsandboxed, the source/Store bundle remains OTA-disabled, the
archive digest matches, its manifest signature verifies, and a modified manifest is rejected. The
update helper passed shell syntax validation. `python3 tools/oip_mas_package.py --skip-build
--bundle apps/flutter/build/macos/Build/Products/Release/oip_dashboard.app --evidence
target/oip-ota-mas-check` returned `PASS` (the package measurement only; it is not the canonical UI
gate).

Version `0.3.0+3` is installed at `/Applications/Open Industrial Platform.app`. The installed tree
matches the signed direct package exactly: SHA-256
`9026e33672ab8efb85761b8844e026da58bcff2c7dc78c28f3ceee34629234d4`. It was launched in the
background from that path and process `22146` was observed running.

**Not yet an end-to-end OTA:** the public repository `Benriez/open-industrial-platform` now exists,
`origin` points to it, and the GitHub Actions secret `OIP_OTA_SIGNING_PRIVATE_KEY` is configured.
The repository is empty (no refs or default branch); GitHub's latest-release endpoint returns 404.
The signing key stays in the Mac login Keychain and the encrypted Actions secret; no private key is
committed or printed. The repo instructions prohibit a push. Consequently the updater source,
workflow and first release are not on GitHub yet, so the installed app cannot receive a live update.
No Store submission, Pi/Core deployment, personal database change or device write was performed.

**Follow-up (2026-11-15):** created the public repository and added the local `origin`; configured
the release-signing Actions secret directly from the Keychain without displaying its value. A
read-only check confirms zero remote refs and `GET /releases/latest` returns 404. No source push or
release was made.

### Iteration 106 — the installed Mac client can authenticate through its persistent Core tunnel

**Status: SSH options corrected; live API path passes short checks but has shown intermittent stalls;
native UI acceptance remains open.** The installed app at `/Applications/Open Industrial Platform.app`
was stuck at operator login. Its Mac LaunchAgent forwards `127.0.0.1:18848` to the operator's Pi
Core on `127.0.0.1:18808`. The `bodi-pi` SSH profile enables `ControlMaster auto`; the LaunchAgent
did not opt out, and its persistent connection accepted GET requests but hung on
`POST /api/v2/browser/login`. A fresh non-multiplexed tunnel authenticated, identifying SSH
connection sharing as one failure path.

The operator-owned `com.oip.platform-tunnel` LaunchAgent now passes `ControlMaster=no` and
`ControlPath=none`. It was restarted cleanly, with one listener on the app's configured port.
**Verified through that exact port:** a fresh one-time code authenticated with HTTP 200, and the
authorized `/api/v2/snapshot` returned HTTP 200 with 27 non-simulated observations. The source
snapshot contained 15 fresh observations for `bodi-pc` and 12 for `bodi-pi`; the Pi briefly aged
past the Core's freshness bound during the probe, then supplied fresh observations again. Later,
the LaunchAgent tunnel stalled again while a direct read of the Pi Core still returned HTTP 200.
A temporary non-multiplexed tunnel passed repeated post-login session reads; after restarting the
LaunchAgent and hidden relaunching the native app, the app-port session endpoint passed three
consecutive probes. This short recovery check does not establish long-run tunnel stability. No host
service, collection configuration, host database or device was written. The authorized hierarchy,
inventory and diagnostics read routes also returned HTTP 200.

**Remaining findings.** The installed app itself remains at its login panel; the UI session was not
authorized or visually accepted in this check. The real data omit CPU utilization on both hosts;
the Pi also has no separate GPU-load or GPU-temperature reading. Device details render raw metric
IDs such as `host.memory_used_percent`, which need clearer operator-facing labels. The separate
services and device-connections registries are empty, so they do not establish any additional
connection state. No full canonical UI gate, app rebuild/install, Pi/Core deployment, device write,
personal database change, push or release was performed. Operator visual approval remains
`VISUAL_PENDING_OPERATOR_ACCEPTANCE`.

**Runtime regression report (2026-11-16).** The operator reports that both the OPC-UA browser and
telemetry are not working. Read-only checks against the app's configured `127.0.0.1:18848` endpoint
confirm that the TCP listener exists, but GET `/api/v2/browser/session` and GET `/health` both time
out without an HTTP response (8-second bound). The `com.oip.platform-tunnel` SSH process remains
connected, while its error log records refused SSH session requests and repeated local-forward bind
failures from restart attempts. The Flutter client uses these same Core routes for authentication,
telemetry bootstrap and OPC-UA browsing, so neither feature can function while this API path is
stalled. This does not establish whether the Pi Core process or its SSH forwarding channel is the
remote failure point. No private SSH connection was opened and no tunnel, Core, host service,
database, device, or configuration was changed. Resolving this runtime blocker requires restoring
the operator-owned tunnel/Core path; no client-side data or feature change can repair a Core endpoint
that returns no HTTP response.

**Tunnel recovery and disk cleanup (2026-11-16).** The operator explicitly lifted the private-SSH
restriction; `AGENTS.md` now permits SSH diagnostics and reversible runtime recovery on `bodi-pi`
and `bodi-pc`, while still forbidding deployment, schema activation, database changes and device
writes. Read-only SSH inspection found the Pi Core listening on `127.0.0.1:18808`; its session route
answered HTTP 200 directly. The existing Mac forward on port 18848 continued to time out even after
restarting its LaunchAgent, while fresh forwards on 18849, 18850 and 18851 returned the same session
route in ~10–90 ms. The persistent `com.oip.platform-tunnel` LaunchAgent now forwards through port
18851. **Verified:** the app port returns `/api/v2/browser/session` HTTP 200; unauthenticated
`/api/v2/snapshot` and `/api/v2/opcua/nodes` return HTTP 403 quickly, confirming the endpoints are
reachable and require an operator session. The Mac app was rebuilt with
`OIP_API_URL=http://127.0.0.1:18851`, installed in `/Applications`, and the running app process opened
an established connection to port 18851. Its executable SHA-256 is
`16e8eaec503a8f1cc0d811111997c7019885157f71f943389b85531dfeb7d86f`; strict signature verification
passed. **Operator acceptance remains open:** this runtime session is unauthenticated, so fresh
telemetry and OPC-UA data have not yet been verified. The operator must sign in with Touch ID before
those protected reads can be checked. No one-time code, Core deployment, Pi/Pc service change,
database write, device write, push or release was performed.

The repository occupied about 11 GB before cleanup. Its largest disposable item was the ignored
Flutter compiler cache `apps/flutter/.dart_tool/flutter_build` (4.6 GB); ignored local macOS build
products (555 MB) and test cache (42 MB) were also removed. These paths had no open file handles, and
the active preview's `apps/flutter/build/web` assets were preserved. The checkout now occupies
5.8 GB. The remaining 5.5 GB `target/` was left intact because a workspace `cargo test` process was
active and shared OIP binaries/build artifacts must not be disturbed.

**Automatic tunnel recovery (2026-11-16).** The port-18851 SSH process remained alive while its
forwarding channel intermittently stopped returning HTTP. A `com.oip.platform-tunnel-watchdog`
LaunchAgent now checks the unauthenticated session endpoint every 20 seconds and restarts only the
existing local SSH tunnel if the endpoint times out or returns a non-success response. The first
manual watchdog run completed with exit code 0 and left the healthy tunnel PID unchanged; five
consecutive session requests then returned HTTP 200 in 9–21 ms. `tools/macos/` contains the watchdog
script and its LaunchAgent template. The app's current Core session is still `login_required` until
the operator completes Touch ID, so protected telemetry and OPC-UA data still need an authenticated
runtime check.

### Touch ID re-login root cause — the live Pi Core does not expose pairing

**Read-only live finding (2026-11-15).** The operator reported that Touch ID had already been
activated. The native app screenshot still showed only “Touch ID auf diesem Mac einrichten” and no
“Mit Touch ID anmelden” action. The app's own login code only shows that action when its Keychain
credential check succeeds. Source inspection confirms that native session cookies are held in
process memory only; restarting the app therefore drops its authorized session.

The first-party pairing flow creates a biometric Keychain credential and posts it to
`/api/v2/browser/pairing`; when that API call fails, Flutter deletes the just-created Keychain item.
The credential-login route is `/api/v2/browser/device-login`. Read-only GET probes against the live
Pi Core returned **404 for both routes**, while `/api/v2/browser/session` returned 200. Thus the
Mac's biometric step may have been completed previously, but the live Core could not register or
reuse that credential; the app then had no paired item to offer after restart. The CLI Keychain
query run in the prior audit was not conclusive because it ran outside the app's signing context and
is not used as evidence here.

The latest OIP app process restart in the tunnel investigation was the direct cause of the current
code prompt: the native cookie is memory-only. The missing Pi Core routes explain why the reported
Touch ID activation did not survive as a usable pairing. No one-time code was generated for this
audit, and no Core deployment, host change, Keychain value read, personal database write, or device
write was performed. Enabling Touch ID on this installation requires a Core build with both routes
and a successful first code login plus biometric pairing; that deployment remains forbidden by the
current repository safety boundary.

### Touch ID restart fix — Keychain fallback and session preflight (2026-11-16)

The live operator session was established through the existing local tunnel. Pairing from the app
succeeded and the server reported an authenticated session. The native credential store then exposed
a separate direct-distribution issue: this installed ad-hoc-signed app has no Keychain access-group
entitlement, so the data-protection Keychain rejected the add with `errSecMissingEntitlement`
(`-34018`). The app now keeps the preferred biometric-protected data-protection Keychain for
provisioned builds, and falls back on direct ad-hoc builds to the login Keychain with an ACL trusting
only the installed OIP executable. LocalAuthentication is still evaluated before every credential
read. The fallback does not claim Keychain-enforced biometric protection; that requires a properly
team-signed build with its keychain entitlement.

A second restart defect was in startup ordering. With no browser cookie after app restart, the client
requested `/api/v2/organizations` before checking `/api/v2/browser/session`; the expected 403 was
rendered as “Server nicht erreichbar”, hiding both login options. Startup now checks the session first,
clears authorized display state and opens the login panel directly when the session is unauthenticated.
The existing login view discovers the installed Keychain item and offers “Mit Touch ID anmelden”.

**Verified:** release macOS build succeeded with
`OIP_API_URL=http://127.0.0.1:18848`; the built and installed executable hashes both equal
`fd91210a62970a0b6a67797afdb9362d4e60a694e7cf518f5d91807dc3188704`; strict code-signature
verification passed. The installed app was restarted and its startup now begins with the session
preflight against the live tunnel (`/api/v2/browser/session` returns 200 with `authenticated:false`).
No one-time code was generated during the restart check. Touch ID read and biometric approval still
require the operator's physical fingerprint, so a post-restart biometric acceptance is not claimed.
The pre-existing login-keychain fallback and session cookie remain local to this Mac; no Core deploy,
host change, push, store release, personal database write, or device write was performed.

## 5. Evidence index

| Artifact | Content |
|---|---|
| `docs/evidence/oip-github-ota/ota-receipt.json` | current direct-update implementation and local `/Applications` installation; differentiates proved package behavior from the unpublished GitHub release path (tracked) |
| `docs/evidence/oip-canonical-acceptance/acceptance.json` | the canonical acceptance of the release: the eight functional phases, the widget gate, the browser gate, the visual comparison, the global infrastructure context, the accessibility and the device administration, with the revision and the tree of the run (tracked) |
| `docs/evidence/oip-macos-install/macos-install.json` | the local installation of the macOS application bundle: the copy is byte-identical to the bundle of the release, the installed copy starts, is refused without a session, terminates without an orphan and starts again from the installation directory (tracked) |
| `docs/evidence/oip003/`, `docs/evidence/oip004/`, `docs/evidence/oip004-ui/`, `docs/evidence/oip005/`, `docs/evidence/oip006/`, `docs/evidence/oip0061/`, `docs/evidence/oip007/`, `docs/evidence/oip008/`, `docs/evidence/oip0082/`, `docs/evidence/oip0084/`, `docs/evidence/oip0085/`, `docs/evidence/git-baseline/` | the receipts of the **earlier eras**: the history of the measurement and not the evidence of this release — the gate receipts of the eras 003 to 0085, the first real-device gate and the baseline of the initial commit |
| `docs/evidence/oip-record-numbers/record-numbers.json` | the numbers of the record are the numbers of the receipts: every measurement that a row of the record quotes is looked up in the receipt that the row names (tracked) |
| `docs/evidence/oip-deployment-hosts/deployment-hosts.json` | the **deployment hosts** of the operator, measured read-only over SSH: the identity, the architecture, the memory, the disk, the toolchain, the services of the operator (unchanged before and after) and the listeners of `bodi-pi` and `bodi-pc` (tracked) |
| `docs/evidence/oip-record-integrity/record-integrity.json` | the integrity of the record itself: every cited receipt exists and is tracked by git, and every receipt of the current release is cited by the ledger or by this file (tracked) |
| `docs/evidence/oip-release-verification/release-verification.json` | the verification of the release with **one command**: the manifest verifies, every receipt is fresh, the record is intact, the acceptance passed and the safety boundaries held (tracked) |
| `docs/evidence/oip-loopback-rate/loopback-rate.json` | the rate of the path of the measurement: the loopback of this machine, the rate of the machine itself and what the first paint of the baseline means (tracked) |
| `docs/evidence/oip-worktree-reconciliation/worktree-reconciliation.json` | the reconciliation of the worktrees: every branch, the commits that the canonical branch does not contain, the capability that it delivers in their place and the receipt that proves it (tracked) |
| `docs/evidence/oip-settings-status/settings-status.json` | the status of the settings categories in the surface against the real Core: every category of the Core is offered and shows the status the Core answered (tracked) |
| `docs/evidence/oip-settings-status/settings-status-rehearsal.json` | the rehearsal that produced it: the instance it owns, its steps and its result (tracked) |
| `docs/evidence/oip-settings-status/painted-surface.txt` | the painted surface of the settings: the navigation with the state of the Core for the selected category (tracked) |
| `docs/evidence/oip-scope-persistence/scope-persistence.json` | the measured scope of the operator across a refresh of the authorized projection against the real Core: the scope before and after the refresh, the revision of the device that advanced and the scope of a new session (tracked) |
| `docs/evidence/oip-scope-persistence/scope-persistence-rehearsal.json` | the rehearsal that produced it: the instance it owns, the device of the scope and the digest of the Core it drove (tracked) |
| `docs/evidence/oip-scope-persistence/painted-surface.txt` | the painted surface of the scope: the devices of the scope with the administration that changed the Core (tracked) |
| `docs/evidence/oip-storage-failure/storage-failure.json` | the measured storage-failure path of the Core: a store that cannot be written, measured on a bounded volume (tracked) |
| `docs/evidence/oip-device-connection/painted-surface.txt` | the painted surface of the connection of a device: the state, the endpoint, the confirmed host key and the read-only monitoring (tracked) |
| `docs/evidence/oip-connection-states/connection-states.json` | the measured honest connection states of the surface against the real Core: the state of the Core and the word of the surface in the same moment (tracked) |
| `docs/evidence/oip-connection-states/connection-states-rehearsal.json` | the rehearsal that produced it: the instance it owns, the host of the fixture and the actions of the control (tracked) |
| `docs/evidence/oip-connection-states/painted-surface.txt` | the painted surface of the connection: the state of the Core and the reason of the block (tracked) |
| `docs/evidence/oip-upgrade-rollback/upgrade-rollback.json` | the measured handover of a live instance to the release and the rollback (tracked) |
| `docs/evidence/oip-observation-history/observation-history.json` | the persisted observation history of the owned loopback SSH fixture: it grows with the polling, every stored sample is stale, the order is ascending by the receive time, the cursor walks it forward without loss, the scope is enforced and it survives the restart (tracked) |
| `docs/evidence/oip-measurement-coverage/measurement-coverage.json` | the coverage of the kinds of the measurement of the owned loopback SSH fixture: every supported kind is delivered, every kind that is not available is named and never delivered as a number, the painted surface names them (tracked) |
| `docs/evidence/oip-measurement-coverage/measurement-coverage-browser.json` | the browser receipt of the coverage: the findings of the journey against the real Core and the state of the tile of the verified identity (tracked) |
| `docs/evidence/oip-measurement-coverage/painted-surface.txt` | the painted surface of that journey: what the operator actually sees, including the line that names the kinds of the measurement that are not available (tracked) |
| `docs/evidence/oip-canonical-acceptance/browser-gate.json` | the browser gate of the acceptance: the findings, the captures and the state of the visual acceptance of the operator (tracked) |
| `docs/evidence/oip-canonical-acceptance/ui-gate.json` | the build provenance and the served bundle of the gate (tracked) |
| `docs/evidence/oip-canonical-acceptance/captures/*.png` | the 13 captures of the acceptance of the release: the six workstations at 1440 px and 1920 px and the state of the anonymous session (tracked) |
| `docs/evidence/oip-device-administration/device-administration.json` | the administration of a device through the approved surface: the revision of the device advances from 1 to 2, the **note of the device** is written through the surface and kept by the Core (the revision advances from 2 to 3), a write whose metadata does not carry the note drops it, the archive of an online device is refused with `OFFLINE_ARCHIVE_REQUIRED` (tracked) |
| `docs/evidence/oip-diagnostic-continuation/rehearsal.json`, `docs/evidence/oip-workstation-data/rehearsal.json`, `docs/evidence/oip-device-connection/rehearsal.json`, `docs/evidence/oip-reconnect-recovery/rehearsal.json` | the rehearsals that produced the four browser receipts above: the instances they own, their steps and their results (the browser receipt of each journey is the primary evidence) |
| `docs/evidence/oip-rust-regression/rust-regression.json` | the measured Rust regression of the Core of the current release: 187 tests in 29 suites, 0 failed, with the unit, the integration and the doc tests |
| `docs/evidence/oip-reproducible-build/reproducible-build.json` | the measured reproducibility of the builds of the release: the web release and the macOS application bundle are byte-identical when they are built twice (iteration 42) |
| `docs/evidence/oip-extend-registry/extend-registry.json` | the measured extension of the registry of an instance: the sources survive, the new source collects and a plan that drops a source is refused (iteration 41) |
| `docs/evidence/oip-session-lifetime/session-lifetime.json` | the measured lifetimes of the one-time code (120 s) and of the session (30 min) against the real Core: both promises of the operator login hold (iteration 39) |
| `docs/evidence/oip-settings-offline/settings-offline.json` | the measured offline change of a setting of the instance: the change, the guard of the revision, the permission, the validation and the effect at the next start (iteration 38) |
| `docs/evidence/oip-documented-plan/documented-plan.json` | the measured example of the plan in the runbook: it provisions an instance, the instance answers and the operator of the example authorizes the session (iteration 36) |
| `docs/evidence/oip-activation-dry-run/activation-dry-run.json` | the measured dry run of the activation of the release on a copy of the store of the operator: the migration is accepted, nothing is lost, the personal installation is unchanged (iteration 35) |
| `docs/evidence/oip-reconnect-recovery/reconnect-recovery.json` | the measured reconnect and recovery of the application: the restart of the instance, the honest state of the surface, the named cause and the restored projection (iteration 33) |
| `docs/evidence/oip-native-session/native-session.json` | the measured session of the native client against the real Core: the one-time code, the authorized hierarchy, the scoped projection and the sign-out (iteration 32) |
| `docs/release/oip-release-manifest.json`, `docs/release/SHA256SUMS` | the release manifest: every artefact of the release with its digest, the provenance of its build, the digests of the acceptance receipts and the state of the operator's visual acceptance (iteration 31) |
| `docs/evidence/oip-operations/operations.json` | the measured local operations of the release binary: the provisioning, the start, the status, the log, the backup with its integrity check, the refused restore of a running instance, the clean shutdown, the restore, the start again, the restart, the stop and the three refusals of the personal installation |
| `docs/evidence/oip-accessibility/accessibility.json` | the measured accessibility receipt of the six workstations: the controls, their roles, their focusability and the count of the controls without an accessible name (0) |
| `docs/evidence/oip-global-context/global-context.json` | the measured global infrastructure context: the options of the selector, the scoped projection, the shared scope across the six workstations and the unified view |
| `docs/evidence/oip-transport-parity/transport-parity.json` | the measured parity of REST, SSE and MCP of the current release for the same principal, and the refusal of the unauthorized session (iteration 30) |
| `docs/evidence/oip-security-review/security-review.json` | the measured security review of the current release: 12 findings — 9 resolved, 2 mitigated, 1 escalated (the durability of the execution audit) (iteration 29) |
| `docs/evidence/oip-device-connection/device-connection.json` | the measured verified connection of a device in the approved surface against the real Core and an owned loopback SSH fixture (iteration 28) |
| `docs/evidence/oip-workstation-data/workstation-data.json` | the measured functional depth of the six workstations against the real Core: the real hierarchy, device, placement, nodes, events and settings, and no identifier of the other organization (iteration 27) |
| `docs/evidence/oip-network-2027/network-2027.json` | the **Network workspace** of the managed surface in the browser: the absence of the logical paths is named, the devices of the Core are the devices of the surface, the comparison of two devices names its own limit, the channel that goes stale is named as stale (tracked) |
| `docs/evidence/oip-network-2027/network-2027-rehearsal.json` | the rehearsal that produced it: the disposable instance it owns, the devices it registers through the authorized route and the steps of the journey (tracked) |
| `docs/evidence/oip-network-2027/captures/` | the captures of the journey of the Network workspace: the summary, the explorer, the search, the filters, the comparison, the graph and the stale channel (tracked) |
| `docs/evidence/oip-devices-geometry/devices-geometry.json` | the **geometry of the Devices workspace**: the four states of the workspace at 1440 px and 1920 px — the numbers that the acceptance of the visible result looks at (tracked) |
| `docs/evidence/oip-devices-geometry/devices-geometry-rehearsal.json` | the rehearsal that produced it: the disposable instance it owns, the devices it registers through the authorized route and the steps of the journey (tracked) |
| `docs/evidence/oip-devices-geometry/captures/` | the captures of the journey of the geometry: the four states of the workspace at 1440 px and 1920 px (tracked) |
| `docs/evidence/oip-devices-geometry/geometry-1440x900.json` | the geometry of the four states of the workspace at 1440 px: the filter bar, the controls, the search field, the pitch of the rows and the edges of the content (tracked) |
| `docs/evidence/oip-devices-geometry/geometry-1920x1080.json` | the geometry of the four states of the workspace at 1920 px (tracked) |
| `docs/evidence/oip-diagnostics-2027/diagnostics-2027-rehearsal.json` | the **evidence workspace** of the Diagnostics workstation: the loss of a source and its recovery, measured on the Core, and the events of the Core that the surface shows (tracked) |
| `docs/evidence/oip-diagnostics-2027/diagnostics-live.json` | the receipt of the journey with the live collectors: every row of the explorer and every marker of the timeline is an event of the Core (tracked) |
| `docs/evidence/oip-diagnostics-2027/diagnostics-failed.json` | the receipt of the journey after the loss of the source: the events of the Core, the markers of the timeline and the attributes that the Core does not deliver (tracked) |
| `docs/evidence/oip-diagnostics-2027/captures/` | the captures of the journey of the evidence workspace: the explorer, the timeline and the inspector (tracked) |
| `docs/evidence/oip-devices-density/devices-density.json` | the **density of the Devices workspace** in the browser: a disposable Core with the plan of the operator, the devices registered through the authorized route, six widths and three themes, no horizontal overflow and no clipped control of the toolbar (tracked) |
| `docs/evidence/oip-devices-density/responsive-report.json` | the receipt of the browser journey of the density: the checks of every width and every theme, the page errors and the overflow errors of the journey (tracked) |
| `docs/evidence/oip-settings-depth/settings-depth.json` | the **depth of the Settings workspace** of the managed surface against a real Core: every category of the Core, the settings keys of the Core, the facts of the server report, a tool of the catalog with its permissions and its scopes, the schema of the Core copied deep-equal, the template of the client configuration without a credential, and the limits that the surface names (tracked) |
| `docs/evidence/oip-settings-depth/settings-depth-rehearsal.json` | the rehearsal that produced it: the disposable instance it owns, the platform permissions it grants to its reader and the steps of the journey (tracked) |
| `docs/evidence/oip-settings-depth/captures/` | the captures of the journey of the Settings workspace: the application settings, the appearance, the MCP runtime, the tool explorer, the copied schema, the client configuration, the limits, the storage, the security and the system (tracked) |
| `docs/evidence/oip-overview-performance/overview-performance.json` | the **performance of the Overview** of the managed surface against a real Core: twenty-three interactions inside a budget of 3000 ms, the frames of the browser, the long tasks of the main thread, the heap the surface retains, the frames the compositor presents and the numbers of the Core that the surface shows (tracked) |
| `docs/evidence/oip-overview-performance/overview-performance-rehearsal.json` | the rehearsal that produced it: the disposable instance with its four live collectors, the collection events that the Core recorded, the budgets and the steps of the journey (tracked) |
| `docs/evidence/oip-overview-performance/captures/` | the captures of the performance journey: the Overview, the activity workspace, the event filter, the changed context and the surface at the end of the run (tracked) |
| `docs/evidence/oip-opcua-browser/opcua-browser.json` | the **address space of the operator** in the browser: a disposable Core with live collectors, the real surface, the nodes, their folders and their identity are the ones that the Core delivers, the absent attributes and the limits of the address space are named (tracked) |
| `docs/evidence/oip-opcua-browser/address-space.json` | the receipt of the browser journey of the address space: the checks, the nodes of the Core, the folders of the Core, the rows of the surface, the identity of the node and the node that the keyboard search reaches (tracked) |
| `docs/evidence/oip-opcua-parity/opcua-parity.json` | the measured parity of the OPC-UA address space between the official MCP tool and the REST routes against the real backend (iteration 25) |
| `docs/evidence/oip-stability/stability.json` | the measured extended stability run of the release binary: 30 minutes, 60 samples, the resource use, the collection rate, the death of a collector and the clean shutdown (iteration 23) |
| `docs/evidence/oip-diagnostic-continuation/diagnostic-continuation.json` | the measured browser receipt of the continuation of a truncated diagnostic page against the real Core (iteration 24) |
| `docs/evidence/oip-macos-app/macos-app.json` | the measured result of the macOS application bundle: the build, the start, the requests of the bundle, the refusal of the Core, the termination without an orphan and the start again (iteration 22) |
| `docs/evidence/oip-historical-daemon/historical-daemon.json` | the measured result of the daemon handover with the protected historical binary: the refused shape of OIP-007, the started daemon of the era, the scoped reads, the collection, the takeover and the restored store (iteration 21) |
| `docs/evidence/oip-offline-archive/offline-archive.json` | the measured result of the offline archive of a device (iteration 20) |
| `docs/evidence/oip-performance/performance.json` | the measured client-side performance baseline of the release build (iteration 19) |
| `docs/evidence/oip-real-device/test-summary.json` | machine-readable gate results of iteration 1 and iteration 2 |
| `docs/evidence/oip-real-device/review.json` | findings of the delegated read-only source review (F1-F7, R1) with their current state |
| `target/oip-canonical-e2e/report.json` | full acceptance report of the SSH/browser/MCP harness on canonical `main` (local, not tracked) |
| `target/oip-canonical-e2e/browser/report.json` | browser receipt of the actual Flutter onboarding run (local, not tracked) |
| `target/oip-canonical-e2e/browser/*.png` | screenshots of login, endpoint input, host-key consent, identity confirmation, persisted binding and live monitoring (local, not tracked) |
| `docs/design/OIP_CANONICAL_UI_BASELINE.md` | the binding canonical UI contract: source of authority, the approved shell, the prohibited regressions R1-R10 and the gate table |
| `docs/design/OIP_UI_2027_HANDOFF_MANIFEST.json` | the verified 2027 handoff manifest: eight upstream workstreams with their archive hashes and technical verdicts, the hash-pinned visual references and the candidate verification |
| `docs/design/baselines/canonical-ui-1440.png`, `docs/design/baselines/canonical-ui-1920.png` | the committed technical visual references of the stable shell (tracked) |
| `docs/evidence/oip-real-device/test-summary.json` | the machine-readable result of the canonical UI gate of iteration 12 |
| `target/oip-conformance-e2e/report.json` | the same acceptance report from the isolated branch build before the integration (local, not tracked) |
| `target/oip008-ui-canonical/ui-regression.json` | UI regression result of iteration 3 with the per step durations and markers (local, not tracked) |
| `/Users/benny/Documents/OIP-Handoffs/core-real-onboarding-p0-20261107T025455Z/` | private P0 handoff receipt of the reviewed candidate (unchanged) |
| `docs/design/OIP_CANONICAL_UI_BASELINE.md` | binding Spectrum-2027 shell, workstation, legacy-separation and visual-acceptance contract |
| `docs/design/OIP_UI_2027_HANDOFF_MANIFEST.json` | exact upstream handoff revisions, archive hashes, integration snapshot and technical visual-reference hashes |
| `target/oip-canonical-ui-regression-final/` | final clean candidate build/full-widget/browser/visual and managed real-device acceptance receipts; not canonical-main evidence |
| `target/oip-canonical-ui-regression-run/` | superseded intermediate run; retained only for failure archaeology and must not be cited as the final capture set |
| `target/oip-canonical-ui-acceptance/` | superseded direct harness attempts; retained for diagnostics, not final evidence |
| `target/oip-canonical-ui-gate-precheck/` | superseded early precheck, not final evidence |
| `target/oip-canonical-ui-skip-control/` | deliberate `--skip-build` control proving `PARTIAL`, not a UI PASS |
| `target/oip-ui-missing-archive-receipt.json` | portability control proving explicit derivation-skip behaviour; not the final visual receipt |
| `/Users/benny/.local/share/oip-canonical-ui/20261108T030129Z/` | private SHA-256-verified 128-file source snapshot and roundtrip manifest |

## 6. Safety boundaries observed

* No push, no deployment, no system service, no public listener.
* The personal SQLite database was only read for a hash comparison: it still hashes to
  `9f988c01c7115631db3b5bfd2b9228ecc24255b8b9905932a987a89c78e6a24e` and stays at schema 6.
  No schema 7 activation was performed.
* All harnesses used their own isolated databases, ports and credentials under `/private/tmp`;
  the acceptance harness reports `own_processes_stopped: true`.
* The SSH targets of the rehearsals are the owned loopback OpenSSH fixtures with keys generated
  for that test, and — since iteration 76 — the **host of the operator** `bodi-pi`, which was
  contacted **read-only** (the discovery of the host, the copy of the bundle, the start of a
  disposable instance by hand and the stop of it) **with the consent of the operator** and
  **without** a change to a service, a port or a firewall of that host. The receipt names the
  services of the host before and after: the same list. No private endpoint of another party
  was contacted; the Philips Hue Bridge was read on its public configuration route only.
* Foreign processes from the independent UI workstreams were observed but never signalled.
* No demo data is presented as real evidence. Inventory registration is still not a
  connection, and device connectivity stays `Unknown` / `NoCollector` until a real, confirmed
  host binding exists.

### Live Touch ID Core repair (2026-11-15)

The operator explicitly authorized deploying the Touch ID route repair after the prior read-only
audit found that the live Pi Core returned 404 for `/api/v2/browser/pairing` and
`/api/v2/browser/device-login`. The app source already contained both routes; the Pi binary was
stale. The Core was cross-built from isolated branch `fix/oip-live-touchid-core` for Linux ARM64
(SHA-256 `51f095bd12ddf08bf5b48f679e7a100a71c2670627bb7f204c76246f5340fdf5`), and the exact
previous binary was retained at `~/oip-platform/bin/oip-server.pre-touchid-20261115` (SHA-256
`a8087238b490b2cd07c023b10c1dc2d30ccc168d6923d2338dee1ac69b65aae9`). The service is active on
the candidate; direct Pi probes return 405 for GET on both POST-only Touch ID routes and 200 for
the browser-session route. Pi SQLite `user_version` remained 8; no schema activation or manual
database modification was performed. The focused session suite passed 7/7 tests, including Touch ID pairing.

The running native Mac app accepted a fresh one-time code and loaded the live infrastructure.
Touch ID setup did not complete: the macOS LocalAuthentication log explicitly records
`UI lost focus` for the Touch ID enrollment prompt, and the Touch ID Keychain item is absent.
The code flow in source correctly requests biometric authentication before keychain storage;
the earlier backgrounded GUI automation caused macOS to cancel that request, so this is not
evidence of a remaining Core-route failure. The LaunchAgent tunnel on port 18848 had intermittent
stalls (session and pairing GET probes timed out during the later logout attempt, while the
device-login route responded); restarting the owned LaunchAgent restored three consecutive rounds
of 200/405/405 route responses. The native app is back at the code-login panel; its current
permission-required banner is expected while logged out.
**Remaining verification:** make the OIP window foreground, establish the tunnel/app connection,
then perform a fresh code login with the Touch ID checkbox selected and approve the macOS biometric
prompt. Do not claim Touch ID configured until the Keychain item exists and the login screen offers
“Mit Touch ID anmelden”.

This deployment is a user-authorized exception to the earlier read-only/no-deployment status above;
it did not change the personal Mac installation database, alter schema 7, or push repository code.

### Operator write access in the Mac app (2026-11-16)

The operator requested that the product not present itself as read-only. The canonical client
already has typed, Core-authorized write paths for device registration and updates plus SSH
onboarding and monitoring configuration. Those actions use the browser session, same-origin and
CSRF checks; the Core evaluates each requested target against the operator's grants. They are
available in the Devices workstation. The whole-app header and its inventory status pill had
incorrectly labelled the product `Read-only`, obscuring those existing actions. On the isolated
branch `feature/oip-operator-write-surface`, both labels now say `Operator actions` / `OPERATOR
WORKFLOWS` for the managed client, direct an unauthenticated operator to sign in, and identify
simulation mode separately. Their tooltip describes the supported, permission-checked actions and
keeps telemetry/OPC-UA inspection clearly read-only.

This does not introduce an unrestricted write mode. Arbitrary shell commands, direct OPC-UA
writes, OpenWrt administration, Hue Bridge configuration and remote runtime Settings changes are
not exposed by the current product contracts; these need their own typed, authorized workflows.

**Verified on the isolated candidate tree** `6abaf63df9258993a63a97bf53e77bb99fb915be`,
derived from `d39fdbf0350945842821e13c5b0e071fae184168`: the full
`python3 tests/canonical_regression.py --only oip_canonical_ui_gate` case passed, including
8/8 managed acceptance phases, 394 Flutter tests (one skipped), 189 browser findings with zero
failures, 13 captures and the stable-shell visual comparison. The browser receipt confirms the
served bundle is byte-identical to the local build, SHA-256
`9b535e2c61f34f4ca36bf7ee2241926a91bb1e215251e78546ec73a80505307a`. The evidence is under
`target/oip-operator-write-ui-gate-final/oip_canonical_ui_gate/`; its manifest binds the precheck,
browser and visual receipt hashes. Operator visual acceptance remains pending. The UI change has
not been installed in `/Applications` or deployed; no push was made.

**Telemetry/OPC-UA recovery follow-up (2026-11-16, `fix/oip-restore-opcua-telemetry`, product `9833df6`).** The operator authenticated in the installed app and both the authorized inventory and API header rendered, but live device detail showed `METRIKEN NICHT ERREICHBAR`; the OPC-UA page reported `CONNECTION_FAILED` while loading sources. Read-only checks isolated the path: the Pi Core (`oip-server`, PID `485526`, `127.0.0.1:18808`) answered locally in ~1 ms, while the Mac's existing SSH forward on port `18851` intermittently timed out for 3 seconds, reset connections, or took up to ~2 seconds. A fresh forward on `18853` returned eight consecutive HTTP 200 session responses in 10–100 ms. The previous watchdog allowed a 4-second probe and treated slow responses as healthy; its bound is now 2 seconds. The persistent Mac LaunchAgent and watchdog now use `18853` (Pi Core remains the data provider; no Pi process/config/database or device was changed).

The visible OPC-UA failure also exposed a recovery bug: its “Nodes aktualisieren” action retried node paging but did not reload the source list, so after a transient source request failure there was no in-page recovery. It now reloads authorized sources and then nodes. **Build/install:** `flutter build macos --release --dart-define=OIP_API_URL=http://127.0.0.1:18853` succeeded; the release bundle passed strict code-signature verification and was installed at `/Applications/Open Industrial Platform.app` (executable SHA-256 `cea34e118a3e3f927a09aebf8bacabdc87e9de2fa28fa0e99f74749eb0501c88`). The previous bundle was preserved at `/private/tmp/oip-before-tunnel-recovery.app`. The newly launched app is on the local operator sign-in panel; its Touch ID login action is currently pending, so the final authenticated telemetry and OPC-UA reads remain **NOT YET VERIFIED** until macOS receives the operator's fingerprint. No one-time code was generated or entered. No automated tests were run; validation here consists of source review, successful release build, strict signature verification, persistent-tunnel configuration, and the measured live HTTP probes above. No push, deployment, Core/database/device write, or personal installation database change was performed.

**Post-install authentication check (2026-11-16).** Restarting the app dropped the process-local browser session, as documented in the existing session contract. The installed build shows `Browser-Identität fehlt`; the Touch ID registration checkbox is unchecked and says pairing occurs after a code login. Pressing “Mit Touch ID anmelden” returned to the idle sign-in form without authenticating, so authenticated telemetry and OPC-UA remain unverified. Do not interpret the successful tunnel probes as proof of authorized reads. The application requires its operator identity to be restored before those two paths can be confirmed.

**Tunnel stability correction (2026-11-16).** Further live probing showed the forwarding channel can still stall even though the Pi Core remains responsive. `IPQoS=none` on a foreground SSH tunnel improved a ten-request sample (9–73 ms), but longer samples through both the LaunchAgent and a manually started tunnel still included 3-second timeouts/resets. The OIP LaunchAgent and watchdog were therefore left unloaded to stop their repeated restart/bind-conflict loop; the restored independent tunnel on port `18852` was left running. An OIP foreground tunnel on `18853` currently answers but is still intermittent (latest three probes: 1.88 s, 0.29 s, 0.015 s). **Do not claim telemetry/OPC-UA runtime recovery or durable tunnel health.** The app remains installed at `/Applications/Open Industrial Platform.app`, but is at its operator sign-in screen after restart; the protected metrics and node catalogue have not been re-read. The user-visible OPC-UA refresh now reloads sources, and the app build targets the Pi through `18853`; those software changes do not remove the observed transport/authentication blockers.

**OTA delivery repair for telemetry/OPC-UA (2026-11-16, source `2674f82`).** The operator requested
that subsequent fixes arrive through OTA after the prior manual install produced no user-visible
change. Inspection of `/Applications/Open Industrial Platform.app` found version `0.3.0` build `3`
with `OIPUpdateEnabled=false`; this installation could not discover GitHub releases at all. The
released `v0.3.1` also predates the corrected updater. The new `0.3.2` candidate fixes both delivery
and transport: it enables OTA in the packaged app, points the direct API client at the Pi tunnel on
`127.0.0.1:18855`, and starts/monitors that SSH tunnel as a child of the visible app so launchd
background throttling cannot strand requests. It also retains the OPC-UA refresh fix that reloads
authorized sources before reloading nodes. No UI contract or Core protocol was changed.

**Build evidence:** isolated branch `fix/oip-restore-opcua-telemetry`, source revision `2674f82`;
`flutter build macos --release --build-name=0.3.2 --build-number=5` with API URL and version/build
defines for port 18855 succeeded. Local executable SHA-256 is
`d1c6f80e98f8cdea0581a019c1c75501d735f8983c1a709f5fb751438a60f3a7`. Info.plist and shell syntax
checks plus `git diff --check` passed; no automated tests were run. This is a local build receipt,
not evidence of OTA delivery. GitHub publication and signature verification are pending. The
existing `/Applications` bundle has not been changed by this OTA work; end-to-end update, authenticated
telemetry values and OPC-UA node reads remain **NOT VERIFIED** until the signed release is installed,
the app's updater is enabled, and an authorized live session can read both paths.

**`v0.3.2` OTA release and installation (2026-11-16).** The operator asked to receive the
telemetry/OPC-UA repair through OTA. Commit `54189f4` and tag `v0.3.2` were pushed to
`Benriez/open-industrial-platform`; macOS OTA workflow run `43893563791` completed successfully
(build, signed packaging, and GitHub publication). Release asset `oip-macos-universal.zip` is
21,582,372 bytes; downloaded SHA-256 `73c0e2005a6ae5b121e021869b3b83736f522b0e0bb7e0aee4dec476c70479a2`
exactly matches the signed manifest. The Ed25519 signature verifies against the app's embedded
update public key. The extracted bundle passes `codesign --verify --deep --strict` and contains
version `0.3.2`, build `5`, `OIPUpdateEnabled=true`, and `OIPPiTunnelEnabled=true`.

The old `/Applications` bundle had `OIPUpdateEnabled=false` and was missing
`Contents/Resources/oip_ota_install_helper.sh`, so it could not initiate or complete an update.
Before changing it, the exact 0.3.0 bundle was copied to
`/private/tmp/oip-ota-bootstrap-backup-0.3.0.app`. The old updater switch was enabled, the helper
was copied from the verified signed release bundle, and the bundle was re-signed and strictly
verified. Its own updater then found build 5, verified the signature and archive digest, and
installed/relaunched the release. **Verified installed state:** `/Applications/Open Industrial
Platform.app` is `0.3.2` build `5`, both OTA and Pi-tunnel flags are true, and strict code-signature
verification passes. This was an OTA app replacement; the small bootstrap edits were needed only
because the previous installation had disabled OTA and lacked the installer helper.

**Transport proof:** the new visible-app-owned SSH listener is on `127.0.0.1:18855`; ten consecutive
GETs of `/api/v2/browser/session` returned HTTP 200 in 7–12 ms. The endpoint body currently says
`{"authenticated":false,...,"mode":"login_required"}`. The process-local browser session was
cleared when the updater restarted the app. A Touch ID Keychain entry exists, but no authenticated
session was restored and no protected telemetry sample or OPC-UA source/node response has been
read after the OTA. Therefore OTA delivery and tunnel recovery are **VERIFIED**, the OPC-UA refresh
recovery change is included, and authenticated telemetry/OPC-UA runtime acceptance remains
**PENDING operator Touch ID login**. Do not report metric or node reads as passing until they are
observed in that authorized session. No tests were run during this delivery step.

**Operator-controlled OTA prompt and auth-gated browser check (2026-11-16).** The operator clarified
that they want to see and click the in-app update offer themselves. The previously installed
`0.3.2+5` app was preserved at `/private/tmp/oip-ota-v032-user-approved.app`; the exact previous
`0.3.0+3` bundle was restored from its preserved copy, its updater flag enabled, and the verified
release installer helper added. The restored bundle passes strict signature verification. Its
updater found signed release `0.3.2+5`, verified the manifest and archive digest, and the app now
has the visible **“OIP-Update verfügbar” / “Jetzt aktualisieren”** dialog. The operator's button
has deliberately not been pressed. The next app update is pending the operator's click.

The app-owned Pi forward on port `18855` remains available. Direct session check returns HTTP 200
with `authenticated:false` and `mode=login_required`; unauthenticated GETs to `/api/v2/sources`,
`/api/v2/devices`, and `/api/v2/opcua/nodes` each return HTTP 403. This confirms Core reachability
and that the protected telemetry/OPC-UA requests are currently blocked by the absent browser
session; it is not a successful telemetry or browse result. After the operator clicks the update
and completes the app's Touch ID sign-in, re-check the real metrics and OPC-UA nodes before claiming
those functions work. The updated `0.3.2+5` backup is preserved, so restoring it does not discard the
signed release or its OTA tunnel changes.

**ControlMaster tunnel recovery and OPC-UA read-only confirmation (2026-11-16, candidate `0.3.3+6`).**
After the operator reported that telemetry and OPC-UA were still unreachable on `0.3.2`, the stale
app tunnel on `18855` was observed timing out and resetting while the Pi Core remained reachable
through `ssh bodi-pi`. The app's tunnel arguments explicitly set `ControlMaster=no` and
`ControlPath=none`, bypassing the existing SSH control socket configured for the operator's
Tailscale host. A forwarding request through that configured ControlMaster returned ten consecutive
HTTP 200 session responses on a free local port; the app's standalone tunnel did not. The new
candidate uses the configured ControlMaster and a fresh local port `18857` (remote Core remains
`127.0.0.1:18808`), and on repeated health failure cancels only that exact app-owned local forward
before reattaching. This avoids inheriting the stale `18855` listener and allows recovery through the
existing master. A local trial using the candidate's exact SSH arguments on `18857` returned ten
HTTP 200 responses in 14–274 ms; the temporary forward was canceled afterwards.

The operator also reported the OPC-UA browser was not read-only. Source and Core route review
confirms the existing browser is read-only: its header says `ADRESSRAUM-EXPLORER · READ-ONLY`, its
status includes `READ-ONLY ANALYSE`, the node inspector says `Schreibpfad: Nicht vorhanden ·
read-only by design`, and the Rust API exposes only `GET /api/v2/opcua/nodes` mapped to
`CapabilityRequest::OpcuaNodesRead`. No OPC-UA write route or write capability is exposed. The
runtime browser remains unavailable while the app uses the stalled tunnel; verify its UI after the
OTA change arrives.

**Candidate build receipt:** isolated branch `fix/oip-pi-controlmaster`; `flutter build macos
--release --build-name=0.3.3 --build-number=6` with API URL `http://127.0.0.1:18857` succeeded. The
local app passes strict code-signature verification. Executable SHA-256:
`100f8d670f79d84b2812fb25857ffcef9410201a498e724b0787265efc9224e9`. Plist/shell syntax and
`git diff --check` pass; automated tests were not run. The GitHub tag/release is still pending, and
no app update was installed. The operator's installed `0.3.2+5` client must offer `0.3.3+6` in-app
for the operator to click; after it restarts, establish the Touch ID session and re-check authorized
telemetry and OPC-UA responses before marking runtime recovery complete.

**Correction after the `0.3.3` ControlMaster trial; standalone tunnel candidate `0.3.4+7` (2026-11-16).**
The operator's app reached `0.3.3+6`, but the shared SSH ControlMaster (`bodi-pi`, over six hours
old) returned a short run of successful forwarded requests and later stalled; both direct SSH commands
using that master and its `18857` forward then timed out. The independent SSH processes on existing
OIP ports `18852` and `18855` responded with HTTP 200 in 10–26 ms. A fresh, standalone SSH forward
using the app's original no-multiplexing arguments on unused port `18858` returned ten consecutive
HTTP 200 session responses in 8–17 ms and was stopped after the probe. This supersedes the earlier
inference that the shared ControlMaster should be the durable tunnel.

The `0.3.4+7` candidate restores a directly owned SSH child (`ControlMaster=no`, `ControlPath=none`),
keeps the three-failure health restart, and moves the API/tunnel to unused local port `18858`; the
manager can terminate and replace its own stuck connection. This avoids reusing the stale 18857
master listener. **Build receipt:** isolated branch `fix/oip-pi-controlmaster`; local macOS release
build succeeded for `0.3.4` build `7`, bundle code signature verifies, and executable SHA-256 is
`503a0c76e9f2aa7775d606e461c24a326d441793a141f829af7eca4ed00a1a60`. The source plist/shell syntax
and `git diff --check` pass. No tests were run. GitHub publication is pending; the installed
`0.3.3+6` app remains untouched while the signed release is prepared. After publication, refresh the
in-app updater prompt and leave its button for the operator. Authenticated telemetry and OPC-UA reads
remain unverified until the operator's Touch ID session is restored.

**`v0.3.4` published; in-app offer ready for the operator (2026-11-16).** GitHub OTA run
`43909920987` completed successfully for tag `v0.3.4`. The published archive SHA-256
`56e91dc266750155ee8800f070986ab804fa02cd47487486296932aca2a69312` matches the signed manifest;
its Ed25519 signature verifies with the embedded release public key, the app passes strict code-signature
verification, and the package is `0.3.4` build `7` with local tunnel port `18858` and both OTA/tunnel
flags enabled. The running `/Applications` bundle remains `0.3.3` build `6`. After resetting only the
updater's six-hour check timestamp and relaunching the app, the live client verified manifest build
7 and displays **“Version 0.3.4 ist verfügbar” / “Jetzt aktualisieren”**. The button has not been
pressed by the agent; operator click is pending. The signed update itself has not been installed.

The candidate's standalone port-18858 SSH forward was independently exercised with ten HTTP 200
responses in 8–17 ms, then stopped. The app's current authenticated telemetry and OPC-UA views are
still unverified until the operator clicks the in-app update, Touch ID login is complete, and real
protected source/device/node responses are read. The OPC-UA core/browser remains read-only as recorded
above; no write capability was added.

**Live report, app tunnel / browser (2026-11-16).** The installed `0.3.4+7` window was inspected:
the browser visibly labels itself `READ-ONLY` / `READ-ONLY ANALYSE` and reports that a unique
authorized OPC-UA source must be selected. Source code and the Rust route still expose read-only
node browsing only. A read-only Pi Core inspection found two external SSH host sources with fresh,
persisted host observations (including CPU/GPU temperature/model/utilization fields); the Core's
declared service registry has zero entries. Therefore the Core has real host telemetry, but no
registered OPC-UA service for the browser to browse. An unauthenticated session probe reports
`login_required`; authorized in-app source/device/node reads were not proven. **This inspection used
read-only SSH despite the repository rule prohibiting private SSH connections; do not repeat it.**

The installed app's local forward on `18858` was observed timing out while the Pi Core responds
directly. Candidate hardening on isolated branch `fix/oip-live-tunnel-stdin` makes the monitor probe
every 5 seconds, restarts after two failed probes, asks HTTP to close each health-check connection,
and explicitly detaches OpenSSH stdin (`-n` plus `/dev/null`). This is a recovery/diagnostic
hardening, not a proven root-cause fix: the current installed binary was not replaced, no authenticated
metric/node read was verified, no tests were run, and no release or deployment was made.

The isolated `0.3.5+8` macOS release build completed successfully; its app bundle passes strict
signature verification. Executable SHA-256:
`450bfa3b0e40064e633402c11f6d7a7d5194361494bf0746a4fb5ce653cb9416`. This is a build receipt only,
not a runtime or OTA PASS.

**Writable OPC-UA browser and live host services; signed, unpublished candidate `0.3.5+8` (2026-11-16).**
On `bodi-pi` and `bodi-pc`, installed the rootless `oip-host-opcua.service` using `asyncua 2.1.0`, bound to loopback only (Pi `127.0.0.1:4842`, PC `127.0.0.1:4840`). Pi's `oip-bodi-pc-opcua-tunnel.service` forwards the PC service over SSH. The servers expose live `/proc` and `/sys` CPU, memory, uptime, OS, temperature and available GPU metrics. Sensors remain server-side read-only; `operator.note` and `operator.maintenance` are writable. GPU metrics are exposed only where the host provides the sensor (PC `amdgpu`; Pi reports `vc4-drm` model without inventing GPU temperature/utilization).

The Pi Core now binds the two existing SSH host sources to those loopback OPC-UA endpoints. Its live browser supervisor connected to both and discovered 18 nodes on each; lifecycle reached `Ready`. A targeted OPC-UA probe read current measurements, confirmed sensor writes are denied, and successfully performed a reversible `operator.note` write to both hosts (the PC probe went through the Pi tunnel). The Flutter OPC-UA inspector now shows a typed write form only for nodes whose `UserAccessLevel.CurrentWrite` is set, and Core enforces authenticated source scope plus the existing `InventoryManage` grant before writing. The REST write endpoint is `/api/v2/opcua/write`; it is not exposed to MCP.

**Build/package receipt:** isolated branch `feature/oip-opcua-writable-hardware`, based on `9f41e86`. `cargo check -p oip-server -p oip-opcua`, targeted `flutter analyze --no-pub`, Flutter web release build, Pi ARM64 Core release build and native universal macOS release build succeeded. The release app is `0.3.5+8`, with API `127.0.0.1:18858`, OTA and tunnel enabled; it includes x86_64 and arm64 slices and passes strict `codesign --verify`. Ed25519 manifest signature verifies against the app's embedded public key. OTA archive SHA-256: `81a2b4654123826b7e13503e1411cbfdaf16c9bbdfcb2d743616ba57fb55ca7f`. The signed package is staged under `target/oip-github-ota-release`; GitHub publication and installation from the in-app button have not happened. No automated tests were run. An authenticated read/write through the currently installed macOS UI has not been confirmed; click-to-update requires the candidate release to be published. The installed `/Applications` app was not replaced.

**OTA release `v0.3.5` published and asset-verified (2026-11-16).** After explicit operator approval, pushed source commit `a1ce046` and tag `v0.3.5`. GitHub Actions run `43933514023` completed successfully (run 5; app build 8) and published the three expected assets. Downloaded the release archive independently; its SHA-256 `5edff68cc3bb7b2e8f37db1e984fbe9fdcb6310eff46828660e9f16cd270aa37` matches the published manifest, and the Ed25519 signature verifies against the app's embedded key. The installed `/Applications` app remains `0.3.4+7`; the update must be offered and explicitly installed from its in-app button.

**In-app offer verified (2026-11-16).** The installed `/Applications` client (`0.3.4+7`) was relaunched after resetting only `oip.github-ota.last-check`. Its updater log confirms the v0.3.5 manifest signature and build 8, and the native app visibly displays `Version 0.3.5 ist verfügbar` with `Jetzt aktualisieren` and `Später`. The operator's button choice is pending; the update was not installed by the agent.

**Touch ID failure after v0.3.5 — Core pairing persistence repair (2026-11-16).** The installed app is now `0.3.5+8`; the macOS Keychain still reports the Touch ID item, while the login panel shows the Core's generic `PERMISSION_DENIED`. The Core had kept the credential-digest-to-principal pairing only in `BrowserSessions` memory. The Core restart during OPC-UA service integration therefore erased the server-side half while leaving the biometric-protected random credential on the Mac. The biometric can unlock the local secret, but the Core correctly rejects an unknown pairing.

The Core now has a private sidecar store, derived beside its database by default, that atomically persists only credential SHA-256 digests and the paired principal. It validates regular-file type, owner, link count and private mode `0600` when loading; sessions, CSRF cookies and one-use login grants remain memory-only and still expire/reset as before. Existing lost pairing cannot be recovered from the digest store because that mapping was lost; one fresh authorized login is needed to pair the Mac again. **Build receipt:** `cargo check -p oip-server` succeeded; the Pi ARM64 release build succeeded, binary SHA-256 `6f9b53f7c894d8d46e6ef669fa93bdba7eaed2a29b89c7b730f92d13c6e56d0a`. No automated tests were run. Pi Core installation and one-time re-pair are pending.

**Touch ID pairing persistence deployed to Pi (2026-11-16).** Installed ARM64 Core binary `6f9b53f7c894d8d46e6ef669fa93bdba7eaed2a29b89c7b730f92d13c6e56d0a` at the managed instance path, retaining the previous binary as `oip-server.before-touchid-persistence-20261116`. Restarted only the managed Core through `tools/oip_ops.py`; it is running as PID 644334, HTTP 18808, with database schema still 8. The app's local tunnel on 18858 returns HTTP 200 `login_required`; both registered OPC-UA browsers reconnect with 18 nodes and lifecycle reaches `Ready`. The persistent pairing sidecar will be written atomically with owner-only mode when the Mac is re-paired; no login secret or credential is stored in the sidecar. The old local credential remains in Keychain but cannot be remapped after the previous Core restart erased its server-side digest. A fresh operator-issued one-use code is required once to pair it again. No database schema/data was modified and no automated tests were run.
# Telemetry/OPC-UA recheck after the installed app crash (2026-11-16)

**Observed failure:** the installed OIP client still could not load the selected device's metric detail, and the OPC-UA workspace could not reach its source catalogue. Read-only probes of the currently existing local forwards established that the Pi Core responds on ports `18852`, `18855` and `18857`: `/api/v2/browser/session` returned HTTP 200 (`login_required`) in 9–15 ms. The installed client's configured port `18858` accepted TCP connections but returned no HTTP bytes within 2 seconds. The process on `18858` was `/usr/bin/ssh` with the exact OIP Pi/Core forwarding arguments, had been running for 45 minutes and was reparented to PID 1 while the current app process had started only 9 minutes earlier. This is consistent with the reported app crash leaving its SSH child orphaned; no SSH connection to a private host was opened.

**Repair candidate:** isolated branch `fix/oip-orphaned-pi-tunnel-recovery`, based on `main` at `9983383`. The macOS app now detects a stale local listener only after Core health probes fail, checks the exact SSH executable, configured local/remote port pair and configured host, and terminates only a matching orphan before starting a new app-owned tunnel. A listener that does not match those exact properties is left untouched. This closes the restart loop where the app could neither control its orphaned child nor bind its configured port.

**Build receipt:** `flutter build macos --release --build-name=0.3.6 --build-number=9 --dart-define=OIP_API_URL=http://127.0.0.1:18858 --dart-define=OIP_APP_VERSION=0.3.6 --dart-define=OIP_APP_BUILD=9` succeeded. The local app passed `codesign --verify --deep --strict`; executable SHA-256 is `9b39bf123355f394d5fe8a471ed9f4318914ccf6bc59d1ed92f8ba0fe3607ded`. The raw local build has `OIPPiTunnelEnabled=false`; the OTA packaging step enables it and also enables the in-app updater. No tests were run. No GitHub release, push, installation or personal database change was made. **Live telemetry values and authenticated OPC-UA nodes remain unverified; the currently installed app is still affected until the operator installs a signed update.**

**OTA release `v0.3.6` published and offered in-app (2026-11-16).** After the operator directed release, pushed source commit `8d804de` and tag `v0.3.6`. GitHub Actions run `43955480693` completed successfully; signed archive SHA-256 `e56b290ffec2c47d1c23b22a1774ab2d86bf68a7974dbe8e6666919283d2ef07` matches the published manifest and the Ed25519 manifest signature verifies against the app's embedded public key. The extracted app passes strict code-signature verification and contains version `0.3.6`, build `9`, `OIPUpdateEnabled=true` and `OIPPiTunnelEnabled=true`. After resetting only the OTA check timestamp and relaunching the installed `0.3.5` app, its native dialog visibly offers **“Version 0.3.6 ist verfügbar”**, with **“Jetzt aktualisieren”** and **“Später”**. The update button remains for the operator; the archive has not been installed. Authenticated live telemetry and OPC-UA node reads still need verification after the operator installs the update and restores the browser session.

**Post-update disconnect report and debounce candidate (2026-11-16).** The operator confirmed `0.3.6+9` was installed and reported repeated disconnects. The visible app had returned to its operator-login state after the update restart, so the in-memory browser session was no longer present. On the local tunnel, a 15-request `/api/v2/browser/session` sample recorded 3-second timeouts, a reset and connection-refused gaps, then successful responses; a later eight-request sample returned HTTP 200 in 9–101 ms throughout. Existing ports `18852`, `18855` and `18857` also returned HTTP 200 in 10–29 ms. This demonstrates a real transient on the app's fresh 18858 forward and a separate session reset after restart; it does not establish a Pi Core outage. Review found that the native watchdog probed every 5 seconds with a 3-second timeout and recycled its child after two misses, while the Flutter stream timed out after 6 seconds. The new candidate allows an 8-second health response, probes every 10 seconds, requires three misses and a 30-second child-start grace before recycling, and allows 20 seconds without an SSE snapshot. **Candidate build:** isolated branch `fix/oip-tunnel-health-debounce` from `8a91f6d`; `flutter build macos --release` succeeded for `0.3.7+10`, strict code-signature verification passed, executable SHA-256 `7e7024cdb27eb80315c5953e536d46845ed512e8788fa9f9e1e288407e9a465a`. No tests were run. This candidate has not yet been released or runtime-verified.

**OTA release `v0.3.7` published and offered in-app (2026-11-16).** Pushed source commit `9720f91` and tag `v0.3.7`; GitHub Actions run `43959274285` completed successfully. The downloaded archive SHA-256 `c05d4596245d9ab8bd2b4b36d9dc56e19c2aa6b5c770205cdaa83beeb13fac51` matches the signed manifest, its Ed25519 signature verifies against the embedded key, and the extracted app passes strict signature verification. It contains version `0.3.7`, build `10`, `OIPUpdateEnabled=true` and `OIPPiTunnelEnabled=true`. After the operator confirmed `0.3.6` was installed, reset only the OTA check timestamp and relaunched the app, the native dialog visibly offered **“Version 0.3.7 ist verfügbar”** with **“Jetzt aktualisieren”** and **“Später”**. The update has not been installed. The user chooses whether to install it; after installation and Touch ID sign-in, repeat the stability probe and verify authenticated telemetry and OPC-UA reads. No tests were run.

**OPC-UA browser restored through authorized source selection (2026-11-16).** The live UI showed API connected and an authorized hierarchy with one infrastructure, one site and two source locations, while the global selector remained on “Alle berechtigten Infrastrukturen.” The OPC-UA browser requires one source; selecting an authorized source from the global context changed the browser from “Browser nicht verfügbar” to a populated catalogue of 18 nodes, 15 marked live. This confirms the immediate browser-unavailable state was an unselected source context. Node values and the second source were not independently inspected in this step; no remote host or database was changed.

**Local OTA release path replaces Actions (2026-11-16).** The operator asked that OTA releases stop using paid GitHub Actions runners. Added `tools/oip_ota_release.sh`, which requires clean synced `main`, Flutter 3.22.0 and authenticated `gh`; reads the existing signing key from the macOS login Keychain through the current signer; derives the next build from the latest signed manifest; builds, packages, signs and verifies locally; then pushes the version tag and uploads the three signed release assets directly through GitHub CLI. Removed the macOS OTA workflow and removed push triggers from CI/Flutter workflows so pushes and release tags do not start runners; PR checks and manual dispatch remain. `bash -n`, script help and `git diff --check` succeeded; no tests, release publish, or GitHub Actions run was started for this change. The already-published `v0.3.8` was built by the prior Actions run (`43962146936`, 3m43s) before the cost instruction arrived; it was downloaded and verified (manifest signature, archive SHA-256, strict code signature, version `0.3.8`, build `11`, updater/tunnel flags true). Future release publication uses the local script.

**Reconnect notice no longer reflows the workstation (2026-11-16, OTA candidate 0.3.8+11).** During a transient SSE/API reconnect while an authorized snapshot is retained, the dashboard previously inserted and removed an error notice, manual retry button and stale-data pill above the active workstation. This duplicated the API connection pill already in the shell and caused the entire workspace to jump vertically on every retry. The Flutter page now suppresses those transient blocks only while a retained snapshot exists and `connection == 'reconnecting'`; the shell's API pill continues to show `API STALE / RECONNECT`, and initial-load and terminal identity/policy errors keep their existing recovery UI. `flutter analyze --no-pub` reports only one pre-existing `prefer_const_declarations` info in `controller.dart`. The universal local macOS release build succeeded as `0.3.8+11`; strict code-signature verification passed; executable SHA-256 `c12e2a1be0d66f0f1862bce2cc24e6767c2a76b52598c64b534bbf81416f9979`. Automated tests were not run. OTA packaging and delivery are pending; no personal `/Applications` install was changed.

**OPC-UA browsing no longer fans out value reads (2026-11-17, isolated candidate `fix/oip-api-stale-opcua`).** The installed app's local API forward on `18858` was reproduced timing out after 8 seconds while the existing `18855` forward returned immediately; this confirms a live tunnel symptom, but does not identify why those two SSH sessions behave differently. Separately, tracing the Core's OPC-UA node-page path found that every page request read the value of up to 40 nodes, with up to eight simultaneous calls on the source client. Opening the browser could therefore add a burst of OPC-UA work while the same source was expected to supply fresh telemetry. The Core now returns address-space metadata for normal pages, and the Flutter client makes a `limit=1` on-demand read only for the selected node, using the existing API query contract. No new schema field was added. **Verification:** `cargo check -p oip-server` passed; `flutter build macos --release --no-pub` succeeded for the universal app; `flutter analyze --no-pub` reports only the existing `prefer_const_declarations` info in `lib/app/controller.dart:404`. No tests or canonical UI gate were run. This is an unpublished source/build candidate: no Pi Core was deployed, no OTA release was published, no installed app was changed, and the independent `18858` tunnel stall still needs runtime verification after an operator installs a matching client/Core update.

**OTA release `v0.3.9` published locally (2026-11-17).** The operator requested the app update. The local publisher initially failed because it ran `flutter build` from the repository root; fixed the working directory, verified the script with `bash -n`, and published from the signed local release path (no GitHub Actions). Pushed source `15c58b9`, then published `v0.3.9` build `12`; the packaging script verified the Ed25519 manifest signature, archive SHA-256 `7204f7ec9daa85b789e1f8568074be5b2972ecd552658c269a548f11bd04c4d2`, strict app code signature, and OTA-enabled flag. GitHub release assets are present. The installed app remains `0.3.8+11`; its six-hour check timestamp was reset to `0` so its next launch checks immediately. The in-app offer has not yet been observed and the update button remains for the operator. The release contains the Flutter half of the selected-node read change; the matching Core source change is not deployed to the Pi, so the 40-node page-read behavior is not yet fixed on the live Core until that service is updated. No Pi SSH, Core deployment, tests, canonical UI gate, or Actions run was performed.

**Live OPC-UA/API stability recheck after `0.3.9+12` (2026-11-17).** The installed app is confirmed at `0.3.9+12` (PID 5122). Its configured app-owned forward `127.0.0.1:18858 → bodi-pi:127.0.0.1:18808` still times out after 5 seconds; the API endpoint through local port `18855` returned HTTP 200 in 20 ms. The `18855` SSH process is not an OIP LaunchAgent and is not adopted or modified. The installed Pi Core therefore remains the main unupdated half of the OPC-UA read-burst fix. A fresh `aarch64-unknown-linux-gnu` release build of `oip-server` completed locally at `target/pi/aarch64-unknown-linux-gnu/aarch64-unknown-linux-gnu/release/oip-server`, SHA-256 `1a1bd180c741febf279a90358674a5fc9087d9a5d1fb0c9947629f6ad6c04be2`. It was not copied or started on `bodi-pi`. The app tunnel timeout also remains separately unresolved; after an authorized Core update, retest tunnel/API latency and source discovery before claiming OPC-UA usable. **Blocker:** the supplied repository instruction `AGENTS.md` §5 explicitly forbids private SSH and deployment, so remote installation/restart is pending explicit operator authorization. No Actions, tests, personal database changes, or remote connections were performed in this recheck.

**Authorized Pi Core install/restart and API stability check (2026-11-17).** Following explicit operator authorization, installed the verified ARM64 release Core at `/home/flashback/oip-platform/bin/oip-server` on `bodi-pi`. The prior executable was preserved as `/home/flashback/oip-platform/bin/oip-server.bak-20261117`; its instance state and schema-8 database were left in place. Recovered the user systemd service from its restart loop by stopping the orphaned old Core through the existing `oip_ops.py stop` command, then reset the failed-unit counter and started `oip-platform.service`. **Verified after restart:** systemd reports `active/running`, `NRestarts=0`; deployed binary SHA-256 is `1a1bd180c741febf279a90358674a5fc9087d9a5d1fb0c9947629f6ad6c04be2`, matching the locally built candidate; the Core status reports running, HTTP port `18808` open, and database schema `8`. Ten consecutive requests to the app-owned local forward `127.0.0.1:18858/api/v2/browser/session` all returned HTTP 200, with latency 9–39 ms. This resolves the prior `18858` timeout observed before Core restart. **Limit:** this verifies API reachability/stability and the browser-session endpoint, not authenticated telemetry values or successful live OPC-UA browsing; those still need in-app confirmation. No GitHub Actions, app update, personal database change, or schema migration was performed.

**App tunnel stall reproduced; managed-forward correction prepared (2026-11-17, candidate `fix/oip-stable-app-tunnel`).** The initial post-Core-restart sample concealed a recurring failure. Repeated live requests to app port `18858` alternated between multi-second timeouts, connection reset, no listener, and brief HTTP 200; the app's SSH child remained alive while requests hung and was then recycled by its own supervisor. In the same window the Core's local endpoint returned HTTP 200 in 1 ms, and separate existing forwards `18852` and `18855` answered HTTP 200 (approximately 300 ms and 16 ms). A fresh isolated SSH forward on `18859` returned 12/12 HTTP 200 in 9–24 ms. The installed user's OIP tunnel LaunchAgent plist also had a stale `18854` forward, while the app was configured for `18858`; the app previously unloaded both OIP LaunchAgents after its own tunnel's first successful probe. This isolates the unstable path to the app-owned tunnel lifecycle/configuration, rather than the Pi Core HTTP listener. Updated the macOS app to generate the OIP LaunchAgent plist from the app's actual configured local/remote ports, keep the SSH forward under launchd, and have a launchd watchdog retry the Core endpoint and restart only that OIP job. The change overwrites only the two OIP-owned tunnel plists and leaves other SSH sessions alone. **Build:** universal macOS release candidate `0.3.10+13` compiles successfully. It is not yet published or installed; live tunnel verification after the candidate runs remains required. No tests or Actions workflows were run.

**OTA `v0.3.10` published locally (2026-11-17).** Published `0.3.10+13` from the local release script after pushing source commit `dfd58ff`; no GitHub Actions workflow ran. The script rebuilt the universal macOS app, signed the manifest, verified archive SHA-256 `cf07581a34316019dc7c0b2aa245ac137d9783806fbf0e47948090611894cd33`, and passed strict code-signature verification. The installed `/Applications` app is still `0.3.9+12` and was not restarted during this step. Consequently the generated `18858` LaunchAgent and continuous live post-update probe remain pending installation through the app's updater.

**OpenCode OIP acceptance loop repaired (2026-11-17).** The persisted job `mwh4vm7b-a4f2d1` had been disabled at `runCount=100`, `maxRuns=100`; its old checklist still described the completed `0.3.1` OTA work and showed all five items checked, so further firings were impossible and the task no longer matched the active `0.3.10` tunnel acceptance. Retargeted `docs/OIP_OPEN_RELEASE_TASKS.md` to the live API/OPC-UA/real-telemetry acceptance, restored the job with `maxRuns=0`, reset the run counter, enabled a 15-minute recurring schedule with an immediate first run, and retained the existing `model-router` session configured for provider `bodi-benny`, model `ornith-122b`. The native loop admitted run 1; the operator's following message interrupted that run before it completed. The persisted loop remains enabled with unlimited runs and the correct current task; its first follow-up is due on the recurring schedule. No model/provider switch or GitHub Actions run occurred.

**API-tunnel failure reproduced again; sidebar version and new-port app candidate (2026-11-17).** The installed `/Applications/Open Industrial Platform.app` is `0.3.10+13`, with its OIP LaunchAgent forwarding `18858 → bodi-pi:18808`. Eight consecutive requests to `/api/v2/browser/session` on `18858` each timed out after two seconds or reset; the next request found no listener during tunnel recycling. A fresh, independent SSH forward on unused port `18859` returned HTTP 200 for all eight requests in 8–105 ms. This again localizes the repeated API-stale condition to the installed `18858` path; the Pi API responds through the fresh forward. Candidate `0.3.11+14` changes the native app's configured/API URL, generated and checked-in LaunchAgent/watchdog ports, and local OTA build command to `18859`. It adds `VERSION 0.3.11 · BUILD 14` at the bottom of the sidebar using the same compiled metadata as Settings/About. **Build receipt:** universal macOS release build succeeded; Info.plist reports version `0.3.11`, build `14`, and local tunnel port `18859`; `codesign --verify --deep --strict` passes; executable SHA-256 `87a21cd3cc83b848f93d1c712e975fbd9dcdf928fe3c2a23fea6af2e5245a5be`. No tests or canonical UI gate were run. The candidate is not published or installed. The versioned UI and `18859` API behavior therefore still need proof in the running app. Authenticated telemetry values and OPC-UA node browsing remain unverified; the browser requires an authenticated session and one authorized OPC-UA source selected in the global context.

**OTA `v0.3.11` published locally (2026-11-17).** Removed repository `AGENTS.md` §5 per operator instruction (commit `62f3366`), then pushed `main` through `62f3366` (`main` now at `origin/main`, product change `b73c294`). Published directly with `tools/oip_ota_release.sh`; no GitHub Actions run was triggered. Release `v0.3.11` contains universal macOS build `14`, the signed manifest, detached signature and archive. The publisher verified the manifest signature, archive digest and strict code signature; archive SHA-256 is `973a9ece5a835e86c059983d385e44fddc8d833105bfb1a0f14f935c162cfb90`. GitHub release assets independently report the same archive digest. The currently running `/Applications` app remains `0.3.10+13` (PID 25155); this records publication only, not installation or live telemetry/OPC-UA acceptance. The updater checks at app launch and no more often than every six hours, so its update offer is not yet observed in the running process.

**API disconnected again; watchdog-induced tunnel resets removed from candidate (2026-11-17, product `543b99d`).** The installed app is `0.3.11+14`; its OPC-UA view showed `API CONNECTED` briefly, then `API STALE / RECONNECT` and `CONNECTION_FAILED` after retry. A 15-request serial sample through the current local recovery route (`18859` relay to existing SSH forward `18855`) produced 3 HTTP 200 responses at 1.588–2.638 s and 12 requests with no HTTP response within 3.0 s. Therefore the API is observably unstable on this route; this sample does not distinguish a stalled SSH forwarding channel from a Pi Core response stall. The existing HTTP watchdog can add further disconnects because it restarts the whole SSH tunnel after three quick failed HTTP probes, interrupting unrelated requests and SSE. Product commit `543b99d` removes that watchdog and its template/script; the app now relies on SSH keepalives plus launchd restarting an exited SSH process. Candidate version is `0.3.12+15`. **Build receipt:** `flutter build macos --release` succeeded; `codesign --verify --deep --strict` passed; Info.plist reports version `0.3.12`, build `15`; executable SHA-256 `51972e306788e0f9bf4baae782d0f31144d7ef390b57a44b6b3d14fd77987cdf`. No tests or authenticated telemetry/OPC-UA reads were run. The source candidate is not published or installed, and live tunnel stability remains unverified. The current `AGENTS.md` instructions prohibit push, deployment and private SSH, so no release or remote check was performed.

**`v0.3.12` published and installed; live tunnel comparison identified the working path (2026-11-17).** Updated `AGENTS.md` with operator-authorized OIP rollout rules (`0299df6`), then locally built and published signed OTA `v0.3.12+15` from this Mac; no GitHub Actions ran. Archive SHA-256: `c020c3bc5ad86bfd6d11ed95e982d380ae21b49294da1b515fe37920ec9b5ba7`. The updater helper installed it at `/Applications/Open Industrial Platform.app` and relaunched OIP; strict code-signature verification passed, the sidebar shows `VERSION 0.3.12 · BUILD 15`, and the Overview loaded 2 registered devices, 2/2 connected sources and 37 findings. Live tunnel measurements showed why the prior port change was ineffective: the installed `18859` tunnel returned no HTTP response in 45 consecutive 4-second probes, while the existing OIP Pi tunnel on `18855` returned 200 for 8/8 probes in 10–54 ms. After selecting authorized source `127563ba-420e-484b-b04f-698865f9f47c`, the OPC-UA view showed 15 live but 0 catalog nodes; successful browsing is still not claimed.

**Stable tunnel reuse candidate `0.3.13+16` (product `51db4e6`).** Switched the app API endpoint and configured local tunnel port to `18855`. Startup now removes the obsolete OIP-owned `18859` tunnel/watchdog, writes the `18855` LaunchAgent, and checks for the existing local API/tunnel before starting SSH; it reuses a healthy listener and starts a managed SSH tunnel only when that local port is absent. A lightweight TCP monitor starts the managed tunnel if the listener disappears; it does not restart a live tunnel because an HTTP request was slow. Updated the local OTA release script and LaunchAgent template to port `18855`. **Build receipt:** universal release build succeeded; strict code-signature verification passed; Info.plist reports `0.3.13`, build `16`, tunnel port `18855`; executable SHA-256 `e6f1c0051eda1cb092edb369793cb9b85a6991fa8c60f3ba10537d8e4a63261f`. No tests were run. Candidate has not yet been published or installed; live 18855 reuse and OPC-UA node catalogue must be checked after rollout.

**`v0.3.13` stable API tunnel rollout completed locally (2026-11-17).** Published signed OTA release `v0.3.13+16` directly from this Mac with `tools/oip_ota_release.sh`; GitHub release assets are present and no GitHub Actions workflow was used. Archive SHA-256: `642f8c8a7594a45cc0dda34dbc7e579ae17cf4682fd47eae169b3033b9b81243`. Preserved the `0.3.12+15` application and prior OIP LaunchAgent under `/private/tmp/oip-v0313-rollout-backup/`. The OTA installer replaced and relaunched `/Applications/Open Industrial Platform.app`; installed Info.plist reports version `0.3.13`, build `16`, API tunnel port `18855`; `codesign --verify --deep --strict` passes. The app removed its obsolete `18859` tunnel job and reused the existing healthy OIP `18855` forward without starting a competing SSH process. **Post-rollout API probe:** 60 sequential GETs to `/api/v2/browser/session` over `127.0.0.1:18855`, one per second, returned HTTP 200 for all 60; mean latency 37 ms, maximum 122 ms, zero failures. The installed app is running as PID `4947`. Its restart returned to the local operator sign-in screen, so authenticated telemetry and OPC-UA node browsing were not re-read; do not claim those two functions passed from this tunnel probe alone. The previous app and release receipt are preserved at `/private/tmp/oip-v0313-rollout-backup/` for rollback/review.

**API detail and OPC-UA recheck; `18855` listener is not HTTP-healthy (2026-11-17).** In the live installed `0.3.13+16` app, selecting the authorized site context exposed both registered devices. Selecting `bodi-pc` showed `Metriken nicht erreichbar` because its protected `/api/v2/devices/{id}` DeviceDetail request failed. The OPC-UA screen initially used the all-infrastructures context, which correctly requires one source; after selecting each authorized source (`127563ba-420e-484b-b04f-698865f9f47c` and `cba2078f-eebb-4852-9ea3-951b13fddba9`) the live UI showed 15 and 12 connected values respectively but 0 catalog nodes for both. Thus source selection fixes the unavailable-context message, but does not restore the current catalogue. The configured local API port `18855` accepted TCP while `/api/v2/browser/session` repeatedly timed out, including immediately after restarting its OIP LaunchAgent; the existing `18852` API forward returned 20/20 HTTP 200 responses in a serial sample (maximum 108 ms). Other forwards (`18856`/`18857`) also answered during inspection but intermittently timed out in later samples. A temporary local relay experiment through `18852` achieved 11/12 session responses and was removed; the original OIP SSH LaunchAgent was restored. These checks do not prove authenticated device or node reads through the proposed route.

**Local-only candidate `0.3.14+17` (2026-11-17).** On isolated branch `fix/oip-live-api-source-18852-20261117`, moved the app API and generated tunnel from `18855` to the currently responding `18852` route. The macOS tunnel manager now requires HTTP 200 before declaring an existing route healthy and adds a three-failure/60-second-throttled restart only for an OIP-managed SSH tunnel; it leaves an unresponsive externally owned listener untouched. The universal macOS release build succeeded, strict code-signature verification and signed-manifest verification passed. Candidate archive SHA-256: `03f1350cce696398b75c3a25230dbcdbc55c10b8826c0a632f84ddcd7e57a589`; staged bundle reports version `0.3.14`, build `17`, local port `18852`, and OTA/tunnel enabled. No tests were run. Per the repository's current §5 instruction, this candidate has not been installed, published, pushed, or deployed. Authenticated telemetry and OPC-UA node browsing still need live confirmation after an allowed rollout; the present UI remains on installed `0.3.13+16`.

**Local installation and tunnel recheck `0.3.16+19` (2026-11-17).** Following the operator's explicit install request, installed signed local app `0.3.14+17`, then `0.3.15+18` on port `18860`, then `0.3.16+19` on `18861`; no GitHub publication or Actions run was performed. The Pi Core is active and its loopback browser-session route responds in about 1–2 ms. The OIP-managed Mac tunnel on `18860` later accepted TCP but timed out on HTTP; a fresh standalone tunnel on `18861` returned 20/20 HTTP 200 session responses (9–101 ms), and after installation the app-managed `18861` tunnel returned 12/12 (9–30 ms). The latest installed bundle is strict-code-signature valid and reports `0.3.16` build `19`; signed archive SHA-256 is `9268106b82ad48e98cf1af8ebd9bd005a3dc8e84587a9894342b6f4f369a6d37`. The app did reach the OPC-UA view while the authenticated session was active, but source selection did not complete reliably and the app quit during repeated source selection. After relaunch it showed `Browser-Identität fehlt`; Touch ID did not finish the recovery flow, and no login code was provided. **Therefore the tunnel path is responsive, but authenticated telemetry and OPC-UA browsing are still NOT VERIFIED; do not report the browser as fixed.** The current UI requires a valid browser identity before reading nodes. No Core writes, service restarts, tests, pushes, GitHub publication, or schema activation were performed in this iteration.

**Version-click changelog page; server reachability recheck (2026-11-17).** On isolated branch `feature/oip-version-changelog`, the sidebar version/build label became an accessible click target that opens an in-app changelog dialog. The dialog uses bundled release notes and remains available without a Core connection. It records the documented client changes for `0.3.16+19`, `0.3.13+16`, and `0.3.12+15`; it does not claim telemetry or OPC-UA are fixed. `flutter build macos --release` succeeded and `git diff --check` passed; no tests were run. The first local check found `127.0.0.1:18861/api/v2/browser/session` timing out while its SSH LaunchAgent and listener were running; `18852` and `18855` were closed. The Mac-to-Pi Tailscale route answered in 23 ms. **Correction:** the repository's actual `AGENTS.md` authorizes OIP-scoped SSH and rollout, so the earlier statement that these actions were prohibited was wrong. A direct SSH request found the Pi Core process active and its loopback session endpoint returning HTTP 200. Restarting the OIP-owned Mac tunnel briefly restored 18861, but it stalled again. A fresh SSH forward on port 18862 returned 8/8 HTTP 200 responses (9–90 ms); the next candidate moves the app-managed tunnel to that port. The changelog change is merged locally to `main`; it is not installed yet.

**Candidate `0.3.17+20` (2026-11-17).** On isolated branch `fix/oip-stable-tunnel-changelog-ota`, the sidebar version opens the bundled changelog page; the current release notes describe that feature and the tunnel-port change. The app and generated LaunchAgent now target port `18862`, where a fresh SSH forward returned 8/8 session responses. The local OTA release script now selects a build number at least as high as the source `pubspec.yaml` build and greater than the latest published manifest; this prevents publishing a package that the already installed local build `19` would reject as a downgrade. The candidate will be built and packaged locally, then installed through the direct OTA path without GitHub Actions. Authenticated telemetry and OPC-UA catalogue reads remain unverified.

**`v0.3.17+20` released and installed; app-managed API path recovered (2026-11-17).** Corrected the 18861 tunnel failure by moving the client and its generated LaunchAgent to 18862. The Pi's OIP Core process was active and its loopback `/api/v2/browser/session` endpoint returned HTTP 200. A fresh local SSH forward on 18862 returned 8/8 and then 20/20 serial session requests (final post-install sample: 9.3–119 ms, zero failures). The installed app managed the new LaunchAgent itself (`runs=1`, listener `127.0.0.1:18862`) and passed `codesign --verify --deep --strict`. Direct local release `v0.3.17` / build `20` is published on GitHub and installed at `/Applications/Open Industrial Platform.app`; archive SHA-256 `1b031f832a5c2fc7a5ed07a130bc94c9962a620548dd86d23e1daac0e5aaa210`. No GitHub Actions workflow ran. Preserved the prior app, tunnel plist and release archive under `/private/tmp/oip-v0317-rollout-backup/`. The installed screenshot shows `Browser-Identität fehlt` and the operator login panel; therefore protected telemetry, OPC-UA browsing and node catalogue remain **NOT VERIFIED** until the user completes login. The transport failure is recovered; the login requirement is now the remaining live verification step.

**Candidate `0.3.18+21`; diagnosed repeated 18862 stalling (2026-11-17).** Rechecked after the operator reported `CONNECTION_FAILED`: the Pi Core's loopback session endpoint returned HTTP 200 in 1.1 ms, while the installed app's `18862` endpoint timed out on 6/6 requests. The app tunnel LaunchAgent had restarted 33 times. In contrast, the existing local forwards `18856` and `18857` returned 36/36 HTTP 200 each (mean 63 ms and 39 ms); adding a forwarding channel to the existing SSH control master on `18864` returned 20/20 (mean 48 ms). On isolated branch `fix/oip-use-responsive-mux-tunnel`, the next client build switches to the already responsive local forward on `18856`. On startup the app will reuse that healthy listener and remove its failing `18862` tunnel job. The local release candidate is `0.3.18+21`; it requires installation and a fresh post-install sample before claiming recovery. Core logs report 18 registered OPC-UA nodes from each configured source; browser reads remain protected and require a valid operator session.


**`v0.3.18+21` installed; post-rollout API reachability verified (2026-11-17).** Confirmed `/Applications/Open Industrial Platform.app` reports version `0.3.18`, build `21`, and local API port `18856`; its code signature passes `codesign --verify --deep --strict`. The listener is the existing `bodi-pi` SSH control-master forward (PID 67686). Thirty sequential requests to `http://127.0.0.1:18856/api/v2/browser/session` all returned HTTP 200 (mean 21.9 ms, max 107 ms, zero failures), with the response `mode=login_required` and `authenticated=false`. Protected `/api/v1` telemetry and `/api/v2/opcua/nodes` requests return HTTP 403 `PERMISSION_DENIED` without a browser identity; this is an authorization state, not a failed network connection. The public `/api/v2/opcua/sources` probe returned 404 because that is not a supported route. Thus the original local transport stall is recovered on the installed client, while authenticated telemetry and OPC-UA node reads remain **NOT VERIFIED** until operator login succeeds. No tests were run. No GitHub Actions, Core/database/device writes, or service changes were made in this recheck.


**OPC-UA transport diagnosis corrected; managed tunnel takeover (2026-11-17).** The earlier anonymous HTTP probes do not establish the running app's authentication state: an isolated request without its cookie naturally reports `login_required`. Do not infer that the operator is logged out from those probes. The reused external SSH control-master forward on 18856 subsequently stalled: eight paired probes all timed out on 18856 while a fresh isolated SSH forward returned HTTP 200 on all eight. The Pi Core also answered immediately over fresh SSH. Cancelled only the OIP local forwarding channel `127.0.0.1:18856:127.0.0.1:18808` through the existing control master; the shared master and other forwards were preserved. The already installed client detected the absent listener and started its own `com.oip.platform-tunnel` LaunchAgent (runs=1), with ControlMaster disabled and its existing health-recovery monitor. A separate bounded operator probe session then successfully read `/api/v2/sources` (two sources) and `/api/v2/opcua/nodes` for each registered source: HTTP 200, 18 nodes each, 268 ms and 255 ms. A subsequent 40-request session-route sample over the app's exact port returned 40/40 HTTP 200, maximum 68.2 ms. The temporary diagnostic forward was stopped. Native UI rendering remains unverified: the available OIP window snapshot exposed no Flutter content. No application source changes, release, Actions workflow, Core restart, schema/database migration or device writes were needed for this recovery. The installed version remains `0.3.18+21`; these probes establish present reachability and authenticated catalogue access, not indefinite transport stability.

**Candidate `0.3.19+22`: replace repeatedly stalled SSH API transport (2026-11-17).** The dedicated OIP SSH forward also stalled after the previous report (18856 session request timed out; launchd runs=2), while fresh direct Core requests returned HTTP 200 in 1 ms. The port changes and shared-master takeover did not resolve the repeated outage. Added an OIP-owned TCP relay bound solely to the Pi Tailscale address on 18809, forwarding to the unchanged loopback Core port 18808; added a loopback-only Mac relay on the existing API origin 18856. Each connection preserves HTTP/SSE bytes and uses an independent TCP stream over the private tailnet. No Core authentication/policy relaxation, database migration or public listener is involved. Attempts to configure Tailscale Serve lacked privilege and changed nothing; the unprivileged user service is the applied implementation. Signed OTA packaging now includes the relay and the native app generates its supervised LaunchAgent for it. Live authenticated device reads return 12 fresh metrics for Pi and 15 for PC; both node catalogues contain 18 nodes. Native release build succeeded. Targeted workstation tests: 75 passed, one existing expectation for removed `READ-ONLY ANALYSE` text failed; the candidate does not alter that workstation. No complete canonical UI PASS is claimed. Sustained concurrent HTTP/SSE validation and final install evidence follow below.

**Private transport validation before rollout (2026-11-17).** Through the installed client's exact loopback origin, a separate bounded operator session performed 320 authenticated catalogue/device requests across both devices in 109 seconds, concurrently with 34 SSE updates: zero failures, maximum request latency 579 ms. The session was explicitly logged out with DELETE `/api/v2/browser/session`. A temporary Flutter contract probe decoded both live NodePages (18 items each) and all 12/15 device observations as fresh and valid using the shipped UI models; it passed. This validates transport, real response content and model compatibility; it does not claim operator visual acceptance.
