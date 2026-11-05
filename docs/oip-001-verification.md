# OIP-001 — Verifikationsbericht

> Historischer Abschlussbericht. Die damals offenen Security-, Interop-, CI- und Audit-Gates werden in OIP-002 behandelt. Der aktuelle Nachweis steht im [OIP-002-Verifikationsbericht](oip-002-verification.md); die folgenden FAIL/NOT_TESTED-Zeilen beschreiben den damaligen Stand.

Stand: 2026-11-03. Alle Angaben beziehen sich auf tatsächlich ausgeführte lokale Läufe. Nicht ausgeführte Bereiche sind als `NOT_TESTED` markiert.

## Umgebung

- macOS
- `rustc 1.93.0 (254b59607 2026-01-19)`
- `cargo 1.93.0 (083ac5135 2025-12-15)`
- async-opcua `=0.19.0`
- open62541 `=0.12.1`, open62541-sys `=0.6.6`
- Nur Loopback-Server und -Clients; keine realen Geräte

## Tests und Prüfungen

| Prüfung | Ergebnis | Evidenz |
|---|---|---|
| Rust-Formatierung | PASS | `cargo fmt --all -- --check` |
| Workspace-Clippy | PASS | `cargo clippy --workspace --all-targets -- -D warnings` |
| Clippy mit open62541 | PASS | `cargo clippy -p oip-opcua --all-targets --features open62541-backend -- -D warnings` |
| Workspace-Check | PASS | `cargo check --workspace --all-targets` |
| Core- und Simulator-Unit-Tests | PASS | IDs, Unknown-Semantik, Reproduzierbarkeit, Szenarien, virtuelle Zeit |
| OPC-UA Endpoint Discovery | PASS | Beide PoCs erhalten lokale EndpointDescriptions |
| Namespace Browse / 1.000 Nodes | PASS | async-opcua-PoC: 1.020 Referenzen; M-01 und Bulk vorhanden |
| Read | PASS | Beide Stacks lesen den Temperatur-Double |
| DataChange Subscription | PASS | Beide Stacks empfangen Änderungen |
| Timestamp/Quality/Origin | PASS | Source/Server/Received, StatusCode, Seed und Szenario geprüft |
| Sensorfehler ohne Nullwert | PASS | `None`, `Bad`, `InvalidMeasurement`; kein numerischer Fallback |
| Reconnect und erneute Subscription | PASS | async-opcua: echter Stopp/Neustart, Datenlücke und neue Observation |
| open62541-Reconnect | PASS mit Einschränkung | Read erkennt Abbruch; Client wird neu erstellt und subscribed erneut |
| Reproduzierbarkeit | PASS | Gleicher Seed/Tick erzeugt identischen Frame; anderer Seed ändert Werte |
| Read-only-Security | PASS | `UserAccessLevel` ohne `CURRENT_WRITE`; Adapter hat keine Schreiboperationen |
| Nicht-lokale Verbindung | PASS | `192.0.2.1` wird vor Netzwerkzugriff abgelehnt |
| Auto-Trust | PASS per Konfigurationsprüfung | Kein `trust_server_certs(true)`, `trust_client_certs(true)` oder `accept_all()` |
| Security-Profil trennt Simulation von Produktion | PASS | `SecurityProfile::Production` schlägt fehl; `None` ist an `LocalSimulation` gebunden |
| Endlicher Reconnect-Versuchszähler | PASS | `session_retry_limit(-1)` wird abgelehnt |
| Loopback-Prüfung auf literaler Adresse | PASS | `localhost` und `192.0.2.1` werden vor dem Netzwerkzugriff abgelehnt |
| Browse-Continuations | PASS | 1.100 Bulk-Nodes; Browse läuft über Continuation Points |
| Browse-Knotenlimit | PASS | `max_browse_nodes` führt zu `BrowseLimitExceeded` |
| Unbekannter Node | PASS | Read liefert einen Fehler, keinen Wert |
| Fehlerursache über StatusCode erhalten | PASS | `BadSensorFailure`/`BadNotConnected`/`BadConnectionClosed` werden verlustfrei zurückgebildet |
| Fremde Herkunft nicht übernommen | PASS | Abweichende, leere und whitespace-`origin_id` ergeben `InvalidProvenance` bzw. `UntrustedProvenance` |
| Read-only-Zugriffsbits aller Prozesswerte | PASS | `CURRENT_READ` gesetzt, `CURRENT_WRITE` nicht gesetzt, für alle sechs Werte geprüft |
| Unabhängige Interoperabilität | PASS in einer Richtung | async-opcua-Client ↔ open62541-Server: Browse/Read/Subscription |
| Forward-Interop | **FAIL / offenes Gate** | open62541-Client ↔ async-opcua-Server: `BadSecurityChecksFailed`; Regressionstest bewusst `#[ignore]` |
| OPC-UA-Events | NOT_TESTED | APIs recherchiert, kein Event-Roundtrip implementiert |
| Sichere Policies/Zertifikats-Roundtrip | NOT_TESTED | Nur explizit lokale `None`-Konfiguration getestet |
| Dependency-Audit (cargo audit/deny) | NOT_TESTED | Werkzeug nicht verfügbar; keine CVE-Prüfung durchgeführt |
| CI-Gate | NOT_TESTED | Keine CI-Konfiguration im Repository |
| macOS ARM64 | PASS | Host `aarch64-apple-darwin`; Build und Tests ausgeführt |
| Linux | NOT_TESTED | Keine Linux-Toolchain ausgeführt |
| Windows | NOT_TESTED | Keine Windows-Toolchain ausgeführt |
| Linux/Windows ARM64 | NOT_TESTED | Keine entsprechenden Ziele oder Hardware ausgeführt |

## CLI-Smoke

**PASS.** Ein separater Simulatorprozess wurde auf `127.0.0.1:58942` mit 1.000 Bulk-Nodes gestartet. Der Testclient führte Discovery, 1.020 Browse-Referenzen, sechs Reads und Subscription-Events aus. Der Server wurde anschließend kontrolliert per SIGINT beendet.

Der Smoke-Test deckte einen echten Fehler auf: Die Freshness-Berechnung maß das Alter des Source-Timestamps gegen die Wanduhr des Clients und markierte dadurch alle Werte der deterministischen Simulation als `stale`. Die Freshness-Logik misst nun gegen die Uhr der Quelle; ein Regressionstest `virtual_clock_values_are_not_mistaken_for_stale_data` sichert das ab.

```sh
cargo run -p oip-opcua --bin oip-simulated-server -- --port 4840
cargo run -p oip-opcua --bin oip-test-client -- --url opc.tcp://127.0.0.1:4840 --samples 2
```

## Performance

Die gemessenen Einzelwerte und ihre eingeschränkte Vergleichbarkeit sind in [ADR 0001](decisions/0001-opc-ua-stack.md) aufgeführt. Sie wurden nicht über mehrere Läufe oder Release-Builds validiert.

## Technische Risiken

1. `BadSecurityChecksFailed` in der Forward-Interop-Richtung muss vor einer breiteren Interop-Zusage untersucht werden.
2. Sichere Zertifikats- und Policy-Pfade sind noch nicht nachgewiesen.
3. Der async-opcua-Workaround mit `Variant::Empty` muss bei Upgrades bestehen bleiben.
4. Der Namespace-Index 2 ist im lokalen PoC fest verdrahtet; ein späterer Adapter soll die NamespaceArray-Auflösung implementieren.
5. Der Namespace-Index 2 und die Simulationseinrichtung sind an den lokalen PoC gebunden; ein fremder Server ohne Simulationsmetadaten liefert `InvalidProvenance` und damit keine übernommene Herkunft.
6. Ein bösartiger lokaler Server kann in async-opcua 0.19.0 beim Dekodieren extremer OPC-UA-Zeitstempel einen Panic in der Abhängigkeit auslösen; das ist upstream zu beheben.
7. Auf Mehrbenutzer-Hosts ist die unverschlüsselte Simulation für jeden lokalen Prozess lesbar.
8. Das optionale open62541-Feature bindet natives C per FFI ein und liegt damit außerhalb der `unsafe_code`-Regeln des Workspace.
9. Es gibt keine CI und keinen Dependency-Audit; Regressionen der Loopback-, Read-only- und Interop-Gates würden erst bei einem lokalen Lauf auffallen.
10. Das HTML-Referenzarbeitsverzeichnis enthält `Open Industrial Platform Demo.html`; die im Task genannte Datei `open-industrial-platform-vision-demo.html` ist nicht vorhanden. Es wurde keine Datei umbenannt oder verändert.

## Reproduzierbare Gesamtprüfung

```sh
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo test -p oip-opcua --features open62541-backend -- --test-threads=1
cargo run -p oip-opcua --bin oip-async-opcua-poc
cargo run -p oip-opcua --bin oip-open62541-poc --features open62541-backend
```

Kein Commit, Push, Production-Deployment, reale Anlagenverbindung oder automatische Aktuierung wurde durchgeführt.
