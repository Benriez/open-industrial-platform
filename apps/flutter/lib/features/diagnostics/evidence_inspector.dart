import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import '../../models/infrastructure.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'diagnostics_model.dart';
import 'event_explorer.dart';

class DiagnosticsEvidenceInspector extends StatelessWidget {
  final DiagnosticEvent? selected;
  final List<DiagnosticEvent> allEvents;
  final SourceInfo? source;
  final bool pinned, compared;
  final VoidCallback onPin, onCompare, onFocusTimeline;
  final ValueChanged<DiagnosticEvent> onSelect;
  final InfrastructureContext? infrastructure;

  const DiagnosticsEvidenceInspector({
    super.key,
    required this.selected,
    required this.allEvents,
    required this.source,
    required this.pinned,
    required this.compared,
    required this.onPin,
    required this.onCompare,
    required this.onFocusTimeline,
    required this.onSelect,
    this.infrastructure,
  });

  @override
  Widget build(BuildContext context) {
    final item = selected;
    return WorkstationPanel(
      key: const Key('diagnostics-evidence-inspector'),
      accent: OipTokens.violet,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 7),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('EVIDENCE INSPECTOR',
                style: WorkstationTokens.eyebrow(context,
                    color: OipTokens.violet)),
            const SizedBox(height: 2),
            Text(
                item == null
                    ? 'Ereignis auswählen'
                    : diagnosticEventTitle(item.event.kind),
                style: Theme.of(context).textTheme.titleMedium),
            Text(
                item == null
                    ? 'Technische Evidenz · Read-only'
                    : 'COLLECTION EVENT · KEINE KAUSALBEHAUPTUNG',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        if (item == null)
          const Expanded(
              child: SingleChildScrollView(
                  padding: EdgeInsets.all(12),
                  child: WorkstationNote(
                    'Kein Ereignis ausgewählt',
                    'Explorer, Timeline und Inspector verwenden denselben Datensatz. Auswahl mit Pfeiltasten, Enter, Touch oder Maus.',
                    icon: Icons.touch_app_outlined,
                    color: OipTokens.violet,
                  )))
        else
          Expanded(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: _content(context, item))),
      ]),
    );
  }

  Widget _content(BuildContext context, DiagnosticEvent item) {
    final event = item.event;
    final tone = diagnosticEventTone(context, event.kind);
    final related = allEvents
        .where((candidate) =>
            candidate.key != item.key &&
            candidate.event.sourceId == event.sourceId &&
            candidate.timestampMs != null)
        .toList()
      ..sort((a, b) {
        final anchor = item.timestampMs;
        if (anchor == null) return a.key.compareTo(b.key);
        final da = (a.timestampMs! - anchor).abs();
        final db = (b.timestampMs! - anchor).abs();
        return da == db ? a.key.compareTo(b.key) : da.compareTo(db);
      });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        ToolButton(
            tooltip: pinned ? 'Ereignis lösen' : 'Ereignis anheften',
            icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
            active: pinned,
            onPressed: onPin),
        ToolButton(
            tooltip:
                compared ? 'Aus Compare entfernen' : 'Zu Compare hinzufügen',
            icon: Icons.compare_arrows_outlined,
            active: compared,
            onPressed: onCompare),
        ToolButton(
            key: const Key('inspector-focus-timeline'),
            tooltip: 'In Timeline fokussieren',
            icon: Icons.center_focus_strong_outlined,
            onPressed: item.hasTimestamp ? onFocusTimeline : null),
      ]),
      const SizedBox(height: 8),
      _section(context, 'IDENTITY', Icons.fingerprint, [
        KeyValue('Event ID / Record-ID',
            item.recordId ?? 'Nicht vom Server geliefert',
            trailing: item.recordId == null
                ? null
                : _copy(context, 'Event ID kopieren', item.recordId!)),
        KeyValue('Event Type', event.kind),
        KeyValue('Source ID', event.sourceId ?? 'Nicht geliefert',
            trailing: event.sourceId == null
                ? null
                : _copy(context, 'Source ID kopieren', event.sourceId!)),
        const KeyValue('Device ID', 'Im CollectionEvent nicht enthalten'),
        if (infrastructure?.ready == true) ...[
          KeyValue('Organization',
              infrastructure!.hierarchy.organizationName(infrastructure!.sourcePlacement(event.sourceId)?.organizationId)),
          KeyValue('Infrastructure',
              infrastructure!.hierarchy.infrastructureName(infrastructure!.sourcePlacement(event.sourceId)?.infrastructureId)),
          KeyValue('Site',
              infrastructure!.hierarchy.siteName(infrastructure!.sourcePlacement(event.sourceId)?.siteId)),
        ],
        KeyValue('Event Category', diagnosticEventCategory(event.kind)),
        const KeyValue('Severity', 'Nicht vom Core geliefert'),
        if (item.deliveryCount > 1)
          KeyValue('Identische Lieferungen',
              '${item.deliveryCount} · als ein Record konsolidiert'),
        if (item.identityConflict)
          const KeyValue('Identitätsprüfung',
              'Gleiche Source-Sequenz mit abweichendem Inhalt · separat ausgewiesen',
              color: OipTokens.red),
      ]),
      _section(context, 'TIMING', Icons.schedule_outlined, [
        KeyValue('EventTimestamp · Server Wall Clock', timestamp(event.atMs),
            trailing: event.atMs == null
                ? null
                : _copy(context, 'Zeitpunkt kopieren', event.atMs.toString())),
        const KeyValue(
            'SourceTimestamp', 'Für CollectionEvent nicht geliefert'),
        const KeyValue('ServerTimestamp',
            'Kein separates Feld; EventTimestamp ist Server-Zeit'),
        const KeyValue('ReceivedTimestamp', 'Nicht geliefert'),
        const KeyValue('Clock Uncertainty',
            'Nicht geliefert · keine Zeitsynchronisation behauptet'),
      ]),
      _section(context, 'COLLECTION CONTEXT', Icons.lan_outlined, [
        KeyValue(
            'Source Health · Reachability',
            source == null
                ? 'Kein aktueller Source-Datensatz'
                : known(source!.reachability)),
        KeyValue('Connection State',
            source == null ? 'Unbekannt' : known(source!.connection)),
        KeyValue('Collection State', _collectionState(event)),
        KeyValue('Tatsächlicher Fehler',
            event.reason ?? source?.lastError ?? 'Nicht geliefert'),
        KeyValue('Freshness',
            source == null ? 'Unbekannt' : known(source!.freshness)),
        KeyValue(
            'Letzter erfolgreicher Empfang', timestamp(source?.lastReceivedMs)),
      ]),
      _section(context, 'DATA GAP', Icons.space_bar_outlined, _gapFacts(item)),
      _section(context, 'PROVENANCE & EVIDENCE', Icons.fact_check_outlined, [
        KeyValue('Aussageherkunft',
            infrastructure?.ready == true
                ? 'Tatsächlich von GET /api/v2/events/history im autorisierten Kontext empfangen'
                : 'Tatsächlich von GET /api/v1/events empfangenes Collection-Ereignis'),
        const KeyValue('Regelbefund',
            'Nein · keine Regel-ID, Version oder Evaluation geliefert'),
        KeyValue('Beobachteter Zustand', _collectionState(event), color: tone),
        KeyValue('Verlorene Samples',
            event.dropped?.toString() ?? 'Nicht geliefert / nicht zutreffend'),
        KeyValue('Gemeldeter Grund', event.reason ?? 'Nicht geliefert'),
      ]),
      _section(context, 'RELATED EVIDENCE · ZEITLICHE NÄHE',
          Icons.compare_arrows_outlined, [
        const KeyValue('Aussagegrenze',
            'Vorher / gleichzeitig / danach ist keine bestätigte Korrelation und keine Ursache',
            mono: false),
        if (related.isEmpty)
          const KeyValue(
              'Benachbarte Ereignisse', 'Keine im aktuell geladenen Fenster'),
        for (final candidate in related.take(4))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: OutlinedButton(
              onPressed: () => onSelect(candidate),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      '${_temporalRelation(item, candidate)} · ${diagnosticEventTitle(candidate.event.kind)}\n${timestamp(candidate.timestampMs)}',
                      style: const TextStyle(fontSize: 11))),
            ),
          ),
      ]),
      _section(context, 'UNKNOWNS / OPEN QUESTIONS', Icons.help_outline, [
        const KeyValue(
            'Ursache', 'Nicht verifiziert · keine Root-Cause-Behauptung',
            mono: false),
        const KeyValue('Historie',
            'Nur aktuell verfügbare Ereignisse; kein Replay und keine vollständige Serverhistorie',
            mono: false),
        const KeyValue('Messwerte',
            'Keine ereignisverknüpften Observation-Referenzen geliefert',
            mono: false),
        const KeyValue('Gap-Grund',
            'DataGap.reason ist im gemeinsamen Flutter-DTO nicht projiziert; daher hier nicht verfügbar',
            mono: false),
      ]),
    ]);
  }

  List<Widget> _gapFacts(DiagnosticEvent item) {
    final event = item.event;
    if (!item.hasGapBounds) {
      return const [
        KeyValue('Data Gap', 'Kein Gap-Datensatz in diesem Ereignis')
      ];
    }
    final duration = event.gapMs == null
        ? event.kind == 'DataLoss'
            ? 'Unbekannt · verlorenes Intervall nicht bestimmbar'
            : item.gapIsInverted
                ? 'Inkonsistent · Ende liegt vor Beginn'
                : 'Unbekannt · Grenze fehlt'
        : event.gapMs == 0
            ? '0 ms · dokumentierte Null-Dauer; beweist keine unterbrechungsfreie Collection'
            : '${event.gapMs} ms · aus dokumentierten Grenzen berechnet';
    return [
      KeyValue('Beginn', timestamp(event.gapStartedMs)),
      KeyValue('Ende', timestamp(event.gapEndedMs)),
      KeyValue('Gemeldete/ableitbare Dauer', duration),
      const KeyValue('Recovery',
          'Reconnect ist kein Nachweis aktueller oder vollständiger Messwerte',
          mono: false),
    ];
  }

  Widget _section(BuildContext context, String title, IconData icon,
          List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, size: 15, color: OipTokens.violet),
            const SizedBox(width: 6),
            Expanded(
                child: Text(title,
                    style: WorkstationTokens.eyebrow(context,
                        color: OipTokens.violet)))
          ]),
          const SizedBox(height: 3),
          ...children,
        ]),
      );

  Widget _copy(BuildContext context, String tooltip, String value) =>
      IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('$tooltip · erledigt')));
          }
        },
        icon: const Icon(Icons.copy_outlined, size: 15),
      );
}

String _collectionState(CollectionEvent event) => switch (event.kind) {
      'ConnectionLost' => 'Verbindungsverlust vom Adapter gemeldet',
      'Reconnected' => 'Reconnect vom Adapter gemeldet',
      'SubscriptionError' => 'Subscription-Fehler gemeldet',
      'DataLoss' => 'Datenverlust gemeldet',
      _ => 'Unbekannter vom Core gelieferter Ereignistyp',
    };

String _temporalRelation(DiagnosticEvent anchor, DiagnosticEvent candidate) {
  if (anchor.timestampMs == null || candidate.timestampMs == null) {
    return 'Zeit unbekannt';
  }
  if (candidate.timestampMs! < anchor.timestampMs!) return 'Vorher';
  if (candidate.timestampMs! > anchor.timestampMs!) return 'Danach';
  return 'Gleichzeitig';
}
