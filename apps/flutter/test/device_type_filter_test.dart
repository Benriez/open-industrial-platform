import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/features/devices/device_inventory.dart';
import 'package:oip_dashboard/features/devices/device_session.dart';
import 'package:oip_dashboard/models/contracts.dart';

import 'support.dart';

/// The type filter of the inventory.
///
/// The filter shows the **word** of the type that the Core holds, and the
/// entry that keeps every type is not a type at all: the surface must not
/// paint that choice as a type that the client failed to know.
void main() {
  testWidgets('the choice that keeps every type is not an unknown type',
      (tester) async {
    final session = DevicesWorkspaceSession();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          child: DeviceFilterBar(
            snapshot: Snapshot.fromJson(fixture()),
            session: session,
            searchController: TextEditingController(),
            searchFocus: FocusNode(),
            changed: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final filter = find.byKey(const Key('device-type-filter'));
    expect(filter, findsOneWidget);
    expect(find.descendant(of: filter, matching: find.text('Alle')),
        findsOneWidget);
    expect(
        find.descendant(
            of: filter, matching: find.textContaining('Unbekannter Gerätetyp')),
        findsNothing);
  });
}
