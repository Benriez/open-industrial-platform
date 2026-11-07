import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app/controller.dart';
import '../models/contracts.dart';
import '../design_system/theme.dart';
import '../widgets/components.dart';
import 'devices.dart';

class NetworkPage extends StatefulWidget {
  final OipController controller;
  const NetworkPage(this.controller, {super.key});

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  final transformation = TransformationController();
  String? selectedId;

  @override
  void dispose() {
    transformation.dispose();
    super.dispose();
  }

  void _zoom(double scale) {
    final current = transformation.value.getMaxScaleOnAxis();
    final next = (current * scale).clamp(.6, 2.0);
    transformation.value = transformation.value.clone()..scale(next / current);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.snapshot!;
    final managed = widget.controller.managed;
    // The legacy demo groups the nodes in fixed network zones. The managed
    // mode knows no such zones: the authorized placement of the session is
    // the site of the registered node.
    final zones = managed
        ? (snapshot.devices.map((device) => device.location).toSet().toList()
          ..sort())
        : <String>[
            'LAN',
            'Tailnet',
            'Remote Site',
            ...snapshot.devices
                .map((device) => device.location)
                .where((zone) => !['LAN', 'Tailnet', 'Remote Site'].contains(zone))
                .toSet(),
          ];
    final zoneDevices = {
      for (final zone in zones)
        zone:
            snapshot.devices.where((device) => device.location == zone).toList()
    };
    final positions = <String, Offset>{};
    const nodeWidth = 236.0, nodeHeight = 58.0, columnWidth = 280.0;
    var maxRows = 0;
    for (var column = 0; column < zones.length; column++) {
      final devices = zoneDevices[zones[column]]!;
      maxRows = devices.length > maxRows ? devices.length : maxRows;
      for (var row = 0; row < devices.length; row++) {
        positions[devices[row].id] =
            Offset(24 + column * columnWidth, 84 + row * 70);
      }
    }
    final canvasWidth = zones.length * columnWidth + 24;
    final canvasHeight = math.max(430.0, maxRows * 70 + 112).toDouble();
    final selected =
        snapshot.devices.where((device) => device.id == selectedId).firstOrNull;

    final graph = Panel(
      padding: EdgeInsets.zero,
      accent: OipTokens.pink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('Logische Topologie',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                IconButton(
                  tooltip: 'Verkleinern',
                  onPressed: () => _zoom(.8),
                  icon: const Icon(Icons.remove, size: 18),
                ),
                IconButton(
                  tooltip: 'Vergrößern',
                  onPressed: () => _zoom(1.25),
                  icon: const Icon(Icons.add, size: 18),
                ),
                IconButton(
                  tooltip: 'Topologie einpassen',
                  onPressed: () => transformation.value = Matrix4.identity(),
                  icon: const Icon(Icons.fit_screen, size: 18),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 510,
            child: ClipRect(
              child: InteractiveViewer(
                transformationController: transformation,
                minScale: .6,
                maxScale: 2,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(80),
                child: SizedBox(
                  key: const Key('topology-canvas'),
                  width: canvasWidth,
                  height: canvasHeight,
                  child: Stack(
                    children: [
                      RepaintBoundary(
                        child: CustomPaint(
                          size: Size(canvasWidth, canvasHeight),
                          painter: _TopologyPainter(
                            links: snapshot.topology,
                            positions: positions,
                            nodeWidth: nodeWidth,
                            nodeHeight: nodeHeight,
                            degradedColor:
                                OipTokens.statusColor(context, 'degraded'),
                            scheme: Theme.of(context).colorScheme,
                          ),
                        ),
                      ),
                        for (var column = 0; column < zones.length; column++)
                        _ZoneBand(
                          left: 12 + column * columnWidth,
                          width: 260,
                          height: canvasHeight - 24,
                          zone: zones[column],
                          zoneLabel: managed
                              ? '${zoneDevices[zones[column]]!.length} Geräte · Standort'
                              : null,
                          count: zoneDevices[zones[column]]!.length,
                          status: _zoneStatus(zones[column],
                              zoneDevices[zones[column]]!, snapshot),
                          accent: [
                            OipTokens.pink,
                            OipTokens.violet,
                            OipTokens.blue,
                            OipTokens.cyan
                          ][column % 4],
                        ),
                      for (final device in snapshot.devices)
                        if (positions[device.id] != null)
                          Positioned(
                            left: positions[device.id]!.dx,
                            top: positions[device.id]!.dy,
                            width: nodeWidth,
                            height: nodeHeight,
                            child: _TopologyNode(
                              device: device,
                              selected: selectedId == device.id,
                              onTap: () {
                                setState(() => selectedId = device.id);
                                showDevice(context, widget.controller, device);
                              },
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(OipTokens.s3),
            child: Text(
              'Zoomen und verschieben mit Maus, Trackpad oder Touch. Linien zeigen ausschließlich vorhandene API-Pfade; Zonenflächen sind Gruppierungen, keine Verbindungen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );

    final detail = InteractiveInspector(
      accent: selected == null
          ? OipTokens.pink
          : OipTokens.deviceCategoryColor(context, selected.kind),
      child: selected == null
          ? const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle('Knotendetails', 'Selektion und Datenqualität'),
                InlineNotice(
                  'Gerät auswählen',
                  'Ein Knoten öffnet die bekannten Gesundheitsdimensionen. Nach dem Schließen bleibt die Auswahl hier sichtbar.',
                  icon: Icons.touch_app_outlined,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                    selected.name, '${selected.kind} · ${selected.location}'),
                _selectedFact('Erreichbarkeit', selected.health.reachability),
                _selectedFact('VPN', selected.health.vpn),
                _selectedFact('Agent', selected.health.agent),
                _selectedFact('Dienst', selected.health.service),
                _selectedFact('Telemetrie', selected.health.freshness),
                const SizedBox(height: OipTokens.s3),
                OutlinedButton.icon(
                  onPressed: () =>
                      showDevice(context, widget.controller, selected),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Gerätedetails öffnen'),
                ),
              ],
            ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('Netzwerk & VPN',
            'Interaktive logische Topologie · keine Netzwerk-Probes',
            accent: OipTokens.pink,
            action: StatusPill(
                snapshot.system.simulated ? 'SIMULATION' : 'API-DATEN',
                color: OipTokens.statusColor(context, 'info'),
                icon: snapshot.system.simulated
                    ? Icons.science_outlined
                    : Icons.cloud_done_outlined)),
        LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 1100
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: graph),
                  const SizedBox(width: OipTokens.s4),
                  Expanded(child: detail),
                ])
              : Column(children: [
                  graph,
                  const SizedBox(height: OipTokens.s4),
                  detail,
                ]),
        ),
        const SizedBox(height: OipTokens.s6),
        SectionTitle(
            'Verbindungspfade',
            snapshot.topology.isNotEmpty &&
                    snapshot.topology.every((link) => link.simulated)
                ? 'Alle Latenzen und Verluste in dieser Ansicht sind Demo-Fixtures.'
                : 'Latenzen und Verluste werden ausschließlich aus API-Pfaden angezeigt.'),
        if (snapshot.topology.isEmpty)
          managed
              ? const InlineNotice(
                  'Keine Verbindungspfade in der autorisierten Projektion',
                  'Die Projektion der Sitzung enthält keine Topologie. Es wird kein Pfad geraten und keine Erreichbarkeit eingefärbt.',
                  icon: Icons.hub_outlined,
                )
              : const StateMessage('Topologie wird geladen',
                  'Der Live-Stream liefert das gemeinsame Rust-Modell.'),
        ...snapshot.topology
            .map((link) => _link(context, link, snapshot.devices)),
        const SizedBox(height: OipTokens.s4),
        if (managed) ...[
          const SectionTitle(
              'Autorisierte Platzierung',
              'Organisation, Infrastruktur, Standort und Quelle der Sitzung · keine erfundenen Verbindungen',
              accent: OipTokens.cyan),
          if (snapshot.locations.isEmpty)
            const InlineNotice(
              'Keine Platzierung geliefert',
              'Die autorisierte Projektion nennt keine Platzierung. Das ist kein Nachweis einer fehlenden Infrastruktur.',
              icon: Icons.account_tree_outlined,
            )
          else
            for (final location in snapshot.locations)
              _PlacementRow(
                location: location,
                devices: snapshot.devices
                    .where((device) => device.location == location.siteId)
                    .toList(),
              ),
          const SizedBox(height: OipTokens.s4),
        ],
        const Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle('Erreichbar bedeutet noch nicht funktionsfähig',
                  'Fünf unabhängige Dimensionen in jedem Gerätedetail'),
              FactGrid(children: [
                Fact('Device Reachability', 'Antwortet der Netzwerkendpunkt?'),
                Fact('VPN Transport',
                    'Ist der Tunnel verbunden, degradiert oder unbekannt?'),
                Fact('Agent Availability', 'Liegt ein Agent-Heartbeat vor?'),
                Fact('Service Health',
                    'Antwortet der tatsächliche Dienst erfolgreich?'),
                Fact('Telemetry Freshness',
                    'Wie aktuell sind die letzten Messwerte?'),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _selectedFact(String label, String status) => Padding(
        padding: const EdgeInsets.symmetric(vertical: OipTokens.s2),
        child: Row(
          children: [
            StatusDot(status),
            const SizedBox(width: OipTokens.s2),
            Expanded(
                child:
                    Text(label, style: Theme.of(context).textTheme.bodySmall)),
            Flexible(child: Text(known(status), textAlign: TextAlign.end)),
          ],
        ),
      );

  String _zoneStatus(String zone, List<Device> devices, Snapshot snapshot) {
    final ids = devices.map((device) => device.id).toSet();
    final links = snapshot.topology
        .where((link) => ids.contains(link.from) || ids.contains(link.to))
        .toList();
    if (links.any((link) => link.status == 'degraded')) return 'degraded';
    if (links.isNotEmpty && links.every((link) => link.status == 'connected')) {
      return 'connected';
    }
    return 'unknown';
  }

  Widget _link(BuildContext context, NetworkLink link, List<Device> devices) {
    String name(String id) =>
        devices.where((device) => device.id == id).firstOrNull?.name ?? id;
    final color = OipTokens.statusColor(context, link.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: OipTokens.s3),
      child: Panel(
        padding: const EdgeInsets.all(OipTokens.s4),
        accent: color,
        child: Wrap(
          spacing: OipTokens.s6,
          runSpacing: OipTokens.s3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 210, maxWidth: 390),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusDot(link.status),
                  const SizedBox(width: OipTokens.s3),
                  Flexible(
                    child: Text('${name(link.from)} → ${name(link.to)}',
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                ],
              ),
            ),
            Text(link.transport),
            Text(link.latency == null
                ? 'RTT unbekannt'
                : 'RTT ${link.latency!.toStringAsFixed(1)} ms'),
            Text(link.loss == null
                ? 'Loss unbekannt'
                : 'Loss ${link.loss!.toStringAsFixed(1)} %'),
            StatusPill(
                '${known(link.status)} · ${link.simulated ? 'Demo' : 'API'}',
                color: color,
                showDot: true),
          ],
        ),
      ),
    );
  }
}

class _ZoneBand extends StatelessWidget {
  final double left, width, height;
  final String zone, status;

  /// The caption of the band. The legacy demo names a logical zone; the
  /// managed mode names the authorized site.
  final String? zoneLabel;
  final int count;
  final Color accent;
  const _ZoneBand({
    required this.left,
    required this.width,
    required this.height,
    required this.zone,
    required this.count,
    required this.status,
    required this.accent,
    this.zoneLabel,
  });

  @override
  Widget build(BuildContext context) => Positioned(
        left: left,
        top: 12,
        width: width,
        height: height,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.all(OipTokens.s3),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [accent.withOpacity(.13), accent.withOpacity(.025)],
              ),
              border: Border.all(color: accent.withOpacity(.28)),
              borderRadius: BorderRadius.circular(OipTokens.radius),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(zone,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                  color: OipTokens.readableAccent(
                                      context, accent))),
                      Text(zoneLabel ?? '$count Geräte · logische Zone',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                StatusPill(
                    status == 'connected'
                        ? 'STABIL'
                        : status == 'degraded'
                            ? 'DEGRADIERT'
                            : 'UNBEKANNT',
                    color: OipTokens.statusColor(context, status),
                    showDot: true),
              ],
            ),
          ),
        ),
      );
}

class _TopologyNode extends StatelessWidget {
  final Device device;
  final bool selected;
  final VoidCallback onTap;
  const _TopologyNode({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = OipTokens.deviceCategoryColor(context, device.kind);
    return Semantics(
      button: true,
      label:
          'Details ${device.name}, Status ${known(device.health.reachability)}',
      child: Material(
        color: Color.lerp(scheme.surface, accent, .10),
        shape: RoundedRectangleBorder(
          side: BorderSide(
              color: selected ? accent : accent.withOpacity(.36),
              width: selected ? 1.8 : 1),
          borderRadius: BorderRadius.circular(OipTokens.radiusSm),
        ),
        child: Tooltip(
          message:
              '${device.name}\n${device.kind} · ${device.location}\nErreichbarkeit: ${known(device.health.reachability)}\nTelemetrie: ${known(device.health.freshness)}',
          child: InkWell(
            key: Key('topology-${device.id}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(OipTokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  StatusDot(device.health.reachability),
                  const SizedBox(width: OipTokens.s2),
                  Icon(deviceIcon(device.kind), size: 17, color: accent),
                  const SizedBox(width: OipTokens.s2),
                  Expanded(
                    child: Text(device.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One authorized placement of the session.
///
/// The projection delivers the identifiers of the placement. Nothing is
/// derived from a name, an address or a device identifier, and no link
/// between two placements is invented.
class _PlacementRow extends StatelessWidget {
  final ScopedLocation location;
  final List<Device> devices;
  const _PlacementRow({required this.location, required this.devices});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: OipTokens.s3),
        child: Panel(
          padding: const EdgeInsets.all(OipTokens.s4),
          accent: OipTokens.cyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  '${location.organizationId} · ${location.infrastructureId} · ${location.siteId}',
                  style: Theme.of(context).textTheme.titleSmall),
              Text('Quelle ${location.sourceId}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: OipTokens.s2),
              Text(
                devices.isEmpty
                    ? 'Kein registriertes Gerät an diesem Standort.'
                    : devices
                        .map((device) =>
                            '${device.name} · ${known(device.health.reachability)}')
                        .join(' · '),
                style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
}

class _TopologyPainter extends CustomPainter {
  final List<NetworkLink> links;
  final Map<String, Offset> positions;
  final double nodeWidth, nodeHeight;
  final Color degradedColor;
  final ColorScheme scheme;
  const _TopologyPainter({
    required this.links,
    required this.positions,
    required this.nodeWidth,
    required this.nodeHeight,
    required this.degradedColor,
    required this.scheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final link in links) {
      final from = positions[link.from];
      final to = positions[link.to];
      if (from == null || to == null) continue;
      final start = from + Offset(nodeWidth / 2, nodeHeight / 2);
      final end = to + Offset(nodeWidth / 2, nodeHeight / 2);
      final linkColor =
          link.status == 'degraded' ? degradedColor : scheme.secondary;
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = linkColor.withOpacity(.10)
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
      final paint = Paint()
        ..color = linkColor
        ..strokeWidth = link.status == 'degraded' ? 2.2 : 1.7
        ..style = PaintingStyle.stroke;
      if (link.status == 'degraded') {
        _dashedLine(canvas, start, end, paint);
      } else {
        canvas.drawLine(start, end, paint);
      }
      canvas.drawCircle(start, 3, paint..style = PaintingStyle.fill);
      canvas.drawCircle(end, 3, paint);
    }
  }

  void _dashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    final distance = (end - start).distance;
    final direction = (end - start) / distance;
    var cursor = 0.0;
    while (cursor < distance) {
      final endCursor = (cursor + 8).clamp(0.0, distance);
      canvas.drawLine(
          start + direction * cursor, start + direction * endCursor, paint);
      cursor += 14;
    }
  }

  @override
  bool shouldRepaint(covariant _TopologyPainter old) =>
      !identical(old.links, links) ||
      !identical(old.positions, positions) ||
      old.degradedColor != degradedColor ||
      old.scheme != scheme;
}
