import '../l10n/oip_strings.dart';
import 'package:flutter/material.dart';
import '../app/controller.dart';
import '../design_system/theme.dart';
import '../models/contracts.dart';
import '../widgets/components.dart';
import 'device_connection_panel.dart';
import 'device_history.dart';
import '../widgets/device_kind.dart';

export 'devices/devices_workstation.dart' show DevicesPage;
export 'devices/device_session.dart' show DevicesWorkspaceSession;

// Shared registry dialog retained for Overview and Network. The Devices page
// itself uses the inline engineering workstation in devices/devices_workstation.dart.

Future<void> showDevice(
        BuildContext context, OipController controller, Device device) =>
    showDialog<void>(
      context: context,
      builder: (context) =>
          DeviceDetailDialog(controller: controller, device: device),
    );

class DeviceDetailDialog extends StatefulWidget {
  final OipController controller;
  final Device device;
  const DeviceDetailDialog(
      {super.key, required this.controller, required this.device});

  @override
  State<DeviceDetailDialog> createState() => _DeviceDetailDialogState();
}

class _DeviceDetailDialogState extends State<DeviceDetailDialog> {
  late final Future<List<Observation>> metrics;

  @override
  void initState() {
    super.initState();
    metrics = widget.controller.api.contextDeviceMetrics(
        widget.device.id, widget.controller.infrastructure);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.controller, builder: (context, _) => _content(context));

  Widget _content(BuildContext context) {
    final device = widget.controller.snapshot?.devices
            .where((value) => value.id == widget.device.id)
            .firstOrNull ??
        widget.device;
    final liveMetrics = widget.controller.snapshot?.metrics
            .where((o) =>
                device.sourceId != null &&
                o.sourceId == device.sourceId &&
                o.entityId == device.id.split(':').last)
            .toList() ??
        <Observation>[];
    final width = MediaQuery.sizeOf(context).width;
    return Dialog(
      alignment: width >= OipTokens.tablet ? Alignment.centerRight : null,
      insetPadding: EdgeInsets.symmetric(
          horizontal: width < OipTokens.mobile ? 12 : 24, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(OipTokens.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: StatusPill(
                          device.simulated
                              ? context.tr("GERÄTEDETAILS · SIMULATION")
                              : context.tr("GERÄTEDETAILS · API"),
                          color: OipTokens.statusColor(context, 'info'),
                          icon: device.simulated
                              ? Icons.science_outlined
                              : Icons.cloud_done_outlined),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr("Details schließen"),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: OipTokens.s4),
              Text(device.name,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: OipTokens.s1),
              Text(
                  '${deviceKindName(device.kind)} · ${device.location} · ${device.connection}'),
              const SizedBox(height: OipTokens.s4),
              InlineNotice(
                widget.controller.managed
                    ? context.tr("SSH-Abfragen bleiben read-only")
                    : context.tr("Read-only als Standard"),
                widget.controller.managed
                    ? context.tr(
                        "Verbindung und Monitoring werden über die autorisierte Core-Verwaltung eingerichtet. Auf dem Gerät wird nichts installiert oder konfiguriert. Fehlende Messwerte bleiben unbekannt.")
                    : context.tr(
                        "Diese Ansicht verändert weder Gerät noch Adapter. Fehlende Messquellen werden nicht durch Schätzwerte ersetzt."),
                icon: Icons.lock_outline,
              ),
              if (widget.controller.managed &&
                  widget.controller.management != null)
                DeviceConnectionPanel(
                    controller: widget.controller, deviceId: device.id)
              else if (widget.controller.managed)
                InlineNotice(
                  context.tr("Management-Adapter nicht verfügbar"),
                  context.tr(
                      "Der Core antwortet autorisiert, aber dieser Client hat keinen Management-Adapter für Verbindungen und Monitoring."),
                  icon: Icons.lock_outline,
                ),
              const SizedBox(height: OipTokens.s5),
              SectionTitle(context.tr("Fünf unabhängige Statusdimensionen"),
                  'Erreichbarkeit ist kein Nachweis eines gesunden Dienstes.'),
              FactGrid(children: [
                Fact(context.tr("Device Reachability"),
                    context.tr(known(device.health.reachability)),
                    valueColor: OipTokens.statusColor(
                        context, device.health.reachability)),
                Fact(context.tr("VPN Transport"),
                    context.tr(known(device.health.vpn)),
                    valueColor:
                        OipTokens.statusColor(context, device.health.vpn)),
                Fact(context.tr("Agent Availability"),
                    context.tr(known(device.health.agent)),
                    valueColor:
                        OipTokens.statusColor(context, device.health.agent)),
                Fact(context.tr("Service Health"),
                    context.tr(known(device.health.service)),
                    valueColor:
                        OipTokens.statusColor(context, device.health.service)),
                Fact(
                    context.tr("Telemetry Freshness"),
                    widget.controller.connection != 'live'
                        ? context.tr("Veraltet / unbekannt")
                        : context.tr(known(device.health.freshness)),
                    valueColor: widget.controller.connection != 'live'
                        ? OipTokens.statusColor(context, 'degraded')
                        : OipTokens.statusColor(
                            context, device.health.freshness)),
              ]),
              const Divider(),
              SectionTitle(context.tr("Verfügbare Metriken"),
                  'Rust-API · Keine synthetischen Ersatzwerte'),
              FutureBuilder<List<Observation>>(
                future: metrics,
                builder: (context, snapshot) {
                  if (snapshot.hasError && liveMetrics.isEmpty) {
                    return StateMessage(
                      context.tr("Metriken nicht erreichbar"),
                      context.tr("Serververbindung prüfen."),
                      compact: true,
                    );
                  }
                  if (!snapshot.hasData && liveMetrics.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(OipTokens.s4),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final values =
                      liveMetrics.isNotEmpty ? liveMetrics : snapshot.data!;
                  if (values.isEmpty) {
                    return InlineNotice(
                      context.tr("Keine Messquelle angebunden"),
                      context.tr("CPU, GPU und RAM: unbekannt."),
                      icon: Icons.data_exploration_outlined,
                    );
                  }
                  return FactGrid(
                    children: values
                        .map((observation) => Fact(
                              observation.metricId,
                              '${observation.display} ${observation.symbol} · '
                              '${known(observation.quality)} · ${known(observation.freshness)}',
                            ))
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: OipTokens.s4),
              if (widget.controller.managed &&
                  widget.controller.management != null)
                DeviceHistorySection(
                    api: widget.controller.management!, deviceId: device.id)
              else if (widget.controller.managed)
                InlineNotice(
                  context.tr("Management-Adapter nicht verfügbar"),
                  context.tr(
                      "Der Core besitzt den Historienendpunkt, aber dieser Client hat keinen autorisierten Management-Adapter."),
                  icon: Icons.history,
                  color: OipTokens.statusColor(context, 'degraded'),
                )
              else
                InlineNotice(
                  context.tr("Historie noch nicht verfügbar"),
                  context.tr(
                      "Serverseitiger Historienendpunkt noch nicht implementiert. Der Overview zeigt ausschließlich empfangene Sitzungspunkte."),
                  icon: Icons.history,
                  color: OipTokens.statusColor(context, 'degraded'),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.tr("Schließen"))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
