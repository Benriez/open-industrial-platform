import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/features/settings/paired_device_sign_ins.dart';
import 'package:oip_dashboard/services/api.dart';

class DeviceSignInsFixture implements PairedDeviceManagementApi {
  final devices = [
    const PairedDeviceSignIn('office-mac', 'Office Mac', false),
    const PairedDeviceSignIn('local-mac', 'Local Mac', true),
  ];

  @override
  Future<List<PairedDeviceSignIn>> pairedDeviceSignIns() async =>
      List.of(devices);

  @override
  Future<void> renameDeviceSignIn(String id, String label) async {
    final index = devices.indexWhere((device) => device.id == id);
    devices[index] = PairedDeviceSignIn(id, label, devices[index].current);
  }

  @override
  Future<bool> revokeDeviceSignIn(String id) async {
    final device = devices.singleWhere((device) => device.id == id);
    devices.remove(device);
    return device.current;
  }
}

void main() {
  testWidgets('operators can name and revoke only the chosen device sign-in',
      (tester) async {
    final api = DeviceSignInsFixture();
    var signedOut = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PairedDeviceSignIns(
          api: api,
          onCurrentRevoked: () => signedOut = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final office = find.byKey(const ValueKey('office-mac'));
    final local = find.byKey(const ValueKey('local-mac'));
    Finder action(Finder row, IconData icon) =>
        find.descendant(of: row, matching: find.byIcon(icon));

    await tester.tap(action(office, Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('sign-in-device-name')), 'Werkstatt');
    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Werkstatt'), findsOneWidget);

    await tester.tap(action(office, Icons.block_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Abbrechen'));
    await tester.pumpAndSettle();
    expect(office, findsOneWidget);

    Future<void> revoke(Finder row) async {
      await tester.tap(action(row, Icons.block_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-revoke-device-sign-in')));
      await tester.pumpAndSettle();
    }

    await revoke(office);
    expect(office, findsNothing);
    expect(local, findsOneWidget);
    expect(signedOut, isFalse);

    await revoke(local);
    expect(signedOut, isTrue);
  });
}
