# OIP-008 — Vorschlag für mehrere Infrastrukturen

**Vorschlag, nicht implementiert.** OIP-007 bietet einen gemeinsamen lokalen Core und Source-beschränkte Delegation. `SourceScope` ist ausdrücklich keine Tenant-Isolation. Keine neue globale Infrastruktur-ID wurde in Runtime, IPC, Policies oder wiederverwendbare UI-Komponenten eingeführt.

## Ausgangspunkt und fachlicher Vertrag

Heute: registrierte DataSourceId, Geräteidentität aus Registry, EntityId und Observation-Provenienz, zentrale CapabilityService-Autorisierung; ein SQLite-Bestand pro Core. Es gibt keine Organization-/Infrastructure-/Site-API, keine Credential-Verwaltung, kein Tenant-Audit und keine produktive Identität. Source-Geräte besitzen bestehende IDs wie `M-01` und `sim-b:M-01`; daraus darf keine Organisationsberechtigung abgeleitet werden.

Vorgeschlagene neutrale neue ID-Typen: `OrganizationId`, `InfrastructureId`, `SiteId` und explizite Zuordnung zu SourceId/DeviceId. Organizations können mehrere Infrastrukturen besitzen, jede Infrastruktur mehrere Sites. Familie/Bekannte/Firmen sind keine fest codierten Sicherheitsrollen. Eigentümer, delegierter Betreiber und konkreter Zugriff sind getrennte Beziehungen. Ein lokaler Installationsbetreiber ist nicht automatisch Administrator aller fachlichen Organisationen.

## Umsetzungsreihenfolge

1. ADR mit Bedrohungsmodell, Identitätsautorität und Datentrennungsentscheidung. Zunächst typisierte, stabile Registry-Zuordnung mit Migration; keine IDs in Namen/Source-Strings verstecken. Alle vorhandenen Daten benötigen eine ausdrücklich vom Operator bestätigte Legacy-Zuordnung statt einer stillen globalen Tenant-ID.
2. Application Services zuerst: begrenzte read-only Registry-/Infrastrukturabfragen mit neutralen DTOs/Fehlern. REST, MCP und Flutter verwenden dieselben Capabilities. Kein Tenant-Filter ausschließlich im Adapter.
3. ExecutionContext um verifizierte fachliche Principal-/Organization-/Infrastructure-/Site-Scopes ergänzen. Rechte bleiben capability-spezifisch und default-deny. Resource-Enumeration, Device-Auflösung, Events, Diagnosen, Snapshot, Historie und Pagination prüfen Scope vor Datenzugriff. Globale Aggregate nur mit expliziter globaler Berechtigung; kein Quer-Tenant-Leak durch Zähler, Fehlermeldungen oder Resource-Namen.
4. Persistenzvertrag und Migrationsstrategie: FK-/Unique-Grenzen einschließlich Infrastructure und Source; dieselben Metric-/Entity-Namen dürfen in mehreren Infrastrukturen vorkommen. Alle Current-/History-/Gap-/Event-/Diagnostic-Records erhalten ihre autoritative Infrastrukturzuordnung. SQLite Single-Writer bleibt zunächst ein Installationsvertrag, nicht verteilte Mehrmandanten-Persistenz.
5. Credentials und Connector-Bindungen sind infrastrukturspezifisch und serverseitig aufgelöst. Kein Endpoint/Credential aus MCP-Toolparametern. Secret-Storage, Rotation, Dateirechte und Redaction gesondert abnehmen; keine Zugangsdaten in Audit-/Snapshot-/Discovery-DTOs.
6. Belastbare Authentifizierung und dauerhaftes Audit vor mutierenden Verwaltungsfähigkeiten. Audit: Principal, Capability, Organization/Infrastructure/Site/Source/Device, Entscheidung, Zeit, Korrelations-/Idempotenz-ID, Ergebnis. Retention und grenzüberschreitende Administration explizit entscheiden.
7. Multi-Infrastructure-UI erst nach realen Services: Auswahl ist Navigation im autorisierten Bestand, keine Erteilung von Rechten. MCP-Resources und REST/SSE folgen derselben Registry; Session-Policies können keine Infrastruktur aus einer selbst behaupteten ID freischalten.

## Erforderliche Abnahme

Zwei Organisationen, mehrere Infrastrukturen und Sites, gleichnamige Quellen/Geräte/Metriken, jeweils erlaubte und verweigerte direkte Service-/REST-/MCP-/SSE-Zugriffe. Prüfen: Auflistung, Detail/History, Health/Aggregate, Events/Gaps/Diagnosen, Discovery, Fehlermeldungen, Pagination, Restart/Migration, Audit/Secret-Redaction und Revocation bereits verbundener Sessions. Auch ungültige/verwaiste Zuordnungen und Backpressure dürfen keine Scope-Aufweichung verursachen.

Bis zu dieser separaten Architektur-/Security-Abnahme bleibt OIP lokal simuliert und nicht produktionsfreigegeben. Kein voreiliger Tenant-Claim aus den drei OIP-007-Testcredentials. OT-Aktuierung bleibt ein eigenständiges Safety-Gate und ist kein Bestandteil dieses Vorschlags.
