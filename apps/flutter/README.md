# Open Industrial Platform · Flutter

Gemeinsame Flutter/Dart-Codebasis für Web und macOS. UI spricht ausschließlich die öffentliche Rust-API v1 an. Keine Hardware-/OPC-UA-Logik in Dart.

## Spectrum Workstation

Spectrum ist das farbenfrohe Dark-Standardtheme. Die Schaltfläche **Darstellung wechseln** durchläuft Spectrum → Daylight → Graphite. Getönte Gradient-Panels, semantische Statusindikatoren, KPI-Tiles, Inspector und Chart-/Timeline-Container liegen in `lib/widgets/components.dart`; Palette, Statusfarben, Breakpoints und Theme-Varianten in `lib/design_system/theme.dart`.

Die fünf Ansichten bleiben read-only. Die Diagnostics kann echte, zeitgestempelte Collection-Ereignisse zusätzlich als Zeitspur darstellen; die klassische Liste bleibt verfügbar. Incidents ohne reale Zeitstempel werden nicht in diese Zeitachse projiziert. Flutter implementiert keine eigene MCP-Runtime und zeigt keine künstliche Agentenaktivität. Der lokale Rust-MCP-Adapter aus OIP-006 verwendet dieselben Application Services wie REST/SSE.

## Lokaler Start

Aus dem Repository-Root:

```sh
cd apps/flutter
flutter pub get
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn --pwa-strategy=none
cd ../..
cargo run -p oip-server -- --demo
```

Danach `http://127.0.0.1:8080` öffnen. `--demo` startet den lokalen read-only OPC-UA-Simulator automatisch. Die Datenbank `oip-demo.sqlite` enthält ausschließlich Simulation. Beenden mit Ctrl-C.

Native App bei laufendem Backend:

```sh
cd apps/flutter
flutter run -d macos --dart-define=OIP_API_URL=http://127.0.0.1:8080
```

Web und native App verwenden dieselbe UI. `OIP_API_URL` ist eine Compile-Time-Konfiguration; im Web ist der Default die aktuelle Origin, nativ `http://127.0.0.1:8080`.

## Checks

```sh
flutter analyze
flutter test
flutter test integration_test/live_dashboard_test.dart -d macos --dart-define=OIP_API_URL=http://127.0.0.1:8080
```

Browser-Fachregression sowie reproduzierbare Screenshots/Frame-Pacing bei laufendem Server:

```sh
cd apps/flutter/test
npm ci
OIP_URL=http://127.0.0.1:8080 npm run test:browser
OIP_URL=http://127.0.0.1:8080 npm run test:spectrum
OIP_URL=http://127.0.0.1:8080 npm run test:visual
```

Die Skripte schreiben unabhängig vom aktuellen Arbeitsverzeichnis getrennt nach `docs/evidence/oip0061/browser/` und `visual/`. `OIP_EVIDENCE_DIR` kann das jeweilige Ausgabeverzeichnis überschreiben. Ältere Lieferantenevidenz bleibt erhalten. Node ≥18 ist erforderlich. Auf diesem macOS-Host wird vorhandenes Chrome verwendet; sonst `npx playwright install chromium` ausführen oder `CHROME_PATH` auf einen Chrome-/Chromium-Binarypfad setzen. Release-Browser prüfen DOM-Überlauf; Flutter-Render-Überläufe werden durch die Widgettests mit `tester.takeException()` geprüft.

Flutter 3.22.0 / Dart 3.4.0 ist die auf diesem Host ausgeführte stabile Toolchain und in der CI gepinnt. Kein Upgrade oder globale Systeminstallation gehört zu diesem Slice. Der aktuelle Abgleich, tatsächliche Ergebnisse und Plattformgrenzen stehen in `docs/oip-006-1-spectrum-integration.md`; ältere Verifikationsberichte bleiben historische Nachweise.
