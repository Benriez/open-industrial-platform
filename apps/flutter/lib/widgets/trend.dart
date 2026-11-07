import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/contracts.dart';
import '../design_system/theme.dart';

bool continuesTrend(Observation? previous, Observation current) =>
    continuesSeries(previous, current, 2500);

/// The continuity rule of a measured series.
///
/// The legacy demo publishes every second and connects points that are at
/// most 2.5 s apart. A real source publishes on its own cadence, so the limit
/// follows the cadence the series itself showed: a point that arrives later
/// than one and a half times the median interval of the series is a gap and
/// is not connected over it.
bool continuesSeries(Observation? previous, Observation current, int gapLimit) {
  if (current.number == null || current.quality != 'good') return false;
  if (previous == null ||
      current.sourceMs == null ||
      previous.sourceMs == null ||
      previous.sourceId != current.sourceId ||
      previous.entityId != current.entityId) {
    return false;
  }
  final elapsed = current.sourceMs! - previous.sourceMs!;
  return elapsed > 0 && elapsed <= gapLimit;
}

/// The gap limit of a measured series.
///
/// The limit follows the cadence the series showed: the median interval
/// between two received points, with a tolerance of half of it. The floor is
/// the limit of the legacy demo, so the demo behaviour stays exactly as it
/// was.
int seriesGapLimit(List<Observation> samples) {
  final intervals = <int>[];
  for (var i = 1; i < samples.length; i++) {
    final previous = samples[i - 1].sourceMs;
    final current = samples[i].sourceMs;
    if (previous != null && current != null && current > previous) {
      intervals.add(current - previous);
    }
  }
  if (intervals.isEmpty) return 2500;
  intervals.sort();
  final median = intervals[intervals.length ~/ 2];
  final limit = (median * 3) ~/ 2;
  return limit > 2500 ? limit : 2500;
}

class TrendChart extends StatelessWidget {
  final List<Observation> samples;

  /// The name of the measured series. The legacy demo measures the
  /// temperature; a real source names the metric it measured.
  final String title;

  /// The unit of the measured series.
  final String unit;

  /// The unit as it is read out.
  final String semanticUnit;

  /// The caption that names the measured series.
  final String caption;

  /// Whether the gap limit follows the cadence of the measured series.
  final bool adaptiveGap;
  const TrendChart(this.samples,
      {super.key,
      this.title = 'Temperaturverlauf',
      this.unit = '°C',
      this.semanticUnit = 'Grad Celsius',
      this.caption = 'Temperatur · M-01',
      this.adaptiveGap = false});

  @override
  Widget build(BuildContext context) {
    final numbers =
        samples.where((s) => s.number != null).map((s) => s.number!).toList();
    final min =
        numbers.isEmpty ? null : numbers.reduce((a, b) => a < b ? a : b);
    final max =
        numbers.isEmpty ? null : numbers.reduce((a, b) => a > b ? a : b);
    final limit = adaptiveGap ? seriesGapLimit(samples) : 2500;
    return Semantics(
      label:
          '$title, ${samples.length} empfangene Messpunkte, Minimum ${min?.toStringAsFixed(1) ?? 'unbekannt'}, Maximum ${max?.toStringAsFixed(1) ?? 'unbekannt'} $semanticUnit',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 220,
            width: double.infinity,
            child: CustomPaint(
              painter: _TrendPainter(
                samples,
                OipTokens.categoryColor(context, 'sensor'),
                OipTokens.categoryColor(context, 'industrial'),
                Theme.of(context).colorScheme.outline,
                Theme.of(context).textTheme.bodySmall ??
                    const TextStyle(fontSize: 11),
                limit,
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  min == null
                      ? 'Warte auf Messwerte'
                      : 'Min ${min.toStringAsFixed(1)} $unit',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: OipTokens.s2),
              Expanded(
                child: Text(
                  max == null ? '—' : 'Max ${max.toStringAsFixed(1)} $unit',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: OipTokens.s2),
          Wrap(
            spacing: OipTokens.s3,
            runSpacing: OipTokens.s1,
            children: [
              Text(caption, style: Theme.of(context).textTheme.bodySmall),
              Text('${samples.length}/60 Sitzungspunkte · virtuelle Quellzeit',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<Observation> samples;
  final Color color, accent, grid;
  final TextStyle labelStyle;
  final int gapLimit;
  _TrendPainter(List<Observation> values, this.color, this.accent, this.grid,
      this.labelStyle, this.gapLimit)
      : samples = List.of(values);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 46.0, right = 8.0, top = 12.0, bottom = 28.0;
    final chart =
        Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    final gridPaint = Paint()
      ..color = grid.withOpacity(.72)
      ..strokeWidth = .7;
    final numbers =
        samples.where((s) => s.number != null).map((s) => s.number!).toList();
    if (numbers.isEmpty) {
      for (var i = 0; i < 5; i++) {
        final y = chart.top + i * chart.height / 4;
        canvas.drawLine(
            Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      }
      return;
    }
    final dataMin = numbers.reduce((a, b) => a < b ? a : b);
    final dataMax = numbers.reduce((a, b) => a > b ? a : b);
    final lo = dataMin - 2;
    final hi = dataMax + 2;

    for (var i = 0; i < 5; i++) {
      final ratio = i / 4;
      final y = chart.top + ratio * chart.height;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      _label(canvas, (hi - ratio * (hi - lo)).toStringAsFixed(0),
          Offset(0, y - 7), const Size(left - 8, 14),
          align: TextAlign.right);
    }

    for (var i = 0; i <= 6; i++) {
      final x = chart.left + i * chart.width / 6;
      canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom),
          gridPaint..color = grid.withOpacity(.34));
    }

    if (samples.isNotEmpty) {
      _label(canvas, _time(samples.first.sourceMs),
          Offset(chart.left, chart.bottom + 8), const Size(80, 16));
      const lastWidth = 80.0;
      _label(
          canvas,
          _time(samples.last.sourceMs),
          Offset(chart.right - lastWidth, chart.bottom + 8),
          const Size(lastWidth, 16),
          align: TextAlign.right);
    }

    final path = Path();
    Observation? previous;
    var pen = false;
    Offset? lastPoint;
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      if (!continuesSeries(previous, sample, gapLimit)) pen = false;
      final number = sample.number;
      if (number == null || sample.quality != 'good') {
        previous = sample;
        continue;
      }
      final point = Offset(
        samples.length < 2
            ? chart.center.dx
            : chart.left + i / (samples.length - 1) * chart.width,
        chart.bottom - (number - lo) / (hi - lo) * chart.height,
      );
      if (!pen) {
        path.moveTo(point.dx, point.dy);
        pen = true;
      } else {
        path.lineTo(point.dx, point.dy);
      }
      lastPoint = point;
      previous = sample;
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(colors: [accent, color]).createShader(chart)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (lastPoint != null) {
      canvas.drawCircle(lastPoint, 5, Paint()..color = color.withOpacity(.15));
      canvas.drawCircle(lastPoint, 3, Paint()..color = color);
    }
  }

  void _label(Canvas canvas, String text, Offset offset, Size size,
      {TextAlign align = TextAlign.left}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle.copyWith(fontSize: 10)),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
    )..layout(minWidth: size.width, maxWidth: size.width);
    painter.paint(canvas, offset);
  }

  static String _time(int? ms) {
    if (ms == null) return 'unbekannt';
    final time = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      color != old.color ||
      accent != old.accent ||
      grid != old.grid ||
      labelStyle != old.labelStyle ||
      gapLimit != old.gapLimit ||
      !listEquals(samples, old.samples);
}
