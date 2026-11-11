import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/controller.dart';
import '../services/api.dart';
import '../models/contracts.dart';
import '../design_system/theme.dart';
import '../widgets/adaptive_workspace.dart';
import '../widgets/components.dart';
import '../widgets/workstation.dart';
import '../widgets/opcua_compare.dart';
import 'diagnostics.dart' show scenarios;
import 'opcua_value.dart';

/// OPC UA workstation: context rail, node explorer and value inspector.
///
/// Everything shown comes from `/api/v1/opcua/nodes` and the live snapshot.
/// Pins, recents, density, view mode and the per-metric session history are
/// local UI state only; nothing is written to the Core.
class OpcuaPage extends StatefulWidget {
  final OipController controller;
  const OpcuaPage(this.controller, {super.key});

  @override
  State<OpcuaPage> createState() => _OpcuaPageState();
}

enum _ViewMode { list, grouped }

class _OpcuaPageState extends State<OpcuaPage> {
  /// The folders of the address space of the source, as the **Core** names
  /// them. The list is delivered with every page; the legacy catalogue of
  /// the demo is not assumed by the client any more.
  List<String> theFolders = const [];
  static const maxPins = 8, maxRecent = 5, maxSamples = 60, maxCompare = 4;

  NodePage? page;
  OpcNode? selected;
  String search = '', folder = 'all';
  String? error, loadedFolder, loadedSource, selectedNodeSource;
  String? selectedSource, sourcesError, typeFilter, qualityFilter;
  bool loading = false, dense = false, showCompare = false, showFilters = false;
  bool nodeSelectionExplicit = false;
  _ViewMode view = _ViewMode.list;
  OpcValueFormat valueFormat = OpcValueFormat.original;
  int offset = 0, generation = 0;
  Timer? debounce;

  /// Every identity includes its source. NodeIds are not globally unique.
  final pinned = <String, OpcNode>{};
  final compared = <String, OpcNode>{};
  final recent = <String, OpcNode>{};
  final totals = <String, int>{};
  List<SourceInfo> sources = const [];

  /// Real samples per source and metric, bounded to this mounted UI session.
  final sessionHistory = <String, List<Observation>>{};
  Snapshot? ingested;
  String? scopeSignature;

  final searchController = TextEditingController();
  final searchFocus = FocusNode(debugLabel: 'opcua-search');
  final listFocus = FocusNode(debugLabel: 'opcua-list');
  final inspectorFocus = FocusNode(debugLabel: 'opcua-inspector');
  final listScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final preference = widget.controller.workspaces.layout(WorkspaceId.opcua);
    dense = preference.dense ?? false;
    showFilters = preference.advancedFilters;
    view = _ViewMode.values
            .where((item) => item.name == preference.view)
            .firstOrNull ??
        _ViewMode.list;
    widget.controller.addListener(_ingest);
    _ingest();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadSources();
    _load();
  }

  Future<void> _reloadContext() async {
    await _loadSources();
    _load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_ingest);
    debounce?.cancel();
    searchController.dispose();
    searchFocus.dispose();
    listFocus.dispose();
    inspectorFocus.dispose();
    listScroll.dispose();
    super.dispose();
  }

  void _ingest() {
    final nextScope = widget.controller.contextScopeSignature;
    if (scopeSignature != null && scopeSignature != nextScope) {
      generation++;
      debounce?.cancel();
      page = null;
      selected = null;
      selectedNodeSource = null;
      nodeSelectionExplicit = false;
      sources = const [];
      selectedSource = widget.controller.infrastructure.selection.sourceId;
      loadedFolder = null;
      loadedSource = null;
      error = null;
      offset = 0;
      pinned.clear();
      compared.clear();
      recent.clear();
      totals.clear();
      sessionHistory.clear();
      // The scope of the operator changed: the folders of the previous
      // scope belong to a source that is no longer shown.
      theFolders = const [];
      folder = 'all';
      _reloadContext();
    }
    scopeSignature = nextScope;
    final snapshot = widget.controller.snapshot;
    if (snapshot == null || identical(snapshot, ingested)) return;
    ingested = snapshot;
    selectedSource ??= snapshot.primarySourceId;
    for (final observation in snapshot.metrics.where((item) =>
        item.sourceId != null &&
        _entityOf(item.sourceId!) == item.entityId &&
        item.sourceMs != null)) {
      final key = _sampleKey(observation.sourceId!, observation.metricId);
      final list = sessionHistory.putIfAbsent(key, () => []);
      if (list.isNotEmpty && observation.sourceMs! < list.last.sourceMs!) {
        list.clear();
      }
      if (list.isEmpty ||
          list.last.sourceMs != observation.sourceMs ||
          list.last.value != observation.value ||
          list.last.quality != observation.quality ||
          list.last.freshness != observation.freshness) {
        list.add(observation);
        if (list.length > maxSamples) list.removeAt(0);
      }
    }
  }

  String _sampleKey(String source, String metric) => '$source\n$metric';
  String _nodeKey(OpcNode node, String source) => '$source\n${node.id}';
  String _keySource(String key) => key.split('\n').first;
  String? get _currentSource =>
      selectedSource ?? widget.controller.snapshot?.primarySourceId;

  /// The entity of a source.
  ///
  /// The Core names the entity of a source: the id of the device for a real
  /// source, the identifier of the simulation for a simulated one. The
  /// workstation binds its live values, its history and its alarm to that
  /// name — it never assumes the identity of the demo. Only the legacy demo,
  /// whose sources the Core does not list, keeps the identity of the demo,
  /// and only as long as the Core says that its data is simulated.
  String? _entityOf(String sourceId) {
    for (final source in sources) {
      if (source.id == sourceId) return source.entityId;
    }
    for (final source
        in widget.controller.snapshot?.sources ?? const <SourceInfo>[]) {
      if (source.id == sourceId) return source.entityId;
    }
    if (widget.controller.snapshot?.system.simulated == true) return 'M-01';
    return null;
  }

  /// The entity of the selected source.
  String? get _currentEntity {
    final id = _currentSource;
    return id == null ? null : _entityOf(id);
  }

  String _sourceFor(OpcNode node) =>
      node.observation?.sourceId ??
      (identical(node, selected) ? selectedNodeSource : null) ??
      _currentSource ??
      'unknown';

  Future<void> _loadSources() async {
    try {
      final result = await widget.controller.api
          .contextSources(widget.controller.infrastructure);
      if (!mounted) return;
      setState(() {
        sources = result;
        sourcesError = null;
        final globalSource =
            widget.controller.infrastructure.selection.sourceId;
        if (widget.controller.infrastructure.ready) {
          if (globalSource != null &&
              result.any((item) => item.id == globalSource)) {
            selectedSource = globalSource;
          } else if (!result.any((item) => item.id == selectedSource)) {
            selectedSource = result.firstOrNull?.id;
          }
        } else {
          // Legacy v1 may report a primary source separately from its optional
          // sources read. Do not replace that identity by list ordering.
          selectedSource ??= result.firstOrNull?.id;
        }
      });
      if (widget.controller.infrastructure.ready &&
          _currentSource != null &&
          loadedSource != _currentSource) {
        _load();
      }
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        sourcesError = apiErrorMessage(exception,
            'Quellenliste nicht verfügbar. Der Browser nutzt die Primärquelle.');
      });
    }
  }

  Future<void> _load() async {
    final gen = ++generation;
    final requestSource = _currentSource;
    if (widget.controller.infrastructure.ready && requestSource == null) {
      generation++;
      setState(() {
        page = null;
        selected = null;
        loading = false;
        error =
            'Eine eindeutige autorisierte OPC-UA-Source muss ausgewählt werden.';
      });
      return;
    }
    final requestFolder = folder;
    final requestSearch = search;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.controller.api.contextNodes(requestSearch,
          requestFolder, offset, widget.controller.infrastructure,
          source: requestSource);
      if (!mounted || gen != generation) return;
      // The Core names the folders of its address space. A requested folder
      // that the Core does not name does not exist — also when the Core
      // names no folder at all: the whole catalogue is shown instead, and
      // the scope of the operator is named.
      if (requestFolder != 'all' && !result.folders.contains(requestFolder)) {
        if (mounted && gen == generation) {
          setState(() {
            folder = 'all';
            offset = 0;
          });
          await _load();
          return;
        }
      }
      final changedWindow = page == null ||
          page!.offset != result.offset ||
          page!.total != result.total ||
          requestFolder != loadedFolder ||
          requestSource != loadedSource;
      loadedFolder = requestFolder;
      loadedSource = requestSource;
      if (changedWindow && listScroll.hasClients) listScroll.jumpTo(0);
      setState(() {
        page = result;
        // The folders are the ones of **this** page: the folders of a
        // previous source never survive a change of the source.
        theFolders = result.folders;
        if (requestSearch.trim().isEmpty) {
          totals['$requestSource|$requestFolder'] = result.total;
        }
        final current = selected;
        final currentKey = current == null
            ? null
            : _nodeKey(
                current, selectedNodeSource ?? requestSource ?? 'unknown');
        final onPage = currentKey == null
            ? null
            : result.items
                .where((item) =>
                    _nodeKey(item, requestSource ?? 'unknown') == currentKey)
                .firstOrNull;
        final retained = onPage != null ||
            (current != null && pinned.containsKey(currentKey));
        selected = onPage ?? (retained ? current : result.items.firstOrNull);
        if (!retained) nodeSelectionExplicit = false;
        selectedNodeSource = selected == null ? null : requestSource;
        loading = false;
      });
    } catch (exception) {
      if (mounted && gen == generation) {
        setState(() {
          error = apiErrorMessage(exception,
              'OPC-UA-Nodes konnten nicht geladen werden. Bitte erneut versuchen.');
          loading = false;
        });
      }
    }
  }

  void _select(OpcNode node, {bool focusList = false, String? source}) {
    setState(() {
      final previous = selected;
      final previousSource = selectedNodeSource;
      selected = node;
      selectedNodeSource = source ?? _currentSource;
      if (previous != null &&
          previousSource != null &&
          _nodeKey(previous, previousSource) !=
              _nodeKey(
                  node, selectedNodeSource ?? _currentSource ?? 'unknown')) {
        final key = _nodeKey(previous, previousSource);
        recent.remove(key);
        recent[key] = previous;
        while (recent.length > maxRecent) {
          recent.remove(recent.keys.first);
        }
      }
    });
    nodeSelectionExplicit = true;
    widget.controller.revealInspector(WorkspaceId.opcua);
    if (focusList) listFocus.requestFocus();
  }

  void _togglePin(OpcNode node, {String? source}) => setState(() {
        final sourceId = source ?? _sourceFor(node);
        final key = _nodeKey(node, sourceId);
        if (pinned.containsKey(key)) {
          pinned.remove(key);
        } else if (pinned.length < maxPins) {
          pinned[key] = node;
        }
      });

  void _toggleCompare(OpcNode node) => setState(() {
        final source = _sourceFor(node);
        final key = _nodeKey(node, source);
        if (compared.containsKey(key)) {
          compared.remove(key);
        } else if (compared.length < maxCompare) {
          compared[key] = node;
          showCompare = true;
        }
      });

  void _setSource(String? value) {
    if (value == null || value == _currentSource) return;
    debounce?.cancel();
    generation++;
    setState(() {
      selectedSource = value;
      selectedNodeSource = null;
      selected = null;
      page = null;
      loadedSource = null;
      loadedFolder = null;
      error = null;
      offset = 0;
      typeFilter = null;
      qualityFilter = null;
      // The folders belong to the source that delivered them: the chips of
      // a previous source are not shown next to the catalogue of this one.
      theFolders = const [];
      folder = 'all';
    });
    _load();
  }

  void _setFolder(String value) {
    if (folder == value) return;
    setState(() {
      folder = value;
      offset = 0;
    });
    _load();
  }

  void _onSearchChanged(String value) {
    search = value;
    offset = 0;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), _load);
    setState(() {});
  }

  void _clearSearch() {
    debounce?.cancel();
    searchController.clear();
    search = '';
    offset = 0;
    _load();
  }

  void _focusSearch() {
    searchFocus.requestFocus();
    searchController.selection = TextSelection(
        baseOffset: 0, extentOffset: searchController.text.length);
  }

  int get _pageSize => page == null || page!.limit <= 0 ? 40 : page!.limit;
  int get _total => page?.total ?? 0;
  int get _pageCount => _total == 0 ? 1 : (_total / _pageSize).ceil();
  int get _pageIndex => (page?.offset ?? offset) ~/ _pageSize + 1;

  void _goTo(int newOffset) {
    if (loading) return;
    offset = newOffset.clamp(0, math.max(0, (_pageCount - 1) * _pageSize));
    _load();
  }

  bool get _hasNext => !loading && offset + _pageSize < _total;
  bool get _hasPrevious => !loading && offset > 0;

  KeyEventResult _onListKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final items = _filteredItems(
        page?.items ?? const <OpcNode>[], _liveMap(), _currentSource);
    final key = event.logicalKey;
    final index = items.indexWhere((item) => item.id == selected?.id);
    void move(int target) {
      if (items.isEmpty) return;
      final clamped = target.clamp(0, items.length - 1);
      _select(items[clamped]);
      _reveal(clamped);
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      move(index + 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      move(index <= 0 ? 0 : index - 1);
    } else if (key == LogicalKeyboardKey.home) {
      move(0);
    } else if (key == LogicalKeyboardKey.end) {
      move(items.length - 1);
    } else if (key == LogicalKeyboardKey.pageDown) {
      if (_hasNext) _goTo(offset + _pageSize);
    } else if (key == LogicalKeyboardKey.pageUp) {
      if (_hasPrevious) _goTo(offset - _pageSize);
    } else if (key == LogicalKeyboardKey.keyP) {
      if (selected != null) _togglePin(selected!);
    } else if (key == LogicalKeyboardKey.keyC) {
      if (selected != null) _toggleCompare(selected!);
    } else if (key == LogicalKeyboardKey.enter) {
      if (selected != null) inspectorFocus.requestFocus();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _reveal(int index) {
    if (!listScroll.hasClients || view != _ViewMode.list) return;
    final rowHeight =
        dense ? WorkstationTokens.rowDense : WorkstationTokens.rowComfortable;
    final top = index * rowHeight;
    final viewport = listScroll.position.viewportDimension;
    if (top < listScroll.offset) {
      listScroll.jumpTo(top);
    } else if (top + rowHeight > listScroll.offset + viewport) {
      listScroll.jumpTo(top + rowHeight - viewport + 12);
    }
  }

  (Observation?, bool) _resolve(
      OpcNode node, Map<String, Observation> liveById, String? source) {
    final live = liveById[node.name];
    if (live != null && live.sourceId == source) return (live, true);
    final cached = node.observation;
    return (cached != null && cached.sourceId == source ? cached : null, false);
  }

  Map<String, Observation> _liveMap() {
    final source = _currentSource;
    final entity = _currentEntity;
    return {
      for (final observation
          in widget.controller.snapshot?.metrics ?? const <Observation>[])
        if (source != null &&
            entity != null &&
            observation.sourceId == source &&
            observation.entityId == entity)
          observation.metricId: observation
    };
  }

  List<OpcNode> _filteredItems(
      List<OpcNode> items, Map<String, Observation> liveById, String? source) {
    return items.where((node) {
      if (typeFilter != null && node.dataType != typeFilter) return false;
      if (qualityFilter != null &&
          _resolve(node, liveById, source).$1?.quality != qualityFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  List<Observation> _samplesFor(OpcNode node, String? source) {
    if (source == null) return const [];
    if (node.name == 'temperature' &&
        source == widget.controller.snapshot?.primarySourceId &&
        widget.controller.history.isNotEmpty) {
      return widget.controller.history;
    }
    return sessionHistory[_sampleKey(source, node.name)] ?? const [];
  }

  List<OpcCompareEntry> _compareEntries(
      Map<String, Observation> liveById, String? activeSource) {
    return compared.entries.map((item) {
      final source = _keySource(item.key);
      final resolved = _resolve(
          item.value, source == activeSource ? liveById : const {}, source);
      return OpcCompareEntry(
        sourceId: source,
        node: item.value,
        observation: resolved.$1,
        live: resolved.$2,
        samples: _samplesFor(item.value, source),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.snapshot!;
    selectedSource ??= snapshot.primarySourceId;
    final primary = _currentSource;
    final liveById = _liveMap();
    final node = selected;
    final (observation, live) =
        node == null ? (null, false) : _resolve(node, liveById, primary);
    final alarm = snapshot.hasAlarm(deviceId: _currentEntity ?? 'M-01');
    final viewport = MediaQuery.sizeOf(context).height;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.slash): () {
          if (!searchFocus.hasFocus) _focusSearch();
        },
        const SingleActivator(LogicalKeyboardKey.slash, shift: true): () {
          if (!searchFocus.hasFocus) _focusSearch();
        },
        const SingleActivator(LogicalKeyboardKey.keyP): () {
          if (!searchFocus.hasFocus && selected != null) _togglePin(selected!);
        },
        const SingleActivator(LogicalKeyboardKey.keyC): () {
          if (!searchFocus.hasFocus && selected != null) {
            _toggleCompare(selected!);
          }
        },
        const SingleActivator(LogicalKeyboardKey.f6): () {
          if (searchFocus.hasFocus) {
            listFocus.requestFocus();
          } else if (listFocus.hasFocus) {
            inspectorFocus.requestFocus();
          } else {
            _focusSearch();
          }
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (searchFocus.hasFocus) {
            if (search.isNotEmpty) {
              _clearSearch();
            } else {
              listFocus.requestFocus();
            }
          } else if (showCompare) {
            setState(() => showCompare = false);
          }
        },
      },
      // The shortcut wrapper owns a Focus node; keep page texts as separate
      // semantics nodes instead of merging them into that node.
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, snapshot),
            const SizedBox(height: OipTokens.s4),
            LayoutBuilder(builder: (context, box) {
              final hasExplicitSelection =
                  node != null && nodeSelectionExplicit;
              final showInspector = widget.controller
                  .inspectorVisible(WorkspaceId.opcua, hasExplicitSelection);
              Widget inspectorArea({required bool bounded}) =>
                  AdaptiveInspector(
                    controller: widget.controller,
                    workspace: WorkspaceId.opcua,
                    label: 'Node-Wert & technische Attribute',
                    hasSelection: hasExplicitSelection,
                    child: _inspectorArea(context, snapshot, node, observation,
                        live, alarm, primary,
                        bounded: bounded),
                  );
              if (box.maxWidth >= OipTokens.workstation) {
                final railWidth = box.maxWidth >= 1400 ? 252.0 : 220.0;
                final height = (viewport - 290).clamp(540.0, 1200.0);
                return SizedBox(
                  height: height,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                          width: railWidth,
                          child: _rail(context, snapshot, liveById, primary,
                              bounded: true)),
                      const SizedBox(width: OipTokens.s3),
                      Expanded(
                          flex: 11,
                          child: _explorer(context, liveById, primary, alarm,
                              autofocus: true)),
                      if (showInspector) ...[
                        const SizedBox(width: OipTokens.s3),
                        Expanded(flex: 13, child: inspectorArea(bounded: true)),
                      ],
                    ],
                  ),
                );
              }
              if (box.maxWidth >= OipTokens.tablet) {
                final height = (viewport - 420).clamp(480.0, 900.0);
                return Column(children: [
                  _contextStrip(context, snapshot, liveById, primary),
                  const SizedBox(height: OipTokens.s3),
                  SizedBox(
                    height: height,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                            child:
                                _explorer(context, liveById, primary, alarm)),
                        if (showInspector) ...[
                          const SizedBox(width: OipTokens.s3),
                          Expanded(child: inspectorArea(bounded: true)),
                        ],
                      ],
                    ),
                  ),
                ]);
              }
              return Column(children: [
                _contextStrip(context, snapshot, liveById, primary),
                const SizedBox(height: OipTokens.s3),
                SizedBox(
                    height: 480,
                    child: _explorer(context, liveById, primary, alarm)),
                if (showInspector) ...[
                  const SizedBox(height: OipTokens.s3),
                  SizedBox(height: 560, child: inspectorArea(bounded: true)),
                ],
              ]);
            }),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _header(BuildContext context, Snapshot snapshot) {
    final system = snapshot.system;
    final source = _selectedSourceInfo;
    final sourceConnection = source?.connection ?? system.opcua;
    final sourceSubscription = _currentSource == snapshot.primarySourceId
        ? system.subscription
        : 'unknown';
    final stale = widget.controller.stale;
    return AdaptiveWorkspaceHeader(
      eyebrow: 'ADRESSRAUM-EXPLORER · READ-ONLY',
      title: 'OPC-UA-Browser',
      subtitle: 'Source wählen · Node suchen · Wert und Attribute untersuchen',
      accent: OipTokens.violet,
      primaryAction: WorkspacePrimaryAction(
        buttonKey: const Key('opcua-primary-search'),
        label: 'Node suchen',
        tooltip: 'Node-Suche fokussieren · Shortcut /',
        icon: Icons.search,
        onPressed: searchFocus.requestFocus,
      ),
      actions: [
        InspectorOpenAction(
          controller: widget.controller,
          workspace: WorkspaceId.opcua,
          hasSelection: selected != null && nodeSelectionExplicit,
          onOpen: () => setState(() {}),
        ),
        ToolButton(
          key: const Key('compare-open'),
          icon: Icons.compare_arrows_outlined,
          tooltip: 'Node-Vergleich öffnen · ${compared.length}/$maxCompare',
          accent: OipTokens.cyan,
          active: showCompare,
          onPressed: () => setState(() => showCompare = true),
        ),
        ToolButton(
          key: const Key('density-toggle'),
          icon: dense
              ? Icons.density_small_outlined
              : Icons.density_medium_outlined,
          tooltip: dense ? 'Komfortable Liste' : 'Dichte Liste',
          active: dense,
          onPressed: () {
            setState(() => dense = !dense);
            widget.controller.setWorkspaceDensity(WorkspaceId.opcua, dense);
          },
        ),
        ToolButton(
          key: const Key('refresh-nodes'),
          icon: Icons.refresh,
          tooltip: 'Nodes aktualisieren',
          onPressed: loading ? null : _load,
        ),
      ],
      status: [
        StatusPill(
          stale ? 'OPC UA STALE' : 'OPC UA · ${known(sourceConnection)}',
          color: OipTokens.statusColor(
              context, stale ? 'degraded' : sourceConnection),
          showDot: true,
        ),
        StatusPill(
          'SUBSCRIPTION · ${known(sourceSubscription)}',
          color: OipTokens.statusColor(context, sourceSubscription),
          showDot: true,
        ),
        const StatusPill('READ-ONLY ANALYSE',
            color: OipTokens.lime, icon: Icons.lock_outline),
        const KbdHint('Ctrl K · / Suche · F6 Bereich'),
      ],
    );
  }

  // ------------------------------------------------------------------ rail

  SourceInfo? get _selectedSourceInfo {
    final source = _currentSource;
    return sources.where((item) => item.id == source).firstOrNull;
  }

  Widget _sourceSelector(BuildContext context, {bool compact = false}) {
    final current = _currentSource;
    final items = sources.isNotEmpty
        ? sources
        : [
            if (current != null)
              SourceInfo.fromJson({
                'id': current,
                'name': current,
                'entity_id': _currentEntity ?? current,
                'simulated':
                    widget.controller.snapshot?.system.simulated ?? false,
                'reachability': 'unknown',
                'connection': 'unknown',
                'service': 'unknown',
                'freshness': 'unknown',
                'validity': 'unknown',
                'last_received_ms': null,
                'last_error': null,
              })
          ];
    return Semantics(
      label: 'OPC-UA-Datenquelle',
      child: DropdownButton<String>(
        key: const Key('source-select'),
        value: items.any((item) => item.id == current) ? current : null,
        isExpanded: true,
        isDense: compact,
        underline: const SizedBox.shrink(),
        hint: const Text('Quelle unbekannt'),
        items: [
          for (final source in items)
            DropdownMenuItem(
              value: source.id,
              child: Text(
                  widget.controller.infrastructure.ready
                      ? '${source.name} · ${source.id}\n${widget.controller.infrastructure.selectedBreadcrumb}'
                      : '${source.name} · ${source.id}',
                  overflow: TextOverflow.ellipsis,
                  style: WorkstationTokens.mono(context, size: 11.5)),
            )
        ],
        onChanged: items.isEmpty ? null : _setSource,
      ),
    );
  }

  String _namespaceLabel() {
    final indices =
        (page?.items ?? const <OpcNode>[]).map((n) => n.namespace).toSet();
    if (indices.isEmpty) return 'Namespace unbekannt';
    if (indices.length == 1) return 'Namespace ${indices.single}';
    return 'Namespaces ${(indices.toList()..sort()).join(', ')}';
  }

  /// The scopes of the address space: every folder that the Core delivered
  /// and the whole catalogue.
  List<String> get theScopes => [...theFolders, 'all'];

  String _scopeTitle(String value) => value == 'all' ? 'Alle' : value;
  String _scopeCaption(String value) => switch (value) {
        'all' => 'Gesamter gelieferter Katalog',
        _ => 'Ordner des gelieferten Adressraums',
      };
  IconData _scopeIcon(String value) => switch (value) {
        'all' => Icons.all_inclusive,
        _ => Icons.account_tree_outlined,
      };

  Widget _scopeRow(BuildContext context, String value, {bool compact = false}) {
    final active = folder == value;
    final tone = OipTokens.readableAccent(context, OipTokens.violet);
    final count = totals['${_currentSource ?? 'unknown'}|$value'];
    return Semantics(
      button: true,
      selected: active,
      label: _scopeTitle(value),
      hint: '${_scopeCaption(value)}${count == null ? '' : ', $count Nodes'}',
      excludeSemantics: true,
      child: Material(
        color: active ? tone.withOpacity(.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
        child: InkWell(
          key: Key('folder-$value'),
          onTap: () => _setFolder(value),
          borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
          child: Container(
            padding:
                EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 8 : 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
              border: Border.all(
                  color: active
                      ? tone.withOpacity(.5)
                      : compact
                          ? WorkstationTokens.line(context)
                          : Colors.transparent),
            ),
            child: Row(
                mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  Icon(_scopeIcon(value),
                      size: 15,
                      color: active ? tone : OipTokens.muted(context)),
                  const SizedBox(width: 8),
                  if (compact)
                    Text(_scopeTitle(value),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontSize: 12.5,
                            color: active
                                ? tone
                                : Theme.of(context).colorScheme.onSurface))
                  else
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_scopeTitle(value),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                      fontSize: 12.5,
                                      color: active
                                          ? tone
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface)),
                          Text(_scopeCaption(value),
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontSize: 10.5)),
                        ],
                      ),
                    ),
                  if (count != null) ...[
                    const SizedBox(width: 8),
                    Text('$count',
                        style: WorkstationTokens.mono(context,
                            size: 11,
                            color: active ? tone : OipTokens.muted(context))),
                  ],
                ]),
          ),
        ),
      ),
    );
  }

  Widget _statusLine(BuildContext context, String label, String value,
      {String? status}) {
    final tone = status == null
        ? OipTokens.muted(context)
        : OipTokens.statusColor(context, status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 84,
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: WorkstationTokens.eyebrow(context)),
        ),
        if (status != null) ...[
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(value,
              overflow: TextOverflow.ellipsis,
              style: WorkstationTokens.mono(context,
                  size: 11.5,
                  color: status == null
                      ? Theme.of(context).colorScheme.onSurface
                      : tone)),
        ),
      ]),
    );
  }

  Widget _rail(BuildContext context, Snapshot snapshot,
      Map<String, Observation> liveById, String? primary,
      {required bool bounded}) {
    final system = snapshot.system;
    final source = _selectedSourceInfo;
    final sourceConnection = source?.connection ?? system.opcua;
    final sourceSubscription = _currentSource == snapshot.primarySourceId
        ? system.subscription
        : 'unknown';
    final first = _total == 0 ? 0 : (page?.offset ?? offset) + 1;
    final last = math.min(_total, (page?.offset ?? offset) + _pageSize);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const PanelLabel('Quelle', color: OipTokens.violet),
        _sourceSelector(context),
        if (sourcesError != null)
          Text(sourcesError!, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        _statusLine(context, 'OPC UA', known(sourceConnection),
            status: sourceConnection),
        _statusLine(context, 'Subscription', known(sourceSubscription),
            status: sourceSubscription),
        _statusLine(
            context,
            'Szenario',
            // The scenario is a concept of the demo. The authorized scope
            // carries no scenario: the line names that instead of showing an
            // internal wire value as a fact.
            system.demoControls
                ? (scenarios[system.scenario] ?? known(system.scenario))
                : 'nicht geliefert'),
        _statusLine(context, 'Ursprung',
            (source?.simulated ?? system.simulated) ? 'Simulation' : 'Backend'),
        const Hairline(),
        PanelLabel('Adressraum',
            color: OipTokens.violet,
            trailing: Text('${theScopes.length} Scopes',
                style: WorkstationTokens.mono(context,
                    size: 10, color: OipTokens.muted(context)))),
        Text(_namespaceLabel(), style: Theme.of(context).textTheme.titleSmall),
        Text('Index aus den gelieferten Nodes · flacher Katalog',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontSize: 10.5)),
        const SizedBox(height: OipTokens.s2),
        for (final value in theScopes)
          Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: _scopeRow(context, value)),
        const Hairline(),
        const PanelLabel('Datendichte', color: OipTokens.violet),
        _statusLine(context, 'Im Scope', '$_total Nodes'),
        _statusLine(
            context, 'Sichtbar', _total == 0 ? '—' : 'Position $first–$last'),
        _statusLine(context, 'Je Abruf', '$_pageSize'),
        _statusLine(
            context,
            _currentEntity == null ? 'Live' : 'Live ${_currentEntity!}',
            '${liveById.length} Variablen'),
        const Hairline(),
        PanelLabel('Angeheftet',
            color: OipTokens.violet,
            trailing: Text('${pinned.length}/$maxPins',
                style: WorkstationTokens.mono(context,
                    size: 10, color: OipTokens.muted(context)))),
        if (pinned.isEmpty)
          Text(
              'Mit P oder dem Pin-Symbol anheften, um Werte nebeneinander zu halten.',
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11))
        else
          for (final entry in pinned.entries)
            _pinnedRow(context, entry.value, liveById, _keySource(entry.key)),
        if (recent.isNotEmpty) ...[
          const Hairline(),
          const PanelLabel('Zuletzt betrachtet', color: OipTokens.violet),
          for (final entry in recent.entries)
            _recentRow(context, entry.value, _keySource(entry.key)),
        ],
        const Hairline(),
        const WorkstationNote(
          'Keine Referenzhierarchie verfügbar',
          'Ordner sind die Parent-Namen des Adressraums des Servers. Parent, Children und BrowseReferences werden nicht geliefert; deshalb zeigt OIP keinen erfundenen Baum.',
          icon: Icons.account_tree_outlined,
          color: OipTokens.violet,
        ),
        const SizedBox(height: OipTokens.s3),
        const Align(
          alignment: Alignment.centerLeft,
          child: StatusPill('READ-ONLY · RUST-CAPABILITIES',
              color: OipTokens.lime, icon: Icons.lock_outline),
        ),
      ],
    );
    return WorkstationPanel(
      accent: OipTokens.violet,
      padding: const EdgeInsets.all(14),
      child: bounded ? SingleChildScrollView(child: content) : content,
    );
  }

  Widget _pinnedRow(BuildContext context, OpcNode node,
      Map<String, Observation> liveById, String? primary) {
    final (observation, _) = _resolve(node, liveById, primary);
    final active = selected != null &&
        _nodeKey(
                selected!, selectedNodeSource ?? _currentSource ?? 'unknown') ==
            _nodeKey(node, primary ?? 'unknown');
    final tone = OipTokens.readableAccent(context, OipTokens.violet);
    return Semantics(
      button: true,
      selected: active,
      label: 'Angeheftet ${node.name}',
      child: Material(
        color: active ? tone.withOpacity(.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: Key('pin-${node.name}'),
          onTap: () => _select(node, source: primary),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: Row(children: [
              TypeGlyph(node.dataType, size: 18, active: active),
              const SizedBox(width: 8),
              Expanded(
                child: Text(node.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: active
                            ? tone
                            : Theme.of(context).colorScheme.onSurface)),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(_nodeValue(node, observation),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: WorkstationTokens.mono(context,
                        size: 11,
                        color: observation == null
                            ? OipTokens.muted(context)
                            : null)),
              ),
              const SizedBox(width: 6),
              StatusIndicator(observation?.quality, size: 6),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Pin entfernen',
                child: InkWell(
                  onTap: () => _togglePin(node, source: primary),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(Icons.close,
                        size: 12, color: OipTokens.muted(context)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _recentRow(BuildContext context, OpcNode node, String source) =>
      Semantics(
          button: true,
          label: 'Zuletzt ${node.name}, Quelle $source',
          child: InkWell(
            onTap: () => _select(node, source: source),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(children: [
                TypeGlyph(node.dataType, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(node.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                ),
                Text(node.folder,
                    style: WorkstationTokens.mono(context,
                        size: 10, color: OipTokens.muted(context))),
              ]),
            ),
          ));

  /// Compact horizontal context for tablet and mobile widths.
  Widget _contextStrip(BuildContext context, Snapshot snapshot,
      Map<String, Observation> liveById, String? primary) {
    final system = snapshot.system;
    return WorkstationPanel(
      accent: OipTokens.violet,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: OipTokens.s2,
            runSpacing: OipTokens.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final value in theScopes)
                _scopeRow(context, value, compact: true),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: OipTokens.s4,
            runSpacing: 4,
            children: [
              Text(_namespaceLabel(),
                  style: Theme.of(context).textTheme.titleSmall),
              SizedBox(
                  width: 260, child: _sourceSelector(context, compact: true)),
              Text('$_total Nodes im Scope',
                  style: WorkstationTokens.mono(context,
                      size: 11.5, color: OipTokens.muted(context))),
              Text('${liveById.length} live · ${known(system.subscription)}',
                  style: WorkstationTokens.mono(context,
                      size: 11.5,
                      color:
                          OipTokens.statusColor(context, system.subscription))),
            ],
          ),
          if (pinned.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in pinned.entries)
                  InputChip(
                    key: Key('pin-${entry.value.name}'),
                    avatar: TypeGlyph(entry.value.dataType, size: 18),
                    label: Text(
                        '${entry.value.name} · ${_nodeValue(entry.value, _resolve(entry.value, liveById, _keySource(entry.key)).$1)}',
                        style: const TextStyle(fontSize: 11.5)),
                    selected: selected != null &&
                        _nodeKey(
                                selected!,
                                selectedNodeSource ??
                                    _currentSource ??
                                    'unknown') ==
                            entry.key,
                    onPressed: () =>
                        _select(entry.value, source: _keySource(entry.key)),
                    onDeleted: () =>
                        _togglePin(entry.value, source: _keySource(entry.key)),
                    deleteIconColor: OipTokens.muted(context),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------- explorer

  Widget _pageFilter<T extends String>(
    BuildContext context, {
    required Key key,
    required String label,
    required T? value,
    required List<T> values,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: WorkstationTokens.well(context),
        border: Border.all(color: WorkstationTokens.hairline(context)),
        borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
      ),
      child: DropdownButton<String>(
        key: key,
        value: value ?? '__all__',
        underline: const SizedBox.shrink(),
        isDense: true,
        style: Theme.of(context).textTheme.bodySmall,
        items: [
          DropdownMenuItem(value: '__all__', child: Text('$label: alle')),
          for (final item in values)
            DropdownMenuItem(value: item, child: Text('$label: $item')),
        ],
        onChanged: (selected) =>
            onChanged(selected == '__all__' ? null : selected as T?),
      ),
    );
  }

  Widget _explorer(BuildContext context, Map<String, Observation> liveById,
      String? primary, bool alarm,
      {bool autofocus = false}) {
    final allItems = page?.items ?? const <OpcNode>[];
    final items = _filteredItems(allItems, liveById, primary);
    final cyan = OipTokens.readableAccent(context, OipTokens.cyan);
    final liveOnPage = items.where((n) => liveById.containsKey(n.name)).length;
    final scopeLabel =
        '${_scopeTitle(folder)} · ${_scopeCaption(folder)}${search.trim().isEmpty ? '' : ' · Serverweite Namenssuche „${search.trim()}“'}';
    return WorkstationPanel(
      accent: OipTokens.cyan,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('node-search'),
                  controller: searchController,
                  focusNode: searchFocus,
                  decoration: InputDecoration(
                    hintText: 'Nodes durchsuchen',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: search.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: Align(
                                widthFactor: 1,
                                heightFactor: 1,
                                child: KbdHint('/')))
                        : IconButton(
                            tooltip: 'Suche löschen',
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close, size: 16),
                          ),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(width: 8),
              ToolButton(
                key: const Key('filters-toggle'),
                icon: Icons.filter_alt_outlined,
                tooltip: 'Seitenfilter für Typ und Quality',
                accent: OipTokens.cyan,
                active:
                    showFilters || typeFilter != null || qualityFilter != null,
                onPressed: () {
                  setState(() => showFilters = !showFilters);
                  widget.controller
                      .setAdvancedFilters(WorkspaceId.opcua, showFilters);
                },
              ),
              const SizedBox(width: 4),
              ToolButton(
                key: const Key('view-list'),
                icon: Icons.view_list_outlined,
                tooltip: 'Flache Liste',
                accent: OipTokens.cyan,
                active: view == _ViewMode.list,
                onPressed: () {
                  setState(() => view = _ViewMode.list);
                  widget.controller
                      .setWorkspaceView(WorkspaceId.opcua, view.name);
                },
              ),
              const SizedBox(width: 4),
              ToolButton(
                key: const Key('view-grouped'),
                icon: Icons.segment_outlined,
                tooltip: 'Nach Datentyp gruppieren',
                accent: OipTokens.cyan,
                active: view == _ViewMode.grouped,
                onPressed: () {
                  setState(() => view = _ViewMode.grouped);
                  widget.controller
                      .setWorkspaceView(WorkspaceId.opcua, view.name);
                },
              ),
            ]),
          ),
          if (showFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Server-Suche: Browse-Name des Servers · gesamte ausgewählte Quelle. Typ/Quality: nur geladene Seite.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontSize: 10.5),
                    ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      _pageFilter<String>(
                        context,
                        key: const Key('type-filter'),
                        label: 'Typ',
                        value: typeFilter,
                        values: allItems
                            .map((node) => node.dataType)
                            .toSet()
                            .toList()
                          ..sort(),
                        onChanged: (value) =>
                            setState(() => typeFilter = value),
                      ),
                      _pageFilter<String>(
                        context,
                        key: const Key('quality-filter'),
                        label: 'Quality',
                        value: qualityFilter,
                        values: const ['good', 'uncertain', 'bad', 'unknown'],
                        onChanged: (value) =>
                            setState(() => qualityFilter = value),
                      ),
                      if (typeFilter != null || qualityFilter != null)
                        TextButton.icon(
                          key: const Key('clear-page-filters'),
                          onPressed: () => setState(() {
                            typeFilter = null;
                            qualityFilter = null;
                          }),
                          icon: const Icon(Icons.filter_alt_off_outlined,
                              size: 15),
                          label: const Text('Seitenfilter zurücksetzen'),
                        ),
                    ]),
                  ]),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: WorkstationTokens.well(context),
              border: Border.symmetric(
                  horizontal:
                      BorderSide(color: WorkstationTokens.hairline(context))),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 3,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(scopeLabel.toUpperCase(),
                    style: WorkstationTokens.eyebrow(context, color: cyan)),
                if (liveOnPage > 0)
                  Text('LIVE $liveOnPage',
                      style: WorkstationTokens.mono(context,
                          size: 10.5, color: cyan)),
                Text('${items.length}/${allItems.length} auf dieser Seite',
                    style: WorkstationTokens.mono(context,
                        size: 10.5, color: OipTokens.muted(context))),
              ],
            ),
          ),
          SizedBox(
            height: 2,
            child: loading
                ? const LinearProgressIndicator(minHeight: 2)
                : const SizedBox.shrink(),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: _notice(context, Icons.cloud_off_outlined,
                  'Browser nicht verfügbar', error!,
                  color: OipTokens.statusColor(context, 'degraded'),
                  action: TextButton(
                      onPressed: _load, child: const Text('Erneut versuchen'))),
            ),
          if (!loading && error == null && page != null && items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: _notice(
                  context,
                  Icons.search_off_outlined,
                  allItems.isEmpty ? 'Keine Nodes' : 'Keine Seiten-Treffer',
                  allItems.isEmpty
                      ? 'Suche ändern oder Collector-Verbindung prüfen.'
                      : 'Typ-/Quality-Filter gelten nur für diese geladene Seite. Filter zurücksetzen oder Seite wechseln.'),
            ),
          Expanded(
            child: Focus(
              focusNode: listFocus,
              autofocus: autofocus,
              onKeyEvent: _onListKey,
              child: Builder(builder: (context) {
                final focused = Focus.of(context).hasFocus;
                return Container(
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(
                        color: focused
                            ? OipTokens.readableAccent(context, OipTokens.cyan)
                            : Colors.transparent),
                    borderRadius:
                        BorderRadius.circular(WorkstationTokens.radiusSm),
                  ),
                  child: _list(context, items, liveById, primary, alarm),
                );
              }),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: WorkstationTokens.hairline(context))),
            ),
            child: Row(children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('$_total Nodes · Seite $_pageIndex',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface)),
                    Text('von $_pageCount',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              ToolButton(
                icon: Icons.first_page,
                tooltip: 'Zum Anfang',
                accent: OipTokens.cyan,
                onPressed: _hasPrevious ? () => _goTo(0) : null,
              ),
              const SizedBox(width: 4),
              ToolButton(
                icon: Icons.chevron_left,
                tooltip: 'Vorherige Nodes',
                accent: OipTokens.cyan,
                onPressed:
                    _hasPrevious ? () => _goTo(offset - _pageSize) : null,
              ),
              const SizedBox(width: 4),
              ToolButton(
                key: const Key('next-nodes'),
                icon: Icons.chevron_right,
                tooltip: 'Nächste Nodes',
                accent: OipTokens.cyan,
                onPressed: _hasNext ? () => _goTo(offset + _pageSize) : null,
              ),
              const SizedBox(width: 4),
              ToolButton(
                icon: Icons.last_page,
                tooltip: 'Zum Ende',
                accent: OipTokens.cyan,
                onPressed:
                    _hasNext ? () => _goTo((_pageCount - 1) * _pageSize) : null,
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _notice(
      BuildContext context, IconData icon, String title, String message,
      {Color? color, Widget? action}) {
    final tone = color ?? OipTokens.muted(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WorkstationTokens.well(context),
        borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
        border: Border.all(color: WorkstationTokens.hairline(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 8),
          Expanded(
              child:
                  Text(title, style: Theme.of(context).textTheme.titleSmall)),
        ]),
        const SizedBox(height: 4),
        Text(message, style: Theme.of(context).textTheme.bodySmall),
        if (action != null) action,
      ]),
    );
  }

  Widget _list(BuildContext context, List<OpcNode> items,
      Map<String, Observation> liveById, String? primary, bool alarm) {
    final rowHeight =
        dense ? WorkstationTokens.rowDense : WorkstationTokens.rowComfortable;
    Widget row(OpcNode node) {
      final (observation, live) = _resolve(node, liveById, primary);
      return _NodeRow(
        key: Key('node-${node.name}'),
        node: node,
        active: selected != null &&
            _nodeKey(selected!,
                    selectedNodeSource ?? _currentSource ?? 'unknown') ==
                _nodeKey(node, primary ?? 'unknown'),
        dense: dense,
        pinned: pinned.containsKey(_nodeKey(node, primary ?? 'unknown')),
        live: live,
        value: _nodeValue(node, observation),
        quality: observation?.quality,
        alarm: alarm && node.name == 'temperature',
        onTap: () => _select(node, focusList: true, source: primary),
      );
    }

    const padding = EdgeInsets.fromLTRB(8, 6, 8, 6);
    if (view == _ViewMode.list) {
      return ListView.builder(
        key: const Key('node-list'),
        controller: listScroll,
        padding: padding,
        itemExtent: rowHeight,
        itemCount: items.length,
        itemBuilder: (context, index) => row(items[index]),
      );
    }
    final groups = <NodeTypeFamily, List<OpcNode>>{};
    for (final node in items) {
      groups.putIfAbsent(nodeTypeFamily(node.dataType), () => []).add(node);
    }
    final entries = <Object>[];
    for (final family in NodeTypeFamily.values) {
      final members = groups[family];
      if (members == null) continue;
      entries.add(family);
      entries.addAll(members);
    }
    return ListView.builder(
      key: const Key('node-list'),
      controller: listScroll,
      padding: padding,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry is NodeTypeFamily) {
          final tone = nodeTypeColor(context, entry);
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
            child: Row(children: [
              Text(nodeTypeFamilyLabel(entry).toUpperCase(),
                  style: WorkstationTokens.eyebrow(context, color: tone)),
              const SizedBox(width: 8),
              Text('${groups[entry]!.length}',
                  style: WorkstationTokens.mono(context,
                      size: 10, color: OipTokens.muted(context))),
              const SizedBox(width: 8),
              Expanded(
                  child: Container(
                      height: 1, color: WorkstationTokens.hairline(context))),
            ]),
          );
        }
        return SizedBox(height: rowHeight, child: row(entry as OpcNode));
      },
    );
  }

  // ------------------------------------------------------------- inspector

  Widget _inspectorArea(BuildContext context, Snapshot snapshot, OpcNode? node,
      Observation? observation, bool live, bool alarm, String? primary,
      {required bool bounded}) {
    final child = showCompare
        ? OpcCompareWorkspace(
            bounded: bounded,
            entries: _compareEntries(_liveMap(), primary),
            onRemove: (entry) => setState(
                () => compared.remove(_nodeKey(entry.node, entry.sourceId))),
            onClear: () => setState(() => compared.clear()),
            onClose: () => setState(() => showCompare = false),
          )
        : _inspector(context, snapshot, node, observation, live, alarm, primary,
            bounded: bounded);
    return Focus(
      focusNode: inspectorFocus,
      child: Builder(builder: (context) {
        final focused = Focus.of(context).hasFocus;
        return Container(
          foregroundDecoration: BoxDecoration(
            border: Border.all(
                color: focused
                    ? OipTokens.readableAccent(context, OipTokens.violet)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(WorkstationTokens.radius),
          ),
          child: child,
        );
      }),
    );
  }

  Widget _inspector(BuildContext context, Snapshot snapshot, OpcNode? node,
      Observation? observation, bool live, bool alarm, String? primary,
      {required bool bounded}) {
    if (node == null) {
      return WorkstationPanel(
        accent: OipTokens.violet,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.manage_search_outlined,
                size: 28,
                color: OipTokens.readableAccent(context, OipTokens.violet)),
            const SizedBox(height: OipTokens.s3),
            Text('Node auswählen',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: OipTokens.s1),
            Text('Wähle eine Variable aus dem Adressraum.',
                style: Theme.of(context).textTheme.bodyMedium),
          ]),
        ),
      );
    }
    final system = snapshot.system;
    final cyan = OipTokens.readableAccent(context, OipTokens.cyan);
    final isAlarm = alarm && node.name == 'temperature';
    final valueTone = isAlarm
        ? OipTokens.statusColor(context, 'alarm')
        : observation == null
            ? OipTokens.muted(context)
            : cyan;
    final nodeSource = selectedNodeSource ?? _sourceFor(node);
    final nodeKey = _nodeKey(node, nodeSource);
    final isPinned = pinned.containsKey(nodeKey);
    final isCompared = compared.containsKey(nodeKey);
    final samples = _samplesFor(node, nodeSource);
    final analysis = SessionAnalysis.fromSamples(samples);
    final numbers = samples
        .where((sample) => sample.quality == 'good')
        .map((sample) => sample.number)
        .whereType<double>()
        .toList();
    final family = nodeTypeFamily(node.dataType);
    final stale = widget.controller.stale;
    final symbol = observation?.symbol ?? '';
    final simulated = _selectedSourceInfo?.simulated ?? system.simulated;

    String historyNote() {
      if (!live) {
        return 'Kein Verlauf · Einzelabfrage. Die API liefert für diese Node keine History.';
      }
      if (family != NodeTypeFamily.numeric || observation?.number == null) {
        return 'Kein numerischer Verlauf für diesen Datentyp.';
      }
      return 'Verlauf baut sich aus echten Live-Snapshots auf · ${numbers.length} Punkt${numbers.length == 1 ? '' : 'e'}.';
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TypeGlyph(node.dataType, size: 40, active: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(node.name,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 2),
                Text('ns=${node.namespace} · ${node.folder} · ${node.id}',
                    overflow: TextOverflow.ellipsis,
                    style: WorkstationTokens.mono(context,
                        size: 11, color: OipTokens.muted(context))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ToolButton(
            key: const Key('pin-toggle'),
            icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            tooltip: isPinned ? 'Pin entfernen' : 'Node anheften',
            active: isPinned,
            onPressed: !isPinned && pinned.length >= maxPins
                ? null
                : () => _togglePin(node),
          ),
          const SizedBox(width: 4),
          ToolButton(
            key: const Key('compare-toggle'),
            icon: isCompared
                ? Icons.compare_arrows
                : Icons.compare_arrows_outlined,
            tooltip: isCompared
                ? 'Aus Vergleich entfernen (C)'
                : 'Zum Vergleich hinzufügen (C)',
            active: isCompared,
            accent: OipTokens.cyan,
            onPressed: !isCompared && compared.length >= maxCompare
                ? null
                : () => _toggleCompare(node),
          ),
          const SizedBox(width: 4),
          ToolButton(
            icon: Icons.copy_outlined,
            tooltip: 'NodeId kopieren',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: node.id));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('NodeId kopiert')));
            },
          ),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            color: WorkstationTokens.well(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: WorkstationTokens.hairline(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Text('AKTUELLER WERT',
                    style: WorkstationTokens.eyebrow(context, color: cyan)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    live
                        ? 'Live-Abonnement'
                        : observation == null
                            ? 'Kein Wert'
                            : 'Einzelabfrage · ${_clock(observation.receivedMs)}',
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: WorkstationTokens.mono(context,
                        size: 10.5, color: OipTokens.muted(context)),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('DARSTELLUNG',
                        style: WorkstationTokens.eyebrow(context)),
                    DropdownButton<OpcValueFormat>(
                      key: const Key('value-format'),
                      value: valueFormat,
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      style: Theme.of(context).textTheme.bodySmall,
                      items: [
                        for (final mode in OpcValueFormat.values)
                          DropdownMenuItem(
                              value: mode,
                              child: Text(opcValueFormatLabel(mode)))
                      ],
                      onChanged: (mode) => setState(
                          () => valueFormat = mode ?? OpcValueFormat.original),
                    ),
                    ToolButton(
                      key: const Key('copy-original-value'),
                      icon: Icons.copy_all_outlined,
                      tooltip: 'Unveränderten API-Wert kopieren',
                      accent: OipTokens.cyan,
                      onPressed: observation == null
                          ? null
                          : () async {
                              await Clipboard.setData(ClipboardData(
                                  text: originalObservationValue(observation)));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Originalwert kopiert')));
                            },
                    ),
                  ]),
              Text(
                observationValueWithUnit(observation, valueFormat),
                key: const Key('node-value'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontSize: 28,
                  height: 1.15,
                  color: valueTone,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (valueFormat != OpcValueFormat.original)
                Text(
                  'Formatierte Ansicht · Original bleibt per Kopieraktion abrufbar',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusPill(known(observation?.quality),
                      color:
                          OipTokens.statusColor(context, observation?.quality),
                      showDot: true),
                  StatusPill(
                    stale
                        ? 'Veraltet'
                        : live
                            ? known(observation!.freshness)
                            : 'Einzelabfrage',
                    color: stale
                        ? OipTokens.statusColor(context, 'degraded')
                        : OipTokens.statusColor(
                            context, observation?.freshness),
                    showDot: true,
                  ),
                  StatusPill(simulated ? 'OPC-UA-SIMULATOR' : 'OPC-UA-API',
                      color: OipTokens.statusColor(context, 'info'),
                      icon: system.simulated
                          ? Icons.science_outlined
                          : Icons.cloud_done_outlined),
                ],
              ),
              const SizedBox(height: 12),
              Row(children: [
                Text('SITZUNGSVERLAUF',
                    style: WorkstationTokens.eyebrow(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    numbers.length >= 2
                        ? '${numbers.length} Punkte · ${simulated ? 'virtuelle Quellzeit' : 'Quellzeit'}'
                        : '',
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: WorkstationTokens.mono(context,
                        size: 10.5, color: OipTokens.muted(context)),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              if (numbers.length >= 2) ...[
                Sparkline(numbers, color: valueTone),
                const SizedBox(height: 4),
                Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: OipTokens.s3,
                    children: [
                      Text(
                          'Min ${formatNumberForAnalysis(analysis.minimum!)} $symbol'
                              .trim(),
                          style: WorkstationTokens.mono(context,
                              size: 10.5, color: OipTokens.muted(context))),
                      Text(
                          'Max ${formatNumberForAnalysis(analysis.maximum!)} $symbol'
                              .trim(),
                          style: WorkstationTokens.mono(context,
                              size: 10.5, color: OipTokens.muted(context))),
                    ]),
              ] else
                Text(historyNote(),
                    style: Theme.of(context).textTheme.bodySmall),
              if (analysis.sampleCount > 0) ...[
                const Hairline(vertical: 8),
                KeyValueGrid(children: [
                  KeyValue('Samples · Session', '${analysis.sampleCount}'),
                  KeyValue('Quality-Wechsel', '${analysis.qualityChanges}'),
                  KeyValue(
                      'Zeitbereich · Quellzeit',
                      analysis.sourceRangeMs == null
                          ? 'Unbekannt'
                          : '${analysis.sourceRangeMs} ms'),
                  KeyValue(
                      'Größter Sample-Abstand · kein Datenlückenbeweis',
                      analysis.largestSampleGapMs == null
                          ? 'Nicht ableitbar'
                          : '${analysis.largestSampleGapMs} ms',
                      mono: false),
                  KeyValue(
                      'Letzter Empfang', timestamp(analysis.lastReceivedMs)),
                ]),
              ],
              const SizedBox(height: OipTokens.s2),
              const WorkstationNote(
                'Historische API nicht verfügbar',
                'Dieser Verlauf enthält ausschließlich reale Samples dieser UI-Sitzung. Er ist keine Server-History. Datenlücken und frühere Werte können ohne HistoryQuery nicht bestimmt werden.',
                key: Key('history-unavailable'),
                icon: Icons.history_toggle_off_outlined,
                color: OipTokens.violet,
              ),
            ],
          ),
        ),
        _section(context, 'Identität', [
          KeyValue('NodeId', node.id),
          KeyValue('Namespace', 'ns=${node.namespace}'),
          KeyValue('Name · BrowseName des Servers', node.name),
          KeyValue('Ordner · Parent im Adressraum des Servers', node.folder,
              mono: false),
          KeyValue('Datenquelle', nodeSource),
          const KeyValue('Parent / References',
              'Nicht verfügbar · keine BrowseReferences-Capability',
              mono: false),
        ]),
        _section(context, 'Zugriff & Typ', [
          KeyValue('Datentyp · Core-Angabe',
              '${node.dataType} · ${nodeTypeCode(node.dataType)}'),
          KeyValue('Zugriff · Core-Angabe', _accessLabel(node.access)),
          KeyValue('Wertetyp', _valueKind(observation)),
          const KeyValue('Schreibpfad', 'Nicht vorhanden · read-only by design',
              mono: false),
        ]),
        const ExpansionTile(
          key: Key('technical-details'),
          title: Text('Technische OPC-UA-Details'),
          subtitle:
              Text('Nicht gelieferte Attribute ausdrücklich kennzeichnen'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          children: [
            KeyValueGrid(children: [
              KeyValue('BrowseName', 'Nicht von API geliefert', mono: false),
              KeyValue('DisplayName', 'Nicht von API geliefert', mono: false),
              KeyValue('NodeClass', 'Nicht von API geliefert', mono: false),
              KeyValue('ValueRank', 'Nicht von API geliefert', mono: false),
              KeyValue('ArrayDimensions', 'Nicht von API geliefert',
                  mono: false),
              KeyValue('AccessLevel / UserAccessLevel',
                  'Nicht von Serverattributen geliefert',
                  mono: false),
              KeyValue('Historizing', 'Nicht von API geliefert', mono: false),
            ]),
          ],
        ),
        _section(context, 'Zeitstempel', [
          KeyValue(
              simulated
                  ? 'SourceTimestamp · virtuelle Quellzeit'
                  : 'SourceTimestamp',
              timestamp(observation?.sourceMs)),
          KeyValue('ServerTimestamp', timestamp(observation?.serverMs)),
          KeyValue('ReceivedTimestamp · lokale Empfangszeit',
              timestamp(observation?.receivedMs)),
          KeyValue('Server → Empfang · inkl. Uhrendifferenz',
              _delta(observation?.serverMs, observation?.receivedMs)),
          KeyValue('Alter bei Snapshot · lokale Empfangszeit',
              _delta(observation?.receivedMs, system.generatedMs)),
        ]),
        _section(context, 'Qualität & Erfassung', [
          KeyValue('Quality',
              '${known(observation?.quality)} · ${observation?.quality ?? 'unknown'}',
              color: OipTokens.statusColor(context, observation?.quality)),
          KeyValue('StatusCode', _statusCode(observation?.statusCode)),
          KeyValue('CollectionError',
              observation?.collectionError ?? 'Keine gemeldet',
              color: observation?.collectionError == null
                  ? null
                  : OipTokens.statusColor(context, 'degraded')),
          KeyValue('Freshness (API)',
              '${known(observation?.freshness)} · ${observation?.freshness ?? 'unknown'}'),
          KeyValue(
              'Quality-Bedeutung', _qualityExplanation(observation?.quality),
              mono: false),
        ]),
        _section(context, 'Subscription', [
          KeyValue(
              'Status',
              live
                  ? known(system.subscription)
                  : 'Nicht abonniert · gezielte API-Einzelabfrage',
              mono: false),
          KeyValue(
              'Modus',
              live
                  ? 'Fortlaufendes Abonnement über den Rust-Adapter'
                  : 'Seitenweise gelesen · die Messung entsteht im Kollektor',
              mono: false),
        ]),
        _section(context, 'Provenienz', [
          KeyValue(
              'Ursprung',
              observation == null
                  ? 'Unbekannt'
                  : observation.simulated
                      ? 'Simulation · simulation_origin'
                      : 'Backend',
              mono: false),
          KeyValue('Snapshot erzeugt', timestamp(system.generatedMs)),
        ]),
        const SizedBox(height: OipTokens.s3),
        const WorkstationNote(
          'Sicherer Analysemodus',
          'Lesender Adressraumzugriff über typisierte Rust-Capabilities. Die Messung entsteht im Kollektor; der Browser liest den Adressraum des Servers, ohne zu messen und ohne zu schreiben. Kein Schreibpfad – by design.',
          icon: Icons.lock_outline,
          color: OipTokens.lime,
        ),
      ],
    );
    return WorkstationPanel(
      accent: OipTokens.violet,
      child: bounded ? SingleChildScrollView(child: content) : content,
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> rows) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Hairline(vertical: 10),
        PanelLabel(title, color: OipTokens.violet),
        KeyValueGrid(children: rows),
      ]);

  // --------------------------------------------------------------- helpers

  String _accessLabel(String access) =>
      access == 'Read' ? 'Read · lesend' : access;

  String _valueKind(Observation? observation) {
    if (observation == null) return 'Unbekannt';
    if (!observation.valueValid) return 'Ungültig';
    final value = observation.value;
    if (value == null) return 'Unbekannt';
    if (value is bool) return 'Boolean';
    if (value is int) return 'Ganzzahl';
    if (value is num) return 'Gleitkomma';
    if (value is String) return 'Text';
    return value.runtimeType.toString();
  }

  String _qualityExplanation(String? quality) => switch (quality) {
        'good' => 'Vom Core als uneingeschränkt nutzbar geliefert.',
        'uncertain' =>
          'Vom Core als unsicher markiert; Wert mit Vorsicht lesen.',
        'bad' => 'Vom Core als ungültig markiert; CollectionError prüfen.',
        'unknown' => 'Keine belastbare Quality-Angabe geliefert.',
        null => 'Keine Beobachtung geliefert.',
        _ => 'Unbekannter Quality-Code aus der API.',
      };

  String _statusCode(int? code) => code == null
      ? 'Unbekannt'
      : '$code · 0x${code.toRadixString(16).padLeft(8, '0').toUpperCase()}${code == 0 ? ' · Good' : ''}';

  String _delta(int? server, int? received) =>
      server == null || received == null
          ? 'Unbekannt'
          : '${received - server} ms';

  String _clock(int? ms) {
    if (ms == null) return 'unbekannt';
    final value = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    String two(int part) => part.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)} UTC';
  }

  String _nodeValue(OpcNode node, Observation? observation) {
    final value = observation?.display ?? 'Unbekannt';
    final symbol = observation?.symbol ?? '';
    if (observation?.number == null) {
      return '$value $symbol'.trim();
    }
    if (value.contains('e') || value.contains('E')) {
      return '$value $symbol'.trim();
    }
    // Large values are grouped. The rule depends on the **value**, not on
    // the name of a folder of a demo.
    if (value.split('.').first.replaceAll('-', '').length < 5) {
      return '$value $symbol'.trim();
    }
    final parts = value.split('.');
    final grouped = parts.first.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]}.');
    return '${parts.length > 1 ? '$grouped,${parts.last}' : grouped} $symbol'
        .trim();
  }
}

/// One explorer row. Hover state stays local so the page does not rebuild.
class _NodeRow extends StatefulWidget {
  final OpcNode node;
  final bool active, dense, pinned, live, alarm;
  final String value;
  final String? quality;
  final VoidCallback onTap;
  const _NodeRow({
    super.key,
    required this.node,
    required this.active,
    required this.dense,
    required this.pinned,
    required this.live,
    required this.alarm,
    required this.value,
    required this.quality,
    required this.onTap,
  });

  @override
  State<_NodeRow> createState() => _NodeRowState();
}

class _NodeRowState extends State<_NodeRow> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final tone = OipTokens.readableAccent(context, OipTokens.violet);
    final cyan = OipTokens.readableAccent(context, OipTokens.cyan);
    final scheme = Theme.of(context).colorScheme;
    final active = widget.active;
    final dense = widget.dense;
    final background = active
        ? tone.withOpacity(.13)
        : hover
            ? WorkstationTokens.hover(context)
            : Colors.transparent;
    final valueColor = widget.alarm
        ? OipTokens.statusColor(context, 'alarm')
        : widget.quality == null
            ? OipTokens.muted(context)
            : scheme.onSurface;
    final label = StringBuffer(
        'Node ${widget.node.name}, ${widget.node.dataType}, ${widget.value}');
    if (widget.quality != null) {
      label.write(', ${OipTokens.statusLabel(widget.quality)}');
    }
    if (widget.live) label.write(', live');
    return Semantics(
      button: true,
      selected: active,
      label: label.toString(),
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(WorkstationTokens.radiusSm),
                  border: Border.all(
                      color:
                          active ? tone.withOpacity(.5) : Colors.transparent),
                ),
                child: Row(children: [
                  Container(
                    width: 2,
                    height: dense ? 14 : 24,
                    decoration: BoxDecoration(
                        color: active ? tone : Colors.transparent,
                        borderRadius: BorderRadius.circular(1)),
                  ),
                  const SizedBox(width: 8),
                  TypeGlyph(widget.node.dataType,
                      size: dense ? 20 : 28, active: active),
                  const SizedBox(width: 10),
                  Expanded(
                    child: dense
                        ? Text(widget.node.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: active ? tone : scheme.onSurface))
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.node.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: active ? tone : scheme.onSurface)),
                              const SizedBox(height: 1),
                              Text(widget.node.id,
                                  overflow: TextOverflow.ellipsis,
                                  style: WorkstationTokens.mono(context,
                                      size: 10.5,
                                      weight: FontWeight.w400,
                                      color: OipTokens.muted(context))),
                            ],
                          ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: dense ? 140 : 170),
                    child: Text(widget.value,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: WorkstationTokens.mono(context,
                            size: dense ? 11.5 : 12, color: valueColor)),
                  ),
                  const SizedBox(width: 8),
                  StatusIndicator(widget.quality, size: dense ? 6 : 7),
                  if (widget.live && !dense) ...[
                    const SizedBox(width: 6),
                    Text('LIVE',
                        style: WorkstationTokens.eyebrow(context, color: cyan)
                            .copyWith(fontSize: 8.5)),
                  ],
                  if (widget.pinned) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.push_pin, size: 12, color: tone),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
