import 'dart:math' as math;

import '../../models/contracts.dart';
import '../../models/infrastructure.dart';

/// Session-local presentation identity for a delivered collection record.
/// No server event UUID is invented: [recordId] exists only when the API
/// supplies both its source-local sequence and source ID.
class DiagnosticEvent {
  final CollectionEvent event;
  final String key;
  final String? recordId;
  final int deliveryCount;
  final bool identityConflict;

  const DiagnosticEvent({
    required this.event,
    required this.key,
    required this.recordId,
    this.deliveryCount = 1,
    this.identityConflict = false,
  });

  String? get atMs => event.atMs?.toString();
  String? get sourceId => event.sourceId;
  int? get timestampMs => event.atMs;
  bool get hasTimestamp => event.atMs != null;
  bool get hasGapBounds =>
      event.gapStartedMs != null || event.gapEndedMs != null;
  bool get hasCompleteGap =>
      event.gapStartedMs != null && event.gapEndedMs != null;
  bool get gapIsInverted =>
      hasCompleteGap && event.gapEndedMs! < event.gapStartedMs!;
  bool get isDataLoss => event.kind == 'DataLoss';
  String get sourceLabel => event.sourceId ?? 'Quelle nicht geliefert';
}

String diagnosticEventTitle(String kind) => switch (kind) {
      'ConnectionLost' => 'Verbindung verloren',
      'Reconnected' => 'Verbindung wiederhergestellt',
      'SubscriptionError' => 'Subscription-Fehler',
      'DataLoss' => 'Datenverlust gemeldet',
      _ => 'Unbekanntes Collection-Ereignis',
    };

String diagnosticEventCategory(String kind) => switch (kind) {
      'ConnectionLost' || 'Reconnected' => 'Connection State',
      'SubscriptionError' => 'Collection Error',
      'DataLoss' => 'Data Gap',
      _ => 'Unknown',
    };

String _fingerprint(CollectionEvent event) => [
      event.sourceId ?? '-',
      event.sequence?.toString() ?? '-',
      event.atMs?.toString() ?? '-',
      event.kind,
      event.reason ?? '-',
      event.gapStartedMs?.toString() ?? '-',
      event.gapEndedMs?.toString() ?? '-',
      event.dropped?.toString() ?? '-',
    ].join('|');

/// Creates deterministic, duplicate-safe session identities. Exact repetitions
/// of a source+sequence record are one fact with multiple deliveries. Fallback
/// events have no authoritative identity and therefore remain separate even if
/// their fields are identical.
List<DiagnosticEvent> diagnosticEventsFromApi(List<CollectionEvent> delivered) {
  final result = <DiagnosticEvent>[];
  final byRecord = <String, int>{};
  final fallbackOccurrences = <String, int>{};
  final conflictOccurrences = <String, int>{};
  for (final event in delivered) {
    final fingerprint = _fingerprint(event);
    final source = event.sourceId;
    final sequence = event.sequence;
    if (source != null && sequence != null) {
      final recordId = '$source#$sequence';
      final existing = byRecord[recordId];
      if (existing != null &&
          _fingerprint(result[existing].event) == fingerprint) {
        final previous = result[existing];
        result[existing] = DiagnosticEvent(
          event: previous.event,
          key: previous.key,
          recordId: previous.recordId,
          deliveryCount: previous.deliveryCount + 1,
        );
        continue;
      }
      final conflict = existing != null;
      final occurrence =
          conflictOccurrences.update(recordId, (n) => n + 1, ifAbsent: () => 0);
      final key = conflict ? '$recordId~conflict-$occurrence' : recordId;
      byRecord.putIfAbsent(recordId, () => result.length);
      result.add(DiagnosticEvent(
        event: event,
        key: key,
        recordId: recordId,
        identityConflict: conflict,
      ));
    } else {
      final occurrence = fallbackOccurrences.update(fingerprint, (n) => n + 1,
          ifAbsent: () => 0);
      result.add(DiagnosticEvent(
        event: event,
        key: 'local|$fingerprint|$occurrence',
        recordId: null,
      ));
    }
  }
  return result;
}

enum DiagnosticEventSort { newest, oldest, source, type }

enum DiagnosticEventGrouping { none, organization, infrastructure, site, source, type }

enum DiagnosticTimeWindow { all, oneMinute, fifteenMinutes, oneHour }

String diagnosticSortLabel(DiagnosticEventSort value) => switch (value) {
      DiagnosticEventSort.newest => 'Neueste zuerst',
      DiagnosticEventSort.oldest => 'Älteste zuerst',
      DiagnosticEventSort.source => 'Source, dann Zeit',
      DiagnosticEventSort.type => 'Typ, dann Zeit',
    };

String diagnosticGroupingLabel(DiagnosticEventGrouping value) =>
    switch (value) {
      DiagnosticEventGrouping.none => 'Keine',
      DiagnosticEventGrouping.organization => 'Organization',
      DiagnosticEventGrouping.infrastructure => 'Infrastructure',
      DiagnosticEventGrouping.site => 'Site',
      DiagnosticEventGrouping.source => 'Source',
      DiagnosticEventGrouping.type => 'Ereignistyp',
    };

String diagnosticTimeWindowLabel(DiagnosticTimeWindow value) => switch (value) {
      DiagnosticTimeWindow.all => 'Gesamtes geladenes Fenster',
      DiagnosticTimeWindow.oneMinute => 'Letzte Minute im Datenfenster',
      DiagnosticTimeWindow.fifteenMinutes => 'Letzte 15 min im Datenfenster',
      DiagnosticTimeWindow.oneHour => 'Letzte Stunde im Datenfenster',
    };

int? _windowDuration(DiagnosticTimeWindow value) => switch (value) {
      DiagnosticTimeWindow.all => null,
      DiagnosticTimeWindow.oneMinute => 60 * 1000,
      DiagnosticTimeWindow.fifteenMinutes => 15 * 60 * 1000,
      DiagnosticTimeWindow.oneHour => 60 * 60 * 1000,
    };

List<DiagnosticEvent> filterDiagnosticEvents(
  List<DiagnosticEvent> input, {
  String query = '',
  String? source,
  String? type,
  DiagnosticTimeWindow window = DiagnosticTimeWindow.all,
  DiagnosticEventSort sort = DiagnosticEventSort.newest,
  InfrastructureContext? infrastructure,
  String? organization,
  String? infrastructureId,
  String? site,
}) {
  final normalized = query.trim().toLowerCase();
  final timestamps = input.map((item) => item.timestampMs).whereType<int>();
  final latest = timestamps.isEmpty ? null : timestamps.reduce(math.max);
  final duration = _windowDuration(window);
  final filtered = input.where((item) {
    final event = item.event;
    if (source != null && event.sourceId != source) return false;
    if (type != null && event.kind != type) return false;
    if (organization != null || infrastructureId != null || site != null) {
      final placement = infrastructure?.sourcePlacement(event.sourceId);
      if (placement == null) return false;
      if (organization != null && placement.organizationId != organization) {
        return false;
      }
      if (infrastructureId != null &&
          placement.infrastructureId != infrastructureId) {
        return false;
      }
      if (site != null && placement.siteId != site) return false;
    }
    if (duration != null &&
        (item.timestampMs == null ||
            latest == null ||
            item.timestampMs! < latest - duration)) {
      return false;
    }
    if (normalized.isEmpty) return true;
    return [
      diagnosticEventTitle(event.kind),
      item.recordId ?? '',
      event.kind,
      event.sourceId ?? '',
      event.sequence?.toString() ?? '',
      event.atMs?.toString() ?? '',
      event.reason ?? '',
      event.dropped?.toString() ?? '',
    ].any((value) => value.toLowerCase().contains(normalized));
  }).toList();
  filtered.sort((a, b) {
    final primary = switch (sort) {
      DiagnosticEventSort.newest =>
        (b.timestampMs ?? -1).compareTo(a.timestampMs ?? -1),
      DiagnosticEventSort.oldest => (a.timestampMs ?? 253402300799999)
          .compareTo(b.timestampMs ?? 253402300799999),
      DiagnosticEventSort.source => a.sourceLabel.compareTo(b.sourceLabel),
      DiagnosticEventSort.type => a.event.kind.compareTo(b.event.kind),
    };
    if (primary != 0) return primary;
    if (sort == DiagnosticEventSort.source ||
        sort == DiagnosticEventSort.type) {
      final time = (b.timestampMs ?? -1).compareTo(a.timestampMs ?? -1);
      if (time != 0) return time;
    }
    return a.key.compareTo(b.key);
  });
  return filtered;
}

String diagnosticEventGroup(
  DiagnosticEvent item,
  DiagnosticEventGrouping grouping, [
  InfrastructureContext? infrastructure,
]) {
  final placement = infrastructure?.sourcePlacement(item.event.sourceId);
  return switch (grouping) {
    DiagnosticEventGrouping.none => '',
    DiagnosticEventGrouping.organization =>
      'ORGANIZATION · ${placement == null ? 'nicht geliefert' : infrastructure!.hierarchy.organizationName(placement.organizationId)}',
    DiagnosticEventGrouping.infrastructure =>
      'INFRASTRUCTURE · ${placement == null ? 'nicht geliefert' : infrastructure!.hierarchy.infrastructureName(placement.infrastructureId)}',
    DiagnosticEventGrouping.site =>
      'SITE · ${placement == null ? 'nicht geliefert' : infrastructure!.hierarchy.siteName(placement.siteId)}',
    DiagnosticEventGrouping.source => 'SOURCE · ${item.sourceLabel}',
    DiagnosticEventGrouping.type =>
      'TYP · ${diagnosticEventTitle(item.event.kind)}',
  };
}

/// Immutable timeline viewport. Padding around a single timestamp is display
/// geometry only and never creates an observation or extends the data window.
class DiagnosticsTimelineRange {
  final int dataStartMs, dataEndMs;
  final int startMs, endMs;
  final double zoom;
  final int panMs;

  const DiagnosticsTimelineRange({
    required this.dataStartMs,
    required this.dataEndMs,
    required this.startMs,
    required this.endMs,
    required this.zoom,
    required this.panMs,
  });

  int get spanMs => math.max(1, endMs - startMs);
  bool contains(int atMs) => atMs >= startMs && atMs <= endMs;

  DiagnosticsTimelineRange copyWith({int? startMs, int? endMs}) =>
      DiagnosticsTimelineRange(
        dataStartMs: dataStartMs,
        dataEndMs: dataEndMs,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        zoom: zoom,
        panMs: panMs,
      );
}

DiagnosticsTimelineRange diagnosticsTimelineRange(
  Iterable<DiagnosticEvent> events, {
  double zoom = 1,
  int panMs = 0,
}) {
  final stamps =
      events.map((item) => item.timestampMs).whereType<int>().toList();
  if (stamps.isEmpty) {
    return DiagnosticsTimelineRange(
      dataStartMs: 0,
      dataEndMs: 0,
      startMs: 0,
      endMs: 1,
      zoom: zoom,
      panMs: panMs,
    );
  }
  final first = stamps.reduce(math.min);
  final last = stamps.reduce(math.max);
  final padding =
      first == last ? 1000 : math.max(1, ((last - first) * .04).round());
  final baseStart = first - padding;
  final baseEnd = last + padding;
  final baseSpan = baseEnd - baseStart;
  final effectiveZoom = zoom.clamp(1.0, 64.0);
  final visibleSpan = math.max(1, (baseSpan / effectiveZoom).round());
  final maximumPan = math.max(0, (baseSpan - visibleSpan) ~/ 2);
  final effectivePan = panMs.clamp(-maximumPan, maximumPan);
  final baseCenter = (baseStart + baseEnd) ~/ 2;
  final center = baseCenter + effectivePan;
  var start = center - visibleSpan ~/ 2;
  start = start.clamp(baseStart, math.max(baseStart, baseEnd - visibleSpan));
  return DiagnosticsTimelineRange(
    dataStartMs: first,
    dataEndMs: last,
    startMs: start,
    endMs: start + visibleSpan,
    zoom: effectiveZoom,
    panMs: effectivePan,
  );
}

/// Groups only visually overlapping markers in one lane. Every member remains
/// selectable through the group disclosure; count and actual time bounds stay
/// attached to the group.
class DiagnosticTimelineCluster {
  final List<DiagnosticEvent> events;
  final double leftPx;
  const DiagnosticTimelineCluster(this.events, this.leftPx);
  int? get firstMs => events.first.timestampMs;
  int? get lastMs => events.last.timestampMs;
}

List<DiagnosticTimelineCluster> diagnosticTimelineClusters(
  List<DiagnosticEvent> laneEvents,
  DiagnosticsTimelineRange range,
  double widthPx,
) {
  final visible = laneEvents
      .where((item) =>
          item.timestampMs != null && range.contains(item.timestampMs!))
      .toList()
    ..sort((a, b) {
      final time = a.timestampMs!.compareTo(b.timestampMs!);
      return time == 0 ? a.key.compareTo(b.key) : time;
    });
  if (visible.isEmpty || widthPx <= 0) return const [];
  final usable = math.max(1.0, widthPx - 48);
  double x(DiagnosticEvent item) =>
      (item.timestampMs! - range.startMs) / range.spanMs * usable;
  final clusters = <DiagnosticTimelineCluster>[];
  var members = <DiagnosticEvent>[visible.first];
  var left = x(visible.first);
  for (final item in visible.skip(1)) {
    final nextX = x(item);
    if (nextX - left < 52) {
      members.add(item);
    } else {
      clusters.add(DiagnosticTimelineCluster(List.unmodifiable(members), left));
      members = [item];
      left = nextX;
    }
  }
  clusters.add(DiagnosticTimelineCluster(List.unmodifiable(members), left));
  return clusters;
}
