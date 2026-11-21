import '../../l10n/oip_strings.dart';
import 'package:flutter/material.dart';
import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'overview_selection.dart';

enum OverviewWorkspaceTab { activity, coverage, sources }

class ActivityCoverageWorkspace extends StatefulWidget {
  final Snapshot snapshot;
  final List<SourceInfo> sources;
  final List<CollectionEvent> events;
  final List<CollectionEvent> allEvents;
  final OverviewSelection selection;
  final ValueChanged<CollectionEvent> onEvent;
  final ValueChanged<SourceInfo> onSource;
  final void Function(int) navigate;
  const ActivityCoverageWorkspace({
    super.key,
    required this.snapshot,
    required this.sources,
    required this.events,
    required this.allEvents,
    required this.selection,
    required this.onEvent,
    required this.onSource,
    required this.navigate,
  });

  @override
  State<ActivityCoverageWorkspace> createState() =>
      _ActivityCoverageWorkspaceState();
}

class _ActivityCoverageWorkspaceState extends State<ActivityCoverageWorkspace> {
  OverviewWorkspaceTab tab = OverviewWorkspaceTab.activity;
  String eventFilter = 'all';

  @override
  Widget build(BuildContext context) {
    return WorkstationPanel(
      key: const Key('overview-activity-coverage-workspace'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _tab(OverviewWorkspaceTab.activity, 'Activity',
                    Icons.event_note_outlined),
                _tab(OverviewWorkspaceTab.coverage, 'Data Coverage',
                    Icons.fact_check_outlined),
                _tab(OverviewWorkspaceTab.sources, 'Source Health',
                    Icons.account_tree_outlined),
              ]),
            ),
          ),
          if (tab == OverviewWorkspaceTab.activity)
            IconButton(
              key: const Key('overview-workspace-open-diagnostics'),
              tooltip: context.tr("Diagnostics öffnen"),
              onPressed: () => widget.navigate(4),
              icon: const Icon(Icons.arrow_outward, size: 17),
            ),
        ]),
        const SizedBox(height: 5),
        Expanded(
          child: switch (tab) {
            OverviewWorkspaceTab.activity => _activity(context),
            OverviewWorkspaceTab.coverage => _coverage(context),
            OverviewWorkspaceTab.sources => _sources(context),
          },
        ),
      ]),
    );
  }

  Widget _tab(OverviewWorkspaceTab value, String label, IconData icon) =>
      Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          key: Key('overview-workspace-tab-${value.name}'),
          avatar: Icon(icon, size: 15),
          label: Text(label),
          selected: tab == value,
          showCheckmark: false,
          materialTapTargetSize: MaterialTapTargetSize.padded,
          onSelected: (_) => setState(() => tab = value),
        ),
      );

  Widget _activity(BuildContext context) {
    final kinds = widget.events.map((event) => event.kind).toSet().toList()
      ..sort();
    if (eventFilter != 'all' && !kinds.contains(eventFilter)) {
      eventFilter = 'all';
    }
    final filtered = widget.events
        .where((event) => eventFilter == 'all' || event.kind == eventFilter)
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text(
            context.tr(
                "{0} Collection-Records · aktuelles begrenztes API-Fenster{1}",
                [
                  filtered.length,
                  widget.selection.sourceId == null
                      ? ''
                      : ' · Source ${widget.selection.sourceId}'
                ]),
            overflow: TextOverflow.ellipsis,
            style: WorkstationTokens.mono(context, size: 10),
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String>(
            key: const Key('overview-event-filter'),
            isExpanded: true,
            value: eventFilter,
            decoration: InputDecoration(
                isDense: true,
                labelText: context.tr("EVENT-TYP"),
                border: OutlineInputBorder()),
            items: [
              DropdownMenuItem(
                  value: 'all', child: Text(context.tr("Alle gelieferten"))),
              ...kinds.map(
                  (kind) => DropdownMenuItem(value: kind, child: Text(kind))),
            ],
            onChanged: (value) => setState(() => eventFilter = value ?? 'all'),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      Expanded(
        child: filtered.isEmpty
            ? Align(
                alignment: Alignment.centerLeft,
                child: Text(context
                    .tr("Keine Events im ausgewählten aktuellen Datenumfang.")))
            : ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final event = filtered[index];
                  final key = overviewEventKey(event);
                  final selected =
                      widget.selection.kind == OverviewSelectionKind.event &&
                          widget.selection.eventKey == key;
                  return ListTile(
                    key: Key(
                        'overview-event-${event.sourceId ?? 'unknown'}-${event.kind}-${event.sequence ?? event.atMs ?? identityHashCode(event)}'),
                    dense: true,
                    minTileHeight: 40,
                    selected: selected,
                    selectedColor:
                        OipTokens.readableAccent(context, OipTokens.violet),
                    leading: Icon(
                        event.gapStartedMs != null
                            ? Icons.space_bar_outlined
                            : Icons.event_note_outlined,
                        size: 16),
                    title: Text(
                        '${event.kind} · ${overviewEventIdentity(event)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${event.sourceId ?? 'Source nicht projiziert'} · ${timestamp(event.atMs ?? event.gapEndedMs)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right, size: 16),
                    onTap: () => widget.onEvent(event),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _coverage(BuildContext context) {
    final system = widget.snapshot.system;
    final hasSignals = widget.snapshot.metrics.isNotEmpty;
    final simulated = system.simulated ||
        widget.snapshot.metrics.any((signal) => signal.simulated);
    final rows = [
      (
        'OPC-UA Signale',
        hasSignals ? 'VORHANDEN' : 'UNAVAILABLE',
        hasSignals
            ? '${simulated ? 'SIMULATED · ' : ''}OBSERVED'
            : 'Keine Observation'
      ),
      (
        'Network RTT / Loss',
        'NICHT GEMESSEN',
        widget.snapshot.topology.isEmpty
            ? 'UNAVAILABLE · kein Probe'
            : 'SIMULATED · kein aktiver Probe'
      ),
      (
        'Host CPU',
        system.cpu == null ? 'UNAVAILABLE' : 'VORHANDEN',
        system.cpu == null ? 'Kein Collector' : 'OBSERVED'
      ),
      (
        'Host GPU',
        system.gpu == null ? 'UNAVAILABLE' : 'VORHANDEN',
        system.gpu == null ? 'Kein Collector' : 'OBSERVED'
      ),
      (
        'Host RAM',
        system.ram == null ? 'UNAVAILABLE' : 'VORHANDEN',
        system.ram == null ? 'Kein Collector' : 'OBSERVED'
      ),
      (
        'Persistierte Observations',
        system.persisted?.toString() ?? 'UNAVAILABLE',
        system.persisted == null
            ? 'NICHT IM TENANT-SNAPSHOT'
            : 'REPORTED · globaler Core/SQLite-Bestand'
      ),
      (
        'Persistente History im Chart',
        'UNAVAILABLE IN UI',
        'v2 Browser-Identity fehlt · session-lokal'
      ),
    ];
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            context.tr("DATA COVERAGE & TRUST · Snapshot {0}",
                [timestamp(system.generatedMs)]),
            style: WorkstationTokens.eyebrow(context, color: OipTokens.cyan)),
        const SizedBox(height: 4),
        ...rows.map((row) => Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: WorkstationTokens.hairline(context)))),
              child: Row(children: [
                Expanded(flex: 3, child: Text(row.$1)),
                Expanded(
                    flex: 2,
                    child: Text(row.$2,
                        style: WorkstationTokens.mono(context, size: 10.5))),
                Expanded(flex: 4, child: Text(row.$3)),
              ]),
            )),
        Text(
            context.tr(
                "Persistierte Zahl: kein Zeitraum- oder Tenant-Aggregat; ermittelt {0}. Fehlende Werte werden nicht als 0 dargestellt.",
                [timestamp(system.generatedMs)]),
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  Widget _sources(BuildContext context) {
    if (widget.sources.isEmpty) {
      return Align(
          alignment: Alignment.centerLeft,
          child: Text(context
              .tr("SourceHealth im aktuellen Datenumfang nicht verfügbar.")));
    }
    return ListView(
      children: widget.sources.map((source) {
        final gaps = widget.allEvents
            .where((event) =>
                event.sourceId == source.id && event.gapStartedMs != null)
            .length;
        return ListTile(
          key: Key('overview-health-source-${source.id}'),
          dense: true,
          minTileHeight: 44,
          leading: StatusDot(source.connection),
          title: Text('${source.name} · ${source.id}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              context.tr(
                  "{0} · {1} · Empfang {2} · {3} dokumentierte Gaps im aktuellen Fenster · keine History-Behauptung",
                  [
                    known(source.connection),
                    known(source.freshness),
                    timestamp(source.lastReceivedMs),
                    gaps
                  ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right, size: 16),
          onTap: () => widget.onSource(source),
        );
      }).toList(),
    );
  }
}
