# OIP-008 — Multi-Infrastructure Core

OIP IS AGENT-FIRST BY DESIGN. Lokaler Entwicklungsmeilenstein auf `a27e7b1e01dc1cb6f4d97c34319b0aa6d7321871`, Feature-Branch `feature/oip-008-multi-infrastructure`. Kein Merge nach main, kein Push. Entscheidung: [ADR 0003](../decisions/0003-multi-infrastructure.md).

## Bestandsaufnahme und Entscheidung

OIP-007 hatte eine Runtime, einen Writer, unabhängige Source-Worker, Sidecar-Ownership und authentisierte lokale IPC-Sessions. Diese Komponenten werden weiterverwendet. SourceId war bereits global und Bestandteil von Observation-/Event-Identitäten. Device-Anzeigen verwendeten `M-01` bzw. Source-Präfixe; das war keine belastbare Autorisierungszuordnung. SourceScope kannte keine Organizations. Globale Snapshots enthielten Run-ID, Revision, Queue und Counts. Event-Sequenzen und Event-Cache waren installationsweit. REST verwendete eine ausdrücklich lokale Operator-Policy statt benutzerbezogener Authentisierung.

Die frühere OIP-008-Proposal wird konkretisiert: **keine neue Runtime**, keine neue Crate, keine Tenant-Spalte in jeder Observation, kein globaler Snapshot für eingeschränkte Principals. SourceScope bleibt ausschließlich Legacy-Kompatibilität. Neue hierarchische Berechtigungen verwenden `AccessScope` und die persistierte Registrierung.

## Domain und IDs

`oip-core/src/hierarchy.rs`: Organization → Infrastructure → Site → SourcePlacement. OrganizationId, InfrastructureId, SiteId, PrincipalId, RoleId sind ASCII-validierte Newtypes mit 1–128 Zeichen, DeviceId mit 1–256 Zeichen (erhält zulässige Legacy-Gerätealiase). SourceId verwendet den vorhandenen DataSourceId-Typ, Konfiguration/Registry validieren dessen kanonischen Zeichensatz und 128-Zeichen-Grenze. Die generierten Schemas enthalten die Grenzen. Keine Präfix-Autorisierung.

Eine Source hat genau eine Site. Eine Infrastructure genau eine Organization. Eine Site genau eine Infrastructure. In dieser Phase hat jede Source genau **ein** registriertes Device mit einem EntityId; das entspricht den vorhandenen Simulator-/Collector-Verträgen. DeviceId ist global eindeutig; gleiche OPC-UA Entity-/Node-IDs mehrerer Sources bleiben durch SourceId verschieden. `Node` enthält zusätzlich `data_source_id`. Eine spätere Mehrquellen-Korrelation physischer Geräte braucht eine eigene explizite fachliche Zuordnung; es werden keine Alias-Heuristiken eingeführt.

Historische Observations, Events, Gaps, Checkpoints, Source-Health und Node-Kataloge erben ihre Hierarchie über die unveränderliche SourcePlacement-Beziehung. Geräte-/Parent-Verschiebungen sind gesperrt; zukünftige Verschiebungen brauchen eine eigene Datenmigration. Neue Organizations/Infrastructures/Sites/Sources können offline additiv provisioniert werden. Leere Infrastructures/Sites sind erlaubt. Grenzen: 64 Organizations, 128 Infrastructures, 256 Sites, 32 Sources, 64 Principals/Roles, 512 Bindings.

## Application und Betrieb

`HierarchyRegistry` validiert Parents und Policies und entscheidet zentral über Capabilities. `ApplicationServices` löst authentisierte Principals auf und projiziert Read-Modelle; REST/MCP führen keine eigenen fachlichen Berechtigungsregeln aus. Ingestion, Recovery und Offline-Adoption nutzen denselben `validate_observation` des Application-Core. SQL-Key und SourceDefinition-Payload müssen dieselbe Identität besitzen.

`CoreRuntime` und Writer bleiben einmalig. `DatabaseOwnership` wird für Runtime und Offline-Provisioning wiederverwendet; neue DB-/Sidecar-Dateien sind privat. Ein zweiter Daemon oder ein Provisioning gegen eine laufende DB scheitert an derselben kanonischen Ownership. MCP-Bridges besitzen weiterhin nur ihren Transport. Keine neuen Protokolle, kein Remote-MCP, keine Flutter-Änderung.

## Typisierte Management-Grenze

`ProvisioningPlan` → validierte HierarchyRegistry → `SqliteStore::provision_file` → `ProvisioningResult`. Fehler sind typisierte StorageError-/CapabilityError-Kategorien; ungültige Parents, widersprüchliche Legacy-Daten, Ownership- und Transaktionsfehler scheitern geschlossen. Offline-Policy-Ersetzung kann Bindings widerrufen, Read-Roles ändern und Principals deaktivieren, ohne Daten zu verschieben. IDs bleiben erhalten; keine Online-Policy-Mutation.

Dies ist der begrenzte lokale Operator-Bootstrap. Management ist **nicht** als REST/MCP-Schreib-Capability freigegeben. Spätere Freigabe benötigt authentisierte Operator-Identität, zielbezogene administrative Permissions, dauerhaftes Audit, Wiederholungs-/Idempotenzstrategie und Sicherheitsabnahme. Die bestehende Demo-Mutation bleibt ausschließlich im expliziten Single-Infrastructure-Demoprofil verfügbar.

## Grenzen

Keine produktive Tenant-Zertifizierung: derselbe OS-Benutzer bleibt vertrauenswürdig, kein Login-/OIDC-/TLS-/Remote-RBAC, kein Credential-Vault. Sources sind weiter ausschließlich lokale OPC-UA-Simulationen. Audit ist lokal und nicht manipulationssicher. Diagnostics-Ausführung und vollständige Historien fehlen; es gibt keine neuen SNMP-/MQTT-/Modbus-/Host-Adapter. RUSTSEC-2023-0071 und bestehende Advisory-Ausnahmen bleiben offen.
