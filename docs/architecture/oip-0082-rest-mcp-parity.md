# OIP-008.2 — REST/MCP Capability Parity

24 typed capabilities:17 prior +7 historical read capabilities;23 reads, one existing local-demo mutation remains blocked over MCP. Principal-mode MCP catalog has16 tools; legacy read policy has13. Existing routes/tools remain compatible; no mutation or listener added. The official rmcp3.8.0 stack/protocol negotiation is unchanged.

Every row uses ApplicationServices::execute -> central hierarchy resolution -> diagnostic_read -> read-only storage adapter / pure rule. Transport-specific envelopes differ only: REST returns DTO, MCP returns CapabilityOutput {type,value}. Both use generated Rust schemas and structured capability errors. Existing SourcePlacement ancestry is authoritative.

| Capability | Rust | Storage | REST GET /api/v2/ | MCP | Scope | Permission | Tests |
|---|---|---|---|---|---|---|---|
| Event History / `event_history_read` | IMPLEMENTED | persisted evidence | `events/history` | `oip_event_history_read` | authorized Organization/Infrastructure/Site/Source; exact Device registry filter | events_read + telemetry_read | diagnostics.rs, history.rs, real four-source E2E |
| Event Detail / `event_detail_read` | IMPLEMENTED | persisted evidence | `events/detail` | `oip_event_detail_read` | authorized Organization/Infrastructure/Site/Source; exact Device registry filter | events_read + telemetry_read | diagnostics.rs, history.rs, real four-source E2E |
| Source Health History / `source_health_history_read` | IMPLEMENTED | persisted evidence | `diagnostics/health-history` | `oip_source_health_history_read` | authorized Organization/Infrastructure/Site/Source; exact Device registry filter | events_read + sources_read | diagnostics.rs, history.rs, real four-source E2E |
| Data Gap Query / `data_gaps_read` | IMPLEMENTED | persisted evidence | `diagnostics/gaps` | `oip_data_gaps_read` | authorized Organization/Infrastructure/Site/Source; exact Device registry filter | events_read | diagnostics.rs, history.rs, real four-source E2E |
| Evidence Query / `evidence_read` | IMPLEMENTED | persisted evidence | `diagnostics/evidence` | `oip_evidence_read` | authorized Organization/Infrastructure/Site/Source; exact Device registry filter | events_read + telemetry_read + sources_read | diagnostics.rs, history.rs, real four-source E2E |
| Deterministic Findings / `diagnostic_findings_read` | IMPLEMENTED | derived from stored gaps | `diagnostics/findings` | `oip_diagnostic_findings_read` | authorized Organization/Infrastructure/Site/Source; exact Device registry filter | events_read | diagnostics.rs, history.rs, real four-source E2E |
| Observation History / `observation_history_read` | IMPLEMENTED | persisted evidence | `observations/history` | `oip_observation_history_read` | authorized Organization/Infrastructure/Site/Source; exact Device registry filter | telemetry_read | diagnostics.rs, history.rs, real four-source E2E |

No historical severity/correlation-ID query, free-form diagnosis rule execution, alarm-history engine, root-cause confirmation, persisted diagnostic-run history or full event replay is claimed. Those are NOT_SUPPORTED here. One factual finding rule is implemented; a generic rule engine is NOT_IMPLEMENTED.

## Authority and errors

Principal comes only from existing local IPC credential/peer binding or REST Bearer binding. Tool/query Actor/Principal/Scope/Grants are rejected. Permissions must match the same target scope; grants from unrelated sources never combine. Source/parent/device selectors are checked before SQL and before cursor lookup. Event IDs are looked up only within the authorized source set. Foreign and missing details/evidence anchors yield identical404 RESOURCE_NOT_ACCESSIBLE. Missing identity/capability grants403 PERMISSION_DENIED. Invalid fields/time/cursor/filter/limits400 INVALID_DIAGNOSTIC_QUERY; oversized stored evidence400 HISTORY_BYTE_LIMIT; admission/deadline503 HISTORY_BUSY/HISTORY_TIMEOUT; storage error500 HISTORY_UNAVAILABLE. MCP maps the same category/code into structured tool errors; syntactic SDK errors may use InvalidParams. No foreign names or global counts.

Audit uses the existing port, principal/actor/capability/correlation/time/outcome plus validated selected hierarchy or resolved detail/evidence source. Invalid foreign IDs/payloads are not logged as targets. Audit remains local, non-durable/non-tamperproof; cancellation before completion can have unconfirmed target context.

## SSE

Existing v2 stream remains an authenticated scoped full snapshot, no replay. EventRecord gains optional id computed from the original persisted control-event identity, including recovered cache records. History uses that same event key. Observation events are not added to the live control cache. Full resync and authorization remain unchanged. SSE snapshot IDs are transport snapshot hashes, not historical event IDs/cursors; Last-Event-ID cannot authorize history. Live event freshness follows current runtime; historical measurements are explicitly stale projections.

## Production boundaries

Local simulation only. Same-UID hostile programs are not isolated; no productive remote/browser identity, immutable durable execution audit or enterprise tenant certification. RUSTSEC-2023-0071 remains a production blocker; existing2023-0089/2024-0449 exceptions remain open. No Cloud/OT-write/control/provisioning API or new remote listener.
