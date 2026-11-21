import '../../l10n/oip_strings.dart';
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
            Text(context.tr("EVIDENCE INSPECTOR"),
                style: WorkstationTokens.eyebrow(context,
                    color: OipTokens.violet)),
            const SizedBox(height: 2),
            Text(
                item == null
                    ? context.tr("Ereignis auswählen")
                    : context.tr(diagnosticEventTitle(item.event.kind)),
                style: Theme.of(context).textTheme.titleMedium),
            Text(
                item == null
                    ? context.tr("Technische Evidenz · Read-only")
                    : context.tr("COLLECTION EVENT · KEINE KAUSALBEHAUPTUNG"),
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        if (item == null)
          Expanded(
              child: SingleChildScrollView(
                  padding: EdgeInsets.all(12),
                  child: WorkstationNote(
                    context.tr("Kein Ereignis ausgewählt"),
                    context.tr(
                        "Explorer, Timeline und Inspector verwenden denselben Datensatz. Auswahl mit Pfeiltasten, Enter, Touch oder Maus."),
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
            tooltip: pinned
                ? context.tr("Ereignis lösen")
                : context.tr("Ereignis anheften"),
            icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
            active: pinned,
            onPressed: onPin),
        ToolButton(
            tooltip: compared
                ? context.tr("Aus Compare entfernen")
                : context.tr("Zu Compare hinzufügen"),
            icon: Icons.compare_arrows_outlined,
            active: compared,
            onPressed: onCompare),
        ToolButton(
            key: const Key('inspector-focus-timeline'),
            tooltip: context.tr("In Timeline fokussieren"),
            icon: Icons.center_focus_strong_outlined,
            onPressed: item.hasTimestamp ? onFocusTimeline : null),
      ]),
      const SizedBox(height: 8),
      _section(context, 'IDENTITY', Icons.fingerprint, [
        KeyValue(context.tr("Event ID / Record-ID"),
            item.recordId ?? context.tr("Nicht vom Server geliefert"),
            trailing: item.recordId == null
                ? null
                : _copy(context, 'Event ID kopieren', item.recordId!)),
        KeyValue(context.tr("Event Type"), event.kind),
        KeyValue(context.tr("Source ID"),
            event.sourceId ?? context.tr("Nicht geliefert"),
            trailing: event.sourceId == null
                ? null
                : _copy(context, 'Source ID kopieren', event.sourceId!)),
        KeyValue(context.tr("Device ID"),
            context.tr("Im CollectionEvent nicht enthalten")),
        if (infrastructure?.ready == true) ...[
          KeyValue(
              context.tr("Organization"),
              infrastructure!.hierarchy.organizationName(infrastructure!
                  .sourcePlacement(event.sourceId)
                  ?.organizationId)),
          KeyValue(
              context.tr("Infrastructure"),
              infrastructure!.hierarchy.infrastructureName(infrastructure!
                  .sourcePlacement(event.sourceId)
                  ?.infrastructureId)),
          KeyValue(
              context.tr("Site"),
              infrastructure!.hierarchy.siteName(
                  infrastructure!.sourcePlacement(event.sourceId)?.siteId)),
        ],
        KeyValue(context.tr("Event Category"),
            context.tr(diagnosticEventCategory(event.kind))),
        KeyValue(
            context.tr("Severity"), context.tr("Nicht vom Core geliefert")),
        if (item.deliveryCount > 1)
          KeyValue(
              context.tr("Identische Lieferungen"),
              context.tr(
                  "{0} · als ein Record konsolidiert", [item.deliveryCount])),
        if (item.identityConflict)
          KeyValue(
              context.tr("Identitätsprüfung"),
              context.tr(
                  "Gleiche Source-Sequenz mit abweichendem Inhalt · separat ausgewiesen"),
              color: OipTokens.red),
      ]),
      _section(context, 'TIMING', Icons.schedule_outlined, [
        KeyValue(context.tr("EventTimestamp · Server Wall Clock"),
            timestamp(event.atMs),
            trailing: event.atMs == null
                ? null
                : _copy(context, 'Zeitpunkt kopieren', event.atMs.toString())),
        KeyValue(context.tr("SourceTimestamp"),
            context.tr("Für CollectionEvent nicht geliefert")),
        KeyValue(context.tr("ServerTimestamp"),
            context.tr("Kein separates Feld; EventTimestamp ist Server-Zeit")),
        KeyValue(
            context.tr("ReceivedTimestamp"), context.tr("Nicht geliefert")),
        KeyValue(
            context.tr("Clock Uncertainty"),
            context
                .tr("Nicht geliefert · keine Zeitsynchronisation behauptet")),
      ]),
      _section(context, 'COLLECTION CONTEXT', Icons.lan_outlined, [
        KeyValue(
            context.tr("Source Health · Reachability"),
            source == null
                ? context.tr("Kein aktueller Source-Datensatz")
                : context.tr(known(source!.reachability))),
        KeyValue(
            context.tr("Connection State"),
            source == null
                ? context.tr("Unbekannt")
                : context.tr(known(source!.connection))),
        KeyValue(context.tr("Collection State"),
            context.tr(_collectionState(event))),
        KeyValue(context.tr("Tatsächlicher Fehler"),
            event.reason ?? source?.lastError ?? context.tr("Nicht geliefert")),
        KeyValue(
            context.tr("Freshness"),
            source == null
                ? context.tr("Unbekannt")
                : context.tr(known(source!.freshness))),
        KeyValue(context.tr("Letzter erfolgreicher Empfang"),
            timestamp(source?.lastReceivedMs)),
      ]),
      _section(context, 'DATA GAP', Icons.space_bar_outlined, _gapFacts(item)),
      _section(context, 'PROVENANCE & EVIDENCE', Icons.fact_check_outlined, [
        KeyValue(
            context.tr("Aussageherkunft"),
            infrastructure?.ready == true
                ? context.tr(
                    "Tatsächlich von GET /api/v2/events/history im autorisierten Kontext empfangen")
                : context.tr(
                    "Tatsächlich von GET /api/v1/events empfangenes Collection-Ereignis")),
        KeyValue(
            context.tr("Regelbefund"),
            context.tr(
                "Nein · keine Regel-ID, Version oder Evaluation geliefert")),
        KeyValue(context.tr("Beobachteter Zustand"),
            context.tr(_collectionState(event)),
            color: tone),
        KeyValue(
            context.tr("Verlorene Samples"),
            event.dropped?.toString() ??
                context.tr("Nicht geliefert / nicht zutreffend")),
        KeyValue(context.tr("Gemeldeter Grund"),
            event.reason ?? context.tr("Nicht geliefert")),
      ]),
      _section(context, 'RELATED EVIDENCE · ZEITLICHE NÄHE',
          Icons.compare_arrows_outlined, [
        KeyValue(
            context.tr("Aussagegrenze"),
            context.tr(
                "Vorher / gleichzeitig / danach ist keine bestätigte Korrelation und keine Ursache"),
            mono: false),
        if (related.isEmpty)
          KeyValue(context.tr("Benachbarte Ereignisse"),
              context.tr("Keine im aktuell geladenen Fenster")),
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
        KeyValue(context.tr("Ursache"),
            context.tr("Nicht verifiziert · keine Root-Cause-Behauptung"),
            mono: false),
        KeyValue(
            context.tr("Historie"),
            context.tr(
                "Nur aktuell verfügbare Ereignisse; kein Replay und keine vollständige Serverhistorie"),
            mono: false),
        KeyValue(
            context.tr("Messwerte"),
            context.tr(
                "Keine ereignisverknüpften Observation-Referenzen geliefert"),
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
      // The Core delivers the reason of the gap with the event. The panel
      // shows it; it never claims that the reason is missing.
      KeyValue(
          'Grund',
          (event.reason == null || event.reason!.isEmpty)
              ? 'Der Core hat für dieses Ereignis keinen Grund geliefert'
              : '${event.reason} · vom Core für dieses Ereignis geliefert',
          mono: false),
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
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(context.tr("{0} · erledigt", [tooltip]))));
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
