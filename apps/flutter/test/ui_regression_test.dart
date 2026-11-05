import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/design_system/theme.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/services/api.dart';
import 'support.dart';

void main() {
  testWidgets('Large inventory renders only one 50-device page at a time',
      (tester) async {
    final app = await _bootstrap(tester);
    final data = fixture();
    final template = (data['devices'] as List).first as Json;
    data['devices'] = List.generate(125, (index) {
      final device = Map<String, dynamic>.from(template);
      device['id'] = 'bulk-$index';
      device['name'] = 'Bulk Device $index';
      device['location'] = index.isEven ? 'LAN' : 'Tailnet';
      return device;
    });
    app.api.data = data;
    app.controller.snapshot = Snapshot.fromJson(data);
    app.controller.notifyListeners();
    await tester.pumpAndSettle();
    await _navigate(tester, 1, 1440);
    expect(_deviceRows(), findsNWidgets(50));
    expect(find.text('Seite 1 / 3'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Nächste Geräte'));
    await tester.tap(find.byTooltip('Nächste Geräte'));
    await tester.pumpAndSettle();
    expect(_deviceRows(), findsNWidgets(50));
    expect(find.text('Seite 2 / 3'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Nächste Geräte'));
    await tester.tap(find.byTooltip('Nächste Geräte'));
    await tester.pumpAndSettle();
    expect(_deviceRows(), findsNWidgets(25));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Device metric request survives controller-driven rebuilds',
      (tester) async {
    final app = await _bootstrap(tester);
    await _navigate(tester, 1, 1440);
    await tester.tap(find.byKey(const Key('device-evo')));
    await tester.pumpAndSettle();
    expect(app.api.metricRequests, 1);
    app.controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(app.api.metricRequests, 1);
    expect(find.text('Fünf unabhängige Statusdimensionen'), findsOneWidget);
    await tester.tap(find.byTooltip('Details schließen'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Device freshness is source-specific and an open dialog follows recovery',
      (tester) async {
    final data = fixture();
    (data['system'] as Json)['opcua_status'] = 'reconnecting';
    final a = (data['devices'] as List).first as Json;
    a['data_source_id'] = 'a';
    a['is_faulted'] = true;
    (a['health'] as Json)['service_health'] = 'degraded';
    (a['health'] as Json)['telemetry_freshness'] = 'stale';
    final b = Map<String, dynamic>.from(a);
    b['id'] = 'b:M-01';
    b['name'] = 'Simulation B';
    b['data_source_id'] = 'b';
    b['is_faulted'] = false;
    b['health'] = {
      ...a['health'] as Json,
      'service_health': 'connected',
      'telemetry_freshness': 'fresh'
    };
    data['devices'] = [a, b];
    final app = await _bootstrap(tester, data: data);
    await _navigate(tester, 1, 1440);
    await tester.tap(find.byKey(const Key('device-b:M-01')));
    await tester.pumpAndSettle();
    expect(find.text('Aktuell'), findsWidgets);
    expect(find.text('Veraltet / unbekannt'), findsNothing);
    final requests = app.api.metricRequests;
    (b['health'] as Json)['service_health'] = 'degraded';
    (b['health'] as Json)['telemetry_freshness'] = 'stale';
    app.controller.snapshot = Snapshot.fromJson(data);
    app.controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Degradiert'), findsWidgets);
    expect(find.bySemanticsLabel('Degradiert'), findsWidgets);
    (b['health'] as Json)['service_health'] = 'connected';
    (b['health'] as Json)['telemetry_freshness'] = 'fresh';
    app.controller.snapshot = Snapshot.fromJson(data);
    app.controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(app.api.metricRequests, requests);
    expect(find.text('Aktuell'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Metric detail failure stays explicit inside the dialog',
      (tester) async {
    await _bootstrap(tester, configure: (api) => api.failMetrics = true);
    await _navigate(tester, 1, 1440);
    await tester.tap(find.byKey(const Key('device-evo')));
    await tester.pumpAndSettle();
    expect(find.text('Metriken nicht erreichbar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OPC UA node failure and retry do not synthesize nodes',
      (tester) async {
    final app =
        await _bootstrap(tester, configure: (api) => api.failNodes = true);
    await _navigate(tester, 3, 1440);
    expect(find.text('Browser nicht verfügbar'), findsOneWidget);
    expect(find.byKey(const Key('node-temperature')), findsNothing);
    app.api.failNodes = false;
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('node-temperature')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Diagnostics renders collection gaps separately and exposes errors',
      (tester) async {
    final app = await _bootstrap(tester);
    await _navigate(tester, 4, 1440);
    expect(find.text('Verbindung verloren'), findsOneWidget);
    expect(find.text('Verbindung wiederhergestellt'), findsOneWidget);
    expect(find.text('Dokumentierte Lücke: 2500 ms'), findsOneWidget);
    app.api.failEvents = true;
    await tester.tap(find.byTooltip('Diagnosedaten aktualisieren'));
    await tester.pumpAndSettle();
    expect(find.text('Collection-Ereignisse nicht verfügbar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Network zoom and node selection preserve detail navigation',
      (tester) async {
    await _bootstrap(tester);
    await _navigate(tester, 2, 1440);
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final transformation = viewer.transformationController!;
    transformation.value = Matrix4.identity()..translate(40.0, 30.0);
    await tester.tap(find.byTooltip('Vergrößern'));
    await tester.pump();
    expect(transformation.value.getTranslation().x, 40);
    expect(transformation.value.getTranslation().y, 30);
    await tester.tap(find.byKey(const Key('topology-evo')));
    await tester.pumpAndSettle();
    expect(find.text('Fünf unabhängige Statusdimensionen'), findsOneWidget);
    await tester.tap(find.byTooltip('Details schließen'));
    await tester.pumpAndSettle();
    expect(find.text('Gerätedetails öffnen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Incident hero keeps support, contradiction and uncertainty visible',
      (tester) async {
    final data = fixture();
    data['incidents'] = [
      {
        'id': 'incident-test',
        'title': 'Testbefund ohne Kausalbehauptung',
        'category': 'Test',
        'device_id': 'M-01',
        'simulated': true,
        'supporting': ['Beobachtung A'],
        'contradicting': ['Gegenbeobachtung B'],
        'missing': ['Messung C fehlt'],
        'timeline': ['Erster Schritt', 'Zweiter Schritt']
      }
    ];
    await _bootstrap(tester, data: data);
    await _navigate(tester, 4, 1440);
    expect(find.text('Testbefund ohne Kausalbehauptung'), findsOneWidget);
    expect(find.text('Beobachtung A'), findsOneWidget);
    expect(find.text('Gegenbeobachtung B'), findsOneWidget);
    expect(find.text('Messung C fehlt'), findsOneWidget);
    expect(
        find.text('Korrelation ist keine bewiesene Ursache'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Scenario rejection is separate from transport health',
      (tester) async {
    final app = await _bootstrap(
      tester,
      configure: (api) => api.scenarioFailure = const ApiFailure(
        'Demo deaktiviert',
        code: 'DEMO_DISABLED',
        path: '/api/v1/demo/scenario',
      ),
    );
    await _navigate(tester, 4, 1440);
    await tester.tap(find.byKey(const Key('scenario-agent')));
    await tester.pumpAndSettle();
    expect(find.text('Szenariowechsel nicht ausgeführt'), findsOneWidget);
    expect(find.text('Demo deaktiviert (DEMO_DISABLED)'), findsOneWidget);
    expect(find.text('Verbindung und Datenaktualität'), findsNothing);
    expect(app.controller.error, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OPC UA pagination follows the response limit', (tester) async {
    await _bootstrap(tester, configure: (api) => api.nodeLimit = 25);
    await _navigate(tester, 3, 1440);
    expect(find.text('1006 Nodes · Seite 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('next-nodes')));
    await tester.pumpAndSettle();
    expect(find.text('1006 Nodes · Seite 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Device locations derive from inventory and page clamps safely',
      (tester) async {
    final app = await _bootstrap(tester);
    final data = fixture();
    final template = (data['devices'] as List).first as Json;
    data['devices'] = List.generate(55, (index) {
      final device = Map<String, dynamic>.from(template);
      device['id'] = 'bulk-$index';
      device['name'] = 'Bulk Device $index';
      device['location'] = index == 54 ? 'Neue Zone' : 'LAN';
      return device;
    });
    app.api.data = data;
    app.controller.snapshot = Snapshot.fromJson(data);
    app.controller.notifyListeners();
    await _navigate(tester, 1, 1440);
    await tester.tap(find.byKey(const Key('filter-Standort')));
    await tester.pumpAndSettle();
    expect(find.text('Standort: Neue Zone'), findsOneWidget);
    await tester.tap(find.text('Standort: Neue Zone').last);
    await tester.pumpAndSettle();
    expect(
        find.text('1 von 55 Geräten · Simuliertes Inventar'), findsOneWidget);
    await tester.tap(find.byKey(const Key('filter-Standort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standort: Alle').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Nächste Geräte'));
    await tester.tap(find.byTooltip('Nächste Geräte'));
    await tester.pumpAndSettle();
    data['devices'] = (data['devices'] as List).take(10).toList();
    app.api.data = data;
    app.controller.snapshot = Snapshot.fromJson(data);
    app.controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(_deviceRows(), findsNWidgets(10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Topology sizes the canvas for every device row', (tester) async {
    final app = await _bootstrap(tester);
    final data = fixture();
    final template = (data['devices'] as List).first as Json;
    data['devices'] = List.generate(14, (index) {
      final device = Map<String, dynamic>.from(template);
      device['id'] = 'bulk-$index';
      device['name'] = 'Bulk Device $index';
      device['location'] = 'LAN';
      return device;
    });
    app.api.data = data;
    app.controller.snapshot = Snapshot.fromJson(data);
    app.controller.notifyListeners();
    await _navigate(tester, 2, 1440);
    for (var index = 0; index < 14; index++) {
      expect(find.byKey(Key('topology-bulk-$index')), findsOneWidget);
    }
    expect(
        tester.getSize(find.byKey(const Key('topology-canvas'))).height, 1092);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Light status colours meet text contrast on white',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      theme: OipTokens.theme(Brightness.light),
      home: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      }),
    ));
    for (final status in ['info', 'degraded', 'alarm']) {
      final color = OipTokens.statusColor(context, status);
      final contrast = (Colors.white.computeLuminance() + .05) /
          (color.computeLuminance() + .05);
      expect(contrast, greaterThanOrEqualTo(4.5), reason: status);
    }
  });

  testWidgets('Non-simulated backend data is never labelled as simulation',
      (tester) async {
    final data = fixture();
    (data['system'] as Json)['simulated'] = false;
    data['devices'] = (data['devices'] as List).map((device) {
      final copy = Map<String, dynamic>.from(device as Json);
      copy['simulated'] = false;
      return copy;
    }).toList();
    await _bootstrap(tester, data: data);
    expect(find.text('BACKEND-DATEN'), findsOneWidget);
    expect(find.text('LOKALE SIMULATION'), findsNothing);
    await _navigate(tester, 1, 1440);
    expect(find.textContaining('API-Inventar'), findsOneWidget);
    expect(find.text('SIMULATION'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Owned controller is disposed with the production app',
      (tester) async {
    final api = FakeApi();
    final controller = OipController(api);
    await tester.pumpWidget(OipApp(
      controller: controller,
      autoStart: false,
      ownsController: true,
    ));
    await tester.pumpWidget(const SizedBox());
    expect(api.closeCalls, 1);
  });
}

Finder _deviceRows() => find.byWidgetPredicate((widget) =>
    widget.key is ValueKey<String> &&
    (widget.key as ValueKey<String>).value.startsWith('device-bulk-'));

Future<_TestApp> _bootstrap(
  WidgetTester tester, {
  Json? data,
  void Function(FakeApi)? configure,
}) async {
  const size = Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  final api = FakeApi();
  if (data != null) api.data = data;
  configure?.call(api);
  final controller = OipController(api)
    ..snapshot = Snapshot.fromJson(api.data)
    ..connection = 'live';
  await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.binding.setSurfaceSize(null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  return _TestApp(api, controller);
}

Future<void> _navigate(WidgetTester tester, int page, double width) async {
  if (width < 1080) {
    await tester.tap(find.byKey(const Key('open-navigation')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(Key('nav-$page')));
  await tester.pumpAndSettle();
}

class _TestApp {
  final FakeApi api;
  final OipController controller;
  const _TestApp(this.api, this.controller);
}
