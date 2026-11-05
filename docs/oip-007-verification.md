# OIP-007 — Persistent Core Daemon & Multi-Client MCP

Stand: 2026-11-05, macOS arm64. **OIP IS AGENT-FIRST BY DESIGN.** Entwicklungsabnahme für lokale Simulation, keine Produktionsfreigabe.

## Ausgangspunkt, Scope und Baseline

Die sechs angeforderten OIP-005/006/006.1-Berichte, reale Runtime/Source-Worker, ApplicationServices/CapabilityService, Audit/Permissions, REST/SSE, rmcp-Transport und SQLite-Ownership wurden geprüft. Die gemeldeten Referenztests wurden nicht als neue Evidenz übernommen: **89 Rust-Workspace-Tests einschließlich bestehender MCP-/Storage-/Capability-/Reliability-Tests vor Source-Änderungen erneut PASS**, [Baseline-Log](evidence/oip007/baseline-rust-tests.log).

Session `01a1a3b3-9469-7311-be9a-1218be181ebc`, Workstream Rust/Core/Runtime/MCP. Branch weiterhin `main`, HEAD unborn, null tracked Dateien. Alle **947** nicht ignorierten Projektdateien inventarisiert, gehasht und extern gesichert:

`/Users/benny/Documents/OIP-Handoffs/core-007-baseline-20261105T010256Z/project-baseline.tar.gz`

SHA-256 `0d47867328bde4e883e859864f92e0d8f825bc1dc86a58c7f1b28c1f3d8345c9`, 64.422.918 Bytes. Alle Member unabhängig wieder gelesen und gegen das Inventar geprüft. Ignorierte DBs, PKI, Secrets, Dependencies und Build-Caches ausgeschlossen; Originale erhalten. Kein Commit als künstliche Baseline. [Baseline](evidence/oip007/baseline.json), [Inventar](evidence/oip007/inventory.json), [Sessions/Scopes](evidence/oip007/sessions.json).

Verfügbarer OpenCode-Aktivstatus ohne konkurrierenden OIP-Schreib-Workstream; ein weiterer lokaler Sessiondienst lieferte kein auswertbares JSON. Keine globale Sperre fremder Programme behauptet. Bekannte Spectrum-UI-Session bleibt außerhalb der Schreibautorität. Vorhandene Server PID2091 (18086) und PID74048 (18080) blieben unverändert. Alle neuen Instanzen besitzen eigene zufällige Loopback-Ports, DBs und Prozess-IDs. **Alle Flutter-Quelldateien, Assets, Packages und nativen Projektdateien byteidentisch zur Baseline.** [Finale Integrität](evidence/oip007/final-integrity.json).

## Tatsächliche Architekturänderungen

[Runtime-Audit mit zehn beantworteten Ausgangsfragen](architecture/oip-007-persistent-runtime.md), [IPC/Multi-Client/Autorisierung](architecture/oip-007-mcp-multiclient.md), [OIP-008-Vorschlag](architecture/oip-008-multi-infrastructure-proposal.md).

- `--daemon` besitzt dauerhaft genau eine vorhandene CoreRuntime, einen Writer und dieselben unabhängigen Source-Worker. REST und alle MCP-Sessions erhalten dieselbe ApplicationServices-Instanz.
- `--mcp-bridge` ist ein früher CLI-Pfad ohne CoreConfig/DB/Collector-Start. Je Client eine stdio-Bridge, je Verbindung ein eigener rmcp-Server über UnixStream.
- Neue strikt typisierte, geschützte lokale IPC-Konfiguration bindet OS-UID plus32Byte-Credential an eine serverseitige read-only McpPolicy. Explizite REST-Operator-Policy; keine Autorität aus Clientparametern oder Connection-ID.
- Begrenzter Session-JoinSet mit eigenen Cancellation-/Request-Zuständen. EOF, fehlerhafte Eingaben, Output-Stall und Überlast betreffen nur diese Session. Daemon arbeitet bei null Clients weiter.
- Sichere kooperative Socket-Ownership mit privaten Dateirechten, Peer-Identität, Lock, begrenztem Probe und persistierter eigener Socket-Identität. Kein blindes Löschen bestehender Socket-Dateien.
- Unix-stdout-Pipe ist tatsächlich nichtblockierend über die vorhandene sichere Tokio-Pipe-API, auch im alten stdio-Modus. Keine zusätzliche Runtime-Dependency und kein eigener unsafe-Code.
- Enger Lifecycle-Fix aus dem echten Offline-Shutdown-Test: Remote-CloseSession-Bestätigung von verifizierter lokaler Producer-Beendigung getrennt. Unbestätigtes Remote-Close wird protokolliert; nur wirklich gestoppter Producer darf zum Queue-/Writer-Drain weitergehen. Unbeendeter Producer bleibt Fehler.

Neue Produktdatei `crates/oip-server/src/mcp/ipc.rs`; Änderungen an main, mcp-Modul/Transport, Runtime sowie minimalem OPC-UA-Lifecycle-/Testcode. Domain, ApplicationServices, Capability-Verträge, REST-DTOs, Storage/Migrationen, sämtliche Cargo-Manifeste/-Lock, Security-Ausnahmen und acht Workspace-Mitglieder unverändert. Kein zweiter Core, keine neue Crate oder Plugin-/Agenten-Runtime, keine Flutter-Business-Logik.

## Unabhängige Reviews und behobene Befunde

Zwei separat delegierte, ausschließlich lesende Reviews unter der ausdrücklichen Phase-K-Autorisierung:

- [Review A Runtime/Reliability](evidence/oip007/reviews/runtime-review.md), Reviewer `/root/review_runtime_007`: Discover-Idle fälschlich auf5s begrenzt; SDK-Cleanup konnte vorzeitig verlassen werden; blockierender Socket-Probe; nur bedingt verifizierter Producer-Stop; fehlender früher Startup-Rollback. Alle Befunde im finalen Code geschlossen, keine weiteren Blocking-Findings im geprüften Scope.
- [Review B IPC/Authorization](evidence/oip007/reviews/ipc-security-review.md), Reviewer `/root/review_security_007`: Descriptor-Schutzattribute, Stale-/Live-Socket-Unterscheidung, stdout-Stall/Bridge-Cleanup und explizite REST-Autorität. Alle geschlossen; Reviewer hat finalen12-Phasen-E2E und neun IPC-Tests als Evidenz gelesen, nicht als selbst erneut ausgeführt ausgegeben.

Die anfänglichen Review-Turns wurden nach konkreten Befunden durch ein Nutzungslimit unterbrochen, später fortgesetzt und abgeschlossen. Keine bloße Selbstbewertung als unabhängiger Review ausgegeben. [Hashgebundener Review-Code](evidence/oip007/reviews/reviewed-source-hashes.json).

## Tatsächlich ausgeführte Regression

Host Rust1.93.0, rmcp3.8.0 unverändert; Flutter3.22.0/Dart3.4.0, vorhandenes Xcode/Chrome, Node23.3 und vorhandene aktuelle SQLite-CLI. Keine globale Installation.

| Prüfung | Ergebnis / Evidenz unter docs/evidence/oip007 |
|---|---|
| Vorherige Rust-Baseline | PASS89 — baseline-rust-tests.log |
| cargo fmt/check/clippy --all-targets, warnings denied | PASS — rust-regression.json / Einzel-Logs |
| Workspace inkl. Storage/Recovery/Capability/Permissions/MCP | **PASS100** — rust-workspace-tests.log |
| OPC-UA beide Backends | **PASS37** — rust-interop-tests.log |
| open62541-only | PASS2 — rust-open-only-tests.log |
| Ohne Defaultbackend/open-only/beide check+clippy | PASS — rust-regression.json |
| cargo-deny / locked Build / SDK-Beispiele | PASS, unveränderte Advisory-Ausnahmen — rust-regression.json |
| Neue Unix-IPC-Integrationstests | PASS9 — ipc-tests.log |
| Startup-Record-Rollback auf echtem Dateisystem | PASS1 — rollback-test.log, ebenfalls Workspace |
| Alter Headless-E2E mit zwei Quellen und Crash | PASS7 Phasen — headless/report.json |
| Vorhandener echter SDK-stdio-E2E | PASS — mcp/report.json, sdk-transcript.json |
| Neuer Daemon/Bridge/Multi-Client/Flutter-E2E | PASS12 Phasen — e2e/report.json |
| Echter blockierter stdout im alten stdio-owned Modus | PASS — blocked-stdio/report.json |
| Dart Format, ohne Änderung | PASS — dart-format.log |
| Flutter Analyze | PASS0Issues — flutter-analyze.log |
| Flutter-Tests | **PASS80** — flutter-tests.log |
| Flutter Web Release, lokale CanvasKit-Ressourcen | PASS — flutter-web-build.log |
| Browser-Fachregression, unveränderte fünf Ansichten | **PASS16** — browser/browser-verification.json |
| Spectrum-Interaktionen | PASS4 Gruppen — interactions/spectrum-interactions.json |
| Theme-/Responsive-Visual-Suite | PASS30 aktuelle Captures — visual/responsive-verification.json |
| Native macOS mit Alarm/Reconnect | PASS1 — native_macos-console.log, ui-regression.json |
| Eigener Demo-Core nach UI-/Native-Regression | PASS sauber beendet — ui-regression.json |
| launchd-Beispielsyntax | PASS plutil lint — launchd-template-lint.log; nicht installiert |

**100 =89 vorhandene +9 IPC +1 Rollback +1 OPC-UA-Offline-Stop-Test.** Deshalb Interop37 statt36; kein Test gelöscht. Testgruppen überlappen, nicht künstlich summieren. Zwölf Read-Capabilities, sechs Tools und Protokoll-/Schema-Semantik bleiben erhalten. Die bisherigen direkten Service/REST/MCP-Paritäts-, Source-Scope-, Permission-, Cancellation- und Output-Limit-Tests laufen im Workspace mit.

Moderne Discover-Sitzung mit5,2s Idle und nachfolgendem Tool-Aufruf getestet; Legacy Initialize separat. Weitere echte Grenzen: schlechte/partielle Authentisierung, falscher Token/Magic, fremde konfigurierte UID, chmod/Symlink/Hardlink/Regular-file-Ziele, duplizierte Credentials, mutierende Policy, begrenzte Session-Admission, echte Request-Cancellation und Disconnect bei pending Service-Future. Normaler clientseitiger Disconnect cancelt nicht den Runtime-Owner.

## Zusammenhängender realer Akzeptanzlauf

`python3 tests/oip007/acceptance.py`, [Report](evidence/oip007/e2e/report.json) und [SDK-Transkript](evidence/oip007/e2e/sdk-transcript.json). Zwei echte lokale OPC-UA-Prozesse; ein tatsächlicher Daemon; drei unabhängige offizielle rmcp-SDK-Clientprozesse über je eine echte Bridge; unveränderter Flutter-Release im echten frischen Chrome-Kontext. Kein KI-Modell oder Fixture-API.

1. Daemon ohne Client-Ownership starten; beide Quellen, SQLite-Anteile, REST/SSE-Vollsnapshot und fünf Flutter-Ansichten nachweisen. Tatsächlich empfangenes main.dart.js SHA-256 `c8d267715a4cc627328ef2efd513a6bb681cf1b12044d479091bd3c3ac083f68`, identisch zum unveränderten Spectrum-Release.
2. A erhält explizite All-Read-Policy, B nur sim-a, C nur sim-b. Parallele Reads, echte Device-/Source-/Observation-Zuordnung, Ressourcen-Enumeration, Fremdsource-/Global-Snapshot-Denials und moderne/Legacy-Sitzung prüfen.
3. Zweiter Daemon auf gleicher DB sowie Symlink-Alias vor Collector-Start verweigert; erste Instanz bleibt aktiv. Voller nicht kooperierender Unix-Backlog wird unverändert erhalten.
4. Bridge A tatsächlich SIGKILLen; B, C, Flutter und Ingestion bleiben aktiv. A neu verbinden, gleicher Core-run_id.
5. Alle MCP-Clients trennen; zusätzliche SQLite-Observations ohne Clients nachweisen, REST/SSE/Flutter bleiben verfügbar. Wiederverbinden ohne Runtime-Neustart.
6. 1/3/8 Clients mit echten parallelen Reads, zwölf Connect/Read/Disconnect-Zyklen und25 IPC-Auth-Latenzproben. Separater längerer kurzer Vergleichslauf unten.
7. Manipulierte Actor/Grants, falsche IDs/URIs, Zeitstempelfeld, überlange Query/Limits, Schreibtool, neue Bridge mit weiterhin eingeschränktem Credential und falsche lokale Authentisierung verweigert. Tausend reale Nodes in zehn100er-Seiten. Ungültiges JSON und >16KiB-Zeile über echte Bridge, danach gültiger Ping. Dann mit acht großen100-Node-Toolergebnissen stdout tatsächlich füllen: stdin offen, stdout ungelesen, Bridge beendet sich selbst mit Timeout; anderer Client und Datenerfassung bleiben gesund.65536 ausgegebene Pipebytes, keine heimliche globale Shutdown-Wirkung.
8. Source A stoppen; B zählt/persistiert weiter. REST/SSE/MCP identische fachliche Zustände, Flutter zeigt A stale/degraded und B frisch sowie tatsächliches Core-Degraded bei live verbundener API.
9. A im vorhandenen Simulator-CLI kritischen Sensor95°C liefern lassen, tatsächlichen Core-/UI-Alarm nachweisen. Normal neu starten; Reconnect, neue Samples und persistierte source-spezifische Datenlücken.
10. Kontrollierter Daemon-Stop, gleicher Bestand ohne laufende Quellen erneut geöffnet: gespeicherte Werte stale, Reachability unknown, Runtime-Empfangszeit null, keine künstliche Freshness. UI reconnectet. Erst echte Quellenwiederaufnahme Ready/Live und weitere Persistenz.
11. Echter SIGKILL des Daemons: Socket bleibt als Crash-Rest. Neustart erwirbt frei gewordene OS-Locks, validiert eigenen Rest-Socket und Run-Journal `interrupted`. SQLite quick_check ok, keine doppelten Observation-Keys, stale/unknown bis neuer Empfang.
12. Flutter schließen während MCP/Daemon noch laufen und weitere Reads prüfen. Eigene Clients, Sources und Daemon kontrolliert stoppen; Socket entfernt. Audit/UID/Session-/Scope-/Korrelation vorhanden, Credential-Bytes/Hexwerte und Sentinel nicht in Produktlogs. Alle eigenen Testprozesse beendet.

Aktuelle Screenshots: [Daemon live](evidence/oip007/e2e/ui/daemon-spectrum-live.png), [A stale](evidence/oip007/e2e/ui/source-a-stale.png), [B frisch](evidence/oip007/e2e/ui/source-b-fresh.png), [Core degraded](evidence/oip007/e2e/ui/core-degraded-live-api.png), [Sensoralarm](evidence/oip007/e2e/ui/sensor-alarm.png), [stale Restore](evidence/oip007/e2e/ui/daemon-restored-stale.png). Weitere aktuelle Fach-/Responsive-Captures unter browser/visual; historische OIP-006.1-Aufnahmen nicht als neue Daemon-Aufnahmen ausgegeben.

## Performance und Cleanup

| Modus / Clients | Reads / 8s | Mittel / p95 ms | Core-RSS Ende KiB | Core-CPU % eines Kerns | Neue persistierte Observations |
|---|---:|---:|---:|---:|---:|
| 006-stdio /1 | 146 | 1.69 / 2.06 | 24880 | 3.72 | 107 |
| 007-Daemon /1 | 142 | 2.56 / 4.46 | 24080 | 3.75 | 109 |
| 007-Daemon /3 | 438 | 1.48 / 1.91 | 24304 | 5.87 | 107 |
| 007-Daemon /8 | 1174 | 1.42 / 2.09 | 25552 | 9.32 | 100 |

Methodik: jeweils acht Sekunden, zwei identische lokale Sources, SourcesRead etwa alle50ms pro echtem SDK-Client, gleiche finale Binary/Host/Profile. Die Referenz ist der weiterhin vorhandene **OIP-006-stdio-owned Modus derselben finalen Binary**, kein vorgetäuschter historischer Binary-A/B-Vergleich. Client-Kontrollhop über den SDK-Testprozess ist in der Latenz enthalten. Finaler Messlauf nach den übrigen Regressionen; erster Lauf während paralleler Prüfungen separat unter development/performance-concurrent-regression.json erhalten. Eigene Core-CPU aus Prozess-CPU-Zeit/Wallzeit, RSS Punktmessung; Zeitauflösung etwa10ms. Kein Peak-/Leak-/Dauerlauf-/SLA-Nachweis oder behaupteter Performancegewinn.

[Messwerte](evidence/oip007/performance/report.json). Session-Task-Telemetrie zeigt tatsächliches JoinSet mit1/3/8 Session-Tasks und Rückkehr auf0. OS-Threads separat gemessen, nicht als Tokio-Tasks ausgegeben. Vollständiger Census aller internen SDK-/Tokio-Tasks ist NOT_TESTED; keine zusätzliche Instrumentierungs-Runtime eingebaut. Bounds aus Code, aktive Sessionzählung und erfolgreiches Cleanup sind belegt.

IPC-Connect+Auth im E2E25-mal gemessen, zwölf Connect/Read/Close-Zyklen und Reconnect-Dauer als echte Rohwerte erhalten. Source-Reconnect durch kontrollierten Test-Timeout begrenzt; keine beliebige maximale Betriebsdauer eingeführt. Stdio-owned Prozess unter physisch ungelesenem Output beendet sich nach rund6,1s samt sauberem Writer-Drain; Bridge-Ausgabefrist3s plus begrenzter Executor-Abschluss, Daemon-Lifecycle unabhängig.

## Entwicklungsbefunde und transparente Grenzen

Frühere Fehlversuche unter development/ sind keine PASS-Evidenz. Anfangs testete die Flutter-Steuerung zwar alle Funktionen, hielt beim Ende aber den Node-stdin offen; explizites stdin-Cleanup und Bestätigung des Browser-Endes korrigierten den Harness. Ein früherer Testdaten-/Compile-Lauf besaß eine falsche SourceScope-JSON-Form/fehlendes mut, später eine mehrdeutige Read/Write-by_ref-Nutzung; korrigiert, finale Builds/Tests sauber.

Der Live-Socket-Test bestätigte auf macOS ConnectionRefused trotz vollem Backlog; nicht durch längere Frist kaschiert, sondern Ownership-Nachweis hinzugefügt. Der anfängliche Slow-Client-Test verwendete zu kleine Snapshots, die bulk.* absichtlich ausfiltern; dessen Timeout beweist keine tatsächliche Pipe-Sättigung. Korrigierte große Node-Toolantworten prüfen diese nun wirklich. Der blockierende Tokio-stdout-Pfad wurde auf Review hin durch die sichere vorhandene Unix-Pipe-API ersetzt; ein versuchter AsyncFd-Konstruktor war im installierten Tokio bereits deprecated/unsound und wurde nicht übernommen. Kein neues Crate, keine Lint-Ausnahme und kein unsafe-Code zur Umgehung.

RUSTSEC-2023-0071 bleibt produktiver Blocker, ebenso bleiben Ausnahmen2023-0089/2024-0449 offen. cargo-deny-PASS ist keine Behebung. Keine öffentlichen MCP-/HTTP-Listener, Industrieanlagen, Remote-Administration, Schreibtools, Maschinensteuerung, Cloud oder Credential-Ausgabe. Lokale OS-Eigentümer bleiben vertrauenswürdig; Credential-Scopes sind keine Isolation gegeneinander feindlicher Programme desselben UID. Der explizite Loopback-REST-Operatorzugang ist eine eigene lokale Autorität. Policies sind Startup-Snapshots, keine implementierte Hot-Revocation.

NOT_TESTED: reale fremde OS-UID-Prozesse mangels privilegiertem Testsetup (Kernel-Identität/Dateimodi und fremde konfigurierte UID sind geprüft), native Linux-/Windows-Ausführung, Named Pipes, produktive Remote-/Tenant-Authentifizierung, manipulationssicheres dauerhaftes Audit, blockierter Operator-stderr-Sink, globale faire CPU-/Memory-Budgets, Hardware-Stromausfall, industrielle Dauerlast/Leak-/SLA-Tests, andere reale Browser/OS-/Mobilgeräte, Remote-CI und Installation/Aktivierung von launchd/systemd. Moderne/Legacy-Clients vom offiziellen Rust-SDK sind echt geprüft, keine beliebige Clientzertifizierung.

## Exakte Startbefehle

Freie lokale Ports/eigenen Datenbestand verwenden; keine vorhandenen Prozesse beenden. Alle vier Betriebsarten wurden in den beschriebenen Prozessläufen mit isolierten Pfaden/Ports tatsächlich ausgeführt. Folgende Operatorbefehle verwenden das vorhandene Zweiquellenbeispiel; separate Terminals für die zwei Simulatoren:

```sh
cd /Users/benny/Code/open-industrial-platform
cargo build --locked --workspace
cargo build --locked -p oip-server --examples
target/debug/oip-simulated-server --port 14841 --seed 42 --tick-ms 250
```

```sh
cd /Users/benny/Code/open-industrial-platform
target/debug/oip-simulated-server --port 14842 --seed 77 --tick-ms 250
```

A — Bisheriger Headless-Core mit REST, ohne UI:

```sh
cd /Users/benny/Code/open-industrial-platform
target/debug/oip-server --config examples/core-local.json \
 --database /Users/benny/Code/open-industrial-platform/target/operator-headless.sqlite --no-web
```

B — Bisheriger client-owned MCP-Modus, vom MCP-Client mit stdin/stdout-Pipes starten lassen:

```sh
/Users/benny/Code/open-industrial-platform/target/debug/oip-server \
 --mcp-stdio --config /Users/benny/Code/open-industrial-platform/examples/core-local.json \
 --database /Users/benny/Code/open-industrial-platform/target/operator-stdio.sqlite \
 --mcp-policy /Users/benny/Code/open-industrial-platform/examples/mcp-read-local.json
```

Optional `--mcp-rest` für denselben Prozess; Client-EOF stoppt weiterhin dessen eigene Instanz.

C — Neuer Daemon. Setup nur in einem **neuen** privaten Verzeichnis; bestehende Credentials werden nie überschrieben. Das Helper-Script ist tatsächlich geprüft, installiert/startet aber keinen Dienst:

```sh
cd /Users/benny/Code/open-industrial-platform
python3 examples/prepare-local-ipc.py /Users/benny/Code/open-industrial-platform/target/operator-ipc
# optional vor GUI-Nutzung, keine Source-Änderung:
cd apps/flutter
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
cd ../..
target/debug/oip-server --daemon --config examples/core-local.json \
 --database /Users/benny/Code/open-industrial-platform/target/operator-daemon.sqlite \
 --ipc-config /Users/benny/Code/open-industrial-platform/target/operator-ipc/ipc.json \
 --web-dir /Users/benny/Code/open-industrial-platform/apps/flutter/build/web
```

REST/Flutter dann `http://127.0.0.1:18084`, sofern dieser Port frei war und der Operator die Instanz tatsächlich startet. **OIP-007 hinterlässt keinen neu laufenden Test-Daemon.** Die vorher bestehende006.1-Vorschau18086 wurde nicht umgedeutet oder beendet. SIGINT/SIGTERM am Daemon sind der autorisierte Operator-Shutdown; kein Shutdown-MCP-Tool.

D — Neue Bridge, durch einen generischen MCP-Client starten lassen:

```sh
/Users/benny/Code/open-industrial-platform/target/debug/oip-server \
 --mcp-bridge \
 --ipc-socket /Users/benny/Code/open-industrial-platform/target/operator-ipc/mcp.sock \
 --ipc-credential /Users/benny/Code/open-industrial-platform/target/operator-ipc/source-a.credential
```

Generische Launcher-Konfiguration, keine Credential-Inhalte oder Anbieterbindung:

```json
{"mcpServers":{"oip-source-a-read":{"command":"/Users/benny/Code/open-industrial-platform/target/debug/oip-server","args":["--mcp-bridge","--ipc-socket","/Users/benny/Code/open-industrial-platform/target/operator-ipc/mcp.sock","--ipc-credential","/Users/benny/Code/open-industrial-platform/target/operator-ipc/source-a.credential"]}}}
```

Weitere Clients nutzen eigene Bridge-Prozesse und die jeweils ausdrücklich freigegebene Credential-Datei. Beispiel-All-Credential ist eine separate Operatorfreigabe, keine clientseitige Rechteeskalation.

Optionale, **nicht installierte/aktivierte** Templates: [launchd](../examples/services/oip-daemon.plist.template), [systemd](../examples/services/oip-daemon.service.template). Pfad-/User-Platzhalter zuerst bewusst ersetzen; launchd-Syntax gelintet, systemd nicht nativ ausgeführt. Keine Systemdienständerung im Auftrag.

## Exakte Wiederholungsbefehle

```sh
cd /Users/benny/Code/open-industrial-platform
python3 tests/oip007/regress_rust.py
python3 tests/oip007/mcp_acceptance.py
python3 tests/oip007/blocked_stdio.py
OIP_EVIDENCE_DIR=docs/evidence/oip007/headless python3 tests/oip004/acceptance.py
python3 tests/oip007/acceptance.py
python3 tests/oip007/ui_regression.py
# Vergleich ohne konkurrierenden Regressionstest:
python3 tests/oip007/performance.py
cd apps/flutter
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test --reporter expanded
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
```

Rust-Runner führt fmt, check/clippy, Workspace, alle bestehenden Backendkombinationen, deny und locked Builds aus; exakte Einzelargumente in rust-regression.json. Prozesslokale platzsparende Buildvariablen wie bereits006, keine globale Cargo-Konfiguration. Vorhandene Chrome-/Playwright-/Flutter-/SQLite-Toolchains erforderlich; keine Cloud. Alle Runner besitzen eigene Prozesse/DBs und hinterlassen nur ignorierte Runtime-Artefakte, keine aktiven Testservices. Wiederholung aktualisiert ausschließlich007-Evidenzpfade, nicht historische Berichte.

## Abschluss-Gates

| Gate | Ergebnis |
|---|---|
| G1 Architecture | PASS — eine vorhandene Runtime/Writer/Serviceinstanz |
| G2 Persistent Lifecycle | PASS — null Clients, Ingestion/REST/SSE/Flutter laufen weiter |
| G3 MCP Multi-Client | PASS — drei getrennte echte SDK-Clients und acht parallele Clients |
| G4 Client Isolation | PASS — Kill/Disconnect/Cancel/Output-Stall bleiben lokal |
| G5 Authorization | PASS — explizite Policies, Credential+Peer, Scope-Denials, geschützter Socket |
| G6 Data Integrity | PASS — DB-Doppelstart/Alias verweigert, SQLite/Run-Journal/Keys geprüft |
| G7 Interoperability | PASS — zwölf Reads/sechs Tools, Schemas, Discover/Legacy/REST-Parität |
| G8 Reliability | PASS — zwei Quellen, Reconnect, Drain, Restart und echter SIGKILL-Recovery |
| G9 Regression | PASS —100 Rust/37 Interop/80 Flutter/16 Browser/native macOS |
| G10 Isolation | PASS — UI/Altdaten/Fremdprozesse erhalten, keine Git-Writes/Deployments |
| G11 Reproducibility | PASS — neue Dokumentation, SDK-/Browser-/Prozessrunner und Evidenz |
| G12 Future Architecture | PASS — präziser OIP-008-Vorschlag, keine implementierte Tenant-Behauptung |

Nächster Schritt: OIP-008-Identitäts-/Infrastruktur-ADR und Data-/Scope-Migration separat spezifizieren; produktive Freigabe erst nach Security-Blocker-Behebung, belastbarer Identität und dauerhaftem Audit.

OIP_007_PERSISTENT_CORE_PASS
