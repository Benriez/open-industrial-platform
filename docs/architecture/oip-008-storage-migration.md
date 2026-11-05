# OIP-008 — SQLite und Legacy-Adoption

## Schema3

Die SQL-/Checksum-Texte der bisherigen Migrationen1/2 bleiben unverändert. Vor jeglichem DDL werden PRAGMA-Version und die exakt lückenlose Ledger-Folge1..Version geprüft (Maximum, Anzahl, Minimum bei eindeutigem Integer-Primärschlüssel). Fehlende/Null-/negative Ledger-Versionen werden nicht durch erneutes Anwenden früherer Migrationen repariert. Migration3 ergänzt Organizations, Infrastructures, Sites, SourcePlacements, Principals, ReadRoles, RoleBindings, Provisioning-Metadaten/Audit und Source-lokale Control-Event-Sequenzen. Parent-FKs und eindeutige Source-/Device-IDs verhindern verwaiste bzw. doppelte Zuordnungen. Polymorphe Binding-Targets werden zusätzlich durch validierte Domain-Registry und SQL-Insert-Trigger geprüft. Parent-/Placement-/Identity-/Binding-Updates sind gesperrt. Policies werden ausschließlich durch validierte Offline-Transaktionen ersetzt.

Bestehende Observations/Events/Gaps bleiben über SourceId zugeordnet. Keine redundanten Organization-Spalten in allen historischen Zeilen. Source-Placement referenziert sowohl die persistierte Definition als auch die Source-Identität. Deferred Foreign Keys erlauben atomaren Erstaufbau, nicht einen halbfertigen sichtbaren Bestand.

Indizes: Organization→Infrastructure, Infrastructure→Site, Site→Source, eindeutiger Device-Lookup, bestehender Observation-Index `(entity, source, metric, source_ts)` sowie `(source, control_sequence)`. Tenant-Reads verwenden bounded Runtime-Read-Modelle; keine SQL-Queries aus MCP-Handlern. Node-Browse bleibt Source-spezifisch und auf100 pro Seite begrenzt. Startup-/Offline-Integritätsprüfungen können historische Daten vollständig lesen; sie sind kein Beleg für große Enterprise-Datenbestände.

Control-Events erhalten Source-lokale Sequenzen und einen Cache von maximal100 pro Source. Damit erzeugt fremde Aktivität keine globale Sequenzlücke oder Cache-Verdrängung in einer Tenant-Ansicht. Das ist kein vollständiges Event-Replay. Observation-Keys, Event-Keys und vorhandene Counts werden nicht geändert; abgeleitete Transport-/Control-Sequenzen sind keine fachlichen Datensatzidentitäten.

## Migration eines OIP-007-Bestands

Ein gefülltes Schema2 wird beim normalen Start **nicht** automatisch einem Tenant zugewiesen. Der Operator muss:

1. Core stoppen, DB samt WAL sichern und exklusive Ownership gewährleisten.
2. `--inspect-legacy` ausführen: Source-Menge, Counts und Digest der relevanten historischen Datensätze/Checkpoints prüfen.
3. Einen eindeutigen Single-Organization-/Infrastructure-/Site-Plan mit denselben Sources/Definitionen erstellen.
4. Die historische Single-Infrastructure-Zugehörigkeit außerhalb des Schemas prüfen und `confirms_single_infrastructure: true` ausdrücklich bestätigen.
5. `--provision PLAN --adopt-legacy MANIFEST` ausführen.

Das Manifest allein beweist keine historische Eigentümerschaft. Ohne nachvollziehbare Operator-Zuordnung ist die Adoption abzulehnen. Source-Mengen, Definitionen, Payload-/Spaltenidentitäten, Herkunft, Geräte-Entities, Event-/Observation-/Gap-Verknüpfungen und bestehende FK-Integrität werden geprüft. Migration und komplette neue Zuordnung erfolgen in einer Transaktion. Vor/nach Commit werden Counts und Digest verglichen. Fehler lassen Schema2 und Historie erhalten; keine destruktive Neuinitialisierung.

Schema1-Adoption wird vor einer Teilmigration abgewiesen; dafür zunächst den separat verifizierten OIP-007-Upgradepfad mit Backup verwenden. Die bestehende Schema1→2-Regression bleibt erhalten. Mehrdeutige, externe oder widersprüchliche Legacy-Provenienz wird nicht stillschweigend übernommen.

Nach Adoption ist ein expliziter einseitiger Übergang `legacy_single=true → false` mit additiver Datenhierarchie möglich. Zurückschalten auf einen unbeschränkten Legacy-Modus ist verboten. Offline-Policy-Ersetzung kann Berechtigungen widerrufen; vorhandene Daten-/Principal-/Role-Identitäten bleiben erhalten. Ein Runtime-Neustart lädt die neue Registry.

## Ownership und Recovery

Daemon und Provisioning verwenden dieselbe kanonische Sidecar-Sperre. Neue DB/Sidecar0600; bestehende Dateien müssen dem Operator gehören und privat sein. Unsichere Sidecars, Symlinks/Hardlinks und doppelte Besitzer werden abgewiesen; fremde Dateien werden nicht automatisch gechmoddet. Für ältere eigene0644-Testbestände muss der Operator die Rechte ausdrücklich korrigieren. Die OS-UID wird aus dem festen Systemwerkzeug `/usr/bin/id -u` ermittelt, nicht aus Umgebungsvariablen.

OIP-007-Run-Journal, Transaktionsdrain und Crash-Recovery bleiben aktiv. Gespeicherte Messwerte werden bei Restore Stale; Source-Freshness und Receive-Zeit werden nicht aus historischen Werten als Live übernommen. Ein neuer fehlgeschlagener Verbindungsversuch kann Reachability von Unknown auf Unreachable ändern. Erst erneuter tatsächlicher Empfang erzeugt Freshness Fresh.
