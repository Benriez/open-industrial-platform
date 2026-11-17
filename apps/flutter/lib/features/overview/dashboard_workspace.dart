import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/controller.dart';
import '../../design_system/theme.dart';
import '../../models/contracts.dart';
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
  int columns = 3;
  bool editing = false;
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
        if (decoded is Map<String, dynamic>) {
          final savedPanels = decoded['panels'];
          if (savedPanels is List) {
            restored = savedPanels
                .map(_PanelSpec.fromJson)
                .whereType<_PanelSpec>()
                .toList();
          }
          final savedColumns = decoded['columns'];
          if (savedColumns is int && savedColumns >= 1 && savedColumns <= 4) {
            columns = savedColumns;
          }
        } else if (decoded is List) {
          // Read the original v1 list layout and upgrade it on next edit.
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
        key,
        jsonEncode({
          'columns': columns,
          'panels': restored.map((p) => p.toJson()).toList(),
        }),
      );
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
      jsonEncode({
        'columns': columns,
        'panels': panels.map((panel) => panel.toJson()).toList(),
      }),
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
        accent: OipTokens.cyan,
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
        child: LayoutBuilder(builder: (context, box) {
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.monitor_heart_outlined,
                    color: OipTokens.cyan, size: 18),
                const SizedBox(width: 7),
                Text('LIVE DASHBOARD',
                    style: WorkstationTokens.eyebrow(context,
                        color: OipTokens.cyan)),
                const SizedBox(width: 10),
                _LiveIndicator(live: controller.connection == 'live'),
              ]),
              const SizedBox(height: 6),
              Text(scopeLabel,
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              Text(
                activeKey == null
                    ? 'Zum Bearbeiten anmelden und eine Infrastruktur auswählen.'
                    : '${panels.length} Panels · ${observations.length} gelieferte Messpunkte · persönliches Layout',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
          final controls = Wrap(spacing: 8, runSpacing: 8, children: [
            if (editing)
              PopupMenuButton<int>(
                tooltip: 'Spaltenbreite',
                initialValue: columns,
                onSelected: (value) async {
                  setState(() => columns = value);
                  await _save();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 1, child: Text('1 Spalte')),
                  PopupMenuItem(value: 2, child: Text('2 Spalten')),
                  PopupMenuItem(value: 3, child: Text('3 Spalten')),
                  PopupMenuItem(value: 4, child: Text('4 Spalten')),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    border: Border.all(color: WorkstationTokens.line(context)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.view_column_outlined, size: 18),
                    const SizedBox(width: 7),
                    Text('$columns Spalten'),
                  ]),
                ),
              ),
            OutlinedButton.icon(
              key: const Key('overview-dashboard-edit'),
              onPressed: activeKey == null
                  ? null
                  : () => setState(() => editing = !editing),
              icon: Icon(editing ? Icons.check : Icons.tune, size: 17),
              label: Text(editing ? 'Fertig' : 'Anpassen'),
            ),
            FilledButton.icon(
              key: const Key('overview-dashboard-add-panel'),
              onPressed:
                  activeKey == null || observations.isEmpty ? null : _addPanel,
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Panel hinzufügen'),
            ),
          ]);
          return box.maxWidth < 780
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [heading, const SizedBox(height: 14), controls],
                )
              : Row(children: [
                  Expanded(child: heading),
                  const SizedBox(width: 12),
                  controls,
                ]);
        }),
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
        LayoutBuilder(builder: (context, constraints) {
          final effectiveColumns = constraints.maxWidth < 580
              ? 1
              : constraints.maxWidth < 1000
                  ? columns.clamp(1, 2)
                  : columns;
          const gap = OipTokens.s2;
          final tileWidth =
              (constraints.maxWidth - gap * (effectiveColumns - 1)) /
                  effectiveColumns;
          return Wrap(
            key: const Key('overview-modular-dashboard-panels'),
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var index = 0; index < panels.length; index++)
                Builder(builder: (context) {
                  final spec = panels[index];
                  final observation = observations
                      .where(
                          (item) => observationKey(item) == spec.observationKey)
                      .firstOrNull;
                  final wide = spec.kind == _PanelKind.trend;
                  final width = wide ? constraints.maxWidth : tileWidth;
                  return SizedBox(
                    width: width,
                    child: _DashboardPanel(
                      observation: observation,
                      spec: spec,
                      history: controller.history,
                      selected: controller.telemetryKey == spec.observationKey,
                      editing: editing,
                      onSelect: observation == null
                          ? null
                          : () =>
                              controller.selectTelemetry(spec.observationKey),
                      onRemove: () async {
                        setState(() => panels.removeAt(index));
                        await _save();
                      },
                      onMove: (direction) async {
                        final target = index + direction;
                        if (target < 0 || target >= panels.length) return;
                        setState(() {
                          final panel = panels.removeAt(index);
                          panels.insert(target, panel);
                        });
                        await _save();
                      },
                      onKindChanged: (kind) async {
                        setState(() => panels[index] =
                            _PanelSpec(spec.observationKey, kind));
                        await _save();
                      },
                    ),
                  );
                }),
            ],
          );
        }),
    ]);
  }
}

class _DashboardPanel extends StatelessWidget {
  final Observation? observation;
  final _PanelSpec spec;
  final List<Observation> history;
  final bool selected;
  final bool editing;
  final VoidCallback? onSelect;
  final VoidCallback onRemove;
  final ValueChanged<int> onMove;
  final ValueChanged<_PanelKind> onKindChanged;

  const _DashboardPanel({
    required this.observation,
    required this.spec,
    required this.history,
    required this.selected,
    required this.editing,
    required this.onSelect,
    required this.onRemove,
    required this.onMove,
    required this.onKindChanged,
  });

  @override
  Widget build(BuildContext context) {
    final item = observation;
    return WorkstationPanel(
      accent: item == null
          ? OipTokens.yellow
          : OipTokens.statusColor(context, item.freshness),
      padding: EdgeInsets.fromLTRB(
          spec.kind == _PanelKind.value ? 16 : 14, 14, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      item == null ? 'SIGNAL NICHT VERFÜGBAR' : item.metricId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WorkstationTokens.eyebrow(context),
                    ),
                  ),
                  if (editing) ...[
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Panel nach links/oben verschieben',
                      onPressed: () => onMove(-1),
                      icon: const Icon(Icons.arrow_upward, size: 17),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Panel nach rechts/unten verschieben',
                      onPressed: () => onMove(1),
                      icon: const Icon(Icons.arrow_downward, size: 17),
                    ),
                  ],
                ]),
                if (item != null)
                  Text(
                      '${item.entityId} · ${item.sourceId ?? 'Quelle nicht angegeben'}',
                      style: WorkstationTokens.mono(context,
                          size: 10, color: OipTokens.muted(context)),
                      overflow: TextOverflow.ellipsis),
              ])),
          if (editing)
            PopupMenuButton<_PanelKind>(
              tooltip: 'Darstellung ändern',
              icon: const Icon(Icons.more_horiz),
              onSelected: onKindChanged,
              itemBuilder: (context) => const [
                PopupMenuItem(
                    value: _PanelKind.value, child: Text('Aktueller Wert')),
                PopupMenuItem(
                    value: _PanelKind.trend, child: Text('Session-Verlauf')),
              ],
            ),
          if (editing)
            IconButton(
                tooltip: 'Panel entfernen',
                onPressed: onRemove,
                icon: const Icon(Icons.close)),
        ]),
        if (item == null)
          const Text(
              'Das konfigurierte Signal ist in diesem Kontext nicht verfügbar.')
        else if (spec.kind == _PanelKind.value) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
                child: Text('${item.display} ${item.symbol}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontSize: 31, fontWeight: FontWeight.w700))),
            Tooltip(
              message: 'Messqualität ${item.quality}',
              child: Icon(
                item.freshness == 'fresh'
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_outlined,
                color: OipTokens.statusColor(context, item.freshness),
                size: 20,
              ),
            ),
          ]),
          const SizedBox(height: 7),
          Row(children: [
            _FreshnessBadge(value: item.freshness),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.receivedMs == null
                    ? 'Empfangszeit nicht geliefert'
                    : 'Empfangen ${DateTime.fromMillisecondsSinceEpoch(item.receivedMs!, isUtc: true).toLocal().toString().substring(11, 19)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (selected)
              const Icon(Icons.show_chart, size: 16, color: OipTokens.cyan)
            else
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Session-Verlauf dieses Signals aufnehmen',
                onPressed: onSelect,
                icon: const Icon(Icons.show_chart, size: 17),
              ),
          ]),
          if (selected && history.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _MiniTrend(samples: history, color: OipTokens.cyan),
            ),
        ] else ...[
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
                height: 236),
          Text(
              'Session-Verlauf · ${history.length} Samples · keine persistierte Historie',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
    );
  }
}

class _LiveIndicator extends StatelessWidget {
  final bool live;
  const _LiveIndicator({required this.live});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: OipTokens.statusColor(context, live ? 'fresh' : 'stale')
              .withOpacity(.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: OipTokens.statusColor(context, live ? 'fresh' : 'stale'),
            ),
          ),
          const SizedBox(width: 6),
          Text(live ? 'LIVE' : 'VERBINDUNG PRÜFEN',
              style: WorkstationTokens.eyebrow(context,
                  color: OipTokens.statusColor(
                      context, live ? 'fresh' : 'stale'))),
        ]),
      );
}

class _FreshnessBadge extends StatelessWidget {
  final String value;
  const _FreshnessBadge({required this.value});

  @override
  Widget build(BuildContext context) {
    final color = OipTokens.statusColor(context, value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        border: Border.all(color: color.withOpacity(.35)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(value.toUpperCase(),
          style: WorkstationTokens.eyebrow(context, color: color)),
    );
  }
}

class _MiniTrend extends StatelessWidget {
  final List<Observation> samples;
  final Color color;
  const _MiniTrend({required this.samples, required this.color});

  @override
  Widget build(BuildContext context) {
    final values = samples
        .where((sample) => sample.number != null)
        .map((sample) => sample.number!)
        .toList();
    if (values.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 34,
      width: double.infinity,
      child: CustomPaint(painter: _MiniTrendPainter(values, color)),
    );
  }
}

class _MiniTrendPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  const _MiniTrendPainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final range = max - min;
    final line = Path();
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final normalized = range == 0 ? .5 : (values[index] - min) / range;
      final y = size.height - normalized * (size.height - 4) - 2;
      if (index == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(line, stroke);
    final end = line.getBounds().centerRight;
    canvas.drawCircle(end, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MiniTrendPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.values != values;
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
