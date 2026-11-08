import 'package:flutter/material.dart';

import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import '../../models/infrastructure.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'network_model.dart';

/// Dense, keyboard-accessible inventory explorer. Every row is backed by a
/// registered Device; relation counts come only from delivered logical links.
class NetworkDeviceExplorer extends StatelessWidget {
  final Snapshot snapshot;
  final List<NetworkEdge> edges;
  final List<Device> devices;
  final List<Device> recent;
  final Set<String> pinned;
  final Set<String> compared;
  final String? selectedId;
  final String query;
  final String? kindFilter, statusFilter;
  final NetworkRelationFilter relationFilter;
  final NetworkDeviceSort sort;
  final bool transportLive, showFilters;
  final TextEditingController searchController;
  final FocusNode searchFocus, listFocus;
  final ValueChanged<String> onQuery;
  final VoidCallback onClearSearch, onToggleFilters;
  final ValueChanged<String?> onKind, onStatus;
  final ValueChanged<NetworkRelationFilter> onRelation;
  final ValueChanged<NetworkDeviceSort> onSort;
  final ValueChanged<Device> onSelect, onPin, onCompare;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final InfrastructureContext? infrastructure;
  final String contextGrouping;
  final ValueChanged<String?> onContextGrouping;

  const NetworkDeviceExplorer({
    super.key,
    required this.snapshot,
    required this.edges,
    required this.devices,
    required this.recent,
    required this.pinned,
    required this.compared,
    required this.selectedId,
    required this.query,
    required this.kindFilter,
    required this.statusFilter,
    required this.relationFilter,
    required this.sort,
    required this.transportLive,
    required this.showFilters,
    required this.searchController,
    required this.searchFocus,
    required this.listFocus,
    required this.onQuery,
    required this.onClearSearch,
    required this.onToggleFilters,
    required this.onKind,
    required this.onStatus,
    required this.onRelation,
    required this.onSort,
    required this.onSelect,
    required this.onPin,
    required this.onCompare,
    required this.onKeyEvent,
    this.infrastructure,
    this.contextGrouping = 'none',
    required this.onContextGrouping,
  });

  @override
  Widget build(BuildContext context) {
    final linked = networkLinkedDeviceIds(edges);
    final knownCount =
        snapshot.devices.where((device) => linked.contains(device.id)).length;
    final unknownCount = snapshot.devices.length - knownCount;
    final kinds = snapshot.devices.map((device) => device.kind).toSet().toList()
      ..sort();
    return WorkstationPanel(
      key: const Key('network-device-explorer'),
      accent: OipTokens.cyan,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 8, 8),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DEVICE EXPLORER',
                        style: WorkstationTokens.eyebrow(context,
                            color: OipTokens.cyan)),
                    const SizedBox(height: 2),
                    Text('${devices.length}/${snapshot.devices.length} Geräte',
                        style: Theme.of(context).textTheme.titleSmall),
                  ]),
            ),
            ToolButton(
              key: const Key('network-filters-toggle'),
              icon: Icons.filter_alt_outlined,
              tooltip: 'Explorer-Filter anzeigen oder ausblenden',
              accent: OipTokens.cyan,
              active: showFilters ||
                  kindFilter != null ||
                  statusFilter != null ||
                  relationFilter != NetworkRelationFilter.all,
              onPressed: onToggleFilters,
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: TextField(
            key: const Key('network-search'),
            controller: searchController,
            focusNode: searchFocus,
            onChanged: onQuery,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Name, ID oder Source',
              prefixIcon: const Icon(Icons.search, size: 17),
              suffixIcon: query.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Align(
                          widthFactor: 1, heightFactor: 1, child: KbdHint('/')))
                  : IconButton(
                      tooltip: 'Suche löschen',
                      onPressed: onClearSearch,
                      icon: const Icon(Icons.close, size: 16)),
            ),
          ),
        ),
        if (showFilters)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Column(children: [
              _dropdown<NetworkRelationFilter>(
                context,
                key: const Key('network-relation-filter'),
                label: 'Relation',
                value: relationFilter,
                values: NetworkRelationFilter.values,
                itemLabel: networkRelationFilterLabel,
                onChanged: (value) => onRelation(value!),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: _dropdown<String>(
                    context,
                    key: const Key('network-kind-filter'),
                    label: 'Typ',
                    value: kindFilter,
                    values: kinds,
                    nullable: true,
                    onChanged: onKind,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _dropdown<String>(
                    context,
                    key: const Key('network-status-filter'),
                    label: 'Status',
                    value: statusFilter,
                    values: const ['reachable', 'unknown', 'attention'],
                    nullable: true,
                    itemLabel: (value) =>
                        value == 'attention' ? 'Aufmerksamkeit' : known(value),
                    onChanged: onStatus,
                  ),
                ),
              ]),
              if (infrastructure?.ready == true) ...[
                const SizedBox(height: 6),
                _dropdown<String>(
                  context,
                  key: const Key('network-context-grouping'),
                  label: 'Kontextgruppe',
                  value: contextGrouping,
                  values: const [
                    'none',
                    'organization',
                    'infrastructure',
                    'site',
                    'segment'
                  ],
                  itemLabel: (value) => switch (value) {
                    'none' => 'Keine Kontextgruppe',
                    'organization' => 'Organization',
                    'infrastructure' => 'Infrastructure',
                    'site' => 'Site',
                    'segment' => 'Registry-Segment',
                    _ => value,
                  },
                  onChanged: onContextGrouping,
                ),
              ],
              const SizedBox(height: 6),
              _dropdown<NetworkDeviceSort>(
                context,
                key: const Key('network-sort'),
                label: 'Sortierung',
                value: sort,
                values: NetworkDeviceSort.values,
                itemLabel: networkDeviceSortLabel,
                onChanged: (value) => onSort(value!),
              ),
            ]),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: WorkstationTokens.well(context),
          child: Wrap(spacing: 8, runSpacing: 3, children: [
            Text('TOPOLOGIE $knownCount',
                style:
                    WorkstationTokens.eyebrow(context, color: OipTokens.cyan)),
            Text('RELATION UNBEKANNT $unknownCount',
                style: WorkstationTokens.eyebrow(context)),
          ]),
        ),
        if (pinned.isNotEmpty || recent.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 3),
            child: Wrap(spacing: 5, runSpacing: 5, children: [
              for (final device
                  in snapshot.devices.where((d) => pinned.contains(d.id)))
                InputChip(
                  key: Key('network-pin-${device.id}'),
                  avatar: const Icon(Icons.push_pin, size: 13),
                  label: Text(device.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10)),
                  selected: selectedId == device.id,
                  onPressed: () => onSelect(device),
                  onDeleted: () => onPin(device),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              if (recent.isNotEmpty)
                Tooltip(
                  message:
                      'Zuletzt ausgewählt: ${recent.map((d) => d.name).join(', ')}',
                  child: Chip(
                    avatar: const Icon(Icons.history, size: 14),
                    label: Text('Zuletzt ${recent.length}',
                        style: const TextStyle(fontSize: 10)),
                  ),
                ),
            ]),
          ),
        Expanded(
          child: Focus(
            focusNode: listFocus,
            onKeyEvent: onKeyEvent,
            child: Builder(builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return Container(
                foregroundDecoration: BoxDecoration(
                  border: Border.all(
                      color: focused
                          ? OipTokens.readableAccent(context, OipTokens.cyan)
                          : Colors.transparent),
                ),
                child: devices.isEmpty
                    ? const SingleChildScrollView(
                        padding: EdgeInsets.all(14),
                        child: WorkstationNote(
                          'Keine Geräte im Filter',
                          'Suche oder Filter ändern. Ein leeres Ergebnis bedeutet weder Offline noch Isolation.',
                          icon: Icons.search_off_outlined,
                        ),
                      )
                    : ListView.builder(
                        key: const Key('network-device-list'),
                        padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
                        itemCount: devices.length,
                        itemBuilder: (context, index) {
                          final device = devices[index];
                          final group = _contextGroup(device, linked);
                            final showGroup = index == 0 ||
                                _contextGroup(devices[index - 1], linked) != group;
                          return Column(children: [
                            if (showGroup)
                              _groupLabel(
                                  context,
                                  group),
                            _DeviceRow(
                              device: device,
                              relationCount:
                                  networkDeviceEdges(device.id, edges).length,
                              selected: selectedId == device.id,
                              pinned: pinned.contains(device.id),
                              compared: compared.contains(device.id),
                              transportLive: transportLive,
                              onTap: () => onSelect(device),
                              onPin: () => onPin(device),
                              onCompare: () => onCompare(device),
                            ),
                          ]);
                        },
                      ),
              );
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 9),
          child: Text(
            'Pfeile Auswahl · Enter Inspector · P Pin · C Compare\nRelation unbekannt ist nicht offline oder isoliert',
            style: WorkstationTokens.mono(context,
                size: 9.5, color: OipTokens.muted(context)),
          ),
        ),
      ]),
    );
  }

  String _contextGroup(Device device, Set<String> linked) {
    if (contextGrouping == 'none') {
      return linked.contains(device.id)
          ? 'BEKANNTE TOPOLOGIE-ENDPUNKTE'
          : 'REGISTRIERT · RELATION UNBEKANNT';
    }
    if (contextGrouping == 'segment') {
      return 'REGISTRY-SEGMENT · ${device.location}';
    }
    final placement = infrastructure?.devicePlacement(device);
    if (placement == null) return 'KONTEXT NICHT GELIEFERT';
    return switch (contextGrouping) {
      'organization' =>
        'ORGANIZATION · ${infrastructure!.hierarchy.organizationName(placement.organizationId)}',
      'infrastructure' =>
        'INFRASTRUCTURE · ${infrastructure!.hierarchy.infrastructureName(placement.infrastructureId)}',
      'site' => 'SITE · ${infrastructure!.hierarchy.siteName(placement.siteId)}',
      _ => 'KONTEXT NICHT GELIEFERT',
    };
  }

  Widget _groupLabel(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(7, 8, 7, 4),
        child: Text(label, style: WorkstationTokens.eyebrow(context)),
      );

  Widget _dropdown<T>(
    BuildContext context, {
    required Key key,
    required String label,
    required T? value,
    required List<T> values,
    required ValueChanged<T?> onChanged,
    String Function(T)? itemLabel,
    bool nullable = false,
  }) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: WorkstationTokens.well(context),
        border: Border.all(color: WorkstationTokens.hairline(context)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: DropdownButton<T>(
        key: key,
        value: value,
        underline: const SizedBox.shrink(),
        isDense: true,
        isExpanded: true,
        style: Theme.of(context).textTheme.bodySmall,
        items: [
          if (nullable)
            DropdownMenuItem<T>(
                value: null,
                child: Text('$label: alle', overflow: TextOverflow.ellipsis)),
          for (final item in values)
            DropdownMenuItem<T>(
              value: item,
              child: Text(
                  nullable
                      ? itemLabel?.call(item) ?? '$item'
                      : '$label: ${itemLabel?.call(item) ?? '$item'}',
                  overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final Device device;
  final int relationCount;
  final bool selected, pinned, compared, transportLive;
  final VoidCallback onTap, onPin, onCompare;

  const _DeviceRow({
    required this.device,
    required this.relationCount,
    required this.selected,
    required this.pinned,
    required this.compared,
    required this.transportLive,
    required this.onTap,
    required this.onPin,
    required this.onCompare,
  });

  @override
  Widget build(BuildContext context) {
    final status = transportLive ? device.health.reachability : 'stale';
    final statusColor = OipTokens.statusColor(context, status);
    final accent = OipTokens.readableAccent(context, OipTokens.violet);
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: 'Gerät ${device.name} auswählen, ID ${device.id}, '
          'Status ${known(status)}, $relationCount bekannte logische Verbindungen, '
          '${device.simulated ? 'Demo-Inventar' : 'API-Inventar'}',
      child: Material(
        color: selected ? accent.withOpacity(.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          key: Key('explorer-device-${device.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.fromLTRB(7, 6, 3, 6),
            decoration: BoxDecoration(
              border: Border(
                  left: BorderSide(
                      color: selected ? accent : Colors.transparent, width: 2)),
            ),
            child: Row(children: [
              Icon(networkKindIcon(device.kind),
                  size: 19,
                  color: OipTokens.readableAccent(context, OipTokens.cyan)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(device.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(
                        '${known(status)} · $relationCount Relationen · ${device.simulated ? 'Demo' : 'API'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WorkstationTokens.mono(context,
                            size: 9.5, color: statusColor),
                      ),
                      if (device.sourceId != null)
                        Text('Source ${device.sourceId}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WorkstationTokens.mono(context,
                                size: 9, color: OipTokens.muted(context))),
                    ]),
              ),
              IconButton(
                key: Key('explorer-compare-${device.id}'),
                tooltip: compared
                    ? '${device.name} aus Vergleich entfernen'
                    : '${device.name} vergleichen',
                onPressed: onCompare,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                    compared
                        ? Icons.compare_arrows
                        : Icons.compare_arrows_outlined,
                    size: 16,
                    color: compared ? OipTokens.cyan : null),
              ),
              IconButton(
                key: Key('explorer-pin-${device.id}'),
                tooltip: pinned
                    ? '${device.name} loslösen'
                    : '${device.name} anheften',
                onPressed: onPin,
                visualDensity: VisualDensity.compact,
                icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 16, color: pinned ? accent : null),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
