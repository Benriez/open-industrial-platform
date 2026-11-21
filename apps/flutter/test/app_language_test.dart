import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/l10n/oip_strings.dart';
import 'package:oip_dashboard/services/api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canonical_ui_gate_test.dart' show managedShellController, pumpShell;
import 'support.dart';

void main() {
  testWidgets('switches both directions and restores the local choice',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = managedShellController();
    await controller.resyncInfrastructure();
    addTearDown(controller.dispose);

    Future<void> mount() async {
      await pumpShell(tester, controller);
      await tester.tap(find.byKey(const Key('nav-5')));
      await tester.pumpAndSettle();
    }

    Future<void> select(String language) async {
      await tester.tap(find.byKey(const Key('oip-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(language).last);
      await tester.pumpAndSettle();
    }

    await mount();
    expect(find.text('Einstellungen').first, findsOneWidget);
    await select('English');
    expect(find.text('Settings').first, findsOneWidget);
    expect(find.text('Devices & Services'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Inspect effective values, editability, and permissions'),
        findsOneWidget);
    expect(find.text('Your language choice is saved on this device.'),
        findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('oip-language'),
        'en');

    await tester.pumpWidget(const SizedBox());
    await mount();
    expect(find.text('Settings').first, findsOneWidget);
    await select('Deutsch');
    expect(find.text('Einstellungen').first, findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('oip-language'),
        'de');
  });

  testWidgets('sign-in uses the saved locale before authentication',
      (tester) async {
    SharedPreferences.setMockInitialValues({'oip-language': 'en'});
    final data = fixture();
    (data['system'] as Map<String, dynamic>)['simulated'] = false;
    final api = FakeApi()
      ..data = data
      ..infrastructureFailure = const ApiFailure(
        'Operator session required.',
        code: 'PERMISSION_DENIED',
        statusCode: 403,
      );
    final controller =
        OipController(api, retryDelay: const Duration(milliseconds: 1));
    addTearDown(controller.dispose);

    final running = controller.start();
    for (var i = 0; i < 50 && !controller.loginRequired; i++) {
      await tester.pump(const Duration(milliseconds: 2));
    }
    expect(controller.loginRequired, isTrue);
    await running;

    await pumpShell(tester, controller);
    expect(find.text('One-time code'), findsOneWidget);
    await tester.tap(find.byKey(const Key('oip-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deutsch').last);
    await tester.pumpAndSettle();
    expect(find.text('Einmalcode'), findsOneWidget);
    expect(controller.loginRequired, isTrue);
  });

  test('interpolation preserves operator and equipment identifiers', () {
    const strings = OipStrings(Locale('en'));
    expect(strings.message('Navigation {0}', ['Geräte & Dienste']),
        'Navigation Geräte & Dienste');
    expect(strings.message('Site {0} · {1}', ['{1}', 'raw-node-22']),
        'Site {1} · raw-node-22');
  });
}
