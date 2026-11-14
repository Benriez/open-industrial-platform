import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/features/devices/device_administration.dart';
import 'package:oip_dashboard/models/history.dart';
import 'package:oip_dashboard/models/infrastructure.dart';
import 'package:oip_dashboard/models/onboarding.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/services/api.dart';

import 'infrastructure_support.dart';
import 'support.dart';

/// The administration of a device: the update and the archive.
///
/// The Core owns the inventory. Both writes carry the revision of the device
/// as their guard, so a stale revision is refused and the refusal of the Core
/// is shown instead of a friendly invention.
class _AdminApi extends FakeApi implements DeviceManagementApi {
  final List<Map<String, Object?>> updates = [];
  final List<Map<String, Object?>> archives = [];
  Object? failure;

  @override
  bool get managed => true;

  @override
  Future<void> update(Json device, {required int expectedRevision}) async {
    if (failure != null) throw failure!;
    updates.add({...device, 'expected_revision': expectedRevision});
  }

  @override
  Future<void> archive(String id, {required int expectedRevision}) async {
    if (failure != null) throw failure!;
    archives.add({'id': id, 'expected_revision': expectedRevision});
  }

  @override
  Future<void> register(Json device) async {}

  @override
  Future<BrowserSession> session() async => BrowserSession.fromJson({
        'authenticated': true,
        'principal_id': 'fixture-operator',
        'csrf_token': null,
        'mode': 'local_operator_session',
      });

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

void main() {
  late _AdminApi api;
  late OipController controller;

  setUp(() async {
    api = _AdminApi()..infrastructure = infrastructureFixture();
    controller = OipController(api);
    await controller.resyncInfrastructure();
  });

  tearDown(() => controller.dispose());

  Future<void> openDevice(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.tap(find.byKey(const Key('nav-1')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.tap(find.byKey(const Key('device-device-a1')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('The device administration shows the revision it works on',
      (tester) async {
    await openDevice(tester);
    expect(find.byKey(const Key('device-administration')), findsOneWidget);
    expect(find.textContaining('REVISION 1'), findsOneWidget);
  });

  testWidgets('The update sends the device with the expected revision',
      (tester) async {
    await openDevice(tester);
    await tester.ensureVisible(find.byKey(const Key('device-administration-name')));
    await tester.enterText(
        find.byKey(const Key('device-administration-name')), 'Pump A1 neu');
    await tester.ensureVisible(
        find.byKey(const Key('device-administration-update')));
    await tester.tap(find.byKey(const Key('device-administration-update')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(api.updates, hasLength(1));
    expect(api.updates.single['id'], 'device-a1');
    expect(api.updates.single['display_name'], 'Pump A1 neu');
    expect(api.updates.single['device_type'], 'sensor');
    expect(api.updates.single['site_id'], 'site-a1-1');
    // An update is a full replacement: the metadata of the record is sent
    // back unchanged.
    expect(api.updates.single['metadata'], isA<Map<String, dynamic>>());
    // The guard of the write is the revision the surface worked on.
    expect(api.updates.single['expected_revision'], 1);
  });

  testWidgets('The administration names the type with the shared word',
      (tester) async {
    await openDevice(tester);
    await tester.ensureVisible(
        find.byKey(const Key('device-administration-type')));
    await tester.tap(find.byKey(const Key('device-administration-type')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    // The word of a type has one owner: the administration offers the same
    // word as the identity panel and the filter, and never a second
    // vocabulary of its own.
    expect(find.text('Einzelplatine'), findsWidgets);
    expect(find.text('Netzwerkgerät'), findsWidgets);
    expect(find.text('Single board'), findsNothing);
  });

  testWidgets('A type that the client does not know is not rewritten',
      (tester) async {
    const device = InventoryDevice(
      id: 'device-a1',
      name: 'Pump A1',
      // A type that the Core of today does not deliver: the administration
      // must not turn it into another type behind the back of the operator.
      type: 'quantum_processor',
      siteId: 'site-a1-1',
      organizationId: 'org-a',
      infrastructureId: 'infra-a1',
      registration: 'registered',
      origin: 'manual_operator',
      connectivity: 'unknown',
      telemetry: 'no_collector',
      health: 'not_evaluated',
      sourceIds: [],
      revision: 1,
      metadata: {},
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DeviceAdministration(
              device: device, api: api, onChanged: () {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // The type that the client does not know is shown honestly.
    expect(find.text('Unbekannter Gerätetyp · quantum_processor'),
        findsWidgets);
    await tester.ensureVisible(
        find.byKey(const Key('device-administration-type')));
    await tester.tap(find.byKey(const Key('device-administration-type')));
    await tester.pumpAndSettle();
    // The type stays an entry of the list and is named honestly.
    expect(find.text('Unbekannter Gerätetyp · quantum_processor'),
        findsWidgets);
    // The menu is closed again, so that the write can be driven.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
        find.byKey(const Key('device-administration-update')));
    await tester.tap(find.byKey(const Key('device-administration-update')));
    await tester.pumpAndSettle();
    expect(api.updates.single['device_type'], 'quantum_processor');
  });

  testWidgets('The note of the device is written and the metadata survives',
      (tester) async {
    await openDevice(tester);
    await tester.ensureVisible(
        find.byKey(const Key('device-administration-note')));
    await tester.enterText(
        find.byKey(const Key('device-administration-note')),
        'Nur lesbar: die Lichter brauchen ein Anwendungs-Token des Betreibers.');
    await tester.ensureVisible(
        find.byKey(const Key('device-administration-update')));
    await tester.tap(find.byKey(const Key('device-administration-update')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(api.updates, hasLength(1));
    final metadata = api.updates.single['metadata'] as Map<String, dynamic>;
    expect(metadata['notes'],
        'Nur lesbar: die Lichter brauchen ein Anwendungs-Token des Betreibers.');
    // The Core replaces the metadata as a whole: the merge of the client keeps
    // the fields that the operator did not touch.
    expect(metadata.keys, containsAll(['physical_location']));
  });

  testWidgets('The archive is named as the offline operation it is',
      (tester) async {    await openDevice(tester);
    // The managed session of the Core refuses an archive with
    // OFFLINE_ARCHIVE_REQUIRED: the archive is an offline operation. The
    // surface therefore states the procedure and never offers a write that
    // the Core would refuse.
    expect(find.text('Archivierung ist ein Offline-Vorgang'), findsOneWidget);
    expect(find.textContaining('--inventory-plan'), findsOneWidget);
    expect(api.archives, isEmpty);
  });

  testWidgets('A refusal of the Core is shown and nothing is written',
      (tester) async {
    await openDevice(tester);
    api.failure = const ApiFailure(
      'Die Revision des Geräts ist veraltet',
      code: 'INVENTORY_REVISION_MISMATCH',
      statusCode: 409,
    );
    await tester.ensureVisible(
        find.byKey(const Key('device-administration-update')));
    await tester.tap(find.byKey(const Key('device-administration-update')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(api.updates, isEmpty);
    expect(find.text('Änderung nicht angenommen'), findsOneWidget);
    expect(find.textContaining('Revision'), findsWidgets);
  });
}
