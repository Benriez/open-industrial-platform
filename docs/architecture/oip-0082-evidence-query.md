# OIP-008.2 — Historical and Evidence Queries

## Query contract

DiagnosticQuery is a deny_unknown_fields object with optional organization, infrastructure, site, source, device, event_id, event_type, metric, start_ms, end_ms, limit and cursor. Calendar filters accept Unix milliseconds1601..9999; start/end inclusive and start<=end. Default limit50, range1..100. event_id/cursor require64 lowercase hex characters. Source/metric length128; DeviceId uses the existing validated type. No severity/correlation filter exists because there is no authoritative stored field. Unknown fields, irrelevant filters and unsupported combinations fail explicitly.

Event detail requires event_id; no cursor. Evidence requires start/end, <=7days, an event_id or explicit source, limit4..100; event_type/metric/cursor are unsupported. Other histories reject irrelevant event filters; metric only applies to observation history. Events sort ascending(at_ms,event_key); observations(received_ts_ms,observation_key); gaps(started_at_ms,gap_key); health(at_ms,id). Event detail still honors supplied filters. Unfiltered queries preserve even recorded invalid/sentinel timestamps; no read-time event re-identification.

## Cursor and snapshot semantics

A first query starts a read-only deferred SQLite transaction and captures internal insertion highwater rowids of all four evidence tables in that snapshot. Later pages use those watermarks and keyset positions on new short transactions. Subsequent/new/backfilled inserts are excluded, including older event timestamps. Existing immutable payloads/keys remain stable; duplicate counters are not returned. Retention/deletion is not implemented. These are bounded query snapshots, not event replay or exactly-once delivery.

Cursors are cryptographically random opaque32byte tokens represented as64hex. Server-side state binds principal/actor, capability, effective authorized sources, legacy grants/source scope, all filters/time bounds/limit, fixed sort, watermarks and position. No credentials/IDs/counts appear inside the token. Authorization runs again before lookup. TTL300seconds from first page, invalid after process restart. Max64 active chains/principal,1024 retained tokens globally, two recent continuations/chain to allow near-page retries; older continuations can expire before TTL. Arbitrarily long traversal does not accumulate one permanent entry/page. Foreign/tampered/expired/too-old tokens yield the same INVALID_DIAGNOSTIC_QUERY. Start a fresh query and deduplicate by stable keys after expiry; no implicit scope migration.

## Bounds and query plans

Four admitted blocking historical reads globally; excess returns HISTORY_BUSY immediately. No unbounded request queue. Permit remains owned by a detached blocking read until it ends. Transport cancellation flips an atomic flag on drop; SQLite progress handler checks cancellation/deadline every1000VM instructions. Busy wait100ms, SQL budget2s, application deadline3s. MCP also retains existing session/input/output/timeout limits. No writer transaction or protocol request in the read path.

Each authorized source uses an indexed keyset SELECT LIMIT(limit+1), at most32 source fanouts; merge is bounded, never a full history load. Payload/reason length is checked via SQLite octet_length(column) before fetching it, <=64KiB/row and512KiB cumulative/read. Over-limit returns HISTORY_BYTE_LIMIT without silently dropping rows. Evidence has four bounded component reads, not unbounded joins. Internal MAX(rowid) is a table-tail lookup and is never serialized or used as a tenant count. Per-source event/time, event/kind/time, observation/receive, gap/start and health/time indexes support these reads. Query plans and synthetic100000-event measurements accompany verification; no enterprise scaling or SLA claim.

## Evidence correlation

Anchor event must be in the authorized query result. Related events/observations/gaps/health are restricted to exactly that source, or the explicit source when no anchor was requested. Same read snapshot and requested time window. At most floor(limit/4) records/component plus optional anchor; truncated flags are independent. Component next_cursor is absent: continue with the corresponding historical capability and same selectors. There is no complete correlation graph, inferred causal relation or cross-source expansion by correlation IDs.

Missing observations/gaps, missing historical health coverage and clock/causal uncertainty are explicit. Evidence references point to existing stable keys plus category/source; they grant no access. Supporting association is not an independent cause measurement. Empty evidence is Unknown, not zero or proof of uninterrupted service.

## Gaps

Gap query filters the documented start marker, not interval overlap. Both endpoints are stored non-null by the original model. Their difference is a documented marker interval, not measured outage duration. Zero-length DataLoss markers mean an unknown sample-loss interval, not continuity. Stored end does not prove a currently healthy connection; no open/current interruption is inferred. Reason is recorded collector context, not a verified root cause. Event.gap_id links to the original gap; related event queries preserve those links.

## Schema4

Append-only migration4 adds source_health_history(id PK,source FK core_sources,run FK core_runs,at_ms,payload_json) and the query indexes. Existing migration texts/checksums1..3 are unchanged. One atomic migration transaction; failure rolls back all new DDL/ledger changes. Old rows, keys, hierarchy, checkpoints and counts are preserved. Existing schema2 attested adoption remains explicit and first finishes schema3; normal subsequent opening upgrades3->4. No tenant assignment/default changes. Only the existing owner opens/migrates the writer; bridges never own databases.
