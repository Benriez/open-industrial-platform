import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import 'network_model.dart';
import '../../widgets/device_kind.dart';

/// Geometry for the network view. Registered devices remain visible even when
/// no links were delivered; only actual snapshot links create edges. No edge
/// is inferred from a name, location, transport annotation or device type.
class TopologyLayout {
  static const nodeWidth = 180.0;
  static const nodeHeight = 64.0;
  static const rowGap = 18.0;
  static const layerGap = 60.0;
  static const padding = 28.0;
  static const componentGap = 40.0;

  final List<Device> devices;
  final List<NetworkEdge> edges;
  final Map<String, Offset> positions;
  final Size size;
  final String signature;

  const TopologyLayout({
    required this.devices,
    required this.edges,
    required this.positions,
    required this.size,
    required this.signature,
  });

  factory TopologyLayout.build(
      List<Device> input, List<NetworkEdge> inputEdges) {
    final devices = [...input]..sort((a, b) => a.id.compareTo(b.id));
    final ids = devices.map((device) => device.id).toSet();
    final edges = inputEdges
        .where((edge) =>
            ids.contains(edge.link.from) && ids.contains(edge.link.to))
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final adjacency = <String, Set<String>>{
      for (final id in ids) id: <String>{}
    };
    for (final edge in edges) {
      adjacency[edge.link.from]!.add(edge.link.to);
      adjacency[edge.link.to]!.add(edge.link.from);
    }

    // Connected components are based solely on delivered logical links.
    final components = <List<String>>[];
    final remaining = devices.map((device) => device.id).toSet();
    while (remaining.isNotEmpty) {
      final first = remaining.reduce((a, b) => a.compareTo(b) < 0 ? a : b);
      final component = <String>[];
      final queue = <String>[first];
      remaining.remove(first);
      while (queue.isNotEmpty) {
        final id = queue.removeAt(0);
        component.add(id);
        final neighbors = adjacency[id]!.toList()..sort();
        for (final neighbor in neighbors) {
          if (remaining.remove(neighbor)) queue.add(neighbor);
        }
      }
      component.sort();
      components.add(component);
    }
    components.sort((a, b) {
      final bySize = b.length.compareTo(a.length);
      return bySize != 0 ? bySize : a.first.compareTo(b.first);
    });

    final positions = <String, Offset>{};
    var componentTop = 0.0;
    var canvasWidth = 320.0;
    for (final component in components) {
      final componentEdges =
          edges.where((edge) => component.contains(edge.link.from)).toList();
      final ranks = _directedRanks(component, componentEdges);
      final maxRank = ranks.values.fold(0, math.max);
      final byRank = <int, List<String>>{};
      for (final id in component) {
        byRank.putIfAbsent(ranks[id]!, () => <String>[]).add(id);
      }
      for (final rank in byRank.values) {
        rank.sort();
      }

      final local = <String, Offset>{};
      for (var rank = 0; rank <= maxRank; rank++) {
        final layer = byRank[rank] ?? const <String>[];
        for (var row = 0; row < layer.length; row++) {
          local[layer[row]] = Offset(
            padding + rank * (nodeWidth + layerGap),
            padding + row * (nodeHeight + rowGap),
          );
        }
      }

      // Centre single-node layers against their actual neighbours. This is a
      // deterministic optical alignment, not an additional relationship.
      for (var rank = 0; rank <= maxRank; rank++) {
        final layer = byRank[rank] ?? const <String>[];
        if (layer.length != 1) continue;
        final id = layer.single;
        final relatedCentres = <double>[];
        for (final edge in componentEdges) {
          final other = edge.link.from == id
              ? edge.link.to
              : edge.link.to == id
                  ? edge.link.from
                  : null;
          if (other == null || local[other] == null) continue;
          final otherRank = ranks[other]!;
          if ((rank == 0 && otherRank > rank) ||
              (rank == maxRank && otherRank < rank)) {
            relatedCentres.add(local[other]!.dy + nodeHeight / 2);
          }
        }
        if (relatedCentres.isNotEmpty) {
          final centre =
              relatedCentres.reduce((a, b) => a + b) / relatedCentres.length;
          local[id] = Offset(local[id]!.dx, centre - nodeHeight / 2);
        }
      }

      var componentBottom = padding + nodeHeight;
      for (final position in local.values) {
        componentBottom = math.max(componentBottom, position.dy + nodeHeight);
      }
      for (final entry in local.entries) {
        positions[entry.key] = entry.value + Offset(0, componentTop);
      }
      final componentWidth =
          padding * 2 + (maxRank + 1) * nodeWidth + maxRank * layerGap;
      canvasWidth = math.max(canvasWidth, componentWidth);
      componentTop += componentBottom + padding + componentGap;
    }

    final canvasHeight = components.isEmpty
        ? 180.0
        : math.max(180.0, componentTop - componentGap);
    final size = Size(canvasWidth, canvasHeight);
    final nodeSignature = devices
        .map((device) =>
            '${device.id}:${positions[device.id]?.dx},${positions[device.id]?.dy}')
        .join('|');
    final edgeSignature = edges.map((edge) => edge.id).join('|');
    final signature =
        '$nodeSignature|${size.width}x${size.height}|$edgeSignature';
    return TopologyLayout(
      devices: devices,
      edges: edges,
      positions: positions,
      size: size,
      signature: signature,
    );
  }

  static Map<String, int> _directedRanks(
      List<String> component, List<NetworkEdge> edges) {
    final incoming = <String, List<String>>{for (final id in component) id: []};
    final outgoing = <String, List<String>>{for (final id in component) id: []};
    final indegree = <String, int>{for (final id in component) id: 0};
    for (final edge in edges) {
      final from = edge.link.from, to = edge.link.to;
      if (from == to || outgoing[from]!.contains(to)) continue;
      outgoing[from]!.add(to);
      incoming[to]!.add(from);
      indegree[to] = indegree[to]! + 1;
    }
    for (final list in [...incoming.values, ...outgoing.values]) {
      list.sort();
    }
    final ranks = <String, int>{};
    final ready = component.where((id) => indegree[id] == 0).toList()..sort();
    while (ready.isNotEmpty) {
      final id = ready.removeAt(0);
      final parents = incoming[id]!;
      ranks[id] = parents.isEmpty
          ? 0
          : parents
              .where(ranks.containsKey)
              .map((parent) => ranks[parent]! + 1)
              .fold(0, math.max);
      for (final child in outgoing[id]!) {
        indegree[child] = indegree[child]! - 1;
        if (indegree[child] == 0) {
          ready.add(child);
          ready.sort();
        }
      }
    }
    // Cyclic relations remain renderable and honest. Unranked members share a
    // stable vertical layer instead of recursing forever or inventing a root.
    for (final id in component) {
      ranks.putIfAbsent(id, () => 0);
    }
    return ranks;
  }

  Rect rect(String id) {
    final position = positions[id];
    if (position == null) return Rect.zero;
    return position & const Size(nodeWidth, nodeHeight);
  }

  Offset? center(String id) {
    final position = positions[id];
    return position == null
        ? null
        : position + const Offset(nodeWidth / 2, nodeHeight / 2);
  }

  /// All labels are inside their node cards and every edge terminates on those
  /// cards, so the padded union of node rectangles is the complete fit bounds.
  Rect get contentBounds => Offset.zero & size;
}

class NetworkEdgeCurve {
  final Offset start, control1, control2, end;
  const NetworkEdgeCurve(this.start, this.control1, this.control2, this.end);
}

NetworkEdgeCurve? networkEdgeCurve(TopologyLayout layout, NetworkLink link) {
  final from = layout.rect(link.from);
  final to = layout.rect(link.to);
  if (from == Rect.zero || to == Rect.zero || from == to) return null;
  final horizontal = (to.center.dx - from.center.dx).abs() >
      (to.center.dy - from.center.dy).abs();
  late final Offset start, end;
  if (horizontal) {
    final forward = to.center.dx >= from.center.dx;
    start = forward ? from.centerRight : from.centerLeft;
    end = forward ? to.centerLeft : to.centerRight;
    final bend = math.max(36.0, (end.dx - start.dx).abs() * .46);
    final direction = end.dx >= start.dx ? 1.0 : -1.0;
    return NetworkEdgeCurve(
      start,
      start + Offset(direction * bend, 0),
      end - Offset(direction * bend, 0),
      end,
    );
  }
  final forward = to.center.dy >= from.center.dy;
  start = forward ? from.bottomCenter : from.topCenter;
  end = forward ? to.topCenter : to.bottomCenter;
  final bend = math.max(30.0, (end.dy - start.dy).abs() * .46);
  final direction = end.dy >= start.dy ? 1.0 : -1.0;
  return NetworkEdgeCurve(
    start,
    start + Offset(0, direction * bend),
    end - Offset(0, direction * bend),
    end,
  );
}

(Offset, Offset)? networkEdgeEndpoints(
    TopologyLayout layout, NetworkLink link) {
  final curve = networkEdgeCurve(layout, link);
  return curve == null ? null : (curve.start, curve.end);
}

Offset networkEdgePoint(NetworkEdgeCurve curve, double t) {
  final u = 1 - t;
  return curve.start * (u * u * u) +
      curve.control1 * (3 * u * u * t) +
      curve.control2 * (3 * u * t * t) +
      curve.end * (t * t * t);
}

Path networkEdgePath(NetworkEdgeCurve curve) => Path()
  ..moveTo(curve.start.dx, curve.start.dy)
  ..cubicTo(
    curve.control1.dx,
    curve.control1.dy,
    curve.control2.dx,
    curve.control2.dy,
    curve.end.dx,
    curve.end.dy,
  );

double networkDistanceToCurve(Offset point, NetworkEdgeCurve curve) {
  var previous = curve.start;
  var distance = double.infinity;
  for (var step = 1; step <= 32; step++) {
    final next = networkEdgePoint(curve, step / 32);
    distance =
        math.min(distance, networkDistanceToSegment(point, previous, next));
    previous = next;
  }
  return distance;
}

class NetworkTopologyGraph extends StatefulWidget {
  final TopologyLayout layout;
  final List<NetworkEdge> edges;
  final TransformationController transformation;
  final FocusNode focusNode;
  final String? selectedDeviceId, selectedEdgeId;
  final Set<String> highlightedDeviceIds;
  final bool transportLive;
  final bool showEdgeLabels;
  final ValueChanged<Device> onNode;
  final ValueChanged<NetworkEdge> onEdge;
  final ValueChanged<Size> onViewportSize;
  final VoidCallback? onInteraction;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;

  const NetworkTopologyGraph({
    super.key,
    required this.layout,
    required this.edges,
    required this.transformation,
    required this.focusNode,
    required this.selectedDeviceId,
    required this.selectedEdgeId,
    required this.highlightedDeviceIds,
    required this.transportLive,
    this.showEdgeLabels = true,
    required this.onNode,
    required this.onEdge,
    required this.onViewportSize,
    this.onInteraction,
    this.onKeyEvent,
  });

  @override
  State<NetworkTopologyGraph> createState() => _NetworkTopologyGraphState();
}

class _NetworkTopologyGraphState extends State<NetworkTopologyGraph> {
  Size? lastViewport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final viewport = Size(constraints.maxWidth, constraints.maxHeight);
      if (lastViewport != viewport) {
        lastViewport = viewport;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onViewportSize(viewport);
        });
      }
      return Focus(
        focusNode: widget.focusNode,
        onKeyEvent: widget.onKeyEvent,
        child: Semantics(
          container: true,
          label: 'Topologie-Viewport',
          child: ClipRect(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(scheme.surface,
                    Theme.of(context).scaffoldBackgroundColor, .42),
              ),
              child: widget.layout.devices.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Keine registrierten Geräte im aktuellen Kontext oder Filter.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : InteractiveViewer(
                      key: const Key('network-viewer'),
                      transformationController: widget.transformation,
                      minScale: .35,
                      maxScale: 2.5,
                      constrained: false,
                      boundaryMargin: const EdgeInsets.all(24),
                      trackpadScrollCausesScale: false,
                      onInteractionStart: (_) => widget.onInteraction?.call(),
                      child: SizedBox(
                        key: const Key('topology-canvas'),
                        width: widget.layout.size.width,
                        height: widget.layout.size.height,
                        child: Stack(children: [
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (details) =>
                                  _selectEdgeAt(details.localPosition),
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  painter: NetworkTopologyPainter(
                                    layout: widget.layout,
                                    edges: widget.edges,
                                    selectedEdgeId: widget.selectedEdgeId,
                                    selectedDeviceId: widget.selectedDeviceId,
                                    selectedColor: OipTokens.readableAccent(
                                        context, OipTokens.violet),
                                    connectedColor: OipTokens.statusColor(
                                        context, 'connected'),
                                    degradedColor: OipTokens.statusColor(
                                        context, 'degraded'),
                                    errorColor: OipTokens.statusColor(
                                        context, 'critical'),
                                    unknownColor: OipTokens.statusColor(
                                        context, 'unknown'),
                                    hairline: scheme.outlineVariant,
                                    labelColor: OipTokens.muted(context),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          for (final device in widget.layout.devices)
                            if (widget.layout.positions[device.id] != null)
                              Positioned(
                                left: widget.layout.positions[device.id]!.dx,
                                top: widget.layout.positions[device.id]!.dy,
                                width: TopologyLayout.nodeWidth,
                                height: TopologyLayout.nodeHeight,
                                child: Opacity(
                                  opacity: (widget.selectedDeviceId != null ||
                                              widget.selectedEdgeId != null) &&
                                          !widget.highlightedDeviceIds
                                              .contains(device.id)
                                      ? .38
                                      : 1,
                                  child: RepaintBoundary(
                                    child: NetworkTopologyNode(
                                      device: device,
                                      selected:
                                          widget.selectedDeviceId == device.id,
                                      highlighted: widget.highlightedDeviceIds
                                          .contains(device.id),
                                      transportLive: widget.transportLive,
                                      onTap: () => widget.onNode(device),
                                    ),
                                  ),
                                ),
                              ),
                          for (final handle in _edgeHandles())
                            Positioned(
                              left: handle.position.dx - 30,
                              top: handle.position.dy - 13,
                              width: 60,
                              height: 26,
                              child: _EdgeHandle(
                                edge: handle.edge,
                                selected:
                                    widget.selectedEdgeId == handle.edge.id,
                                onTap: () => widget.onEdge(handle.edge),
                              ),
                            ),
                        ]),
                      ),
                    ),
            ),
          ),
        ),
      );
    });
  }

  List<({NetworkEdge edge, Offset position})> _edgeHandles() {
    if (!widget.showEdgeLabels) return const [];
    final handles = <({NetworkEdge edge, Offset position})>[];
    for (final edge in widget.edges) {
      final curve = networkEdgeCurve(widget.layout, edge.link);
      if (curve == null) continue;
      final midpoint = networkEdgePoint(curve, .5);
      final covered = widget.layout.devices.any((device) =>
          widget.layout.rect(device.id).inflate(4).contains(midpoint));
      if (covered) continue;
      handles.add((edge: edge, position: midpoint));
    }
    return handles;
  }

  void _selectEdgeAt(Offset point) {
    NetworkEdge? nearest;
    var distance = 14.0;
    for (final edge in widget.edges) {
      final curve = networkEdgeCurve(widget.layout, edge.link);
      if (curve == null) continue;
      final current = networkDistanceToCurve(point, curve);
      if (current <= distance) {
        nearest = edge;
        distance = current;
      }
    }
    if (nearest != null) widget.onEdge(nearest);
  }
}

class NetworkTopologyNode extends StatelessWidget {
  final Device device;
  final bool selected, highlighted, transportLive;
  final VoidCallback onTap;

  const NetworkTopologyNode({
    super.key,
    required this.device,
    required this.selected,
    required this.highlighted,
    required this.transportLive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = OipTokens.deviceCategoryColor(context, device.kind);
    final accent = OipTokens.readableAccent(context, category);
    final status = transportLive ? device.health.reachability : 'stale';
    final statusColor = OipTokens.statusColor(context, status);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Details ${device.name}, Status ${OipTokens.statusLabel(status)}',
      child: Material(
        color: Color.lerp(scheme.surface, category, selected ? .10 : .035),
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: selected
                ? OipTokens.readableAccent(context, OipTokens.violet)
                : highlighted
                    ? accent.withOpacity(.72)
                    : scheme.outline,
            width: selected ? 1.8 : 1,
          ),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Tooltip(
          message:
              '${device.name}\n${deviceKindName(device.kind)} · ${device.location}\nErreichbarkeit: ${OipTokens.statusLabel(status)}\nTelemetrie: ${OipTokens.statusLabel(transportLive ? device.health.freshness : 'stale')}\n${device.simulated ? 'Demo-Inventar' : 'API-Inventar'}',
          child: InkWell(
            key: Key('topology-${device.id}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(9),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              child: Row(children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(.10),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: accent.withOpacity(.28)),
                  ),
                  child: Icon(networkKindIcon(device.kind),
                      size: 17, color: accent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(
                        '${deviceKindName(device.kind)} · ${OipTokens.statusLabel(status)} · ${device.simulated ? 'Demo' : 'API'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(fontSize: 9.5, color: statusColor),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeHandle extends StatelessWidget {
  final NetworkEdge edge;
  final bool selected;
  final VoidCallback onTap;
  const _EdgeHandle(
      {required this.edge, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? OipTokens.readableAccent(context, OipTokens.violet)
        : OipTokens.statusColor(context, edge.link.status);
    final from = edge.link.from;
    final to = edge.link.to;
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label:
          'Verbindung $from nach $to, ${edge.link.transport}, Status ${OipTokens.statusLabel(edge.link.status)}',
      child: Tooltip(
        message: '$from → $to\n${edge.link.transport}\n'
            'Status ${OipTokens.statusLabel(edge.link.status)}\n'
            '${edge.link.simulated ? 'Demo / Fixture' : 'API'}',
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: BorderSide(color: color.withOpacity(selected ? 1 : .65)),
          ),
          child: InkWell(
            key: Key('edge-handle-${edge.id.hashCode}'),
            onTap: onTap,
            customBorder:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Row(children: [
                Container(
                  width: selected ? 7 : 5,
                  height: selected ? 7 : 5,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    edge.link.transport,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class NetworkTopologyPainter extends CustomPainter {
  final TopologyLayout layout;
  final List<NetworkEdge> edges;
  final String? selectedEdgeId;
  final String? selectedDeviceId;
  final Color selectedColor,
      connectedColor,
      degradedColor,
      errorColor,
      unknownColor,
      hairline,
      labelColor;

  const NetworkTopologyPainter({
    required this.layout,
    required this.edges,
    required this.selectedEdgeId,
    this.selectedDeviceId,
    required this.selectedColor,
    required this.connectedColor,
    required this.degradedColor,
    required this.errorColor,
    required this.unknownColor,
    required this.hairline,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // A restrained grid makes pan and zoom legible without suggesting zones,
    // physical locations or additional connections.
    final grid = Paint()
      ..color = hairline.withOpacity(.22)
      ..strokeWidth = .6;
    for (var x = 28.0; x < size.width; x += 56) {
      for (var y = 28.0; y < size.height; y += 56) {
        canvas.drawCircle(Offset(x, y), .75, grid);
      }
    }
    for (final edge in edges) {
      final curve = networkEdgeCurve(layout, edge.link);
      if (curve == null) continue;
      final path = networkEdgePath(curve);
      final selected = edge.id == selectedEdgeId;
      final status = edge.link.status;
      final color = selected
          ? selectedColor
          : switch (status) {
              'connected' || 'active' => connectedColor,
              'degraded' || 'stale' => degradedColor,
              'critical' || 'offline' || 'alarm' => errorColor,
              _ => unknownColor,
            };
      final related = selectedDeviceId == null ||
          edge.link.from == selectedDeviceId ||
          edge.link.to == selectedDeviceId;
      final displayColor = related || selected ? color : color.withOpacity(.22);
      final line = Paint()
        ..color = displayColor.withOpacity(selected ? 1 : .82)
        ..strokeWidth = selected ? 2.8 : 1.6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      if (selected) {
        canvas.drawPath(
            path,
            Paint()
              ..color = selectedColor.withOpacity(.12)
              ..strokeWidth = 10
              ..strokeCap = StrokeCap.round
              ..style = PaintingStyle.stroke);
      }
      if (status != 'connected' && status != 'active') {
        for (final metric in path.computeMetrics()) {
          var distance = 0.0;
          while (distance < metric.length) {
            final end = math.min(distance + 7, metric.length);
            canvas.drawPath(metric.extractPath(distance, end), line);
            distance += 12;
          }
        }
      } else {
        canvas.drawPath(path, line);
      }
      canvas.drawCircle(
          curve.start,
          selected ? 3.5 : 2.5,
          Paint()
            ..color = displayColor
            ..style = PaintingStyle.fill);
      _arrow(canvas, curve, displayColor, selected ? 7 : 6);
    }
  }

  void _arrow(Canvas canvas, NetworkEdgeCurve curve, Color color, double size) {
    final before = networkEdgePoint(curve, .985);
    final direction = curve.end - before;
    if (direction.distance == 0) return;
    final unit = direction / direction.distance;
    final normal = Offset(-unit.dy, unit.dx);
    final base = curve.end - unit * size;
    final path = Path()
      ..moveTo(curve.end.dx, curve.end.dy)
      ..lineTo(
          base.dx + normal.dx * size * .42, base.dy + normal.dy * size * .42)
      ..lineTo(
          base.dx - normal.dx * size * .42, base.dy - normal.dy * size * .42)
      ..close();
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant NetworkTopologyPainter oldDelegate) =>
      oldDelegate.layout.signature != layout.signature ||
      oldDelegate.edges.map((edge) => edge.signature).join('|') !=
          edges.map((edge) => edge.signature).join('|') ||
      oldDelegate.selectedEdgeId != selectedEdgeId ||
      oldDelegate.selectedDeviceId != selectedDeviceId ||
      oldDelegate.connectedColor != connectedColor ||
      oldDelegate.degradedColor != degradedColor ||
      oldDelegate.errorColor != errorColor ||
      oldDelegate.unknownColor != unknownColor ||
      oldDelegate.hairline != hairline;
}
