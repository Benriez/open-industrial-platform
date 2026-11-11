import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'overview_selection.dart';
import '../../widgets/device_kind.dart';

class InfrastructureExplorer extends StatefulWidget {
  final Snapshot snapshot;
  final List<SourceInfo> sources;
  final OverviewSelection selection;
  final ValueChanged<SourceInfo> onSource;
  final ValueChanged<Device> onDevice;
  const InfrastructureExplorer({
    super.key,
    required this.snapshot,
    required this.sources,
    required this.selection,
    required this.onSource,
    required this.onDevice,
  });

  @override
  State<InfrastructureExplorer> createState() => _InfrastructureExplorerState();
}

class _InfrastructureExplorerState extends State<InfrastructureExplorer> {
  final searchController = TextEditingController();
  final listFocus = FocusNode(debugLabel: 'overview-infrastructure-list');
  final listScroll = ScrollController();
  String telemetryFilter = 'all';

  @override
  void dispose() {
    searchController.dispose();
    listFocus.dispose();
    listScroll.dispose();
    super.dispose();
  }

  String _deviceTelemetry(Device device) {
    final signals = overviewSignalsFor(widget.snapshot,
        sourceId: device.sourceId, deviceId: device.id);
    if (signals.isEmpty) return 'none';
    if (signals.any((signal) => signal.freshness == 'fresh')) return 'fresh';
    if (signals.any((signal) => signal.freshness == 'stale')) return 'stale';
    return 'unknown';
  }

  String _sourceTelemetry(SourceInfo source) {
    final signals = overviewSignalsFor(widget.snapshot, sourceId: source.id);
    if (signals.isEmpty) return 'none';
    if (signals.any((signal) => signal.freshness == 'fresh')) return 'fresh';
    if (signals.any((signal) => signal.freshness == 'stale')) return 'stale';
    return 'unknown';
  }

  bool _matchesTelemetry(String state) => switch (telemetryFilter) {
        'fresh' => state == 'fresh',
        'stale' => state == 'stale' || state == 'unknown',
        'none' => state == 'none',
        _ => true,
      };

  List<Widget> _rows(List<_ExplorerEntry> entries) {
    final query = searchController.text.trim().toLowerCase();
    final children = <Widget>[];
    for (final source in widget.sources) {
      final signals = overviewSignalsFor(widget.snapshot, sourceId: source.id);
      final devices = widget.snapshot.devices
          .where((device) => device.sourceId == source.id)
          .toList();
      final sourceMatches =
          '$source.name $source.id'.toLowerCase().contains(query);
      final matchingDevices = devices.where((device) {
        final matchesQuery = query.isEmpty ||
            '${device.name} ${device.id} ${device.kind} ${device.sourceId ?? ''}'
                .toLowerCase()
                .contains(query);
        return matchesQuery && _matchesTelemetry(_deviceTelemetry(device));
      }).toList();
      if (query.isNotEmpty && !sourceMatches && matchingDevices.isEmpty) {
        continue;
      }
      if (!_matchesTelemetry(_sourceTelemetry(source)) &&
          matchingDevices.isEmpty) {
        continue;
      }
      final sourceEntry = _ExplorerEntry.source(source);
      entries.add(sourceEntry);
      children.add(_sourceRow(source, signals.length));
      for (final device in matchingDevices) {
        entries.add(_ExplorerEntry.device(device, source.id));
        children.add(_deviceRow(device));
      }
    }
    final unassigned = widget.snapshot.devices
        .where((device) =>
            device.sourceId == null ||
            !widget.sources.any((source) => source.id == device.sourceId))
        .where((device) {
      final matchesQuery = query.isEmpty ||
          '${device.name} ${device.id} ${device.kind}'
              .toLowerCase()
              .contains(query);
      return matchesQuery && _matchesTelemetry(_deviceTelemetry(device));
    }).toList();
    if (unassigned.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
        child: Text('KEINE SOURCE-ZUORDNUNG',
            style: WorkstationTokens.eyebrow(context)),
      ));
      for (final device in unassigned) {
        entries.add(_ExplorerEntry.device(device, device.sourceId));
        children.add(_deviceRow(device));
      }
    }
    return children;
  }

  Widget _sourceRow(SourceInfo source, int signalCount) {
    final selected = widget.selection.kind == OverviewSelectionKind.source &&
        widget.selection.sourceId == source.id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Material(
        color: selected
            ? OipTokens.cyan.withOpacity(.12)
            : WorkstationTokens.well(context),
        borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
        child: Semantics(
          button: true,
          selected: selected,
          excludeSemantics: true,
          label: 'Source ${source.name} ${source.id} auswählen · '
              '$signalCount Signale · ${known(source.connection)} · ${known(source.freshness)}',
          child: ListTile(
            key: Key('overview-explorer-source-${source.id}'),
            dense: true,
            minTileHeight: 52,
            selected: selected,
            selectedColor: OipTokens.readableAccent(context, OipTokens.cyan),
            leading: StatusDot(source.connection),
            title: Text(source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
                '${source.id} · $signalCount Signale\n${known(source.connection)} · ${known(source.freshness)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            onTap: () => widget.onSource(source),
          ),
        ),
      ),
    );
  }

  Widget _deviceRow(Device device) {
    final selected = widget.selection.kind == OverviewSelectionKind.device &&
        widget.selection.deviceId == device.id;
    final telemetry = _deviceTelemetry(device);
    final source = device.sourceId ?? 'keine Source';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 1, 6, 1),
      child: Material(
        color:
            selected ? OipTokens.violet.withOpacity(.13) : Colors.transparent,
        borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
        child: Semantics(
          button: true,
          selected: selected,
          excludeSemantics: true,
          label:
              'Gerät ${device.name} ${device.id} auswählen · ${deviceKindName(device.kind)} · '
              '$source · Daten ${_telemetryLabel(telemetry)} · Reachability ${known(device.health.reachability)} reported',
          child: ListTile(
            key: Key('overview-explorer-device-${device.id}'),
            dense: true,
            minTileHeight: 56,
            selected: selected,
            leading: Icon(Icons.dns_outlined,
                size: 17,
                color: selected
                    ? OipTokens.readableAccent(context, OipTokens.violet)
                    : OipTokens.muted(context)),
            title: Text('${device.name} · ${device.id}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5)),
            subtitle: Text(
                '${deviceKindName(device.kind)} · $source\n'
                'Daten: ${_telemetryLabel(telemetry)} · Reachability: ${known(device.health.reachability)} (reported)',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5)),
            onTap: () => widget.onDevice(device),
          ),
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final entries = <_ExplorerEntry>[];
    _rows(entries);
    if (entries.isEmpty) return KeyEventResult.ignored;
    var index = entries.indexWhere((entry) => entry.selected(widget.selection));
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      index = (index + 1).clamp(0, entries.length - 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      index = index <= 0 ? 0 : index - 1;
    } else if (key == LogicalKeyboardKey.home) {
      index = 0;
    } else if (key == LogicalKeyboardKey.end) {
      index = entries.length - 1;
    } else {
      return KeyEventResult.ignored;
    }
    entries[index].select(widget);
    if (listScroll.hasClients) {
      final target = (index * 58.0).clamp(listScroll.position.minScrollExtent,
          listScroll.position.maxScrollExtent);
      listScroll.animateTo(target,
          duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final entries = <_ExplorerEntry>[];
    final rows = _rows(entries);
    return WorkstationPanel(
      key: const Key('overview-infrastructure-explorer'),
      accent: OipTokens.cyan,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelLabel('Infrastructure Explorer',
            trailing: Text(
                '${widget.sources.length}S · ${widget.snapshot.devices.length}D',
                style: WorkstationTokens.mono(context, size: 10))),
        TextField(
          key: const Key('overview-explorer-search'),
          controller: searchController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 17),
            hintText: 'Source, Gerät, Typ …',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 7),
        DropdownButtonFormField<String>(
          key: const Key('overview-explorer-filter'),
          isExpanded: true,
          value: telemetryFilter,
          decoration: const InputDecoration(
              isDense: true,
              labelText: 'TELEMETRIE',
              border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Alle Zustände')),
            DropdownMenuItem(value: 'fresh', child: Text('Frisch beobachtet')),
            DropdownMenuItem(value: 'stale', child: Text('Stale / unknown')),
            DropdownMenuItem(value: 'none', child: Text('Keine Telemetrie')),
          ],
          onChanged: (value) =>
              setState(() => telemetryFilter = value ?? 'all'),
        ),
        const SizedBox(height: 7),
        Expanded(
          child: Focus(
            key: const Key('overview-explorer-list'),
            focusNode: listFocus,
            onKeyEvent: _onKey,
            child: rows.isEmpty
                ? const Center(
                    child: Text('Keine Registry-Einträge im aktuellen Filter.',
                        textAlign: TextAlign.center))
                : ListView(
                    controller: listScroll,
                    children: rows,
                  ),
          ),
        ),
        const SizedBox(height: 5),
        Builder(builder: (context) {
          final states = widget.snapshot.devices.map(_deviceTelemetry).toList();
          return Text(
              'FRESH OBSERVED ${states.where((state) => state == 'fresh').length} · '
              'STALE / UNKNOWN ${states.where((state) => state == 'stale' || state == 'unknown').length} · '
              'NO TELEMETRY ${states.where((state) => state == 'none').length}',
              style: WorkstationTokens.eyebrow(context));
        }),
        const SizedBox(height: 3),
        Text('Pfeile Auswahl · Enter öffnet Zeile · reported ≠ gemessen',
            style: WorkstationTokens.mono(context,
                size: 9.5, color: OipTokens.muted(context))),
      ]),
    );
  }
}

String _telemetryLabel(String state) => switch (state) {
      'fresh' => 'fresh',
      'stale' => 'stale',
      'none' => 'keine',
      _ => 'unknown',
    };

class _ExplorerEntry {
  final SourceInfo? source;
  final Device? device;
  final String? sourceId;
  const _ExplorerEntry.source(SourceInfo this.source)
      : device = null,
        sourceId = null;
  const _ExplorerEntry.device(Device this.device, this.sourceId)
      : source = null;
  bool selected(OverviewSelection selection) => source != null
      ? selection.kind == OverviewSelectionKind.source &&
          selection.sourceId == source!.id
      : selection.kind == OverviewSelectionKind.device &&
          selection.deviceId == device!.id;
  void select(InfrastructureExplorer widget) {
    if (source != null) widget.onSource(source!);
    if (device != null) widget.onDevice(device!);
  }
}
