import 'package:flutter/material.dart';

import '../../design_system/theme.dart';
import '../../models/infrastructure.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'diagnostics_model.dart';

class DiagnosticsEventExplorer extends StatelessWidget {
  final List<DiagnosticEvent> allEvents, events, recent;
  final Set<String> pinned, compared;
  final String? selectedKey, sourceFilter, typeFilter;
  final String? organizationFilter, infrastructureFilter, siteFilter;
  final InfrastructureContext? infrastructure;
  final String query;
  final DiagnosticEventSort sort;
  final DiagnosticEventGrouping grouping;
  final DiagnosticTimeWindow timeWindow;
  final bool showFilters, stale, moreAvailable;
  final List<String> missingEvidence;
  final VoidCallback onLoadMore;
  final TextEditingController searchController;
  final FocusNode searchFocus, listFocus;
  final ValueChanged<String> onQuery;
  final VoidCallback onClearSearch, onToggleFilters;
  final ValueChanged<String?> onSource, onType;
  final ValueChanged<String?> onOrganization, onInfrastructure, onSite;
  final ValueChanged<DiagnosticEventSort> onSort;
  final ValueChanged<DiagnosticEventGrouping> onGrouping;
  final ValueChanged<DiagnosticTimeWindow> onTimeWindow;
  final ValueChanged<DiagnosticEvent> onSelect, onPin, onCompare;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  const DiagnosticsEventExplorer({
    super.key,
    required this.allEvents,
    required this.events,
    required this.recent,
    required this.pinned,
    required this.compared,
    required this.selectedKey,
    required this.sourceFilter,
    required this.typeFilter,
    required this.query,
    required this.sort,
    required this.grouping,
    required this.timeWindow,
    required this.showFilters,
    required this.stale,
    required this.moreAvailable,
    required this.missingEvidence,
    required this.onLoadMore,
    required this.searchController,
    required this.searchFocus,
    required this.listFocus,
    required this.onQuery,
    required this.onClearSearch,
    required this.onToggleFilters,
    required this.onSource,
    required this.onType,
    required this.onOrganization,
    required this.onInfrastructure,
    required this.onSite,
    required this.onSort,
    required this.onGrouping,
    required this.onTimeWindow,
    required this.onSelect,
    required this.onPin,
    required this.onCompare,
    required this.onKeyEvent,
    this.organizationFilter,
    this.infrastructureFilter,
    this.siteFilter,
    this.infrastructure,
  });

  @override
  Widget build(BuildContext context) {
    final sources = allEvents
        .map((item) => item.event.sourceId)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    final types = allEvents.map((item) => item.event.kind).toSet().toList()
      ..sort();
    return WorkstationPanel(
      key: const Key('diagnostics-event-explorer'),
      accent: OipTokens.cyan,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 8, 7),
          child: Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('EVENT EXPLORER',
                      style: WorkstationTokens.eyebrow(context,
                          color: OipTokens.cyan)),
                  const SizedBox(height: 2),
                  Text('Collection-Ereignisse',
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(
                      '${events.length}/${allEvents.length} im geladenen Fenster',
                      style: Theme.of(context).textTheme.bodySmall),
                ])),
            ToolButton(
              key: const Key('diagnostics-filters-toggle'),
              icon: Icons.filter_alt_outlined,
              tooltip: 'Explorer-Filter anzeigen oder ausblenden',
              accent: OipTokens.cyan,
              active: showFilters ||
                  sourceFilter != null ||
                  typeFilter != null ||
                  timeWindow != DiagnosticTimeWindow.all,
              onPressed: onToggleFilters,
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: TextField(
            key: const Key('diagnostics-search'),
            controller: searchController,
            focusNode: searchFocus,
            onChanged: onQuery,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Typ, Source, Sequenz oder Grund',
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
              if (infrastructure?.ready == true) ...[
                _contextDropdown(context,
                    key: const Key('diagnostics-organization-filter'),
                    label: 'Organization',
                    kind: InfrastructureSelectionKind.organization,
                    value: organizationFilter,
                    onChanged: onOrganization),
                const SizedBox(height: 6),
                _contextDropdown(context,
                    key: const Key('diagnostics-infrastructure-filter'),
                    label: 'Infrastructure',
                    kind: InfrastructureSelectionKind.infrastructure,
                    value: infrastructureFilter,
                    onChanged: onInfrastructure),
                const SizedBox(height: 6),
                _contextDropdown(context,
                    key: const Key('diagnostics-site-filter'),
                    label: 'Site',
                    kind: InfrastructureSelectionKind.site,
                    value: siteFilter,
                    onChanged: onSite),
                const SizedBox(height: 6),
              ],
              _dropdown<String>(context,
                  key: const Key('diagnostics-source-filter'),
                  label: 'Source',
                  value: sourceFilter,
                  values: sources,
                  nullable: true,
                  onChanged: onSource),
              const SizedBox(height: 6),
              _dropdown<String>(context,
                  key: const Key('diagnostics-type-filter'),
                  label: 'Ereignistyp',
                  value: typeFilter,
                  values: types,
                  nullable: true,
                  itemLabel: diagnosticEventTitle,
                  onChanged: onType),
              const SizedBox(height: 6),
              _dropdown<DiagnosticTimeWindow>(context,
                  key: const Key('diagnostics-time-filter'),
                  label: 'Zeitbereich',
                  value: timeWindow,
                  values: DiagnosticTimeWindow.values,
                  itemLabel: diagnosticTimeWindowLabel,
                  onChanged: (value) => onTimeWindow(value!)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: _dropdown<DiagnosticEventSort>(context,
                        key: const Key('diagnostics-sort'),
                        label: 'Sortierung',
                        value: sort,
                        values: DiagnosticEventSort.values,
                        itemLabel: diagnosticSortLabel,
                        onChanged: (value) => onSort(value!))),
                const SizedBox(width: 6),
                Expanded(
                    child: _dropdown<DiagnosticEventGrouping>(context,
                        key: const Key('diagnostics-grouping'),
                        label: 'Gruppe',
                        value: grouping,
                        values: DiagnosticEventGrouping.values,
                        itemLabel: diagnosticGroupingLabel,
                        onChanged: (value) => onGrouping(value!))),
              ]),
            ]),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: WorkstationTokens.well(context),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              stale
                  ? 'LETZTER ERFOLGREICHER STAND · ABRUF FEHLER'
                  : moreAvailable
                      ? 'WEITERE AUTORISIERTE EREIGNISSE VORHANDEN'
                      : 'NUR DAS TATSÄCHLICH GELADENE AUTORISIERTE FENSTER',
              style: WorkstationTokens.eyebrow(context,
                  color: stale || moreAvailable ? OipTokens.yellow : null),
            ),
            if (missingEvidence.isNotEmpty)
              Text('${missingEvidence.length} missing-evidence Marker',
                  style: WorkstationTokens.eyebrow(context)),
            if (moreAvailable)
              TextButton.icon(
                key: const Key('diagnostics-load-more'),
                onPressed: onLoadMore,
                icon: const Icon(Icons.expand_more, size: 15),
                label: const Text('Weitere Ereignisse laden'),
              ),
          ]),
        ),
        if (pinned.isNotEmpty || recent.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 6, 9, 2),
            child: Wrap(spacing: 4, runSpacing: 4, children: [
              for (final item
                  in allEvents.where((item) => pinned.contains(item.key)))
                InputChip(
                  key: Key('diagnostics-pin-${item.key}'),
                  avatar: const Icon(Icons.push_pin, size: 13),
                  label: Text(
                      item.recordId ?? diagnosticEventTitle(item.event.kind),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10)),
                  selected: selectedKey == item.key,
                  onPressed: () => onSelect(item),
                  onDeleted: () => onPin(item),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              if (recent.isNotEmpty)
                Tooltip(
                  message:
                      'Zuletzt: ${recent.map((item) => item.recordId ?? diagnosticEventTitle(item.event.kind)).join(', ')}',
                  child: Chip(
                      avatar: const Icon(Icons.history, size: 14),
                      label: Text('Zuletzt ${recent.length}',
                          style: const TextStyle(fontSize: 10))),
                ),
            ]),
          ),
        Expanded(
          child: Focus(
            key: const Key('diagnostics-list-focus'),
            focusNode: listFocus,
            onKeyEvent: onKeyEvent,
            child: Builder(builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return Container(
                foregroundDecoration: BoxDecoration(
                    border: Border.all(
                        color: focused ? OipTokens.cyan : Colors.transparent)),
                child: events.isEmpty
                    ? const SingleChildScrollView(
                        padding: EdgeInsets.all(12),
                        child: WorkstationNote(
                          'Keine Collection-Ereignisse geliefert',
                          'Entweder enthält das aktuelle API-Fenster keine Einträge oder die lokalen Filter schließen alle aus. Dies ist weder eine vollständige Historie noch ein Gesundheitsbeweis.',
                          icon: Icons.search_off_outlined,
                        ))
                    : ListView.builder(
                        key: const Key('diagnostics-event-list'),
                        padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
                        itemCount: events.length,
                        itemBuilder: (context, index) {
                          final item = events[index];
                          final group = diagnosticEventGroup(item, grouping);
                          final showGroup = group.isNotEmpty &&
                              (index == 0 ||
                                  diagnosticEventGroup(events[index - 1],
                                          grouping, infrastructure) !=
                                      group);
                          return Column(children: [
                            if (showGroup)
                              Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(7, 8, 7, 4),
                                  child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(group,
                                          style: WorkstationTokens.eyebrow(
                                              context)))),
                            _EventRow(
                              item: item,
                              selected: selectedKey == item.key,
                              pinned: pinned.contains(item.key),
                              compared: compared.contains(item.key),
                              onTap: () => onSelect(item),
                              onPin: () => onPin(item),
                              onCompare: () => onCompare(item),
                            ),
                          ]);
                        },
                      ),
              );
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Text(
              'Pfeile Auswahl · Enter Inspector · P Pin · C Compare\nSeverity wird von dieser API nicht geliefert',
              style: WorkstationTokens.mono(context,
                  size: 9.5, color: OipTokens.muted(context))),
        ),
      ]),
    );
  }

  Widget _contextDropdown(
    BuildContext context, {
    required Key key,
    required String label,
    required InfrastructureSelectionKind kind,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final values = <String, String>{};
    for (final item in allEvents) {
      final placement = infrastructure?.sourcePlacement(item.event.sourceId);
      if (placement == null) continue;
      final id = switch (kind) {
        InfrastructureSelectionKind.organization => placement.organizationId,
        InfrastructureSelectionKind.infrastructure => placement.infrastructureId,
        InfrastructureSelectionKind.site => placement.siteId,
        _ => '',
      };
      if (id.isEmpty) continue;
      values[id] = switch (kind) {
        InfrastructureSelectionKind.organization =>
          infrastructure!.hierarchy.organizationName(id),
        InfrastructureSelectionKind.infrastructure =>
          infrastructure!.hierarchy.infrastructureName(id),
        InfrastructureSelectionKind.site => infrastructure!.hierarchy.siteName(id),
        _ => id,
      };
    }
    final ids = values.keys.toList()..sort();
    return _dropdown<String>(context,
        key: key,
        label: label,
        value: ids.contains(value) ? value : null,
        values: ids,
        nullable: true,
        itemLabel: (id) => values[id] ?? id,
        onChanged: onChanged);
  }

  Widget _dropdown<T>(BuildContext context,
      {required Key key,
      required String label,
      required T? value,
      required List<T> values,
      required ValueChanged<T?> onChanged,
      String Function(T)? itemLabel,
      bool nullable = false}) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
          color: WorkstationTokens.well(context),
          border: Border.all(color: WorkstationTokens.hairline(context)),
          borderRadius: BorderRadius.circular(7)),
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
                    overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final DiagnosticEvent item;
  final bool selected, pinned, compared;
  final VoidCallback onTap, onPin, onCompare;
  const _EventRow(
      {required this.item,
      required this.selected,
      required this.pinned,
      required this.compared,
      required this.onTap,
      required this.onPin,
      required this.onCompare});

  @override
  Widget build(BuildContext context) {
    final event = item.event;
    final tone = diagnosticEventTone(context, event.kind);
    final title = diagnosticEventTitle(event.kind);
    final accent = OipTokens.readableAccent(context, OipTokens.violet);
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label:
          'Ereignis $title auswählen, ${item.sourceLabel}, ${timestamp(event.atMs)}, Severity nicht geliefert, ${item.recordId == null ? 'keine Server-Record-ID' : 'Record ${item.recordId}'}',
      child: Material(
        color: selected ? accent.withOpacity(.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          key: Key('diagnostics-event-${item.key}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 7, 4, 7),
            decoration: BoxDecoration(
                border: Border(
                    left: BorderSide(
                        color: selected ? accent : tone.withOpacity(.65),
                        width: 2))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                      event.kind == 'ConnectionLost'
                          ? Icons.link_off
                          : event.kind == 'Reconnected'
                              ? Icons.link
                              : event.kind == 'DataLoss'
                                  ? Icons.data_usage_outlined
                                  : Icons.error_outline,
                      size: 17,
                      color: tone)),
              const SizedBox(width: 8),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(
                        'Quelle: ${event.sourceId ?? 'unbekannt'} · ${diagnosticEventCategory(event.kind)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                    Text(timestamp(event.atMs),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WorkstationTokens.mono(context,
                            size: 9.5, color: OipTokens.muted(context))),
                    if (event.gapMs != null)
                      Text('Dokumentierte Lücke: ${event.gapMs} ms',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: tone, fontSize: 10)),
                    if (item.hasGapBounds && event.gapMs == null)
                      Text(
                          event.kind == 'DataLoss'
                              ? 'Datenlücke: Zeitraum nicht bestimmbar'
                              : item.gapIsInverted
                                  ? 'Datenlücke: inkonsistente Zeitgrenzen'
                                  : 'Datenlücke: unvollständige Zeitgrenzen',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: OipTokens.yellow, fontSize: 10)),
                    Wrap(spacing: 4, runSpacing: 2, children: [
                      Text(
                          item.recordId == null
                              ? 'OHNE RECORD-ID'
                              : 'API-RECORD ${item.recordId}',
                          style: WorkstationTokens.eyebrow(context,
                              color: OipTokens.muted(context))),
                      if (item.deliveryCount > 1)
                        Text('${item.deliveryCount}× GELIEFERT',
                            style: WorkstationTokens.eyebrow(context,
                                color: OipTokens.yellow)),
                      if (item.identityConflict)
                        Text('SEQUENZKONFLIKT',
                            style: WorkstationTokens.eyebrow(context,
                                color: OipTokens.red)),
                    ]),
                  ])),
              Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                        tooltip:
                            pinned ? 'Ereignis lösen' : 'Ereignis anheften',
                        onPressed: onPin,
                        icon: Icon(
                            pinned ? Icons.push_pin : Icons.push_pin_outlined,
                            size: 15,
                            color: pinned
                                ? OipTokens.violet
                                : OipTokens.muted(context)))),
                SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                        tooltip: compared
                            ? 'Aus Compare entfernen'
                            : 'Zu Compare hinzufügen',
                        onPressed: onCompare,
                        icon: Icon(
                            compared
                                ? Icons.compare_arrows
                                : Icons.add_chart_outlined,
                            size: 15,
                            color: compared
                                ? OipTokens.cyan
                                : OipTokens.muted(context)))),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

Color diagnosticEventTone(BuildContext context, String kind) => switch (kind) {
      'ConnectionLost' ||
      'SubscriptionError' =>
        OipTokens.statusColor(context, 'alarm'),
      'Reconnected' => OipTokens.statusColor(context, 'connected'),
      'DataLoss' => OipTokens.statusColor(context, 'degraded'),
      _ => OipTokens.statusColor(context, 'unknown'),
    };
