import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/core/sse.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'support.dart';

void main() {
  testWidgets(
      'The managed network view shows the authorized placement and no loading state',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    final events = StreamController<ServerEvent>.broadcast();
    final api = ManagedApi(managedClient(scopedSnapshot), events);
    // The session of the server marks the client as managed.
    await api.session();
    final controller = OipController(api,
        retryDelay: const Duration(milliseconds: 1))
      ..snapshot = Snapshot.fromScopedJson(scopedSnapshot())
      ..connection = 'live';
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    expect(controller.managed, isTrue);
    await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-2')));
    await tester.pumpAndSettle();

    // The registered node of the session is drawn.
    expect(find.byKey(const Key('topology-device-a')), findsOneWidget);
    // The authorized placement is shown with the identifiers the Core
    // delivered for it.
    expect(find.text('Autorisierte Platzierung'), findsOneWidget);
    expect(find.text('org-a · infra-a1 · site-a1'), findsOneWidget);
    expect(find.text('Quelle source-ssh'), findsOneWidget);
    // The projection carries no topology. That is a fact, not a state that
    // is still loading, and no path is guessed.
    expect(find.text('Topologie wird geladen'), findsNothing);
    expect(find.text('Keine Verbindungspfade in der autorisierten Projektion'),
        findsOneWidget);
    // The zones of the legacy demo are not shown in the managed mode.
    expect(find.text('LAN'), findsNothing);
    expect(find.text('Tailnet'), findsNothing);
    expect(find.text('Remote Site'), findsNothing);
    // The real site of the node is the zone of the session.
    expect(find.text('site-a1'), findsWidgets);
    expect(find.textContaining('1 Geräte · Standort'), findsOneWidget);
  });
}
