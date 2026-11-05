# OIP-004 — Implementation und Verifikation

Datum: 2026-11-04. Testhost: macOS arm64, Rust 1.93.0, Flutter 3.22.0/Dart 3.4.0, Xcode 26.6, Chrome 156.0.8078.80. Keine Produktionsfreigabe.

## Baseline und überprüfte Vorgängerergebnisse

Vor Änderungen wurden Workspace, alle acht Crates, Domain/Application, Adapter, SQLite, Server, Simulation, Tests, CI, ADR 0001/0002 und die drei vorhandenen Verifikationsberichte geprüft. Alle vorhandenen Repository-Dateien waren untracked. Eine unabhängige Baseline wurde unter `target/oip004-baseline` gesichert; [75 Dateihashes](evidence/oip004/baseline-hashes.json) ermöglichen den Vergleich ohne Git-Commit. Keine vorhandene Datei dieser Baseline fehlt. Kein Commit, Push, Deployment oder öffentlicher Port wurde angelegt.

Die OIP-003-Meldungen sind durch die vorhandenen damaligen Logs nachvollziehbar, ersetzen aber keine neue Ausführung. Vor OIP-004 wurden [57 Rust-Tests](evidence/oip004/baseline-rust.log), [9 Flutter-Tests](evidence/oip004/baseline-flutter-tests.log) und Flutter analyze erneut erfolgreich ausgeführt. Interop, Browser und native Integration wurden zusätzlich nach der Implementierung erneut getestet. Die ursprüngliche OIP-003-Evidenz blieb erhalten.

Bereits vorher vorhanden: deterministischer Simulator, read-only OPC UA mit Security-Profilen, typisierte Envelopes, Quality/Provenienz, idempotente SQLite-Persistenz und Migration 1, die sieben bestehenden API-Lesepfade, SSE und fünf Flutter-Ansichten. Neu sind deren modulare Orchestrierung, Fehlerisolation, Lifecycle/Health, Mehrquellenbetrieb, Backpressure-Evidenz, atomare aktuelle Checkpoints und zuverlässigerer Wiederanlauf. Agent/Gateway/Diagnostik-Crates bleiben Platzhalter. Details und Entscheidungen: [Core-Architektur](architecture/oip-004-modular-core.md).

## Verifikations-Gates

| Gate | Ergebnis | Nachweis |
|---|---|---|
| A Architektur | PASS | Infrastrukturfreier Application-Core, Repository-Port, unabhängige Adapterverträge; acht unveränderte Workspace-Mitglieder, azyklischer [Dependency-Graph](evidence/oip004/final-integrity.json) |
| B Funktion | PASS | Zwei echte lokale OPC-UA-Serverprozesse, unabhängige Sessions/Identitäten, SQLite → REST/SSE, vollständiger Headless-Betrieb ohne Webverzeichnis/Flutter |
| C Integrität | PASS | Duplikate, Out-of-order, ungültige Typen/Zeitstempel/NaN/fehlende Werte, atomarer Rollback, wiederhergestellte stale Checkpoints, SIGKILL und SQLite quick_check |
| D Reliability | PASS | Isolation A/B, beide offline, unabhängiger Reconnect, kontrollierter Shutdown/Run-Journal, begrenzte Queues, tatsächlicher Overflow mit persistierter Verlustmeldung, DB-Sperre und Recovery |
| E Regression | PASS | fmt/check/clippy/build, 71 Workspace-Tests, 36 Interop-Tests, 2 open62541-only-Tests, Flutter 9, Web-Build, 15 Browser-Prüfungen, native macOS-Integration |

## Ausgeführte Prüfungen

| Prüfung | Ergebnis / Evidenz |
|---|---|
| `cargo fmt --all -- --check` | PASS, [fmt.log](evidence/oip004/fmt.log) |
| `cargo check --workspace --all-targets` | PASS, [check.log](evidence/oip004/check.log) |
| `cargo clippy --workspace --all-targets -- -D warnings` | PASS, [clippy.log](evidence/oip004/clippy.log) |
| `cargo build --workspace` | PASS, [build.log](evidence/oip004/build.log) |
| `cargo test --workspace -- --test-threads=1` | **71 PASS**, darunter 34 bestehende OPC-UA-, 6 API-, 12 neue Reliability- und 11 Storage-Tests; [Log](evidence/oip004/rust-workspace.log) |
| Kein Default-Backend: check + clippy | PASS, `no-default-check.log`, `no-default-clippy.log` |
| Nur open62541: check + clippy + Tests | PASS, **2 Tests**, `open-only-{check,clippy,test}.log` |
| Beide Backends: clippy + Interop-Tests | PASS, **36 Tests**, [Interop-Log](evidence/oip004/interop-test.log), `interop-clippy.log` |
| cargo-deny advisories/licenses/bans/sources | PASS **mit den unveränderten drei Advisory-Ausnahmen**; Duplicate-Warnungen, [deny.log](evidence/oip004/deny.log). Keine Behebung des RSA-Risikos |
| `flutter analyze` | PASS, [Log](evidence/oip004/flutter-analyze.log) |
| `flutter test --reporter expanded` | **9 PASS**, [Log](evidence/oip004/flutter-tests.log) |
| Flutter Web Release Build, lokale CanvasKit-Ressourcen | PASS, [Log](evidence/oip004/flutter-web-build.log) |
| Browser gegen aktuellen Rust-Server | **15 PASS**, keine externen Requests, keine unerwarteten Browserfehler; [JSON](evidence/oip004/browser/browser-verification.json) |
| Nativer macOS-Integrationstest gegen aktuellen Rust-Server | PASS, [Log](evidence/oip004/macos-integration.log) |
| Zusammenhängender API-/Core-E2E-Test | PASS, [Phasenreport](evidence/oip004/acceptance/report.json), [Konsolenlog](evidence/oip004/acceptance-console.log) |

Die Testzahlen überlappen: Die 36 Interop-Tests enthalten Tests, die auch im Default-Lauf enthalten sind. Sie werden nicht zu einer künstlichen Gesamtsumme addiert. Lokal ausführbare CI-Schritte wurden ausgeführt; der neue Headless-Akzeptanzlauf ist zusätzlich im Linux-x86_64-CI-Job hinterlegt. Die Remote-CI-Matrix wurde nicht gestartet.

Die 12 neuen Reliability-Tests decken Normalbetrieb, getrennte Ordnung/Idempotenz/Freshness, ungültige Eingaben, Restart mit zurückgesetzter Simulator-Uhr, reale SQLite-Schreibsperre und Recovery, sichtbare Queue-Überlast, fehlgeschlagenen Shutdown mit uncommitted-Zähler, Drain zugelassener Daten, langsamen SSE-Client/Resync, Adapter-Panic-Isolation, falsche Konfiguration vor Ressourcenstart, echten Adapter-Overflow, Runtime-Verlust und Uhr-Rücksprung bei Recovery ab. Mehrere Anforderungen werden innerhalb eines Tests kombiniert. Tests mit kontrollierter Domain-Zeit sind deterministisch; tatsächliche Netzwerk-/Prozessprüfungen verwenden begrenzte Wait-Bedingungen. Sie setzen kein willkürliches Laufzeitlimit für normalen Core-Betrieb.

## Abschließender zusammenhängender Akzeptanzlauf

Ausgeführt nach den letzten Rust-Änderungen mit `python3 tests/oip004/acceptance.py`. Das Skript startet und beendet nur eigene lokale Prozesse und erzeugt einen eigenen SQLite-Bestand. Es importiert weder Flutter noch Browserbibliotheken.

1. **Start:** Zwei Simulatorprozesse mit verschiedenen Ports/Seeds (42/77); Core `--config ... --no-web`. Beide Quellen connected/fresh, Lifecycle Ready. `/` bleibt 404. Quelle/Provenienz im API- und SQLite-Bestand getrennt.
2. **Ingestion:** Werte beider Quellen durch Adapter/Application bis SQLite; REST bestätigt Quelle/Seed, SSE liefert vollständigen Snapshot und echte Event-ID. Ein TCP-SSE-Client liest nicht weiter; Quelle B und Persistenz laufen dennoch fort.
3. **Isolation:** Simulator A kontrolliert per SIGINT beendet. A disconnected, Core Degraded/teilweise ready, B sammelt weiter. Danach beide offline: live=true, ready=false, kein letzter Wert Fresh.
4. **Recovery:** A und B separat neu gestartet. Tatsächliche neue Werte und Reconnected-Ereignisse, persistierte quellbezogene Datenlücken, Rückkehr zu Ready.
5. **Core-Neustart:** Core mit offenen SSE-Clients heruntergefahren. Adapter/Writer sauber abgeschlossen, `uncommitted=0`; langsame HTTP-Ausgabe gegebenenfalls separat als forced-close protokolliert. Bei Neustart mit zunächst ausgeschalteten Simulatoren bleiben gespeicherte Werte Stale, Reachability Unknown, letzte Runtime-Empfangszeit null. Nach Quellenstart wird Beobachtung fortgesetzt, identische Redelivery erhöht Duplikatzähler ohne doppelte Observation-Keys. Alte SSE-ID erhält neue Run-ID und explizite Resynchronisierung.
6. **Crash während Ingestion:** SQLite-Schreibtransaktion absichtlich gesperrt, Core per SIGKILL beendet. Neustart markiert vorherigen Run interrupted; `PRAGMA quick_check` ist ok, keine doppelten Observation-Keys; beide Quellen liefern weiter. Letzter Abschluss wieder kontrolliert.
7. **Regression:** Workspace-/Interop-/SQLite-Tests sowie Web-, Browser- und macOS-Prüfungen gegen den aktuellen Backendstand ausgeführt.

Der maschinenlesbare Report enthält Prozessargumente, konkrete Quellzustände, SQLite-Zähler, Datenlücken, Run-Journal und Shutdown-Ergebnisse. Prozesslogs liegen daneben. `target/oip004-acceptance-*/evidence.sqlite` enthält den jeweils angegebenen Prüfbestand. Alte Entwicklungsfehlläufe sind keine finalen Nachweise; die hier verlinkten finalen Logs/Reports sind maßgeblich.

## Flutter-Schutz und tatsächliche Screenshots

[Integritätsvergleich](evidence/oip004/final-integrity.json): alle 22 geprüften Flutter-lib/test/integration_test-Dateien unverändert, keine neuen Flutter-Packages oder Ansichten. Die Browser-Testhilfe erhielt nur einen separaten Evidenz-Ausgabepfad und Tastaturaktivierung für den zweiten Theme-Wechsel: ein Hover-Tooltip überlagerte den automatisierten Pointer-Hit-Test. Keine Produktänderung hierfür. Der erste fehlgeschlagene Browser-Versuch ist unter `evidence/oip004/development` nachvollziehbar; der vollständige erneute Lauf bestand alle 15 Prüfungen.

Tatsächliche Anwendung gegen aktuellen Rust-Server: [Desktop](evidence/oip004/browser/overview-desktop.png), [Tablet](evidence/oip004/browser/tablet-overview.png), [Mobile 320 px](evidence/oip004/browser/narrow-overview.png), [OPC-UA-Browser](evidence/oip004/browser/opcua-bulk.png), [Sensoralarm](evidence/oip004/browser/sensor-alarm-live.png), [Reconnect](evidence/oip004/browser/reconnected.png). Alle fünf Ansichten wurden bei 1440×1000, 834×1112, 390×844 und 320×740 navigiert; keine gemeldeten Overflows. Messungen dieses einzelnen lokalen Browserlaufs: erster Live-Zustand 606 ms, Node-Seite 75 ms, Alarm bis UI 651 ms; keine Performance-SLA oder Lasttestaussage.

Designreferenz vor und nach der Arbeit unverändert:

`bd9f9d8696ed48676055ee9a2cd0afb29e6c3d59e0945e662d925306f73c753e`

## Exakte lokale Startbefehle

Vom Repository-Verzeichnis aus, drei Terminals. Ausschließlich Loopback-Simulation:

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

Terminal Core (kein Flutter nötig):

```sh
cd /Users/benny/Code/open-industrial-platform
target/debug/oip-server --config examples/core-local.json --no-web
```

```sh
curl --fail http://127.0.0.1:18084/api/v1/core/health
curl --fail http://127.0.0.1:18084/api/v1/sources
curl --fail http://127.0.0.1:18084/api/v1/metrics/current
curl --fail http://127.0.0.1:18084/api/v1/events
curl -N http://127.0.0.1:18084/api/v1/stream
```

Ctrl+C beendet die jeweiligen Prozesse. Quelle A stoppen und am selben Port mit identischem Seed erneut starten, während B läuft. Für State-Recovery nur den Core stoppen/neu starten und `oip-core.sqlite` erhalten. Quellen-IDs/Endpoint-Bindings einer bestehenden Datenbank nicht umbenennen.

Unverändertes einzelnes UI-Demoprofil, alternativ zu den drei Terminals:

```sh
cd /Users/benny/Code/open-industrial-platform/apps/flutter
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
cd ../..
target/debug/oip-server --demo --port 18404 --opcua-port 14844 --database target/oip004-ui-demo.sqlite
```

Browser: `http://127.0.0.1:18404`. Der Headless-Core benötigt weder Flutter-SDK noch ein Web-Build. Ein eingefrorener Single-Source-UI-Client ist keine Mehrquellen-Konfigurationsoberfläche.

## Exakte Wiederholungsbefehle

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
python3 tests/oip004/acceptance.py
cd apps/flutter
flutter analyze
flutter test --reporter expanded
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
```

cargo-deny liegt bereits repository-lokal unter dem genannten OIP-002-Pfad; auf einer anderen Maschine wird ein verfügbares `cargo deny` benötigt. Es wurden keine globalen Tools installiert. Das Python-Skript benötigt SQLite ≥3.37 (STRICT): vorzugsweise aktuelle Python-stdlib, andernfalls eine vorhandene SQLite-CLI, optional `OIP_SQLITE_CLI=/pfad/sqlite3`. Der Host hatte Python 3.10.1 mit alter SQLite-Version; deshalb wurde die vorhandene Homebrew-CLI verwendet.

Mit laufendem separaten UI-Demoprofil auf 18404, Browser und macOS-Test nacheinander (beide wechseln Szenarien):

```sh
cd /Users/benny/Code/open-industrial-platform/tests/oip003
OIP_URL=http://127.0.0.1:18404 OIP_EVIDENCE_DIR=../../docs/evidence/oip004/browser npm test
cd ../../apps/flutter
flutter test integration_test/live_dashboard_test.dart -d macos --dart-define=OIP_API_URL=http://127.0.0.1:18404 --reporter expanded
```

Der vorhandene Browserrunner benötigt seine vorhandenen npm-Abhängigkeiten und Chrome; `CHROME_PATH` kann den ausführbaren Pfad überschreiben. Keine Cloud erforderlich.

## Verbleibende Grenzen und nächste Phase

- **RUSTSEC-2023-0071 bleibt offen und verhindert Produktion.** Die Ausnahmen 2023-0089 und 2024-0449 bleiben ebenfalls unverändert. Kein Audit-Ergebnis hebt diese Risiken auf.
- Keine produktive Remote-Freigabe, echte Industriehardware, Schreiboperationen oder Zertifikatsumgehung. Alle Verbindungen lokal simuliert.
- SSE liefert koaleszierende vollständige Zustände, kein lückenloses Event-Replay. REST-Resync ist erforderlich; 100 Kontrollereignisse sind keine vollständige Historien-API.
- Ein Core-Prozess pro SQLite-Datenbank. Kein Multi-Prozess-Writer-Lease, keine dauerhafte Ingestion-Spool. Unbestätigte In-flight-Daten bei SIGKILL können fehlen; es wird keine Exactly-once-Garantie behauptet.
- Historische SQL-Aggregation und Langzeit-Retention sind noch nicht für unbegrenzt große Bestände optimiert. Queue-/Störungstests sind kein industrieller Dauertest.
- NOT_TESTED: Remote-CI-Ausführung, native Linux-/Windows-/Android-/iOS-Läufe, physischer Stromausfall, defektes Speichermedium, reales Netzwerk/Hardware (außerhalb des zulässigen Scopes). Prozess-Crash und lokale Socket-Ausfälle wurden tatsächlich getestet.
- Nächste Phase: Security-Stack/RSA-Risiko beheben, Langzeitbetrieb und Retention messen, Konfigurationsmigration und optional dauerhafte Admission/Replay-Verträge anhand konkreten Bedarfs spezifizieren. Keine UI-Erweiterung aus OIP-004.

OIP_004_CORE_PASS
