# OIP-008.4 — MCP management read models

Existing rmcp3.8.0, protocol2026-07-28 and tested legacy2025-11-25 remain unchanged. Daemon owns the persistent shared runtime; stdio bridges own only transport. No HTTP MCP transport, new collector, writer, crate or dependency upgrade.

`oip_mcp_management_read` accepts ManagementQuery {section}, deny_unknown_fields. All sections require centrally authorized Platform McpManagementRead. A bounded report contains section/availability, facts, tools, optional client_configuration and limitations. This is computed runtime information, not persisted configuration.

| Section | Actual information |
|---|---|
| server | composed runtime mode (local_ipc / stdio_owned / unavailable), lifecycle, protocol/SDK, configured session maximum and fixed request/input/output limits |
| tools / permissions |18 registered read tools from the actual shared mapping, descriptions, core capability IDs, required permissions, input/output schemas, policy availability separately from transport-runtime availability |
| sessions | **unsupported**: no reliable queryable initialized-client lifecycle registry; no credential/process guesses, online counts or client names |
| client_configuration | valid generic mcpServers JSON; current executable when available; exact bridge option names; private socket/credential path placeholders |
| diagnostics | current local runtime observation and documented limits; no credential/path/remote probe or implied successful handshake |
| system | actual package/build revision, monotonic runtime uptime, OS/arch, schema, source count, REST versions and registered capability count; Platform only |
| storage | actual schema; database path not exported, integrity check explicitly not run, retention cleanup unsupported |
| security | current bound principal, local identity mode, audit limitations and open advisories |
| diagnostic_rules | actual shared documented-gap rule ID/version constants, immutable rule policy and honest health/gap coverage |

Schemas are generated from core Rust types. Immutable capability mapping is cached; runtime lock is held only for a small state clone. Counts are derived from the registry, not copied from old reports. **27 declared capabilities:25 reads, legacy SimulationScenarioSet, offline-only SettingsChange.**18 MCP tools are registered; an old principal without new grants still discovers its original16, an explicitly scoped SettingsRead principal17, and an explicitly platform-authorized settings/management operator18. Mutations remain absent from all tool discovery/execution. Existing health/snapshot/source resources unchanged.

ClientConfigurationPreview is intentionally unusable until an operator replaces placeholders using an **existing authorized profile**. No credential is provisioned or tested. The executable may be absent outside a real server process; the template then says so. Exact options remain --mcp-bridge --ipc-socket ABS --ipc-credential ABS. JSON copying performs no command, creates no grants and exposes no credential bytes/private profile path. Socket/credential placeholders must not be treated as an installed setup. No arbitrary path parameter or credential oracle exists. The security section does not enumerate roles or administer users; role inventory/editor and credential UI remain unsupported.

MCP enable/disable, per-tool switches, session disconnect, credential lifecycle, service installation and remote integration remain unsupported management mutations. Protected startup configuration/explicit offline provisioning remain authoritative. There is no UI-only security control.
