import '../l10n/oip_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/controller.dart';
import '../design_system/theme.dart';
import '../models/contracts.dart';
import '../widgets/adaptive_workspace.dart';
import '../widgets/components.dart';
import '../widgets/workstation.dart';
import 'devices.dart';
import 'overview/activity_workspace.dart';
import 'overview/context_inspector.dart';
import 'overview/dashboard_workspace.dart';
import 'overview/infrastructure_explorer.dart';
import 'overview/overview_selection.dart';
import 'overview/telemetry_chart.dart';
import 'overview/unified_infrastructure_summary.dart';

class OverviewPage extends StatefulWidget {
  final OipController controller;
  final void Function(int) navigate;
  const OverviewPage(this.controller, this.navigate, {super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

enum _OverviewMobilePane { explorer, focus, inspector }

class _OverviewPageState extends State<OverviewPage> {
  late OverviewSelection selection;
  final GlobalKey<OverviewTrendChartState> chartKey = GlobalKey();
  _OverviewMobilePane mobilePane = _OverviewMobilePane.focus;
  String? scopeSignature;
  bool dashboardMode = false;

  OipController get controller => widget.controller;

  void _contextChanged() {
    final next = controller.contextScopeSignature;
    if (!mounted || scopeSignature == next) return;
    scopeSignature = next;
    setState(() {
      selection = const OverviewSelection.none();
      mobilePane = _OverviewMobilePane.focus;
    });
  }

  @override
  void initState() {
    super.initState();
    scopeSignature = controller.contextScopeSignature;
    controller.addListener(_contextChanged);
    // Orientation starts without a synthetic object. In the explicitly retained
    // expert workspace, the authorized primary source restores the established
    // full-panel workflow after module navigation.
    final primary = controller.snapshot?.primarySourceId;
    final expert =
        controller.workspaces.layout(WorkspaceId.overview).expertWorkspace;
    selection = expert && primary != null
        ? OverviewSelection.source(primary)
        : const OverviewSelection.none();
  }

  Snapshot get snapshot => controller.snapshot!;
  List<SourceInfo> get sources => controller.operationalSources.isNotEmpty
      ? controller.operationalSources
      : snapshot.sources;
  List<CollectionEvent> get events => controller.operationalEvents.isNotEmpty
      ? controller.operationalEvents
      : snapshot.recentEvents;
  List<CollectionEvent> get scopedEvents => selection.sourceId == null
      ? selection.kind == OverviewSelectionKind.device
          ? const []
          : events
      : events.where((event) => event.sourceId == selection.sourceId).toList();

  @override
  void dispose() {
    controller.removeListener(_contextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expert =
        controller.workspaces.layout(WorkspaceId.overview).expertWorkspace;
    final selected = selection.kind == OverviewSelectionKind.none && !expert
        ? null
        : controller.selectedTelemetry ??
            (controller.telemetrySelectionExplicit
                ? null
                : snapshot.primaryTemperature);
    final attention = _attentionEntries();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f6): () {
          chartKey.currentState?.focusNextSampleAction();
        },
      },
      child: Focus(
        autofocus: true,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: OipTokens.s2),
              _contextBar(),
              const SizedBox(height: OipTokens.s2),
              _statusStrip(),
              if (controller.infrastructure.ready &&
                  controller.infrastructure.selection.isUnified) ...[
                const SizedBox(height: OipTokens.s2),
                UnifiedInfrastructureSummary(controller: controller),
              ],
              const SizedBox(height: OipTokens.s3),
              if (dashboardMode)
                DashboardWorkspace(
                  key: ValueKey(controller.contextScopeSignature),
                  controller: controller,
                )
              else if (!controller.workspaces
                      .layout(WorkspaceId.overview)
                      .expertWorkspace &&
                  selection.kind == OverviewSelectionKind.none)
                SizedBox(
                  height: MediaQuery.sizeOf(context).width < OipTokens.tablet
                      ? 220
                      : 176,
                  child: ActivityCoverageWorkspace(
                    snapshot: snapshot,
                    sources: sources,
                    events: scopedEvents,
                    allEvents: events,
                    selection: selection,
                    onEvent: _selectEvent,
                    onSource: _selectSource,
                    navigate: widget.navigate,
                  ),
                )
              else ...[
                LayoutBuilder(builder: (context, box) {
                  final explorer = InfrastructureExplorer(
                    snapshot: snapshot,
                    sources: sources,
                    selection: selection,
                    onSource: _selectSource,
                    onDevice: _selectDevice,
                  );
                  final focus = _operationalFocus(selected);
                  final inspector = AdaptiveInspector(
                    controller: controller,
                    workspace: WorkspaceId.overview,
                    label: context.tr("Kontext & Provenienz"),
                    hasSelection: selection.kind != OverviewSelectionKind.none,
                    child: OverviewContextInspector(
                      snapshot: snapshot,
                      sources: sources,
                      events: events,
                      selection: selection,
                      attention: attention,
                      onClear: () {
                        setState(
                            () => selection = const OverviewSelection.none());
                        controller.setInspectorOpen(
                            WorkspaceId.overview, false);
                      },
                      onEvent: _selectEvent,
                      onDeviceDetails: (device) =>
                          showDevice(context, controller, device),
                      navigate: widget.navigate,
                    ),
                  );
                  final showInspector = controller.inspectorVisible(
                      WorkspaceId.overview,
                      selection.kind != OverviewSelectionKind.none);
                  if (box.maxWidth >= OipTokens.workstation) {
                    final viewport = MediaQuery.sizeOf(context).height;
                    final mainHeight = viewport >= 1000
                        ? (viewport - 540).clamp(370.0, 620.0)
                        : 370.0;
                    return SizedBox(
                      height: mainHeight,
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                                width: box.maxWidth >= 1500 ? 252 : 232,
                                child: explorer),
                            const SizedBox(width: OipTokens.s2),
                            Expanded(child: focus),
                            if (showInspector) ...[
                              const SizedBox(width: OipTokens.s2),
                              SizedBox(
                                  width: box.maxWidth >= 1500 ? 310 : 288,
                                  child: inspector),
                            ],
                          ]),
                    );
                  }
                  if (box.maxWidth >= OipTokens.tablet) {
                    return Column(children: [
                      SizedBox(
                        height: 430,
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 238, child: explorer),
                              const SizedBox(width: OipTokens.s2),
                              Expanded(child: focus),
                            ]),
                      ),
                      if (showInspector) ...[
                        const SizedBox(height: OipTokens.s2),
                        SizedBox(height: 360, child: inspector),
                      ],
                    ]);
                  }
                  return Column(children: [
                    _mobilePaneSelector(),
                    const SizedBox(height: OipTokens.s2),
                    switch (mobilePane) {
                      _OverviewMobilePane.explorer =>
                        SizedBox(height: 480, child: explorer),
                      _OverviewMobilePane.focus => focus,
                      _OverviewMobilePane.inspector =>
                        SizedBox(height: 460, child: inspector),
                    },
                  ]);
                }),
                const SizedBox(height: OipTokens.s2),
                SizedBox(
                  height: MediaQuery.sizeOf(context).width < OipTokens.tablet
                      ? 220
                      : 176,
                  child: ActivityCoverageWorkspace(
                    snapshot: snapshot,
                    sources: sources,
                    events: scopedEvents,
                    allEvents: events,
                    selection: selection,
                    onEvent: _selectEvent,
                    onSource: _selectSource,
                    navigate: widget.navigate,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => AdaptiveWorkspaceHeader(
        eyebrow: dashboardMode
            ? context.tr("VISUALISIERUNG · AUTORISIERTE MESSWERTE")
            : context.tr("INFRASTRUCTURE COMMAND CENTER · READ-ONLY"),
        title: dashboardMode
            ? context.tr("Infrastruktur-Dashboard")
            : context.tr("Operations Workstation"),
        subtitle: dashboardMode
            ? context.tr("Panels je Benutzer und Infrastruktur zusammenstellen")
            : context.tr(
                "Zustand erkennen · Auffälligkeiten auswählen · technisch vertiefen"),
        accent: OipTokens.cyan,
        primaryAction: WorkspacePrimaryAction(
          buttonKey: const Key('overview-primary-diagnostics'),
          label: context.tr("Diagnose öffnen"),
          tooltip: context.tr(
              "Findings, aktuelle Ereignisse und Collection-Probleme untersuchen"),
          icon: Icons.fact_check_outlined,
          onPressed: () => widget.navigate(4),
        ),
        actions: [
          WorkspacePrimaryAction(
            buttonKey: const Key('overview-dashboard-toggle'),
            label: dashboardMode
                ? context.tr("Übersicht")
                : context.tr("Dashboard öffnen"),
            tooltip: dashboardMode
                ? context.tr("Zur Operations-Übersicht zurückkehren")
                : context.tr(
                    "Persönliche Live-Panels für diesen Infrastrukturkontext öffnen"),
            icon: dashboardMode
                ? Icons.arrow_back
                : Icons.dashboard_customize_outlined,
            onPressed: () => setState(() => dashboardMode = !dashboardMode),
          ),
          InspectorOpenAction(
            controller: controller,
            workspace: WorkspaceId.overview,
            hasSelection: selection.kind != OverviewSelectionKind.none,
            onOpen: () {
              controller.setExpertWorkspace(WorkspaceId.overview, true);
              if (MediaQuery.sizeOf(context).width < OipTokens.tablet) {
                setState(() => mobilePane = _OverviewMobilePane.inspector);
              }
            },
          ),
          WorkspaceLayoutAction(
              controller: controller, workspace: WorkspaceId.overview),
        ],
        status: [
          StatusPill(
            snapshot.system.simulated
                ? context.tr("DEMO / SIMULATION")
                : context.tr("BACKEND-DATEN"),
            color: OipTokens.statusColor(context, 'info'),
            icon: snapshot.system.simulated
                ? Icons.science_outlined
                : Icons.cloud_done_outlined,
          ),
          StatusPill(context.tr("READ-ONLY"), icon: Icons.lock_outline),
        ],
      );

  Widget _contextBar() => WorkstationPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: LayoutBuilder(builder: (context, box) {
          final infrastructure = controller.infrastructure;
          final facts = [
            (
              'KONTEXT',
              infrastructure.ready
                  ? infrastructure.selectedBreadcrumb
                  : 'Lokal · autorisierter v1-Umfang'
            ),
            (
              'SOURCE',
              infrastructure.selection.sourceId ??
                  (selection.kind == OverviewSelectionKind.device &&
                          selection.sourceId == null
                      ? 'Nicht zugeordnet'
                      : selection.sourceId ??
                          snapshot.primarySourceId ??
                          'Nicht eindeutig geliefert')
            ),
            (
              'ORG / SITE',
              infrastructure.ready
                  ? '${infrastructure.hierarchy.organizationName(infrastructure.selection.organizationId)} / ${infrastructure.hierarchy.siteName(infrastructure.selection.siteId)}'
                  : 'Nicht im v1-Vertrag geliefert'
            ),
            (
              'TATSÄCHLICHER EMPFANG',
              timestamp(snapshot.system.lastReceivedMs)
            ),
            ('TRANSPORT', controller.connection.toUpperCase()),
          ];
          final columns = box.maxWidth < 520 ? 2 : 5;
          final width = (box.maxWidth - (columns - 1) * 10) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 5,
            children: facts
                .map((fact) => SizedBox(
                    width: width, child: _contextFact(fact.$1, fact.$2)))
                .toList(),
          );
        }),
      );

  Widget _contextFact(String label, String value) => Row(children: [
        Flexible(
          flex: 2,
          child: Text('$label  ',
              overflow: TextOverflow.ellipsis,
              style: WorkstationTokens.eyebrow(context)),
        ),
        Expanded(
          flex: 3,
          child: Text(value,
              overflow: TextOverflow.ellipsis,
              style: WorkstationTokens.mono(context, size: 10.5)),
        ),
      ]);

  Widget _statusStrip() {
    final connected =
        sources.where((source) => source.connection == 'connected').length;
    final freshness = _freshness(snapshot.metrics);
    final contextFindings = controller.infrastructure.findings;
    final findings = controller.infrastructure.ready
        ? contextFindings
            ?.where((finding) => finding.evidenceSourceIds.any((sourceId) {
                  final placement =
                      controller.infrastructure.sourcePlacement(sourceId);
                  return placement != null &&
                      controller.infrastructure.selection.matches(
                        organizationId: placement.organizationId,
                        infrastructureId: placement.infrastructureId,
                        siteId: placement.siteId,
                        sourceId:
                            controller.infrastructure.selection.sourceId == null
                                ? null
                                : sourceId,
                      );
                }))
            .length
        : snapshot.incidents.length;
    final items = [
      (
        'CORE',
        controller.connection == 'live'
            ? _coreLabel(snapshot.core.lifecycle).toUpperCase()
            : 'STALE / RECONNECT',
        controller.connection == 'live'
            ? _coreTone(snapshot.core.lifecycle)
            : 'stale'
      ),
      (
        'SOURCES',
        sources.isEmpty
            ? known(snapshot.system.opcua).toUpperCase()
            : '$connected / ${sources.length} CONNECTED',
        sources.isEmpty
            ? snapshot.system.opcua
            : connected == sources.length
                ? 'connected'
                : 'degraded'
      ),
      ('DEVICES', '${snapshot.devices.length} REGISTERED', 'info'),
      (
        'FINDINGS',
        findings == null
            ? 'NICHT IM KONTEXT GELIEFERT'
            : findings == 0
                ? 'NONE IN CURRENT DATA'
                : '$findings DELIVERED',
        findings == null || findings == 0 ? 'unknown' : 'degraded'
      ),
      ('DATA TRUST', freshness.toUpperCase(), freshness),
    ];
    return WorkstationPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: LayoutBuilder(builder: (context, box) {
        final columns = box.maxWidth >= 900
            ? 5
            : box.maxWidth >= 520
                ? 3
                : 2;
        final width = (box.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 5,
          children: items
              .map((item) => SizedBox(
                  width: width, child: _statusValue(item.$1, item.$2, item.$3)))
              .toList(),
        );
      }),
    );
  }

  Widget _statusValue(String label, String value, String status) => Semantics(
        excludeSemantics: true,
        label: label == 'CORE'
            ? context.tr("Core-Zustand: {0}", [
                value == 'STALE / RECONNECT'
                    ? 'Status veraltet'
                    : value[0] + value.substring(1).toLowerCase()
              ])
            : '$label: $value',
        child: Row(children: [
          StatusDot(status),
          const SizedBox(width: 7),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: WorkstationTokens.eyebrow(context)),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WorkstationTokens.mono(context,
                      size: 10.5, weight: FontWeight.w700)),
            ]),
          ),
        ]),
      );

  Widget _operationalFocus(Observation? selected) {
    final selectedSource = selection.kind == OverviewSelectionKind.device &&
            selection.sourceId == null
        ? ''
        : selection.sourceId ?? selected?.sourceId;
    final selectedDevice = selection.kind == OverviewSelectionKind.device
        ? selection.deviceId
        : null;
    final options = overviewSignalsFor(snapshot,
        sourceId: selectedSource, deviceId: selectedDevice);
    final selectedKey = selected == null ? null : observationKey(selected);
    final gaps = events
        .where((event) =>
            event.gapStartedMs != null &&
            (selected == null || event.sourceId == selected.sourceId))
        .toList();
    return WorkstationPanel(
      key: const Key('overview-operational-focus'),
      accent: OipTokens.cyan,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: SingleChildScrollView(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PanelLabel(context.tr("Operational Focus · Session Telemetry"),
              trailing: Wrap(children: [
                if (MediaQuery.sizeOf(context).width < OipTokens.tablet)
                  ToolButton(
                    key: const Key('overview-mobile-open-inspector'),
                    icon: Icons.info_outline,
                    tooltip: context.tr("Inspector anzeigen"),
                    onPressed: () => setState(
                        () => mobilePane = _OverviewMobilePane.inspector),
                  ),
                ToolButton(
                  key: const Key('overview-open-opcua'),
                  icon: Icons.arrow_outward,
                  tooltip: context.tr("OPC-UA untersuchen"),
                  onPressed: () => widget.navigate(3),
                ),
              ])),
          Row(children: [
            Expanded(
              child: Text(
                selectedSource == null
                    ? context.tr("Alle im Snapshot verfügbaren Signale")
                    : '$selectedSource${selectedDevice == null ? '' : ' · $selectedDevice'}',
                overflow: TextOverflow.ellipsis,
                style: WorkstationTokens.mono(context, size: 10.5),
              ),
            ),
            Text(context.tr("{0}/60 SESSION", [controller.history.length]),
                style: WorkstationTokens.mono(context, size: 10)),
          ]),
          const SizedBox(height: 7),
          DropdownButtonFormField<String>(
            key: const Key('overview-signal-select'),
            isExpanded: true,
            value: options.any((item) => observationKey(item) == selectedKey)
                ? selectedKey
                : null,
            decoration: InputDecoration(
                labelText: context.tr("SIGNAL / NODE"),
                isDense: true,
                border: OutlineInputBorder()),
            items: options
                .map((item) => DropdownMenuItem(
                    value: observationKey(item),
                    child: Text('${item.entityId} · ${item.metricId}',
                        overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: options.isEmpty
                ? null
                : (key) {
                    if (key != null) _selectSignal(key);
                  },
          ),
          const SizedBox(height: 7),
          if (selected == null)
            WorkstationNote(
              context.tr("Kein Live-Signal verfügbar"),
              context.tr(
                  "Für diesen Kontext enthält der Snapshot keine auswählbare Observation. Keine Ersatzwerte, kein Chart und kein Wert 0."),
              icon: Icons.sensors_off_outlined,
              color: OipTokens.muted(context),
            )
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${selected.display} ${selected.symbol}',
                    style: Theme.of(context).textTheme.headlineMedium),
                StatusPill(known(selected.freshness).toUpperCase(),
                    color: OipTokens.statusColor(context, selected.freshness),
                    showDot: true),
                StatusPill(
                    context.tr("QUALITÄT {0}",
                        [known(selected.quality).toUpperCase()]),
                    color: OipTokens.statusColor(context, selected.quality)),
                if (selected.simulated)
                  StatusPill(context.tr("SIMULATED"),
                      icon: Icons.science_outlined),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 14, runSpacing: 3, children: [
              Text(
                  context.tr("TATSÄCHLICHER EMPFANG {0}",
                      [timestamp(selected.receivedMs)]),
                  style: WorkstationTokens.mono(context, size: 9.5)),
              Text(
                  '${selected.simulated ? 'SIMULATOR-QUELLZEIT' : 'QUELLZEIT'} ${timestamp(selected.sourceMs)}',
                  style: WorkstationTokens.mono(context,
                      size: 9.5,
                      color: selected.simulated ? OipTokens.violet : null)),
              if (selected.virtualTimeMs != null)
                Text(context.tr("VIRTUAL +{0} ms", [selected.virtualTimeMs]),
                    style: WorkstationTokens.mono(context, size: 9.5)),
            ]),
            OverviewTrendChart(
              key: chartKey,
              samples: controller.history,
              gaps: gaps,
              unit: selected.symbol,
              simulated: selected.simulated,
              height: MediaQuery.sizeOf(context).height >= 1000 ? 230 : 156,
            ),
            Text(
              context.tr(
                  "Session-lokal · keine persistierte History · Linien nur zwischen gültigen, zeitnahen Samples ohne belegte Gap. Freshness folgt dem Core, nicht der virtuellen Wanduhr."),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ]),
      ),
    );
  }

  Widget _mobilePaneSelector() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final entry in [
            (
              _OverviewMobilePane.explorer,
              'Explorer',
              Icons.account_tree_outlined
            ),
            (_OverviewMobilePane.focus, 'Focus', Icons.sensors),
            (_OverviewMobilePane.inspector, 'Inspector', Icons.info_outline),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: Key('overview-mobile-pane-${entry.$1.name}'),
                avatar: Icon(entry.$3, size: 15),
                label: Text(entry.$2),
                selected: mobilePane == entry.$1,
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => setState(() => mobilePane = entry.$1),
              ),
            ),
        ]),
      );

  void _selectSource(SourceInfo source) {
    setState(() {
      selection = OverviewSelection.source(source.id);
      if (MediaQuery.sizeOf(context).width < OipTokens.tablet) {
        mobilePane = _OverviewMobilePane.focus;
      }
    });
    controller.revealInspector(WorkspaceId.overview);
    _selectPreferred(sourceId: source.id);
  }

  void _selectDevice(Device device) {
    setState(() {
      selection = OverviewSelection.device(device.sourceId, device.id);
      if (MediaQuery.sizeOf(context).width < OipTokens.tablet) {
        mobilePane = _OverviewMobilePane.focus;
      }
    });
    controller.revealInspector(WorkspaceId.overview);
    _selectPreferred(sourceId: device.sourceId, deviceId: device.id);
  }

  void _selectEvent(CollectionEvent event) {
    setState(() {
      selection =
          OverviewSelection.event(event.sourceId, overviewEventKey(event));
      if (MediaQuery.sizeOf(context).width < OipTokens.tablet) {
        mobilePane = _OverviewMobilePane.inspector;
      }
    });
    controller.revealInspector(WorkspaceId.overview);
    _selectPreferred(sourceId: event.sourceId);
  }

  void _selectPreferred({String? sourceId, String? deviceId}) {
    final signal = preferredOverviewSignal(snapshot,
        sourceId: sourceId == '' ? null : sourceId, deviceId: deviceId);
    if (signal == null) {
      controller.clearTelemetry();
    } else {
      controller.selectTelemetry(observationKey(signal));
    }
  }

  void _selectSignal(String key) {
    final signal = snapshot.metrics
        .where((item) => observationKey(item) == key)
        .firstOrNull;
    if (signal == null) return;
    final device = snapshot.devices
        .where((item) => item.id == signal.entityId)
        .firstOrNull;
    setState(() {
      selection = device == null
          ? OverviewSelection.source(signal.sourceId ?? '')
          : OverviewSelection.device(signal.sourceId ?? '', device.id);
    });
    controller.selectTelemetry(key);
  }

  List<OverviewAttentionEntry> _attentionEntries() {
    final result = <OverviewAttentionEntry>[
      ...snapshot.incidents.map((incident) => OverviewAttentionEntry(
            title:
                '${incident.title} · ${incident.simulated ? 'Simulation' : 'Backend'}',
            detail:
                'FINDING · ${incident.simulated ? 'SIMULATED' : 'REPORTED'} · ${incident.deviceId} · keine Severity/Ursache geliefert',
            tone: 'degraded',
            icon: Icons.radar,
            diagnostics: true,
          )),
      ...sources
          .where((source) => source.connection != 'connected')
          .map((source) => OverviewAttentionEntry(
                title: '${source.name}: ${known(source.connection)}',
                detail: source.lastError ??
                    'SourceHealth disconnected · aktueller Core-Status',
                tone: 'stale',
                icon: Icons.link_off_outlined,
                diagnostics: true,
              )),
    ];
    final stale =
        snapshot.metrics.where((signal) => signal.freshness == 'stale').length;
    if (stale > 0) {
      result.add(OverviewAttentionEntry(
          title: '$stale Signal(e) stale',
          detail: 'Letzte bekannte Observationen · kein aktuelles Live-Signal',
          tone: 'stale',
          icon: Icons.schedule_outlined));
    }
    final gap = events
        .where((event) => event.gapMs != null && event.gapMs! > 0)
        .lastOrNull;
    if (gap != null) {
      result.add(OverviewAttentionEntry(
          title: 'Documented Data Gap · ${gap.gapMs} ms',
          detail:
              '${gap.kind} · ${gap.sourceId ?? 'Source nicht projiziert'} · ${timestamp(gap.atMs ?? gap.gapEndedMs)}',
          tone: 'degraded',
          icon: Icons.space_bar_outlined,
          event: gap));
    }
    if (snapshot.system.network == 'unknown' || snapshot.topology.isEmpty) {
      result.add(const OverviewAttentionEntry(
          title: 'Network Reachability unverified',
          detail:
              'Kein aktiver Probe · Registry/Reported getrennt von gemessener Erreichbarkeit',
          tone: 'unknown',
          icon: Icons.network_check_outlined));
    }
    if (snapshot.system.cpu == null &&
        snapshot.system.gpu == null &&
        snapshot.system.ram == null) {
      result.add(const OverviewAttentionEntry(
          title: 'Host-Telemetrie nicht integriert',
          detail: 'CPU/GPU/RAM Collector unavailable · kein gemessener Ausfall',
          tone: 'unknown',
          icon: Icons.memory_outlined));
    }
    return result;
  }
}

String _freshness(List<Observation> metrics) {
  if (metrics.isEmpty) return 'unknown';
  if (metrics.every((item) => item.freshness == 'fresh')) return 'fresh';
  if (metrics.any((item) => item.freshness == 'fresh')) return 'mixed';
  if (metrics.any((item) => item.freshness == 'stale')) return 'stale';
  return 'unknown';
}

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
