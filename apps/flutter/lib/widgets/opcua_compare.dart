import '../l10n/oip_strings.dart';
import 'package:flutter/material.dart';

import '../design_system/theme.dart';
import '../features/opcua_value.dart';
import '../models/contracts.dart';
import 'components.dart';
import 'workstation.dart';

/// A source-scoped comparison entry. Observations are never synthesized.
class OpcCompareEntry {
  final String sourceId;
  final OpcNode node;
  final Observation? observation;
  final bool live;
  final List<Observation> samples;

  const OpcCompareEntry({
    required this.sourceId,
    required this.node,
    required this.observation,
    required this.live,
    this.samples = const [],
  });
}

/// Dense, honest node comparison. Values and timestamps remain independent;
/// no time alignment, unit conversion or interpolation is implied.
class OpcCompareWorkspace extends StatelessWidget {
  final List<OpcCompareEntry> entries;
  final void Function(OpcCompareEntry) onRemove;
  final VoidCallback onClear;
  final VoidCallback onClose;
  final bool bounded;

  const OpcCompareWorkspace({
    super.key,
    required this.entries,
    required this.onRemove,
    required this.onClear,
    required this.onClose,
    this.bounded = true,
  });

  @override
  Widget build(BuildContext context) {
    final cyan = OipTokens.readableAccent(context, OipTokens.cyan);
    return WorkstationPanel(
      key: const Key('compare-workspace'),
      accent: OipTokens.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.compare_arrows_outlined, size: 22, color: cyan),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr("Node-Vergleich"),
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(
                        context.tr("{0}/4 · quellenbezogen · sitzungslokal",
                            [entries.length]),
                        style: WorkstationTokens.mono(context,
                            size: 10.5, color: OipTokens.muted(context))),
                  ]),
            ),
            ToolButton(
              key: const Key('compare-clear'),
              icon: Icons.delete_sweep_outlined,
              tooltip: context.tr("Vergleich leeren"),
              accent: OipTokens.cyan,
              onPressed: entries.isEmpty ? null : onClear,
            ),
            const SizedBox(width: 4),
            ToolButton(
              key: const Key('compare-close'),
              icon: Icons.close,
              tooltip: context.tr("Vergleich schließen (Esc)"),
              accent: OipTokens.cyan,
              onPressed: onClose,
            ),
          ]),
          const Hairline(),
          if (entries.isEmpty)
            WorkstationNote(
              context.tr("Noch keine Nodes im Vergleich"),
              context.tr(
                  "Node im Inspector mit C oder der Vergleichs-Aktion hinzufügen. Pins und Vergleiche bleiben sitzungslokal; es werden keine Benutzerpräferenzen im Core gespeichert."),
              icon: Icons.compare_arrows_outlined,
              color: OipTokens.cyan,
            )
          else ...[
            WorkstationNote(
              context.tr("Unabhängige Messzeitpunkte"),
              context.tr(
                  "Werte werden nebeneinander gezeigt, nicht zeitlich synchronisiert. Es gibt keine Interpolation, Einheitenumrechnung oder Differenzbildung. Zeitstempel und Provenienz gelten jeweils nur für ihre eigene Spalte."),
              icon: Icons.schedule_outlined,
              color: OipTokens.cyan,
            ),
            const SizedBox(height: OipTokens.s3),
            if (bounded) Expanded(child: _table(context)) else _table(context),
          ],
        ],
      ),
    );
  }

  Widget _table(BuildContext context) {
    const labels = [
      'Aktueller Wert · API-Original',
      'NodeId',
      'Source',
      'Namespace',
      'Datentyp · Core-Angabe',
      'Einheit',
      'Quality',
      'Freshness',
      'SourceTimestamp',
      'ServerTimestamp',
      'ReceivedTimestamp',
      'Subscription',
      'CollectionError',
      'Provenienz',
      'Session-Samples',
      'Session Min / Max',
    ];
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: 150 + entries.length * 210),
          child: Table(
            columnWidths: {
              0: const FixedColumnWidth(150),
              for (var index = 0; index < entries.length; index++)
                index + 1: const FixedColumnWidth(210),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            border: TableBorder(
              horizontalInside:
                  BorderSide(color: WorkstationTokens.hairline(context)),
              verticalInside:
                  BorderSide(color: WorkstationTokens.hairline(context)),
            ),
            children: [
              TableRow(children: [
                _cell(context, 'ATTRIBUT', header: true),
                for (final entry in entries) _headerCell(context, entry),
              ]),
              for (final label in labels)
                TableRow(children: [
                  _cell(context, label, header: true),
                  for (final entry in entries)
                    _cell(context, _value(entry, label),
                        color: label == 'Quality'
                            ? OipTokens.statusColor(
                                context, entry.observation?.quality)
                            : null),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCell(BuildContext context, OpcCompareEntry entry) => Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          TypeGlyph(entry.node.dataType, size: 26, active: true),
          const SizedBox(width: 8),
          Expanded(
            child: Text(entry.node.name,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall),
          ),
          ToolButton(
            key: Key('compare-remove-${entry.node.name}'),
            icon: Icons.close,
            tooltip:
                context.tr("{0} aus Vergleich entfernen", [entry.node.name]),
            accent: OipTokens.cyan,
            onPressed: () => onRemove(entry),
          ),
        ]),
      );

  Widget _cell(BuildContext context, String value,
          {bool header = false, Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: SelectableText(
          value,
          style: header
              ? WorkstationTokens.eyebrow(context)
              : WorkstationTokens.mono(context, size: 11.5, color: color),
        ),
      );

  String _value(OpcCompareEntry entry, String label) {
    final observation = entry.observation;
    final analysis = SessionAnalysis.fromSamples(entry.samples);
    return switch (label) {
      'Aktueller Wert · API-Original' =>
        observationValueWithUnit(observation, OpcValueFormat.original),
      'NodeId' => entry.node.id,
      'Source' => entry.sourceId,
      'Namespace' => 'ns=${entry.node.namespace}',
      'Datentyp · Core-Angabe' => entry.node.dataType,
      'Einheit' => observation == null
          ? 'Unbekannt'
          : observation.symbol.isEmpty
              ? observation.unit
              : observation.symbol,
      'Quality' => known(observation?.quality),
      'Freshness' => known(observation?.freshness),
      'SourceTimestamp' => timestamp(observation?.sourceMs),
      'ServerTimestamp' => timestamp(observation?.serverMs),
      'ReceivedTimestamp' => timestamp(observation?.receivedMs),
      'Subscription' => entry.live
          ? 'Live · aktive Quelle'
          : 'Nicht live · letzter gelieferter Read',
      'CollectionError' => observation?.collectionError ?? 'Keine gemeldet',
      'Provenienz' => observation == null
          ? 'Unbekannt'
          : observation.simulated
              ? 'Simulation'
              : 'Backend',
      'Session-Samples' => entry.live
          ? '${analysis.sampleCount} · nur diese Sitzung'
          : '0 · keine Live-Samples',
      'Session Min / Max' => analysis.minimum == null
          ? 'Nicht verfügbar'
          : '${formatNumberForAnalysis(analysis.minimum!)} / '
              '${formatNumberForAnalysis(analysis.maximum!)}',
      _ => 'Unbekannt',
    };
  }
}

String formatNumberForAnalysis(num value) {
  if (!value.isFinite) return value.toString();
  final absolute = value.abs();
  if (absolute >= 1e6 || (absolute > 0 && absolute < 1e-3)) {
    return value.toStringAsExponential(3);
  }
  return value.toString();
}
