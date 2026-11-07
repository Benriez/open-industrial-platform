import 'package:flutter/material.dart';
import '../app/controller.dart';
import '../design_system/theme.dart';
import '../models/contracts.dart';
import '../widgets/components.dart';
import '../widgets/trend.dart';
import 'devices.dart';

class OverviewPage extends StatelessWidget {
  final OipController controller;
  final void Function(int) navigate;
  const OverviewPage(this.controller, this.navigate, {super.key});

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot!;
    final temperature = snapshot.primaryTemperature;
    final alarm = snapshot.hasAlarm(deviceId: 'M-01');
    final zoneCount = snapshot.devices.map((device) => device.location).toSet();
    final reachable = snapshot.devices
        .where((device) => device.health.reachability == 'reachable')
        .length;
    final focus = _focusDevices(snapshot.devices);
    final simulated = snapshot.system.simulated;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: OipTokens.s4,
          runSpacing: OipTokens.s3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('COMMAND CENTER',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: OipTokens.cyan)),
                const SizedBox(height: OipTokens.s1),
                Text('Deine Infrastruktur. Ein Bild.',
                    style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: OipTokens.s2),
                Text('Lokal beobachten. Zusammenhänge verstehen.',
                    style: TextStyle(color: OipTokens.muted(context))),
              ],
            ),
            StatusPill(
              simulated ? 'LOKALE SIMULATION' : 'BACKEND-DATEN',
              color: OipTokens.statusColor(context, 'info'),
              icon: simulated
                  ? Icons.science_outlined
                  : Icons.cloud_done_outlined,
            ),
          ],
        ),
        const SizedBox(height: OipTokens.s4),
        GradientCard(
          accent: OipTokens.violet,
          padding: const EdgeInsets.symmetric(
              horizontal: OipTokens.s4, vertical: OipTokens.s3),
          child: Wrap(
            spacing: OipTokens.s5,
            runSpacing: OipTokens.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Tooltip(
                message: 'Liveness: ${_flag(snapshot.core.live)} · '
                    'Readiness: ${_flag(snapshot.core.ready)} · '
                    'Persistenz: ${_flag(snapshot.core.persistenceHealthy)}',
                child: Semantics(
                  label:
                      'Core-Zustand: ${controller.connection == 'live' ? _coreLabel(snapshot.core.lifecycle) : 'Status veraltet'}',
                  child: _ribbonValue(
                      context,
                      'CORE',
                      controller.connection == 'live'
                          ? _coreLabel(snapshot.core.lifecycle)
                          : 'Status veraltet',
                      controller.connection == 'live'
                          ? _coreTone(snapshot.core.lifecycle)
                          : 'stale'),
                ),
              ),
              _ribbonValue(context, 'OPC UA SOURCE',
                  known(snapshot.system.opcua), snapshot.system.opcua),
              _ribbonValue(
                  context,
                  'SUBSCRIPTION',
                  known(snapshot.system.subscription),
                  snapshot.system.subscription),
              _ribbonValue(context, 'NETWORK', known(snapshot.system.network),
                  snapshot.system.network),
              _ribbonValue(
                  context,
                  'DATENFRISCHE',
                  controller.stale ? 'Veraltet / unbekannt' : 'Live-Snapshot',
                  controller.stale ? 'stale' : 'fresh'),
              Text('Empfangen: ${timestamp(snapshot.system.lastReceivedMs)}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(height: OipTokens.s4),
        ResponsiveGrid(
          minWidth: 205,
          children: [
            MetricCard(
                'Erfasste Geräte',
                '${snapshot.devices.length}',
                'Rust-Inventar · ${zoneCount.length} ${controller.managed ? 'Standortangaben' : 'Netzwerkzonen'}',
                Icons.dns_outlined,
                color: OipTokens.blue),
            MetricCard(
                'Erreichbare Geräte',
                '$reachable',
                '${snapshot.devices.where((d) => d.isFaulted).length} gestört · ${simulated ? 'simulierte Zustände' : 'Backend-Zustände'}',
                Icons.hub_outlined,
                color: OipTokens.cyan),
            MetricCard(
                'Aktive Hinweise',
                controller.managed
                    ? 'Nicht ausgewertet'
                    : '${snapshot.incidents.length}',
                controller.managed
                    ? 'Keine Incident-Auswertung in dieser Projektion'
                    : simulated
                        ? 'Deterministische Demoszenarien'
                        : 'Vom Backend gelieferte Hinweise',
                Icons.radar,
                color: controller.managed
                    ? OipTokens.muted(context)
                    : snapshot.incidents.isEmpty
                        ? OipTokens.lime
                        : OipTokens.statusColor(context, 'degraded')),
            MetricCard(
              'Temperatur M-01',
              temperature == null
                  ? '—'
                  : '${temperature.display} ${temperature.symbol}',
              controller.stale
                  ? 'Veraltet · letzter bekannter Wert'
                  : alarm
                      ? 'Alarm vom OPC-UA-Datenmodell gemeldet'
                      : 'OPC UA → SQLite → SSE',
              Icons.thermostat_outlined,
              color: alarm
                  ? OipTokens.statusColor(context, 'alarm')
                  : temperature == null
                      ? OipTokens.muted(context)
                      : OipTokens.violet,
            ),
          ],
        ),
        const SizedBox(height: OipTokens.s4),
        LayoutBuilder(builder: (context, box) {
          final chart = ChartContainer(
            title: 'Live-Telemetrie / Maschinensignal',
            subtitle: 'Empfangene OPC-UA-Werte · keine interpolierten Lücken',
            accent: OipTokens.cyan,
            action: StatusPill(
              simulated ? 'SIM' : 'API',
              color: OipTokens.statusColor(context, 'info'),
              icon: simulated
                  ? Icons.science_outlined
                  : Icons.cloud_done_outlined,
            ),
            child: RepaintBoundary(child: TrendChart(controller.history)),
          );
          final events = SectionContainer(
            title: 'Aktive Incidents',
            subtitle: 'Evidenz vor Annahmen · Auswahl öffnet Diagnose',
            accent: OipTokens.pink,
            icon: Icons.radar,
            action: IconButton(
              tooltip: 'Diagnose öffnen',
              onPressed: () => navigate(4),
              icon: const Icon(Icons.arrow_outward, size: 18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (snapshot.incidents.isEmpty)
                  InlineNotice(
                    controller.managed
                        ? 'Incidents hier nicht ausgewertet'
                        : 'Keine aktiven Incidents',
                    controller.managed
                        ? 'Die autorisierte Live-Projektion enthält keine Incident-Auswertung. Das ist kein Nachweis eines gesunden Geräts.'
                        : 'Messwerte prüfen; fehlende Befunde werden nicht ergänzt.',
                    icon: controller.managed
                        ? Icons.help_outline
                        : Icons.verified_outlined,
                  ),
                ...snapshot.incidents.take(3).map((incident) => Padding(
                      padding: const EdgeInsets.only(bottom: OipTokens.s3),
                      child: _IncidentSummary(
                        incident: incident,
                        critical:
                            snapshot.hasAlarm(deviceId: incident.deviceId),
                      ),
                    )),
                const Divider(),
                Fact('OPC-UA-Subscription',
                    OipTokens.statusLabel(snapshot.system.subscription)),
                Fact(
                  'Letzte Diagnose',
                  snapshot.incidents.isEmpty
                      ? 'Keine Diagnose erzeugt'
                      : '${snapshot.incidents.first.title} · ${snapshot.incidents.first.simulated ? 'Simulation' : 'Backend'}',
                ),
              ],
            ),
          );
          return box.maxWidth >= OipTokens.desktop
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: chart),
                  const SizedBox(width: OipTokens.s4),
                  Expanded(flex: 2, child: events),
                ])
              : Column(children: [
                  chart,
                  const SizedBox(height: OipTokens.s4),
                  events,
                ]);
        }),
        const SizedBox(height: OipTokens.s6),
        SectionTitle(
          'System & Datenpfad',
          'Fehlende Telemetrie bleibt ausdrücklich unbekannt.',
          accent: OipTokens.yellow,
          action: TextButton(
              onPressed: () => navigate(3),
              child: const Text('OPC UA öffnen →')),
        ),
        ResponsiveGrid(
          minWidth: 205,
          children: [
            MetricCard(
                'CPU-Auslastung',
                snapshot.system.cpu == null ? '—' : '${snapshot.system.cpu} %',
                snapshot.system.cpu == null
                    ? 'Unbekannt · kein Host-Collector'
                    : 'Wert aus dem Systemstatus geliefert',
                Icons.memory,
                color: OipTokens.blue),
            MetricCard(
                'GPU-Auslastung',
                snapshot.system.gpu == null ? '—' : '${snapshot.system.gpu} %',
                snapshot.system.gpu == null
                    ? 'Unbekannt · kein GPU-Exporter'
                    : 'Wert aus dem Systemstatus geliefert',
                Icons.developer_board_outlined,
                color: OipTokens.violet),
            MetricCard(
                'RAM-Verbrauch',
                snapshot.system.ram == null ? '—' : '${snapshot.system.ram} %',
                snapshot.system.ram == null
                    ? 'Unbekannt · keine Messquelle'
                    : 'Wert aus dem Systemstatus geliefert',
                Icons.storage_outlined,
                color: OipTokens.pink),
            MetricCard(
                'Persistierte Werte',
                snapshot.system.persisted?.toString() ?? 'Nicht freigegeben',
                'SQLite · Netzwerkstatus: ${known(snapshot.system.network)}',
                Icons.data_object,
                color: OipTokens.lime),
          ],
        ),
        const SizedBox(height: OipTokens.s6),
        SectionTitle(
          'Geräte im Fokus',
          'Identität, Verbindung und Datenqualität',
          accent: OipTokens.blue,
          action: TextButton(
              onPressed: () => navigate(1), child: const Text('Alle Geräte →')),
        ),
        ResponsiveGrid(
          minWidth: 270,
          maxColumns: 3,
          children: focus
              .map((device) => DeviceCard(device,
                  onTap: () => showDevice(context, controller, device)))
              .toList(),
        ),
      ],
    );
  }

  Widget _ribbonValue(
          BuildContext context, String label, String value, String status) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        StatusDot(status),
        const SizedBox(width: OipTokens.s2),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ]);

  List<Device> _focusDevices(List<Device> devices) {
    final result = <Device>[];
    void add(Iterable<Device> candidates) {
      for (final device in candidates) {
        if (result.length >= 3) break;
        if (!result.any((existing) => existing.id == device.id)) {
          result.add(device);
        }
      }
    }

    add(devices.where((device) => device.isFaulted));
    add(devices.where((device) => device.id == 'M-01'));
    add(devices);
    return result;
  }
}

class _IncidentSummary extends StatelessWidget {
  final Incident incident;
  final bool critical;
  const _IncidentSummary({required this.incident, required this.critical});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(OipTokens.s3),
        decoration: BoxDecoration(
          color: OipTokens.pink.withOpacity(.07),
          borderRadius: BorderRadius.circular(OipTokens.radiusSm),
          border: Border.all(color: OipTokens.pink.withOpacity(.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: StatusDot(critical ? 'alarm' : 'degraded'),
            ),
            const SizedBox(width: OipTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(incident.title,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: OipTokens.s1),
                  Text('${incident.category} · ${incident.deviceId}',
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(
                      'Zeitpunkt nicht vom API-Vertrag geliefert · ${incident.simulated ? 'Simulation' : 'Backend'}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );
}

String _flag(bool? value) => value == null
    ? 'Unbekannt'
    : value
        ? 'Ja'
        : 'Nein';
String _coreLabel(CoreLifecycle state) => switch (state) {
      CoreLifecycle.initializing => 'Initialisierung',
      CoreLifecycle.ready => 'Bereit',
      CoreLifecycle.degraded => 'Degradiert',
      CoreLifecycle.stopping => 'Stoppt',
      CoreLifecycle.stopped => 'Gestoppt',
      CoreLifecycle.failed => 'Fehlgeschlagen',
      CoreLifecycle.unknown => 'Unbekannt',
    };
String _coreTone(CoreLifecycle state) => switch (state) {
      CoreLifecycle.ready => 'connected',
      CoreLifecycle.degraded => 'degraded',
      CoreLifecycle.initializing || CoreLifecycle.stopping => 'waiting',
      CoreLifecycle.stopped => 'offline',
      CoreLifecycle.failed => 'critical',
      CoreLifecycle.unknown => 'unknown',
    };
