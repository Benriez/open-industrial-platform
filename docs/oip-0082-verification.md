# OIP-008.2 — Diagnostics & Evidence Core

2026-11-05. **OIP IS AGENT-FIRST BY DESIGN.** Lokale Entwicklung und Simulation; keine Produktionsfreigabe.

## Ausgangspunkt, Autorität und Isolation

Kanonischer Ausgangs-Commit `79639ff42c68ee2ede34862929822a4789845268`, sauberer main,359 getrackte Dateien. Eigener Worktree `/Users/benny/Code/open-industrial-platform-worktrees/oip-0082`, Branch `feature/oip-0082-diagnostics-evidence`. Session `01a1a3b3-9469-7311-be9a-1218be181ebc`, Scope ausschließlich Rust/Diagnostics/Storage/REST/MCP/Tests/Dokumentation. Lokale Feature-Commits autorisiert, kein Merge nach main oder Push.

Die acht angeforderten Berichte und die realen Domain-/Application-/Storage-/MCP-/Runtime-Quellen wurden geprüft. **118 Workspace-Tests der unveränderten kanonischen Baseline vor den Featureprüfungen erneut bestanden.** Leeres OpenCode-Aktivstatus-JSON ist keine globale Schreibsperre: Die laufende Diagnostics-UI wurde zusätzlich anhand isolierter Verzeichnisse/Prozesse erkannt und blieb außerhalb des Schreibbereichs. Bestehende Vorschauen und fremde SQLite-Dateien wurden nicht verändert/geöffnet/beendet. Eigene Tests besitzen eigene Ports, private Runtime-Verzeichnisse, Credentials und Datenbanken.

Externe Sicherung sämtlicher359 Git-Quelldateien, unabhängig gegen Git-Blobs verifiziert:

`/Users/benny/Documents/OIP-Handoffs/core-0082-20261105T222139Z/baseline.tar`

SHA-256 `f19bc3f025e7eefd09a1c9723e79c872cf6e01acc262763597b2589ac3cd74c4`.

[Preflight/Backup](evidence/oip0082/preflight.json), [Integrität](evidence/oip0082/integrity.json). Main bleibt byteidentisch zu79639ff; sämtliche Flutter-Quellen/Assets/Packages/nativen Projektdateien unverändert. Keine UI-Handoffs integriert und keine neue Vorschau erzeugt. Die Test-UI verwendet einen externen Web-Build; laufende Operator-Webassets wurden nicht ersetzt.

## Fachlicher Audit und Implementierung

[Domain/Gap-Matrix](architecture/oip-0082-diagnostics-domain.md), [Query/Storage](architecture/oip-0082-evidence-query.md), [Zeitsemantik](architecture/oip-0082-time-semantics.md), [REST/MCP-Matrix](architecture/oip-0082-rest-mcp-parity.md), [Flutter-Vertrag v2.1](architecture/oip-0082-diagnostics-flutter-contract.md).

Vorher vorhanden: stabile persistierte Observation-/Event-/Gap-Schlüssel, SourcePlacement-Hierarchie, zentrale Rollen/Scopes, tatsächliche Kontrollereignisse, Source-Health, Reconnect/Run-Journal, eine Runtime/ein Writer und begrenzte IPC-/MCP-Sessions. Keine autorisierte historische Application-Query; EventsRead war ein Cache der letzten100 Kontrollereignisse/Source. `oip-diagnostics` enthielt nur einen Platzhalter. oip-agent/oip-gateway bleiben leere Einstiegsskelette, keine neue Agentenabhängigkeit.

Neu:

- Core `diagnostics.rs`: typisierte historische Events/Observations/Gaps/Health, Queries, Seiten, Evidenz und Befunde. Vorhandene ClientEvents/Envelopes/Health-Dimensionen wiederverwendet.
- Storage `history.rs`: separate read-only Verbindungen, Snapshot-Watermarks, indexgestützte keyset-Seiten, Byte-Budgets, Cancellation/Deadline. Kein direkter SQL-Zugriff aus REST/MCP-Handlern.
- Application `diagnostic_services.rs`: zentrale Validierung/Hierarchie-Autorisierung, Cursor-Bindung, begrenzte Admission, gleiche Ausführung für beide Adapter.
- Bestehender Writer zeichnet tatsächlich beobachtete Dimensionsänderungen auf. Prozessanfang previous=null, keine nachträglich erfundenen Übergänge.
- `oip-diagnostics`: genau eine deterministische Regel `oip.documented-collection-gap` v1. Sie bestätigt ausschließlich einen dokumentierten Gap, keine Root Cause. Evidenz, Zeitmarker und fehlende unabhängige Messungen ausdrücklich enthalten. Befunde dynamisch abgeleitet, keine erfundenen gespeicherten Diagnoseläufe.
- Live-Kontrollrecords erhalten additiv ihre ursprüngliche persistierte Event-ID. Historie und SSE verwenden dieselbe Identität; kein Event-Replay hinzugefügt.

24 Capabilities, davon23 lesend;16 MCP-Tools im Principal-Modus,13 unter passender Legacy-Policy. Sieben neue Reads: EventHistoryRead, EventDetailRead, DataGapsRead, SourceHealthHistoryRead, EvidenceRead, DiagnosticFindingsRead, ObservationHistoryRead. Keine Mutation freigeschaltet. Acht Workspace-Crates, kein SDK-/Versionsupgrade; vorhandenes rusqlite aktiviert hooks. Cargo.lock ergänzt lediglich Workspace-Abhängigkeitskanten.

## Semantik und Sicherheitsgrenzen der Queries

Limit1..100, Standard50, stabile Zeit/Schlüssel-Sortierung, keine globalen Counts. Kalenderfilter1601..9999, inklusive Enden, ungültige Bereiche abgewiesen. Ungefilterte Events/Detail bewahren auch ursprünglich gespeicherte ungültige Sentinel-Zeiten. Beobachtungshistorie nach Receive-Zeit; Source-/Server-/Receive-Zeit und Provenienz bleiben getrennt. Fehlende Receive-Zeit wird nicht ersetzt. Historische Samples einschließlich eingebetteter Observation-Events sind Stale-Projektionen; gespeicherte Daten bleiben unverändert.

Gaps werden nach dokumentiertem Startmarker gefiltert, **keine Intervall-Overlap-Query**. Zero-Length-DataLoss-Marker sind kein Beweis für0ms Unterbrechung. Endmarker beweisen keine aktuelle Erreichbarkeit. Ein Gap ist kein nachgewiesener Netzwerk-/OPC-UA-Fehler. Evidenz ist strikt zeitlich/kontextuell in derselben autorisierten Source korreliert; keine automatisch erweiterten Beziehungen, Ursachen oder Gegenbelege.

Opaque zufällige Cursor binden Principal/Actor, effektive Rechte/Sources, Capability und sämtliche Filter/Zeitbereich/Limit/Sortierung. Neue/backfilled Inserts nach dem ersten Snapshot bleiben ausgeschlossen. TTL300s; nach Neustart ungültig.64 aktive Chains/Principal,1024 Tokens global, zwei jüngste Continuations/Chain; ältere Continuations können vor TTL entfallen. Kein unbegrenzter Cache und keine Exactly-once-Garantie. Requests ohne Cursor eröffnen gegebenenfalls neue Chains; dauerndes unpaginiertes Polling kann das dokumentierte Capacity-Limit erreichen.

Vier aktive blockierende Reads global, keine unbegrenzte Warteschlange. SQL-Budget2s, Application3s, Busy-Wait100ms. Transportabbruch cancelt die SQL-Arbeit mittels Atomic/SQLite-Progress-Hook; der Admission-Permit bleibt bis zum tatsächlichen Ende gehalten.64KiB pro Payload/Reason vor Laden,512KiB kumulativ/Read, explizite Fehler statt stiller Auslassung. Evidence maximal vier begrenzte Komponenten plus Anchor. Bestehende MCP-Input-/Output-/Session-Limits bleiben erhalten.

Principal/Scopes stammen aus dem vorhandenen lokalen Credential-/Peer-Binding, niemals aus Tool-/Query-Parametern. Historische Events enthalten gegebenenfalls Telemetrie und benötigen deshalb EventsRead+TelemetryRead; Health-Historie EventsRead+SourcesRead; Evidence alle drei. Gleiche zielbezogene Grants müssen zusammenpassen. Fremde/fehlende Detail-IDs generisch404, fehlende Rechte403, manipulierte/abgelaufene Cursor400; keine fremden Namen/Counts. Audit erhält validierten Hierarchie-/Anchor-Kontext, keine Credentials/Payloads.

## Schema und Migration

Append-only **Migration4** ergänzt Health-Historie mit Source-/Run-FKs und fünf nachgewiesene Query-Indizes. SQL/Checksums1..3 unverändert. Historische Organization-Zuordnung weiterhin ausschließlich über unveränderliche SourcePlacement-Beziehungen; keine stillen neuen Legacy-Tenants. Event-/Observation-/Gap-Keys unverändert. FK-/Transaktions-/Ownership-Regeln bleiben erhalten.

Real erzeugter Schema3-Bestand mit dem gesicherten OIP-008-Binary SHA-256 `889a36b2cf0d761796662e0437a18c2ed43dc8c1b1da82d70fecdd5a055865c6`:24 Observations,56 Events,4 Gaps. Schlüssel vor/nach erhalten, Schema4, Foreign Keys/Integrität und Stale-Restore bestanden. Offline-Provisionierung endet bei diesem Pfad bewusst weiterhin auf3; **erst Runtime-Open aktiviert4**. Ein bereits über SqliteStore::open auf4 gebrachter Store meldet bei Provisioning wahrheitsgemäß4. Keine neue Admin-CLI erforderlich.

Die separate echte Schema2-Adoption wurde mit dem **geschützten OIP-007-Binary** aus dem OIP-008.1-Receipt wiederholt; nicht versehentlich mit einem aktuellen Main-Binary. Unbestätigtes/geändertes Manifest abgewiesen, Daten und Schlüssel erhalten. Unit-Failure-Injection beweist atomaren3→4-DDL-Rollback, Idempotenz und erhaltene Schlüssel. [Beide Migrationen](evidence/oip0082/migration.json).

## Tatsächlich ausgeführte Regression

macOS arm64, Rust1.93.0, vorhandenes rmcp3.8.0, Flutter3.22.0/Dart3.4.0, Xcode/Chrome/Node und SQLite-CLI. Keine globalen Installationen.

| Prüfung | Neues Ergebnis |
|---|---|
| Rust fmt/check/clippy, warnings denied | PASS |
| Workspace | **135 PASS**;118 Baseline +17 neue Tests |
| Storage | **30 PASS**, überlappende Workspace-Gruppe |
| OPC-UA beide Backends | **37 PASS** |
| open62541-only |2 PASS |
| no-default/open-only/beide check+clippy | PASS |
| cargo-deny, locked Build, SDK-Beispiele | PASS mit unveränderten Advisory-Ausnahmen |
| Historische Rust/REST/echte SDK-Parität | alle sieben Reads PASS |
| Cursor/Scopes/Schema/Byte-Limits/Deadline/Cancel/Audit | PASS; darunter135er Suite |
| Headless mit Shutdown/Restart/Crash |7 Phasen PASS |
| Vorhandener echter MCP-stdio-E2E |9 Phasen PASS, inkl. Slow-Client/Framing |
| Neuer Vier-Quellen-Mehrorg-E2E |10 gruppierte Phasen PASS |
| Dart Format/Flutter Analyze | PASS,0 Issues |
| Unveränderte Flutter-Tests |**80 PASS** |
| Externer Flutter-Web-Release | PASS |
| Browser-Fachregression |**16 PASS** |
| Spectrum-Interaktionen/Themes/Responsive | PASS,30 aktuelle Captures |
| Native macOS |1 Integrationstest mit Alarm/Reconnect PASS |
| Alle eigenen Prozess-Cleanups | PASS |

[Maschinenlesbare Befehle/Resultate](evidence/oip0082/test-summary.json). Testgruppen überlappen und werden nicht künstlich summiert. Kein Test gelöscht. Alte Harnesses ändern nur additive Discovery-Zahlen. Flutter wurde aus dem byteidentischen kanonischen UI-Verzeichnis mit vorhandenen Tool-Caches geprüft; Backend und Webassets kommen aus dem neuen Feature bzw. dessen externem Build. SDK-Tests nutzen modellfreie offizielle Clients, kein Prompt-/Mock-Ersatz.

## Zusammenhängender E2E

`tests/oip0082/acceptance.py` verwendet vier echte Simulatorprozesse, zwei Organizations, mehrere Infrastructures/Sites, fünf eingeschränkte Principal-Profile plus expliziten Testoperator, eine Runtime/einen Writer. Die Prozesssteuerung baut auf dem vorhandenen OIP-008-Harness auf.

Nach Provisioning/Ingestion/REST/SSE/Discovery: drei unabhängige und acht parallele MCP-Clients, Scope-Denials auf allen Ebenen, manipulierte Actor-/Principal-/Filter-Inputs und gesperrte Mutation. Client-SIGKILL/Disconnect beeinflussen andere Clients/Core nicht; ohne Clients wird weiter persistiert. Source A aus, Organization B liefert weiter; tatsächlicher Reconnect, Gaps und neue **eindeutige** Beobachtungen. Danach sieben historische Reads mit echter REST/MCP-Parität, Zeit-/Source-Filter,124 stabile IDs in62 Seiten unter fortlaufender Ingestion, Gap-/Health-/Evidence-/Finding-Queries, fremde Detail-/Evidence-IDs und Cursor verweigert, SSE-ID/History-ID identisch. Acht parallele historische SDK-Reads samt weiterlaufender Ingestion. Kontrollierter Neustart ohne Sources: gespeicherte Werte Stale, Source Unknown/last_received=null. Erst tatsächlicher neuer Empfang macht Live. Echter SIGKILL, Run-Journal interrupted, alte Event-IDs erhalten, keine doppelten Observation-Keys, SQLite integrity_check/FKs okay. Alle eigenen Prozesse beendet. [Report](evidence/oip0082/e2e.json).

Entwicklungsfehler wurden nicht als PASS ausgegeben: Fixture-FK-Cleanup, fehlender Host-Header einer REST-Fixture, eine überschattete Harness-Prozessvariable und ein zu früher Receive-Zeit-Endmarker korrigiert. Nach Simulator-Neustart können deterministisch identische Samples zuerst dedupliziert werden; der Test wartet deshalb auf einen wirklich neuen persistierten Schlüssel mit passender Receive-Zeit. Originale erste Empfangszeiten werden nicht nachträglich durch Redelivery ersetzt. Frühere Logs bleiben extern unter development erhalten. Die initiale irrtümliche Schema4-Erwartung an Offline-Provisioning wurde anhand der realen Architektur berichtigt; kein Produktfallback eingeführt.

## Performance

100000 ausdrücklich synthetische Event-Fixtures in separater Testdatenbank; keine behaupteten echten Messungen. Ein realer Daemon mit vier laufenden Sources wurde danach über authentifiziertes REST und den offiziellen MCP-Client befragt.25 Requests je Transport/Fall, inklusive SDK-Kontrollhop bei MCP; fortlaufende Ingestion nachgewiesen. [Messwerte, Query-Plans, CPU/RSS und Methodik](evidence/oip0082/performance.json).

| Abfrage | REST p50/p95 ms | MCP p50/p95 ms |
|---|---|---|
| Eventseite50 |2.200 /2.783 |7.397 /7.649 |
| Eventdetail |1.342 /1.705 |1.647 /1.931 |
| Evidence |1.813 /2.187 |3.554 /3.879 |

Query-Plans prüfen Source-/Zeit-/Kind-Indizes und PK-Lookups. Zusätzlich60 CLI-Proben/Query inklusive Prozessstart: p95 etwa11.8–16.4ms, nicht mit reiner SQL-Latenz gleichgesetzt. Reale8-Client-Batch-Latenzen4.5–29.8ms. Ein bewusster Principal-Cursor-Überlastversuch liefert CURSOR_CAPACITY, während anderer Principal und Writer funktionieren. Das erste Messskript überschritt mit80 neuen unbenutzten Chains dieses dokumentierte Limit; der finale Lauf misst50 erste Seiten und testet Überlast danach ausdrücklich.

RSS/CPU sind kurze Prozess-Stichproben/Lebenszeitdurchschnitte, keine Peaks. Fremde Operator-/UI-Prozesse blieben aktiv; keine isolierte Hardware-A/B-Verbesserungsbehauptung. Keine SLA, industrielle Langzeit-/Leak- oder große Observation-TSDB-Zertifizierung.

## Unabhängige Reviews und Security

Review A `/root/review_storage_0082`: Storage/Evidence/Time/Migration/Writer. Review B `/root/review_auth_0082`: Authorization/REST/MCP/Cursor/Audit. Beide getrennte read-only Sessions; sie prüften Code und anschließend Eltern-Testnachweise, führten diese nicht selbst erneut aus. [Befunde und finale Code-Hashes](evidence/oip0082/reviews.json).

Behoben: fehlende kombinierte Leserechte, SQLite/Rust-Byte-Limits vor Fetch, unbounded JSON-Filter, globale Run-ID/erratbarer Epochbezug, spätes Health-Schreibfehler-Shutdown, langsame Highwater-Abfrage, ehrliche Provisioning-Version, Erhalt negativer/ungültiger alter Zeiten, unbegrenzt anwachsende Cursor-Kette, Audit-Kontext, Tool-Required-Schemas/Bounds und falscher Performance-Baseline-Metadatenanker. Finale Reviews ohne offene Blocking-Findings im lokalen Scope.

Gitleaks8.30.1 auf dem vollständigen Source-Kandidaten tatsächlich ausgeführt; vorher bekannte27 False Positives in unveränderten Hash-/Gap-Manifesten erneut quellbezogen geprüft. Finale Funde/Hashbindung: [Scan](evidence/oip0082/secret-scan.json). Kein Scanner abgeschaltet, keine ungeklärten Secrets zugelassen. Rohlogs, Credentials, Datenbanken, PKI/Build-Caches und Captures bleiben ignoriert bzw. extern; nur bereinigte JSON-Nachweise versioniert.

**RUSTSEC-2023-0071 bleibt Produktionsblocker**, Ausnahmen2023-0089/2024-0449 bleiben offen. Keine öffentlichen Listener, echten OT-Verbindungen, Writes/Maschinensteuerung, Cloud, Remote-Administration oder neuen Admin-Mutationen. Keine produktive Remote-/Browser-Identity, Isolation feindlicher Same-UID-Prozesse oder manipulationssichere dauerhafte Audits. Health-Zwischenzustände während Persistenzfehler/Crash können fehlen und werden nicht rekonstruiert. Source-Historie vor Schema4 nicht erfunden. Kein Full-Replay, kein dauerhafter Spool, keine persistierten Diagnoseläufe oder allgemeine Rule Engine.

NOT_TESTED: Remote-CI, fremde reale OS-Konten/hostileSameUID, native Windows/Linux/Android/iOS, andere reale Browser, industrielle Dauer-/Last-/Hardware-Power-Failure-Tests, Produktivdaten und neue Diagnostics-UI-Integration. Sichere Browser-Session/SSE-Anbindung und UI-Caches bleiben OIP-009.

## Exakte Start- und Wiederholungsbefehle

```sh
cd /Users/benny/Code/open-industrial-platform-worktrees/oip-0082
cargo build --locked --workspace
cargo build --locked -p oip-server --examples
python3 tests/oip008/prepare_local.py --directory /private/tmp/oip0082-local-operator
# Nur neues privates Verzeichnis; keine bestehenden Credentials überschreiben.
target/debug/oip-server --config /private/tmp/oip0082-local-operator/core.json --provision /private/tmp/oip0082-local-operator/plan.json
```

Vier separate Simulator-Terminals (nur freie eigene Ports):

```sh
target/debug/oip-simulated-server --port 15861 --seed 42 --tick-ms 250
target/debug/oip-simulated-server --port 15862 --seed 49 --tick-ms 250
target/debug/oip-simulated-server --port 15863 --seed 56 --tick-ms 250
target/debug/oip-simulated-server --port 15864 --seed 63 --tick-ms 250
```

```sh
target/debug/oip-server --daemon --config /private/tmp/oip0082-local-operator/core.json --ipc-config /private/tmp/oip0082-local-operator/ipc.json
```

REST danach auf dem konfigurierten Loopback18808, nur mit Authorization-Header; keine anonyme Multi-Infrastructure-UI-URL. Generischer modellfreier MCP-Client startet die bestehende Bridge mit `--mcp-bridge --ipc-socket /private/tmp/oip0082-local-operator/s --ipc-credential /private/tmp/oip0082-local-operator/reader-org-a.credential`. Beispiel-Tool `oip_event_history_read` mit `{ "source":"source-a", "limit":50 }`, anschließend opake Continuation unverändert mit denselben Filtern. Evidence benötigt start_ms/end_ms plus Source oder Event-ID. Ctrl+C beendet kontrolliert, DB für Restore behalten. Keine Testinstanz bleibt nach diesem Auftrag laufen.

```sh
cargo fmt --all -- --check
cargo check --locked --workspace --all-targets
cargo clippy --locked --workspace --all-targets -- -D warnings
cargo test --locked --workspace -- --test-threads=1
cargo test --locked -p oip-opcua --features open62541-backend -- --test-threads=1
target/oip-002-tools/bin/cargo-deny check advisories licenses bans sources
python3 tests/oip0082/acceptance.py
python3 tests/oip0082/schema3_migration.py --baseline-binary /Users/benny/Documents/OIP-Handoffs/core-0082-20261105T222139Z/oip008-baseline-server --baseline-sha256 889a36b2cf0d761796662e0437a18c2ed43dc8c1b1da82d70fecdd5a055865c6
python3 tests/oip0082/performance.py
python3 tests/oip0082/application_performance.py
```

Weitere tatsächlich ausgeführte Backend-/Buildbefehle im Test-Summary. Die bestehenden Legacy-/Headless-/MCP-/UI-Harnesses wurden mit dem externen OIP-008.1-Runner ausschließlich hinsichtlich Artefakt-/geschützter Legacy-Binary-Pfade umgebunden; Produktlogik unverändert. Reproduktionsrunner und Rohlogs bleiben unter dem obigen externen Receipt. Die geschützte OIP-007-Binary für Schema2 muss weiterhin tatsächlich Schema2 erzeugen; niemals blind das aktuelle Main-Binary als Legacy einsetzen.

Flutter aus dem unveränderten kanonischen apps/flutter-Verzeichnis: `flutter analyze`, `flutter test --reporter expanded`, `flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none --output=<externes-testverzeichnis>`. Die Browser-/native Sequenz startet ausschließlich einen eigenen Demo-Core gegen diese externen Assets; konkrete Befehle im externen ui-Receipt und Test-Summary. Keine vorhandene Preview überschreiben.

## Abschluss und nächste Integration

[Alle16 Gates](evidence/oip0082/test-summary.json) fachlich bestanden. Lokaler Feature-Commit enthält ausschließlich geprüfte Core-/Test-/Dokumentationsdateien; exakter endgültiger Hash und Post-Commit-Prüfung werden im externen `git-final.json` und im Session-Abschluss festgehalten (kein selbstreferentieller Hash/Amend). Main bleibt79639ff. Kein Merge, Push oder Deployment. Designreferenz unverändert SHA-256 `bd9f9d8696ed48676055ee9a2cd0afb29e6c3d59e0945e662d925306f73c753e`.

Nächste Arbeiten: separate kanonische Core-Integration, danach Diagnostics & Events2027 über den versionierten Flutter-Vertrag mit sicherer Browser-Identity/SSE und Scope-Cache-Isolation anbinden. Produktive Identity/Audit/Advisory-Bereinigung bleibt eigenständiges Gate.

OIP_008_2_DIAGNOSTICS_CORE_PASS
