# OIP — Initial Local Git Baseline

Datum: 2026-11-05. Baseline **OIP-007**. Der Operator hat den ersten lokalen Commit ausdrücklich autorisiert. Kein Push, keine Remote-Erstellung/-Änderung und kein Deployment.

## Git und Integrationsautorität

Vorher: Branch `main`, unborn HEAD, null tracked Dateien, leerer Index, keine Remotes. Vorhandene gültige Git-Autoren-/Committeridentität aus der bestehenden Konfiguration wird unverändert verwendet; keine erfundene Identität, kein Initialisieren oder Umschreiben von Historie. Commit-Message: `chore: establish verified OIP-007 project baseline`.

Core-Session `01a1a3b3-9469-7311-be9a-1218be181ebc` besitzt ausschließlich die lokale Git-Baseline-Autorität. Keine fachlichen Source-Änderungen. Beobachteter OpenCode-Aktivstatus ohne konkurrierenden Schreibauftrag im Haupt-Checkout; ein weiterer Sessiondienst war nicht auswertbar. Hashvergleiche vor Staging/Commit sichern gegen Source-Drift ab, ersetzen aber keine globale Schreibsperre.

Die OPC-UA-UI-Arbeit unter `/Users/benny/Code/oip-ui-isolated/OIP-UI-OPCUA-2027-20261105` einschließlich ihrer Vorschau auf18096 bleibt isoliert. Ihr nächstes Handoff ist nicht Bestandteil dieser Baseline. Keine dortigen Dateien oder Prozesse verändert. Bestehende Instanzen auf18080/18086 ebenfalls unberührt.

Der tatsächliche Commit-Hash wird nach Ausführung im Session-Abschluss genannt. Dieses Dokument wird dafür nicht nachträglich amendiert oder durch einen zweiten reinen Hash-Commit verändert. Nachkontrollen werden extern dokumentiert.

## Geprüfter Umfang und Allowlist

Inventar vor Ignore-Härtung: **1074** nicht ignorierte Dateien einschließlich untracked. Alle einzeln nach Größe/SHA-256 erfasst und extern gesichert.

| Kategorie | Vorher | Behandlung |
|---|---:|---|
| A Source, Konfiguration, Tests, Lizenzen, Dokumentation |272| vollständig enthalten |
| B geprüfte kompakte Nachweise/Manifeste |40| einzeln geprüft und enthalten |
| C generierte/lokale Evidenz und Metadaten |762| unverändert lokal und verifiziert extern erhalten; nicht getrackt |

Dazu sieben neue Git-/Baseline-Dokumentations-/Manifestdateien: **319 geplante Commit-Dateien =275 A +44 B, null C**. [Vollständige dateiweise Allowlist](git-baseline-files.txt), [Klassifikation](evidence/git-baseline/classification-summary.json). Staging ausschließlich anhand dieser konkreten Pfade, kein `git add .` oder `git add -A`.

Alle acht Rust-Crates, API-/Capability-/MCP-/Daemon-Verträge, Collector/Storage, Workspace-Cargo/Lock, CI, sämtliche Flutter-Quellen/native macOS-Projektdateien/Webquellen, Pubspec/Lock, alle Test-Harnesses, Startup-Beispiele und Dokumentation gehören zum Kandidaten. Der schmale async-opcua-Source-Patch ist vollständig mit upstream MPL-2.0-Lizenz und Provenienz enthalten; Root-Lizenz Apache-2.0 unverändert. Die vier benötigten Schriftdateien samt Apache-/SIL-OFL-Lizenzen und Web-Icons sind bewusst erforderliche Source-Assets, keine versehentlichen Build-Binaries.

Bewusst enthaltene Evidence-Abhängigkeiten: `docs/evidence/oip006/rust-regression.json` für vorhandene Regressionrunner, die ursprünglichen Hashmanifeste für Handoff-Rundreise und `oip0061/preview-process.json` für historische lokale Capture-Harnesses. Letzteres ist eine dokumentierte lokale Beispiel-/Provenienzkonfiguration ohne Credentials, keine Aussage über eine auf anderen Rechnern laufende Instanz. Das aktuelle Capability-Mapping/Schema und OIP-007-Reviews/Ergebnisberichte sind enthalten.

## Exclusions, Aufbewahrung und historische Links

.gitignore erhält nur notwendige Regeln für beobachtete IPC-Credential-/Socket-/Lockdateien und lokale IPC-Konfiguration sowie eine **exakte** Positivliste der versionierten Evidence-Dateien. Source außerhalb docs/evidence wird dadurch nicht ausgeblendet. Bestehende Regeln für target, Flutter-Caches/Binaries, node_modules, DB/WAL, PKI/Private Keys und .env bleiben erhalten.

Nicht versioniert: Screenshots, Roh-SDK-Transkripte, Debug-/Rohlogs, Session-/Prozessinventare, große generierte Capture-/Hashsammlungen und Entwicklungsfehlversuche, soweit nicht ausdrücklich in B ausgewählt. Keine Datei gelöscht. Diese ursprünglichen docs/evidence-Pfade bleiben im Checkout erhalten und im externen Archiv identisch auffindbar. Historische Berichte werden nicht umgeschrieben: Links auf ausgeschlossene Rohartefakte benötigen im frischen Checkout dieses Archiv oder einen erneuten Testlauf. Sie sind nicht als im Git-Commit vorhanden ausgegeben.

Neue geprüfte externe Sicherung:

`/Users/benny/Documents/OIP-Handoffs/git-initial-baseline-20261105T115216Z/`

- Source-/Projektbestand vor Git-Vorbereitung: `project-pre-git-baseline.tar.gz`, SHA-256 `f2f596041cd624c90c6493358aa6222c16a258733aae683d7120a116f3097122`,1074 Dateien,79.017.315 Bytes.
- Vollständige historische Evidence einschließlich ignorierter Logs: `historical-evidence-complete.tar.gz`, SHA-256 `9633dc4e625070ba0fe79435ffeb408316399db77bdc34a6cca552ccdcd80dce`,1230 Dateien,78.854.794 Bytes.

Beide Archive unabhängig memberweise gegen ihre Hashmanifeste geprüft. Neue private Credentials/Runtime-DBs sind nicht Teil dieser Source-/Evidence-Archive. Früher verifizierte OIP-005.1/006.1/007-Backups bleiben unverändert. [Archivverzeichnis und Wiederherstellung](evidence/git-baseline/external-evidence.json). Erst isoliert extrahieren/verifizieren, niemals blind Source-Dateien überschreiben. Runtime-Daten und Caches bleiben an ihren ursprünglichen ignorierten Orten.

## Whitespace-Policy ohne Source-Änderungen

Der erste unkonfigurierte `git diff --cached --check` meldete exakt drei bereits vorhandene Stellen: OFL-Lizenz Zeile21 (trailing space), vendored session/manager.rs Zeile94 (trailing space) und Cargo-Manifest oip-server Zeile35 (leere Schlusszeile). Originalbytes bleiben erhalten. Die neue .gitattributes deaktiviert ausschließlich blank-at-eol auf diesen zwei konkreten Lizenz-/Vendor-Pfaden und blank-at-eof auf genau diesem Manifest. Alle anderen Whitespace-Kategorien bleiben aktiv; keine globale Abschaltung, kein Security-Scanner-Bypass. Die normale Git-Prüfung wird mit dieser dokumentierten Repository-Policy erneut ausgeführt. Die HTML-Referenz benötigt keine Ausnahme und bleibt unverändert.

## Secret- und Sicherheitsgate

Installiertes **Gitleaks8.30.1**, Standardregeln,100% Redaction, keine neue Scanner-Ausnahme. Initial1502 Source-/Evidenzdateien einschließlich historischer Rohlogs in isolierter Kopie tatsächlich gescannt. Roh-Exitcode1 mit84 Treffern:46 Datei-SHA-256-Werte und38 deterministische Simulations-Datenlücken-Hashidentitäten. Jede Fundstelle anhand des Schlüssels/Dateikontexts geprüft; keine dieser Kennungen ist ein Authentisierungswert. Nicht als „Scanner meldet null“ ausgegeben.

Der finale319-Dateien-Kandidat wurde separat gescannt: Roh-Exitcode1, 21 ausdrücklich geprüfte False Positives (Datei-SHA-256 bzw. deterministische Simulations-Gap-Hashes), null ungeklärte Befunde. Keine Regel deaktiviert und keine Ausnahmedatei eingeführt. Fundstellen und Entscheidungen stehen im versionierten Scan-Manifest; Rohreport extern.

Zusätzliche gezielte Prüfung: PEM-/SSH-Private-Key-Marker, bekannte Tokenformate, eingebettete Zugangsdaten, lokale Credential-/PKI-/SQLite-/Binary-Dateien, verdächtige JSON-Felder, Lizenzumfang und persönliche Daten. Beispiel-Policies enthalten freigegebene lokale Read-Scopes, aber keine Zugangsschlüssel. IPC-Credentials werden zur Laufzeit erzeugt und liegen ausschließlich in ignorierten privaten Runtime-Verzeichnissen. macOS-Projekt besitzt Ad-hoc-Signing statt persönlicher Provisioning-Credentials. Vorhandene Operator-Dateipfade und historische Simulations-IDs bleiben bewusst dokumentierte Provenienz, keine neu exportierten privaten Sessioninventare.

[Maschinenlesbares Scan-Ergebnis](evidence/git-baseline/secret-scan.json). Vollständige redigierte Scannerberichte und fundstellenbezogene Triage extern erhalten; keine Secrets im Bericht wiedergegeben. Kein ungeklärter kritischer Befund darf zum Commit gelangen.

`RUSTSEC-2023-0071` bleibt produktiver Blocker. Weitere bestehende Advisory-Ausnahmen bleiben offen. Ein Git-Baseline-Commit ist keine Produktions- oder Remote-Freigabe.

## Neu ausgeführte Regression und Integrität

[Neue Testergebnisse](evidence/git-baseline/test-summary.json), vollständige neue Logs im externen Baseline-Verzeichnis:

- `cargo fmt --all -- --check`: PASS.
- `cargo check --locked --workspace --all-targets`: PASS.
- `cargo test --locked --workspace -- --test-threads=1`: **PASS100** einschließlich Storage/Recovery/Capability-/Permission-/MCP-/IPC-Tests und Doc-Tests.
- `flutter analyze`: PASS, null Issues.
- `flutter test --reporter expanded`: **PASS80**.
- Acht Workspace-Mitglieder, fachliche Architektur-/MCP-Dateien, Vendoring und Build-Lockfiles vollständig; alle Anwendungssourcen gegenüber dem gesicherten OIP-007-Stand unverändert.
- Designreferenz unverändert: `bd9f9d8696ed48676055ee9a2cd0afb29e6c3d59e0945e662d925306f73c753e`.

**Frühere**, nicht für diesen Git-Auftrag erneut ausgeführte OIP-007-Evidenz:37 OPC-UA-Interop,16 Browserchecks, nativer macOS-Test und vollständiger Daemon-/Multi-Client-E2E PASS. [Historischer OIP-007-Bericht](oip-007-verification.md). Keine neue Produktänderung begründet eine fälschlich behauptete erneute Ausführung dieser Gruppen.

## Commit- und Nachprüfung

Vor Commit: byteidentischer Kandidat/Index, explizite Dateiliste, Dateimodi/-größen/Binary-Assets, Ignore-Proben für Runtime/Secrets, vollständiger Source-Abgleich, `git diff --cached --check` und `--stat`. Keine Credentials, DBs, PKI, Socket-Dateien, Build-/Abhängigkeitsausgaben oder nicht freigegebene Rohartefakte im Kandidaten.

Nach tatsächlichem Commit werden Status, `git log -1 --format=fuller`, `git show --stat --oneline HEAD`, `git ls-files`, `git fsck`, leerer Index und untracked Rest geprüft. Hash/Ergebnisse extern und im Session-Abschluss ausgeben; dieses vor Commit erstellte Dokument verspricht keinen noch nicht ausgeführten Nachcheck. Absichtlich ignorierte lokale Artefakte gelten nicht als gelöscht. Ein eventuell nicht sauberer Working Tree muss ausdrücklich so berichtet werden.

**Kein Push autorisiert oder ausgeführt. Keine Remote-Konfiguration geändert.** Kein Branchwechsel, History-Rewrite, Git Clean, Deployment, Source-/UI-Handoff oder Eingriff in fremde Arbeitskopien/Prozesse.
