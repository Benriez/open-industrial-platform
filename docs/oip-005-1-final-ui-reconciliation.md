# OIP-005.1 — Final UI Integration & Canonical Reconciliation

Datum: 2026-11-04. Ausschließlich lokale Simulation/Entwicklung. **OIP IS AGENT-FIRST BY DESIGN.** Keine Produktionsfreigabe.

## Ausgangszustand und Integrationsautorität

Die drei OIP-005-Berichte, die relevanten OIP-004-Core-/UI-Berichte, Handoff-Manifeste und die aktuelle Implementierung wurden geprüft. Branch weiterhin `main`, HEAD unborn, **0 tracked und 415 nicht ignorierte untracked Projektdateien**. Der aktuelle Source-Stand stimmt vollständig mit `docs/evidence/oip005/final-source-hashes.json` überein. Die ältere Baseline von 01:22 UTC wurde nur als ursprünglicher Provenienzanker verwendet, nicht als aktueller Stand.

Einzige Integrationsautorität: Core-Session `01a1a3b3-9469-7311-be9a-1218be181ebc`, Workstream OIP-005.1. Die UI-Session `ses_e5c15927effeK5cDlqK9FuEkuE` bleibt Zulieferer in ihrer isolierten Snapshot-Kopie. Andere bekannte OIP-Analyse-/Review-Sessions und die UI-Session waren in der verfügbaren lokalen Aktivliste nicht aktiv. Session-IDs, Workstreams, Verzeichnisse, Branch/Arbeitskopie, Autorität, Status und bekannte Zeitstempel: [sessions.json](evidence/oip005/reconciliation-005-1/sessions.json). Zusätzlich sichern Hashvergleiche vor Anwendung und zum Abschluss gegen Source-Drift ab. Es wird keine globale Schreibsperre für fremde Programme behauptet.

Ein vorhandener, vom Operator gestarteter alter lokaler Server auf Port 18080 wurde nicht verändert oder beendet. Alle neuen Prozessprüfungen verwenden eigene Loopback-Ports, Datenbanken und Prozess-IDs.

## G1 — Neue externe Baseline

Vor Integration wurde der gesamte aktuelle nicht ignorierte Projektbestand extern archiviert. Alle Archivdateien wurden unabhängig wieder gelesen und gegen das Inventar geprüft:

`/Users/benny/Documents/OIP-Handoffs/core-005-1-baseline-20261104T220739Z/oip005-project-baseline.tar.gz`

SHA-256:

`7be7a92c73fb32461c023de8c247b4875a8166fbb055bfb054e81badfba246ae`

415 Source-/Projekt-/Evidenzdateien, 15.214.426 Archivbytes. Das externe Verzeichnis enthält `inventory.json`, `baseline.json`, `git-status.txt`, `sessions.json` und den isolierten Reconciliation-Arbeitsbereich. 135.666 ignorierte Dateien wurden als Metadaten inventarisiert. Ignorierte Build-Caches, Dependencies, Runtime-Datenbanken, PKI und Credentials wurden nicht in ein übertragbares Source-Archiv aufgenommen; ihre Originale blieben erhalten. Kein Commit als künstliche Baseline, keine Bereinigung oder Löschung vorhandener Projektdateien.

[Baseline-Zusammenfassung](evidence/oip005/reconciliation-005-1/baseline.json), [abschließender Integritätsnachweis](evidence/oip005/reconciliation-005-1/final-integrity.json).

## G2 — Beide UI-Archive und sichere Validierung

| Revision | Tatsächlich geprüfter SHA-256 | Ablage / Behandlung |
|---|---|---|
| Bereits in OIP-005 integrierte UI | `2e657d4b9c28a6d8adc7aa55151a3fe5a2601e2fb01fc8894afb02fd2c91714a` | ursprüngliche dauerhafte Dateien unter `/Users/benny/Documents/OIP-Handoffs/ui-004/` unverändert erhalten |
| Finales UI-Handoff | `1986cb1061c8781f6d3462c7a3689d2b46530ac0bb18459d07fd32347399de82` | temporäre Kopie geprüft; unveränderte Kopie einschließlich identischem Bericht neu unter `/Users/benny/Documents/OIP-Handoffs/ui-004/final-1986cb1061c8/` abgelegt und erneut gehasht |

Das finale gzip/Tar-Archiv hat 128 Member, 112 manifestierte Dateien und 25 Flutter-Payload-Dateien. PASS: vollständiger Manifestbestand, alle Payload-/Patch-Hashes, kanonische relative Pfade, keine absoluten/Traversal-/Backslash-Pfade, doppelten Einträge, Symlinks, Hardlinks oder Special-Files, begrenzte Membergrößen, keine Credential-Marker. Alle Source-Payloads stimmen exakt mit der Patch-Dateiliste überein; ausschließlich `apps/flutter/**`, keine Rust-/Cargo-/Storage-/CI-Datei.

Die validierte Extraktion liegt ausschließlich außerhalb des aktiven Checkouts beim neuen Backup. Reverse-Patch und anschließender Forward-Patch wurden auf separaten Kopien ausgeführt: **25/25 bytegenaue Rundreise**. Die rekonstruierte ursprüngliche BASE stimmt mit dem unabhängig gehashten ursprünglichen OIP-003-Archiv überein (`56f79d98…`, exakter Hash im Provenienzreport). Kein Entpacken im Repository-Root und kein pauschales Anwenden des Patches gegen OURS.

[Finaler Lieferbericht](evidence/oip005/reconciliation-005-1/OIP_004_UI_HANDOFF_FINAL.md), [Lieferantenmanifest](evidence/oip005/reconciliation-005-1/supplier-SHA256SUMS), [Provenienz und Abgleich](evidence/oip005/reconciliation-005-1/reconciliation-plan.json).

Die 41 Flutter-Tests, 16 Browserchecks, 30 Captures und der native Test des Zulieferers wurden als historische Lieferantenevidenz erhalten. Alle 30 im responsiven Liefermanifest aufgeführten PNGs wurden zusätzlich auf vorhandene Hashes, gültige PNG-Struktur und passende dokumentierte Breiten geprüft: [30/30-Nachweis](evidence/oip005/reconciliation-005-1/supplier-captures-verified.json). Sie ersetzen die folgenden integrierten Prüfungen nicht.

## G3 — Vollständiger Drei-Wege-Abgleich

- **BASE:** ursprüngliche, per Reverse-Patch rekonstruierte und gegen das alte Source-Archiv bestätigte OIP-003-Basis; neue Dateien sind dort abwesend.
- **OURS:** bytegenau gesicherter aktueller OIP-005-Stand.
- **THEIRS:** vollständig manifestierter finaler Lieferstand `1986cb10…`.

Jede der 25 Dateien wurde verglichen. Gegen die ursprüngliche BASE ergeben sich 17 textuell überlappende Dateien, sechs einfache neue Änderungen und zwei bereits identische Dateien. Der ebenfalls hashgebundene ältere UI-Lieferstand `2e657d4b…` ist eine belegte gemeinsame Zwischenrevision: Seine Deltas wurden verwendet, um bereits gemeinsam integrierte Arbeit von den beiden verbleibenden Änderungslinien zu unterscheiden. Er ersetzt die ursprüngliche BASE-Prüfung nicht. Es wurde weder anhand von Zeitstempeln entschieden noch OURS/THEIRS pauschal bevorzugt.

Nach diesem Abgleich verbleiben **sechs tatsächliche Konfliktdateien**. Sie wurden einzeln fachlich zusammengeführt. Weitere vier Dateien besitzen kombinierte, textuell sauber zusammenführbare Reständerungen. Ergebnis: **25 abgeglichene Dateien, 22 aktualisierte Payload-Dateien, drei unverändert erhaltene Dateien, null ungelöste Konflikte**.

Alle folgenden Pfade sind relativ zu `apps/flutter/`. Die JSON-Datei enthält BASE-/OURS-/THEIRS-/Zwischenrevisions-/Endhashes pro Datei.

| Datei | Klassifikation / tatsächliche Auflösung |
|---|---|
| `README.md` | neue Lieferänderung; reproduzierbare Tests ergänzt, aktuelle isolierte Evidenzpfade dokumentiert |
| `lib/app/app.dart` | Lieferänderung ohne OIP-005-Restkonflikt; Ownership/Disposal, zugängliche Navigation und getrennte Fehler. Banner unterscheidet tatsächlich verlorenen UI-Transport von gestörter Primärquelle |
| `lib/app/controller.dart` | semantisch kompatibel zusammengeführt; neue strukturierte/Timeout-/Szenariofehler plus erhaltene Quellen-/Freshness-/Clock-/REST-Resync-Regeln, nullable Zeitstempel abgesichert |
| `lib/design_system/theme.dart` | Lieferänderung; Light-Statuskontraste und Statuslabels, kein Redesign |
| `lib/features/devices.dart` | Konflikt gelöst: source-spezifischer live aktualisierter Dialog und stabiler API-Future bleiben; neue Pagination, Standorte, Simulationsflags und kontrastgerechte Farben ergänzt |
| `lib/features/diagnostics.dart` | Konflikt gelöst: source-kontextuelle Records/DataLoss bleiben; Incident-Flags, öffentliche Fehler und einheitliche Core-Klassifikation zusammengeführt; ohne Demo-Control keine unmögliche Szenarioaufforderung |
| `lib/features/network.dart` | Lieferänderung; alle Gerätezeilen im Canvas, Zoom erhält Pan, API-Link-/Simulationsflags; keine erfundenen Verbindungen |
| `lib/features/opcua.dart` | Lieferänderung plus notwendiger Quellenabgleich: tatsächliches Response-Page-Limit, strukturierte Fehler; Live- und Cachewerte nur aus der kanonischen Primärquelle |
| `lib/features/overview.dart` | Konflikt gelöst: primärquellengebundene Temperatur erhalten; abgeleitete Zonen, korrekte Hardware-/Simulationslabels und registry-gebundene Incident-Darstellung |
| `lib/main.dart` | Lieferänderung; Produktions-App besitzt/disposed ihren Controller |
| `lib/models/contracts.dart` | semantisch zusammengeführt; defensive Werte/Units/Zeiten plus Source-IDs, Core-Fault-Flag, Primärbindung, Eventkontext und unbekanntes Verlustintervall erhalten |
| `lib/services/api.dart` | Konflikt gelöst: Records-vor-Legacy-Fallback innerhalb strukturierter Request-/Contract-Fehler; `DEMO_DISABLED` und URI-Basispfad erhalten |
| `lib/services/event_transport_web.dart` | Lieferänderung; named SSE-error von Transportverlust unterscheiden, Listener/Transport korrekt schließen |
| `lib/widgets/components.dart` | unverändert OURS: vorhandene OIP-005-Semantics für selektierbare Fakten erhalten; THEIRS hatte hier keine neue Änderung |
| `lib/widgets/trend.dart` | Konflikt gelöst: Quellen-/Entity-Unterbrechung zusammen mit nullable Timestamp- und Unknown-Zeitdarstellung |
| `test/contracts_test.dart` | Lieferänderung erhalten; Alarmtest verwendet tatsächliche OIP-005-Core-Klassifikation und prüft zusätzlich, dass rohe Metriken keine UI-Geschäftsregel umgehen |
| `test/support.dart` | kompatible Merge-Änderung; Source-/Primär-/Fault-Felder bleiben, zusätzliche Transport-/Page-/Disposal-Teststeuerung ergänzt |
| `test/ui_regression_test.dart` | kompatible Merge-Änderung; OIP-005-Source-Dialogtest und alle neuen Review-Regressionen erhalten |
| `test/trend_test.dart` | Lieferänderung; unbekannte Zeiten und bestehende Gap-Regeln geprüft |
| `test/browser_oip004.mjs` | Konflikt gelöst: CWD-unabhängige Navigation/Pfade und 16 echte Assertions plus expliziter separater Evidenzpfad |
| `test/browser_visual_oip004.mjs` | neue Datei; reproduzierbare Theme-/Responsive-/Performance-Prüfung, eigener Evidenzpfad |
| `test/package.json` | neue Test-DevDependency-Konfiguration, keine App-Runtime-Abhängigkeit |
| `test/package-lock.json` | neuer Lock für Playwright 1.60.0; `npm ci` tatsächlich ausgeführt |
| `test/widget_test.dart` | bereits identisch; unverändert |
| `web/index.html` | bereits identisch; unverändert |

Zusätzlich wurde die ausschließlich in OURS vorhandene `test/core_integration_test.dart` vollständig erhalten und um zwei Verknüpfungstests erweitert: ungültige/null Source-Zeiten und identische Metriknamen aus unterschiedlichen Quellen im OPC-UA-Inspector. Neue E2E-Automation liegt getrennt unter `tests/oip0051/browser_integration.mjs`. Keine bestehende Testdatei gelöscht.

**Bewusster semantischer Abgleich:** Der Lieferstand leitete Alarme zusätzlich aus rohen `alarm_active`-Werten ab. Dies würde OIP-005-Source-/Freshness-/Quality-Regeln umgehen. Die einheitliche, entity-spezifische `hasAlarm`-Darstellung verwendet deshalb ausschließlich die bereits vorhandene autoritative Device-/Registry-Klassifikation des Rust-Cores. Das Review-Ziel der konsistenten Incident-Semantik bleibt erfüllt; die frühere zusätzliche Frontend-Geschäftsregel wird nicht zurückgebracht. `Device.isFaulted` bleibt ebenfalls an `is_faulted` aus Rust gebunden.

## G4/G5 — Architektur und API-Kompatibilität

**Sämtliche vorhandenen Rust-Dateien sind byteidentisch zum gesicherten OIP-005-Stand.** Kein Core-Regressionsfix war erforderlich. CapabilityService, alle 13 IDs/Requests/Outputs, Permissions, Source-Scope, Audit-Port, Application Services, OPC-UA-Adapter, SQLite-Migrationen, Runtime/Writer und REST/SSE-Adapter wurden nicht verändert. Cargo-Manifeste/-Lock, Flutter-Pubspec/-Lock, Security-Ausnahmen und native Projektdateien bleiben erhalten.

Core-Health/Source-Health, Device Registry, Current Observations, paginierte Nodes, Events/Diagnose-Fixtures, vollständige SSE-Snapshots und Simulation Control arbeiten mit den bestehenden Verträgen. Primärgerät weiterhin `M-01`, weitere Geräte z. B. `sim-b:M-01`; source-kontextuelle Records werden bevorzugt, Legacy-Ereignisse bleiben lesbar. Unknown wird nicht Offline, Stale nicht Fresh, fehlende Werte nicht Nullmessung. DataLoss-Zeitpunktmarker wird nicht als gemessene Dauer dargestellt. Der volle Snapshot ist koaleszierend; REST-Resync bleibt erhalten, keine Replay-/Exactly-once-Annahme.

Der echte Core begrenzt eine Node-Anfrage mit `limit=10000` auf 100 und `limit=0` auf 1; der Browser folgt dem zurückgegebenen Limit. [Live-API-Nachweis](evidence/oip005/reconciliation-005-1/opcua-page-limits.json). Acht Workspace-Mitglieder bleiben azyklisch, Produktabhängigkeiten des Domain-/Application-Contract-Cores weiterhin nur serde/thiserror. Das bestehende Capability-Inventar bleibt inhaltlich zutreffend und wurde nicht historisch umgeschrieben.

## G6 — Erneut ausgeführte Regression

Host: macOS arm64, Rust 1.93.0, Flutter 3.22.0 / Dart 3.4.0, Xcode 26.6, Node 23.3.0, vorhandenes Chrome. Keine globalen Toolchain-Installationen.

| Prüfung | Ergebnis / Evidenz unter `docs/evidence/oip005/reconciliation-005-1/` |
|---|---|
| Rust fmt/check/clippy, warnings denied | PASS — `rust-fmt.log`, `rust-check.log`, `rust-clippy.log` |
| Workspace-Tests | PASS, **78** — `rust-workspace.log`; enthält Capability-/Permission-/Source-Scope-, 11 Storage- und 12 Reliability-Tests |
| Workspace-Build | PASS — `rust-build.log` |
| Kein Defaultbackend und open62541-only check/clippy | PASS — `no-default-*.log`, `open-only-*.log` |
| OPC-UA-Interoperabilität, beide Backends | PASS, **36** — `interop-tests.log`, `interop-clippy.log` |
| open62541-only Tests | PASS, **2** — `open-only-tests.log` |
| cargo-deny | PASS mit unveränderten Advisory-Ausnahmen — `deny.log`; keine Risikobehebung |
| Headless-E2E | PASS, sieben Phasen — [Report](evidence/oip005/reconciliation-005-1/headless/report.json) |
| Dart Formatcheck | PASS, null Änderungen — `dart-format-check.log` |
| flutter analyze | PASS, null Issues — `flutter-analyze.log` |
| Flutter-Tests | PASS, **47** — `flutter-tests.log` |
| Web-Release mit lokalen CanvasKit-Ressourcen | PASS — `flutter-web-build.log` |
| Gepinnte Browser-Testinstallation | PASS — `npm-ci.log`, keine gemeldeten Vulnerabilities; nur Test-DevDependencies |
| Browser-Fachregression | PASS, **16** — [Report](evidence/oip005/reconciliation-005-1/browser/browser-verification.json); echte Evidenz-/Gegenbeleg-/Missing-Assertions und named SSE-error/Reconnect |
| Responsive/Light/Dark und Capture-Automation | PASS, **30 neue Integrations-Captures** — [Report](evidence/oip005/reconciliation-005-1/visual/responsive-verification.json) |
| Nativer macOS-Integrationstest | PASS, ein Test mit Alarm und Reconnect — `macos-integration.log` |
| Integrierter Zwei-Quellen-Browser-E2E | PASS, sechs Phasen — [Report](evidence/oip005/reconciliation-005-1/integration-ui/report.json) |

[Maschinenlesbare Testergebnisse](evidence/oip005/reconciliation-005-1/test-summary.json). Die 47 Flutter-Tests setzen sich aus 41 Lieferantentests, vier erhaltenen OIP-005-Tests und zwei neuen Reconciliation-Grenztests zusammen. Kein Review-Test wurde zum Erreichen der Zahl entfernt. Die Rust-/Interop-Gruppen überlappen und werden nicht zu einer künstlichen eindeutigen Summe addiert.

Die erste Ausführung des neuen Invalid-Time-Tests scheiterte in der Testdatenkonstruktion: eine als `Map<String,int>` inferierte Map erlaubte keinen Nullwert. Die Fixture wurde korrekt als dynamisches JSON konstruiert; danach bestanden alle 47 Tests. Das Fehlerlog bleibt unter `development/flutter-test-fixture-map.log` erhalten. Dies war kein versteckter Produktionsfix oder ignorierter Testfehler.

Alle fünf Ansichten sind im Browser bei Desktop und 834/390/320 px navigiert. Die neue Capture-Suite prüft alle fünf Ansichten bei 1920/1440/1024/768/375 px sowie Light bei 1440 px. Widgettests prüfen Flutter-Render-Overflow bis 320 px mittels `tester.takeException()`; Browser-Dokumentbreite allein ist dafür kein Nachweis. Die gelieferten 30 Captures sind separat verifiziert; die zusätzlichen aktuellen Aufnahmen prüfen die tatsächlich zusammengeführten Layout-/Kontrast-/Accessibility-Fixes. Kein Spectrum-Redesign.

## G7 — Zusammenhängender E2E-Nachweis

Der Headless-Lauf verwendet zwei echte lokale OPC-UA-Prozesse mit eigenen IDs/Ports und Seeds 42/77. Er prüft Persistenz, REST/SSE, unabhängigen Ausfall beider Quellen, langsamen SSE-Client, Reconnect, kontrollierten Neustart und Prozess-Crash während gesperrter Ingestion. SQLite quick_check ok, Run-Journal erkennt Unterbrechung, keine doppelten Observation-Keys.

Der neue Browser-E2E verwendet denselben Core-Build und zwei äquivalente eigenständige Simulationsquellen:

1. Beide Simulatoren/Core starten; Source-Health, SQLite-Anteile und vollständigen SSE-Snapshot prüfen.
2. Tatsächlichen Flutter-Web-Release öffnen, alle fünf Ansichten bedienen und echte Prozesswerte lesen.
3. Neue Messprobe nachweisen. A über den vorhandenen lokalen Simulator-CLI mit `critical_sensor` starten; tatsächliche Wertänderung von Normalwert zu **95 °C**, Core-Device-Alarm und sichtbaren UI-Alarm nachweisen. Kein OPC-UA-Schreiben und kein neuer API-Befehl. B bleibt auf eigener Quelle/normalen Messwerten.
4. A kontrolliert stoppen. B zählt weitere Observations und persistiert; Flutter zeigt A degradiert/veraltet und B weiterhin aktuell. REST/SSE melden denselben getrennten Quellenzustand. Detail B enthält nur B-Werte; Diagnostics erhält die tatsächlichen Source-A-Ereignisse.
5. A normal wieder starten, Reconnect, neue frische Beobachtungen und persistierte Datenlücken prüfen.
6. Core und Quellen kontrolliert stoppen. Denselben Datenbankbestand zunächst ohne laufende Quellen öffnen: gespeicherte Werte stale, Reachability unknown, Runtime-Empfangszeit null. Flutter reconnectet und zeigt stale. Erst nach echtem Quellenstart wieder Live/Ready, neue Persistenz ohne doppelte Observation-Keys. Alle eigenen Prozesse abschließend kontrolliert stoppen.

Tatsächliche Screenshots: [Sensoralarm](evidence/oip005/reconciliation-005-1/integration-ui/source-a-real-sensor-alarm.png), [A offline](evidence/oip005/reconciliation-005-1/integration-ui/source-a-offline.png), [B bleibt frisch](evidence/oip005/reconciliation-005-1/integration-ui/source-b-still-fresh.png), [Datenlücken](evidence/oip005/reconciliation-005-1/integration-ui/source-a-gap.png), [stale Restore](evidence/oip005/reconciliation-005-1/integration-ui/core-restored-stale.png), [live nach Neustart](evidence/oip005/reconciliation-005-1/integration-ui/core-restarted-live.png). Browser-Fachregression, Visual-Suite und nativer Szenariotest wurden auf ihrer eigenen Demo-Instanz nacheinander ausgeführt.

## Exakte Start- und Testbefehle

Zwei Quellen, je ein Terminal:

```sh
cd /Users/benny/Code/open-industrial-platform
cargo build --workspace
target/debug/oip-simulated-server --port 14841 --seed 42 --tick-ms 250
```

```sh
cd /Users/benny/Code/open-industrial-platform
target/debug/oip-simulated-server --port 14842 --seed 77 --tick-ms 250
```

Core ohne Flutter, drittes Terminal:

```sh
cd /Users/benny/Code/open-industrial-platform
target/debug/oip-server --config examples/core-local.json --no-web
```

Alternativ denselben Core mit gebauter UI ausliefern; nicht parallel denselben SQLite-Bestand öffnen:

```sh
cd /Users/benny/Code/open-industrial-platform/apps/flutter
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
cd ../..
target/debug/oip-server --config examples/core-local.json --web-dir apps/flutter/build/web
```

Browser: `http://127.0.0.1:18084`. API: `/api/v1/core/health`, `/api/v1/sources`, `/api/v1/devices`, `/api/v1/metrics/current`, `/api/v1/events`, `/api/v1/opcua/nodes`, `/api/v1/stream`. Ctrl+C stoppt kontrolliert; DB für Wiederanlauf erhalten.

Regression ab Repository-Root:

```sh
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace -- --test-threads=1
cargo test -p oip-opcua --features open62541-backend -- --test-threads=1
cargo test -p oip-opcua --no-default-features --features open62541-backend -- --test-threads=1
target/oip-002-tools/bin/cargo-deny check advisories licenses bans sources
cargo build --workspace
OIP_EVIDENCE_DIR=docs/evidence/oip005/reconciliation-005-1/headless python3 tests/oip004/acceptance.py
cd apps/flutter
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test --reporter expanded
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
cd test
npm ci --ignore-scripts
cd ../../..
node tests/oip0051/browser_integration.mjs
```

Zusätzlich ausgeführt: `cargo check` und `cargo clippy -- -D warnings` für `oip-opcua --no-default-features`, für `--no-default-features --features open62541-backend` und Clippy für beide Backends, jeweils mit `--all-targets`. Unveränderte CI-Definitionen bleiben erhalten; Remote-CI wurde nicht gestartet.

Für Fachbrowser, Visual-Suite und nativen Test eine separate lokale Demo-Instanz starten:

```sh
cd /Users/benny/Code/open-industrial-platform
target/debug/oip-server --demo --port 18406 --opcua-port 14846 --database target/oip0051-ui-demo.sqlite
```

Nacheinander, nicht konkurrierend Szenarien wechseln:

```sh
cd /Users/benny/Code/open-industrial-platform/apps/flutter/test
OIP_URL=http://127.0.0.1:18406 npm run test:browser
OIP_URL=http://127.0.0.1:18406 npm run test:visual
cd ..
flutter test integration_test/live_dashboard_test.dart -d macos --dart-define=OIP_API_URL=http://127.0.0.1:18406 --reporter expanded
```

Browser-Skripte haben CWD-unabhängige Defaults in getrennten aktuellen Evidenzordnern. `OIP_EVIDENCE_DIR` überschreibt den jeweiligen Zielpfad. Vorhandenes Chrome verwenden oder `CHROME_PATH` setzen; Playwright ist lokal gepinnt, kein Produkt-Runtime-Dienst. Python/CLI-Tests benötigen SQLite ≥3.37 für STRICT; auf diesem Host wird die vorhandene aktuelle SQLite-CLI verwendet (`OIP_SQLITE_CLI` optional). cargo-deny wurde aus dem vorhandenen lokalen OIP-002-Toolverzeichnis gestartet. Keine globale Installation oder Cloud erforderlich.

## G8 — Isolation, Security und verbleibende Grenzen

Keine Commits, Pushes, Branchwechsel, Deployments, neue Produktionsverbindungen oder Änderungen an anderen Projekten. Die ausdrücklich angeforderte externe Sicherung und versionierte Handoff-Kopie sind die einzigen zusätzlichen Projektablagen außerhalb des Checkouts. Keine vorhandene Baseline-Datei verloren; ältere Verifikationsberichte und Evidenz bleiben historische Nachweise. Native Konfiguration, Flutter-Runtime-Packages, Rust-Code und Capability-Inventar unverändert.

Designreferenz vor/nach Integration identisch:

`bd9f9d8696ed48676055ee9a2cd0afb29e6c3d59e0945e662d925306f73c753e`.

**RUSTSEC-2023-0071 bleibt produktiver Blocker.** Die bestehenden Advisory-Ausnahmen RUSTSEC-2023-0089 und RUSTSEC-2024-0449 bleiben offen; das deny-Gate ist keine Behebung. Nur Loopback-Simulation, keine Industrieanlagen, Maschinensteuerung, OPC-UA-Schreiboperationen, Zertifikatsumgehung, Cloud oder MCP-Runtime.

Unveränderte OIP-005-Grenzen: lokale Entwicklungsidentität statt produktiver Authentifizierung, nicht dauerhaftes Execution-Audit, kein Tenant-Modell, kein vollständiges Event-Replay, eine Core-Instanz pro SQLite-Bestand, kein dauerhafter Ingestion-Spool, keine produktive Diagnose-/Historien-/Konfigurationsverwaltung. UI-Node-Browser bedient weiterhin die Primärquelle; kein neuer Bedienworkflow wurde ergänzt.

NOT_TESTED: Remote-CI-Matrix, Safari/Firefox/Edge/reale Mobilbrowser, native Windows/Linux/Android/iOS-Ausführung, Hardware-Stromausfall, industrielle Langzeit-/Last-/Leaktests und Flutter-DevTools-Rasterprofile. Physische Systeme und produktive Remote-Sicherheit wurden nicht behauptet. Die Browser-Frame-Pacing-Aufnahme ist ein kurzer lokaler Messlauf, keine Performance-SLA und kein mit anderen Refresh-Raten vergleichbarer Verbesserungsnachweis.

## Final Acceptance Gates

| Gate | Ergebnis |
|---|---|
| G1 Baseline | PASS — neue vollständige externe Source-Sicherung und unabhängige Verifikation |
| G2 Handoff | PASS — finales Archiv `1986cb10…`, vollständiges Manifest/Pfade/Hashes/Rundreise |
| G3 Reconciliation | PASS — alle 25 Dateien, 22 Updates, sechs Konfliktdateien aufgelöst, keine verlorene Änderung |
| G4 Architecture | PASS — Rust, alle 13 Capabilities, Permission-/Source-/Audit-Grenzen byteidentisch |
| G5 Functional | PASS — finale UI mit unveränderten Core-APIs kompatibel |
| G6 Regression | PASS — 78 Rust, 36 Interop, 47 Flutter, 16 Browserchecks, native macOS-Integration |
| G7 E2E | PASS — zwei Quellen, tatsächlicher Sensoralarm, Isolation, Reconnect, Persistenz/Restore bis UI |
| G8 Isolation | PASS — keine unautorisierten Änderungen, kein Commit/Push, keine Produktionsverbindung |

Nächster empfohlener Schritt: OIP-006 als separaten lokalen, zunächst lesenden MCP-Adapter auf die bereits implementierte CapabilityService-Grenze mit eigenem Security-Gate beginnen. Spectrum-Redesign separat behandeln; keine dieser Folgephasen wurde vorweggenommen.

OIP_005_1_PASS
