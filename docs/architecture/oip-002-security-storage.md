# OIP-002: Security, robuste Verarbeitung und Persistenz

## Modulgrenzen

- `oip-core`: Domainmodell, `ClientEvent`, `DataGap`, `EventContext`, `OriginClass`, neutraler `ObservationSink`/`EventSink` und `ObservationRepository`.
- `oip-opcua`: read-only Adapter, LocalSimulation und Production, Eingabevalidierung, beide Interop-Richtungen.
- `oip-storage`: SQLite-Implementierung der neutralen Verträge. Keine Abhängigkeit zu `oip-opcua`.
- `oip-simulator`: unveränderte deterministische M-01-Wert- und Szenariologik.
- `oip-server`, `oip-agent`, `oip-gateway`, `oip-diagnostics`: weiterhin bewusst ohne neue Produktfunktion.

## SecurityProfile

`LocalSimulation` verwendet None/Anonymous ausschließlich mit literalen Loopback-Adressen. `Production` verlangt dagegen:

- `Basic256Sha256` + `SignAndEncrypt`;
- absolute PKI-Wurzel und traversal-freie relative Pfade zu Zertifikat und privatem Schlüssel;
- vorhandenes `trusted`-Verzeichnis mit byte-genau installierten Peer-Zertifikaten;
- erfolgreiches Parsen und Zeitvalidierung des eigenen Zertifikats sowie Parsen des privaten Schlüssels vor dem Start;
- keine Auto-Trust-Einstellung und keine insecure Fallback-Konfiguration.

Der Production-Server hat keinen None-Endpunkt. Der Verbindungsaufbau ist auf 15 Sekunden begrenzt. Private-Key-Inhalte werden nicht protokolliert. Zertifikatspfade und Thumbprints sind keine geheimen Schlüsseldaten.

### Rotation und Reconnect

Ein normaler Serverneustart mit unverändertem Zertifikat verwendet weiterhin den OIP-001-Resubscribe-Pfad. Nach einem Serverzertifikatswechsel beendet der alte Client den Reconnect mit einem expliziten Security-Ereignis, weil async-opcua 0.19 den alten Thumbprint cached. Ein neuer Client führt Discovery erneut aus und verbindet sich nur, wenn das neue Zertifikat bereits im Trust Store liegt. Clientseitige Schlüsselrotation erfordert ebenfalls eine neue Client-Konfiguration; laufende Schlüssel werden nicht still aus dem Dateisystem nachgeladen.

## Eingabe- und Zeithärtung

- Wire-DateTime: Grenzwerte und Property-Tests über beliebige `i64`-Ticks, ohne Prozessabbruch.
- Null-, Endtime- und außerhalb 1601–9999 liegende Source-/Server-Zeit: `InvalidTimestamp`, Quality Bad, Freshness Unknown; ursprünglicher Millisekundenwert bleibt erhalten.
- Domain-Timestamp außerhalb des OPC-UA-Kalenders: `TimestampOutOfRange` vor der Upstream-Tick-Arithmetik.
- Freshness-Rechnung: `i128`, keine signed-overflow-Falle.
- NaN/±Infinity: explizite Eingabe-/Storage-Fehler statt JSON-/SQLite-NULL-Verfälschung.
- Fehlende Messwerte bleiben `None`; kein Zero- oder Offline-Fallback.

## SQLite

Schemaversion 1 enthält:

- `source_identities` und `device_identities`;
- `observations` mit Source/Server/Received, Quality, Freshness, CollectionError, Origin-Class und vollständigem JSON-Payload;
- `collection_events` mit Source, Art, Zeit, Payload und Duplicate-Zähler;
- `data_gaps` mit Source, Beginn, Ende, Grund und Duplicate-Zähler;
- `schema_migrations` mit Version, Name und SHA-256-Checksum.

`EventContext` ist für alle Events verpflichtend. Bei Observation-Events muss er exakt zur Observation passen. Dadurch kollidieren gleichartige Ereignisse verschiedener Quellen nicht. `latest_observation` verlangt Entity, DataSource und Metric.

Migrationen sind append-only; Checksummen- oder Versionsabweichungen schlagen fehl. Writes verwenden `IMMEDIATE`-Transaktionen; ein Batchfehler rollt alle bereits verarbeiteten Events zurück. WAL und `synchronous=FULL` sind konfiguriert. Die Tests schließen Öffnen nach Neustart, Idempotenz, Rollback, corrupted DB/JSON, Source-Trennung und `u64::MAX` ein.

## CI

`.github/workflows/ci.yml` definiert fmt/check/clippy, beide OPC-UA-Feature-Konfigurationen, Default-Tests auf Linux x86_64/ARM64, macOS ARM64 und Windows x86_64, open62541-Interop unter Linux sowie `cargo-deny` für Advisories, Lizenzen, Bans und Quellen. Toolchain und Actions sind gepinnt. Die Konfiguration ist kein Nachweis eines bereits erfolgten Remote-Laufs; siehe Verifikationsbericht.

## Befehle

```sh
cargo test --workspace -- --test-threads=1
cargo test -p oip-opcua --features open62541-backend -- --test-threads=1
cargo check -p oip-opcua --no-default-features --all-targets
cargo check -p oip-opcua --no-default-features --features open62541-backend --all-targets
cargo run -p oip-opcua --bin oip-simulated-server -- --port 4840 --bulk-nodes 1000
cargo run -p oip-opcua --bin oip-test-client -- --url opc.tcp://127.0.0.1:4840 --samples 2
```

Production ist in OIP-002 eine Library-/Testfunktion; die Simulator-CLI bleibt absichtlich lokal und unverschlüsselt. Es werden keine realen Anlagen verbunden.
