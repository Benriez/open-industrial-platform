import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/widgets/workstation.dart';

import 'infrastructure_support.dart';
import 'support.dart';

/// Regression coverage for the OPC UA workstation (context rail, explorer,
/// inspector). Every assertion uses data the fake API actually delivered.
void main() {
  testWidgets('Explorer renders a full 40-node page with pins and keyboard',
      (tester) async {
    final app = await _bootstrap(tester, const Size(1440, 1000),
        configure: (api) => api.generatedBulkNodes = 1000);
    await _navigate(tester, 1440);
    expect(find.text('6 Nodes · Seite 1'), findsOneWidget);
    expect(find.text('von 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('folder-all')));
    await tester.pumpAndSettle();
    expect(find.text('1006 Nodes · Seite 1'), findsOneWidget);
    expect(find.text('von 26'), findsOneWidget);
    expect(find.text('Namespace 2'), findsOneWidget);
    expect(find.byKey(const Key('node-alarm_active')), findsOneWidget);
    expect(find.byKey(const Key('node-temperature')), findsOneWidget);
    expect(find.text('READ-ONLY ANALYSE'), findsOneWidget);

    // Selecting a row focuses the list; arrow keys move the selection.
    await tester.tap(find.byKey(const Key('node-alarm_active')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('node-value')), findsOneWidget);
    expect(find.text('false'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
        tester.widget<Text>(find.byKey(const Key('node-value'))).data, 'true');
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(find.text('bulk.0033'), findsWidgets);

    // P pins the selected node; the rail shows it with its delivered value.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pin-bulk.0033')), findsOneWidget);
    expect(find.text('1/8'), findsOneWidget);

    // PageDown requests the next page from the API; the pin survives.
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(find.text('1006 Nodes · Seite 2'), findsOneWidget);
    expect(find.byKey(const Key('pin-bulk.0033')), findsOneWidget);
    expect(find.byKey(const Key('node-bulk.0034')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pin-bulk.0033')));
    await tester.pumpAndSettle();
    expect(find.text('bulk.0033'), findsWidgets);
    expect(app.controller.error, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Density, grouping and scope keep pagination honest',
      (tester) async {
    await _bootstrap(tester, const Size(1440, 1000),
        configure: (api) => api.generatedBulkNodes = 1000);
    await _navigate(tester, 1440);
    await tester.tap(find.byKey(const Key('density-toggle')));
    await tester.pumpAndSettle();
    final row = tester.getSize(find.byKey(const Key('node-temperature')));
    expect(row.height, WorkstationTokens.rowDense);
    await tester.tap(find.byKey(const Key('view-grouped')));
    await tester.pumpAndSettle();
    expect(find.text('NUMERISCH'), findsOneWidget);
    expect(find.text('BOOLEAN'), findsOneWidget);
    expect(find.text('TEXT'), findsOneWidget);
    await tester.tap(find.byKey(const Key('folder-Bulk')));
    await tester.pumpAndSettle();
    expect(find.text('1000 Nodes · Seite 1'), findsOneWidget);
    expect(find.text('BOOLEAN'), findsNothing);
    await tester.tap(find.byKey(const Key('next-nodes')));
    await tester.pumpAndSettle();
    expect(find.text('1000 Nodes · Seite 2'), findsOneWidget);
    expect(find.text('Position 41–80'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Search shortcut focuses the field and Escape clears it',
      (tester) async {
    await _bootstrap(tester, const Size(1440, 1000),
        configure: (api) => api.generatedBulkNodes = 1000);
    await _navigate(tester, 1440);
    await tester.tap(find.byKey(const Key('folder-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('node-temperature')));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final field =
        tester.widget<TextField>(find.byKey(const Key('node-search')));
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.enterText(find.byKey(const Key('node-search')), 'bulk.09');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('100 Nodes · Seite 1'), findsOneWidget);
    expect(find.textContaining('SUCHE „BULK.09“'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('1006 Nodes · Seite 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inspector separates live subscription from single reads',
      (tester) async {
    final app = await _bootstrap(tester, const Size(1440, 1000),
        configure: (api) => api.generatedBulkNodes = 40);
    await _navigate(tester, 1440);
    await tester.tap(find.byKey(const Key('node-temperature')));
    await tester.pumpAndSettle();
    expect(find.text('Live-Abonnement'), findsOneWidget);
    expect(find.text('61.2 °C'), findsWidgets);
    expect(find.text('0 · 0x00000000 · Good'), findsOneWidget);
    expect(find.text('SourceTimestamp · virtuelle Quellzeit'), findsOneWidget);
    expect(find.text('100000000000 ms'), findsOneWidget);
    expect(find.byType(Sparkline), findsNothing);

    // Two accepted live samples produce a real sparkline; nothing is invented.
    final data = fixture();
    data['metrics'] = [
      observation(value: 62.0)
        ..['timestamps'] = {
          'source': 1700000001000,
          'server': 1700000001000,
          'received': 1800000001000
        }
    ];
    app.controller.snapshot = Snapshot.fromJson(data);
    app.controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(Sparkline), findsOneWidget);
    expect(find.text('2 Punkte · virtuelle Quellzeit'), findsOneWidget);

    await tester.tap(find.byKey(const Key('folder-Bulk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('node-bulk.0000')));
    await tester.pumpAndSettle();
    expect(find.text('Einzelabfrage'), findsOneWidget);
    expect(find.byType(Sparkline), findsNothing);
    expect(
        find.text(
            'Kein Verlauf · Einzelabfrage. Die API liefert für diese Node keine History.'),
        findsOneWidget);
    expect(find.text('Nicht abonniert · gezielte API-Einzelabfrage'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stale transport and bad quality stay explicit in the inspector',
      (tester) async {
    final data = fixture();
    data['metrics'] = [observation(value: null)];
    final app = await _bootstrap(tester, const Size(1440, 1000), data: data);
    await _navigate(tester, 1440);
    expect(find.text('Ungültig · bad'), findsOneWidget);
    expect(find.text('invalid_measurement'), findsOneWidget);
    app.controller.connection = 'reconnecting';
    app.controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('OPC UA STALE'), findsOneWidget);
    expect(find.text('Veraltet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Non-simulated backend never labels source time as virtual',
      (tester) async {
    final data = fixture();
    (data['system'] as Json)['simulated'] = false;
    await _bootstrap(tester, const Size(1440, 1000), data: data);
    await _navigate(tester, 1440);
    expect(find.text('SourceTimestamp'), findsOneWidget);
    expect(find.text('SourceTimestamp · virtuelle Quellzeit'), findsNothing);
    expect(find.text('OPC-UA-API'), findsOneWidget);
    expect(find.text('OPC-UA-SIMULATOR'), findsNothing);
    expect(find.text('Backend'), findsWidgets);
    expect(find.textContaining('urn:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(1920, 1080),
    Size(1440, 1000),
    Size(1024, 900),
    Size(834, 1112),
    Size(768, 1024),
    Size(390, 844),
    Size(320, 740)
  ]) {
    for (final theme in const ['Spectrum', 'Daylight', 'Graphite']) {
      testWidgets(
          'Dense 40-node workstation has no overflow in $theme at $size',
          (tester) async {
        await _bootstrap(tester, size,
            configure: (api) => api.generatedBulkNodes = 1000);
        final clicks = ['Spectrum', 'Daylight', 'Graphite'].indexOf(theme);
        for (var i = 0; i < clicks; i++) {
          await tester.tap(find.byKey(const Key('theme-toggle')));
          await tester.pumpAndSettle();
        }
        await _navigate(tester, size.width);
        await tester.ensureVisible(find.byKey(const Key('folder-all')));
        await tester.tap(find.byKey(const Key('folder-all')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('node-temperature')));
        await tester.tap(find.byKey(const Key('node-temperature')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pin-toggle')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('density-toggle')));
        await tester.tap(find.byKey(const Key('density-toggle')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('next-nodes')));
        await tester.tap(find.byKey(const Key('next-nodes')));
        await tester.pumpAndSettle();
        expect(find.text('1006 Nodes · Seite 2'), findsOneWidget);
        expect(find.byKey(const Key('pin-temperature')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$theme $size');
      });
    }
  }
  testWidgets(
      'The authorized scope shows no scenario as an internal wire value',
      (tester) async {
    // The scenario is a concept of the demo. The authorized projection of a
    // tenant carries none: the source panel names that instead of showing
    // "authorized_context" as a fact.
    final api = FakeApi();
    final controller = OipController(api)
      ..snapshot = infrastructureFixture().snapshot.toSnapshot()
      ..connection = 'live';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
    await tester.pumpAndSettle();
    await _navigate(tester, 1440);

    expect(find.text('nicht geliefert'), findsWidgets);
    expect(find.text('authorized_context'), findsNothing);
  });
}

Future<_TestApp> _bootstrap(
  WidgetTester tester,
  Size size, {
  Json? data,
  void Function(FakeApi)? configure,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  final api = FakeApi();
  if (data != null) api.data = data;
  configure?.call(api);
  final controller = OipController(api)
    ..snapshot = Snapshot.fromJson(api.data)
    ..connection = 'live'
    ..workspaces.setInspectorOpen(WorkspaceId.opcua, true);
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

Future<void> _navigate(WidgetTester tester, double width) async {
  if (width < 1080) {
    await tester.tap(find.byKey(const Key('open-navigation')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('nav-3')));
  await tester.pumpAndSettle();
}

class _TestApp {
  final FakeApi api;
  final OipController controller;
  const _TestApp(this.api, this.controller);
}
