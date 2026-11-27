import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oip_dashboard/features/settings/license_status.dart';
import 'package:oip_dashboard/l10n/oip_strings.dart';
import 'package:oip_dashboard/models/license.dart';
import 'package:oip_dashboard/services/api.dart';

const _artifact = ' { "v": 1, "kid": "fixture", "payload": "Müster", '
    '"signature": "signature" }\n';

const _pending = LicenseStatus(
  proofState: LicenseProofState.missing,
  commercial: LicenseEntitlement.unconfirmed,
  support: LicenseEntitlement.unconfirmed,
  canManage: true,
);

const _installed = LicenseStatus(
  proofState: LicenseProofState.verified,
  commercial: LicenseEntitlement.active,
  support: LicenseEntitlement.ended,
  licenseId: 'id-1',
  licensee: 'Muster GmbH',
  organization: 'Werk A',
  canManage: false,
);

class _LicenseApi implements LicenseManagementApi {
  _LicenseApi(this.current);

  LicenseStatus current;
  bool denied = false;
  int reviews = 0;
  final confirmations = <String>[];

  @override
  Future<LicenseStatus> licenseStatus() async {
    if (denied) throw const ApiFailure('Permission denied', statusCode: 403);
    return current;
  }

  @override
  Future<LicensePreview> previewLicense(LicenseProof proof) async {
    reviews++;
    expect(proof.artifact, _artifact);
    return const LicensePreview(_installed, 'confirmation');
  }

  @override
  Future<LicenseStatus> applyLicense(String confirmation) async {
    confirmations.add(confirmation);
    return current = _installed;
  }
}

Future<void> _mount(WidgetTester tester, _LicenseApi api,
    {Locale? locale, Future<String?> Function(int)? filePicker}) async {
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: oipLocales,
    localizationsDelegates: const [
      OipStrings.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: Scaffold(
      body: SingleChildScrollView(
          child: InstallationLicense(api: api, filePicker: filePicker)),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, String key) async {
  final button = find.byKey(Key(key));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('license cannot be applied before verifying and confirming',
      (tester) async {
    final api = _LicenseApi(_pending);
    await _mount(tester, api, locale: const Locale('de'));
    expect(find.text('Kein Nachweis gespeichert'), findsOneWidget);
    await _press(tester, 'enter-license-proof');
    await _press(tester, 'preview-license');
    expect(api.reviews, 0);
    expect(find.text('Füge einen gültigen JSON-Lizenznachweis ein.'),
        findsOneWidget);

    final input = find.byKey(const Key('license-proof-input'));
    await tester.enterText(input, List.filled(2731, '€').join());
    await _press(tester, 'preview-license');
    expect(api.reviews, 0);
    expect(find.text('Die Lizenzdatei darf höchstens 8 KB groß sein.'),
        findsOneWidget);

    await tester.enterText(input, _artifact);
    await _press(tester, 'preview-license');
    expect(api.reviews, 1);
    expect(api.confirmations, isEmpty);
    expect(find.text('Muster GmbH'), findsOneWidget);
    expect(find.text('Werk A'), findsOneWidget);
    expect(find.text('Aktiv'), findsOneWidget);
    expect(find.text('Beendet'), findsOneWidget);
    expect(find.byKey(const Key('license-proof-input')), findsNothing);

    await _press(tester, 'confirm-license');
    expect(api.confirmations, ['confirmation']);
    expect(find.text('Lizenznachweis gespeichert.'), findsOneWidget);
    expect(find.text('Nachweis geprüft'), findsOneWidget);
    expect(find.text('Muster GmbH'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('readers see distinct English entitlements without import',
      (tester) async {
    final api = _LicenseApi(_installed);
    await _mount(tester, api, locale: const Locale('en'));
    expect(find.text('Licence and support'), findsOneWidget);
    expect(find.text('Commercial use'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Support entitlement'), findsOneWidget);
    expect(find.text('Ended'), findsOneWidget);
    expect(find.byKey(const Key('enter-license-proof')), findsNothing);

    api.denied = true;
    await tester.tap(find.text('Refresh status'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('installation-license')), findsNothing);
    expect(find.text('Muster GmbH'), findsNothing);
  });

  testWidgets('choosing a bounded local file opens only a preview',
      (tester) async {
    final api = _LicenseApi(_pending);
    var picked = 0;
    await _mount(tester, api, locale: const Locale('de'),
        filePicker: (maxBytes) async {
      expect(maxBytes, 8192);
      switch (++picked) {
        case 1:
          return null;
        case 2:
          throw RangeError('Too large');
        default:
          return _artifact;
      }
    });
    await _press(tester, 'enter-license-proof');
    await _press(tester, 'choose-license-file');
    expect(api.reviews, 0);
    await _press(tester, 'choose-license-file');
    expect(find.text('Die Lizenzdatei darf höchstens 8 KB groß sein.'),
        findsOneWidget);
    expect(api.reviews, 0);
    await _press(tester, 'choose-license-file');
    expect(api.reviews, 1);
    expect(api.confirmations, isEmpty);
    expect(find.text('Muster GmbH'), findsOneWidget);
    await _press(tester, 'confirm-license');
    expect(api.confirmations, ['confirmation']);
  });

  testWidgets('a verified licence without support shows that explicitly',
      (tester) async {
    final api = _LicenseApi(LicenseStatus.fromJson({
      'proof_state': 'verified',
      'commercial': 'active',
      'support': 'not_granted',
      'can_manage': false,
    }));
    await _mount(tester, api, locale: const Locale('de'));
    expect(find.text('Nachweis geprüft'), findsOneWidget);
    expect(find.text('Aktiv'), findsOneWidget);
    expect(find.text('Nicht enthalten'), findsOneWidget);
    expect(find.text('Unbestätigt'), findsNothing);
  });

  test('license HTTP contracts reuse authenticated session and CSRF', () async {
    const result = {
      'proof_state': 'verified',
      'commercial': 'active',
      'support': 'ended',
      'license_id': 'id-1',
      'licensee': 'Muster GmbH',
      'organization': 'Werk A',
      'can_manage': true,
    };
    final calls = <String>[];
    final api = RestApi(Uri.parse('http://127.0.0.1:8080'),
        client: MockClient((request) async {
      final path = request.url.path;
      calls.add('${request.method} $path');
      if (path == '/api/v2/browser/login') {
        return http.Response(
            jsonEncode({
              'mode': 'authenticated',
              'authenticated': true,
              'csrf_token': 'session-proof',
            }),
            200);
      }
      expect(request.headers['x-oip-csrf'], 'session-proof');
      if (path.endsWith('/preview')) {
        expect(jsonDecode(request.body), {
          'proof': {'artifact': _artifact},
        });
        return http.Response(
            jsonEncode({
              'status': result,
              'confirmation': 'confirmation',
            }),
            200);
      }
      if (path.endsWith('/apply')) {
        expect(jsonDecode(request.body), {'confirmation': 'confirmation'});
      }
      return http.Response(jsonEncode(result), 200);
    }));
    addTearDown(api.close);

    await api.login('one-time-code');
    expect((await api.licenseStatus()).support, LicenseEntitlement.ended);
    final preview = await api.previewLicense(const LicenseProof(_artifact));
    expect(preview.status.licensee, 'Muster GmbH');
    expect((await api.applyLicense(preview.confirmation)).commercial,
        LicenseEntitlement.active);
    expect(calls, [
      'POST /api/v2/browser/login',
      'GET /api/v2/license',
      'POST /api/v2/license/preview',
      'POST /api/v2/license/apply',
    ]);
  });
}
