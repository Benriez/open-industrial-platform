import '../../l10n/oip_strings.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import '../../widgets/components.dart';
import '../../widgets/trend.dart';
import '../../widgets/workstation.dart';

/// Session-local, time-scaled telemetry. Missing and bad samples break the line.
class OverviewTrendChart extends StatefulWidget {
  final List<Observation> samples;
  final List<CollectionEvent> gaps;
  final String unit;
  final bool simulated;
  final double height;
  const OverviewTrendChart({
    super.key,
    required this.samples,
    this.gaps = const [],
    this.unit = '',
    this.simulated = false,
    this.height = 156,
  });

  @override
  State<OverviewTrendChart> createState() => OverviewTrendChartState();
}

class OverviewTrendChartState extends State<OverviewTrendChart> {
  int? selected;
  int zoom = 1;
  final FocusNode sampleNextFocus =
      FocusNode(debugLabel: 'overview-next-sample');

  void focusNextSampleAction() => sampleNextFocus.requestFocus();

  @override
  void dispose() {
    sampleNextFocus.dispose();
    super.dispose();
  }

  List<Observation> get visibleSamples {
    final samples = widget.samples;
    if (zoom == 1 || samples.length <= 2) return samples;
    final count = math.max(2, (samples.length / zoom).ceil());
    final start = samples.length - count;
    return samples.sublist(start, start + count);
  }

  List<int> get selectable => [
        for (var index = 0; index < visibleSamples.length; index++)
          if (visibleSamples[index].number != null &&
              visibleSamples[index].sourceMs != null)
            index,
      ];

  @override
  void didUpdateWidget(covariant OverviewTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSignal = oldWidget.samples.firstOrNull;
    final newSignal = widget.samples.firstOrNull;
    if (oldSignal != null &&
        newSignal != null &&
        observationKey(oldSignal) != observationKey(newSignal)) {
      zoom = 1;
      selected = null;
    }
    if (selected != null &&
        (selected! >= visibleSamples.length ||
            visibleSamples[selected!].number == null)) {
      selected = null;
    }
  }

  void selectRelative(bool forward) {
    final indices = selectable;
    if (indices.isEmpty) return;
    final position = selected == null ? -1 : indices.indexOf(selected!);
    final next = forward
        ? indices[(position + 1).clamp(0, indices.length - 1)]
        : indices[position < 0
            ? indices.length - 1
            : (position - 1).clamp(0, indices.length - 1)];
    setState(() => selected = next);
  }

  void setZoom(int value) {
    setState(() {
      zoom = value.clamp(1, 8);
      selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final samples = visibleSamples;
    final numbers = samples
        .where((sample) => sample.number != null)
        .map((sample) => sample.number!)
        .toList();
    final minimum =
        numbers.isEmpty ? null : numbers.reduce((a, b) => a < b ? a : b);
    final maximum =
        numbers.isEmpty ? null : numbers.reduce((a, b) => a > b ? a : b);
    final selectedSample = selected == null || selected! >= samples.length
        ? null
        : samples[selected!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Semantics(
            container: true,
            label: context.tr(
                "Session-lokaler Signalverlauf, {0} von {1} Samples, Zoom {2}-fach, {3}, Minimum {4}, Maximum {5}",
                [
                  samples.length,
                  widget.samples.length,
                  zoom,
                  widget.simulated ? 'Simulator-Quellzeit' : 'Quellzeit',
                  minimum?.toStringAsFixed(1) ?? 'unbekannt',
                  maximum?.toStringAsFixed(1) ?? 'unbekannt'
                ]),
            child: LayoutBuilder(builder: (context, constraints) {
              final size = Size(constraints.maxWidth, widget.height);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final indices = selectable;
                  if (indices.isEmpty) return;
                  final rect = _chartRect(size);
                  var nearest = indices.first;
                  var distance = double.infinity;
                  for (final index in indices) {
                    final x = _xFor(samples, index, rect);
                    final candidate = (details.localPosition.dx - x).abs();
                    if (candidate < distance) {
                      nearest = index;
                      distance = candidate;
                    }
                  }
                  setState(() => selected = nearest);
                },
                child: CustomPaint(
                  painter: _OverviewTrendPainter(
                    samples: samples,
                    gaps: widget.gaps,
                    selected: selected,
                    simulated: widget.simulated,
                    color: OipTokens.categoryColor(context, 'sensor'),
                    grid: Theme.of(context).colorScheme.outline,
                    surface: Theme.of(context).colorScheme.surface,
                    labelStyle: Theme.of(context).textTheme.bodySmall ??
                        const TextStyle(fontSize: 11),
                  ),
                ),
              );
            }),
          ),
        ),
        Row(children: [
          Expanded(
            child: Text(
              minimum == null
                  ? context.tr("Keine numerischen Samples im Sitzungsfenster")
                  : context.tr("{0}/{1} SAMPLES · MIN {2} {3} · MAX {4} {5}", [
                      samples.length,
                      widget.samples.length,
                      minimum.toStringAsFixed(1),
                      widget.unit,
                      maximum!.toStringAsFixed(1),
                      widget.unit
                    ]),
              overflow: TextOverflow.ellipsis,
              style: WorkstationTokens.mono(context, size: 10),
            ),
          ),
          IconButton(
            key: const Key('overview-chart-zoom-out'),
            tooltip: context.tr("Zeitraum verkleinern"),
            onPressed: zoom == 1 ? null : () => setZoom(zoom ~/ 2),
            icon: const Icon(Icons.zoom_out, size: 18),
          ),
          IconButton(
            key: const Key('overview-chart-zoom-in'),
            tooltip: context.tr("In verfügbares Datenfenster zoomen"),
            onPressed: widget.samples.length < 3 || zoom >= 8
                ? null
                : () => setZoom(zoom * 2),
            icon: const Icon(Icons.zoom_in, size: 18),
          ),
          IconButton(
            key: const Key('overview-chart-reset'),
            tooltip: context.tr("Zeitraum zurücksetzen"),
            onPressed: zoom == 1 ? null : () => setZoom(1),
            icon: const Icon(Icons.restart_alt, size: 18),
          ),
          IconButton(
            key: const Key('overview-sample-previous'),
            tooltip: context.tr("Vorheriges Sample"),
            onPressed: selectable.isEmpty ? null : () => selectRelative(false),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            key: const Key('overview-sample-next'),
            focusNode: sampleNextFocus,
            tooltip: context.tr("Nächstes Sample"),
            onPressed: selectable.isEmpty ? null : () => selectRelative(true),
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
        if (selectedSample != null)
          Container(
            key: const Key('overview-sample-detail'),
            padding: const EdgeInsets.all(OipTokens.s2),
            color: WorkstationTokens.well(context),
            child: Text(
              context
                  .tr("{0} {1} · {2} · {3} {4} · Tatsächlicher Empfang {5}", [
                selectedSample.display,
                selectedSample.symbol,
                known(selectedSample.quality),
                selectedSample.simulated ? 'Simulator-Quellzeit' : 'Quellzeit',
                timestamp(selectedSample.sourceMs),
                timestamp(selectedSample.receivedMs)
              ]),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

Rect _chartRect(Size size) =>
    Rect.fromLTRB(48, 10, size.width - 10, size.height - 26);

double _xFor(List<Observation> samples, int index, Rect chart) {
  final times = samples
      .where((sample) => sample.sourceMs != null)
      .map((sample) => sample.sourceMs!)
      .toList();
  final current = samples[index].sourceMs;
  if (current == null) return chart.center.dx;
  final first = times.reduce((a, b) => a < b ? a : b);
  final last = times.reduce((a, b) => a > b ? a : b);
  if (first == last) return chart.center.dx;
  return chart.left + (current - first) / (last - first) * chart.width;
}

bool crossesDocumentedGap(
    Observation previous, Observation current, List<CollectionEvent> gaps) {
  final start = previous.sourceMs;
  final end = current.sourceMs;
  if (start == null || end == null) return false;
  return gaps.any((event) =>
      event.gapStartedMs != null &&
      event.gapEndedMs != null &&
      event.gapEndedMs! >= event.gapStartedMs! &&
      start < event.gapEndedMs! &&
      end > event.gapStartedMs!);
}

class _OverviewTrendPainter extends CustomPainter {
  final List<Observation> samples;
  final List<CollectionEvent> gaps;
  final int? selected;
  final bool simulated;
  final Color color, grid, surface;
  final TextStyle labelStyle;

  const _OverviewTrendPainter({
    required this.samples,
    required this.gaps,
    required this.selected,
    required this.simulated,
    required this.color,
    required this.grid,
    required this.surface,
    required this.labelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final chart = _chartRect(size);
    final gridPaint = Paint()
      ..color = grid.withOpacity(.55)
      ..strokeWidth = .7;
    final numbers = samples
        .where((sample) => sample.number != null)
        .map((sample) => sample.number!)
        .toList();
    for (var line = 0; line < 5; line++) {
      final y = chart.top + line * chart.height / 4;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }
    if (numbers.isEmpty) {
      _label(canvas, 'KEINE SAMPLE-DATEN',
          Offset(chart.left + 8, chart.top + 8), const Size(210, 16));
      return;
    }
    final dataMin = numbers.reduce((a, b) => a < b ? a : b);
    final dataMax = numbers.reduce((a, b) => a > b ? a : b);
    final padding = (dataMax - dataMin).abs().clamp(.2, double.infinity) * .15;
    final low = dataMin - padding;
    final high = dataMax + padding;

    for (var line = 0; line < 5; line++) {
      final ratio = line / 4;
      final y = chart.top + ratio * chart.height;
      _label(canvas, (high - ratio * (high - low)).toStringAsFixed(1),
          Offset(0, y - 7), const Size(42, 14),
          align: TextAlign.right);
    }
    final timed = samples.where((sample) => sample.sourceMs != null).toList();
    if (timed.isNotEmpty) {
      _label(canvas, '${simulated ? 'SIM ' : ''}${_time(timed.first.sourceMs)}',
          Offset(chart.left, chart.bottom + 6), const Size(90, 16));
      _label(
          canvas,
          '${simulated ? 'SIM ' : ''}${_time(timed.last.sourceMs)} UTC',
          Offset(chart.right - 110, chart.bottom + 6),
          const Size(110, 16),
          align: TextAlign.right);
    }

    for (final gap in gaps) {
      if (gap.gapStartedMs == null || gap.gapEndedMs == null) continue;
      final times = samples.map((sample) => sample.sourceMs).whereType<int>();
      if (times.isEmpty) continue;
      final first = times.reduce((a, b) => a < b ? a : b);
      final last = times.reduce((a, b) => a > b ? a : b);
      if (gap.gapEndedMs! < first ||
          gap.gapStartedMs! > last ||
          first == last) {
        continue;
      }
      final left = chart.left +
          (gap.gapStartedMs!.clamp(first, last) - first) /
              (last - first) *
              chart.width;
      final right = chart.left +
          (gap.gapEndedMs!.clamp(first, last) - first) /
              (last - first) *
              chart.width;
      canvas.drawRect(
          Rect.fromLTRB(left, chart.top, right.clamp(left + 1, chart.right),
              chart.bottom),
          Paint()..color = grid.withOpacity(.18));
    }

    // The gap limit follows the cadence of the measured series. The legacy
    // demo publishes every second and keeps its own limit; a real source
    // publishes on its own cadence and would otherwise be drawn as isolated
    // points.
    final gapLimit = seriesGapLimit(samples);
    final path = Path();
    Observation? previous;
    var pen = false;
    Offset? selectedPoint;
    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index];
      final number = sample.number;
      if (number == null || sample.sourceMs == null) {
        previous = sample;
        pen = false;
        continue;
      }
      final point = Offset(
        _xFor(samples, index, chart),
        chart.bottom - (number - low) / (high - low) * chart.height,
      );
      final continuous = continuesSeries(previous, sample, gapLimit) &&
          !crossesDocumentedGap(previous!, sample, gaps);
      if (sample.quality == 'good') {
        if (!pen || !continuous) path.moveTo(point.dx, point.dy);
        if (pen && continuous) path.lineTo(point.dx, point.dy);
        canvas.drawCircle(point, 2.1, Paint()..color = color);
        pen = true;
      } else {
        pen = false;
      }
      if (selected == index) selectedPoint = point;
      previous = sample;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (selectedPoint != null) {
      canvas.drawCircle(selectedPoint, 6, Paint()..color = surface);
      canvas.drawCircle(selectedPoint, 4, Paint()..color = color);
    }
  }

  void _label(Canvas canvas, String text, Offset offset, Size size,
      {TextAlign align = TextAlign.left}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle.copyWith(fontSize: 9)),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
    )..layout(minWidth: size.width, maxWidth: size.width);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _OverviewTrendPainter old) =>
      !listEquals(samples, old.samples) ||
      !listEquals(gaps, old.gaps) ||
      selected != old.selected ||
      simulated != old.simulated ||
      color != old.color ||
      grid != old.grid ||
      surface != old.surface ||
      labelStyle != old.labelStyle;
}

String _time(int? ms) {
  if (ms == null) return 'unbekannt';
  final time = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';
}
