import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/design_system/theme.dart';
import 'package:oip_dashboard/features/diagnostics.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/models/diagnostics.dart';
import 'package:oip_dashboard/services/api.dart';

import 'infrastructure_support.dart';
import 'support.dart';

/// A managed client that also serves the persisted evidence of the Core.
class EvidenceApi extends FakeApi {
  @override
  Future<CollectionEvents> collectionEventsWithStatus() async =>
      CollectionEvents(const [], 'not_implemented',
          replaySupported: false, resyncRequired: true);

  @override
  Future<DiagnosticPage> diagnosticGaps({int limit = 50, String? cursor}) async =>
      DiagnosticPage.fromJson({
        'items': [
          {
            'category': 'gap',
            'record': {
              'id': 'gap-1',
              'source': 'source-a1',
              'origin': 'external',
              'documented_start_ms': 1800000000000,
              'documented_end_ms': 1800000030000,
              'reason': 'Verbindung verloren',
            }
          }
        ],
        'truncated': false,
        'next_cursor': null,
        'missing_evidence': const [
          'Keine dokumentierte Lücke heißt nicht lückenlose Überwachung'
        ],
        'time_semantics': 'Gap: documented start marker.',
      });

  @override
  Future<DiagnosticPage> healthHistory({int limit = 50, String? cursor}) async =>
      DiagnosticPage.fromJson({
        'items': [
          {
            'category': 'health',
            'record': {
              'id': 'health-1',
              'source': 'source-a1',
              'at_ms': 1800000000000,
              'previous': null,
              'current': {
                'reachability': 'reachable',
                'connection': 'connected',
                'service': 'healthy',
                'freshness': 'fresh',
                'validity': 'valid',
              },
              'provenance': 'runtime_observed_dimensions',
            }
          }
        ],
        'truncated': false,
        'next_cursor': null,
        'missing_evidence': const <String>[],
        'time_semantics': 'Health: runtime wall-clock observation.',
      });
}

Future<void> pumpDiagnostics(WidgetTester tester, OipController controller) async {
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
          builder: (context, _) => DiagnosticsPage(controller),
        ),
      ),
    ),
  ));
  // The diagnostics workspace owns a periodic refresh timer, so the frame
  // sequence is bounded instead of settled.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets(
      'The managed diagnostics view shows the persisted evidence of the Core',
      (tester) async {
    final api = EvidenceApi()..infrastructure = infrastructureFixture();
    final controller = OipController(api);
    await controller.resyncInfrastructure();
    addTearDown(controller.dispose);
    expect(controller.managed, isTrue);

    await pumpDiagnostics(tester, controller);

    // The persisted evidence of the authorized sources is shown.
    expect(find.text('PERSISTIERTE EVIDENZ · CORE-SPEICHER'), findsOneWidget);
    expect(find.textContaining('Dokumentierte Lücke · source-a1'),
        findsOneWidget);
    expect(find.textContaining('Verbindung verloren'), findsWidgets);
    // The health transition keeps its unknown previous state unknown.
    expect(find.textContaining('Gesundheitsverlauf · source-a1'),
        findsOneWidget);
    expect(find.textContaining('Unbekannt → Verbunden'), findsOneWidget);
    // The state of the diagnosis history is the answer of the Core.
    expect(find.text('Diagnosehistorie: nicht implementiert'), findsOneWidget);
    expect(find.textContaining('demo_only'), findsNothing);
    // The limits that the Core states are shown, not hidden.
    expect(find.textContaining('Grenzen dieser Evidenz'), findsOneWidget);
  });

  testWidgets('A missing session shows the operator login and no demo dashboard',
      (tester) async {
    final data = fixture();
    (data['system'] as Json)['simulated'] = false;
    final api = FakeApi()
      ..data = data
      ..infrastructureFailure = const ApiFailure(
          'Browser-Session oder zentrale Policy erlaubt diesen Management-Read nicht.',
          code: 'PERMISSION_DENIED',
          statusCode: 403);
    final controller = OipController(api,
        retryDelay: const Duration(milliseconds: 1));
    final running = controller.start();
    // Inside a widget test the clock is the fake one: only a pump advances it.
    for (var i = 0; i < 50 && !controller.loginRequired; i++) {
      await tester.pump(const Duration(milliseconds: 2));
    }
    addTearDown(controller.dispose);
    expect(controller.loginRequired, isTrue);
    // The identity failure is terminal: the transport ends instead of retrying.
    await running;

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // The operator authorizes the session; the old demo dashboard is not
    // shown as a substitute for a failed authentication.
    expect(find.byKey(const Key('operator-login')), findsOneWidget);
    expect(find.byKey(const Key('operator-login-code')), findsOneWidget);
    expect(find.textContaining('Deine Infrastruktur. Ein Bild.'), findsNothing);
    expect(find.textContaining('COMMAND CENTER'), findsNothing);
  });
}
