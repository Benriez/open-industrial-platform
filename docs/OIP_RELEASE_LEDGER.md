# OIP release acceptance ledger (N12 offline inventory)

Inventory taken on `main` and **kept current in every iteration**: the revision, the tree and the
measured evidence are named below, and every receipt under `docs/evidence/` names the revision it
was measured on; the receipts of the current iteration name the tree and the state of the working tree
as well. Statuses: DONE, READY, BLOCKED_OPERATOR, BLOCKED_DEPENDENCY, FAILED.
Overall verdict: **OIP_PRODUCTION_NOT_READY**. No gate below is accepted for production.

`AGENTS.md` now exists in this repository and binds every session that changes the Flutter
application. The binding rules come from `AGENTS.md`,
`docs/design/OIP_CANONICAL_UI_BASELINE.md` (the binding canonical UI contract),
`docs/OIP_RELEASE_PROGRESS.md`, `docs/decisions/*` and `docs/architecture/*`.

**GitHub OTA client updater fix (2026-11-15).** The silent offer failure of the installed
`0.3.0+3` app against the signed `v0.3.1+4` release is diagnosed and fixed on the isolated branch
`fix/oip-github-ota-asset-name` (product `1143e4c`): the client looked for the never-published
asset `oip-macos-manifest.sig` instead of the published `oip-macos-manifest.json.sig`. The decision
logic is now the shared, unit-tested `OIPGitHubOTA` module, the live updater uses its types and
logs every reject reason, and the installer helper's replace/verify/rollback/relaunch path is
reviewed and regression-tested. Verified: `flutter build macos --release` compiles with 251
`OIPGitHubOTA` symbols in the universal binary, and `tests/oip_ota_logic.py` (2),
`tests/oip_ota_install_helper.py` (4) and `tests/oip_github_ota_package.py` (1) pass. This is a
software-ready fix; the **live** end-to-end OTA install against the running `0.3.0+3` app (pid 33826)
stays **BLOCKED_OPERATOR** — an operator must install the fixed build and trigger the offer
(`docs/evidence/oip-github-ota/ota-receipt.json`). **Staged candidate (loop `9751d2a`, 2026-11-15):**
the canonical worktree's on-disk `.app` is a stale pre-fix build, so the verified fixed build
(`fix/oip-github-ota-asset-name` HEAD `c3e5d91`; 251 `OIPGitHubOTA` symbols; binary sha256
`2cf06734d07157cfb76dba4b7e82b4019324539dffc9f18843399d3d0184c2f5`, ad-hoc, version `0.3.0` build `3`
with the fixed updater) was copied byte-identically to `/private/tmp/oip-ota-candidate/oip_dashboard.app`
for the operator; `/Applications` and pid 33826 untouched. The receipt records the path and the
operator install steps; gate G9 (macOS build / local operations) is the gate this closes once the
operator runs the live install. **OTA archive-digest rejection unit-tested (loop `2665891`,
2026-11-15):** the digest check that acceptance requires was inline in the live downloader with a
dead `archiveDigestMismatch` enum case, so no test covered it. It is now the pure `OIPGitHubOTA`
helpers `sha256Hex(of:)` / `verifyArchiveDigest(sha256Hex:manifest:)`, called by the live downloader
and by `tests/oip_ota_logic.py` (matching digest accepted, tampered digest returns
`.archiveDigestMismatch(got, expected)`). Native release build compiles with 254 `OIPGitHubOTA`
symbols (fresh binary sha256 `f84b61f009a324bd3275a0d73352c12a15773229ca71b4392d1ed111ba853760);
all 7 OTA tests pass; the operator candidate was re-staged from this build. **Process-state note
(loop `2665891`):** the recorded installed-app pid 33826 is no longer running (the operator quit it);
the installed app is still `0.3.0+3` at `/Applications`. Task 4 (G12) stays `BLOCKED_OPERATOR`
regardless — the loop must not trigger a live self-install from a build; the install and the offer
observation remain the operator's acceptance action.

**Published `v0.3.1` ships the pre-fix updater — new operator/external blocker (loop `e0300c8`,
2026-11-15).** Re-verifying the live OTA target, the shipped `v0.3.1+4` bundle was found to contain the
**pre-fix** updater, not the fixed `OIPGitHubOTA` client. Tag `v0.3.1` → `45e09015` and CI record
`6a77133` both predate the fix `1143e4c` by ~3h; neither release tree contains
`apps/flutter/macos/Runner/OIPGitHubOTA.swift`, their `MainFlutterWindow.swift` still searches the
never-published `oip-macos-manifest.sig`, and the freshly downloaded shipped binary (`0.3.1+4`) has
**0 `OIPGitHubOTA` symbols** (sha256 `d341348c…0502` vs the fixed candidate `f84b61f…853760`, 254
symbols). The operator's G12 offer check still succeeds (the fixed candidate offers `v0.3.1+4`), but
completing that update installs a bundle whose own updater is still broken, and a public download of
`v0.3.1` carries the same latent bug forward. **New required operator action (BLOCKED_OPERATOR /
external):** re-publish the fixed client as a signed GitHub release (`v0.3.2`, or re-tag `v0.3.1` from a
post-fix commit such as `e0300c8`) so the shipped artifact contains `OIPGitHubOTA.swift`; the loop
cannot push or publish. Evidence: `docs/evidence/oip-github-ota/ota-receipt.json`
(`github_delivery.published_release_updater_state`).

| Gate | Status | Basis and gap |
|---|---|---|
| G1 integrated Core + six workstations | DONE | The Spectrum-2027 Engineering Workstations are the canonical application of `main` since `ddb446e` (contract `docs/design/OIP_CANONICAL_UI_BASELINE.md`). The managed diagnostics capability of `feature/oip-managed-diagnostics` (`55d4f50`) is reconciled into the approved workspace: the capability was carried over, the opaque continuation and the limits of the answer were restored in `7fc612e`. All six workstations render against the real authorized backend; the browser gate proves 189 findings with zero failures over them (`docs/evidence/oip-canonical-acceptance/browser-gate.json`, counted by `docs/evidence/oip-canonical-acceptance/acceptance.json`). |
| G2 auth, sessions, REST/SSE/MCP parity, org isolation | READY (the software part) | Browser session contract and parity gate recorded as passing. The **lifetimes** that the operator login promises are measured against the real Core with the real lifetimes (`tests/oip_session_lifetime.py`, `docs/evidence/oip-session-lifetime/session-lifetime.json`): a one-time code that is older than 120 s is refused with 403, and a session that is older than 30 minutes reports itself as not authenticated and its management reads are refused with 403 `PERMISSION_DENIED`. The **parity of the three transports** of the current release is re-inventoried against the **Core binary whose digest the receipt of that measurement names** with the collectors of the simulated endpoints (`tests/oip_transport_parity.py`, `docs/evidence/oip-transport-parity/transport-parity.json`): the REST route `/api/v2/snapshot`, the SSE stream `/api/v2/stream` and the MCP resource `oip://v2/snapshot/current` — the three identifiers are named by the receipt that drove them — deliver the **same** authorized projection for the same principal (the three sources and the three devices of the organization), the projection carries nothing of the other organization, and both HTTP transports refuse an unauthorized session with 403. The same-UID boundary and the productive remote identity are measured in the security review (G10): the Core binds to the loopback only and the local IPC does not isolate hostile processes of the same user — both **mitigated** and **not claimed**. Missing: the acceptance of the production-security scope by the operator (G10). |
| G3 global infrastructure context | DONE | The dependency of N3 is resolved: the UI workstreams are reconciled, the selector offers the unified view and every organization, infrastructure, site and source of the authorized hierarchy, and the scope of the operator **follows the session across the six workstations** — while a **new session starts in the unified view again**: the scope is the choice of the session and not a persisted state, and the browser receipt measures exactly that (the Core has no whoami route, so the identity of the authorized session is the missing evidence, `8b06720`). The scope **survives a refresh of the authorized projection**, and this is proven against the **real Core** (`tests/oip_scope_persistence.py`, `apps/flutter/test/browser_scope_persistence.mjs`, `docs/evidence/oip-scope-persistence/scope-persistence.json`): the operator selects the scope of a site, the administration of a device changes the Core (the revision of the device advances), the surface reads the authorized projection again and shows the new state — and the scope of the operator is the scope of the operator still (`site-a1` before and after), while the new session of the page starts in the unified view again. The evidence of the identity of the session is what keeps the scope: the Core has no whoami route, and the session of the browser carries the principal. The browser receipt `apps/flutter/test/browser_global_context.mjs` proves it against the real Core: the global selection offers the individual infrastructures, the selection scopes the projection, **the shared scope follows the operator across all six workstations** and the unified view returns every authorized infrastructure. The receipt runs inside the canonical acceptance; the measured evidence is `docs/evidence/oip-global-context/global-context.json`. |
| G4 device management in Flutter | READY (the software part) | The Core owns the inventory and supports the register, the update and the archive. The client could not write the update at all: the Flutter API knew the register only and the approved device workspace had no administration. That gap is closed (`8b06720`): the administration surface of the device names the revision it works on, sends the full replacement the Core requires and shows the refusal of the Core verbatim. The **identity** of a device is named where the operator looks at it: the Devices workspace asks the inventory of the Core for the record of the selected device and shows the facts the Core holds (manufacturer and model, firmware and OS, serial or bridge id, MAC and address); a fact that the Core does not hold is named as unavailable and **never invented** (`7ce11fd`, `apps/flutter/test/device_identity_test.dart`). Proven by the widget test and by the real-device journey
(`docs/evidence/oip-device-administration/device-administration.json`): the update of a device
through the surface with the revision advancing from 1 to 2, the **note of the device written
through the surface and kept by the Core** with the revision advancing from 2 to 3 (a write whose
metadata does not carry the note drops it — the contract of the Core, measured), and the refusal
of the archive of an online device with `OFFLINE_ARCHIVE_REQUIRED`. The **keys of the page belong
to the field that is edited**: the shortcuts of a workstation (the pin `p`, the comparison `c`, the
search `/`) are the keys of the page, but the handler of the page swallowed them while a field of
the inspector was edited — the operator lost every `c` of the note and every `c` toggled the
comparison instead. The four workstations ask now whether a text field owns the keyboard
(`apps/flutter/lib/core/keyboard.dart`); the keys that were usable before stay usable (the escape
of the devices workstation still closes the details), and the regression test of the guard is
meaningful: without the guard it fails, and it carries a positive control
(`apps/flutter/test/devices_workstation_test.dart`). The **archive is an offline operation of the Core** — the managed session refuses it with `OFFLINE_ARCHIVE_REQUIRED` — so the surface names the offline procedure instead of offering a refused write, and the supported path is rehearsed (`tests/oip_offline_archive.py`, `docs/evidence/oip-offline-archive/offline-archive.json`): the offline plan is applied with the Core stopped, the archived device keeps its record, its identity and its metadata, it advances its revision and it disappears from the active inventory. The **association of a device with a verified connection** through the surface is proven against the real Core and an owned loopback SSH fixture with a real host key (`tests/oip_device_connection.py`, `apps/flutter/test/browser_device_connection.mjs`, `docs/evidence/oip-device-connection/device-connection.json`): the device is registered through the authorized session, the connection is started, the host key of the fixture is presented and confirmed, the identity of the host is verified and the identity confirmation enables the read-only monitoring — and the surface then shows the device with that connection: the state (`Collecting`), the **confirmed host key** (the surface shows exactly the fingerprint that the host really presents — the fixture generates a fresh key for every run, so the receipt of the run names it, `docs/evidence/oip-device-connection/device-connection.json`), the endpoint, the really verified identity behind the expansion (hostname, `Darwin`, 17 179 869 184 bytes) and the read-only monitoring with its polling and its revision (9 checks, and the journey reports no JavaScript error — the receipt carries the empty error list of the journey). Remaining: the same association on physical hardware (G5). |
| G5 real device connections | BLOCKED_OPERATOR | Fixture only. No physical device contacted; needs operator-approved target. F5 permission rule (N1b) is also BLOCKED_OPERATOR. The **honest connection states** of the surface are proven against the **real Core** and an owned loopback SSH fixture (`tests/oip_connection_states.py`, `apps/flutter/test/browser_connection_states.mjs`, `docs/evidence/oip-connection-states/connection-states.json`): the Core and the surface are read in the same moment in the states the Core really produces — verified without the monitoring (`SSH Verified · Monitoring deaktiviert`), collecting (`Collecting · aktuelle Messwerte empfangen`), an unreachable host (`Unreachable · tatsächlicher Verbindungsversuch fehlgeschlagen`), the **recovery** when the host comes back (`Collecting` again) and a changed host key (`Host-Key geändert · Verbindung blockiert`, with the reason `HOST_KEY_CHANGED` named). The operator enables the monitoring through the switch of the surface, and the host of the rehearsal disappears, comes back and comes back with another key — the Core is never touched. The Core derives **eight** states (`crates/oip-server/src/connection_service.rs`): the four that the receipt proves against the real Core (`ssh_verified`, `collecting`, `unreachable`, `host_key_changed`) and the four others (`host_key_unknown`, `stale`, `collector_configured`, `verification_failed`). The widget test (`apps/flutter/test/device_connection_states_test.dart`) asserts **all eight** of them, and a state that the client does not know is named on the surface and never shown as the wire name of the Core. The Core derives the cadence of a source from its polling — twice the interval plus fifteen seconds — so a collected device reaches `unreachable` before it reaches `stale`, which needs samples that stop without a failed attempt. A blocked connection cannot be shown as connected without a failing test. |
| G6 monitoring | READY (the software part) | Measurements and history proven against the fixture; the **coverage of the kinds** and the **history of the measurements of the owned loopback SSH fixture** (a real SSH server with a real host key on the loopback of the machine — the local host, not a physical device) are measured as well. The **long-run stability and the reconnect** are now measured against the **Core binary whose digest the receipt of that measurement names** under the load of the collectors of the simulated endpoints (`tests/oip_stability.py`, `docs/evidence/oip-stability/stability.json`): over a sustained run under the load of the collectors the Core answered **every** probe, the resident memory **did not grow** over the run, the CPU rested at a low average, the observations were persisted at a steady rate, the log grew slowly, and the death of a collector was noticed and recorded as a documented gap while the collection resumed. The receipt of the run names the minutes, the samples and every measured value; the property is the one that matters: **the working set of the Core does not grow over the run**. The **coverage of the kinds of the measurement** is measured against the real Core and an owned loopback SSH fixture (`tests/oip_measurement_coverage.py`, `docs/evidence/oip-measurement-coverage/measurement-coverage.json`): every supported kind is delivered as an observation of the authorized source — CPU (`host.cpu_info`, `host.model`), RAM (`host.memory_total_bytes`, `host.memory_used_bytes`), storage (`host.disks`), network (`host.interfaces`) and uptime (`host.uptime_seconds`) — while the three kinds that the contract of the real device names as unavailable (GPU, temperature, CPU utilisation) are **named** in the connection record and are **never** delivered as a number, the report carries its provenance, and the painted surface **names** the kinds that are not available (`Nicht verfügbar: gpu, temperature, cpu_utilization`), so a measurement that is missing never looks like a measurement of zero. The browser journey proves the surface against the real Core (9 checks, no JavaScript error) and the tile of the verified identity stays open over the refresh of the panel. The **recovery of the collection** is proven in the surface against the real Core: the host of the rehearsal disappears, the Core answers `unreachable` and the surface says so, the host comes back and the Core collects again — the surface shows `Collecting` (`docs/evidence/oip-connection-states/connection-states.json`). The **history of the measurements of the owned loopback SSH fixture** is measured against the real Core (`tests/oip_observation_history.py`, `docs/evidence/oip-observation-history/observation-history.json`): the history **grows** with the polling — the samples are persisted, not computed for the request — every stored sample is reported as **stale** while the current route of the same metric reports the live one (`fresh`), the order is ascending by the receive time and the receive time is present, the cursor walks the history forward with **disjoint and complete** pages, the stable id deduplicates the samples, a device of another organization and a device that does not exist are refused **identically** (`404 RESOURCE_NOT_ACCESSIBLE` — the answer does not disclose whether the target exists), and the history **survives the restart** of the instance while the collection resumes. Missing: the measurements on real physical hardware. |
| G7 Spectrum-2027 UX preserved | DONE | Integrated into canonical `main` with a real `git merge --ff-only` after the two parallel executions were reconciled into one candidate. The binding contract is `docs/design/OIP_CANONICAL_UI_BASELINE.md` with the prohibited regressions R1-R10; the permanent gate is `tests/canonical_ui_gate.py` (build provenance, widget gate, browser gate, stable-shell visual comparison with negative controls) and runs inside the canonical acceptance workflow. The OIP/005 dashboard, the gradient KPI cards, the `M-01` defaults, the "Normalbetrieb" context and the AGENT-FIRST sidebar footer are prohibited regressions and are proven absent. The rule of the **automatic legacy fallback** is a property of the **product** now, and not of a fixture: the client accepts the legacy demo only when the Core states its demo mode with the scenario controls it offers — a Core with simulated data and no demo mode never shows the demo dashboard, and the widget gate proves exactly that with the default fixture (`apps/flutter/lib/app/controller.dart`, `apps/flutter/test/canonical_ui_gate_test.dart`). Operator visual acceptance stays `VISUAL_PENDING_OPERATOR_ACCEPTANCE`. |
| G8 six functional views | READY (the software part) | Overview, Devices & Services, Network & VPN, Diagnostics & Events, Settings and the OPC-UA Browser all render in the browser gate at 1440 px and 1920 px against the authorized backend, and the diagnostics view now shows the persisted evidence of the Core (documented gaps, health transitions, the named diagnosis-history state). The **continuation of a truncated page** is proven in the browser against a real Core whose page really is truncated (`tests/oip_diagnostic_continuation.py`, `apps/flutter/test/browser_diagnostic_continuation.mjs`, `docs/evidence/oip-diagnostic-continuation/diagnostic-continuation.json`): the Core cuts the page at 50 entries and hands an opaque cursor, the surface offers the continuation, the continuation asks the same authorized route with that cursor, the pages are disjoint — no row is repeated and no row is lost (the receipt of the run names the rows), the offer disappears when the last page is reached, and the evidence and its disclosed limits stay visible. The **functional depth** of the six workstations is proven in the browser against the real Core (`tests/oip_workstation_data.py`, `apps/flutter/test/browser_workstation_data.mjs`, `docs/evidence/oip-workstation-data/workstation-data.json`): the operator selects a source in the global Infrastructure Context and every workstation then shows real data of the authorized Core — the hierarchy and its counts, the device of the source, the authorized placement, the nodes of the source, the events of the scope and the settings of the instance — while **no identifier of the other organization** appears in any of the six (17 checks, no JavaScript error). The **settings navigation names the status of the Core** for every category: the Core states whether a category is administered offline or only read, and the navigation shows that answer instead of a guess of the client (the wire names of the Core are snake_case, the mapping is explicit). This is proven against the **real Core** (`tests/oip_settings_status.py`, `apps/flutter/test/browser_settings_status.mjs`, `docs/evidence/oip-settings-status/settings-status.json`, `docs/evidence/oip-settings-status/settings-status-rehearsal.json`): the Core answers a **typed** state for each of its **seven** categories (the type is `SettingsCategoryStatus` of `crates/oip-core/src/settings.rs`), every category is selected in the navigation, and the word of the surface is **determined by the answer** — two categories that the Core answers alike show the same word, two that it answers differently show different words (85 checks). The dependence is proved by a **negative control** (`apps/flutter/test/settings_workstation_test.dart`): the Core answers that the General category is only read — the opposite of the usual answer — and the navigation shows that answer, so a navigation with a table of its own would fail. A state that the client does not know is **named** on the surface and never shown as the wire name of the Core — this clause is pinned by the widget test (`apps/flutter/test/settings_workstation_test.dart`), the journey against the real Core never meets an unknown state — and the answer of the Core is the same in the scope of the platform and in the scope of an organization. The **OPC-UA workstation** binds its live values, its session history and its alarm to the entity that the **Core** names for the selected source — the id of the device for a real source, the identifier of the simulation for a simulated one — and never assumes the identity of the demo (`apps/flutter/lib/features/opcua.dart`, `apps/flutter/test/opcua_workstation_test.dart`). The **diagnostics inspector** shows the reason of a data gap that the Core delivered instead of claiming that the reason is not projected (`apps/flutter/lib/features/diagnostics/evidence_inspector.dart`). Unsupported protocols stay labelled. The **services** are **delivered** now: the Core owns the authorized service registry that the operator declared in the plan (`service_registry_read`, `GET /api/v2/services`, `oip_services_read`), the Devices workspace shows the services of the scope with their provenance `declared`, and an empty registry is the statement of the operator while a Core that does not deliver the registry is named as the absence (`docs/evidence/oip-service-registry/service-registry.json`). The **VPN** is still named by the surface as not delivered: the Core owns no VPN read route and measures no tunnel, and the Network workspace says `NICHT GELIEFERT` instead of showing a placeholder as a working feature — the record claims no administration capability for it. The **Settings** workstation *reads* the settings of the Core: the Core has no HTTP or MCP write path, the surface names that (`Kein Browser-Save`), and the offline change with its refusal of a conflicting revision is proven by the offline rehearsal (`docs/evidence/oip-settings-offline/settings-offline.json`). The **honest states of the surface** are proven by the design regression gate after a systematic sweep: the footer names that the security blocker of the platform is not delivered to a tenant session instead of showing a placeholder as an open blocker, the OPC-UA browser names that the scenario of the demo is not delivered instead of showing the internal wire value `authorized_context`, and the operator login names the restart of the instance as the third cause of the end of a session — the browser session lives in the memory of the Core (387 of 387 Flutter tests, 189 browser findings with zero failures, the visual comparison PASS, 8 of 8 phases — `docs/evidence/oip-canonical-acceptance/acceptance.json`). The **parity of the OPC-UA address space** between the official MCP tool and the REST route is re-inventoried against the real backend. The address space is the one of the **server**: the browse delivers the name and the folder of every node, the Core admits them all and no folder is derived from the name of a node; the page names the folders of the address space (`NodePage.folders`), and the client offers exactly these folders (`crates/oip-opcua/src/adapter.rs`, `crates/oip-server/src/application_services.rs`, `apps/flutter/lib/features/opcua.dart`). The **value of a node belongs to the node with the node id of the server**: it is read by that id and never reconstructed from the name, it is bound to the **entity that the source declares** (not to the machine of a simulator profile), the namespace of a node is the namespace of its node id and its access is the access of the class of the node — the proof is the adapter test (`crates/oip-opcua/src/async_opcua/client/tests.rs`: a name that names no node still delivers the value of the node id) and the API test (`crates/oip-server/tests/api.rs`: the namespace of every node is the namespace of its node id, and the sum of the totals of the folders is the total of the catalogue, so every node belongs to **exactly one** folder and the pages stay disjoint). The **browser reads without measuring**: a single read shows the value of a node and is **not** ingested — the measurement belongs to the collector that subscribes to the registered metrics of the source; the four statements that claimed a persistence of the single read are corrected (the API contract, the capability inventory, the description of the MCP tool and the note of the surface)
The **address space of the operator is measured in the browser**: the rehearsal
`tests/oip_opcua_browser.py` starts a disposable Core with live collectors and drives the real
surface (`apps/flutter/test/browser_opcua_address_space.mjs`); the journey reads the address space
from the API and names **no** node and **no** folder of its own, so every name it looks for is the
name the Core delivered — the rows of the surface are the nodes of the Core, the identity of a node
carries the namespace, the folder and the node id that the Core delivered, the attributes that the
Core does not deliver are **named** instead of invented, the limits of the address space (no
history, no hierarchy) are named, and the keyboard search reaches a node of the Core before the
pagination (`docs/evidence/oip-opcua-browser/opcua-browser.json`,
`docs/evidence/oip-opcua-browser/address-space.json`).
The **search of the address space keeps every character**: the plain
characters of the page are handled by the page and not by a shortcut — a shortcut that matches a
character swallows it, and the operator lost every `c` of the search (the laboratory of the loop
measured `ab` for the typed `abc`). The canonical gate proves it in the browser now
(`apps/flutter/test/browser_canonical_ui_gate.mjs`).
An **independent verification** of that change (a delegated, read-only audit of the source) confirmed the eight properties as closed and found three residuals, which are closed as well: the surface named a derivation that no longer exists (the name is the BrowseName of the server, the folder is the parent in its address space), the fallback to the whole catalogue only worked when the Core named at least one folder, and the folders of a source survived the switch to another source. The browser gates derive the folder, the node and the identity of the node from the API instead of naming them, and the Rust suite relates the total of a folder to the total of the catalogue instead of encoding the size of the simulation (`apps/flutter/lib/features/opcua.dart`, `apps/flutter/test/opcua_phase2_test.dart`, `apps/flutter/test/browser_oip004.mjs`, `crates/oip-server/tests/api.rs`) (`tests/oip_opcua_parity.py`, `docs/evidence/oip-opcua-parity/opcua-parity.json`): the MCP answer, `/api/v2/opcua/nodes` and `/api/v1/opcua/nodes` are the same page (the same nodes, the same offset and the same limit), the pages are disjoint and the boundary is exact, and the reader of the other organization is refused with `RESOURCE_NOT_ACCESSIBLE` without a name of the foreign source. |
| G9 macOS build, install, start/stop, logging, backup/restore | READY (the software part) | The release build exists and is proven: the **canonical gate executed the binary that the manifest names** — the Core and the official MCP probe of the release, byte-identical with the two builds of the reproducible-build rehearsal (`docs/evidence/oip-reproducible-build/reproducible-build.json`) and with the artefacts of the manifest (`docs/release/oip-release-manifest.json`) — and the gate passes (8/8 phases, 189 browser findings with zero failures, 387/387 Flutter tests, one skipped; `docs/evidence/oip-canonical-acceptance/acceptance.json`). The served web bundle is byte-identical with the local build of the same revision. The **canonical acceptance** names the revision it ran on and the digest of the binary it executed (`docs/evidence/oip-canonical-acceptance/acceptance.json`), and the **manifest** names the binary of the release with its digest and the revision that binary names (`docs/release/oip-release-manifest.json`). `docs/runbooks/operations.md` describes the local operations and `tools/oip_ops.py` performs them; `tests/oip_operations.py` proves the sequence against a disposable instance: provisioning, start, status, log, backup with an integrity check, the refused restore of a running instance, the clean shutdown without uncommitted observations, restore, start, restart and stop, plus the three refusals of the personal installation. The **macOS application bundle** of the Flutter client is built reproducibly and proven against a disposable managed instance of the Core binary whose digest the receipt of that measurement names (`tests/oip_macos_app.py`, `docs/evidence/oip-macos-app/macos-app.json`): the bundle builds in a few seconds, it starts and reaches the Core within the first second, it asks for the authorized projection of the principal and obtains **nothing** without a session — the Core refuses every read with `403 PERMISSION_DENIED`, and the receipt names the **code** of every refusal, so the evidence says that the session was refused and not the origin, it shows the approved Spectrum-2027 shell with the operator login, it terminates on the operator's signal without leaving an orphan behind, and it starts again and reaches the Core again. Its window is checked against the visible frames of the machine and the placement is reported in the log of the bundle. The **builds of the release are reproducible**: the web release and the macOS application bundle are byte-identical when they are built twice (`tests/oip_reproducible_build.py`, `docs/evidence/oip-reproducible-build/reproducible-build.json`). The rehearsal builds the Core **twice** and the two builds are byte-identical. The manifest states the property of the release — the Core is byte-reproducible for its revision — together with the fact that the **sources of the Core are unchanged since that measurement** (`the_property_holds_for_the_release`); the strict comparison of the bytes (`the_manifest_names_the_reproducible_binary`) is reported as well and is false whenever a later build of another revision stands in the build tree, because the binary names the revision it was built from. The **whole evidence of the release is re-measured with one command** (`tools/oip_refresh_evidence.py`): every rehearsal runs and every receipt is published into its place in the checkout. The web release and the macOS bundle of this run are byte-identical to the artefacts of the acceptance, so the acceptance still describes what the release delivers. The **local installation** of the application is rehearsed (`tests/oip_macos_install.py`, `docs/evidence/oip-macos-install/macos-install.json`): the bundle of the release is copied into an installation directory — the copy is **byte-identical** over the tree of the bundle — and the **installed copy** starts, reaches the Core, is refused without a session, obtains **no** data, shows the approved shell with the operator login, terminates on the operator's signal without leaving an orphan behind and starts again from the installation directory. The rehearsal installs into a directory of the temporary tree, never into `/Applications`; the procedure for the operator is in `docs/runbooks/operations.md` §9.1. The **release manifest** names every artefact of the release with its digest, the provenance of its build, the digest over the tracked sources of the revision, the digests of the tracked acceptance receipts (including the whole acceptance of the release under `docs/evidence/oip-canonical-acceptance/`) and the state of the operator's visual acceptance (`tools/oip_release_manifest.py`, `docs/release/oip-release-manifest.json`, `docs/release/SHA256SUMS`); `--verify` recomputes every digest, so the manifest is a receipt and not a promise. The manifest names **every receipt of the release** with its digest — the two that are measured after it are the only exception, and they are named by the record — and the one-command verification fails when a receipt of the release is not digested by it. The verification also recomputes the equality of the binary that the canonical gate executed and the binary that the manifest names, and fails when the two disagree. The bundle could **not** hold a session at all: only a browser sends the origin and the cookie of the session, so the native client was refused by the Core at the login and at every read (`2e2bef1`). That defect is fixed and proven: the native client of the release build logs in with the one-time code of the operator, reads the hierarchy of the authorized scope and the scoped projection and signs out again (`tests/oip_native_session.py`, `docs/evidence/oip-native-session/native-session.json`). Remaining: the local installation as a launch agent needs operator authorization. |
| G10 security release review | READY (the review is done) · BLOCKED_OPERATOR (the acceptance) | The **review of the current release** is measured (`tests/oip_security_review.py`, `docs/evidence/oip-security-review/security-review.json`): 12 findings — 9 **resolved**, 2 **mitigated**, 1 **escalated**. Resolved: the dependency advisories of the complete lockfile (`cargo deny`: advisories, licenses, bans and sources ok; the three exceptions are documented with a reason and a review date) — **two advisories that the ecosystem reported after the last review are closed by the lockfile itself** (`Cargo.lock`): the bundled SQLite of `libsqlite3-sys` (RUSTSEC-2026-0459) and the unbounded buffering of the MCP SDK (RUSTSEC-2026-0462); `rusqlite` moves to 0.41 and `rmcp` to 3.9.0, and the whole Rust suite passes with them (`docs/evidence/oip-rust-regression/rust-regression.json`), the advisories of the **client** (the advisory service of the ecosystem reports none for `http` 1.2.2 and `flutter_lints` 3.0.2 — the only third-party packages of the client), the secret scan of the **676** files that ship (28 candidates, every one of them the digest of a file of the repository or an opaque key of the Core inside a measurement receipt — classified one by one by the receipt itself, **none** unclassified), the browser session contract (`HttpOnly`, `SameSite=Strict`, `Max-Age=1800`, `Cache-Control: no-store`, `X-Frame-Options: DENY`, CSP `frame-ancestors 'none'`), the single use of the pairing code, the origin and CSRF rule of every write, the protection of the credentials (a private 0600 file of 32 bytes that reaches no log) the enforcement of the scope (the reader of one organization sees no source of the other) and the **non-disclosure of a foreign resource** (a foreign device and a device that does not exist are refused identically with `404 RESOURCE_NOT_ACCESSIBLE` — the answer does not name the target and does not distinguish the two cases). Mitigated: the remote identity (the Core binds to 127.0.0.1 only — a productive remote identity is **not** implemented and **not** claimed) and the same-UID boundary (0600/0700 and the UID rule; the boundary does **not** isolate hostile processes of the same user). Escalated: the execution audit is a structured local log and is **neither durable nor tamper-resistant** — acceptable for a local instance with an authorized operator, a prerequisite for a remote or productive deployment. The production-security scope needs the explicit acceptance of the operator. The one-command verification **measures** the boundary of the personal store of the operator instead of asserting it: the digest and the schema of the store are read read-only and compared with the digest of the record and with the digest that the rehearsal of the activation recorded — the store is unchanged and still at schema 6, and a store that cannot be read is reported instead of passing silently. |
| G11 acceptance, a11y, perf, resilience, upgrade/rollback | DONE | The **storage-failure path of the Core is measured** (`tests/oip_storage_failure.py`, `docs/evidence/oip-storage-failure/storage-failure.json`): a store that cannot be written is the one failure mode of the instance, and it is rehearsed on a **bounded volume** — a disk image of 64 MiB that the store of a disposable instance fills up until the write is refused (the receipt names the space that was still free when the refusal came), without any privilege and without touching the personal installation. Measured: the instance **survives** the full volume (it keeps answering with 200), the health **degrades honestly** (the instance is no longer `ready`, `persistence_healthy` is false, the counter of the persistence errors grows and the last error is named `commit_failed_retry_pending`), the log **names** the failure (`persistence_retry`), the store is **not corrupted** (`pragma integrity_check` answers `ok`), the instance **recovers** when the space is freed (`ready` is true again, the persistence is healthy and the collection continues — the receipt of the run names the counts), and the shutdown is clean. The lifecycle of the Core follows the state of its store: it is `ready`, it becomes `degraded` while the store cannot be written, and it is `ready` again after the recovery — the receipt of the run names the three states. The earlier escalation — that the mode of the file or of its directory does not fail the writes of an open store, a full disk is forbidden and a read-only mount is privileged — is answered by the bounded volume; the gap is closed and needs no operator decision. The **Rust** suite of the Core is part of the evidence of the release: `cargo test --workspace --release` on the tree that carries the last change of the Core delivers **191 tests in 30 suites, 0 failed** — the unit tests of every crate, the eleven integration suites of the Core (`api`, `browser_session`, `capabilities`, `diagnostics`, `hierarchy`, `inventory`, `ipc`, `mcp`, `provision_cli`, `reliability`, `settings`) and the doc tests (`tests/oip_rust_regression.py`, `docs/evidence/oip-rust-regression/rust-regression.json`). The canonical regression passes with the **release** binary and the release web bundle; the whole acceptance is a tracked receipt (`docs/evidence/oip-canonical-acceptance/`). The accessibility receipt of the six workstations measures the name and role coverage of the rendered surface: 152 controls, none without an accessible name, no JavaScript error, no external request (`docs/evidence/oip-accessibility/accessibility.json`); it is not a full WCAG audit. The upgrade and the rollback of a local instance are rehearsed against a protected historical binary and the current release binary: the store is migrated from schema 3 to 8 with the data intact and the backup restores the previous state (`docs/evidence/oip-upgrade-rollback/upgrade-rollback.json`). The rehearsal runs the **daemon of the era against real collectors**, so the store of the handover is a live instance: the whole inventory of the operator survives the takeover (the hierarchy, the principals, the roles, the observations **by their stable Core IDs**, the events, the gaps and the health transitions), the migration creates the tables of the new era, and the rollback restores the store **exactly** — including the absence of the tables the era did not know. The **performance baseline** of the release build is measured over three runs against a disposable managed instance (`docs/evidence/oip-performance/performance.json`): the **first paint of the delivered web release is bound to the transfer of its bundle over the loopback of this machine** — it is the only measurement of the run that the transfer dominates; the application itself is interactive as soon as the session exists and the authorized projection is rendered immediately afterwards. The receipt of the run carries the numbers of the three runs, their median and the resident memory of the Core; a local measurement, not an SLA. The **daemon handover** with the protected historical binary is rehearsed against a disposable instance (`tests/oip_historical_daemon.py`, `docs/evidence/oip-historical-daemon/historical-daemon.json`): the OIP-007 shape of the local IPC policy is *measured* to be refused by the historical daemon (`invalid protected local IPC configuration/path`), the OIP-008 shape of its era — a credential bound to a provisioned, enabled principal — starts the daemon, which collects the observations of its sources and answers the authorized reads of its principals, each only in its own scope (the reader of an organization sees three sources, the reader of the other organization sees the fourth, a read without a credential is refused with 403). The release binary then takes over the same store (schema 5 to 8, the observations intact), the backup restores the state of the historical daemon (schema 5, the observations identical), and the historical binary adopts the restored store **and serves it again**. The **reconnect and the recovery of the application** are proven in the browser against the real Core (`tests/oip_reconnect_recovery.py`, `docs/evidence/oip-reconnect-recovery/reconnect-recovery.json`): a restart of the instance in the middle of a session leaves no stale content on the surface, the operator sees the identity notice with the refusal of the Core, the login panel names the restart as a cause of the end of the session, and a new one-time code restores the authorized projection with a fresh moment (11 checks). The **extended stability run** of the release binary is measured over a sustained run under the load of the collectors (`tests/oip_stability.py`, `docs/evidence/oip-stability/stability.json`): the Core answered every probe, the resident memory did not grow, the collection rate stayed steady, the death of a collector was recorded as a documented gap and the collection resumed, the shutdown was clean and the integrity check of the store answered `ok`. The **canonical acceptance** of the release was run with the release binary and the delivered web bundle; the whole acceptance is a **tracked receipt** (`docs/evidence/oip-canonical-acceptance/acceptance.json`) and names the revision and the tree of its run: 387 of 387 Flutter tests, 189 browser findings with zero failures, 13 captures, the visual comparison **PASS**, the eight functional phases 8 of 8 **PASS**, the served bundle byte-identical to the local build. Missing: nothing of the acceptance of this gate is open; the visual acceptance of the operator stays `VISUAL_PENDING_OPERATOR_ACCEPTANCE` and belongs to G12. |
| G12 operator acceptance | BLOCKED_OPERATOR | Requires the operator to launch, authenticate, configure and connect real devices. The path is rehearsed: the native client of the release build holds a session of the real Core, the device with its verified connection is shown in the surface, and the operator login names **every** cause of the end of a session — the lifetime, the sign-out and the restart of the instance — and the pinned test asserts all three (`apps/flutter/test/managed_core_integration_test.dart`). The **login in the shipped macOS bundle** is the one step that no rehearsal drives: the login of the browser is proven by the acceptance, the login of the native transport by the native client, and the bundle itself is proven to reach the Core with the URL of the operator and to be refused without a session — but a one-time code is typed into a native window, and an autonomous run on this machine cannot drive that window (the terminal holds no assistive access). **That step is the operator's own** and belongs to his acceptance. What remains is the operator himself and a physical device. |

## Next READY tasks (independent of blockers)

1. **N19 (G11)**: the performance baseline of the release build is **measured** over three runs
   against a disposable managed instance (`tests/oip_performance.py`,
   `docs/evidence/oip-performance/performance.json`) and **interpreted**: the first paint is bound
   to the transfer of the bundle of the web release over the loopback, not to the application —
   the shell is interactive as soon as the session exists and the authorized projection follows
   immediately. The receipt of the run carries the numbers of the three runs and their median. A
   smaller delivery — or a local service worker — is a **product decision** and is named as such
   in the operator actions below; it is not an agent decision.

2. **N20 (the architecture of the operator)**: the **Core on the Raspberry Pi**. The
   reconciliation of the intended architecture with the contracts of the Core and of the
   client is in `docs/runbooks/operations.md` §15: a forward of the loopback of the Mac (an
   SSH tunnel) keeps the **identical origin** of the session, so the session contract, the
   origin rule and the security scope of G10 stay unchanged and **nothing is exposed**. The
   cross build of the workspace for the target of the Pi is **READY** on the Mac
   (`tools/oip_pi_build.sh`);    the **read-only discovery** of the host, the disposable
   instance that is started by hand and the tunnel are **BLOCKED_OPERATOR** — the SSH
   session of the loop is not permitted (`tools/oip_pi_discovery.sh` is the script the
   operator runs). The **bundle of the instance** is READY and measured: the operator's part
   is one copy and one command (`tools/oip_pi_bundle.sh`, `docs/evidence/oip-pi-bundle/pi-bundle.json`).

3. **N21 (the deployed hosts and the device classes of the operator)**: the **hosts** are
   **measured** read-only in their own rehearsal, so that their receipt stays fresh at every
   revision of the release (`tests/oip_deployment_hosts.py`,
   `docs/evidence/oip-deployment-hosts/deployment-hosts.json`: the identity, the architecture, the
   memory, the disk, the toolchain, the services of the operator — unchanged before and after the
   measurement — and the listeners of `bodi-pi` and `bodi-pc`, the target of the cross build
   answered by the Pi and the ports of the plan free on it). The **discovery** of the two new
   devices is measured in the rehearsal of the discovery
   (`tests/oip_deployment_discovery.py`,
   `docs/evidence/oip-deployment-discovery/deployment-discovery.json`; the receipt of this revision
   is **stale**: the router and the bridge are on `192.168.1.x` and the network of this machine is
   `192.168.178.0/24`, so the rehearsal of the discovery failed in the refresh of this iteration —
   the operator's action below): the architecture of the Pi
   answers the target of the cross build, the ports of the plan are free, the services of the
   operator are unchanged before and after the measurement, the router answers with **dropbear**
   (the JSON form of `ip` does not exist there — the collector of the Core reads the one-line
   form now), and the bridge answers its public configuration while it **refuses** its lights
   without a token. The **Core needs no change for the router** (the SSH onboarding applies); the
   bridge has **no onboarding transport in the Core** and is therefore an inventory device with
   its measured identity — its monitoring and its control are **not** implemented and are not
   simulated (`docs/architecture/oip-capability-inventory.md`).

4. **N22 (the Mac App Store readiness of the client)**: the **requirements of the store are
   read** (`docs/release/mac-app-store/requirements.md`, with the sources and the date), and the
   **package is measured** (`tools/oip_mas_package.py`,
   `docs/evidence/oip-mas-package/mas-package.json`): the release build carries the **hardened
   runtime**, the entitlements of the release are the **app sandbox** and the **network client**
   (the entitlements file carries no debug entitlement), the bundle carries the **privacy
   manifest** (`PrivacyInfo.xcprivacy`: no tracking, no collected data, the three required-reason
   categories with their reason codes), **no file** carries the `com.apple.quarantine` attribute,
   and the `Info.plist` names the category and the exception of the transport security for the
   local networking (the Core of OIP answers on the loopback). The **metadata** of the listing and
   the **privacy policy** are prepared (`docs/release/mac-app-store/metadata.md`,
   `docs/release/mac-app-store/privacy-policy.md`). The **store assets** of the listing are
   **measured** as well (N25): the six workstations of the client in a size that Apple accepts
   for a Mac app, without an alpha channel, checked against the prohibited regressions
   (`docs/evidence/oip-store-screenshots/`). The upload itself, the identity, the certificate,
   the profile and the two public URLs are the operator's.

5. **N24 (the Core on the Raspberry Pi)**: the **deployment is measured** now
   (`tests/oip_pi_instance.py`, `docs/evidence/oip-pi-instance/pi-instance.json`): the cross build for
   the target of the host, the bundle, the **start by hand** (no service, no published port, nothing
   outside the directory of the instance), the Core answering **through a tunnel of the loopback**,
   the session of the operator minted **on the host** over its local IPC, the authorized projection
   (the address space of the simulation of the host: 1020 nodes in five folders) and the **stop** —
   with the services of the operator the **same list** before and after. The host discovery that
   decided the target is measured too (`docs/evidence/oip-deployment-discovery/deployment-discovery.json`).

6. **N25 (the store assets of the Mac App Store listing)**: **measured**. The **sizes that Apple
   accepts for a Mac app** are read from the official source and recorded with the date
   (`docs/release/mac-app-store/screenshots.md`: 1280 x 800, 1440 x 900, 2560 x 1600,
   2880 x 1800, each with a 16:10 aspect ratio; **no alpha channel**). The **six workstations
   of the client are captured in 1440 x 900** by the release build of the client through the
   managed Core (`tests/oip_store_screenshots.py`,
   `apps/flutter/test/browser_store_screenshots.mjs`,
   `docs/evidence/oip-store-screenshots/store-screenshots.json`,
   `docs/evidence/oip-store-screenshots/captures/`): every capture is the **viewport** (never
   the full page), its **exact pixel size and the absence of an alpha channel are read out of
   the file itself**, the captures carry **none** of the prohibited regressions R1-R10 (every
   marker of the contract is checked on every workstation), and the rehearsal leaves **no
   process** behind. The captures are the **store assets**; the acceptance of the operator of
   the visible result stays **pending** (G12) and is never claimed by the capture.

7. **N26 (the Philips Hue Bridge as a real device)**: the **onboarding is implemented and
   measured** (`tools/oip_hue.py`, `tests/oip_hue_device.py`,
   `docs/evidence/oip-hue-device/hue-device.json`; the receipt of this revision is **stale**: the
   bridge is on `192.168.1.x` and the network of this machine is `192.168.178.0/24`, so the
   rehearsal of the bridge failed in the refresh of this iteration — the operator's action below):
   the identity of the bridge is verified
   against the **pin** of its own certificate (`docs/release/hue/bridge-certificate.pem` — the
   bridge does not present the root of its chain, so the certificate of the device is the only
   trust anchor, exactly like the host key of an SSH host), the **public configuration** is read
   in **one** verified TLS session, the device is written into the inventory of the Core through
   the **authorized session** and its verified facts (model, software, API, bridge id, MAC) are
   readable there. A bridge with **another** certificate is refused — at the pin **and** in the
   TLS session. The **lights stay unsupported**: the bridge refuses them without an application
   token, and the token is a **write on the device** that belongs to the operator. Nothing is
   simulated.

8. **N27 (the type of a device is named honestly)**: **measured**. The Core paints the type of a
   device as the **raw identifier of its own enum** — `SingleBoardComputer`, `NetworkDevice`,
   `IndustrialDevice` — and the client painted that identifier as if it were a word of the
   surface; the defect was visible in the **own painted-surface evidence** of the record
   (`docs/evidence/oip-device-connection/painted-surface.txt`). The vocabulary now has **one**
   owner (`apps/flutter/lib/widgets/device_kind.dart`): every type that the Core can really
   deliver gets a word, an icon of its own and a category, and a type that the client does not
   know stays honestly named with the icon of an unknown device. The filters show the word and
   keep the identifier as the value; the grouping stays on the identifier. The test closes a gap
   of zero coverage (`apps/flutter/test/device_kind_test.dart`).

9. **N28 (the export recipe of the App Store listing)**: **measured**. The **upload step** has a
   recipe in the repository now: a template with **placeholders** (the team, the profile and the
   certificate are the operator's), a tool that renders it into the build tree of the machine,
   prints the command and **refuses** while the identity of the operator is incomplete — naming the
   flag and the environment variable of every missing value — the **display name** of the app
   (`CFBundleDisplayName = Open Industrial Platform`, while the name on the disk stays the
   technical one, because the paths of the release name it) and the **App Review notes** of a
   client whose access is a one-time code minted on the instance itself
   (`docs/release/mac-app-store/ExportOptions.plist.template`, `tools/oip_mas_export.py`,
   `tests/oip_mas_export.py`, `docs/evidence/oip-mas-export/mas-export.json`). The recipe is
   measured, not asserted: the rendered file carries every key and no placeholder any more, lies
   outside the release and leaves the checkout untouched. Nothing of it invents a credential and
   nothing of it uploads.

10. **N23 (the secure update of the deployed software)**: the **update path of the Core** is
   implemented and **measured** (`tools/oip_update.py`, `tests/oip_update.py`,
   `docs/evidence/oip-update/update.json`, `docs/runbooks/operations.md` §16): the bundle is
   **authenticated** with an Ed25519 signature over the exact bytes of the manifest, the
   **integrity** of every artefact is verified before the activation and again after the
   write, the activation is **atomic** (a renamed symlink), the new version is **health
   checked** as a disposable instance, a version that does not become ready is **rolled
   back**, and every attempt — the successful ones and the refused ones — is written into a
   **durable journal** of the instance. The **private key of the operator never reaches a
   host**; the public key of the instance is the only thing the host sees. The **client**
   of the operator is **not** updated by this path: an app of the Mac App Store is updated
   by the store.

11. **N29 (the note of a device)**: **measured**. The Core holds an optional free text `notes` in
    its inventory (`crates/oip-core/src/inventory.rs`), and the client read the inventory but
    **never showed** the note — so the honest limit of a capability (the Philips Hue Bridge: a
    read-only identity, no control without an application token) was in the record of the Core and
    nowhere in the surface. The Devices workspace shows the note under the identity grid
    (`apps/flutter/lib/features/devices/device_detail.dart`); a note that the Core does not hold is
    named as unavailable, and the panel never invents one
    (`apps/flutter/test/device_identity_test.dart`).

12. **N30 (the export recipe of the App Store listing)**: **measured**. The recipe wrote wherever
    it was told to write: the directory of the rendered options (`--out`) was not validated, and
    the tool **removes** that directory before it writes into it — a directory that the operator
    names by mistake would have been removed. The tool now **refuses** every directory outside the
    build tree of the machine, and it checks the directory **before** it writes anything. The
    recipe also named a signing style that the operator did not choose: the profile and the
    certificate are required, while `xcodebuild` honours them only under the **manual** style — the
    tool now exports with that style and refuses another one with that reason. The refusal names
    the flag and the environment variable of every missing value, and the rehearsal reads the
    **rendered file** itself instead of the report of the tool
    (`tools/oip_mas_export.py`, `tests/oip_mas_export.py`,
    `docs/evidence/oip-mas-export/mas-export.json`).
13. **N31 (the state of the VPN on the surface, and the contract of the service inventory)**:
    **measured**. The summary of the Network workstation showed `VPN-TELEMETRIE · Nicht verbunden`
    — a hard-coded string, while the Core delivers **no** VPN telemetry (no peer, no endpoint, no
    handshake, no route, no tunnel health); in the demo the Core delivers `connected` for the
    remote devices, and the chip contradicted it. The chip says **`NICHT GELIEFERT`** now — the
    word that the logical paths use when the Core delivers no topology — and the hint of the VPN
    workspace says `Keine VPN-Telemetrie geliefert` (`apps/flutter/lib/features/network.dart`).
    The **contract** of the capability that is missing exists now
    (`docs/architecture/OIP_DEVICES_SERVICES_2027_CORE_REQUIREMENTS.md`): the Services workspace
    pointed at a document that the repository did not hold.

14. **N32 (the authorized service inventory of the Core)**: **measured**. The Core had **no** service
    registry: the inventory is a registry of **devices**, the plan had no section for the services,
    and the Core had no capability, no route and no MCP tool — the two workstations that would show
    them named the absence honestly. The registry is what the **operator declared** in the plan
    (the Core measures no service, so every record carries the provenance `declared`), and the Core
    delivers it like the inventory: the capability `service_registry_read` with the permission of
    the inventory read, the route `GET /api/v2/services` and the MCP tool `oip_services_read`, the
    scope of the hierarchy and the refusal of a foreign identifier **identically** to the refusal of
    an unknown one (`crates/oip-core/src/services.rs`, `crates/oip-server/src/service_services.rs`,
    `docs/architecture/OIP_DEVICES_SERVICES_2027_CORE_REQUIREMENTS.md`). The store holds the
    declarations (the migration 8 ✓), a declaration is stable like every other identity of the
    plan ✓, and the client shows the registry in the Services workspace, in the comparison and in
    the device detail ✓ (`apps/flutter/lib/features/devices/service_registry.dart`) — measured in
    `docs/evidence/oip-service-registry/service-registry.json`.

15. **N33 (the note of a device is writable in the surface)**: **measured**. The Core holds an
    optional free text `notes` in its inventory and the client **showed** it (N29 ✓), but the
    operator could not write it: the Core replaces the metadata of a device as a whole, so the
    client had to merge the edited note into the metadata that it sends back — otherwise the
    write dropped the note. The **note is writable where the device is** now: the administration
    of the inspector carries the field of the note, the client merges the note into the metadata
    that it sends back (a write of the name never drops the note, and an emptied note is removed
    from the record instead of being written as an empty text), and the controller of the field
    is released with the widget (`apps/flutter/lib/features/devices/device_administration.dart`).
    The **journey of the real surface** proves it against the real Core
    (`apps/flutter/test/browser_onboarding.mjs`,
    `docs/evidence/oip-device-administration/device-administration.json`): the operator writes the
    note in the inspector, the Core keeps it and the revision of the record advances, and a write
    whose metadata does not carry the note **drops** it — the contract of the Core is measured,
    not asserted. The widget test proves the merge of the client
    (`apps/flutter/test/device_administration_test.dart`).


16. **N34 (the journeys of the client that no harness names)**: **measured**. Twenty-two browser
    journeys and performance scripts under `apps/flutter/test/` were named by **no** harness: no
    rehearsal of the refresh, no case of the canonical regression, no script of the tools. Their
    proofs were therefore **no receipts** — and every one of them waited for the surface of the
    OIP/005 demo (`Operations Workstation`), one of them for its slogan (`Deine Infrastruktur. Ein
    Bild.`): a file that asserts the prohibited surface is a trap for the next reader. The journeys
    are **retired** (they stay in the history of the repository). The claim of the address space,
    which the record had backed with one of them, is measured again by a **rehearsal**
    (`tests/oip_opcua_browser.py`, `apps/flutter/test/browser_opcua_address_space.mjs`,
    `docs/evidence/oip-opcua-browser/opcua-browser.json`).

17. **N35 (the live claims of the retired journeys)**: the **next READY task**. Ten of the retired
    journeys still prove **live** claims of the surface — the density and the geometry of the
    Devices workspace, the geometry, the comparison and the transport of the Network workspace, the
    value modes, the page filter and the performance of the address space, the timeline and the
    stale marking of the Diagnostics workspace, the depth and the performance of the settings, and
    the performance of the Overview. Each group needs its own rehearsal — a disposable Core with the
    collectors that it needs, the journey, and the receipt that the refresh publishes. The journeys
    that need the **fixture servers** of the old contract need those servers taught the current
    contract first (the session, the hierarchy and the snapshot of the managed mode), or the claim
    is withdrawn. The files stay in the history of the repository until then.

    The **first group is measured**: the density of the Devices workspace. The rehearsal
    `tests/oip_devices_density.py` starts a disposable Core with the plan of the operator,
    registers the devices **through the authorized route** (so the rows of the inventory are the
    devices that the Core delivered) and drives the real surface in the browser
    (`apps/flutter/test/browser_devices_density.mjs`): six widths (320, 390, 768, 1024, 1440 and
    1920 px) and three themes (Spectrum, Graphite and Daylight), fourteen checks in all — the
    document never scrolls horizontally, no control of the filter toolbar is clipped outside the
    viewport, the disclosure of the secondary filters opens and the inventory explorer is rendered
    (`docs/evidence/oip-devices-density/devices-density.json`). The **next** group is the
    Diagnostics workspace: the timeline and the stale marking of its events.

    The **second group is measured**: the Network workspace of the managed surface. The Core of
    the managed mode delivers the devices, the sources, the observations and the events — and
    **no logical path**: the scoped snapshot of the Core has no topology
    (`crates/oip-core/src/hierarchy.rs`), no route delivers links (`crates/oip-server/src/api.rs`)
    and the projection of the client knows that the paths are not delivered
    (`apps/flutter/lib/models/infrastructure.dart`). The rehearsal
    (`tests/oip_network_2027.py`, `apps/flutter/test/browser_network_2027.mjs`) measures what the
    managed surface can honestly measure, in twelve checks
    (`docs/evidence/oip-network-2027/network-2027.json`): the summary names the absence
    (`LOGISCHE PFADE NICHT GELIEFERT`, `VPN-TELEMETRIE NICHT GELIEFERT`, `DEMO-PFADE 0`), the list
    of the paths is empty and says that an empty result is no offline state, the transport filter
    offers only the transports that the Core delivered — here only `alle` — the Device Explorer
    shows exactly the devices that the Core delivered (the counter, the rows, the search, the
    relation filter), the comparison of two devices names its own limit (`2/4 Geräte · 0/4 Pfade ·
    sitzungslokal`), the graph names its empty state, the markers of the demo of the generation
    2027 are absent, and the channel that goes stale is named as stale and comes back.

    The **third group is measured**: the geometry of the Devices workspace. The layout is a claim
    of the release — the operator accepts the visible result (G12) — and the numbers of the layout
    are the evidence that the acceptance can look at. The rehearsal
    (`tests/oip_devices_geometry.py`, `apps/flutter/test/browser_devices_geometry.mjs`) registers
    the devices **through the authorized route** and measures the **four states** of the workspace
    — no selection, a device selected, the secondary filters open and the comparison — at 1440 px
    and 1920 px: the height of the filter bar (42 px, 79 px with the secondary filters open), the
    number of its controls (4 and 7), the height of the search field, the pitch of the rows of the
    inventory, the edges of the content and the height of the document
    (`docs/evidence/oip-devices-geometry/devices-geometry.json`).

    The **fourth group is measured**: the evidence workspace of the Diagnostics workstation. The
    rehearsal (`tests/oip_diagnostics_2027.py`, `apps/flutter/test/browser_diagnostics_2027.mjs`)
    starts a disposable Core with **live** collectors, drives the surface and then changes the
    state of the source: the collectors die and come back. The journey names **no event of its
    own** — every row of the explorer and every marker of the timeline is checked against the
    events of the Core (read from the diagnostic history of the authorized context), the attributes
    that the Core does not deliver are named instead of invented (the severity, the source
    timestamp, the record id), and the **loss** of a source is the evidence of the Core: the
    `ConnectionLost` event, the sources `disconnected` / `unknown` / **stale** with the last error
    named, and the recovery measured by the health of the source
    (`docs/evidence/oip-diagnostics-2027/diagnostics-2027-rehearsal.json`). The **recovery of an
    OPC-UA source is not a collection event of the Core** — the adapter reconnects without an
    event — so the evidence of the recovery is the health of the source and its reconnect attempts.
    The **next** group is the **Settings workspace** (the depth of its categories) and the
    **Overview** (its performance).

    **Two claims of the group are withdrawn**: the geometry of the graph over real links and the
    transport filter over real transports cannot be measured against the managed Core, because the
    Core delivers no link. The geometry stays proven at the widget level
    (`apps/flutter/test/network_workstation_test.dart`), and the browser proves that the surface
    names the absence instead of simulating it.

    The **fifth group is measured**: the depth of the Settings workspace. The rehearsal
    (`tests/oip_settings_depth_2027.py`, `apps/flutter/test/browser_settings_depth_2027.mjs`)
    starts a disposable Core with the plan of the operator and drives the managed surface with the
    session of the operator. The settings and the management report are **platform** capabilities;
    the example plan grants neither, so the rehearsal grants `settings_read` and
    `mcp_management_read` at platform scope to the reader it authenticates and records the grant in
    the receipt — without it the surface would show the refusal of the Core instead of the
    workspace. The journey names **no settings key, no tool and no schema of its own**: every
    category of the Core is offered, the settings keys are the keys of the Core, the server section
    names every fact of the server report, the search reaches a tool of the tool catalog, the
    inspector names its permissions and its scopes, and the copied schema is **byte-equal** to the
    schema that the Core delivered for that tool. The write path is proven absent (no save control
    and the offline administration of the Core), the client configuration is the template of the
    Core (the two placeholders, no bearer token, no credential-looking value and
    `credential_provisioned: false`), and the limits are named: the unsupported client sessions,
    the absent retention cleanup, the read-only connection diagnostics, the open advisories of the
    security category and the `Unknown — no host collector data in this contract` of the runtime.
    Twelve checks, measured against the Core (`docs/evidence/oip-settings-depth/settings-depth.json`).
    The **next** group is the performance of the Overview.

    The **sixth group is measured**: the performance of the Overview. The rehearsal
    (`tests/oip_overview_performance_2027.py`, `apps/flutter/test/browser_overview_performance_2027.mjs`)
    starts a disposable Core with four live collectors, waits until the Core has recorded the
    collection events that the Overview lists, and drives the managed surface with the session of
    the operator. The journey measures what the operator feels: the latency of **twenty-three**
    interactions — the three tabs of the activity workspace, the event filter of the kind that the
    Core delivered (`Reconnected`), the change of the global context and its return to the unified
    view, six round trips through the Devices workstation and six switches of the theme — with a
    median of 224 ms, a p95 of 602 ms and a maximum of 755 ms against a budget of 3000 ms; the
    frames of the browser (516 samples, median 17 ms, p95 17 ms, max 50 ms); the long tasks of the
    main thread (one task of 51 ms against a budget of 250 ms); the heap the surface retains
    (7,789,951 bytes after an explicit collection, against a budget of 24 MiB) and the frames the
    compositor presented (363 presented frames, 297 paints, 365 layerizations, 77 layouts and 139
    style recalculations). The numbers of the surface are the numbers of the Core: the status strip
    names 3 sources and 3 devices, the activity list holds the records of the Core, and the filter
    reaches the kind that the Core delivered. The refusals of the Core (6 routes at the platform
    scope of the reader) are recorded as refusals and no request leaves the loopback. The **scope is
    a local measurement on the loopback of this machine, not an SLA**
    (`docs/evidence/oip-overview-performance/overview-performance.json`,
    `docs/evidence/oip-overview-performance/overview-performance-rehearsal.json`): eleven checks,
    measured at `d177881` on a clean tree. The **next READY task** is N36.

18. **N36 (the actions of a row reach the semantics tree)**: **COMPLETE — committed in `4132d8d`
   ("the compare and the pin of an explorer row reach the semantics tree"), the canonical source
   revision of the product, and part of the accepted release at `0a9b64f`.** The compare and the pin
   of a row **are** in the semantics tree of the surface: each row excludes only its **icon** and its
   **texts** with `ExcludeSemantics`, and the compare and the pin `IconButton`s are **not** excluded,
   so assistive technology reaches them by name without the keyboard. It is so in the row of the
   Device Explorer (`apps/flutter/lib/features/network/network_explorer.dart`) and the row of the
   Event Explorer (`apps/flutter/lib/features/diagnostics/event_explorer.dart`), and it is proven in
   the browser by `apps/flutter/test/browser_network_2027.mjs` ("the compare and the pin of a row are
   in the semantics tree and reachable by name") and
   `apps/flutter/test/browser_diagnostics_2027.mjs` ("the pin of an event row is in the semantics
   tree and reachable by name"). The Event Explorer row also shows the record id the Core delivers
   (`API-RECORD <id>`, or `OHNE RECORD-ID` when it is absent) instead of the earlier
   `keine Server-Record-ID`. The defect that this closed — the row excluded the semantics of its
   whole descendants, so the two buttons were reachable only by the documented keyboard (`P`, `C`) —
   was a product change and needed the re-measurement of the release, which the accepted tree at
   `0a9b64f` carries.

The independent tasks of this list are **exhausted**: **N35 is complete** — its six groups are
measured (the density and the geometry of the Devices workspace, the Network workspace with two
claims withdrawn, the evidence workspace of the Diagnostics workstation, the depth of the Settings
workspace and the performance of the Overview) — and **N36 is complete** (`4132d8d`). The full
release cycle at the final revision that was to follow N36 is **done**: the final acceptance ran on
`0a9b64f` and the record was verified at `1d3fc02`; the canonical source revision of the product is
`4132d8d`. There is **no** agent-addressable task left in this list — every item N19–N36 is measured
or complete — and the release is feature-complete for the agent. What remains are the operator
actions in the next section: the product decision on the delivery of the web release, the physical
device of G5, the production-security scope of G10, the operator acceptance of G12, the network
reachability of the two deployed devices for their discovery, and the Mac App Store archive and
upload.

## Operator actions required (nothing here is executed by the loop)

* The **two real devices of the operator are reachable** from the network of this machine: the
  router (`192.168.1.1`) and the Philips Hue Bridge (`192.168.1.131`, model `BSB002`) are on
  `192.168.1.0/24`, and the machine is now on the same network (`en0` = `192.168.1.219`, gateway
  `192.168.1.1`). A **read-only** discovery in the refresh of this iteration re-confirmed the bridge
  of Iterations 73 and 79 — the same `BSB002` that their receipts discovered (API `1.78.0` in
  `docs/evidence/oip-hue-device/hue-device.json`); its REST API is up but **authentication-gated**
  (a `GET` of the API refuses without a key) and the router serves LuCI behind a login. Nothing on
  either device was touched: no API key was requested, no link button pressed, no router login. The
  discovery and bridge receipts (`docs/evidence/oip-deployment-discovery/deployment-discovery.json`,
  `docs/evidence/oip-hue-device/hue-device.json`) are present, tracked and **not** flagged by the
  verification of the release. The bridge is an **identity-only inventory device** (model, bridge id,
  MAC, IP, verified pin); its **monitoring and control are not supported** — a control capability
  would be a new permission, audit and scope (the negative control is measured in `hue-device.json`),
  which only the operator can authorize. The operator's action: authorize the Hue monitoring/control
  capability (an API key via the link button, plus the new permission), or accept the bridge as an
  identity-only inventory device. (The earlier note that the devices were unreachable from
  `192.168.178.0/24` was the state of the machine on another network and is superseded.)

* Decide F5 permission rule (N1b) and protected schema-7 activation with a fresh schema-6 backup (N4).
  The activation itself is **rehearsed on a copy** of the store of the operator: the migration is
  accepted (schema 6 to 8), the inventory of the instance survives it unchanged, the integrity
  check answers `ok` and the personal installation itself is untouched
  (`docs/evidence/oip-activation-dry-run/activation-dry-run.json`). The decision and the fresh
  backup remain the operator's.
* Name an approved physical device and credentials path for G5/G12.
* Accept or reject the production-security scope (G10).
* The operator adds infrastructure by **extending** the plan of the instance and provisioning it
  again (`docs/runbooks/operations.md` §1.2, measured in
  `docs/evidence/oip-extend-registry/extend-registry.json`): the sources survive, the new source
  collects, and a plan that drops a source is refused — the registry of an instance is stable.
* The operator can give their instance a name with the **offline** change of a setting — the
  only path the Core offers (`docs/runbooks/operations.md` §12, measured in
  `docs/evidence/oip-settings-offline/settings-offline.json`). Nothing has to be authorized for
  it; the procedure is documented.
* Authorize the local installation of the application as a launch agent (G9/N17) and name the
  release artifacts that may be signed and distributed. The application bundle itself is built
  and proven (`docs/evidence/oip-macos-app/macos-app.json`); only the installation as a system
  service is missing. The artifacts that could be signed are named with their digests in
  `docs/release/oip-release-manifest.json` and `docs/release/SHA256SUMS` — the decision is which
  of them may be distributed, not what they are.
* Decide the pagination contract of the OPC-UA address space: the address space is the live
  catalog of the collector and is paginated by offset. The pages of an unchanged address space
  are disjoint and the boundary is exact (measured), but the catalog is replaced when the
  collector connects again, so a page that is read across such a change **can** repeat a node at the
  boundary. The measured reconnect shows the opposite of a repetition — the content and the order
  of the page did not change and **no** node was repeated at the boundary
  (`docs/evidence/oip-opcua-parity/opcua-parity.json`) — so the repetition is a possibility of the
  design of the collector and **not** a measured effect. Every other paginated surface of
  the Core — the diagnostic pages, the observation history — uses an opaque cursor and is
  therefore stable. Giving the address space the same cursor changes the query of the REST and
  MCP surface of the Core and is a contract decision of the operator, not of the loop.
* **The Core on `bodi-pi`**: the **deployment is measured** — the Core really runs on the
  Raspberry Pi, it answers through a tunnel of the loopback, the session of the operator is minted on
  the host, and the services of the operator are unchanged
  (`docs/evidence/oip-pi-instance/pi-instance.json`). What remains for the operator is the
  **decision to keep it running** (the rehearsal stops the instance and leaves its files on the host)
  and the **client** that is built for the port of the instance. The operator intends the Core to run
  on the Raspberry Pi and
  the Mac to run **only** the Flutter client. The reconciliation and the smallest safe step
  are in `docs/runbooks/operations.md` §15; the plan installs no service, publishes no port,
  changes no BODI service of the host and touches no personal data. The **outstanding
  operator action** is the read-only discovery of the host: the SSH session of this loop is
  not permitted, so the operator runs `tools/oip_pi_discovery.sh` on `bodi-pi` and reports
  the architecture (`aarch64` or `armv7l`) and the free port; the loop then fixes the
   the target of the cross build (`tools/oip_pi_build.sh`) and the operator starts a disposable
  instance **by hand** over SSH and reaches it through a tunnel of the loopback. The **cross
  build itself is measured**: the workspace builds for `aarch64-unknown-linux-gnu` without a
  Rust toolchain on the Pi — the Core and the simulator are ELF binaries for ARM aarch64, and
  the digests are named in `docs/runbooks/operations.md` §15.3. The target depends on the answer
  of the discovery, and the artefacts were **never started on the Pi**: a binary that was not run
  on the target host is not a proven artefact. The runtime proof is the operator's phase 2 and
  phase 4.
* **The instance of the Pi is one bundle and one command** (`tools/oip_pi_bundle.sh`): the bundle
  carries the two binaries, the tool of the instance, the generator of the files of the instance,
  the scripts and the digest of every file; the operator copies it to the host and runs
  `./bin/start.sh`. The **bundle is measured** (`tests/oip_pi_bundle.py`,
  `docs/evidence/oip-pi-bundle/pi-bundle.json`): the whole procedure is rehearsed with stubs, the
  files of the instance are absolute and inside the instance, the procedure writes **nothing
  outside** the instance, the code of the operator session is minted over the local IPC of the
  instance, the instance stops without a forced signal, and the bundle installs **no service**,
  publishes **no port** and names **no path** of the machine it was built on. Two facts of the
  audit of the host-locality are part of the plan: the code of the session can only be minted in
  the **principal mode** of the local IPC (the generator writes it), and the **Core needs no
  change** — the trust of the simulation origin is bound to the origin id and not to a host, so
  the simulation of the Pi is trusted exactly like the simulation of the Mac.
* **The OpenWrt router**: the operator onboards it over SSH like every other device: the
  credentials and the **confirmation of the host key** are the operator's step
  (`tests/oip_deployment_discovery.py` names the banner and the host keys of the router). The
  Core reads the host report of a router — the BusyBox form of `ip` included — and states every
  measurement it could not take.
* **The Philips Hue Bridge**: the Core has **no onboarding transport for a device with an HTTP
  API**, so the bridge is an inventory device with its measured identity (model `BSB002`, the
  software version, the bridge id, the MAC and the IP). Its lights are **refused without a
  token** (measured), and a token is a **write on the device** (the button of the bridge and
  `POST /api`). A monitoring or control capability for the bridge is a **new capability** with
  its own permission, its own audit and its own scope — it is named here and **not** simulated.
* **The secure update**: the update path of the Core is implemented and measured. The
  operator still owns the **private key** (it never reaches a host) and the **public key of
  the instance** (`instance/etc/update-public.pem`); the first signed bundle of a release
  needs that key pair. The path updates the **Core**; the **client** of the operator is
  updated by the store (Mac App Store) or by the notarised path of the direct distribution.
* **The Mac App Store**: the package of the client is **upload-ready** and measured
  (`docs/evidence/oip-mas-package/mas-package.json`), and the requirements of the store are read
  with their sources (`docs/release/mac-app-store/requirements.md`). The operator still has to:
  build the **archive** with the *Apple Distribution* certificate and the *Mac App Distribution*
  profile of the account (the local build is signed ad-hoc, and Xcode injects a development
  entitlement into an ad-hoc build that a distribution build does not carry); publish the
  **privacy policy** and the **support URL**; answer the **app privacy details** (the client
  collects nothing) and the **age rating**; and then **upload** the archive. The loop does not
  submit and does not publish.
* Decide the delivery of the web release: the measured baseline
  (`docs/evidence/oip-performance/performance.json`) shows that the first paint of the delivered
  web release is bound to the transfer over the loopback and not to the application — the shell
  is interactive as soon as the session exists and the authorized projection follows
  immediately. **The numbers are a property of the measurement path, not of
  the release** (`tests/oip_loopback_rate.py`,
  `docs/evidence/oip-loopback-rate/loopback-rate.json`): one connection of the loopback of this
machine delivers a rate of a few hundred KiB/s, the limit grows with the number of connections, and the
**same machine** delivers the same data over a Unix socket at a rate that is **orders of
magnitude** higher — the path, not the machine, is slow. The receipt of the run names the rates
it measured and the delivery of the browser before the first paint (the bundle of the release plus
  the renderer, the fonts and the assets): it needs minutes at the rate of one connection of this
  path and seconds over the few connections the browser opens in parallel. On a machine with an
  ordinary loopback the same delivery is a fraction of a second. **The operator should therefore measure the first paint on
  their own machine before deciding** — `python3 tools/oip_measure_delivery.py` reports the size of
  the delivery, the rate of the path and the rate of the machine of the operator. A smaller
  delivery, a compressed asset or a local cache of the release is a product decision of the
  operator, and the decision must not be taken on the number of a throttled path.
* The UI ownership question is settled: the Spectrum-2027 workstations are the canonical
  application of `main` and `feature/oip-managed-diagnostics` is reconciled into them. The
  recovery review command of that branch (`docs/recovery/oip-loop-20261108.md`) is no longer
  required for the integration. The **evidence of that reconciliation** is preserved in the
  canonical branch (`docs/recovery/oip-loop-20261108.md` and its machine-readable receipt
  `docs/recovery/oip-loop-20261108-evidence.json`), and the capability of the branch is proven in
  the canonical branch by the rehearsal of the diagnostic continuation
  (`docs/evidence/oip-diagnostic-continuation/diagnostic-continuation.json`). The reconciliation
  of the worktrees is proved, not asserted: `tests/oip_worktree_reconciliation.py`
  (`docs/evidence/oip-worktree-reconciliation/worktree-reconciliation.json`) names every branch
  of every worktree, the commits of the branches that `main` does not contain, and the
  capability that the canonical branch delivers in their place.

## The evidence of the release (every receipt, with what it proves)

Every receipt names the revision and the tree it was measured on, and whether the working tree was
clean. A reader can therefore tell whether a receipt is current; the receipts of the earlier eras
name their own older revision and are kept as the history of that era.

| Receipt | What it proves |
|---|---|
| `docs/evidence/oip-canonical-acceptance/acceptance.json` | the eight phases of the acceptance of the release, with the revision and the tree of the run |
| `docs/evidence/oip-canonical-acceptance/browser-gate.json` | the browser gate: the findings, the captures and the state of the visual acceptance |
| `docs/evidence/oip-canonical-acceptance/captures/*.png` | the 13 captures of the acceptance of the release (`docs/evidence/oip-canonical-acceptance/acceptance.json`): the six workstations at 1440 px and 1920 px and the state of the anonymous session |
| `docs/evidence/oip-canonical-acceptance/ui-gate.json` | the build provenance and the served bundle of the gate |
| `docs/evidence/oip-accessibility/accessibility.json` | 174 controls, 0 of them unnamed |
| `docs/evidence/oip-global-context/global-context.json` | the selector of the global infrastructure context and the six workstations |
| `docs/evidence/oip-device-administration/device-administration.json` | the administration of a device through the surface: the revision advances from 1 to 2, the note of the device is written through the surface and kept by the Core (the revision advances from 2 to 3), a write whose metadata does not carry the note drops it, the archive of an online device is refused |
| `docs/evidence/oip-device-connection/device-connection.json` | the read-only monitoring with its polling, its revision and its honest states |
| `docs/evidence/oip-device-connection/rehearsal.json` | the rehearsal of the device connection against the real Core |
| `docs/evidence/oip-diagnostic-continuation/diagnostic-continuation.json` | the continuation of the diagnostics: the disjoint pages, the opaque cursor |
| `docs/evidence/oip-diagnostic-continuation/rehearsal.json` | the rehearsal of the diagnostic continuation |
| `docs/evidence/oip-workstation-data/workstation-data.json` | the six workstations with the data of the authorized backend |
| `docs/evidence/oip-workstation-data/rehearsal.json` | the rehearsal of the workstations |
| `docs/evidence/oip-reconnect-recovery/reconnect-recovery.json` | the restart of the Core and the recovery of the client |
| `docs/evidence/oip-reconnect-recovery/rehearsal.json` | the rehearsal of the reconnect and the recovery |
| `docs/evidence/oip-performance/performance.json` | the performance baseline of the release build over three runs |
| `docs/evidence/oip-stability/stability.json` | the extended stability run: the collectors under load, the working set, the collection rate and the documented gap of the dead collector |
| `docs/evidence/oip-storage-failure/storage-failure.json` | the storage-failure path of the Core: a store that cannot be written, measured on a bounded volume |
| `docs/evidence/oip-macos-install/macos-install.json` | the local installation of the bundle: the copy is byte-identical, the installed copy starts, is refused, terminates and starts again |
| `docs/evidence/oip-loopback-rate/loopback-rate.json` | the rate of the path of the measurement: the loopback of this machine, the rate of the machine itself and what the first paint of the baseline means |
| `docs/evidence/oip-worktree-reconciliation/worktree-reconciliation.json` | the reconciliation of the worktrees: every branch, the commits that the canonical branch does not contain, the capability that it delivers in their place and the receipt that proves it |
| `docs/evidence/oip-scope-persistence/scope-persistence.json` | the scope of the operator across a refresh of the authorized projection: the scope before and after the refresh, and the scope of a new session |
| `docs/evidence/oip-scope-persistence/scope-persistence-rehearsal.json` | the rehearsal that produced it: the instance it owns and the device of the scope |
| `docs/evidence/oip-connection-states/connection-states.json` | the honest connection states of the surface against the real Core: the state of the Core and the word of the surface in the same moment, in the states the rehearsal drives against the real Core |
| `docs/evidence/oip-connection-states/connection-states-rehearsal.json` | the rehearsal that produced it: the instance it owns, the host of the fixture and the actions of the control |
| `docs/evidence/oip-settings-status/settings-status.json` | the status of the settings categories in the surface against the real Core: every category of the Core is offered and shows the status the Core answered |
| `docs/evidence/oip-settings-status/settings-status-rehearsal.json` | the rehearsal that produced it: the instance it owns, its steps and its result |
| `docs/evidence/oip-observation-history/observation-history.json` | the persisted observation history of the owned loopback SSH fixture: it grows with the polling, every stored sample is stale, the order is ascending by the receive time, the cursor walks it forward without loss, the scope is enforced and it survives the restart |
| `docs/evidence/oip-measurement-coverage/measurement-coverage.json` | the coverage of the kinds of the measurement of the owned loopback SSH fixture: every supported kind is delivered, every kind that is not available is named and never delivered as a number, the surface names them |
| `docs/evidence/oip-measurement-coverage/measurement-coverage-browser.json` | the browser receipt of the coverage: the findings of the journey against the real Core and the state of the tile of the verified identity |
| `docs/evidence/oip-measurement-coverage/painted-surface.txt` | the painted surface of that journey: what the operator actually sees, including the line that names the kinds of the measurement that are not available |
| `docs/evidence/oip-device-connection/painted-surface.txt` | the painted surface of the connection of a device: the state, the endpoint, the confirmed host key and the read-only monitoring |
| `docs/evidence/oip-settings-status/painted-surface.txt` | the painted surface of the settings: the navigation with the state of the Core for the selected category |
| `docs/evidence/oip-scope-persistence/painted-surface.txt` | the painted surface of the scope: the devices of the scope with the administration that changed the Core |
| `docs/evidence/oip-connection-states/painted-surface.txt` | the painted surface of the connection: the state of the Core and the reason of the block |
| `docs/evidence/oip003/`, `docs/evidence/oip004/`, `docs/evidence/oip004-ui/`, `docs/evidence/oip005/`, `docs/evidence/oip006/`, `docs/evidence/oip0061/`, `docs/evidence/oip007/`, `docs/evidence/oip008/`, `docs/evidence/oip0082/`, `docs/evidence/oip0084/`, `docs/evidence/oip0085/`, `docs/evidence/git-baseline/` | the receipts of the **earlier eras**: the history of the measurement and not the evidence of this release — the gate receipts of the eras 003 to 0085, the first real-device gate and the baseline of the initial commit |
| `docs/evidence/oip-record-numbers/record-numbers.json` | the numbers of the record are the numbers of the receipts: every measurement that a row of the record quotes is looked up in the receipt that the row names |
| `docs/evidence/oip-record-integrity/record-integrity.json` | the integrity of the record itself: every cited receipt and every cited path exists and is tracked, every receipt of the release is cited |
| `docs/evidence/oip-release-verification/release-verification.json` | the verification of the release with one command: the manifest, the freshness of the receipts, the integrity of the record, the acceptance and the safety boundaries |
| `docs/evidence/oip-session-lifetime/session-lifetime.json` | the promised lifetimes: the one-time code and the session |
| `docs/evidence/oip-reproducible-build/reproducible-build.json` | the reproducibility of the web release and of the macOS bundle of the release |
| `docs/evidence/oip-macos-app/macos-app.json` | the macOS bundle of the release: it starts, it is refused, it terminates, it starts again |
| `docs/evidence/oip-native-session/native-session.json` | the session of the native client against the real Core |
| `docs/evidence/oip-transport-parity/transport-parity.json` | the parity of REST, SSE and MCP and the scope of the projection |
| `docs/evidence/oip-security-review/security-review.json` | the security release review: 12 findings, 9 resolved, 2 mitigated, 1 escalated |
| `docs/evidence/oip-rust-regression/rust-regression.json` | the Rust regression of the workspace: 191 tests in 30 suites |
| `docs/evidence/oip-hue-device/hue-device.json` | the **Philips Hue Bridge of the operator** as a real device: the identity verified against the **pin** of the certificate of the bridge (the bridge does not present the root of its chain), the public configuration read in **one** verified TLS session, the onboarding into the inventory of the Core through the **authorized session**, the read-back of the verified facts, the refusal of a bridge with another certificate (at the pin **and** in the TLS session) and the refusal of a principal of another organization (`docs/evidence/oip-hue-device/bridge-certificate.pem` is the verified certificate) |
| `docs/evidence/oip-store-screenshots/store-screenshots.json` | the **store assets** of the Mac App Store listing: the six workstations of the client captured in 1440 x 900 — a size that Apple accepts for a Mac app — by the release build of the client through the managed Core; every capture is measured out of the file itself (the exact pixel size, the absence of an alpha channel), the captures carry none of the prohibited regressions of the UI contract, and the acceptance of the operator of the visible result stays **pending** (`docs/evidence/oip-store-screenshots/captures/`) |
| `docs/evidence/oip-pi-instance/pi-instance.json` | the disposable instance of the Core on the Raspberry Pi: the cross build for the target of the host, the bundle, the **start by hand**, the Core answering through a tunnel of the loopback, the session of the operator minted on the host, the authorized projection (the address space of the simulation of the host and the organization of the instance), **no published port** and the **services of the operator unchanged** before and after |
| `docs/evidence/oip-update/update.json` | the secure update of the Core of an instance: a signed bundle is verified (the Ed25519 signature over the exact bytes of the manifest), the digests are verified before the activation and again after the write, the switch is atomic, the new version is health checked as a disposable instance, a version that does not become ready is rolled back, and the durable journal of the instance names every attempt — the changed artefact, the forged manifest, the foreign target and the repeated revision are refused |
| `docs/evidence/oip-mas-package/mas-package.json` | the package of the macOS client for the Mac App Store: the release build, the entitlements of the bundle (the app sandbox and the network client, without the debug entitlement of the entitlements file), the hardened runtime in the signature, the privacy manifest in the bundle, the absence of the quarantine attribute on every file, the category and the transport security of the Info.plist, the icon and the signature of every executable |
| `docs/evidence/oip-service-registry/service-registry.json` | the **service registry** that the operator declared in the plan: the Core delivers it with the provenance `declared` (the Core measures no service), the scope of the read is the scope of the hierarchy, a foreign identifier is refused **identically** to an unknown one, the MCP tool answers the same registry as the route, and a plan that declares a service for a site that does not exist is refused |
| `docs/evidence/oip-mas-export/mas-export.json` | the **export recipe** of the Mac App Store listing: the template carries every key that the export needs and every identity of the operator as a placeholder, the tool **refuses** while that identity is incomplete and names the missing values, the rendered file carries every key and **no placeholder** any more and lies **outside** the checkout, the printed command names the archive and the options file, and the checkout stays **untouched** — the rehearsal never exports, never signs and never uploads |
| `docs/evidence/oip-deployment-hosts/deployment-hosts.json` | the **deployment hosts** of the operator, measured read-only over SSH: the identity, the architecture, the memory, the disk, the toolchain, the services of the operator (unchanged before and after) and the listeners of `bodi-pi` and `bodi-pc` — the receipt is fresh at every revision, the devices of the operator live on the network of the operator and their discovery is the receipt of the measurement that could reach them |
| `docs/evidence/oip-deployment-discovery/deployment-discovery.json` | the deployed hosts and the two device classes of the operator, measured read-only: the identity, the architecture, the memory, the disk, the toolchain, the services of the operator (unchanged before and after) and the listeners of `bodi-pi` and `bodi-pc`; the SSH banner and the host keys of the OpenWrt router; the public configuration of the Hue Bridge and the refusal of its lights without a token |
| `docs/evidence/oip-pi-bundle/pi-bundle.json` | the bundle of a disposable instance for a foreign host: the whole procedure measured with stubs — the files of the instance are absolute and inside the instance, the procedure writes nothing outside it, the code of the operator session is minted over the local IPC, the instance stops without a forced signal, and the bundle installs no service and names no path of the machine it was built on |
| `docs/evidence/oip-operations/operations.json` | the local operations: the backup, the refused restore, the clean shutdown, the three refusals of the personal installation |
| `docs/evidence/oip-documented-plan/documented-plan.json` | the documented plan of an instance and the session route of the Core |
| `docs/evidence/oip-activation-dry-run/activation-dry-run.json` | the activation of schema 7 on a **copy** of the store of the operator |
| `docs/evidence/oip-upgrade-rollback/upgrade-rollback.json` | the handover of a live instance to the release and the rollback |
| `docs/evidence/oip-historical-daemon/historical-daemon.json` | the daemon of the era and the actor shape that it refuses |
| `docs/evidence/oip-extend-registry/extend-registry.json` | the extension of the registry of an instance and the refused plan that drops a source |
| `docs/evidence/oip-settings-offline/settings-offline.json` | the offline change of a setting and its refusal on a conflict |
| `docs/evidence/oip-offline-archive/offline-archive.json` | the offline archive of a device and the refused archive of an online device |
| `docs/evidence/oip-network-2027/network-2027.json` | the **Network workspace** of the managed surface in the browser: the absence of the logical paths is named, the devices of the Core are the devices of the surface, the comparison of two devices names its own limit, the channel that goes stale is named as stale |
| `docs/evidence/oip-network-2027/network-2027-rehearsal.json` | the rehearsal that produced it: the disposable instance it owns, the devices it registers through the authorized route and the steps of the journey |
| `docs/evidence/oip-network-2027/captures/` | the captures of the journey of the Network workspace: the summary, the explorer, the search, the filters, the comparison, the graph and the stale channel |
| `docs/evidence/oip-devices-geometry/devices-geometry.json` | the **geometry of the Devices workspace**: the four states of the workspace at 1440 px and 1920 px — the numbers that the acceptance of the visible result looks at |
| `docs/evidence/oip-devices-geometry/devices-geometry-rehearsal.json` | the rehearsal that produced it: the disposable instance it owns, the devices it registers through the authorized route and the steps of the journey |
| `docs/evidence/oip-devices-geometry/captures/` | the captures of the journey of the geometry: the four states of the workspace at 1440 px and 1920 px |
| `docs/evidence/oip-devices-geometry/geometry-1440x900.json` | the geometry of the four states of the workspace at 1440 px: the filter bar, the controls, the search field, the pitch of the rows and the edges of the content |
| `docs/evidence/oip-devices-geometry/geometry-1920x1080.json` | the geometry of the four states of the workspace at 1920 px |
| `docs/evidence/oip-diagnostics-2027/diagnostics-2027-rehearsal.json` | the **evidence workspace** of the Diagnostics workstation: the loss of a source and its recovery, measured on the Core, and the events of the Core that the surface shows |
| `docs/evidence/oip-diagnostics-2027/diagnostics-live.json` | the receipt of the journey with the live collectors: every row of the explorer and every marker of the timeline is an event of the Core |
| `docs/evidence/oip-diagnostics-2027/diagnostics-failed.json` | the receipt of the journey after the loss of the source: the events of the Core, the markers of the timeline and the attributes that the Core does not deliver |
| `docs/evidence/oip-diagnostics-2027/captures/` | the captures of the journey of the evidence workspace: the explorer, the timeline and the inspector |
| `docs/evidence/oip-devices-density/devices-density.json` | the **density of the Devices workspace** in the browser: a disposable Core with the plan of the operator, the devices registered through the authorized route, six widths and three themes, no horizontal overflow and no clipped control of the toolbar |
| `docs/evidence/oip-devices-density/responsive-report.json` | the receipt of the browser journey of the density: the checks of every width and every theme, the page errors and the overflow errors of the journey |
| `docs/evidence/oip-settings-depth/settings-depth.json` | the **depth of the Settings workspace** of the managed surface against a real Core: every category of the Core, the settings keys of the Core, the facts of the server report, a tool of the catalog with its permissions and its scopes, the schema of the Core copied byte-equal, the template of the client configuration without a credential, and the limits that the surface names |
| `docs/evidence/oip-settings-depth/settings-depth-rehearsal.json` | the rehearsal that produced it: the disposable instance it owns, the platform permissions it grants to its reader and the steps of the journey |
| `docs/evidence/oip-settings-depth/captures/` | the captures of the journey of the Settings workspace: the application settings, the appearance, the MCP runtime, the tool explorer, the copied schema, the client configuration, the limits, the storage, the security and the system |
| `docs/evidence/oip-overview-performance/overview-performance.json` | the **performance of the Overview** of the managed surface against a real Core: twenty-three interactions inside a budget of 3000 ms, the frames of the browser, the long tasks of the main thread, the heap the surface retains, the frames the compositor presents and the numbers of the Core that the surface shows |
| `docs/evidence/oip-overview-performance/overview-performance-rehearsal.json` | the rehearsal that produced it: the disposable instance with its four live collectors, the collection events that the Core recorded, the budgets and the steps of the journey |
| `docs/evidence/oip-overview-performance/captures/` | the captures of the performance journey: the Overview, the activity workspace, the event filter, the changed context and the surface at the end of the run |
| `docs/evidence/oip-opcua-browser/opcua-browser.json` | the **address space of the operator** in the browser: a disposable Core with live collectors, the real surface, the nodes, their folders and their identity are the ones that the Core delivers, the absent attributes and the limits of the address space are named |
| `docs/evidence/oip-opcua-browser/address-space.json` | the receipt of the browser journey of the address space: the checks, the nodes of the Core, the folders of the Core, the rows of the surface, the identity of the node and the node that the keyboard search reaches |
| `docs/evidence/oip-opcua-parity/opcua-parity.json` | the pagination and the scope of the OPC-UA address space |
| `docs/evidence/oip-real-device/test-summary.json` | the acceptance of the milestone era (history) |
| `docs/evidence/oip-real-device/review.json` | the source review of the milestone era (history) |
