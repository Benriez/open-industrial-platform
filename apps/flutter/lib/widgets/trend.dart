import '../models/contracts.dart';

/// The continuity rule of a measured series under the legacy demo limit.
///
/// The legacy demo publishes every second and connects points that are at
/// most 2.5 s apart. A real source publishes on its own cadence, so the
/// limit follows the cadence the series itself showed: a point that arrives
/// later than one and a half times the median interval of the series is a
/// gap and is not connected over it.
bool continuesTrend(Observation? previous, Observation current) =>
    continuesSeries(previous, current, 2500);

/// The continuity rule of a measured series with an explicit gap limit.
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
