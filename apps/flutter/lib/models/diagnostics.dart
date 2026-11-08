import 'contracts.dart';

/// One documented gap of the authorized evidence.
///
/// The Core documents both markers of a gap. The difference between them is
/// not a measured outage and a zero length is not continuity.
class DiagnosticGap {
  final String id, source, origin, reason;
  final int documentedStartMs, documentedEndMs;
  DiagnosticGap.fromJson(Json j)
      : id = j['id'] as String,
        source = j['source'] as String,
        origin = j['origin'] as String,
        reason = j['reason'] as String,
        documentedStartMs = j['documented_start_ms'] as int,
        documentedEndMs = j['documented_end_ms'] as int;
  int? get durationMs =>
      documentedEndMs > documentedStartMs ? documentedEndMs - documentedStartMs : null;
}

/// The health of a source at one point of the authorized history.
class DiagnosticHealthState {
  final String reachability, connection, service, freshness, validity;
  DiagnosticHealthState.fromJson(Json j)
      : reachability = j['reachability'] as String,
        connection = j['connection'] as String,
        service = j['service'] as String,
        freshness = j['freshness'] as String,
        validity = j['validity'] as String;
}

/// One health transition of the authorized evidence.
///
/// Historical health never overrides the fresh live state of the runtime.
class DiagnosticHealthTransition {
  final String id, source, provenance;
  final int atMs;
  final DiagnosticHealthState? previous, current;
  DiagnosticHealthTransition.fromJson(Json j)
      : id = j['id'] as String,
        source = j['source'] as String,
        provenance = j['provenance'] as String,
        atMs = j['at_ms'] as int,
        previous = j['previous'] is Json
            ? DiagnosticHealthState.fromJson(j['previous'] as Json)
            : null,
        current = j['current'] is Json
            ? DiagnosticHealthState.fromJson(j['current'] as Json)
            : null;
}

/// One page of the authorized persisted evidence.
///
/// The Core reports no total. It says whether the page was cut off and hands
/// a cursor for the continuation, and it states the limits of the answer in
/// `missingEvidence` and `timeSemantics`.
class DiagnosticPage {
  final List<DiagnosticGap> gaps;
  final List<DiagnosticHealthTransition> transitions;
  final bool truncated;
  final String? nextCursor;
  final List<String> missingEvidence;
  final String timeSemantics;

  factory DiagnosticPage.fromJson(Json j) {
    final gaps = <DiagnosticGap>[];
    final transitions = <DiagnosticHealthTransition>[];
    for (final item in (j['items'] as List).cast<Json>()) {
      final record = item['record'];
      if (record is! Json) continue;
      switch (item['category']) {
        case 'gap':
          gaps.add(DiagnosticGap.fromJson(record));
        case 'health':
          transitions.add(DiagnosticHealthTransition.fromJson(record));
      }
    }
    return DiagnosticPage._(
      gaps: gaps,
      transitions: transitions,
      truncated: j['truncated'] as bool,
      nextCursor: j['next_cursor'] as String?,
      missingEvidence:
          ((j['missing_evidence'] as List?) ?? const []).cast<String>(),
      timeSemantics: j['time_semantics'] as String? ?? '',
    );
  }

  /// Continue the same authorized query without duplicating stable Core IDs.
  DiagnosticPage followedBy(DiagnosticPage page) => DiagnosticPage._(
        gaps: {
          for (final gap in [...gaps, ...page.gaps]) gap.id: gap
        }.values.toList(),
        transitions: {
          for (final item in [...transitions, ...page.transitions])
            item.id: item
        }.values.toList(),
        truncated: page.truncated,
        nextCursor: page.nextCursor,
        missingEvidence: {...missingEvidence, ...page.missingEvidence}.toList(),
        timeSemantics: page.timeSemantics,
      );

  const DiagnosticPage._({
    required this.gaps,
    required this.transitions,
    required this.truncated,
    required this.nextCursor,
    required this.missingEvidence,
    required this.timeSemantics,
  });
}

/// The collection events of the session and the state of the persisted
/// diagnosis history.
///
/// The state is the answer of the Core, not an assumption of the client.
class CollectionEvents {
  final List<CollectionEvent> events;
  final String diagnosisHistoryStatus;
  final bool replaySupported, resyncRequired;
  CollectionEvents(this.events, this.diagnosisHistoryStatus,
      {this.replaySupported = false, this.resyncRequired = false});
}
