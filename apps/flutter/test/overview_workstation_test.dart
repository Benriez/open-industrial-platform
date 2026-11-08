import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/design_system/theme.dart';
import 'package:oip_dashboard/features/overview.dart';
import 'package:oip_dashboard/features/overview/telemetry_chart.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'support.dart';

Json overviewFixture() {
  final data = fixture();
  data['sources'] = [
    {
      'id': 'oip-local-simulation-v1',
      'name': 'Local OPC-UA Simulation',
      'entity_id': 'M-01',
      'simulated': true,
      'reachability': 'reachable',
      'connection': 'connected',
      'service': 'healthy',
      'freshness': 'fresh',
      'validity': 'valid',
      'last_received_ms': 1800000000000,
      'last_error': null,
    }
  ];
  data['records'] = [
    {
      'context': {'data_source_id': 'oip-local-simulation-v1'},
      'sequence': 7,
      'event': {
        'Reconnected': {
          'at': 1800000002500,
          'gap': {'started_at': 1800000000000, 'ended_at': 1800000002500}
        }
      }
    },
    {
      'context': {'data_source_id': 'oip-local-simulation-v1'},
      'sequence': 8,
      'event': {
        'SubscriptionError': {'at': 1800000003000, 'reason': 'fixture'}
      }
    }
  ];
  return data;
}

Json addSecondSource(Json data) {
  final pressure = observation(value: 320.5);
  pressure['entity_id'] = 'M-02';
  pressure['metric_id'] = 'pressure';
  pressure['unit'] = 'kilo_pascal';
  pressure['data_source_id'] = 'source-b';
  (data['metrics'] as List).add(pressure);
  (data['sources'] as List).add({
    'id': 'source-b',
    'name': 'Fixture Source B',
    'entity_id': 'M-02',
    'simulated': true,
    'reachability': 'unknown',
    'connection': 'connected',
    'service': 'unknown',
    'freshness': 'fresh',
    'validity': 'valid',
    'last_received_ms': 1800000003000,
    'last_error': null,
  });
  (data['devices'] as List).add({
    'id': 'M-02',
    'is_faulted': false,
    'data_source_id': 'source-b',
    'name': 'Fixture Device B',
    'kind': 'Sensor',
    'location': 'Fixture',
    'connection': 'OPC UA',
    'simulated': true,
    'health': {
      'reachability': 'unknown',
      'vpn_transport': 'not_applicable',
      'agent_availability': 'unknown',
      'service_health': 'unknown',
      'telemetry_freshness': 'fresh'
    }
  });
  (data['records'] as List).add({
    'id': 'event-b-1',
    'context': {'data_source_id': 'source-b', 'origin_class': 'fixture'},
    'sequence': 1,
    'event': {
      'ConnectionLost': {'at': 1800000004000, 'reason': 'fixture disconnect'}
    }
  });
  return data;
}

OipController overviewController([Json? data]) => OipController(FakeApi())
  ..snapshot = Snapshot.fromJson(data ?? overviewFixture())
  ..connection = 'live'
  ..workspaces.setExpertWorkspace(WorkspaceId.overview, true)
  ..workspaces.setInspectorOpen(WorkspaceId.overview, true);

Future<void> revealExplorer(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
          of: find.byKey(const Key('overview-infrastructure-explorer')),
          matching: find.byType(Scrollable))
      .last;
  await tester.scrollUntilVisible(finder, 70, scrollable: scrollable);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> revealActivity(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
          of: find.byKey(const Key('overview-activity-coverage-workspace')),
          matching: find.byType(Scrollable))
      .last;
  await tester.scrollUntilVisible(finder, 60, scrollable: scrollable);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> pumpOverview(WidgetTester tester, OipController controller,
    {Size size = const Size(1440, 1000),
    OipThemeVariant variant = OipThemeVariant.spectrum,
    void Function(int)? onNavigate}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: OipTokens.theme(Brightness.light),
    darkTheme: OipTokens.theme(Brightness.dark,
        spectrum: variant != OipThemeVariant.graphite),
    themeMode:
        variant == OipThemeVariant.daylight ? ThemeMode.light : ThemeMode.dark,
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) =>
              OverviewPage(controller, onNavigate ?? (_) {}),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Operational status and persisted count retain their exact scope',
      (tester) async {
    final controller = overviewController();
    await pumpOverview(tester, controller);
    expect(find.text('1 / 1 CONNECTED'), findsOneWidget);
    expect(find.text('2 REGISTERED'), findsOneWidget);
    expect(find.text('NONE IN CURRENT DATA'), findsOneWidget);
    await tester.tap(find.byKey(const Key('overview-workspace-tab-coverage')));
    await tester.pumpAndSettle();
    expect(find.textContaining('globaler Core/SQLite-Bestand'), findsOneWidget);
    expect(find.textContaining('kein Zeitraum- oder Tenant-Aggregat'),
        findsOneWidget);
    expect(find.text('Erreichbare Geräte'), findsNothing);
    expect(find.textContaining('kein aktiver Probe'), findsWidgets);
    expect(find.textContaining('UNAVAILABLE'), findsWidgets);
    expect(find.text('0 %'), findsNothing);
  });

  testWidgets('Telemetry selection remains source and signal scoped',
      (tester) async {
    final data = overviewFixture();
    final pressure = observation(value: 320.5);
    pressure['metric_id'] = 'pressure';
    pressure['unit'] = 'kilo_pascal';
    pressure['data_source_id'] = 'source-b';
    (data['metrics'] as List).add(pressure);
    final controller = overviewController(data);
    await pumpOverview(tester, controller);
    controller.selectTelemetry(observationKey(Observation.fromJson(pressure)));
    await tester.pump();
    expect(find.text('320.5 kPa'), findsOneWidget);
    expect(controller.selectedTelemetry?.sourceId, 'source-b');
    expect(controller.history.single.sourceId, 'source-b');
    expect(controller.history.single.metricId, 'pressure');
    expect(find.textContaining('1/60 SESSION'), findsOneWidget);
  });

  testWidgets('Chart sample selection exposes value, quality and both clocks',
      (tester) async {
    final controller = overviewController();
    final observationValue = controller.snapshot!.metrics.single;
    controller.selectTelemetry(observationKey(observationValue));
    await pumpOverview(tester, controller);
    await tester.ensureVisible(find.byKey(const Key('overview-sample-next')));
    await tester.tap(find.byKey(const Key('overview-sample-next')));
    await tester.pump();
    expect(find.byKey(const Key('overview-sample-detail')), findsOneWidget);
    expect(find.textContaining('61.2 °C'), findsWidgets);
    expect(find.textContaining('Simulator-Quellzeit'), findsWidgets);
    expect(find.textContaining('2023-11-14 22:13:20.000 UTC'), findsWidgets);
    await tester.tap(find.byKey(const Key('overview-sample-previous')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const Key('overview-sample-next'))).height,
        greaterThanOrEqualTo(44));
  });

  testWidgets('No telemetry produces an honest missing-data state',
      (tester) async {
    final data = overviewFixture()..['metrics'] = <dynamic>[];
    final controller = overviewController(data);
    await pumpOverview(tester, controller);
    expect(find.text('Kein Live-Signal verfügbar'), findsOneWidget);
    expect(find.textContaining('Keine Ersatzwerte'), findsOneWidget);
    expect(find.text('0.0 °C'), findsNothing);
  });

  testWidgets('Attention and recent activity open evidence then Diagnostics',
      (tester) async {
    final controller = overviewController();
    var page = 0;
    await pumpOverview(tester, controller, onNavigate: (value) => page = value);
    expect(find.textContaining('SubscriptionError'), findsWidgets);
    final event = find.byKey(const Key(
        'overview-event-oip-local-simulation-v1-SubscriptionError-8'));
    await tester.ensureVisible(event);
    await tester.pumpAndSettle();
    await tester.tap(event);
    await tester.pumpAndSettle();
    expect(find.text('AVAILABLE EVIDENCE · REASON'), findsOneWidget);
    expect(find.textContaining('kein ID-Router-Kontext'), findsOneWidget);
    await tester.ensureVisible(
        find.byKey(const Key('overview-inspector-open-diagnostics')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('overview-inspector-open-diagnostics')));
    await tester.pumpAndSettle();
    expect(page, 4);
  });

  testWidgets('Same event kind and sequence from two sources never collide',
      (tester) async {
    final data = overviewFixture();
    final first = (data['records'] as List).first as Json;
    (data['records'] as List).add(<String, Object>{
      ...first.map((key, value) => MapEntry(key, value as Object)),
      'context': {'data_source_id': 'source-b'},
    });
    final controller = overviewController(data);
    await pumpOverview(tester, controller);
    await tester.tap(find.byKey(const Key('overview-inspector-clear')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(
            const Key('overview-event-oip-local-simulation-v1-Reconnected-7')),
        findsOneWidget);
    await revealActivity(
        tester, find.byKey(const Key('overview-event-source-b-Reconnected-7')));
    expect(find.byKey(const Key('overview-event-source-b-Reconnected-7')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Event filter only uses delivered event kinds', (tester) async {
    final controller = overviewController();
    await pumpOverview(tester, controller);
    await tester.ensureVisible(find.byKey(const Key('overview-event-filter')));
    await tester.tap(find.byKey(const Key('overview-event-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reconnected').last);
    await tester.pumpAndSettle();
    expect(
        find.byKey(
            const Key('overview-event-oip-local-simulation-v1-Reconnected-7')),
        findsOneWidget);
    expect(
        find.byKey(const Key(
            'overview-event-oip-local-simulation-v1-SubscriptionError-8')),
        findsNothing);
  });

  test('Documented gaps break chart continuity only across actual bounds', () {
    final first = Observation.fromJson(observation());
    final secondJson = observation(value: 62);
    (secondJson['timestamps'] as Json)['source'] = 1700000002000;
    final second = Observation.fromJson(secondJson);
    final gap = CollectionEvent.fromJson({
      'Reconnected': {
        'gap': {'started_at': 1699999999000, 'ended_at': 1700000001000}
      }
    });
    expect(crossesDocumentedGap(first, second, [gap]), isTrue);
    expect(crossesDocumentedGap(first, second, const []), isFalse);
  });

  testWidgets('Device telemetry groups are disjoint and registry based',
      (tester) async {
    final controller = overviewController();
    await pumpOverview(tester, controller);
    expect(find.textContaining('FRESH OBSERVED 1'), findsOneWidget);
    expect(find.textContaining('NO TELEMETRY 1'), findsOneWidget);
    expect(find.textContaining('STALE / UNKNOWN 0'), findsOneWidget);
  });

  for (final width in [
    320.0,
    375.0,
    390.0,
    768.0,
    834.0,
    1024.0,
    1440.0,
    1920.0
  ]) {
    testWidgets('Overview remains usable at $width px', (tester) async {
      final controller = overviewController();
      await pumpOverview(tester, controller, size: Size(width, 1000));
      expect(
          find.text('OPERATIONAL FOCUS · SESSION TELEMETRY'), findsOneWidget);
      await tester.ensureVisible(
          find.byKey(const Key('overview-workspace-tab-coverage')));
      await tester
          .tap(find.byKey(const Key('overview-workspace-tab-coverage')));
      await tester.pumpAndSettle();
      expect(find.textContaining('DATA COVERAGE & TRUST'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final theme in OipThemeVariant.values) {
    testWidgets('Overview preserves semantics in ${theme.name}',
        (tester) async {
      final controller = overviewController();
      await pumpOverview(tester, controller, variant: theme);
      expect(find.text('OPERATIONAL ATTENTION'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('Primary SSE disconnect and recovery update SourceHealth honestly',
      () async {
    final api = FakeApi()..data = overviewFixture();
    final controller = OipController(api);
    final running = controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.operationalSources.single.connection, 'connected');
    (api.data['system'] as Json)['opcua_status'] = 'disconnected';
    ((api.data['metrics'] as List).single as Json)['freshness'] = 'stale';
    api.emit();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.operationalSources.single.connection, 'disconnected');
    expect(controller.operationalSources.single.freshness, 'stale');
    (api.data['system'] as Json)['opcua_status'] = 'connected';
    ((api.data['metrics'] as List).single as Json)['freshness'] = 'fresh';
    api.emit();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.operationalSources.single.connection, 'connected');
    expect(controller.operationalSources.single.freshness, 'fresh');
    controller.dispose();
    await running;
  });

  test('SSE retains bootstrap context and scope changes invalidate it',
      () async {
    final api = FakeApi()..data = overviewFixture();
    final controller = OipController(api);
    final running = controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.operationalSources, hasLength(1));
    expect(controller.operationalEvents, hasLength(2));
    api.data = fixture();
    api.emit();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.operationalSources, hasLength(1));
    expect(controller.operationalEvents, hasLength(2));
    api.data['system']['primary_source_id'] = 'source-b';
    ((api.data['metrics'] as List).single as Json)['data_source_id'] =
        'source-b';
    api.emit();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.operationalSources, isEmpty);
    expect(controller.operationalEvents, isEmpty);
    expect(controller.selectedTelemetry?.sourceId, 'source-b');
    controller.dispose();
    await running;
  });

  testWidgets('Mixed freshness never becomes a globally fresh claim',
      (tester) async {
    final data = overviewFixture();
    final stale = observation(value: 10);
    stale['metric_id'] = 'stale-signal';
    stale['freshness'] = 'stale';
    (data['metrics'] as List).add(stale);
    final controller = overviewController(data);
    await pumpOverview(tester, controller);
    expect(find.text('MIXED'), findsOneWidget);
  });

  testWidgets('Source investigation synchronizes focus, inspector and activity',
      (tester) async {
    final controller = overviewController(addSecondSource(overviewFixture()));
    var page = 0;
    await pumpOverview(tester, controller, onNavigate: (value) => page = value);
    await revealExplorer(
        tester, find.byKey(const Key('overview-explorer-source-source-b')));
    await tester
        .tap(find.byKey(const Key('overview-explorer-source-source-b')));
    await tester.pumpAndSettle();
    expect(controller.selectedTelemetry?.sourceId, 'source-b');
    expect(controller.selectedTelemetry?.metricId, 'pressure');
    expect(find.text('320.5 kPa'), findsOneWidget);
    expect(find.text('Fixture Source B'), findsWidgets);
    expect(find.text('AVAILABLE SIGNALS'), findsOneWidget);
    expect(find.text('1 im aktuellen Snapshot'), findsOneWidget);
    expect(find.textContaining('Source source-b'), findsOneWidget);
    expect(find.byKey(const Key('overview-event-source-b-ConnectionLost-1')),
        findsOneWidget);
    expect(
        find.byKey(const Key(
            'overview-event-oip-local-simulation-v1-SubscriptionError-8')),
        findsNothing);
    await tester
        .ensureVisible(find.byKey(const Key('overview-inspector-open-opcua')));
    await tester.tap(find.byKey(const Key('overview-inspector-open-opcua')));
    await tester.pumpAndSettle();
    expect(page, 3);
  });

  testWidgets(
      'Device without telemetry clears prior chart and opens real detail',
      (tester) async {
    final controller = overviewController();
    await pumpOverview(tester, controller);
    await revealExplorer(
        tester, find.byKey(const Key('overview-explorer-device-evo')));
    await tester.tap(find.byKey(const Key('overview-explorer-device-evo')));
    await tester.pumpAndSettle();
    expect(controller.selectedTelemetry, isNull);
    expect(controller.history, isEmpty);
    expect(find.text('Kein Live-Signal verfügbar'), findsOneWidget);
    expect(find.textContaining('Reachability'), findsWidgets);
    expect(find.textContaining('kein aktiver Probe'), findsWidgets);
    expect(find.text('0.0 °C'), findsNothing);
    await tester
        .ensureVisible(find.byKey(const Key('overview-inspector-open-device')));
    await tester.tap(find.byKey(const Key('overview-inspector-open-device')));
    await tester.pumpAndSettle();
    expect(find.text('AMD EVO-X2'), findsWidgets);
  });

  testWidgets(
      'Event selection exposes actual ID, evidence and wall-clock context',
      (tester) async {
    final controller = overviewController(addSecondSource(overviewFixture()));
    await pumpOverview(tester, controller);
    await revealExplorer(
        tester, find.byKey(const Key('overview-explorer-source-source-b')));
    await tester
        .tap(find.byKey(const Key('overview-explorer-source-source-b')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('overview-event-source-b-ConnectionLost-1')));
    await tester.pumpAndSettle();
    expect(find.text('event-b-1'), findsWidgets);
    expect(find.text('EVENT TIME · CONTROL/WALL CLOCK'), findsOneWidget);
    expect(find.text('fixture disconnect'), findsOneWidget);
    expect(find.textContaining('fixture'), findsWidgets);
    expect(find.textContaining('Ursache und globale Severity nicht geliefert'),
        findsOneWidget);
  });

  testWidgets('Source without telemetry never retains another source value',
      (tester) async {
    final data = addSecondSource(overviewFixture());
    (data['metrics'] as List).removeLast();
    final controller = overviewController(data);
    await pumpOverview(tester, controller);
    await revealExplorer(
        tester, find.byKey(const Key('overview-explorer-source-source-b')));
    await tester
        .tap(find.byKey(const Key('overview-explorer-source-source-b')));
    await tester.pumpAndSettle();
    expect(controller.selectedTelemetry, isNull);
    expect(find.text('Kein Live-Signal verfügbar'), findsOneWidget);
    expect(find.text('61.2 °C'), findsNothing);
    expect(find.byKey(const Key('overview-open-opcua')), findsOneWidget);
  });

  testWidgets(
      'Attention excludes reconnect duplicates but activity retains them',
      (tester) async {
    final controller = overviewController();
    await pumpOverview(tester, controller);
    expect(
        find.byKey(const Key('overview-attention-Reconnected')), findsNothing);
    expect(
        find.byKey(
            const Key('overview-event-oip-local-simulation-v1-Reconnected-7')),
        findsOneWidget);
  });

  testWidgets('Chart zoom and reset change only the available sample window',
      (tester) async {
    final controller = overviewController();
    final first = controller.snapshot!.metrics.single;
    controller.history
      ..clear()
      ..add(first);
    for (var index = 1; index < 4; index++) {
      final json = observation(value: 61.2 + index);
      (json['timestamps'] as Json)['source'] = 1700000000000 + index * 1000;
      controller.history.add(Observation.fromJson(json));
    }
    await pumpOverview(tester, controller);
    await tester.ensureVisible(find.byKey(const Key('overview-chart-zoom-in')));
    await tester.tap(find.byKey(const Key('overview-chart-zoom-in')));
    await tester.pump();
    expect(find.textContaining('2/4 SAMPLES'), findsOneWidget);
    await tester.tap(find.byKey(const Key('overview-chart-reset')));
    await tester.pump();
    expect(find.textContaining('4/4 SAMPLES'), findsOneWidget);
  });

  testWidgets(
      'Explorer search, telemetry filter and arrow selection stay linked',
      (tester) async {
    final controller = overviewController(addSecondSource(overviewFixture()));
    await pumpOverview(tester, controller);
    await tester.enterText(
        find.byKey(const Key('overview-explorer-search')), 'Fixture Device B');
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('overview-explorer-device-M-02')), findsOneWidget);
    expect(find.byKey(const Key('overview-explorer-device-evo')), findsNothing);
    await tester.tap(find.byKey(const Key('overview-explorer-search')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.tap(find.byKey(const Key('overview-explorer-list')));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.selectedTelemetry?.sourceId, isNotNull);
    await tester.tap(find.byKey(const Key('overview-explorer-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Frisch beobachtet').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Empty inspector and missing diagnostics stay compact and honest',
      (tester) async {
    final data = overviewFixture()..['records'] = <dynamic>[];
    final controller = overviewController(data);
    await pumpOverview(tester, controller);
    await tester.tap(find.byKey(const Key('overview-inspector-clear')));
    await tester.pumpAndSettle();
    controller.setInspectorOpen(WorkspaceId.overview, false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overview-adaptive-inspector')), findsNothing);
    await tester.tap(find.byKey(const Key('overview-inspector-open')));
    await tester.pumpAndSettle();
    expect(find.text('Quelle, Gerät oder Ereignis auswählen.'), findsOneWidget);
    expect(find.text('Keine Events im ausgewählten aktuellen Datenumfang.'),
        findsOneWidget);
  });

  testWidgets('F6 and Enter inspect a sample without pointer input',
      (tester) async {
    final controller = overviewController();
    controller
        .selectTelemetry(observationKey(controller.snapshot!.metrics.single));
    await pumpOverview(tester, controller);
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.pump();
    expect(find.byKey(const Key('overview-sample-next')).evaluate().isNotEmpty,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(const Key('overview-sample-detail')), findsOneWidget);
  });

  testWidgets('Shell deep dives use only existing module destinations',
      (tester) async {
    final api = FakeApi();
    final controller = OipController(api)
      ..snapshot = Snapshot.fromJson(overviewFixture())
      ..connection = 'live'
      ..workspaces.setExpertWorkspace(WorkspaceId.overview, true)
      ..workspaces.setInspectorOpen(WorkspaceId.overview, true);
    await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('overview-open-opcua')));
    await tester.pumpAndSettle();
    expect(find.text('Namespace 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
