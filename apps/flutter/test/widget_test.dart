import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'support.dart';

void main() {
  for (final size in [
    const Size(1920, 1080),
    const Size(1440, 1000),
    const Size(1024, 900),
    const Size(834, 1112),
    const Size(768, 1024),
    const Size(390, 844),
    const Size(375, 812),
    const Size(320, 740)
  ]) {
    testWidgets('Responsive navigation, filters, panels and themes $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = FakeApi();
      final controller = OipController(api)
        ..snapshot = Snapshot.fromJson(fixture())
        ..connection = 'live';
      await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
      await tester.pumpAndSettle();
      expect(find.text('Operations Workstation'), findsOneWidget);
      Future<void> navigate(int page) async {
        if (size.width < 1080) {
          await tester.tap(find.byKey(const Key('open-navigation')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(Key('nav-$page')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await navigate(1);
      await tester.enterText(find.byKey(const Key('device-search')), 'AMD');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-evo')), findsOneWidget);
      expect(find.byKey(const Key('device-M-01')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('device-evo')));
      await tester.tap(find.byKey(const Key('device-evo')));
      await tester.pumpAndSettle();
      expect(find.text('Fünf unabhängige Statusdimensionen'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Details schließen'));
      await tester.tap(find.byTooltip('Details schließen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('device-search')), 'missing');
      await tester.pumpAndSettle();
      expect(find.text('Keine Geräte gefunden'), findsOneWidget);
      await navigate(2);
      await navigate(3);
      expect(find.text('Namespace 2'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('next-nodes')));
      await tester.tap(find.byKey(const Key('next-nodes')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Seite 2'), findsOneWidget);
      await navigate(4);
      if (size.width < 600) {
        expect(tester.getSize(find.byKey(const Key('scenario-agent'))).height,
            greaterThanOrEqualTo(44));
      }
      await tester.ensureVisible(find.byKey(const Key('scenario-agent')));
      await tester.tap(find.byKey(const Key('scenario-agent')));
      await tester.pumpAndSettle();
      expect(api.chosen, 'agent');
      await tester.tap(find.byKey(const Key('theme-toggle')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.binding.setSurfaceSize(null);
    });
  }
  testWidgets('Initial error and reconnect state stay explicit',
      (tester) async {
    final controller = OipController(FakeApi())
      ..error = 'OIP-Server nicht erreichbar';
    await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
    await tester.pump();
    expect(find.text('Server nicht erreichbar'), findsOneWidget);
    controller.snapshot = Snapshot.fromJson(fixture());
    controller.connection = 'reconnecting';
    controller.notifyListeners();
    await tester.pump();
    expect(find.text('API STALE / RECONNECT'), findsOneWidget);
    expect(find.textContaining('VERALTET / UNBEKANNT'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
