import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/controller.dart';
import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'telemetry_chart.dart';

enum _PanelKind { value, trend }

class _PanelSpec {
  final String observationKey;
  final _PanelKind kind;

  const _PanelSpec(this.observationKey, this.kind);

  Map<String, Object> toJson() => {
        'observation': observationKey,
        'kind': kind.name,
      };

  static _PanelSpec? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final observation = value['observation'];
    final kind = _PanelKind.values.where((item) => item.name == value['kind']);
    if (observation is! String || kind.isEmpty) return null;
    return _PanelSpec(observation, kind.first);
  }
}

/// A personal modular dashboard. Its key is bound to the authenticated
/// principal and the selected authorized infrastructure scope.
class DashboardWorkspace extends StatefulWidget {
  final OipController controller;

  const DashboardWorkspace({super.key, required this.controller});

  @override
  State<DashboardWorkspace> createState() => _DashboardWorkspaceState();
}

class _DashboardWorkspaceState extends State<DashboardWorkspace> {
  List<_PanelSpec> panels = [];
  bool loaded = false;
  String? storageKey;

  OipController get controller => widget.controller;
  String? get principal => controller.infrastructure.principalIdentity;

  String? get currentStorageKey {
    if (!controller.infrastructure.ready || principal == null) return null;
    return 'oip.dashboard.v1.${Uri.encodeComponent(principal!)}.'
        '${Uri.encodeComponent(controller.infrastructure.selection.scopeKey)}';
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(_contextChanged);
    _loadForCurrentScope();
  }

  @override
  void dispose() {
    controller.removeListener(_contextChanged);
    super.dispose();
  }

  void _contextChanged() {
    final next = currentStorageKey;
    if (next == storageKey) return;
    _loadForCurrentScope();
  }

  Future<void> _loadForCurrentScope() async {
    final key = currentStorageKey;
    setState(() {
      loaded = false;
      storageKey = key;
      panels = [];
    });
    if (key == null) {
      if (mounted) setState(() => loaded = true);
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(key);
    var restored = <_PanelSpec>[];
    if (encoded != null) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is List) {
          restored =
              decoded.map(_PanelSpec.fromJson).whereType<_PanelSpec>().toList();
        }
      } catch (_) {
        restored = [];
      }
    } else {
      // First view is useful immediately, but only from measurements actually
      // supplied by this authorized context.
      final seen = <String>{};
      restored = [
        for (final observation
            in controller.snapshot?.metrics ?? const <Observation>[])
          if (observation.number != null &&
              seen.add(observationKey(observation)) &&
              restored.length < 4)
            _PanelSpec(observationKey(observation), _PanelKind.value),
      ];
      await preferences.setString(
          key, jsonEncode(restored.map((p) => p.toJson()).toList()));
    }
    if (!mounted || storageKey != key) return;
    setState(() {
      panels = restored;
      loaded = true;
    });
  }

  Future<void> _save() async {
    final key = storageKey;
    if (key == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      key,
      jsonEncode(panels.map((panel) => panel.toJson()).toList()),
    );
  }

  List<Observation> get observations =>
      controller.snapshot?.metrics ?? const [];

  Future<void> _addPanel() async {
    final candidates = observations;
    if (candidates.isEmpty) return;
    final selected =
        await showDialog<({Observation observation, _PanelKind kind})>(
      context: context,
      builder: (context) => _AddPanelDialog(observations: candidates),
    );
    if (selected == null || !mounted) return;
    final key = observationKey(selected.observation);
    setState(() {
      panels.add(_PanelSpec(key, selected.kind));
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final scope = controller.infrastructure;
    final scopeLabel =
        scope.ready ? scope.selectedBreadcrumb : 'Kein autorisierter Kontext';
    final activeKey = currentStorageKey;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      WorkstationPanel(
        accent: OipTokens.violet,
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
            builder: (context, box) => Row(
                  children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const PanelLabel('PERSÖNLICHES DASHBOARD'),
                          Text(scopeLabel,
                              style: WorkstationTokens.mono(context, size: 11),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Text(
                            activeKey == null
                                ? 'Zum Bearbeiten anmelden und eine Infrastruktur auswählen.'
                                : 'Layout wird auf diesem Gerät je Benutzer und Kontext gespeichert.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ])),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      key: const Key('overview-dashboard-add-panel'),
                      onPressed: activeKey == null || observations.isEmpty
                          ? null
                          : _addPanel,
                      icon: const Icon(Icons.add, size: 17),
                      label: const Text('Panel hinzufügen'),
                    ),
                  ],
                )),
      ),
      const SizedBox(height: OipTokens.s2),
      if (!loaded)
        const LinearProgressIndicator()
      else if (activeKey == null)
        const WorkstationNote(
          'Dashboard schreibgeschützt',
          'Eine angemeldete Sitzung und ein autorisierter Infrastrukturkontext sind erforderlich, damit das persönliche Layout getrennt gespeichert wird.',
          icon: Icons.lock_outline,
        )
      else if (panels.isEmpty)
        const WorkstationNote(
          'Noch keine Panels',
          'Füge ein Live-Messsignal als Wert oder Verlauf hinzu. Angezeigt werden nur Daten des aktuellen Infrastrukturkontexts.',
          icon: Icons.dashboard_customize_outlined,
        )
      else
        ReorderableListView.builder(
          key: const Key('overview-modular-dashboard-panels'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: panels.length,
          onReorder: (oldIndex, newIndex) async {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              final panel = panels.removeAt(oldIndex);
              panels.insert(newIndex, panel);
            });
            await _save();
          },
          itemBuilder: (context, index) {
            final spec = panels[index];
            final observation = observations
                .where((item) => observationKey(item) == spec.observationKey)
                .firstOrNull;
            return Padding(
              key: ValueKey(
                  'dashboard-panel-${spec.observationKey}-${spec.kind.name}-$index'),
              padding: const EdgeInsets.only(bottom: OipTokens.s2),
              child: _DashboardPanel(
                observation: observation,
                spec: spec,
                history: controller.history,
                selected: controller.telemetryKey == spec.observationKey,
                onSelect: observation == null
                    ? null
                    : () => controller.selectTelemetry(spec.observationKey),
                onRemove: () async {
                  setState(() => panels.removeAt(index));
                  await _save();
                },
                onKindChanged: (kind) async {
                  setState(() =>
                      panels[index] = _PanelSpec(spec.observationKey, kind));
                  await _save();
                },
              ),
            );
          },
        ),
    ]);
  }
}

class _DashboardPanel extends StatelessWidget {
  final Observation? observation;
  final _PanelSpec spec;
  final List<Observation> history;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback onRemove;
  final ValueChanged<_PanelKind> onKindChanged;

  const _DashboardPanel({
    required this.observation,
    required this.spec,
    required this.history,
    required this.selected,
    required this.onSelect,
    required this.onRemove,
    required this.onKindChanged,
  });

  @override
  Widget build(BuildContext context) {
    final item = observation;
    return WorkstationPanel(
      accent: OipTokens.cyan,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                PanelLabel(item == null
                    ? 'SIGNAL NICHT IM KONTEXT'
                    : '${item.entityId} · ${item.metricId}'),
                if (item != null)
                  Text(
                      '${item.sourceId ?? 'Quelle nicht angegeben'} · ${item.quality.toUpperCase()} · ${item.freshness.toUpperCase()}',
                      style: WorkstationTokens.mono(context, size: 10),
                      overflow: TextOverflow.ellipsis),
              ])),
          PopupMenuButton<_PanelKind>(
            tooltip: 'Darstellung ändern',
            icon: const Icon(Icons.tune),
            onSelected: onKindChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(
                  value: _PanelKind.value, child: Text('Aktueller Wert')),
              PopupMenuItem(
                  value: _PanelKind.trend, child: Text('Session-Verlauf')),
            ],
          ),
          IconButton(
              tooltip: 'Panel entfernen',
              onPressed: onRemove,
              icon: const Icon(Icons.close)),
          const Icon(Icons.drag_indicator, size: 20),
        ]),
        if (item == null)
          const Text(
              'Das konfigurierte Signal ist in diesem Kontext nicht verfügbar.')
        else if (spec.kind == _PanelKind.value)
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
                child: Text('${item.display} ${item.symbol}',
                    style: Theme.of(context).textTheme.headlineMedium)),
            StatusPill(item.freshness.toUpperCase(),
                color: OipTokens.statusColor(context, item.freshness),
                showDot: true),
          ])
        else ...[
          Row(children: [
            Expanded(
                child: Text('Messwert ${item.display} ${item.symbol}',
                    style: Theme.of(context).textTheme.titleMedium)),
            TextButton.icon(
                onPressed: onSelect,
                icon: Icon(selected ? Icons.check : Icons.show_chart),
                label: Text(selected ? 'Aktive Reihe' : 'Reihe laden')),
          ]),
          if (!selected)
            const WorkstationNote('Verlauf auswählen',
                'Der Verlauf basiert auf den seit Auswahl empfangenen Samples dieser Sitzung.',
                icon: Icons.timeline)
          else if (history.length < 2)
            const WorkstationNote('Sammle Verlauf',
                'Mindestens zwei gültige, zeitlich geordnete Samples sind erforderlich.',
                icon: Icons.hourglass_empty)
          else
            OverviewTrendChart(
                samples: history,
                unit: item.symbol,
                simulated: item.simulated,
                height: 190),
          Text('Session-Verlauf · keine persistierte Historie',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
    );
  }
}

class _AddPanelDialog extends StatefulWidget {
  final List<Observation> observations;
  const _AddPanelDialog({required this.observations});

  @override
  State<_AddPanelDialog> createState() => _AddPanelDialogState();
}

class _AddPanelDialogState extends State<_AddPanelDialog> {
  String? selectedKey;
  _PanelKind kind = _PanelKind.value;

  @override
  Widget build(BuildContext context) {
    final choices = <String, Observation>{};
    for (final item in widget.observations) {
      choices.putIfAbsent(observationKey(item), () => item);
    }
    selectedKey ??= choices.keys.firstOrNull;
    return AlertDialog(
      title: const Text('Dashboard-Panel hinzufügen'),
      content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: selectedKey,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Live-Messsignal'),
              items: choices.entries
                  .map((entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                            '${entry.value.sourceId ?? 'Quelle'} · ${entry.value.entityId} · ${entry.value.metricId}',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => selectedKey = value),
            ),
            const SizedBox(height: 12),
            SegmentedButton<_PanelKind>(
              segments: const [
                ButtonSegment(
                    value: _PanelKind.value,
                    icon: Icon(Icons.speed),
                    label: Text('Wert')),
                ButtonSegment(
                    value: _PanelKind.trend,
                    icon: Icon(Icons.show_chart),
                    label: Text('Verlauf')),
              ],
              selected: {kind},
              onSelectionChanged: (value) => setState(() => kind = value.first),
            ),
          ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen')),
        FilledButton(
            onPressed: selectedKey == null
                ? null
                : () => Navigator.pop(
                    context, (observation: choices[selectedKey]!, kind: kind)),
            child: const Text('Hinzufügen')),
      ],
    );
  }
}
