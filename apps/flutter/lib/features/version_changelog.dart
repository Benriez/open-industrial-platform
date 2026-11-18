import 'package:flutter/material.dart';

import '../design_system/theme.dart';
import '../models/app_metadata.dart';
import 'settings/ota_update_control.dart';

/// Opens the bundled release history without making a request to the OIP Core.
/// This keeps version notes available when the server is offline.
Future<void> showVersionChangelog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const VersionChangelogDialog(),
    );

class VersionChangelogDialog extends StatelessWidget {
  const VersionChangelogDialog({super.key});

  static const _releases = <_ReleaseNotes>[
    _ReleaseNotes(
      version: '0.3.36',
      build: '39',
      date: '18. November 2026',
      changes: [
        'Der OPC-UA-Browser lädt Quellen und Knoten nach einer kurzen Verbindungsstörung erneut.',
        'Bei einem Fehler im Live-Stream lädt die Mac-App den aktuellen Stand über die bestehende Anmeldung.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.35',
      build: '38',
      date: '18. November 2026',
      changes: [
        'Updateangebote warten, wenn macOS gerade Touch ID verwendet.',
        'Die Versionsübersicht kann direkt nach signierten Updates suchen.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.34',
      build: '37',
      date: '18. November 2026',
      changes: [
        'Wenn der Live-Stream stockt, lädt die Mac-App den aktuellen Stand über dieselbe Anmeldung nach.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.33',
      build: '36',
      date: '18. November 2026',
      changes: [
        'Der Verbindungsstatus unterscheidet eine erforderliche Anmeldung von einem API-Ausfall.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.32',
      build: '35',
      date: '18. November 2026',
      changes: [
        'Das Änderungsprotokoll enthält jetzt auch die aktuellen App-Versionen.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.31',
      build: '34',
      date: '18. November 2026',
      changes: [
        'Die Netzwerktopologie zeigt bestätigte LAN-Nachbarn zwischen registrierten Geräten.',
        'SSH-Abfragen aktualisieren Nachbarschaftsdaten, damit neue Verbindungen erscheinen.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.30',
      build: '33',
      date: '18. November 2026',
      changes: [
        'Direkte macOS-Installationen können in Einstellungen → About manuell nach signierten OTA-Updates suchen.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.29',
      build: '32',
      date: '17. November 2026',
      changes: [
        'Das native Fenster öffnet sich mit einer nutzbaren Mindestgröße.',
        'Der OPC-UA-Browser vermeidet doppelte Leseabfragen beim Öffnen.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.28',
      build: '31',
      date: '17. November 2026',
      changes: [
        'Die erste Anmeldung schlägt Touch ID standardmäßig zur Einrichtung vor, wenn noch kein OIP-Schlüssel gespeichert ist.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.27',
      build: '30',
      date: '17. November 2026',
      changes: [
        'Netzwerkknoten bleiben sichtbar, wenn für sie keine frischen Verbindungsdaten vorliegen.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.26',
      build: '29',
      date: '17. November 2026',
      changes: [
        'Die Netzwerkansicht zeigt registrierte Geräte und ihre belegte Tailnet-Zugehörigkeit.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.25',
      build: '28',
      date: '17. November 2026',
      changes: [
        'Autorisierte Tailscale-Peers werden den passenden registrierten Geräten zugeordnet.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.24',
      build: '27',
      date: '17. November 2026',
      changes: [
        'Die Netzwerkansicht zeigt den autorisierten Gerätebestand statt einer leeren Topologie.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.23',
      build: '26',
      date: '17. November 2026',
      changes: [
        'Dashboards bieten weitere Darstellungen und ein automatisch erzeugtes Layout für verfügbare Messwerte.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.22',
      build: '25',
      date: '17. November 2026',
      changes: [
        'Dashboard-Panels zeigen Messwerte als Anzeigen, Statistiken und Balken.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.21',
      build: '24',
      date: '17. November 2026',
      changes: [
        'Dashboard-Panels passen sich als Kacheln an die verfügbare Fensterbreite an.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.20',
      build: '23',
      date: '17. November 2026',
      changes: [
        'Persönliche Dashboards lassen sich je Benutzer und Infrastruktur zusammenstellen.',
        'OpenWrt liefert echte SSH-Messwerte für seine unterstützten Systemdaten.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.19',
      build: '22',
      date: '17. November 2026',
      changes: [
        'Die Verbindung zum Pi nutzt das private Tailscale-Netz direkt.',
        'Telemetrie und OPC-UA-Abfragen verwenden eigene Verbindungen ohne gemeinsam genutzte SSH-Kanäle.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.18',
      build: '21',
      date: '17. November 2026',
      changes: [
        'Der Client verwendet wieder den stabil antwortenden lokalen OIP-Tunnel.',
        'Ein gesunder, bereits laufender Tunnel wird weiterverwendet, statt einen zweiten SSH-Forward zu starten.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.17',
      build: '20',
      date: '17. November 2026',
      changes: [
        'Ein Klick auf die Versionsanzeige öffnet jetzt die Änderungsübersicht, auch wenn der OIP-Server nicht erreichbar ist.',
        'Der lokale API-Tunnel verwendet einen frischen Weiterleitungsport.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.16',
      build: '19',
      date: '17. November 2026',
      changes: [
        'Die lokale API-Tunnelkonfiguration verwendet Port 18861.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.13',
      build: '16',
      date: '17. November 2026',
      changes: [
        'Der Client kann einen bereits laufenden lokalen OIP-Tunnel wiederverwenden.',
      ],
    ),
    _ReleaseNotes(
      version: '0.3.12',
      build: '15',
      date: '17. November 2026',
      changes: [
        'Version und Build sind in der Seitenleiste sichtbar.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      key: const Key('version-changelog-dialog'),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              child: Row(
                children: [
                  Icon(Icons.history, color: OipTokens.cyan),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Änderungsprotokoll',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 3),
                        Text(
                          '${kOipApplication.name} · Version ${kOipApplication.version} · Build ${kOipApplication.build}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: OipTokens.muted(context),
                                  ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('version-changelog-close'),
                    tooltip: 'Schließen',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outline),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: _releases.length,
                separatorBuilder: (_, __) => const SizedBox(height: 20),
                itemBuilder: (context, index) => _ReleaseCard(
                  release: _releases[index],
                  current: _releases[index].version == kOipApplication.version,
                ),
              ),
            ),
            Divider(height: 1, color: scheme.outline),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Die Versionshinweise sind in der App enthalten und benötigen keine Serververbindung.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: OipTokens.muted(context),
                        ),
                  ),
                  const OipOtaUpdateControl(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReleaseNotes {
  const _ReleaseNotes({
    required this.version,
    required this.build,
    required this.date,
    required this.changes,
  });

  final String version;
  final String build;
  final String date;
  final List<String> changes;
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.release, required this.current});

  final _ReleaseNotes release;
  final bool current;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Version ${release.version} · Build ${release.build}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if (current)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: OipTokens.cyan.withOpacity(.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'INSTALLIERT',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color:
                              OipTokens.readableAccent(context, OipTokens.cyan),
                          fontWeight: FontWeight.w700,
                          letterSpacing: .4,
                        ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(release.date,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: OipTokens.muted(context),
                  )),
          const SizedBox(height: 12),
          for (final change in release.changes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 10),
                    child: Icon(Icons.circle, size: 6, color: OipTokens.cyan),
                  ),
                  Expanded(child: Text(change)),
                ],
              ),
            ),
        ],
      );
}
