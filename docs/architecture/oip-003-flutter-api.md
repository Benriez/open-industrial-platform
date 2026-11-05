# OIP-003 — Flutter, lokale API und Live-Dashboard

## Grenzen und Komponenten

Flutter/Dart ist die einzige Produkt-UI. Material 3 trägt ein eigenes OIP-Designsystem. Es gibt keine FFI-Verbindung, keine Rust-Crate-Abhängigkeit in Flutter und keine OPC-UA-Protokolllogik in Dart. Die acht bestehenden Workspace-Crates bleiben erhalten. Die Änderungen an Rust beschränken sich auf den vorher leeren `oip-server` und dessen Abhängigkeiten/Lockfile.

- `apps/flutter/lib/app`: Anwendung, responsive Shell, ChangeNotifier-Zustand und Reconnect.
- `core`: SSE-Parser und Transportvertrag.
- `design_system`: Farben, Typografie, Abstände, Breakpoints und Theme-Konfiguration.
- `models`: typisierte DTOs für Rusts öffentliche API.
- `services`: REST, nativer SSE-Byte-Stream und bedingt eingebundener Web-EventSource-Adapter.
- `features`: Overview, Devices, Network & VPN, OPC-UA-Browser, Diagnostics.
- `widgets`: Surfaces, Status-Pills, Metrikkarten, responsive Grids, Details, Zustände und CustomPainter-Chart.
- `crates/oip-server/src`: `contracts`, `state`, `collector`, `demo`, `api` und CLI.

`--demo` startet den unveränderten lokalen OPC-UA-Simulator innerhalb des Rust-Prozesses. Ein dedizierter Supervisor startet/stoppt ausschließlich diesen Simulator für Sensor-/Offline-Szenarien. Ohne `--demo` verbindet sich der Server lesend zum separat gestarteten Loopback-Simulator; die Demo-Steuerung ist dann gesperrt.

## Vertikaler Datenpfad

1. Bestehende deterministische Simulation veröffentlicht sechs Prozessvariablen und 1.000 Bulk-Nodes über async-opcua.
2. Bestehender read-only Adapter führt Discovery/Browse/Read/Subscribe aus.
3. `ObservationEnvelope` bleibt das Rust-Domänenmodell mit Quality, Freshness, Source/Server/Received-Zeit und SimulationOrigin.
4. Der Collector schreibt `ClientEvent` zuerst über `SqliteStore::ingest_event`. Erst nach erfolgreichem Commit aktualisiert er den veröffentlichten Zustand.
5. REST lädt den Anfangszustand. SSE überträgt vollständige, konvergente Snapshots bei Änderungen und spätestens jede Sekunde. Ein unterbrochener Client lädt REST erneut und erhält einen neuen vollständigen Snapshot; kein unimplementiertes Event-Replay wird zugesagt.
6. Flutter hält maximal 60 empfangene Temperaturpunkte der Sitzung. Fehlende/ungültige Werte und Quellzeitsprünge werden nicht zu Linien über Datenlücken verbunden.

Sechs Prozessvariablen sind kontinuierlich abonniert. Der Bulk-Browser liest maximal 100 Variablen je API-Seite (UI: 40), mit maximal acht gleichzeitigen Reads; jede erfolgreiche Einzelabfrage wird ebenfalls persistiert. Die UI rendert nur die Seite über `ListView.builder`. Bulk-Einzelabfragen behaupten keinen gesunden Prozess-Collector.

Der lokale Dashboard-Server verlangt eine eigene Simulationsdatenbank; fremde oder externe Observation-Herkünfte werden vor Veröffentlichung abgelehnt.

SQLite verwendet die unveränderte OIP-002-Migration, WAL, FULL-Synchronisierung, Inhalts-Idempotenz und Source-/Origin-Trennung. Werte werden nach Prozessneustart wiederhergestellt, aber bis zu neuem Empfang ausdrücklich als stale behandelt. Es gibt noch keine Langzeit-Retention oder TSDB. Startup und Collection-Event-Abfrage lesen bestehende Evidenz vollständig ein; das ist eine bekannte Skalierungsgrenze dieses lokalen Slices.

## API v1

Verbindliche Rust-DTOs: `crates/oip-server/src/contracts.rs`; Dart-DTOs: `apps/flutter/lib/models/contracts.dart`. JSON verwendet snake_case, Timestamps sind Unix-Millisekunden, fehlende Werte `null`. Der originale Domänenwert bleibt ein getaggtes Objekt, z. B. `{"float":60.5}` oder `{"boolean":true}`. `null` ist niemals numerisch Null.

| Methode / Pfad | Antwort / Verhalten |
|---|---|
| `GET /api/v1/system/status` | `SystemStatus`: Version, Simulation, OPC-UA-/Subscription-Status, letzter Empfang, Persistenzzähler, CPU/GPU/RAM optional, offener Security-Blocker |
| `GET /api/v1/devices` | `Device[]`: backendseitiges Inventar, Simulation und fünf getrennte Health-Dimensionen |
| `GET /api/v1/devices/{id}` | `{device, metrics, history_status:"not_implemented"}`; unbekannte ID: 404 |
| `GET /api/v1/metrics/current` | `ObservationEnvelope[]` für sechs Prozessvariablen, nach Commit |
| `GET /api/v1/events` | `{incidents, collection_events, diagnosis_history_status:"demo_only"}`; höchstens 50 publizierte Nicht-Observation-Events |
| `GET /api/v1/opcua/nodes` | `NodePage {items,total,offset,limit}`; Query `q`, `folder=M-01|Bulk|all`, `offset`, `limit` (1–100) |
| `GET /api/v1/stream` | `text/event-stream`, Ereignistyp `snapshot`, Daten `Snapshot {system,devices,metrics,incidents,topology}`; 2-s-Keepalive, vollständiger Zustand mindestens jede Sekunde |
| `POST /api/v1/demo/scenario` | Nur `--demo`; JSON `{"scenario":"normal"}`; 200 bedeutet angenommen, nicht bereits abgeschlossenen OPC-UA-Wiederanlauf |

Strukturierte Fehler: `{ok:false,code,message}`. Unter anderem `DEVICE_NOT_FOUND`, `INVALID_QUERY`, `INVALID_JSON`, `INVALID_SCENARIO`, `DEMO_DISABLED`, `LOCAL_ONLY`, `STORAGE_UNAVAILABLE`. Nicht erlaubte HTTP-Methoden folgen Axums 405-Standardantwort.

Die statischen Flutter-Dateien werden von Axum aus `apps/flutter/build/web` ausgeliefert. REST/SSE sind same-origin. Die CLI akzeptiert nur Ports, keinen Bind-Host, und bindet immer `127.0.0.1`. Host-/Origin-Prüfung lehnt fremde Hosts und fremde Origins ab. Es gibt keine CORS-Freigabe und keine produktive Remote-Authentifizierung. Native Clients verwenden HTTP auf Loopback.

## Wahrheit und Freshness

- Alle Inventargeräte, Topologielinks, Demo-Incidents und OPC-UA-Simulatorwerte sind ausdrücklich Simulation.
- CPU, GPU, RAM und echter Netzwerkzustand bleiben `null`/`unknown`; es existiert kein Host-/GPU-Collector.
- GPU-, Inferenz-, VPN- und Agent-Szenarien sind explizite Rust-Fixtures in Diagnostics/Topology. Sie erzeugen keine angeblichen Host-Messwerte.
- Der Sensoralarm wechselt den echten lokalen OPC-UA-Simulator zu `critical_sensor`; die Temperatur über 90 °C und `alarm_active` müssen tatsächlich empfangen werden.
- Offline stoppt den echten Simulator sechs Sekunden und startet ihn neu. Der Stream zum Dashboard bleibt erreichbar; Collector-Gesundheit und UI-Transport werden getrennt angezeigt.
- Browser-Offline trennt zusätzlich die tatsächliche UI-Verbindung. Flutter erkennt EOF/Fehler oder sechs Sekunden ohne SSE-Ereignis; Reconnect mit 1/2/4/8 Sekunden Abstand.
- Die Quellzeit der Simulation ist virtuell. Gegen Wanduhr verglichen wird ausschließlich die lokale Empfangszeit: nach fünf Sekunden ohne Prozesswert gilt der Collector als stale. Ein frischer Empfang sagt nichts über einen fehlenden externen Agenten oder Dienst aus.

## Design und Plattformen

Referenz: `design/reference/Open Industrial Platform Demo.html`. Die gesamte Datei enthält Landingpage, App-CSS, 18 Konzeptgeräte, sieben Seiten, vier Szenarien, Diagramme, Netzwerkmodell, Browser, Drawer, Such-/Filter-/Flow-/Copy-Interaktionen und Breakpoints 1100/820/620. Die neue App übernimmt den Produktbereich: blau-schwarze Surfaces, mintfarbene Navigation, ruhige Karten, Status-Pills, dezente Konturen und klare Typografie.

Bewusste Unterschiede: keine Marketing-Landingpage, keine noch ungebaute Flow-/Integrationsverwaltung, 17 angeforderte Gerätetypen statt des zusätzlichen Konzept-Inferenzservers, authentischer Temperaturtrend statt erfundener GPU-Verläufe, paginierter echter OPC-UA-Adressraum statt sieben hartcodierter Konzeptnodes, Dark und Light, Drawer unter 1080 px und gestapelte Panels unter 700–800 px. Topologie ist ein interaktives Zonen-/Pfadmodell; kein frei verschiebbarer Graph. Animationen beschränken sich auf Material-Fokus, Menüs und Themewechsel.

Web-Engine, Roboto und Symbolfallback sind lokal gebündelt, inklusive Lizenzen. Der eigene Bootstrap überschreibt CanvasKit- und Fontfallback-URLs. Es gibt keinen Service Worker und keine Laufzeit-CDN-Abhängigkeit. Der Browsernachweis blockiert ausnahmslos alle fremden Origins.

Web ist P0; macOS nutzt dieselben Features, REST und SSE mit freigegebenem Sandbox-Netzwerkclient. Windows/Linux/Android/iOS benötigen später generierte Runner und die jeweiligen SDKs. Die Featurelogik enthält keine plattformspezifischen Sonderfälle; nur die SSE-Transportimplementierung ist technisch bedingt unterschiedlich.

## Sicherheit und nächste Phase

`RUSTSEC-2023-0071` bleibt ein produktiver Security-Blocker. `RUSTSEC-2023-0089` und `RUSTSEC-2024-0449` bleiben bekannte Upstream-Risiken. OIP-003 verändert keine dieser Ausnahmen und erlaubt ausschließlich lokale Simulation. Keine Industrieanlage, OPC-UA-Schreiboperation, Maschinensteuerung, öffentliche Exposition, VPN-Freigabe oder Cloud-Anbindung.

Nächste Phase: Security-Stack/Advisories lösen, authentifizierte öffentliche API-Verträge spezifizieren (ohne öffentliche Freigabe), echte freiwillige Host-Collector, bounded SQL-Historienabfragen/Retention, persistierte Diagnose-Läufe, weitere native Runner und plattformspezifische CI. Vor externer Nutzung ist eine neue Sicherheitsfreigabe erforderlich.
