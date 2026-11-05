# ADR 0001 — OPC-UA-Stack für OIP-001

> Historische OIP-001-Entscheidung. [ADR 0002](0002-security-interop.md) dokumentiert den reparierten Forward-Interop-Pfad, Production-Security und die verbleibenden Advisory-/Release-Gates.

- Status: **Accepted**
- Datum: 2026-11-03
- Entscheidung: **async-opcua 0.19.0** ist das Standardbackend. **open62541 0.12.1 / open62541-sys 0.6.6** bleibt als isolierter, optionaler Vergleichs-PoC erhalten.

## Kontext

OIP benötigt einen austauschbaren, read-only OPC-UA-Adapter für lokale Simulation, Browse, Read, DataChange und Reconnect. Die Entscheidung darf nicht allein auf Dokumentation beruhen. Beide Kandidaten wurden mit Rust 1.93.0 auf macOS kompiliert und mit lokalen Server/Client-Läufen geprüft.

Beide Rust-Projekte stehen unter MPL-2.0. Diese Lizenz ist mit der Apache-2.0-Lizenz von OIP vereinbar; MPL-2.0-Dateien und Abhängigkeiten behalten ihre jeweiligen Lizenzpflichten. Eine Zertifizierung der zugrunde liegenden Implementierungen wird nicht auf OIP vererbt.

## Praktischer Vergleich

| Kriterium | async-opcua 0.19.0 | open62541 0.12.1 |
|---|---|---|
| Rust-Integration | Reine Rust-Crates | Rust-Bindings, C-Build über CMake/bindgen |
| macOS-Build | PASS | PASS |
| Client und Server | PASS | PASS |
| Endpoint Discovery | PASS | PASS |
| Namespace Browse | PASS; 1.018 Referenzen im PoC | PASS; M-01 mit sechs Child-Nodes |
| Read mit Timestamps/Status | PASS | PASS |
| DataChange Subscription | PASS | PASS |
| Verbindungsverlust erkennen | PASS | PASS über fehlgeschlagenen Read |
| Reconnect derselben Client-Instanz | PASS | **FAIL im getesteten Lauf** |
| Explizite Wiederherstellung | PASS mit erneuter Subscription | PASS nur durch Client-Neuerstellung und erneute Subscription |
| Events | API vorhanden; NOT_TESTED | API vorhanden; NOT_TESTED |
| Security Policies | None sowie moderne Policies im API vorhanden | None sowie moderne Policies im API vorhanden; verschlüsselte Konfiguration erfordert Mbed TLS |
| Zertifikatsvalidierung | Kein Auto-Trust im PoC; sichere Richtung NOT_TESTED | Kein `accept_all`; sichere Richtung NOT_TESTED |
| Wartbarkeit im OIP-Kontext | Kein nativer Build-Teil; Tokio/tracing konsistent | Zusätzliche C-/CMake-/libclang-Kette und FFI-Grenze |

## Gemessene Laufzeitwerte

Lokale Debug-Builds, ein Lauf pro Kandidat, 1.000 Bulk-Nodes. Die Werte sind Beobachtungen, keine statistisch belastbaren Benchmarks. Browse-Umfang und Discovery-/Connect-Grenzen unterscheiden sich und sind deshalb nicht als direkter Geschwindigkeitssieger zu interpretieren.

| Messung | async-opcua | open62541 |
|---|---:|---:|
| Connect + Discovery / Discovery | 145.043 µs inkl. Connect und Metadaten | 110.301 µs nur Discovery |
| Browse | 202.308 µs für 1.020 Referenzen | 165 µs für sechs M-01-Referenzen |
| Read | 227 µs | 117 µs |
| Erste Subscription | 110.954 µs | 510.153 µs |
| Reconnect inkl. Resubscribe | 226.996 µs, dieselbe Client-Instanz | 1.245.152 µs, Client neu erstellt |
| Gemeldete Datenlücke | 105 ms | im Report nicht separat als OPC-UA-Eventmodell ausgegeben |

Beobachtete initiale Buildzeiten: async-opcua Testbuild 32,55 s; open62541 Build/Run 31,82 s. Die Läufe teilten teilweise bereits kompilierte Abhängigkeiten und sind kein kontrollierter Clean-Build-Vergleich.

## Interoperabilität

- **PASS:** async-opcua-Client gegen unabhängigen open62541-Server: Browse, Read und DataChange Subscription.
- **FAIL:** open62541-Client gegen async-opcua-Server endete im getesteten `SecurityPolicy=None`-Lauf nach `CreateSession` mit `BadSecurityChecksFailed`. Die Sicherheitsprüfung wurde nicht durch Auto-Trust umgangen. Diese Richtung bleibt als ignorierter Regressionstest und offenes Interop-Gate dokumentiert.

## Entscheidung

async-opcua wird Standard, weil der komplette Kernakzeptanzpfad ohne native Build-Abhängigkeiten funktioniert und der Client nach einem echten Server-Neustart dieselbe Instanz wiederverbindet, Metadaten aktualisiert und erneut subscribed. Die Adaptergrenze bleibt neutral; `open62541-backend` ist ein optionales Feature und kein Bestandteil der Domänenmodelle.

Die Neutralität umfasst auch den Ereignispfad: `ReadOnlyOpcUaAdapter::next_event` liefert Beobachtungen, Verbindungsverlust, Reconnect mit Datenlücke und Subscription-Fehler über dieselbe Schnittstelle, die auch ein späterer Backend-Adapter implementieren muss.

## Konsequenzen und offene Gates

1. Produktive oder reale Endpunkte benötigen eine separate Security-Phase mit expliziten Trust Stores, Zertifikatsvalidierung und sicheren Policies. `SecurityProfile::Production` schlägt bis dahin fehl.
2. OPC-UA-Events sind noch nicht implementiert oder getestet.
3. Forward-Interop `open62541 → async-opcua` ist offen.
4. Linux, Windows und zusätzliche ARM64-Ziele benötigen eigene Build-/Testnachweise.
5. Performance muss bei späteren Lasttests über mehrere Läufe und Release-Builds gemessen werden.
6. `async-opcua` 0.19.0 ist exakt gepinnt; der dokumentierte Statusverlust valueless DataValues erfordert beim Upgrade einen Regressionstest.
7. Ein Upstream-Panic beim Dekodieren extremer OPC-UA-Zeitstempel in async-opcua 0.19.0 ist im Upstream zu beheben; OIP kann ihn an der eigenen Grenze nicht vollständig ausschließen.
8. Eine CI und ein Dependency-Audit fehlen; beide sind Voraussetzung für einen belastbaren Release-Nachweis.
