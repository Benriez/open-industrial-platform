# ADR 0003 — Persistent hierarchy and central read authorization

OIP-008, implementation decision. One runtime/writer, append-only versioned SQLite schema. Global immutable SourceId; typed Organization/Infrastructure/Site/Device/Principal/Role IDs. One device maps to one Source+Entity in this phase. No prefix grants or implicit cross-source device aliases; Node identity includes Source+OPC-UA ID.

Source placement is immutable so observations, gaps, events, health and node catalogs inherit hierarchy through their authoritative SourceId. No redundant tenant column in every observation. Parent changes require a future explicit audited data migration. Offline provisioning validates a complete bounded plan and is idempotent, additive for data hierarchy and supports offline read-policy revocation, transactionally protected by the same database ownership as runtime. Legacy adoption requires explicit operator evidence/attestation and unchanged sample/event identities; unassigned existing data cannot silently become a tenant.

Principal/role/scope are separate. Resolve binding scope before unioning permissions. Default deny, central CapabilityService, no identity/grants from request payloads. IPC credential binds a stored PrincipalId. Loopback REST credentials use the same principal; unauthenticated multi-infrastructure reads denied. Legacy GUI is permitted only in an explicitly selected single-infrastructure development mode.

Global platform health/queue/system/snapshot require platform scope. A separate authorized scoped snapshot excludes global counts, revision/run IDs and unscoped diagnostics. Tenant SSE is a full authorized resync, with content-derived opaque cursors, no replay. Control event sequence/cache must be source-local and bounded per source so other organizations cannot create sequence/count or cache-eviction side channels.

Local OS owner remains trusted; no production multi-tenant certification. Mutating network/MCP administration remains unavailable. Management plan is typed and run only by offline operator with exclusive DB ownership. Diagnostics product execution remains unimplemented. No new protocol or UI.
