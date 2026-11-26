import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/models/infrastructure.dart';
import 'package:oip_dashboard/features/diagnostics/evidence_timeline.dart';
import 'package:oip_dashboard/features/network/network_graph.dart';
import 'package:oip_dashboard/widgets/workstation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'infrastructure_support.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OIP-UX-001 adaptive layout state', () {
    test('selection-driven inspector, close, pin and context invalidation', () {
      final controller = OipController(FakeApi());
      expect(controller.inspectorVisible(WorkspaceId.devices, false), isFalse);
      expect(controller.inspectorVisible(WorkspaceId.devices, true), isTrue);

      controller.setInspectorOpen(WorkspaceId.devices, false);
      expect(controller.inspectorVisible(WorkspaceId.devices, true), isFalse);
      controller.revealInspector(WorkspaceId.devices);
      expect(controller.inspectorVisible(WorkspaceId.devices, true), isTrue);
      controller.toggleInspectorPin(WorkspaceId.devices);
      expect(controller.workspaces.layout(WorkspaceId.devices).inspectorPinned,
          isTrue);
      controller.workspaces.invalidateObjects();
      expect(controller.inspectorVisible(WorkspaceId.devices, false), isTrue,
          reason:
              'Pinned layout survives, while object data is cleared by pages');

      controller.setInspectorOpen(WorkspaceId.overview, true);
      controller.workspaces.invalidateObjects();
      expect(controller.inspectorVisible(WorkspaceId.overview, false), isFalse,
          reason: 'Unpinned inspector returns to selection-driven disclosure');
      controller.dispose();
    });

    test('view, density and advanced filters are memory-only per workstation',
        () {
      final controller = OipController(FakeApi());
      controller.setWorkspaceView(WorkspaceId.diagnostics, 'timeline');
      controller.setWorkspaceDensity(WorkspaceId.opcua, true);
      controller.setAdvancedFilters(WorkspaceId.network, true);
      expect(controller.workspaces.layout(WorkspaceId.diagnostics).view,
          'timeline');
      expect(controller.workspaces.layout(WorkspaceId.opcua).dense, isTrue);
      expect(controller.workspaces.layout(WorkspaceId.network).advancedFilters,
          isTrue);
      expect(controller.workspaces.layout(WorkspaceId.settings).view, isNull);
      controller.dispose();
    });
  });

  group('OIP-UX-001 task-based widget acceptance · contract fixture', () {
    Future<OipController> boot(WidgetTester tester,
        {Size size = const Size(1440, 900),
        InfrastructureBootstrap? fixtureData}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.binding.setSurfaceSize(size);
      final api = FakeApi()
        ..infrastructure = fixtureData ?? infrastructureFixture();
      final controller = OipController(api);
      await controller.resyncInfrastructure();
      await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
      await tester.pumpAndSettle();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await tester.binding.setSurfaceSize(null);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      return controller;
    }

    Future<void> navigate(WidgetTester tester, int index,
        {double width = 1440}) async {
      if (width < 1080) {
        await tester.tap(find.byKey(const Key('open-navigation')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(Key('nav-$index')));
      await tester.pumpAndSettle();
    }

    testWidgets('Overview orients first and object selection reveals details',
        (tester) async {
      final controller = await boot(tester);
      expect(find.byKey(const Key('unified-infrastructure-summary')),
          findsOneWidget);
      expect(find.byKey(const Key('overview-activity-coverage-workspace')),
          findsOneWidget);
      expect(find.byKey(const Key('overview-infrastructure-explorer')),
          findsNothing);
      expect(
          find.byKey(const Key('overview-adaptive-inspector')), findsNothing);

      // Manual open works directly from orientation; no separate mode.
      await tester.tap(find.byKey(const Key('overview-inspector-open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overview-infrastructure-explorer')),
          findsOneWidget);
      expect(
          find.byKey(const Key('overview-adaptive-inspector')), findsOneWidget);
      expect(controller.workspaces.layout(WorkspaceId.overview).expertWorkspace,
          isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Devices primary add path is honest and selection opens inspector',
        (tester) async {
      final controller = await boot(tester);
      await navigate(tester, 1);
      expect(find.byKey(const Key('devices-add-primary')), findsOneWidget);
      expect(find.byKey(const Key('devices-adaptive-inspector')), findsNothing);
      expect(find.byKey(const Key('device-search')), findsOneWidget);
      await tester.tap(find.byKey(const Key('devices-add-primary')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-onboarding-dialog')), findsOneWidget);
      expect(find.textContaining('Offline-Aufgabe'), findsOneWidget);
      expect(find.textContaining('erfolgreich'), findsNothing);
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('device-device-a1')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('devices-adaptive-inspector')), findsOneWidget);
      await tester.tap(find.byKey(const Key('devices-inspector-pin')));
      await tester.pumpAndSettle();
      expect(controller.workspaces.layout(WorkspaceId.devices).inspectorPinned,
          isTrue);
      await navigate(tester, 2);
      await navigate(tester, 1);
      expect(
          find.byKey(const Key('devices-adaptive-inspector')), findsOneWidget);
      expect(find.text('Pump A1'), findsWidgets);
      controller.selectInfrastructure(
          const InfrastructureSelection.infrastructure('org-a', 'infra-a2'));
      await tester.pumpAndSettle();
      expect(find.text('Pump A1'), findsNothing);
      expect(find.byKey(const Key('device-device-a2')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Diagnostics starts with current status and keeps the technical timeline',
        (tester) async {
      await boot(tester);
      await navigate(tester, 4);
      expect(find.text('Aktueller Zustand'), findsOneWidget);
      expect(find.text('Letzte Ereignisse'), findsOneWidget);
      expect(
          find.byKey(const Key('diagnostics-primary-timeline')), findsNothing);
      await tester.tap(find.byKey(const Key('diagnostics-show-technical')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('diagnostics-primary-timeline')),
          findsOneWidget);
      expect(find.byKey(const Key('diagnostics-mode-events')), findsOneWidget);
      expect(find.byType(DiagnosticsEventTimeline), findsNothing);
      await tester.tap(find.byKey(const Key('diagnostics-primary-timeline')));
      await tester.pumpAndSettle();
      expect(find.byType(DiagnosticsEventTimeline), findsOneWidget);
      await tester.tap(find.byKey(const Key('diagnostics-show-status')));
      await tester.pumpAndSettle();
      expect(find.text('Aktueller Zustand'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Network opens on wiring and preserves the reported map',
        (tester) async {
      await boot(tester);
      await navigate(tester, 2);
      expect(find.byKey(const Key('network-lan-view')), findsOneWidget);
      expect(find.byKey(const Key('network-summary')), findsNothing);
      await tester.tap(find.byKey(const Key('network-tab-connections')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('network-show-logical-map')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fit-topology')), findsOneWidget);
      expect(find.byKey(const Key('topology-canvas')), findsOneWidget);
      final fit =
          tester.widget<ToolButton>(find.byKey(const Key('fit-topology')));
      expect(fit.onPressed, isNotNull,
          reason: 'registered devices remain visible when paths are absent');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Saved LAN cables form a router star within the selected site',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = await boot(tester,
          fixtureData: infrastructureFixture(networkExample: true));
      controller.selectInfrastructure(
          const InfrastructureSelection.infrastructure('org-a', 'infra-a1'));
      controller.connection = 'live';
      await tester.pumpAndSettle();
      await navigate(tester, 2);

      NetworkTopologyGraph graph() => tester
          .widget<NetworkTopologyGraph>(find.byType(NetworkTopologyGraph));
      expect(graph().edges, isEmpty);
      expect(graph().layout.devices, hasLength(6));
      await tester.tap(find.byKey(const Key('lan-wiring-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lan-router-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Site router').last);
      await tester.pumpAndSettle();
      for (final id in ['desk-a1', 'server-a1', 'bridge-a1']) {
        final checkbox = find.byKey(Key('lan-client-$id'));
        await tester.ensureVisible(checkbox);
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
      }
      expect(
          find.byKey(const Key('lan-client-device-a1-manual')), findsNothing);
      await tester.tap(find.byKey(const Key('lan-wiring-save')));
      await tester.pumpAndSettle();
      final edges = graph().edges;
      expect(edges.map((edge) => edge.link.from).toSet(), {'router-a1'});
      expect(edges.map((edge) => edge.link.to).toSet(),
          {'desk-a1', 'server-a1', 'bridge-a1'});
      expect(
          edges.every(
              (edge) => edge.recordedLan && edge.link.status == 'unknown'),
          isTrue);
      final positions = graph().layout.positions;
      expect(edges.map((edge) => positions[edge.link.to]!.dx).toSet(),
          hasLength(1));

      await tester.tap(find.byKey(const Key('network-tab-connections')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('network-show-logical-map')));
      await tester.pumpAndSettle();
      expect(graph().edges.map((edge) => edge.link.from).toSet(),
          {'server-a1', 'desk-a1'});
      expect(graph().edges.every((edge) => !edge.recordedLan), isTrue);
      await tester.tap(find.byKey(const Key('network-tab-lan')));
      await tester.pumpAndSettle();
      await navigate(tester, 1);
      await navigate(tester, 2);
      expect(graph().edges, hasLength(3));
      controller.selectInfrastructure(
          const InfrastructureSelection.infrastructure('org-a', 'infra-a2'));
      await tester.pumpAndSettle();
      expect(graph().edges, isEmpty);
      expect(find.byKey(const Key('topology-router-a1')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'OPC-UA search and source stay primary; inspector needs node intent',
        (tester) async {
      await boot(tester);
      await navigate(tester, 3);
      expect(find.byKey(const Key('opcua-primary-search')), findsOneWidget);
      expect(find.byKey(const Key('source-select')), findsOneWidget);
      expect(find.byKey(const Key('opcua-adaptive-inspector')), findsNothing);
      await tester.tap(find.byKey(const Key('opcua-primary-search')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('node-search')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Settings selection opens details; scope switch cannot leak them',
        (tester) async {
      final controller = await boot(tester);
      await navigate(tester, 5);
      expect(
          find.byKey(const Key('settings-adaptive-inspector')), findsNothing);
      await tester.tap(find.byKey(const Key('settings-section-application')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-refresh')));
      await tester.pumpAndSettle();
      controller.selectInfrastructure(
          const InfrastructureSelection.infrastructure('org-a', 'infra-a2'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('infrastructure-context-selector')),
          findsOneWidget);
      expect(
          find.byKey(const Key('settings-adaptive-inspector')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Manual inspector open synchronizes compact panes',
        (tester) async {
      await boot(tester, size: const Size(390, 844));
      for (final (index, id) in [
        (1, 'devices'),
        (2, 'network'),
        (3, 'opcua'),
        (4, 'diagnostics'),
        (5, 'settings'),
      ]) {
        await navigate(tester, index, width: 390);
        if (id == 'diagnostics') {
          final technical = find.byKey(const Key('diagnostics-show-technical'));
          await tester.ensureVisible(technical);
          await tester.tap(technical);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(Key('$id-inspector-open')));
        await tester.pumpAndSettle();
        expect(find.byKey(Key('$id-adaptive-inspector')), findsOneWidget,
            reason: id);
        expect(tester.takeException(), isNull, reason: id);
      }
    });

    testWidgets('Orientation and expert controls remain usable at all widths',
        (tester) async {
      for (final width in [320.0, 390.0, 768.0, 1024.0, 1440.0, 1920.0]) {
        await boot(tester, size: Size(width, width < 600 ? 844 : 1000));
        expect(find.byKey(const Key('infrastructure-context-selector')),
            findsOneWidget);
        expect(
            find.byKey(const Key('overview-workspace-toggle')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$width');
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
