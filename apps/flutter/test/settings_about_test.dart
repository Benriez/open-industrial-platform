import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/models/app_metadata.dart';

// Reuses the fixture harness of the Settings workstation suite: it wires a
// contract fixture controller, logs the shell in and opens the Settings
// workstation, whose default section is "Application" — where the About block
// lives. Only the bootstrap helper is imported so this file keeps its own
// main().
import 'settings_workstation_test.dart' show bootstrapSettings;

void main() {
  testWidgets('The Settings workstation shows the client identity (About)',
      (tester) async {
    // The Application settings section is the default when Settings opens.
    await bootstrapSettings(tester);

    final header = find.text('About');
    expect(header, findsOneWidget);
    // The About block sits below the settings form; bring it into view before
    // asserting its contents.
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();

    expect(find.text('About'), findsOneWidget);
    expect(find.text('CLIENT IDENTITY'), findsOneWidget);
    // Version and build are exposed with stable keys and mirror the manifest.
    expect(find.byKey(const Key('settings-about-version')), findsOneWidget);
    expect(find.text('0.3.0'), findsOneWidget);
    expect(find.byKey(const Key('settings-about-build')), findsOneWidget);
    expect(find.byKey(const Key('settings-about-shell')), findsOneWidget);
    // The software license is attributed for store-ready provenance.
    expect(find.byKey(const Key('settings-about-license')), findsOneWidget);
    expect(find.text('Apache-2.0'), findsOneWidget);
    // The local-first data disclosure is rendered for the operator.
    expect(find.text('Lokal · keine Telemetrie'), findsOneWidget);
    // The rendered identity mirrors the package manifest exactly; the version
    // and build are the single source of truth, not invented values.
    expect(kOipApplication.version, '0.3.4');
    expect(kOipApplication.build, '7');
    expect(kOipApplication.license, 'Apache-2.0');
    expect(OipApplicationInfo.manifestDeclaration, '0.3.4+7');
    expect(tester.takeException(), isNull);
  });
}
