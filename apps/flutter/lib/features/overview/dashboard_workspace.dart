import '../../l10n/oip_strings.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/controller.dart';
import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import '../../widgets/workstation.dart';
import '../../services/api.dart';
import 'dashboard_panel_frame.dart';
import 'hue_lights.dart';
import 'telemetry_chart.dart';

part 'dashboard_visuals.dart';

/// The visualisations of a dashboard panel. `value` is the stored name of the
/// stat panel and stays readable for layouts saved by earlier versions.
enum _PanelKind {
  gauge('Gauge', Icons.speed),
  ring('Ring', Icons.donut_large),
  value('Stat', Icons.pin_outlined),
  bar('Balken', Icons.linear_scale),
  tank('Füllstand', Icons.battery_std),
  spark('Linie', Icons.area_chart),
  bars('Säulen', Icons.bar_chart),
  histogram('Histogramm', Icons.equalizer),
  timeline('Zustand', Icons.view_timeline_outlined),
  stats('Statistik', Icons.functions),
  trend('Verlauf', Icons.show_chart),
  table('Tabelle', Icons.table_rows_outlined),
  compare('Vergleich', Icons.align_horizontal_left),
  devices('Gerätestatus', Icons.grid_view),
  heading('Abschnitt', Icons.title);

  final String label;
  final IconData icon;
  const _PanelKind(this.label, this.icon);

  /// Device status and section rows are not bound to a measurement.
  bool get needsSignal => this != devices && this != heading;

  /// Kinds whose picture depends on a display range or thresholds.
  bool get usesScale =>
      needsSignal && this != table && this != trend && this != stats;

  /// Kinds that take the height of their content instead of the tile height.
  bool get naturalHeight =>
      this == trend ||
      this == table ||
      this == compare ||
      this == devices ||
      this == heading;

  /// Columns a panel spans unless the user chose a width; 0 is the full row.
  int get defaultSpan => switch (this) {
        trend || heading || devices => 0,
        table || compare => 2,
        _ => 1,
      };

  String get hint => switch (this) {
        gauge => 'Bogen mit Schwellenband',
        ring => 'Geschlossener Ring',
        value => 'Großer Wert mit Sparkline',
        bar => 'Segmentierter Balken',
        tank => 'Vertikaler Füllstand',
        spark => 'Kompakte Flächenlinie der Sitzung',
        bars => 'Sitzungswerte als Säulen',
        histogram => 'Verteilung der Sitzungswerte',
        timeline => 'Schwellen- oder Heat-Streifen über die Zeit',
        stats => 'Aktuell, Ø, Min und Max der Sitzung',
        trend => 'Interaktiver Verlauf in voller Breite',
        table => 'Alle Signale des Geräts mit Balken',
        compare => 'Dieselbe Metrik über alle Geräte',
        devices => 'Erreichbarkeit aller Geräte im Kontext',
        heading => 'Überschrift zum Gliedern',
      };
}

const _layoutVersion = 2;
const _sessionSamples = 120;
const _tileHeight = 196.0;

class _PanelSpec {
  final String observationKey;
  final _PanelKind kind;

  /// Display range and thresholds. With [custom] false they follow the unit
  /// convention of the signal; with [custom] true a null means "not set".
  final bool custom;
  final double? min, max, warn, crit;

  /// Width in columns; null follows the kind, 0 is the full row.
  final int? span;

  /// The text of a section row.
  final String? title;

  const _PanelSpec(
    this.observationKey,
    this.kind, {
    this.custom = false,
    this.min,
    this.max,
    this.warn,
    this.crit,
    this.span,
    this.title,
  });

  _PanelSpec withKind(_PanelKind next) => _PanelSpec(observationKey, next,
      custom: custom,
      min: min,
      max: max,
      warn: warn,
      crit: crit,
      span: span,
      title: title);

  Map<String, Object> toJson() => {
        'observation': observationKey,
        'kind': kind.name,
        if (custom) 'custom': true,
        if (min != null) 'min': min!,
        if (max != null) 'max': max!,
        if (warn != null) 'warn': warn!,
        if (crit != null) 'crit': crit!,
        if (span != null) 'span': span!,
        if (title != null) 'title': title!,
      };

  static _PanelSpec? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final observation = value['observation'];
    final kind = _PanelKind.values.where((item) => item.name == value['kind']);
    if (observation is! String || kind.isEmpty) return null;
    double? number(String key) {
      final raw = value[key];
      return raw is num && raw.isFinite ? raw.toDouble() : null;
    }

    final span = value['span'];
    final title = value['title'];
    return _PanelSpec(
      observation,
      kind.first,
      custom: value['custom'] == true,
      min: number('min'),
      max: number('max'),
      warn: number('warn'),
      crit: number('crit'),
      span: span is int && span >= 0 && span <= 4 ? span : null,
      title: title is String ? title : null,
    );
  }
}

/// The resolved scale of one panel: where the gauge starts and ends and at
/// which values the colour changes.
class _Scale {
  final double min, max;
  final double? warn, crit;

  /// True when the range was derived from the unit or the session values and
  /// not set by the user.
  final bool auto;
  const _Scale(this.min, this.max, this.warn, this.crit, {required this.auto});

  double fraction(double value) =>
      max <= min ? 0 : ((value - min) / (max - min)).clamp(0.0, 1.0);

  /// 0 = normal, 1 = warning, 2 = critical; null without thresholds.
  int? level(double value) {
    if (warn == null && crit == null) return null;
    if (crit != null && value >= crit!) return 2;
    if (warn != null && value >= warn!) return 1;
    return 0;
  }
}

double _niceCeil(double value) {
  if (value <= 0) return 1;
  final magnitude = math.pow(10, (math.log(value) / math.ln10).floor());
  for (final step in const [1, 2, 2.5, 5, 10]) {
    if (value <= step * magnitude) return (step * magnitude).toDouble();
  }
  return (10 * magnitude).toDouble();
}

_Scale _resolveScale(
    _PanelSpec spec, Observation item, List<Observation> samples) {
  final numbers = [
    if (item.number != null) item.number!,
    for (final sample in samples)
      if (sample.number != null) sample.number!,
  ];
  final seenMin = numbers.isEmpty ? 0.0 : numbers.reduce(math.min);
  final seenMax = numbers.isEmpty ? 0.0 : numbers.reduce(math.max);

  // Unit conventions: a percentage and a temperature have a natural 0–100
  // display range; every other unit is scaled to the values seen so far.
  final bounded = item.unit == '%' || item.unit == 'celsius';
  var min = math.min(0.0, seenMin);
  var max = bounded && seenMax <= 100 ? 100.0 : _niceCeil(seenMax * 1.15);
  double? warn, crit;
  if (item.unit == '%') {
    warn = 70;
    crit = 90;
  } else if (item.unit == 'celsius') {
    warn = 70;
    crit = 85;
  }
  // Only a range derived from the session values is labelled as automatic;
  // the 0–100 convention of a bounded unit needs no remark.
  var auto = !(bounded && seenMax <= 100);
  if (spec.custom) {
    warn = spec.warn;
    crit = spec.crit;
    if (spec.min != null) min = spec.min!;
    if (spec.max != null) max = spec.max!;
    if (spec.min != null && spec.max != null) auto = false;
  }
  if (max <= min) max = min + 1;
  return _Scale(min, max, warn, crit, auto: auto);
}

String _trim(double value, int digits) {
  final text = value.toStringAsFixed(digits);
  return text.contains('.')
      ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : text;
}

/// A number in the unit of [item], shortened the way a monitoring panel
/// expects it (binary byte prefixes, durations, one decimal).
({String text, String unit}) _formatValue(double value, Observation item) {
  switch (item.unit) {
    case 'bytes':
      const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
      var scaled = value;
      var index = 0;
      while (scaled.abs() >= 1024 && index < units.length - 1) {
        scaled /= 1024;
        index++;
      }
      return (
        text: _trim(scaled, scaled.abs() < 10 && index > 0 ? 2 : 1),
        unit: units[index]
      );
    case 'seconds':
      final total = value.round();
      if (total >= 86400) {
        return (
          text: '${total ~/ 86400}d ${(total % 86400) ~/ 3600}h',
          unit: ''
        );
      }
      if (total >= 3600) {
        return (text: '${total ~/ 3600}h ${(total % 3600) ~/ 60}m', unit: '');
      }
      if (total >= 60) {
        return (text: '${total ~/ 60}m ${total % 60}s', unit: '');
      }
      return (text: '$total', unit: 's');
    default:
      return (
        text: value == value.roundToDouble() && value.abs() < 1e12
            ? value.round().toString()
            : _trim(value, value.abs() < 10 ? 2 : 1),
        unit: item.symbol
      );
  }
}

({String text, String unit}) _formatObservation(Observation item) =>
    item.number == null
        ? (text: item.display, unit: item.number == null ? '' : item.symbol)
        : _formatValue(item.number!, item);

String _formatBound(double value, Observation item) {
  final formatted = _formatValue(value, item);
  return formatted.unit.isEmpty
      ? formatted.text
      : '${formatted.text} ${formatted.unit}';
}

Color _levelColor(BuildContext context, int? level) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (level) {
    2 => dark ? const Color(0xfff2495c) : const Color(0xffc4162a),
    1 => dark ? const Color(0xffffb357) : const Color(0xffb35c00),
    0 => dark ? const Color(0xff73bf69) : const Color(0xff2f7d32),
    _ => dark ? const Color(0xff5794f2) : const Color(0xff1f60c4),
  };
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

  /// Fresh samples received while this dashboard is open, per signal. This is
  /// a session buffer for sparklines and trends, not the persisted history.
  final Map<String, List<Observation>> session = {};

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
    controller.addListener(_controllerChanged);
    _recordSession();
    _loadForCurrentScope();
  }

  @override
  void dispose() {
    controller.removeListener(_controllerChanged);
    super.dispose();
  }

  void _controllerChanged() {
    if (!mounted) return;
    final next = currentStorageKey;
    if (next != storageKey) {
      session.clear();
      _recordSession();
      _loadForCurrentScope();
      return;
    }
    if (_recordSession()) setState(() {});
  }

  bool _recordSession() {
    var changed = false;
    for (final observation in observations) {
      final at = observation.sourceMs ?? observation.receivedMs;
      if (observation.number == null ||
          observation.freshness != 'fresh' ||
          at == null) {
        continue;
      }
      final samples =
          session.putIfAbsent(observationKey(observation), () => []);
      if (samples.isNotEmpty) {
        final last = samples.last;
        final lastAt = (last.sourceMs ?? last.receivedMs)!;
        if (at < lastAt) samples.clear();
        if (at == lastAt && last.value == observation.value) continue;
      }
      samples.add(observation);
      if (samples.length > _sessionSamples) samples.removeAt(0);
      changed = true;
    }
    return changed;
  }

  static _PanelKind _defaultKind(Observation observation) =>
      switch (observation.unit) {
        '%' => _PanelKind.gauge,
        'celsius' => _PanelKind.tank,
        _ => _PanelKind.value,
      };

  /// A starting layout built only from what this authorized context delivers:
  /// the device status, then per device its signals in fitting visualisations,
  /// a table of all its signals and one session line.
  List<_PanelSpec> _autoLayout() {
    final devices = controller.snapshot?.devices ?? const <Device>[];
    final groups = <String, List<Observation>>{};
    final seen = <String>{};
    for (final item in observations) {
      if (item.number == null || !seen.add(observationKey(item))) continue;
      groups
          .putIfAbsent('${item.sourceId ?? ''}\u001f${item.entityId}', () => [])
          .add(item);
    }
    const percentKinds = [_PanelKind.gauge, _PanelKind.ring, _PanelKind.bar];
    return [
      if (devices.isNotEmpty) const _PanelSpec('', _PanelKind.devices),
      for (final signals in groups.values.take(4)) ...[
        if (groups.length > 1)
          _PanelSpec('', _PanelKind.heading,
              title: devices
                      .where((device) => device.id == signals.first.entityId)
                      .firstOrNull
                      ?.name ??
                  signals.first.entityId),
        for (final (index, item) in signals.take(6).indexed)
          _PanelSpec(
              observationKey(item),
              item.unit == '%'
                  ? percentKinds[signals
                          .take(index)
                          .where((other) => other.unit == '%')
                          .length %
                      percentKinds.length]
                  : _defaultKind(item)),
        if (signals.length > 2)
          _PanelSpec(observationKey(signals.first), _PanelKind.table),
        _PanelSpec(
            observationKey(
                signals.where((item) => item.unit == '%').firstOrNull ??
                    signals.first),
            _PanelKind.spark),
      ],
    ];
  }

  Future<void> _applyAutoLayout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr("Auto-Layout anwenden?")),
        content: Text(context.tr(
            "Das aktuelle Layout dieses Kontexts wird durch ein automatisch aus den gelieferten Geräten und Messpunkten erzeugtes ersetzt.")),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr("Abbrechen"))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr("Ersetzen"))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => panels = _autoLayout());
    await _save();
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
    var store = false;
    if (encoded != null) {
      try {
        final decoded = jsonDecode(encoded);
        var version = 1;
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
          final savedVersion = decoded['version'];
          if (savedVersion is int) version = savedVersion;
        } else if (decoded is List) {
          // Read the original v1 list layout and upgrade it below.
          restored =
              decoded.map(_PanelSpec.fromJson).whereType<_PanelSpec>().toList();
        }
        // Layouts saved before the gauge panels existed only knew the plain
        // value tile. Show bounded signals as gauges once; the user can switch
        // every panel back afterwards.
        if (version < _layoutVersion && observations.isNotEmpty) {
          final byKey = {
            for (final item in observations) observationKey(item): item
          };
          restored = [
            for (final panel in restored)
              if (panel.kind == _PanelKind.value &&
                  byKey[panel.observationKey] != null)
                panel.withKind(_defaultKind(byKey[panel.observationKey]!))
              else
                panel,
          ];
          store = true;
        }
      } catch (_) {
        restored = [];
      }
    } else {
      // First view is useful immediately, but only from data actually
      // supplied by this authorized context.
      restored = _autoLayout();
      store = true;
    }
    if (store) await preferences.setString(key, _encode(restored));
    if (!mounted || storageKey != key) return;
    setState(() {
      panels = restored;
      loaded = true;
    });
  }

  String _encode(List<_PanelSpec> value) => jsonEncode({
        'version': _layoutVersion,
        'columns': columns,
        'panels': value.map((panel) => panel.toJson()).toList(),
      });

  Future<void> _save() async {
    final key = storageKey;
    if (key == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, _encode(panels));
  }

  List<Observation> get observations =>
      controller.snapshot?.metrics ?? const [];

  Future<void> _addPanel() async {
    final candidates = observations;
    final selected = await showDialog<_PanelSpec>(
      context: context,
      builder: (context) => _AddPanelDialog(observations: candidates),
    );
    if (selected == null || !mounted) return;
    setState(() => panels.add(selected));
    await _save();
  }

  Future<void> _configure(int index, Observation? observation) async {
    final updated = await showDialog<_PanelSpec>(
      context: context,
      builder: (context) => _PanelOptionsDialog(
        spec: panels[index],
        observation: observation,
        samples: session[panels[index].observationKey] ?? const [],
      ),
    );
    if (updated == null || !mounted || index >= panels.length) return;
    setState(() => panels[index] = updated);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final scope = controller.infrastructure;
    final scopeLabel =
        scope.ready ? scope.selectedBreadcrumb : 'Kein autorisierter Kontext';
    final activeKey = currentStorageKey;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _toolbar(context, scopeLabel, activeKey),
      const SizedBox(height: OipTokens.s2),
      if (controller.api is HueApi)
        for (final bridge in controller.snapshot?.devices ?? const <Device>[])
          if (bridge.hasHueLights)
            Padding(
              key: ValueKey(
                  'hue-${controller.contextScopeSignature}-${bridge.sourceId}'),
              padding: const EdgeInsets.only(bottom: OipTokens.s2),
              child: HueLightsPanel(
                api: controller.api as HueApi,
                source: bridge.sourceId!,
                bridgeName: bridge.name,
              ),
            ),
      if (!loaded)
        const LinearProgressIndicator()
      else if (activeKey == null)
        WorkstationNote(
          context.tr("Dashboard schreibgeschützt"),
          context.tr(
              "Eine angemeldete Sitzung und ein autorisierter Infrastrukturkontext sind erforderlich, damit das persönliche Layout getrennt gespeichert wird."),
          icon: Icons.lock_outline,
        )
      else if (panels.isEmpty)
        WorkstationNote(
          context.tr("Noch keine Panels"),
          context.tr(
              "Füge Panels hinzu oder wähle unter „Anpassen“ das Auto-Layout. Angezeigt werden nur Daten des aktuellen Infrastrukturkontexts."),
          icon: Icons.dashboard_customize_outlined,
        )
      else
        LayoutBuilder(builder: (context, constraints) {
          final effectiveColumns = constraints.maxWidth < 520
              ? 1
              : constraints.maxWidth < 900
                  ? columns.clamp(1, 2)
                  : columns;
          const gap = OipTokens.s2;
          // Floor the tile width so rounding never pushes the last tile of a
          // row into the next one.
          final tileWidth =
              ((constraints.maxWidth - gap * (effectiveColumns - 1)) /
                      effectiveColumns)
                  .floorToDouble();
          final byKey = <String, Observation>{};
          for (final item in observations) {
            byKey.putIfAbsent(observationKey(item), () => item);
          }
          return Wrap(
            key: const Key('overview-modular-dashboard-panels'),
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var index = 0; index < panels.length; index++)
                SizedBox(
                  width: () {
                    final span =
                        panels[index].span ?? panels[index].kind.defaultSpan;
                    return span == 0 || span >= effectiveColumns
                        ? constraints.maxWidth
                        : tileWidth * span + gap * (span - 1);
                  }(),
                  child: _DashboardPanel(
                    observation: byKey[panels[index].observationKey],
                    spec: panels[index],
                    samples: session[panels[index].observationKey] ?? const [],
                    all: observations,
                    session: session,
                    devices: controller.snapshot?.devices ?? const [],
                    editing: editing,
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
                    onConfigure: () =>
                        _configure(index, byKey[panels[index].observationKey]),
                  ),
                ),
            ],
          );
        }),
    ]);
  }

  Widget _toolbar(BuildContext context, String scopeLabel, String? activeKey) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: WorkstationTokens.panel(context),
        border: Border.all(color: WorkstationTokens.hairline(context)),
        borderRadius: BorderRadius.circular(DashboardPanelFrame.radius),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.dashboard_outlined,
                  color: OipTokens.cyan, size: 17),
              const SizedBox(width: 7),
              Flexible(
                child: Text(scopeLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 10),
              _LiveIndicator(live: controller.connection == 'live'),
            ]),
            const SizedBox(height: 4),
            Text(
              activeKey == null
                  ? context.tr(
                      "Zum Bearbeiten anmelden und eine Infrastruktur auswählen.")
                  : context.tr(
                      "{0} Panels · {1} gelieferte Messpunkte · persönliches Layout",
                      [panels.length, observations.length]),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
        final controls = Wrap(spacing: 8, runSpacing: 8, children: [
          if (editing)
            OutlinedButton.icon(
              key: const Key('overview-dashboard-auto-layout'),
              onPressed: _applyAutoLayout,
              icon: const Icon(Icons.auto_awesome_mosaic_outlined, size: 17),
              label: Text(context.tr("Auto-Layout")),
            ),
          if (editing)
            PopupMenuButton<int>(
              tooltip: 'Spaltenbreite',
              initialValue: columns,
              onSelected: (value) async {
                setState(() => columns = value);
                await _save();
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 1, child: Text(context.tr("1 Spalte"))),
                PopupMenuItem(value: 2, child: Text(context.tr("2 Spalten"))),
                PopupMenuItem(value: 3, child: Text(context.tr("3 Spalten"))),
                PopupMenuItem(value: 4, child: Text(context.tr("4 Spalten"))),
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
                  Text(context.tr("{0} Spalten", [columns])),
                ]),
              ),
            ),
          OutlinedButton.icon(
            key: const Key('overview-dashboard-edit'),
            onPressed: activeKey == null
                ? null
                : () => setState(() => editing = !editing),
            icon: Icon(editing ? Icons.check : Icons.tune, size: 17),
            label:
                Text(editing ? context.tr("Fertig") : context.tr("Anpassen")),
          ),
          FilledButton.icon(
            key: const Key('overview-dashboard-add-panel'),
            onPressed: activeKey == null ? null : _addPanel,
            icon: const Icon(Icons.add, size: 17),
            label: Text(context.tr("Panel hinzufügen")),
          ),
        ]);
        return box.maxWidth < 780
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [heading, const SizedBox(height: 10), controls],
              )
            : Row(children: [
                Expanded(child: heading),
                const SizedBox(width: 12),
                controls,
              ]);
      }),
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  final Observation? observation;
  final _PanelSpec spec;
  final List<Observation> samples;
  final List<Observation> all;
  final Map<String, List<Observation>> session;
  final List<Device> devices;
  final bool editing;
  final VoidCallback onRemove;
  final ValueChanged<int> onMove;
  final VoidCallback onConfigure;

  const _DashboardPanel({
    required this.observation,
    required this.spec,
    required this.samples,
    required this.all,
    required this.session,
    required this.devices,
    required this.editing,
    required this.onRemove,
    required this.onMove,
    required this.onConfigure,
  });

  Widget _action(String tooltip, IconData icon, VoidCallback onPressed) =>
      SizedBox(
        width: 26,
        height: 26,
        child: IconButton(
          padding: EdgeInsets.zero,
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: 15),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final item = observation;
    final kind = spec.kind;
    final height = kind.naturalHeight ? null : _tileHeight;
    final actions = [
      if (editing) ...[
        _action('Panel nach vorne verschieben', Icons.chevron_left,
            () => onMove(-1)),
        _action('Panel nach hinten verschieben', Icons.chevron_right,
            () => onMove(1)),
        _action('Panel konfigurieren', Icons.settings_outlined, onConfigure),
        _action('Panel entfernen', Icons.close, onRemove),
      ],
    ];
    final parts = spec.observationKey.split('\u001f');

    if (kind == _PanelKind.heading) {
      return _HeadingPanel(
          title: spec.title?.trim().isNotEmpty == true
              ? spec.title!.trim()
              : 'Abschnitt',
          actions: actions);
    }
    if (kind == _PanelKind.devices) {
      return DashboardPanelFrame(
        title: 'Gerätestatus',
        subtitle: '${devices.length} Geräte · Erreichbarkeit laut Core',
        actions: actions,
        child: _DevicesBody(devices: devices),
      );
    }
    if (kind == _PanelKind.compare) {
      return DashboardPanelFrame(
        title: parts.last,
        subtitle: 'Vergleich über Geräte',
        actions: actions,
        child: _CompareBody(spec: spec, metricId: parts.last, all: all),
      );
    }
    if (item == null) {
      return DashboardPanelFrame(
        title: parts.last,
        subtitle: parts.length > 1 ? parts[1] : null,
        stateColor: OipTokens.statusColor(context, 'unknown'),
        badge: 'KEIN SIGNAL',
        actions: actions,
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Text(
              context.tr(
                  "Das konfigurierte Signal ist in diesem Kontext nicht verfügbar."),
              style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }
    if (kind == _PanelKind.table) {
      return DashboardPanelFrame(
        title: item.entityId,
        subtitle: item.sourceId ?? 'Quelle nicht angegeben',
        actions: actions,
        child: _TableBody(anchor: item, all: all, session: session),
      );
    }

    final fresh = item.freshness == 'fresh';
    final stateColor = OipTokens.statusColor(context, item.freshness);
    final received = item.receivedMs == null
        ? 'Empfangszeit nicht geliefert'
        : 'Empfangen ${DateTime.fromMillisecondsSinceEpoch(item.receivedMs!, isUtc: true).toLocal().toString().substring(11, 19)}';
    final scale = _resolveScale(spec, item, samples);
    final number = item.number;
    // A value that is not fresh is never drawn in a live threshold colour.
    final color = !fresh || number == null
        ? OipTokens.muted(context)
        : _levelColor(context, scale.level(number));

    final Widget body;
    if (kind == _PanelKind.trend) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (samples.length < 2)
              SizedBox(
                height: 120,
                child: Center(
                  child: Text(context.tr(
                      "Sammle Verlauf – mindestens zwei frische Samples erforderlich.")),
                ),
              )
            else
              OverviewTrendChart(
                  samples: samples,
                  unit: item.symbol,
                  simulated: item.simulated,
                  height: 220),
            const SizedBox(height: 4),
            Text(
                context.tr(
                    "Session-Verlauf · {0} Samples seit Öffnen des Dashboards · keine persistierte Historie",
                    [samples.length]),
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    } else if (number == null) {
      body = Center(
        child: Text(item.display,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: OipTokens.muted(context))),
      );
    } else {
      body = switch (kind) {
        _PanelKind.gauge || _PanelKind.ring => _GaugeBody(
            item: item,
            value: number,
            scale: scale,
            color: color,
            ring: kind == _PanelKind.ring),
        _PanelKind.bar =>
          _BarBody(item: item, value: number, scale: scale, color: color),
        _PanelKind.tank =>
          _TankBody(item: item, value: number, scale: scale, color: color),
        _PanelKind.spark || _PanelKind.bars => _SeriesBody(
            item: item,
            samples: samples,
            color: color,
            bars: kind == _PanelKind.bars),
        _PanelKind.histogram =>
          _HistogramBody(item: item, samples: samples, color: color),
        _PanelKind.timeline => _TimelineBody(
            item: item, samples: samples, scale: scale, color: color),
        _PanelKind.stats =>
          _StatsBody(item: item, value: number, samples: samples, color: color),
        _ => _StatBody(item: item, samples: samples, color: color),
      };
    }

    return DashboardPanelFrame(
      title: item.metricId,
      subtitle: item.entityId,
      tooltip:
          '${item.sourceId ?? 'Quelle nicht angegeben'} · ${item.entityId}\n'
          '$received · Qualität ${item.quality} · ${item.freshness}',
      stateColor: stateColor,
      badge: fresh ? null : item.freshness.toUpperCase(),
      actions: actions,
      height: height,
      child: body,
    );
  }
}

TextStyle _valueStyle(BuildContext context, Color color, double size) =>
    TextStyle(
      fontSize: size,
      height: 1.05,
      fontWeight: FontWeight.w600,
      letterSpacing: -.5,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

class _ValueText extends StatelessWidget {
  final Observation item;
  final Color color;
  final double size;
  const _ValueText(
      {required this.item, required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    final formatted = _formatObservation(item);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text.rich(
        TextSpan(text: formatted.text, children: [
          if (formatted.unit.isNotEmpty)
            TextSpan(
                text: ' ${formatted.unit}',
                style: TextStyle(fontSize: size * .5, letterSpacing: 0)),
        ]),
        maxLines: 1,
        style: _valueStyle(context, color, size),
      ),
    );
  }
}

class _GaugeBody extends StatelessWidget {
  final Observation item;
  final double value;
  final _Scale scale;
  final Color color;
  final bool ring;
  const _GaugeBody({
    required this.item,
    required this.value,
    required this.scale,
    required this.color,
    this.ring = false,
  });

  @override
  Widget build(BuildContext context) {
    final bounds = WorkstationTokens.mono(context,
        size: 10, color: OipTokens.muted(context));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Column(children: [
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            return Stack(alignment: Alignment.center, children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GaugePainter(
                    ring: ring,
                    fraction: scale.fraction(value),
                    color: color,
                    track: WorkstationTokens.hairline(context),
                    bands: [
                      for (final band in _bands(scale))
                        (
                          from: band.from,
                          to: band.to,
                          color: _levelColor(context, band.level)
                        ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment(0, ring ? 0 : .5),
                child: SizedBox(
                  width: math.min(box.maxWidth, box.maxHeight * 1.3) *
                      (ring ? .42 : .56),
                  child: _ValueText(
                      item: item,
                      color: color,
                      size: (box.maxHeight * .24).clamp(18.0, 34.0)),
                ),
              ),
            ]);
          }),
        ),
        Row(children: [
          Text(_formatBound(scale.min, item), style: bounds),
          Expanded(
            child: Text(scale.auto ? context.tr("Skala automatisch") : '',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: bounds),
          ),
          Text(_formatBound(scale.max, item), style: bounds),
        ]),
      ]),
    );
  }
}

/// The threshold segments of a scale as fractions of its range.
List<({double from, double to, int? level})> _bands(_Scale scale) {
  if (scale.warn == null && scale.crit == null) {
    return [(from: 0, to: 1, level: null)];
  }
  final warn = scale.warn == null ? null : scale.fraction(scale.warn!);
  final crit = scale.crit == null ? null : scale.fraction(scale.crit!);
  final normalEnd = warn ?? crit!;
  return [
    if (normalEnd > 0) (from: 0, to: normalEnd, level: 0),
    if (warn != null && (crit ?? 1) > warn)
      (from: warn, to: crit ?? 1, level: 1),
    if (crit != null && crit < 1) (from: crit, to: 1, level: 2),
  ];
}

class _GaugePainter extends CustomPainter {
  /// A ring is a closed circle starting at twelve o'clock; the gauge is a
  /// 240° arc starting at 150°.
  final bool ring;
  double get _start => ring ? -math.pi / 2 : math.pi * 5 / 6;
  double get _sweep => ring ? math.pi * 2 : math.pi * 4 / 3;

  final double fraction;
  final Color color, track;
  final List<({double from, double to, Color color})> bands;
  const _GaugePainter({
    this.ring = false,
    required this.fraction,
    required this.color,
    required this.track,
    required this.bands,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    // The 240° arc is 2r wide and 1.5r high.
    final outer = ring
        ? math.min(size.width, size.height) / 2 - 1
        : math.min(size.width / 2, size.height / 1.5) - 1;
    if (outer < 12) return;
    final thickness = (outer * .2).clamp(6.0, 18.0);
    const band = 3.0;
    final center = ring
        ? size.center(Offset.zero)
        : Offset(size.width / 2, (size.height - outer * 1.5) / 2 + outer);
    final bandRect = Rect.fromCircle(center: center, radius: outer - band / 2);
    final valueRadius = outer - band - 3 - thickness / 2;
    final valueRect = Rect.fromCircle(center: center, radius: valueRadius);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    for (final segment in bands) {
      canvas.drawArc(
          bandRect,
          _start + _sweep * segment.from,
          _sweep * (segment.to - segment.from),
          false,
          stroke
            ..strokeWidth = band
            ..color = segment.color);
    }
    canvas.drawArc(
        valueRect,
        _start,
        _sweep,
        false,
        stroke
          ..strokeWidth = thickness
          ..color = track.withOpacity(.55));
    if (fraction > 0) {
      canvas.drawArc(
          valueRect,
          _start,
          _sweep * fraction,
          false,
          stroke
            ..strokeWidth = thickness
            ..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.ring != ring ||
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.bands.length != bands.length ||
      [for (var i = 0; i < bands.length; i++) old.bands[i] != bands[i]]
          .contains(true);
}

class _BarBody extends StatelessWidget {
  final Observation item;
  final double value;
  final _Scale scale;
  final Color color;
  const _BarBody({
    required this.item,
    required this.value,
    required this.scale,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bounds = WorkstationTokens.mono(context,
        size: 10, color: OipTokens.muted(context));
    final live = color != OipTokens.muted(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _ValueText(item: item, color: color, size: 34),
          ),
        ),
        SizedBox(
          height: 30,
          child: CustomPaint(
            painter: _BarPainter(
              fraction: scale.fraction(value),
              unlit: WorkstationTokens.hairline(context),
              colorAt: (position) => live
                  ? _levelColor(
                      context,
                      scale.level(
                          scale.min + (scale.max - scale.min) * position))
                  : color,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Row(children: [
          Text(_formatBound(scale.min, item), style: bounds),
          Expanded(
            child: Text(scale.auto ? context.tr("Skala automatisch") : '',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: bounds),
          ),
          Text(_formatBound(scale.max, item), style: bounds),
        ]),
      ]),
    );
  }
}

/// A segmented ("LCD") horizontal bar: lit cells up to the value, each cell in
/// the colour of the threshold range it lies in.
class _BarPainter extends CustomPainter {
  final double fraction;
  final Color unlit;
  final Color Function(double position) colorAt;
  const _BarPainter({
    required this.fraction,
    required this.unlit,
    required this.colorAt,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    const cell = 7.0, gap = 2.0;
    final count = math.max(1, ((size.width + gap) / (cell + gap)).floor());
    final width = (size.width - gap * (count - 1)) / count;
    final lit = fraction <= 0 ? 0 : math.max(1, (fraction * count).round());
    final paint = Paint();
    for (var index = 0; index < count; index++) {
      paint.color =
          index < lit ? colorAt(index / count) : unlit.withOpacity(.55);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(index * (width + gap), 0, width, size.height),
            const Radius.circular(1.5)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => true;
}

class _StatBody extends StatelessWidget {
  final Observation item;
  final List<Observation> samples;
  final Color color;
  const _StatBody(
      {required this.item, required this.samples, required this.color});

  @override
  Widget build(BuildContext context) {
    final values = [
      for (final sample in samples)
        if (sample.number != null) sample.number!,
    ];
    return Stack(children: [
      if (values.length > 1)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 64,
          child: CustomPaint(painter: _SparklinePainter(values, color)),
        ),
      Positioned.fill(
        bottom: values.length > 1 ? 54 : 10,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(child: _ValueText(item: item, color: color, size: 40)),
        ),
      ),
    ]);
  }
}

/// The session samples of a stat panel as a line with a faded area below.
class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _SparklinePainter(List<double> values, this.color) : values = List.of(values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;
    final min = values.reduce(math.min);
    final max = values.reduce(math.max);
    final range = max - min;
    final line = Path();
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final normalized = range == 0 ? .5 : (values[index] - min) / range;
      final y = size.height - 6 - normalized * (size.height - 12);
      if (index == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(.28), color.withOpacity(.03)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) {
    if (old.color != color || old.values.length != values.length) return true;
    for (var index = 0; index < values.length; index++) {
      if (old.values[index] != values[index]) return true;
    }
    return false;
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
          Text(live ? context.tr("LIVE") : context.tr("VERBINDUNG PRÜFEN"),
              style: WorkstationTokens.eyebrow(context,
                  color: OipTokens.statusColor(
                      context, live ? 'fresh' : 'stale'))),
        ]),
      );
}

/// The visualisation picker: every kind as a chip with its icon.
class _KindPicker extends StatelessWidget {
  final _PanelKind kind;
  final ValueChanged<_PanelKind> onChanged;
  const _KindPicker({required this.kind, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final value in _PanelKind.values)
              ChoiceChip(
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                avatar: Icon(value.icon, size: 16),
                label: Text(value.label),
                selected: value == kind,
                onSelected: (_) => onChanged(value),
              ),
          ]),
          const SizedBox(height: 8),
          Text(kind.hint, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _AddPanelDialog extends StatefulWidget {
  final List<Observation> observations;
  const _AddPanelDialog({required this.observations});

  @override
  State<_AddPanelDialog> createState() => _AddPanelDialogState();
}

class _AddPanelDialogState extends State<_AddPanelDialog> {
  String? selectedKey;
  _PanelKind kind = _PanelKind.gauge;
  final title = TextEditingController();

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final choices = <String, Observation>{};
    for (final item in widget.observations) {
      choices.putIfAbsent(observationKey(item), () => item);
    }
    selectedKey ??= choices.keys.firstOrNull;
    return AlertDialog(
      title: Text(context.tr("Dashboard-Panel hinzufügen")),
      content: SizedBox(
          width: 520,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _KindPicker(
                    kind: kind,
                    onChanged: (value) => setState(() => kind = value)),
                const SizedBox(height: 14),
                if (kind == _PanelKind.heading)
                  TextField(
                    controller: title,
                    decoration:
                        InputDecoration(labelText: context.tr("Überschrift")),
                  )
                else if (!kind.needsSignal)
                  Text(context.tr("Dieses Panel benötigt kein Messsignal."),
                      style: Theme.of(context).textTheme.bodySmall)
                else if (choices.isEmpty)
                  Text(
                      context.tr(
                          "Dieser Kontext liefert derzeit keine Messsignale."),
                      style: Theme.of(context).textTheme.bodySmall)
                else
                  DropdownButtonFormField<String>(
                    value: selectedKey,
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: context.tr("Live-Messsignal")),
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
              ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr("Abbrechen"))),
        FilledButton(
            onPressed: kind.needsSignal && selectedKey == null
                ? null
                : () => Navigator.pop(
                    context,
                    _PanelSpec(kind.needsSignal ? selectedKey! : '', kind,
                        title: kind == _PanelKind.heading
                            ? title.text.trim()
                            : null)),
            child: Text(context.tr("Hinzufügen"))),
      ],
    );
  }
}

/// Visualisation, width, display range and thresholds of one panel.
class _PanelOptionsDialog extends StatefulWidget {
  final _PanelSpec spec;
  final Observation? observation;
  final List<Observation> samples;
  const _PanelOptionsDialog({
    required this.spec,
    required this.observation,
    required this.samples,
  });

  @override
  State<_PanelOptionsDialog> createState() => _PanelOptionsDialogState();
}

class _PanelOptionsDialogState extends State<_PanelOptionsDialog> {
  late _PanelKind kind = widget.spec.kind;
  late int? span = widget.spec.span;
  late final TextEditingController min, max, warn, crit, title;
  String? error;

  @override
  void initState() {
    super.initState();
    final spec = widget.spec;
    final item = widget.observation;
    // Prefill with what the panel currently shows so that saving without a
    // change keeps the picture.
    final scale =
        item == null ? null : _resolveScale(spec, item, widget.samples);
    String text(double? value) => value == null ? '' : _trim(value, 3);
    min = TextEditingController(text: text(spec.custom ? spec.min : null));
    max = TextEditingController(text: text(spec.custom ? spec.max : null));
    warn = TextEditingController(
        text: text(spec.custom ? spec.warn : scale?.warn));
    crit = TextEditingController(
        text: text(spec.custom ? spec.crit : scale?.crit));
    title = TextEditingController(text: spec.title ?? '');
  }

  @override
  void dispose() {
    for (final field in [min, max, warn, crit, title]) {
      field.dispose();
    }
    super.dispose();
  }

  /// A panel can only become a kind that fits what it is bound to.
  bool _allowed(_PanelKind next) =>
      next.needsSignal == widget.spec.kind.needsSignal;

  String? get _title =>
      kind == _PanelKind.heading ? title.text.trim() : widget.spec.title;

  void _submit() {
    if (!kind.usesScale) {
      Navigator.pop(
          context,
          _PanelSpec(widget.spec.observationKey, kind,
              custom: widget.spec.custom,
              min: widget.spec.min,
              max: widget.spec.max,
              warn: widget.spec.warn,
              crit: widget.spec.crit,
              span: span,
              title: _title));
      return;
    }
    final parsed = <double?>[];
    for (final field in [min, max, warn, crit]) {
      final raw = field.text.trim().replaceAll(',', '.');
      if (raw.isEmpty) {
        parsed.add(null);
        continue;
      }
      final value = double.tryParse(raw);
      if (value == null || !value.isFinite) {
        setState(() => error = 'Bitte nur Zahlen eingeben.');
        return;
      }
      parsed.add(value);
    }
    if (parsed[0] != null && parsed[1] != null && parsed[1]! <= parsed[0]!) {
      setState(() => error = 'Maximum muss größer als Minimum sein.');
      return;
    }
    if (parsed[2] != null && parsed[3] != null && parsed[3]! < parsed[2]!) {
      setState(
          () => error = 'Kritisch darf nicht unter der Warnschwelle liegen.');
      return;
    }
    Navigator.pop(
      context,
      _PanelSpec(widget.spec.observationKey, kind,
          custom: true,
          min: parsed[0],
          max: parsed[1],
          warn: parsed[2],
          crit: parsed[3],
          span: span,
          title: _title),
    );
  }

  Widget _field(TextEditingController controller, String label, String hint) =>
      Expanded(
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: true),
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final symbol = widget.observation?.symbol ?? '';
    final unit = symbol.isEmpty ? '' : ' ($symbol)';
    return AlertDialog(
      title: Text(context.tr("Panel konfigurieren")),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.spec.kind.needsSignal) ...[
                _KindPicker(
                    kind: kind,
                    onChanged: (value) {
                      if (_allowed(value)) setState(() => kind = value);
                    }),
                const SizedBox(height: 16),
              ],
              if (kind == _PanelKind.heading) ...[
                TextField(
                  controller: title,
                  decoration:
                      InputDecoration(labelText: context.tr("Überschrift")),
                ),
                const SizedBox(height: 16),
              ],
              if (kind != _PanelKind.heading) ...[
                Text(context.tr("Breite"),
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 6),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: -1, label: Text(context.tr("Auto"))),
                    ButtonSegment(
                        value: 1, label: Text(context.tr("1 Spalte"))),
                    ButtonSegment(
                        value: 2, label: Text(context.tr("2 Spalten"))),
                    ButtonSegment(
                        value: 0, label: Text(context.tr("Volle Zeile"))),
                  ],
                  selected: {span ?? -1},
                  onSelectionChanged: (value) => setState(
                      () => span = value.first == -1 ? null : value.first),
                ),
              ],
              if (kind.usesScale) ...[
                const SizedBox(height: 16),
                Row(children: [
                  _field(min, 'Minimum$unit', 'automatisch'),
                  const SizedBox(width: 12),
                  _field(max, 'Maximum$unit', 'automatisch'),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  _field(warn, 'Warnung ab$unit', 'keine'),
                  const SizedBox(width: 12),
                  _field(crit, 'Kritisch ab$unit', 'keine'),
                ]),
                const SizedBox(height: 10),
                Text(
                  error ??
                      context.tr(
                          "Skala und Schwellen sind reine Darstellung dieses Panels. Leere Felder: automatische Skala bzw. keine Schwelle."),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: error == null
                          ? null
                          : Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr("Abbrechen"))),
        if (kind.usesScale)
          TextButton(
              onPressed: () => Navigator.pop(
                  context,
                  _PanelSpec(widget.spec.observationKey, kind,
                      span: span, title: _title)),
              child: Text(context.tr("Standard"))),
        FilledButton(onPressed: _submit, child: Text(context.tr("Übernehmen"))),
      ],
    );
  }
}
