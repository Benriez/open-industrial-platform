# OIP-006 — Native MCP Verification

Datum: 2026-11-05, Europe/Berlin. Ausschließlich lokale Simulation. **OIP IS AGENT-FIRST BY DESIGN.** Keine Produktionsfreigabe.

## Baseline, Autorität und Provenienz

Core-Session `01a1a3b3-9469-7311-be9a-1218be181ebc`, Rust/MCP-Workstream. Die vier angeforderten OIP-005-/005.1-Berichte, Capability-Verträge, ApplicationServices, Runtime, REST/SSE, Audit/Permissions, Tests und CI wurden geprüft. Aktuell weiterhin `main`, unborn HEAD, null tracked Dateien. Kein Initial-Commit, Push oder Branchwechsel.

Vor Source-Änderungen wurden 575 nicht ignorierte Projekt-/Source-/Evidenzdateien mit Größen und SHA-256 inventarisiert und extern archiviert:

`/Users/benny/Documents/OIP-Handoffs/core-006-baseline-20261104T224649Z/project-baseline.tar.gz`

SHA-256: `120b85deb7746180313ab9cca6dcad701ebfc0caa239e185b31562d1078c2174`.

Alle Archivmember wurden unabhängig wieder gelesen und gegen das Inventar verglichen. Keine PKI, privaten Schlüssel, Secrets, Runtime-Datenbanken, installierten Dependencies oder Build-Caches im Source-Archiv. Ihre Originale blieben erhalten. [Baseline](evidence/oip006/baseline.json), [Sessionprüfung](evidence/oip006/sessions.json).

Bekannte Spectrum-Session `ses_e574f4783ffe57EjpGTv3i535K` mit separater Arbeitskopie unter `/Users/benny/Code/oip-ui-isolated/…`; keine UI-Schreibautorität dieser Core-Session. Der verfügbare lokale Aktivstatus meldete keine aktiven konkurrierenden Core-Tasks. Bereits laufende fremde Server, darunter Ports 18080, 18735 und 18736, wurden nicht beendet oder verändert. Eigene Tests verwenden eigene Prozesse, freie Loopback-Ports und eigene DBs. Sessionbeobachtung ist keine globale Dateisperre.

Die Baseline wurde erneut aus einer unveränderlichen Kopie ausgeführt: **78 Workspace-Tests einschließlich Doc-Tests PASS**, [baseline-frozen-tests.log](evidence/oip006/baseline-frozen-tests.log). Ein früherer Lauf bestand zwar alle 78 Testfälle, sein nachlaufender Doc-Test sah bereits eine in Arbeit befindliche neue Moduldatei; dieser Mischlauf wird nicht als saubere Baseline gewertet.

## Implementierung

[Architektur](architecture/oip-006-mcp.md), [fachliches Mapping](architecture/oip-mcp-capability-mapping.md), [generierter maschinenlesbarer Katalog und Schemas](evidence/oip006/capability-mapping.json).

- Offizielles `rmcp 3.8.0`, MCP 2026-07-28 Discover/per-request metadata und Legacy 2025-11-25 Initialize tatsächlich getestet. Tokio-stdio, kein MCP-Netzwerktransport, kein Modell.
- Sechs Tools: Devices, Device, Observations, Sources, Events und OpcuaNodes, mit den bestehenden IDs und typisierten Verträgen. Sechs globale Resource-Operationen plus registrierte Source-Health-URIs. **12 bestehende Read-Capabilities exponiert, SimulationScenarioSet gesperrt.** Nicht implementierte Administration/OT/Shell/Datei-Funktionen bleiben nicht discoverbar.
- Ein Prozess, eine CoreRuntime, ein Writer, eine gemeinsame `Arc<ApplicationServices>` für REST und MCP. Keine zweite Ingestion, Source-Registry, SQL-Abstraktion oder OPC-UA-Implementierung im Adapter.
- Vertrauenswürdige explizite lokale Read-Policy; Actor/Grants/SourceScope nie aus Toolparametern. Dieselbe Policy gilt für optionalen gleichzeitigen REST-Zugriff. Keine produktive Identitäts-/Tenant-Garantie.
- Schemas aus vorhandenen Rust-Verträgen über optionales neutrales Core-Feature; keine rmcp-Abhängigkeit im fachlichen Core. Adapter-Inputs strikt begrenzt, unbekannte Felder abgelehnt, Node-Pagination höchstens 100. Stale/Unknown/Quality/Provenienz unverändert.
- Prozessübergreifende kanonische DB-Sidecar-Sperre, absoluter MCP-DB-Pfad, kontrollierter EOF/Signal-/Transport-Shutdown und getrennte Daten-/stdio-Drain-Grenzen. Kein implizites Attach an einen bestehenden Core.
- Bestehender Audit-Port erfasst zusätzlich unterbrochene autorisierte Service-Futures. Strukturierte Rejections ohne untrusted Payloads. SDK-Rohpayload-Logging im MCP-Modus auch gegen spezifisches RUST_LOG deaktiviert.

Neue Dateien liegen ausschließlich in `crates/oip-server/src/mcp*`, dessen Tests/Beispielen, `examples/mcp-read-*.json`, `tests/oip006`, neuer Dokumentation/Evidenz. Bestehende Änderungen betreffen optionale Core-Schema-Metadaten, Server-Composition/Serviceinjektion/Audit-Unterbrechung/Ownership, Cargo-Lock und Ignore für erzeugte Ownership-Sidecars. Keine neue Crate, Migration, Geräteintegration oder Produktfunktion außerhalb dieses Adapters. Flutter, OPC-UA-/Storage-Implementierung und historische Berichte bleiben unverändert.

## Tatsächlich ausgeführte Verifikation

Host: macOS arm64, Rust 1.93.0, Flutter 3.22.0 / Dart 3.4.0, vorhandenes Xcode/Chrome/Node, Homebrew SQLite für STRICT. Keine globale Toolchain-Installation. Dependency-Audit mit unveränderten Advisory-Ausnahmen; [deny.log](evidence/oip006/deny.log).

| Prüfung | Ergebnis / Evidenz unter `docs/evidence/oip006/` |
|---|---|
| Gefrorene Baseline | PASS, 78 Rust-Tests und Doc-Tests — baseline-frozen-tests.log |
| cargo fmt/check/clippy --all-targets, warnings denied | PASS — fmt.log, check.log, clippy.log |
| Rust Workspace | PASS, **89 Tests = 78 vorhandene + 11 neue MCP-/Ownership-/Audit-Tests** — workspace-tests.log |
| OPC-UA beide Backends | PASS, **36** — interop-tests.log |
| open62541-only | PASS, **2** — open-only-tests.log |
| Kein Defaultbackend/open-only/beide: check und clippy | PASS — rust-regression.json und einzelne Logs |
| SQLite/Recovery/Permissions/Source-Scope | PASS, bestehende 11 Storage-, 12 Reliability- und Capability-Tests im Workspace; zusätzliche MCP-Grenztests |
| cargo-deny | PASS mit unveränderten 2023-0071/2023-0089/2024-0449-Ausnahmen; keine Behebung |
| Build Server und modellfreier SDK-Client/Katalog | PASS — build-final.log, build-examples.log |
| Headless-E2E einschließlich Prozess-Crash | PASS, sieben Phasen — headless/report.json |
| Echter MCP-stdio-Client + zwei Quellen | PASS — e2e/report.json, e2e/sdk-transcript.json und Prozesslogs |
| Dart-Formatierung ohne Änderungen | PASS — dart-format.log |
| flutter analyze | PASS, null Issues — flutter-analyze.log |
| Flutter-Regression | PASS, **47** — flutter-tests.log |
| Flutter Web Release, lokale CanvasKit-Ressourcen | PASS — flutter-web-build.log |
| Browser-Fachregression | PASS, **16** — browser/browser-verification.json |
| Native macOS-Integration | PASS, **1**, Alarm/Reconnect — native-macos.log |
| Demo-Backend nach Browser/native sauber stoppen | PASS — ui-regression.json und ui-backend.log |
| UI-/Design-/Provenienz-Integrität | PASS — final-integrity.json |

Testgruppen überlappen und werden nicht künstlich addiert. Flutter bleibt exakt der kanonische OIP-005.1-Stand. Browserprüfungen decken fünf Ansichten, Desktop/834/390/320 px, Alarm, SSE-Fehler, Reconnect und 1.000 Nodes ab. Aktuelle Screenshots liegen im Browser-Evidenzverzeichnis; kein Spectrum-Redesign und keine erneute Behauptung von 30 OIP-005.1-Captures.

Die elf neuen Rust-Tests prüfen sechs Tools über echtes SDK-Protokoll gegen direkte Service-/REST-Ergebnisse, globale Resource-Parität einschließlich SSE-Queue/Snapshot, fehlende Grants/fremde Sources/Resource-Denials, malformed/oversized Inputs und gesperrte Mutationen, Cancellation einer Service-Future, echte SDK-Cancel-Notification, Unterbrechungs-Audit am realen ApplicationService, Outputgrenze, 16er-Admission-Fenster, physisch blockiertes Ausgabemedium bei weiterlaufender Persistenz sowie Doppelstart/Symlink/Neustart-Ownership. Im eingefrorenen Snapshotvergleich wird ausschließlich aufrufzeitabhängiges `generated_at_ms` normalisiert; Messidentitäten, Quality, Freshness, Provenienz und Messzeitstempel werden nicht entfernt.

## Zusammenhängender MCP-E2E

Der ausführbare Runner `python3 tests/oip006/acceptance.py` startet zwei echte lokale OPC-UA-Prozesse mit Seeds 42/77 und einen vom **offiziellen rmcp-Testclient** gestarteten tatsächlichen `oip-server --mcp-stdio --mcp-rest`. Der Client ist `crates/oip-server/examples/mcp_probe.rs`; keine modellabhängigen Prompts, kein HTTP-Proxy.

A: Beide Sources, zwei tatsächliche Registry-IDs (`M-01`, `sim-b:M-01`), echte Observations und SQLite-Anteile, REST und SSE-Vollsnapshot. Zweiter Core auf demselben Bestand wird vor Collector-Start abgewiesen; dessen stdout bleibt leer.

B/C: Modernes Discover, sechs Tools und im Zweiquellenprofil acht Resources, Schemas und Read-only-Annotationen. Alle sechs Tools ausführbar. 1.000 Bulk-Nodes in zehn Seiten zu 100, Source-B-Provenienz erhalten; neue Messproben nachgewiesen.

D/E: A kontrolliert stoppen, A disconnected/degraded, B accepted-Zähler und Reads laufen weiter. MCP-/REST-Source-Zustände stimmen überein. A neu starten, tatsächliche Freshness/Ready und persistierte Source-A-Lücken/Reconnected-Records nachweisen. Kein fehlender Wert wird Null, kein Replay behauptet.

F: MCP-stdin schließen, denselben Core einschließlich REST sauber drainen; Quellen stoppen. Neustart desselben SQLite-Bestands mit Legacy-Initialize: gespeicherte Werte stale, Reachability unknown, letzte Runtime-Empfangszeit null. Erst echte neue Quellenbeobachtung erzeugt Live-Zustände. Keine doppelten Observation-Keys, SQLite quick_check ok.

G: Scope-A-Client kann B und globale Snapshots nicht lesen. Grants/Actor-Parameter, unbekannte Device-/Resource-/Toolnamen, Konfigurationszugriff, Mutation, ungültige Zeitstempelfelder/Listen/Limits und übergroße Eingaben werden verweigert. Acht gleichzeitige SDK-Reads und 25 wiederholte Reads funktionieren. Ein Test-Secret-Sentinel erscheint nicht in Antworten oder Produktlogs, auch unter aggressivem RUST_LOG. Audit-/Scope-/Korrelationseinträge vorhanden. Ergänzend echter stdio-only-Prozess ohne HTTP-Listener; Raw-Client mit kaputtem JSON, ungültiger RPC-Form, >16-KiB-Zeile und anschließend gültigem Ping. Ein nicht lesender Ausgabekonsument blockiert die Ingestion nicht; stdout enthält ausschließlich JSON-RPC. Alle eigenen Prozesse kontrolliert beendet.

H: Workspace/Interop/Storage/Capability/Headless sowie unveränderte Flutter-Tests, Web, Browser und macOS wie oben. Source-/Design-Hashes und Git-/Sessionstatus abschließend kontrolliert. [Zusammenfassung](evidence/oip006/test-summary.json).

## Performance und Grenzen

Messwerte des lokalen 25-Read-Laufs stehen unverändert in `e2e/report.json` unter `G_authorization_security_performance` (`read_latency_ms`, `rss_kib`). Tatsächlich gemessen: 1.37 ms Mittel, 1.58 ms Maximum; RSS 35104 KiB nach dem Leselauf. Es ist ein kurzer Entwicklungslauf, keine SLA oder Peak-/Langzeitmessung. Acht konkurrierende Reads wurden separat tatsächlich ausgeführt. Die 1.000 Nodes bleiben paginiert, der Writer nimmt weiter auf. Feste Limits und Cancellation-Verhalten einschließlich konservativer Cancel-Admission-Reservation sind in der Architektur dokumentiert.

Der stdio-Prozess besitzt den Core: Client-Disconnect, Window-Überlast oder dauerhaft blockierte Ausgabe beenden ihn kontrolliert. Eine dauerhaft unabhängig vom Agenten laufende Instanz mit lokalem Attach erfordert einen eigenen abgesicherten IPC-/Transportauftrag; hier wird kein gemeinsamer Daemon vorgetäuscht. Read-only Resources werden erneut abgefragt, keine Subscriptions. Maximal 100 Kontrollereignisse sind keine vollständige Historie. Ein Store pro kooperierendem Core-Prozess, kein Multi-Host-Lease, kein dauerhafter Ingestion-Spool.

## Entwicklungsfehler und ihre Behandlung

Der Host erreichte während zusätzlicher Debug-Builds weniger als 500 MiB freien Speicher. Der eigene Build wurde gestoppt. Ausschließlich neu in diesem Auftrag erzeugte Incremental-Verzeichnisse wurden entfernt. Ein anschließender Versuch, Debugdaten neuer rlib-Dateien zu entfernen, beschädigte deren Rust-Metadaten; diese neuen Artefakte wurden verworfen und korrekt ohne Debug-/Incremental-Daten neu gebaut. [Genauer Artefaktumfang](evidence/oip006/build-space.json). Keine bestehende Source-/Evidenzdatei oder fremde Buildablage bereinigt. Für reproduzierbar kleine Builds wurden lokale Prozess-Environmentvariablen verwendet, keine globale Cargo-Konfiguration geändert.

Die erste Dateisperre auf SQLite selbst verursachte DatabaseBusy auf macOS; ersetzt durch die geprüfte kanonische Sidecar. Ein Rohprotokolltest erwartete fälschlich eine Antwort auf syntaktisch unlesbares JSON; gegen das aktuelle SDK geprüft und in separate Discard-/Invalid-Request-Assertions aufgeteilt. Ein späterer Demo-Shutdown zeigte eine Regression durch zu frühe Simulator-Cancellation; die Reihenfolge wurde wiederhergestellt und MCP-Cancellation getrennt. Browser/native einschließlich sauberem Backend-Abschluss und MCP-E2E danach erneut geprüft. Frühe Logs/Fehler bleiben unter `development` bzw. den ausdrücklich benannten Entwicklungslogs erhalten und gelten nicht als finale PASS-Evidenz.

## Exakte Startbefehle

Keine bereits laufende Core-Instanz für denselben Bestand verwenden. Alte Binaries kontrolliert stoppen; die neue Sperre schützt nur kooperierende aktuelle Starts. Verfügbare lokale Ports wählen.

```sh
cd /Users/benny/Code/open-industrial-platform
cargo build --locked --workspace
cargo build --locked -p oip-server --examples
```

Zwei separate Terminals:

```sh
cd /Users/benny/Code/open-industrial-platform
target/debug/oip-simulated-server --port 14841 --seed 42 --tick-ms 250
```

```sh
cd /Users/benny/Code/open-industrial-platform
target/debug/oip-simulated-server --port 14842 --seed 77 --tick-ms 250
```

MCP vom Client starten lassen, stdin/stdout nicht als interaktives Terminal bedienen:

```sh
/Users/benny/Code/open-industrial-platform/target/debug/oip-server \
  --config /Users/benny/Code/open-industrial-platform/examples/core-local.json \
  --database /Users/benny/Code/open-industrial-platform/oip-core.sqlite \
  --mcp-stdio \
  --mcp-policy /Users/benny/Code/open-industrial-platform/examples/mcp-read-local.json
```

Für **denselben** Prozess mit Flutter/REST zusätzlich `--mcp-rest --web-dir /Users/benny/Code/open-industrial-platform/apps/flutter/build/web`. Port aus core-local.json: Loopback 18084. Nicht zusätzlich einen separaten REST-Core auf derselben DB starten. Eine Source-A-Policy ist als `examples/mcp-read-source-a.json` vorhanden; sie erlaubt ausdrücklich keine globalen Snapshots/Health-Aggregate und ist deshalb kein All-Source-Flutter-Kontext.

Generische Clientkonfiguration (Launcher-Feldnamen sind Clientkonvention, keine eigene MCP-Protokollerweiterung):

```json
{
  "mcpServers": {
    "oip-local-read": {
      "command": "/absolute/path/open-industrial-platform/target/debug/oip-server",
      "args": [
        "--config", "/absolute/path/open-industrial-platform/examples/core-local.json",
        "--database", "/absolute/path/open-industrial-platform/oip-core.sqlite",
        "--mcp-stdio",
        "--mcp-policy", "/absolute/path/open-industrial-platform/examples/mcp-read-local.json"
      ]
    }
  }
}
```

Die Datei ist lokal vom Operator zu schützen. Keine Credentials oder Agent-/Anbieterbindung. Ohne angeschlossenen Client funktioniert weiterhin der gewöhnliche Headless-Core: `target/debug/oip-server --config examples/core-local.json --no-web`.

## Exakte Wiederholungsbefehle

Vom Repository-Root; bei knapper Platte optional nur für diese Shell:

```sh
export CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 CARGO_BUILD_JOBS=2
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace -- --test-threads=1
cargo test -p oip-opcua --features open62541-backend -- --test-threads=1
cargo test -p oip-opcua --no-default-features --features open62541-backend -- --test-threads=1
target/oip-002-tools/bin/cargo-deny check advisories licenses bans sources
cargo build --locked --workspace --examples
cargo build --locked --workspace
python3 tests/oip006/acceptance.py
OIP_EVIDENCE_DIR=docs/evidence/oip006/headless python3 tests/oip004/acceptance.py
python3 tests/oip006/ui_regression.py
```

Zusätzlich ausgeführte Check-/Clippy-Backendkombinationen stehen mit exakten Argumenten in `rust-regression.json`. `ui_regression.py` startet/stoppt ausschließlich seine eigene Demo-Instanz, führt Browser und nativen Test nacheinander aus und prüft den Backend-Abschluss. Voraussetzungen: vorhandenes Chrome, gepinnte bestehende Playwright-Testinstallation in apps/flutter/test/node_modules, vorhandene Flutter-/Xcode-Toolchain. `OIP_SQLITE_CLI` kann die vorhandene SQLite-CLI für Acceptance überschreiben.

```sh
cd apps/flutter
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test --reporter expanded
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
```

## Security, NOT_TESTED und Abschluss-Gates

**RUSTSEC-2023-0071 bleibt Produktionsblocker.** Ausnahmen 2023-0089 und 2024-0449 bleiben offen und unverändert. Keine produktiven Anlagen, OPC-UA-Schreiboperationen, Maschinensteuerung, öffentlichen MCP-Endpunkte, Cloud-Abhängigkeiten, Credential-Ausgaben, Commits, Pushes oder Deployments. Lokale Read-Policy und Log-Audit sind kein produktives Multi-Tenant-RBAC oder dauerhaftes Audit.

NOT_TESTED: Remote-CI-Plattformmatrix, nativer MCP-Server auf Windows/Linux, andere unabhängige MCP-Clientimplementierungen, Safari/Firefox/Edge, reale Mobilgeräte, Hardware-Stromausfall, Langzeit-/Leak-/industrielle Lasttests, produktive Identitäten und Remote-Auth. Ein realer offizieller SDK-Client und echte stdio-Prozesse sind geprüft; keine allgemeine Zertifizierung beliebiger Clients behauptet.

HTML-Referenz vor/nach unverändert: `bd9f9d8696ed48676055ee9a2cd0afb29e6c3d59e0945e662d925306f73c753e`. Keine Flutter-Quelländerung. Historische OIP-005/005.1-Berichte bleiben historische Nachweise.

| Gate | Ergebnis |
|---|---|
| G1 Architecture | PASS — Adapter ausschließlich auf CapabilityService, neutrale Core-Verträge |
| G2 Runtime | PASS — gemeinsame Serviceinstanz/Runtime, kanonische Ownership und Doppelstart-Abweisung |
| G3 Protocol | PASS — echter SDK-Client, Discover 2026-07-28 und Initialize 2025-11-25, Tools/Resources |
| G4 Capability parity | PASS — alle zwölf Read-Capabilities gegen direkte Services und REST/SSE |
| G5 Authorization | PASS — Permissions, Source-Scope, Resource-Denials, kein Parameter-Grant |
| G6 Reliability | PASS — Isolation/Reconnect/Restore, Cancellation, begrenzte Ausgabe/Admission, kontrollierter Shutdown |
| G7 Security | PASS — ausschließlich lokale Reads, Mutationen gesperrt, keine MCP-Netzwerkfreigabe |
| G8 Regression | PASS — Rust/Interop/Storage/REST/SSE/Flutter/Browser/native einschließlich sauberem Demo-Shutdown |
| G9 Isolation | PASS — Flutter unverändert, keine fremden Prozesse/Schreibbereiche verändert, kein Git-Write |
| G10 Reproducibility | PASS — SDK-Client, E2E-Runner, Schemas/Mapping, Logs und Startbefehle |

OIP_006_MCP_PASS
