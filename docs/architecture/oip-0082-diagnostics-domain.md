# OIP-008.2 — Diagnostics & Evidence Domain

OIP IS AGENT-FIRST BY DESIGN. Feature baseline `79639ff42c68ee2ede34862929822a4789845268`. No Flutter changes, no MCP mutation, no new runtime or crate.

## Audit and capability gaps

| Existing capability/data | Baseline reality | OIP-008.2 change |
|---|---|---|
| Observations | Envelopes persisted with stable SHA-256 keys; current checkpoint/cache API only | Bounded historical receive-time query |
| Collection events | Observation, ConnectionLost, Reconnected, SubscriptionError, DataLoss persisted; recent control cache100/source | Historical event query/detail uses original keys; DataLoss distinguished from SQL subscription_error by gap relation |
| Gaps | Stored start/end/reason; not an inferred network cause | Typed gap pages and evidence references |
| Source health | Current five dimensions and runtime counters; prior transitions not persisted | Schema4 stores actual dimension changes, first previous state unknown |
| Reconnect/recovery | Recorded connection/reconnect/gap events and run journal | Query existing events, never manufacture missing transitions |
| Alarms | Device classification and explicit demo incidents; no dedicated persisted alarm-event model | No invented alarm/severity/correlation filter |
| Diagnostics crate | Empty future-rule placeholder | One deterministic factual gap rule, version1 |
| Diagnosis history | No persisted evaluations or root-cause engine | Findings derived from persisted gaps on read; no claim of stored diagnosis runs |
| Audit | Existing capability execution port and offline provisioning journal | Same audit port; validated hierarchy/anchor context; no payload/credential logs |
| SSE | Authorized current snapshots, no history/replay | Additive persisted control-event id shared with historical detail |

## Contracts and responsibilities

Core `diagnostics.rs` defines DiagnosticQuery, CollectionEventKind, DiagnosticEvent, HistoricalObservation, CollectionGap, SourceHealthState/Transition, EvidenceReference, DiagnosticFinding, DiagnosticItem, DiagnosticPage and EvidenceSet. Existing ClientEvent, ObservationEnvelope, OriginClass and five source-health dimensions are reused. No competing event or health state machine.

Application `diagnostic_services.rs` validates input, resolves existing hierarchy authorization, binds cursors, applies admission/deadlines, invokes the storage adapter and the pure deterministic evaluator. REST/MCP only map typed requests/outputs. Storage knows no transport/principal policy; it receives the authorized SourceId set. Domain has no SQLite/Axum/rmcp dependency. Existing oip-diagnostics now depends only on oip-core.

The hierarchy remains immutable SourcePlacement ancestry. Device selection resolves the actual registry DeviceId to its source; no string-prefix policy. Historical records inherit that source context. Sources with equal entity/metric names remain distinct. No hierarchy migration or new tenant fallback.

## Health evidence

One existing writer records changes of reachability, connection, service, freshness and validity after controlled runtime publications/ticks. Counters are not a second state machine; reconnect attempts do not fabricate a Reconnecting state. Each process begins with previous=null. Historical transitions before schema4 or across crashed/uncommitted publications are unavailable, not inferred from old event text. Global run FK remains internal; response IDs use an opaque random per-writer epoch, source and local sequence. No global run counter in tenant DTOs.

A failed health write marks persistence unhealthy, logs an explicit failure and retries the latest dimensions on next publication. Intermediate transitions during failure may be unavailable. Shutdown takes one cutoff; pending health evidence makes shutdown unclean. No fallible health write occurs after the run-journal completion. This is not an atomic event+health commit guarantee or durable spool.

## Findings

`oip.documented-collection-gap`, version1, states only that a gap was documented. Evidence is the original gap key/source; evaluated window is its stored markers. Missing independent network/service measurements and uncertain exact interruption boundaries are explicit. Status is historical_record_not_current_health. It neither confirms root cause nor invents contradictory measurements. Findings are deterministic read projections, not persisted diagnostic executions, alarm incidents, an extensible rule engine or LLM output.

## Dependencies

Eight existing workspace crates remain. No SDK/dependency version upgrade. Existing rusqlite enables its hooks feature for interrupt/deadline enforcement. Server adds the existing diagnostics crate dependency; diagnostics adds core. Cargo.lock changes only workspace dependency edges. Security advisory policy is unchanged.
