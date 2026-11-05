> OIP-008 Feature-Stand: 17 Capabilities, neun MCP-Tools im Principal-Modus; aktuelles [Scope-/Paritätsinventar](oip-008-rest-mcp-parity.md). Die folgenden Angaben dokumentieren den früheren Meilenstein.

# OIP Capability → MCP Mapping — OIP-006

Stand 2026-11-05. Die 13 bestehenden Core-Capabilities bleiben vollständig erhalten. **12 lesende Capabilities MCP-IMPLEMENTED**, sechs Tools und sechs globale Resource-Operationen; SourcesRead besitzt zusätzlich quellbezogene Resources. Eine vorhandene Mutation ist bewusst gesperrt. Historischer fachlicher Katalog: [OIP-005-Inventar](oip-capability-inventory.md).

Maschinenlesbar und aus derselben Rust-Allowlist generiert: [capability-mapping.json](../evidence/oip006/capability-mapping.json). Erzeugung: `cargo run --locked -p oip-server --example mcp_catalog`. Der Katalog enthält alle IDs, Permissions, Status, Namen/URIs sowie generierte Ein-/Ausgabeschemas. Er ist ein Operator-Artefakt, kein zusätzliches MCP-Tool. `IMPLEMENTED` gilt ausschließlich für lokale freigegebene Reads. Kein produktives MCP-READY für Mutationen.

| Core-ID / Status | MCP-Zugang / Status | Eingabe → bestehende Ausgabe | REST / Flutter |
|---|---|---|---|
| core_health_read / IMPLEMENTED | Resource `oip://v1/core/health` / IMPLEMENTED | Unit → CoreHealth | GET core/health; im UI-Snapshot enthalten |
| core_liveness_read / IMPLEMENTED | Resource `oip://v1/core/liveness` / IMPLEMENTED | Unit → CoreHealth | GET /health/live; keine direkte GUI-Nutzung |
| core_readiness_read / IMPLEMENTED | Resource `oip://v1/core/readiness` / IMPLEMENTED | Unit → CoreHealth | GET /health/ready; keine direkte GUI-Nutzung |
| queue_read / IMPLEMENTED | Resource `oip://v1/core/queue` / IMPLEMENTED | Unit → QueueHealth | SSE.queue; kein eigener REST-Endpoint, keine eigene UI-Ansicht |
| system_status_read / IMPLEMENTED | Resource `oip://v1/system/status` / IMPLEMENTED | Unit → SystemStatus | GET system/status; Topbar/Resync |
| snapshot_read / IMPLEMENTED | Resource `oip://v1/snapshot/current` / IMPLEMENTED | Unit → Snapshot | SSE-Vollsnapshot; alle fünf Ansichten |
| sources_read / IMPLEMENTED | Tool `oip_sources_read`, Resource `oip://v1/sources/{id}/health` / IMPLEMENTED | SourceQuery → Vec<SourceHealth> | GET sources; Geräte-/Source-Zustände |
| devices_read / IMPLEMENTED | Tool `oip_devices_read` / IMPLEMENTED | DeviceQuery → Vec<Device> | GET devices; Inventar/Overview/Topologie |
| device_read / IMPLEMENTED | Tool `oip_device_read` / IMPLEMENTED | DeviceRequest → DeviceDetail | GET devices/{id}; bestehender Detaildialog |
| observations_read / IMPLEMENTED | Tool `oip_observations_read` / IMPLEMENTED | SourceQuery → Vec<ObservationEnvelope> | GET metrics/current; Messwerte/Trend |
| events_read / IMPLEMENTED | Tool `oip_events_read` / IMPLEMENTED | SourceQuery → EventsResponse | GET events; Diagnostics |
| opcua_nodes_read / IMPLEMENTED | Tool `oip_opcua_nodes_read` / IMPLEMENTED | NodeQuery → NodePage | GET opcua/nodes; vorhandener Primärquellen-Browser |
| simulation_scenario_set / IMPLEMENTED | **BLOCKED**, kein MCP-Name | ScenarioRequest → ScenarioResponse nur über bisherigen lokalen Demo-Service | bisheriges POST demo/scenario und GUI-Demoprofil erhalten; nicht im MCP-Modus freigegeben |

REST-Pfade ohne Präfix beziehen sich auf `/api/v1/`. Alle MCP-Ausgaben behalten den Core-Dispatch-Umschlag `{type,value}`. REST liefert die vorhandenen v1-Bodies; Queue/Snapshot werden für Parität aus SSE gelesen. Liveness/Readiness verwenden denselben Health-DTO; REST übersetzt das boolesche Ergebnis zusätzlich in 200/503. Das MCP-Resultat erfindet keinen separaten Health-Status.

Inputs: Devices `{q?,location?,source?}`, Device `{id}`, SourceQuery `{source?}`, Nodes `{q?,folder?,source?,offset?,limit?}`. Source ist die tatsächlich registrierte DataSourceId, keine URL. Keine Grants-, Actor-, Rollen-, Tenant- oder Zeitstempelparameter. Unbekannte Felder werden abgelehnt. Grenzen und Null-Semantik: [Architektur](oip-006-mcp.md). Device-IDs werden nicht zur Erteilung von Source-Rechten geparst: autoritative Registrierung ist maßgeblich.

Permissions stammen unverändert aus `CapabilityId::descriptor()`: CoreRead für globale Core-/Queue-/System-Reads; SourcesRead, DevicesRead, TelemetryRead, EventsRead jeweils für ihren Bereich; DeviceRead zusätzlich TelemetryRead; Nodes OpcuaRead + TelemetryRead; Snapshot alle enthaltenen Leseberechtigungen. Default-Deny bei fehlenden Grants. SourceScope::Only erfordert bei Listen eine explizite erlaubte Quelle; globale Resources sind verweigert. DeviceRead verwendet den tatsächlichen Registry-Scope. Discovery ersetzt keine erneute Ausführungsautorisierung.

Fachfehler bleiben CapabilityError: ResourceNotFound, SourceUnavailable, InvalidInput, PermissionDenied, OperationNotSupported, PersistenceUnavailable, AuditUnavailable. DataStale ist vorbereitet, aktuelle Reads liefern Stale/Unknown/Invalid ausdrücklich als Daten. Missing ist keine Nullmessung. Events sind maximal 100 aktuelle persistierte Kontrollrecords, `replay_supported=false`; keine vollständige Historie. Diagnose-Fixtures bleiben markiert; ohne Demo-Profil keine erfundenen Incidents. OPC-UA-Reads sind gegenüber Geräten lesend, ihr vorhandener Service persistiert gelesene Samples über die kanonische Ingestion.

Paritätstests in `crates/oip-server/tests/mcp.rs`: alle sechs Tools über direkten CapabilityService, REST und echtes rmcp-Protokoll; globale Resources einschließlich Queue/Snapshot gegen direkte Services und REST/SSE; typisierte Source-/Permission-Denials und Resource-Scope-Grenzen. Nur das zur Aufrufzeit neu erzeugte `generated_at_ms` wird im eingefrorenen Vergleich normalisiert. Identitäten, Quality, Freshness, Provenienz und Messzeitstempel werden nicht entfernt. Der Live-Prozess-E2E ergänzt reale Quellen, Pagination, Fehlerisolation und stale Restore.

Noch nicht implementiert und deshalb nicht discoverbar: historische Telemetriequeries, produktive Diagnostik, Runtime-Konfigurationsverwaltung, Registrierung, Userverwaltung, Core-Administration, Datei-/Shellzugriff und OT-Schreiben. Keine dieser Planungen ist eine zusätzliche Core-Dispatch-Operation. Resource-Subscriptions sind NOT_SUPPORTED in diesem Adapter; später allenfalls auf vorhandenen Runtime-Notifications mit erneuter Autorisierung, ohne neue Ingestion und ohne Replay-Garantie.
