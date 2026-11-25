import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/services/api.dart';
import 'package:oip_dashboard/widgets/infrastructure_selector.dart';

import 'infrastructure_support.dart';
import 'support.dart';

/// The canonical UI gate.
///
/// This suite protects the Spectrum-2027 Engineering Workstations against an
/// accidental restoration of the OIP/005 dashboard. It is a binding
/// integration contract, see `docs/design/OIP_CANONICAL_UI_BASELINE.md`.
///
/// Every check is a widget, state or provenance check. A substring search alone
/// is not a proof: the shell, the six workstations, the global infrastructure
/// context, the real-mode states and the authentication boundary are checked
/// as rendered widgets.
const canonicalPageTitles = [
  'Übersicht',
  'Geräte & Dienste',
  'Netzwerk & VPN',
  'OPC-UA-Browser',
  'Diagnose & Ereignisse',
  'Einstellungen',
];

Future<void> pumpShell(WidgetTester tester, OipController controller,
    {Size size = const Size(1440, 1000)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

OipController managedShellController() {
  final api = FakeApi()..infrastructure = infrastructureFixture();
  return OipController(api);
}

void main() {
  group('Canonical UI gate · approved application shell', () {
    testWidgets('The shell offers the six Spectrum-2027 workstations',
        (tester) async {
      final controller = managedShellController();
      await controller.resyncInfrastructure();
      addTearDown(controller.dispose);

      await pumpShell(tester, controller);

      // Six workstations in the approved order.
      expect(pageTitles, canonicalPageTitles);
      for (final title in canonicalPageTitles) {
        expect(find.text(title), findsWidgets, reason: 'missing $title');
      }
      // The approved group structure of the sidebar.
      expect(find.text('ARBEITSBEREICH'), findsOneWidget);
      expect(find.text('DATEN & ANALYSE'), findsOneWidget);
      expect(find.text('SYSTEM'), findsOneWidget);
      // The application identity is the current one, not the OIP/005 label.
      expect(find.text('OIP · SPECTRUM 2027'), findsOneWidget);
      expect(find.textContaining('OIP / 005'), findsNothing);
    });

    testWidgets('The global infrastructure context selector is present',
        (tester) async {
      final controller = managedShellController();
      await controller.resyncInfrastructure();
      addTearDown(controller.dispose);

      await pumpShell(tester, controller);

      // The selector is a widget of the approved type and carries its key.
      expect(find.byType(InfrastructureSelector), findsOneWidget);
      expect(find.byKey(const Key('infrastructure-context-selector')),
          findsOneWidget);
      // It names every authorized infrastructure of the session.
      expect(find.textContaining('Alle berechtigten Infrastrukturen'),
          findsWidgets);
      // The scenario selector never replaces it in the real mode.
      expect(find.byKey(const Key('scenario-select')), findsNothing);
      expect(find.text('Normalbetrieb'), findsNothing);
    });

    testWidgets('The sidebar carries no decorative AGENT-FIRST card',
        (tester) async {
      final controller = managedShellController();
      await controller.resyncInfrastructure();
      addTearDown(controller.dispose);

      await pumpShell(tester, controller);

      // The agent-first principle stays architectural; it is not a decoration.
      expect(find.text('AGENT-FIRST'), findsNothing);
      expect(find.textContaining('MCP · REST/SSE · Flutter'), findsNothing);
    });

    testWidgets('Every workstation renders its own workspace header',
        (tester) async {
      final controller = managedShellController();
      await controller.resyncInfrastructure();
      addTearDown(controller.dispose);

      await pumpShell(tester, controller);

      void expectWorkstationTitle(String title) {
        expect(
          find.descendant(
            of: find.byKey(const Key('workstation-title')),
            matching: find.text(title),
          ),
          findsOneWidget,
        );
        // The two visible copies are the navigation item and the shell title.
        expect(find.text(title), findsNWidgets(2));
      }

      // Overview is the default landing page of the approved design.
      expectWorkstationTitle('Übersicht');
      expect(find.byKey(const Key('overview-primary-diagnostics')),
          findsOneWidget);

      // Devices & Services.
      await tester.tap(find.text('Geräte & Dienste').first);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expectWorkstationTitle('Geräte & Dienste');
      expect(find.byKey(const Key('devices-add-primary')), findsOneWidget);

      // Network & VPN.
      await tester.tap(find.text('Netzwerk & VPN').first);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expectWorkstationTitle('Netzwerk & VPN');
      expect(
          find.byKey(const Key('network-primary-connections')), findsOneWidget);

      // OPC-UA Browser.
      await tester.tap(find.text('OPC-UA-Browser').first);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expectWorkstationTitle('OPC-UA-Browser');
      expect(find.byKey(const Key('opcua-primary-search')), findsOneWidget);

      // Diagnostics & Events.
      await tester.tap(find.text('Diagnose & Ereignisse').first);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expectWorkstationTitle('Diagnose & Ereignisse');
      expect(find.byKey(const Key('diagnostics-primary-timeline')),
          findsOneWidget);

      // Settings.
      await tester.tap(find.text('Einstellungen').first);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expectWorkstationTitle('Einstellungen');
      expect(find.byKey(const Key('settings-page-header')), findsOneWidget);
    });

    testWidgets('The real mode shows no legacy dashboard and no demo identity',
        (tester) async {
      final controller = managedShellController();
      await controller.resyncInfrastructure();
      addTearDown(controller.dispose);

      await pumpShell(tester, controller);

      // The OIP/005 command center is not the default of the real mode.
      expect(
          find.textContaining('Deine Infrastruktur. Ein Bild.'), findsNothing);
      // The decorative gradient KPI row of the old overview is gone.
      expect(find.text('Erfasste Geräte'), findsNothing);
      expect(find.text('Erreichbare Geräte'), findsNothing);
      expect(find.text('Temperatur · M-01'), findsNothing);
      expect(find.textContaining('Netzwerkzonen'), findsNothing);
      // The demo inventory of 17 devices is never shown in the real mode.
      expect(find.textContaining('M-01'), findsNothing);
      expect(find.text('LAN'), findsNothing);
      expect(find.text('Tailnet'), findsNothing);
      expect(find.text('Remote Site'), findsNothing);
    });

    testWidgets('The real mode shows the authorized projection and its states',
        (tester) async {
      final controller = managedShellController();
      await controller.resyncInfrastructure();
      addTearDown(controller.dispose);

      await pumpShell(tester, controller);

      // The unified infrastructure view counts only authorized rows.
      expect(find.text('UNIFIED INFRASTRUCTURE VIEW'), findsOneWidget);
      expect(find.text('ORGANIZATIONS'), findsOneWidget);
      expect(find.text('INFRASTRUCTURES'), findsOneWidget);
      expect(find.text('SITES'), findsOneWidget);
      // The placement of an authorized infrastructure is shown.
      expect(find.textContaining('Organization A / Infrastructure A1'),
          findsOneWidget);
      // An empty result is a fact, not an offline state.
      expect(find.textContaining('Unknown ≠ Offline'), findsOneWidget);
    });

    testWidgets('The shell is responsive and keeps the context selector',
        (tester) async {
      final controller = managedShellController();
      await controller.resyncInfrastructure();
      addTearDown(controller.dispose);

      for (final size in const [
        Size(390, 844),
        Size(768, 1024),
        Size(1440, 1000),
        Size(1920, 1200),
      ]) {
        await pumpShell(tester, controller, size: size);
        // The context selector survives every approved width; the compact
        // layout moves it into the drawer instead of dropping it.
        expect(find.byType(InfrastructureSelector), findsOneWidget,
            reason: 'no infrastructure context selector at ${size.width}px');
        expect(find.text('Übersicht'), findsWidgets);
      }
    });

    testWidgets('The real mode keeps the device onboarding action reachable',
        (tester) async {
      final controller = managedShellController();
      await controller.resyncInfrastructure();
      addTearDown(controller.dispose);

      await pumpShell(tester, controller);
      await tester.tap(find.text('Geräte & Dienste').first);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      // The secure browser write path of the Core is offered.
      expect(find.byKey(const Key('devices-add-primary')), findsOneWidget);
      expect(find.text('Autorisierter v2-Scope'), findsNothing);
    });

    testWidgets('API and authentication failures never restore the legacy UI',
        (tester) async {
      for (final failure in const [
        ApiFailure('authentication required',
            code: 'UNAUTHENTICATED', statusCode: 401),
        ApiFailure('temporary transport failure',
            code: 'CONNECTION_FAILED', statusCode: 500),
      ]) {
        final api = FakeApi()..infrastructureFailure = failure;
        // The Core is **not** in demo mode — it still answers with simulated
        // data. The rule of the baseline is proved by the mode of the Core,
        // not by a fixture that has the fallback switched off by hand.
        (api.data['system'] as Map<String, dynamic>)['demo_controls'] = false;
        final controller =
            OipController(api, retryDelay: const Duration(milliseconds: 1));
        final running = controller.start();
        await pumpShell(tester, controller);

        expect(controller.snapshot, isNull);
        expect(controller.error, isNotNull);
        expect(find.textContaining('Deine Infrastruktur. Ein Bild.'),
            findsNothing);
        expect(find.text('Erfasste Geräte'), findsNothing);
        expect(find.text('Temperatur · M-01'), findsNothing);
        expect(find.text('Normalbetrieb'), findsNothing);
        expect(find.text('AGENT-FIRST'), findsNothing);
        if (failure.statusCode == 401) {
          expect(find.text('Lokale Operator-Anmeldung'), findsOneWidget);
          expect(find.text('UNIFIED INFRASTRUCTURE VIEW'), findsNothing);
        }
        controller.dispose();
        await tester.pump(const Duration(milliseconds: 20));
        await running;
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('The three themes stay available in the approved shell',
        (tester) async {
      final controller = managedShellController();
      await controller.resyncInfrastructure();
      addTearDown(controller.dispose);

      await pumpShell(tester, controller);
      expect(find.text('SPECTRUM'), findsOneWidget);

      await tester.tap(find.byKey(const Key('theme-toggle')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(find.text('DAYLIGHT'), findsOneWidget);

      await tester.tap(find.byKey(const Key('theme-toggle')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(find.text('GRAPHITE'), findsOneWidget);
    });
  });
}
