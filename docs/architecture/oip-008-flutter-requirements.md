# OIP-008 — Flutter-API-Anforderung v2

Die Flutter-Sources, Assets, Packages und das isolierte OPC-UA-2027-Workstream bleiben unverändert. Die aktuelle Spectrum-App wird gegen den neuen Rust-Core im ausdrücklich lokalen `--demo`-/Single-Infrastructure-Modus regressionsgeprüft. Multi-Infrastructure-Bedienung wird nicht vorgetäuscht.

## Implementierte API-Grundlage

Bearer-gebundene Principals, autorisierte Organizations/Infrastructures/Sites, Source-Filter und ScopedSnapshot/SSE über `/api/v2/*`. Laufzeitdaten bleiben source-spezifisch. Keine globale Revision, kein globaler Count in Tenant-Snapshots. Device- und Source-Identitäten sind Registry-IDs. Node-Ausgaben enthalten zusätzlich SourceId; NodeQuery benötigt bei mehreren erlaubten Sources eine ausdrückliche Auswahl. Der ScopedSnapshot/SSE enthält derzeit den gesamten für den Principal sichtbaren Scope; er besitzt noch keinen zusätzlichen dynamischen Hierarchie-Selektor. DevicesRead unterstützt Principal-Scope und Source-Filter, keine neue Hierarchie-Query. Engere dynamische UI-Kontexte benötigen dafür eine spätere typisierte Query-Erweiterung; die Principal-Grenze bleibt verbindlich. Noch keine produktiven Diagnostics-/Historien-/Administrations-APIs.

## Nächster separater UI-Auftrag

Organization-, Infrastructure-, Site- und Source-Switcher ausschließlich aus autorisierten API-Listen. Ancestor-Labels sind Navigationskontext, keine Berechtigung auf Geschwister. Auswahl darf weder Primärquelle noch Tenant aus Device-Präfixen ableiten. Scope-Wechsel muss laufende Requests abbrechen, alte Cache-/Chart-/Inspector-Daten verwerfen und den neuen autorisierten Snapshot laden.

Aggregierte Dashboards, Devices, Diagnostics und Node-Browser müssen die gewählte autorisierte Hierarchie berücksichtigen. HTTP403/404, Unknown, Stale, fehlende Messwerte, Data Quality und Provenienz bleiben unterscheidbar. Reconnect verwendet vollständigen autorisierten REST-/SSE-Resync, keine Event-Replay-Annahme. Farben sind kein alleiniger Statusnachweis.

Credential-Bereitstellung für einen Browser ist ein eigener Security-Entwurf: keine Tokens in URL, gebauten Assets, LocalStorage-Beispielen oder Screenshots. Der derzeitige lokale Bearer-Entwicklungspfad ersetzt keine produktive Login-/Session-/CSRF-/Remote-TLS-Abnahme. Keine Dropdowns mit fiktiven Organizations in dieser Phase.

## Kompatibilität

Der bisherige v1-Full-Snapshot bleibt nur für ausdrücklich autorisierten Legacy-/Platform-Zugriff. Anonyme Multi-Infrastructure-Reads scheitern geschlossen. Es gibt keinen All-Access-Fallback für ältere Flutter-Versionen. Die UI-Session kann v2 auf dieser dokumentierten Grenze entwickeln; Integration nach main bleibt ein separater Auftrag.
