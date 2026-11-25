import '../../l10n/oip_strings.dart';
import 'package:flutter/material.dart';
import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'overview_selection.dart';
import '../../widgets/device_kind.dart';

class OverviewAttentionEntry {
  final String title, detail, tone;
  final IconData icon;
  final CollectionEvent? event;
  final bool diagnostics;
  const OverviewAttentionEntry({
    required this.title,
    required this.detail,
    required this.tone,
    required this.icon,
    this.event,
    this.diagnostics = false,
  });
}

class OverviewContextInspector extends StatelessWidget {
  final Snapshot snapshot;
  final bool transportLive;
  final List<SourceInfo> sources;
  final List<CollectionEvent> events;
  final OverviewSelection selection;
  final List<OverviewAttentionEntry> attention;
  final VoidCallback onClear;
  final ValueChanged<CollectionEvent> onEvent;
  final ValueChanged<Device> onDeviceDetails;
  final void Function(int) navigate;
  const OverviewContextInspector({
    super.key,
    required this.snapshot,
    required this.transportLive,
    required this.sources,
    required this.events,
    required this.selection,
    required this.attention,
    required this.onClear,
    required this.onEvent,
    required this.onDeviceDetails,
    required this.navigate,
  });

  @override
  Widget build(BuildContext context) {
    return WorkstationPanel(
      key: const Key('overview-context-inspector'),
      accent: OipTokens.violet,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: LayoutBuilder(builder: (context, constraints) {
        final selectionDetail = switch (selection.kind) {
          OverviewSelectionKind.none => _empty(context),
          OverviewSelectionKind.source => _source(context),
          OverviewSelectionKind.device => _device(context),
          OverviewSelectionKind.event => _event(context),
        };
        final detail = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr("Core-Zustand: {0}", [context.tr(_coreStatus)]),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            selectionDetail,
          ],
        );
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelLabel(context.tr("Context Inspector"),
                  trailing: IconButton(
                    key: const Key('overview-inspector-clear'),
                    tooltip: context.tr("Auswahl aufheben"),
                    onPressed: selection.hasEntity ? onClear : null,
                    icon: const Icon(Icons.close, size: 17),
                  )),
              if (constraints.hasBoundedHeight)
                Expanded(child: SingleChildScrollView(child: detail))
              else
                detail,
              const Hairline(vertical: 5),
              _attention(context),
              _actions(context),
            ]);
      }),
    );
  }

  String get _coreStatus => !transportLive
      ? 'Status veraltet'
      : switch (snapshot.core.lifecycle) {
          CoreLifecycle.initializing => 'Initialisierung',
          CoreLifecycle.ready => 'Bereit',
          CoreLifecycle.degraded => 'Degradiert',
          CoreLifecycle.stopping => 'Stoppt',
          CoreLifecycle.stopped => 'Gestoppt',
          CoreLifecycle.failed => 'Fehlgeschlagen',
          CoreLifecycle.unknown => 'Unbekannt',
        };

  Widget _empty(BuildContext context) => WorkstationNote(
        context.tr("Quelle, Gerät oder Ereignis auswählen."),
        context.tr(
            "Explorer, Operational Focus und Activity verwenden denselben technischen Kontext."),
        icon: Icons.touch_app_outlined,
      );

  Widget _source(BuildContext context) {
    final source =
        sources.where((item) => item.id == selection.sourceId).firstOrNull;
    if (source == null) {
      return WorkstationNote(
          context.tr("Source nicht im aktuellen Datenumfang"),
          context.tr(
              "Die Auswahl bleibt ohne fremde oder veraltete Source-Metadaten."),
          icon: Icons.cloud_off_outlined);
    }
    final signals = overviewSignalsFor(snapshot, sourceId: source.id);
    final sourceEvents =
        events.where((event) => event.sourceId == source.id).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _identity(context, source.name, source.id, Icons.account_tree_outlined,
          OipTokens.cyan),
      KeyValue(
          context.tr("CONNECTION STATE"), context.tr(known(source.connection))),
      KeyValue(context.tr("FRESHNESS"), context.tr(known(source.freshness))),
      KeyValue(context.tr("TATSÄCHLICHER EMPFANG"),
          timestamp(source.lastReceivedMs)),
      KeyValue(
          context.tr("PROVENIENZ"),
          context.tr("{0} · Reachability {1} · kein aktiver Probe", [
            source.simulated ? 'SIMULATED' : 'REPORTED',
            known(source.reachability)
          ])),
      KeyValue(context.tr("AVAILABLE SIGNALS"),
          context.tr("{0} im aktuellen Snapshot", [signals.length])),
      KeyValue(
          context.tr("COLLECTION EVENTS"),
          context.tr(
              "{0} im begrenzten aktuellen Fenster", [sourceEvents.length])),
      if (source.lastError != null)
        KeyValue(context.tr("LAST ERROR"), source.lastError!,
            color: OipTokens.yellow),
    ]);
  }

  Widget _device(BuildContext context) {
    final device = snapshot.devices
        .where((item) => item.id == selection.deviceId)
        .firstOrNull;
    if (device == null) {
      return WorkstationNote(
          context.tr("Gerät nicht im aktuellen Registry-Stand"),
          context.tr("Es werden keine früheren Gerätedaten untergeschoben."),
          icon: Icons.dns_outlined);
    }
    final signals = overviewSignalsFor(snapshot,
        sourceId: device.sourceId, deviceId: device.id);
    final lastReceived = signals
        .map((signal) => signal.receivedMs)
        .whereType<int>()
        .fold<int?>(
            null,
            (latest, value) =>
                latest == null || value > latest ? value : latest);
    final states = signals.map((signal) => signal.freshness).toSet().toList()
      ..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _identity(context, device.name, device.id, Icons.dns_outlined,
          OipTokens.violet),
      KeyValue(context.tr("SOURCE"),
          device.sourceId ?? context.tr("Nicht zugeordnet")),
      KeyValue(context.tr("REGISTRY"),
          '${deviceKindName(device.kind)} · ${device.location} · ${device.connection}'),
      KeyValue(
          context.tr("OBSERVED TELEMETRY"),
          signals.isEmpty
              ? context.tr("Keine Observation im Snapshot")
              : context.tr(
                  "{0} Signale · {1}", [signals.length, states.join(', ')])),
      KeyValue(context.tr("LAST KNOWN DATA"), timestamp(lastReceived)),
      KeyValue(
          context.tr("CONNECTIVITY"),
          context.tr("{0} · REPORTED{1} · kein aktiver Probe", [
            known(device.health.reachability),
            device.simulated ? ' / SIMULATED' : ''
          ])),
      KeyValue(
          context.tr("UNAVAILABLE / UNKNOWN"),
          context.tr("Agent {0} · VPN {1} · keine Ableitung aus Registry",
              [known(device.health.agent), known(device.health.vpn)])),
    ]);
  }

  Widget _event(BuildContext context) {
    final event = events
        .where((item) => overviewEventKey(item) == selection.eventKey)
        .firstOrNull;
    if (event == null) {
      return WorkstationNote(
          context.tr("Ereignis nicht im aktuellen Fenster"),
          context.tr(
              "Die begrenzte API-Ansicht enthält diesen Record nicht mehr."),
          icon: Icons.event_busy_outlined);
    }
    final control = const {
      'ConnectionLost',
      'Reconnected',
      'SubscriptionError',
      'DataLoss'
    }.contains(event.kind);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _identity(context, event.kind, overviewEventIdentity(event),
          Icons.event_note_outlined, OipTokens.amber),
      KeyValue(context.tr("EVENT ID / RECORD"), overviewEventIdentity(event)),
      KeyValue(context.tr("EVENT TYPE"), event.kind),
      KeyValue(context.tr("SOURCE"),
          event.sourceId ?? context.tr("Nicht projiziert")),
      KeyValue(
          control
              ? context.tr("EVENT TIME · CONTROL/WALL CLOCK")
              : context.tr("EVENT TIME · API"),
          timestamp(event.atMs)),
      KeyValue(context.tr("PROVENIENZ"),
          '${event.originClass ?? 'v1 Collection Record'}${snapshot.system.simulated ? ' · Demo-Core' : ''}'),
      if (event.sequence != null)
        KeyValue(context.tr("SEQUENCE"), '${event.sequence}'),
      if (event.reason != null)
        KeyValue(context.tr("AVAILABLE EVIDENCE · REASON"), event.reason!),
      if (event.gapStartedMs != null)
        KeyValue(context.tr("DOCUMENTED GAP"),
            '${timestamp(event.gapStartedMs)} → ${timestamp(event.gapEndedMs)}${event.gapMs == null ? '' : ' · ${event.gapMs} ms'}'),
      if (event.dropped != null)
        KeyValue(context.tr("DROPPED"), '${event.dropped}'),
      KeyValue(
          context.tr("OPEN QUESTIONS"),
          context.tr(
              "Ursache und globale Severity nicht geliefert; kein ID-Router-Kontext.")),
    ]);
  }

  Widget _identity(BuildContext context, String title, String id, IconData icon,
          Color accent) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: accent.withOpacity(.12),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium),
              Text(id,
                  style: WorkstationTokens.mono(context,
                      size: 10.5, color: OipTokens.muted(context))),
            ]),
          ),
        ]),
      );

  Widget _action(BuildContext context, String label, IconData icon,
          {Key? key, required VoidCallback? onPressed}) =>
      Padding(
        padding: const EdgeInsets.only(top: 5),
        child: OutlinedButton.icon(
          key: key,
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: onPressed,
          icon: Icon(icon, size: 16),
          label: Text(label),
        ),
      );

  Widget _actions(BuildContext context) {
    final device = snapshot.devices
        .where((item) => item.id == selection.deviceId)
        .firstOrNull;
    return switch (selection.kind) {
      OverviewSelectionKind.none => const SizedBox.shrink(),
      OverviewSelectionKind.source => Row(children: [
          Expanded(
            child: _action(context, 'OPC-UA untersuchen', Icons.arrow_outward,
                key: const Key('overview-inspector-open-opcua'),
                onPressed: () => navigate(3)),
          ),
          IconButton(
              key: const Key('overview-inspector-open-network'),
              tooltip: context.tr("Netzwerk untersuchen"),
              onPressed: () => navigate(2),
              icon: const Icon(Icons.hub_outlined, size: 18)),
          IconButton(
              key: const Key('overview-inspector-source-diagnostics'),
              tooltip: context.tr("Diagnostics öffnen"),
              onPressed: () => navigate(4),
              icon: const Icon(Icons.radar, size: 18)),
        ]),
      OverviewSelectionKind.device => Row(children: [
          Expanded(
            child: _action(context, 'Gerätedetails öffnen', Icons.dns_outlined,
                key: const Key('overview-inspector-open-device'),
                onPressed:
                    device == null ? null : () => onDeviceDetails(device)),
          ),
          IconButton(
              tooltip: context.tr("Network & VPN öffnen"),
              onPressed: () => navigate(2),
              icon: const Icon(Icons.hub_outlined, size: 18)),
        ]),
      OverviewSelectionKind.event => _action(
          context, 'Diagnostics öffnen', Icons.arrow_outward,
          key: const Key('overview-inspector-open-diagnostics'),
          onPressed: () => navigate(4)),
    };
  }

  Widget _attention(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PanelLabel(context.tr("Operational Attention"),
          color: OipTokens.amber,
          trailing: Text('${attention.length}',
              style: WorkstationTokens.mono(context, size: 11))),
      if (attention.isEmpty)
        Text(
            context.tr(
                "Keine aktiven Findings oder Störungen im verfügbaren Snapshot/Eventfenster. Beobachtungslücken bleiben separat ausgewiesen."),
            style: Theme.of(context).textTheme.bodySmall),
      ...attention.take(1).map((entry) => Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Material(
              color: WorkstationTokens.well(context),
              borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
              child: ListTile(
                key: Key('overview-attention-${entry.title}'),
                dense: true,
                minTileHeight: 44,
                leading: Icon(entry.icon,
                    size: 17,
                    color: OipTokens.statusColor(context, entry.tone)),
                title: Text(entry.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(entry.detail,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: entry.event != null
                    ? () => onEvent(entry.event!)
                    : entry.diagnostics
                        ? () => navigate(4)
                        : null,
              ),
            ),
          )),
      if (attention.length > 1)
        Text(
            context.tr(
                "+{0} weitere · Activity/Diagnostics für den vollständigen Umfang",
                [attention.length - 1]),
            style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
