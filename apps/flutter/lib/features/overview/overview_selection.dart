import '../../models/contracts.dart';

enum OverviewSelectionKind { none, source, device, event }

/// Session-local workstation selection. IDs come only from authorized v1 DTOs.
class OverviewSelection {
  final OverviewSelectionKind kind;
  final String? sourceId, deviceId, eventKey;
  const OverviewSelection._(
      this.kind, this.sourceId, this.deviceId, this.eventKey);
  const OverviewSelection.none()
      : this._(OverviewSelectionKind.none, null, null, null);
  const OverviewSelection.source(String id)
      : this._(OverviewSelectionKind.source, id, null, null);
  const OverviewSelection.device(String? source, String id)
      : this._(OverviewSelectionKind.device, source, id, null);
  const OverviewSelection.event(String? source, String key)
      : this._(OverviewSelectionKind.event, source, null, key);

  bool get hasEntity => kind != OverviewSelectionKind.none;
}

String overviewEventKey(CollectionEvent event) =>
    '${event.id ?? '${event.sourceId ?? 'unknown'}#${event.sequence ?? 'unsequenced'}'}'
    '|${event.kind}|${event.atMs ?? 'unknown'}'
    '|${event.gapStartedMs ?? 'unknown'}|${event.gapEndedMs ?? 'unknown'}';

String overviewEventIdentity(CollectionEvent event) =>
    event.id ??
    (event.sourceId != null && event.sequence != null
        ? '${event.sourceId}#${event.sequence}'
        : 'Nicht geliefert');

List<Observation> overviewSignalsFor(
  Snapshot snapshot, {
  String? sourceId,
  String? deviceId,
}) =>
    snapshot.metrics
        .where((signal) =>
            (sourceId == null || signal.sourceId == sourceId) &&
            (deviceId == null || signal.entityId == deviceId))
        .toList();

Observation? preferredOverviewSignal(Snapshot snapshot,
    {String? sourceId, String? deviceId}) {
  final signals =
      overviewSignalsFor(snapshot, sourceId: sourceId, deviceId: deviceId);
  if (signals.isEmpty) return null;
  return signals
          .where((signal) =>
              signal.metricId == 'temperature' &&
              signal.number != null &&
              signal.sourceMs != null)
          .firstOrNull ??
      signals
          .where((signal) => signal.number != null && signal.sourceMs != null)
          .firstOrNull ??
      signals.first;
}
