import '../../l10n/oip_strings.dart';
import 'package:flutter/material.dart';
import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import '../../models/infrastructure.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'device_inventory.dart';
import 'device_session.dart';
import 'devices_layout.dart';
import '../../widgets/device_kind.dart';

class DeviceComparisonWorkspace extends StatefulWidget {
  final Snapshot snapshot;
  final DevicesWorkspaceSession session;
  final ValueChanged<Device> onRemove;
  final ValueChanged<Device> onSelect;
  final void Function(int) navigate;
  final VoidCallback onToggle;
  final InfrastructureContext? infrastructure;
  const DeviceComparisonWorkspace({
    super.key,
    required this.snapshot,
    required this.session,
    required this.onRemove,
    required this.onSelect,
    required this.navigate,
    required this.onToggle,
    this.infrastructure,
  });

  @override
  State<DeviceComparisonWorkspace> createState() =>
      _DeviceComparisonWorkspaceState();
}

class _DeviceComparisonWorkspaceState extends State<DeviceComparisonWorkspace> {
  bool compareTab = true;

  @override
  Widget build(BuildContext context) {
    final expanded = widget.session.compareExpanded;
    final empty = widget.session.compare.isEmpty;
    return WorkstationPanel(
      key: const Key('device-comparison-workspace'),
      padding: const EdgeInsets.symmetric(
          horizontal: DevicesLayout.panelPadding, vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 28,
          child: Row(children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    key: const Key('device-compare-tab'),
                    avatar: const Icon(Icons.compare_outlined, size: 14),
                    label: Text(
                        context.tr("Comparison {0}/4",
                            [widget.session.compare.length]),
                        style: const TextStyle(fontSize: 11)),
                    selected: compareTab,
                    showCheckmark: false,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                    onSelected: (_) => _selectTab(true),
                  ),
                  ChoiceChip(
                    key: const Key('device-activity-tab'),
                    avatar: const Icon(Icons.event_note_outlined, size: 14),
                    label: Text(context.tr("Related Activity"),
                        style: TextStyle(fontSize: 11)),
                    selected: !compareTab,
                    showCheckmark: false,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                    onSelected: (_) => _selectTab(false),
                  ),
                  Text(context.tr("SESSION-LOCAL · keine Persistenz"),
                      style: WorkstationTokens.eyebrow(context)),
                ],
              ),
            ),
            SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                key: const Key('device-comparison-toggle'),
                tooltip: expanded
                    ? context.tr("Vergleich einklappen")
                    : context.tr("Vergleich ausklappen"),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 28, height: 28),
                onPressed: widget.onToggle,
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18),
              ),
            ),
          ]),
        ),
        if (expanded) ...[
          const SizedBox(height: 4),
          Expanded(
              child: compareTab ? _comparison(context) : _activity(context)),
        ] else if (empty) ...[
          const SizedBox(height: 2),
          SizedBox(
            height: 20,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.tr(
                    "Bis zu vier Geräte über Compare auswählen. Unterschiedliche Messdimensionen werden nicht zu einer gemeinsamen Kennzahl verrechnet."),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  /// Selecting a tab reveals the panel. A tab the user cannot see is not a
  /// result, so the disclosure follows the intent.
  void _selectTab(bool comparison) {
    setState(() => compareTab = comparison);
    if (!widget.session.compareExpanded) widget.onToggle();
  }

  Widget _comparison(BuildContext context) {
    final devices = widget.session.compare
        .map((id) =>
            widget.snapshot.devices.where((item) => item.id == id).firstOrNull)
        .whereType<Device>()
        .toList();
    if (devices.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(context.tr(
            "Bis zu vier Geräte über Compare auswählen. Unterschiedliche Messdimensionen werden nicht zu einer gemeinsamen Kennzahl verrechnet.")),
      );
    }
    final fields = <String, String Function(Device)>{
      'Name / ID': (device) => '${device.name}\n${device.id}',
      'Device Type': (device) => deviceKindName(device.kind),
      'Source': (device) => device.sourceId ?? 'Nicht zugeordnet',
      'Organization': (device) => widget.infrastructure?.ready == true
          ? widget.infrastructure!.hierarchy.organizationName(
              widget.infrastructure!.devicePlacement(device)?.organizationId)
          : 'Nicht im v1-Vertrag verfügbar',
      'Infrastructure': (device) => widget.infrastructure?.ready == true
          ? widget.infrastructure!.hierarchy.infrastructureName(
              widget.infrastructure!.devicePlacement(device)?.infrastructureId)
          : 'Nicht im v1-Vertrag verfügbar',
      'Site': (device) => widget.infrastructure?.ready == true
          ? widget.infrastructure!.hierarchy
              .siteName(widget.infrastructure!.devicePlacement(device)?.siteId)
          : 'Nicht im v1-Vertrag verfügbar',
      'Registry Status': (device) => device.isFaulted
          ? 'Faulted · reported'
          : 'Registry vorhanden · kein Fault gemeldet',
      'Reachability + Provenance': (device) =>
          '${known(device.health.reachability)} · ${device.simulated ? 'SIMULATED / REPORTED' : 'REPORTED'} · keine Probe',
      'Data Freshness': (device) =>
          deviceSnapshotObservations(widget.snapshot, device).isEmpty
              ? '${known(device.health.freshness)} · REPORTED'
              : deviceObservedFreshness(widget.snapshot, device),
      'Available Telemetry': (device) {
        final count =
            deviceSnapshotObservations(widget.snapshot, device).length;
        return count == 0 ? 'Keine im Snapshot' : '$count im Snapshot';
      },
      'Observation Quality': (device) =>
          deviceObservedQuality(widget.snapshot, device),
      'Related Events': (device) {
        final findings = widget.snapshot.incidents
            .where((item) => item.deviceId == device.id)
            .length;
        final sourceEvents = widget.snapshot.recentEvents
            .where((item) =>
                device.sourceId != null && item.sourceId == device.sourceId)
            .length;
        return '$findings Device-Findings · $sourceEvents Source-Events';
      },
      'Known Services': (device) {
        // The registry holds what the **operator declared**. A Core that does
        // not deliver the registry has no service inventory at all: that is
        // unknown, and the surface says so.
        final registry = widget.infrastructure?.services;
        if (registry == null) {
          return 'Unbekannt · kein autorisiertes Service-Register';
        }
        final services =
            registry.where((s) => s.deviceId == device.id).toList();
        if (services.isEmpty) return 'Keine Dienste deklariert';
        return services.map((s) => s.name).join(' · ');
      },
      'Missing Data': (device) => [
            if (device.sourceId == null) 'Source',
            if (deviceSnapshotObservations(widget.snapshot, device).isEmpty)
              'Telemetry',
            if (widget.infrastructure?.ready != true) 'Org/Site',
            if (widget.infrastructure?.services == null) 'Services',
            'Probe'
          ].join(', '),
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: 160 + devices.length * 210),
        child: SizedBox(
          width: 160 + devices.length * 210,
          child: ListView(
            key: const Key('device-comparison-fields'),
            children: [
              Row(children: [
                SizedBox(width: 160, child: Text(context.tr("VERGLEICHSFELD"))),
                ...devices.map((device) => SizedBox(
                      width: 210,
                      child: ListTile(
                        key: Key('device-compare-column-${device.id}'),
                        dense: true,
                        title: Text(device.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(device.id,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        leading: Icon(deviceIcon(device.kind), size: 17),
                        trailing: IconButton(
                          key: Key('device-compare-remove-${device.id}'),
                          tooltip: context.tr("Aus Vergleich entfernen"),
                          onPressed: () => widget.onRemove(device),
                          icon: const Icon(Icons.close, size: 16),
                        ),
                        onTap: () => widget.onSelect(device),
                      ),
                    )),
              ]),
              ...fields.entries.map((field) => Container(
                    key: Key('device-comparison-field-${field.key}'),
                    decoration: BoxDecoration(
                        border: Border(
                            top: BorderSide(
                                color: WorkstationTokens.hairline(context)))),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      SizedBox(
                          width: 160,
                          child: Text(field.key.toUpperCase(),
                              style: WorkstationTokens.eyebrow(context))),
                      ...devices.map((device) => SizedBox(
                            width: 210,
                            child: Text(field.value(device),
                                style:
                                    WorkstationTokens.mono(context, size: 10)),
                          )),
                    ]),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activity(BuildContext context) {
    final selected = widget.snapshot.devices
        .where((item) => item.id == widget.session.selectedId)
        .firstOrNull;
    if (selected == null) {
      return Align(
          alignment: Alignment.centerLeft,
          child: Text(context.tr(
              "Gerät auswählen, um exakt zugeordnete Findings und Source-Events zu sehen.")));
    }
    final findings = widget.snapshot.incidents
        .where((item) => item.deviceId == selected.id)
        .toList();
    final events = widget.snapshot.recentEvents
        .where((item) =>
            selected.sourceId != null && item.sourceId == selected.sourceId)
        .take(20)
        .toList();
    if (findings.isEmpty && events.isEmpty) {
      return Align(
          alignment: Alignment.centerLeft,
          child: Text(context.tr(
              "Keine Related Activity für {0} im aktuellen API-Fenster.",
              [selected.id])));
    }
    return ListView(children: [
      ...findings.map((item) => ListTile(
            dense: true,
            minTileHeight: 36,
            leading: const Icon(Icons.radar, size: 16),
            title:
                Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(context.tr("{0} · exakte Device-ID · {1}",
                [item.id, item.simulated ? 'SIMULATED' : 'REPORTED'])),
            onTap: () => widget.navigate(4),
          )),
      ...events.map((item) => ListTile(
            dense: true,
            minTileHeight: 36,
            leading: const Icon(Icons.account_tree_outlined, size: 16),
            title: Text('${item.kind} · ${item.sourceId}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(context.tr("{0} · {1} · Source-Ereignis", [
              item.id ?? 'Sequenz ${item.sequence ?? 'unbekannt'}',
              timestamp(item.atMs ?? item.gapEndedMs)
            ])),
            onTap: () => widget.navigate(4),
          )),
    ]);
  }
}

class DeviceInventoryHealth extends StatelessWidget {
  final Snapshot snapshot;
  final List<SourceInfo> sources;
  const DeviceInventoryHealth(
      {super.key, required this.snapshot, required this.sources});

  @override
  Widget build(BuildContext context) {
    final withSource =
        snapshot.devices.where((item) => item.sourceId != null).length;
    final withTelemetry = snapshot.devices
        .where((item) => deviceSnapshotObservations(snapshot, item).isNotEmpty)
        .length;
    final reachable = snapshot.devices
        .where((item) => item.health.reachability == 'reachable')
        .length;
    return WorkstationPanel(
      key: const Key('device-inventory-health'),
      accent: OipTokens.cyan,
      child: SingleChildScrollView(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PanelLabel(context.tr("Inventory Health · Beobachtungsumfang")),
          KeyValueGrid(children: [
            KeyValue(
                context.tr("REGISTRY"),
                context.tr(
                    "{0} Geräte im v1-Snapshot", [snapshot.devices.length])),
            KeyValue(context.tr("SOURCE-ZUORDNUNG"),
                '$withSource / ${snapshot.devices.length}'),
            KeyValue(context.tr("OBSERVED TELEMETRY"),
                '$withTelemetry / ${snapshot.devices.length}'),
            KeyValue(
                context.tr("REPORTED REACHABILITY"),
                context
                    .tr("{0} erreichbar · nicht aktiv gemessen", [reachable])),
            KeyValue(
                context.tr("SIMULATED INVENTORY"),
                context.tr("{0} Geräte",
                    [snapshot.devices.where((item) => item.simulated).length])),
            KeyValue(context.tr("SERVICE COVERAGE"),
                context.tr("Unbekannt · Capability fehlt")),
          ]),
          const Hairline(),
          PanelLabel(context
              .tr("Source Health · nicht mit Device Health gleichsetzen")),
          if (sources.isEmpty)
            Text(context
                .tr("SourceHealth im aktuellen Datenumfang nicht verfügbar."))
          else
            ...sources.map((source) => ListTile(
                  key: Key('device-health-source-${source.id}'),
                  dense: true,
                  leading: StatusDot(source.connection),
                  title: Text('${source.name} · ${source.id}'),
                  subtitle: Text(context.tr("{0} · {1} · Empfang {2} · {3}", [
                    known(source.connection),
                    known(source.freshness),
                    timestamp(source.lastReceivedMs),
                    source.simulated ? 'SIMULATED' : 'REPORTED'
                  ])),
                )),
          WorkstationNote(
            context.tr("Kein globales Gesundheitsurteil"),
            context.tr(
                "Registry-Mitgliedschaft, SourceHealth, Observations, gemeldete Reachability und Diagnosebefunde bleiben getrennt. Fehlende Services und aktive Probes bleiben unbekannt."),
            icon: Icons.fact_check_outlined,
          ),
        ]),
      ),
    );
  }
}
