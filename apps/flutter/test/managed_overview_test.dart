import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/design_system/theme.dart';
import 'package:oip_dashboard/features/overview.dart';
import 'package:oip_dashboard/models/infrastructure.dart';

import 'infrastructure_support.dart';
import 'support.dart';

Future<void> pumpManaged(WidgetTester tester, OipController controller,
    Widget Function(OipController) page) async {
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
          builder: (context, _) => page(controller),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The managed projection of the OIP-008.5 contract.
OipController managedController() {
  final api = FakeApi()..infrastructure = infrastructureFixture();
  final controller = OipController(api);
  return controller;
}

void main() {
  testWidgets(
      'The managed overview shows the authorized infrastructure and its placement',
      (tester) async {
    final controller = managedController();
    await controller.resyncInfrastructure();
    addTearDown(controller.dispose);
    expect(controller.managed, isTrue);

    await pumpManaged(tester, controller, (c) => OverviewPage(c, (_) {}));

    // The shell owns the global context selector. The workstation's
    // infrastructure summary represents the authorized unified selection.
    expect(find.byKey(const Key('unified-infrastructure-summary')),
        findsOneWidget);
    // The unified view counts only the rows the Core delivered.
    expect(find.text('UNIFIED INFRASTRUCTURE VIEW'), findsOneWidget);
    expect(find.text('ORGANIZATIONS'), findsOneWidget);
    expect(find.text('INFRASTRUCTURES'), findsOneWidget);
    expect(find.text('SITES'), findsOneWidget);
    // The placement of an authorized infrastructure is shown with the
    // identifiers the Core delivered for it.
    expect(find.textContaining('Organization A / Infrastructure A1'),
        findsOneWidget);
    expect(find.textContaining('2 Sites'), findsWidgets);
    // The demo coordinates are gone in the managed mode.
    expect(find.textContaining('M-01'), findsNothing);
    expect(find.textContaining('Temperatur M-01'), findsNothing);
    expect(find.textContaining('Netzwerkzonen'), findsNothing);
    // Unknown is not offline and no global severity is invented.
    expect(find.textContaining('keine globale Health-Severity'), findsOneWidget);
    expect(find.textContaining('Unknown ≠ Offline'), findsOneWidget);
  });

  testWidgets('The managed overview names the measured metric of a source',
      (tester) async {
    final controller = managedController();
    await controller.resyncInfrastructure();
    addTearDown(controller.dispose);

    await pumpManaged(tester, controller, (c) => OverviewPage(c, (_) {}));

    // The measured series of the authorized source is named with its source.
    final selected = controller.selectedTelemetry;
    expect(selected, isNotNull);
    expect(selected!.sourceId, isNotNull);
    expect(controller.telemetryKey, isNotNull);
    expect(controller.telemetryKey, contains(selected.metricId));
    // The legacy demo coordinate is never the managed default: the entity
    // `M-01` of the primary source is a demo rule, not an authorization.
    expect(selected.entityId, isNot('M-01'));
    // The choice is deterministic: the same projection yields the same metric.
    final first = controller.telemetryKey;
    await controller.resyncInfrastructure();
    expect(controller.telemetryKey, first);
  });

  test('An authorized snapshot invents no global count, health or topology', () {
    final snapshot = AuthorizedSnapshot.fromJson({
      'sources': <dynamic>[],
      'devices': <dynamic>[],
      'observations': <dynamic>[],
      'events': [
        {
          'id': 'actual-event',
          'sequence': 1,
          'context': {'data_source_id': 'source-a'},
          'event': {
            'Reconnected': {'at': 1700000000000}
          }
        }
      ],
      'locations': <dynamic>[],
      'resync_required': false,
      'replay_supported': false,
    }).toSnapshot();
    expect(snapshot.system.persisted, isNull);
    expect(snapshot.system.generatedMs, isNull);
    expect(snapshot.system.cpu, isNull);
    expect(snapshot.system.lastReceivedMs, isNull);
    expect(snapshot.core.ready, isNull);
    expect(snapshot.incidents, isEmpty);
    expect(snapshot.topology, isEmpty);
    expect(snapshot.system.demoControls, isFalse);
    expect(snapshot.incidentsDelivered, isFalse);
    expect(snapshot.topologyDelivered, isFalse);
  });
}
