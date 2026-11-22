import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/models/history.dart';
import 'package:oip_dashboard/models/infrastructure.dart';
import 'package:oip_dashboard/models/onboarding.dart';
import 'package:oip_dashboard/services/api.dart';

import 'infrastructure_support.dart';
import 'support.dart';

void main() {
  group('OIP-009 global context state · contract fixture only', () {
    test('Unified, infrastructure, site and source projections stay consistent',
        () async {
      final api = FakeApi()..infrastructure = infrastructureFixture();
      final controller = OipController(api);
      final running = controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.hasAuthorizedContext, isTrue);
      expect(controller.snapshot!.devices, hasLength(5));
      expect(controller.snapshot!.sources, hasLength(4));
      expect(controller.infrastructure.hierarchy.organizations, hasLength(2));
      expect(controller.infrastructure.hierarchy.infrastructures, hasLength(3));
      expect(controller.infrastructure.hierarchy.sites, hasLength(4));

      controller.selectInfrastructure(
          const InfrastructureSelection.infrastructure('org-a', 'infra-a1'));
      expect(controller.snapshot!.devices.map((item) => item.id).toSet(), {
        'device-a1',
        'device-a1-manual',
      });
      expect(controller.snapshot!.sources.map((item) => item.id).toSet(),
          {'source-a1', 'source-a1b'});
      expect(controller.snapshot!.metrics.map((item) => item.sourceId).toSet(),
          {'source-a1'});
      expect(controller.history.map((item) => item.sourceId).toSet(),
          {'source-a1'});

      controller.selectInfrastructure(
          const InfrastructureSelection.infrastructure('org-a', 'infra-a2'));
      expect(controller.snapshot!.devices.single.id, 'device-a2');
      expect(controller.snapshot!.sources.single.id, 'source-a2');
      expect(controller.snapshot!.recentEvents.single.sourceId, 'source-a2');

      controller.selectInfrastructure(const InfrastructureSelection.site(
          'org-a', 'infra-a1', 'site-a1-2'));
      expect(controller.snapshot!.devices.single.id, 'device-a1-manual');
      expect(controller.snapshot!.devices.single.sourceId, isNull);
      expect(controller.snapshot!.devices.single.health.freshness,
          'no_collector');
      expect(controller.snapshot!.devices.single.health.reachability, 'unknown');
      expect(controller.snapshot!.metrics, isEmpty);

      controller.selectInfrastructure(const InfrastructureSelection.source(
          'org-a', 'infra-a1', 'site-a1-1', 'source-a1'));
      expect(controller.snapshot!.devices.single.id, 'device-a1');
      expect(controller.snapshot!.sources.single.id, 'source-a1');

      controller.selectInfrastructure(const InfrastructureSelection.unified());
      expect(controller.snapshot!.devices, hasLength(5));
      expect(controller.infrastructure.selectedLabel,
          'Alle berechtigten Infrastrukturen');
      controller.dispose();
      await running;
    });

    test('Restricted principal never receives another organization', () async {
      final api = FakeApi()
        ..infrastructure = infrastructureFixture(restricted: true);
      final controller = OipController(api);
      final running = controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final hierarchy = controller.infrastructure.hierarchy;
      expect(hierarchy.organizations.map((item) => item.id), ['org-a']);
      expect(hierarchy.infrastructures.map((item) => item.id), ['infra-a1']);
      expect(controller.snapshot!.devices.map((item) => item.id),
          ['device-a1']);
      expect(
        () => controller.selectInfrastructure(
            const InfrastructureSelection.infrastructure('org-b', 'infra-b1')),
        throwsArgumentError,
      );
      controller.dispose();
      await running;
    });

    test('Empty authorized installation is not populated with demo data',
        () async {
      final api = FakeApi()..infrastructure = infrastructureFixture(empty: true);
      final controller = OipController(api);
      final running = controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.infrastructure.ready, isTrue);
      expect(controller.infrastructure.hasInfrastructure, isFalse);
      expect(controller.snapshot!.devices, isEmpty);
      expect(controller.snapshot!.sources, isEmpty);
      expect(controller.snapshot!.system.demoControls, isFalse);
      controller.dispose();
      await running;
    });

    test('Authorization revocation discards the selected scope and old data',
        () async {
      final api = FakeApi()..infrastructure = infrastructureFixture();
      final controller = OipController(
        api,
        retryDelay: const Duration(milliseconds: 1),
      );
      final running = controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      controller.selectInfrastructure(const InfrastructureSelection.site(
          'org-b', 'infra-b1', 'site-b1-1'));
      expect(controller.snapshot!.devices, hasLength(2));
      final oldRevision = controller.infrastructure.contextRevision;

      api.infrastructure = infrastructureFixture(restricted: true);
      controller.reconnect();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(controller.infrastructure.selection.isUnified, isTrue);
      expect(controller.infrastructure.contextRevision,
          greaterThan(oldRevision));
      expect(controller.snapshot!.devices.single.id, 'device-a1');
      expect(controller.infrastructure.hierarchy.organizations, hasLength(1));
      controller.dispose();
      await running;
    });

    test('Principal change has a separate cache/session generation', () async {
      final api = FakeApi()..infrastructure = infrastructureFixture();
      final controller = OipController(api,
          retryDelay: const Duration(milliseconds: 1));
      final running = controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      controller.selectInfrastructure(
          const InfrastructureSelection.infrastructure('org-a', 'infra-a2'));
      final oldSignature = controller.contextScopeSignature;
      api.infrastructure = infrastructureFixture(principal: 'fixture-reader-2');
      controller.reconnect();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(controller.infrastructure.principalIdentity, 'fixture-reader-2');
      expect(controller.contextScopeSignature, isNot(oldSignature));
      expect(controller.infrastructure.selection.isUnified, isTrue);
      controller.dispose();
      await running;
    });

    test('Authorized SSE updates preserve selection but replace only exact data',
        () async {
      final api = FakeApi()..infrastructure = infrastructureFixture();
      final controller = OipController(api);
      final running = controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      controller.selectInfrastructure(
          const InfrastructureSelection.infrastructure('org-a', 'infra-a2'));
      final signature = controller.contextScopeSignature;
      final oldRevision = controller.infrastructure.contextRevision;
      final observation =
          (api.infrastructure!.snapshot.raw['observations'] as List)
              .cast<Json>()
              .firstWhere((item) => item['data_source_id'] == 'source-a2');
      (observation['value'] as Json)['float'] = 62.0;
      api.emit();
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(controller.contextScopeSignature, signature);
      expect(controller.infrastructure.selection.infrastructureId, 'infra-a2');
      expect(controller.infrastructure.contextRevision, greaterThan(oldRevision));
      expect(controller.snapshot!.metrics.single.value, 62.0);
      expect(controller.snapshot!.devices.single.id, 'device-a2');
      controller.dispose();
      await running;
    });

    test('Unknown principal rebootstrap invalidates caches without scope expansion',
        () async {
      final base = infrastructureFixture();
      final api = FakeApi()
        ..infrastructure = InfrastructureBootstrap(
          principalIdentity: null,
          hierarchy: base.hierarchy,
          snapshot: base.snapshot,
          inventory: base.inventory,
          findings: base.findings,
          origin: InfrastructureDataOrigin.liveApi,
        );
      final controller = OipController(api,
          retryDelay: const Duration(milliseconds: 1));
      final running = controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      controller.selectInfrastructure(
          const InfrastructureSelection.infrastructure('org-a', 'infra-a2'));
      controller.reconnect();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(controller.infrastructure.principalIdentity, isNull);
      expect(controller.infrastructure.selection.infrastructureId, 'infra-a2');
      expect(controller.snapshot!.devices.single.id, 'device-a2');
      expect(controller.snapshot!.metrics.single.sourceId, 'source-a2');
      controller.dispose();
      await running;
    });

    test('The selected scope survives a refresh of the authorized projection',
        () async {
      // The session of the browser is the identity evidence of the principal.
      // A refresh of the projection reads the inventory again — after an
      // authorized write, for example — and it must not discard the scope of
      // the operator.
      final api = _SessionApi()..infrastructure = infrastructureFixture();
      final controller = OipController(api,
          retryDelay: const Duration(milliseconds: 1));
      await controller.resyncInfrastructure();
      controller.selectInfrastructure(
          const InfrastructureSelection.infrastructure('org-a', 'infra-a1'));
      final generation = controller.infrastructure.sessionGeneration;
      expect(controller.infrastructure.selection.infrastructureId, 'infra-a1');

      await controller.resyncInfrastructure();

      expect(controller.infrastructure.selection.infrastructureId, 'infra-a1');
      expect(controller.infrastructure.sessionGeneration, generation);
      expect(controller.infrastructure.principalIdentity, 'fixture-operator');
      controller.dispose();
    });

    test('Reconnect loading never expands the selected scope', () async {
      final api = FakeApi()..infrastructure = infrastructureFixture();
      final controller = OipController(api,
          retryDelay: const Duration(milliseconds: 5));
      final running = controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      controller.selectInfrastructure(
          const InfrastructureSelection.infrastructure('org-a', 'infra-a2'));
      api.infrastructureFailure = const ApiFailure('temporary transport gap',
          code: 'CONNECTION_FAILED');
      controller.reconnect();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(controller.infrastructure.reloading, isTrue);
      expect(controller.infrastructure.ready, isTrue);
      expect(controller.snapshot!.devices.single.id, 'device-a2');
      expect(controller.snapshot!.sources.single.id, 'source-a2');
      api.infrastructureFailure = null;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(controller.infrastructure.selection.infrastructureId, 'infra-a2');
      controller.dispose();
      await running;
    });

    test('Real non-demo identity denial does not fall back to v1 data',
        () async {
      final api = FakeApi()
        ..infrastructureFailure = const ApiFailure('denied',
            code: 'PERMISSION_DENIED', statusCode: 403);
      (api.data['system'] as Json)['demo_controls'] = false;
      (api.data['system'] as Json)['simulated'] = false;
      final controller = OipController(api,
          retryDelay: const Duration(milliseconds: 5));
      final running = controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.infrastructure.status,
          InfrastructureContextStatus.permissionDenied);
      expect(controller.snapshot, isNull);
      expect(controller.history, isEmpty);
      controller.dispose();
      await running;
    });

    test('Logout clears the authorized scope before an old resync returns',
        () async {
      final bootstrap = infrastructureFixture();
      final api = _SessionApi()..infrastructure = bootstrap;
      final controller = OipController(api);
      addTearDown(controller.dispose);
      await controller.resyncInfrastructure();
      controller.selectInfrastructure(
          const InfrastructureSelection.infrastructure('org-a', 'infra-a1'));
      final pending = Completer<InfrastructureBootstrap>();
      api.pendingBootstrap = pending;
      final resync = controller.resyncInfrastructure();
      await api.bootstrapRequested.future;

      await controller.logout();
      expect(controller.loginRequired, isTrue);
      expect(controller.infrastructure.ready, isFalse);
      expect(controller.infrastructure.hierarchy.infrastructures, isEmpty);
      expect(controller.infrastructure.selection.isUnified, isTrue);
      pending.complete(bootstrap);
      await resync;

      expect(controller.snapshot, isNull);
      expect(controller.infrastructure.ready, isFalse);
      expect(controller.history, isEmpty);
    });

    test('Stale session preflight cannot replace a newer authorized session',
        () async {
      final api = _SessionApi()..infrastructure = infrastructureFixture();
      final controller = OipController(api);
      addTearDown(controller.dispose);
      final pending = Completer<BrowserSession>();
      api.pendingSession = pending;
      final oldConnection = controller.start();
      api.pendingSession = null;
      final live = Completer<void>();
      controller.addListener(() {
        if (controller.connection == 'live' && !live.isCompleted) {
          live.complete();
        }
      });
      controller.reconnect();
      await live.future;

      pending.complete(BrowserSession.fromJson({
        'authenticated': false,
        'mode': 'local_operator_session',
      }));
      await oldConnection;

      expect(controller.connection, 'live');
      expect(controller.hasAuthorizedContext, isTrue);
      expect(controller.snapshot, isNotNull);
    });

    test('Identity denial during preflight discards retained tenant data',
        () async {
      final api = _SessionApi()..infrastructure = infrastructureFixture();
      final controller = OipController(api);
      addTearDown(controller.dispose);
      await controller.resyncInfrastructure();
      expect(controller.infrastructure.ready, isTrue);
      api.sessionFailure = const ApiFailure('denied',
          code: 'PERMISSION_DENIED', statusCode: 403);

      await controller.start();

      expect(controller.loginRequired, isTrue);
      expect(controller.infrastructure.ready, isFalse);
      expect(controller.snapshot, isNull);
      expect(controller.operationalSources, isEmpty);
    });

    test('Loss of the managed route cannot switch the shell to legacy demo',
        () async {
      final api = _SessionApi()..infrastructure = infrastructureFixture();
      final controller = OipController(api);
      addTearDown(controller.dispose);
      await controller.resyncInfrastructure();
      api.infrastructureFailure =
          const ApiFailure('route unavailable', statusCode: 404);

      await controller.start();

      expect(controller.connection, 'context-unsupported');
      expect(controller.infrastructure.principalIdentity, isNull);
      expect(controller.snapshot, isNull);
    });
  });

  group('OIP-009 selector and cross-module UI · marked fixture', () {
    Future<({FakeApi api, OipController controller})> bootstrap(
      WidgetTester tester, {
      Size size = const Size(1440, 900),
      InfrastructureBootstrap? fixture,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.binding.setSurfaceSize(size);
      final api = FakeApi()
        ..infrastructure = fixture ?? infrastructureFixture();
      final controller = OipController(api);
      await controller.resyncInfrastructure();
      await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pumpAndSettle();
      expect(controller.infrastructure.ready, isTrue);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await tester.binding.setSurfaceSize(null);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      return (api: api, controller: controller);
    }

    Future<void> navigate(WidgetTester tester, int index, double width) async {
      if (width < 1080) {
        await tester.tap(find.byKey(const Key('open-navigation')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(Key('nav-$index')));
      await tester.pumpAndSettle();
    }

    testWidgets('Unified summary switches the one global context directly',
        (tester) async {
      final harness = await bootstrap(tester);
      expect(find.byKey(const Key('unified-infrastructure-summary')),
          findsOneWidget);
      expect(find.text('Alle berechtigten Infrastrukturen'), findsWidgets);
      await tester.ensureVisible(
          find.byKey(const Key('unified-infrastructure-infra-a2')));
      await tester.tap(find.byKey(const Key('unified-infrastructure-infra-a2')));
      await tester.pumpAndSettle();
      expect(harness.controller.infrastructure.selection.infrastructureId,
          'infra-a2');
      expect(harness.controller.snapshot!.devices.single.id, 'device-a2');
      expect(find.byKey(const Key('unified-infrastructure-summary')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Searchable hierarchy keeps one selection across all six pages',
        (tester) async {
      final harness = await bootstrap(tester);
      for (final page in [0, 1, 2, 3, 4, 5]) {
        await navigate(tester, page, 1440);
        expect(find.byKey(const Key('infrastructure-context-selector')),
            findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('infrastructure-context-selector')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('infrastructure-context-search')), 'A2');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('context-option-infrastructure-infra-a2')),
          findsOneWidget);
      await tester.tap(
          find.byKey(const Key('context-option-infrastructure-infra-a2')));
      await tester.pumpAndSettle();
      for (final page in [0, 1, 2, 3, 4, 5]) {
        await navigate(tester, page, 1440);
        expect(harness.controller.infrastructure.selection.infrastructureId,
            'infra-a2');
        expect(find.textContaining('Infrastructure A2'), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('Source-less device remains visible in Site and Unified scopes',
        (tester) async {
      final harness = await bootstrap(tester);
      harness.controller.selectInfrastructure(const InfrastructureSelection.site(
          'org-a', 'infra-a1', 'site-a1-2'));
      await navigate(tester, 1, 1440);
      expect(find.byKey(const Key('device-device-a1-manual')), findsOneWidget);
      await tester.tap(find.byKey(const Key('device-device-a1-manual')));
      await tester.pumpAndSettle();
      expect(find.text('no_collector'), findsWidgets);
      expect(find.text('Organization A'), findsWidgets);
      expect(find.text('Site 2'), findsWidgets);
      harness.controller
          .selectInfrastructure(const InfrastructureSelection.unified());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-device-a1-manual')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Selector supports arrows, Enter and all required widths',
        (tester) async {
      for (final size in [
        const Size(320, 740),
        const Size(390, 844),
        const Size(768, 1024),
        const Size(1024, 900),
        const Size(1440, 900),
        const Size(1920, 1080),
      ]) {
        final harness = await bootstrap(tester, size: size);
        await tester.tap(
            find.byKey(const Key('infrastructure-context-selector')));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(harness.controller.infrastructure.selection.isUnified, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}

/// A client that carries the identity of the authorized session.
class _SessionApi extends FakeApi implements DeviceManagementApi {
  Completer<BrowserSession>? pendingSession;
  ApiFailure? sessionFailure;
  Completer<InfrastructureBootstrap>? pendingBootstrap;
  final bootstrapRequested = Completer<void>();

  @override
  Future<InfrastructureBootstrap> infrastructureBootstrap() async {
    final pending = pendingBootstrap;
    if (pending == null) return super.infrastructureBootstrap();
    if (!bootstrapRequested.isCompleted) bootstrapRequested.complete();
    return pending.future;
  }

  @override
  bool get managed => true;

  @override
  Future<BrowserSession> session() async {
    if (sessionFailure != null) throw sessionFailure!;
    final pending = pendingSession;
    if (pending != null) return pending.future;
    return BrowserSession.fromJson({
      'authenticated': true,
      'principal_id': 'fixture-operator',
      'csrf_token': null,
      'mode': 'local_operator_session',
    });
  }

  @override
  Future<BrowserSession> login(String code) async => session();

  @override
  Future<void> logout() async {}

  @override
  Future<List<HierarchyItem>> hierarchy(
          String level, Map<String, String> scope) async =>
      const [];

  @override
  Future<Json> inventory(String id) async => const {};

  @override
  Future<void> register(Json device) async {}

  @override
  Future<void> update(Json device, {required int expectedRevision}) async {}

  @override
  Future<void> archive(String id, {required int expectedRevision}) async {}

  @override
  Future<ConnectionResult> connection(
          {String? deviceId, String? planId}) async =>
      ConnectionResult.fromJson({'profiles': [], 'observations': []});

  @override
  Future<ConnectionResult> configure(Json action) async =>
      ConnectionResult.fromJson({'profiles': [], 'observations': []});

  @override
  Future<HistoryPage> observationHistory(
          {required String deviceId, String? cursor, int limit = 20}) async =>
      HistoryPage.fromJson({'items': [], 'truncated': false});
}
