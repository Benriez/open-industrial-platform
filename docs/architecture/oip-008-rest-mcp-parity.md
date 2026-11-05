# OIP-008 — REST/SSE/MCP-Parität

Alle fachlichen Reads gehen durch denselben CapabilityService. Transportadapter etablieren die Identität und validieren die Syntax; sie vergeben keine fachlichen Grants. Es gibt weiterhin eine gemeinsame CoreRuntime und einen Writer.

## Capability-Matrix

| Capability | Rust Core | REST | MCP | Scope | Permission | Test |
|---|---|---|---|---|---|---|
| OrganizationsRead | IMPLEMENTED | GET /api/v2/organizations | oip_organizations_read | sichtbare eigene/Ancestor-Organizations | hierarchy_read | hierarchy.rs + realer E2E |
| InfrastructuresRead | IMPLEMENTED | GET /api/v2/infrastructures | oip_infrastructures_read | autorisierte Infrastructures/Ancestor-Labels | hierarchy_read | hierarchy.rs + E2E |
| SitesRead | IMPLEMENTED | GET /api/v2/sites | oip_sites_read | autorisierte Sites/Ancestor-Labels | hierarchy_read | hierarchy.rs + E2E |
| SourcesRead | IMPLEMENTED | GET /api/v2/sources; v1 kompatibel | oip_sources_read; Source-Resources | autorisierte Sources | sources_read | SDK/REST-Parität + E2E |
| DevicesRead / DeviceRead | IMPLEMENTED | GET /api/v2/devices[/{id}]; v1 kompatibel | oip_devices_read / oip_device_read | autoritative registrierte Source | devices_read; Detail zusätzlich telemetry_read | direkte/SDK-Parität, Scope-Tests |
| ObservationsRead | IMPLEMENTED | GET /api/v2/observations; v1 metrics/current | oip_observations_read | autorisierte Sources | telemetry_read | SDK/REST-Parität + E2E |
| EventsRead | IMPLEMENTED | GET /api/v2/events; v1 kompatibel | oip_events_read | autorisierte Sources | events_read | SDK/REST/E2E, Gaps |
| OpcuaNodesRead | IMPLEMENTED | GET /api/v2/opcua/nodes; v1 kompatibel | oip_opcua_nodes_read | exakt registrierte autorisierte Source | opcua_read + telemetry_read | Source-Auswahl, Pagination, reale Simulatoren |
| ScopedSnapshotRead | IMPLEMENTED | GET /api/v2/snapshot; /api/v2/stream | oip://v2/snapshot/current | nur gemeinsam autorisierte Sources | sources/devices/telemetry/events_read | Negativtests + E2E-SSE |
| CoreHealth/Liveness/Readiness/Queue/SystemStatus/Snapshot | IMPLEMENTED, bestehende6 | bestehende v1/health-Routen | bestehende6 globale Resources | ausschließlich Platform | jeweilige bisherigen Permissions | bisherige MCP-Parität + Tenant-Denials |
| SimulationScenarioSet | Legacy-Demo IMPLEMENTED | nur explizites lokales --demo | BLOCKED | keine Tenant-/MCP-Mutation | simulation_control | bestehende Mutation-Denials |
| produktive Diagnostics / historische Queries | NOT_IMPLEMENTED | keine neue produktive Route | kein erfundenes Tool | später fachlich definieren | nicht freigegeben | Legacy-Fixtures bleiben gekennzeichnet |
| Hierarchie-/Policy-Management | typisierter Offline-Bootstrap IMPLEMENTED | BLOCKED | BLOCKED | exklusiver lokaler Operator | OS-/DB-Ownership | atomare Provisioning-/Revocation-Tests |

17 Capability-IDs: 13 bestehende und vier neue Reads; damit16 Reads und eine gesperrte MCP-Mutation. Neun Tools im Principal-Modus. Discovery ist autorisiert, daher sind nicht alle Resources jeder Session sichtbar. Legacy-Policies behalten die sechs bisherigen Tools; die vier neuen Reads setzen einen gebundenen Principal voraus. Maschinenlesbare Schemas/Mapping: `oip_server::mcp::capability_mapping()` bzw. der vorhandene ausführbare Mapping-Exporter `target/debug/examples/mcp_catalog`.

## Verträge

HierarchyQuery: optionale `organization`, `infrastructure`, `site`, `offset`, `limit`; alle Parent-Filter müssen konsistent sein. Antwort `Page<T>{items,offset,limit,has_more}`, ohne globalen Count. SourceQuery ergänzt dieselben Filter; Source-/Observation-/Event-Listen verwenden bounded offset/limit (Standard100, maximal100). NodeQuery verlangt bei mehr als einer erlaubten Source eine explizite Source; maximal100 Nodes/Seite. DeviceRequest verwendet die tatsächliche Registry-ID; keine untrusted Präfixableitung.

v1-DTOs bleiben überwiegend kompatibel; Node ergänzt SourceId additiv. Neue globale Read-Beschränkungen sind absichtlich fail-closed. Bestehende Flutter-Clients funktionieren nur im explizit autorisierten Single-Infrastructure-Modus. Ein alter Client erhält niemals automatisch installationsweiten Tenant-Zugriff.

## SSE und Cursor

`/api/v2/stream` authentisiert vor HTTP200 und ruft wiederholt ScopedSnapshotRead auf. Jede Sekunde ein vollständiger autorisierter Snapshot; kein globaler Watch-Revisionskanal. Die Event-ID ist SHA-256 des autorisierten Payloads. Fremde Source-Änderungen dürfen weder globale Revisionszähler noch Cache-Verdrängung in die Antwort übertragen. `Last-Event-ID` ist kein Autorisierungswert; Reconnect liefert erneut den kompletten eigenen Snapshot. Kein Replay, keine Exactly-once-Garantie. Keepalive/Transport-Cadence sind kein Hinweis auf andere Organizations.

Globale v1-SSE-Snapshots erfordern Platform-Scope oder explizite Legacy-Autorität. Read-Timeouts, begrenzte MCP-Konkurrenz, Output-Limits und Session-Cancellation bleiben erhalten. Langsame MCP-Ausgabe blockiert nicht den Writer; bestehende echte SDK-/IPC-Tests prüfen das weiterhin. Überschrittene SDK-Zeilenlängen werden begrenzt verworfen; ein gültiger Folgerequest bleibt möglich. Syntaktische Toolfehler innerhalb des Rahmens werden strukturiert gemeldet.

## Paritätsnachweis

Die neuen Rust-Tests vergleichen direkte Capability-Ergebnisse mit dem echten offiziellen SDK, einschließlich generierter Input-/Output-Schemas. Der Mehrorganisations-E2E vergleicht denselben laufenden Core über MCP und authentifiziertes REST, prüft gefilterte SSE-Snapshots/Reconnects, fremde IDs, manipulierte Grants und Source-Ausfall. Bestehende sechs Tools behalten direkte/REST/SDK-Parität in der Legacy-Regression. Aktuelle Resultate: [Verifikation](../oip-008-verification.md).
