# OIP-008.5 — Real inventory Flutter contract v2.3

Flutter sources and all existing UI handoffs are unchanged. The current canonical Flutter build is not a secured real-infrastructure onboarding UI. No screenshots or functioning browser-write workflow is claimed. Browser identity/session/SSE integration remains OIP-009. No bearer in URLs, webassets or LocalStorage and no anonymous tenant bypass.

## First run and context

A normal empty core exposes only GET /api/v2/installation/status → an empty InventoryPage with `No infrastructure configured`. It returns no private IDs/names/counts and stops being public after hierarchy provisioning. Authenticated clients then use InventoryRead to distinguish `No devices registered` and `Devices registered · Telemetry unavailable` in their own selected scope. Search-empty is not absence of the whole installation. Do not create fake devices to fill views.

Organization/Infrastructure/Site selection uses the existing authorized hierarchy APIs. Device placement is directly Site-based; Source is optional. Cache keys include principal/auth generation, all selected parents/source, full query, archived filter and registration revision. On scope/principal change cancel reads and discard old devices, details, metadata, plan previews and history cursors. Read after restart to refresh the immutable runtime inventory snapshot; offline persistence does not hot-apply to an existing runtime.

## Devices & Services

GET /api/v2/inventory/devices provides registry/list/search/id detail, metadata, actual associations and monitoring availability through one typed core capability. Results are bounded ID-sorted pages with offset/limit/has_more, no global total. Respect revision and nullable provenance fields. Registration is not hardware verification. Existing source records have explicit stored-source origin, Other type and unknown historical creation time/registrar. Manual fields are operator assertions.

Connectivity is currently Unknown for inventory devices; collector endpoint reachability is a separate SourceHealth read, never a generic host probe. NoCollector is not Offline. IP presence is not reachability. Health NotEvaluated is not healthy/NoFinding. No samples means unavailable, not numerical zero. monitoring_simulated is false with no collector, true/false only with actual runtime source provenance, and null when offline provenance is unavailable. Null must never become false. Do not derive source identity from name/IP/DeviceId prefixes.

Add/Edit/Archive/Import are currently **local offline administration**, not HTTP/MCP writes. A future UI must explicitly display Offline Administration Required. POST /api/v2/inventory/plan and oip_inventory_plan_read validate only, require InventoryManage and always report applied=false. A preview creates no IDs/reservations/credentials, no grants and no source. Update sends complete metadata under CAS; a UI editing only selected fields must preserve all other fields or request explicit reset. Site/ownership moves and permanent delete are unsupported. Archive preserves history and does not stop an associated collector. Source binding is the existing offline provisioning path, currently0..1 association/device; no invented placeholder OPC source.

## Other views

Overview: counts from authorized returned inventory, sources from actual source registry; no fake host CPU/RAM/network metrics. Network & VPN: registered nodes only, no automatically guessed links/topology or green reachability. Diagnostics: actual scoped historical/live collection evidence only; no demo incidents in normal mode, no inferred cause from a gap. Settings → Infrastructure links the inventory/hierarchy/source capabilities and actual management information; there is no global active-infrastructure setting or source-reconfiguration toggle.

Existing v1/SSE projections include authorized manual devices with empty telemetry and unknown status. SystemStatus.primary_source_id is nullable when no source exists; prior source-bearing responses retain the same string value. The old UI must handle this in its future integration, not invent a fallback primary. Default normal core does not automatically serve old webassets. Explicit isolated demo UI regression remains supported separately.

Errors: invalid schema/type/filter/page → structured InvalidInput; missing/foreign IDs → generic inaccessible; no grant → denied. Never show foreign names through errors or counters. Plan/apply revision conflict requires reread and deliberate retry, never blind overwrite. No inventory SSE change feed/replay is added: existing SSE scoped snapshots and authenticated REST resync remain. Read-only MCP/REST share the same ApplicationServices; UI filtering is never authorization.

Future adapters (SNMP, SSH read-only host metrics, local host agent, OS/network/VPN telemetry, MQTT/Modbus) remain unimplemented. A future collector contract must bind type+target DeviceId+authorized source placement+credential reference+read-only operations+poll/subscription mode+freshness/provenance+last successful observation+failure/resource bounds. Credentials do not belong in DeviceMetadata. The current OPC-UA runtime configuration is still a local simulation profile; no real OT deployment is authorized by this inventory milestone.
