import '../../l10n/oip_strings.dart';
import 'package:flutter/material.dart';

import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'network_model.dart';
import '../../widgets/device_kind.dart';

/// Session-local engineering comparison. Device and link semantics are kept in
/// separate tables; no timestamps, samples or measurements are synthesized.
class NetworkCompareWorkspace extends StatelessWidget {
  final Snapshot snapshot;
  final List<Device> devices;
  final List<NetworkEdge> edges;
  final bool transportLive, bounded;
  final ValueChanged<Device> onRemoveDevice;
  final ValueChanged<NetworkEdge> onRemoveEdge;
  final ValueChanged<Device> onSelectDevice;
  final ValueChanged<NetworkEdge> onSelectEdge;
  final VoidCallback onClear, onClose;

  const NetworkCompareWorkspace({
    super.key,
    required this.snapshot,
    required this.devices,
    required this.edges,
    required this.transportLive,
    required this.onRemoveDevice,
    required this.onRemoveEdge,
    required this.onSelectDevice,
    required this.onSelectEdge,
    required this.onClear,
    required this.onClose,
    this.bounded = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      key: const Key('network-compare-scroll'),
      padding: EdgeInsets.zero,
      children: [
        WorkstationNote(
          context.tr("Unabhängige Beobachtungskontexte"),
          context.tr(
              "Geräte und logische Pfade werden getrennt verglichen. Fehlende oder unterschiedliche Zeitstempel bedeuten keine Zeitsynchronität; es gibt keine Interpolation oder künstliche Messreihe."),
          icon: Icons.schedule_outlined,
          color: OipTokens.cyan,
        ),
        const SizedBox(height: OipTokens.s3),
        _deviceTable(context),
        const SizedBox(height: OipTokens.s4),
        _edgeTable(context),
      ],
    );
    return WorkstationPanel(
      key: const Key('network-compare-workspace'),
      accent: OipTokens.cyan,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.compare_arrows_outlined, color: OipTokens.cyan),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr("Network Compare"),
                  style: Theme.of(context).textTheme.titleLarge),
              Text(
                context.tr("{0}/4 Geräte · {1}/4 Pfade · sitzungslokal",
                    [devices.length, edges.length]),
                style: WorkstationTokens.mono(context,
                    size: 10.5, color: OipTokens.muted(context)),
              ),
            ]),
          ),
          ToolButton(
            key: const Key('network-compare-clear'),
            icon: Icons.delete_sweep_outlined,
            tooltip: context.tr("Network-Vergleich leeren"),
            accent: OipTokens.cyan,
            onPressed: devices.isEmpty && edges.isEmpty ? null : onClear,
          ),
          const SizedBox(width: 4),
          ToolButton(
            key: const Key('network-compare-close'),
            icon: Icons.close,
            tooltip: context.tr("Vergleich schließen (Esc)"),
            accent: OipTokens.cyan,
            onPressed: onClose,
          ),
        ]),
        const Hairline(),
        if (devices.isEmpty && edges.isEmpty)
          WorkstationNote(
            context.tr("Noch keine Engineering-Auswahl"),
            context.tr(
                "Geräte im Explorer oder Inspector mit C hinzufügen. Pfade lassen sich im Verbindungs- oder Edge-Inspector vergleichen. Maximal vier Einträge je fachlicher Kategorie."),
            icon: Icons.compare_arrows_outlined,
            color: OipTokens.cyan,
          )
        else if (bounded)
          Expanded(child: content)
        else
          SizedBox(height: 620, child: content),
      ]),
    );
  }

  Widget _deviceTable(BuildContext context) {
    const attributes = [
      'Device-ID',
      'Kategorie · Registry',
      'Source',
      'Status · gemeldet',
      'Freshness · geliefert',
      'Direkte Relationen',
      'Relation unbekannt',
      'Observation Quality',
      'Collection Errors',
      'Observed / Source Time',
      'Provenienz',
    ];
    return _compareTable(
      context,
      title: 'GERÄTEVERGLEICH · ${devices.length}/4',
      empty:
          'Keine Geräte ausgewählt. Über Explorer oder Node Inspector hinzufügen.',
      attributes: attributes,
      entries: devices,
      header: (device) => device.name,
      value: (device, attribute) {
        final observations = snapshot.metrics
            .where((observation) =>
                observation.entityId == device.id ||
                (device.sourceId != null &&
                    observation.sourceId == device.sourceId))
            .toList();
        final qualities =
            observations.map((o) => known(o.quality)).toSet().toList()..sort();
        final errors = observations
            .where((observation) => observation.collectionError != null)
            .toList();
        final times = observations
            .map((observation) => observation.sourceMs)
            .whereType<int>()
            .toSet()
            .toList()
          ..sort();
        final related = networkDeviceEdges(device.id, networkEdges(snapshot));
        return switch (attribute) {
          'Device-ID' => device.id,
          'Kategorie · Registry' => deviceKindName(device.kind),
          'Source' => device.sourceId ?? 'Nicht geliefert',
          'Status · gemeldet' => known(device.health.reachability),
          'Freshness · geliefert' => known(device.health.freshness),
          'Direkte Relationen' => '${related.length}',
          'Relation unbekannt' =>
            related.isEmpty ? 'Ja · keine Kante geliefert' : 'Nein',
          'Observation Quality' =>
            qualities.isEmpty ? 'Nicht geliefert' : qualities.join(' / '),
          'Collection Errors' => errors.isEmpty
              ? 'Keine geliefert'
              : errors.map((o) => o.collectionError!).toSet().join(' · '),
          'Observed / Source Time' => times.isEmpty
              ? 'Nicht verfügbar'
              : times.map(timestamp).join(' / '),
          'Provenienz' =>
            device.simulated ? 'Demo / Simulation' : 'API / Backend',
          _ => 'Unbekannt',
        };
      },
      onRemove: onRemoveDevice,
      onSelect: onSelectDevice,
    );
  }

  Widget _edgeTable(BuildContext context) {
    const attributes = [
      'Endpoint A',
      'Endpoint B',
      'Connection ID',
      'Typ · Transport',
      'Status · belegt',
      'RTT',
      'Packet Loss',
      'Messdatenverfügbarkeit',
      'Zeitstempel',
      'Provenienz',
    ];
    return _compareTable(
      context,
      title: 'VERBINDUNGSVERGLEICH · ${edges.length}/4',
      empty:
          'Keine logischen Pfade ausgewählt. Über Verbindungsliste oder Edge Inspector hinzufügen.',
      attributes: attributes,
      entries: edges,
      header: (edge) => edge.shortLabel,
      value: (edge, attribute) {
        final link = edge.link;
        return switch (attribute) {
          'Endpoint A' => link.from,
          'Endpoint B' => link.to,
          'Connection ID' => 'Nicht im Legacy-DTO enthalten',
          'Typ · Transport' => '${networkEdgeKind(link)} · ${link.transport}',
          'Status · belegt' => known(link.status),
          'RTT' => networkLinkRtt(link),
          'Packet Loss' => networkLinkLoss(link),
          'Messdatenverfügbarkeit' => link.simulated
              ? 'Nur Demo-Fixture · keine Betriebsmessung'
              : 'Gelieferte Felder; Messmethode nicht belegt',
          'Zeitstempel' => 'Nicht im Link-DTO enthalten',
          'Provenienz' => link.simulated ? 'Demo / Fixture' : 'API / Backend',
          _ => 'Unbekannt',
        };
      },
      onRemove: onRemoveEdge,
      onSelect: onSelectEdge,
    );
  }

  Widget _compareTable<T>(
    BuildContext context, {
    required String title,
    required String empty,
    required List<String> attributes,
    required List<T> entries,
    required String Function(T) header,
    required String Function(T, String) value,
    required ValueChanged<T> onRemove,
    required ValueChanged<T> onSelect,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: WorkstationTokens.eyebrow(context, color: OipTokens.cyan)),
      const SizedBox(height: 8),
      if (entries.isEmpty)
        Text(empty, style: Theme.of(context).textTheme.bodySmall)
      else
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: 160 + entries.length * 220),
            child: Table(
              columnWidths: {
                0: const FixedColumnWidth(160),
                for (var index = 0; index < entries.length; index++)
                  index + 1: const FixedColumnWidth(220),
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
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.all(7),
                      child: Row(children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => onSelect(entry),
                            child: Text(header(entry),
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall),
                          ),
                        ),
                        ToolButton(
                          icon: Icons.close,
                          tooltip: context.tr(
                              "{0} aus Vergleich entfernen", [header(entry)]),
                          accent: OipTokens.cyan,
                          onPressed: () => onRemove(entry),
                        ),
                      ]),
                    ),
                ]),
                for (final attribute in attributes)
                  TableRow(children: [
                    _cell(context, attribute, header: true),
                    for (final entry in entries)
                      _cell(context, value(entry, attribute)),
                  ]),
              ],
            ),
          ),
        ),
    ]);
  }

  Widget _cell(BuildContext context, String value, {bool header = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        child: SelectableText(
          value,
          style: header
              ? WorkstationTokens.eyebrow(context)
              : WorkstationTokens.mono(context, size: 11),
        ),
      );
}
