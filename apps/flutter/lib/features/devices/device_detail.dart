import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import '../../models/infrastructure.dart';
import '../../services/api.dart';
import '../../widgets/components.dart';
import '../../widgets/device_kind.dart';
import '../../widgets/workstation.dart';
import '../device_connection_panel.dart';
import '../device_history.dart';
import 'device_administration.dart';
import 'device_inventory.dart';
import 'devices_layout.dart';

class DeviceEngineeringWorkspace extends StatelessWidget {
  final Device? device;
  final Snapshot snapshot;
  final List<SourceInfo> sources;
  final List<Observation> metrics;
  final bool loading;
  final Object? error;
  final String connection;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  final void Function(int) navigate;
  final InfrastructureContext? infrastructure;

  /// The inventory record of the selected device.
  ///
  /// The Core holds the identity of a device in its inventory: the
  /// manufacturer, the model, the firmware and the serial number. The
  /// summary of a device does not carry them, so the workspace asks the
  /// inventory for them — and names them as unavailable when the Core holds
  /// no record.
  final InventoryDevice? inventoryDevice;

  /// The controller is only needed for the authorized management surfaces:
  /// the monitoring measurements and the persisted observation history.
  final OipController? controller;
  const DeviceEngineeringWorkspace({
    super.key,
    required this.device,
    required this.snapshot,
    required this.sources,
    required this.metrics,
    required this.loading,
    required this.error,
    required this.connection,
    required this.onRetry,
    required this.onClose,
    required this.navigate,
    this.infrastructure,
    this.inventoryDevice,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    if (device == null) {
      return const WorkstationPanel(
        key: Key('device-engineering-workspace'),
        accent: OipTokens.blue,
        padding: EdgeInsets.all(DevicesLayout.panelPadding),
        child: Align(
          alignment: Alignment.topLeft,
          child: WorkstationNote(
            'Gerät für die technische Untersuchung auswählen',
            'Explorer, Engineering Workspace, Inspector und Related Activity verwenden anschließend dieselbe Device-ID. Es werden keine vorherigen Messwerte übernommen.',
            icon: Icons.dns_outlined,
          ),
        ),
      );
    }
    final current = device!;
    return WorkstationPanel(
      key: const Key('device-engineering-workspace'),
      accent: OipTokens.blue,
      padding: const EdgeInsets.fromLTRB(
          DevicesLayout.panelPadding, 10, DevicesLayout.panelPadding, 8),
      child: DefaultTabController(
        length: 3,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ENGINEERING WORKSPACE',
                        style: WorkstationTokens.eyebrow(context,
                            color: OipTokens.blue)),
                    Text('${current.name} · ${current.id}',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                  ]),
            ),
            if (current.simulated)
              const StatusPill('SIMULATED', icon: Icons.science_outlined),
            if (error != null) ...[
              StatusPill(
                'METRIKEN NICHT ERREICHBAR',
                color: OipTokens.statusColor(context, 'degraded'),
                icon: Icons.error_outline,
              ),
              // A failed DeviceDetail request must be visible and recoverable
              // without scrolling through the identity grid first.
              IconButton(
                key: const Key('device-metrics-retry-header'),
                tooltip: 'DeviceDetail erneut laden',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
            IconButton(
              key: const Key('device-detail-close'),
              tooltip: 'Details schließen',
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 18),
            ),
          ]),
          const TabBar(
            tabs: [
              Tab(text: 'Engineering'),
              Tab(text: 'Telemetry'),
              Tab(text: 'Related Events'),
            ],
          ),
          Expanded(
            child: TabBarView(children: [
              _engineering(context, current),
              _telemetry(context, current),
              _events(context, current),
            ]),
          ),
        ]),
      ),
    );
  }

  /// The identity facts of the device as the Core holds them.
  ///
  /// A fact that the Core does not hold is named as unavailable: the panel
  /// never invents an identity and never shows a placeholder as a fact.
  String _identity(InventoryDevice? record, String first, [String? second]) {
    final metadata = record?.metadata;
    if (metadata == null) return 'Nicht verfügbar';
    final parts = [first, second]
        .whereType<String>()
        .map((key) => metadata[key])
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toList();
    return parts.isEmpty ? 'Nicht verfügbar' : parts.join(' / ');
  }

  /// The note of the device as the Core holds it.
  ///
  /// The inventory carries an optional note: the free text that the operator
  /// wrote about the device — for example the honest limit of its capability
  /// (a bridge that is read-only without an application token). The note
  /// belongs where the operator looks at the device; a note that the Core does
  /// not hold is named as unavailable, and the panel never invents one.
  String _note(InventoryDevice? record) {
    final metadata = record?.metadata;
    if (metadata == null) return 'Nicht verfügbar';
    final value = metadata['notes'];
    if (value is! String || value.trim().isEmpty) return 'Nicht verfügbar';
    return value.trim();
  }

  Widget _engineering(BuildContext context, Device device) {
    final source =
        sources.where((item) => item.id == device.sourceId).firstOrNull;
    final observations = metrics;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelLabel('Identity & Registry',
            trailing:
                Text('READ-ONLY', style: WorkstationTokens.eyebrow(context))),
        KeyValueGrid(children: [
          KeyValue('DEVICE ID', device.id),
          KeyValue('DISPLAY NAME', device.name),
          KeyValue('DEVICE TYPE', deviceKindName(device.kind)),
          KeyValue('SOURCE ID', device.sourceId ?? 'Nicht verfügbar'),
          KeyValue('REGISTRY LOCATION', device.location),
          KeyValue('REGISTRY CONNECTION TYPE', device.connection),
          KeyValue('MANUFACTURER / MODEL', _identity(inventoryDevice, 'manufacturer',
              'model')),
          KeyValue('FIRMWARE / OS',
              _identity(inventoryDevice, 'operating_system')),
          KeyValue('SERIAL / BRIDGE-ID',
              _identity(inventoryDevice, 'serial_number')),
          KeyValue('MAC / IP-ADRESSE', _identity(inventoryDevice, 'mac_address',
              'ip_address')),
          if (infrastructure?.ready == true) ...[
            KeyValue('ORGANIZATION',
                infrastructure!.hierarchy.organizationName(infrastructure!.devicePlacement(device)?.organizationId)),
            KeyValue('INFRASTRUCTURE',
                infrastructure!.hierarchy.infrastructureName(infrastructure!.devicePlacement(device)?.infrastructureId)),
            KeyValue('SITE',
                infrastructure!.hierarchy.siteName(infrastructure!.devicePlacement(device)?.siteId)),
          ] else
            const KeyValue('ORGANIZATION / INFRASTRUCTURE / SITE',
                'Nicht im autorisierten v1-Vertrag verfügbar'),
          const KeyValue('INTERFACE TYPE',
              'Nicht separat verfügbar; Registry Connection Type oben'),
        ]),
        // The note of the device is a free text, so it stands under the grid
        // and takes the whole width of the panel.
        KeyValue('NOTE', _note(inventoryDevice),
            key: const Key('device-identity-note'), mono: false),
        const Hairline(vertical: 4),
        const PanelLabel('Observation & Telemetry'),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (error != null)
          const WorkstationNote(
            'Metriken nicht erreichbar',
            'Der DeviceDetail-Request ist fehlgeschlagen. Frühere oder fremde Messwerte werden nicht angezeigt.',
            icon: Icons.error_outline,
            color: OipTokens.yellow,
          )
        else if (observations.isEmpty)
          const WorkstationNote(
            'Keine Telemetrie für dieses Gerät verfügbar',
            'DeviceDetail enthält keine Observations. Kein Ersatzwert, kein 0 % und kein künstlicher Chart.',
            icon: Icons.sensors_off_outlined,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: observations
                .take(3)
                .map((item) => _metricChip(context, item))
                .toList(),
          ),
        if (error != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('device-metrics-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Erneut versuchen'),
            ),
          ),
        if (controller?.management != null && controller!.managed) ...[
          const Hairline(vertical: 4),
          const PanelLabel('Connection & Monitoring'),
          DeviceConnectionPanel(
              controller: controller!, deviceId: device.id),
          const Hairline(vertical: 4),
          const PanelLabel('Persistierte Messhistorie'),
          DeviceHistorySection(
              api: controller!.management!, deviceId: device.id),
        ],
        const Hairline(vertical: 4),
        const PanelLabel('Connectivity Evidence'),
        KeyValueGrid(children: [
          KeyValue('REGISTRY CONNECTION TYPE', device.connection),
          KeyValue('REPORTED REACHABILITY',
              '${known(device.health.reachability)} · ${device.simulated ? 'SIMULATED / REPORTED' : 'REPORTED'}'),
          KeyValue(
              'OBSERVED SOURCE CONNECTION',
              source == null
                  ? 'Unbekannt / keine Source'
                  : known(source.connection)),
          const KeyValue('ACTUAL PROBE RESULT',
              'Unbekannt · kein aktiver Probe ausgeführt'),
        ]),
        const Hairline(vertical: 4),
        Row(children: [
          Expanded(
            child: Text('Fünf unabhängige Statusdimensionen',
                style: WorkstationTokens.eyebrow(context)),
          ),
          Text('REPORTED', style: WorkstationTokens.eyebrow(context)),
        ]),
        KeyValueGrid(children: [
          KeyValue('DEVICE REACHABILITY', known(device.health.reachability),
              color:
                  OipTokens.statusColor(context, device.health.reachability)),
          KeyValue('VPN TRANSPORT', known(device.health.vpn),
              color: OipTokens.statusColor(context, device.health.vpn)),
          KeyValue('AGENT AVAILABILITY', known(device.health.agent),
              color: OipTokens.statusColor(context, device.health.agent)),
          KeyValue('SERVICE HEALTH', known(device.health.service),
              color: OipTokens.statusColor(context, device.health.service)),
          KeyValue(
              'TELEMETRY FRESHNESS',
              connection == 'live'
                  ? known(device.health.freshness)
                  : 'Veraltet / unbekannt',
              color: connection == 'live'
                  ? OipTokens.statusColor(context, device.health.freshness)
                  : OipTokens.statusColor(context, 'degraded')),
        ]),
        const Hairline(vertical: 4),
        const PanelLabel('Zustandsdimensionen getrennt'),
        KeyValueGrid(children: [
          KeyValue(
              'SOURCE HEALTH',
              source == null
                  ? 'Unbekannt'
                  : '${known(source.connection)} · ${known(source.service)}'),
          KeyValue(
              'DEVICE TELEMETRY FRESHNESS',
              observations.isEmpty
                  ? known(device.health.freshness)
                  : known(deviceObservedFreshness(snapshot, device))),
          KeyValue(
              'OBSERVATION QUALITY',
              observations.isEmpty
                  ? 'Unbekannt'
                  : deviceObservedQuality(snapshot, device).toUpperCase()),
          KeyValue('NETWORK REACHABILITY',
              '${known(device.health.reachability)} · REPORTED, nicht gemessen'),
          KeyValue('DIAGNOSTIC FINDINGS',
              '${snapshot.incidents.where((item) => item.deviceId == device.id).length} exakt zugeordnet'),
        ]),
        const SizedBox(height: 6),
        const WorkstationNote(
          'Keine Gesundheitsableitung',
          'Ein Source-Reconnect beweist nicht, dass jedes zugeordnete Gerät vollständig funktioniert. Registry Presence, Telemetrie, Reachability und Findings bleiben getrennt.',
          icon: Icons.fact_check_outlined,
        ),
      ]),
    );
  }

  Widget _metricChip(BuildContext context, Observation item) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: WorkstationTokens.well(context),
          border: Border.all(color: WorkstationTokens.hairline(context)),
          borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
        ),
        child: Text(
          '${item.metricId}  ${item.display} ${item.symbol} · '
          '${known(item.quality)} · ${known(item.freshness)}',
          style: WorkstationTokens.mono(context, size: 10.5),
        ),
      );

  Widget _telemetry(BuildContext context, Device device) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return const Center(
        child: WorkstationNote(
          'Metriken nicht erreichbar',
          'Der ausgewählte DeviceDetail-Umfang konnte nicht geladen werden.',
          icon: Icons.error_outline,
          color: OipTokens.yellow,
        ),
      );
    }
    if (metrics.isEmpty) {
      return const Center(
        child: WorkstationNote(
          'Keine Telemetrie für dieses Gerät verfügbar',
          'Keine Observations im autorisierten DeviceDetail. Frühere Geräte- oder Source-Werte werden nicht untergeschoben.',
          icon: Icons.sensors_off_outlined,
        ),
      );
    }
    return ListView.builder(
      itemCount: metrics.length,
      itemBuilder: (context, index) {
        final item = metrics[index];
        return Container(
          key: Key('device-observation-${item.metricId}'),
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: WorkstationTokens.well(context),
            border: Border.all(color: WorkstationTokens.hairline(context)),
            borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${item.entityId} · ${item.metricId}',
                style: Theme.of(context).textTheme.titleSmall),
            Text('${item.display} ${item.symbol}',
                style: Theme.of(context).textTheme.headlineSmall),
            KeyValueGrid(children: [
              KeyValue('QUALITÄT / FRESHNESS',
                  '${known(item.quality)} · ${known(item.freshness)}'),
              KeyValue('DATENHERKUNFT',
                  '${item.simulated ? 'SIMULATED · ' : ''}OBSERVED · ${item.sourceId ?? 'Source unbekannt'}'),
              KeyValue('SOURCE TIMESTAMP', timestamp(item.sourceMs)),
              KeyValue('SERVER TIMESTAMP', timestamp(item.serverMs)),
              KeyValue('RECEIVE TIMESTAMP', timestamp(item.receivedMs)),
              KeyValue('STATUS / COLLECTION ERROR',
                  '${item.statusCode ?? 'Nicht verfügbar'} · ${item.collectionError ?? 'Kein Fehler geliefert'}'),
            ]),
          ]),
        );
      },
    );
  }

  Widget _events(BuildContext context, Device device) {
    final incidents =
        snapshot.incidents.where((item) => item.deviceId == device.id).toList();
    final sourceEvents = snapshot.recentEvents
        .where((item) =>
            device.sourceId != null && item.sourceId == device.sourceId)
        .toList();
    if (incidents.isEmpty && sourceEvents.isEmpty) {
      return const Center(
        child: WorkstationNote(
          'Keine zuordenbaren Ereignisse',
          'Weder eine exakte Device-ID- noch eine Source-ID-Beziehung ist im aktuellen Ereignisfenster vorhanden.',
          icon: Icons.event_busy_outlined,
        ),
      );
    }
    return ListView(children: [
      ...incidents.map((incident) => ListTile(
            key: Key('device-finding-${incident.id}'),
            dense: true,
            leading: const Icon(Icons.radar, size: 17),
            title: Text(incident.title),
            subtitle: Text(
                '${incident.id} · exakte Device-ID · ${incident.simulated ? 'SIMULATED' : 'REPORTED'} · keine Severity/Kausalität abgeleitet'),
            trailing: const Icon(Icons.arrow_outward, size: 16),
            onTap: () => navigate(4),
          )),
      ...sourceEvents.map((event) => ListTile(
            key: Key(
                'device-source-event-${event.id ?? '${event.kind}-${event.sequence ?? event.atMs}'}'),
            dense: true,
            leading: const Icon(Icons.account_tree_outlined, size: 17),
            title: Text(event.kind),
            subtitle: Text(
                '${event.id ?? 'Source/Sequenz ${event.sequence ?? 'unbekannt'}'} · ${event.sourceId} · ${timestamp(event.atMs ?? event.gapEndedMs)}\nSource-Ereignis, nicht automatisch ein Device-Incident${event.reason == null ? '' : ' · ${event.reason}'}'),
            trailing: const Icon(Icons.arrow_outward, size: 16),
            onTap: () => navigate(4),
          )),
    ]);
  }
}

class DeviceContextInspector extends StatelessWidget {
  final Device? device;
  final Snapshot snapshot;
  final List<SourceInfo> sources;
  final List<Observation> metrics;
  final bool pinned;
  final bool compared;
  final ValueChanged<Device> onPin;
  final ValueChanged<Device> onCompare;
  final void Function(String label, String value) onCopy;
  final void Function(int) navigate;
  final InfrastructureContext? infrastructure;

  /// The inventory record of the selected device.
  ///
  /// The administration of a device needs its revision: it is the guard of
  /// every authorized write against the inventory.
  final InventoryDevice? inventoryDevice;

  /// The administration writes and the refresh of the authorized projection.
  final DeviceManagementApi? management;
  final VoidCallback? onInventoryChanged;
  const DeviceContextInspector({
    super.key,
    required this.device,
    required this.snapshot,
    required this.sources,
    required this.metrics,
    required this.pinned,
    required this.compared,
    required this.onPin,
    required this.onCompare,
    required this.onCopy,
    required this.navigate,
    this.infrastructure,
    this.inventoryDevice,
    this.management,
    this.onInventoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final current = device;
    return WorkstationPanel(
      key: const Key('device-context-inspector'),
      accent: OipTokens.violet,
      padding: const EdgeInsets.fromLTRB(
          DevicesLayout.panelPadding, 10, DevicesLayout.panelPadding, 8),
      child: current == null
          ? const Align(
              alignment: Alignment.topLeft,
              child: WorkstationNote(
                'Kein Gerät ausgewählt',
                'Identität, Availability, Data Quality, Relationships und Provenienz erscheinen nach der Auswahl.',
                icon: Icons.info_outline,
              ),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _details(context, current),
                      // The administration scrolls with the details: it is a
                      // part of the object, not a fixed footer.
                      if (inventoryDevice != null && management != null) ...[
                        const Hairline(vertical: 4),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: DeviceAdministration(
                            device: inventoryDevice!,
                            api: management,
                            onChanged: onInventoryChanged ?? () {},
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Hairline(vertical: 4),
              _actions(context, current),
            ]),
    );
  }

  Widget _details(BuildContext context, Device device) {
    final source =
        sources.where((item) => item.id == device.sourceId).firstOrNull;
    final latest = metrics.isEmpty
        ? null
        : metrics.reduce(
            (a, b) => (a.receivedMs ?? -1) >= (b.receivedMs ?? -1) ? a : b);
    final links = snapshot.topology
        .where((link) => link.from == device.id || link.to == device.id)
        .toList();
    final findings = snapshot.incidents
        .where((incident) => incident.deviceId == device.id)
        .length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PanelLabel('Context Inspector',
          trailing: Text(device.simulated ? 'SIMULATED' : 'API',
              style: WorkstationTokens.eyebrow(context))),
      Text(device.name, style: Theme.of(context).textTheme.titleMedium),
      Text(device.id,
          style: WorkstationTokens.mono(context,
              size: 10.5, color: OipTokens.muted(context))),
      const Hairline(vertical: 5),
      const PanelLabel('Identification'),
      _kv('TYPE / SOURCE',
          '${deviceKindName(device.kind)} · ${device.sourceId ?? 'Nicht zugeordnet'}'),
      if (infrastructure?.ready == true) ...[
        _kv('ORGANIZATION',
            infrastructure!.hierarchy.organizationName(infrastructure!.devicePlacement(device)?.organizationId)),
        _kv('INFRASTRUCTURE',
            infrastructure!.hierarchy.infrastructureName(infrastructure!.devicePlacement(device)?.infrastructureId)),
        _kv('SITE',
            infrastructure!.hierarchy.siteName(infrastructure!.devicePlacement(device)?.siteId)),
        _kv('REGISTRATION STATE',
            infrastructure!.inventory
                    ?.where((item) => item.id == device.id)
                    .firstOrNull
                    ?.registration ??
                'Nicht geliefert'),
        _kv('TELEMETRY AVAILABILITY',
            infrastructure!.inventory
                    ?.where((item) => item.id == device.id)
                    .firstOrNull
                    ?.telemetry ??
                (device.sourceId == null ? 'no_collector' : 'unknown')),
      ] else
        _kv('HIERARCHISCHE ZUORDNUNG',
            'Registry Device → ${source == null ? 'Source unbekannt' : source.name}; Org/Infrastructure/Site nicht geliefert'),
      const PanelLabel('Availability'),
      _kv(
          'REGISTRY PRESENCE', 'Im aktuellen autorisierten Snapshot vorhanden'),
      _kv(
          'DATA FRESHNESS',
          metrics.isEmpty
              ? '${known(device.health.freshness)} · REPORTED'
              : known(deviceObservedFreshness(snapshot, device))),
      _kv('SOURCE CONNECTION',
          source == null ? 'Unbekannt' : known(source.connection)),
      _kv('REACHABILITY PROVENANCE',
          '${known(device.health.reachability)} · ${device.simulated ? 'SIMULATED / REPORTED' : 'REPORTED'} · keine Probe'),
      const PanelLabel('Data Quality'),
      _kv(
          'LETZTER MESSWERT',
          latest == null
              ? 'Nicht verfügbar'
              : '${latest.metricId} · ${latest.display} ${latest.symbol}'),
      _kv(
          'QUALITÄT / EMPFANG',
          latest == null
              ? 'Unbekannt'
              : '${known(latest.quality)} · ${timestamp(latest.receivedMs)}'),
      const PanelLabel('Relationships'),
      _kv(
          'SOURCE',
          source == null
              ? 'Keine Source-Zuordnung'
              : '${source.name} · ${source.id}'),
      _kv('DEVICE / SERVICE RELATION', _servicesOf(device)),
      _kv(
          'NETZWERKBEZIEHUNG',
          links.isEmpty
              ? 'Keine belegte Relation im Snapshot'
              : '${links.length} exakte ID-Relation(en) · ${links.every((link) => link.simulated) ? 'SIMULATED / logisch' : 'REPORTED'} · keine physische Nachbarschaft'),
      _kv(
          'OPC-UA REFERENZ',
          device.sourceId == null
              ? 'Nicht zuordenbar'
              : 'Source-Zuordnung vorhanden; Node-ID-Routing nicht verfügbar'),
      _kv('DIAGNOSTIC REFERENCES', '$findings exakte Device-ID-Findings'),
      const PanelLabel('Provenance'),
      _kv(
          'OBSERVED',
          metrics.isEmpty
              ? 'Keine Observation im DeviceDetail'
              : '${metrics.length} DeviceDetail-Observations'),
      _kv('REPORTED / DERIVED',
          'Registry-/Health-Felder reported; UI-Aggregate derived ohne neue Fachlogik'),
      _kv('UNKNOWN',
          'Organization, Site, Firmware, OS, Services, aktive Probes und physische Beziehungen'),
    ]);
  }

  /// The services that the **operator declared** for the device.
  ///
  /// The registry is a declaration, not a measurement: a Core that does not
  /// deliver the registry has no service inventory at all, and the surface
  /// names that instead of deriving a service from the device.
  String _servicesOf(Device device) {
    final registry = infrastructure?.services;
    if (registry == null) return 'Unbekannt · kein autorisiertes Service-Register';
    final services = registry.where((s) => s.deviceId == device.id).toList();
    if (services.isEmpty) return 'Keine Dienste deklariert';
    return '${services.length} deklariert · '
        '${services.map((s) => s.name).join(' · ')}';
  }

  /// Dense key/value row for the narrow inspector column.
  Widget _kv(String label, String value) =>
      KeyValue(label, value, dense: true);

  Widget _actions(BuildContext context, Device device) {
    return Column(children: [
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('device-inspector-pin'),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6)),
            onPressed: () => onPin(device),
            icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 16),
            label: Text(pinned ? 'Gepinnt' : 'Pinnen'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('device-inspector-compare'),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6)),
            onPressed: () => onCompare(device),
            icon: const Icon(Icons.compare_outlined, size: 16),
            label: Text(compared ? 'Im Vergleich' : 'Vergleichen'),
          ),
        ),
      ]),
      Wrap(spacing: 3, children: [
        ToolButton(
          key: const Key('device-copy-id'),
          icon: Icons.copy_outlined,
          tooltip: 'Device ID kopieren',
          onPressed: () => onCopy('Device ID', device.id),
        ),
        ToolButton(
          key: const Key('device-copy-source'),
          icon: Icons.account_tree_outlined,
          tooltip: 'Source ID kopieren',
          onPressed: device.sourceId == null
              ? null
              : () => onCopy('Source ID', device.sourceId!),
        ),
        ToolButton(
          key: const Key('device-inspector-network'),
          icon: Icons.hub_outlined,
          tooltip: 'Network Explorer öffnen · Modulziel, kein ID-Deep-Link',
          onPressed: () => navigate(2),
        ),
        ToolButton(
          key: const Key('device-inspector-opcua'),
          icon: Icons.account_tree_outlined,
          tooltip: device.sourceId == null
              ? 'OPC-UA nicht zuordenbar'
              : 'OPC-UA-Browser öffnen · Source-Modul, kein Node-Deep-Link',
          onPressed: device.sourceId == null ? null : () => navigate(3),
        ),
        ToolButton(
          key: const Key('device-inspector-diagnostics'),
          icon: Icons.radar,
          tooltip: 'Diagnostics öffnen · Modulziel, kein Event-Deep-Link',
          onPressed: () => navigate(4),
        ),
        ToolButton(
          key: const Key('device-inspector-overview'),
          icon: Icons.space_dashboard_outlined,
          tooltip: 'Overview öffnen · Modulziel, kein Device-Deep-Link',
          onPressed: () => navigate(0),
        ),
      ]),
    ]);
  }
}
