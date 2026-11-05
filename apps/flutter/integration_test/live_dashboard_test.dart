import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/services/api.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Simulator to native Flutter, alarm and reconnect',
      (tester) async {
    const base = String.fromEnvironment('OIP_API_URL',
        defaultValue: 'http://127.0.0.1:8080');
    final controller = OipController(RestApi(Uri.parse(base)));
    await tester.pumpWidget(OipApp(controller: controller));
    Future<void> until(bool Function() ready) async {
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (ready()) return;
      }
      fail('Timed out waiting for live backend');
    }

    await until(() =>
        controller.connection == 'live' &&
        controller.snapshot!.metrics.isNotEmpty);
    expect(controller.snapshot!.system.persisted, greaterThan(0));
    expect(controller.snapshot!.metrics.first.simulated, isTrue);
    await controller.setScenario('sensor');
    await until(() => controller.snapshot!.metrics
        .any((m) => m.metricId == 'temperature' && (m.number ?? -1) > 90));
    await controller.setScenario('offline');
    await until(() => controller.stale);
    await until(() => !controller.stale);
    await controller.setScenario('normal');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
