import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/controller.dart';
import '../design_system/theme.dart';
import '../models/contracts.dart';
import '../models/diagnostics.dart';
import '../services/api.dart';
import '../widgets/adaptive_workspace.dart';
import '../widgets/components.dart';
import '../widgets/workstation.dart';
import 'diagnostics/diagnostics_model.dart';
import 'diagnostics/diagnostics_workspaces.dart';
import 'diagnostics/event_explorer.dart';
import 'diagnostics/evidence_inspector.dart';
import 'diagnostics/evidence_timeline.dart';

const scenarios = {
  'normal': 'Normalbetrieb',
  'gpu': 'Hohe GPU-Last',
  'inference': 'Langsame Inferenz',
  'vpn': 'VPN-Störung',
  'sensor': 'Sensoralarm',
  'agent': 'Remote-Agent fehlt',
  'offline': 'Offline & Reconnect'
};

enum _DiagnosticsMode { events, incidents, timeline, health, compare }

enum _MobilePane { explorer, workspace, inspector }

class DiagnosticsPage extends StatefulWidget {
  final OipController controller;
  const DiagnosticsPage(this.controller, {super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  final searchController = TextEditingController();
  final searchFocus = FocusNode(debugLabel: 'diagnostics-search');
  final listFocus = FocusNode(debugLabel: 'diagnostics-list');
  final inspectorFocus = FocusNode(debugLabel: 'diagnostics-inspector');
  Timer? refreshTimer, followUpTimer;

  List<DiagnosticEvent> allEvents = const [];
  List<SourceInfo> sources = const [];
  bool eventsLoaded = false, loadingEvents = false, loadingSources = false;
  bool eventsTruncated = false;
  String? eventsNextCursor;
  List<String> eventsMissingEvidence = const [];
  Object? eventsError, sourcesError;
  int generation = 0, sourcesGeneration = 0;
  String? scopeSignature;

  /// The persisted evidence of the authorized sources: the documented gaps and
  /// the health transitions that the Core stored.
  DiagnosticPage? documentedGaps, healthTransitions;
  Object? evidenceError;
  String diagnosisHistoryStatus = 'unknown';
  bool evidenceLoaded = false;
  int evidenceGeneration = 0;

  _DiagnosticsMode mode = _DiagnosticsMode.events;
  _MobilePane mobilePane = _MobilePane.explorer;
  bool showTimeline = true, showFilters = false;
  bool tabletExplorer = false, tabletInspector = false;
  String? selectedKey, sourceFilter, typeFilter;
  String? organizationFilter, infrastructureFilter, siteFilter;
  String query = '';
  DiagnosticEventSort sort = DiagnosticEventSort.newest;
  DiagnosticEventGrouping grouping = DiagnosticEventGrouping.none;
  DiagnosticTimeWindow timeWindow = DiagnosticTimeWindow.all;
  final pinned = <String>{};
  final recentKeys = <String>[];
  final compareKeys = <String>[];
  double timelineZoom = 1;
  int timelinePanMs = 0;

  @override
  void initState() {
    super.initState();
    scopeSignature = widget.controller.contextScopeSignature;
    final layout = widget.controller.workspaces.layout(WorkspaceId.diagnostics);
    mode = _DiagnosticsMode.values
            .where((item) => item.name == layout.view)
            .firstOrNull ??
        _DiagnosticsMode.events;
    showFilters = layout.advancedFilters;
    widget.controller.addListener(_controllerChanged);
    _loadEvents();
    _loadSources();
    _loadEvidence();
    // Bounded visible-page refresh. No overlapping request is started and stale
    // responses are rejected by generation; the API itself has no cancellation.
    refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _loadEvents(automatic: true);
      if (mode == _DiagnosticsMode.health) _loadSources(automatic: true);
    });
  }

  void _controllerChanged() {
    final next = widget.controller.contextScopeSignature;
    if (!mounted || next == scopeSignature) return;
    scopeSignature = next;
    generation++;
    sourcesGeneration++;
    setState(() {
      // A source/principal scope transition starts a fresh session workspace.
      allEvents = const [];
      sources = const [];
      eventsLoaded = false;
      eventsTruncated = false;
      eventsNextCursor = null;
      eventsMissingEvidence = const [];
      loadingEvents = false;
      loadingSources = false;
      eventsError = null;
      sourcesError = null;
      selectedKey = null;
      pinned.clear();
      recentKeys.clear();
      compareKeys.clear();
      sourceFilter = null;
      typeFilter = null;
      organizationFilter = null;
      infrastructureFilter = null;
      siteFilter = null;
      query = '';
      searchController.clear();
      timelineZoom = 1;
      timelinePanMs = 0;
    });
    _loadEvents();
    _loadSources();
  }

  Future<void> _loadEvents(
      {bool automatic = false, bool append = false}) async {
    if (loadingEvents || (automatic && searchFocus.hasFocus)) return;
    // An explicitly expanded cursor window is not undone by the periodic
    // first-page refresh. Manual refresh remains available.
    if (automatic && eventsTruncated) return;
    if (append && !eventsTruncated) return;
    loadingEvents = true;
    final current = ++generation;
    try {
      final result = await widget.controller.api.contextEventPage(
          widget.controller.infrastructure,
          cursor: append ? eventsNextCursor : null);
      if (!mounted || current != generation) return;
      final next = diagnosticEventsFromApi(append
          ? [...allEvents.map((item) => item.event), ...result.events]
          : result.events);
      if (!append && eventsError == null && _sameEventWindow(allEvents, next)) {
        return;
      }
      setState(() {
        allEvents = next;
        eventsLoaded = true;
        eventsError = null;
        eventsTruncated = result.truncated && result.nextCursor != null;
        eventsNextCursor = result.nextCursor;
        eventsMissingEvidence = result.missingEvidence;
        final valid = next.map((item) => item.key).toSet();
        if (!valid.contains(selectedKey)) selectedKey = null;
        pinned.removeWhere((key) => !valid.contains(key));
        recentKeys.removeWhere((key) => !valid.contains(key));
        compareKeys.removeWhere((key) => !valid.contains(key));
      });
    } catch (error) {
      if (!mounted || current != generation) return;
      setState(() {
        eventsError = error;
        eventsLoaded = true;
      });
    } finally {
      if (current == generation) loadingEvents = false;
    }
  }

  /// The persisted evidence exists only for an authorized transport. The legacy
  /// demo serves no diagnostic history and never pretends to.
  ///
  /// A continuation asks the same authorized route with the opaque cursor of
  /// the Core and merges the answer by the stable Core IDs, so no row is
  /// duplicated. A failed continuation keeps the evidence that is already
  /// loaded and offers a fresh authorized query.
  Future<void> _loadEvidence({bool moreGaps = false, bool moreHealth = false}) async {
    if (!widget.controller.managed) return;
    final current = ++evidenceGeneration;
    setState(() => evidenceBusy = true);
    try {
      final status = await widget.controller.api.collectionEventsWithStatus();
      final gapPage = moreHealth
          ? null
          : await widget.controller.api
              .diagnosticGaps(cursor: moreGaps ? documentedGaps?.nextCursor : null);
      final healthPage = moreGaps
          ? null
          : await widget.controller.api
              .healthHistory(cursor: moreHealth ? healthTransitions?.nextCursor : null);
      if (!mounted || current != evidenceGeneration) return;
      setState(() {
        diagnosisHistoryStatus = status.diagnosisHistoryStatus;
        if (gapPage != null) {
          documentedGaps =
              moreGaps ? documentedGaps!.followedBy(gapPage) : gapPage;
        }
        if (healthPage != null) {
          healthTransitions = moreHealth
              ? healthTransitions!.followedBy(healthPage)
              : healthPage;
        }
        evidenceError = null;
        evidenceLoaded = true;
      });
    } catch (error) {
      if (!mounted || current != evidenceGeneration) return;
      setState(() {
        evidenceError = error;
        evidenceLoaded = true;
      });
    } finally {
      if (mounted && current == evidenceGeneration) {
        setState(() => evidenceBusy = false);
      }
    }
  }

  /// A continuation of the authorized query is running.
  bool evidenceBusy = false;

  Future<void> _loadSources({bool automatic = false}) async {
    if (loadingSources || (automatic && searchFocus.hasFocus)) return;
    loadingSources = true;
    final current = ++sourcesGeneration;
    try {
      final result = await widget.controller.api
          .contextSources(widget.controller.infrastructure);
      if (!mounted || current != sourcesGeneration) return;
      setState(() {
        sources = result;
        sourcesError = null;
      });
    } catch (error) {
      if (!mounted || current != sourcesGeneration) return;
      setState(() => sourcesError = error);
    } finally {
      if (current == sourcesGeneration) loadingSources = false;
    }
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    followUpTimer?.cancel();
    generation++;
    sourcesGeneration++;
    widget.controller.removeListener(_controllerChanged);
    searchController.dispose();
    searchFocus.dispose();
    listFocus.dispose();
    inspectorFocus.dispose();
    super.dispose();
  }

  List<DiagnosticEvent> get filteredEvents => filterDiagnosticEvents(
        allEvents,
        query: query,
        source: sourceFilter,
        type: typeFilter,
        window: timeWindow,
        sort: sort,
        infrastructure: widget.controller.infrastructure,
        organization: organizationFilter,
        infrastructureId: infrastructureFilter,
        site: siteFilter,
      );

  DiagnosticEvent? get selected =>
      allEvents.where((item) => item.key == selectedKey).firstOrNull;

  List<DiagnosticEvent> get recent => recentKeys
      .map((key) => allEvents.where((item) => item.key == key).firstOrNull)
      .whereType<DiagnosticEvent>()
      .toList();

  List<DiagnosticEvent> get compared => compareKeys
      .map((key) => allEvents.where((item) => item.key == key).firstOrNull)
      .whereType<DiagnosticEvent>()
      .toList();

  void _select(DiagnosticEvent item, {bool showInspector = true}) {
    setState(() {
      selectedKey = item.key;
      recentKeys.remove(item.key);
      recentKeys.insert(0, item.key);
      if (recentKeys.length > 6) recentKeys.removeLast();
      if (MediaQuery.sizeOf(context).width < OipTokens.mobile &&
          showInspector) {
        mobilePane = _MobilePane.inspector;
      } else if (showInspector && MediaQuery.sizeOf(context).width < 1280) {
        tabletInspector = true;
        tabletExplorer = false;
      }
    });
    if (showInspector) {
      widget.controller.revealInspector(WorkspaceId.diagnostics);
    }
  }

  void _togglePin(DiagnosticEvent item) {
    if (!pinned.contains(item.key) && pinned.length >= 8) {
      _message('Maximal 8 angeheftete Ereignisse in dieser Session.');
      return;
    }
    setState(() {
      if (!pinned.remove(item.key)) pinned.add(item.key);
    });
  }

  void _toggleCompare(DiagnosticEvent item) {
    if (compareKeys.contains(item.key)) {
      setState(() => compareKeys.remove(item.key));
      return;
    }
    if (compareKeys.length >= 4) {
      _message(
          'Maximal 4 Ereignisse pro Vergleich. Erst einen Eintrag entfernen.');
      return;
    }
    setState(() {
      compareKeys.add(item.key);
      mode = _DiagnosticsMode.compare;
      if (MediaQuery.sizeOf(context).width < OipTokens.mobile) {
        mobilePane = _MobilePane.workspace;
      }
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  KeyEventResult _pageKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final command = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (command && key == LogicalKeyboardKey.keyK) {
      searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (searchFocus.hasFocus) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.slash) {
      searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      _fitTimeline();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP && selected != null) {
      _togglePin(selected!);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC && selected != null) {
      _toggleCompare(selected!);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        selectedKey = null;
        searchController.clear();
        query = '';
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _listKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || searchFocus.hasFocus) {
      return KeyEventResult.ignored;
    }
    final items = filteredEvents;
    if (items.isEmpty) return KeyEventResult.ignored;
    final current = items.indexWhere((item) => item.key == selectedKey);
    final key = event.logicalKey;
    var next = current;
    if (key == LogicalKeyboardKey.arrowDown) {
      next = math.min(items.length - 1, current + 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      next = math.max(0, current < 0 ? 0 : current - 1);
    } else if (key == LogicalKeyboardKey.home) {
      next = 0;
    } else if (key == LogicalKeyboardKey.end) {
      next = items.length - 1;
    } else if (key == LogicalKeyboardKey.enter && selected != null) {
      inspectorFocus.requestFocus();
      if (MediaQuery.sizeOf(context).width < OipTokens.mobile) {
        setState(() => mobilePane = _MobilePane.inspector);
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyP && selected != null) {
      _togglePin(selected!);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyC && selected != null) {
      _toggleCompare(selected!);
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    _select(items[next], showInspector: false);
    return KeyEventResult.handled;
  }

  DiagnosticsTimelineRange get _range => diagnosticsTimelineRange(
        filteredEvents,
        zoom: timelineZoom,
        panMs: timelinePanMs,
      );

  void _fitTimeline() {
    setState(() {
      mode = _DiagnosticsMode.timeline;
      showTimeline = true;
      timelineZoom = 1;
      timelinePanMs = 0;
    });
  }

  void _zoomTimeline(double factor) {
    setState(() {
      mode = _DiagnosticsMode.timeline;
      showTimeline = true;
      timelineZoom = (timelineZoom * factor).clamp(1.0, 64.0);
      timelinePanMs = _range.panMs;
    });
  }

  void _panTimeline(int delta) {
    setState(() => timelinePanMs = _range.panMs + delta);
  }

  void _focusSelectedTimeline() {
    final item = selected;
    if (item?.timestampMs == null) return;
    final base = diagnosticsTimelineRange(filteredEvents);
    final nextZoom = math.max(4.0, timelineZoom);
    final next = diagnosticsTimelineRange(filteredEvents,
        zoom: nextZoom,
        panMs: item!.timestampMs! - (base.startMs + base.spanMs ~/ 2));
    setState(() {
      mode = _DiagnosticsMode.timeline;
      showTimeline = true;
      timelineZoom = nextZoom;
      timelinePanMs = next.panMs;
      if (MediaQuery.sizeOf(context).width < OipTokens.mobile) {
        mobilePane = _MobilePane.workspace;
      }
    });
  }

  Future<void> _setScenario(String value) async {
    await widget.controller.setScenario(value);
    await _loadEvents();
    followUpTimer?.cancel();
    if (value == 'offline' || value == 'sensor') {
      followUpTimer = Timer(const Duration(seconds: 7), () {
        _loadEvents();
        _loadSources();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.snapshot!;
    final filtered = filteredEvents;
    final current = selected;
    final currentSource = current == null
        ? null
        : sources
            .where((source) => source.id == current.event.sourceId)
            .firstOrNull;
    return Focus(
      onKeyEvent: _pageKey,
      skipTraversal: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AdaptiveWorkspaceHeader(
          eyebrow: 'DIAGNOSTICS · EVIDENCE WORKSPACE',
          title: 'Diagnose & Ereignisse',
          subtitle:
              'Findings prüfen · Ereignis auswählen · Evidence gezielt vertiefen',
          accent: OipTokens.yellow,
          primaryAction: WorkspacePrimaryAction(
            buttonKey: const Key('diagnostics-primary-timeline'),
            label: 'Evidence Timeline',
            tooltip: 'Vollständige Timeline mit Source-Lanes direkt öffnen',
            icon: Icons.timeline_outlined,
            onPressed: () => _setMode(_DiagnosticsMode.timeline),
          ),
          actions: [
            InspectorOpenAction(
              controller: widget.controller,
              workspace: WorkspaceId.diagnostics,
              hasSelection: current != null,
              onOpen: () => setState(() {
                if (MediaQuery.sizeOf(context).width < OipTokens.mobile) {
                  mobilePane = _MobilePane.inspector;
                } else {
                  tabletInspector = true;
                  tabletExplorer = false;
                }
              }),
            ),
            WorkspaceLayoutAction(
                controller: widget.controller,
                workspace: WorkspaceId.diagnostics),
            IconButton(
              tooltip: 'Diagnosedaten aktualisieren',
              onPressed: loadingEvents ? null : _loadEvents,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (MediaQuery.sizeOf(context).width >= OipTokens.mobile)
          Wrap(spacing: 7, runSpacing: 5, children: [
            apiConnectionStatus(context, widget.controller),
            StatusPill(
                widget.controller.infrastructure.ready
                    ? 'KONTEXT · ${widget.controller.infrastructure.selectedBreadcrumb}'
                    : 'SOURCE · ${snapshot.primarySourceId ?? 'NICHT GELIEFERT'}',
                color: OipTokens.cyan),
            const StatusPill('READ-ONLY · SESSION-INVESTIGATION',
                color: OipTokens.violet),
            const StatusPill('GETRENNT VON DER DIAGNOSE',
                color: OipTokens.blue),
          ]),
        const SizedBox(height: OipTokens.s3),
        if (snapshot.system.demoControls) _scenarioControl(snapshot),
        if (eventsError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InlineNotice(
              'Collection-Ereignisse nicht verfügbar',
              '${apiErrorMessage(eventsError!, 'Collection-Ereignisse konnten nicht geladen werden.')} Angezeigte Events sind der letzte erfolgreiche, jetzt stale Stand.',
              icon: Icons.cloud_off_outlined,
              color: OipTokens.red,
            ),
          ),
        const SizedBox(height: OipTokens.s3),
        _modeTabs(),
        const SizedBox(height: OipTokens.s3),
        LayoutBuilder(builder: (context, box) {
          final width = MediaQuery.sizeOf(context).width;
          if (width < OipTokens.mobile) {
            return Column(children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_MobilePane>(
                  style: const ButtonStyle(
                    padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 4)),
                    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11)),
                  ),
                  segments: const [
                    ButtonSegment(
                        value: _MobilePane.explorer,
                        icon: Icon(Icons.list_alt, size: 16),
                        label: Text('Explorer')),
                    ButtonSegment(
                        value: _MobilePane.workspace,
                        icon: Icon(Icons.timeline, size: 16),
                        label: Text('Timeline')),
                    ButtonSegment(
                        value: _MobilePane.inspector,
                        icon: Icon(Icons.info_outline, size: 16),
                        label: Text('Inspector')),
                  ],
                  selected: {mobilePane},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) =>
                      setState(() => mobilePane = value.single),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                  height: 620,
                  child: switch (mobilePane) {
                    _MobilePane.explorer => _explorer(filtered),
                    _MobilePane.workspace =>
                      _workspace(filtered, current, currentSource),
                    _MobilePane.inspector => _inspector(current, currentSource),
                  }),
            ]);
          }
          if (box.maxWidth < 1120) {
            return Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton.icon(
                    onPressed: () => setState(() {
                          tabletExplorer = !tabletExplorer;
                          if (tabletExplorer) tabletInspector = false;
                        }),
                    icon: const Icon(Icons.list_alt, size: 16),
                    label: Text(tabletExplorer
                        ? 'Explorer schließen'
                        : 'Explorer öffnen')),
                const SizedBox(width: 6),
                TextButton.icon(
                    onPressed: () => setState(() {
                          tabletInspector = !tabletInspector;
                          if (tabletInspector) tabletExplorer = false;
                        }),
                    icon: const Icon(Icons.info_outline, size: 16),
                    label: Text(tabletInspector
                        ? 'Inspector schließen'
                        : 'Inspector öffnen')),
              ]),
              SizedBox(
                  height: 650,
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (tabletExplorer) ...[
                          SizedBox(
                              width: math.min(300, box.maxWidth * .42),
                              child: _explorer(filtered)),
                          const SizedBox(width: 10)
                        ],
                        Expanded(
                            child:
                                _workspace(filtered, current, currentSource)),
                        if (tabletInspector) ...[
                          const SizedBox(width: 10),
                          SizedBox(
                              width: math.min(330, box.maxWidth * .45),
                              child: _inspector(current, currentSource))
                        ],
                      ])),
            ]);
          }
          return SizedBox(
              height: 680,
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 278, child: _explorer(filtered)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _workspace(filtered, current, currentSource)),
                    if (widget.controller.inspectorVisible(
                        WorkspaceId.diagnostics, current != null)) ...[
                      const SizedBox(width: 12),
                      SizedBox(
                          width: 326,
                          child: Focus(
                              focusNode: inspectorFocus,
                              child: _inspector(current, currentSource))),
                    ],
                  ]));
        }),
        if (mode != _DiagnosticsMode.incidents &&
            widget.controller.workspaces
                .layout(WorkspaceId.diagnostics)
                .expertWorkspace) ...[
          const SizedBox(height: OipTokens.s4),
          Text('INVESTIGATION DETAILS · INCIDENTS / DEMO-BEFUNDE',
              style:
                  WorkstationTokens.eyebrow(context, color: OipTokens.violet)),
          const SizedBox(height: 6),
          DiagnosticsIncidentsWorkspace(
              snapshot: snapshot,
              controller: widget.controller,
              embedded: true),
        ],
        if (widget.controller.managed) ...[
          const SizedBox(height: OipTokens.s4),
          _persistedEvidence(context),
        ],
      ]),
    );
  }

  /// The state of the persisted diagnosis history is the answer of the Core,
  /// never an assumption of the client.
  String _diagnosisTitle() => switch (diagnosisHistoryStatus) {
        'demo_only' => 'Diagnosehistorie: nur Demo',
        'not_implemented' => 'Diagnosehistorie: nicht implementiert',
        final status => 'Diagnosehistorie: $status',
      };

  String _diagnosisMessage() => switch (diagnosisHistoryStatus) {
        'demo_only' =>
          'Noch kein persistierter Diagnoselauf. Die aktuellen Demo-Befunde werden vom Rust-Backend erzeugt.',
        'not_implemented' =>
          'Eine persistierte Diagnoseausführung ist nicht implementiert. Die dokumentierten Lücken und Gesundheitsverläufe sind der persistierte Stand des Core; sie sind keine gespeicherte Diagnose und keine Ursache.',
        final status => 'Der Core nennt den Stand der Diagnosehistorie: $status.',
      };

  Widget _persistedEvidence(BuildContext context) {
    final gaps = documentedGaps;
    final health = healthTransitions;
    return WorkstationPanel(
      accent: OipTokens.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('PERSISTIERTE EVIDENZ · CORE-SPEICHER',
              style: WorkstationTokens.eyebrow(context, color: OipTokens.cyan)),
          const SizedBox(height: 6),
          InlineNotice(
            _diagnosisTitle(),
            _diagnosisMessage(),
            icon: Icons.history_edu_outlined,
            color: OipTokens.statusColor(context, 'degraded'),
          ),
          const SizedBox(height: OipTokens.s3),
          // A failed continuation keeps the evidence that is already loaded
          // and offers a fresh authorized query. It never hides the proof it
          // already holds.
          if (evidenceError != null)
            StateMessage(
              'Persistierte Evidenz nicht verfügbar',
              apiErrorMessage(
                evidenceError!,
                'Die persistierte Evidenz konnte nicht geladen werden.',
              ),
              compact: true,
              action: TextButton(
                onPressed: evidenceBusy ? null : _loadEvidence,
                child: const Text('Erneut laden'),
              ),
            ),
          if (gaps != null && health != null)
            _evidence(context, gaps, health)
          else if (evidenceError == null)
            const Padding(
              padding: EdgeInsets.all(OipTokens.s4),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _evidence(
      BuildContext context, DiagnosticPage gaps, DiagnosticPage health) {
    final notes = <String>[...gaps.missingEvidence, ...health.missingEvidence];
    if (gaps.gaps.isEmpty && health.transitions.isEmpty) {
      return const InlineNotice(
        'Keine dokumentierte Lücke und kein Gesundheitsverlauf',
        'Das Core hat nichts dokumentiert. Das ist kein Nachweis einer lückenlosen Überwachung.',
        icon: Icons.rule_outlined,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final gap in gaps.gaps)
          Padding(
            padding: const EdgeInsets.only(bottom: OipTokens.s2),
            child: FactGrid(children: [
              Fact('Dokumentierte Lücke · ${gap.source}',
                  '${timestamp(gap.documentedStartMs)} → '
                  '${timestamp(gap.documentedEndMs)}'
                  '${gap.durationMs == null ? ' · unbekannter Markerabstand' : ' · Markerabstand: ${gap.durationMs} ms, keine gemessene Ausfalldauer'}'),
              Fact('Grund', '${gap.reason} · Herkunft: ${gap.origin}'),
            ]),
          ),
        for (final transition in health.transitions)
          Padding(
            padding: const EdgeInsets.only(bottom: OipTokens.s2),
            child: FactGrid(children: [
              Fact('Gesundheitsverlauf · ${transition.source}',
                  timestamp(transition.atMs)),
              Fact(
                  'Zustand',
                  '${transition.previous == null ? 'Unbekannt' : _healthLabel(transition.previous!)} → '
                  '${transition.current == null ? 'Unbekannt' : _healthLabel(transition.current!)}'),
              Fact('Provenienz', transition.provenance),
            ]),
          ),
        _continuation(gaps, 'Lücken',
            () => _loadEvidence(moreGaps: true)),
        _continuation(health, 'Gesundheitsverlauf',
            () => _loadEvidence(moreHealth: true)),
        if (gaps.timeSemantics.isNotEmpty || health.timeSemantics.isNotEmpty)
          ExpansionTile(
            title: const Text('Zeit- und Herkunftssemantik'),
            children: [
              Text(gaps.timeSemantics),
              Text(health.timeSemantics),
              const Text('Markerabstände sind keine gemessenen Ausfalldauern. '
                  'Historische Zustände beweisen keine aktuelle Erreichbarkeit.'),
            ],
          ),
        if (notes.isNotEmpty)
          Text('Grenzen dieser Evidenz: ${notes.join(' ')}',
              style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  /// The continuation of an authorized diagnostic page.
  ///
  /// A truncated answer without a cursor is explicitly incomplete; it never
  /// implies that the evidence was read completely.
  Widget _continuation(DiagnosticPage page, String label, VoidCallback load) {
    if (!page.truncated) return const SizedBox.shrink();
    if (page.nextCursor == null) {
      return Text('$label: Antwort gekürzt; keine Fortsetzung verfügbar.');
    }
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: evidenceBusy ? null : load,
        child: Text('$label: weitere Einträge laden'),
      ),
    );
  }

  String _healthLabel(DiagnosticHealthState state) =>
      '${known(state.connection)} · ${known(state.reachability)} · '
      '${known(state.service)} · ${known(state.freshness)} · ${known(state.validity)}';

  Widget _scenarioControl(Snapshot snapshot) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      decoration: BoxDecoration(
          color: WorkstationTokens.well(context),
          border: Border.all(color: WorkstationTokens.hairline(context)),
          borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            MediaQuery.sizeOf(context).width < OipTokens.mobile
                ? 'DEMO · BESTEHENDE API · GETRENNT'
                : 'DEMO-SZENARIEN · BESTEHENDE AUTORISIERTE SIMULATORSTEUERUNG · GETRENNT VON ECHTEN COLLECTION-EVENTS',
            style: WorkstationTokens.eyebrow(context, color: OipTokens.yellow)),
        const SizedBox(height: 5),
        Wrap(
            spacing: 6,
            runSpacing: 6,
            children: scenarios.entries
                .map((entry) => ChoiceChip(
                      key: Key('scenario-${entry.key}'),
                      label: Text(entry.value),
                      labelStyle: const TextStyle(fontSize: 11),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      showCheckmark: false,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      selected: snapshot.system.scenario == entry.key,
                      onSelected: !snapshot.system.demoControls ||
                              widget.controller.scenarioBusy
                          ? null
                          : (_) => _setScenario(entry.key),
                    ))
                .toList()),
      ]),
    );
  }

  void _setMode(_DiagnosticsMode value) {
    setState(() {
      mode = value;
      if (value == _DiagnosticsMode.timeline) showTimeline = true;
      if (MediaQuery.sizeOf(context).width < OipTokens.mobile) {
        mobilePane = _MobilePane.workspace;
      }
    });
    widget.controller.setWorkspaceView(WorkspaceId.diagnostics, value.name);
  }

  Widget _modeTabs() {
    Widget tab(_DiagnosticsMode value, String label, IconData icon) =>
        ChoiceChip(
          key: Key('diagnostics-mode-${value.name}'),
          avatar: Icon(icon, size: 15),
          label: Text(label),
          selected: mode == value,
          onSelected: (_) => _setMode(value),
        );
    return Wrap(spacing: 6, runSpacing: 6, children: [
      tab(_DiagnosticsMode.events, 'Events', Icons.list_alt_outlined),
      tab(_DiagnosticsMode.incidents, 'Incidents', Icons.fact_check_outlined),
      tab(_DiagnosticsMode.timeline, 'Timeline', Icons.timeline_outlined),
      tab(_DiagnosticsMode.health, 'Collection Health',
          Icons.monitor_heart_outlined),
      tab(_DiagnosticsMode.compare, 'Compare ${compareKeys.length}/4',
          Icons.compare_arrows_outlined),
    ]);
  }

  Widget _explorer(List<DiagnosticEvent> filtered) => DiagnosticsEventExplorer(
        allEvents: allEvents,
        events: filtered,
        recent: recent,
        pinned: pinned,
        compared: compareKeys.toSet(),
        selectedKey: selectedKey,
        sourceFilter: sourceFilter,
        typeFilter: typeFilter,
        query: query,
        sort: sort,
        grouping: grouping,
        timeWindow: timeWindow,
        showFilters: showFilters,
        stale: eventsError != null,
        searchController: searchController,
        searchFocus: searchFocus,
        listFocus: listFocus,
        onQuery: (value) => setState(() => query = value),
        onClearSearch: () => setState(() {
          query = '';
          searchController.clear();
        }),
        onToggleFilters: () {
          setState(() => showFilters = !showFilters);
          widget.controller
              .setAdvancedFilters(WorkspaceId.diagnostics, showFilters);
        },
        onSource: (value) => setState(() => sourceFilter = value),
        onType: (value) => setState(() => typeFilter = value),
        onOrganization: (value) => setState(() => organizationFilter = value),
        onInfrastructure: (value) =>
            setState(() => infrastructureFilter = value),
        onSite: (value) => setState(() => siteFilter = value),
        organizationFilter: organizationFilter,
        infrastructureFilter: infrastructureFilter,
        siteFilter: siteFilter,
        infrastructure: widget.controller.infrastructure,
        onSort: (value) => setState(() => sort = value),
        onGrouping: (value) => setState(() => grouping = value),
        onTimeWindow: (value) => setState(() => timeWindow = value),
        onSelect: _select,
        onPin: _togglePin,
        onCompare: _toggleCompare,
        onKeyEvent: _listKey,
        moreAvailable: eventsTruncated && eventsNextCursor != null,
        missingEvidence: eventsMissingEvidence,
        onLoadMore: () => _loadEvents(append: true),
      );

  Widget _inspector(DiagnosticEvent? current, SourceInfo? source) =>
      AdaptiveInspector(
        controller: widget.controller,
        workspace: WorkspaceId.diagnostics,
        label: 'Event Details & Evidence',
        hasSelection: current != null,
        child: DiagnosticsEvidenceInspector(
          selected: current,
          allEvents: allEvents,
          source: source,
          pinned: current != null && pinned.contains(current.key),
          compared: current != null && compareKeys.contains(current.key),
          onPin: () => _togglePin(current!),
          onCompare: () => _toggleCompare(current!),
          onFocusTimeline: _focusSelectedTimeline,
          onSelect: _select,
          infrastructure: widget.controller.infrastructure,
        ),
      );

  Widget _workspace(List<DiagnosticEvent> filtered, DiagnosticEvent? current,
      SourceInfo? source) {
    if (mode == _DiagnosticsMode.timeline && !showTimeline) {
      return WorkstationPanel(
        accent: OipTokens.violet,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text('Evidence Timeline',
                    style: Theme.of(context).textTheme.titleMedium)),
            TextButton.icon(
                onPressed: () => setState(() => showTimeline = true),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Spuren zeigen'))
          ]),
          const Expanded(
              child: Center(
                  child: InlineNotice('Klassische Ereignisliste aktiv',
                      'Alle Collection-Ereignisse bleiben im Event Explorer vollständig bedienbar.',
                      icon: Icons.list_alt_outlined))),
        ]),
      );
    }
    return switch (mode) {
      _DiagnosticsMode.events => DiagnosticsEventsOverview(
          all: allEvents,
          filtered: filtered,
          transportLive: widget.controller.connection == 'live'),
      _DiagnosticsMode.incidents => DiagnosticsIncidentsWorkspace(
          snapshot: widget.controller.snapshot!, controller: widget.controller),
      _DiagnosticsMode.timeline => DiagnosticsEventTimeline(
          events: filtered,
          selectedKey: selectedKey,
          range: _range,
          onZoomIn: () => _zoomTimeline(2),
          onZoomOut: () => _zoomTimeline(.5),
          onFit: _fitTimeline,
          onPanLeft: () => _panTimeline(-_range.spanMs ~/ 2),
          onPanRight: () => _panTimeline(_range.spanMs ~/ 2),
          onPanDelta: (delta) => _panTimeline(delta.round()),
          onHide: () => setState(() {
            showTimeline = false;
            selectedKey = null;
          }),
          onSelected: _select,
        ),
      _DiagnosticsMode.health => DiagnosticsCollectionHealth(
          sources: sources,
          sourcesError: sourcesError,
          events: allEvents,
          transportLive: widget.controller.connection == 'live',
          onSelect: _select),
      _DiagnosticsMode.compare => DiagnosticsCompareWorkspace(
          events: compared,
          onRemove: _toggleCompare,
          onSelect: _select,
          onClear: () => setState(() {
                compareKeys.clear();
                mode = _DiagnosticsMode.events;
              })),
    };
  }
}

bool _sameEventWindow(
    List<DiagnosticEvent> previous, List<DiagnosticEvent> next) {
  if (previous.length != next.length) return false;
  for (var index = 0; index < previous.length; index++) {
    final a = previous[index];
    final b = next[index];
    if (a.key != b.key || a.deliveryCount != b.deliveryCount) return false;
    final x = a.event;
    final y = b.event;
    if (x.kind != y.kind ||
        x.atMs != y.atMs ||
        x.reason != y.reason ||
        x.gapStartedMs != y.gapStartedMs ||
        x.gapEndedMs != y.gapEndedMs ||
        x.dropped != y.dropped) {
      return false;
    }
  }
  return true;
}
