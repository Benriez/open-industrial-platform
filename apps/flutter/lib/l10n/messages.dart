// Client-owned interface copy. Unmapped source strings are used verbatim.

const englishMessages = <String, String>{
  "25. November 2026": "25 November 2026",
  "Jeder Arbeitsbereich hat eine Spectrum-Überschrift. Die wichtigsten Aktionen stehen kompakt darunter.":
      "Each workspace has a Spectrum title with its main actions grouped below.",
  "Du kannst gespeicherte Geräteanmeldungen in den Einstellungen sperren. Die Sperre gilt auch nach einem Core-Neustart.":
      "You can revoke saved device sign-ins in Settings. Revocation persists after a Core restart.",
  "Zwei Sicherheitsbefunde in den OPC-UA-Bibliotheken wurden behoben.":
      "Two security issues in the OPC UA libraries were fixed.",
  "Sperren": "Revoke",
  "Gespeicherte Geräteanmeldungen": "Saved device sign-ins",
  "Hier verwaltest du Macs, die sich mit Touch ID bei diesem Core anmelden dürfen.":
      "Manage the Macs allowed to sign in to this Core with Touch ID.",
  "Für dein Konto sind keine Geräteanmeldungen gespeichert.":
      "There are no saved device sign-ins for your account.",
  "Name": "Name",
  "Zum Ersetzen sperrst du die bisherige Anmeldung und richtest Touch ID mit einem neuen Einmalcode wieder ein.":
      "To replace a device sign-in, revoke the old one and set up Touch ID again with a new one-time code.",
  "Diese Anmeldung": "Current sign-in",
  "Geräteanmeldung benennen": "Name device sign-in",
  "Anmeldung sperren": "Revoke sign-in",
  "Anmeldung für {0} sperren?": "Revoke sign-in for {0}?",
  "Du wirst sofort abgemeldet. Für eine erneute Einrichtung brauchst du einen Einmalcode.":
      "You will be signed out immediately. You will need a one-time code to set up this device again.",
  "Dieses Gerät wird abgemeldet. Für eine erneute Einrichtung braucht es einen Einmalcode.":
      "This device will be signed out. It will need a one-time code to set up sign-in again.",
  "Geräteanmeldungen konnten nicht geladen werden.":
      "Could not load device sign-ins.",
  "Der Name konnte nicht gespeichert werden.": "Could not save the name.",
  "Die Geräteanmeldung wurde gesperrt.": "The device sign-in was revoked.",
  "Der Core konnte die Sperre nicht bestätigen. Versuche es erneut.":
      "The Core could not confirm the revocation. Try again.",
  "Ein": "On",
  "Aus": "Off",
  "Die App sucht das ausgewählte Gerät.":
      "The app is looking for the selected device.",
  "Für dieses Gerät ist keine bestätigte Identität hinterlegt. Wende dich an die Person, die deine OIP-Installation verwaltet.":
      "This device has no approved identity. Contact the person who manages your OIP installation.",
  "Die App meldet sich am Gerät an.": "The app is signing in to the device.",
  "Die App liest Geräteinformationen.":
      "The app is reading device information.",
  "Das Gerät konnte nicht geprüft werden.": "The device could not be verified.",
  "{0} einrichten": "Set up {0}",
  "Geräteverbindung": "Device connection",
  "Verbindung einrichten": "Set up connection",
  "Verbunden. Die App empfängt Messwerte.":
      "Connected. The app is receiving measurements.",
  "Das Gerät ist verbunden. Die Überwachung ist aus.":
      "The device is connected. Monitoring is off.",
  "Das Gerät antwortet zurzeit nicht. Prüfe, ob es eingeschaltet und mit dem Netzwerk verbunden ist.":
      "The device is not responding. Check that it is on and connected to the network.",
  "Die App kann die Identität des Geräts nicht bestätigen. Die Verbindung wurde blockiert.":
      "The app cannot confirm the device's identity. The connection was blocked.",
  "Die App wartet auf die ersten Messwerte.":
      "The app is waiting for the first measurements.",
  "Die App empfängt zurzeit keine Messwerte.":
      "The app is not receiving measurements.",
  "Messwerte automatisch erfassen": "Collect measurements automatically",
  "Gerätedaten (OPC UA)": "Device data (OPC UA)",
  "Gerätedaten prüfen": "Check device data",
  "Gerätedaten ansehen": "View device data",
  "Gerätedaten verfügbar. {0} Einträge gefunden.":
      "Device data is available. Found {0} entries.",
  "Gerätedaten zurzeit nicht verfügbar. Prüfe, ob das Gerät eingeschaltet ist, und versuche es erneut.":
      "Device data is currently unavailable. Check that the device is on and try again.",
  "Die Gerätedaten konnten nicht geprüft werden. Versuche es erneut.":
      "The device data could not be checked. Try again.",
  "Gerät einrichten": "Set up device",
  "Ein Gerät für den ausgewählten Standort hinzufügen.":
      "Add a device to the selected site.",
  "Gib einen Gerätenamen ein und wähle einen Standort.":
      "Enter a device name and choose a site.",
  "Wähle einen vorbereiteten Gerätezugang.":
      "Choose a device connection that has been prepared.",
  "Einrichtung schließen": "Close setup",
  "Computer oder Router verbinden": "Connect a computer or router",
  "Vorbereitetes Gerät": "Prepared device",
  "Verbindungsdaten selbst eingeben": "Enter connection details manually",
  "Vorbereitetes Gerät auswählen": "Choose a prepared device",
  "Für diesen Bereich ist noch kein Gerätezugang freigegeben. Wende dich an die Person, die deine OIP-Installation verwaltet.":
      "Device access has yet to be enabled for this area. Contact the person who manages your OIP installation.",
  "Gerät prüfen": "Check device",
  "Das Gerät hat sich mit seinem bekannten Schlüssel gemeldet.":
      "The device presented its known key.",
  "Geräteinformationen abrufen": "Read device information",
  "Verbindungsauswahl ändern": "Change connection selection",
  "Gerätename: {0}": "Device name: {0}",
  "Betriebssystem: {0}": "Operating system: {0}",
  "Technische Gerätedaten": "Technical device information",
  "Nach deiner Bestätigung beginnt die App mit der Überwachung.":
      "The app starts monitoring once you confirm.",
  "Hue Bridge verbinden": "Connect Hue Bridge",
  "Lampen und Steckdosen hinzufügen": "Add lights and smart plugs",
  "Verbinde zuerst deine Hue Bridge mit Open Industrial Platform.":
      "Connect your Hue Bridge to Open Industrial Platform first.",
  "Drücke die große Taste in der Mitte deiner Hue Bridge. Wähle direkt danach hier „Jetzt verbinden“.":
      "Press the large button in the middle of your Hue Bridge, then select Connect now.",
  "Schalte die Hue-Lampe oder Steckdose ein und halte sie in Reichweite der Bridge. Wähle dann „Suche starten“.":
      "Turn on the Hue light or smart plug and keep it within range of the bridge. Then select Start search.",
  "Jetzt verbinden": "Connect now",
  "Suche starten": "Start search",
  "Hue Bridge verbunden.": "Hue Bridge connected.",
  "Die Bridge sucht nach Geräten. Das dauert bis zu 45 Sekunden.":
      "The bridge is searching for devices. This takes up to 45 seconds.",
  "Das Suchergebnis konnte nicht geladen werden.":
      "Could not load the search result.",
  "Keine neuen Geräte gefunden. Prüfe Stromversorgung und Abstand zur Bridge.":
      "No new devices found. Check the power supply and distance to the bridge.",
  "Ein neues Gerät gefunden.": "One new device found.",
  "{0} neue Geräte gefunden.": "Found {0} new devices.",
  "Drücke die Taste an der Hue Bridge und versuche es erneut.":
      "Press the button on the Hue Bridge and try again.",
  "Dein Konto darf diese Hue Bridge nicht einrichten.":
      "Your account does not have permission to set up this Hue Bridge.",
  "Die Hue-Einrichtung konnte nicht abgeschlossen werden.":
      "Could not finish Hue setup.",
  "Hue-Beleuchtung": "Hue lights",
  "Lichter aktualisieren": "Refresh lights",
  "Hue-Lichter konnten nicht geladen werden.": "Could not load Hue lights.",
  "Die Bridge hat die Änderung nicht bestätigt.":
      "The bridge did not confirm the change.",
  "Auf dieser Bridge sind keine Lichter eingerichtet.":
      "This bridge has no lights.",
  "Zum Steuern mit einem berechtigten Operator-Konto anmelden.":
      "Sign in with an authorized operator account to control these lights.",
  "{0} schalten": "Switch {0}",
  "Helligkeit von {0}": "Brightness of {0}",
  "Lichtfarbe": "Light color",
  "Weißton": "White light",
  "Farbtemperatur": "Color temperature",
  "Farbton": "Hue",
  "Sättigung": "Saturation",
  "Farbe": "Color",
  "+{0} weitere nicht dargestellt": "+{0} more not shown",
  "+{0} weitere · Activity/Diagnostics für den vollständigen Umfang":
      "+{0} further · Activity/Diagnostics for the full scope",
  "0 ms ist ein dokumentierter Wert, kein Beweis für fehlende Unterbrechung. Reconnected bedeutet nicht, dass alle Messwerte frisch oder Lücken geschlossen sind. Gap-Gründe sind im aktuellen Flutter-DTO nicht verfügbar.":
      "0 ms is a documented value, not evidence of missing interruption. Reconnected does not mean that all readings are fresh or gaps closed. Gap reasons are not available in the current Flutter DTO.",
  "2 Spalten": "2 columns",
  "25 Reads, legacy SimulationScenarioSet und offline-only SettingsChange sind Core-Vertragsbestand. Mutierende MCP-Tools, Remote MCP, Browser-Administration und aktive Session-Inventarisierung werden nicht angeboten.":
      "The Core contract includes 25 read operations, legacy SimulationScenarioSet, and offline-only SettingsChange. MCP tools that modify data, remote MCP, browser administration, and listing active sessions are unavailable.",
  "3 Spalten": "3 columns",
  "4 Spalten": "4 Columns",
  "AKTUELLER WERT": "CURRENT VALUE",
  "ANMELDUNG ERFORDERLICH": "SIGN-IN REQUIRED",
  "API VERBINDET": "API CONNECTING",
  "API-Daten konnten nicht geladen werden": "API data could not be loaded",
  "ARBEITSBEREICH": "WORKSPACE",
  "Abbrechen": "Cancel",
  "Abmelden": "Sign out",
  "Adressraum": "Address space",
  "Agent {0} · VPN {1} · keine Ableitung aus Registry":
      "Agent {0} · VPN {1} · no derivative from registry",
  "Agent-first Backend-Anforderung": "Agent-first backend request",
  "Aktiv": "Active",
  "Aktive MCP-Client-Sessions können derzeit nicht zentral aufgelistet werden.":
      "Active MCP client sessions cannot currently be listed centrally.",
  "Aktualisieren": "Refresh",
  "Aktuell": "Fresh",
  "Aktuell, Ø, Min und Max der Sitzung":
      "Current, Ø, Min and Max of the session",
  "Aktuelle Messwerte": "Current measured values",
  "Aktuelle Source-Datensätze + {0} geladene Kontrollereignisse. Keine Source-Health-Historie.":
      "Current source records + {0} loaded control events. No source health history.",
  "Aktuelle lokale Identität und dokumentierte Produktionsgrenzen. Keine Sicherheitszertifizierung.":
      "Current local identity and documented production boundaries. No security certification.",
  "Alle": "All",
  "Alle Berechtigungen": "All permissions",
  "Alle Capabilities": "All capabilities",
  "Alle Collection-Ereignisse bleiben im Event Explorer vollständig bedienbar.":
      "All collection events remain fully operable in Event Explorer.",
  "Alle Signale des Geräts mit Balken": "All signals of the device with bars",
  "Alle Zustände": "All states",
  "Alle berechtigten Infrastrukturen": "All authorized infrastructures",
  "Alle gelieferten": "All reported items",
  "Alle im Snapshot verfügbaren Signale":
      "All signals available in the snapshot",
  "Alle registrierten Geräte": "All registered devices",
  "Alter bei Snapshot · lokale Empfangszeit":
      "Age at snapshot · local receive time",
  "Analysis · tatsächlich verfügbare Daten":
      "Analysis · actually available data",
  "Angeheftet": "Pinned",
  "Angeheftet {0}": "Pinned {0}",
  "Anmelden …": "Signing in …",
  "Anpassen": "Customize",
  "Ansicht zurücksetzen": "Reset view",
  "Anzahl Relationen": "Number of relations",
  "Anzeigename": "Display name",
  "App-Identität, Build-Nummer, Lizenz und Datenschutzerklärung. Keine Core-Konfiguration.":
      "App identity, build number, license and privacy policy. No core configuration.",
  "App-Version und Updates sind in den Einstellungen ohne Plattformrechte zugänglich.":
      "The app version and updates are accessible in the settings without platform rights.",
  "App-Version und Updates öffnen": "Open app version and updates",
  "Arbeitsbereich": "Workspace",
  "Archivierung ist ein Offline-Vorgang": "Archiving is an offline process",
  "Auf Auswahl fokussieren": "Focus on selection",
  "Auf dem Mac passt sich der Fensterinhalt an, sobald du den Fensterrand loslässt.":
      "On the Mac, the window contents will adjust as soon as you let go of the window edge.",
  "Aus Vergleich entfernen": "Remove from comparison",
  "Aus Vergleich entfernen (C)": "Remove from comparison (C)",
  "Ausgewählt": "Selected",
  "Aussagegrenze": "Limits of evidence",
  "Aussageherkunft": "Evidence source",
  "Auswahl aufheben": "Clear selection",
  "Authentifizieren und Hostdaten lesen": "Authenticate and read host data",
  "Authorization Scope ≠ Selected UI Context. Auswahl erteilt keine Berechtigung.":
      "Authorization Scope ≠ Selected UI Context. Selection does not grant permission.",
  "Autorisierte Core-Daten werden gelesen …": "Authorized core data is read...",
  "Autorisierte Konfiguration konnte nicht geladen werden.":
      "Authorized configuration could not load.",
  "Autorisierte Tailscale-Peers werden den passenden registrierten Geräten zugeordnet.":
      "Authorized tailscale peers are assigned to the appropriate registered devices.",
  "Autorisierten Management-Read erneut prüfen":
      "Retry the authorized management request",
  "Autorisierten Read erneut versuchen": "Try Authorized Read Again",
  "Autorisierter Infrastructure Context wird nicht unterstützt.":
      "Authorized Infrastructure Context is not supported.",
  "Autorisierter v2-Kontext inklusive Devices ohne Collector. Keine Inventar- oder Geräteverwaltung in diesem Bereich.":
      "Authorized v2 context including devices without a collector. No inventory or device management in this area.",
  "Autorisierter v2-SSE wird nicht unterstützt.":
      "Authorized v2-SSE is not supported.",
  "BACKEND-DATEN": "BACKEND DATA",
  "Beginn {0}\nEnde {1}\n{2}": "Begin {0} End {1} {2}",
  "Bei einem Fehler im Live-Stream lädt die Mac-App den aktuellen Stand über die bestehende Anmeldung.":
      "If there is an error in the live stream, the Mac app loads the current status via the existing login.",
  "Bei verweigertem Management-Zugriff führt ein Link direkt zu den lokalen Updates.":
      "If management access is denied, a link leads directly to the local updates.",
  "Bekannte Topologie-Endpunkte": "Known topology endpoints",
  "Bekannte Verbindungen öffnen": "Open known connections",
  "Benachbarte Ereignisse": "Neighboring events",
  "Benötigt werden autorisierte, scoped und paginierte ServiceDeclaration-DTOs mit Provenance, Freshness und Device-ID-Beziehung. Der Vertrag: docs/architecture/OIP_DEVICES_SERVICES_2027_CORE_REQUIREMENTS.md.":
      "Authorized, scoped and paginated ServiceDeclaration DTOs with provenance, freshness and device ID relationship are required.",
  "Beobachtet ausschließlich die eigene autorisierte Core-Runtime. Kein Credential-, Datei-, Remote- oder Handshake-Test.":
      "Watch only your own authorized core runtime, no credential, file, remote or handshake test.",
  "Beobachteter Zustand": "Observed state",
  "Bereit": "Ready",
  "Beschriftung": "Label",
  "Bestehende autorisierte Hierarchie-Reads bleiben maßgeblich; Browser-Admin-Mutationen sind nicht verfügbar.":
      "Existing authorized hierarchy reads remain authoritative; browser admin mutations are not available.",
  "Betroffenes Gerät: {0}": "Affected device: {0}",
  "Beziehungen prüfen": "Inspect connections",
  "Bis zu vier Geräte über Compare auswählen. Unterschiedliche Messdimensionen werden nicht zu einer gemeinsamen Kennzahl verrechnet.":
      "Select up to four devices for comparison. Measurements with different dimensions are displayed separately.",
  "Bogen mit Schwellenband": "Arc gauge with threshold band",
  "Breite": "Width",
  "Browser-Identität fehlt": "Browser identity is missing",
  "Build-, Runtime- und Capability-Fakten ohne erfundene Host-Metriken.":
      "Build, runtime and capability facts without invented host metrics.",
  "CONTRACT FIXTURE · NICHT LIVE": "CONTRACT FIXTURE · NOT LIVE",
  "CPU, GPU und RAM: unbekannt.": "CPU, GPU and RAM: unknown.",
  "Collection Error": "Collection error",
  "Collection Errors · geliefert": "Collection Errors · delivered",
  "Collection-Ereignisse": "Collection events",
  "Collection-Ereignisse konnten nicht geladen werden.":
      "Collection events could not be loaded.",
  "Collection-Ereignisse nicht verfügbar": "Collection events not available",
  "Collection-Ereignisse sind Transport-/Collection-Beobachtungen. Incidents werden separat ausgewiesen. Zeitliche Nähe erzeugt weder Korrelationsnachweis noch Ursache.":
      "Collection events are transport/collection observations. Incidents are reported separately. Time proximity produces neither proof of correlation nor cause.",
  "Comfortable-Dichte": "Comfortable density",
  "Compact-Dichte": "Compact density",
  "Core-Einstellungen": "Core settings",
  "Core-Zustand: {0}": "Core state: {0}",
  "DARSTELLUNG": "DISPLAY FORMAT",
  "DATEN & ANALYSE": "DATA & ANALYSIS",
  "DEMO-SZENARIEN · BESTEHENDE AUTORISIERTE SIMULATORSTEUERUNG · GETRENNT VON ECHTEN COLLECTION-EVENTS":
      "DEMO SCENARIOS · EXISTING AUTHORISED SIMULATOR TAXATION · SEPARATED FROM REAL COLLECTION EVENTS",
  "Darstellung": "Format",
  "Darstellung wechseln": "Change appearance",
  "Das Backend liefert aktuell keine Incidents. Collection-Ereignisse bleiben separat verfügbar.":
      "The backend does not currently deliver incidents. Collection events remain available separately.",
  "Das Core hat nichts dokumentiert. Das ist kein Nachweis einer lückenlosen Überwachung.":
      "The core hasn't documented anything. That's not evidence of seamless surveillance.",
  "Das Gerät konnte nicht aktualisiert werden.":
      "The device could not be updated.",
  "Das Update wird geladen und nach dem Neustart installiert.":
      "Downloading the update. It will be installed after restart.",
  "Das Update wurde zurückgestellt.": "The update was deferred.",
  "Das aktuelle Layout dieses Kontexts wird durch ein automatisch aus den gelieferten Geräten und Messpunkten erzeugtes ersetzt.":
      "The current layout of this context is replaced by an automatically generated from the supplied devices and measuring points.",
  "Das ist ein gelieferter leerer Snapshot, kein abgeleiteter Real-Mode- oder Registry-Zustand.":
      "This is a delivered empty snapshot, not a derived real-mode or registry state.",
  "Das konfigurierte Signal ist in diesem Kontext nicht verfügbar.":
      "The configured signal is not available in this context.",
  "Das native Fenster öffnet sich mit einer nutzbaren Mindestgröße.":
      "The native window opens with a usable minimum size.",
  "Das neue OIP-Logo erscheint in der App, im macOS-Dock, im Stage Manager und in der Web-App.":
      "The new OIP logo appears in the app, macOS dock, stage manager and web app.",
  "Das Änderungsprotokoll enthält jetzt auch die aktuellen App-Versionen.":
      "The change log now also includes the current app versions.",
  "Dashboard schreibgeschützt": "Read-only dashboard",
  "Dashboard öffnen": "Open dashboard",
  "Dashboard-Panel hinzufügen": "Add dashboard panel",
  "Dashboard-Panels passen sich als Kacheln an die verfügbare Fensterbreite an.":
      "Dashboard panels adapt as tiles to the available window width.",
  "Dashboard-Panels zeigen Messwerte als Anzeigen, Statistiken und Balken.":
      "Dashboard panels display metrics as ads, statistics, and bars.",
  "Dashboards bieten weitere Darstellungen und ein automatisch erzeugtes Layout für verfügbare Messwerte.":
      "Dashboards provide additional representations and an automatically generated layout for available metrics.",
  "Daten konnten nicht geladen werden.": "Data could not be loaded.",
  "Datendichte": "Data density",
  "Datenlücke: Zeitraum nicht bestimmbar":
      "Data gap: time period not determinable",
  "Datenlücke: inkonsistente Zeitgrenzen": "Data gap: inconsistent time limits",
  "Datenlücke: unvollständige Zeitgrenzen": "Data gap: incomplete time limits",
  "Datenträger: {0}": "Disk: {0}",
  "Datentyp": "Data type",
  "Datenverlust gemeldet": "Reported data loss",
  "Davon im lokalen Filter": "Of which in the local filter",
  "Degradiert": "Degraded",
  "Der Client kann einen bereits laufenden lokalen OIP-Tunnel wiederverwenden.":
      "The client can reuse an already running local OIP tunnel.",
  "Der Client verwendet wieder den stabil antwortenden lokalen OIP-Tunnel.":
      "The client again uses the stable-responding local OIP tunnel.",
  "Der Core antwortet autorisiert, aber dieser Client hat keinen Management-Adapter für Verbindungen und Monitoring.":
      "The core responds authorized, but this client does not have a management adapter for connections and monitoring.",
  "Der Core besitzt den Historienendpunkt, aber dieser Client hat keinen autorisierten Management-Adapter.":
      "The core owns the history endpoint, but this client does not have an authorized management adapter.",
  "Der Core besitzt keine verlässlich abfragbare initialized-client Registry.":
      "The core does not have a reliably queried initialized client registry.",
  "Der Core besitzt keinen HTTP-/MCP-Schreibpfad. Änderungen erfordern den exklusiven lokalen Operator-CLI-Prozess und werden erst beim nächsten validierten Core-Start aktiv.":
      "The core does not have an HTTP/MCP write path. Changes require the exclusive local operator CLI process and become active only at the next validated core start.",
  "Der Core bestimmt den autorisierten Principal-Scope. Die Auswahl grenzt nur bereits autorisierte Daten ein und erteilt keine Berechtigung.":
      "The core determines the authorized principal scope; the selection limits only already authorized data and does not grant permission.",
  "Der Core hat für dieses Ereignis keinen Grund geliefert":
      "The Core did not provide a reason for this event",
  "Der Core hat für dieses Gerät keine gespeicherten Beobachtungen. Das ist kein Nachweis einer lückenlosen Überwachung.":
      "The core has no stored observations for this device, which is not evidence of seamless monitoring.",
  "Der Core konnte die Abmeldung nicht bestätigen. Verbinde dich erneut und wiederhole die Abmeldung.":
      "The Core could not confirm sign-out. Reconnect and sign out again.",
  "Der Core liefert das Register der Dienste des autorisierten Scopes, und der Betreiber hat für diesen Scope keinen Dienst deklariert. Ein leeres Register ist eine Aussage des Betreibers, keine Messung.":
      "The core provides the register of services of the authorized scope, and the operator has not declared a service for this scope.",
  "Der Core misst keinen Dienst: das Register ist die Deklaration des Betreibers im Plan der Instanz.":
      "The core does not measure a service: the registry is the operator’s declaration in the entity’s plan.",
  "Der Core nennt den Stand der Diagnosehistorie: \$status.":
      "The Core calls the status of the diagnosis history: \$status.",
  "Der Core prüft ausschließlich diesen expliziten Endpoint. Es findet kein Netzwerkscan statt.":
      "The core only checks this explicit endpoint. No network scan takes place.",
  "Der Core stellt keinen Retention-Cleanup bereit.":
      "The core does not provide a retention cleanup.",
  "Der DeviceDetail-Request ist fehlgeschlagen. Frühere oder fremde Messwerte werden nicht angezeigt.":
      "The DeviceDetail request failed; previous or external measurements are not displayed.",
  "Der Gesundheitsverlauf wird von diesem API-Client nicht unterstützt.":
      "Health history is not supported by this API client.",
  "Der Katalog enthält keine mutierenden MCP-Tools. Enable/Disable, Remote MCP und per-tool Freigaben bleiben unsupported; geschützte Startup-Konfiguration ist maßgeblich.":
      "The catalog does not contain mutating MCP tools. Enable/Disable, Remote MCP and per-tool releases remain unsupported; protected startup configuration is relevant.",
  "Der Kontext ist nicht mehr autorisiert. Daten werden neu gelesen.":
      "The context is no longer authorized. Data is re-read.",
  "Der Live-Snapshot verletzt den erwarteten Datenvertrag.":
      "The live snapshot violates the expected data contract.",
  "Der Mac-Updater stellt die vorherige App wieder her, wenn macOS den Start der neuen Version verweigert.":
      "The Mac updater restores the previous app if macOS refuses to start the new version.",
  "Der OPC-UA-Browser lädt Quellen und Knoten nach einer kurzen Verbindungsstörung erneut.":
      "The OPC UA browser reloads sources and nodes after a brief connection malfunction.",
  "Der OPC-UA-Browser vermeidet doppelte Leseabfragen beim Öffnen.":
      "The OPC UA browser avoids duplicate read queries when opened.",
  "Der Verbindungsstatus unterscheidet eine erforderliche Anmeldung von einem API-Ausfall.":
      "The connection status distinguishes a required login from an API failure.",
  "Der aktuelle Lauf liefert keine autorisierten Organizations, Infrastructures oder Sites. Es werden weder Namen geraten noch Nullbestände behauptet.":
      "The current run does not provide authorized organizations, infrastructures or sites; no names are guessed or zero stocks claimed.",
  "Der ausgewählte DeviceDetail-Umfang konnte nicht geladen werden.":
      "The selected DeviceDetail scope could not be loaded.",
  "Der autorisierte Live-Snapshot verletzt den v2-Datenvertrag.":
      "The authorized live snapshot violates the v2 data contract.",
  "Der autorisierte Principal sieht aktuell keine Infrastructure. Es wird keine Demo-Organization angelegt.":
      "The authorized principal does not currently see any infrastructure. No demo organization is created.",
  "Der lokale API-Tunnel nutzt einen frischen Forwarding-Port.":
      "The local API tunnel opens a new forwarding port.",
  "Der lokale API-Tunnel verwendet einen frischen Weiterleitungsport.":
      "The local API tunnel uses a fresh forwarding sport.",
  "Detail-Inspector manuell öffnen": "Open detail inspector",
  "Details schließen": "Close details",
  "Deutsch und Englisch lassen sich beim Anmelden und in den lokalen Einstellungen auswählen.":
      "Choose German or English at sign-in or in local settings.",
  "Device ID kopieren": "Copy device ID",
  "Device-ID kopieren": "Copy device ID",
  "DeviceDetail enthält keine Observations. Kein Ersatzwert, kein 0 % und kein künstlicher Chart.":
      "DeviceDetail does not contain observations, no substitute value, no 0% and no artificial chart.",
  "DeviceDetail erneut laden": "Reload device details",
  "Diagnose & Ereignisse": "Diagnostics & Events",
  "Diagnose öffnen": "Open diagnostics",
  "Diagnosedaten aktualisieren": "Update diagnostic data",
  "Diagnosehistorie: nicht implementiert":
      "Diagnostic history: not implemented",
  "Diagnosehistorie: nicht verfügbar": "Diagnostic history: not available",
  "Diagnosehistorie: nur Demo": "Diagnostic history: Demo only",
  "Diagnostics · {0} Fehler · {1} Befunde":
      "Diagnostics · {0} Errors · {1} Findings",
  "Diagnostics öffnen": "Open Diagnostics",
  "Diagnostics öffnen · Modulziel, kein Event-Deep-Link":
      "Open Diagnostics · Module goal, no event-deep link",
  "Dichte Liste": "Compact list",
  "Die API hat keine darstellbaren Collection-Zeitpunkte geliefert.":
      "The API did not provide any displayable collection time points.",
  "Die API liefert keine Sources; daraus folgt kein Fehlerzustand und keine vollständige Abdeckung.":
      "The API does not provide any sources; this does not result in an error state and complete coverage.",
  "Die API-Antwort ist kein gültiges JSON.":
      "The API response is not valid JSON.",
  "Die API-Antwort verletzt den erwarteten Datenvertrag.":
      "The API response violates the expected data contract.",
  "Die Auswahl bleibt ohne fremde oder veraltete Source-Metadaten.":
      "The selection remains without foreign or outdated source metadata.",
  "Die Auswahl ändert das laufende Flutter-Designsystem sofort. Sie ist keine serverweite Core-Konfiguration und wird nicht als solche persistiert.":
      "The selection immediately changes the running Flutter design system; it is not a server-wide core configuration and does not persist as such.",
  "Die Einstellungen öffnen zuerst die lokalen App-Präferenzen.":
      "The settings first open the local app preferences.",
  "Die Management-Antwort ist kein JSON-Objekt.":
      "The management response is not a JSON object.",
  "Die Management-Antwort ist kein gültiges JSON-Objekt.":
      "The management response is not a valid JSON object.",
  "Die Management-Antwort verletzt den Core-Vertrag.":
      "The management response violates the core contract.",
  "Die Messung entsteht im Kollektor. Der Browser liest den Serveradressraum; Schreibaktionen erscheinen nur bei serverseitiger ReadWrite-Freigabe und zulässigem Operator-Kontext.":
      "The measurement is made in the collector. The browser reads the server address space; write actions appear only with server-side ReadWrite sharing and allowed operator context.",
  "Die Netzwerkansicht zeigt den autorisierten Gerätebestand statt einer leeren Topologie.":
      "The network view shows the authorized device inventory instead of an empty topology.",
  "Die Netzwerkansicht zeigt registrierte Geräte und ihre belegte Tailnet-Zugehörigkeit.":
      "The network view shows registered devices and their occupied tailnet affiliation.",
  "Die Netzwerktopologie zeigt bestätigte LAN-Nachbarn zwischen registrierten Geräten.":
      "The network topology shows confirmed LAN neighbors between registered devices.",
  "Die Provenienz des Kontext-Reads weicht vom Bootstrap ab.":
      "The provenance of the context read deviates from the bootstrap.",
  "Die Settings-Antwort verletzt den Core-Vertrag.":
      "The Settings response violates the Core contract.",
  "Die Theme-Auswahl gilt bis zum Ende der laufenden App-Sitzung.":
      "The selected theme applies to the current app session.",
  "Die Update-Prüfung ist fehlgeschlagen. Bitte später erneut versuchen.":
      "The update check failed. Try again later.",
  "Die Verbindung zum Pi nutzt das private Tailscale-Netz direkt.":
      "The connection to the Pi uses the private tailscale network directly.",
  "Die Versionshinweise sind in der App enthalten und benötigen keine Serververbindung.":
      "The version notes are contained in the app and do not require a server connection.",
  "Die Versionsübersicht kann direkt nach signierten Updates suchen.":
      "The version overview can search directly for signed updates.",
  "Die angeforderte Hauptnavigation ist nicht registriert.":
      "The requested main navigation is not registered.",
  "Die autorisierte Hierarchie übersteigt den sicheren UI-Leseumfang.":
      "The authorized hierarchy exceeds the secure UI reading scope.",
  "Die begrenzte API-Ansicht enthält diesen Record nicht mehr.":
      "The limited API view no longer contains this record.",
  "Die bestehende Source-API konnte nicht gelesen werden. Geladene Events bleiben separat und werden nicht als aktueller Gesundheitszustand interpretiert.":
      "The existing source API could not be read. loaded events remain separate and are not interpreted as current health status.",
  "Die erste Anmeldung schlägt Touch ID standardmäßig zur Einrichtung vor, wenn noch kein OIP-Schlüssel gespeichert ist.":
      "The first application suggests Touch ID for setup by default if no OIP key has yet been stored.",
  "Die gewählte Sprache wird auf diesem Gerät gespeichert.":
      "Your language choice is saved on this device.",
  "Die lokale API-Tunnelkonfiguration verwendet Port 18861.":
      "The local API tunnel configuration uses port 18861.",
  "Die lokale Anmeldung wird von diesem Client nicht unterstützt.":
      "Local login is not supported by this client.",
  "Die lokale Operator-Sitzung wurde beendet.":
      "The local operator session ended.",
  "Die lokale Sitzung hat kein Zeitlimit. Sie endet beim Abmelden oder mit einem Neustart der Instanz. Mit eingerichteter Touch ID kannst du danach eine neue Sitzung öffnen. Sonst brauchst du einen neuen Einmalcode.":
      "The local session has no time limit. It ends when you sign out or when the Core restarts. If you have set up Touch ID, use it to sign in again. Otherwise, request a new one-time code.",
  "Die persistierte Evidenz konnte nicht geladen werden.":
      "The persisted evidence could not be loaded.",
  "Die reale Infrastruktur ist geschützt. Erzeuge über das autorisierte lokale Operator-Profil einen Einmalcode. Er gilt 120 Sekunden und kann genau einmal verwendet werden.":
      "Access to the live infrastructure is protected. Generate a one-time code with your authorized local operator profile. The code is valid for 120 seconds and can only be used once.",
  "Diese Ansicht verändert weder Gerät noch Adapter. Fehlende Messquellen werden nicht durch Schätzwerte ersetzt.":
      "This view does not change the device or adapter, and the missing sources of measurement are not replaced by estimates.",
  "Diese ermittelte Identität gehört zum ausgewählten Gerät.":
      "This identified identity belongs to the selected device.",
  "Dieselbe Metrik über alle Geräte": "Same metric across all devices",
  "Dieselbe globale Auswahl gilt in allen Workstations. Sie ist keine administrative Berechtigung.":
      "The same global selection is valid in all workstations. It's not an administrative right.",
  "Dieser Client hat keinen autorisierten Management-Adapter. Das Gerät kann hier nicht geändert werden.":
      "This client does not have an authorized management adapter and the device cannot be changed here.",
  "Dieser Core bietet keinen autorisierten v2-Kontext; reale v1-Daten werden nicht anonym übernommen.":
      "This core does not provide an authorized v2 context; real v1 data is not transferred anonymously.",
  "Dieser Core liefert kein autorisiertes Service-Register. Gerätenamen, Device.kind und Registry Connection Type werden nicht als Dienste ausgegeben.":
      "This core does not provide an authorized service registry. Device name, Device.kind and Registry Connection Type are not displayed as services.",
  "Dieser Kontext liefert derzeit keine Messsignale.":
      "This context does not currently provide any measurement signals.",
  "Dieser Verlauf enthält ausschließlich reale Samples dieser UI-Sitzung. Er ist keine Server-History. Datenlücken und frühere Werte können ohne HistoryQuery nicht bestimmt werden.":
      "This history contains only real samples of this UI session. It is not a server history. Data gaps and previous values cannot be determined without HistoryQuery.",
  "Dieses Panel benötigt kein Messsignal.":
      "This panel does not require a measurement signal.",
  "Direkte macOS-Installationen können in Einstellungen → About manuell nach signierten OTA-Updates suchen.":
      "Direct macOS installations can manually search for signed OTA updates in Settings → About.",
  "Dokumentierte Lücke · {0}": "Documented Gap · {0}",
  "Dokumentierte Lücke: {0} ms": "Documented gap: {0} ms",
  "Dokumentierte Lücken werden von diesem API-Client nicht unterstützt.":
      "Documented gaps are not supported by this API client.",
  "Drei validierte Core-Schlüssel. Effektiver Wert, Default, Persistenz und Apply-Status bleiben getrennt.":
      "Three validated core keys: Effective Value, Default, Persistence, and Apply status remain separate.",
  "Du kannst Monitoring auch später im Geräte-Inspector einschalten.":
      "You can also turn on Monitoring later in the Device Inspector.",
  "Du verwendest die neueste Version.": "You are using the latest version.",
  "Edge Labels anzeigen": "Show edge labels",
  "Edge Labels ausblenden": "Hide edge labels",
  "Effektiver Scope, Provenienz und Offline-Change-Channel":
      "Effective scope, provenance, and offline change channel",
  "Effektives Schreibrecht vom Server geliefert; Rohattribute nicht geliefert":
      "Effective writing right delivered from server; raw attributes not delivered",
  "Ein Klick auf die Versionsanzeige öffnet jetzt die Änderungsübersicht, auch wenn der OIP-Server nicht erreichbar ist.":
      "Clicking on the version display now opens the change overview, even if the OIP server is not reachable.",
  "Ein Source-Reconnect beweist nicht, dass jedes zugeordnete Gerät vollständig funktioniert. Registry Presence, Telemetrie, Reachability und Findings bleiben getrennt.":
      "A source reconnect does not prove that every assigned device is fully functional; registry presence, telemetry, reachability, and finding remain separate.",
  "Ein archiviertes Gerät sammelt keine Messwerte mehr. Seine Historie bleibt erhalten.":
      "An archived device no longer collects measured values and its history is preserved.",
  "Ein erfolgreicher Status-Read ist kein erfolgreicher MCP-Client-Handshake. Refresh wiederholt nur autorisierte GET-Reads.":
      "A successful status read is not a successful MCP client handshake. Refresh only repeats authorized GET reads.",
  "Ein gesunder, bereits laufender Tunnel wird weiterverwendet, statt einen zweiten SSH-Forward zu starten.":
      "A healthy, already running tunnel will continue to be used instead of starting a second SSH forward.",
  "Ein registriertes Tool auswählen, um Schema, Permissions, Scopes und effektive Verfügbarkeit zu prüfen.":
      "Select a registered tool to check schema, permissions, scopes and effective availability.",
  "Ein sicherer Browser-Schreibpfad ist nicht verfügbar. Registrierung bleibt eine Offline-Aufgabe des lokalen Operators: Gerät mit stabiler ID und tatsächlichem Site-Placement über den lokalen OIP-Operator-Contract erfassen, danach Core gemäß RequiresRestart neu starten. Diese Ansicht erzeugt weder ein Gerät noch eine Source und meldet keinen falschen Erfolg.":
      "A secure browser write path is not available. Registration remains an offline task of the local operator: capture device with stable ID and actual site placement via the local OIP operator contract, then restart Core according to RequiresRestart. This view does not generate a device or source and does not report a false success.",
  "Eine Update-Prüfung läuft bereits.": "An update check is already running.",
  "Eine angemeldete Sitzung und ein autorisierter Infrastrukturkontext sind erforderlich, damit das persönliche Layout getrennt gespeichert wird.":
      "A logged-in session and an authorized infrastructure context are required for the personal layout to be stored separately.",
  "Eine eindeutige autorisierte OPC-UA-Source muss ausgewählt werden.":
      "A unique authorized OPC UA source must be selected.",
  "Eine persistierte Diagnoseausführung ist nicht implementiert. Die dokumentierten Lücken und Gesundheitsverläufe sind der persistierte Stand des Core; sie sind keine gespeicherte Diagnose und keine Ursache.":
      "The documented gaps and health histories are the persistent state of the core; they are not a stored diagnosis and not a cause.",
  "Einheit ungültig": "Unit invalid",
  "Einmalcode": "One-time code",
  "Einstellung, Berechtigung & Provenienz": "Setting, permissions & provenance",
  "Einstellungen": "Settings",
  "Einzelabfrage": "On-demand read",
  "Einzelabfrage · {0}": "On-demand read · {0}",
  "Empfangen {0}": "Received {0}",
  "Empfangenes API-Collection-Ereignis": "Received API Collection Event",
  "Entdecken, auswählen und vergleichen Sie tatsächlich gelieferte Collection-Ereignisse. Die API bietet keine vollständige historische Suche.":
      "Discover, select and compare actual delivered collection events. The API does not provide a complete historical search.",
  "Entweder enthält das aktuelle API-Fenster keine Einträge oder die lokalen Filter schließen alle aus. Dies ist weder eine vollständige Historie noch ein Gesundheitsbeweis.":
      "Either the current API window does not contain any entries, or the local filters exclude all, which is neither a complete history nor a health proof.",
  "Ereignis auswählen": "Select event",
  "Ereignis lösen": "Clear event selection",
  "Ereignis nicht im aktuellen Fenster": "Event not in the current window",
  "Ereignis {0} auswählen, {1}, {2}, Severity nicht geliefert, {3}":
      "Select event {0}, {1}, {2}, Severity not delivered, {3}",
  "Ereignis-Zeitspuren, {0} API-Ereignisse":
      "Event time tracks, {0} API events",
  "Ereignisse": "Events",
  "Ereignisse ohne EventTimestamp bleiben vollständig im Explorer und Inspector verfügbar. Es wird keine Position erfunden.":
      "Events without EventTimestamp remain fully available in the Explorer and Inspector.",
  "Erneut laden": "Reload",
  "Erneut versuchen": "Try again",
  "Erreichbar": "Reachable",
  "Erreichbar · reported": "Reachable · reported",
  "Erreichbarkeit aller Geräte im Kontext":
      "Reachability of all devices in the current context",
  "Ersetzen": "Replace",
  "Es gibt keinen aktiven Button Historie löschen und keinen Management-Export. Offline-Backups und mögliche zukünftige Retention-Funktionen bleiben Operator-/Core-Aufgaben.":
      "There is no active erase history button and no management export. Offline backups and possible future retention functions remain operator/core tasks.",
  "Es werden keine früheren Gerätedaten untergeschoben.":
      "No earlier device data is transferred.",
  "Executable, privater Socket und Credential-Datei müssen aus einem bereits autorisierten lokalen Profil stammen. Platzhalter sind keine installierte Verbindung. Kopieren führt keinen Befehl aus und erzeugt keine Grants.":
      "Executable, private socket and credential file must come from an already authorized local profile. wildcards are not an installed connection. Copying does not execute commands and does not generate grants.",
  "Execution & Fehler": "Execution and Error",
  "Explorer schließen": "Close Explorer",
  "Explorer öffnen": "Open Explorer",
  "Explorer, Engineering Workspace, Inspector und Related Activity verwenden anschließend dieselbe Device-ID. Es werden keine vorherigen Messwerte übernommen.":
      "Explorer, Engineering Workspace, Inspector and Related Activity then use the same device ID.",
  "Explorer, Operational Focus und Activity verwenden denselben technischen Kontext.":
      "Explorer, Operational Focus and Activity use the same technical context.",
  "Explorer, Timeline und Inspector verwenden denselben Datensatz. Auswahl mit Pfeiltasten, Enter, Touch oder Maus.":
      "Explorer, Timeline and Inspector use the same data set, selecting with arrow keys, enter, touch or mouse.",
  "Explorer-Filter anzeigen oder ausblenden": "View or hide Explorer filters",
  "Fachlicher Status": "Professional status",
  "Fehler": "Error",
  "Fehlgeschlagen": "Failed",
  "Fehlt · keine IDs im Device-DTO": "Missing · no IDs in the device record",
  "Filter zurücksetzen": "Reset filters",
  "Findings sind ohne Cursor abgeschnitten.":
      "Findings are cut off without cursors.",
  "Findings, aktuelle Ereignisse und Collection-Probleme untersuchen":
      "Inspect findings, recent events, and collection issues",
  "Findings-Provenienz weicht vom Snapshot ab.":
      "Findings provenance deviates from the snapshot.",
  "Fingerprint geprüft · diesem Host-Key vertrauen":
      "Fingerprint verified · trust this host key",
  "Flache Liste": "Flat list",
  "Formatierte Ansicht · Original bleibt per Kopieraktion abrufbar":
      "Formatted view · Original remains available via copy action",
  "Fortlaufendes Abonnement über den Rust-Adapter":
      "Continuous subscription via the Rust adapter",
  "Freier Text des Betreibers zu diesem Gerät":
      "Free text of the operator to this device",
  "Frisch beobachtet": "Freshly observed",
  "Füge Panels hinzu oder wähle unter „Anpassen“ das Auto-Layout. Angezeigt werden nur Daten des aktuellen Infrastrukturkontexts.":
      "Add panels or select the auto-layout under “Adjust” and display only data from the current infrastructure context.",
  "Fünf unabhängige Statusdimensionen": "Five independent status dimensions",
  "Für CollectionEvent nicht geliefert": "Not delivered for CollectionEvent",
  "Für Node-Browsing muss eine eindeutige Source ausgewählt werden.":
      "For node browsing, a unique source must be selected.",
  "Für die erste Anmeldung brauchst du einen Einmalcode und bestätigst deinen Fingerabdruck. Danach kannst du dich mit Touch ID erneut anmelden.":
      "For the first sign-in, use a one-time code and confirm your fingerprint. You can then sign in with Touch ID.",
  "Für diese Installation ist eine Operator-Anmeldung erforderlich.":
      "An operator login is required for this installation.",
  "Für diesen Kontext enthält der Snapshot keine auswählbare Observation. Keine Ersatzwerte, kein Chart und kein Wert 0.":
      "For this context, the snapshot does not contain a selectable observation, no substitute values, no chart, and no value of 0.",
  "Für diesen Kontext wurden keine Geräte geliefert.":
      "No devices were supplied for this context.",
  "Für diesen Mac ist Touch ID nicht eingerichtet.":
      "Touch ID is not set up for this Mac.",
  "GERÄTEDETAILS · API": "DEVICE DETAILS · API",
  "GERÄTEDETAILS · SIMULATION": "DEVICE DETAILS · SIMULATION",
  "GET /api/v1/events liefert maximal 100 aktuelle Kontrollereignisse je Source. Keine vollständige Serverhistorie, kein Replay; nach SSE-Reconnect ist Resync erforderlich.":
      "GET /api/v1/events delivers a maximum of 100 current control events per source. No complete server history, no replay; SSE-Reconnect requires Resync.",
  "GETRENNT VON DER DIAGNOSE": "SEPARATED FROM DIAGNOSE",
  "Gelieferte Source-IDs": "Delivered source IDs",
  "Gelieferte fachliche Records": "Records reported by the Core",
  "Gelieferte logische Pfade mit VPN-Transport · Demo-Fixtures":
      "Delivered Logical Paths with VPN Transport · Demo Fixtures",
  "Gemeldete/ableitbare Dauer": "Reported/derivable duration",
  "Gemeldeter Grund": "Reason reported",
  "Gemischte Datenherkunft im Infrastructure Context.":
      "Mixed Data Source in Infrastructure Context.",
  "Generisches mcpServers-Template aus dem Core-Vertrag. Keine Client-spezifische Konvertierung.":
      "Generic mcpServers template from the core contract. No client-specific conversion.",
  "Gepinnt": "Pinned",
  "Gerät anheften (P)": "Pin device (P)",
  "Gerät archiviert": "Device archived",
  "Gerät auswählen": "Select device",
  "Gerät auswählen, um exakt zugeordnete Findings und Source-Events zu sehen.":
      "Select device to see exactly matched finds and source events.",
  "Gerät bearbeiten": "Edit device",
  "Gerät für die technische Untersuchung auswählen":
      "Select equipment for technical inspection",
  "Gerät hinzufügen": "Add device",
  "Gerät lokal registrieren": "Register device locally",
  "Gerät nicht im aktuellen Registry-Stand":
      "Device not in current registry status",
  "Gerät nicht zugänglich.": "Device not accessible.",
  "Gerät registrieren": "Register device",
  "Gerät registrieren oder die sichere SSH-Einrichtung starten. Der Core prüft die Berechtigung für den gewählten Bereich.":
      "Register a device or start secure SSH setup. The Core checks permissions for the selected scope.",
  "Gerät {0} auswählen, ID {1}, Status {2}, {3} bekannte logische Verbindungen, {4}":
      "Select device {0}, ID {1}, status {2}, {3} known logical connections, {4}",
  "Gerät {0} {1} auswählen · {2} · {3} · Daten {4} · Reachability {5} reported":
      "Select device {0} {1} · {2} · {3} · Data {4} · Reachability {5} reported",
  "Gerät {0} {1} auswählen · {2} · {3} · {4} · Reachability {5} reported{6}":
      "Select the device {0} {1} · {2} · {3} · {4} · Reachability {5} reported{6}",
  "Geräte": "Devices",
  "Geräte & Dienste": "Devices & Services",
  "Geräte im Explorer oder Inspector mit C hinzufügen. Pfade lassen sich im Verbindungs- oder Edge-Inspector vergleichen. Maximal vier Einträge je fachlicher Kategorie.":
      "Add devices in the Explorer or Inspector with C. Paths can be compared in the Connect or Edge Inspector.",
  "Geräte und logische Pfade werden getrennt verglichen. Fehlende oder unterschiedliche Zeitstempel bedeuten keine Zeitsynchronität; es gibt keine Interpolation oder künstliche Messreihe.":
      "Devices and logical paths are compared separately; missing or different time stamps do not mean time synchronism; there is no interpolation or artificial measurement series.",
  "Geräte-ID: {0}": "Device ID: {0}",
  "Gerätekontext & Provenienz": "Device context & provenance",
  "Gerätename": "Device name",
  "Gerätestatus": "Device status",
  "Gerätetyp": "Device type",
  "Gesamter gelieferter Katalog": "All delivered catalogue",
  "Gesamtes geladenes Fenster": "Total loaded window",
  "Geschlossener Ring": "Closed ring",
  "Gestoppt": "Stopped",
  "Gesundheitsverlauf · {0}": "Health history · {0}",
  "Gleiche Source-Sequenz mit abweichendem Inhalt · separat ausgewiesen":
      "Same source sequence with different content · shown separately",
  "Global für alle OIP-Workstations": "Global for all OIP workstations",
  "Globaler Infrastructure Context · keine Szenarioauswahl":
      "Global Infrastructure Context · no scenario selection",
  "Grenzen & Anforderungen": "Limitations and Requirements",
  "Grenzen dieser Evidenz: {0}": "Limits of this evidence: {0}",
  "Grenzen dieser Historie: {0}": "Limits of this history: {0}",
  "Großer Wert mit Sparkline": "Large value with sparkline",
  "Grund": "Reason",
  "Grund nicht geliefert": "Reason not delivered",
  "Größter Sample-Abstand · kein Datenlückenbeweis":
      "Largest sample distance · no data gap proof",
  "Gut": "Good",
  "Helle Oberflächen · hohe Lesbarkeit": "Light surfaces · high readability",
  "Hierarchie und Snapshot haben unterschiedliche Provenienz.":
      "Hierarchy and snapshot have different provenances.",
  "Hierarchieauswahl benötigt einen engeren Kontext.":
      "Hierarchy selection requires a narrower context.",
  "Hinweis": "Notice",
  "Hinzufügen": "Adding",
  "Historie gekürzt": "History truncated",
  "Historie nicht abrufbar.": "History not available.",
  "Historie nicht verfügbar": "History not available",
  "Historie noch nicht verfügbar": "History not yet available",
  "Historische API nicht verfügbar": "Historical API not available",
  "Host-Key bereits vertrauenswürdig": "Host key already trusted",
  "Host-Key geändert · Verbindung blockiert":
      "Host key changed · Connection blocked",
  "Host-Key unbekannt · Identität vor der nächsten Verbindung bestätigen":
      "Host Key Unknown · Confirm identity before next connection",
  "IDENTITÄT ERFORDERLICH": "IDENTITY REQUIRED",
  "Ich bestätige die reine Inventarregistrierung ohne Verbindung.":
      "I confirm the pure inventory registration without connection.",
  "Identische Lieferungen": "Duplicate records",
  "Identität bestätigen und Verbindung speichern":
      "Confirm identity and save connection",
  "Identität, Availability, Data Quality, Relationships und Provenienz erscheinen nach der Auswahl.":
      "Identity, Availability, Data Quality, Relationships and Provenance appear after the selection.",
  "Identitätsprüfung": "Identity verification",
  "Im CollectionEvent nicht enthalten": "Not included in the CollectionEvent",
  "Im Explorer oder Inspector C beziehungsweise Compare wählen. Maximal vier; keine dauerhafte Investigation-API.":
      "Select in Explorer or Inspector C or Compare. Maximum four; no permanent Investigation API.",
  "Im Graph fokussieren": "Focus on the graph",
  "Im Vergleich": "Comparison",
  "Im geladenen Eventfenster: {0} Verbindungsverluste · {1} Reconnects · {2} Gap-Datensätze":
      "In the loaded event window: {0} Connection losses · {1} Reconnects · {2} Gap datasets",
  "In Timeline fokussieren": "Focus on Timeline",
  "In verfügbares Datenfenster zoomen": "Zoom into available data window",
  "Index aus den gelieferten Nodes · flacher Katalog":
      "Index from the delivered nodes · flat catalogue",
  "Infrastructure Context schließen": "Close infrastructure context selector",
  "Infrastructure {0} {1} global auswählen":
      "Select Infrastructure {0} {1} globally",
  "Infrastruktur": "Infrastructure",
  "Infrastruktur-Dashboard": "Infrastructure dashboard",
  "Initialisierung": "Initialisation",
  "Inspector anzeigen": "Show inspector",
  "Inspector für diese Workstation anheften":
      "Pin inspector for this workstation",
  "Inspector nicht mehr anheften": "Unpin inspector",
  "Inspector schließen": "Close inspector",
  "Inspector schließen · Objekt- und Datenwahl bleibt erhalten":
      "Close Inspector · Object and data selection is preserved",
  "Inspector öffnen": "Open the Inspector",
  "Intensität: {0} – {1}": "Intensity: {0} – {1}",
  "Interaktiver Verlauf in voller Breite": "Full-width interactive chart",
  "Inventar gespeichert. Keine Verbindung und keine Telemetrie.":
      "Inventory stored. No connection and no telemetry.",
  "Inventar und bisherige Identität bleiben erhalten. Schließe den Dialog und korrigiere Endpoint oder Identität für einen neuen Versuch.":
      "Inventory and previous identity are preserved. Close the dialog and correct endpoint or identity for a new attempt.",
  "Inventarregistrierung prüfen": "Check inventory registration",
  "Inventory Health · Beobachtungsumfang":
      "Inventory Health · Scope of observation",
  "Inventory überschreitet den Core-Bound.":
      "Inventory exceeds the core bound.",
  "Inventory-Paginierung ist inkonsistent.":
      "Inventory pagination is inconsistent.",
  "Inventory-Provenienz weicht vom Snapshot ab.":
      "Inventory provenance deviates from the snapshot.",
  "Jetzt erneut verbinden": "Reconnect now",
  "KEIN V2-KONTEXT": "NO V2 CONTEXT",
  "KONTEXT NICHT GELIEFERT": "CONTEXT NOT SUPPLIED",
  "Kein Browser-Onboarding, keine Demo-Datenlöschung und kein Source-Reconfigure. OIP-008.5 wird nicht verändert oder vorweggenommen.":
      "No browser onboarding, no demo data deletion, and no source reconfigure. OIP-008.5 is not modified or anticipated.",
  "Kein Browser-Save": "No browser save",
  "Kein Browser-Speichern": "No browser storage",
  "Kein Ereignis ausgewählt": "No event selected",
  "Kein Fehler geliefert": "No errors delivered",
  "Kein Gap-Datensatz": "No gap dataset",
  "Kein Gap-Datensatz in diesem Ereignis": "No gap record in this event",
  "Kein Gerät ausgewählt": "No device selected",
  "Kein Gerät liefert diese Metrik in diesem Kontext.":
      "No device provides this metric in this context.",
  "Kein Graph-Fokus: Relation unbekannt": "No graph focus: relation unknown",
  "Kein Live-Signal verfügbar": "No live signal available",
  "Kein Principal-Scope-Inventar geliefert":
      "No Principal Scope inventory delivered",
  "Kein Security-Blocker gemeldet": "No security blocker reported",
  "Kein Verbindungsnachweis": "No proof of connection",
  "Kein Wert": "No value",
  "Kein aktiver Demo-Vorfall": "No active demo incident",
  "Kein aktiver Vorfall": "No active incident",
  "Kein aktueller Source-Datensatz": "No current source dataset",
  "Kein autorisierter Kontext passt zur Suche.":
      "No authorized context fits the search.",
  "Kein autorisiertes Hierarchie-Inventar in dieser Browser-Ansicht":
      "No authorized hierarchical inventory in this browser view",
  "Kein autorisiertes Service-Inventar verfügbar.":
      "No authorized service inventory available.",
  "Kein freigegebenes SSH-Profil. Der lokale Operator muss eine SSH-Identität und den erlaubten Endpoint im Core-Profil konfigurieren. Keine privaten Schlüssel im Browser.":
      "No shared SSH profile. The local operator must configure an SSH identity and allowed endpoint in the core profile. No private keys in the browser.",
  "Kein globales Gesundheitsurteil": "No global health judgement",
  "Kein persistierter Diagnoselauf, keine Regelversion und keine strukturierten Evidenzreferenzen. Keine Flutter-Rekonstruktion als Core-Befund.":
      "No persistent diagnostic run, no rule version, no structured evidence references. No Flutter reconstruction as a core finding.",
  "Kein separates Feld; EventTimestamp ist Server-Zeit":
      "Not a separate field; EventTimestamp is server time",
  "Keine": "None",
  "Keine Beobachtung geliefert.": "No observation provided.",
  "Keine Chronologie geliefert.": "No chronology is provided.",
  "Keine Client-Namen, Session-IDs, Connected-Zustände, Last-Activity-Werte oder Connection Counts. Ein konfiguriertes Clientprofil ist keine aktive Session.":
      "No client names, session IDs, connected states, last activity values, or connection counts. A configured client profile is not an active session.",
  "Keine Collection-Ereignisse geliefert": "No collection events delivered",
  "Keine Datenlöschung": "No data deletion",
  "Keine Dienste deklariert.": "No services declared.",
  "Keine Ereignisse im Vergleich": "No events in comparison",
  "Keine Ersatzwerte": "No substitute values",
  "Keine Events im ausgewählten aktuellen Datenumfang.":
      "No events in the selected current data scope.",
  "Keine Eventtypen geliefert.": "No event types delivered.",
  "Keine Gap-Datensätze im geladenen Fenster. Das beweist keine lückenlose Historie.":
      "No gap records in the loaded window, which does not prove a complete history.",
  "Keine Geräte gefunden": "No devices found",
  "Keine Geräte im Filter": "No devices in the filter",
  "Keine Gesundheitsableitung": "No health derivation",
  "Keine Hintergrund-Polls; nur dieser bounded Read.":
      "No background polls; only this bounded read.",
  "Keine Kontextgruppe": "No context group",
  "Keine Messquelle angebunden": "No measurement source connected",
  "Keine Observation im Snapshot": "No observation in the snapshot",
  "Keine Observations im autorisierten DeviceDetail. Frühere Geräte- oder Source-Werte werden nicht untergeschoben.":
      "No observations in the Authorized DeviceDetail. Previous device or source values are not subtracted.",
  "Keine Referenzhierarchie verfügbar": "No reference hierarchy available",
  "Keine Registry-Einträge im aktuellen Filter.":
      "No registry entries in the current filter.",
  "Keine Related Activity für {0} im aktuellen API-Fenster.":
      "No related activity for {0} in the current API window.",
  "Keine Server-Record-ID": "No server record ID",
  "Keine Service-Route bzw. kein Service-Tool vorhanden":
      "There is no service route or service tool",
  "Keine Source": "No source",
  "Keine Source-DTOs geliefert": "No source DTOs delivered",
  "Keine Source-Datensätze": "No source data sets",
  "Keine Source-Zuordnung": "No source assigned",
  "Keine Telemetrie": "No telemetry",
  "Keine Telemetrie für dieses Gerät verfügbar":
      "No telemetry available for this device",
  "Keine Tools im Filter": "No tools in the filter",
  "Keine aktiven Findings oder Störungen im verfügbaren Snapshot/Eventfenster. Beobachtungslücken bleiben separat ausgewiesen.":
      "No active finds or disturbances in the available snapshot/event window. observation gaps remain shown separately.",
  "Keine belastbare Quality-Angabe geliefert.":
      "No reliable quality information supplied.",
  "Keine dokumentierte Lücke und kein Gesundheitsverlauf":
      "No documented gap and no health history",
  "Keine ereignisverknüpften Observation-Referenzen geliefert":
      "No event-related observation references provided",
  "Keine gelieferten Pfade im Filter": "No delivered paths in the filter",
  "Keine gemeldet": "Not reported",
  "Keine im aktuell geladenen Fenster": "None in the current time window",
  "Keine numerischen Samples im Sitzungsfenster":
      "No numerical samples in the session window",
  "Keine persistierten Messwerte": "No persisted measured values",
  "Keine registrierten Geräte im aktuellen Kontext oder Filter.":
      "No registered devices in the current context or filters.",
  "Keine zeitgestempelten Ereignisse": "No time-stamped events",
  "Keine zuordenbaren Ereignisse": "No attributable events",
  "Keine zusätzliche Reason/Dropped-Evidenz":
      "No additional reason/dropped evidence",
  "Klassische Ereignisliste aktiv": "Classic event list active",
  "Knoten": "Node",
  "Komfortable Liste": "Comfortable list",
  "Kompakte Flächenlinie der Sitzung": "Compact session area chart",
  "Konfigurierter Default und tatsächliche Query-Semantik ohne Browser-Mutation.":
      "Configured default and actual query semantics without browser mutation.",
  "Konsolidierte Mehrfachlieferungen": "Consolidated multiple deliveries",
  "Kontext & Provenienz": "Context & provenance",
  "Kontext nicht autorisiert": "Context not authorized",
  "Kontext wird autorisiert …": "Authorizing context …",
  "Kontext {0} auswählen": "Select Context {0}",
  "Korrelation ist keine bewiesene Ursache":
      "Correlation is not a proven cause",
  "Kritisch": "Critical",
  "LETZTER ERFOLGREICHER STAND · ABRUF FEHLER":
      "LAST SUCCESSFUL RESULT · REQUEST FAILED",
  "Letzte 15 min im Datenfenster": "Last 15 minutes in the data window",
  "Letzte Minute im Datenfenster": "Last Minute in the Data Window",
  "Letzte Source-Werte können veraltet sein. UI-Reconnect, Source-Reconnect und frische Messwerte sind verschiedene Zustände.":
      "Recent source values may be obsolete. UI-reconnect, source-reconnect and fresh readings are different states.",
  "Letzte Stunde im Datenfenster": "Last hour in the data window",
  "Letzte erfolgreiche Erfassung: {0}": "Last successful acquisition: {0}",
  "Letzter Empfang": "Last received",
  "Letzter Prüfversuch: {0}": "Last test attempt: {0}",
  "Letzter Prüfversuch: {0} · {1}": "Last test attempt: {0} · {1}",
  "Letzter erfolgreicher Empfang": "Last successful receipt",
  "Live · kein Source-Health-Beweis": "Live · no source health proof",
  "Live-Daten vorübergehend nicht verfügbar.":
      "Live data temporarily unavailable.",
  "Live-Verbindung geschlossen.": "Live connection closed.",
  "Lizenz": "Licence",
  "Logische Topologie": "Logical topology",
  "Lokal · keine Telemetrie": "Local · no telemetry",
  "Lokale Anmeldung fehlgeschlagen.": "Local sign-in failed.",
  "Lokale Entwicklung und Simulation": "Local development and simulation",
  "Lokale Operator-Anmeldung": "Local operator sign-in",
  "Lokale SSH-Identität": "Local SSH identity",
  "Lokaler Demo-Kontext": "Local demo context",
  "Lokalisiert": "Localised",
  "METRIKEN NICHT ERREICHBAR": "METRICS NOT ACCESSIBLE",
  "Management-Adapter nicht verfügbar": "Management adapter not available",
  "Management-Read wird von diesem API-Client nicht unterstützt.":
      "Management Read is not supported by this API client.",
  "Marker gruppieren sich nur visuell; Gruppen öffnen alle Mitglieder. Gap-Flächen nutzen ausschließlich dokumentierte Grenzen.":
      "Markers are grouped only visually; groups open all members. Gap areas use only documented boundaries.",
  "Markerabstände sind keine gemessenen Ausfalldauern. Historische Zustände beweisen keine aktuelle Erreichbarkeit.":
      "Marker distances are not measured failure times. Historical conditions do not prove current accessibility.",
  "Melde dich an, um die für dein Operator-Profil erlaubten Geräteaktionen zu öffnen.":
      "Sign in to access the device actions available to your operator profile.",
  "Messwert": "Measurement",
  "Messwerte": "Measurements",
  "Metriken nicht erreichbar": "Metrics unavailable",
  "Mit P oder dem Pin-Symbol anheften, um Werte nebeneinander zu halten.":
      "Stick with P or the pin icon to keep values side by side.",
  "Mit Source + Sequenz": "with source + sequence",
  "Mit Touch ID anmelden": "Sign in with Touch ID",
  "Mit einem aktualisierten OIP-Core bleibt die Anmeldung über 30 Minuten hinaus gültig.":
      "With an updated OIP core, the registration remains valid beyond 30 minutes.",
  "Monitoring aktivieren": "Enable monitoring",
  "Monitoring wird erst nach der Identitätsbestätigung separat aktiviert.":
      "Monitoring is only activated separately after the identity confirmation.",
  "Monitoring-Änderung fehlgeschlagen.": "The change in monitoring failed.",
  "NICHT GELIEFERT": "NOT SUPPLIED",
  "NUR DAS TATSÄCHLICH GELADENE AUTORISIERTE FENSTER":
      "ONLY THE ACTUALLY CHARGED AUTHORISED FLOW",
  "Nach Datentyp gruppieren": "Group by data type",
  "Nach Updates suchen": "Check for updates",
  "Name, ID oder Source": "Name, ID or Source",
  "Navigation öffnen": "Open navigation",
  "Near-black · präzise Spektral-Akzente":
      "Near-black · vivid spectrum accents",
  "Nein · keine Regel-ID, Version oder Evaluation geliefert":
      "No · no rule ID, version or evaluation delivered",
  "Network & VPN öffnen": "Open Network & VPN",
  "Network Compare öffnen · {0} ausgewählt":
      "Open Network Compare · {0} selected",
  "Network Explorer öffnen · Modulziel, kein ID-Deep-Link":
      "Open Network Explorer · Module target, no ID-deep link",
  "Network-Vergleich leeren": "Clear network comparison",
  "Netzwerk": "Network",
  "Netzwerk & VPN": "Network & VPN",
  "Netzwerk untersuchen": "Inspect network",
  "Netzwerk-Interfaces (vom Host gemeldet): {0}":
      "Network interfaces (reported by the host): {0}",
  "Netzwerkbeziehungen & Evidence": "Network connections & evidence",
  "Netzwerkknoten bleiben sichtbar, wenn für sie keine frischen Verbindungsdaten vorliegen.":
      "Network nodes remain visible if they do not have fresh connection data.",
  "Neuer Wert": "New value",
  "Neuere Einträge laden": "Load newer entries",
  "Neueste zuerst": "Latest first",
  "Neutral dunkel · reduzierte Farbwirkung": "Neutral dark · muted colors",
  "Nicht ableitbar": "Cannot be inferred",
  "Nicht abonniert · gezielte API-Einzelabfrage":
      "Not subscribed · on-demand API read",
  "Nicht autorisiert / nicht mehr vorhanden":
      "Unauthorized / no longer available",
  "Nicht autorisiert geliefert": "No authorized record available",
  "Nicht deklariert": "Not declared",
  "Nicht durchgeführt": "Not performed",
  "Nicht eindeutig geliefert": "Not clearly indicated",
  "Nicht erreichbar": "Unreachable",
  "Nicht erreichbar · reported": "Unreachable · reported",
  "Nicht geliefert": "Not provided",
  "Nicht geliefert / nicht zutreffend": "Not delivered/not applicable",
  "Nicht geliefert · keine Zeitsynchronisation behauptet":
      "Not delivered · no time synchronization claimed",
  "Nicht gelieferte Attribute ausdrücklich kennzeichnen":
      "Explicitly identify attributes not delivered",
  "Nicht gemessen": "Not measured",
  "Nicht im Legacy-DTO enthalten": "Not included in Legacy DTO",
  "Nicht im Link-DTO enthalten": "Not included in the link DTO",
  "Nicht im Management-Vertrag geliefert":
      "Not delivered in management contract",
  "Nicht im Tailscale-Netz": "Outside the Tailscale network",
  "Nicht im autorisierten v1-Vertrag verfügbar":
      "Not available in the authorized v1 contract",
  "Nicht projiziert": "Not projected",
  "Nicht separat verfügbar; Registry Connection Type oben":
      "Not available separately; Registry Connection Type above",
  "Nicht verfügbar": "Unavailable",
  "Nicht verfügbar · keine BrowseReferences-Capability":
      "Not available · no BrowseReferences capability",
  "Nicht verfügbar: {0}": "Not available: {0}",
  "Nicht verifiziert · keine Root-Cause-Behauptung":
      "Not verified · no root-cause claim",
  "Nicht vom Core geliefert": "Not delivered by the core",
  "Nicht vom Server geliefert": "Not delivered by the server",
  "Nicht von API geliefert": "Not supplied by API",
  "Nicht zugeordnet": "Unassigned",
  "Nicht zuordenbar": "Cannot be associated",
  "Nicht zutreffend": "Not applicable",
  "Nicht „Secure for Production“": "Not “Secure for Production”",
  "Noch kein persistierter Diagnoselauf. Die aktuellen Demo-Befunde werden vom Rust-Backend erzeugt.":
      "The current demo findings are generated by the rust backend.",
  "Noch keine Engineering-Auswahl": "No engineering selection yet",
  "Noch keine Nodes im Vergleich": "No nodes yet in comparison",
  "Noch keine Panels": "No panels yet",
  "Noch keine aktuellen Messwerte. Verifizierung allein ist kein kontinuierliches Monitoring.":
      "Verification alone is not continuous monitoring.",
  "Node auswählen": "Select node",
  "Node im Inspector mit C oder der Vergleichs-Aktion hinzufügen. Pins und Vergleiche bleiben sitzungslokal; es werden keine Benutzerpräferenzen im Core gespeichert.":
      "Add node in the Inspector with C or the Compare action. Pins and comparisons remain session-local; no user preferences are stored in the core.",
  "Node suchen": "Find a node",
  "Node-Suche fokussieren · Shortcut /": "Focus node search · shortcut /",
  "Node-Vergleich": "Node comparison",
  "Node-Vergleich öffnen · {0}/{1}": "Open Node Comparison · {0}/{1}",
  "Node-Wert & technische Attribute": "Node value & technical attributes",
  "NodeId kopieren": "Copy NodeId",
  "NodeId kopiert": "NodeId copied",
  "Nodes durchsuchen": "Search for nodes",
  "Normal {0} · Warnung {1} · Kritisch {2}":
      "Normal {0} · Warning {1} · Critical {2}",
  "Normalbetrieb liefert bewusst keinen Incident. Es wird kein Befund für visuelle Vollständigkeit erzeugt.":
      "Normal operation deliberately does not produce an incident; no result for visual completeness is generated.",
  "Null-Dauer und Recovery": "Zero Duration and Recovery",
  "Numerisch": "Numeric",
  "Nur Inventar, keine Verbindung": "Inventory only, no connection",
  "Nur Inventar: Registered · Connectivity Unknown · Telemetry NoCollector · Health NotEvaluated. Es wird keine Verbindung aufgebaut.":
      "Inventory only: Registered · Connectivity Unknown · Telemetry NoCollector · Health NotEvaluated.",
  "Nur aktuell verfügbare Ereignisse": "Only currently available events",
  "Nur aktuell verfügbare Ereignisse; kein Replay und keine vollständige Serverhistorie":
      "Only currently available events; no replay and no complete server history",
  "Nur bereits vorhandene autorisierte v1-Snapshot-Daten. Keine konkurrierende Geräteverwaltung.":
      "Only pre-existing authorized v1 snapshot data. No competing device management.",
  "Nur diese UI-Sitzung": "Current session only",
  "Nur dokumentierte Gap-Marker. Ein Intervall mit Länge null beweist keine Kontinuität; Unknown bleibt von gesund, gestört und unsupported getrennt.":
      "A zero-length interval proves no continuity; Unknown remains separated from healthy, disturbed, and unsupported.",
  "Nur im Inventar registrieren": "Register only in inventory",
  "Nur lesend": "Read-only",
  "Nur offline administrierbar": "Managed offline only",
  "Nur tatsächlich autorisierte Rows · keine globale Health-Severity · Unknown ≠ Offline · NoCollector ≠ Fehler":
      "Only actually authorized rows · no global health-severity · Unknown ≠ Offline · NoCollector ≠ Errors",
  "Nur tatsächlich beobachtete Transitionen gemäß Core-Report":
      "Only actually observed transitions according to Core report",
  "Nur zeitgestempelte Collection-Ereignisse · zeitliche Nähe beweist keine Ursache":
      "Only time-stamped collection events · time proximity proves no cause",
  "Nächste Geräte": "Next devices",
  "Nächste Nodes": "Next Nodes",
  "Nächstes Sample": "Next sample",
  "OIP-Server meldet einen Fehler.": "OIP server reports an error.",
  "OIP-Server nicht erreichbar.": "OIP server unreachable.",
  "OPC UA: separater autorisierter Source-Provisioning-Pfad. SNMP, Windows, Android und VPN-Monitoring sind hier nicht implementiert.":
      "OPC UA: separate authorized source provisioning path. SNMP, Windows, Android and VPN monitoring are not implemented here.",
  "OPC-UA nicht zuordenbar": "OPC-UA not attributable",
  "OPC-UA untersuchen": "Inspect OPC UA",
  "OPC-UA-Browser": "OPC UA Browser",
  "OPC-UA-Browser öffnen · Source-Modul, kein Node-Deep-Link":
      "Open OPC UA browser · Source module, no node-deep link",
  "OPC-UA-Nodes konnten nicht geladen werden. Bitte erneut versuchen.":
      "OPC UA nodes could not be loaded.",
  "OPC-UA-Wert schreiben": "Write OPC UA value",
  "Observed Evidence, regelbasierte Befunde und Hypothesen bleiben getrennt. Dieser Incident enthält freie Evidenztexte und keine autoritative Regel-Evaluation.":
      "Observed evidence, rule-based findings and hypotheses remain separate. This incident contains free evidence texts and no authoritative rule evaluation.",
  "Onboarding schließen": "Close onboarding",
  "OpenWrt liefert echte SSH-Messwerte für seine unterstützten Systemdaten.":
      "OpenWrt delivers real SSH metrics for its supported system data.",
  "Operator abmelden": "Sign out",
  "Operator-Hinweise öffnen": "Open Operator Instructions",
  "Operator-Sitzung autorisieren": "Authorize operator session",
  "Optionaler autorisierter Hostalias": "Optional authorized host alias",
  "Ordner": "Folder",
  "Ordner des gelieferten Adressraums": "Folder of the delivered address space",
  "Ordner sind die Parent-Namen des Adressraums des Servers. Parent, Children und BrowseReferences werden nicht geliefert; deshalb zeigt OIP keinen erfundenen Baum.":
      "Folders are the parent names of the address space of the server. Parent, Children and BrowseReferences are not delivered; therefore, OIP does not show an invented tree.",
  "Ordner · Parent im Adressraum des Servers":
      "Folder · Parent in the address space of the server",
  "Organisation": "Organization",
  "Organization, Infrastructure, Site oder Source …":
      "Organization, Infrastructure, Site or Source...",
  "Originalwert kopiert": "Original value copied",
  "Overview öffnen · Modulziel, kein Device-Deep-Link":
      "Open Overview · Module target, no device-deep link",
  "Panel hinzufügen": "Add panel",
  "Permission {0}: {1}. Berechtigung {2}":
      "Permission {0}: {1}. Authorization {2}",
  "Persistierte Evidenz nicht verfügbar": "Persisted evidence not available",
  "Persistierte Messhistorie": "Persistent measurement history",
  "Persistierte Zahl: kein Zeitraum- oder Tenant-Aggregat; ermittelt {0}. Fehlende Werte werden nicht als 0 dargestellt.":
      "Persisted number: no time period or tenant aggregate; determined {0}.",
  "Persönliche Dashboards lassen sich je Benutzer und Infrastruktur zusammenstellen.":
      "Personal dashboards can be put together for each user and infrastructure.",
  "Persönliche Live-Panels für diesen Infrastrukturkontext öffnen":
      "Open your live panels for this infrastructure",
  "Pfad": "Path",
  "Pfad aus Vergleich entfernen": "Remove path from comparison",
  "Pfad aus Vergleich entfernen (C)": "Remove path from comparison (C)",
  "Pfad vergleichen": "Compare the path",
  "Pfad zum Vergleich hinzufügen (C)": "Add path for comparison (C)",
  "Pfeile Auswahl · Enter Inspector · P Pin · C Compare\nRelation unbekannt ist nicht offline oder isoliert":
      "Arrows Selection · Enter Inspector · P Pin · C Compare Relation unknown is not offline or isolated",
  "Pfeile Auswahl · Enter Inspector · P Pin · C Compare\nSeverity wird von dieser API nicht geliefert":
      "Arrows Selection · Enter Inspector · P Pin · C Compare Severity is not supplied by this API",
  "Pfeile Auswahl · Enter öffnet Zeile · reported ≠ gemessen":
      "Arrows Selection · Enter opens row · reported ≠ measured",
  "Pfeile/Home/End · Enter öffnet · P Pin · C Compare":
      "Arrows/Home/End · Enter opens · P Pin · C Compare",
  "Pin entfernen (P)": "Remove pin (P)",
  "Pinnen": "Pin",
  "Principal: {0} · keine Credentials in URL oder LocalStorage":
      "Principal: {0} · no credentials in URL or LocalStorage",
  "Prüfung läuft": "Check in progress",
  "QUALITÄT / FRESHNESS": "QUALITY / FRESHNESS",
  "QUALITÄT {0}": "QUALITY {0}",
  "Quality-Bedeutung": "Quality significance",
  "Quality-Wechsel": "Quality change",
  "Qualität": "Quality",
  "Quelle": "Source",
  "Quelle nicht angegeben": "Source not specified",
  "Quelle nicht geliefert": "Source not supplied",
  "Quelle unbekannt": "Source unknown",
  "Quelle, Gerät oder Ereignis auswählen.":
      "Select the source, device or event.",
  "Quelle: {0} · {1}": "Source: {0} · {1}",
  "Quellen": "Sources",
  "Quellenliste nicht verfügbar.": "List of sources not available.",
  "Quellenstatus": "Source status",
  "REST lädt den Anfangszustand. SSE liefert danach Änderungen.":
      "REST loads the initial state. SSE then delivers changes.",
  "Offen sind RUSTSEC-2024-0449, die Absicherung externer Browser-Anmeldungen und des lokalen Systemkontos, ein extern abgesichertes Audit und der Nachweis der Betriebssicherheit.":
      "Outstanding items include RUSTSEC-2024-0449, protection for remote browser identities and the local system account, independent audit anchoring and operational safety evidence.",
  "Read + Write · serverseitig freigegeben":
      "Read + Write · Available on the server",
  "Read · lesend": "Read-only",
  "Reale Core-Komposition, lokale stdio-Bridges und Unix-IPC. Kein Remote-MCP-Listener.":
      "Real core composition, local stdio bridges and Unix IPC. No remote MCP listener.",
  "Reale Infrastruktur · lokale Operator-Sitzung":
      "Real infrastructure · local operator session",
  "ReceivedTimestamp · lokale Empfangszeit":
      "ReceivedTimestamp · local reception time",
  "Reconnect gemeldet": "Reconnect reported",
  "Reconnect ist kein Nachweis aktueller oder vollständiger Messwerte":
      "Reconnect is not a proof of current or complete measured values",
  "Reconnect vom Adapter gemeldet": "Reconnect reported by the adapter",
  "Regelbefund": "Rule finding",
  "Registrierte Capability-Anzahl und tatsächliches MCP-Mapping; keine Ausführung über Settings.":
      "Registered capacity number and actual MCP mapping; no execution via settings.",
  "Registry-Gerätedetails öffnen": "Open Registry Device Details",
  "Registry-Mitgliedschaft, SourceHealth, Observations, gemeldete Reachability und Diagnosebefunde bleiben getrennt. Fehlende Services und aktive Probes bleiben unbekannt.":
      "Registry membership, SourceHealth, Observations, reported reachability and diagnostic findings remain separate; missing services and active probes remain unknown.",
  "Relation unbekannt": "Relation Unknown",
  "SESSION-LOCAL · keine Persistenz": "SESSION-LOCAL · no persistence",
  "SSH Verified · Monitoring deaktiviert":
      "SSH Verified · Monitoring deactivated",
  "SSH Verified. Monitoring bleibt deaktiviert.":
      "SSH Verified. Monitoring remains deactivated.",
  "SSH-Abfragen aktualisieren Nachbarschaftsdaten, damit neue Verbindungen erscheinen.":
      "SSH queries update neighborhood data so that new connections appear.",
  "SSH-Abfragen bleiben read-only": "SSH queries remain read-only",
  "SSH-Identität verifiziert und Collector aktiviert. Collecting wird erst nach tatsächlich empfangenen Messwerten angezeigt.":
      "SSH identity verified and Collector activated. Collecting is only displayed after actually received measured values.",
  "SSH-Verbindung testen": "Test SSH connection",
  "Sammle Sitzungswerte …": "Collecting session values …",
  "Sammle Verlauf – mindestens zwei frische Samples erforderlich.":
      "Collect course – at least two fresh samples required.",
  "Sanitized · keine Credentials": "Sanitized · no credentials",
  "Schema kopieren": "Copy schema",
  "Schema wird vom Core geliefert; keine Migration durch Flutter":
      "Schema is supplied by the Core; no migration by Flutter",
  "Schemas gewähren keine Ausführung. Der Core prüft Ziel-Scope und Berechtigung bei jedem Aufruf erneut und liefert strukturierte Capability-Fehler. Diese Workstation führt keine Tools aus.":
      "Schemas do not grant execution. The core rechecks target scope and permissions on each call and delivers structured capability errors. This workstation does not run tools.",
  "Schließen": "Close",
  "Schreiben": "Write",
  "Schreiben benötigt eine autorisierte Infrastruktur-Session.":
      "Writing requires an authorized infrastructure session.",
  "Schreiben fehlgeschlagen: {0}": "Write failed: {0}",
  "Schreiben über den OPC-UA-Browser wird vom Transport nicht unterstützt.":
      "Writing via the OPC-UA browser is not supported by transport.",
  "Schritt {0}/5 · {1}": "Step {0}/5 · {1}",
  "Schwellen- oder Heat-Streifen über die Zeit":
      "Threshold or heat strip over time",
  "Security-Blocker werden vom Server geladen":
      "Security blockers are loaded from the server",
  "Security-Blocker: an diese Sitzung nicht geliefert":
      "Security blocker: not delivered to this session",
  "Segmentierter Balken": "Segmented bar",
  "Seite {0} / {1}": "Page {0} / {1}",
  "Seitenfilter für Typ und Quality": "Side filters for type and quality",
  "Seitenfilter zurücksetzen": "Reset side filters",
  "Seitenweise gelesen · die Messung entsteht im Kollektor":
      "Read side by side · the measurement is produced in the collector",
  "Server nicht erreichbar": "Server unreachable",
  "Server → Empfang · inkl. Uhrendifferenz":
      "Server → Reception · incl. clock difference",
  "Server-Suche: Browse-Name des Servers · gesamte ausgewählte Quelle. Typ/Quality: nur geladene Seite.":
      "Server search: server browse name · entire selected source. Type/Quality: page loaded only.",
  "Serverseitiger Historienendpunkt noch nicht implementiert. Der Overview zeigt ausschließlich empfangene Sitzungspunkte.":
      "Server-side history endpoint not yet implemented; the Overview shows only received session points.",
  "Serververbindung prüfen.": "Check the server connection.",
  "Service-Paginierung ist inkonsistent.":
      "Service pagination is inconsistent.",
  "Service-Provenienz weicht vom Snapshot ab.":
      "Service provenance deviates from the snapshot.",
  "Service-Registry überschreitet den Core-Bound.":
      "Service registry exceeds the core bound.",
  "Session-Verlauf · {0} Samples seit Öffnen des Dashboards · keine persistierte Historie":
      "Session history · {0} Samples since opening the dashboard · no persistent history",
  "Session-lokal · keine persistierte History · Linien nur zwischen gültigen, zeitnahen Samples ohne belegte Gap. Freshness folgt dem Core, nicht der virtuellen Wanduhr.":
      "Session-local · no persisted history · lines only between valid, timely samples with no occupied gap. Freshness follows the core, not the virtual wall clock.",
  "Session-lokaler Signalverlauf, {0} von {1} Samples, Zoom {2}-fach, {3}, Minimum {4}, Maximum {5}":
      "Session-local signal curve, {0} of {1} samples, zoom {2}-fold, {3}, minimum {4}, maximum {5}",
  "Setting oder Tool auswählen. Der Inspector zeigt nur gelieferte Vertragsdaten, Permission-Grenzen und konkrete Backend-Anforderungen.":
      "The Inspector shows only supplied contract data, permission limits and specific back-end requirements.",
  "Setting {0}. Effektiver Wert {1}. Offline Administration Required.":
      "Setting {0}. Effective value {1}. Offline administration required.",
  "Settings-Bereich {0}": "Settings section {0}",
  "Settings-Kategorie {0}": "Settings category {0}",
  "Settings-Read wird von diesem API-Client nicht unterstützt.":
      "Settings Read is not supported by this API client.",
  "Simuliert": "Simulated",
  "Simuliertes Gerät zur Vorschau hinzufügen.":
      "Add a simulated device to the preview.",
  "Sitzungswerte als Säulen": "Session values as columns",
  "Skala automatisch": "Automatic scale",
  "Skala und Schwellen sind reine Darstellung dieses Panels. Leere Felder: automatische Skala bzw. keine Schwelle.":
      "Scale and thresholds are a pure representation of this panel. Empty fields: automatic scale or no threshold.",
  "Snapshot erzeugt": "Snapshot generated",
  "Snapshot nicht verfügbar": "Snapshot is not available",
  "Sonstige": "Other",
  "Source Health · nicht mit Device Health gleichsetzen":
      "Source Health does not equate with Device Health",
  "Source ID kopieren": "Copy source ID",
  "Source nicht im aktuellen Datenumfang":
      "Source not in the current data scope",
  "Source nicht projiziert": "Source not projected",
  "Source unbekannt": "Source unknown",
  "Source und Nodes aktualisieren": "Refresh source and nodes",
  "Source {0} {1} auswählen · {2} Signale · {3} · {4}":
      "Select Source {0} {1} · {2} Signals · {3} · {4}",
  "Source, Gerät, Typ …": "Source, device, type ...",
  "Source, dann Zeit": "Source, then time",
  "Source-Diagnostik & dokumentierte Datenlücken":
      "Source diagnostics & documented data gaps",
  "Source-ID kopieren": "Copying the source ID",
  "Source-Umfang überschreitet den UI-Bound.":
      "Source scope exceeds the UI bound.",
  "Source-Zustände nicht verfügbar": "Source states not available",
  "SourceHealth im aktuellen Datenumfang nicht verfügbar.":
      "SourceHealth is not available in the current data scope.",
  "Sources, Devices und Demo/Real-Modus sind Unknown; keine Nullwerte werden ersetzt.":
      "Sources, Devices and Demo/Real mode are Unknown; no null values are replaced.",
  "Speichern": "Save",
  "Sprache": "Language",
  "Sprache und Darstellung dieser App wählen.":
      "Choose this app’s language and appearance.",
  "Spuren ausblenden": "Hide traces",
  "Spuren zeigen": "Show traces",
  "Standort": "Site",
  "Standort (Site)": "Location (Site)",
  "Standorte": "Sites",
  "Status aktualisieren": "Refresh status",
  "Status unbekannt": "Unknown status",
  "Subscription Error gemeldet": "Subscription Error reported",
  "Subscription-Fehler": "Subscription error",
  "Subscription-Fehler gemeldet": "Subscription error reported",
  "Suche löschen": "Clear search",
  "Suche nach Updates …": "Checking for updates …",
  "Suche oder Filter ändern. Der Core-Katalog bleibt unverändert.":
      "The core catalogue remains unchanged.",
  "Suche oder Filter ändern. Ein leeres Ergebnis bedeutet weder Offline noch Isolation.":
      "An empty result means neither offline nor isolation.",
  "Suche oder Filter ändern. Ein leeres Ergebnis wird nicht als Offline-Zustand interpretiert.":
      "A blank result is not interpreted as an offline state.",
  "Suchen": "Search",
  "Szenariowechsel fehlgeschlagen. Bitte erneut versuchen.":
      "Scenario change failed. Please try again.",
  "Szenariowechsel nicht ausgeführt": "Scenario change not performed",
  "TATSÄCHLICHER EMPFANG": "ACTUAL RECEIPT",
  "TATSÄCHLICHER EMPFANG {0}": "ACTUAL RECEIPT {0}",
  "Tatsächlich gelieferte Verbindungspfade untersuchen":
      "Inspect the reported connection paths",
  "Tatsächlich unterstützte Flutter-Theme-Varianten.":
      "Choose an appearance for this app.",
  "Tatsächlich verifizierte Identität": "Actually Verified Identity",
  "Tatsächlich von GET /api/v1/events empfangenes Collection-Ereignis":
      "Collection event actually received by GET /api/v1/events",
  "Tatsächlich von GET /api/v2/events/history im autorisierten Kontext empfangen":
      "Actually received by GET /api/v2/events/history in an authorized context",
  "Tatsächlicher Fehler": "Actual error",
  "Technisch": "Technical",
  "Technische Diagnoseinformationen kopieren":
      "Copy technical diagnostic information",
  "Technische Evidenz · Read-only": "Technical evidence · Read-only",
  "Technische Fehlerdetails": "Technical error details",
  "Technische OPC-UA-Details": "OPC UA technical details",
  "Technische Storage-Fakten aus dem Management-Read. Datenbankpfade werden nicht exportiert.":
      "Technical storage facts from the management read. database paths are not exported.",
  "Technischer Kontext & Vertragsdetails":
      "Technical context & contract details",
  "Telemetrie": "Telemetry",
  "Telemetrie und OPC-UA-Abfragen verwenden eigene Verbindungen ohne gemeinsam genutzte SSH-Kanäle.":
      "Telemetry and OPC UA queries use their own connections without shared SSH channels.",
  "Theme {0}. Lokale UI-Präferenz.": "Theme {0}. Local preference.",
  "Timeline nach links": "Timeline to the left",
  "Timeline nach rechts": "Timeline to the right",
  "Timeline vergrößern": "Zoom in on timeline",
  "Timeline verkleinern": "Zoom out on timeline",
  "Tool auswählen": "Select tool",
  "Tool, Capability oder Beschreibung": "Tool, capability or description",
  "Tool-Katalog als technische Textansicht kopieren":
      "Copy tool catalogue as a technical text view",
  "Tool-Namen kopieren": "Copy tool names",
  "Tool-Namen {0} kopieren": "Copy tool names {0}",
  "Topologie": "Topology",
  "Topologie einpassen": "Fit topology to view",
  "Touch ID für künftige Anmeldungen einrichten":
      "Set up Touch ID for future sign-ins",
  "Touch ID konnte nicht eingerichtet werden.": "Touch ID setup failed.",
  "Touch ID nicht verfügbar.": "Touch ID is not available.",
  "Touch-ID-Anmeldung fehlgeschlagen.": "Touch ID sign-in failed.",
  "Typ, Source, Sequenz oder Grund": "Type, source, sequence or reason",
  "Typ, dann Zeit": "Type, then time",
  "UI-Transport nicht live": "UI transport not live",
  "Unabhängige Beobachtungskontexte": "Independent observation contexts",
  "Unabhängige EventTimestamps und Quellen. Keine Synchronisation, Interpolation, Incident-ID oder Kausalbehauptung.":
      "Independent EventTimestamps and Sources. No synchronization, interpolation, incident ID or causal claim.",
  "Unabhängige Messzeitpunkte": "Independent measurement times",
  "Unbekannt": "Unknown",
  "Unbekannt / keine Source": "Unknown / No Source",
  "Unbekannt / nicht verfügbar": "Unknown / Unavailable",
  "Unbekannt · kein aktiver Probe ausgeführt": "Unknown · no active probe run",
  "Unbekannte Hierarchieebene.": "Unknown hierarchical level.",
  "Unbekannte Management-Sektion.": "Unknown management section.",
  "Unbekannter Gerätetyp · \$kind": "Unknown device type · \$kind",
  "Unbekannter Host-Key · Bestätigung erforderlich":
      "Unknown host key · Confirmation required",
  "Unbekannter Management-Fehler.": "Unknown management error.",
  "Unbekannter Quality-Code aus der API.": "Unknown quality code from the API.",
  "Unbekannter vom Core gelieferter Ereignistyp":
      "Unknown event type delivered by the core",
  "Unbekanntes Collection-Ereignis": "Unknown collection event",
  "Unbekanntes Modul": "Unknown module",
  "Ungültig": "Invalid",
  "Ungültiger Settings-Scope oder Schlüssel.": "Invalid Settings Scope or Key.",
  "Unified View · gesamter autorisierter Principal-Scope":
      "Unified view · all infrastructure authorized for this identity",
  "Unreachable · tatsächlicher Verbindungsversuch fehlgeschlagen":
      "Unreachable · actual connection attempt failed",
  "Unsicher": "Uncertain",
  "Unveränderliche Core-Regelmetadaten. Keine visuelle Rule Engine und keine KI-Kausalität.":
      "Immutable core rule metadata. No visual rule engine and no AI causality.",
  "Unveränderten API-Wert kopieren": "Copy unchanged API value",
  "Updateangebote warten, wenn macOS gerade Touch ID verwendet.":
      "Update offers wait when macOS is currently using Touch ID.",
  "Ursache und globale Severity nicht geliefert; kein ID-Router-Kontext.":
      "Cause and global severity not delivered; no ID router context.",
  "Ursprung": "Origin",
  "VERBINDUNG PRÜFEN": "TEST CONNECTION",
  "VERWALTUNG · REVISION {0}": "MANAGEMENT · REVISION {0}",
  "VISUALISIERUNG · AUTORISIERTE MESSWERTE":
      "VISUALIZATION · AUTHORIZED METRICS",
  "Valides generisches JSON; Platzhalter erforderlich":
      "Valides generic JSON; placeholder required",
  "Veraltet": "Stale",
  "Veraltet / unbekannt": "Stale / unknown",
  "Verbindung & Monitoring": "Connection and monitoring",
  "Verbindung für dieses Gerät einrichten": "Set up connection for this device",
  "Verbindung und Datenaktualität": "Connection and data freshness",
  "Verbindung und Monitoring werden über die autorisierte Core-Verwaltung eingerichtet. Auf dem Gerät wird nichts installiert oder konfiguriert. Fehlende Messwerte bleiben unbekannt.":
      "Connection and monitoring are set up via the authorized core management, nothing is installed or configured on the device, and missing metrics remain unknown.",
  "Verbindung verloren": "Connection lost",
  "Verbindung wiederhergestellt": "Connection restored",
  "Verbindung wird aufgebaut": "Connecting",
  "Verbindung zum lokalen OIP-Server": "Connection to local OIP server",
  "Verbindung {0} nach {1}, {2}, Status {3}":
      "Connection {0} to {1}, {2}, status {3}",
  "Verbindungsinformationen nicht zugänglich.":
      "Connection information not accessible.",
  "Verbindungsmethode": "Connection method",
  "Verbindungsmethode wählen": "Select the connection method",
  "Verbindungspfad {0} nach {1}, {2}, {3}, RTT {4}, Loss {5}":
      "Connection path {0} to {1}, {2}, {3}, RTT {4}, Loss {5}",
  "Verbindungsstatus konnte nicht gelesen werden.":
      "Connection status could not be read.",
  "Verbindungsstatus unbekannt": "Connection status unknown",
  "Verbindungsverlust vom Adapter gemeldet":
      "Connection loss reported by the adapter",
  "Verbunden": "Connected",
  "Verfügbare Metriken": "Available Metrics",
  "Vergleich ausklappen": "Expand comparison",
  "Vergleich einklappen": "Collapse comparison",
  "Vergleich leeren": "Clear comparison",
  "Vergleich schließen": "Close the comparison",
  "Vergleich schließen (Esc)": "Close the Comparison (ESC)",
  "Vergleiche diese Informationen mit deinem erwarteten Gerät. Ein gleicher Anzeigename ist kein Identitätsnachweis.":
      "Compare this information to your expected device, and the same display name is not proof of identity.",
  "Vergleiche diesen Fingerprint über einen unabhängigen vertrauenswürdigen Weg mit dem Zielgerät. Der Handshake allein beweist keine Geräteidentität.":
      "Compare this fingerprint with the target device through an independent trusted path, and the handshake alone does not prove device identity.",
  "Vergleichen": "Compare",
  "Vergrößern": "Zoom in",
  "Verification complete · tatsächlich gelesene Geräteidentität":
      "Verification complete · Actually read device identity",
  "Verifikation fehlgeschlagen · Identität nicht bestätigt":
      "Verification failed · Identity not confirmed",
  "Verkleinern": "Zoom out",
  "Verlauf": "History",
  "Version und Build sind in der Seitenleiste sichtbar.":
      "The version and build are visible in the sidebar.",
  "Versionen & Updates": "Versions & Updates",
  "Versionshinweise": "Release notes",
  "Versionshinweise öffnen. Version {0}, Build {1}":
      "Open release notes. Version {0}, build {1}",
  "Verteilung der Sitzungswerte": "Distribution of session values",
  "Verteilung · {0} Samples": "Distribution · {0} Samples",
  "Vertikaler Füllstand": "Vertical level",
  "Verwaltung nicht verfügbar": "Management not available",
  "Volle Zeile": "Full row",
  "Vollständige Timeline mit Source-Lanes direkt öffnen":
      "Open the full timeline with source lanes",
  "Vom Core als uneingeschränkt nutzbar geliefert.":
      "Delivered from the core as fully usable.",
  "Vom Core als ungültig markiert; CollectionError prüfen.":
      "Marked as invalid by the core; check CollectionError.",
  "Vom Core als unsicher markiert; Wert mit Vorsicht lesen.":
      "Marked by the core as unsafe; read value with caution.",
  "Vom OPC-UA-Server nicht freigegeben": "Not permitted by the OPC UA server",
  "Vor Verwendung ersetzen": "Replace before use",
  "Vorgang fehlgeschlagen. Es wurde keine erfolgreiche Verbindung bestätigt.":
      "Process failed. No successful connection was confirmed.",
  "Vorhanden; Dauer unbekannt/inkonsistent":
      "Presence; duration unknown/inconsistent",
  "Vorhandene Eventtypen": "Existing event types",
  "Vorhandene deterministische History-/Evidence-Verträge; keine Retention- oder Root-Cause-Funktion.":
      "Existing deterministic history/evidence contracts; no retention or root cause function.",
  "Vorher / gleichzeitig / danach ist keine bestätigte Korrelation und keine Ursache":
      "Before/simultaneously/after there is no confirmed correlation and no cause",
  "Vorherige Geräte": "Previous devices",
  "Vorherige Nodes": "Previous nodes",
  "Vorheriges Sample": "Previous sample",
  "WEITERE AUTORISIERTE EREIGNISSE VORHANDEN":
      "FURTHER AUTHORISED EVENTS EXIST",
  "Warnung": "Warning",
  "Wartet auf Daten": "Waiting for data",
  "Weder eine exakte Device-ID- noch eine Source-ID-Beziehung ist im aktuellen Ereignisfenster vorhanden.":
      "Neither an exact device ID nor a source ID relationship exists in the current event window.",
  "Weiter": "Next",
  "Weitere Einträge liegen vor, die Fortsetzung ist derzeit nicht abrufbar.":
      "Further entries are available, the continuation is currently not available.",
  "Weitere Ereignisse laden": "Load more events",
  "Weitere Filter": "Other filters",
  "Wenn der Live-Stream stockt, lädt die Mac-App den aktuellen Stand über dieselbe Anmeldung nach.":
      "If the live stream stops, the Mac app loads the current status via the same login.",
  "Wert passt nicht zum OPC-UA-Datentyp.":
      "Value does not match the OPC-UA data type.",
  "Wert schreiben": "Write value",
  "Werte werden nebeneinander gezeigt, nicht zeitlich synchronisiert. Es gibt keine Interpolation, Einheitenumrechnung oder Differenzbildung. Zeitstempel und Provenienz gelten jeweils nur für ihre eigene Spalte.":
      "Values are shown side by side, not synchronized in time. There is no interpolation, unit conversion or difference formation. Timestamp and provenance apply only to their own column.",
  "Wissenschaft": "Science",
  "Wähle eine Variable aus dem Adressraum.":
      "Select a variable from the address space.",
  "Zeigt bekannte Geräte und ihre gemeldeten Verbindungen. Führt keine Netzwerkscans aus.":
      "Shows known devices and their reported connections. It does not scan the network.",
  "ZEITBASIS · EVENT TIMESTAMP / SERVER WALL CLOCK · UTC\n{0}/{1} zeitgestempelte Ereignisse im Viewport · {2} ohne Zeitstempel nur im Explorer":
      "ZEITBASIS · EVENT TIMESTAMP / SERVER WALL CLOCK · UTC {0}/{1} time stamped events in the viewport · {2} without time stamp only in the Explorer",
  "Zeit- und Herkunftssemantik": "Semantics of time and origin",
  "Zeitbereich · Quellzeit": "Time domain · Source time",
  "Zeitraum verkleinern": "Zoom in on time range",
  "Zeitraum zurücksetzen": "Reset time period",
  "Zeitstempel": "Timestamp",
  "Zentrale, read-only Permission-Matrix. Keine Selbstfreigabe und keine Rollenableitung.":
      "Central, read-only permission matrix. No self-release and no role derivation.",
  "Zu Compare hinzufügen": "Add to Compare",
  "Zugriff nach Serverrechten": "Access by server rights",
  "Zuletzt ausgewählt: {0}": "Last selected: {0}",
  "Zuletzt betrachtet": "Recently viewed",
  "Zuletzt {0}": "Last {0}",
  "Zuletzt {0}, Quelle {1}": "Last {0}, Source {1}",
  "Zuletzt: {0}": "Lastly, {0}",
  "Zum Anfang": "Go to start",
  "Zum Bearbeiten anmelden und eine Infrastruktur auswählen.":
      "Sign up for editing and select an infrastructure.",
  "Zum Ende": "Go to end",
  "Zum Geräteinventar": "Go to device inventory",
  "Zum Vergleich hinzufügen (C)": "Add to comparison (C)",
  "Zur Operations-Übersicht zurückkehren": "Return to the operations overview",
  "Zurück": "Back",
  "Zustand": "Condition",
  "Zustandsdimensionen getrennt": "State dimensions separately",
  "active_startup_snapshot beschreibt den laufenden Snapshot. persisted_requires_restart wäre ein Offline-Ergebnis, kein aktiver Runtime-Wert. Ein exakter Scope-Datensatz und ein geerbter effektiver Wert sind nicht dasselbe.":
      "active_startup_snapshot describes the running snapshot. persisted_requires_restart would be an offline result, not an active runtime value.",
  "expected_revision bezieht sich beim Offline-CLI auf den exakten Scope-Datensatz (0 bei Abwesenheit), nicht auf eine geerbte effective_revision. Die UI führt keine Mutation aus.":
      "expected_revision in the offline CLI refers to the exact scope dataset (0 in the absence), not to an inherited effective_revision.",
  "gestoppt (deklariert)": "stopped (declared)",
  "keine Source": "No source",
  "läuft (deklariert)": "running (declared)",
  "oip-server --browser-login --ipc-socket <privater Socket> --ipc-credential <eigenes autorisiertes Profil>":
      "oip-server --browser-login --ipc-socket <private socket> --ipc-credential <your authorized profile>",
  "v1-Snapshot · Filter nicht serverseitig":
      "v1-Snapshot · Filter not server-sided",
  "v2 autorisierter Scope · UI-Auswahl ist Präsentationsfilter":
      "v2 authorized scope · UI selection is presentation filter",
  "vom Core nicht geliefert": "Not delivered by the core",
  "vom Core nicht geliefert / Session-Vertrag offen":
      "Not delivered by the core / session contract open",
  "von {0}": "from {0}",
  "{0}\nErreichbarkeit {1} · Dienst {2} · Telemetrie {3}":
      "{0} Accessibility {1} · Service {2} · Telemetry {3}",
  "{0}\n{1} · {2}\nErreichbarkeit: {3}\nTelemetrie: {4}\n{5}":
      "{0} {1} · {2} Accessibility: {3} Telemetry: {4} {5}",
  "{0} Angezeigte Events sind der letzte erfolgreiche, jetzt stale Stand.":
      "{0} Shown events are the last successful, now stale stand.",
  "{0} Collection-Records · aktuelles begrenztes API-Fenster{1}":
      "{0} Collection records · current limited API window{1}",
  "{0} Dienste deklariert": "{0} Services declared",
  "{0} Geräte": "{0} Devices",
  "{0} Geräte im v1-Snapshot": "{0} Devices in the v1 snapshot",
  "{0} Nodes im Scope": "{0} Nodes in the scope",
  "{0} Nodes · Seite {1}": "{0} Nodes · Page {1}",
  "{0} Panels · {1} gelieferte Messpunkte · persönliches Layout":
      "{0} Panels · {1} delivered measurement points · personal layout",
  "{0} Pins/Compare sitzungslokal · Read-only · keine Shell-, VPN- oder Netzwerksteuerung.":
      "{0} Pins/Compare meeting location · Read-only · no shell, VPN or network control.",
  "{0} Punkte · {1}": "{0} Points · {1}",
  "{0} Spalten": "{0} columns",
  "{0} aus Vergleich entfernen": "Remove {0} from comparison",
  "{0} bis {1}\nVisuelle Gruppe · keine Korrelation oder Ursache":
      "{0} to {1} Visual group · no correlation or cause",
  "{0} dauerhaft für diese Sitzung öffnen": "Keep {0} open for this session",
  "{0} erreichbar · nicht aktiv gemessen":
      "{0} reachable · no active measurement",
  "{0} exakt zugeordnet": "{0} Exactly assigned",
  "{0} geliefert": "{0} Delivered",
  "{0} im aktuellen Snapshot": "{0} in the current snapshot",
  "{0} im begrenzten aktuellen Fenster": "{0} in the limited current window",
  "{0} kopiert": "{0} Copied",
  "{0} kopiert.": "{0} copied.",
  "{0} kopiert: {1}": "{0} copied: {1}",
  "{0} loslösen": "Unpin {0}",
  "{0} registrierte Tools aus dem autorisierten Core-Mapping. Sichtbarkeit ist keine Ausführungsfreigabe.":
      "{0} registered tools from the authorized core mapping. Visibility is not an execution release.",
  "{0} registrierte Tools geliefert": "{0} Registered tools delivered",
  "{0} schließen": "Close {0}",
  "{0} vergleichen": "Compare {0}",
  "{0} von {1} Geräten · {2}": "{0} of {1} devices · {2}",
  "{0} von {1} Tools · Filter wirken nur auf den gelieferten Katalog":
      "{0} from {1} Tools · Filters only affect the delivered catalog",
  "{0} wurde geschrieben.": "{0} was written.",
  "{0} zeitnahe Ereignisse": "{0} timely events",
  "{0} {1} · {2} · {3} {4} · Tatsächlicher Empfang {5}":
      "{0} {1} · {2} · {3} {4} · Actual reception {5}",
  "{0} · REPORTED, nicht gemessen": "{0} · REPORTED, not measured",
  "{0} · Skala automatisch": "{0} · Scale automatically",
  "{0} · als ein Record konsolidiert": "{0} · consolidated as a record",
  "{0} · exakte Device-ID · {1} · keine Severity/Kausalität abgeleitet":
      "{0} · exact device ID · {1} · no severity/causality derived",
  "{0} · keine realen Ereigniszeiten": "{0} · no real event times",
  "{0} · vom Core für dieses Ereignis geliefert":
      "{0} · Delivered by the Core for this event",
  "{0} · {1}\nDaten: {2} · Reachability: {3} (reported)":
      "{0} · {1} Data: {2} · Reachability: {3} (reported)",
  "{0} · {1} · Empfang {2} · {3} dokumentierte Gaps im aktuellen Fenster · keine History-Behauptung":
      "{0} · {1} · Reception {2} · {3} documented gaps in the current window · no history claim",
  "{0} · {1} · {2}\nSource-Ereignis, nicht automatisch ein Device-Incident{3}":
      "{0} · {1} · {2} Source event, not automatically a device incident{3}",
  "{0}/4 Ereignisse · session-lokal": "{0}/4 Events · session-local",
  "{0}/4 Geräte · {1}/4 Pfade · sitzungslokal":
      "{0}/4 devices · {1}/4 paths · current session",
  "{0}/4 · quellenbezogen · sitzungslokal":
      "{0}/4 · scoped to source · current session",
  "{0}/{1} Geräte": "{0}/{1} devices",
  "{0}/{1} auf dieser Seite": "{0}/{1} on this page",
  "{0}/{1} im geladenen Fenster": "{0}/{1} in the loaded window",
  "{0}: Antwort gekürzt; keine Fortsetzung verfügbar.":
      "{0}: Answer shortened; no continuation available.",
  "{0}: alle": "{0}: all",
  "{0}: weitere Einträge laden": "{0}: loading further entries",
  "{0}Nur bestätigte logische Snapshot-Pfade · keine physische Verkabelung. +/− Zoom · F Fit · 0 Reset · Pfeile Auswahl.":
      "{0}Only confirmed logical snapshot paths · no physical wiring. +/− Zoom · F Fit · 0 Reset · Arrows selection.",
  "Älteste zuerst": "Oldest first",
  "Änderung nicht angenommen": "Change rejected",
  "Änderungen speichern": "Save changes",
  "Änderungsprotokoll": "Changelog",
  "Übernehmen": "Apply",
  "Überschrift": "Heading",
  "Überschrift zum Gliedern": "Heading to organize the dashboard",
  "Übersicht": "Overview",
  "Überwachung konfiguriert · noch keine Messwerte empfangen":
      "Monitoring configured · not yet receiving measured values",
};

const germanMessages = <String, String>{
  "About": "Über die App",
  "Allowed Scopes": "Erlaubte Geltungsbereiche",
  "Appearance & Preferences": "Erscheinungsbild & Sprache",
  "Apply Mode": "Anwendungsmodus",
  "Apply Status": "Anwendungsstatus",
  "Arguments": "Argumente",
  "Audit & Security": "Audit & Sicherheit",
  "Authenticating": "Anmeldung läuft",
  "Authorize a managed operator session to open actions permitted for its scope.":
      "Melde dich als Operator an, um die freigegebenen Aktionen zu nutzen.",
  "Availability": "Verfügbarkeit",
  "Available": "Verfügbar",
  "Available Metrics": "Verfügbare Messwerte",
  "CLIENT IDENTITY": "CLIENT-IDENTITÄT",
  "CLIENT LOCAL": "LOKAL AUF DIESEM GERÄT",
  "CREDENTIAL SOURCE": "QUELLE DER ZUGANGSDATEN",
  "Capability": "Fähigkeit",
  "Change Channel": "Änderungskanal",
  "Classification": "Klassifikation",
  "Client Configuration": "Client-Konfiguration",
  "Client Sessions": "Client-Sitzungen",
  "Clock Uncertainty": "Zeitunsicherheit",
  "Collection Error": "Erfassungsfehler",
  "Collection State": "Erfassungsstatus",
  "Config Contract": "Konfigurationsvertrag",
  "Connection Diagnostics": "Verbindungsdiagnose",
  "Connection State": "Verbindungsstatus",
  "Connection Test": "Verbindungstest",
  "Context / Help": "Kontext / Hilfe",
  "Context Inspector": "Kontextinspektor",
  "Copy CLI Template": "CLI-Vorlage kopieren",
  "Core Capabilities": "Core-Fähigkeiten",
  "Current Identity": "Aktuelle Identität",
  "Current Principal": "Aktuelle Identität",
  "Data Source": "Datenquelle",
  "Diagnostic Rules": "Diagnoseregeln",
  "Effective Permissions": "Effektive Berechtigungen",
  "General": "Allgemein",
  "Health History": "Zustandsverlauf",
  "Historical Data": "Historische Daten",
  "History Limits": "Grenzen der Historie",
  "Inventory registration and updates, SSH onboarding and monitoring configuration are available when permitted by the current scope. Telemetry is collector-owned; OPC-UA writes require server-reported ReadWrite access and an authorized scope.":
      "Geräteinventar, SSH-Einrichtung und Überwachung stehen im berechtigten Bereich zur Verfügung. Die Telemetrie stammt aus der Datenerfassung. OPC-UA-Schreibzugriffe erfordern ReadWrite am Server und eine passende Berechtigung.",
  "Last Seen": "Zuletzt gesehen",
  "Last Updated": "Zuletzt aktualisiert",
  "No data available.": "Keine Daten verfügbar.",
  "Operator actions · Self-hosted": "Operator-Aktionen · Eigenbetrieb",
  "Permissions & Scopes": "Berechtigungen & Geltungsbereiche",
  "Retention": "Aufbewahrung",
  "Server preference synchronization": "Synchronisierung mit dem Core",
  "Settings navigation": "Einstellungsnavigation",
  "Sign in to manage · Self-hosted": "Anmeldung zur Verwaltung · Eigenbetrieb",
  "Simulation only; no real infrastructure changes.":
      "Die Simulation verändert keine reale Infrastruktur.",
  "Simulation · Self-hosted": "Simulation · Eigenbetrieb",
  "Source & Device": "Quelle & Gerät",
  "Status unknown": "Status unbekannt",
  "System Runtime": "Systemlaufzeit",
  "Tools & Capabilities": "Werkzeuge & Fähigkeiten",
  "Unavailable": "Nicht verfügbar",
  "Value Format": "Werteformat",
  "WORKSPACE / LOCAL LAB": "ARBEITSBEREICH / LOKALE INSTANZ",
};
