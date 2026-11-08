import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import '../../models/infrastructure.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'device_session.dart';
import 'devices_layout.dart';

List<Observation> deviceSnapshotObservations(
        Snapshot snapshot, Device device) =>
    snapshot.metrics
        .where((item) =>
            device.sourceId != null &&
            item.sourceId == device.sourceId &&
            item.entityId == device.id)
        .toList();

String deviceObservedFreshness(Snapshot snapshot, Device device) =>
    observedFreshnessOf(deviceSnapshotObservations(snapshot, device));

String deviceObservedQuality(Snapshot snapshot, Device device) =>
    observedQualityOf(deviceSnapshotObservations(snapshot, device));

/// Freshness of the observations that are actually displayed. The displayed
/// set is the authorized DeviceDetail scope (live-replaced by exact identity),
/// never the bulk snapshot, so the workspace and the inspector describe the
/// same observations the user sees.
String observedFreshnessOf(List<Observation> values) {
  if (values.isEmpty) return 'unknown';
  if (values.every((item) => item.freshness == 'fresh')) return 'fresh';
  if (values.any((item) => item.freshness == 'fresh')) return 'mixed';
  if (values.any((item) => item.freshness == 'stale')) return 'stale';
  return 'unknown';
}

/// Quality of the observations that are actually displayed.
String observedQualityOf(List<Observation> values) {
  if (values.isEmpty) return 'unknown';
  if (values.every((item) => item.quality == 'good')) return 'good';
  if (values.any((item) => item.quality == 'bad')) return 'bad';
  return 'mixed';
}

List<Device> filteredDevices(
    Snapshot snapshot, DevicesWorkspaceSession session,
    [InfrastructureContext? infrastructure]) {
  final query = session.search.trim().toLowerCase();
  final result = snapshot.devices.where((device) {
    final observed = deviceSnapshotObservations(snapshot, device);
    final observedFreshness = deviceObservedFreshness(snapshot, device);
    final quality = deviceObservedQuality(snapshot, device);
    final placement = infrastructure?.devicePlacement(device);
    final hierarchyText = placement == null || infrastructure == null
        ? ''
        : '${infrastructure.hierarchy.organizationName(placement.organizationId)} '
            '${infrastructure.hierarchy.infrastructureName(placement.infrastructureId)} '
            '${infrastructure.hierarchy.siteName(placement.siteId)}';
    final matchesQuery = query.isEmpty ||
        '${device.id} ${device.name} ${device.kind} ${device.sourceId ?? ''} '
                '${device.location} ${device.connection} $hierarchyText'
            .toLowerCase()
            .contains(query);
    final matchesScope = switch (session.scope) {
      'pinned' => session.pinned.contains(device.id),
      'recent' => session.recents.contains(device.id),
      _ => true,
    };
    final matchesFreshness = switch (session.freshness) {
      'observed-fresh' => observedFreshness == 'fresh',
      'observed-stale' =>
        observedFreshness == 'stale' || observedFreshness == 'mixed',
      'reported-unknown' =>
        observed.isEmpty || device.health.freshness == 'unknown',
      'none' => observed.isEmpty,
      _ => true,
    };
    final matchesConnectivity = switch (session.connectivity) {
      'reported-reachable' => device.health.reachability == 'reachable',
      'reported-unreachable' => device.health.reachability == 'unreachable' ||
          device.health.reachability == 'offline',
      'unknown' => device.health.reachability == 'unknown',
      'simulated' => device.simulated,
      _ => true,
    };
    return matchesQuery &&
        matchesScope &&
        (session.type == 'all' || device.kind == session.type) &&
        (session.source == 'all' ||
            (session.source == 'unassigned'
                ? device.sourceId == null
                : device.sourceId == session.source)) &&
        (session.location == 'all' || device.location == session.location) &&
        (session.quality == 'all' || quality == session.quality) &&
        matchesFreshness &&
        matchesConnectivity;
  }).toList();
  int text(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
  result.sort((a, b) => switch (session.sort) {
        'type' => text(a.kind, b.kind) != 0
            ? text(a.kind, b.kind)
            : text(a.name, b.name),
        'location' => text(a.location, b.location) != 0
            ? text(a.location, b.location)
            : text(a.name, b.name),
        'source' => text(a.sourceId ?? 'zzz', b.sourceId ?? 'zzz') != 0
            ? text(a.sourceId ?? 'zzz', b.sourceId ?? 'zzz')
            : text(a.name, b.name),
        'freshness' => text(deviceObservedFreshness(snapshot, a),
                    deviceObservedFreshness(snapshot, b)) !=
                0
            ? text(deviceObservedFreshness(snapshot, a),
                deviceObservedFreshness(snapshot, b))
            : text(a.name, b.name),
        _ => text(a.name, b.name),
      });
  return result;
}

class DeviceFilterBar extends StatelessWidget {
  final Snapshot snapshot;
  final DevicesWorkspaceSession session;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final VoidCallback changed;
  final InfrastructureContext? infrastructure;
  const DeviceFilterBar({
    super.key,
    required this.snapshot,
    required this.session,
    required this.searchController,
    required this.searchFocus,
    required this.changed,
    this.infrastructure,
  });

  /// Toolbar width below which the filters wrap into a stacked layout.
  static const _wideToolbar = 1080.0;

  /// Fixed width of the secondary-filter disclosure.
  static const _moreFiltersWidth = 170.0;

  @override
  Widget build(BuildContext context) {
    final types = snapshot.devices.map((item) => item.kind).toSet().toList()
      ..sort();
    final sources = snapshot.devices.map((item) => item.sourceId).toSet();
    final locations =
        snapshot.devices.map((item) => item.location).toSet().toList()..sort();
    return WorkstationPanel(
      key: const Key('device-filter-bar'),
      padding: const EdgeInsets.symmetric(
          horizontal: DevicesLayout.panelPadding,
          vertical: DevicesLayout.controlGap),
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= _wideToolbar;
        final stackedWidth =
            box.maxWidth < 760 ? (box.maxWidth - 8) / 2 : 168.0;
        double width(double wideWidth) => wide ? wideWidth : stackedWidth;

        final search = SizedBox(
          width: wide ? 190 : box.maxWidth,
          height: DevicesLayout.controlHeight,
          child: TextField(
            key: const Key('device-search'),
            controller: searchController,
            focusNode: searchFocus,
            onChanged: (value) {
              session.search = value;
              session.offset = 0;
              changed();
            },
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10),
              prefixIcon: Icon(Icons.search, size: 16),
              prefixIconConstraints: BoxConstraints(minWidth: 30, minHeight: 30),
              hintText: 'Name, ID, Typ, Source …',
              border: OutlineInputBorder(),
            ),
          ),
        );

        final primary = <Widget>[
          _filter(
              context,
              'device-type-filter',
              'TYP',
              session.type,
              ['all', ...types],
              width(145),
              (value) => session.type = value),
          _filter(
              context,
              'device-source-filter',
              'SOURCE',
              session.source,
              ['all', ...sources.whereType<String>(), 'unassigned'],
              width(150),
              (value) => session.source = value),
          _filter(
              context,
              'filter-Standort',
              'STANDORT',
              session.location,
              ['all', ...locations],
              width(160),
              (value) => session.location = value),
          _filter(
              context,
              'device-sort',
              'SORTIERUNG',
              session.sort,
              ['name', 'type', 'source', 'location', 'freshness'],
              width(150),
              (value) => session.sort = value),
        ];
        final secondary = <Widget>[
          _filter(
              context,
              'device-quality-filter',
              'QUALITÄT',
              session.quality,
              ['all', 'good', 'bad', 'mixed', 'unknown'],
              width(150),
              (value) => session.quality = value),
          _filter(
              context,
              'device-freshness-filter',
              'FRESHNESS',
              session.freshness,
              [
                'all',
                'observed-fresh',
                'observed-stale',
                'reported-unknown',
                'none'
              ],
              width(160),
              (value) => session.freshness = value),
          _filter(
              context,
              'device-connectivity-filter',
              'CONNECTIVITY',
              session.connectivity,
              [
                'all',
                'reported-reachable',
                'reported-unreachable',
                'unknown',
                'simulated'
              ],
              width(175),
              (value) => session.connectivity = value),
        ];

        final activeSecondary = [
          session.quality,
          session.freshness,
          session.connectivity
        ].where((value) => value != 'all').length;

        final toggle = SizedBox(
          width: _moreFiltersWidth,
          child: _MoreFiltersButton(
            activeCount: activeSecondary,
            expanded: session.showAdvancedFilters,
            onTap: () {
              session.showAdvancedFilters = !session.showAdvancedFilters;
              changed();
            },
          ),
        );
        final reset = SizedBox(
          width: DevicesLayout.controlHeight,
          height: DevicesLayout.controlHeight,
          child: IconButton(
            key: const Key('device-filter-reset'),
            tooltip: 'Filter zurücksetzen',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            onPressed: () {
              session.resetFilters();
              searchController.clear();
              changed();
            },
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
          ),
        );
        final note = Text(
          infrastructure?.ready == true
              ? 'v2 autorisierter Scope · UI-Auswahl ist Präsentationsfilter'
              : 'v1-Snapshot · Filter nicht serverseitig',
          style: WorkstationTokens.mono(context,
              size: 9, color: OipTokens.muted(context)),
        );

        if (wide) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              search,
              const SizedBox(width: DevicesLayout.controlGap),
              primary[0],
              const SizedBox(width: DevicesLayout.controlGap),
              primary[1],
              const SizedBox(width: DevicesLayout.controlGap),
              primary[2],
              const SizedBox(width: DevicesLayout.groupGap),
              primary[3],
              const Spacer(),
              toggle,
              const SizedBox(width: DevicesLayout.controlGap),
              reset,
            ]),
            if (session.showAdvancedFilters) ...[
              const SizedBox(height: DevicesLayout.controlGap),
              Row(children: [
                secondary[0],
                const SizedBox(width: DevicesLayout.controlGap),
                secondary[1],
                const SizedBox(width: DevicesLayout.controlGap),
                secondary[2],
              ]),
            ],
            const SizedBox(height: 2),
            Align(alignment: Alignment.centerRight, child: note),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          search,
          const SizedBox(height: DevicesLayout.controlGap),
          Wrap(
            spacing: DevicesLayout.controlGap,
            runSpacing: DevicesLayout.controlGap,
            children: [...primary, toggle],
          ),
          if (session.showAdvancedFilters) ...[
            const SizedBox(height: DevicesLayout.controlGap),
            Wrap(
              spacing: DevicesLayout.controlGap,
              runSpacing: DevicesLayout.controlGap,
              children: secondary,
            ),
          ],
          const SizedBox(height: 2),
          Row(children: [Expanded(child: note), reset]),
        ]);
      }),
    );
  }

  Widget _filter(BuildContext context, String key, String label, String value,
      List<String> values, double width, ValueChanged<String> set) {
    final current = values.contains(value) ? value : 'all';
    final items = values
        .map((item) => DropdownMenuItem(
            value: item,
            child: Text(label == 'STANDORT'
                ? 'Standort: ${_filterValue(item)}'
                : _filterValue(item))))
        .toList();
    return SizedBox(
      width: width,
      child: _FilterSelect(
        controlKey: Key(key),
        label: label,
        value: current,
        display: _filterValue(current),
        items: items,
        onChanged: (next) {
          if (next == null) return;
          set(next);
          session.offset = 0;
          changed();
        },
      ),
    );
  }
}

/// Bordered single-line select with a fixed label column.
///
/// The label is part of the control, so there is no floating label, no
/// overlapping hint and no second row. Every control uses the same label
/// column width, which aligns the values of the whole toolbar.
class _FilterSelect extends StatelessWidget {
  final Key controlKey;
  final String label;
  final String value;
  final String display;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;
  const _FilterSelect({
    required this.controlKey,
    required this.label,
    required this.value,
    required this.display,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
        height: DevicesLayout.controlHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: WorkstationTokens.well(context),
          border: Border.all(color: WorkstationTokens.hairline(context)),
          borderRadius: BorderRadius.circular(7),
        ),
        child: DropdownButton<String>(
          key: controlKey,
          value: value,
          isExpanded: true,
          isDense: true,
          underline: const SizedBox.shrink(),
          padding: EdgeInsets.zero,
          iconSize: 16,
          style:
              Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
          selectedItemBuilder: (context) => items
              .map((item) => Row(children: [
                    SizedBox(
                      width: DevicesLayout.filterLabelWidth - 10,
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WorkstationTokens.eyebrow(context)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(display,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ]))
              .toList(),
          items: items,
          onChanged: onChanged,
        ),
      );
}

/// Disclosure that reveals the secondary filters. The badge counts the
/// secondary filters that are not on their default value.
class _MoreFiltersButton extends StatelessWidget {
  final int activeCount;
  final bool expanded;
  final VoidCallback onTap;
  const _MoreFiltersButton({
    required this.activeCount,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = OipTokens.readableAccent(context, OipTokens.blue);
    return Container(
      height: DevicesLayout.controlHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: expanded
            ? accent.withOpacity(.12)
            : WorkstationTokens.well(context),
        border: Border.all(
            color: expanded ? accent : WorkstationTokens.hairline(context)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Semantics(
        button: true,
        child: InkWell(
          key: const Key('device-more-filters'),
          onTap: onTap,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(expanded ? Icons.expand_less : Icons.tune, size: 15),
          const SizedBox(width: 6),
          Flexible(
            child: Text('Weitere Filter',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
          if (activeCount > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: accent.withOpacity(.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('$activeCount',
                  style: WorkstationTokens.mono(context, size: 9.5, color: accent)),
            ),
          ],
          ]),
        ),
      ),
    );
  }
}

String _filterValue(String value) => switch (value) {
      'all' => 'Alle',
      'unassigned' => 'Keine Source',
      'observed-fresh' => 'Frisch beobachtet',
      'observed-stale' => 'Stale / mixed',
      'reported-unknown' => 'Unknown / reported',
      'none' => 'Keine Telemetrie',
      'reported-reachable' => 'Erreichbar · reported',
      'reported-unreachable' => 'Nicht erreichbar · reported',
      'simulated' => 'Simuliert',
      'name' => 'Name',
      'type' => 'Typ',
      'source' => 'Source',
      'location' => 'Standort',
      'freshness' => 'Freshness',
      _ => known(value),
    };

class DeviceInventoryExplorer extends StatefulWidget {
  final Snapshot snapshot;
  final DevicesWorkspaceSession session;
  final ValueChanged<Device> onSelect;
  final ValueChanged<Device> onPin;
  final ValueChanged<Device> onCompare;
  final VoidCallback? onOpen;
  final InfrastructureContext? infrastructure;
  const DeviceInventoryExplorer({
    super.key,
    required this.snapshot,
    required this.session,
    required this.onSelect,
    required this.onPin,
    required this.onCompare,
    this.onOpen,
    this.infrastructure,
  });

  @override
  State<DeviceInventoryExplorer> createState() =>
      DeviceInventoryExplorerState();
}

class DeviceInventoryExplorerState extends State<DeviceInventoryExplorer> {
  static const pageSize = 50;
  final listFocus = FocusNode(debugLabel: 'device-inventory-list');
  final listScroll = ScrollController();

  /// Moves the keyboard focus into the device list so that arrow keys, Home,
  /// End, P and C act on the inventory right after a selection.
  void requestListFocus() {
    if (!listFocus.hasFocus) listFocus.requestFocus();
  }

  @override
  void dispose() {
    listFocus.dispose();
    listScroll.dispose();
    super.dispose();
  }

  List<Device> get devices =>
      filteredDevices(widget.snapshot, widget.session, widget.infrastructure);

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final visible = devices;
    if (visible.isEmpty) return KeyEventResult.ignored;
    var index =
        visible.indexWhere((item) => item.id == widget.session.selectedId);
    final key = event.logicalKey;
    final selected = widget.snapshot.devices
        .where((item) => item.id == widget.session.selectedId)
        .firstOrNull;
    if (key == LogicalKeyboardKey.keyP && selected != null) {
      widget.onPin(selected);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC && selected != null) {
      widget.onCompare(selected);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      index = (index + 1).clamp(0, visible.length - 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      index = index <= 0 ? 0 : index - 1;
    } else if (key == LogicalKeyboardKey.home) {
      index = 0;
    } else if (key == LogicalKeyboardKey.end) {
      index = visible.length - 1;
    } else if (key == LogicalKeyboardKey.enter) {
      // Enter opens the device under the keyboard cursor in the workspace.
      final device = visible[index.clamp(0, visible.length - 1)];
      widget.onSelect(device);
      widget.onOpen?.call();
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    widget.onSelect(visible[index]);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final all = devices;
    final pages = all.isEmpty ? 1 : (all.length / pageSize).ceil();
    final currentPage = (widget.session.offset ~/ pageSize).clamp(0, pages - 1);
    final offset = currentPage * pageSize;
    final visible = all.skip(offset).take(pageSize).toList();
    final entries = <_InventoryEntry>[];
    String? group;
    for (final device in visible) {
      final next = _group(device);
      if (widget.session.group != 'none' && next != group) {
        group = next;
        entries.add(_InventoryEntry.header(next));
      }
      entries.add(_InventoryEntry.device(device));
    }
    return WorkstationPanel(
      key: const Key('device-inventory-explorer'),
      accent: OipTokens.blue,
      padding: const EdgeInsets.fromLTRB(
          DevicesLayout.panelPadding, 10, DevicesLayout.panelPadding, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelLabel('Inventory Explorer',
            bottom: 4,
            trailing: Text('${all.length}/${widget.snapshot.devices.length}',
                style: WorkstationTokens.mono(context, size: 10))),
        _scopeSegments(context),
        const SizedBox(height: DevicesLayout.controlGap),
        Row(children: [
          Expanded(child: _groupSelect(context)),
          const SizedBox(width: DevicesLayout.controlGap),
          SizedBox(
            width: DevicesLayout.controlHeight,
            height: DevicesLayout.controlHeight,
            child: IconButton(
              key: const Key('device-density'),
              tooltip: widget.session.compact
                  ? 'Comfortable-Dichte'
                  : 'Compact-Dichte',
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints.tightFor(width: 36, height: 36),
              onPressed: () => setState(
                  () => widget.session.compact = !widget.session.compact),
              icon: Icon(
                widget.session.compact
                    ? Icons.density_medium
                    : Icons.density_small,
                size: 18,
              ),
            ),
          ),
        ]),
        const SizedBox(height: DevicesLayout.controlGap),
        Expanded(
          child: Focus(
            key: const Key('device-inventory-list'),
            focusNode: listFocus,
            onKeyEvent: _key,
            child: entries.isEmpty
                ? const Center(
                    child: Text('Keine Geräte gefunden',
                        textAlign: TextAlign.center))
                : SingleChildScrollView(
                    controller: listScroll,
                    child: Column(
                      children: entries.map((entry) {
                        return entry.device == null
                            ? Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(6, 5, 6, 2),
                                child: Text(entry.header!.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: WorkstationTokens.eyebrow(context,
                                        color: OipTokens.cyan)),
                              )
                            : _row(entry.device!);
                      }).toList(),
                    ),
                  ),
          ),
        ),
        Row(children: [
          Expanded(
            child: Text('Seite ${currentPage + 1} / $pages',
                style: WorkstationTokens.mono(context, size: 9.5)),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              tooltip: 'Vorherige Geräte',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              onPressed: currentPage == 0
                  ? null
                  : () => setState(
                      () => widget.session.offset = (currentPage - 1) * pageSize),
              icon: const Icon(Icons.chevron_left, size: 18),
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              tooltip: 'Nächste Geräte',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              onPressed: currentPage + 1 >= pages
                  ? null
                  : () => setState(
                      () => widget.session.offset = (currentPage + 1) * pageSize),
              icon: const Icon(Icons.chevron_right, size: 18),
            ),
          ),
        ]),
        Text('Pfeile/Home/End · Enter öffnet · P Pin · C Compare',
            style: WorkstationTokens.mono(context,
                size: 9, color: OipTokens.muted(context))),
      ]),
    );
  }

  /// Compact segment selection for the three inventory scopes. The segments
  /// share one bordered row so the scope, the grouping and the density control
  /// use the same control height.
  Widget _scopeSegments(BuildContext context) {
    final entries = <(String, String)>[
      ('all', 'Alle'),
      ('pinned', 'Pinned ${widget.session.pinned.length}'),
      ('recent', 'Recents ${widget.session.recents.length}'),
    ];
    final accent = OipTokens.readableAccent(context, OipTokens.blue);
    return Container(
      height: DevicesLayout.controlHeight,
      decoration: BoxDecoration(
        border: Border.all(color: WorkstationTokens.hairline(context)),
        borderRadius: BorderRadius.circular(7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(children: [
        for (var index = 0; index < entries.length; index++) ...[
          if (index > 0)
            Container(width: 1, color: WorkstationTokens.hairline(context)),
          Expanded(
            child: _scopeSegment(
              context,
              value: entries[index].$1,
              label: entries[index].$2,
              selected: widget.session.scope == entries[index].$1,
              accent: accent,
            ),
          ),
        ],
      ]),
    );
  }

  Widget _scopeSegment(
    BuildContext context, {
    required String value,
    required String label,
    required bool selected,
    required Color accent,
  }) =>
      Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          key: Key('device-scope-$value'),
          onTap: () => setState(() {
            widget.session.scope = value;
            widget.session.offset = 0;
          }),
          child: Container(
            color: selected ? accent.withOpacity(.14) : Colors.transparent,
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? accent : OipTokens.muted(context),
              ),
            ),
          ),
        ),
      );

  /// Grouping control with the same compact geometry as the filter toolbar.
  Widget _groupSelect(BuildContext context) {
    final options = <(String, String)>[
      ('source', 'Source'),
      ('type', 'Gerätetyp'),
      ('location', 'Standort'),
      if (widget.infrastructure?.ready == true) ...[
        ('organization', 'Organization'),
        ('infrastructure', 'Infrastructure'),
        ('site', 'Site'),
      ],
      ('none', 'Keine'),
    ];
    final current = options.any((entry) => entry.$1 == widget.session.group)
        ? widget.session.group
        : 'source';
    return Container(
      height: DevicesLayout.controlHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: WorkstationTokens.well(context),
        border: Border.all(color: WorkstationTokens.hairline(context)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: DropdownButton<String>(
        key: const Key('device-group'),
        value: current,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        padding: EdgeInsets.zero,
        iconSize: 16,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
        selectedItemBuilder: (context) => options
            .map((entry) => Row(children: [
                  SizedBox(
                    width: 78,
                    child: Text('GRUPPIERUNG',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WorkstationTokens.eyebrow(context)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(entry.$2,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ]))
            .toList(),
        items: options
            .map((entry) =>
                DropdownMenuItem(value: entry.$1, child: Text(entry.$2)))
            .toList(),
        onChanged: (value) =>
            setState(() => widget.session.group = value ?? 'source'),
      ),
    );
  }

  String _group(Device device) {
    final placement = widget.infrastructure?.devicePlacement(device);
    return switch (widget.session.group) {
      'type' => device.kind,
      'location' => device.location,
      'source' => device.sourceId ?? 'Keine Source-Zuordnung',
      'organization' => placement == null
          ? 'Organization nicht geliefert'
          : widget.infrastructure!.hierarchy
              .organizationName(placement.organizationId),
      'infrastructure' => placement == null
          ? 'Infrastructure nicht geliefert'
          : widget.infrastructure!.hierarchy
              .infrastructureName(placement.infrastructureId),
      'site' => placement == null
          ? 'Site nicht geliefert'
          : widget.infrastructure!.hierarchy.siteName(placement.siteId),
      _ => '',
    };
  }

  Widget _row(Device device) {
    final selected = widget.session.selectedId == device.id;
    final pinned = widget.session.pinned.contains(device.id);
    final compared = widget.session.compare.contains(device.id);
    final observed = deviceSnapshotObservations(widget.snapshot, device);
    final freshness = deviceObservedFreshness(widget.snapshot, device);
    final reachability = known(device.health.reachability);
    final height = widget.session.compact
        ? DevicesLayout.rowCompact
        : DevicesLayout.rowComfortable;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Gerät ${device.name} ${device.id} auswählen · ${device.kind} · '
            '${device.sourceId ?? 'keine Source'} · '
            '${observed.isEmpty ? 'keine aktuelle Observation' : '${observed.length} Observations'} · '
            'Reachability $reachability reported${device.simulated ? ' · simuliert' : ''}',
        child: Material(
          color:
              selected ? OipTokens.blue.withOpacity(.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
          child: InkWell(
            key: Key('device-${device.id}'),
            borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
            onTap: () {
              widget.onSelect(device);
              widget.onOpen?.call();
            },
            child: SizedBox(
              height: height,
              child: Row(children: [
                const SizedBox(width: 6),
                Icon(deviceIcon(device.kind),
                    size: 16,
                    color: selected
                        ? OipTokens.readableAccent(context, OipTokens.blue)
                        : OipTokens.muted(context)),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tooltip(
                          message: '${device.name} · ${device.id}',
                          child: Text('${device.name} · ${device.id}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5, fontWeight: FontWeight.w600)),
                        ),
                        Text(
                            '${device.kind} · ${device.sourceId ?? 'keine Source'} · '
                            '${observed.isEmpty ? 'keine Observation' : known(freshness)} · '
                            '$reachability reported${device.simulated ? ' · SIM' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 9.5,
                                color: OipTokens.muted(context))),
                      ]),
                ),
                _rowAction(
                    key: Key('device-pin-${device.id}'),
                    tooltip: pinned ? 'Pin entfernen' : 'Gerät pinnen',
                    icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    onTap: () => widget.onPin(device)),
                _rowAction(
                    key: Key('device-compare-${device.id}'),
                    tooltip: compared
                        ? 'Aus Vergleich entfernen'
                        : 'Vergleich hinzufügen',
                    icon: compared ? Icons.compare : Icons.compare_outlined,
                    onTap: () => widget.onCompare(device)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowAction(
          {required Key key,
          required String tooltip,
          required IconData icon,
          required VoidCallback onTap}) =>
      Semantics(
        button: true,
        label: tooltip,
        child: Tooltip(
          message: tooltip,
          excludeFromSemantics: true,
          child: InkWell(
            key: key,
            onTap: onTap,
            child: SizedBox(
                width: 28,
                height: 32,
                child: Icon(icon, size: 15)),
          ),
        ),
      );
}

class _InventoryEntry {
  final String? header;
  final Device? device;
  const _InventoryEntry.header(String this.header) : device = null;
  const _InventoryEntry.device(Device this.device) : header = null;
}
