# OIP-008.4 — Typed application settings

**OIP IS AGENT-FIRST BY DESIGN.** Baseline `0e20f7283a8815242aaa71a2066a9944cb8cafc8`; isolated branch `feature/oip-0084-application-settings`. Eight workspace crates and existing protocol/dependency versions retained. No Flutter change.

## Audit and decision

Previously CoreConfig was startup-file configuration; hierarchy/policies were exclusively provisioned offline. No persistent application-settings table or queryable initialized MCP-client registry existed. IPC JoinSet admission/log counters are not a client inventory. The existing shared CapabilityService, HierarchyRegistry, SQLite ownership and MCP tool/schema generation are reused.

The safe initial change channel is **exclusive local offline administration**. There is no REST/MCP write endpoint, self-grant, runtime listener toggle or source reconfiguration. This deliberately avoids claiming a live apply when only persistence happened. CoreRuntime loads a validated immutable settings snapshot before starting the existing writer/workers. One runtime and one writer remain.

## Supported keys

| Key | Type / default | Scopes | Validation | Apply |
|---|---|---|---|---|
| instance_name | Text / Open Industrial Platform | Platform | 1–80 UTF-8 bytes, nonblank, no control characters | next CoreRuntime start |
| instance_description | Text / empty | Platform | 0–256 UTF-8 bytes, no control characters | next CoreRuntime start |
| history_page_size | Integer / 50 | Platform, Organization, Infrastructure, Site, Source | 4–100 inclusive | next CoreRuntime start; actual omitted-limit historical queries |

Values are explicitly non-sensitive. Never place credentials in metadata. SettingValue is a tagged Rust enum, not arbitrary JSON. Unknown keys/types/fields are rejected. Defaults, definitions, categories, apply modes/statuses, scopes and effective revisions are typed core contracts (`oip-core/src/settings.rs`). Definitions also carry permission, sensitivity, persistence, change channel and validation text.

Only history_page_size inherits: Source > Site > Infrastructure > Organization > Platform > built-in default. An explicit request limit wins (the established request range remains 1–100; Evidence requires at least4). The deepest **explicit history query filter** selects the configuration context. A query without organization/infrastructure/site/source filters uses the Platform default; no principal-dependent implicit context is guessed, including device-only queries. Explicit mixed-parent validation and authorization still run normally. The setting does not authorize a query or expand its sources. At an unauthorized scope SettingsRead fails; a consumer need not gain SettingsRead merely to use the non-sensitive query default.

Instance metadata has no descendant override/inheritance. EffectiveSetting separates requested_scope, persisted exact-scope record, effective value, origin scope and effective_revision (0 means built-in default). Inherited records do not expose ancestor actors. Exact-scope actors are null unless the caller has platform management authority. Tenant snapshots also redact the global startup timestamp. Active reads say active_startup_snapshot. An offline change result says persisted_requires_restart and effective_runtime_value=null; no running runtime exists in that operation. Expected revision0 creates, otherwise exact CAS on the same scope/key is required.

## Categories and availability

Seven typed navigation categories: General, MCP & Agents, Infrastructure, Data & Storage, Diagnostics, Security & Access, System. Category capability references are navigation metadata, **not grants**. The UI must evaluate discovery and per-target authorization. Editable General/Diagnostics keys require offline administration; other sections are computed read models. Existing hierarchy/source read capabilities serve Infrastructure. No fake reconnect/source-endpoint switches, host metrics or settings for unsupported controls are added.

Theme, density, inventory sorting, language and visual time display remain client preferences, not server settings. Application mode, live transport enable/disable, retention deletion, source timeouts/reconnect tuning, dynamic authorization and destructive actions are not editable keys. Unsupported controls must be visibly unavailable.
