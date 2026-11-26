import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../models/contracts.dart';
import '../../widgets/device_kind.dart';

/// Stable presentation identity for the legacy Link DTO, which has no link ID.
/// The ordinal only disambiguates duplicate endpoint/transport tuples.
class NetworkEdge {
  final NetworkLink link;
  final int ordinal;
  final bool recordedLan;

  const NetworkEdge(this.link, this.ordinal) : recordedLan = false;
  NetworkEdge.lan(String router, String device)
      : link = NetworkLink.recordedLan(router, device),
        ordinal = 0,
        recordedLan = true;

  String get id => '${link.from}\n${link.to}\n${link.transport}\n$ordinal';
  String get shortLabel => '${link.from} → ${link.to}';
  String get signature => '$id\n${link.status}\n${link.latency}\n'
      '${link.loss}\n${link.simulated}';
}

Set<String> networkLinkedDeviceIds(Iterable<NetworkEdge> edges) => {
      for (final edge in edges) ...[edge.link.from, edge.link.to],
    };

List<NetworkEdge> networkDeviceEdges(
        String deviceId, Iterable<NetworkEdge> edges) =>
    edges
        .where((edge) => edge.link.from == deviceId || edge.link.to == deviceId)
        .toList();

enum NetworkRelationFilter { all, known, unknown }

enum NetworkDeviceSort { name, id, kind, status, relations }

String networkRelationFilterLabel(NetworkRelationFilter value) =>
    switch (value) {
      NetworkRelationFilter.all => 'Alle registrierten Geräte',
      NetworkRelationFilter.known => 'Bekannte Topologie-Endpunkte',
      NetworkRelationFilter.unknown => 'Relation unbekannt',
    };

String networkDeviceSortLabel(NetworkDeviceSort value) => switch (value) {
      NetworkDeviceSort.name => 'Name',
      NetworkDeviceSort.id => 'Device-ID',
      NetworkDeviceSort.kind => 'Gerätetyp',
      NetworkDeviceSort.status => 'Gemeldeter Status',
      NetworkDeviceSort.relations => 'Anzahl Relationen',
    };

List<Device> networkExplorerDevices(
  Snapshot snapshot,
  List<NetworkEdge> edges, {
  required String query,
  required String? kind,
  required String? status,
  required NetworkRelationFilter relation,
  required NetworkDeviceSort sort,
  required bool transportLive,
}) {
  final linked = networkLinkedDeviceIds(edges);
  final devices = snapshot.devices.where((device) {
    if (!networkDeviceMatches(device, query, kind, status, transportLive)) {
      return false;
    }
    return switch (relation) {
      NetworkRelationFilter.all => true,
      NetworkRelationFilter.known => linked.contains(device.id),
      NetworkRelationFilter.unknown => !linked.contains(device.id),
    };
  }).toList();
  int compareText(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());
  devices.sort((a, b) {
    if (relation == NetworkRelationFilter.all &&
        linked.contains(a.id) != linked.contains(b.id)) {
      return linked.contains(a.id) ? -1 : 1;
    }
    final result = switch (sort) {
      NetworkDeviceSort.name => compareText(a.name, b.name),
      NetworkDeviceSort.id => compareText(a.id, b.id),
      NetworkDeviceSort.kind => compareText(a.kind, b.kind),
      NetworkDeviceSort.status => compareText(
          transportLive ? a.health.reachability : 'stale',
          transportLive ? b.health.reachability : 'stale'),
      NetworkDeviceSort.relations => networkDeviceEdges(b.id, edges).length -
          networkDeviceEdges(a.id, edges).length,
    };
    return result != 0 ? result : compareText(a.id, b.id);
  });
  return devices;
}

List<NetworkEdge> networkEdges(Snapshot snapshot) {
  final counts = <String, int>{};
  final edges = snapshot.topology.map((link) {
    final base = '${link.from}\n${link.to}\n${link.transport}';
    final ordinal = counts[base] ?? 0;
    counts[base] = ordinal + 1;
    return NetworkEdge(link, ordinal);
  }).toList()
    ..sort((a, b) {
      final left = '${a.link.from}\n${a.link.to}\n${a.link.transport}';
      final right = '${b.link.from}\n${b.link.to}\n${b.link.transport}';
      final byTuple = left.compareTo(right);
      return byTuple != 0 ? byTuple : a.ordinal.compareTo(b.ordinal);
    });
  return edges;
}

String networkEdgeKind(NetworkLink link) {
  final transport = link.transport.toLowerCase();
  if (transport.contains('vpn') ||
      transport.contains('wireguard') ||
      transport.contains('tailnet') ||
      transport.contains('tailscale')) {
    return 'Logischer VPN-/Tunnelpfad';
  }
  return 'Logischer Netzwerkpfad';
}

String networkLinkRtt(NetworkLink link) {
  final value = link.latency;
  if (value == null || !value.isFinite) return 'Nicht gemessen';
  return '${value.toStringAsFixed(1)} ms${link.simulated ? ' · Fixture' : ''}';
}

String networkLinkLoss(NetworkLink link) {
  final value = link.loss;
  if (value == null || !value.isFinite) return 'Nicht verfügbar';
  return '${value.toStringAsFixed(1)} %${link.simulated ? ' · Fixture' : ''}';
}

/// Device kind comes directly from the registry DTO. No name-based guessing.
///
/// The **word** of the type and its icon have one owner
/// (`widgets/device_kind.dart`): the Core paints the type of a device as the
/// identifier of its own enum, and the surface names it.
IconData networkKindIcon(String kind) => deviceKindIcon(kind);

/// The category of a device in the Network workspace.
///
/// The word of the type comes from the vocabulary of the Core; a type that
/// the client does not know is named as unknown and carries the identifier
/// of the Core with it.
String networkDeviceCategory(String kind) {
  final label = deviceKindLabel(kind);
  return label == null
      ? 'Unbekannter Gerätetyp · Registry-Angabe: $kind'
      : '$label · Registry-Angabe';
}

bool networkDeviceMatches(Device device, String query, String? kind,
    String? status, bool transportLive) {
  final normalized = query.trim().toLowerCase();
  final text = '${device.name} ${device.id} ${device.location} '
          '${device.kind} ${device.sourceId ?? ''}'
      .toLowerCase();
  if (normalized.isNotEmpty && !text.contains(normalized)) return false;
  if (kind != null && device.kind != kind) return false;
  if (status != null) {
    final actual = transportLive ? device.health.reachability : 'stale';
    if (status == 'attention') {
      final healthy = actual == 'reachable' &&
          device.health.service != 'alarm' &&
          device.health.service != 'critical';
      if (healthy) return false;
    } else if (actual != status) {
      return false;
    }
  }
  return true;
}

bool networkEdgeMatches(NetworkEdge edge, List<Device> devices, String query,
    String? transport, String? status) {
  final link = edge.link;
  if (transport != null && link.transport != transport) return false;
  if (status != null && link.status != status) return false;
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  String name(String id) =>
      devices
          .where((device) => device.id == id)
          .map((device) => device.name)
          .firstOrNull ??
      id;
  return '${name(link.from)} ${name(link.to)} ${link.from} ${link.to} '
          '${link.transport} ${link.status}'
      .toLowerCase()
      .contains(normalized);
}

/// Distance used by the graph's edge hit test. No backend semantics involved.
double networkDistanceToSegment(Offset point, Offset start, Offset end) {
  final delta = end - start;
  final lengthSquared = delta.dx * delta.dx + delta.dy * delta.dy;
  if (lengthSquared == 0) return (point - start).distance;
  final projection =
      ((point - start).dx * delta.dx + (point - start).dy * delta.dy) /
          lengthSquared;
  final t = projection.clamp(0.0, 1.0);
  return (point - (start + delta * t)).distance;
}

double networkFitScale(Size viewport, Size content,
    {double padding = 24, double min = .35, double max = 1}) {
  if (viewport.width <= 0 ||
      viewport.height <= 0 ||
      content.width <= 0 ||
      content.height <= 0) {
    return 1;
  }
  final available = Size(math.max(1, viewport.width - padding),
      math.max(1, viewport.height - padding));
  final scale = math.min(
      available.width / content.width, available.height / content.height);
  return scale.clamp(min, max).toDouble();
}

/// Maps content coordinates into the viewport with a centred, uniform scale.
/// The content rectangle already includes node extents and layout padding.
Matrix4 networkFitTransform(Rect content, Size viewport,
    {double padding = 24, double min = .35, double max = 1}) {
  final scale = networkFitScale(viewport, content.size,
      padding: padding, min: min, max: max);
  final scaled = Size(content.width * scale, content.height * scale);
  final x = scaled.width > viewport.width - padding
      ? padding / 2 - content.left * scale
      : viewport.width / 2 - content.center.dx * scale;
  final y = scaled.height > viewport.height - padding
      ? padding / 2 - content.top * scale
      : viewport.height / 2 - content.center.dy * scale;
  final translation = Offset(x, y);
  return Matrix4.identity()
    ..scale(scale)
    ..setTranslationRaw(translation.dx, translation.dy, 0);
}

Rect networkTransformedRect(Rect rect, Matrix4 transform) {
  final scale = transform.getMaxScaleOnAxis();
  final translation = transform.getTranslation();
  return Rect.fromLTWH(
    rect.left * scale + translation.x,
    rect.top * scale + translation.y,
    rect.width * scale,
    rect.height * scale,
  );
}
