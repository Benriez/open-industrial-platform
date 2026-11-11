import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/controller.dart';
import '../design_system/theme.dart';
import '../models/contracts.dart';
import '../widgets/adaptive_workspace.dart';
import '../widgets/components.dart';
import '../widgets/workstation.dart';
import 'devices.dart';
import 'network/network_compare.dart';
import 'network/network_explorer.dart';
import 'network/network_graph.dart';
import 'network/network_model.dart';
import '../widgets/device_kind.dart';

enum _NetworkMode { topology, connections, vpn, diagnostics, compare }

enum _MobilePane { primary, explorer, inspector }

/// Network engineering explorer over the existing snapshot contract.
///
/// The page never discovers devices, probes endpoints or creates VPN state.
/// Registry health, logical links, measured facts and demo fixtures remain
/// explicitly separate. Pins, recents and comparisons are bounded UI-session
/// state and are never presented as persisted preferences.
class NetworkPage extends StatefulWidget {
  final OipController controller;
  const NetworkPage(this.controller, {super.key});

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  static const maxPins = 8;
  static const maxRecent = 6;
  static const maxCompare = 4;

  final transformation = TransformationController();
  final searchController = TextEditingController();
  final searchFocus = FocusNode(debugLabel: 'network-search');
  final listFocus = FocusNode(debugLabel: 'network-device-list');
  final graphFocus = FocusNode(debugLabel: 'network-graph');
  final inspectorFocus = FocusNode(debugLabel: 'network-inspector');

  final pinned = <String, Device>{};
  final comparedDevices = <String, Device>{};
  final comparedEdges = <String, NetworkEdge>{};
  final recentIds = <String>[];

  _NetworkMode mode = _NetworkMode.connections;
  _MobilePane mobilePane = _MobilePane.primary;
  String? selectedId, selectedEdgeId;
  String? kindFilter, statusFilter, transportFilter, edgeStatusFilter;
  String query = '';
  NetworkRelationFilter relationFilter = NetworkRelationFilter.all;
  NetworkDeviceSort deviceSort = NetworkDeviceSort.name;
  String? scopeSignature;
  String contextGrouping = 'infrastructure';
  bool neighborsOnly = false;
  bool showEdgeLabels = true;
  bool showFilters = false;
  bool tabletExplorer = false;
  bool tabletInspector = false;
  Size graphViewport = Size.zero;
  bool fitRequested = true;
  bool fitScheduled = false;
  bool userCameraUsed = false;
  bool preserveNextViewport = false;

  @override
  void initState() {
    super.initState();
    final preference = widget.controller.workspaces.layout(WorkspaceId.network);
    mode = _NetworkMode.values
            .where((item) => item.name == preference.view)
            .firstOrNull ??
        _NetworkMode.connections;
    showFilters = preference.advancedFilters;
  }

  @override
  void dispose() {
    transformation.dispose();
    searchController.dispose();
    searchFocus.dispose();
    listFocus.dispose();
    graphFocus.dispose();
    inspectorFocus.dispose();
    super.dispose();
  }

  bool get transportLive => widget.controller.connection == 'live';

  void _zoom(double factor) {
    userCameraUsed = true;
    final current = transformation.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(.35, 2.5).toDouble();
    if (graphViewport == Size.zero) return;
    final focus = Offset(graphViewport.width / 2, graphViewport.height / 2);
    final translation = transformation.value.getTranslation();
    final origin = Offset(translation.x, translation.y);
    final contentFocus = (focus - origin) / current;
    _setTransform(next, focus - contentFocus * next);
  }

  void _setTransform(double scale, Offset translation) {
    userCameraUsed = true;
    transformation.value = Matrix4.identity()
      ..scale(scale)
      ..setTranslationRaw(translation.dx, translation.dy, 0);
  }

  void _fit(TopologyLayout layout, {bool user = false}) {
    if (user) userCameraUsed = true;
    if (graphViewport == Size.zero) {
      fitRequested = true;
      return;
    }
    final readableMin = graphViewport.width < 600 ? .55 : .35;
    transformation.value = networkFitTransform(
        layout.contentBounds, graphViewport,
        min: readableMin);
    fitRequested = false;
  }

  void _scheduleFit(TopologyLayout layout) {
    if (!fitRequested || fitScheduled || graphViewport == Size.zero) return;
    fitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fitScheduled = false;
      if (mounted && fitRequested) _fit(layout);
    });
  }

  void _viewportChanged(Size size, TopologyLayout layout) {
    final previous = graphViewport;
    if (preserveNextViewport && previous != Size.zero && previous != size) {
      // Selection-only toolbar chrome must not refit or recentre an already
      // visible node. The smaller clip still contains the original selection.
      graphViewport = size;
      preserveNextViewport = false;
      return;
    }
    if (previous != Size.zero &&
        previous != size &&
        userCameraUsed &&
        !fitRequested) {
      final scale = transformation.value.getMaxScaleOnAxis();
      final oldTranslation = transformation.value.getTranslation();
      final oldCentre = Offset(previous.width / 2, previous.height / 2);
      final contentCentre =
          (oldCentre - Offset(oldTranslation.x, oldTranslation.y)) / scale;
      _setTransform(scale,
          Offset(size.width / 2, size.height / 2) - contentCentre * scale);
    }
    graphViewport = size;
    if (!userCameraUsed) fitRequested = true;
    if (fitRequested) _fit(layout);
  }

  bool _selectionFullyVisible(TopologyLayout layout) =>
      selectedId != null && _deviceFullyVisible(selectedId!, layout);

  bool _deviceFullyVisible(String deviceId, TopologyLayout layout) {
    if (graphViewport == Size.zero) return false;
    final position = layout.positions[deviceId];
    if (position == null) return false;
    final scale = transformation.value.getMaxScaleOnAxis();
    final translation = transformation.value.getTranslation();
    final origin = Offset(translation.x, translation.y);
    final node = Rect.fromLTWH(position.dx, position.dy,
        TopologyLayout.nodeWidth, TopologyLayout.nodeHeight);
    final transformed = Rect.fromLTWH(origin.dx + node.left * scale,
        origin.dy + node.top * scale, node.width * scale, node.height * scale);
    final viewport =
        Rect.fromLTWH(0, 0, graphViewport.width, graphViewport.height);
    return transformed.left >= viewport.left &&
        transformed.top >= viewport.top &&
        transformed.right <= viewport.right &&
        transformed.bottom <= viewport.bottom;
  }

  void _focusSelection(TopologyLayout layout, {bool onlyIfNeeded = false}) {
    if (onlyIfNeeded && _selectionFullyVisible(layout)) return;
    Offset? center;
    if (selectedId != null) center = layout.center(selectedId!);
    if (selectedEdgeId != null) {
      final edge = networkEdges(widget.controller.snapshot!)
          .where((item) => item.id == selectedEdgeId)
          .firstOrNull;
      if (edge != null) {
        final endpoints = networkEdgeEndpoints(layout, edge.link);
        if (endpoints != null) center = (endpoints.$1 + endpoints.$2) / 2;
      }
    }
    if (center == null || graphViewport == Size.zero) return;
    final scale = transformation.value.getMaxScaleOnAxis();
    _setTransform(
        scale,
        Offset(graphViewport.width / 2, graphViewport.height / 2) -
            center * scale);
  }

  void _selectFromExplorer(Device device) {
    final snapshot = widget.controller.snapshot!;
    final layout = _topologyLayout(snapshot);
    final graphAvailable = MediaQuery.of(context).size.width >= 600;
    final alreadyVisible = graphAvailable &&
        layout.positions.containsKey(device.id) &&
        _deviceFullyVisible(device.id, layout);
    if (alreadyVisible) preserveNextViewport = true;
    setState(() {
      selectedId = device.id;
      selectedEdgeId = null;
      if (!layout.positions.containsKey(device.id)) neighborsOnly = false;
      _remember(device);
      if (MediaQuery.of(context).size.width < 600) {
        mobilePane = _MobilePane.inspector;
      }
    });
    widget.controller.revealInspector(WorkspaceId.network);
    if (layout.positions.containsKey(device.id) && graphAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && selectedId == device.id && !alreadyVisible) {
          _focusSelection(layout, onlyIfNeeded: true);
        }
        if (alreadyVisible) {
          // LayoutBuilder reports its new viewport in this frame's post-frame
          // callbacks. Clear the one-shot guard only after that delivery.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            preserveNextViewport = false;
          });
        }
      });
    }
  }

  void _selectGraphNode(Device device) {
    setState(() {
      selectedId = device.id;
      selectedEdgeId = null;
      _remember(device);
    });
    widget.controller.revealInspector(WorkspaceId.network);
    // Preserve the existing graph-to-detail navigation used by the shared
    // browser regression. Explorer selection itself stays in the workstation.
    showDevice(context, widget.controller, device);
  }

  void _selectNodeFromInspector(Device device) {
    setState(() {
      selectedId = device.id;
      selectedEdgeId = null;
      if (networkDeviceEdges(
              device.id, networkEdges(widget.controller.snapshot!))
          .isEmpty) {
        neighborsOnly = false;
      }
      _remember(device);
    });
    widget.controller.revealInspector(WorkspaceId.network);
  }

  void _selectEdge(NetworkEdge edge) {
    widget.controller.revealInspector(WorkspaceId.network);
    setState(() {
      selectedEdgeId = edge.id;
      selectedId = null;
      if (MediaQuery.of(context).size.width < 600) {
        mobilePane = _MobilePane.inspector;
      }
    });
  }

  void _remember(Device device) {
    recentIds.remove(device.id);
    recentIds.insert(0, device.id);
    if (recentIds.length > maxRecent) recentIds.removeLast();
  }

  void _clearSelection() => setState(() {
        selectedId = null;
        selectedEdgeId = null;
        neighborsOnly = false;
      });

  void _clearSearch() {
    searchController.clear();
    setState(() {
      query = '';
      fitRequested = true;
    });
    searchFocus.requestFocus();
  }

  void _focusSearch() {
    final width = MediaQuery.of(context).size.width;
    setState(() {
      if (width < 600) {
        mobilePane = _MobilePane.explorer;
      } else if (width < 1080) {
        tabletExplorer = true;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) searchFocus.requestFocus();
    });
  }

  void _togglePin(Device device) => setState(() {
        if (pinned.containsKey(device.id)) {
          pinned.remove(device.id);
        } else if (pinned.length < maxPins) {
          pinned[device.id] = device;
        }
      });

  void _toggleCompareDevice(Device device) => setState(() {
        if (comparedDevices.containsKey(device.id)) {
          comparedDevices.remove(device.id);
        } else if (comparedDevices.length < maxCompare) {
          comparedDevices[device.id] = device;
        }
      });

  void _toggleCompareEdge(NetworkEdge edge) => setState(() {
        if (comparedEdges.containsKey(edge.id)) {
          comparedEdges.remove(edge.id);
        } else if (comparedEdges.length < maxCompare) {
          comparedEdges[edge.id] = edge;
        }
      });

  void _focusNode(Device device) {
    final layout = _topologyLayout(widget.controller.snapshot!);
    if (!layout.positions.containsKey(device.id)) return;
    setState(() {
      mode = _NetworkMode.topology;
      selectedId = device.id;
      selectedEdgeId = null;
      if (MediaQuery.of(context).size.width < 600) {
        mobilePane = _MobilePane.primary;
      }
    });
    widget.controller
        .setWorkspaceView(WorkspaceId.network, _NetworkMode.topology.name);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusSelection(layout);
    });
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label kopiert')));
  }

  void _reconcileSnapshot(Snapshot snapshot, List<NetworkEdge> edges) {
    final signature = widget.controller.contextScopeSignature;
    if (scopeSignature != null && scopeSignature != signature) {
      pinned.clear();
      comparedDevices.clear();
      comparedEdges.clear();
      recentIds.clear();
      selectedId = null;
      selectedEdgeId = null;
      contextGrouping = 'infrastructure';
      fitRequested = true;
    }
    scopeSignature = signature;
    final devices = {for (final device in snapshot.devices) device.id: device};
    pinned.removeWhere((id, _) => !devices.containsKey(id));
    comparedDevices.removeWhere((id, _) => !devices.containsKey(id));
    recentIds.removeWhere((id) => !devices.containsKey(id));
    final edgeIds = edges.map((edge) => edge.id).toSet();
    comparedEdges.removeWhere((id, _) => !edgeIds.contains(id));
    if (selectedId != null && !devices.containsKey(selectedId)) {
      selectedId = null;
    }
    if (selectedEdgeId != null && !edgeIds.contains(selectedEdgeId)) {
      selectedEdgeId = null;
    }
    for (final entry in pinned.entries.toList()) {
      pinned[entry.key] = devices[entry.key]!;
    }
    for (final entry in comparedDevices.entries.toList()) {
      comparedDevices[entry.key] = devices[entry.key]!;
    }
    for (final entry in comparedEdges.entries.toList()) {
      comparedEdges[entry.key] =
          edges.firstWhere((edge) => edge.id == entry.key);
    }
  }

  List<Device> _explorerDevices(Snapshot snapshot, List<NetworkEdge> edges) =>
      networkExplorerDevices(snapshot, edges,
          query: query,
          kind: kindFilter,
          status: statusFilter,
          relation: relationFilter,
          sort: deviceSort,
          transportLive: transportLive);

  List<Device> _visibleDevices(Snapshot snapshot, List<NetworkEdge> edges) {
    var devices = _explorerDevices(snapshot, edges);
    if (neighborsOnly && selectedId != null) {
      final neighbors = <String>{selectedId!};
      for (final link in snapshot.topology) {
        if (link.from == selectedId) neighbors.add(link.to);
        if (link.to == selectedId) neighbors.add(link.from);
      }
      devices =
          devices.where((device) => neighbors.contains(device.id)).toList();
    }
    return devices;
  }

  TopologyLayout _topologyLayout(Snapshot snapshot) {
    final edges = networkEdges(snapshot);
    final linked = networkLinkedDeviceIds(edges);
    final devices = _visibleDevices(snapshot, edges)
        .where((device) => linked.contains(device.id))
        .toList();
    return TopologyLayout.build(devices, _visibleEdges(snapshot, edges));
  }

  List<NetworkEdge> _visibleEdges(Snapshot snapshot, List<NetworkEdge> edges) {
    if (mode == _NetworkMode.connections) {
      return edges
          .where((edge) => networkEdgeMatches(
              edge, snapshot.devices, query, transportFilter, edgeStatusFilter))
          .toList();
    }
    final visible =
        _visibleDevices(snapshot, edges).map((device) => device.id).toSet();
    return edges
        .where((edge) =>
            visible.contains(edge.link.from) && visible.contains(edge.link.to))
        .toList();
  }

  KeyEventResult _pageKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final focus = FocusManager.instance.primaryFocus;
    final editing =
        focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (editing) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.slash) {
      _focusSearch();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f6) {
      if (searchFocus.hasFocus) {
        listFocus.requestFocus();
      } else if (listFocus.hasFocus && mode == _NetworkMode.topology) {
        graphFocus.requestFocus();
      } else {
        inspectorFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    final snapshot = widget.controller.snapshot;
    if (snapshot == null) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.keyF && mode == _NetworkMode.topology) {
      _fit(_topologyLayout(snapshot), user: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP && selectedId != null) {
      final device =
          snapshot.devices.where((item) => item.id == selectedId).firstOrNull;
      if (device != null) _togglePin(device);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      if (selectedId != null) {
        final device =
            snapshot.devices.where((item) => item.id == selectedId).firstOrNull;
        if (device != null) _toggleCompareDevice(device);
      } else if (selectedEdgeId != null) {
        final edge = networkEdges(snapshot)
            .where((item) => item.id == selectedEdgeId)
            .firstOrNull;
        if (edge != null) _toggleCompareEdge(edge);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _explorerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final snapshot = widget.controller.snapshot;
    if (snapshot == null) return KeyEventResult.ignored;
    final devices = _explorerDevices(snapshot, networkEdges(snapshot));
    if (devices.isEmpty) return KeyEventResult.ignored;
    final current = devices.indexWhere((device) => device.id == selectedId);
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _selectFromExplorer(
          devices[(current + 1 + devices.length) % devices.length]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _selectFromExplorer(
          devices[(current - 1 + devices.length) % devices.length]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _selectFromExplorer(devices.first);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _selectFromExplorer(devices.last);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && current >= 0) {
      inspectorFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP && current >= 0) {
      _togglePin(devices[current]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC && current >= 0) {
      _toggleCompareDevice(devices[current]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _graphKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final snapshot = widget.controller.snapshot;
    if (snapshot == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add) {
      _zoom(1.25);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus) {
      _zoom(.8);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit0) {
      _setTransform(1, Offset.zero);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      _fit(_topologyLayout(snapshot), user: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _clearSelection();
      return KeyEventResult.handled;
    }
    final devices = _topologyLayout(snapshot).devices;
    if (devices.isEmpty) return KeyEventResult.ignored;
    final current = devices.indexWhere((device) => device.id == selectedId);
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      _selectNodeFromInspector(
          devices[(current + 1 + devices.length) % devices.length]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      _selectNodeFromInspector(
          devices[(current - 1 + devices.length) % devices.length]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && current >= 0) {
      showDevice(context, widget.controller, devices[current]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.snapshot!;
    final edges = networkEdges(snapshot);
    _reconcileSnapshot(snapshot, edges);
    final layout = _topologyLayout(snapshot);
    if (mode == _NetworkMode.topology) _scheduleFit(layout);
    final relatedCount =
        selectedId == null ? 0 : networkDeviceEdges(selectedId!, edges).length;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (searchFocus.hasFocus && query.isNotEmpty) {
            _clearSearch();
          } else if (mode == _NetworkMode.compare) {
            _setMode(_NetworkMode.topology);
          } else {
            _clearSelection();
          }
        },
      },
      child: Focus(
        onKeyEvent: _pageKey,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(snapshot),
              const SizedBox(height: OipTokens.s3),
              _summary(snapshot, edges),
              const SizedBox(height: OipTokens.s3),
              _modeTabs(),
              const SizedBox(height: OipTokens.s3),
              _workstation(snapshot, edges, layout),
              const SizedBox(height: OipTokens.s3),
              _contextFooter(snapshot, relatedCount),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(Snapshot snapshot) {
    final hasSimulation = snapshot.system.simulated ||
        snapshot.devices.any((device) => device.simulated) ||
        snapshot.topology.any((link) => link.simulated);
    final compareCount = comparedDevices.length + comparedEdges.length;
    return AdaptiveWorkspaceHeader(
      eyebrow: 'NETWORK ENGINEERING EXPLORER · READ-ONLY',
      title: 'Netzwerk & VPN',
      subtitle:
          'Bekannte Geräte und gelieferte Beziehungen · keine aktiven Probes',
      accent: OipTokens.violet,
      primaryAction: WorkspacePrimaryAction(
        buttonKey: const Key('network-primary-connections'),
        label: 'Beziehungen prüfen',
        tooltip: 'Tatsächlich gelieferte Verbindungspfade untersuchen',
        icon: Icons.alt_route_outlined,
        onPressed: () => _setMode(_NetworkMode.connections),
      ),
      actions: [
        InspectorOpenAction(
          controller: widget.controller,
          workspace: WorkspaceId.network,
          hasSelection: selectedId != null || selectedEdgeId != null,
          onOpen: () => setState(() {
            if (MediaQuery.sizeOf(context).width < OipTokens.mobile) {
              mobilePane = _MobilePane.inspector;
            } else {
              tabletInspector = true;
            }
          }),
        ),
        ToolButton(
          key: const Key('network-compare-open'),
          icon: Icons.compare_arrows_outlined,
          tooltip: 'Network Compare öffnen · $compareCount ausgewählt',
          accent: OipTokens.cyan,
          active: mode == _NetworkMode.compare,
          onPressed: () => _setMode(_NetworkMode.compare),
        ),
      ],
      status: [
        NetworkBadge(
          transportLive ? 'API CONNECTED' : 'API STALE / UNBEKANNT',
          transportLive ? 'connected' : 'stale',
          icon: transportLive ? Icons.sensors : Icons.sync_problem_outlined,
        ),
        NetworkBadge(
          hasSimulation ? 'DEMO / SIMULATION' : 'API-INVENTAR',
          hasSimulation ? 'info' : 'connected',
          icon: hasSimulation ? Icons.science_outlined : Icons.cloud_outlined,
        ),
        // READ-ONLY is already stated by the eyebrow; keyboard shortcuts stay
        // active without forcing another header row at tablet widths.
      ],
    );
  }

  void _setMode(_NetworkMode value) {
    setState(() => mode = value);
    widget.controller.setWorkspaceView(WorkspaceId.network, value.name);
  }

  Widget _summary(Snapshot snapshot, List<NetworkEdge> edges) {
    final reachable = snapshot.devices
        .where((device) => device.health.reachability == 'reachable')
        .length;
    final unknown = snapshot.devices
        .where((device) => device.health.reachability == 'unknown')
        .length;
    final demoLinks = edges.where((edge) => edge.link.simulated).length;
    return NetworkSurface(
      key: const Key('network-summary'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Wrap(spacing: 0, runSpacing: 4, children: [
        NetworkSummaryItem('REGISTRIERTE NODES', '${snapshot.devices.length}',
            Icons.hub_outlined),
        NetworkSummaryItem(
            'LOGISCHE PFADE',
            snapshot.topologyDelivered ? '${edges.length}' : 'NICHT GELIEFERT',
            Icons.alt_route_outlined),
        NetworkSummaryItem(
            'ERREICHBAR GEMELDET', '$reachable', Icons.check_circle_outline,
            status: 'reachable'),
        NetworkSummaryItem('UNBEKANNT', '$unknown', Icons.help_outline,
            status: 'unknown'),
        NetworkSummaryItem('DEMO-PFADE', '$demoLinks', Icons.science_outlined,
            status: demoLinks > 0 ? 'info' : 'unknown'),
        const NetworkSummaryItem(
            'VPN-TELEMETRIE', 'Nicht verbunden', Icons.vpn_lock_outlined,
            status: 'unknown'),
      ]),
    );
  }

  Widget _modeTabs() {
    Widget tab(_NetworkMode value, String label, IconData icon) {
      final active = mode == value;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          key: Key('network-tab-${value.name}'),
          avatar: Icon(icon, size: 16),
          label: Text(label),
          selected: active,
          showCheckmark: false,
          onSelected: (_) => _setMode(value),
        ),
      );
    }

    return Wrap(runSpacing: 6, children: [
      tab(_NetworkMode.topology, 'Topologie', Icons.hub_outlined),
      tab(_NetworkMode.connections, 'Verbindungspfade',
          Icons.alt_route_outlined),
      tab(_NetworkMode.vpn, 'VPN', Icons.vpn_lock_outlined),
      tab(_NetworkMode.diagnostics, 'Diagnostik', Icons.troubleshoot_outlined),
      tab(
          _NetworkMode.compare,
          'Vergleich ${comparedDevices.length + comparedEdges.length}',
          Icons.compare_arrows_outlined),
    ]);
  }

  Widget _explorer(Snapshot snapshot, List<NetworkEdge> edges) {
    final devicesById = {
      for (final device in snapshot.devices) device.id: device
    };
    return NetworkDeviceExplorer(
      snapshot: snapshot,
      edges: edges,
      devices: _explorerDevices(snapshot, edges),
      recent: [
        for (final id in recentIds)
          if (devicesById[id] != null) devicesById[id]!
      ],
      pinned: pinned.keys.toSet(),
      compared: comparedDevices.keys.toSet(),
      selectedId: selectedId,
      query: query,
      kindFilter: kindFilter,
      statusFilter: statusFilter,
      relationFilter: relationFilter,
      sort: deviceSort,
      transportLive: transportLive,
      showFilters: showFilters,
      searchController: searchController,
      searchFocus: searchFocus,
      listFocus: listFocus,
      onQuery: (value) => setState(() {
        query = value;
        fitRequested = true;
      }),
      onClearSearch: _clearSearch,
      onToggleFilters: () {
        setState(() => showFilters = !showFilters);
        widget.controller.setAdvancedFilters(WorkspaceId.network, showFilters);
      },
      onKind: (value) => setState(() {
        kindFilter = value;
        fitRequested = true;
      }),
      onStatus: (value) => setState(() {
        statusFilter = value;
        fitRequested = true;
      }),
      onRelation: (value) => setState(() {
        relationFilter = value;
        fitRequested = true;
      }),
      onSort: (value) => setState(() => deviceSort = value),
      onSelect: _selectFromExplorer,
      onPin: _togglePin,
      onCompare: _toggleCompareDevice,
      onKeyEvent: _explorerKey,
      infrastructure: widget.controller.infrastructure,
      contextGrouping: contextGrouping,
      onContextGrouping: (value) =>
          setState(() => contextGrouping = value ?? 'none'),
    );
  }

  Widget _workstation(
      Snapshot snapshot, List<NetworkEdge> edges, TopologyLayout layout) {
    final hasSelection = selectedId != null || selectedEdgeId != null;
    final showInspector =
        widget.controller.inspectorVisible(WorkspaceId.network, hasSelection);
    Widget inspector() => AdaptiveInspector(
          controller: widget.controller,
          workspace: WorkspaceId.network,
          label: 'Netzwerkbeziehungen & Evidence',
          hasSelection: hasSelection,
          child: _inspector(snapshot, edges),
        );
    final primary = switch (mode) {
      _NetworkMode.topology => _topologyPrimary(snapshot, edges, layout),
      _NetworkMode.connections => _connectionsWorkspace(snapshot, edges),
      _NetworkMode.vpn => _vpnWorkspace(snapshot, edges),
      _NetworkMode.diagnostics => _diagnosticsWorkspace(snapshot, edges),
      _NetworkMode.compare => _compareWorkspace(snapshot, bounded: true),
    };
    return LayoutBuilder(builder: (context, box) {
      final viewportHeight = MediaQuery.of(context).size.height;
      if (box.maxWidth >= 1080) {
        final height = (viewportHeight - 380).clamp(540.0, 760.0);
        return SizedBox(
          height: height,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 240, child: _explorer(snapshot, edges)),
            const SizedBox(width: OipTokens.s3),
            Expanded(child: primary),
            if (showInspector) ...[
              const SizedBox(width: OipTokens.s3),
              SizedBox(width: 330, child: inspector()),
            ],
          ]),
        );
      }
      if (box.maxWidth >= 600) {
        return Column(children: [
          NetworkSurface(
            padding: const EdgeInsets.all(7),
            child: Wrap(spacing: 7, runSpacing: 6, children: [
              FilterChip(
                key: const Key('network-tablet-explorer'),
                avatar: const Icon(Icons.list_alt, size: 16),
                label: const Text('Device Explorer'),
                selected: tabletExplorer,
                onSelected: (value) => setState(() => tabletExplorer = value),
              ),
              FilterChip(
                key: const Key('network-tablet-inspector'),
                avatar: const Icon(Icons.info_outline, size: 16),
                label: const Text('Context Inspector'),
                selected: tabletInspector,
                onSelected: (value) {
                  setState(() => tabletInspector = value);
                  widget.controller
                      .setInspectorOpen(WorkspaceId.network, value);
                },
              ),
            ]),
          ),
          if (tabletExplorer) ...[
            const SizedBox(height: OipTokens.s3),
            SizedBox(height: 520, child: _explorer(snapshot, edges)),
          ],
          const SizedBox(height: OipTokens.s3),
          SizedBox(
              height: mode == _NetworkMode.topology
                  ? (viewportHeight - 400).clamp(300.0, 520.0)
                  : 610,
              child: primary),
          if (tabletInspector) ...[
            const SizedBox(height: OipTokens.s3),
            SizedBox(height: 620, child: inspector()),
          ],
        ]);
      }
      return Column(children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_MobilePane>(
            segments: const [
              ButtonSegment(
                  value: _MobilePane.primary,
                  icon: Icon(Icons.hub_outlined, size: 16),
                  label: Text('Arbeitsbereich')),
              ButtonSegment(
                  value: _MobilePane.explorer,
                  icon: Icon(Icons.list_alt, size: 16),
                  label: Text('Explorer')),
              ButtonSegment(
                  value: _MobilePane.inspector,
                  icon: Icon(Icons.info_outline, size: 16),
                  label: Text('Inspector')),
            ],
            selected: {mobilePane},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => mobilePane = selection.single),
          ),
        ),
        const SizedBox(height: OipTokens.s3),
        SizedBox(
          height: 600,
          child: switch (mobilePane) {
            _MobilePane.primary => primary,
            _MobilePane.explorer => _explorer(snapshot, edges),
            _MobilePane.inspector => inspector(),
          },
        ),
      ]);
    });
  }

  Widget _topologyPrimary(
      Snapshot snapshot, List<NetworkEdge> edges, TopologyLayout layout) {
    final visibleEdges = _visibleEdges(snapshot, edges);
    final hasTopology = layout.devices.isNotEmpty;
    final graphSelectedDeviceId =
        layout.positions.containsKey(selectedId) ? selectedId : null;
    final highlighted = <String>{};
    if (graphSelectedDeviceId != null) {
      highlighted.add(graphSelectedDeviceId);
      for (final edge in edges) {
        if (edge.link.from == graphSelectedDeviceId) {
          highlighted.add(edge.link.to);
        }
        if (edge.link.to == graphSelectedDeviceId) {
          highlighted.add(edge.link.from);
        }
      }
    }
    final graphSelectedEdgeId =
        layout.edges.any((edge) => edge.id == selectedEdgeId)
            ? selectedEdgeId
            : null;
    if (graphSelectedEdgeId != null) {
      for (final edge
          in edges.where((edge) => edge.id == graphSelectedEdgeId)) {
        highlighted.addAll([edge.link.from, edge.link.to]);
      }
    }
    final hasGraphSelection =
        graphSelectedDeviceId != null || graphSelectedEdgeId != null;
    final panningRecommended = MediaQuery.of(context).size.width < 600 &&
        layout.size.width * .55 > 300;
    return WorkstationPanel(
      accent: OipTokens.cyan,
      padding: EdgeInsets.zero,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
          child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Semantics(
                    container: true,
                    excludeSemantics: true,
                    label: 'Logische Topologie',
                    child: const Text('Logische Topologie',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                NetworkBadge(
                    '${layout.devices.length} TOPOLOGIE-NODES', 'unknown'),
                NetworkBadge('${visibleEdges.length} PFADE', 'unknown'),
                ToolButton(
                    icon: Icons.remove,
                    tooltip: 'Verkleinern',
                    onPressed: hasTopology ? () => _zoom(.8) : null),
                ToolButton(
                    icon: Icons.add,
                    tooltip: 'Vergrößern',
                    onPressed: hasTopology ? () => _zoom(1.25) : null),
                ToolButton(
                    key: const Key('fit-topology'),
                    icon: Icons.fit_screen,
                    tooltip: 'Topologie einpassen',
                    onPressed:
                        hasTopology ? () => _fit(layout, user: true) : null),
                ToolButton(
                    icon: Icons.restart_alt,
                    tooltip: 'Ansicht zurücksetzen',
                    onPressed: hasTopology
                        ? () => _setTransform(1, Offset.zero)
                        : null),
                ToolButton(
                    icon: Icons.center_focus_strong,
                    tooltip: 'Auf Auswahl fokussieren',
                    onPressed: !hasGraphSelection
                        ? null
                        : () => _focusSelection(layout)),
                ToolButton(
                    key: const Key('edge-labels-toggle'),
                    icon: showEdgeLabels
                        ? Icons.label_outlined
                        : Icons.label_off_outlined,
                    tooltip: showEdgeLabels
                        ? 'Edge Labels ausblenden'
                        : 'Edge Labels anzeigen',
                    active: showEdgeLabels,
                    accent: OipTokens.cyan,
                    onPressed: hasTopology
                        ? () => setState(() => showEdgeLabels = !showEdgeLabels)
                        : null),
                IconButton(
                  key: const Key('selection-clear'),
                  tooltip: 'Auswahl aufheben',
                  onPressed: selectedId == null && selectedEdgeId == null
                      ? null
                      : _clearSelection,
                  icon: const Icon(Icons.deselect, size: 18),
                ),
              ]),
        ),
        if (graphSelectedDeviceId != null &&
            networkDeviceEdges(graphSelectedDeviceId, edges).isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                key: const Key('neighbors-only'),
                label: const Text('Show Direct Neighbors'),
                selected: neighborsOnly,
                onSelected: (value) => setState(() {
                  neighborsOnly = value;
                  fitRequested = true;
                }),
              ),
            ),
          ),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        Expanded(
          child: NetworkTopologyGraph(
            layout: layout,
            edges: visibleEdges,
            transformation: transformation,
            focusNode: graphFocus,
            selectedDeviceId: graphSelectedDeviceId,
            selectedEdgeId: graphSelectedEdgeId,
            highlightedDeviceIds: highlighted,
            transportLive: transportLive,
            showEdgeLabels: showEdgeLabels,
            onNode: _selectGraphNode,
            onEdge: _selectEdge,
            onViewportSize: (size) => _viewportChanged(size, layout),
            onInteraction: () => userCameraUsed = true,
            onKeyEvent: _graphKey,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
          child: Text(
            '${panningRecommended ? 'Lesbare Mindestgröße: horizontal pannen; alle Pfade zusätzlich im Verbindungsworkspace. · ' : ''}Nur bestätigte logische Snapshot-Pfade · keine physische Verkabelung. +/− Zoom · F Fit · 0 Reset · Pfeile Auswahl.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ]),
    );
  }

  Widget _inspector(Snapshot snapshot, List<NetworkEdge> edges) {
    final edge = edges.where((edge) => edge.id == selectedEdgeId).firstOrNull;
    final device =
        snapshot.devices.where((device) => device.id == selectedId).firstOrNull;
    return Focus(
      focusNode: inspectorFocus,
      child: Builder(builder: (context) {
        final focused = Focus.of(context).hasFocus;
        return Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(WorkstationTokens.radius),
            border: Border.all(
                color: focused
                    ? OipTokens.readableAccent(context, OipTokens.violet)
                    : Colors.transparent,
                width: 2),
          ),
          child: SingleChildScrollView(
            key: const Key('network-inspector-scroll'),
            child: edge != null
                ? _edgeInspector(snapshot, edge)
                : device != null
                    ? _nodeInspector(snapshot, device, edges)
                    : _analysisInspector(snapshot, edges),
          ),
        );
      }),
    );
  }

  Widget _analysisInspector(Snapshot snapshot, List<NetworkEdge> edges) {
    final linked = networkLinkedDeviceIds(edges);
    final linkedCount =
        snapshot.devices.where((device) => linked.contains(device.id)).length;
    final errors = snapshot.metrics
        .where((observation) => observation.collectionError != null)
        .length;
    final sources = snapshot.devices
        .map((device) => device.sourceId)
        .whereType<String>()
        .toSet()
        .length;
    final demoCount = edges.where((edge) => edge.link.simulated).length;
    return WorkstationPanel(
      key: const Key('network-inspector-empty'),
      accent: OipTokens.violet,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const NetworkSectionHeader(
            'Network Analysis', 'Bestand, Qualität und Beobachtungsgrenzen'),
        const SizedBox(height: OipTokens.s3),
        const PanelLabel('Known topology', color: OipTokens.cyan),
        NetworkKeyValue('Registrierte Geräte', '${snapshot.devices.length}'),
        NetworkKeyValue('Bekannte Topologie-Endpunkte', '$linkedCount'),
        NetworkKeyValue('Bekannte logische Pfade', '${edges.length}'),
        NetworkKeyValue(
            'Relation unbekannt', '${snapshot.devices.length - linkedCount}'),
        const NetworkDivider(),
        const PanelLabel('Reported health', color: OipTokens.cyan),
        NetworkKeyValue('Reachability · gemeldet',
            '${snapshot.devices.where((d) => d.health.reachability == 'reachable').length} erreichbar'),
        NetworkKeyValue('Collection Errors · geliefert', '$errors'),
        NetworkKeyValue('Unterschiedliche Sources', '$sources'),
        NetworkKeyValue(
            'Snapshot erzeugt', timestamp(snapshot.system.generatedMs)),
        const NetworkDivider(),
        const PanelLabel('Measured reachability'),
        const NetworkKeyValue('Aktive Probes', 'Nicht ausgeführt'),
        const NetworkHint('Gemeldet ist nicht gemessen',
            'Device Health und Transportstatus stammen aus dem Snapshot. Es liegt keine aktive Probe-Messmethode für diese UI vor.'),
        const NetworkDivider(),
        const PanelLabel('Demo fixture', color: OipTokens.amber),
        NetworkKeyValue('Demo-/Fixture-Pfade', '$demoCount von ${edges.length}',
            status: demoCount == 0 ? 'unknown' : 'info'),
        const NetworkKeyValue('Physische Topologie', 'Nicht verfügbar'),
        const NetworkKeyValue('Link History', 'Nicht verfügbar'),
        const NetworkDivider(),
        const NetworkHint('Arbeitskontext wählen',
            'Gerät links oder im Graph auswählen. Pfeiltasten navigieren, P pinnt, C vergleicht. Relation unbekannt bedeutet nicht offline.'),
      ]),
    );
  }

  Widget _nodeInspector(
      Snapshot snapshot, Device device, List<NetworkEdge> edges) {
    final related = networkDeviceEdges(device.id, edges);
    final freshness = transportLive ? device.health.freshness : 'stale';
    final observations = snapshot.metrics
        .where((observation) =>
            (device.sourceId != null &&
                observation.sourceId == device.sourceId) ||
            observation.entityId == device.id)
        .toList();
    final errors = observations
        .where((observation) => observation.collectionError != null)
        .toList();
    final incidents = snapshot.incidents
        .where((incident) => incident.deviceId == device.id)
        .toList();
    final observationTimes = observations
        .map((observation) => observation.sourceMs)
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    final isPinned = pinned.containsKey(device.id);
    final isCompared = comparedDevices.containsKey(device.id);
    return WorkstationPanel(
      key: const Key('node-inspector'),
      accent: OipTokens.violet,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(networkKindIcon(device.kind), size: 30, color: OipTokens.cyan),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(device.name, style: Theme.of(context).textTheme.titleLarge),
              Text(networkDeviceCategory(device.kind),
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ]),
        const SizedBox(height: OipTokens.s2),
        Wrap(spacing: 6, runSpacing: 6, children: [
          NetworkBadge(device.simulated ? 'DEMO-INVENTAR' : 'API-INVENTAR',
              device.simulated ? 'info' : 'connected'),
          NetworkBadge(
              known(device.health.reachability), device.health.reachability,
              showDot: true),
        ]),
        const SizedBox(height: OipTokens.s2),
        Wrap(spacing: 4, runSpacing: 4, children: [
          ToolButton(
            key: const Key('network-pin-toggle'),
            icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            tooltip: isPinned ? 'Pin entfernen (P)' : 'Gerät anheften (P)',
            active: isPinned,
            onPressed: () => _togglePin(device),
          ),
          ToolButton(
            key: const Key('network-compare-toggle'),
            icon: isCompared
                ? Icons.compare_arrows
                : Icons.compare_arrows_outlined,
            tooltip: isCompared
                ? 'Aus Vergleich entfernen (C)'
                : 'Zum Vergleich hinzufügen (C)',
            active: isCompared,
            accent: OipTokens.cyan,
            onPressed: !isCompared && comparedDevices.length >= maxCompare
                ? null
                : () => _toggleCompareDevice(device),
          ),
          ToolButton(
            key: const Key('network-focus-node'),
            icon: Icons.center_focus_strong,
            tooltip: related.isEmpty
                ? 'Kein Graph-Fokus: Relation unbekannt'
                : 'Im Graph fokussieren',
            onPressed: related.isEmpty ? null : () => _focusNode(device),
          ),
          ToolButton(
            key: const Key('network-copy-id'),
            icon: Icons.copy_outlined,
            tooltip: 'Device-ID kopieren',
            onPressed: () => _copy('Device-ID', device.id),
          ),
          ToolButton(
            key: const Key('network-copy-source'),
            icon: Icons.source_outlined,
            tooltip: 'Source-ID kopieren',
            onPressed: device.sourceId == null
                ? null
                : () => _copy('Source-ID', device.sourceId!),
          ),
        ]),
        const NetworkDivider(),
        const PanelLabel('Identity', color: OipTokens.violet),
        NetworkKeyValue('Device-ID', device.id),
        if (widget.controller.infrastructure.ready) ...[
          NetworkKeyValue(
              'Organization',
              widget.controller.infrastructure.hierarchy.organizationName(widget
                  .controller.infrastructure
                  .devicePlacement(device)
                  ?.organizationId)),
          NetworkKeyValue(
              'Infrastructure',
              widget.controller.infrastructure.hierarchy.infrastructureName(
                  widget.controller.infrastructure
                      .devicePlacement(device)
                      ?.infrastructureId)),
          NetworkKeyValue(
              'Site',
              widget.controller.infrastructure.hierarchy.siteName(widget
                  .controller.infrastructure
                  .devicePlacement(device)
                  ?.siteId)),
        ],
        NetworkKeyValue('Source-ID', device.sourceId ?? 'Nicht geliefert'),
        NetworkKeyValue('Device Type · Registry', deviceKindName(device.kind)),
        NetworkKeyValue('Standort / Kontext · Registry', device.location),
        NetworkKeyValue('Verbindung · Registry', device.connection),
        NetworkKeyValue(
            'Datenprovenienz', device.simulated ? 'Simulation' : 'API'),
        const NetworkDivider(),
        const PanelLabel('Connectivity', color: OipTokens.cyan),
        NetworkKeyValue('Direkte logische Nachbarn', '${related.length}'),
        if (related.isEmpty)
          const NetworkHint('Relation unbekannt · keine bekannten Pfade',
              'Keine Kante wurde geliefert. Das beweist weder Isolation noch Offline-Status; es wird keine Relation aus Name oder Typ abgeleitet.'),
        for (final edge in related) _edgeLink(snapshot, edge),
        if (related.isNotEmpty)
          TextButton.icon(
            key: const Key('network-open-connections'),
            onPressed: () => _setMode(_NetworkMode.connections),
            icon: const Icon(Icons.alt_route_outlined, size: 16),
            label: const Text('Bekannte Verbindungen öffnen'),
          ),
        const NetworkDivider(),
        const PanelLabel('Reachability & Health · reported'),
        NetworkKeyValue(
            'Device Reachability', known(device.health.reachability),
            status: device.health.reachability),
        NetworkKeyValue(
            'Observation Time',
            observationTimes.isEmpty
                ? 'Nicht im Device-Health-DTO enthalten'
                : observationTimes.map(timestamp).join(' / ')),
        NetworkKeyValue('Telemetry Freshness', known(freshness),
            status: freshness),
        NetworkKeyValue('VPN Transport', known(device.health.vpn),
            status: device.health.vpn),
        NetworkKeyValue('Agent Availability', known(device.health.agent),
            status: device.health.agent),
        NetworkKeyValue('Service Health', known(device.health.service),
            status: device.health.service),
        const NetworkKeyValue(
            'Measured Reachability', 'Keine Probe ausgeführt'),
        NetworkKeyValue(
            'Collection State',
            observations.isEmpty
                ? 'Keine gerätespezifische Angabe'
                : observations
                    .map((o) => known(o.freshness))
                    .toSet()
                    .join(' / ')),
        if (!transportLive)
          const NetworkHint('Datenalter nicht aktuell verifizierbar',
              'Der SSE-Kanal ist nicht live. Zuletzt gelieferte Werte werden nicht als aktuelle Erreichbarkeit ausgegeben.'),
        const NetworkDivider(),
        PanelLabel(
            'Diagnostics · ${errors.length} Fehler · ${incidents.length} Befunde'),
        if (errors.isEmpty)
          const NetworkHint('Keine Collection Errors geliefert',
              'Das ist kein Nachweis eines fehlerfreien Netzwerks.'),
        for (final observation in errors)
          NetworkHint(
              'Belegt · ${observation.metricId}', observation.collectionError!,
              status: 'bad'),
        for (final incident in incidents)
          NetworkHint(
              '${incident.simulated ? 'Demo-Befund' : 'Belegt'} · ${incident.title}',
              'Keine automatische Root-Cause-Zuordnung. Details bleiben im Diagnose-Workspace.',
              status: incident.simulated ? 'info' : 'degraded'),
        const SizedBox(height: OipTokens.s3),
        OutlinedButton.icon(
          onPressed: () => showDevice(context, widget.controller, device),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Registry-Gerätedetails öffnen'),
        ),
      ]),
    );
  }

  Widget _edgeLink(Snapshot snapshot, NetworkEdge edge) {
    String name(String id) =>
        snapshot.devices.where((device) => device.id == id).firstOrNull?.name ??
        id;
    return ListTile(
      key: Key('edge-${edge.id.hashCode}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 18,
      leading: Icon(Icons.alt_route_outlined,
          size: 17, color: OipTokens.statusColor(context, edge.link.status)),
      title: Text('${name(edge.link.from)} → ${name(edge.link.to)}',
          overflow: TextOverflow.ellipsis),
      subtitle: Text('${edge.link.transport} · ${known(edge.link.status)}'),
      onTap: () => _selectEdge(edge),
    );
  }

  Widget _edgeInspector(Snapshot snapshot, NetworkEdge edge) {
    final link = edge.link;
    final compared = comparedEdges.containsKey(edge.id);
    String name(String id) =>
        snapshot.devices.where((device) => device.id == id).firstOrNull?.name ??
        id;
    return WorkstationPanel(
      key: const Key('edge-inspector'),
      accent: OipTokens.violet,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const NetworkSectionHeader(
            'Verbindungsinspektion', 'Ausgewählter logischer Edge'),
        const SizedBox(height: OipTokens.s3),
        Text('${name(link.from)} → ${name(link.to)}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: OipTokens.s2),
        Wrap(spacing: 6, runSpacing: 6, children: [
          NetworkBadge(known(link.status), link.status, showDot: true),
          NetworkBadge(link.simulated ? 'DEMO-FIXTURE' : 'API',
              link.simulated ? 'info' : 'connected'),
        ]),
        const SizedBox(height: OipTokens.s2),
        ToolButton(
          key: const Key('network-edge-compare-toggle'),
          icon: compared ? Icons.compare_arrows : Icons.compare_arrows_outlined,
          tooltip: compared
              ? 'Pfad aus Vergleich entfernen (C)'
              : 'Pfad zum Vergleich hinzufügen (C)',
          active: compared,
          accent: OipTokens.cyan,
          onPressed: !compared && comparedEdges.length >= maxCompare
              ? null
              : () => _toggleCompareEdge(edge),
        ),
        const NetworkDivider(),
        const PanelLabel('Endpoint A / B', color: OipTokens.violet),
        NetworkKeyValue('Endpoint A', '${name(link.from)} · ${link.from}'),
        NetworkKeyValue('Endpoint B', '${name(link.to)} · ${link.to}'),
        const NetworkKeyValue('Connection ID', 'Nicht im Legacy-DTO enthalten'),
        NetworkKeyValue('Connection Type', networkEdgeKind(link)),
        NetworkKeyValue('Transport · DTO', link.transport),
        const NetworkDivider(),
        const PanelLabel('Relation Provenance & Verification'),
        const NetworkHint('Logische Zuordnung · nicht physikalisch verifiziert',
            'Der Edge stammt aus dem Snapshot. Er beweist keine aktive Paket- oder Link-Erreichbarkeit und keine physische Verbindung.'),
        NetworkKeyValue('Status · geliefert', known(link.status),
            status: link.status),
        NetworkKeyValue(
            'Provenienz', link.simulated ? 'Simulation / Fixture' : 'API'),
        const NetworkKeyValue('Timestamps', 'Nicht im Link-DTO enthalten'),
        const NetworkKeyValue('Datenalter', 'Nicht im Link-DTO enthalten'),
        const NetworkDivider(),
        const PanelLabel('Available Metrics'),
        NetworkKeyValue('RTT', networkLinkRtt(link)),
        NetworkKeyValue('Packet Loss', networkLinkLoss(link)),
        const NetworkKeyValue('Bandwidth', 'Nicht verfügbar'),
        const NetworkKeyValue('Link History', 'Nicht verfügbar'),
        const NetworkKeyValue(
            'Bekannte Link-Fehler', 'Kein Link-Fehler-DTO vorhanden'),
        if (link.simulated)
          const NetworkHint('Demo-Werte, keine Betriebsmessung',
              'RTT und Paketverlust sind Bestand des simulierten Szenarios und werden nicht mit realen Messungen vermischt.',
              status: 'info'),
        const SizedBox(height: OipTokens.s3),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final id in [link.from, link.to])
            OutlinedButton(
              onPressed: () {
                final device = snapshot.devices
                    .where((device) => device.id == id)
                    .firstOrNull;
                if (device != null) _selectNodeFromInspector(device);
              },
              child: Text('Zu ${name(id)}'),
            ),
        ]),
      ]),
    );
  }

  Widget _connectionsWorkspace(Snapshot snapshot, List<NetworkEdge> edges) {
    final visible = _visibleEdges(snapshot, edges);
    final transports = snapshot.topology
        .map((link) => link.transport)
        .toSet()
        .toList()
      ..sort();
    return WorkstationPanel(
      accent: OipTokens.cyan,
      padding: EdgeInsets.zero,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Wrap(spacing: 8, runSpacing: 7, children: [
            const Padding(
              padding: EdgeInsets.only(top: 7),
              child: NetworkSectionHeader('Verbindungspfade',
                  'Logische DTO-Relationen · keine physische Verkabelung'),
            ),
            Semantics(
              container: true,
              excludeSemantics: true,
              label: '${visible.length}/${edges.length}',
              child: Text('${visible.length}/${edges.length}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            _connectionFilter('Transport', transportFilter, transports,
                (value) => setState(() => transportFilter = value),
                key: const Key('network-transport-filter')),
            _connectionFilter(
                'Link-Status',
                edgeStatusFilter,
                const ['connected', 'degraded', 'critical', 'unknown'],
                (value) => setState(() => edgeStatusFilter = value),
                key: const Key('network-edge-status-filter')),
          ]),
        ),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        Expanded(
          child: visible.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: WorkstationNote('Keine gelieferten Pfade im Filter',
                        'Suche oder Filter ändern. Ein leeres Ergebnis wird nicht als Offline-Zustand interpretiert.'),
                  ),
                )
              : ListView.separated(
                  key: const Key('connections-list'),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  itemBuilder: (context, index) =>
                      _connectionRow(snapshot, visible[index]),
                ),
        ),
      ]),
    );
  }

  Widget _connectionFilter(String label, String? value, List<String> values,
      ValueChanged<String?> onChanged,
      {required Key key}) {
    return SizedBox(
      width: 175,
      child: DropdownButton<String>(
        key: key,
        value: value ?? '__all__',
        underline: const SizedBox.shrink(),
        isDense: true,
        isExpanded: true,
        style: Theme.of(context).textTheme.bodySmall,
        items: [
          DropdownMenuItem(value: '__all__', child: Text('$label: alle')),
          for (final item in values)
            DropdownMenuItem(
                value: item, child: Text('$label: ${known(item)}')),
        ],
        onChanged: (selected) =>
            onChanged(selected == '__all__' ? null : selected),
      ),
    );
  }

  Widget _connectionRow(Snapshot snapshot, NetworkEdge edge) {
    final link = edge.link;
    final compared = comparedEdges.containsKey(edge.id);
    String name(String id) =>
        snapshot.devices.where((device) => device.id == id).firstOrNull?.name ??
        id;
    final selected = selectedEdgeId == edge.id;
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: 'Verbindungspfad ${name(link.from)} nach ${name(link.to)}, '
          '${link.transport}, ${known(link.status)}, '
          'RTT ${networkLinkRtt(link)}, Loss ${networkLinkLoss(link)}',
      child: Material(
        color:
            selected ? OipTokens.violet.withOpacity(.10) : Colors.transparent,
        child: InkWell(
          key: Key('connection-${edge.id.hashCode}'),
          onTap: () => _selectEdge(edge),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('${name(link.from)} → ${name(link.to)}',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                IconButton(
                  key: Key('connection-compare-${edge.id.hashCode}'),
                  tooltip: compared
                      ? 'Pfad aus Vergleich entfernen'
                      : 'Pfad vergleichen',
                  onPressed: () => _toggleCompareEdge(edge),
                  icon: Icon(
                      compared
                          ? Icons.compare_arrows
                          : Icons.compare_arrows_outlined,
                      size: 18,
                      color: compared ? OipTokens.cyan : null),
                ),
              ]),
              const SizedBox(height: 5),
              Wrap(spacing: 10, runSpacing: 4, children: [
                Text(link.transport),
                Text(known(link.status),
                    style: TextStyle(
                        color: OipTokens.statusColor(context, link.status))),
                Text('RTT ${networkLinkRtt(link)}'),
                Text('Loss ${networkLinkLoss(link)}'),
                Text(link.simulated ? 'Demo / Fixture' : 'API'),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _compareWorkspace(Snapshot snapshot, {required bool bounded}) {
    final edgeById = {for (final edge in networkEdges(snapshot)) edge.id: edge};
    return NetworkCompareWorkspace(
      snapshot: snapshot,
      devices: comparedDevices.values.toList(),
      edges: comparedEdges.values.map((edge) => edgeById[edge.id]!).toList(),
      transportLive: transportLive,
      bounded: bounded,
      onRemoveDevice: _toggleCompareDevice,
      onRemoveEdge: _toggleCompareEdge,
      onSelectDevice: _selectNodeFromInspector,
      onSelectEdge: _selectEdge,
      onClear: () => setState(() {
        comparedDevices.clear();
        comparedEdges.clear();
      }),
      onClose: () => _setMode(_NetworkMode.topology),
    );
  }

  Widget _vpnWorkspace(Snapshot snapshot, List<NetworkEdge> edges) {
    final reports = snapshot.devices
        .where((device) => device.health.vpn != 'not_applicable')
        .toList();
    final logicalVpnPaths = edges
        .where((edge) => networkEdgeKind(edge.link).contains('VPN'))
        .toList();
    return WorkstationPanel(
      key: const Key('network-vpn-empty'),
      accent: OipTokens.cyan,
      padding: EdgeInsets.zero,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        const NetworkSectionHeader('VPN Engineering',
            'Provider, Peers, Tunnel und Routes · capability-basiert'),
        const SizedBox(height: OipTokens.s3),
        _vpnSection(
          context,
          'VPN OVERVIEW',
          Icons.vpn_lock_outlined,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            NetworkKeyValue(
                'Network Status · System DTO', known(snapshot.system.network),
                status: snapshot.system.network),
            const NetworkKeyValue(
                'Provider', 'Kein Provider-Datensatz verfügbar'),
            const NetworkKeyValue(
                'Datenquelle', 'Snapshot.system + Device Health'),
            NetworkKeyValue(
                'Snapshot erzeugt', timestamp(snapshot.system.generatedMs)),
            const NetworkKeyValue('Telemetrieverfügbarkeit', 'Nicht verfügbar'),
            const NetworkHint('Keine VPN-Telemetrie verbunden',
                'Der Core liefert keine Peer-, Endpoint-, Handshake-, Route- oder Tunnel-Health-Datensätze. Vorhandene Transport-Strings sind keine Peer-Telemetrie.'),
          ]),
        ),
        _vpnSection(
          context,
          'PEER EXPLORER',
          Icons.people_outline,
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            NetworkKeyValue('Gelieferte Peer-Datensätze', '0'),
            NetworkHint('Keine VPN-Peer-Telemetrie verfügbar',
                'Keine Tailscale- oder WireGuard-Peers, Allowed IPs, Endpoints oder Handshake-Zeiten werden erfunden.'),
            NetworkBadge('PEERS · NICHT VERFÜGBAR', 'unknown'),
          ]),
        ),
        _vpnSection(
          context,
          'TUNNEL INSPECTOR',
          Icons.account_tree_outlined,
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            NetworkKeyValue('Bekannte Tunnel', 'Keine Tunnel-Datensätze'),
            NetworkKeyValue('Tunnel Health', 'Nicht verfügbar'),
            NetworkKeyValue('Handshake Age', 'Nicht verfügbar'),
            NetworkBadge('TUNNEL HEALTH · NICHT VERFÜGBAR', 'unknown'),
          ]),
        ),
        _vpnSection(
          context,
          'ROUTING & REACHABILITY',
          Icons.alt_route_outlined,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const NetworkKeyValue(
                'VPN Routes / Allowed IPs', 'Nicht verfügbar'),
            const NetworkKeyValue(
                'Measured Reachability', 'Keine Probe ausgeführt'),
            const NetworkKeyValue(
                'Tunnel Traffic / RTT / Loss', 'Keine VPN-Messung'),
            const NetworkBadge('ROUTES · NICHT VERFÜGBAR', 'unknown'),
            if (logicalVpnPaths.isNotEmpty) ...[
              const NetworkDivider(),
              Text(
                  'Gelieferte logische Pfade mit VPN-Transport · Demo-Fixtures',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final edge in logicalVpnPaths) _edgeLink(snapshot, edge),
              const NetworkHint('Logische Pfade sind keine Tunnelmessung',
                  'Diese Snapshot-Relationen belegen weder Peer-Handshake, Route noch aktuelle Tunnel-Health.'),
            ],
          ]),
        ),
        _vpnSection(
          context,
          'DIAGNOSTICS · DELIVERED DEVICE HEALTH',
          Icons.troubleshoot_outlined,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (reports.isEmpty)
              const NetworkHint('Keine VPN-Felder gemeldet',
                  'Es gibt keine darstellbaren Geräte-VPN-Zustände.'),
            for (final device in reports)
              ListTile(
                key: Key('vpn-report-${device.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(networkKindIcon(device.kind), size: 20),
                title: Text(device.name),
                subtitle: Text(
                    '${known(device.health.vpn)} · ${device.simulated ? 'Demo-Health' : 'API-Health'} · ${device.connection}'),
                trailing: StatusDot(device.health.vpn),
                onTap: () => _selectNodeFromInspector(device),
              ),
            for (final incident in snapshot.incidents)
              NetworkHint(
                  '${incident.simulated ? 'Demo-Befund' : 'Belegt'} · ${incident.title}',
                  'Allgemeiner Snapshot-Befund, kein gesonderter Tunnel-Event. ${incident.missing.join(' ')}',
                  status: incident.simulated ? 'info' : 'degraded'),
          ]),
        ),
        const NetworkHint(
            'Core-Capabilities erforderlich · nicht implementiert',
            'Tailscale/WireGuard Read, Peer Health, Handshake Age, Routes, Allowed IPs, Reachability, RTT/Loss, Traffic und Collection Errors sind Anforderungen an den Core, keine vorhandenen UI-Funktionen.'),
      ]),
    );
  }

  Widget _vpnSection(
      BuildContext context, String title, IconData icon, Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WorkstationTokens.well(context),
        border: Border.all(color: WorkstationTokens.hairline(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 17, color: OipTokens.cyan),
          const SizedBox(width: 8),
          Expanded(
              child: Text(title, style: WorkstationTokens.eyebrow(context))),
        ]),
        const SizedBox(height: 7),
        child,
      ]),
    );
  }

  Widget _diagnosticsWorkspace(Snapshot snapshot, List<NetworkEdge> edges) {
    final errors = snapshot.metrics
        .where((observation) => observation.collectionError != null)
        .toList();
    final unknown = snapshot.devices
        .where((device) => device.health.reachability == 'unknown')
        .length;
    final sources = snapshot.devices
        .map((device) => device.sourceId)
        .whereType<String>()
        .toSet();
    return WorkstationPanel(
      key: const Key('network-diagnostics'),
      accent: OipTokens.cyan,
      padding: EdgeInsets.zero,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        const NetworkSectionHeader('Network Diagnostics & Analysis',
            'Evidenz, gemeldete Zustände und fehlende Messungen getrennt'),
        const SizedBox(height: OipTokens.s3),
        Wrap(spacing: 8, runSpacing: 8, children: [
          NetworkBadge(
              transportLive ? 'DATENKANAL · LIVE' : 'DATENKANAL · STALE',
              transportLive ? 'connected' : 'stale',
              showDot: true),
          NetworkBadge('${errors.length} COLLECTION ERRORS',
              errors.isEmpty ? 'unknown' : 'bad'),
          NetworkBadge('$unknown REACHABILITY UNBEKANNT', 'unknown'),
          NetworkBadge('${sources.length} SOURCES', 'unknown'),
        ]),
        const NetworkDivider(),
        const PanelLabel('Analysis · tatsächlich verfügbare Daten',
            color: OipTokens.cyan),
        NetworkKeyValue('Registrierte Geräte', '${snapshot.devices.length}'),
        NetworkKeyValue('Bekannte Topologie-Endpunkte',
            '${networkLinkedDeviceIds(edges).length}'),
        NetworkKeyValue('Relation unbekannt',
            '${snapshot.devices.length - networkLinkedDeviceIds(edges).length}'),
        NetworkKeyValue('Bekannte logische Pfade', '${edges.length}'),
        NetworkKeyValue('Snapshot Datenalter / erzeugt',
            timestamp(snapshot.system.generatedMs)),
        NetworkHint(
            transportLive
                ? 'Belegt · Snapshot-Kanal aktiv'
                : 'Indiz · Snapshot-Kanal nicht live',
            'Eine funktionierende API oder ein aktiver SSE-Kanal beweist weder Source-Health noch gemessene Geräteerreichbarkeit.',
            status: transportLive ? 'connected' : 'stale'),
        const NetworkDivider(),
        const PanelLabel('Collection Errors · geliefert'),
        if (errors.isEmpty)
          const NetworkHint('Keine Collection Errors geliefert',
              'Nicht bekannt ist nicht gleich gesund. Für Links liegen keine separaten Collection Errors vor.'),
        for (final observation in errors)
          NetworkHint(
              'Belegt · ${observation.sourceId ?? observation.entityId} / ${observation.metricId}',
              '${observation.collectionError} · Quality ${known(observation.quality)} · Freshness ${known(observation.freshness)}',
              status: 'bad'),
        const NetworkDivider(),
        const PanelLabel('Device / Link Events'),
        for (final incident in snapshot.incidents)
          NetworkHint(
              '${incident.simulated ? 'Indiz · Demo' : 'Belegt'} · ${incident.title}',
              '${incident.supporting.join(' ')} Fehlend: ${incident.missing.join(' ')}',
              status: incident.simulated ? 'info' : 'degraded'),
        const NetworkSectionHeader('Network Events / Link History',
            'Kein entsprechender Core-Vertrag'),
        const NetworkHint('Nicht verfügbar',
            'Link-Up/Down-, Tunnel-, Route- und historische Link-Metriken werden aktuell nicht geliefert. Es wird keine Ereignis- oder Verlustgeschichte abgeleitet.'),
        const NetworkHint('Keine doppelte Geräteliste',
            'Geräte, Status und Provenienz werden links im Device Explorer untersucht; dieser Modus konzentriert sich auf Fehler, Lücken und Datenqualität.'),
      ]),
    );
  }

  Widget _contextFooter(Snapshot snapshot, int relatedCount) {
    final selected =
        snapshot.devices.where((device) => device.id == selectedId).firstOrNull;
    final message = selected != null
        ? '${selected.name} · $relatedCount gelieferte direkte Pfade · Auswahl bleibt bei Snapshot-Updates erhalten.'
        : selectedEdgeId != null
            ? 'Edge ausgewählt · Topologie, Verbindungsliste und Inspector verwenden dieselbe Identität.'
            : widget.controller.infrastructure.ready
                ? 'Globaler Kontext · ${widget.controller.infrastructure.selectedBreadcrumb} · nur gelieferte Kanten werden verbunden.'
                : 'Lokaler Anzeigekontext · keine Organization-/Site-Filter ohne autorisierten Core-Vertrag.';
    return NetworkSurface(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, size: 16, color: OipTokens.cyan),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$message Pins/Compare sitzungslokal · Read-only · keine Shell-, VPN- oder Netzwerksteuerung.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ]),
    );
  }
}

class NetworkSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const NetworkSurface(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Color.lerp(
            scheme.surface, Theme.of(context).scaffoldBackgroundColor, .12),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class NetworkSectionHeader extends StatelessWidget {
  final String title, subtitle;
  const NetworkSectionHeader(this.title, this.subtitle, {super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        excludeSemantics: true,
        label: subtitle.isEmpty ? title : '$title. $subtitle',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall),
          if (subtitle.isNotEmpty)
            Text(subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 10.5)),
        ]),
      );
}

class NetworkBadge extends StatelessWidget {
  final String text, status;
  final IconData? icon;
  final bool showDot;
  const NetworkBadge(this.text, this.status,
      {super.key, this.icon, this.showDot = false});

  @override
  Widget build(BuildContext context) {
    final color = OipTokens.statusColor(context, status);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(.07),
          border: Border.all(color: color.withOpacity(.28)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) Icon(icon, size: 12, color: color),
          if (showDot)
            Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
          if (icon != null || showDot) const SizedBox(width: 5),
          Flexible(
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

class NetworkSummaryItem extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final String? status;
  const NetworkSummaryItem(this.label, this.value, this.icon,
      {super.key, this.status});

  @override
  Widget build(BuildContext context) {
    final color = OipTokens.statusColor(context, status);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$label $value',
      child: Container(
        constraints: const BoxConstraints(minWidth: 140),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontSize: 8.5, letterSpacing: .35)),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }
}

class NetworkKeyValue extends StatelessWidget {
  final String label, value;
  final String? status;
  const NetworkKeyValue(this.label, this.value, {super.key, this.status});

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        excludeSemantics: true,
        label: '$label: $value',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child:
                    Text(label, style: Theme.of(context).textTheme.bodySmall)),
            const SizedBox(width: 8),
            Flexible(
              child: SelectableText(value,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: status == null
                          ? null
                          : OipTokens.statusColor(context, status))),
            ),
          ]),
        ),
      );
}

class NetworkHint extends StatelessWidget {
  final String title, message;
  final String status;
  const NetworkHint(this.title, this.message,
      {super.key, this.status = 'unknown'});

  @override
  Widget build(BuildContext context) {
    final color = OipTokens.statusColor(context, status);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$title. $message',
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(OipTokens.statusIcon(status), size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600, color: color)),
              Text(message,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 10.5)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class NetworkDivider extends StatelessWidget {
  const NetworkDivider({super.key});
  @override
  Widget build(BuildContext context) =>
      Divider(height: 24, color: Theme.of(context).colorScheme.outlineVariant);
}
