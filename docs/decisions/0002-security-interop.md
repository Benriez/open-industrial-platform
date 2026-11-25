# ADR 0002: Security, Interoperabilität und Evidenzpersistenz

Status: accepted für die lokale OIP-002-Testumgebung, 2026-11-04. **Keine Freigabe realer Industrieanlagen.**

## Kontext

OIP-001 nutzte ausschließlich `SecurityPolicy=None` und hatte einen offenen Forward-Interop-Fehler. async-opcua 0.19.0 erzeugte bei `ActivateSession` unter Policy None eine leere Session-Nonce. open62541 1.5.10 lehnte sie mit `BadSecurityChecksFailed` ab. Die reproduzierte Logmeldung lautet „Session cannot be activated with a nonce that is too short“.

## Entscheidungen

1. **Production:** ausschließlich `Basic256Sha256` mit `SignAndEncrypt`. Client und Server benötigen absolute, explizite PKI-Wurzeln, eigene Zertifikate/Schlüssel und ein `trusted`-Verzeichnis. Eigene Zertifikate und Schlüssel werden vor dem Verbindungsaufbau geparst; Zertifikate werden zeitvalidiert. `trust_server_certs(false)`, `trust_client_certs(false)`, `verify_server_certs(true)` und `check_cert_time(true)` bleiben aktiv. Es gibt kein automatisches Trust-on-first-use und keine Rückstufung auf None.
2. **Adressen:** nur numerische IP-Literale. Simulation ist auf `127.0.0.1`/`::1` beschränkt; der mitgelieferte Server bindet tatsächlich an `127.0.0.1`. Hostnamen und `localhost` werden ohne DNS-Auflösung abgelehnt, wodurch DNS-Rebinding die geprüfte Adresse nicht verändern kann.
3. **Interop:** `vendor/async-opcua-server` enthält genau eine fachliche Änderung: die ActivateSession-Nonce hat unabhängig von der Policy mindestens 32 Byte. Keine Sicherheitsprüfung wird deaktiviert. Der Patch muss bei jedem Upgrade erneut geprüft werden.
4. **Zertifikatsrotation:** der gepinnte async-opcua-Client cached den Server-Thumbprint. Ein Wechsel wird mit `BadNoValidCertificates` sofort als terminaler Security-Pfad gemeldet. Die Wiederherstellung verwendet neue Discovery und eine neue Client-Session mit bereits explizit vertrautem neuem Zertifikat; kein automatischer Reconnect mit altem Thumbprint und keine Auto-Trust-Ausnahme.
5. **Zeit:** ungültige externe Zeitstempel bleiben mit ihrem ursprünglichen Millisekundenwert erhalten und werden `Bad`/`Unknown` + `InvalidTimestamp`. Domain-zu-OPC-UA-Konvertierungen sind auf 1601–9999 begrenzt. Nicht finite Double-Werte werden abgelehnt.
6. **Persistenz:** `oip-core` enthält die neutralen Event-, Source- und Repository-Verträge. `oip-storage` implementiert SQLite mit append-only Migrationen, SHA-256-Migrationsprüfsummen, Inhalts-Hashes für idempotente Ingestion, `IMMEDIATE`-Transaktionen, WAL und `synchronous=FULL`. Jede Observation und jedes Event/jede Lücke trägt Source und Origin-Class. Eine Source-ID kann nicht gleichzeitig Simulation und External sein.

## Konsequenzen

- Beide ungesicherten Interop-Richtungen sind verpflichtende Tests, nicht mehr ignoriert.
- Production sichert die OPC-UA-Anwendungsidentitäten, verwendet in OIP-002 aber weiterhin Anonymous User Tokens. Benutzerauthentifizierung, CA-Ketten, CRL/Revocation und produktive Schlüsselverwaltung sind nicht implementiert.
- Im aktuellen OPC-UA-Stack behebt RSA 0.10.0 den Befund `RUSTSEC-2023-0071`. Die gepflegte Implementierung `sad-chrono 0.5.2` ersetzt Chrono (`RUSTSEC-2026-0543`). Die bestehende Ausnahme für den YAML-Parser (`RUSTSEC-2024-0449`) muss bis 2027-02-03 neu bewertet werden. Die verbleibenden Freigabepunkte sind im [Security-Audit](../architecture/oip-security-audit-remediation.md) dokumentiert.
- Ein späterer TSDB-Adapter implementiert die Verträge aus `oip-core`, ohne von SQLite oder einem OPC-UA-Stack abzuhängen.
