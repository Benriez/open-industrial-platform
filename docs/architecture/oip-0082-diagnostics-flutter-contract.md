# OIP-008.2 — Diagnostics Flutter Contract v2.1

The Diagnostics & Events2027 UI worktree/handoff is not modified or integrated. These are actual implemented core contracts for a later OIP-009 integration, not a browser authentication bypass. See [parity matrix](oip-0082-rest-mcp-parity.md) for exact GET endpoints and permissions; [query contract](oip-0082-evidence-query.md) and [time semantics](oip-0082-time-semantics.md).

## Requests and DTOs

GET /api/v2/events/history?source=SOURCE&start_ms=...&end_ms=...&limit=50
GET /api/v2/events/detail?event_id=KEY
GET /api/v2/diagnostics/health-history
GET /api/v2/diagnostics/gaps
GET /api/v2/diagnostics/evidence?event_id=KEY&start_ms=...&end_ms=...&limit=40
GET /api/v2/diagnostics/findings
GET /api/v2/observations/history?source=SOURCE&metric=METRIC&start_ms=...&end_ms=...

All accept supported DiagnosticQuery selectors: organization/infrastructure/site/source/device, inclusive calendar range, limit1..100, opaque cursor. Detail/evidence required fields and unsupported filters differ as documented. Evidence max7days and limit>=4. No token in URL. GET unknown fields fail; no silently ignored invented severity/correlation filter.

DiagnosticPage {items:[DiagnosticItem], truncated:bool, next_cursor:string|null, missing_evidence:[string], time_semantics:string}. DiagnosticItem {category:event|observation|gap|health|finding,record:...}. No total count. More data is indicated by truncated and normal-page cursor. Evidence components can be truncated without cursors; use individual historical capabilities to continue.

Event: {id,source,origin,at_ms,kind,event,observation_id|null,gap_id|null}. kind is snake_case; embedded ClientEvent keeps its established Rust Serde variant envelope (ConnectionLost/Reconnected/etc). Values and provenance of embedded Observation are preserved, freshness is stale. Device/hierarchy context resolves through authoritative source registration; never derive source from DeviceId prefixes.

Observation: {id,observation:ObservationEnvelope}. Optional value/server/receive/status/error stay null. Source/entity/metric/quality/units/SourceTimestamp/ServerTimestamp/ReceivedTimestamp/SimulationOrigin retain the current envelope. Receive-time filter excludes unknown receive times; no SourceTimestamp fallback.

Gap: {id,source,origin,documented_start_ms,documented_end_ms,reason}. Both markers are currently stored; do not render their difference as a measured outage or0ms as continuity. Gap filtering is by start marker, not interval overlap. Reasons are collector context, not a verified root cause. Past end marker does not imply current health.

Health: {id,source,at_ms,previous:null|SourceHealthState,current:SourceHealthState,provenance}. State has reachability/connection/service/freshness/validity. No extra Reconnecting/Ready enum or global run_id. First previous unknown, historical coverage before schema4 and crashed publications unavailable. Historical health never overrides fresh live runtime state.

EvidenceSet {anchor:Event|null,events:DiagnosticPage,observations:DiagnosticPage,gaps:DiagnosticPage,health:DiagnosticPage,relation,missing_evidence}. All evidence is same authorized anchor/explicit source and requested window; relation is contextual/temporal, never root cause. No cross-source automatic expansion. Contradictory evidence is not fabricated when absent.

Finding: {id,rule_id,rule_version,statement,evidence:[{category,id,source}],missing_evidence,evaluated_start_ms,evaluated_end_ms,status}. Currently only factual documented-gap rulev1; historical projection, not a saved diagnosis execution. Display rule/evidence/unknowns, not confirmed root cause or active incident. Persisted diagnosis history, severity-ranked incident management and general rule execution remain OPEN.

## Authentication, scopes, caches and errors

Same existing server-bound principal; valid local Bearer in Authorization header for REST. No Webasset/URL/LocalStorage credential storage. A secure browser-session/SSE authentication design remains OIP-009; the implemented and verified part of that boundary is documented in [oip-009-browser-session-sse.md](oip-009-browser-session-sse.md). An anonymous Flutter request in multi mode is denied; no legacy All-Access fallback.

Cache key includes principal/auth generation + selected organization/infrastructure/site/source/device + capability + entire query. Scope/principal changes cancel in-flight requests, discard cursors and all old evidence/selection/trend caches. Cursor remains query-bound and expires after300s/restart; retain stable IDs to deduplicate after a fresh query. Older than the two recent continuation tokens can become invalid even within TTL. Retry near-page responses without inventing exactly-once behavior. Treat HISTORY_BUSY as bounded backoff, not offline;400 cursor invalid means restart query;403/404 cannot expose foreign names.

Use EventRecord.id to link live control events to history/detail. SSE only delivers current scoped snapshots; never build complete history from received samples. Reconnect does authorized REST resync. Do not put bearer in EventSource URL or bypass scope to keep legacy UI working. Existing v1 demo UI is separately regression-tested; the observations history of a device is connected in the operator device view as named below, the event history and the remaining diagnostic surfaces stay unconnected.

## The device scoped observation history in the operator view

The Flutter device view requests `GET /api/v2/observations/history?device=DEVICE_ID&limit=20`. The device scope is deliberate: the device is resolved to its source through the authoritative source registration, so no organization, infrastructure or site selection is invented and no global context is required. This surface needs only `telemetry_read`; the event history needs `events_read` and is not part of it.

Every sample is rendered as history. The stored record is stale by definition, the receive time the Core guarantees for it is reported, and the `missing_evidence` and `time_semantics` of the answer are shown instead of being hidden. The Core serves the history from the oldest stored entry; the cursor walks forward to the newer entries, stays bound to the query and the principal, and expires after 300 s. The stable id of a sample deduplicates a refresh, a refresh never drops a loaded sample, and `truncated` together with `next_cursor` is surfaced. There is no total.

The browser session cookie authorizes this route. `crates/oip-server/tests/browser_session.rs` proves that boundary with a cookie: the bound device is served with its persisted sample, a foreign scope and an unknown device are refused with `RESOURCE_NOT_ACCESSIBLE`, a principal without `telemetry_read` is refused with `PERMISSION_DENIED` and a request without a session is refused. `tests/real_device/acceptance.py` proves that the samples of a connected device reach the Core database and that the operator view renders them; `apps/flutter/test/observation_history_test.dart` proves the rendering, the continuation and the recovery from a device that is not accessible yet. The route answers `HISTORY_UNAVAILABLE` when the database is not file backed.

Unknown/Missing is not numerical zero, not Offline, and not evidence against an incident. Historical samples are stale; simulated origin remains labeled. Times from different clocks cannot prove event causality. All new field schemas derive from core Rust contracts and MCP discovery; machine-readable capability mapping is exported by the existing mcp_catalog example.
