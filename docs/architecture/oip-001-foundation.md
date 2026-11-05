# OIP-001 — Rust Foundation und OPC UA PoC

> Historische OIP-001-Architektur. Die aktuelle Security- und Storage-Architektur steht in [OIP-002](oip-002-security-storage.md).

## Umfang

OIP-001 stellt einen lokalen, read-only OPC-UA-Kreislauf bereit. Es gibt keine Webanwendung, kein Deployment und keine reale Geräteanbindung. Alle Netzwerklistener und Clients sind auf Loopback beschränkt.

## Crate-Verantwortlichkeiten

| Crate | OIP-001-Verantwortung |
|---|---|
| `oip-core` | Stack-neutrale IDs, Werte, Quality, Freshness, Timestamps, Collection Errors, Simulation Origin und Observation Envelope |
| `oip-simulator` | Deterministische Testanlage M-01, Szenarien und skalierbare Bulk-Werte |
| `oip-opcua` | Read-only-Adaptergrenze, async-opcua-Standardbackend, isolierter open62541-PoC und Testwerkzeuge |
| `oip-server` | Unverändert; spätere Backend-Orchestrierung |
| `oip-agent` | Unverändert; späterer lokaler Telemetrie-Agent |
| `oip-gateway` | Unverändert; späteres Edge-Gateway |
| `oip-storage` | Unverändert; spätere SQLite-/Evidenzpersistenz |
| `oip-diagnostics` | Unverändert; spätere evidenzbasierte Diagnostik |

## Adaptergrenze

`ReadOnlyOpcUaAdapter` besitzt ausschließlich Discovery-, Browse-, Read-, Subscribe- und Event-Operationen (`next_event`). Es gibt keine Write-, Method-Call- oder NodeManagement-Schnittstelle. OPC-UA-spezifische `NodeId`-, `Variant`- oder FFI-Typen sind nicht Teil von `oip-core`.

`ClientEvent` unterscheidet Beobachtungen, Verbindungsverlust, Reconnect mit `DataGap` und Subscription-Fehler. Fehlende Messwerte bleiben `None`; ein unbekannter Zustand wird weder als `offline` noch als numerischer Nullwert dargestellt.

### Security-Profil

`SecurityProfile::LocalSimulation` ist das einzige Profil, das `SecurityPolicy=None` mit anonymer Authentifizierung verwenden darf. `SecurityProfile::Production` schlägt fehl, solange kein Trust Store und keine Zertifikate konfiguriert sind; es wird nie still auf `None` herabgestuft. Der Session-Reconnect-Versuch muss endlich sein; ein unbegrenztes `-1` wird abgelehnt.

### Grenzen gegenüber untrusted Quellen

- Der Endpoint muss eine geparste Loopback-URL mit literaler Adresse `127.0.0.1` oder `::1` sein. `localhost` wird abgelehnt, damit die Loopback-Zusage nicht von der Namensauflösung abhängt.
- Die Herkunft einer Beobachtung gilt nur dann als vertrauenswürdig, wenn sie dem erwarteten lokalen Simulationsursprung entspricht. Eine abweichende oder leere `origin_id` wird als `InvalidProvenance` gemeldet und nicht übernommen; die Beobachtung erhält dann keinen Simulationsursprung.
- Der Client liest Herkunftsmetadaten aus dem Adressraum, behandelt sie aber als Eingabe: `seed`, `scenario`, Epoch und Tick-Dauer werden gegen die erwartete Simulations-ID geprüft.
- Die Browse-Traversierung ist auf `max_browse_nodes` begrenzt und bricht mit `BrowseLimitExceeded` ab.
- Freshness wird aus dem Alter des Source-Timestamps abgeleitet. Zu alte Werte ergeben `Stale`, Werte zu weit in der Zukunft ergeben `Uncertain`.
- Fehlende oder zu große Ereigniskanäle werden nicht still verschluckt: verworfene Beobachtungen werden gezählt und protokolliert, der Zähler ist über `dropped_observations()` abrufbar.

## Testanlage

Namespace: `urn:oip:local-simulation` (im aktuellen lokalen Adressraum Index 2).

Unter `M-01` werden bereitgestellt:

- `temperature` in °C
- `pressure` in kPa
- `motor_running`
- `operating_mode`
- `alarm_active`
- `units_produced`
- statische Unit-Nodes für Temperatur und Druck

Unter `Bulk` werden standardmäßig 1.000 Double-Nodes (`bulk.0000` bis `bulk.0999`) erzeugt. Unter `Simulation` liefern `origin_id`, `seed` und `scenario` die Herkunftsmetadaten.

Szenarien: `normal`, `temperature_rise`, `critical_sensor`, `sensor_fault`, `server_restart`, `connection_interrupted`, `reconnect`.

Die Szenarien beschreiben die **Wertsebene** der Anlage: `server_restart` meldet den Collector als nicht verfügbar, `connection_interrupted` meldet eine unterbrochene Verbindung, `reconnect` meldet Werte nach einer Wiederverbindung. Sie öffnen und schließen keine Socket und starten keinen Serverprozess neu. Die **Transportebene** — echter Abbruch, echter Server-Neustart auf demselben Loopback-Port, anschließende Wiederverbindung mit erneuter Subscription — wird von den Integrationstests in `crates/oip-opcua/src/async_opcua/client/tests.rs` durchgeführt.

Gleicher Seed, Szenario und Tick erzeugen denselben fachlichen Frame. Die Quelle verwendet einen festen virtuellen Epoch und `tick * tick_duration_ms`; Wall-Clock, Netzwerk- und Scheduler-Timing steuern die fachlichen Werte nicht.

## Timestamp und Quality

Der Server setzt SourceTimestamp aus der virtuellen Simulation und ServerTimestamp beim Schreiben. Der Client fordert `Both` an und ergänzt einen Received-Timestamp. Der OPC-UA-StatusCode wird im neutralen Envelope als Rohwert und als Quality abgebildet.

Bei `sensor_fault` bleibt der Temperaturwert `None`, Quality ist `Bad` und der Collection Error ist `InvalidMeasurement`. async-opcua 0.19.0 verwirft beim Lesen valueless DataValues den Status; der Adapter verwendet daher `Variant::Empty`, damit Bad-Status und fehlender numerischer Wert übertragen werden.

Die konkrete Fehlerursache wird über unterscheidbare OPC-UA-StatusCodes übertragen und vom Client verlustfrei zurückgebildet: `BadSensorFailure` → `InvalidMeasurement`, `BadNotConnected` → `DeviceUnreachable`, `BadConnectionClosed` → `ConnectionInterrupted`, `BadWaitingForInitialData` → `CollectorUnavailable`. `DataQuality::Unknown` und `DeviceUnreachable` sind damit über den Adapter erreichbar und nicht mehr toter Code.

## Reconnect

Der async-opcua-Client deaktiviert die stille automatische Subscription-Wiederherstellung (`recreate_subscriptions=false`). Nach einem tatsächlichen Reconnect werden zunächst veraltete Subscriptions gelöscht, dann Simulationsmetadaten erneut gelesen und danach Subscription und Monitored Items explizit neu erstellt. Die Resubscription läuft in einem separaten Tokio-Task, damit die Session-Event-Loop weiterpollen kann. Zwischen Verbindungsverlust und erfolgreicher Resubscription wird eine `DataGap` gemeldet.

Ein Reconnect ohne zuvor beobachteten Verbindungsverlust führt ebenfalls zur Wiederherstellung der Subscription; die Datenlücke wird dann mit dem Reconnect-Zeitpunkt und der Begründung „reconnect without recorded connection loss" ausgewiesen. `Reconnected` wird ausschließlich nach erfolgreicher Resubscription gemeldet, sonst `SubscriptionError`.

## Start

Voraussetzung: macOS mit Rust 1.93 oder kompatibler Toolchain. Es werden keine Cloud-Konten oder realen Anlagen verwendet.

```sh
cargo run -p oip-opcua --bin oip-simulated-server -- \
  --port 4840 --seed 42 --scenario normal --bulk-nodes 1000 --tick-ms 1000
```

In einem zweiten Terminal:

```sh
cargo run -p oip-opcua --bin oip-test-client -- \
  --url opc.tcp://127.0.0.1:4840 --namespace 2 --samples 5
```

Der Server wird mit Ctrl+C beendet. `--samples 0` lässt den Client bis Ctrl+C laufen.

Weitere Szenarien:

```sh
cargo run -p oip-opcua --bin oip-simulated-server -- --scenario temperature_rise
cargo run -p oip-opcua --bin oip-simulated-server -- --scenario critical_sensor
cargo run -p oip-opcua --bin oip-simulated-server -- --scenario sensor_fault
```

## Security-Grenzen

- Listener: ausschließlich `127.0.0.1`.
- Client: nur geparste `opc.tcp`-URLs mit literaler Loopback-Adresse `127.0.0.1` oder `::1`; andere Hosts und der Alias `localhost` werden vor dem Verbindungsaufbau abgelehnt.
- `SecurityPolicy=None` und `MessageSecurityMode=None` gelten nur für `SecurityProfile::LocalSimulation`. Andere Profile schlagen fehl.
- Keine automatische Vertrauensfreigabe: `trust_server_certs(false)` und `trust_client_certs(false)`.
- Keine Schlüsselerzeugung und keine PKI-Ablage im PoC; verschlüsselte Endpunkte sind nicht Teil dieses Nachweises.
- Server-Variablen sind mit `CURRENT_READ`, ohne `CURRENT_WRITE`, angelegt und per gelesenem `UserAccessLevel` für alle sechs Prozesswerte geprüft.
- Keine Writes, Method Calls oder NodeManagement-Operationen im Testclient.
- Die Session besitzt einen endlichen Reconnect-Versuchszähler.

### Bekannte Restrisiken im OIP-001-Umfang

- Auf einem Mehrbenutzer-Host kann jeder lokale Prozess die unverschlüsselte Simulation lesen. Für geteilte Hosts ist eine Bind-Adresse- oder ACL-Regelung erforderlich.
- Ein bösartiger lokaler Server kann in async-opcua 0.19.0 beim Dekodieren extremer OPC-UA-Zeitstempel einen Panic in der Abhängigkeit auslösen. Das ist im Upstream zu beheben; der Adapter begrenzt die Werte, die er selbst verwendet.
- Das optionale Feature `open62541-backend` bindet natives C per FFI ein. Diese Abhängigkeit liegt außerhalb der `unsafe_code = "forbid"`-Regel des Workspace und ist nicht Teil des Standard-Builds.
- Es existiert noch keine CI und kein `cargo audit`/`cargo deny`; Abhängigkeitslücken sind nicht geprüft.

Die Stackentscheidung und Vergleichsdaten stehen in [ADR 0001](../decisions/0001-opc-ua-stack.md). Ausführungsnachweise stehen im [OIP-001-Verifikationsbericht](../oip-001-verification.md).
