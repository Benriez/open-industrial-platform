# OIP operations runbook (local instance)

The runbook describes how an operator runs a **local OIP Core** on a macOS
machine without OpenCode: how it is provisioned, started, stopped, restarted,
how its log is read and how its data is backed up and restored.

The historical operational receipts in `docs/evidence/oip-operations/`
cover the separate procedures below. The local Apple Silicon profile uses
its own installation and acceptance tests.

The tool is `tools/oip_ops.py`. It operates **one** explicit instance: one
configuration file, one IPC configuration, one database and one state
directory. It installs no system service, it contacts no endpoint outside the
machine and it refuses to touch the personal installation of the operator.

---

## Lokales Betreiberprofil auf Apple Silicon

OIP unterstützt in diesem Entwicklungsprofil einen lokalen Core und die
Spectrum-Browseroberfläche auf demselben Mac. Das Einrichtungswerkzeug
`current/tools/oip_local.py` richtet eine Arbeitsumgebung mit Organisation,
Infrastruktur und Standort ein. Der normale Betrieb braucht einen lokalen
Browser und eine Anmeldung. Einrichter und Betreiber können ohne GitHub-Konto,
Container oder KI arbeiten. Das Profil installiert keine systemweiten Dienste.

### Bestandsaufnahme des Ausgangspunkts

Grundlage ist `origin/main` bei `445c8a7eb0f251aebc28bb4f1da648070e8752bd`.
Der Checkout enthielt bereits die Spectrum-Workstations. Maßgeblich für UI und
Betriebsgrenzen sind die [kanonische UI-Baseline](../design/OIP_CANONICAL_UI_BASELINE.md)
und der [Remediation-Stand](../architecture/oip-security-audit-remediation.md).
Die GitHub-Issue-Funktion ist deaktiviert. Historische Prüfberichte belegen ihre
jeweilige Revision.

| Kategorie | Ausgangspunkt | Überprüfung am Checkout |
|---|---|---|
| Vorhanden und verifiziert | Spectrum, autorisierte Projektionen, lokale Browser-Anmeldung, SQLite und gespeicherte Beobachtungen | Vertragsdateien und Implementierungen in `apps/flutter`, `oip-server` und `oip-storage`; Skripte `canonical_regression.py` und `oip0082/acceptance.py` verfügbar |
| Vorhanden, ungeprüft | Nativer macOS-Updater, signierter Core-Paketweg, Sicherheitsbefunde und Rollout-Stand auf fremden Hosts | `tools/oip_ota_release.sh`, `tools/oip_update.py`, Auditunterlagen; produktive Installationen sind außerhalb dieses Profils |
| Fehlerhaft für diesen Auftrag | Die bisherige Datenbanksicherung deckte Konfiguration, Zertifikate und Geheimnisse unvollständig ab. Der SQLite-Snapshot war unverschlüsselt. | `tools/oip_ops.py`, Befehle `backup` und `restore` dienen dem historischen DB-Weg |
| Fehlte | Fortsetzbare Erstzuordnung, expliziter lesender OPC-UA-Betriebsmodus, prüfbares begrenztes Supportpaket und verschlüsselter Restore auf einer isolierten Instanz | Core-Provisioning und autorisierte Source-Reads waren bereits vorhanden. Die neuen Werkzeuge und der Supportpaket-Vertrag nutzen sie. |

### Voraussetzungen und erster Start

Benötigt werden Apple Silicon, ein lokales macOS-Benutzerkonto, Python ab 3.10,
ein aktueller Browser, Python-`cryptography` mit Ed25519-Unterstützung,
ein signiertes Paket samt vertrauenswürdig übergebenem
Herausgeberschlüssel und Schreibrechte für zwei private Ordner. Für Recovery
benötigt der Einrichter zusätzlich GnuPG mit AES-256/OCB, das mit macOS gelieferte
SQLite-Werkzeug und `sandbox-exec`. Das Profil verwendet ausschließlich
Loopback für HTTP und IPC für die geschützte lokale Autorisierung. Vor Anbindung
einer Testquelle muss ein Anlagen- oder Netzwerkverantwortlicher den Endpoint,
den Anlagenzugriff und die Belastung freigeben. Der Mac benötigt freien Platz
für Paket, aktive Datenbank, private Logs, Update-Staging und einen separaten
temporären Restore. Die dauerhaft zulässige Datenmenge im Pilotbetrieb ist vor
dessen Beginn festzulegen.

Installiere das signierte Paket gemäß [Abschnitt 16](#16-the-secure-update-of-the-core-of-an-instance).
Die folgenden Beispiele setzen das installierte Paket unter einem privaten
absoluten Pfad voraus. Der übergeordnete Ordner für Instanz und Sicherungen muss
bereits existieren.

```sh
export OIP_INSTANCE="$HOME/OIP-Betrieb"
export OIP_BACKUPS="$HOME/OIP-Sicherungen"
export OIP_TOOLS="$OIP_INSTANCE/current/tools"

python3 "$OIP_TOOLS/oip_local.py" --instance "$OIP_INSTANCE" setup \
  --organization "Testbetrieb" --infrastructure "Testhalle" \
  --site "Prüfstand" --backup-directory "$OIP_BACKUPS" \
  --package-public-key "$TRUSTED_UPDATE_KEY"
python3 "$OIP_TOOLS/oip_local.py" --instance "$OIP_INSTANCE" run --open
```

Wiederhole eine unterbrochene Einrichtung mit denselben Angaben. Der lokale
Einmalcode erscheint am Terminal. **OPC-UA-Browser** zeigt die Quelle
**OPC-UA-Simulation** und ihre Messpunkte. **Diagnose & Ereignisse** zeigt
Verbindung, Datenzustand und letzte Ereignisse. Mit `Ctrl+C` beendet der
Einrichter die Vordergrundinstanz. Nach Neustart verwendet sie dieselbe
Zuordnung und SQLite-Datenbank. Eine neue Browser-Sitzung erhält mit
`oip_local.py --instance "$OIP_INSTANCE" login` einen neuen Einmalcode. Ein
Portkonflikt oder ein Schreibfehler stoppt die Einrichtung oder den Start.
`oip.log` liegt privat im Instanzordner. Ein simulierter Wert bleibt an seiner
Quelle erkennbar. Für eine Testquelle wird ein separater Quelleneintrag
provisioniert; die Simulation bleibt als Testwerkzeug eigenständig.

### Freigegebene OPC-UA-Testquelle

Die Variante wird offline im passenden Standort provisioniert. Sichere die
Instanz vorher und kontrolliere Quell-ID, Geräte-ID, Endpoint, erwartete
Server-Application-URI und Namespace-URI anhand der Betreiberangaben. Der
Core unterstützt im expliziten Testprofil `Basic256Sha256`,
`SignAndEncrypt`, eine freigegebene Client-Zertifikatsidentität und anonymes
OPC-UA-User-Token. Das Gegenüber muss die Clientidentität akzeptieren. Der
Einrichter prüft das Serverzertifikat außerhalb der Verbindung, vergleicht
den vom Verantwortlichen bestätigten Fingerprint und hinterlegt das
freigegebene Zertifikat in `trusted/` im privaten PKI-Ordner. Hat der Core
genau dieses Zertifikat zuvor in `rejected/` abgelegt, verschiebe nach dem
Fingerabdruckvergleich nur diese bestätigte Datei in `trusted/`. Abgelaufene,
ungültige und zur erwarteten Identität unpassende Zertifikate bleiben
gesperrt. Ein Passwortprofil und eine geführte Vertrauensentscheidung im
Browser sind ausstehende Abnahmepunkte.

Füge im gestoppten Profil unter `sources` in `core.json` einen Eintrag nach
diesem Muster hinzu. Die Adresse und URIs sind Beispielwerte. Nutze die
vom Anlagenverantwortlichen bestätigten Werte.

```json
{
  "id": "opcua-test",
  "entity_id": "testanlage",
  "name": "Freigegebener Teststand",
  "endpoint": "opc.tcp://127.0.0.1:4842",
  "opcua": {
    "server_application_uri": "urn:example:server",
    "namespace_uri": "urn:example:measurements",
    "poll_ms": 5000,
    "pki_dir": "/private/tmp/oip-example/approved-pki",
    "certificate_path": "own/certificate.der",
    "private_key_path": "own/private-key.pem",
    "points": [
      {"metric": "temperature", "node_id": "s=Temperature", "value_kind": "float"}
    ]
  }
}
```

Ergänze in `plan.json` unter `sources` die Zuordnung für denselben Teststand.
Führe die bestehende offline Provisionierung unter dem Instanzkonto aus.
Erhalte die bisherigen Einträge und Berechtigungen.

```json
{"source_id":"opcua-test","entity_id":"testanlage","site_id":"local-site","device_id":"testanlage"}
```

```sh
"$OIP_INSTANCE/current/oip-server" --config "$OIP_INSTANCE/core.json" \
  --provision "$OIP_INSTANCE/plan.json"
```

Starte OIP erst nach erfolgreicher Provisionierung. Der Core prüft beim
Start, ob Quellenkonfiguration und Zuordnung übereinstimmen. Bei abgebrochener
Provisionierung prüfe beide Dateien und wiederhole den Befehl. Die
SQLite-Provisionierung ist transaktional. Gib keine Verbindungsdaten aus
dieser Konfiguration in einem Supportpaket weiter.

Pro Quelle werden im Profil höchstens 16 konfigurierte skalare Werte in einem
Batch mit einem Abstand zwischen 5 und 60 Sekunden gelesen. Pro Instanz ist
eine solche Testquelle vorgesehen. Die Zuordnung nutzt Server-Application-URI
und Namespace-URI statt eines dauerhaft gespeicherten NamespaceIndex. Nutze
quellenseitig beschränkte Rechte. Die Abfragen erzeugen Verkehr. Der Core setzt
das lesende Profil auch bei REST und lokaler IPC/MCP durch.

### Sicherung und Wiederherstellung

Stoppe die Instanz vor der Sicherung. Lege die Passphrase getrennt vom
Sicherungsmedium ab. Bewahre das vertrauenswürdige Paket mit genau derselben
Core-Binärdatei auf. Das aktuell geprüfte Verfahren benutzt Schema 8.

```sh
export OIP_FILE="$OIP_BACKUPS/erste-sicherung.oip"
export OIP_CORE="$OIP_INSTANCE/current/oip-server"
export OIP_RESTORE="$HOME/OIP-Wiederherstellungstest"

python3 "$OIP_TOOLS/oip_ops.py" recovery-backup --binary "$OIP_CORE" \
  --config "$OIP_INSTANCE/core.json" --ipc-config "$OIP_INSTANCE/ipc.json" \
  --output "$OIP_FILE"
python3 "$OIP_TOOLS/oip_ops.py" recovery-restore --binary "$OIP_CORE" \
  --source "$OIP_FILE" --restore-dir "$OIP_RESTORE"
python3 "$OIP_TOOLS/oip_ops.py" recovery-start --binary "$OIP_CORE" \
  --restore-dir "$OIP_RESTORE" --port 18871 --web-dir "$OIP_INSTANCE/current/web"
```

Der Restore verwendet einen neuen Ordner. Der wiederhergestellte Core
startet zunächst mit blockierten ausgehenden Verbindungen. Auf ausdrückliche
Freigabe ist für den Test genau ein konfigurierter Loopback-OPC-UA-Port über
`--test-source-port` zulässig. Halte dabei die ursprüngliche Instanz gestoppt.
Der Klon bleibt eine Prüfkopie. Zum Beenden dient `recovery-stop
--restore-dir "$OIP_RESTORE"`. Vergleiche Zuordnungen, Rechte, gespeicherte
Werte und erneut eintreffende Testdaten. Die Integritätsprüfung des Archivs ist
ein eigener Nachweis neben dem Wiederherstellungstest.

Die Sicherung enthält Datenbank und erfasste Historien, Konfiguration,
Quellenzuordnung, lokale Zugangsdaten, Trust und benötigte Schlüssel des
unterstützten Profils. Ein hinterlegter Lizenznachweis wird zusammen mit der
Ausstellerrichtlinie verschlüsselt gesichert. Nach der Wiederherstellung prüft
der Core den Nachweis erneut, einschließlich der aktuellen Zeiträume.
Sicherung und Restore bleiben auch ohne Nachweis möglich.
Private SQLite-Daten, der private PKI-Bestand,
Staging beim Restore sowie Logs auf dem aktiven Mac sind über Dateirechte
geschützt. Für Schutz bei ausgeschaltetem Mac und bei lokalem Restore muss
der Betreiber die Verschlüsselung des betreffenden Volumes prüfen. Ein
Browserprofil hat eigene lokale Einstellungen. Dashboard-Layout und
OPC-UA-Browser-Pins sind im ersten Stand nicht Teil dieser Sicherung.

### Diagnose und Übergabe

Wähle in **Diagnose & Ereignisse** zuerst eine Infrastruktur und öffne
**Supportpaket**. Prüfe die JSON-Vorschau. Die Datei enthält feste technische
Felder und aggregierte Zustände des gewählten Kontexts. Sie wird lokal
gespeichert. Der Betreiber entscheidet über die Weitergabe. Die Betreiberin
oder der Betreiber kann nach der Einweisung Daten und Quellenstatus prüfen,
eine Unterbrechung erkennen und das Paket sichern. Der Einrichter übernimmt
Paketprüfung, Einrichtung, Zertifikatsprüfung, gesicherten Restore und
Updates. Freigabe, Betriebsfenster und Änderungen an Anlage und Netzwerk
verbleiben beim Anlagenverantwortlichen.

| Funktion | Bedienweg | API und MCP | Rolle und Prüfung |
|---|---|---|---|
| Quelle und Messwerte lesen | OPC-UA-Browser und Infrastruktur-Auswahl | `sources`, `observations`, `opcua/nodes`; `oip_sources_read`, `oip_observations_read`, `oip_opcua_nodes_read` | Authentifizierter Quellkontext; fremde Quellen verweigert |
| Supportpaket | Diagnose, Kontext wählen, Vorschau öffnen, JSON speichern | `GET /api/v2/support-package?infrastructure=…`; `oip_support_package_read` | `sources_read` im angegebenen Scope; fehlender und fremder Kontext verweigert |
| Installation, Quellen- und Trust-Provisionierung, Recovery, Offline-Update | Berechtigte lokale Einrichterwerkzeuge | Parität ausstehend | Betreiberkonto, explizite lokale Aktion, getrennte Prüfzustände |

Das geplante Kundenangebot umfasst gewerbliche Nutzungsberechtigung,
einmalige Einrichtung und Einweisung sowie getrennt vereinbarte Wartung und
Unterstützung. Selbstbetreiber können Einrichtung und Betreuung selbst
übernehmen. Private Nutzung bleibt im geplanten Angebot kostenlos. Der
bestehende Quellcode steht unter Apache-2.0, das auch gewerbliche Nutzung
gestattet. Ein gesondertes Angebot für kommerziell lizenzierte Produkte
erfordert eine geklärte Distribution und gültige Nutzungsbedingungen.
Preise, Umfang und Vertragsfristen bleiben offen. Der lokale Datenbetrieb
und der Zugang zu Recovery hängen nicht von einem Supportvertrag ab.

### Nutzungsnachweise einrichten und verwalten

In **Einstellungen → System → Versionen & Updates** zeigt OIP den
gewerblichen Nutzungsnachweis und die Supportberechtigung getrennt an. Der
Nachweis wird lokal für die Installation hinterlegt. OIP zeigt den im
Nachweis genannten Inhaber und die Kennung für die Verwaltung an. Bei
Fragen oder einem fehlenden Nachweis wendet sich der Betreiber an die
zuständige Person für die Installation. Die lokale Datenerfassung sowie
berechtigte Datenzugriffe, Export, Sicherung und Wiederherstellung stehen
unabhängig vom Prüfstatus zur Verfügung.
Ein verifizierter Nachweis ohne Support zeigt bei der Supportberechtigung
**Nicht enthalten**. Fehlt ein überprüfbarer Nachweis, lautet der Status
**Unbestätigt**.

Einrichter beziehen die freigegebene Vertrauensrichtlinie für OIP vom
zuständigen Herausgeber. Sie enthält öffentliche Ed25519-Schlüssel,
zulässige Nachweisarten und gegebenenfalls Rechte mit Obergrenzen.
Für eine neue Richtlinie exportiert der Herausgeber im License Center unter
**Sicherheit → Öffentliche Schlüssel exportieren** das Register
`pruefschluessel.json`. Gleiche die vollständigen SHA-256-Fingerabdrücke der
freigegebenen OIP-Schlüssel über einen getrennt authentifizierten Kanal mit
dem Herausgeber ab. Erstelle daraus lokal die Richtlinie in einer neuen Datei.

```sh
python3 "$OIP_TOOLS/oip_local.py" prepare-license-policy \
  --registry pruefschluessel.json \
  --key-fingerprint SHA256_FINGERABDRUCK \
  --kind FREIGEGEBENE_NACHWEISART > oip-richtlinie-neu.json
"$OIP_INSTANCE/current/oip-server" --check-license-policy < oip-richtlinie-neu.json
```

Wiederhole `--key-fingerprint` und `--kind` für weitere freigegebene Werte.
Für ausdrücklich vereinbarte Rechte kann `--right NAME=OBERGRENZE`
wiederholt werden. Das Register macht einen Schlüssel sichtbar. Erst der
bestätigte Fingerabdruck nimmt ihn in die neue Richtlinie auf. Ein
vorbereiteter Schlüssel kann vor der Aktivierung verteilt werden. Bereits
ausgestellte Nachweise können mit einem weiterhin freigegebenen historischen
Schlüssel geprüft werden. Schlüssel anderer Produkte und als kompromittiert
markierte Schlüssel weist der Befehl ab.

Bei Auslieferung als signiertes Paket kann der Herausgeber die freigegebene
Richtlinie im Manifest mitgeben. Der Einrichter verwendet für `setup` denselben
aus vertrauenswürdiger Quelle bezogenen öffentlichen Paketschlüssel wie für die
Installation. Dazu dient `--package-public-key PFAD`. Die Ersteinrichtung prüft
das installierte Manifest und seine Dateien erneut. Der Core prüft die
freigegebene Richtlinie, bevor die Einrichtung sie speichert. Ein Update oder
ein erneuter Aufruf von `setup` übernimmt keine neuen Lizenzvorgaben in eine
bestehende Einrichtung. Der individuelle Nachweis wird weiterhin separat in OIP
importiert.

Für die separate Provisionierung nutze `oip_local.py setup --license-policy
PFAD` mit der freigegebenen Datei. Gib jede ausdrücklich als gewerblich
vereinbarte Nachweisart separat
mit `--commercial-license-kind ART` an. Ohne diese Zuordnung weist der Core
keine Art als gewerblich aus. Die Einrichtung prüft die Richtlinie vor dem
Schreiben der Konfiguration. Die Vorbereitung startet keine Instanz.

Bei einer bestehenden lokalen Instanz ohne Lizenzrichtlinie stoppt der
Einrichter OIP regulär, erstellt eine verschlüsselte Sicherung und ruft die
Vorschau auf. Sie zeigt das Instanzverzeichnis, die vollständigen Fingerabdrücke
der Herausgeberschlüssel, die Nachweisarten, ihre gewerbliche Zuordnung sowie die
definierten Rechte und Grenzen.

```sh
python3 "$OIP_TOOLS/oip_local.py" --instance "$OIP_INSTANCE" install-license-policy \
  --license-policy oip-richtlinie.json --commercial-license-kind FREIGEGEBENE_ART
```

Für die freigegebene Richtlinie aus dem aktuell installierten signierten Paket
verwende stattdessen `install-license-policy --package-public-key PFAD`. Der
Einrichter muss den vertrauenswürdig bezogenen Paketschlüssel verwenden. In
beiden Fällen prüft der Core die Richtlinie. Nach dem Abgleich mit der Freigabe
des Herausgebers wiederholt der Einrichter den Befehl mit
`--confirm BESTAETIGUNG_AUS_VORSCHAU`. Bei einer geänderten Richtlinie, Zuordnung
oder Konfiguration ist eine neue Vorschau erforderlich. Bereits konfigurierte
und ausgesetzte Lizenzrichtlinien werden über den Schlüsselwechsel verwaltet.

Das Einrichten der ersten Richtlinie ändert nur die beiden Lizenzfelder der
privaten Core-Konfiguration. Der Einrichter startet OIP wieder und prüft den
Lizenzstatus. Der individuelle Nachweis wird separat in der App hinterlegt.
Aktuelle lokale Einrichtungen enthalten bereits die vorgesehene Plattformrolle.
Bei dem älteren lokalen Installationsprofil kann der Einrichter die fehlenden
Lizenzrechte für den ursprünglichen Betreiber `operator` ergänzen. Halte die
Instanz für diesen Schritt an und sichere sie verschlüsselt. Rufe die Vorschau
mit den Werkzeugen der aktualisierten Installation auf.

```sh
python3 "$OIP_TOOLS/oip_local.py" --instance "$OIP_INSTANCE" enable-license-management
```

Prüfe Instanz, Betreiber und die plattformweite Geltung der beiden
Lizenzrechte `license_read` und `license_manage`. Wiederhole den Befehl
mit `--confirm BESTAETIGUNG_AUS_VORSCHAU`. Ändern sich Core-Konfiguration
oder Berechtigungen zwischen den Aufrufen, ist eine neue Vorschau erforderlich.
Der Core ergänzt die Zuweisung und protokolliert sie in einer Transaktion.
Er verwendet dafür die aktuelle Berechtigungslage aus der Datenbank. Bei
entzogener Betreiberrolle oder einem Konflikt mit der bereits vorhandenen
Lizenzrolle verlangt er eine Prüfung der Zugriffsregeln durch den Einrichter.

Dieser Schritt übernimmt die Rolle unmittelbar in die laufzeitrelevante
Datenbank. Die ursprüngliche `plan.json` dient weiterhin als Nachweis der
Ersteinrichtung. Übernimm die bestätigte Rolle und Zuweisung bei einer späteren
vollständigen Provisionierung in den dafür eigens geprüften Plan. Separat
delegierter Lesezugriff benötigt nur `license_read`. Die Nachrüstung wurde
mit dem ursprünglichen Einrichtungswerkzeug und dem aktuellen Core mit
`tests/oip_license_legacy.py --evidence PFAD` erprobt.

Für einen geplanten Schlüsselwechsel bereitet der Einrichter zunächst eine
Richtlinie mit beiden bestätigten Schlüsseln vor. Er stoppt die gewählte
Instanz regulär, erzeugt eine verschlüsselte
[Sicherung](#sicherung-und-wiederherstellung) und ruft die Vorschau auf.

```sh
python3 "$OIP_TOOLS/oip_local.py" --instance "$OIP_INSTANCE" rotate-license-keys \
  --license-policy oip-richtlinie-neu.json
```

Die Vorschau zeigt das Instanzverzeichnis und die vollständigen
Fingerabdrücke der hinzugefügten, beibehaltenen und entfernten Schlüssel.
Nach dem Abgleich mit der Freigabe des Herausgebers führt der Einrichter
denselben Befehl mit `--confirm BESTAETIGUNG_AUS_VORSCHAU` aus.
Eine Änderung an Konfiguration oder Richtliniendatei erfordert eine neue
Vorschau. Der Befehl übernimmt ausschließlich Schlüsseländerungen in der
privaten Core-Konfiguration der gewählten Instanz. Nachweisarten, ihre
gewerbliche Zuordnung und vereinbarte Rechte bleiben erhalten.

Wenn ein signiertes OIP-Update die bestätigten Ersatzschlüssel enthält,
kann der Einrichter nach der Installation stattdessen
`rotate-license-keys --package-public-key PFAD` verwenden. Verwende den
bereits vertrauenswürdig bezogenen öffentlichen Paketschlüssel. Von der
Vorschau bis zur Bestätigung prüft der Befehl bei jedem Aufruf die Signatur
und die Dateien des aktuell installierten Pakets erneut. Das Paket muss
dieselben Nachweisarten, Rechte und gewerblichen Zuordnungen wie die
Installation ausweisen. Der Schlüsselwechsel bleibt ein separat
bestätigter Wartungsschritt nach dem Update.

Starte diese Instanz und prüfe den bestehenden Nachweis. Hinterlege und
prüfe anschließend den neu ausgestellten Nachweis in der App. Entferne den
alten Schlüssel in einem zweiten bestätigten Wechsel, sobald der neue
Nachweis geprüft ist. Bei einem kompromittierten Schlüssel prüft der
Einrichter die korrigierte Richtlinie mit dem Herausgeber und entfernt den
Schlüssel auf jeder betroffenen Installation. Die lokale Prüfung verwendet
die installierte Richtlinie. Ohne deren Aktualisierung erfährt die Instanz
nichts von einer Änderung im License Center. Nach dem Neustart werden mit
einem entfernten Schlüssel ausgestellte Nachweise als ungültig angezeigt.

Ist der einzige vertrauenswürdige Schlüssel kompromittiert und liegt noch
kein freigegebener Ersatz vor, verwende im selben Wartungsablauf
`rotate-license-keys --suspend-trust` anstelle von
`rotate-license-keys --license-policy PFAD`. Prüfe die angezeigten
Fingerabdrücke und bestätige die Änderung mit `--confirm`. Nach dem Neustart
zeigt OIP **Lizenzprüfung ausgesetzt**. Nutzungs- und Supportberechtigung sind
unbestätigt. Die gespeicherte Nachweisdatei bleibt verfügbar und ein neuer
Nachweis kann erst nach Freigabe eines Ersatzschlüssels hinterlegt werden.
Für die Wiederaufnahme verwende `rotate-license-keys --license-policy PFAD`
mit der bestätigten Ersatzrichtlinie. Die Ersteinrichtung und signierte
Installationspakete mit Lizenzrichtlinie benötigen weiterhin mindestens
einen vertrauenswürdigen Schlüssel.

Eine Wiederherstellung aus einer älteren Sicherung verwendet deren
Richtlinie. Vergleiche die Schlüssel in der isolierten Prüfkopie vor einer
erneuten betrieblichen Nutzung mit der aktuellen Freigabe des Herausgebers.
Die Datenerfassung und die berechtigten Datenzugriffe bleiben unabhängig
vom Lizenzstatus verfügbar.

Nach Einweisung kann ein Lizenzverwalter den erhaltenen JSON-Nachweis in
der App als Datei auswählen und prüfen. Die angezeigten Berechtigungen
und die Identität können vor der ausdrücklichen Übernahme kontrolliert werden. Die Bestätigung gilt höchstens
fünf Minuten für dieselbe Identität und denselben vorherigen Dateistand.
Sie ist einmalig einlösbar und verfällt bei einem Core-Neustart oder wenn
ein anderer Nachweis gespeichert wurde. Die Datei liegt im geschützten
Instanzverzeichnis neben der Datenbank und wird bei jedem Statusabruf
geprüft. Der Core vergleicht Gültigkeitszeiten mit der lokalen Uhr.
Bewahre den erhaltenen signierten Nachweis separat auf. Nach einer
isolierten Wartungswiederherstellung kann ein berechtigter Betreiber den
Nachweis bei Bedarf erneut übernehmen. Der Nachweis enthält keine
Recovery-Geheimnisse und erteilt keine Verbindungsfreigabe.

| Funktion | UI | REST · MCP | Rolle und Nachweis |
|---|---|---|---|
| Status ansehen | Versionen & Updates | `GET /api/v2/license` · `oip_license_status_read` | Plattformweit `license_read`. Ohne Berechtigung bleiben auch Namen und Kennungen verborgen. |
| Nachweis prüfen | Lizenznachweis hinterlegen → Nachweis prüfen | `POST /api/v2/license/preview` · `oip_license_proof_preview` | Plattformweit `license_read` und `license_manage`. Die Signatur, der Geltungsbereich und die installierte Ausstelleridentität werden geprüft. Fehlerhafte Nachweise werden abgewiesen. |
| Geprüften Nachweis übernehmen | Nachweis übernehmen | `POST /api/v2/license/apply` · `oip_license_proof_apply` | Gleiche Rolle. Einmalige, zur Vorschau gehörige Bestätigung erforderlich. Für MCP-Verwaltung ist ein explizit so berechtigter lokaler IPC-Client nötig. |
| Herausgeberrichtlinie vorbereiten und hinterlegen | Einrichter bei der Provisionierung | `prepare-license-policy`, `--check-license-policy`, geschützte lokale Core-Konfiguration | Zuständiger lokaler Einrichter. Auswahl über separat bestätigte Fingerabdrücke. Der signierte Nachweis kann die Ausstellerkonfiguration nicht verändern. |
| Lizenzverwaltung im älteren lokalen Profil nachrüsten | Wartung der lokalen Installation | `enable-license-management` mit gestopptem Core. Der neue Berechtigungsstand gilt anschließend auch über App, REST und MCP. | Besitzer des privaten Instanzverzeichnisses. Vorschau und Bestätigung für den ursprünglichen, weiterhin berechtigten lokalen Betreiber. |
| Erste Lizenzrichtlinie hinterlegen, Herausgeberschlüssel wechseln oder Lizenzprüfung aussetzen | Wartung der lokalen Installation | `install-license-policy` oder `rotate-license-keys` an der gestoppten Instanz. Der daraus folgende Lizenzstatus erscheint in der App, REST und MCP. | Besitzer des privaten Instanzverzeichnisses. Vorschau und ausdrückliche Bestätigung für das gewählte Verzeichnis, den Konfigurationsstand und die gewählte Änderung. |

Die technische Ausgabe von Nachweisen erfolgt über das separate License
Center. Wähle dort das Produkt OIP und gib die signierte JSON-Datei
unverändert weiter. Die Kundeninstallation prüft sie offline und verwendet
dafür ausschließlich öffentliche Schlüssel. Der OIP-Core prüft das
Lizenzformat v1 selbst und verwendet Ed25519 aus einer Rust-Bibliothek.
Verwahre den privaten Schlüssel beim Aussteller mit Zugriffsschutz und
gesicherter Wiederherstellung.
Halte Lizenzkennung, Vertragsgrundlage und die unabhängig vereinbarten
Zeiträume für Nutzung und Support beim Herausgeber fest. Das Format verlangt
einen Nutzungszeitraum. Eine Supportvereinbarung ist optional. Bei Ersatz
müssen alle weiterhin vereinbarten Berechtigungen im neuen Nachweis stehen.
Der Code veröffentlicht keine Vertragsbedingungen. Eine geänderte
Distribution erfordert die geklärte Rechtekette und ausdrückliche Freigabe
der endgültigen Bedingungen. Bereits unter Apache-2.0 erhaltene
Nutzungsrechte bleiben bestehen.

Die technische Prüfung ist mit `tests/oip_license_policy.py`, `tests/oip_license_issue.py` und
`tests/oip_license_e2e.py --evidence PFAD` reproduzierbar. Mit `--browser`
und eingerichtetem Playwright prüft der Test zusätzlich den Dateidialog der
gebauten Weboberfläche. Der Test
startet eine frische, isolierte Instanz mit synthetischen Nachweisen. Dazu
gehören im PHP-Aussteller erzeugte OIP- und ODP-Testdateien. Er prüft REST,
MCP, die Produkt- und Rollengrenzen und den durchgehenden Datenbetrieb bei
fehlendem, beschädigtem oder abgelaufenem Nachweis.

Die Paketprobe in `tests/oip_update.py` verwendet den gebauten Core,
die Weboberfläche und den Simulator. Die Paketprüfung verlangt den Lizenztext
und die Hinweise zu Drittbestandteilen als signierte Manifest-Einträge.
Der Test erzeugt die öffentliche Herausgeberrichtlinie aus einem
Schlüsselregister mit bestätigten Fingerabdrücken und
prüft einen ausgestellten Nachweis über die Operator-Sitzung. Ein
Nachweis, der mit dem Paket-Signierschlüssel ausgestellt wurde, wird
abgelehnt. Danach prüft der Test, ob Nachweis, Vertrauen und Rolle nach
dem signierten Offline-Update weiterhin verfügbar sind. Beide Schlüssel
der Paketprobe werden eigens für die isolierte Prüfung erzeugt.

---

## 0. What the instance consists of

| Item | Meaning |
|---|---|
| `--config FILE` | the Core configuration: the database path, the HTTP port, the sources and the web directory |
| `--ipc-config FILE` | the protected local IPC configuration: the Unix socket and the credentials of the local clients |
| `--state-dir DIR` | the state of the tool: the pid file, the log file and the backups |
| the database | the SQLite data store of the instance; the Core writes its schema with STRICT tables and refuses a file that anybody but the owner can read |

Two files must be owner-private (`0600`) and one directory (`0700`):

* the IPC configuration — the Core reads it as a protected file;
* every credential file of the IPC configuration — 32 random bytes, never logged;
* the directory that holds the Unix socket — macOS authorizes the socket through this directory.

The tool creates a missing credential and tightens the permissions of the IPC
configuration. It never prints a credential.

### 0.1 The files of an instance

The procedures of this runbook use three paths. An instance of the operator
lives in the personal installation; a disposable instance of a rehearsal lives
in a directory of its own. The three paths are named once:

```sh
# the instance of the operator (the paths of the personal installation)
export OIP_HOME="$HOME/Library/Application Support/OIP/real"
export CORE_CONFIG="$OIP_HOME/core.json"      # the configuration of the Core
export IPC_CONFIG="$OIP_HOME/ipc.json"        # the protected local IPC
export STATE="$OIP_HOME/state"                # the pid, the log and the backups

# a disposable instance (a rehearsal, a test)
export OIP_HOME="/private/tmp/oip-instance"
export CORE_CONFIG="$OIP_HOME/core.json"
export IPC_CONFIG="$OIP_HOME/ipc.json"
export STATE="$OIP_HOME/state"
```

The directory of the instance is owner-private (`0700`), the two
configurations are `0600`, and the data store of the instance is the SQLite
file `core.sqlite` beside them. The Core refuses a data store that anybody but
the owner can read.

**The tool refuses the personal installation.** Every operation of
`tools/oip_ops.py` whose target resolves into `~/Library/Application Support/OIP`,
`~/.local/share/OIP`, `/etc/oip` or `/var/lib/oip` is refused with
`refusing to … the personal installation`. The activation of the release on
that store is the operator's own step (§11) — the loop never performs it.

## 1. Provision the data store (once, offline)

The Core creates its data store with the hierarchy and the enabled principals
of a plan. This is a separate operator step and never runs while an instance
is running.

```sh
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" \
    provision-plan --plan examples/multi-infrastructure-plan.json
```

The sources of the plan must match the sources of the configuration. The
example plan carries an OPC UA source; an instance without that source uses a
plan without it.

The plan names the principals. The IPC configuration must bind to a principal
that the plan enables, otherwise the Core refuses to start with
`IPC binding requires a provisioned enabled principal or explicit legacy mode`.

### 1.1 The parts of a plan

A plan is the hierarchy of the instance and the permissions of its principals.
The example `examples/multi-infrastructure-plan.json` carries two
organizations; the smallest useful plan for an operator looks like this:

```json
{
  "organizations": [
    { "id": "org-1", "name": "Meine Organisation" }
  ],
  "infrastructures": [
    { "id": "infra-1", "organization_id": "org-1", "name": "Meine Infrastruktur" }
  ],
  "sites": [
    { "id": "site-1", "infrastructure_id": "infra-1", "name": "Mein Standort" }
  ],
  "sources": [
    { "source_id": "source-1", "site_id": "site-1", "device_id": "device-1",
      "entity_id": "M-01" }
  ],
  "principals": [
    { "id": "operator", "name": "operator", "enabled": true }
  ],
  "roles": [
    { "id": "reader", "name": "Read only capabilities",
      "permissions": ["core_read", "sources_read", "devices_read", "telemetry_read",
                      "events_read", "opcua_read", "hierarchy_read"] }
  ],
  "bindings": [
    { "principal_id": "operator", "role_id": "reader",
      "scope": { "kind": "organization", "id": "org-1" } }
  ],
  "services": [
    { "id": "svc-1", "name": "OPC-UA des Standorts", "site_id": "site-1",
      "device_id": "device-1", "kind": "opcua",
      "endpoint": "opc.tcp://127.0.0.1:4840", "port": 4840,
      "state": "running" }
  ],
  "legacy_single_infrastructure": false
}
```

* The **services** of the plan are the services the operator **declares** for
  the sites of the instance. The Core measures no service: every record of the
  registry carries the provenance `declared`, and a service of a site that the
  plan does not name is refused. The section is optional — a plan without
  services is a plan without a service registry.
* The **sources** of the plan must exactly match the sources of the
  configuration of the instance — the same identifiers. The Core refuses the
  start otherwise with `runtime sources must exactly match provisioned
  registry`.
* A **principal** may be bound to a scope: `platform`, `organization`,
  `infrastructure`, `site` or `source`. The scope of a binding decides what the
  principal sees; a role of an organization does not see the sources of the
  next organization.
* The **permissions** of a role decide what the principal may do. The read
  permissions are `core_read`, `sources_read`, `devices_read`, `telemetry_read`,
  `events_read`, `opcua_read` and `hierarchy_read`. The writing permissions
  (`settings_write`, `inventory_manage`) are separate and are bound with their
  own role.
* `legacy_single_infrastructure` stays `false` for a multi-infrastructure
  instance. It is the only way to the legacy mode, in which the instance
  serves the local operator access without a bearer.
* The **device** of a source placement (`device_id`) becomes the device of the
  inventory of the instance. The registration of a device with a connection of
  its own is a separate, later step (§7 and the onboarding of the surface).

### 1.2 The extension of the registry of an instance

The operator adds infrastructure by **extending** the plan and provisioning it
again. The registry of an instance is stable: a plan that drops an organization,
an infrastructure, a site, a source or a principal is **refused** with
`hierarchy/provisioning validation failed`, and the registry of the instance
stays as it was.

```sh
# 1. the instance is stopped: the provisioning is an offline operation
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" stop

# 2. the plan is extended (here by a source) and the configuration with it:
#    the sources of the plan and the sources of the configuration must be the
#    same identifiers.
#    ... edit "$PLAN" and "$CORE_CONFIG" ...

# 3. the instance is provisioned again with the extended plan
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" \
    provision-plan --plan "$PLAN"

# 4. the instance serves the extended registry
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" \
    --ipc-config "$IPC_CONFIG" --binary target/release/oip-server start
```

The answer of the Core names the schema, the number of organizations and the
number of sources of the registry. The identities of the instance stay stable
across the extension: a principal may be **disabled** by the plan, never
removed.

Measured with the release binary (`tests/oip_extend_registry.py`,
`docs/evidence/oip-extend-registry/extend-registry.json`): an instance with four
sources is extended by a fifth, the four sources survive, the fifth is
registered and collects (the receipt of the run names its observations), and the plan that drops the fifth
source is refused while the registry keeps its five sources.

## 2. Start, status, stop, restart

```sh
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" \
    --ipc-config "$IPC_CONFIG" --binary target/release/oip-server start
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" status
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" \
    --ipc-config "$IPC_CONFIG" --binary target/release/oip-server restart
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" stop
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" log --lines 50
```

* `start` launches the daemon in its own session, writes the pid file and
  waits until the HTTP port answers. It fails when the Core does not answer
  within 30 seconds.
* `stop` sends `SIGTERM` and waits for the clean shutdown of the Core. It
  never forces a signal: an instance that does not stop within 30 seconds is
  reported as such.
* `restart` is `stop` followed by `start`.
* `status` reports the pid, the port, the port state, the database, its
  schema version and the log file.
* `log` prints the last lines of the log of the instance — the last 50 by
  default, `--lines 0` prints all of them. The operator reads the log of his
  instance without an editor and without OpenCode.

The daemon always runs with its protected IPC configuration; the tool refuses
a `start` without it.

## 3. The log

The Core writes JSON lines to stderr. The tool redirects them into
`$STATE/oip.log`. The daemon uses the filter `warn,oip_server=info,rmcp=off`,
so a more specific `RUST_LOG` cannot lift the redaction of the SDK traces.

```sh
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" log --lines 50
tail -f "$STATE/oip.log" | python3 -m json.tool --json-lines
```

A clean shutdown ends with a line that names the state of the shutdown:

```json
{"clean":true,"uncommitted":0,"adapter_failures":0,"persistence_thread_joined":true,"http_drained":true,"http_forced_close":false}
```

`uncommitted` is the number of observations that were not persisted when the
Core stopped. It must be `0` for a clean shutdown.

## 4. Backup

```sh
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" backup
```

The backup is a consistent snapshot of the running instance (the SQLite backup
API), it is verified with an integrity check, it is a single file and it stays
owner-private. The default target is
`$STATE/backups/<timestamp>.sqlite`; `--output FILE` names another target.

The Core writes its schema with STRICT tables. The SQLite of a system Python
can be older than the release that knows STRICT, so the tool uses the SQLite
of the machine (`/usr/bin/sqlite3`) when it is available.

## 5. Restore

```sh
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" \
    restore --source "$STATE/backups/20261108T143554Z.sqlite"
```

A restore is refused while the instance is running. The source is verified
with an integrity check before it replaces the database, and the restored file
is owner-private, because the Core refuses a database that anybody but the
owner can read. The replacement is atomic: the copy is written next to the
database and renamed over it.

After a restore, start the instance again and check the log.

## 6. Upgrade and rollback

An upgrade of a local instance is a handover of the data store to the new
binary. It is rehearsed by `tests/oip_upgrade_rollback.py` against a protected
historical binary and the current release binary:

```sh
python3 tests/oip_upgrade_rollback.py --evidence target/oip-upgrade-rollback
```

The rehearsal proves that the release binary takes over the data store of the
previous release, that the schema is migrated and that the data of the store
survives, and that the backup taken before the upgrade restores the previous
state, which the previous release adopts again.

The measured result: the historical binary provisions the store at schema 3
with two organizations; the release binary serves the same store, migrates it
to schema 7 and keeps the organizations; the restore brings the schema back to
3 and the historical binary adopts the restored store.

Three rules of the handover were found while proving it and are part of the
procedure:

* **The runtime sources must exactly match the provisioned registry.** A
  configuration whose sources differ from the provisioned ones is refused with
  `runtime sources must exactly match provisioned registry`.
* **The data store must be owner-private.** A store that anybody but the owner
  can read is refused with `database/sidecar must be owned by operator with
  private permissions`.
* **The configuration of an instance is not portable between releases.** A
  historical binary refuses the fields of a newer configuration and vice
  versa. The upgrade therefore keeps the configuration of the era of the
  instance until the instance has been migrated.

## 7. The archive of a device

The archive of a device is an **offline operation** of the Core. The managed session refuses it
with `OFFLINE_ARCHIVE_REQUIRED` ("Archive remains an explicit offline operation"), because an
archive changes the registry while the Core is serving. The supported path applies the archive
with the Core stopped:

```sh
# 1. the device is registered and known to the operator
# 2. the Core is stopped
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" stop

# 3. the archive is written as the offline plan of the Core
cat > "$STATE/archive.json" <<'JSON'
{
  "principal": "reader-org-a",
  "changes": [
    { "operation": "archive", "id": "<device-id>", "expected_revision": 1 }
  ]
}
JSON

# 4. the plan is applied with the explicit flag of the Core
oip-server --config "$CORE_CONFIG" --inventory-plan "$STATE/archive.json" --inventory-apply

# 5. the Core starts again
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" \
    --ipc-config "$IPC_CONFIG" --binary target/release/oip-server start
```

The Core answers with the plan it applied: `{"applied": true, "apply_mode":
"offline_requires_restart"}` and the action `{"outcome": "archive"}`. The revision of the device
is the guard of the write, exactly as in the online update.

**The precondition of every offline inventory change.** The runtime migration of the Core must
have run before: the instance was started at least once. A store that was only provisioned and
never served has no inventory yet, and the Core refuses the change with
`INVENTORY_MIGRATION_REQUIRED; run controlled runtime migration separately` — it does not migrate
the registry of a store that it is not serving.

**What the archive means.** The record of the device, its identity and its metadata stay intact —
the archive is not a deletion — and the device collects no measurements anymore. An archived device
is not part of the active inventory: the read only shows it when the archived ones are asked for
(`include_archived=true`). The measurements of the device that were collected before the archive
remain in the history.

The rehearsal is `tests/oip_offline_archive.py`; its receipt is
`docs/evidence/oip-offline-archive/offline-archive.json`. It proves the refusal of the managed
session, the application of the offline plan, the hiding of the archived device from the active
inventory and the survival of its identity and its metadata.

### 7.1 The offline registration of a device

The **registration** of a device is possible in two ways: through the surface of the application
(the administration of the device, with the managed session) and **offline** with the same plan
that carries the archive. The offline registration is the path for a device that the operator
wants in the registry before the instance serves:

```sh
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" stop

cat > "$STATE/register.json" <<'JSON'
{
  "principal": "reader-org-a",
  "changes": [
    { "operation": "register",
      "device": { "id": "<device-id>", "display_name": "<name>",
                   "device_type": "server", "site_id": "<site-id>", "metadata": {} } }
  ]
}
JSON

oip-server --config "$CORE_CONFIG" --inventory-plan "$STATE/register.json" --inventory-apply
```

The answer names the plan it applied (`"applied": true`,
`"apply_mode": "offline_requires_restart"`) and the action (`{"outcome": "register"}`). The
registered device belongs to the site of the plan and inherits the scope of the principal that
performed the change: a device of a site of another organization is refused with
`invalid inventory or authorization; no changes applied` — the generic refusal, without the name
of the site or of the device.

Measured with the release binary: the registration of a device at the site of the own
organization is applied (`{"outcome": "create"}`), the registration at the site of the other
organization is refused.

The rehearsal of the archive proves the plan, the flag and the guard of the revision on the same
path; the registration is the same plan with the operation `register`.

## 8. The personal installation is never touched

The personal installation of the operator lives in
`~/Library/Application Support/OIP/real/core.sqlite`. The tool refuses every
operation whose target resolves into the personal installation, a system
directory or the per-user data directory of OIP — also when the path is
reached through a relative path or a symlink:

```
error: refusing to back up the personal installation: /Users/<operator>/Library/Application Support/OIP/real/core.sqlite
error: refusing to restore the personal installation: ...
error: refusing to start against the personal installation: ...
```

The activation of the real installation is an operator decision with its own
backup procedure (see §11 and `docs/OIP_RELEASE_PROGRESS.md`, N4). This
runbook does not perform it.

## 9. The macOS application bundle

### 9.0 The build of the release

The Core of the release is built with **one** command. The command matters:
the feature resolution of the workspace is part of the binary, so a build of
a single package produces a **different** binary than a build of the
workspace. The release is the workspace:

```sh
cargo build --locked --release --workspace \
    --bin oip-server --example mcp_probe
# -> target/release/oip-server
# -> target/release/examples/mcp_probe
```

The same command is used by the acceptance gate, by the manifest of the
release and by the rehearsal of the reproducible builds, so the binary that
the gate proves is the binary that the manifest names. The rehearsal
(`tests/oip_reproducible_build.py`) builds the Core twice and compares the
digests: the same command on the same source produces the **same bytes**.

The desktop client is a Flutter application bundle. It is built reproducibly
from the same Dart code as the web release:

```sh
cd apps/flutter
flutter build macos --release \
    --dart-define=OIP_API_URL=http://127.0.0.1:<port-of-the-instance>
# -> apps/flutter/build/macos/Build/Products/Release/oip_dashboard.app
```

The bundle needs the address of the instance as a compile-time definition
(`OIP_API_URL`). Without it the bundle starts and asks the Core for the
authorized projection of the principal, the Core refuses it with 403, and the
bundle shows the operator login of the approved shell. That is the designed
behaviour of the real mode: the bundle never shows data of a session it does
not have.

**The port of the bundle and the port of the instance.** The address is baked
into the bundle, so the two must agree. The managed Mac OTA release targets
`127.0.0.1:18858`; the direct macOS app maintains an SSH forward from that
local port to the Pi Core at `127.0.0.1:18808`. For a different self-hosted
instance, build the bundle with that instance's reachable URL in `OIP_API_URL`.

The rehearsal `tests/oip_macos_app.py` proves the bundle **of the release**:
it builds it for the documented port, puts a witness on that port, and shows
that the bundle asks the Core, is refused with `403 PERMISSION_DENIED` — the
refusal of the **session**, and the receipt names the code of every refusal —
obtains **no** data, terminates without an orphan and starts again
(`docs/evidence/oip-macos-app/macos-app.json`).

**What the operator does with the bundle.**

```sh
BUNDLE="apps/flutter/build/macos/Build/Products/Release/oip_dashboard.app"

# 1. the one-time code of the operator session
target/release/oip-server --browser-login \
    --ipc-socket "$STATE/s" --ipc-credential "$STATE/platform.credential"

# 2. the bundle
open "$BUNDLE"
# the code of the session is entered in the window of the bundle; the window
# asks for it and the Core refuses every read until the session exists

# 3. the bundle is stopped with the signal of the operator
pkill -TERM -f oip_dashboard.app
```

The window of the bundle is placed by the system; the bundle reports the
placement in its log (`OIP-WINDOW …`). When the frame of the storyboard
touches no visible screen — it belongs to the screen the bundle was generated
for — the runner places the window in the centre of the main screen.

**The first start of a bundle that the operator did not build.** A bundle that
the operator built on the machine starts as it is. A bundle that the operator
**received** carries the quarantine attribute of the download, and macOS then
refuses the first start with the notice that the application is damaged. The
operator confirms it once (right click on the bundle → `Öffnen`) or starts the
executable of the bundle directly:

```sh
"$BUNDLE/Contents/MacOS/oip_dashboard"
```

A signed and notarized release removes the question entirely. **Signing is the
operator's decision** — the artefacts that may be signed are named with their
digests in `docs/release/oip-release-manifest.json`.

**The launch agent is not part of this runbook.** Installing the application
as a launch agent is a system service and needs an explicit operator
authorization. The procedure above keeps the instance under the control of the
operator, without OpenCode, with a reproducible start, stop, restart, backup
and restore.

### 9.1 The local installation

The operator installs the application as a **copy of the bundle of the release**
in the directory of the installation. The copy is the artefact that must work —
not the bundle in the directory of the build.

```sh
# 1. the bundle of the release (the artefact with the digest of the manifest)
BUNDLE="apps/flutter/build/macos/Build/Products/Release/oip_dashboard.app"

# 2. the copy into the directory of the installation
cp -R "$BUNDLE" /Applications/

# 3. the first start of the installed copy
/Applications/oip_dashboard.app/Contents/MacOS/oip_dashboard
```

The copy is byte-identical to the bundle of the release: the digest over the
tree of the bundle is `e5cb5292…` (`docs/release/oip-release-manifest.json`).
The rehearsal of the installation (`tests/oip_macos_install.py`,
`docs/evidence/oip-macos-install/macos-install.json`) copies the bundle into an
installation directory and proves that the **installed copy** starts, reaches
the Core, is refused without a session, obtains **no** data, shows the approved
shell with the operator login, terminates on the operator's signal without
leaving an orphan behind and starts again from the installation directory. The
rehearsal installs into a directory of the temporary tree — **never** into
`/Applications`: the installation of the release there is the step of the
operator.

The identifier of the installed application is `org.openindustrial.oipDashboard`
and its version is `0.3.0`; a copy with another identifier is not this
release. A copy that the operator **received** carries the quarantine
attribute of the download; macOS then refuses the first start until the
operator confirms it once (right click → `Öffnen`).

## 10. The daemon of a historical release

A local instance of an older release is a daemon of its own era. Its protected
local IPC binds the clients to a **provisioned, enabled principal** of the era
(`docs/architecture/oip-008-identity-authorization.md`); the actor with
permissions and a source scope is the shape of OIP-007 and the era refuses it
with `invalid protected local IPC configuration/path`. A daemon that is bound
to a principal that does not exist in its store refuses the start with
`IPC binding requires a provisioned enabled principal or explicit legacy mode`.

The handover of a *running* historical instance is rehearsed by
`tests/oip_historical_daemon.py`: the era starts, collects, answers the
authorized reads of its principals, the release binary takes over the same
store, and the historical binary serves the restored store again.

## 11. The activation of the release on the personal installation

This section is the procedure for the **operator**. The loop never performs
it: the tool refuses every operation whose target is the personal
installation, and the decision with its backup belongs to the operator.

**What is measured.** The rehearsal `tests/oip_activation_dry_run.py` copies
the store of the operator into a disposable directory and lets the release
binary migrate the **copy**
(`docs/evidence/oip-activation-dry-run/activation-dry-run.json`): the
migration of the schema 6 to the schema 7 is **accepted**, the inventory of
the instance survives it unchanged (the organizations, the infrastructures,
the sites, the principals, the roles, the bindings and the devices), the
integrity check answers `ok` and the daemon serves the migrated copy. The
personal installation itself was not touched: the same sha256, still schema 6.

**The procedure.**

```sh
# 1. the fresh backup of the personal store. The tool refuses the personal
#    installation, so the operator copies the store with the backup of
#    SQLite itself. The copy is owner-private.
STORE="$HOME/Library/Application Support/OIP/real/core.sqlite"
BACKUP="$HOME/Library/Application Support/OIP/real/backups/core-$(date -u +%Y%m%dT%H%M%SZ).sqlite"
mkdir -p "$(dirname "$BACKUP")" && chmod 700 "$(dirname "$BACKUP")"
/usr/bin/sqlite3 -readonly "$STORE" ".backup '$BACKUP'"
chmod 600 "$BACKUP"
shasum -a 256 "$STORE" "$BACKUP"

# 2. the dry run: the release binary migrates a COPY of the store. The
#    configuration of the instance names the sources of the registry and the
#    local IPC binds to a principal that the store carries and that is
#    enabled — the Core refuses the start otherwise.
cp "$STORE" "$STORE.dry-run" && chmod 600 "$STORE.dry-run"
#    ... run the release binary against the copy, then check:
/usr/bin/sqlite3 -readonly "$STORE.dry-run" "pragma user_version; pragma integrity_check;"

# 3. the activation itself, with the same configuration, now against the
#    real store. The operator stops the instance first.
/usr/bin/sqlite3 -readonly "$STORE" "pragma user_version;"
target/release/oip-server --config "$HOME/Library/Application Support/OIP/real/core.json"

# 4. the check after the activation
/usr/bin/sqlite3 -readonly "$STORE" "pragma user_version; pragma integrity_check;"
shasum -a 256 "$STORE"   # the store changed: the migration wrote to it
```

**The rollback.** The backup of the first step restores the previous state:
stop the instance, copy the backup over the store, and start the previous
release again. The rehearsal `tests/oip_upgrade_rollback.py` proves exactly
that path with a protected historical binary
(`docs/evidence/oip-upgrade-rollback/upgrade-rollback.json`).

**Two properties of the rehearsal that the procedure keeps.** The copy declares
the sources of the instance with closed loopback ports, so no private endpoint
is contacted; and the local IPC binds to the enabled principal of the store,
because a principal that the store does not carry is refused by the Core.

## 12. The offline change of a setting of the instance

The Core has **no** HTTP and no MCP write path for the settings: the change
is an offline operation of the local operator with the exclusive local CLI. The
settings navigation of the application says so ("Kein Browser-Save"). The
procedure is measured by `tests/oip_settings_offline.py`
(`docs/evidence/oip-settings-offline/settings-offline.json`).

```sh
# 1. the instance is stopped: the change is an offline operation
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" stop

# 2. the change is written as a file and handed to the binary
cat > "$STATE/setting.json" <<'JSON'
{
  "principal": "reader-org-a",
  "scope": { "kind": "platform" },
  "key": "instance_name",
  "value": { "type": "text", "value": "Meine Instanz" },
  "expected_revision": 0
}
JSON
target/release/oip-server --config "$CORE_CONFIG" --settings-change "$STATE/setting.json"

# 3. the instance starts again; the value is effective from this start on
tools/oip_ops.py --state-dir "$STATE" --config "$CORE_CONFIG" \
    --ipc-config "$IPC_CONFIG" --binary target/release/oip-server start
```

**What the Core enforces.** The `principal` must carry the permission
`settings_write` in the scope of the change — a principal without it is
refused. The `scope` decides where the value lives: the metadata of the
instance (`instance_name`, `instance_description`) belongs to the platform
scope, `history_page_size` is inherited and may live in every scope. The
`expected_revision` is the guard of the write: the revision of the value that
the operator has seen; a wrong revision is refused. A value outside the
validation of the key is refused (`history_page_size` accepts 4..100).

The answer of the Core names the record, its revision and the status of the
application. The value becomes effective at the **next validated start** of
the Core (`apply_status: active_startup_snapshot`) — the change itself is
never applied to a running instance.

## 12.1 The measurement of the delivery on the machine of the operator

The first paint of the web release is bound by the **transfer** of the delivery. The baseline of
the release was measured on the machine of the development loop, and the loopback of that machine
is throttled — one connection of it delivers a rate of a few hundred KiB/s, while the same
machine delivers the same data over a Unix socket at a rate that is orders of magnitude higher. **The operator measures the delivery on their own machine:**

```sh
python3 tools/oip_measure_delivery.py
```

The command reports the size of the delivery (the web release that the Core serves), the rate of
the path of this machine, the rate of the machine itself and the time the delivery needs at both
rates. The delivery of the release is about 24 MB over a few dozen files; the browser fetches the
larger half of it before the first paint — three variants of the renderer are shipped and the
browser uses one. The command names the exact numbers of the machine of the operator.

The decision about a smaller delivery, a compressed asset or a local cache of the release is the
operator's and is named in `docs/OIP_RELEASE_LEDGER.md`; the measurement above is what that
decision needs.

## 13. How a third party verifies the release

The whole handoff is checked with **one command**. It needs the checkout of
the release and the build tree of the release (the artefacts live in
`target/` and in `apps/flutter/build/`):

```sh
python3 tools/oip_verify_release.py
```

The command proves:

1. the **manifest** of the release verifies — every digest of every artefact
   and of every receipt is recomputed and compared with the written manifest;
2. **every receipt is fresh** — no receipt of the release names a revision
   that predates the last change of the product it covers;
3. the **record is intact** — every receipt that the ledger and the state file
   cite exists and is tracked by git, and every receipt of the release is
   cited by one of them;
4. the **acceptance passed** — the receipt of the canonical gate says PASS
   with its phases, its browser findings, its Flutter tests, its captures and
   its accessibility numbers;
5. the **safety boundaries held** — no receipt claims that the schema 7 was
   activated on the personal store of the operator.

The verdict of the command is **`OIP_PRODUCTION_NOT_READY`** while the gates
that need the operator are open (G5, G10, G12). The verification is **not** a
production acceptance: the acceptance of the operator and the scope of the
production security are the operator's. The command never claims the visual
acceptance of the operator — a visual acceptance that is not pending is a
problem of the verification.

The receipt of the verification is `docs/evidence/oip-release-verification/release-verification.json`;
the negative control of the verifier is `tests/oip_verify_release_test.py` and
proves that it can fail.

## 13.1 How a third party re-measures the evidence of the release

The command above **verifies** the receipts that the checkout carries. A third party who wants
to **measure** them again — on their own machine, after a change of the product — runs the
rehearsals of the release:

```sh
python3 tools/oip_refresh_evidence.py
```

The command runs every rehearsal of the release in the order of the release, and it publishes
every receipt into its place in the checkout (`docs/evidence/`). The tree must be **clean**: a
receipt that is measured on a dirty tree would not say what it covers. `--list` names the
rehearsals and the receipts they publish, `--only NAME` runs one of them and `--skip NAME`
leaves one out.

Two facts about the runtime:

* the rehearsals measure the **real** lifetimes of the Core — the session of the browser and the
  stability run each last half an hour — so the whole set needs about an hour;
* every rehearsal owns a **disposable** instance of the Core, its own collectors and its own
  store. Nothing of the rehearsal touches the personal installation of the operator, no private
  endpoint is contacted and nothing leaves the machine.

The freshness rule of the record demands that no receipt predates the last change of the code it
covers: after a change of the Core, the command is the way to measure the evidence of the release
again — the verification above then proves that every receipt is fresh.

## 14. What the receipts prove

`docs/evidence/oip-operations/operations.json` records the measured result of
the sequence above against a disposable instance, and
`docs/evidence/oip-upgrade-rollback/upgrade-rollback.json` the result of the
upgrade and the rollback: the provisioning, the start,
the status, the backup with its integrity check, the refused restore of a
running instance, the stop, the restore, the start again, the restart, the
stop and the three refusals of the personal installation together with the
unchanged hash of the personal database.

`docs/evidence/oip-macos-app/macos-app.json` records the measured result of the
application bundle: the build, the start, the requests of the bundle, the
refusal of the Core, the termination without an orphan and the start again.
`docs/evidence/oip-historical-daemon/historical-daemon.json` records the
measured result of the daemon handover: the refused shape of OIP-007, the
started daemon of the era, the scoped reads of its principals, the collection,
the takeover of the release binary and the restored store served by the era
again.

## 15. The Core on another host (the Raspberry Pi `bodi-pi`)

### 15.0 The intended architecture

The operator intends the **Rust OIP Core to run on `bodi-pi`** (a Raspberry
Pi) and the Mac to run **only the Flutter presentation client**. The Mac must
not remain the only host of the application.

This section reconciles that intention with the contracts of the Core and of
the client, and it names the smallest safe step that moves towards it. It
describes what the **operator** runs; the loop does not run it (see §15.6).

### 15.1 What the contracts say today

| Contract | Consequence for a Core on the Pi |
|---|---|
| The Core binds to `127.0.0.1` only; a productive remote identity is **not** implemented and **not** claimed (G10, escalated) | The Core on the Pi keeps that binding. It is reachable through a **forward on the loopback of the Mac**, not through the network. |
| The browser session is bound to the **origin** of the Core (`HttpOnly`, `SameSite=Strict`, the origin rule of every write) | A tunnel that forwards a **port** of the Mac to a port of the Pi keeps the origin **identical**: `http://127.0.0.1:<port>`. No TLS, no new origin, no change of the product. |
| The address of the instance is baked into the client as `OIP_API_URL` (`--dart-define`) | The client needs **no change** for the Pi: the tunnel publishes the Core of the Pi under the same address the client already uses. |
| The one-time code of the operator session is minted over the **local IPC socket** of the Core (`oip-server --browser-login`) | The code is minted **on the Pi** and entered by the operator in the client on the Mac. The socket stays local; it is not forwarded. |
| The Core owns **no service registry** and **no VPN route**; the surfaces name the absence | Unchanged by the place of the Core. The **Network & VPN** workstation still names the absence of a VPN route — a Core on the Pi does not deliver one. |
| The data store of the operator is never touched by the loop | The instance on the Pi is a **disposable** instance with its **own** store. The personal store of the operator stays where it is. |

### 15.2 The reconciliation: the tunnel keeps the product identical

```text
Mac                                         bodi-pi
┌────────────────────────────────┐          ┌──────────────────────────────┐
│ Flutter client (macOS bundle)  │          │ OIP Core (oip-server)       │
│   -> http://127.0.0.1:18808    │  ssh -N  │   binds 127.0.0.1:18808      │
│                                │ -L 18808 │   own data store, own state │
│ ssh tunnel: 127.0.0.1:18808   │ :18808   │   own simulator (loopback)   │
│   -> 127.0.0.1:18808 of the Pi │          │   no BODI service touched   │
└────────────────────────────────┘          └──────────────────────────────┘
```

* The origin of the session is `http://127.0.0.1:18808` **on both sides**. The
  browser session, the origin rule, the CSRF rule and the cookie contract of
  G2 and G10 are therefore **unchanged** — the tunnel is not a new remote
  identity and it does not weaken a rule.
* **Nothing is exposed**: the Core listens on the loopback of the Pi, the
  tunnel is a forward on the loopback of the Mac, and no port of the Pi is
  published to the network. No firewall rule is changed.
* **The Core on the Pi needs a source that the Pi can reach.** The simulation
  of the Mac listens on the loopback of the Mac and is *not* reachable from
  the Pi. The instance on the Pi therefore runs **its own** simulator on the
  loopback of the Pi (`oip-simulated-server`, built for the same target), or
  collects from a device that the Pi reaches over the tailnet. The Core reads
  the source it can reach and states the sources it cannot.
* The escalation of G10 stays as it is: the execution audit of the Core is a
  structured local log and is **neither durable nor tamper-resistant**. A Core
  on the Pi does not change that, and the acceptance of the production-security
  scope stays an operator action.

### 15.3 The smallest safe step

The step is split so that every part can be measured and undone on its own.
**Phase 0 and phase 1 change nothing on the Pi.**

**Phase 0 — the read-only discovery of the host (operator, one command).**

```sh
scp tools/oip_pi_discovery.sh bodi-pi:/tmp/oip_pi_discovery.sh
ssh bodi-pi 'sh /tmp/oip_pi_discovery.sh'
```

The script reads the identity, the architecture, the memory, the disk, the
running services and the listeners of the host and **changes nothing**: it
installs no package, starts no service, stops no service and writes no file
outside `/tmp`. Its answer decides the target of the cross build (phase 1) and
names the free port of the instance.

**Phase 1 — the cross build of the Core for the target of the Pi (Mac).**

```sh
sh tools/oip_pi_build.sh aarch64-unknown-linux-gnu
# -> target/pi/aarch64-unknown-linux-gnu/aarch64-unknown-linux-gnu/release/oip-server
# -> target/pi/aarch64-unknown-linux-gnu/aarch64-unknown-linux-gnu/release/oip-simulated-server
```

The script builds the **same workspace** with the **same flags** as the
release (`--locked --release --workspace`) for the target of the Pi, uses
`zig cc` as the cross compiler and the cross linker and verifies the artefact
(the ELF machine, the digest). It writes **only** into `target/pi/` and it
changes nothing of the release: the release binary of the manifest is the
macOS binary and stays the artefact of the release.

**The build of this revision is measured.** The workspace builds for
`aarch64-unknown-linux-gnu` without a Rust toolchain on the Pi: the only
native dependency of the Core is the bundled SQLite, and the cross compiler
`zig cc` builds it. The two artefacts are ELF binaries for ARM aarch64
(`file`: `ELF 64-bit LSB pie executable, ARM aarch64 … for GNU/Linux 2.0.0`):

| Artefact | sha256 |
|---|---|
| `oip-server` | `d21986a0da19da7390dc599156424d368249bfa1d3ce8e38b096ab37769d686b` |
| `oip-simulated-server` | `61e8e70993ef5af3c5e4026b3c84b1145c60c1a54473af24e6d87ec49b6f7e42` |

Two limits belong to this fact: the **target** depends on the answer of the
discovery (a Pi with a 64-bit system is `aarch64`, a Pi with a 32-bit system
is `armv7l` — the script knows that target as well), and the artefacts were
**never started on the Pi**: a binary that was not run on the target host is
not a proven artefact. The proof of the runtime is the operator's phase 2 and
phase 4. The digests belong to the revision they were built from; a build of
another revision names another revision and yields other bytes.

**Phase 2 — a disposable instance on the Pi, started by hand (operator).**

The instance is started **by hand over SSH** — no systemd unit, no service
installation, no change of the BODI services of the host.

The **bundle** of the instance is assembled on the Mac and copied to the Pi
as **one directory**. The bundle carries the two binaries of phase 1, the
tool of the instance, the generator of the files of the instance, the scripts
and the digest of every file:

```sh
sh tools/oip_pi_bundle.sh aarch64-unknown-linux-gnu
# -> target/pi-bundle/aarch64-unknown-linux-gnu/
scp -r target/pi-bundle/aarch64-unknown-linux-gnu bodi-pi:~/oip-bundle
```

On the Pi the instance is then started **by hand** — one command, no service,
no published port, nothing written outside the directory of the instance:

```sh
ssh bodi-pi
# on the Pi, as the user of the operator:
cd ~/oip-bundle
./bin/start.sh     # prepare, provision, start the simulation and the Core
./bin/status.sh    # the state of the instance and the listeners of the host
./bin/login-code.sh # the one-time code of the operator session
./bin/stop.sh      # the Core and the simulation of the host
```

What `start.sh` does, and what it deliberately does not do:

* it writes the **files of the instance** (`instance/etc/core.json`,
  `instance/etc/plan.json`, `instance/etc/ipc.json`) with **absolute** paths
  inside the directory of the instance — the Core resolves a relative data
  store against the working directory of its process, and a working directory
  is not a contract;
* it starts the **simulation of the host** on the loopback of the host: the
  Core needs a source that the host can reach, and the simulation of the Mac
  is not reachable from the Pi. The simulation is **by hand**, it is not a
  service, and it is stopped with the instance;
* it **provisions** the data store of the instance from the plan of the
  instance and **starts** the Core with the protected local IPC;
* it installs **no service**, registers **no unit** with the init of the host,
  publishes **no port** and touches **no data of the operator**.

The **IPC configuration of the instance is in the principal mode**: every
client of the local IPC names the principal it acts as, and the configuration
carries no legacy actor and no legacy grant. The mode is not a choice of
taste — the code of the operator session (`--browser-login`) is only minted
for a client of the principal mode; a configuration with an actor cannot mint
a session at all.

The verification of the instance on the Pi is the same one the local instance
has (`./bin/status.sh`, the log, the backup) — the receipts of the local
instance are in `docs/evidence/oip-operations/`.

**The bundle is measured.** The rehearsal `tests/oip_pi_bundle.py`
(`docs/evidence/oip-pi-bundle/pi-bundle.json`) assembles the bundle with
stubs, runs the whole procedure — prepare, provision, start, mint the code,
stop — and proves that the procedure calls the Core with the paths of the
instance, that it writes **nothing outside** the directory of the instance,
that the files of the instance name the loopback of the host only, that the
bundle installs no service and names no path of the machine it was built on.

**Phase 3 — the tunnel and the client (operator, on the Mac).**

```sh
# the forward: the loopback of the Mac carries the port of the Core of the Pi
ssh -N -L 127.0.0.1:18808:127.0.0.1:18808 bodi-pi
# in a second terminal: the code of the session, minted on the Pi
ssh bodi-pi 'cd ~/oip-bundle && ./bin/login-code.sh'
# the client of the Mac (the bundle of the release, built for the port 18808)
open apps/flutter/build/macos/Build/Products/Release/oip_dashboard.app
```

**Phase 4 — the verification of the whole path (operator).**

| Check | How it is proven |
|---|---|
| The Core of the Pi answers on the loopback of the Mac | `curl -s http://127.0.0.1:18808/api/v2/system/status` through the tunnel |
| The session works with the **same** origin | the client asks for the code, the Core mints it on the Pi, the client logs in |
| The scope is enforced | the session of another organization is refused with `RESOURCE_NOT_ACCESSIBLE` |
| The data is the data of the Pi | the values of the source of the Pi differ from the values of the simulation of the Mac |
| Nothing is exposed | `ss -ltn` on the Pi shows the Core only on `127.0.0.1`; `ss -ltn` on the Mac shows the forward only on `127.0.0.1` |
| The BODI services of the Pi are untouched | `systemctl list-units --state=running` before and after the instance — the same list |

**The rollback** is one command and needs no plan: the instance of the Pi is
stopped by hand (`python3 tools/oip_ops.py … stop`), the tunnel is closed
(`Ctrl-C`) and the directory of the instance is removed. Nothing of the release
on the Mac changes, nothing of the personal store changes, and the BODI
services of the Pi were never part of the instance.

### 15.4 What is **not** done by this plan

* **No systemd unit and no service installation** — the instance is started by
  hand. A launch agent on the Pi is a system service and needs an explicit
  operator authorization (like the launch agent of the Mac, G9/N17).
* **No change of the firewall and no published port** — the Core binds the
  loopback of the Pi; the tunnel is the only way in.
* **No change of the BODI services** of the host — the instance owns its own
  directory, its own port and its own store.
* **No change of the personal store** of the operator — the instance on the Pi
  is disposable and owns its own data.
* **No change of the product's remote identity** — the origin of the session
  is the loopback of the Mac, exactly as with a local Core. The escalation of
  G10 is not withdrawn by the place of the Core.

### 15.5 The limits that stay limits

* The Core binds the loopback. **A productive remote identity is still not
  implemented** — the tunnel is an operator's measure, not a feature of the
  product.
* The execution audit of the Core is a structured local log: it is **not
  durable** and **not tamper-resistant**. On the Pi that is the same as on the
  Mac, and it stays an escalated finding of G10.
* The cross build produces a binary for the **target of the Pi**. It is not
  executed by the loop: the loop has no session on that host, and a binary
  that was never started there is not a proven artefact. The proof is the
  operator's phase 2 and phase 4.
* The address space of a **real** OPC-UA server is still only reachable for a
  server that speaks the profile of the local simulation (the adapter reads
  the five metadata nodes of the simulation when it connects). A real device
  is collected over the SSH onboarding, not over OPC-UA.
* The **bind address of the Core is the loopback** and is not configurable:
  the Core listens on `127.0.0.1` of the host it runs on, and the rule of the
  origin of the session refuses a request whose `Host` is anything else. The
  tunnel is therefore not a convenience but the **only** way in — that is a
  deliberate gate, and the plan does not weaken it.
* The **trust of the simulation origin is not bound to a host**: the Core
  accepts a source as a simulation when it claims the origin
  `oip-local-simulation-v1`. The simulation of the Pi is therefore trusted
  exactly like the simulation of the Mac — **no change of the product** is
  needed for the host.
* The **path of the instance must not contain a symlink**: the Core refuses a
  socket or a credential whose path contains one. The generator of the files
  of the instance checks that before it prepares anything, so the operator
  gets a message that names the cause.
* The **path of the socket** of the local IPC may not be longer than 100
  bytes, and the directory that carries it must be private (mode `0700`) and
  belong to the user of the instance. The generator writes both.
* The **backup and the restore** of the instance use the `sqlite3` of the
  machine when it is installed (`/usr/bin/sqlite3`); without it the tool
  falls back to the `sqlite3` module of Python, which on some distributions
  is too old for the schema of the Core. The rehearsal of the backup of the
  local instance is in `docs/evidence/oip-operations/`.
* The tool of the instance and the Core now name the **same data store**: the
  tool resolves a relative path against the configuration and hands the
  resolved path to the Core explicitly (`--database`), because the Core
  resolves a relative path against the working directory of its process.

### 15.6 The operator action that is outstanding

The loop cannot run the discovery of §15.3 phase 0: **the SSH session of this
session is not permitted** (`ssh bodi-pi …` is refused by the permission layer
of the session, which cannot ask the operator). The operator runs the script of
phase 0 and reports its answer; the loop then fixes the target of the cross
build of phase 1 and continues with the receipts of the release.

## 16. The secure update of the Core of an instance

The local browser installation packages the Core, its matching Flutter web build
and the local administration tools together. The installer verifies files
obtained over HTTPS or copied from removable media using the same command.
Python 3 and its `cryptography` library with Ed25519 support must already be
available on the installation host. Prepare those dependencies separately for
an offline host.

### 16.1 Release and initial trust

Start with the matching Core, simulator and browser build from an approved
source revision. On the controlled release machine, use the private Ed25519
key to sign the manifest. Set the actual database schema for that build.

```sh
python3 -B tools/oip_update.py --prepare --bundle "$NEW_BUNDLE_ZIP" \
    --binary target/release/oip-server --web apps/flutter/build/web \
    --simulator target/release/oip-simulated-server \
    --signing-key "$RELEASE_SIGNING_KEY" --release-version "$RELEASE_VERSION" \
    --revision "$SOURCE_REVISION" --database-schema "$CORE_DATABASE_SCHEMA"
```

The version uses numeric `major.minor.patch`. The distinct source revision
identifies the release directory. The manifest binds platform, architecture
and database schema to SHA-256 digests of the Core, browser, optional simulator,
administration tools and license. The detached `signature` is the Ed25519
signature of the exact manifest bytes.

Prepare the package from the same clean checkout used for its locked Core and
simulator builds. On the release machine, package preparation uses Git and
the locally cached Cargo archives from that build. The signed package includes
the patched MPL-2.0 OPC UA sources and the original locked archives, plus the
Roboto license. The materials are under `web/licenses/` and described in
`THIRD_PARTY_NOTICES.txt`. The installation host needs neither Git nor Cargo.

For a package with licensing preconfigured, add `--license-policy FILE` to
`--prepare` and repeat `--commercial-license-kind KIND` for each agreed
commercial kind in that policy. Use the policy prepared from explicitly
approved License Center fingerprints. The manifest signs the public policy
and the commercial kinds. The package key cannot be an accepted license
issuer. The installer checks the policy with the staged Core before activation.
Deliver customer proofs separately. Keep both private keys in their protected
publishing or issuing workflows.

For the first installation, obtain `oip_update.py`, its adjacent `oip_ops.py`
and the Ed25519 public key through a trusted installer delivery. Check the
key's `shasum -a 256` against the fingerprint supplied through an independently
authenticated channel. Store the verified public key in an owner-controlled
location outside the incoming package. The private signing key stays on
the release machine. Subsequent updates can use the previously installed
verifier at `current/tools/oip_update.py`.

Use a new path ending in `.zip` for a single downloadable release file. The
publisher verifies the completed archive before making it available at that
path. A path without that suffix still prepares the previous directory format.

Provide the same ZIP on removable media or as an immutable, versioned file on
an approved static HTTPS host. Disclose the intended platform and version
alongside the download. Save the completed download to a local file. OIP
verifies the signed contents directly, so there is no manual extraction.
Instances whose installed verifier still predates ZIP support use the prior
directory format for their next update, or receive the trusted newer verifier
through the original installer delivery path.

### 16.2 Check, install and restart

Create an owner-private instance directory with `mkdir -m 700` for the first
installation. Set `OIP_VERIFIER` to the trusted verifier path described above.
As the OS account that owns the instance, confirm the target instance and
verify the package before scheduling maintenance.

```sh
python3 -B "$OIP_VERIFIER" --instance "$OIP_INSTANCE" --bundle "$BUNDLE_ZIP" \
    --public-key "$TRUSTED_UPDATE_KEY" --dry-run
```

`VERIFIED` confirms the signature, the declared component hashes, the host
target and the installed version and schema checks. For an update, take a
current encrypted backup and stop OIP during the agreed maintenance window.
The operator explicitly starts installation by running the same command
without `--dry-run`.

Installation checks available space and copies the signed files into a private
staging directory. A disposable candidate uses the embedded simulator on new
loopback ports, a fresh database and the staged browser files. OIP must report
ready, the served HTML and JavaScript must match the package, and the actual
schema of the disposable database must match the manifest. Existing sources,
credentials and stored values remain outside this check.

An atomic link selects the verified version as `current`. The previous release
files remain under `versions`. New installations can continue with
`current/tools/oip_local.py setup --package-public-key "$TRUSTED_UPDATE_KEY"`
and their workspace arguments. The package copy is reverified before setup
uses the signed licensing defaults. For updates, restart the normal local
runner and confirm that the configured sources and selected measurements
recover. Expect a collection gap during the maintenance window.

### 16.3 Failures and recovery

The installer rejects an active Core, a concurrent operation, another target,
an older or equal version and a database schema change. The operator can
read the reason on the console. A failed candidate check leaves the active
version in place. After an interruption, check `current` and the journal
before restarting. A hard power loss can leave an unselected directory
under `versions`. Have the installer verify the current selection and
inspect the abandoned staging entry before retrying.

The private journal at `state/updates.jsonl` records preparation and completed
selection. `PREPARED` alone does not confirm activation. A retained release
directory is for inspection and recovery planning. Schema migration, rollback,
automatic discovery and native macOS application updates have separate paths
or are outside this profile.
For an earlier Core-only deployment without a signed installed version
manifest, use a separately verified migration. That older release layout
cannot establish the version floor required by this installer.

Run `python3 tests/oip_update.py` for the private fixture rehearsal. Passing
`--core`, `--web` and optionally `--simulator` also rehearses the prepared
release with the supplied build. The rehearsal uses generated signing keys
and issues a local `update.json` receipt.

To rehearse the issuer handoff, first run the isolated License Center browser
test from its clean checkout with `LICENSE_CENTER_OIP_HANDOFF` set to a new
file in a private test directory. It exports the test registry and the two
proofs downloaded in that run. Use only this synthetic output. Build the
Core, simulator and browser from the clean OIP candidate. Use the workspace
build in §9.0 for the Core and `mcp_probe`, then run:

```sh
PLAYWRIGHT_MODULE="$PLAYWRIGHT_NODE_MODULE" python3 -B tests/oip_update.py \
    --issuer-handoff "$TEST_HANDOFF" --core target/release/oip-server \
    --web apps/flutter/build/web --simulator target/release/oip-simulated-server \
    --evidence target/oip-issuer-handoff
```

This run installs a newly signed ZIP in a fresh instance, checks that only
the approved OIP key is provisioned, rejects the issued ODP proof and imports
the fresh OIP proof in the compiled browser. After restarting the Core, it
checks REST and MCP parity and fresh simulator data with ended support.
`issuer-handoff.json` records source revisions and asset digests. Treat
`issuer-handoff.png` as a browser test capture.

### 16.4 Stage a commercial ZIP for static HTTPS delivery

On the release machine, review the exact ZIP including the signed license
text, third-party notices, public issuer policy and client assets. Approve its
whole-file SHA-256 for transfer. Use the independently provisioned package
public key to stage the same bytes into a new local directory.

```sh
python3 -B tools/oip_publication.py --bundle "$REVIEWED_ZIP" \
    --public-key "$TRUSTED_UPDATE_KEY" --sha256 "$APPROVED_ZIP_SHA256" \
    --output "$NEW_PUBLISH_TREE"
```

The command verifies the signature, all declared files, the signed commercial
assignment, the separation of signing keys and the approved digest of the
exact ZIP. It emits its relative public route, version and signed-manifest
and license digests. The version directory contains only the ZIP and an
Apache `.htaccess` file. Keep the verifier and initial signing-key fingerprint
on the separately authenticated delivery path.

Once the release and HTTPS host are approved, publish the complete version
directory under `/oip/macos-arm64/<version>/`. Provision an Apache HTTPS
virtual host with a valid certificate. Disable directory indexes and content
negotiation on this static route. The version directory's override uses
`AuthConfig`, `FileInfo`, `Options` and `mod_headers`. It requires HTTPS,
serves the ZIP as `application/zip` with immutable caching and denies other
files in the directory. Check override support and actual file readability
on the chosen host. Keep the URL immutable by putting any replacement in a
new version directory. Expose a version directory only after transferring
both files.

Download the public URL with an ordinary TLS-validating client using no
account or token. Compare its SHA-256 with the approved ZIP and run the local
installer with `--dry-run` and the provisioned key. Check the response headers
and verify that plain HTTP and the directory are unavailable. The same approved
ZIP can be delivered on removable media.

The rehearsal uses the macOS Apache binary and OpenSSL on loopback.
It generates short-lived TLS and signing keys and tests the exact staged ZIP
through an anonymous HTTPS download and subsequent offline installation.

```sh
python3 -B tests/oip_update.py --publication --core target/release/oip-server \
    --web apps/flutter/build/web --simulator target/release/oip-simulated-server \
    --evidence target/oip-publication
```

`publication.json` records the rehearsal. Hosting activation and validation
on the approved target require a separate production release.

### 16.6 Local Tailscale membership read

An instance may opt in with `"tailscale_peer_status": true` in its Core
configuration. The Core reads `tailscale status --json` locally every 30
seconds and joins peer hostnames or Tailscale addresses against the devices
already present in the authorized inventory. It returns only each authorized
device's membership state (`online`, `offline`, `not in tailnet`, or `unknown`);
it never returns unrelated tailnet peers or their addresses. The default is
`false`. The read does not probe devices, change routes, or write the database.
