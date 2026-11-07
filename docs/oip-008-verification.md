# OIP-008 — Multi-Infrastructure, Identity & Tenant Isolation

2026-11-05. OIP IS AGENT-FIRST BY DESIGN. Ausschließlich lokale Simulation; **keine Produktionsfreigabe**.

## Baseline, Session und Isolation

Ausgangspunkt: `main`, sauber, Commit `a27e7b1e01dc1cb6f4d97c34319b0aa6d7321871`, 319 getrackte Dateien. Keine Initialisierung/History-Umschreibung. Arbeit ausschließlich in `/Users/benny/Code/open-industrial-platform-worktrees/oip-008`, Branch `feature/oip-008-multi-infrastructure` vom exakten Baseline-Commit. Core-Session `01a1a3b3-9469-7311-be9a-1218be181ebc` besitzt Rust-/Storage-/Authorization-/REST-/MCP-/Test-/Dokumentations-Scope. Die separaten Reviewer arbeiteten ausschließlich lesend.

OpenCode-Aktivliste beim Preflight ohne weiteren aktiven Workstream; ein anderer lokaler Sessiondienst war nicht auswertbar. Das ist keine globale Schreibsperre. Bestehende UI-Arbeit unter `/Users/benny/Code/oip-ui-isolated/OIP-UI-OPCUA-2027-20261105` und vorhandene Services auf18080/18086/18096 wurden nicht geändert oder beendet. Während der Arbeit beobachtete weitere isolierte UI-Vorschauen auf18097 (OPC-UA Phase2) und18098 (Network/VPN) blieben ebenfalls unverändert. Alle eigenen Prozesse erhielten separate Loopback-Ports und Datenbanken. Flutter-Regression verwendete die byteidentischen kanonischen Sources mit vorhandenen ignorierten Tool-Caches; keine UI-Quelländerung.

Zusätzliches externes Baseline-Archiv: `/Users/benny/Documents/OIP-Handoffs/oip008-git-baseline-20261105T160946Z/canonical-oip007.tar`, SHA-256 `d0466a7e70d1166125858f5fcc2fff6bcb3fd0251d9405806981ca0d8361742a`. Alle319 Archivdateien wurden unabhängig gegen die Git-Blobs verifiziert. Ältere Backups und historische Verifikationsberichte bleiben erhalten. [Preflight](evidence/oip008/preflight.json), [Backup](evidence/oip008/backup.json).

## Implementierung und Architektur

- [Domain/Architektur](architecture/oip-008-multi-infrastructure.md), [ADR0003](decisions/0003-multi-infrastructure.md): typisierte globale Identitäten, validierte Parent-Zuordnung, Source-/Device-Registry ohne Präfix-Autorisierung.
- [Identity/Authorization](architecture/oip-008-identity-authorization.md): Principal, Role und hierarchischer Scope getrennt; Permissions erst nach Zielauflösung vereinigt; kein All-Access-Fallback im Multi-Modus.
- [Schema3/Migration](architecture/oip-008-storage-migration.md): atomare Offline-Provisionierung mit gemeinsamer DB-Ownership, explizite Legacy-Adoption, Source-lokale Control-Sequenzen, historische Schlüssel erhalten.
- [Agent-first-Matrix und Verträge](architecture/oip-008-rest-mcp-parity.md): 17 Capability-IDs, davon16 Reads und eine gesperrte MCP-Mutation; neun Tools im Principal-Modus. Drei neue Hierarchie-Reads und ScopedSnapshotRead ergänzen die bestehenden13.
- [Flutter-API-Anforderung v2](architecture/oip-008-flutter-requirements.md): UI bleibt unverändert; spätere Switcher/Scope-Caches separat.

Neue Rust-Module: Core `hierarchy`, Storage `hierarchy`/`ownership`, Server `identity`/`provisioning`/`tenant_services`. Bestehende ApplicationServices, CoreRuntime, REST und MCP verwenden diese Grenzen. Keine neue Crate, kein SDK-Upgrade; lediglich vorhandenes sha2 zusätzlich im Server für scoped Cursor. Kein direkter SQL-/OPC-UA-Zugriff aus MCP-Handlern. Derselbe Core-Observation-Validator wird für Ingestion, Recovery und Adoption verwendet.

Bereits vor008 erfüllt und weiterverwendet: ein Writer/eine CoreRuntime, unabhängige Worker, bounded Ingestion, Cancellation/Drain, Run-Journal, SQLite-Transaktionen, lokaler IPC-Handshake, offizielle rmcp3.8.0-Sessions, MCP-Limits, Source-Reconnect und Spectrum. SourceScope war dabei noch keine Organization-Isolation.

## Echte Akzeptanznachweise

`tests/oip008/acceptance.py` startet vier echte OPC-UA-Prozesse: Organization A mit A1/A2, mehreren Sites und Sources A/B/C; Organization B mit B1/Site B1/Source D. Eine Runtime, ein Writer. Authentisierte Principals für Organization A, Infrastructure A1, Organization B sowie zusätzliche Site-/Source-Reader. Acht unabhängige offizielle SDK-Clients über acht stdio-Bridges wurden parallel geprüft.

Phasen: atomare/idempotente Provisionierung; vier Source-Anteile in SQLite; MCP-Discovery/Node-Pagination; gleiche REST-/MCP-Health-Felder; Org-/Infrastructure-/Site-/Source-Isolation; generisch gleiche404 für fremde/fehlende Ressourcen; gefälschte Actor-/Principal-/Grants-/Pagination-Inputs; gesperrte Mutation; authentifiziertes SSE und gefälschter Cursor; Client-Abbruch; Weiterbetrieb ganz ohne Clients; acht Clients; Source A offline, B-Organization liefert weiter; Reconnect/Gaps; kontrollierter Restart; echter SIGKILL und Recovery. SQLite integrity_check/FKs ok, keine doppelten Beobachtungskennungen; Hierarchie und Zuordnungen bleiben erhalten, alle eigenen Prozesse beendet.

Wichtig beim Restore: **Observations Stale**, Source-Freshness **Unknown**, keine Runtime-Empfangszeit aus alten Daten. Reachability zunächst Unknown; ein tatsächlicher gescheiterter Probeversuch darf Unreachable ergeben. Erst echter neuer Empfang erzeugt Freshness Fresh. Der Test setzt Source-Freshness nicht fälschlich mit Observation-Freshness gleich.

`tests/oip008/legacy_migration.py` erzeugt einen separaten echten Schema2-Bestand mit dem erhaltenen OIP-007-Binary. Unbestätigtes und verändertes Manifest werden bei unverändertem Schema2 abgewiesen. Gültige Adoption bewahrt exakt Observation-Keys,12 Observations,14 Events und2 Gaps; Schema3 und FK-/Integritätsprüfung bestehen. Unit-Tests ergänzen widersprüchliche Origins, falsche Source-Key/Payload-Paare, fremde Event-Bezüge, Checkpoint-Korruption, Transaktionsrollback, unveränderliche Parents und Policy-Widerruf.

Aktuelle maschinenlesbare Ergebnisse: [Mehrorganisationen-E2E](evidence/oip008/e2e.json), [Legacy-Migration](evidence/oip008/legacy-migration.json), [Headless](evidence/oip008/headless.json), [MCP-stdio](evidence/oip008/mcp-legacy.json). Rohlogs/private Runtime-Fixtures bleiben ignoriert unter `target/oip008-*` bzw. privaten Testverzeichnissen; Credentials/DBs werden nicht getrackt.

## Regression

**118 Workspace-Tests,37 OPC-UA-Interop-Tests und21 Storage-Tests** (überlappende Gruppen), sechs neue Hierarchie- und ein neuer CLI-Test. Die finalen Zahlen und Befehle stehen in [test-summary.json](evidence/oip008/test-summary.json). Rust fmt/check/clippy (warnings denied), Workspace-/Storage-/Capability-/Permission-/MCP-/IPC-Tests, beide OPC-UA-Backends, open62541-only/no-default-Prüfungen, cargo-deny, Build und SDK-Beispiele wurden tatsächlich ausgeführt. Kein bisheriger Test entfernt. Die alten CLI-Harnesses wählen den Legacy-Entwicklungsmodus nun ausdrücklich; der bisherige Schema1→2-Test verwendet eine echte Schema1-Fixture statt nachträglich Schema3-Tabellen zu beschädigen.

Flutter: analyze ohne Issues,80 Tests, Web-Release mit lokalen CanvasKit-Ressourcen. Browser:16 Fachchecks, zusätzliche Spectrum-Interaktionen und30 Responsive-Captures; nativer macOS-Integrationstest mit Alarm/Reconnect PASS. Sources/Assets/Packages unverändert. Der native Runner meldete eine Host-Vordergrund-Warnung; der Integrationstest selbst bestand vollständig.

Entwicklungszwischenläufe werden nicht als PASS ausgegeben: zunächst wurden alte Test-Erwartungen zu Schema-/Capability-Zahl angepasst, ein falscher rmcp-Resource-Feldzugriff korrigiert und zwei E2E-Annahmen berichtigt. Das offizielle SDK verwirft übergroße Frames begrenzt und verarbeitet gültige Folgeframes; es muss nicht sofort EOF liefern. Source-Freshness nach Restore ist Unknown, während gespeicherte Observations Stale sind. Finale Läufe prüfen diese tatsächlichen Verträge.

## Unabhängige Reviews

A: `/root/review_domain_008`, Domain/DB/Migration/Ownership. B: `/root/review_auth_008`, Identity/Authorization/REST/SSE/MCP. Read-only, getrennte Reviewer; keine Selbsteinschätzung als unabhängiger Review. [Befunde, Korrekturen und geprüfte Codeversionen](evidence/oip008/reviews.json).

Behoben: UTF-8-Header-Panic, impliziter eingebetteter Legacy-Zugriff, globale Discovery ohne Platform-Scope, Audit-Ziel bei impliziter Source, fehlende Cancellation-/Identity-Audits, fehlende ID-Schema-Grenzen, Device-/Payload-/Origin-/FK-Prüfungen der Migration, Legacy→Multi-Metadaten, private DB-/Sidecar-Rechte und Source-Key/Payload-Konsistenz. Ein später zusätzlicher Ledger-Korruptionsfall wurde vor Commit behoben: Vollständigkeit und positive lückenlose Versionsfolge werden vor jedem DDL geprüft; fehlende1 und Ersatzdurch0/-1 sind Regressionen. Beide finalen Reviews fanden in ihrem Scope keine verbleibenden blockierenden Befunde. Lokales Audit bleibt unvollständig/manipulierbar und keine produktive Compliance-Lösung.

## Performance und Grenzen

Gemessene parallele MCP+REST-Reads (ein kurzer lokaler Lauf): 1 Client(s): 9.56 ms, 3 Client(s): 11.37 ms, 8 Client(s): 35.0 ms; Core RSS/CPU-Stichprobe `32464   7.3` (RSS KiB / %CPU). Reproduzierbare acht echte MCP-Clients mit parallelen Reads und laufender Vier-Source-Ingestion, RSS/CPU-Stichprobe und Dauer im E2E-Report. SQL-Plan-Tests verlangen Indexnutzung für Parent-, Source-, Device-, Observation- und Control-Event-Lookups. Tenant-Read-Modelle sind durch Registry-/Metric-Grenzen begrenzt; Offline-Validierung und Startup-Restore können Historie vollständig lesen. Keine Enterprise-/Dauerlauf-/SLA-Behauptung. [Query-Plans und100-SELECT-CLI-Messungen](evidence/oip008/query-plans.json) sind bereinigt versioniert; CPU/RSS sind kurze lokale Stichproben, keine isolierte Benchmarkverbesserung.

## Exakte Startbefehle

Feature-Worktree verwenden; keine Integration nach main erforderlich:

```sh
cd /Users/benny/Code/open-industrial-platform-worktrees/oip-008
cargo build --locked --workspace
cargo build --locked -p oip-server --examples
python3 tests/oip008/prepare_local.py --directory /private/tmp/oip008-local-operator
# Verzeichnis darf noch nicht existieren; keine vorhandenen Credentials überschreiben.
target/debug/oip-server --config /private/tmp/oip008-local-operator/core.json --provision /private/tmp/oip008-local-operator/plan.json
```

Vier separate Simulator-Terminals:

```sh
target/debug/oip-simulated-server --port 15861 --seed 42 --tick-ms 250
target/debug/oip-simulated-server --port 15862 --seed 49 --tick-ms 250
target/debug/oip-simulated-server --port 15863 --seed 56 --tick-ms 250
target/debug/oip-simulated-server --port 15864 --seed 63 --tick-ms 250
```

Ein Daemon-Terminal:

```sh
target/debug/oip-server --daemon --config /private/tmp/oip008-local-operator/core.json --ipc-config /private/tmp/oip008-local-operator/ipc.json
```

REST ausschließlich `http://127.0.0.1:18808`; Multi-Reads benötigen den passenden Bearer, es gibt hier keine anonyme Multi-Infrastructure-Flutter-URL. Generische MCP-Clientkonfiguration, Pfade gegebenenfalls auf den tatsächlich erzeugten privaten Ordner anpassen:

```json
{
  "mcpServers": {
    "oip-local-read": {
      "command": "/Users/benny/Code/open-industrial-platform-worktrees/oip-008/target/debug/oip-server",
      "args": ["--mcp-bridge", "--ipc-socket", "/private/tmp/oip008-local-operator/s", "--ipc-credential", "/private/tmp/oip008-local-operator/reader-org-a.credential"]
    }
  }
}
```

Bridge startet keinen zweiten Core. Weitere Clients verwenden ihre passenden Credential-Dateien. Plattformweites Lesen ist ausschließlich im expliziten `platform-reader`-Testprofil vorhanden, keine Admin-Mutation. Ctrl+C stoppt den Daemon kontrolliert; DB/Zuordnungen für Restart erhalten. `--provision` darf nicht mit Runtime-Modi kombiniert werden und scheitert bei laufender DB-Ownership.

Bestehende Flutter-Demo separat, eigener DB-Bestand/Port:

```sh
target/debug/oip-server --demo --port 18809 --opcua-port 15865 --database target/oip008-legacy-demo.sqlite --web-dir /Users/benny/Code/open-industrial-platform/apps/flutter/build/web
```

Diese optionale URL `http://127.0.0.1:18809` wird nicht als aktuell laufender Service behauptet. Für reale neue Integrationsnachweise verwendet der Test-Harness eigene geprüfte dynamische URLs und beendet sie danach.

Testbefehle:

```sh
cargo fmt --all -- --check
cargo check --locked --workspace --all-targets
cargo clippy --locked --workspace --all-targets -- -D warnings
cargo test --locked --workspace -- --test-threads=1
cargo test --locked -p oip-opcua --features open62541-backend -- --test-threads=1
target/oip-002-tools/bin/cargo-deny check advisories licenses bans sources
python3 tests/oip008/acceptance.py
python3 tests/oip008/legacy_migration.py
OIP_EVIDENCE_DIR=target/oip008-headless python3 tests/oip004/acceptance.py
OIP_EVIDENCE_DIR=target/oip008-mcp-legacy python3 tests/oip007/mcp_acceptance.py
python3 tests/oip008/ui_regression.py
cd /Users/benny/Code/open-industrial-platform/apps/flutter
flutter analyze
flutter test --reporter expanded
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
```

Die Legacy-Migration benötigt das unveränderte Baseline-Binary im Haupt-Checkout; der Test dokumentiert dessen tatsächlichen Hash und prüft das erzeugte Schema2. SQLite-CLI ≥3.37, vorhandenes Chrome/Playwright, Flutter/macOS/Xcode und cargo-deny wurden wiederverwendet; keine globalen Installationen oder Services aktiviert.

Hinweis (Iteration 3 des Release-Loops, `docs/OIP_RELEASE_PROGRESS.md`): `tests/oip008/ui_regression.py` führt den nativen macOS-Schritt jetzt als eigenen Build-Schritt mit eigenem Zeitfenster und positiver Build-Markierung aus, der native Integrationstest läuft mit explizitem `--timeout 30m`, und die Legacy-Webschritte erhalten den getrennt gebauten HTML-Renderer. Damit ist der native macOS-Nachweis auf diesem Rechner reproduzierbar; die historischen Gates dieses Meilensteins bleiben unverändert.

## Security, Git und verbleibende Arbeiten

RUSTSEC-2023-0071 bleibt Produktionsblocker; RUSTSEC-2023-0089 und RUSTSEC-2024-0449 bleiben offene Ausnahmen. cargo-deny PASS behebt diese Befunde nicht. Keine produktiven OT-Verbindungen, Writes, Maschinensteuerung, öffentlichen Listener, neuen Remote-Endpunkte, Secrets in Git oder Cloud-Dienste.

NOT_TESTED: feindliche separate OS-Konten, Windows-IPC, Remote-/OIDC-Authentisierung, produktive Tenant-Penetrationstests, große Langzeit-/Dauerlast-/Stromausfalltests, Remote-CI und reale Industriehardware. Keine produktive Hierarchie-/Policy-Mutation über REST/MCP. Kein Credential-Vault, kein dauerhaft manipulationssicheres Execution-Audit, keine vollständige Historien-/Diagnostics-Plattform. Spätere UI-Auswahl und produktive Identity-/Session-Sicherheit sind separate Aufträge.

Vor lokalem Commit: geprüfte explizite Dateiliste, [Gitleaks8.30.1-Scan mit einzeln geprüften False Positives und null ungeklärten Befunden](evidence/oip008/secret-scan.json), Source-/Design-/UI-Integrität, keine generierten Runtime-Artefakte. Produktcode-Commit: `dd17dc46bc15de8c5099ebf056566bd737da436e`. Danach wurden leerer Index/Working Tree, alle358 getrackten Dateien, Git-fsck, Baseline-/UI-/Design-Integrität und der bytegenaue Scan-Kandidat geprüft. [Tatsächlicher Git-Nachweis](evidence/oip008/git-verification.json). Die Ergebnisse werden als separater Dokumentations-Commit festgehalten; kein Amend/History-Rewrite. Der abschließende Branch-Tip wird nach diesem Commit im Session-Abschluss angegeben. Kein Merge nach main, kein Push oder Deployment. Alle14 Gates werden im abschließenden Test-Summary einzeln ausgewiesen.


## Finale Gates

| Gate | Ergebnis |
|---|---|
| G1 Domain | PASS — typisierte, validierte Hierarchie und stabile Source-/Device-Zuordnung |
| G2 Storage | PASS — Schema3, referenzielle Integrität, atomare Transaktionen |
| G3 Legacy | PASS — tatsächlicher Schema2-Bestand, unveränderte Schlüssel/Counts, abgewiesene Mehrdeutigkeit |
| G4 Identity | PASS — geschützte IPC-Credentials an gespeicherte Principals gebunden |
| G5 Authorization | PASS — zentrale hierarchische Entscheidung, Default-Deny, Scope-Union-Regression |
| G6 REST/SSE | PASS — authentisierte Projektionen, kein globaler Snapshot/Count für Tenant-Reader |
| G7 MCP | PASS — reale unabhängige Clients, Org-/Infra-/Site-/Source-Isolation und negative Inputs |
| G8 Agent-first | PASS — dieselben CapabilityServices, Paritätsmatrix/Schemas, keine UI-Business-Logik |
| G9 Ingestion | PASS — vier Quellen in zwei Organizations, Ausfallisolierung |
| G10 Recovery | PASS — Restart, tatsächlicher Crash, Run-Journal, Stale-Restore und Migration |
| G11 Security | PASS im lokalen Entwicklungsscope — beide unabhängigen Reviews, Blocking Findings behoben |
| G12 Regression | PASS — 118 Rust,37 Interop,80 Flutter,16 Browserchecks und native macOS-Integration |
| G13 Isolation | PASS — main/Flutter/Design und fremde Services erhalten |
| G14 Git | PASS — tatsächlicher lokaler Feature-Commit und Nachprüfung, kein Merge/Push |

Nächster Auftrag: produktive Identity-/Credential-/Audit-Grenzen und feinere dynamische Read-Kontexte getrennt spezifizieren; anschließend autorisierte Multi-Infrastructure-UI auf APIv2 integrieren. Keine Produktionsfreigabe durch diesen Meilenstein.

OIP_008_MULTI_INFRASTRUCTURE_PASS
