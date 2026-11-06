# OIP-008.4 — Future Flutter Settings contract v2.2

No Flutter source, dependency, widget, asset, native configuration or UI handoff is changed. A safe authenticated browser session/SSE design remains OIP-009; the existing local bearer/IPC trust model must not be bypassed. No bearer in URLs, web assets or LocalStorage.

## Navigation

General → Application (three supported keys where authorized), Preferences (client-only, server preference synchronization unsupported).
MCP & Agents → Server / Client Configuration / Connected Clients / Tools & Capabilities / Permissions / Connection Diagnostics.
Infrastructure → Organizations / Sites / Sources (existing scoped read contracts; management remains offline).
Data & Storage → Database / Historical Data / Retention (retention deletion unsupported).
Diagnostics → Available Rules / Evidence / Health History (existing historical capabilities + rule metadata).
Security & Access → Current Identity / Roles & Permissions / Audit (read-only boundaries, no production user management).
System → Runtime / Versions / Health.

Category definitions are navigation/classification metadata, not a grant. Use authorized capability discovery and each target read. States must distinguish Available, Read-only, Offline Administration Required, Requires Restart, Permission Denied and Unsupported. Do not render an enabled fake Save/Apply button or MCP toggle for unsupported operations.

## Actual DTOs

GET /api/v2/settings?scope=organization&scope_id=ORG&catalog=true reads scoped definitions/categories. key selects a single supported definition. Without catalog=true, settings contains EffectiveSetting records. Definition contains typed key/category/data_type/default, description, supported scopes, inherited flag, validation, permissions, sensitivity, persistence, change_channel and requires_restart apply mode.

EffectiveSetting {key,requested_scope,persisted:SettingRecord|null,effective:SettingValue,origin:AccessScope|null,effective_revision,apply_status:active_startup_snapshot}. SettingValue is {type:text,value:string} or {type:integer,value:number}. A missing persisted record means default/inherited value, not zero. SettingRecord {scope,key,value,revision,updated_ms,actor:PrincipalId|null}. Null actor means redacted. loaded_at_ms is nullable and not a tenant-visible global startup clock. origin=null and effective_revision=0 identify the built-in default. Definition default is separate from effective value. Revision is per scope/key, not a global tenant count. Offline expected_revision uses the exact-scope persisted record revision, or0 if absent; never use the inherited effective_revision as a CAS target.

GET /api/v2/management?section=... returns the sectioned ManagementReport described in [management](oip-0084-mcp-management.md). Tools distinguish registered, available_to_principal, runtime_available and availability. Schema JSON strings can be parsed for an inspector; they do not grant execution. Sessions section is unsupported, never show credential profiles as Connected. Rule constants describe actual deterministic code, no rule editor.

Client configuration has configuration_json, executable|null, args, usable_without_replacement=false and credential_provisioned=false. Copy JSON preserves required placeholders and displays an explicit unresolved-template notice. No successful connection indicator is implied. No UI may read arbitrary local credential files. The future desktop trusted-operator path must be separately designed; current browser API cannot save.

## Save/apply and errors

Currently **no HTTP/MCP settings writes**. Document the local offline administration route instead. The typed offline SettingsChange includes expected_revision and yields persisted_requires_restart plus effective_runtime_value=null. Conflicting revision requires reread and deliberate operator retry; never auto-overwrite. A subsequent runtime start validates/loads the persisted record and returns active_startup_snapshot. Changing while the core owns the database is rejected, including while clients are attached. There is no delayed-live apply, pending request queue or remote restart endpoint.

UI cache keys must include authenticated principal/session generation, complete organization/infrastructure/site/source scope, key/section and revision. On principal/scope change cancel in-flight requests, clear prior settings, previews, tool decisions and history cursors. No cross-scope reuse or retained credential paths. Read after process restart; do not assume a successful offline persistence is already active. History default selection follows the deepest explicit request context; send the selected source/hierarchy context rather than guessing a principal's unique infrastructure. Explicit request limit overrides the default.

Use structured403/400 errors without interpreting them as Offline; do not reveal foreign resource names. Unknown/Missing stays distinct from unsupported/redacted/stale. No Settings SSE event exists: refresh bounded reads deliberately; do not invent subscriptions or poll aggressively. Existing SSE remains scoped current snapshots with authorized REST resync, not full replay. Retention cleanup, credential management, service install, live source tuning, remote MCP, remote session disconnect, productive tenant administration, a role inventory/editor and browser admin identity remain OPEN. The current permission view is a tool matrix, not user administration.
