import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/oip_strings.dart';
import '../../models/contracts.dart';
import '../../models/hue.dart';
import '../../services/api.dart';

class HueLightsPanel extends StatefulWidget {
  final HueApi api;
  final String source, bridgeName;
  const HueLightsPanel(
      {super.key,
      required this.api,
      required this.source,
      required this.bridgeName});

  @override
  State<HueLightsPanel> createState() => _HueLightsPanelState();
}

class _HueLightsPanelState extends State<HueLightsPanel> {
  HueLights? data;
  String? readError, commandError;
  Timer? timer;
  int generation = 0;
  bool fetching = false;
  int? writing;

  @override
  void initState() {
    super.initState();
    _refresh();
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!fetching && writing == null) _refresh();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final ticket = ++generation;
    fetching = true;
    try {
      final next = await widget.api.hueLights(widget.source);
      if (mounted && ticket == generation)
        setState(() {
          data = next;
          readError = null;
        });
    } catch (e) {
      if (mounted && ticket == generation)
        setState(() {
          data = null;
          readError = apiErrorMessage(
              e, context.tr('Hue-Lichter konnten nicht geladen werden.'));
        });
    } finally {
      if (ticket == generation) fetching = false;
    }
  }

  Future<void> _change(HueLight light, Json change) async {
    if (writing != null || data?.canControl != true) return;
    ++generation;
    setState(() {
      writing = light.id;
      commandError = null;
    });
    try {
      await widget.api.changeHueLight(widget.source, light.id, change);
      await Future<void>.delayed(const Duration(milliseconds: 450));
    } catch (e) {
      if (mounted)
        setState(() => commandError = apiErrorMessage(
            e, context.tr('Die Bridge hat die Änderung nicht bestätigt.')));
    } finally {
      if (mounted) await _refresh();
      if (mounted) setState(() => writing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lights = data?.lights ?? const <HueLight>[];
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.lightbulb_outline),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(context.tr('Hue-Beleuchtung'),
                      style: Theme.of(context).textTheme.titleLarge)),
              IconButton(
                  tooltip: context.tr('Lichter aktualisieren'),
                  icon: const Icon(Icons.refresh),
                  onPressed: writing == null ? _refresh : null),
            ]),
            Text(widget.bridgeName,
                style: Theme.of(context).textTheme.bodySmall),
            if (data == null && readError == null)
              const LinearProgressIndicator(),
            if (readError != null) Text(readError!),
            if (commandError != null)
              Semantics(
                  liveRegion: true,
                  child: Text(commandError!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            if (data != null && lights.isEmpty)
              Text(context
                  .tr('Auf dieser Bridge sind keine Lichter eingerichtet.')),
            if (lights.isNotEmpty && !data!.canControl)
              Text(context.tr(
                  'Zum Steuern mit einem berechtigten Operator-Konto anmelden.')),
            if (lights.isNotEmpty)
              LayoutBuilder(builder: (context, constraints) {
                const gap = 10.0;
                final columns =
                    ((constraints.maxWidth + gap) / 285).floor().clamp(1, 4);
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(spacing: gap, runSpacing: gap, children: [
                  for (final light in lights)
                    SizedBox(
                        width: width,
                        child: _LightTile(
                            key: ValueKey(light.id),
                            light: light,
                            allowed: data!.canControl &&
                                writing == null &&
                                light.reachable,
                            pending: writing == light.id,
                            onChange: (change) => _change(light, change))),
                ]);
              }),
          ],
        ));
  }
}

class _LightTile extends StatefulWidget {
  final HueLight light;
  final bool allowed, pending;
  final ValueChanged<Json> onChange;
  const _LightTile(
      {super.key,
      required this.light,
      required this.allowed,
      required this.pending,
      required this.onChange});
  @override
  State<_LightTile> createState() => _LightTileState();
}

class _LightTileState extends State<_LightTile> {
  double? dragging;

  Future<void> _pick() async {
    final change = await showDialog<Json>(
        context: context,
        builder: (context) => _LightColor(light: widget.light));
    if (mounted && change != null && widget.allowed && widget.light.on)
      widget.onChange(change);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.light;
    final active = l.on && l.reachable;
    final theme = Theme.of(context);
    final color = l.hasColor && l.colorMode != 'ct'
        ? HSVColor.fromAHSV(
                1, l.hue!.clamp(0, 360), l.saturation!.clamp(0, 100) / 100, 1)
            .toColor()
        : const Color(0xffffcf83);
    return Card(
        margin: EdgeInsets.zero,
        child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(
                    radius: 17,
                    backgroundColor: active
                        ? color.withOpacity(.18)
                        : theme.colorScheme.surfaceVariant,
                    child: Icon(
                        l.kind.toLowerCase().contains('plug')
                            ? Icons.power
                            : Icons.lightbulb,
                        size: 20,
                        color: active ? color : null)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(l.name, style: theme.textTheme.titleSmall)),
                Semantics(
                    label: context.tr('{0} schalten', [l.name]),
                    child: Switch(
                        value: l.on,
                        onChanged: widget.allowed
                            ? (v) => widget.onChange({'kind': 'power', 'on': v})
                            : null)),
              ]),
              if (!l.reachable) Text(context.tr('Nicht erreichbar')),
              if (widget.pending) const LinearProgressIndicator(),
              if (l.brightness != null)
                Row(children: [
                  const Icon(Icons.brightness_6_outlined, size: 16),
                  Expanded(
                      child: Semantics(
                          label: context.tr('Helligkeit von {0}', [l.name]),
                          child: Slider(
                            min: 1,
                            max: 100,
                            divisions: 99,
                            value: (dragging ?? l.brightness!).clamp(1, 100),
                            onChanged: widget.allowed && l.on
                                ? (v) => setState(() => dragging = v)
                                : null,
                            onChangeEnd: (v) {
                              setState(() => dragging = null);
                              widget.onChange(
                                  {'kind': 'brightness', 'percent': v.round()});
                            },
                          ))),
                  Text('${(dragging ?? l.brightness!).round()} %'),
                ]),
              if (l.hasColor || l.hasWhite)
                TextButton.icon(
                    onPressed: widget.allowed && l.on ? _pick : null,
                    icon: const Icon(Icons.palette_outlined, size: 18),
                    label: Text(
                        context.tr(l.hasColor ? 'Lichtfarbe' : 'Weißton'))),
            ])));
  }
}

class _LightColor extends StatefulWidget {
  final HueLight light;
  const _LightColor({required this.light});
  @override
  State<_LightColor> createState() => _LightColorState();
}

class _LightColorState extends State<_LightColor> {
  late bool white = !widget.light.hasColor ||
      (widget.light.hasWhite && widget.light.colorMode == 'ct');
  late double hue = widget.light.hue ?? 0, sat = widget.light.saturation ?? 100;
  late double ct = (widget.light.ct ?? 0).toDouble();
  @override
  Widget build(BuildContext context) {
    final l = widget.light;
    final preview = HSVColor.fromAHSV(1, hue, sat / 100, 1).toColor();
    return AlertDialog(
        title: Text(l.name),
        content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  if (l.hasColor && l.hasWhite)
                    Wrap(spacing: 8, children: [
                      ChoiceChip(
                          label: Text(context.tr('Farbe')),
                          selected: !white,
                          onSelected: (_) => setState(() => white = false)),
                      ChoiceChip(
                          label: Text(context.tr('Weißton')),
                          selected: white,
                          onSelected: (_) => setState(() => white = true)),
                    ]),
                  const SizedBox(height: 12),
                  if (white) ...[
                    Text(context.tr('Farbtemperatur')),
                    Slider(
                        min: l.ctMin!.toDouble(),
                        max: l.ctMax!.toDouble(),
                        value:
                            ct.clamp(l.ctMin!.toDouble(), l.ctMax!.toDouble()),
                        onChanged: (v) => setState(() => ct = v)),
                    Text(
                        '${(1000000 / ct.clamp(l.ctMin!.toDouble(), l.ctMax!.toDouble())).round()} K'),
                  ] else ...[
                    Container(
                        height: 32,
                        decoration: BoxDecoration(
                            color: preview,
                            borderRadius: BorderRadius.circular(8))),
                    const SizedBox(height: 12),
                    Text(context.tr('Farbton')),
                    DecoratedBox(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(colors: [
                              Colors.red,
                              Colors.yellow,
                              Colors.green,
                              Colors.cyan,
                              Colors.blue,
                              Colors.purple,
                              Colors.red
                            ])),
                        child: Slider(
                            min: 0,
                            max: 360,
                            value: hue,
                            label: '${hue.round()}°',
                            divisions: 360,
                            onChanged: (v) => setState(() => hue = v))),
                    Text(context.tr('Sättigung')),
                    Slider(
                        min: 0,
                        max: 100,
                        value: sat,
                        label: '${sat.round()} %',
                        divisions: 100,
                        onChanged: (v) => setState(() => sat = v)),
                  ],
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('Abbrechen'))),
          FilledButton(
              onPressed: () => Navigator.pop(
                  context,
                  white
                      ? {
                          'kind': 'temperature',
                          'mired': ct
                              .clamp(l.ctMin!.toDouble(), l.ctMax!.toDouble())
                              .round()
                        }
                      : {
                          'kind': 'color',
                          'degrees': hue.round(),
                          'saturation': sat.round()
                        }),
              child: Text(context.tr('Übernehmen'))),
        ]);
  }
}
