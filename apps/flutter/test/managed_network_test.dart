import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/design_system/theme.dart';
import 'package:oip_dashboard/features/network.dart';

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
    final api = FakeApi()..infrastructure = infrastructureFixture();
    final controller = OipController(api);
    await controller.resyncInfrastructure();
    addTearDown(controller.dispose);
    expect(controller.managed, isTrue);

    await pumpNetwork(tester, controller);

    // The authorized placement is shown with the identifiers the Core
    // delivered for it.
    expect(find.textContaining('Infrastructure A1'), findsWidgets);
    expect(find.textContaining('Source source-a1'), findsWidgets);
    // The projection carries no topology. That is a fact, not a state that is
    // still loading, and no path is guessed.
    expect(find.text('Topologie wird geladen'), findsNothing);
    expect(find.text('LOGISCHE PFADE'), findsOneWidget);
    expect(find.text('NICHT GELIEFERT'), findsWidgets);
    // The zones and paths of the legacy demo are not shown in the managed mode.
    expect(find.text('LAN'), findsNothing);
    expect(find.text('Tailnet'), findsNothing);
    expect(find.text('Remote Site'), findsNothing);
    expect(find.text('DEMO-PFADE'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
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
