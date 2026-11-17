import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/design_system/theme.dart';
import 'package:oip_dashboard/features/overview/dashboard_workspace.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/models/infrastructure.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

Json hostMetric(String name, Object value, Object unit,
    {int at = 1800000000000, String freshness = 'fresh'}) {
  final json = observation(value: 1.0);
  json['entity_id'] = 'device-pi';
  json['data_source_id'] = 'ssh-pi';
  json['metric_id'] = 'host.$name';
  json['value'] = {value is int ? 'unsigned_integer' : 'float': value};
  json['unit'] = unit;
  json['freshness'] = freshness;
  json['simulation_origin'] = null;
  (json['timestamps'] as Json)['source'] = at;
  return json;
}

Snapshot hostSnapshot({double memory = 42.5, int at = 1800000000000}) {
  final data = fixture();
  data['metrics'] = [
    hostMetric('memory_used_percent', memory, {'custom': '%'}, at: at),
    hostMetric('cpu_temperature_c', 91.0, 'celsius', at: at),
    hostMetric('memory_used_bytes', 3221225472, {'custom': 'bytes'}, at: at),
    hostMetric('uptime_seconds', 273600.0, {'custom': 'seconds'}, at: at),
    hostMetric('gpu_utilization_percent', 12.0, {'custom': '%'},
        at: at, freshness: 'stale'),
  ];
  return Snapshot.fromJson(data);
}

OipController dashboardController() {
  final controller = OipController(FakeApi())
    ..snapshot = hostSnapshot()
    ..connection = 'live';
  controller.infrastructure
    ..status = InfrastructureContextStatus.ready
    ..principalIdentity = 'fixture-operator';
  return controller;
}

final _boundary = GlobalKey();

Future<void> pumpDashboard(WidgetTester tester, OipController controller,
    {Size size = const Size(1280, 900),
    Brightness brightness = Brightness.dark}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(MaterialApp(
    theme: OipTokens.theme(brightness),
    home: Scaffold(
      body: RepaintBoundary(
        key: _boundary,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => DashboardWorkspace(controller: controller),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Optional local preview: `OIP_DASHBOARD_PREVIEW=<dir> flutter test …` writes
/// the rendered dashboard with the real fonts. Never part of an assertion.
Future<void> writePreview(WidgetTester tester, String name) async {
  final directory = Platform.environment['OIP_DASHBOARD_PREVIEW'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$directory/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> loadPreviewFonts() async {
  final icons = Platform.environment['OIP_DASHBOARD_PREVIEW_ICONS'];
  if (Platform.environment['OIP_DASHBOARD_PREVIEW'] == null) return;
  Future<ByteData> file(String path) async =>
      ByteData.sublistView(File(path).readAsBytesSync());
  final roboto = FontLoader('Roboto');
  for (final entry in Directory('assets/fonts').listSync()) {
    if (entry.path.endsWith('.ttf')) roboto.addFont(file(entry.path));
  }
  await roboto.load();
  if (icons != null) {
    final material = FontLoader('MaterialIcons')..addFont(file(icons));
    await material.load();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('first view renders gauges for bounded units and stats otherwise',
      (tester) async {
    await loadPreviewFonts();
    final controller = dashboardController();
    await pumpDashboard(tester, controller);

    expect(find.text('host.memory_used_percent'), findsOneWidget);
    expect(find.text('host.cpu_temperature_c'), findsOneWidget);
    // Byte and duration units are shortened, not printed raw.
    expect(find.textContaining('3 GiB', findRichText: true), findsOneWidget);
    expect(find.textContaining('3d 4h', findRichText: true), findsOneWidget);
    // Percent and temperature get the gauge with its unit range.
    expect(find.text('100 %'), findsNWidgets(2));
    expect(find.text('100 °C'), findsOneWidget);
    // A stale signal is named and not shown as live.
    expect(find.text('STALE'), findsOneWidget);

    final stored = SharedPreferences.getInstance();
    final saved = jsonDecode((await stored).getString(
            'oip.dashboard.v1.fixture-operator.'
            '${Uri.encodeComponent(controller.infrastructure.selection.scopeKey)}')!)
        as Json;
    expect(saved['version'], 2);
    expect([for (final panel in saved['panels'] as List) panel['kind']],
        ['gauge', 'gauge', 'value', 'value', 'gauge']);

    // New samples feed the session sparkline without a selection.
    for (var tick = 1; tick <= 12; tick++) {
      controller.snapshot = hostSnapshot(
          memory: 42.5 + 6 * (tick % 5), at: 1800000000000 + tick * 1000);
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      controller.notifyListeners();
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    await writePreview(tester, 'dashboard-dark');
  });

  testWidgets('a layout saved before gauges existed is upgraded once',
      (tester) async {
    final controller = dashboardController();
    final key = 'oip.dashboard.v1.fixture-operator.'
        '${Uri.encodeComponent(controller.infrastructure.selection.scopeKey)}';
    final percent = observationKey(controller.snapshot!.metrics.first);
    final bytes = observationKey(controller.snapshot!.metrics[2]);
    SharedPreferences.setMockInitialValues({
      key: jsonEncode({
        'columns': 2,
        'panels': [
          {'observation': percent, 'kind': 'value'},
          {'observation': bytes, 'kind': 'value'},
          {'observation': 'gone\u001fdevice\u001fhost.missing', 'kind': 'value'},
        ],
      }),
    });
    await pumpDashboard(tester, controller);
    final saved =
        jsonDecode((await SharedPreferences.getInstance()).getString(key)!)
            as Json;
    expect(saved['version'], 2);
    expect(saved['columns'], 2);
    expect([for (final panel in saved['panels'] as List) panel['kind']],
        ['gauge', 'value', 'value']);
    expect(find.text('KEIN SIGNAL'), findsOneWidget);
  });

  testWidgets('panel options change visualisation, range and thresholds',
      (tester) async {
    await loadPreviewFonts();
    final controller = dashboardController();
    await pumpDashboard(tester, controller, brightness: Brightness.light);
    await tester.tap(find.byKey(const Key('overview-dashboard-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Panel konfigurieren').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Balken'));
    await tester.enterText(find.widgetWithText(TextField, 'Maximum (%)'), '50');
    await tester.enterText(
        find.widgetWithText(TextField, 'Warnung ab (%)'), '20');
    await tester.enterText(
        find.widgetWithText(TextField, 'Kritisch ab (%)'), '10');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('Kritisch darf nicht unter der Warnschwelle liegen.'),
        findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Kritisch ab (%)'), '40');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('50 %'), findsOneWidget);

    final saved = jsonDecode((await SharedPreferences.getInstance()).getString(
            'oip.dashboard.v1.fixture-operator.'
            '${Uri.encodeComponent(controller.infrastructure.selection.scopeKey)}')!)
        as Json;
    expect((saved['panels'] as List).first, {
      'observation': observationKey(controller.snapshot!.metrics.first),
      'kind': 'bar',
      'custom': true,
      'max': 50.0,
      'warn': 20.0,
      'crit': 40.0,
    });

    // Narrow width: one column, no overflow.
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.physicalSize = const Size(390, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1280, 900);
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpAndSettle();
    await writePreview(tester, 'dashboard-light-edit');
  });
}
