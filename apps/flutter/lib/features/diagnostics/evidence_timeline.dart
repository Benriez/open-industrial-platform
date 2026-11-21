import '../../l10n/oip_strings.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/theme.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'diagnostics_model.dart';
import 'event_explorer.dart';

class DiagnosticsEventTimeline extends StatelessWidget {
  final List<DiagnosticEvent> events;
  final String? selectedKey;
  final DiagnosticsTimelineRange range;
  final VoidCallback onZoomIn, onZoomOut, onFit, onPanLeft, onPanRight, onHide;
  final ValueChanged<DiagnosticEvent> onSelected;
  final ValueChanged<double> onPanDelta;

  const DiagnosticsEventTimeline({
    super.key,
    required this.events,
    required this.selectedKey,
    required this.range,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    required this.onPanLeft,
    required this.onPanRight,
    required this.onHide,
    required this.onSelected,
    required this.onPanDelta,
  });

  @override
  Widget build(BuildContext context) {
    final timestamped = events.where((item) => item.hasTimestamp).toList();
    final missingTime = events.length - timestamped.length;
    final lanes = timestamped.map((item) => item.sourceLabel).toSet().toList()
      ..sort();
    final visibleCount =
        timestamped.where((item) => range.contains(item.timestampMs!)).length;
    return WorkstationPanel(
      key: const Key('diagnostics-evidence-timeline'),
      accent: OipTokens.violet,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
          child: LayoutBuilder(builder: (context, box) {
            final title =
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr("EVIDENCE TIMELINE 2.0"),
                  style: WorkstationTokens.eyebrow(context,
                      color: OipTokens.violet)),
              const SizedBox(height: 2),
              Text(context.tr("Evidence Timeline"),
                  style: Theme.of(context).textTheme.titleMedium),
              if (box.maxWidth >= 500)
                Text(
                    context.tr(
                        "Nur zeitgestempelte Collection-Ereignisse · zeitliche Nähe beweist keine Ursache"),
                    style: Theme.of(context).textTheme.bodySmall),
            ]);
            if (box.maxWidth < 500) {
              return Row(children: [
                Expanded(child: title),
                IconButton(
                    tooltip: context.tr("Spuren ausblenden"),
                    onPressed: onHide,
                    icon: const Icon(Icons.visibility_off_outlined, size: 18)),
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: title),
              TextButton.icon(
                  onPressed: onHide,
                  icon: const Icon(Icons.visibility_off_outlined, size: 16),
                  label: Text(context.tr("Spuren ausblenden"))),
            ]);
          }),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Wrap(
              spacing: 5,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ToolButton(
                    key: const Key('diagnostics-timeline-zoom-out'),
                    icon: Icons.zoom_out,
                    tooltip: context.tr("Timeline verkleinern"),
                    onPressed: range.zoom <= 1 ? null : onZoomOut),
                ToolButton(
                    key: const Key('diagnostics-timeline-zoom-in'),
                    icon: Icons.zoom_in,
                    tooltip: context.tr("Timeline vergrößern"),
                    onPressed: range.zoom >= 64 ? null : onZoomIn),
                ToolButton(
                    key: const Key('diagnostics-timeline-fit'),
                    icon: Icons.fit_screen,
                    tooltip: context.tr("Fit to Available Data"),
                    onPressed: onFit),
                ToolButton(
                    key: const Key('diagnostics-timeline-pan-left'),
                    icon: Icons.arrow_back,
                    tooltip: context.tr("Timeline nach links"),
                    onPressed: onPanLeft),
                ToolButton(
                    key: const Key('diagnostics-timeline-pan-right'),
                    icon: Icons.arrow_forward,
                    tooltip: context.tr("Timeline nach rechts"),
                    onPressed: onPanRight),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('${range.zoom.toStringAsFixed(1)}×',
                        style: WorkstationTokens.mono(context, size: 11))),
              ]),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(10, 7, 10, 6),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
              color: WorkstationTokens.well(context),
              borderRadius: BorderRadius.circular(6)),
          child: Text(
              context.tr(
                  "ZEITBASIS · EVENT TIMESTAMP / SERVER WALL CLOCK · UTC\n{0}/{1} zeitgestempelte Ereignisse im Viewport · {2} ohne Zeitstempel nur im Explorer",
                  [
                    visibleCount,
                    timestamped.length,
                    missingTime
                  ]),
              style: WorkstationTokens.mono(context,
                  size: 9.5, color: OipTokens.muted(context))),
        ),
        if (timestamped.isEmpty)
          Expanded(
              child: Center(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: WorkstationNote(
                          context.tr("Keine zeitgestempelten Ereignisse"),
                          context.tr(
                              "Ereignisse ohne EventTimestamp bleiben vollständig im Explorer und Inspector verfügbar. Es wird keine Position erfunden.")))))
        else ...[
          _Axis(range: range),
          Expanded(
            child: ListView.builder(
              key: const Key('diagnostics-timeline-source-lanes'),
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
              itemCount: lanes.length,
              itemBuilder: (context, index) {
                final lane = lanes[index];
                final laneEvents = timestamped
                    .where((item) => item.sourceLabel == lane)
                    .toList();
                return _SourceLane(
                  lane: lane,
                  events: laneEvents,
                  range: range,
                  selectedKey: selectedKey,
                  onSelected: onSelected,
                  onPanDelta: onPanDelta,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
                context.tr(
                    "Marker gruppieren sich nur visuell; Gruppen öffnen alle Mitglieder. Gap-Flächen nutzen ausschließlich dokumentierte Grenzen."),
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ]),
    );
  }
}

class _Axis extends StatelessWidget {
  final DiagnosticsTimelineRange range;
  const _Axis({required this.range});
  @override
  Widget build(BuildContext context) {
    final middle = range.startMs + range.spanMs ~/ 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(104, 2, 14, 5),
      child: Row(children: [
        Expanded(
            child: Text(_axisTime(range.startMs),
                overflow: TextOverflow.ellipsis,
                style: WorkstationTokens.mono(context, size: 9))),
        Expanded(
            child: Text(_axisTime(middle),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: WorkstationTokens.mono(context, size: 9))),
        Expanded(
            child: Text(_axisTime(range.endMs),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: WorkstationTokens.mono(context, size: 9))),
      ]),
    );
  }
}

String _axisTime(int value) {
  final text = timestamp(value);
  return text.length >= 23 ? text.substring(11, 23) : text;
}

class _SourceLane extends StatelessWidget {
  final String lane;
  final List<DiagnosticEvent> events;
  final DiagnosticsTimelineRange range;
  final String? selectedKey;
  final ValueChanged<DiagnosticEvent> onSelected;
  final ValueChanged<double> onPanDelta;
  const _SourceLane(
      {required this.lane,
      required this.events,
      required this.range,
      required this.selectedKey,
      required this.onSelected,
      required this.onPanDelta});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 70,
      child: Row(children: [
        SizedBox(
          width: 92,
          child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(lane,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: WorkstationTokens.mono(context, size: 9.5)),
                    Text(context.tr("{0} Events", [events.length]),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 10)),
                  ])),
        ),
        Expanded(child: LayoutBuilder(builder: (context, box) {
          final clusters =
              diagnosticTimelineClusters(events, range, box.maxWidth);
          final gaps = events
              .where((item) =>
                  item.hasCompleteGap &&
                  !item.gapIsInverted &&
                  !item.isDataLoss)
              .toList();
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) => onPanDelta(
                -details.delta.dx / math.max(1, box.maxWidth) * range.spanMs),
            child: Container(
              decoration: BoxDecoration(
                  color: WorkstationTokens.well(context),
                  border:
                      Border.all(color: WorkstationTokens.hairline(context)),
                  borderRadius: BorderRadius.circular(7)),
              clipBehavior: Clip.antiAlias,
              child: CustomPaint(
                painter: _GapPainter(
                    gaps: gaps, range: range, color: OipTokens.yellow),
                child: Stack(children: [
                  for (final cluster in clusters)
                    Positioned(
                      left: cluster.leftPx
                          .clamp(0.0, math.max(0.0, box.maxWidth - 48)),
                      top: 10,
                      width: 48,
                      height: 48,
                      child: _TimelineMarker(
                          cluster: cluster,
                          selectedKey: selectedKey,
                          onSelected: onSelected),
                    ),
                ]),
              ),
            ),
          );
        })),
      ]),
    );
  }
}

class _TimelineMarker extends StatelessWidget {
  final DiagnosticTimelineCluster cluster;
  final String? selectedKey;
  final ValueChanged<DiagnosticEvent> onSelected;
  const _TimelineMarker(
      {required this.cluster,
      required this.selectedKey,
      required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final first = cluster.events.first;
    final count = cluster.events.length;
    final selected = cluster.events.any((item) => item.key == selectedKey);
    final tone = count == 1
        ? diagnosticEventTone(context, first.event.kind)
        : OipTokens.violet;
    final label = count == 1
        ? 'Telemetry: $lanePrefix${diagnosticEventTitle(first.event.kind)}, ${timestamp(first.timestampMs)}, ${first.event.reason ?? 'Grund nicht geliefert'}'
        : 'Telemetry: $lanePrefix$count Ereignisse, ${timestamp(cluster.firstMs)} bis ${timestamp(cluster.lastMs)}. Gruppe öffnen.';
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: label,
      child: Material(
        color: selected ? tone : tone.withOpacity(.78),
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          key: Key(count == 1
              ? 'timeline-${first.key}'
              : 'timeline-group-${cluster.firstMs}-${cluster.lastMs}-$count'),
          onTap: () => count == 1 ? onSelected(first) : _openGroup(context),
          borderRadius: BorderRadius.circular(7),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.onSurface
                        : tone,
                    width: selected ? 2 : 1)),
            child: count == 1
                ? Icon(
                    first.event.kind == 'ConnectionLost'
                        ? Icons.link_off
                        : first.event.kind == 'Reconnected'
                            ? Icons.link
                            : first.event.kind == 'DataLoss'
                                ? Icons.data_usage_outlined
                                : Icons.error_outline,
                    size: 18,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? OipTokens.appBackground
                        : Colors.white)
                : Text('$count',
                    style: WorkstationTokens.mono(context,
                        size: 13,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? OipTokens.appBackground
                            : Colors.white,
                        weight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }

  String get lanePrefix {
    final first = cluster.events.first;
    return first.sourceId == null ? '' : '${first.sourceId}: ';
  }

  Future<void> _openGroup(BuildContext context) async {
    final selected = await showDialog<DiagnosticEvent>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            context.tr("{0} zeitnahe Ereignisse", [cluster.events.length])),
        content: SizedBox(
          width: 520,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    context.tr(
                        "{0} bis {1}\nVisuelle Gruppe · keine Korrelation oder Ursache",
                        [
                          timestamp(cluster.firstMs),
                          timestamp(cluster.lastMs)
                        ]),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: cluster.events.length,
                    itemBuilder: (context, index) {
                      final item = cluster.events[index];
                      return ListTile(
                        key:
                            Key('diagnostics-timeline-group-event-${item.key}'),
                        dense: true,
                        title: Text(
                            context.tr(diagnosticEventTitle(item.event.kind))),
                        subtitle: Text(
                            '${item.recordId ?? 'Keine Server-Record-ID'}\n${timestamp(item.timestampMs)}'),
                        onTap: () => Navigator.of(context).pop(item),
                      );
                    },
                  ),
                ),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.tr("Schließen")))
        ],
      ),
    );
    if (selected != null) onSelected(selected);
  }
}

class _GapPainter extends CustomPainter {
  final List<DiagnosticEvent> gaps;
  final DiagnosticsTimelineRange range;
  final Color color;
  const _GapPainter(
      {required this.gaps, required this.range, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    for (final item in gaps) {
      final start = item.event.gapStartedMs!;
      final end = item.event.gapEndedMs!;
      final visibleStart = math.max(start, range.startMs);
      final visibleEnd = math.min(end, range.endMs);
      if (visibleEnd < range.startMs || visibleStart > range.endMs) continue;
      final x1 = (visibleStart - range.startMs) / range.spanMs * size.width;
      final x2 = (visibleEnd - range.startMs) / range.spanMs * size.width;
      final width = math.max(3.0, x2 - x1);
      canvas.drawRect(
          Rect.fromLTWH(
              x1, 4, math.min(width, size.width - x1), size.height - 8),
          Paint()..color = color.withOpacity(.12));
      canvas.drawLine(
          Offset(x1, 4),
          Offset(x1, size.height - 4),
          Paint()
            ..color = color.withOpacity(.6)
            ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(_GapPainter old) =>
      old.gaps.length != gaps.length ||
      old.range != range ||
      old.color != color;
}
