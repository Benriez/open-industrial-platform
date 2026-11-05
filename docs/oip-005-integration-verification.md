# OIP-005 — Canonical Integration Verification

Datum: 2026-11-04. Lokale Simulation auf macOS arm64. Keine Produktionsfreigabe.

## Ausgangsbasis und Provenienz

OIP-004-Architektur- und Verifikationsbericht wurden vollständig gelesen. Die gemeldeten 71/36/2 Rust-Tests und damaligen E2E-Nachweise waren eine Referenz, keine vorausgesetzte neue Abnahme. Die isolierte UI-Session meldete 25 Tests und eigene Browser-/Mac-Prüfungen gegen eine OIP-003-Serverkopie. Diese historische Evidenz wurde getrennt übernommen; die Integration wurde gegen den aktuellen führenden OIP-004-Core erneut getestet.

Git vor Integration: Branch `main`, kein HEAD-Commit, **0 tracked / 284 nicht ignorierte untracked Projektdateien**. Zusätzlich 126.146 ignorierte Dateien als Metadaten inventarisiert. Der vollständige nicht ignorierte Projektbestand wurde vor Änderungen extern archiviert und jeder Archivinhalt gegen SHA-256 verifiziert:

`/Users/benny/Documents/OIP-Handoffs/core-005-baseline-20261104T012210Z/project-baseline.tar.gz`

SHA-256: `56f79d98ad415d31eddbcb5f6a4f48e5e3e582540963f40ac03f0ebc0c9aa052`.

Das externe Verzeichnis enthält das vollständige Inventar mit Größen, Zeiten, Git-Klasse und Source-Hashes sowie Git-Status und Session-Audit. Ignorierte generierte Dateien/DBs/Logs/PKI/Secrets wurden nicht in ein Übergabearchiv gepackt; die Originale blieben unverändert vorhanden. Keine Source-Datei der Baseline fehlt. Reproduzierbarer Vergleich: [integrity.json](evidence/oip005/integrity.json).

Core-Session `01a1a3b3-9469-7311-be9a-1218be181ebc`: einzige OIP-005-Integrationsautorität. UI-Zulieferung `ses_e5c15927effeK5cDlqK9FuEkuE`: isolierte Snapshot-Kopie, keine Schreibautorität im kanonischen Checkout. IDs, Workstreams, Arbeitskopien/Branch, Scope, bekannte Bearbeitungszeiten und beobachtete Status stehen in [sessions.json](evidence/oip005/sessions.json). In der verfügbaren lokalen Session-Liste wurden vor und nach Integration keine aktiven konkurrierenden OIP-Tasks gefunden. Hashvergleich vor Anwendung und zum Abschluss schützt zusätzlich vor unbemerktem Source-Drift. Es wurde kein anderer Task beendet und keine globale Sperre behauptet.

### Geprüftes UI-Paket

Beide Ablagen existierten und hatten denselben erwarteten SHA-256:

- `/private/var/folders/gw/ybd859y97kbgqblclj7tfmvw0000gn/T/opencode/oip-004-ui-20261104/`
- `/Users/benny/Documents/OIP-Handoffs/ui-004/`

`oip-004-ui-handoff.tar.gz`:

`2e657d4b9c28a6d8adc7aa55151a3fe5a2601e2fb01fc8894afb02fd2c91714a`.

PASS: 126 Member, vollständiges Manifest, Hash jedes manifestierten Payloads, identischer äußerer/innerer Bericht, nur reguläre Dateien/Verzeichnisse, keine absoluten/Traversal-/Backslash-Pfade, doppelten Member, Symlinks/Hardlinks oder Special-Files. Credential-Markerprüfung ohne Treffer; keine Credential-Dateien übernommen. Die 19 Source-Payloads entsprechen exakt den Patch-Dateien. Validierung und Patch-Reverse-Roundtrip erfolgten außerhalb des aktiven Checkouts; **kein** Entpacken in den Repository-Root.

Alle rekonstruierten Altdateien stimmen bytegenau mit dem aktuellen Flutter-Ausgangsstand überein; vorhandene OIP-004-Baseline-Hashes bestätigen die OIP-003-Herkunft. Klassifikation: alle 19 ohne Konflikt integrierbar, davon 3 neue Dateien. Bereits vorhanden/manuell abzugleichen/nicht zulässig/nicht mehr anwendbar: jeweils 0. Einzelne Übernahme nach Prüfung, keine Komplettüberschreibung. [Provenienz und Einzelhashes](evidence/oip005/provenance.json), [vollständiger Handoff-Bericht](evidence/oip005/OIP_004_UI_HANDOFF.md).

### Tatsächlich integrierte Flutter-Dateien

Unter `apps/flutter/`:

```text
lib/app/app.dart
lib/app/controller.dart
lib/design_system/theme.dart
lib/features/overview.dart
lib/features/devices.dart
lib/features/network.dart
lib/features/opcua.dart
lib/features/diagnostics.dart
lib/models/contracts.dart
lib/services/api.dart
lib/widgets/components.dart
lib/widgets/trend.dart
test/contracts_test.dart
test/support.dart
test/widget_test.dart
test/trend_test.dart                  (neu)
test/ui_regression_test.dart          (neu)
test/browser_oip004.mjs               (neu)
web/index.html
```

UI-Evidenz wurde ausschließlich in das neue `docs/evidence/oip004-ui` übernommen. Originale OIP-003-/OIP-004-Core-Evidenz blieb erhalten. Keine Rust-, Schema-, Cargo-, CI-, PKI- oder Datenbankdatei aus dem UI-Paket angewandt. `pubspec.yaml`, `pubspec.lock` und native Projektdateien sind unverändert.

## Integrationskorrekturen und Agent-first Core

Es gab keinen Patchkonflikt. Notwendige fachliche Abgleiche nach erfolgreicher Paketübernahme:

1. Transportneutrale Read-DTOs und QueueHealth nach `oip-core` verschoben; alte Server-Typnamen re-exportiert. Dreizehn reale externe Capabilities mit typisierten Requests/Outputs/Fehlern, Permission-Mengen, Source-Scope und Audit-Port. Die bestehende OIP-004-Ingestion, Migrationen, Writer, Adapter und Lifecycle wurden erhalten.
2. Gemeinsamer `ApplicationServices`-Service extrahiert: REST/SSE und spätere MCP-Adapter verwenden dieselben Geräte-/Event-/Node-/Simulationsregeln. Axum enthält nur Transport-Parsing/-Status/-Serialisierung. Keine neue Crate oder Package-Abhängigkeit.
3. Additive `primary_source_id`, `data_source_id` und `is_faulted`; Fault-/Alarmklassifikation pro Quelle in Rust. Kein Vermischen der zwei Temperaturserien oder aktiven Alarme. Source-gebundene Gerätedetailabfragen bleiben source-/entity-gefiltert.
4. UI-Trend nimmt nur frische Beobachtungen der Primärquelle auf. Stale Restore-Werte sind keine neuen Messpunkte. Source-/Clock-Epochen und REST-Resync beginnen ein neues Anzeigefenster; keine Replay-Annahme.
5. Ein geöffneter Gerätedialog folgt aktuellen Backendwerten ohne wiederholte Detail-Requests pro Snapshot. Freshness von Quelle B wird nicht durch den Ausfall der Primärquelle A überschrieben. Selektierbare Fakten erhalten ein explizites Semantics-Label; ihre zuvor nur visuell gerenderten Werte sind dadurch auch zugänglich und verifizierbar.
6. Diagnostics liest bevorzugt source-kontextuelle Ereignisrecords und behandelt DataLoss als echten Zähler bei unbekanntem Intervall. Alte Eventarray-Kompatibilität bleibt. Netzwerkzonen werden gezählt; keine fiktive Telemetrie oder produktive Diagnose.

[Architektur, Grenzen und präziser OIP-006-Auftrag](architecture/oip-005-agent-first-foundation.md), [vollständiges Capability-Inventar](architecture/oip-capability-inventory.md). Das Inventar unterscheidet reale lokale Capabilities von internen Ports, partiellen Historien-/Adminfunktionen und nicht unterstützten OT-Operationen. Noch kein MCP-Server, Remote-Endpoint oder externer Agent.

## Tatsächlich ausgeführte Tests

Werkzeuge: Rust 1.93.0, Flutter 3.22.0 / Dart 3.4.0, Xcode 26.6, Node 23.3.0, Chrome 156.0.8078.80, Python 3.10.1 plus vorhandene aktuelle SQLite-CLI. Keine globalen Tooländerungen.

| Prüfung | Ergebnis | Nachweis |
|---|---|---|
| UI-Paket vor manuellen Korrekturen: Dart-Format/analyze/Tests | PASS, **25 Tests** | `flutter-*-baseline.log` unter evidence/oip005 |
| Rust fmt | PASS | [fmt.log](evidence/oip005/fmt.log) |
| Rust check Workspace/all-targets | PASS | [check.log](evidence/oip005/check.log) |
| Rust clippy Workspace/all-targets, warnings denied | PASS | [clippy.log](evidence/oip005/clippy.log) |
| Rust Workspace-Tests | PASS, **78 Tests** | [rust-workspace.log](evidence/oip005/rust-workspace.log) |
| Storage-/Recovery-/Reliability-Tests | PASS, enthalten: **11 Storage**, **12 Reliability** | Workspace-Log; kein separater künstlicher Gesamttestzähler |
| Neue Service-/Autorisierungstests | PASS, **5 Server- + 2 Core-Tests** | [capabilities.log](evidence/oip005/capabilities.log) und Workspace-Log |
| Rust Workspace-Build | PASS | [build.log](evidence/oip005/build.log) |
| OPC UA ohne Defaultbackend: check/clippy | PASS | `no-default-{check,clippy}.log` |
| Nur open62541: check/clippy/Tests | PASS, **2 Tests** | `open-only-{check,clippy,tests}.log` |
| Beide Backends: clippy/Interoperabilität | PASS, **36 Tests** | [interop-tests.log](evidence/oip005/interop-tests.log), `interop-clippy.log` |
| cargo-deny advisories/licenses/bans/sources | PASS mit unveränderten Advisory-Ausnahmen | [deny.log](evidence/oip005/deny.log), keine Security-Behebung |
| Headless-E2E des aktuellen Cores | PASS, **7 Phasen**, ohne Flutter | [Report](evidence/oip005/headless/report.json), [Log](evidence/oip005/headless-console.log) |
| Dart-Formatcheck, 0 Änderungen | PASS | [flutter-format-check.log](evidence/oip005/flutter-format-check.log) |
| flutter analyze | PASS, 0 Issues | [flutter-analyze.log](evidence/oip005/flutter-analyze.log) |
| Flutter-Tests | PASS, **29 Tests** | [flutter-tests.log](evidence/oip005/flutter-tests.log) |
| Flutter Web Release, lokale CanvasKit-Ressourcen | PASS | [flutter-web-build.log](evidence/oip005/flutter-web-build.log) |
| Browser-Fachregression | PASS, **15 Prüfungen**, keine externen Requests/unerwarteten Browserfehler | [Browserreport](evidence/oip005/browser/browser-verification.json) |
| Zwei Quellen + integrierte Flutter-Web-App | PASS, **5 zusammenhängende Phasen A–E** | [Report](evidence/oip005/integration-ui/report.json), [Log](evidence/oip005/integration-ui-console.log) |
| Native macOS-Integration mit endgültigem UI-Stand | PASS, **1 Test**, Sensoralarm und Reconnect | [macos-integration.log](evidence/oip005/macos-integration.log) |
| Architektur-DAG und Domain-Abhängigkeiten | PASS, acht Mitglieder azyklisch, Core nur serde/thiserror | [architecture-check.json](evidence/oip005/architecture-check.json) |
| Source-/Design-/Package-Integrität | PASS | [integrity.json](evidence/oip005/integrity.json) |

Die Testgruppen überlappen; insbesondere sind 36 Interop-Tests nicht 36 zusätzliche eindeutige Tests zum Workspace-Lauf. Das Web-Build meldet den vorhandenen Cupertino-Font-Hinweis; der Build ist erfolgreich. Browserprüfungen zeigen keine dadurch fehlenden Controls oder unerwarteten Fehler. Es wurden keine Packages allein zum Unterdrücken der Meldung ergänzt.

Neue Tests belegen: direkte Rust-Service-/REST-Semantik, fehlende Grants, Source-Isolation, Verweigerung globaler Aggregate bei Source-Scope, Discovery nach Permissions, typisierte Fehler, unbekannte Schemafelder/Operationen, Audit-Denial/Start/Ergebnis und Fail-closed vor Wirkung sowie Redaktion unbekannter vom Aufrufer gelieferter Audit-Ziele. Ein fehlgeschlagenes Abschluss-Audit wird ausdrücklich als unbestätigte Wirkung behandelt. Flutter-Tests sichern Primärquellenzuordnung, keine gemischten Trends, Stale-Restore, Clock-Reset, kontextuelle Verlustereignisse und den offenen source-spezifischen Gerätedialog.

Entwicklungsfehlläufe wurden behoben, nicht als PASS umgedeutet: Ein erster neuer Browser-Locator suchte einen Namen als isoliertes Textfeld statt innerhalb einer zusammengeführten Gerätezeile. Weitere Prüfungen offenbarten fehlende Web-Semantics für SelectableText-Werte; die Werte waren im Screenshot korrekt sichtbar. Diese Accessibility-Lücke sowie die tatsächlich source-übergreifende Freshness-Regel wurden korrigiert und anschließend automatisiert sowie visuell erneut geprüft. Ein Vorher-Bild liegt unter `evidence/oip005/development`; maßgeblich sind die final verlinkten PASS-Reports.

## Zusammenhängender End-to-End-Nachweis

**A — Headless:** Der bestehende OIP-004-Akzeptanztest wurde mit separatem Evidenzpfad erneut ausgeführt. Zwei echte Simulatorprozesse mit Seeds 42/77, eigene IDs/Ports, Core `--no-web`; validierte Werte in SQLite, REST und SSE. Beide Quellen unabhängig offline/reconnect, langsamer SSE-Client ohne globale Blockierung, kontrollierter Neustart mit stale/unknown Restore und SIGKILL bei gesperrter Ingestion. SQLite quick_check ok, keine doppelten Observation-Keys, Run-Journal erkennt Unterbrechung.

**B — Flutter:** Eine kontrollierte äquivalente Instanz mit denselben zwei Source-IDs/Seeds und aktuellem Rust-Build liefert den tatsächlichen Flutter-Web-Release aus. Overview, Devices, Network & VPN, OPC UA und Diagnostics werden geöffnet. Nur registrierte Quellen, reale Adapterwerte, fehlende physische Links/Diagnosen bleiben leer. OPC-UA-Read und Source-Provenienz werden über die tatsächliche API bestätigt.

**C — Fehlerisolation:** A kontrolliert beendet, A disconnected/degraded/stale, B accepted-Zähler und Persistenz laufen weiter. Flutter zeigt A degradiert/veraltet und B weiterhin aktuell. REST und vollständiger SSE-Snapshot stimmen über Quellverbindungen/Core-Degraded-Zustand überein. Gerätedetail B enthält ausschließlich Source B. Diagnostics zeigt `Quelle: sim-a` für die tatsächlichen Collection-Ereignisse.

**D — Recovery:** A am selben Endpoint neu gestartet. Core kehrt zu Ready zurück, neue empfangene Observations werden frisch, SQLite enthält die zugehörige Datenlücke. Flutter aktualisiert; keine aus gespeicherten Werten erzeugte künstliche Freshness.

**E — Neustart:** Core kontrolliert gestoppt; beide Simulatoren aus. Neustart mit demselben Bestand: Anzahl unverändert, gespeicherte Werte stale, Reachability unknown und letzte Runtime-Empfangszeit null. Flutter reconnectet und zeigt stale. Erst nach tatsächlichem Quellenstart folgen neue Werte/Ready/Live. Bestand wächst ohne doppelte Observation-Keys, SQLite quick_check ok. Abschließend kontrollierter Shutdown der eigenen Testprozesse.

**F — Native macOS:** Unveränderter vorhandener Integrationstest auf nativer Flutter-App gegen eine kontrollierte aktuelle lokale Demo-Instanz. Tatsächlicher Sensoralarm und Offline/Reconnect bestanden. Browser-Fachregression und nativer Test wechseln Szenarien und wurden deshalb auf dieser Instanz nacheinander ausgeführt.

### Tatsächliche Screenshots

[Zwei Quellen im Overview](evidence/oip005/integration-ui/overview-two-sources.png), [Quelle A offline](evidence/oip005/integration-ui/source-a-offline.png), [Quelle B weiter aktuell](evidence/oip005/integration-ui/source-b-still-fresh.png), [dokumentierte Quellereignisse](evidence/oip005/integration-ui/source-a-gap.png), [stale nach Restore](evidence/oip005/integration-ui/core-restored-stale.png), [live nach Neustart](evidence/oip005/integration-ui/core-restarted-live.png).

Die 15 Browser-Fachprüfungen decken Navigation, Suche/Filter/Details, Topologie, 1.000 Nodes mit Pagination, Sensoralarm, Diagnosegrenzen, Socket-Ausfall und Browser-Reconnect ab. Alle fünf Seiten sind bei Desktop, 834×1112, 390×844 und 320×740 navigiert. Die 29 Flutter-Tests enthalten responsive Größen von 320 bis 1920 px. Aktuelle Screenshots/Tests ersetzen keinen Langzeit- oder industriellen Lasttest.

## Exakte lokale Startbefehle

Drei Terminals für zwei Quellen und Core. Bestehende Ports müssen frei sein; keinen fremden Prozess dafür beenden.

```sh
cd /Users/benny/Code/open-industrial-platform
cargo build --workspace
```

Terminal A:

```sh
cd /Users/benny/Code/open-industrial-platform
target/debug/oip-simulated-server --port 14841 --seed 42 --tick-ms 250
```

Terminal B:

```sh
cd /Users/benny/Code/open-industrial-platform
target/debug/oip-simulated-server --port 14842 --seed 77 --tick-ms 250
```

Core vollständig ohne Flutter:

```sh
cd /Users/benny/Code/open-industrial-platform
target/debug/oip-server --config examples/core-local.json --no-web
```

```sh
curl --fail http://127.0.0.1:18084/api/v1/core/health
curl --fail http://127.0.0.1:18084/api/v1/sources
curl --fail http://127.0.0.1:18084/api/v1/devices
curl --fail 'http://127.0.0.1:18084/api/v1/metrics/current?source=sim-b'
curl --fail http://127.0.0.1:18084/api/v1/events
curl -N http://127.0.0.1:18084/api/v1/stream
```

Für dieselbe Zweiquellen-Anwendung **mit** Flutter zunächst bauen:

```sh
cd /Users/benny/Code/open-industrial-platform/apps/flutter
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
cd ../..
target/debug/oip-server --config examples/core-local.json --web-dir apps/flutter/build/web
```

Browser `http://127.0.0.1:18084`. Diese Core-Startvariante ersetzt den Headless-Core-Prozess, nicht parallel denselben SQLite-Bestand öffnen. Ctrl+C beendet kontrolliert. `oip-core.sqlite` für Wiederanlauf erhalten. IDs/Endpoint-Bindings nicht still umbenennen.

Alternatives explizites Single-Source-Demoprofil für vorhandene Szenario-/Native-Tests:

```sh
cd /Users/benny/Code/open-industrial-platform
target/debug/oip-server --demo --port 18405 --opcua-port 14845 --database target/oip005-ui-demo.sqlite
```

## Exakte Wiederholungsbefehle

Vom Repository-Root, vorhandene lokale Toolchains verwenden:

```sh
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace -- --test-threads=1
cargo check -p oip-opcua --no-default-features --all-targets
cargo clippy -p oip-opcua --no-default-features --all-targets -- -D warnings
cargo check -p oip-opcua --no-default-features --features open62541-backend --all-targets
cargo clippy -p oip-opcua --no-default-features --features open62541-backend --all-targets -- -D warnings
cargo test -p oip-opcua --no-default-features --features open62541-backend -- --test-threads=1
cargo clippy -p oip-opcua --features open62541-backend --all-targets -- -D warnings
cargo test -p oip-opcua --features open62541-backend -- --test-threads=1
target/oip-002-tools/bin/cargo-deny check advisories licenses bans sources
cargo build --workspace
OIP_EVIDENCE_DIR=docs/evidence/oip005/headless python3 tests/oip004/acceptance.py
node tests/oip005/browser_integration.mjs
cd apps/flutter
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test --reporter expanded
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
```

Die vorhandene cargo-deny-Binary liegt im OIP-002-Toolverzeichnis; eine andere Maschine benötigt ein separat vorhandenes `cargo deny`. Aktuelle SQLite-CLI alternativ über `OIP_SQLITE_CLI` setzen; das alte Host-Python benötigt sie wegen SQLite STRICT. Browserrunner benötigt die vorhandene Playwright-Installation aus `tests/oip003/node_modules` und Chrome; `PLAYWRIGHT_MODULE`, `CHROME_PATH` können passende lokale Pfade setzen. Keine versteckten Runtime-Cloud-Abhängigkeiten.

Mit laufendem separatem Demo-Server auf 18405, diese beiden Läufe **nacheinander**:

```sh
cd /Users/benny/Code/open-industrial-platform/apps/flutter
OIP_URL=http://127.0.0.1:18405 OIP_EVIDENCE_DIR=../../docs/evidence/oip005/browser PLAYWRIGHT_MODULE=/Users/benny/Code/open-industrial-platform/tests/oip003/node_modules/playwright/index.mjs node test/browser_oip004.mjs
flutter test integration_test/live_dashboard_test.dart -d macos --dart-define=OIP_API_URL=http://127.0.0.1:18405 --reporter expanded
```

## Security, Grenzen und NOT_TESTED

**RUSTSEC-2023-0071 bleibt offen und verhindert Produktion.** Die vorhandenen Advisory-Ausnahmen RUSTSEC-2023-0089 und RUSTSEC-2024-0449 bleiben ebenfalls unverändert. Ein bestandenes deny-Gate mit Ausnahmen ist keine Behebung. Kein öffentlicher Listener, produktiver Remote-Zugriff, MCP-Netzwerkzugang, Industriehardware, OPC-UA-Schreiben oder Maschinensteuerung. Keine Cloud-, Modell- oder Agentenabhängigkeit im Produkt.

Die aktuelle Host-Autorisierung ist ein expliziter lokaler Entwicklungsprincipal, keine produktive Identität. Capability-/Source-Prüfungen sind real getestet; Remote-Auth, Tenant-Scope und dauerhaftes Audit fehlen. SSE liefert Vollzustände ohne Replay; 100 Kontrollereignisse sind keine vollständige Historien-API. Es gibt keine behauptete Exactly-once-Garantie.

Ein Core-Prozess pro SQLite-Bestand; kein dauerhafter Ingestion-Spool oder Multi-Prozess-Writer-Lease. Unbestätigte In-flight-Daten können bei SIGKILL fehlen. Physische Netzwerktopologie, VPN-Telemetrie, Hostmessungen, produktive Diagnostik und Runtime-Administration bleiben nicht implementiert. Der UI-OPC-UA-Browser ist noch auf die Primärquelle ausgerichtet; kein neuer Source-Konfigurationsworkflow wurde ergänzt.

NOT_TESTED: Remote-CI-Matrix, native Windows/Linux/Android/iOS-Ausführung, Safari/Firefox/Edge und reale Mobilbrowser, physischer Stromausfall/Speichermediumfehler, Langzeit-/Leak-/industrienahe Lasttests, produktive Remote-Authentifizierung, produktives dauerhaftes Audit und MCP-Protokollinteroperabilität. Für die letzten drei existiert in OIP-005 absichtlich keine entsprechende Runtime. Der echte lokale Prozess-Crash, Source-Ausfall und Wiederanlauf wurden getestet.

HTML-Designreferenz vor/nach Arbeit identisch:

`bd9f9d8696ed48676055ee9a2cd0afb29e6c3d59e0945e662d925306f73c753e`.

## Abschluss-Gates

| Gate | Ergebnis | Begründung |
|---|---|---|
| 1 Provenienz | PASS | extern verifizierte kanonische Baseline, beide Archivkopien geprüft, vollständiger Manifest-/Pfad-/Roundtrip-Abgleich |
| 2 Integration | PASS | 19 kontrollierte UI-Deltas, keine Core-Dateien aus Paket; notwendige kompatible Abgleiche dokumentiert |
| 3 Funktionalität | PASS | tatsächlicher Simulator → Rust → SQLite → REST/SSE → Flutter-Fluss, fünf Ansichten, native API-Verbindung |
| 4 Reliability | PASS | getrennte Quellen, Isolation, Reconnect, Gaps, stale Restore, kontrollierter Shutdown und Crash-Recovery |
| 5 Regression | PASS | ausgeführte Rust-/Interop-/Storage-/Flutter-/Browser-/Mac-Prüfungen; Plattformgrenzen explizit NOT_TESTED |
| 6 Agent-first Foundation | PASS | reales typisiertes CapabilityService-Interface, Autorisierung/Audit-Grenze, vollständiges ehrliches Inventar und umsetzbarer OIP-006-Auftrag ohne parallele Geschäftslogik |
| 7 Isolation | PASS | nur autorisierte OIP-Änderungen und angeforderte externe Sicherung; kein Commit, Push, Deployment oder produktiver Netzwerkzugriff; Referenz unverändert |

OIP_005_INTEGRATION_PASS
