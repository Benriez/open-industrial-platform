import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/widgets/components.dart';
import 'package:oip_dashboard/widgets/trend.dart';
import 'support.dart';

void main() {
  Observation at(int source, {Object? value = 60.0, String quality = 'good'}) {
    final json = observation(value: value);
    (json['timestamps'] as Json)['source'] = source;
    json['quality'] = quality;
    return Observation.fromJson(json);
  }

  test(
      'Trend connects only adjacent, ordered, good samples within the gap limit',
      () {
    final first = at(1000);
    expect(continuesTrend(null, first), isFalse);
    expect(continuesTrend(first, at(3500)), isTrue);
    expect(continuesTrend(first, at(3501)), isFalse);
    expect(continuesTrend(first, at(1000)), isFalse);
    expect(continuesTrend(first, at(900)), isFalse);
    expect(continuesTrend(first, at(2000, quality: 'bad')), isFalse);
    expect(continuesTrend(first, at(2000, value: null)), isFalse);
  });

  test('The measured series of a real cadence is not broken by the demo limit',
      () {
    // A real source publishes every 30 s. The legacy demo limit of 2.5 s
    // would break the line at every point.
    final samples = [
      at(1700000000000, value: 1.0),
      at(1700000030000, value: 31.0),
    ];
    expect(seriesGapLimit(samples), 45000);
    expect(
        continuesSeries(samples.first, samples.last, seriesGapLimit(samples)),
        isTrue);
    // The legacy rule keeps its own limit.
    expect(continuesTrend(samples.first, samples.last), isFalse);
  });

  test('Collection events preserve actual timestamp, reason and gap', () {
    final event = CollectionEvent.fromJson({
      'Reconnected': {
        'at': 2000,
        'gap': {'started_at': 1000, 'ended_at': 3500, 'reason': 'test'}
      }
    });
    expect(event.kind, 'Reconnected');
    expect(event.atMs, 2000);
    expect(event.gapMs, 2500);
    expect(event.reason, isNull);
  });

  test('Status labels and malformed metric values remain explicit', () {
    final malformed = observation();
    malformed['value'] = <String, dynamic>{};
    expect(Observation.fromJson(malformed).display, 'Ungültiger Wert');
    expect(known('unreachable'), 'Nicht erreichbar');
    expect(known('unknown'), 'Unbekannt');
  });
}
