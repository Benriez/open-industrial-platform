import 'contracts.dart';

/// One persisted measurement that the Core stored in its own database.
///
/// A stored sample is historical by definition. The Core reports every stored
/// observation with the freshness `stale`, and the client never draws it as a
/// live value.
class HistoricalObservation {
  final String id;
  final Observation observation;
  HistoricalObservation.fromJson(Json j)
      : id = j['id'] as String,
        observation = Observation.fromJson(j['observation'] as Json);

  /// The receive time is the ordering the Core guarantees for observations.
  /// It is not aligned with the runtime clock and not inferred.
  int? get receivedMs => observation.receivedMs;
}

/// One page of the authorized persisted history.
///
/// The Core reports no total. It says whether the page was cut off and hands a
/// cursor for the continuation. `missingEvidence` carries the limits the Core
/// states for this answer; they are shown and not hidden.
class HistoryPage {
  final List<HistoricalObservation> observations;

  /// Entries of another category that this surface does not render. They are
  /// counted, never silently dropped.
  final int otherItems;
  final bool truncated;
  final String? nextCursor;
  final List<String> missingEvidence;
  final String timeSemantics;

  factory HistoryPage.fromJson(Json j) {
    final items = (j['items'] as List).cast<Json>();
    final observations = <HistoricalObservation>[];
    var other = 0;
    for (final item in items) {
      if (item['category'] == 'observation') {
        observations.add(
            HistoricalObservation.fromJson(item['record'] as Json));
      } else {
        other++;
      }
    }
    return HistoryPage._(
      observations: observations,
      otherItems: other,
      truncated: j['truncated'] as bool,
      nextCursor: j['next_cursor'] as String?,
      missingEvidence:
          ((j['missing_evidence'] as List?) ?? const []).cast<String>(),
      timeSemantics: j['time_semantics'] as String? ?? '',
    );
  }

  const HistoryPage._({
    required this.observations,
    required this.otherItems,
    required this.truncated,
    required this.nextCursor,
    required this.missingEvidence,
    required this.timeSemantics,
  });
}
