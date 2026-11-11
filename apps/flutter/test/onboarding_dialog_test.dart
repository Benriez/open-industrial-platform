import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/features/device_onboarding.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/models/history.dart';
import 'package:oip_dashboard/models/onboarding.dart';
import 'package:oip_dashboard/services/api.dart';
import 'support.dart';

class InventoryOnlyApi extends FakeApi implements DeviceManagementApi {
  Json? saved;
  @override
  bool get managed => true;
  @override
  Future<BrowserSession> session() async => BrowserSession.fromJson({
        'authenticated': true,
        'principal_id': 'server-bound',
        'mode': 'local_operator_session'
      });
  @override
  Future<BrowserSession> login(String code) => session();
  @override
  Future<void> logout() async {}
  @override
  Future<List<HierarchyItem>> hierarchy(
          String level, Map<String, String> scope) async =>
      [
        HierarchyItem.fromJson({'id': level, 'name': level})
      ];
  @override
  Future<Json> inventory(String id) async => throw UnimplementedError();
  @override
  Future<void> register(Json device) async {
    saved = device;
  }

  @override
  Future<void> update(Json device, {required int expectedRevision}) async {
    saved = device;
  }

  @override
  Future<void> archive(String id, {required int expectedRevision}) async {}

  @override
  Future<ConnectionResult> connection(
          {String? deviceId, String? planId}) async =>
      ConnectionResult.fromJson({
        'profiles': [],
        'plan': null,
        'connection': null,
        'last_attempt': null
      });
  @override
  Future<ConnectionResult> configure(Json action) async =>
      throw StateError('Manual registration must never execute SSH');

  @override
  Future<HistoryPage> observationHistory(
          {required String deviceId, String? cursor, int limit = 20}) async =>
      HistoryPage.fromJson({
        'items': <dynamic>[],
        'truncated': false,
        'next_cursor': null,
        'missing_evidence': <String>[],
        'time_semantics': '',
      });
}

void main() {
  testWidgets('The type of the device is named with the shared vocabulary',
      (tester) async {
    final api = InventoryOnlyApi();
    final controller = OipController(api);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DeviceOnboarding(controller: controller))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('onboarding-type')));
    await tester.tap(find.byKey(const Key('onboarding-type')));
    await tester.pumpAndSettle();
    // The word of the type has one owner: the onboarding dialog does not
    // paint the identifier of the Core as if it were a word of the surface.
    expect(find.text('Einzelplatine'), findsWidgets);
    expect(find.text('Netzwerkgerät'), findsWidgets);
    expect(find.text('single_board_computer'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
      'Manual inventory registration preserves entered identity and requires consent, without SSH',
      (tester) async {
    final api = InventoryOnlyApi();
    final controller = OipController(api);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DeviceOnboarding(controller: controller))));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('device-name')), 'Operator-entered device');
    await tester.tap(find.byKey(const Key('onboarding-scope-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SSH — Linux / macOS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nur Inventar, keine Verbindung').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventarregistrierung prüfen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nur im Inventar registrieren'));
    await tester.pumpAndSettle();
    expect(api.saved, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nur im Inventar registrieren'));
    await tester.pumpAndSettle();
    expect(api.saved!['display_name'], 'Operator-entered device');
    expect(api.saved!['site_id'], 'sites');
    expect(api.saved!['id'], matches(RegExp(r'^[a-f0-9-]{36}$')));
    expect(find.textContaining('Keine Verbindung'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
