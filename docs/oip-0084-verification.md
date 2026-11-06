# OIP-008.4 — Application Settings & MCP Management Core

2026-11-06. **OIP IS AGENT-FIRST BY DESIGN.** Ausschließlich lokale Entwicklung/Simulation. Keine Produktionsfreigabe.

## Ausgangspunkt und Isolation

Kanonischer Commit `0e20f7283a8815242aaa71a2066a9944cb8cafc8`, sauberer main,382 getrackte Dateien. Eigener Worktree `/Users/benny/Code/open-industrial-platform-worktrees/oip-0084`, Branch `feature/oip-0084-application-settings`. Authority: Session `01a1a3b3-9469-7311-be9a-1218be181ebc`, ausschließlich Core/Storage/REST/MCP/Tests/Dokumentation. OpenCode-Status war leer, jedoch **kein globaler Lock-Nachweis**; laufende UI-Arbeiten/Prozesse wurden zusätzlich anhand ihrer isolierten Pfade erkannt. Keine fremden Prozesse beendet, Previews ersetzt oder Operator-Datenbanken geöffnet. Keine Handoff-Integration.

Externer Source-Backup und Receipt:

`/Users/benny/Documents/OIP-Handoffs/core-0084-settings-20261106T182412Z/`

`baseline.tar` enthält alle382 kanonischen Dateien, unabhängig erneut gegen Git-Source-Hashes gelesen. `preflight.json`, `inventory.json`, `baseline-binary.json`, Source-/Testlogs, geprüfte Fixture-Backups und finaler Receipt-Manifest bleiben dort erhalten. Keine Credentials oder Runtime-Daten im Source-Archiv. Geschütztes echtes OIP-008.3-Binary wurde **vor Änderungen** kopiert/gehasht; kein neues Settings-Binary als angeblicher Schema4-Erzeuger verwendet.

83 kanonische Flutter-Dateien byteidentisch; Cargo.lock, acht Workspace-Mitglieder und bisherige SQL-Migrationen1–4 unverändert. Designreferenz SHA-256 weiterhin `bd9f9d8696ed48676055ee9a2cd0afb29e6c3d59e0945e662d925306f73c753e`. Main bleibt unverändert und sauber. Der endgültige lokale Feature-Commit steht im externen git-final.json/Session-Abschluss, ohne selbstreferenziellen Amend.

## Tatsächliche Implementierung

[Domain/Apply](architecture/oip-0084-settings-domain.md), [Storage/Migration](architecture/oip-0084-settings-storage.md), [Authorization](architecture/oip-0084-settings-authorization.md), [MCP Management](architecture/oip-0084-mcp-management.md), [Capability-Matrix](architecture/oip-0084-rest-mcp-parity.md), [Flutter-Vertrag](architecture/oip-0084-flutter-settings-contract.md).

Neu: core/settings.rs typisiert Keys/Werte/Scopes/Kategorien/Definitionen/Revisionen/Apply-Zustände; storage/settings.rs implementiert Migration5, validierte Snapshot-Ladung und eng begrenzte Offline-CAS-Änderung mit atomarem Audit. server/settings_services.rs bietet zentrale Settings-/Management-Reads. Die existing Runtime lädt Settings vor Writer-/Worker-Start. Zwei kleine REST-v2-Adapter und zwei MCP-Tools verwenden denselben ApplicationCore. build.rs ermittelt die echte Build-Revision und verfolgt auch Worktree-HEAD/index/Branch-Ref. Die vorhandene Gap-Regel erhält lediglich gemeinsam verwendete ID-/Versionskonstanten; ihre fachliche Aussage bleibt unverändert.

**Drei veränderbare Einstellungen:** instance_name, instance_description, history_page_size. Nur HistoryPageSize vererbt sich Source→Site→Infrastructure→Organization→Platform→Default. Die tiefste ausdrücklich angegebene History-Query-Filterebene bestimmt den Kontext; unscoped/device-only Queries nutzen Platform. Explizites Query-Limit gewinnt. Metadaten bleiben Platform-only. Revisionsinformationen, Default, exakter Persistenzwert, effektiver Wert und Herkunft sind getrennt. Tenant-Reads erhalten weder fremde Änderungsidentitäten noch den globalen Startup-Zeitpunkt.

**Änderungen sind offline:** bestehende private DB-Ownership plus explizit provisioniertes SettingsWrite am Ziel. Der JSON-Principal ist On-behalf-Policy-Auswahl, nicht remote authentisierte Identität. Der tatsächliche lokale OS-Operator wird separat auditiert. Keine Runtime-Änderung während der Daemon die DB besitzt. Erfolgreiche Persistenz meldet RequiresRestart und keinen aktiven Runtime-Wert; erst der nächste validierte Start macht den neuen Wert wirksam. Keine REST-/MCP-Write-Route und keine Änderung von Credentials, Grants, Listenern oder Sources über Settings.

27 deklarierte Capability-Verträge:25 Reads, bestehende SimulationScenarioSet-Mutation und offline-only SettingsChange. Letztere ist über CapabilityService/REST/MCP gesperrt; die Übersicht kennzeichnet OFFLINE_OPERATOR_ONLY statt einer erfundenen Remote-Implementierung.18 registrierte MCP-Read-Tools bei explizitem Platform-Management-Profil. Unveränderte alte Principal-Policies behalten16; explizite scoped SettingsRead-Profile17. Alle sieben historischen Diagnostics-Reads bleiben erhalten.

## MCP-Management und ehrliche Grenzen

Status/Limits kommen aus realer Komposition/Runtime und dem vorhandenen SDK. Der Tool-Katalog stammt aus derselben registrierten Mapping-/Schemaquelle; registered, available_to_principal und runtime_available sind getrennt. Tool-/Settings-/Policy-Freischaltung über MCP gibt es nicht.

Client-Konfiguration ist gültiges generisches JSON mit tatsächlichem Executable und echten Bridge-Optionen, aber **Platzhaltern** für private Socket-/Credential-Pfade. Sie ist ohne Ersetzung nicht verwendbar, provisioniert keine Credentials und ist kein erfolgreicher Verbindungsnachweis. Tatsächliche Verbindungen werden separat durch SDK-E2E geprüft.

**Queryable Connected Sessions: UNSUPPORTED.** JoinSet-/Log-Zähler beweisen keine initialisierten Clients. Es werden keine Profile als Online-Sessions, geratenen Namen oder falschen Disconnect-Zustände ausgegeben. Diagnose-Reads beobachten die eigene Runtime; sie testen keine fremden Dateien/Credentials/Clients und erzeugen keinen Path-/Credential-Oracle. Enable/Disable, Remote MCP, dynamische Tool-Switches, Session-Disconnect und Source-Reconfiguration bleiben gesperrt.

## Neu ausgeführte Prüfungen

[Kuratiertes Test-Summary](evidence/oip0084/test-summary.json), [Integrität](evidence/oip0084/integrity.json), [Reviews](evidence/oip0084/reviews.json), [Secret-Scan](evidence/oip0084/security.json).

| Prüfung | Ergebnis |
|---|---|
| Unveränderte kanonische Rust-Baseline vor Änderungen |135 PASS |
| Rust fmt/check/clippy -D warnings | PASS |
| Workspace |**144 PASS**:135 vorhandene +5 Storage- und4 Settings-Service-Tests |
| Storage |**35 PASS**, überlappende Workspace-Gruppe |
| OPC-UA beide Backends / open-only |**37 /2 PASS** |
| no-default/open-only/beide check+clippy, locked Workspace-/SDK-Build | PASS |
| cargo-deny | PASS mit unveränderten Advisory-Ausnahmen, keine Behebung |
| Settings Core/REST/offizielles SDK | PASS: gleiche Daten/Scopes/Schemas, negative Grants/Actor/Mutationen |
| Vererbung/Apply | PASS: tatsächliche History-Aufrufe auf allen fünf Ebenen, explizites Limit, Startup-Snapshot |
| Revisions-/Audit-/Migrations-Failure-Injection | PASS: CAS-Konflikt, gemeinsamer Rollback, DDL-Rollback, Scope-/FK-Manipulation |
| Neuer echter Settings-E2E | PASS: vier Simulatoren, zwei Organizations, acht SDK-Clients, Schema4→5, Restart/SIGKILL |
| Vorhandener Diagnostics-Mehrorg-E2E | PASS einschließlich sieben Histories, Cursor/Scopes, acht Clients, Recovery |
| Schema3-Übernahme / echte Schema2-Adoption | PASS mit geschützten alten Binaries; neuester Runtime-Open endet auf5 |
| Headless / MCP-stdio | PASS einschließlich Slow-Client/Framing/Shutdown/Crash |
| SQL-/Application-Performance mit100000 synthetischen Events | PASS, eigene Fixture und reale transportbasierte Reads; keine echten Messereignisse behauptet |
| Dart Format / Flutter Analyze | PASS,0 Issues |
| Unveränderte Flutter-Tests / Web Release |**80 PASS** / PASS |
| Browser / Spectrum-Interaktionen / Responsive |**16 PASS**, zusätzliche30 aktuelle Captures |
| Native macOS |1 Integrationstest mit Alarm/Reconnect PASS |
| Eigene Prozess-Cleanups | PASS |

Testgruppen werden nicht künstlich addiert. UI-Tests liefen aus byteidentischen kanonischen Quellen; der neue Backend-Build und ein **externes** Web-Output wurden verwendet. Laufende Operator-Webassets blieben erhalten. Testprozesse verwendeten ausschließlich eigene Loopback-Ports/DBs. Rohlogs und Fixture-DBs bleiben extern/ignoriert, nicht in Git.

Frühe Entwicklungsfehler sind erhalten: neue Rust-Fixtures mussten private DB-Ownership vor SQLite-Erzeugung erwerben; API-Test nutzte anfangs falschen Router-Namen/private Konstruktion; alte Discovery-Erwartung wurde ehrlich von einer auf zwei gesperrte Mutationsverträge aktualisiert. Ein übergroßer SDK-Frame wurde zunächst irrtümlich als antwortpflichtiger Toolfehler getestet: die begrenzte Transportebene verwirft solche Frames. Finale Manipulationsprüfung nutzt einen gültig gerahmten, fachlich zu langen Input; der vorhandene echte Framing-/Slow-Client-Harness prüft den Transport separat. Ein fehlender lokaler cargo-deny-Pfad wurde durch Kopieren des bestehenden verifizierten Projekttools in den eigenen Build-Bereich behoben. Keine Produkt-Sicherheitsprüfung abgeschaltet und kein fehlgeschlagener Lauf als PASS ausgegeben.

## Zusammenhängender Settings-E2E

Der geschützte echte Schema4-Core erzeugt mit vier OPC-UA-Prozessen Observations/Events/Gaps/Health; danach kontrollierter Stopp und unabhängiges SQLite-Backup. Die neue Runtime migriert auf5. Alle alten IDs/Payloads/Hierarchiezuordnungen bleiben erhalten. Offline-Provisioning neuer Settings-Policies ist ein separater expliziter Operator-Schritt, keine implizite Migrationsberechtigung.

Sechs sichere Settings-Änderungen und zwei gleichzeitige CAS-Kandidaten: **genau einer der beiden gewinnt**, insgesamt sieben atomare Audit-Einträge. Ungültige Werte, falsche Revision und Reader-Write scheitern. Acht unabhängige SDK-Clients prüfen REST-/MCP-Parität, alle Scope-Ebenen, gesperrte fremde Scopes, unbekannte/überlange Inputs und Mutationssperre. Konfigurations-JSON und Bridge-Argumente stimmen, keine Credential-Ausgabe. Änderung bei laufendem Core wird durch Ownership abgewiesen.

Ein Client wird abrupt beendet, übrige/Core bleiben aktiv. Ohne Clients gehen Ingestion/Persistenz weiter. Reconnect, Source-A-Ausfall bei weiterlaufenden anderen Sources und Recovery bestehen. Nach kontrolliertem Restart sind gespeicherte Werte Stale und Source-Zustände Unknown bis zu echtem Empfang. Echter SIGKILL wird als interrupted erkannt. Settings und historische Identitäten bleiben erhalten; keine doppelten Observation-Keys, FKs und integrity_check okay. Alle eigenen Prozesse beendet.

## Performance und Security

25 Reads je Transport/Fall, derselbe echte Core mit vier Sources und acht verbundenen SDK-Clients, macOS arm64/Rust1.93/rmcp3.8.0. MCP-Latenz enthält den modellfreien SDK-Kontrollprozess-Hop. p95 in ms: Katalog REST0.763 /MCP1.660; effektive Settings1.023 /2.208; MCP-Status0.751 /1.180. Unsupported-Session-Status0.645 /0.684 ist **keine Messung eines Session-Discovery-Features**. Sechs Offline-Saves inklusive CLI/Ownership/Transaktion p50/p95:24.977 /37.359ms. Kurze OS-Stichprobe36256KiB RSS /10.3% CPU; Ingestion während Reads48→63 Observations. Keine Peak-/Dauerlauf-/SLA-Aussage.

Zwei unabhängige Read-only-Code-/Evidenzreviews: `/root/review_settings_0084` und `/root/review_security_0084`. Anfangsbefunde behoben: keine erfundene Änderungsidentität, exakte FK-/Scope-Konsistenz, auditiert ungültiger Scope, ehrliche Offline-Mapping-Angabe, getrennte OS-Authority, kurzer Mutex/cached Schema sowie korrekt verfolgte Worktree-Build-Provenienz. Finale Reviews ohne offene Blocking-Findings im geprüften lokalen Scope. Reviewer führten die Tests nicht selbst aus; sie prüften Code und konkrete Eltern-Evidenz.

Gitleaks8.30.1 tatsächlich auf vollständigem Source-Kandidaten:27 bekannte False Positives, jede Fundstelle/File/Line/Rule plus vollständiger unveränderter Baseline-Dateihash erneut geprüft;0 ungeklärte Funde. Kein Scanner deaktiviert. Endgültiger Kandidat und Receipt werden nochmals gehasht/geprüft; keine Credentials/DBs/Logs/Binaries im Feature-Commit.

Offen: **RUSTSEC-2023-0071**, RUSTSEC-2023-0089, RUSTSEC-2024-0449; produktive Remote-/Browser-Identity, feindliche Same-UID-Prozesse, manipulationssicheres dauerhaftes Audit, industrielle Dauer-/OT-Safety-Tests. Nicht implementiert: Remote MCP, Browser-Admin-Session, Credential-Management-UI, Service-Installation, productive Tenant Administration, Retention Cleanup, Remote Session Disconnect, dynamische Source-Reconfiguration, aktive Client-Inventarliste oder Settings-SSE. Keine neue Produktionsberechtigung oder öffentliche Schnittstelle.

NOT_TESTED: Remote-CI, andere native Plattformen/reale Browser, feindliche OS-Konten, Langzeit-Leaks/Hardware-Stromausfall, produktive Daten und zukünftige Settings-/Diagnostics-UI-Anbindung.

## Reproduzierbare Start-/Testbefehle

```sh
cd /Users/benny/Code/open-industrial-platform-worktrees/oip-0084
cargo build --locked --workspace
cargo build --locked -p oip-server --examples
python3 tests/oip0084/prepare_local.py --directory /private/tmp/oip0084-local --settings-operator-principal platform-reader
# Ausschließlich neues privates Verzeichnis; erzeugt noch keine Datenbank/Service.
target/debug/oip-server --config /private/tmp/oip0084-local/core.json --provision /private/tmp/oip0084-local/plan.json
```

Vor Daemon-Start eine eigene Settings-Request-Datei im privaten Verzeichnis anlegen:

```json
{"principal":"platform-reader","scope":{"kind":"platform"},"key":"instance_name","value":{"type":"text","value":"Local OIP"},"expected_revision":0}
```

```sh
target/debug/oip-server --config /private/tmp/oip0084-local/core.json --settings-change /private/tmp/oip0084-local/change.json
# Bei belegter Datenbank abgewiesen. Sonst persisted_requires_restart, nicht live applied.
```

Vier eigene freie Simulatorports entsprechend der erzeugten core.json, jeweils ein Terminal (Beispielkonfiguration15861–15864): `target/debug/oip-simulated-server --port 15861 --seed 42 --tick-ms 250`, weitere Ports/Seeds analog. Danach:

```sh
target/debug/oip-server --daemon --config /private/tmp/oip0084-local/core.json --ipc-config /private/tmp/oip0084-local/ipc.json
```

REST am konfigurierten Loopback18808 mit bestehendem gebundenem Authorization-Header: `/api/v2/settings?catalog=true`, `/api/v2/settings`, `/api/v2/management?section=tools`. Kein Token in der URL; kein anonymer Multi-Tenant-UI-Zugang. Generischer MCP-Client startet dasselbe Binary mit `--mcp-bridge --ipc-socket /private/tmp/oip0084-local/s --ipc-credential /private/tmp/oip0084-local/platform-reader.credential`. Neue Tools `oip_settings_read` und `oip_mcp_management_read`. Kein Settings-Write-Tool. Ctrl+C stoppt kontrolliert; keine Systemdienste installiert.

```sh
cargo fmt --all -- --check
cargo check --locked --workspace --all-targets
cargo clippy --locked --workspace --all-targets -- -D warnings
cargo test --locked --workspace -- --test-threads=1
cargo test --locked -p oip-opcua --features open62541-backend -- --test-threads=1
cargo test --locked -p oip-opcua --no-default-features --features open62541-backend -- --test-threads=1
# Bestehendes lokales Projekttool, kein globales Installieren:
target/oip-002-tools/bin/cargo-deny check advisories licenses bans sources
OIP_EVIDENCE_DIR=<neues-eigenes-evidenzverzeichnis> OIP0083_BASELINE_BINARY=<geschuetztes-exaktes-schema4-binary> OIP0083_BASELINE_SHA256=<gepruefter-hash> python3 tests/oip0084/acceptance.py
```

Exakte ältere Harness-Befehle, Artefaktpfad-Overrides und gesicherte Schema2/3-Binaries stehen im externen Receipt (`harness-provenance.json`, `harness-results.json`, `rust/results.json`, `final-source-checks.json`). Niemals frisch gebautes Feature-Binary als Legacy verwenden. Die vorhandenen Harnesses wurden ausschließlich hinsichtlich eigener Artefakt-/Legacy-Binary-/Weboutput-Pfade umgebunden; Assertionen/Autorisierung unverändert. Geänderte Schema-Erwartungen in vorhandenen Tests beziehen sich auf den aktuellen Runtime-Open5, nicht auf eine erfundene alte Version.

Flutter-Befehle aus byteidentischen kanonischen apps/flutter: `flutter analyze`, `flutter test --reporter expanded`, `flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none --output=<externes-neues-verzeichnis>`. Eigene Backend-/Browser-/native-Sequenz im Receipt, alle ursprünglichen Prozesse erhalten.

Alle18 Gates im kuratierten Summary nachgewiesen. Nächster Schritt ist eine **separate** Core-Integrationsfreigabe, danach OIP-009 Browser-/Session-/SSE-Sicherheitsvertrag und spätere Settings-UI-Anbindung. Kein Merge nach main, kein Push, kein Deployment.

OIP_008_4_APPLICATION_SETTINGS_CORE_PASS
