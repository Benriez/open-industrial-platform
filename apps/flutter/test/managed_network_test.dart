import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/design_system/theme.dart';
import 'package:oip_dashboard/features/network.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'infrastructure_support.dart';
import 'support.dart';

Future<void> pumpNetwork(WidgetTester tester, OipController controller) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.binding.setSurfaceSize(const Size(1600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: OipTokens.theme(Brightness.light),
    darkTheme: OipTokens.theme(Brightness.dark),
    themeMode: ThemeMode.dark,
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => NetworkPage(controller),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'The managed network view shows the authorized placement and no loading state',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = FakeApi()..infrastructure = infrastructureFixture();
    final controller = OipController(api);
    await controller.resyncInfrastructure();
    addTearDown(controller.dispose);
    expect(controller.managed, isTrue);

    await pumpNetwork(tester, controller);

    expect(find.text('LAN-Verkabelung'), findsOneWidget);
    expect(find.text('Topologie wird geladen'), findsNothing);
    expect(find.text('DEMO-PFADE'), findsNothing);
    expect(find.text('LOGISCHE PFADE'), findsNothing);

    await tester.tap(find.byTooltip('Geräteliste'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Infrastructure A1'), findsWidgets);
    expect(find.textContaining('Source source-a1'), findsWidgets);

    await tester.tap(find.text('Verbindungspfade'));
    await tester.pumpAndSettle();
    expect(find.text('LAN-Verkabelung'), findsNothing);
    expect(find.text('Tailnet'), findsNothing);
    expect(find.text('Remote Site'), findsNothing);
    // Missing topology is reported as missing data; it is not turned into an
    // offline or isolated state.
    expect(find.text('Topologie im Snapshot nicht enthalten'), findsOneWidget);
    expect(
      find.textContaining(
          'Erreichbarkeit oder Verbindung werden daraus nicht abgeleitet'),
      findsOneWidget,
    );
  });
}
