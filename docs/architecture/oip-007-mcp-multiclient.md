# OIP-007 — Lokales Multi-Client-MCP

## Protokoll und Adapter

Unverändert offizielles `rmcp 3.8.0`, MCP 2026-07-28 (`server/discover`, Request-Metadaten) und Legacy 2025-11-25 Initialize. [MCP-stdio](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio) definiert newline-delimited JSON-RPC und erlaubt dieselbe Rahmung auf einem zuverlässigen lokalen Byte-Stream. Das [offizielle Rust-SDK](https://github.com/modelcontextprotocol/rust-sdk) besitzt Framing, Korrelation, Discover/Initialize, Schema-/Fehler- und Cancellation-Semantik; diese werden nicht in der Bridge nachgebaut.

Der Daemon verwendet pro akzeptiertem UnixStream einen eigenen `McpAdapter` und `BoundedTransport` mit eigener Request-Map und Cancellation. Alle Adapter erhalten **dieselbe** `Arc<dyn CapabilityService>`, konkret dieselbe ApplicationServices-Instanz wie REST. Keine direkten SQL-/OPC-UA-Aufrufe im IPC-Code. Sechs Tools und zwölf lesende Capabilities/Resources bleiben exakt der bestehenden [Allowlist](oip-mcp-capability-mapping.md) verpflichtet. Keine Mutationen, Subscriptions, zusätzliche Agenten oder Netzwerk-MCP-Listener.

Die Bridge authentifiziert zunächst ihre lokale Verbindung, danach transportiert sie unveränderte MCP-Bytes. Sie ist kein JSON-RPC-Dispatcher, HTTP-Tunnel, Policy-Generator oder automatischer Core-Launcher. Echte offizielle SDK-Clients prüfen den gesamten stdio→Bridge→UDS→SDK→CapabilityService-Pfad. stdout enthält ausschließlich MCP. Fehler/Diagnosen gehen nach stderr. Keine Wiederverbindung mitten in einer Sitzung; nach Verbindungsverlust muss der Client eine neue MCP-Sitzung initialisieren.

## Geschützte lokale Konfiguration

`IpcConfig` ist strikt deserialisiert, maximal 64 KiB:

- `socket`: absoluter kanonischer Pfad ohne Symlink-Komponenten, maximal 100 Unix-Pfadbytes; vorhandenes privates Elternverzeichnis.
- `max_sessions`: 1–32, Standard 16; umfasst auch noch nicht authentifizierte Verbindungen.
- `clients`: 1–32 Einträge mit OS-UID, geschützter `credential_file` und vorhandener `McpPolicy` (Actor, explizite Read-Permissions, SourceScope).
- `rest_policy`: ausdrücklich konfigurierte read-only Operator-Policy für denselben Loopback-REST-Adapter. Keine von einem MCP-Client gesetzten HTTP-Grants.

Konfiguration und Credential-Dateien müssen regulär, ungesymlinkt, einfach verlinkt und vom Daemon-UID besessen sein, ohne Group-/Other-Rechte. Pfad- und Descriptor-Metadaten werden geprüft. Credentials sind exakt 32 zufällige Binärbytes, nicht Beispielpasswörter und nicht Teil des Source-Pakets. Doppelte/Null-Credentials und SimulationControl-Grants werden abgewiesen. Schutz gegen Änderungen durch den vertrauenswürdigen Eigentümer wird nicht behauptet.

Der Socket liegt in einem vom UID besessenen Verzeichnis ohne Group-/Other-Rechte (Setup 0700); Socket 0600. Gerade auf macOS ist die Verzeichnisgrenze entscheidend. Kernel-Peer-UID wird beidseitig über Tokio `UnixStream::peer_cred()` geprüft; PID wird, soweit vom OS geliefert, protokolliert. OIP-007 unterstützt ausdrücklich nur den Daemon-OS-Benutzer. Eine fremde konfigurierte UID wird bereits beim Start verweigert; kein privilegierter Multi-User-Dienst.

Interner IPC-Prelude: acht feste Magic-Bytes `OIPIPC1\n` plus 32 Credential-Bytes, insgesamt maximal 40 Bytes, zwei Sekunden Deadline; Erfolg ein einzelnes Byte. Danach ausschließlich SDK-MCP. Die serverseitig geladenen Credentials und der tatsächliche Peer bestimmen die Policy. Freie Namen, Session-/Connection-IDs, `clientInfo`, Grants/Actor/Role/Tenant-Felder oder Toolparameter können diese Bindung nicht ersetzen. Der Prelude ist eine lokale OIP-Transportauthentisierung, keine MCP-Protokollerweiterung für externe Clients.

**Vertrauensgrenze:** Der OS-Eigentümer und seine geschützte Startkonfiguration bleiben vertrauenswürdig. Code mit denselben OS-Dateirechten kann weitere Owner-Credentials lesen/ersetzen und auf den ausdrücklich freigegebenen lokalen REST-Operatorzugang zugreifen. SourceScope ist eine überprüfte Delegation pro Credential, **keine Isolation feindlicher Prozesse desselben UID und kein Tenant-Modell**. Ein Source-A-Credential kann über eine neue Bridge keine Source-B-Rechte erhalten; Besitz eines anderen freigegebenen Credentials ist eine andere Autorität. Produktive Identitäten/Remote-/Tenant-Isolation fehlen weiterhin.

## Socket-Ownership und sichere Bereinigung

Eine zusätzliche exklusive OS-Dateisperre schützt den IPC-Endpoint unabhängig von der unveränderten kanonischen SQLite-Sidecar. Die IPC-Sidecar ist regulär, Owner-only, nicht symlink-/hardlinked. Sie enthält ausschließlich die nach chmod erfasste Socket-Identität `(dev, ino, ctime, ctime_nsec)`, begrenzt auf 256 Bytes und unter Lock synchronisiert.

Ein fehlgeschlagener Connect beweist auf macOS keinen verwaisten Socket: Auch ein voller Listen-Backlog kann ConnectionRefused liefern. Deshalb wird ein existierender Socket **nur** bereinigt, wenn UID/Typ und gespeicherte eigene Identität passen, die Sperre erworben ist und der auf 500 ms begrenzte Connect tatsächlich verweigert wird. Erfolgreicher Connect/Timeout, fremde/unbekannte Identität, Links und reguläre Dateien werden verweigert. Direkt vor Unlink erneuter Identitätsvergleich. Cleanup entfernt ausschließlich den eigenen unveränderten Socket; Lockdateien bleiben als kooperative Ownership-Evidenz bestehen.

Normale Startup-I/O-Fehler nach Bind werden durch einen früh erstellten Guard zurückgerollt, einschließlich unvollständig publiziertem Record. Ein Crash in diesem winzigen Publikationsfenster muss dagegen fail-closed bleiben; der Operator prüft die Restdateien, es gibt keinen automatischen Delete-anything-Schalter.

## Begrenzungen, Cancellation und Cleanup

- Maximal konfigurierte Sessions; begrenztes JoinSet, fertige Tasks werden gejoint und gezählt. Überschreitung verweigert nur die neue Verbindung.
- Pro Session unverändert maximal 16 ausstehende Requests, 16 KiB Inputzeile, 4 MiB strukturierte Ausgabe, 15 s Read-Deadline, Nodes 1–100 je Seite und Events maximal 100. Die Legacy-Textkopie kann den Wire-Umfang erhöhen. Keine unbegrenzte History oder Replay-Garantie.
- EOF, fehlerhafte/duplizierte Admission und Output-Stall canceln ausschließlich das Session-Kindtoken. Dadurch werden laufende Service-Futures inklusive vorhandenem Interrupted-Audit freigegeben. Weder andere Sessions noch der Writer erhalten diesen Token.
- Authentisierte Clients dürfen nach modernem Discover legitim idle bleiben. Session-Grenze statt einer falschen Initialisierungsfrist; Daemon-Shutdown cancelt auch Bootstrap/Idle.
- SDK-Ausgabestall weiterhin drei Sekunden. Bridge-Ausgabe: 8-KiB-Puffer, nichtblockierender duplizierter Unix-stdout-FD, Tokio Unix-Pipe Sender und drei Sekunden Schreibfrist. Keine Frist auf bloßes Warten auf neue Daten. Bei teilweiser Ausgabe/Stall wird die ganze Session geschlossen, niemals der beschädigte Stream fortgesetzt.
- Die bereits vorhandene sichere API `tokio::net::unix::pipe::Sender::from_owned_fd` prüft den duplizierten stdout-Pipe-FD und setzt Nonblocking. Keine neue Dependency, kein eigener unsafe-Code, keine Verwendung der inzwischen als unsound markierten alten AsyncFd-Konstruktoren. MCP-stdout muss auf Unix ein Client-Pipe sein; Terminal-/Dateiumleitung ist kein unterstützter MCP-Transport. Der FD-Modus gehört diesem Prozess und seinem einzigen Protokollwriter. Tokio-stdout mit blockierendem Worker genügte hier nicht, weil dessen globale stdout-Sperre sogar den Prozessabschluss festhalten konnte. Der sichere Writer wird deshalb auch im alten Unix-stdio-Modus verwendet.
- Der Bridge-Prozess besitzt keinen SDK-Collector/Writer. Sein Tokio-stdin kann wie schon im alten stdio-Modus einen OS-blockierten Read-Thread besitzen; Main begrenzt Executor-Abschluss auf zwei Sekunden. Keine unbewiesene Join-Garantie für solche stdio-Threads. Der nichtblockierende Output vermeidet den tatsächlich nachgewiesenen Exit-Hänger.

Gesamtressourcen sind durch Session- und Request-Limits begrenzt, nicht pro Mandant reserviert. Ein vertrauenswürdiger lokaler Benutzer kann neue Verbindungen bis zur Grenze belegen; bestehende autorisierte Sessions bleiben unabhängig. Globale faire CPU-/Memory-Budgets und dauerhafte Audit-Puffer sind keine implementierten Produktgarantien.

## Audit und Security

Bestehender CapabilityAudit-Port, Actor, Capability, registriertes Ziel, Scope-Korrelation, Entscheid/Ergebnis und Zeitpunkt bleiben unverändert. IPC ergänzt serverseitige Session-ID, Peer-UID/PID, Admission/Cleanup und Autoritätsbindung. Keine Credential-Bytes/Hashes oder vollständigen MCP-Payloads in Produktlogs. SDK-Rohlogging ist auch bei aggressivem RUST_LOG im Daemon/Bridge-Modus ausgeschaltet.

Audit bleibt nicht dauerhaft/manipulationssicher. Der Operator besitzt den stderr-Sink; ein absichtlich blockierter OS-Log-Sink ist keine geprüfte asynchrone Logging-Garantie. Keine Remote-Freigabe, Schreibtools oder Multi-Tenant-Versprechen. **RUSTSEC-2023-0071 bleibt Produktionsblocker**, weitere dokumentierte Advisories unverändert offen.

Konkrete Interop-, Security-, Performance- und Cleanup-Nachweise stehen im [Verifikationsbericht](../oip-007-verification.md).
