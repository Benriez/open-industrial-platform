# OIP Security Audit · Maßnahmen vom 25. November 2026

| Befund | Umsetzung und Freigabe |
| --- | --- |
| OIP-SA-01 · Geräteanmeldung | In der App unter **Einstellungen → Security & Access → Aktuelle Identität** verwalten. Der Core bindet die Kopplung an einen frischen Einmalcode. Der Widerruf beendet die Sitzungen der betroffenen Anmeldung und bleibt bei Neustart sowie nach Restore der Datenbank oder einer älteren Anmeldeliste wirksam, solange die aktuelle Widerrufsdatei erhalten bleibt. |
| OIP-SA-02 · Sitzungen | 30 Minuten Inaktivität und 12 Stunden maximale Gültigkeit. Statusabfragen und Live-Datenströme verlängern die Frist nicht. Acht Sitzungen pro Konto und 64 insgesamt. |
| OIP-SA-03 · Netzwerk-Relay | 64 gleichzeitige Verbindungen insgesamt, 12 je Tailnet-Quelladresse, zehn Sekunden bis zum ersten empfangenen Byte, fünf Minuten ohne Datenverkehr. Der macOS-Dienst sieht alle lokalen Clients über dieselbe Adresse und erlaubt dort 32 gleichzeitige Verbindungen. Die Freigaben im produktiven Tailnet müssen im zugehörigen Administrationskonto geprüft werden. |
| OIP-SA-04 · Protokoll | Der Core protokolliert Online-Schreibaktionen und die Verwaltung von Geräteanmeldungen in einem authentifizierten lokalen Journal. Ein unabhängiger externer Nachweis gegen Austausch von Journal, Schlüssel und Siegel durch das Core-Systemkonto steht aus. |
| OIP-SA-05 · RustSec | `url` ist auf 2.5.9 aktualisiert. Die ungenutzte eingebettete Postcard-Funktion und damit `atomic-polyfill` sind entfernt. `rsa 0.10.0` behebt `RUSTSEC-2023-0071`. Der Chrono-Kompatibilitätsadapter bezieht die Implementierung vollständig aus `sad-chrono 0.5.2` und ersetzt die aufgegebene Bibliothek aus `RUSTSEC-2026-0543`. Der Einsatz auf realen OPC-UA-Quellen und der Ersatz für den ungepflegten YAML-Parser (`RUSTSEC-2024-0449`) bleiben Gegenstand der OPC-UA-Abnahme. |
| OIP-SA-06 · macOS | Der Release-Weg unterstützt Developer ID, Notarisierung und eine Bereitstellungsdatei für biometrisch geschützten Schlüsselbundzugriff. Die Apple-Freigabe und der Nachweis auf einem Mac mit Touch ID stehen bis zur Bereitstellung dieser Apple-Zugangsdaten aus. |

Für den OPC-UA-Ersatzpfad ist der bereits vorhandene open62541-Adapter als
Vergleichskandidat vorgesehen. Freigabekriterien sind dieselben erlaubten
Endpunkte und Knotentypen, Browse- und Leseparität, geprüfte Zertifikatsbindung
und validierte Tunnelgrenzen auf den realen Quellen. Die aktuelle RustSec-Prüfung
läuft mit `cargo deny --locked check advisories` und ist in das lokale
OTA-Release-Verfahren eingebunden.

Die Sicherheitsdateien liegen neben der Datenbank. Die aktuelle Datei
`<Datenbank>.browser-credentials.json.revocations` bleibt für eine
Rücksicherung maßgeblich. Die Online-Prüfungen und das Vorgehen bei
unterbrochenen Schreibaktionen stehen im
[Vertrag für Browser-Sitzungen und Sicherheitsprotokoll](oip-009-browser-session-sse.md).
