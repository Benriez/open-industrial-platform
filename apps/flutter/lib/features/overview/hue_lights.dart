import 'dart:async';
import 'package:flutter/material.dart';
import '../../design_system/theme.dart';
import '../../l10n/oip_strings.dart';
import '../../models/contracts.dart';
import '../../models/hue.dart';
import '../../services/api.dart';
import '../../widgets/workstation.dart';
import 'dashboard_panel_frame.dart';

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
    return DashboardPanelFrame(
      title: context.tr('Hue-Beleuchtung'),
      subtitle: widget.bridgeName,
      actions: [
        IconButton(
          tooltip: context.tr('Lichter aktualisieren'),
          icon: const Icon(Icons.refresh, size: 16),
          onPressed: writing == null ? _refresh : null,
        )
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (data == null && readError == null)
            const LinearProgressIndicator(minHeight: 2),
          if (readError != null) Text(readError!),
          if (commandError != null)
            Semantics(
                liveRegion: true,
                child: Text(commandError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (data != null && lights.isEmpty)
            Text(context
                .tr('Auf dieser Bridge sind keine Lichter eingerichtet.')),
          if (lights.isNotEmpty && !data!.canControl)
            Text(context.tr(
                'Zum Steuern mit einem berechtigten Operator-Konto anmelden.')),
          if (lights.isNotEmpty)
            LayoutBuilder(builder: (context, box) {
              const gutter = 24.0;
              final width = box.maxWidth >= 1040
                  ? (box.maxWidth - gutter) / 2
                  : box.maxWidth;
              return Wrap(spacing: gutter, children: [
                for (final light in lights)
                  SizedBox(
                      key: ValueKey(light.id),
                      width: width,
                      child: _LightRow(
                          light: light,
                          allowed: data!.canControl &&
                              writing == null &&
                              light.reachable,
                          pending: writing == light.id,
                          onChange: (change) => _change(light, change))),
              ]);
            }),
        ]),
      ),
    );
  }
}

class _LightRow extends StatefulWidget {
  final HueLight light;
  final bool allowed, pending;
  final ValueChanged<Json> onChange;
  const _LightRow(
      {required this.light,
      required this.allowed,
      required this.pending,
      required this.onChange});
  @override
  State<_LightRow> createState() => _LightRowState();
}

class _LightRowState extends State<_LightRow> {
  double? dragging;

  Future<void> _pick() async {
    final change = await showDialog<Json>(
        context: context,
        builder: (context) => _LightColor(light: widget.light));
    if (mounted && change != null && widget.allowed && widget.light.on) {
      widget.onChange(change);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.light;
    final theme = Theme.of(context);
    final accent = OipTokens.readableAccent(context, OipTokens.cyan);
    final muted = OipTokens.muted(context);
    final editable = widget.allowed && l.on;
    final color = l.hasColor && l.colorMode != 'ct'
        ? HSVColor.fromAHSV(
                1, l.hue!.clamp(0, 360), l.saturation!.clamp(0, 100) / 100, 1)
            .toColor()
        : OipTokens.readableAccent(context, OipTokens.yellow);
    final name = Row(children: [
      Icon(
          l.kind.toLowerCase().contains('plug')
              ? Icons.power_outlined
              : Icons.lightbulb_outline,
          size: 17,
          color: l.reachable && l.on ? accent : muted),
      const SizedBox(width: 8),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.name,
            style: theme.textTheme.labelLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        if (!l.reachable)
          Text(context.tr('Nicht erreichbar'),
              style: WorkstationTokens.mono(context,
                  size: 10,
                  color: OipTokens.statusColor(context, 'unavailable'))),
      ])),
    ]);
    final power = Semantics(
        container: true,
        label: context.tr('{0} schalten', [l.name]),
        child: Switch(
          value: l.on,
          activeColor: accent,
          activeTrackColor: accent.withOpacity(.22),
          onChanged: widget.allowed
              ? (v) => widget.onChange({'kind': 'power', 'on': v})
              : null,
        ));
    final colorButton = l.hasColor || l.hasWhite
        ? TextButton.icon(
            onPressed: editable ? _pick : null,
            style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurface,
                textStyle: theme.textTheme.labelSmall,
                padding: const EdgeInsets.symmetric(horizontal: 6)),
            icon: Icon(Icons.palette_outlined,
                size: 15, color: editable ? color : muted),
            label: Text(context.tr(l.hasColor ? 'Lichtfarbe' : 'Weißton')))
        : null;
    final brightness = l.brightness;
    final dimmer = brightness == null
        ? null
        : Row(children: [
            Expanded(
                child: Semantics(
              container: true,
              label: context.tr('Helligkeit von {0}', [l.name]),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    tickMarkShape: SliderTickMarkShape.noTickMark,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 13)),
                child: Slider(
                  min: 1,
                  max: 100,
                  divisions: 99,
                  activeColor: accent,
                  inactiveColor: WorkstationTokens.line(context),
                  semanticFormatterCallback: (v) => '${v.round()} %',
                  value: (dragging ?? brightness).clamp(1, 100),
                  onChanged:
                      editable ? (v) => setState(() => dragging = v) : null,
                  onChangeEnd: editable
                      ? (v) {
                          setState(() => dragging = null);
                          widget.onChange(
                              {'kind': 'brightness', 'percent': v.round()});
                        }
                      : null,
                ),
              ),
            )),
            SizedBox(
                width: 40,
                child: Text('${(dragging ?? brightness).round()} %',
                    textAlign: TextAlign.end,
                    style: WorkstationTokens.mono(context,
                        size: 11, color: muted))),
          ]);
    return Container(
      decoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: WorkstationTokens.hairline(context)))),
      child: LayoutBuilder(builder: (context, box) {
        final compact = box.maxWidth < 420;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 46),
                child: Row(children: [
                  Expanded(child: name),
                  if (!compact) ...[
                    SizedBox(
                        width: box.maxWidth < 530 ? 122 : 166, child: dimmer),
                    const SizedBox(width: 10),
                    SizedBox(width: 90, child: colorButton),
                  ] else if (colorButton != null)
                    colorButton,
                  power,
                ]),
              ),
              if (compact && dimmer != null)
                Padding(
                    padding: const EdgeInsets.only(left: 24, right: 8),
                    child: dimmer),
              if (widget.pending) const LinearProgressIndicator(minHeight: 2),
            ]);
      }),
    );
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
        backgroundColor: WorkstationTokens.panel(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: WorkstationTokens.hairline(context))),
        title: Text(l.name, style: Theme.of(context).textTheme.titleMedium),
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
                    Stack(alignment: Alignment.center, children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              gradient: const LinearGradient(colors: [
                                Color(0xffff0000),
                                Color(0xffffff00),
                                Color(0xff00ff00),
                                Color(0xff00ffff),
                                Color(0xff0000ff),
                                Color(0xffff00ff),
                                Color(0xffff0000),
                              ]),
                            )),
                      ),
                      SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: Colors.transparent,
                            inactiveTrackColor: Colors.transparent,
                            activeTickMarkColor: Colors.transparent,
                            inactiveTickMarkColor: Colors.transparent,
                          ),
                          child: Slider(
                              min: 0,
                              max: 360,
                              value: hue,
                              label: '${hue.round()}°',
                              divisions: 360,
                              onChanged: (v) => setState(() => hue = v))),
                    ]),
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
