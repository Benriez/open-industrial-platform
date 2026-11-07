import 'package:flutter/material.dart';
import '../app/controller.dart';
import '../design_system/theme.dart';
import '../models/contracts.dart';
import '../widgets/components.dart';
import 'device_onboarding.dart';
import 'device_connection_panel.dart';
import 'device_history.dart';

class DevicesPage extends StatefulWidget {
  final OipController controller;
  const DevicesPage(this.controller, {super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  static const pageSize = 50;
  String search = '', zone = 'Alle', sort = 'Name', status = 'Alle';
  int offset = 0;
  Snapshot? cachedSnapshot;
  String cachedSearch = '', cachedZone = '', cachedSort = '', cachedStatus = '';
  List<Device>? cachedDevices;

  List<Device> _devices(Snapshot snapshot) {
    if (cachedDevices != null &&
        identical(cachedSnapshot, snapshot) &&
        cachedSearch == search &&
        cachedZone == zone &&
        cachedSort == sort &&
        cachedStatus == status) {
      return cachedDevices!;
    }
    final query = search.trim().toLowerCase();
    final devices = snapshot.devices.where((device) {
      final matchesQuery = query.isEmpty ||
          '${device.name} ${device.kind} ${device.location} ${device.connection}'
              .toLowerCase()
              .contains(query);
      final matchesZone = zone == 'Alle' || device.location == zone;
      final matchesStatus = status == 'Alle' ||
          (status == 'Gestört'
              ? device.isFaulted
              : status == 'Agent fehlt'
                  ? device.health.agent == 'unavailable'
                  : status == 'Nicht erreichbar'
                      ? device.health.reachability == 'unreachable' ||
                          device.health.reachability == 'offline'
                      : device.health.reachability == 'reachable');
      return matchesQuery && matchesZone && matchesStatus;
    }).toList();
    devices.sort((a, b) => sort == 'Standort'
        ? a.location.compareTo(b.location).thenCompare(a.name, b.name)
        : a.name.compareTo(b.name));
    cachedSnapshot = snapshot;
    cachedSearch = search;
    cachedZone = zone;
    cachedSort = sort;
    cachedStatus = status;
    return cachedDevices = devices;
  }

  void _update(void Function() change) => setState(() {
        change();
        offset = 0;
      });

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.snapshot!;
    final devices = _devices(snapshot);
    final pageCount = (devices.length / pageSize).ceil();
    final currentOffset = pageCount > 0 && offset >= devices.length
        ? (pageCount - 1) * pageSize
        : offset;
    final visible = devices.skip(currentOffset).take(pageSize).toList();
    final locations = <String>{
      'Alle',
      ...snapshot.devices.map((device) => device.location),
      if (zone != 'Alle') zone,
    }.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Geräte & Dienste',
            'Ein gemeinsames Inventar. Jede Quelle bleibt erkennbar.',
            accent: OipTokens.blue),
        if (widget.controller.managed)
          Padding(
            padding: const EdgeInsets.only(bottom: OipTokens.s4),
            child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                    key: const Key('add-device'),
                    icon: const Icon(Icons.add),
                    label: const Text('Gerät hinzufügen'),
                    onPressed: () =>
                        showDeviceOnboarding(context, widget.controller))),
          ),
        GradientCard(
          accent: OipTokens.blue,
          padding: const EdgeInsets.all(OipTokens.s3),
          child: LayoutBuilder(builder: (context, box) {
            final compact = box.maxWidth < OipTokens.mobile;
            return Wrap(
              spacing: OipTokens.s3,
              runSpacing: OipTokens.s3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: compact ? box.maxWidth : 300,
                  child: TextField(
                    key: const Key('device-search'),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 19),
                      hintText: 'Geräte durchsuchen',
                    ),
                    onChanged: (value) => _update(() => search = value),
                  ),
                ),
                _filter('Standort', zone, locations, compact,
                    (value) => zone = value),
                _filter(
                    'Status',
                    status,
                    const [
                      'Alle',
                      'Erreichbar',
                      'Gestört',
                      'Nicht erreichbar',
                      'Agent fehlt'
                    ],
                    compact,
                    (value) => status = value),
                _filter('Sortieren', sort, const ['Name', 'Standort'], compact,
                    (value) => sort = value),
              ],
            );
          }),
        ),
        const SizedBox(height: OipTokens.s4),
        Row(
          children: [
            Expanded(
              child: Text(
                '${devices.length} von ${snapshot.devices.length} Geräten · ${snapshot.system.simulated && snapshot.devices.every((device) => device.simulated) ? 'Simuliertes Inventar' : 'API-Inventar'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (devices.length > pageSize)
              Text(
                  '${currentOffset + 1}–${(currentOffset + visible.length).clamp(0, devices.length)}',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: OipTokens.s4),
        if (devices.isEmpty)
          StateMessage(
            'Keine Geräte gefunden',
            widget.controller.managed && snapshot.devices.isEmpty
                ? 'Noch kein Gerät registriert. Inventarregistrierung und Monitoring werden getrennt eingerichtet.'
                : 'Suche oder Filter anpassen.',
            icon: Icons.search_off_outlined,
            action: TextButton(
              onPressed: () => _update(() {
                search = '';
                zone = 'Alle';
                status = 'Alle';
              }),
              child: const Text('Filter zurücksetzen'),
            ),
          )
        else
          LayoutBuilder(builder: (context, box) {
            return box.maxWidth >= 850
                ? _DeviceTable(
                    devices: visible,
                    onTap: (device) =>
                        showDevice(context, widget.controller, device),
                  )
                : ResponsiveGrid(
                    minWidth: 275,
                    maxColumns: 3,
                    children: visible
                        .map((device) => DeviceCard(device,
                            onTap: () =>
                                showDevice(context, widget.controller, device)))
                        .toList(),
                  );
          }),
        if (devices.length > pageSize)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Seite ${currentOffset ~/ pageSize + 1} / $pageCount',
                  style: Theme.of(context).textTheme.bodySmall),
              IconButton(
                tooltip: 'Vorherige Geräte',
                onPressed: currentOffset == 0
                    ? null
                    : () => setState(() => offset = currentOffset - pageSize),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Nächste Geräte',
                onPressed: currentOffset + pageSize >= devices.length
                    ? null
                    : () => setState(() => offset = currentOffset + pageSize),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }

  Widget _filter(String label, String value, List<String> values, bool compact,
          void Function(String) change) =>
      SizedBox(
        width: compact ? double.infinity : 210,
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          key: Key('filter-$label'),
          value: value,
          decoration: const InputDecoration(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 9)),
          borderRadius: BorderRadius.circular(OipTokens.radiusSm),
          items: values
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: Text('$label: $item',
                        style: const TextStyle(fontSize: 12)),
                  ))
              .toList(),
          onChanged: (item) {
            if (item != null) _update(() => change(item));
          },
        ),
      );
}

extension on int {
  int thenCompare(String a, String b) => this != 0 ? this : a.compareTo(b);
}

class _DeviceTable extends StatelessWidget {
  final List<Device> devices;
  final void Function(Device) onTap;
  const _DeviceTable({required this.devices, required this.onTap});

  @override
  Widget build(BuildContext context) => Panel(
        padding: EdgeInsets.zero,
        accent: OipTokens.blue,
        child: Column(
          children: [
            _row(
              context,
              [
                _CellText('GERÄT', 3),
                _CellText('STANDORT / VERBINDUNG', 2),
                _CellText('ERREICHBARKEIT', 2),
                _CellText('DATENQUALITÄT', 2),
              ],
              header: true,
            ),
            const Divider(height: 1),
            ...devices.map((device) => Semantics(
                  button: true,
                  label: 'Details ${device.name}',
                  child: InkWell(
                    key: Key('device-${device.id}'),
                    onTap: () => onTap(device),
                    child: _row(context, [
                      _CellWidget(
                        3,
                        Row(children: [
                          Icon(deviceIcon(device.kind),
                              size: 18,
                              color: OipTokens.deviceCategoryColor(
                                  context, device.kind)),
                          const SizedBox(width: OipTokens.s3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(device.name,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.titleSmall),
                                Text(device.kind,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ]),
                      ),
                      _CellWidget(
                        2,
                        Text('${device.location} · ${device.connection}',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                      _CellWidget(2, _StatusText(device.health.reachability)),
                      _CellWidget(2, _StatusText(device.health.freshness)),
                    ]),
                  ),
                )),
          ],
        ),
      );

  Widget _row(BuildContext context, List<_Cell> cells, {bool header = false}) =>
      Padding(
        padding: EdgeInsets.symmetric(
            horizontal: OipTokens.s4,
            vertical: header ? OipTokens.s3 : OipTokens.s4),
        child: Row(
          children: [
            for (final cell in cells)
              Expanded(
                flex: cell.flex,
                child: Padding(
                  padding: const EdgeInsets.only(right: OipTokens.s3),
                  child: cell.child,
                ),
              ),
          ],
        ),
      );
}

abstract class _Cell {
  final int flex;
  final Widget child;
  const _Cell(this.flex, this.child);
}

class _CellText extends _Cell {
  _CellText(String text, int flex)
      : super(
            flex,
            Text(text,
                style: const TextStyle(fontSize: 10, letterSpacing: .7)));
}

class _CellWidget extends _Cell {
  const _CellWidget(super.flex, super.child);
}

class _StatusText extends StatelessWidget {
  final String status;
  const _StatusText(this.status);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          StatusDot(status),
          const SizedBox(width: OipTokens.s2),
          Expanded(
            child: Text(known(status),
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      );
}

class DeviceCard extends StatelessWidget {
  final Device device;
  final VoidCallback onTap;
  const DeviceCard(this.device, {super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = device.health.reachability;
    return Semantics(
      button: true,
      label: 'Details ${device.name}',
      child: InkWell(
        key: Key('device-${device.id}'),
        borderRadius: BorderRadius.circular(OipTokens.radius),
        onTap: onTap,
        child: Panel(
          accent: OipTokens.deviceCategoryColor(context, device.kind),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(OipTokens.s3),
                    decoration: BoxDecoration(
                      color: OipTokens.deviceCategoryColor(context, device.kind)
                          .withOpacity(.13),
                      borderRadius: BorderRadius.circular(OipTokens.radiusSm),
                    ),
                    child: Icon(deviceIcon(device.kind),
                        color:
                            OipTokens.deviceCategoryColor(context, device.kind),
                        size: 21),
                  ),
                  const SizedBox(width: OipTokens.s3),
                  Expanded(
                    child: Text(device.name,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  const Icon(Icons.chevron_right, size: 17),
                ],
              ),
              const SizedBox(height: OipTokens.s3),
              Wrap(
                spacing: OipTokens.s2,
                runSpacing: OipTokens.s2,
                children: [
                  StatusPill(device.simulated ? 'SIMULATION' : 'API-DATEN',
                      color: OipTokens.statusColor(context, 'info'),
                      icon: device.simulated
                          ? Icons.science_outlined
                          : Icons.cloud_done_outlined),
                  StatusPill(known(status),
                      color: OipTokens.statusColor(context, status),
                      showDot: true),
                  if (device.isFaulted &&
                      status != 'offline' &&
                      status != 'unreachable')
                    StatusPill('Gestört',
                        color: OipTokens.statusColor(context, 'degraded'),
                        icon: Icons.warning_amber),
                ],
              ),
              const SizedBox(height: OipTokens.s3),
              Text('${device.kind} · ${device.location}'),
              const SizedBox(height: OipTokens.s1),
              Wrap(
                spacing: OipTokens.s2,
                children: [
                  Text(device.connection,
                      style: Theme.of(context).textTheme.bodySmall),
                  Text('Daten: ${known(device.health.freshness)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: OipTokens.statusColor(
                              context, device.health.freshness))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
  late final int contextRevision = widget.controller.contextRevision;
  void contextChanged() {
    if (mounted && widget.controller.contextRevision != contextRevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(contextChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(contextChanged);
    metrics = widget.controller.api.deviceMetrics(widget.device.id);
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
                o.entityId ==
                    (widget.controller.managed
                        ? device.id
                        : device.id.split(':').last))
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
                              ? 'GERÄTEDETAILS · SIMULATION'
                              : 'GERÄTEDETAILS · API',
                          color: OipTokens.statusColor(context, 'info'),
                          icon: device.simulated
                              ? Icons.science_outlined
                              : Icons.cloud_done_outlined),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Details schließen',
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
                  '${device.kind} · ${device.location} · ${device.connection}'),
              const SizedBox(height: OipTokens.s4),
              InlineNotice(
                widget.controller.managed
                    ? 'SSH-Abfragen bleiben read-only'
                    : 'Read-only als Standard',
                widget.controller.managed
                    ? 'Verbindung und Monitoring werden über die autorisierte Core-Verwaltung eingerichtet. Auf dem Gerät wird nichts installiert oder konfiguriert. Fehlende Messwerte bleiben unbekannt.'
                    : 'Diese Ansicht verändert weder Gerät noch Adapter. Fehlende Messquellen werden nicht durch Schätzwerte ersetzt.',
                icon: Icons.lock_outline,
              ),
              if (widget.controller.managed)
                DeviceConnectionPanel(
                    controller: widget.controller, deviceId: device.id),
              const SizedBox(height: OipTokens.s5),
              const SectionTitle('Fünf unabhängige Statusdimensionen',
                  'Erreichbarkeit ist kein Nachweis eines gesunden Dienstes.'),
              FactGrid(children: [
                Fact('Device Reachability', known(device.health.reachability),
                    valueColor: OipTokens.statusColor(
                        context, device.health.reachability)),
                Fact('VPN Transport', known(device.health.vpn),
                    valueColor:
                        OipTokens.statusColor(context, device.health.vpn)),
                Fact('Agent Availability', known(device.health.agent),
                    valueColor:
                        OipTokens.statusColor(context, device.health.agent)),
                Fact('Service Health', known(device.health.service),
                    valueColor:
                        OipTokens.statusColor(context, device.health.service)),
                Fact(
                    'Telemetry Freshness',
                    widget.controller.connection != 'live'
                        ? 'Veraltet / unbekannt'
                        : known(device.health.freshness),
                    valueColor: widget.controller.connection != 'live'
                        ? OipTokens.statusColor(context, 'degraded')
                        : OipTokens.statusColor(
                            context, device.health.freshness)),
              ]),
              const Divider(),
              const SectionTitle('Verfügbare Metriken',
                  'Rust-API · Keine synthetischen Ersatzwerte'),
              FutureBuilder<List<Observation>>(
                future: metrics,
                builder: (context, snapshot) {
                  if (snapshot.hasError && liveMetrics.isEmpty) {
                    return const StateMessage(
                      'Metriken nicht erreichbar',
                      'Serververbindung prüfen.',
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
                    return const InlineNotice(
                      'Keine Messquelle angebunden',
                      'CPU, GPU und RAM: unbekannt.',
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
              if (widget.controller.managed)
                DeviceHistorySection(
                    api: widget.controller.management!,
                    deviceId: device.id)
              else
                InlineNotice(
                  'Historie noch nicht verfügbar',
                  'Serverseitiger Historienendpunkt noch nicht implementiert. Der Overview zeigt ausschließlich empfangene Sitzungspunkte.',
                  icon: Icons.history,
                  color: OipTokens.statusColor(context, 'degraded'),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Schließen')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
