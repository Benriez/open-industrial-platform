import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/controller.dart';
import '../device_onboarding.dart';
import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import '../../models/infrastructure.dart';
import '../../widgets/adaptive_workspace.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'device_comparison.dart';
import 'service_registry.dart';
import 'device_detail.dart';
import 'device_inventory.dart';
import 'device_session.dart';
import 'devices_layout.dart';
import '../../core/keyboard.dart';

enum DevicesWorkspaceMode { devices, services, health }

enum DevicesMobilePane { explorer, detail, inspector, compare }

class DevicesPage extends StatefulWidget {
  final OipController controller;
  final void Function(int) navigate;
  final DevicesWorkspaceSession? session;
  const DevicesPage(this.controller, this.navigate, {super.key, this.session});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  late final DevicesWorkspaceSession session;
  late final TextEditingController searchController;
  final FocusNode searchFocus = FocusNode(debugLabel: 'device-search');
  final FocusNode pageFocus = FocusNode(debugLabel: 'devices-workstation');
  DevicesWorkspaceMode mode = DevicesWorkspaceMode.devices;
  DevicesMobilePane mobilePane = DevicesMobilePane.explorer;
  List<Observation> detailMetrics = const [];
  bool detailLoading = false;
  Object? detailError;
  int requestGeneration = 0;
  String? compareMessage;

  /// Mirrors the layout tier decided in the responsive branch so event
  /// handlers use the same threshold (content width, not viewport width).
  bool layoutIsMobile = false;

  @override
  void initState() {
    super.initState();
    session = widget.session ?? DevicesWorkspaceSession();
    searchController = TextEditingController(text: session.search);
    // The shell preserves selection across module navigation, but DeviceDetail
    // belongs to this page's request lifecycle. Reload it instead of showing a
    // false "no telemetry" state with the previous page's empty request state.
    final persisted = widget.controller.snapshot?.devices
        .where((device) => device.id == session.selectedId)
        .firstOrNull;
    if (persisted != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && session.selectedId == persisted.id) {
          _loadMetrics(persisted);
        }
      });
    }
  }

  /// Last observed primary-source scope. The controller is a shared reference,
  /// so the previous scope must be captured in State, not read from oldWidget
  /// (whose controller already points at the new snapshot).
  String? scopeSignature;

  void _reconcileScope() {
    final signature = widget.controller.contextScopeSignature;
    if (scopeSignature != null && scopeSignature != signature) {
      // A new authorization scope invalidates every selection and request.
      requestGeneration++;
      widget.controller.api.cancelDeviceRequests();
      session.selectedId = null;
      session.pinned.clear();
      session.recents.clear();
      session.compare.clear();
      session.offset = 0;
      detailMetrics = const [];
      detailError = null;
      detailLoading = false;
      mobilePane = DevicesMobilePane.explorer;
    }
    final ids = snapshot.devices.map((item) => item.id).toSet();
    session.pinned.removeWhere((id) => !ids.contains(id));
    session.compare.removeWhere((id) => !ids.contains(id));
    session.recents.removeWhere((id) => !ids.contains(id));
    if (session.selectedId != null && !ids.contains(session.selectedId!)) {
      session.selectedId = null;
      detailMetrics = const [];
      detailError = null;
      detailLoading = false;
    }
    scopeSignature = signature;
  }

  @override
  void dispose() {
    requestGeneration++;
    widget.controller.api.cancelDeviceRequests();
    searchController.dispose();
    searchFocus.dispose();
    pageFocus.dispose();
    super.dispose();
  }

  Snapshot get snapshot => widget.controller.snapshot!;
  List<SourceInfo> get sources =>
      widget.controller.operationalSources.isNotEmpty
          ? widget.controller.operationalSources
          : snapshot.sources;
  Device? get selectedDevice => snapshot.devices
      .where((item) => item.id == session.selectedId)
      .firstOrNull;

  /// The inventory record of the selected device.
  ///
  /// The administration of a device writes against the inventory of the Core,
  /// so it needs the record with its revision, not only the device of the
  /// session snapshot.
  InventoryDevice? get _inventoryRecord {
    final current = selectedDevice;
    if (current == null) return null;
    final inventory = widget.controller.infrastructure.inventory ?? const [];
    for (final record in inventory) {
      if (record.id == current.id) return record;
    }
    return null;
  }

  /// The administration writes change the inventory of the Core. The
  /// authorized projection is read again, so the surface shows the state the
  /// Core actually holds.
  Future<void> _refreshInventory() async {
    await widget.controller.resyncInfrastructure();
  }

  List<Observation> get displayMetrics {
    // DeviceDetail defines the authorized metric set. SSE may only replace an
    // exact source/entity/metric identity; it can never add another device's data.
    return detailMetrics.map((detail) {
      return snapshot.metrics
              .where((live) =>
                  live.sourceId == detail.sourceId &&
                  live.entityId == detail.entityId &&
                  live.metricId == detail.metricId)
              .firstOrNull ??
          detail;
    }).toList();
  }

  KeyEventResult _pageKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // Text input is never captured: while the search field owns the focus,
    // every key belongs to the field and only Escape is interpreted.
    if (searchFocus.hasFocus) {
      if (key == LogicalKeyboardKey.escape) {
        searchController.clear();
        session.search = '';
        session.offset = 0;
        searchFocus.unfocus();
        setState(() {});
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // A field of the inspector is a field of the page too: while it is
    // edited, every key belongs to the field.
    if (aTextFieldHasTheFocus()) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.slash) {
      searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (session.selectedId != null) {
        _closeDetails();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final device = selectedDevice;
    if (device == null) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.keyP) {
      _togglePin(device);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      _toggleCompare(device);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _selectDevice(Device device) {
    setState(() {
      session.select(device);
      if (layoutIsMobile) {
        mobilePane = DevicesMobilePane.detail;
      }
    });
    widget.controller.revealInspector(WorkspaceId.devices);
    _loadMetrics(device);
  }

  /// Pointer selection and Enter open a device and make the page shortcuts
  /// available. Arrow/Home/End intentionally do not call this: their focus
  /// must stay in the inventory list for continuous keyboard navigation.
  void _openSelectedDevice() {
    if (!searchFocus.hasFocus) pageFocus.requestFocus();
  }

  Future<void> _loadMetrics(Device device) async {
    final generation = ++requestGeneration;
    widget.controller.api.cancelDeviceRequests();
    setState(() {
      detailMetrics = const [];
      detailError = null;
      detailLoading = true;
    });
    try {
      final values = await widget.controller.api
          .contextDeviceMetrics(device.id, widget.controller.infrastructure);
      if (!mounted ||
          generation != requestGeneration ||
          session.selectedId != device.id) {
        return;
      }
      setState(() {
        detailMetrics = values;
        // A successful retry must clear the previous failure; otherwise the
        // workspace keeps showing the error although data is available again.
        detailError = null;
        detailLoading = false;
      });
    } catch (error) {
      if (!mounted ||
          generation != requestGeneration ||
          session.selectedId != device.id) {
        return;
      }
      setState(() {
        detailMetrics = const [];
        detailError = error;
        detailLoading = false;
      });
    }
  }

  void _closeDetails() {
    requestGeneration++;
    widget.controller.api.cancelDeviceRequests();
    setState(() {
      session.selectedId = null;
      detailMetrics = const [];
      detailError = null;
      detailLoading = false;
      mobilePane = DevicesMobilePane.explorer;
    });
    widget.controller.setInspectorOpen(WorkspaceId.devices, false);
  }

  void _togglePin(Device device) {
    setState(() {
      if (!session.pinned.remove(device.id)) session.pinned.add(device.id);
    });
  }

  void _toggleCompare(Device device) {
    setState(() {
      compareMessage = null;
      if (session.compare.remove(device.id)) return;
      if (session.compare.length >= 4) {
        compareMessage = 'Der Vergleich ist auf vier Geräte begrenzt.';
        return;
      }
      session.compare.add(device.id);
      // A comparison the user cannot see is not a result. The first device
      // opens the comparison strip.
      session.compareExpanded = true;
    });
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label kopiert: $value')));
  }

  @override
  Widget build(BuildContext context) {
    _reconcileScope();
    return Focus(
      focusNode: pageFocus,
      autofocus: true,
      onKeyEvent: _pageKey,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(),
          const SizedBox(height: DevicesLayout.sectionGap),
          _contextBar(),
          const SizedBox(height: DevicesLayout.sectionGap),
          _modeBar(),
          const SizedBox(height: DevicesLayout.sectionGap),
          if (compareMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(compareMessage!,
                  style: TextStyle(
                      color: OipTokens.statusColor(context, 'degraded'))),
            ),
          switch (mode) {
            DevicesWorkspaceMode.services => SizedBox(
                height: 520,
                child: ServiceRegistryPanel(
                    services: widget.controller.infrastructure.services)),
            DevicesWorkspaceMode.health => SizedBox(
                height: 560,
                child: DeviceInventoryHealth(
                    snapshot: snapshot, sources: sources)),
            DevicesWorkspaceMode.devices => _devicesWorkspace(),
          },
        ]),
      ),
    );
  }

  Widget _header() => AdaptiveWorkspaceHeader(
        key: const Key('devices-page-header'),
        eyebrow: 'DEVICES & SERVICES · OBJECT WORKSPACE',
        title: 'Geräte & Dienste',
        subtitle: '',
        accent: OipTokens.blue,
        primaryAction: WorkspacePrimaryAction(
          buttonKey: const Key('devices-add-primary'),
          label: 'Gerät hinzufügen',
          tooltip:
              'Sicheren lokalen Registrierungsweg anzeigen; kein Browser-Write',
          icon: Icons.add,
          onPressed: _showDeviceOnboarding,
        ),
        actions: [
          InspectorOpenAction(
            controller: widget.controller,
            workspace: WorkspaceId.devices,
            hasSelection: selectedDevice != null,
            onOpen: () {
              if (layoutIsMobile) {
                setState(() => mobilePane = DevicesMobilePane.inspector);
              }
            },
          ),
          WorkspaceLayoutAction(
              controller: widget.controller, workspace: WorkspaceId.devices),
        ],
        status: [
          StatusPill(
            snapshot.system.simulated
                ? 'DEMO / SIMULIERTES INVENTAR'
                : 'API-INVENTAR',
            color: OipTokens.statusColor(context, 'info'),
            icon: snapshot.system.simulated
                ? Icons.science_outlined
                : Icons.cloud_done_outlined,
          ),
          const StatusPill('READ-ONLY', icon: Icons.lock_outline),
          if (mode == DevicesWorkspaceMode.devices)
            Text(
              '${filteredDevices(snapshot, session).length} von '
              '${snapshot.devices.length} Geräten · '
              '${snapshot.system.simulated ? 'Simuliertes Inventar' : 'API-Inventar'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      );

  void _showDeviceOnboarding() {
    // An authorized session provides a secure browser write path for the
    // Core's own connection management. Without that session the action stays
    // a local operator hint and never pretends to register a device.
    if (widget.controller.managed &&
        widget.controller.management != null) {
      showDeviceOnboarding(context, widget.controller);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('device-onboarding-dialog'),
        icon: const Icon(Icons.admin_panel_settings_outlined),
        title: const Text('Gerät lokal registrieren'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: const Text(
            'Ein sicherer Browser-Schreibpfad ist nicht verfügbar. '
            'Registrierung bleibt eine Offline-Aufgabe des lokalen Operators: '
            'Gerät mit stabiler ID und tatsächlichem Site-Placement über den '
            'lokalen OIP-Operator-Contract erfassen, danach Core gemäß '
            'RequiresRestart neu starten. Diese Ansicht erzeugt weder ein '
            'Gerät noch eine Source und meldet keinen falschen Erfolg.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Schließen'),
          ),
          FilledButton.icon(
            key: const Key('device-onboarding-open-settings'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              widget.navigate(5);
            },
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Operator-Hinweise öffnen'),
          ),
        ],
      ),
    );
  }

  Widget _contextBar() => WorkstationPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: LayoutBuilder(builder: (context, box) {
          final facts = [
            (
              'SCOPE',
              widget.controller.infrastructure.ready
                  ? 'Autorisierter v2-Scope'
                  : 'Autorisierter v1-Snapshot'
            ),
            ('SOURCES', '${sources.length} geliefert'),
            ('REGISTRY', '${snapshot.devices.length} Geräte'),
            ('EMPFANG', timestamp(snapshot.system.lastReceivedMs)),
            (
              'PROVENIENZ',
              snapshot.system.simulated
                  ? 'SIMULATED / REPORTED / OBSERVED'
                  : 'REPORTED / OBSERVED'
            ),
            (
              'ORG / SITE',
              widget.controller.infrastructure.ready
                  ? widget.controller.infrastructure.selectedBreadcrumb
                  : 'Nicht im v1-Vertrag'
            ),
          ];
          final columns = box.maxWidth < 520
              ? 2
              : box.maxWidth < 900
                  ? 3
                  : 6;
          final width = (box.maxWidth - (columns - 1) * 8) / columns;
          return Wrap(
            spacing: 8,
            runSpacing: 4,
            children: facts
                .map((fact) =>
                    SizedBox(width: width, child: _fact(fact.$1, fact.$2)))
                .toList(),
          );
        }),
      );

  Widget _fact(String label, String value) => Row(children: [
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
              style: WorkstationTokens.mono(context, size: 10)),
        ),
      ]);

  Widget _modeBar() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final entry in [
            (DevicesWorkspaceMode.devices, 'Devices', Icons.dns_outlined),
            (
              DevicesWorkspaceMode.services,
              'Services',
              Icons.account_tree_outlined
            ),
            (
              DevicesWorkspaceMode.health,
              'Inventory Health',
              Icons.fact_check_outlined
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: Key('devices-mode-${entry.$1.name}'),
                avatar: Icon(entry.$3, size: 14),
                label: Text(entry.$2, style: const TextStyle(fontSize: 11.5)),
                selected: mode == entry.$1,
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                onSelected: (_) => setState(() => mode = entry.$1),
              ),
            ),
        ]),
      );

  Widget _devicesWorkspace() {
    final filter = DeviceFilterBar(
      snapshot: snapshot,
      session: session,
      searchController: searchController,
      searchFocus: searchFocus,
      changed: () => setState(() {}),
      infrastructure: widget.controller.infrastructure,
    );
    return Column(children: [
      filter,
      const SizedBox(height: DevicesLayout.sectionGap),
      LayoutBuilder(builder: (context, box) {
        layoutIsMobile = box.maxWidth < OipTokens.tablet;
        final explorer = DeviceInventoryExplorer(
          snapshot: snapshot,
          session: session,
          onSelect: _selectDevice,
          onPin: _togglePin,
          onCompare: _toggleCompare,
          onOpen: _openSelectedDevice,
          infrastructure: widget.controller.infrastructure,
        );
        final workspace = DeviceEngineeringWorkspace(
          device: selectedDevice,
          snapshot: snapshot,
          sources: sources,
          metrics: displayMetrics,
          loading: detailLoading,
          error: detailError,
          connection: widget.controller.connection,
          onRetry: () {
            final current = selectedDevice;
            if (current != null) _loadMetrics(current);
          },
          onClose: _closeDetails,
          navigate: widget.navigate,
          infrastructure: widget.controller.infrastructure,
          inventoryDevice: _inventoryRecord,
          controller: widget.controller,
        );
        final inspector = AdaptiveInspector(
          controller: widget.controller,
          workspace: WorkspaceId.devices,
          label: 'Gerätekontext & Provenienz',
          hasSelection: selectedDevice != null,
          child: DeviceContextInspector(
            device: selectedDevice,
            snapshot: snapshot,
            sources: sources,
            metrics: displayMetrics,
            pinned: selectedDevice != null &&
                session.pinned.contains(selectedDevice!.id),
            compared: selectedDevice != null &&
                session.compare.contains(selectedDevice!.id),
            onPin: _togglePin,
            onCompare: _toggleCompare,
            onCopy: _copy,
            navigate: widget.navigate,
            infrastructure: widget.controller.infrastructure,
            inventoryDevice: _inventoryRecord,
            management: widget.controller.management,
            onInventoryChanged: _refreshInventory,
          ),
        );
        final comparison = DeviceComparisonWorkspace(
          snapshot: snapshot,
          session: session,
          onRemove: _toggleCompare,
          onSelect: _selectDevice,
          navigate: widget.navigate,
          onToggle: () => setState(
              () => session.compareExpanded = !session.compareExpanded),
          infrastructure: widget.controller.infrastructure,
        );
        final viewport = MediaQuery.sizeOf(context).height;
        final showInspector = widget.controller
            .inspectorVisible(WorkspaceId.devices, selectedDevice != null);
        final showWorkspace = selectedDevice != null ||
            widget.controller.workspaces
                .layout(WorkspaceId.devices)
                .expertWorkspace;
        if (box.maxWidth >= OipTokens.workstation && !showWorkspace) {
          return Column(children: [
            SizedBox(height: 420, child: explorer),
            const SizedBox(height: DevicesLayout.panelGap),
            SizedBox(
              height: session.compareExpanded
                  ? DevicesLayout.comparisonExpanded
                  : (session.compare.isEmpty
                      ? DevicesLayout.comparisonEmpty
                      : DevicesLayout.comparisonCollapsed),
              child: comparison,
            ),
          ]);
        }
        if (box.maxWidth >= OipTokens.workstation) {
          // The shell owns the top bar, the scroll padding and the page
          // footer; the page owns the header, the scope strip, the mode tabs
          // and the filter bar. The workstation row takes what is left of the
          // viewport so the inventory starts as high as possible.
          // An expanded comparison strip takes its height from the
          // workstation row, so the page still fits into the viewport.
          final comparisonReserve = session.compareExpanded
              ? DevicesLayout.comparisonExpanded - DevicesLayout.comparisonEmpty
              : 0.0;
          final height =
              (viewport - 480 - comparisonReserve).clamp(300.0, 720.0);
          return Column(children: [
            SizedBox(
              height: height,
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                        width: box.maxWidth >= 1500 ? 278 : 258,
                        child: explorer),
                    const SizedBox(width: DevicesLayout.panelGap),
                    Expanded(child: workspace),
                    if (showInspector) ...[
                      const SizedBox(width: DevicesLayout.panelGap),
                      SizedBox(
                          width: box.maxWidth >= 1500 ? 310 : 286,
                          child: inspector),
                    ],
                  ]),
            ),
            const SizedBox(height: DevicesLayout.panelGap),
            SizedBox(
                height: session.compareExpanded
                    ? DevicesLayout.comparisonExpanded
                    : (session.compare.isEmpty
                        ? DevicesLayout.comparisonEmpty
                        : DevicesLayout.comparisonCollapsed),
                child: comparison),
          ]);
        }
        if (box.maxWidth >= OipTokens.tablet) {
          final comparisonReserve = session.compareExpanded
              ? DevicesLayout.comparisonExpanded - DevicesLayout.comparisonEmpty
              : 0.0;
          final height =
              (viewport - 430 - comparisonReserve).clamp(300.0, 560.0);
          return Column(children: [
            SizedBox(
              height: height,
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 250, child: explorer),
                    const SizedBox(width: DevicesLayout.panelGap),
                    Expanded(child: workspace),
                  ]),
            ),
            if (showInspector) ...[
              const SizedBox(height: DevicesLayout.panelGap),
              SizedBox(height: 420, child: inspector),
              const SizedBox(height: DevicesLayout.panelGap),
            ],
            SizedBox(
                height: session.compareExpanded
                    ? DevicesLayout.comparisonExpanded
                    : (session.compare.isEmpty
                        ? DevicesLayout.comparisonEmpty
                        : DevicesLayout.comparisonCollapsed),
                child: comparison),
          ]);
        }
        return Column(children: [
          _mobileSelector(),
          const SizedBox(height: DevicesLayout.panelGap),
          SizedBox(
            height: switch (mobilePane) {
              DevicesMobilePane.explorer => 520,
              DevicesMobilePane.detail => 560,
              DevicesMobilePane.inspector => 560,
              DevicesMobilePane.compare => 380,
            },
            child: switch (mobilePane) {
              DevicesMobilePane.explorer => explorer,
              DevicesMobilePane.detail => workspace,
              DevicesMobilePane.inspector => inspector,
              DevicesMobilePane.compare => comparison,
            },
          ),
        ]);
      }),
    ]);
  }

  Widget _mobileSelector() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final entry in [
            (DevicesMobilePane.explorer, 'Explorer', Icons.dns_outlined),
            (DevicesMobilePane.detail, 'Details', Icons.engineering_outlined),
            (DevicesMobilePane.inspector, 'Inspector', Icons.info_outline),
            (DevicesMobilePane.compare, 'Compare', Icons.compare_outlined),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: Key('devices-mobile-${entry.$1.name}'),
                avatar: Icon(entry.$3, size: 15),
                label: Text(entry.$2),
                selected: mobilePane == entry.$1,
                showCheckmark: false,
                onSelected: (_) => setState(() => mobilePane = entry.$1),
              ),
            ),
        ]),
      );
}
