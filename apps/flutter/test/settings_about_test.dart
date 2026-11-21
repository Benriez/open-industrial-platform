import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/features/version_changelog.dart';
import 'package:oip_dashboard/models/app_metadata.dart';
import 'package:oip_dashboard/services/api.dart';

// Reuses the fixture harness of the Settings workstation suite: it wires a
// contract fixture controller, logs the shell in and opens the
// Core-Einstellungen section, where an authorized operator also sees About.
import 'settings_workstation_test.dart'
    show FixtureSettingsApi, bootstrapSettings;

void main() {
  testWidgets('The Settings workstation shows the client identity (About)',
      (tester) async {
    await bootstrapSettings(tester);

    final header = find.text('Über die App');
    expect(header, findsOneWidget);
    // The About block sits below the settings form; bring it into view before
    // asserting its contents.
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();

    expect(find.text('Über die App'), findsOneWidget);
    expect(find.text('CLIENT-IDENTITÄT'), findsOneWidget);
    // Version and build are exposed with stable keys and mirror the manifest.
    expect(find.byKey(const Key('settings-about-version')), findsOneWidget);
    expect(find.text(kOipApplication.version), findsOneWidget);
    expect(find.byKey(const Key('settings-about-build')), findsOneWidget);
    expect(find.byKey(const Key('settings-about-shell')), findsOneWidget);
    // The software license is attributed for store-ready provenance.
    expect(find.byKey(const Key('settings-about-license')), findsOneWidget);
    expect(find.text('Apache-2.0'), findsOneWidget);
    // The local-first data disclosure is rendered for the operator.
    expect(find.text('Lokal · keine Telemetrie'), findsOneWidget);
    // The rendered identity mirrors the package manifest exactly; the version
    // and build are the single source of truth, not invented values.
    final declaration = File('pubspec.yaml')
        .readAsLinesSync()
        .singleWhere((line) => line.startsWith('version:'))
        .substring('version:'.length)
        .trim();
    expect('${kOipApplication.version}+${kOipApplication.build}', declaration);
    expect(kOipApplication.license, 'Apache-2.0');
    expect(OipApplicationInfo.manifestDeclaration, declaration);
    expect(tester.takeException(), isNull);
  });

  testWidgets('The version link opens a changelog with the installed release',
      (tester) async {
    await bootstrapSettings(tester);

    await tester.tap(find.byKey(const Key('sidebar-app-version')));
    await tester.pumpAndSettle();

    final dialog = find.byKey(const Key('version-changelog-dialog'));
    expect(dialog, findsOneWidget);
    expect(
        find.text(
            'Version ${kOipApplication.version} · Build ${kOipApplication.build}'),
        findsOneWidget);
    expect(find.text('INSTALLIERT'), findsOneWidget);
    final historicalVersion = find.text('Version 0.3.31 · Build 34');
    await tester.scrollUntilVisible(
      historicalVersion,
      150,
      scrollable:
          find.descendant(of: dialog, matching: find.byType(Scrollable)),
    );
    expect(historicalVersion, findsOneWidget);
    expect(
      find.textContaining(
          'bestätigte LAN-Nachbarn zwischen registrierten Geräten'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('The direct macOS About page can manually check for OTA updates',
      (tester) async {
    const channel = MethodChannel('org.openindustrial.oip/ota');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'isAvailable' => true,
        'checkForUpdates' => 'current',
        _ => null,
      };
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await bootstrapSettings(tester);
    final button = find.byKey(const Key('settings-check-for-updates'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    expect(find.text('Nach Updates suchen'), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(calls, ['isAvailable', 'checkForUpdates']);
    expect(find.text('Du verwendest die neueste Version.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('The changelog can check for updates without a Core session',
      (tester) async {
    const channel = MethodChannel('org.openindustrial.oip/ota');
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'isAvailable' ? true : 'deferred';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showVersionChangelog(context),
            child: const Text('Versionsübersicht'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Versionsübersicht'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nach Updates suchen'));
    await tester.pumpAndSettle();

    expect(calls, ['isAvailable', 'checkForUpdates']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A Management denial links to the local OTA controls',
      (tester) async {
    const channel = MethodChannel('org.openindustrial.oip/ota');
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'isAvailable' ? true : 'current';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final api = FixtureSettingsApi()
      ..settingsFailure = const ApiFailure('Denied',
          code: 'PERMISSION_DENIED', statusCode: 403);
    await bootstrapSettings(tester, api: api);
    expect(find.text('Management-Zugriff nicht autorisiert'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-open-local-versions')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-about-version')), findsOneWidget);
    expect(find.text('Management-Zugriff nicht autorisiert'), findsNothing);
    await tester.tap(find.byKey(const Key('settings-check-for-updates')));
    await tester.pumpAndSettle();
    expect(calls, ['isAvailable', 'checkForUpdates']);
    expect(api.settingsCalls, hasLength(1));
    expect(api.managementCalls, isEmpty);
  });
}
