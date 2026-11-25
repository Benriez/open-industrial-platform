import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'support.dart';

void main() {
  test('Missing or malformed CoreHealth never becomes Ready from UI transport',
      () {
    final missing = Snapshot.fromJson(fixture()).core;
    expect(missing.lifecycle, CoreLifecycle.unknown);
    expect(missing.ready, isNull);
    final malformed = CoreHealthView.fromJson(
        {'lifecycle': 'invented', 'live': 'true', 'ready': 1});
    expect(malformed.lifecycle, CoreLifecycle.unknown);
    expect(malformed.live, isNull);
    expect(malformed.ready, isNull);
  });
  testWidgets(
      'Live API preserves degraded Core independently of primary outage',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      return tester.binding.setSurfaceSize(null);
    });
    final data = fixture();
    data['core'] = {
      'lifecycle': 'degraded',
      'live': true,
      'ready': true,
      'persistence_healthy': true
    };
    (data['system'] as Json)['opcua_status'] = 'disconnected';
    final controller = OipController(FakeApi())
      ..snapshot = Snapshot.fromJson(data)
      ..connection = 'live';
    await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
    await tester.pumpAndSettle();
    expect(find.text('Core-Zustand: Degradiert'), findsNothing);
    await tester.tap(find.byKey(const Key('overview-inspector-open')));
    await tester.pumpAndSettle();
    expect(find.text('Core-Zustand: Degradiert'), findsOneWidget);
    controller.connection = 'reconnecting';
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Core-Zustand: Status veraltet'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
