# OIP-006.1 — Spectrum Integration & Canonical Release Candidate

Stand: 2026-11-05, lokale Entwicklung auf macOS arm64. **OIP IS AGENT-FIRST BY DESIGN.** Lokaler Integrations-RC, keine Produktionsfreigabe.

## Kanonischer Stand und laufende Vorschau

**Tatsächlich geprüfte Spectrum-URL: [http://127.0.0.1:18086](http://127.0.0.1:18086).** Eigener Vorschauprozess PID 2091, SQLite ausschließlich unter `target/oip0061-preview/`, eingebettete lokale Simulation auf 14886. Beide Listener ausschließlich 127.0.0.1. Er bleibt ausdrücklich für den Operator erhalten; alle temporären Testprozesse wurden kontrolliert beendet. [Prozess-/Startdaten](evidence/oip0061/preview-process.json), [abschließender Live-Nachweis](evidence/oip0061/live-preview.json).

Der bestehende fremde Server auf **18080** wurde nicht verändert und kann weiterhin die alte Oberfläche ausliefern. Die neue URL ist 18086. Keine Behauptung, ein alter Browser-Screenshot sei bereits Spectrum gewesen.

Frischer Browserkontext, Service Worker gesperrt und Cache deaktiviert: tatsächlich empfangenes `main.dart.js` entspricht dem lokalen Release-Artefakt. Vorher SHA-256 `367a8bd770101f74eb2b101f09fc7ede10da2472339dfceb767fcae88c6f5c47`, final `c8d267715a4cc627328ef2efd513a6bb681cf1b12044d479091bd3c3ac083f68`. [Vorher](evidence/oip0061/before/report.json), [Nachher](evidence/oip0061/after/report.json), [finale Builddateien](evidence/oip0061/final-web-hashes.json). Die Screenshots sind echte Browseraufnahmen, keine Mockups.

## Baseline und Integrationsautorität

Session `01a1a3b3-9469-7311-be9a-1218be181ebc`, einzige Integrationsautorität. Branch `main`, HEAD weiterhin unborn, null tracked Dateien; Git-Diff allein war keine Baseline. Alle 637 nicht ignorierten Projektdateien wurden mit SHA-256 inventarisiert und extern gesichert:

`/Users/benny/Documents/OIP-Handoffs/core-0061-baseline-20261104T232930Z/project-baseline.tar.gz`

SHA-256: `52891379f5b234ac476d34f5f89d9b9410f991e87fbaf7084c3afa6e74f901e4`, 29.828.219 Bytes. Alle Archivmember unabhängig wieder gelesen und gegen das Inventar geprüft. Kein Source-Drift gegenüber dem versiegelten OIP-006-Stand. Secrets, PKI, Runtime-Datenbanken, installierte Dependencies und Build-Caches nicht im Source-Archiv; ihre Originale erhalten. Der vorhandene alte Web-Release wurde separat als `web-before/` beim Backup gesichert und dateiweise gehasht.

[Baseline](evidence/oip0061/baseline.json), [Sessionprüfung](evidence/oip0061/sessions.json), [finale Integrität](evidence/oip0061/final-integrity.json). Spectrum-Zulieferer `ses_e574f4783ffe57EjpGTv3i535K` und seine Reviews waren abgeschlossen; verfügbarer Aktivstatus ohne konkurrierenden Schreib-Workstream. Seine isolierte Arbeitskopie unter `/Users/benny/Code/oip-ui-isolated/…` wurde nicht beschrieben. Sessionbeobachtung ist keine globale Fremdprozess-Sperre.

## Handoff und Drei-Wege-Abgleich

Manifestbestimmtes Archiv:

`/Users/benny/Documents/OIP-Handoffs/ui-005-spectrum/20261104T231122Z-ses_e574f4783ffe57EjpGTv3i535K/oip-005-ui-spectrum-handoff.tar.gz`

Tatsächlich geprüfter SHA-256:

`be767ee48de12d120b46b599da2e4fa6906c29bfccfe21a7189bbe9ff4da6ad6`.

129 Member, 112 manifestierte Dateien, 15 Flutter-Payloads. PASS: exakter Manifestbestand und Hash jedes Members/Payloads/Patches, relative kanonische Pfade, keine Traversal-/absoluten/Backslash-Pfade, doppelten Einträge, Links oder Special Files. Größen begrenzt, keine Rust-/Storage-/CI-/MCP-Änderung im Payload. Äußere/innere Berichte, Patch und Change-Manifest identisch. Alle 66 Lieferanten-PNGs auf Hash, Größe und PNG-Dimensionen geprüft; historische Lieferantenevidenz bleibt separat im verifizierten externen Paket.

Extraktion ausschließlich in den externen Validierungsbereich beim neuen Backup. Reverse-Patch rekonstruiert BASE, Forward-Patch liefert **15/15 byteidentische Enddateien**, ohne Fuzz. BASE-Hashes entsprechen dem unabhängig erhaltenen kanonischen OIP-005.1-Manifest. Alle **79/79** dort manifestierten Flutter-Dateien waren vor Integration im aktuellen OIP-006-Checkout identisch. OIP-006 hatte somit tatsächlich keine kanonische Flutter-Quelldatei verändert.

- BASE: rekonstruierter und hashbestätigter OIP-005.1-UI-Stand.
- OURS: neu gesicherter aktueller OIP-006-Stand; für die ursprünglichen UI-Dateien identisch BASE.
- THEIRS: finales manifestiertes Spectrum-Payload.

**13 konfliktfreie Änderungen, zwei neue Dateien, null textuelle Konflikte.** Jede Datei vor Anwendung nochmals gegen OURS geprüft. Keine pauschale Archivüberschreibung. [Dateiweise BASE-/OURS-/THEIRS-/Endhashes und Auflösung](evidence/oip0061/reconciliation.json), [Archiv-/Rundreise-Nachweis](evidence/oip0061/handoff-verification.json).

Gelieferte Dateien, relativ zu `apps/flutter/`:

| Datei | Integration |
|---|---|
| README.md | Spectrum-Dokumentation; veraltete Aussage zur fehlenden MCP-Runtime auf den realen Rust-Adapter abgeglichen; aktuelle Evidenzlinks |
| lib/app/app.dart | drei Themes, Workstation-Shell; kurzer vollständig sichtbarer Agent-first-Badge und korrekte Schnittstellenbeschreibung |
| lib/design_system/theme.dart | Spectrum/Graphite/Daylight, Palette, Typografie, Statuskontraste und Breakpoints |
| lib/features/overview.dart | farbige Panels/Chart/Ribbon; unten beschriebene Core-Status-Vertragskorrektur |
| lib/features/devices.dart | getöntes Inventar, Inspector, Memoisation; bestehende Source-/Freshness-/Alarmregeln erhalten |
| lib/features/network.dart | farbige logische Topologie, vollständige Geräte, Zoom/Pan/Inspector; keine neuen Verbindungen |
| lib/features/opcua.dart | Namespace/Nodes/Inspector, responsive Panels; bestehende Pagination und Primärbindung |
| lib/features/diagnostics.dart | tatsächliche zeitgestempelte Collection-Timeline, Inspector, klassische Liste; Evidenz/Gegenbelege/Missing erhalten |
| lib/widgets/components.dart | wiederverwendbare statische Gradient-/Surface-/Inspector-/Status-/Timeline-Komponenten |
| lib/widgets/trend.dart | visuelle Gradient-Linie; Source-/Epoch-/Quality-/Gap-Regeln erhalten |
| test/browser_oip004.mjs | Spectrum-kompatible 16 Fachchecks; neue Evidenzdefaults |
| test/browser_visual_oip004.mjs | drei Theme-Zyklen berücksichtigt; neue Evidenzdefaults |
| test/browser_spectrum.mjs | neue Interaktionsprüfung; Evidenzdefault ins kanonische Verzeichnis umgesetzt |
| test/spectrum_test.dart | sieben zusätzliche Lieferantentests vollständig übernommen |
| test/package.json | ein zusätzlicher Test-Script-Eintrag; keine Dependency-Änderung |

## Kleine notwendige Kompatibilitätskorrektur

Das gelieferte Ribbon „CORE / API“ zeigte nur `controller.connection`. Damit konnte ein degradierter Core bei funktionierendem SSE als bloß „Verbunden“ erscheinen. Der bereits vorhandene `core`-Block im SSE-Snapshot wird jetzt additiv als `CoreHealthView` in `lib/models/contracts.dart` gelesen. Der vorhandene Core-Indikator zeigt **den gelieferten Lifecycle**, Liveness/Readiness/Persistenz als Tooltip. Keine fachliche Health-Berechnung in Dart. UI-Transportverlust markiert diesen letzten Status ausdrücklich als veraltet; Ausfall nur der Primärquelle überschreibt den tatsächlichen Gesamt-Core-Status nicht.

Missing/malformed CoreHealth bleibt Unknown, niemals Ready aus einer laufenden API abgeleitet. Vor dem ersten SSE kann der bestehende REST-Resync mangels Core-Block daher kurz Unknown zeigen. Das ist ehrlicher als ein erfundener Zustand; kein zusätzlicher Endpoint oder API-Vertrag wurde eingeführt. Reale Source-A-Störung bei weiter frischem B und live verbundener API ist im E2E einschließlich sichtbarem Core-Degraded-Indikator geprüft.

Zusätzliche Tests: `test/core_health_projection_test.dart` (zwei gezielte Regressionen) und `test/spectrum_integration_test.dart` (24 Kombinationen aus drei Themes und acht Breiten, jeweils fünf Ansichten mit `tester.takeException()`). Ergebnis **80 = 54 Lieferantentests + 24 Matrixprüfungen + 2 Core-Vertragsprüfungen**. Kein Test entfernt. Alle ursprünglichen OIP-005.1-Source-/Clock-/Alarm-/Incident-/Resync-/Disposal-Fixes erhalten; Controller, REST/SSE-Services und Event-Transporte byteidentisch zur Baseline.

## Sichtbare Abnahme und Themes

Spectrum ist auf den ersten Blick vom alten dunkelblauen/türkisen Dashboard verschieden: nahezu schwarzer Hintergrund, sichtbare getönte Panels und Card-Verläufe, Blau/Cyan/Lime/Violett/Pink, gelbe Diagnostik-/Systemlabels, Gradient-Chart und kompakte Inspector-Struktur. Die technische Theme-Aktivierung wurde im tatsächlichen Browser über `SPECTRUM` und den geladenen Assethash belegt. Kein neues Redesign im Integrationsworkstream.

| Ansicht, gleiche Auflösung 1440×1000 | Alter OIP-006-Build | Integriertes Spectrum |
|---|---|---|
| Overview | [Vorher](evidence/oip0061/before/overview-1440.png) | [Nachher](evidence/oip0061/after/overview-1440.png) |
| Devices | [Vorher](evidence/oip0061/before/devices-1440.png) | [Nachher](evidence/oip0061/after/devices-1440.png) |
| Network & VPN | [Vorher](evidence/oip0061/before/network-1440.png) | [Nachher](evidence/oip0061/after/network-1440.png) |
| OPC UA | [Vorher](evidence/oip0061/before/opcua-1440.png) | [Nachher](evidence/oip0061/after/opcua-1440.png) |
| Diagnostics | [Vorher](evidence/oip0061/before/diagnostics-1440.png) | [Nachher](evidence/oip0061/after/diagnostics-1440.png) |

Beide Reihen verwenden denselben eigenen Backend-/DB-/Source-Prozess und Normalbetrieb. Live-Werte, Datenbankzähler und Zeitstempel laufen tatsächlich weiter; es wurden keine identischen Messwerte fingiert oder API-Antworten eingefroren.

**120 finale Haupt-Captures:** fünf Ansichten × drei Themes × 320/375/390/768/834/1024/1440/1920 px. Zusätzlich 45 nach Scrollen auf den drei schmalen Breiten. Alle referenzieren finalen JS-Hash `c8d26771…`. [Matrix](evidence/oip0061/themes/report.json), [Desktop-Review-Galerie](evidence/oip0061/review-1440.png), [320-px-Review-Galerie](evidence/oip0061/review-320.png). Galerien ordnen Originalaufnahmen für die Review an; Original-PNGs bleiben unverändert. Zusätzlich die 30 aktuellen Captures der unveränderten Lieferanten-Visual-Automation unter `visual/`; sie ersetzen die vollständige neue 120er-Matrix nicht.

Spectrum, Graphite und Daylight visuell geprüft, einschließlich dunkler/heller Statuskontraste, technischer Labels und lesender Inspectors. Browser prüft Dokumentbreite; Widget-Matrix prüft tatsächliche Flutter-Renderexceptions. Status wird zusätzlich durch Text/Symbole/Semantik vermittelt. Graphite reduziert farbige Flächen; Daylight besitzt helle Flächen und dunklere Akzent-Vordergründe.

Theme-Wechsel funktioniert. **Keine persistente Theme-Präferenz implementiert:** ein Reload aus Graphite beginnt wieder bei Spectrum, tatsächlich getestet. Keine fiktive Preferences-/Organization-API.

## Core, MCP und vollständige Regression

**Rust-Quellen, Cargo-Manifeste/Lock, OPC-UA-/SQLite-Code, Permissions, SourceScope, Audit, MCP-Allowlist und Runtime sind byteidentisch zur OIP-006-Baseline.** Keine neue Crate, Runtime-Dependency oder Protokollintegration. Der Core läuft weiterhin ohne Flutter. Zwölf Read-Capabilities, sechs Tools, globale/source-spezifische Resources, Schema-/Error-/Cancellation-/Limit-/Ownership-Grenzen unverändert.

| Tatsächlich ausgeführt | Ergebnis / Evidenz unter `docs/evidence/oip0061/` |
|---|---|
| Rust fmt/check/clippy, warnings denied | PASS — rust-regression.json und Einzel-Logs |
| Workspace-/Capability-/MCP-/Storage-/Recovery-Tests | PASS, **89**; darunter elf MCP-Grenztests — rust-workspace-tests.log |
| OPC-UA beide Backends | PASS, **36** — rust-interop-tests.log |
| open62541-only | PASS, **2** — rust-open-only-tests.log |
| Check/Clippy ohne Defaultbackend, open-only und beide | PASS — rust-regression.json |
| cargo-deny | PASS mit unveränderten Advisory-Ausnahmen, keine Behebung |
| Build einschließlich offiziellem SDK-Testclient | PASS, --locked |
| Headless zwei Quellen, Reconnect, Shutdown, Restart/Crash | PASS, sieben Phasen — headless/report.json |
| Modellfreier tatsächlicher MCP-stdio-E2E | PASS — mcp/report.json und sdk-transcript.json |
| Dart Format | PASS, keine offenen Formatänderungen |
| Flutter Analyze | PASS, null Issues |
| Flutter Tests | PASS, **80** — flutter-tests.log |
| Flutter Web Release, lokale CanvasKit-Ressourcen | PASS — flutter-web-build.log |
| Browser-Fachregression | PASS, **16** — browser/browser-verification.json |
| Spectrum-Interaktionen | PASS, **4 Gruppen** — interactions/spectrum-interactions.json |
| Gelieferte Visual-Automation erneut ausgeführt | PASS, **30** aktuelle Captures — visual/responsive-verification.json |
| Zusätzliche vollständige Theme-/Breakpoint-Matrix | PASS, 120 + 45 aktuelle Captures — themes/report.json |
| Native macOS | PASS, ein Alarm-/Reconnect-Test; eigener Demo-Core sauber beendet — ui-regression.json |
| Gemeinsamer Spectrum/REST/SSE/MCP-E2E | PASS — integration/report.json |
| Neue Runtime-Messung | PASS, tatsächlich gemessene Werte — runtime-resources.json |

Die Gruppen überlappen und sind keine künstlich addierbare Gesamttestzahl. Die Supplier-Zahlen 54/16/30/66 bleiben historische Nachweise des isolierten Pakets; oben stehen erneut ausgeführte integrierte Prüfungen. Chrome/Flutter/Xcode/Rust bereits vorhanden; keine globale Installation. Node-Testinstallation `npm ci --ignore-scripts` erneut ausgeführt, gepinnte bestehende Playwright-Version, keine neuen Dependencies und null gemeldete npm-Vulnerabilities. Der bekannte Cupertino-Font-Buildhinweis bleibt nicht blockierend; tatsächliche Builds und Browserglyphen geprüft.

## Zusammenhängender E2E mit derselben Runtime

`tests/oip0061/integration.mjs` verwendet den unveränderten offiziellen Rust-SDK-Client `mcp_probe`. Dieser startet **einen** Core im tatsächlichen Modus `--mcp-stdio --mcp-rest`, mit zwei externen lokalen Simulatoren, eigener SQLite und dem finalen Flutter-Webverzeichnis. Browser, REST/SSE und MCP bedienen diese gemeinsame Runtime. Es wird kein zweiter MCP-Core auf eine schon geöffnete SQLite-Datei angesetzt.

1. Zwei Simulatoren mit eigenen IDs/Ports und Seeds 42/77 starten; Source-Health, Registry-IDs und SQLite-Anteile prüfen. MCP Discover liefert sechs Tools und acht Resources im Zweiquellenprofil.
2. Spectrum im frischen Browser öffnen, alle fünf Ansichten und tatsächlich empfangene Assetbytes prüfen. Neue tatsächliche Messprobe nachweisen.
3. A mit vorhandenem lokalen Simulator-CLI im `critical_sensor`-Szenario starten. Reale Temperaturänderung, autoritativer Core-Alarm und sichtbarer UI-Wert; B bleibt getrennt. Kein OPC-UA-Schreiben und kein neuer Steuerendpoint.
4. A stoppen: B accepted/Persistenz laufen weiter. A-Details stale/degraded, B aktuell. Core bleibt bei live verbundener API tatsächlich Degraded. REST, SSE und MCP-Sourcezustände stimmen überein; Device B enthält ausschließlich B-Werte.
5. A wieder starten; Reconnect, frische neue Samples, persistierte Source-A-Datenlücken und source-kontextuelle Diagnostics nachweisen.
6. MCP-Client schließt stdin; derselbe Core inklusive REST/Writer wird kontrolliert beendet. Quellen stoppen; denselben Datenbestand zunächst ohne Quellen erneut starten: gespeicherte Werte stale, Reachability unknown, Empfangszeit null. Flutter reconnectet, MCP liefert dieselben stale Werte. Erst tatsächlicher Quellenempfang erzeugt wieder Live/Ready. SQLite quick_check ok, keine doppelten Observation-Keys.
7. Alle eigenen Testprozesse kontrolliert beenden. Separater vollständiger MCP-E2E prüft zusätzlich Denials, fremde Sources, manipulierte Parameter, gesperrte Mutationen, übergroße Inputs, acht konkurrierende Reads, langsamen Client und stdio-only ohne HTTP-Listener.

[Alarm](evidence/oip0061/integration/source-a-real-sensor-alarm.png), [A offline](evidence/oip0061/integration/source-a-offline.png), [B bleibt frisch](evidence/oip0061/integration/source-b-still-fresh.png), [Core Degraded trotz live API](evidence/oip0061/integration/core-degraded-with-live-api.png), [Datenlücken](evidence/oip0061/integration/source-a-gap.png), [stale Restore](evidence/oip0061/integration/core-restored-stale.png), [neuer Empfang](evidence/oip0061/integration/core-restarted-live.png).

## Performance und begrenzte Aussagekraft

Gleicher Chrome/CanvasKit-Release-Workflow, 1440×1000, Normalbetrieb, jeweils acht Sekunden und 481 Frames:

| Kennzahl | Alter Build | Finales Spectrum |
|---|---|---|
| Frame Median | 16,7 ms | 16,7 ms |
| Frame p95 | 16,7 ms | 16,7 ms |
| Frame Maximum | 16,8 ms | 16,8 ms |
| Long Tasks | 0 | 0 |
| JS Heap used | 31.868.554 Bytes | 37.425.967 Bytes |

[Vorher-/Nachher-Rohwerte](evidence/oip0061/after/report.json), [eigener Prozess-CPU-/RSS-Lauf](evidence/oip0061/runtime-resources.json). Separater achtsekündiger Prozesslauf: eigenes Chromium insgesamt etwa **17,0 % eines logischen CPU-Kerns**, Core-Prozess CPU-Zeit +0,17 s, Core-RSS am Ende 27.072 KiB. Chromium-RSS je eigenem PID ist enthalten; Summen teilen Speicher und sind kein Maß für eindeutige physische RAM-Belegung oder einen Peak. Keine dieser Messungen wird als Hosttelemetrie in OIP ausgegeben.

Heap ist eine punktuelle GC-abhängige Aufnahme; kein Leak-Nachweis oder SLA. Kein begründeter erheblicher Frame-/Long-Task-Rückschritt im vergleichbaren kurzen Lauf. Die Visual-Suite liefert einen weiteren getrennten Messlauf. Node-Listen bleiben paginiert, Gerätefilter memoisiert pro Snapshot/Input, sichtbare Views reagieren auf die vorhandenen begrenzten SSE-Snapshots. Codeaudit: statische Decorations, keine neuen Blur-/Daueranimationen, RepaintBoundaries und begrenzter Sitzungstrend. Selektive Flutter-Widget-Rebuild-/UI-/Rasterprofilierung mit DevTools ist **NOT_TESTED**; Browser-Frame-Pacing wird nicht als solches Profil ausgegeben.

## Integrationsbefunde und verbleibende Grenzen

- Der erste erweiterte Matrix-Runner wartete nicht ausreichend auf die animierte Tablet-Drawer-Navigation. Er wurde mit sichtbarem Drawer und tatsächlich erwarteten Seitenmarkern synchronisiert; keine Produktänderung dafür. Früher Fehlerreport bleibt unter `development/`.
- Der übernommene Slow-Client-Test verlangte nach fixen 1,2 s neue eindeutige SQLite-Zeilen. Unter parallelem Testbetrieb ist das keine deterministische Aussage über idempotente Ingestion. Der neue Evidenz-Runner prüft stattdessen einen tatsächlichen autorisierten OPC-UA-/REST-Read und bestätigten Fortschritt aus Zeilen + duplicate_count bei ungelesener MCP-Ausgabe. Der unveränderte Rust-Test mit physisch blockiertem Duplex-Ausgabekanal besteht zusätzlich.
- Ein erster Core-Status-Widgettest suchte ein außerhalb des kleinen Testviewports liegendes Semantics-Element; er verwendet den expliziten Desktop-Viewport. Der Browser-Locator wurde gegen den tatsächlichen Flutter-Semantics-Text statt eines nicht vorhandenen aria-label-Attributs geprüft. Fehlerberichte erhalten; keine Tests gelöscht oder produktiven Fehler ignoriert.
- Es gibt weiterhin keine Infrastructure-/Organization-/Tenant-APIs oder produktives Multi-Tenant-RBAC. Wiederverwendbare Spectrum-Komponenten enthalten keine feste Infrastructure-ID oder eigene Berechtigungslogik; die singuläre Workspace-Beschriftung ist ein lokaler Präsentationskontext. Bestehende Simulator-/Primärquellenbindung (`M-01`) liegt in den bestehenden Features/Verträgen, nicht in einer neu eingeführten Tenant-Architektur.
- UI-OPC-UA-Browser bleibt auf die vom Backend bestimmte Primärquelle ausgerichtet. REST und MCP unterstützen den bestehenden Source-Parameter; im MCP-E2E werden B-Nodes explizit gelesen. Kein neuer Source-Konfigurations-/Selector-Workflow in diesem Integrationsauftrag.
- Keine persistente Theme-Auswahl, produktive Diagnostik/Historienverwaltung oder vollständiges Event-Replay. Physische Topologie/VPN-/Hostmetriken bleiben unbekannt beziehungsweise ausdrücklich simuliert.

## Exakte Start- und Testbefehle

Die oben laufende Vorschau ist bereits gestartet. Für einen neuen lokalen Start freie Ports und einen eigenen DB-Pfad verwenden; keine fremden Prozesse beenden und niemals denselben SQLite-Bestand parallel öffnen:

```sh
cd /Users/benny/Code/open-industrial-platform
cargo build --locked --workspace
cd apps/flutter
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
cd ../..
target/debug/oip-server --demo --port 18087 --opcua-port 14887 \
  --database target/operator-spectrum.sqlite --web-dir apps/flutter/build/web
```

Dann `http://127.0.0.1:18087` öffnen, Ctrl-C stoppt kontrolliert. Die **aktuell laufende, geprüfte** Instanz bleibt 18086, PID 2091. Diese eigene Hintergrundvorschau kann nach Prüfung des PID/Arguments mit `kill -INT 2091` beendet werden; die Testinstanzen sind bereits aus.

Headless/MCP-Start für zwei externe Simulatoren unverändert in [OIP-006](oip-006-verification.md). Dortigen MCP-Start um `--mcp-rest --web-dir /Users/benny/Code/open-industrial-platform/apps/flutter/build/web` ergänzen, um denselben Core grafisch zu bedienen. MCP bleibt stdio; keine neue MCP-HTTP-Schnittstelle.

Tatsächlich verwendete Regression:

```sh
cd /Users/benny/Code/open-industrial-platform
python3 tests/oip0061/regress_rust.py
python3 tests/oip0061/mcp_acceptance.py
OIP_EVIDENCE_DIR=docs/evidence/oip0061/headless python3 tests/oip004/acceptance.py
python3 tests/oip0061/ui_regression.py
node tests/oip0061/integration.mjs
node tests/oip0061/theme_matrix.mjs
node tests/oip0061/resources.mjs
cd apps/flutter
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test --reporter expanded
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
cd test
npm ci --ignore-scripts
```

`regress_rust.py` wiederholt die vorhandenen zwölf Rust-/Backend-Gates plus deny/build/examples und setzt nur pro Prozess die bestehenden platzsparenden Debug-/Incremental-Umgebungsvariablen. Exakte Einzelargumente in `rust-regression.json`. Browsermatrix/Resource-Sampler lesen die eigene `preview-process.json`; für einen anderen Port diese lokale Testkonfiguration passend setzen. UI-/MCP-/E2E-Runner starten und stoppen eigene Prozesse/DBs selbst. Vorher-Capture wurde zwingend **vor** Integration mit `OIP_STAGE=before node tests/oip0061/capture.mjs` erstellt, final mit `OIP_STAGE=after`; Source-/Buildbaseline liegt extern und wird nicht automatisch zurückkopiert.

## Security und Abschluss-Gates

**RUSTSEC-2023-0071 bleibt produktiver Blocker.** Die vorhandenen Ausnahmen RUSTSEC-2023-0089/2024-0449 bleiben unverändert offen. Keine öffentlichen Listener, produktiven Remote-Verbindungen, Industrieanlagen, Maschinensteuerung, OPC-UA-Schreiboperationen, Secrets oder erweiterten Grants. Die lokale Policy und das nicht dauerhafte Audit bleiben Entwicklungsgrenzen, keine Produktionsfreigabe.

NOT_TESTED: Remote-CI-Matrix, andere reale Browser/OS-/Mobilplattformen, Hardware-Stromausfall, industrielle Langzeit-/Last-/Leaktests, Flutter-DevTools-Rebuild-/Rasterprofile und produktive Remote-/Tenant-Authentifizierung. Keine dieser Eigenschaften wird aus kurzen lokalen Messungen behauptet.

HTML-Referenz vor/nach identisch: `bd9f9d8696ed48676055ee9a2cd0afb29e6c3d59e0945e662d925306f73c753e`. Kein Commit, Push, Branchwechsel, Deployment, Git Clean oder Verlust bestehender Source-Dateien. Historische Berichte/Evidenz nicht überschrieben. [Maschinenlesbare Gates und Testergebnisse](evidence/oip0061/test-summary.json).

| Gate | Ergebnis |
|---|---|
| G1 Provenance | PASS — Archiv, Manifest, 79-Dateien-Basis, Rundreise, externe Baseline |
| G2 Reconciliation | PASS — 15 Payloads einzeln abgeglichen; notwendige UI-Vertrags-/Evidenzkorrekturen belegt |
| G3 Visual Acceptance | PASS — sichtbares Spectrum, echter neuer Release und Vorher-/Nachher-Aufnahmen |
| G4 Themes | PASS — Spectrum/Graphite/Daylight, acht Breiten, fünf Ansichten |
| G5 Functionality | PASS — Fachinteraktionen, Datenqualität, echte Core-/Source-Zustände und erhaltene API-/SSE-Fehlerpfade |
| G6 MCP | PASS — unveränderter Core, zwölf Reads, sechs Tools, modellfreier stdio-E2E |
| G7 Reliability | PASS — zwei Quellen, Isolation, Reconnect, Persistenz/Restore bis UI und MCP |
| G8 Regression | PASS — 89 Rust, 36 Interop, 80 Flutter, 16 Browser, native macOS |
| G9 Security | PASS — keine erweiterten produktiven Rechte oder externen Runtime-Dienste |
| G10 Isolation | PASS — keine fremden Sessions/Arbeitskopien/Services verändert, kein Git-Write |

OIP_006_1_SPECTRUM_INTEGRATION_PASS
