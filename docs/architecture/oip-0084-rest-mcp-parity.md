# OIP-008.4 — Capability and transport matrix

Both new HTTP adapters and MCP tools invoke the same ApplicationServices implementation and typed core requests. They contain no SQL, source probing, separate scope engine or extra runtime.

| Operation | Core | REST v2 | MCP | Permission / target | Persisted / computed | Apply / status | Tests |
|---|---|---|---|---|---|---|---|
| Catalog/categories/detail/effective | SettingsRead(SettingsQuery) | GET /api/v2/settings | oip_settings_read | SettingsRead at explicit target | definitions computed; values startup snapshot of SQLite | reads active snapshot | settings.rs REST/direct/officialSDK parity;0084 E2E |
| MCP status/tool schemas/permissions/template/diagnostics | McpManagementRead(ManagementQuery) | GET /api/v2/management | oip_mcp_management_read | McpManagementRead **Platform only** | computed | read-only | schema validation/negative grants/E2E |
| System/storage/security/rule status | same sectioned capability | same route | same tool | same Platform gate | computed | read-only/unsupported facts explicit | all sections schema + E2E |
| Connected sessions | same section=sessions | same | same | same | unavailable | unsupported; no inventory claimed | explicit unsupported assertions |
| Safe config change | SettingsChange offline typed contract | **none** | **none** | SettingsWrite at target + local OS operator, exclusive ownership | SQLite CAS + audit | RequiresRestart; no runtime active-value claim | storage rollback/CAS/migration;CLI E2E |
| Infrastructure/Sites/Sources | existing hierarchy/source capabilities | existing v2 routes | existing tools | unchanged hierarchy permissions | existing registry/runtime | read-only; no source reconfiguration | existing008/0082 E2E |
| Historical diagnostics | existing seven capabilities | existing v2 routes | existing seven tools | unchanged combined read grants | existing bounded SQLite history | read-only; omitted limit uses configured default | all retained tests/history E2E |

SettingsQuery {scope: platform|organization|infrastructure|site|source (default platform), scope_id?:string, key?:instance_name|instance_description|history_page_size, catalog?:bool(default false)}. Non-platform scope requires scope_id; Platform forbids it. All unknown fields fail. key restricts both definition/value response; unsupported key at scope fails. catalog=true returns definitions/categories with empty settings, subject to exactly the same target authorization. No pagination is needed for the fixed three-key/seven-category catalog; no hidden global database scan.

ManagementQuery {section: server(default)|tools|permissions|sessions|client_configuration|diagnostics|system|storage|security|diagnostic_rules}. One bounded platform report, at most18 tools. Limits remain16KiB MCP input,4MiB output,16 requests/session and configured IPC session cap (1–32). Existing bounded framing, cancellation and deadlines retained. Mapping cache has constant size.

Errors use existing core categories: malformed key/type/scope/unknown field → InvalidInput; no grant/foreign scope → PermissionDenied without record/name; unavailable persistence/audit → existing structured errors. The local CLI exits nonzero on ownership denial, malformed typed changes, SettingsWrite failure, schema failure or SETTINGS_REVISION_CONFLICT. No API tokens in URL and no new browser write route. Dynamic uptime/observation timestamps can differ across calls; stable settings/catalogs compare byte-for-byte after transport envelope removal.
