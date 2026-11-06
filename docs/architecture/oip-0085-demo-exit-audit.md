# OIP-008.5 — Demo exit and data provenance

**OIP IS AGENT-FIRST BY DESIGN.** Stacked on settings commit `f9969f0a21f2885a8b6c4695b3c105ad28708d33`; canonical main remains `0e20f7283a8815242aaa71a2066a9944cb8cafc8`. No UI handoff, running operator preview or operator database was modified.

| Data class / actual path | Prior behavior | Normal mode now | Protection / decision |
|---|---|---|---|
| CoreConfig defaults (`oip-server/config.rs`) | default simulation source, oip-demo.sqlite, webassets | sources=[], oip.sqlite, no default webassets | never infer a simulation from an empty setup |
| CoreRuntime / Application initialization | required at least one source; primary mandatory | empty source set and primary=null supported | core readiness is not device reachability |
| Demo bootstrap (`provisioning::legacy_plan`, `main --demo`) | fixed legacy IDs for explicit legacy mode | not executed in normal empty start | retained for explicitly selected isolated compatibility tests; explicit DB/config required |
| Simulator (`oip-simulator`, simulated server CLI) | synthetic samples and fault scenarios | not started | only explicit independent simulation tests; no normal fallback |
| Demo devices/incidents/topology (`demo.rs`, state snapshot) | enabled by scenario controller | only when explicit demo controller exists | fixtures retained, no real inventory adoption |
| Source-derived devices / source placements | device identity existed only through a source | migration preserves IDs with explicit stored source-origin classification | Other/unknown physical type; old creation time/registrar unknown, never migration time |
| Manual inventory | absent | persistent operator registration, independent of sources | manual_operator provenance, actual registration time/actor, no collector invented |
| Observations / events / gaps / health history | source-scoped persisted evidence | unchanged | no rewrite, deletion, rekeying or synthetic replacement |
| REST/SSE/MCP | shared source read models | shared inventory reads plus scoped compatibility projections | no anonymous tenant fallback; bootstrap status only when no hierarchy exists |
| Flutter controller/API | REST initial state + SSE/resync; explicit demo controls | sources unchanged by this workstream | no mock API introduced; real authenticated browser/onboarding UI remains a later integration |
| Test fixtures/harnesses | explicit simulated data | retained in isolated test DBs/processes | version/count assertions advance; no tests removed |
| Existing operator DBs/previews | several explicit demo/isolated UI processes observed | left running and unopened | contents not classified by guessed names; unknown/real data preserved |

Device names, IPs and display labels are **not provenance evidence**. A manually registered `AMD EVO-X2` is tested as manual data, not classified as demo. Simulation origin is retained only from existing registered source identities; it never becomes proof of physical device identity or generic host reachability.

`--inventory-cleanup-plan` is a privileged **read-only assessment**, not a deletion command. It requires explicit Platform InventoryManage and private local DB ownership, reads only supported schema without migration, reports source references/counts/FKs and preserves every row. Missing/older DBs do not get silently created/migrated. No deletion/apply/reset endpoint exists. Backup is explicitly NOT performed by that read; a future destructive cleanup would require an independently verified offline backup, reference-aware plan, explicit approval and restore procedure. Unknown data cannot be removed by this implementation. Disposable test DB creation is separate from operator data cleanup.

Normal first-run states: `No infrastructure configured`; after authorized provisioning `No devices registered`; after registration without collectors `Devices registered · Telemetry unavailable`. Search-empty status is `No matching devices`; other statuses describe the requested active registration scope. Archived rows remain stored and can be requested explicitly. No dummy data is inserted to fill these states.
