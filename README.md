# Open Industrial Platform (OIP)

Die Open Industrial Platform ist eine geplante quelloffene, selbst betriebene und lokal nutzbare Plattform für industrielle Konnektivität, Beobachtbarkeit und evidenzbasierte Diagnostik.

## Lokales Betreiberprofil

Der Entwicklungsstand auf Apple Silicon verbindet den lokalen Core mit der
Spectrum-Browseroberfläche und einem gekennzeichneten OPC-UA-Simulator.
Einrichtung und Wartung verwenden ein signiertes lokales Paket. Das
[Betreiber-Runbook](docs/runbooks/operations.md#lokales-betreiberprofil-auf-apple-silicon)
beschreibt Installation, Anmeldung, Sicherung, Wiederherstellung und Diagnose.

## Historische Meilensteine

OIP-008.5 ergänzt im isolierten Feature-Branch ein persistentes Geräteinventar ohne Collector-Pflicht und einen normalen Start ohne Demo-Daten. Der Branch ist ausdrücklich auf OIP-008.4 (`f9969f0…`) gestapelt; `main` bleibt unverändert. Geräte starten mit Unknown/NoCollector, lokale Registrierung/Import sind autorisiert und offline, REST/MCP liefern dieselben gefilterten Reads. [Verifikation](docs/oip-0085-verification.md) · [Erstes eigenes Gerät registrieren](docs/architecture/oip-0085-operator-onboarding.md). Keine Produktionsfreigabe. Die folgenden Absätze sind historische Meilensteine.

OIP-008 implementiert im isolierten Feature-Branch eine persistierte Organization-/Infrastructure-/Site-/Source-Hierarchie, Principal-/Role-Bindungen und zentrale REST-/SSE-/MCP-Scope-Auswertung. Noch nicht nach main integriert; lokale Simulation, keine produktive Tenant-Zertifizierung. [Implementierung, Startbefehle und aktuelle Verifikation](docs/oip-008-verification.md).

OIP-007 ergänzt einen persistenten lokalen Core-Daemon und stdio-MCP-Bridges über einen geschützten Unix-Socket. Mehrere Clients teilen dieselbe Runtime, denselben Writer und CapabilityService; Disconnect stoppt den Daemon nicht. Zwölf Read-Capabilities bleiben autorisiert, Flutter-Spectrum unverändert. Ausschließlich lokale Entwicklung, keine Produktionsfreigabe.

- [OIP-007: Runtime, Multi-Client-Verifikation, Security-Reviews und Startbefehle](docs/oip-007-verification.md)
- [Persistente Runtime](docs/architecture/oip-007-persistent-runtime.md) · [Lokales MCP/IPC](docs/architecture/oip-007-mcp-multiclient.md)
- [OIP-008: ursprünglicher Architekturvorschlag](docs/architecture/oip-008-multi-infrastructure-proposal.md)

OIP-006.1 integriert das verifizierte Spectrum-Handoff mit dem unveränderten OIP-006-Rust-/MCP-Core. Spectrum, Graphite und Daylight sind auf acht Breiten geprüft; Browser, REST/SSE und MCP bedienen im Integrationslauf dieselbe Runtime. Der lokale RC bleibt ausschließlich Simulation/Entwicklung, ohne Produktionsfreigabe.

- [OIP-006.1: kanonischer Stand, visuelle Abnahme, alle Testnachweise und Startbefehle](docs/oip-006-1-spectrum-integration.md)
- Geprüfte separate lokale Spectrum-Vorschau: `http://127.0.0.1:18086` (Details und eigener Prozess im Bericht).

OIP-006 ergänzt einen echten lokalen Rust-MCP-Server über stdio: zwölf bestehende Read-Capabilities, sechs Tools und versionierte Health-/Snapshot-Resources. MCP und optional REST verwenden dieselbe CoreRuntime und ApplicationServices-Instanz; Source-Scope, Permissions und Audit bleiben gemeinsam. Mutationen und Remote-MCP sind gesperrt. OIP funktioniert weiterhin ohne KI-Modell. `RUSTSEC-2023-0071` bleibt Produktionsblocker.

- [OIP-006: Startbefehle, Interoperabilität und Verifikation](docs/oip-006-verification.md)
- [MCP-Architektur und Betriebsgrenzen](docs/architecture/oip-006-mcp.md)
- [Capability-Parität und generierte Schemas](docs/architecture/oip-mcp-capability-mapping.md)

Die folgenden Abschnitte beschreiben die jeweiligen früheren Meilensteine.

OIP-005.1 führt das finale OIP-004-UI-Handoff mit dem kanonischen OIP-005-Stand zusammen. Der dokumentierte Drei-Wege-Abgleich erhält die Source-Bindung, Resynchronisierung, Core-Klassifikationen und alle 13 Capabilities. Die Review-Fixes sind integriert; ein Spectrum-Redesign und ein MCP-Server gehören weiterhin nicht zu diesem Stand.

- [OIP-005.1: Finaler UI-Abgleich, Testnachweise und Befehle](docs/oip-005-1-final-ui-reconciliation.md)

OIP-005 integriert das geprüfte Flutter-UI-Handoff in den führenden OIP-004-Core. OIP ist agent-first: REST/SSE und künftige MCP-Adapter verwenden dieselben typisierten Application Services mit Capability- und Source-Berechtigungen. Ein MCP-Server ist noch nicht implementiert; das Produkt funktioniert ohne Agent oder KI-Modell.

- [OIP-005: Agent-first-Architektur und OIP-006-Folgeauftrag](docs/architecture/oip-005-agent-first-foundation.md)
- [Capability-Inventar mit Implementierungsstatus](docs/architecture/oip-capability-inventory.md)
- [OIP-005: Integrationsnachweis und Startbefehle](docs/oip-005-integration-verification.md)

OIP-004 härtet den modularen Rust-Core: unabhängige OPC-UA-Quellen, komponentenbasierter Lifecycle, begrenzte Ingestion, atomare Checkpoints, kontrollierter Shutdown und Wiederanlauf. Der Core funktioniert vollständig ohne Flutter. Die vorhandene Oberfläche ist funktional eingefroren.

- [OIP-004: Core-Architektur und Grenzen](docs/architecture/oip-004-modular-core.md)
- [OIP-004: Startbefehle, Tests und Evidenz](docs/oip-004-verification.md)
- [Konfiguration für zwei lokale Simulatoren](examples/core-local.json)

OIP-003 ergänzt Flutter Web und eine native macOS-App, ein eigenes OIP-Designsystem sowie den lokalen Datenpfad OPC-UA-Simulator → Rust-Adapter → Domänenmodell → SQLite → Axum REST/SSE → Flutter. Die fünf Ansichten sind Overview, Geräte, Netzwerk/VPN, OPC-UA-Browser und Diagnostics. Inventar, Topologie und Diagnosen sind explizite Simulation; fehlende Host-Telemetrie bleibt unbekannt. `RUSTSEC-2023-0071` verhindert weiterhin eine produktive Freigabe.

- [OIP-003: Architektur, Datenverträge und Grenzen](docs/architecture/oip-003-flutter-api.md)
- [OIP-003: Startbefehle und Verifikation](docs/oip-003-verification.md)
- [Flutter-Anwendung](apps/flutter/README.md)

- [OIP-002: Architektur und Befehle](docs/architecture/oip-002-security-storage.md)
- [ADR 0002: Security, Interop und Persistenz](docs/decisions/0002-security-interop.md)
- [OIP-002-Verifikationsbericht](docs/oip-002-verification.md)
- [OIP-001: ursprüngliche Architektur](docs/architecture/oip-001-foundation.md)
- [ADR 0001: OPC-UA-Stackentscheidung](docs/decisions/0001-opc-ua-stack.md)
- [OIP-001: historischer Verifikationsbericht](docs/oip-001-verification.md)

## Leitprinzipien

- Rust-first, modular und plattformübergreifend
- self-hosted und local-first
- standardmäßig read-only gegenüber industriellen Systemen
- ohne Cloud-Konto und ohne KI funktionsfähig
- nachvollziehbare Trennung von Erreichbarkeit, Agent-Health, Service-Health und Telemetrie-Aktualität
- klare Trennung von Korrelation und nachgewiesener Kausalität

## Projektstruktur

- `crates/oip-core`: gemeinsame Domänen-, Event-, Source- und Persistenzverträge (IDs, Quality, Freshness, Observation Envelope)
- `crates/oip-simulator`: deterministische Testanlage M-01 mit Szenarien und 1.000 skalierbaren Nodes
- `crates/oip-opcua`: read-only OPC-UA-Adaptergrenze, async-opcua-Standardbackend, open62541-Vergleichs-PoC, Testwerkzeuge
- `crates/oip-server`: lokaler Axum-Server, Collector und API v1 (REST/SSE)
- `crates/oip-agent`: lokaler Telemetrie-Agent (weiterhin Stub)
- `crates/oip-gateway`: Edge-Gateway und Weiterleitung (weiterhin Stub)
- `crates/oip-storage`: versionierte, idempotente SQLite-Observation-/Event-/Gap-Persistenz
- `crates/oip-diagnostics`: deterministische Diagnostik (weiterhin Stub)
- `apps/flutter`: Flutter-/Dart-Benutzeroberfläche für Web und macOS
- `tests`: reserviert für workspace-weite Integrationstests; die OIP-001-Tests liegen in den Crates selbst
- `docs`: Architektur, Entscheidungen, Verifikationsbericht
- `deployment`: spätere Compose-, systemd- und VictoriaMetrics-Konfiguration
- `design/reference`: manuell bereitgestellte Designreferenzen

`frontend/` und `deployment/` bleiben ungenutzte Platzhalter; Browser-Verifikation liegt in `tests/oip003/`.

## Designreferenz

Die vom Operator bereitgestellte Referenzdatei liegt unter `design/reference/`. Der im Auftrag genannte Name `open-industrial-platform-vision-demo.html` ist im Repository nicht vorhanden; vorhanden ist `design/reference/Open Industrial Platform Demo.html` (SHA-256 `bd9f9d8696ed48676055ee9a2cd0afb29e6c3d59e0945e662d925306f73c753e`). Die Datei wurde nicht verändert, umbenannt oder entfernt.

## Grundlegende Workspace-Prüfung

Mit einer bereits installierten Rust-Toolchain:

```sh
cargo metadata --no-deps --format-version 1
cargo check --workspace
```

Der OIP-001-Simulator und Testclient verwenden ausschließlich lokale Loopback-Verbindungen. Weitere Prüfungen:

```sh
cargo test --workspace
cargo test -p oip-opcua --features open62541-backend -- --test-threads=1
```

## Lizenz

Apache License 2.0. Siehe [LICENSE](LICENSE).
