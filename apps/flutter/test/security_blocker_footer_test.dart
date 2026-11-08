import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/models/contracts.dart';

import 'infrastructure_support.dart';
import 'support.dart';

/// The security blocker of the footer.
///
/// The scoped snapshot of a tenant carries no platform fact. The footer must
/// therefore name that the blocker of the platform is **not delivered** to the
/// session instead of presenting a placeholder as an open blocker.

Future<void> pumpShell(WidgetTester tester, OipController controller) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 1000);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets(
      'The footer names that the platform blocker is not delivered to the session',
      (tester) async {
    final api = FakeApi()..infrastructure = infrastructureFixture();
    final controller = OipController(api);
    await controller.resyncInfrastructure();
    addTearDown(controller.dispose);

    await pumpShell(tester, controller);

    expect(find.text('Security-Blocker: an diese Sitzung nicht geliefert'),
        findsOneWidget);
    // A placeholder is never presented as an open blocker.
    expect(find.textContaining('unknown offen'), findsNothing);
  });

  testWidgets('The footer names a blocker that the Core reported', (tester) async {
    // The v1 contract of the Core delivers the platform facts of the
    // instance, the security blocker among them.
    final data = fixture();
    (data['system'] as Map<String, Object?>)['security_blocker'] =
        'RUSTSEC-2023-0071';
    final api = FakeApi()..data = data;
    final controller = OipController(api);
    controller.snapshot = Snapshot.fromJson(data);
    addTearDown(controller.dispose);

    await pumpShell(tester, controller);

    expect(find.text('RUSTSEC-2023-0071 offen'), findsOneWidget);
    expect(find.text('Security-Blocker: an diese Sitzung nicht geliefert'),
        findsNothing);
  });

  testWidgets('The footer names that no blocker was reported', (tester) async {
    final data = fixture();
    (data['system'] as Map<String, Object?>)['security_blocker'] = 'none';
    final api = FakeApi()..data = data;
    final controller = OipController(api);
    controller.snapshot = Snapshot.fromJson(data);
    addTearDown(controller.dispose);

    await pumpShell(tester, controller);

    expect(find.text('Kein Security-Blocker gemeldet'), findsOneWidget);
  });
}
