import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/features/settings.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/services/api.dart';

import 'support.dart';

class FixtureSettingsApi extends FakeApi {
  FixtureSettingsApi(
      {this.contextName = 'platform',
      this.delay = Duration.zero,
      this.statusOverride = const {}});
  final String contextName;
  /// The states the Core answers, if a test wants to change them. The
  /// negative control of the navigation needs an answer that differs from
  /// the usual one.
  final Map<String, String> statusOverride;
  final managementCalls = <String>[];
  final settingsCalls = <String>[];
  final managementFailures = <String, Object>{};
  Object? settingsFailure;
  Duration delay;
  int cancelCalls = 0;

  Json _read(String name) =>
      jsonDecode(File('test/fixtures/settings/$contextName/$name.json')
          .readAsStringSync()) as Json;

  @override
  Future<SettingsSnapshot> settings({
    String scope = 'platform',
    String? scopeId,
    String? key,
    bool catalog = false,
  }) async {
    settingsCalls.add('$scope/$scopeId/$key/$catalog');
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (settingsFailure != null) throw settingsFailure!;
    if (contextName != 'platform') {
      throw const ApiFailure('Settings capability is not authorized',
          code: 'PERMISSION_DENIED', statusCode: 403);
    }
    final data = _read(catalog ? 'settings-catalog' : 'settings-platform');
    if (statusOverride.isNotEmpty) {
      for (final category in (data['categories'] as List).cast<Json>()) {
        final replacement = statusOverride[category['category']];
        if (replacement != null) category['status'] = replacement;
      }
    }
    if (key != null) {
      data['definitions'] = (data['definitions'] as List)
          .where((item) => (item as Json)['key'] == key)
          .toList();
      data['settings'] = (data['settings'] as List)
          .where((item) => (item as Json)['key'] == key)
          .toList();
    }
    return SettingsSnapshot.fromJson(data,
        origin: SettingsDataOrigin.contractFixture);
  }

  @override
  Future<ManagementReport> management(String section) async {
    managementCalls.add(section);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final failure = managementFailures[section];
    if (failure != null) throw failure;
    final data = _read('management-${section.replaceAll('_', '-')}');
    return ManagementReport.fromJson(data,
        origin: SettingsDataOrigin.contractFixture);
  }

  @override
  void cancelSettingsRequests() => cancelCalls++;
}

Future<({FixtureSettingsApi api, OipController controller})> bootstrapSettings(
  WidgetTester tester, {
  Size size = const Size(1440, 1000),
  FixtureSettingsApi? api,
  bool withSnapshot = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  final client = api ?? FixtureSettingsApi();
  final controller = OipController(client);
  if (withSnapshot) controller.snapshot = Snapshot.fromJson(client.data);
  // Avoid the indefinite connecting spinner; data availability is expressed by
  // the snapshot itself, not by a fabricated connected state.
  controller.connection = 'live';
  await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
  if (withSnapshot) {
    await tester.pumpAndSettle();
  } else {
    // The shell shows an indeterminate startup spinner while no snapshot is
    // available. Pump deterministically until Settings is selected.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (size.width < 1080) {
    await tester.tap(find.byKey(const Key('open-navigation')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('nav-5')));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.binding.setSurfaceSize(null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  return (api: client, controller: controller);
}

Future<void> category(WidgetTester tester, SettingsCategory value) async {
  await tester
      .ensureVisible(find.byKey(Key('settings-category-${value.name}')));
  await tester.tap(find.byKey(Key('settings-category-${value.name}')));
  await tester.pumpAndSettle();
}

Future<void> section(WidgetTester tester, SettingsSection value) async {
  var target = find.byKey(Key('settings-section-${value.name}'));
  if (target.evaluate().isEmpty) {
    final chip = find.byKey(const Key('settings-mobile-navigation'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    target = find.byKey(Key('settings-section-${value.name}'));
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('The navigation names the status of the category of the Core',
      (tester) async {
    await bootstrapSettings(tester);

    // The Core states that the General category is administered offline and
    // that the other categories are only read. The navigation shows the answer
    // of the Core, not a guess of the client.
    expect(find.text('CORE · Nur offline administrierbar'), findsOneWidget);
    expect(find.textContaining('CORE · '), findsOneWidget);

    await category(tester, SettingsCategory.mcpAgents);
    // The category change reloads the settings of the Core; the navigation
    // shows its answer when the answer is there.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('CORE · Nur lesend'), findsOneWidget);

    await category(tester, SettingsCategory.dataStorage);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('CORE · Nur lesend'), findsOneWidget);
  });

  testWidgets('The navigation follows the answer of the Core, not a table of the client',
      (tester) async {
    // The negative control: the Core answers that the General category is
    // only read — the opposite of the usual answer. A navigation that showed
    // a table of its own would show the wrong word here.
    await bootstrapSettings(
        tester,
        api: FixtureSettingsApi(
            statusOverride: const {'general': 'read_only'}));

    expect(find.text('CORE · Nur lesend'), findsOneWidget);
    expect(find.text('CORE · Nur offline administrierbar'), findsNothing);
  });

  testWidgets('A state that the client does not know is named, never shown as the wire name',
      (tester) async {
    // The contract of the settings requires that the states are distinguished
    // in the words of the surface; the wire name of an unknown state belongs
    // to the contract of the Core and not to the operator.
    await bootstrapSettings(
        tester,
        api: FixtureSettingsApi(
            statusOverride: const {'general': 'requires_restart'}));

    expect(find.text('CORE · Status unbekannt'), findsOneWidget);
    // The wire name of the state must not be the word of the surface. The
    // text of the panel may mention the name of a state of another subject.
    expect(find.textContaining('CORE · requires_restart'), findsNothing);
  });

  testWidgets('A all seven categories open with functional default sections',
      (tester) async {
    await bootstrapSettings(tester);
    for (final value in SettingsCategory.values) {
      await category(tester, value);
      expect(find.byKey(const Key('settings-workspace')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: value.name);
    }
  });

  testWidgets('B exactly three real Core settings and honest offline state',
      (tester) async {
    await bootstrapSettings(tester);
    for (final key in [
      'instance_name',
      'instance_description',
      'history_page_size',
    ]) {
      expect(find.byKey(Key('settings-setting-$key')), findsOneWidget);
    }
    expect(find.byKey(const Key('settings-setting-theme')), findsNothing);
    expect(find.text('Open Industrial Platform'), findsWidgets);
    expect(find.text('OFFLINE ADMINISTRATION REQUIRED'), findsWidgets);
    expect(find.textContaining('active_startup_snapshot'), findsWidgets);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Apply'), findsNothing);
  });

  testWidgets(
      'Setting selection exposes revision, validation and apply details',
      (tester) async {
    await bootstrapSettings(tester);
    final row = find.byKey(const Key('settings-setting-history_page_size'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    final inspectorScroll = find.descendant(
        of: find.byKey(const Key('settings-inspector')),
        matching: find.byType(Scrollable));
    await tester.drag(inspectorScroll.first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('4..100 inclusive'), findsOneWidget);
    expect(find.text('exclusive_local_operator_cli'), findsOneWidget);
    expect(find.text('built_in_default'), findsWidgets);
    expect(find.text('effective_revision'), findsNothing);
  });

  testWidgets(
      'MCP overview uses real transport, registry and capability counts',
      (tester) async {
    await bootstrapSettings(tester);
    await category(tester, SettingsCategory.mcpAgents);
    expect(find.text('local_ipc'), findsWidgets);
    expect(find.text('local stdio; Unix IPC bridge only'), findsOneWidget);
    expect(find.text('18'), findsWidgets);
    expect(find.text('27'), findsWidgets);
    expect(find.textContaining('Remote MCP'), findsWidgets);
    expect(find.textContaining('Streamable HTTP'), findsNothing);
  });

  testWidgets(
      'D client JSON is valid, copy works and only placeholders are copied',
      (tester) async {
    final clipboard = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await bootstrapSettings(tester);
    await category(tester, SettingsCategory.mcpAgents);
    await section(tester, SettingsSection.clientConfiguration);
    await tester.tap(find.byKey(const Key('settings-copy-configuration')));
    await tester.pumpAndSettle();
    final config = jsonDecode(clipboard.single) as Json;
    expect(config['mcpServers']['oip-local']['args'][0], '--mcp-bridge');
    expect(clipboard.single, contains('<AUTHORIZED_PRIVATE_SOCKET>'));
    expect(clipboard.single, isNot(contains('/Users/')));
    expect(clipboard.single, isNot(contains('Bearer ')));
    await tester.tap(find.byKey(const Key('settings-copy-cli')));
    await tester.pumpAndSettle();
    expect(clipboard.length, 2);
    expect(clipboard.last, contains('--ipc-credential'));
    expect(clipboard.last, contains('<AUTHORIZED_PRIVATE_CREDENTIAL_FILE>'));
  });

  testWidgets(
      'C tool search and selection drive inspector and valid schema copy',
      (tester) async {
    final clipboard = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await bootstrapSettings(tester);
    await category(tester, SettingsCategory.mcpAgents);
    await section(tester, SettingsSection.tools);
    await tester.enterText(
        find.byKey(const Key('settings-tool-search')), 'oip_settings_read');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-tool-oip_settings_read')),
        findsOneWidget);
    expect(
        find.byKey(const Key('settings-tool-oip_devices_read')), findsNothing);
    await tester.tap(find.byKey(const Key('settings-tool-oip_settings_read')));
    await tester.pumpAndSettle();
    final inspectorScroll = find
        .descendant(
            of: find.byKey(const Key('settings-inspector')),
            matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
        find.byKey(const Key('settings-copy-schema')), 200,
        scrollable: inspectorScroll);
    await tester.pumpAndSettle();
    expect(find.textContaining('SettingsQuery'), findsWidgets);
    await tester.tap(find.byKey(const Key('settings-copy-schema')));
    await tester.pumpAndSettle();
    expect(jsonDecode(clipboard.single), isA<Map<String, dynamic>>());
  });

  testWidgets('Tool search exposes an explicit deterministic clear action',
      (tester) async {
    await bootstrapSettings(tester);
    await category(tester, SettingsCategory.mcpAgents);
    await section(tester, SettingsSection.tools);
    await tester.enterText(
        find.byKey(const Key('settings-tool-search')), 'oip_settings_read');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-tool-oip_settings_read')),
        findsOneWidget);
    expect(find.byKey(const Key('settings-tool-search-clear')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-tool-search-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-tool-search-clear')), findsNothing);
    expect(find.textContaining('18 von 18 Tools'), findsOneWidget);
    expect(find.byKey(const Key('settings-tool-oip_devices_read')),
        findsOneWidget);
  });

  testWidgets(
      'E two real principal contexts preserve different tool visibility',
      (tester) async {
    final full = await bootstrapSettings(tester);
    await category(tester, SettingsCategory.mcpAgents);
    await section(tester, SettingsSection.tools);
    final fullReport = await full.api.management('tools');
    expect(fullReport.tools.length, 18);
    expect(
        fullReport.tools.where((tool) => tool.availableToPrincipal).length, 18);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final observer = await bootstrapSettings(tester,
        api: FixtureSettingsApi(contextName: 'management_observer'));
    await category(tester, SettingsCategory.mcpAgents);
    await section(tester, SettingsSection.tools);
    final limited = await observer.api.management('tools');
    expect(limited.tools.length, 18);
    expect(limited.tools.where((tool) => tool.availableToPrincipal).length, 1);
    expect(limited.tools.singleWhere((tool) => tool.availableToPrincipal).name,
        'oip_mcp_management_read');
  });

  testWidgets('Permission filter shows only denied tools for limited principal',
      (tester) async {
    await bootstrapSettings(tester,
        api: FixtureSettingsApi(contextName: 'management_observer'));
    await category(tester, SettingsCategory.mcpAgents);
    await section(tester, SettingsSection.tools);
    await tester.tap(find.byKey(const Key('settings-permission-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Denied by Policy').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-tool-oip_mcp_management_read')),
        findsNothing);
    expect(find.textContaining('17 von 18 Tools'), findsOneWidget);
  });

  testWidgets(
      'F sessions are explicitly unsupported without fictitious clients',
      (tester) async {
    await bootstrapSettings(tester);
    await category(tester, SettingsCategory.mcpAgents);
    await section(tester, SettingsSection.clientSessions);
    expect(
        find.text(
            'Aktive MCP-Client-Sessions können derzeit nicht zentral aufgelistet werden.'),
        findsOneWidget);
    expect(find.text('UNSUPPORTED'), findsWidgets);
    expect(find.textContaining('Session-IDs'), findsWidgets);
    expect(find.text('Connected'), findsNothing);
  });

  testWidgets('H HTTP 403 is authorization state, not offline', (tester) async {
    final api = FixtureSettingsApi()
      ..settingsFailure = const ApiFailure('Denied',
          code: 'PERMISSION_DENIED', statusCode: 403);
    await bootstrapSettings(tester, api: api);
    expect(find.text('Management-Zugriff nicht autorisiert'), findsOneWidget);
    expect(find.textContaining('nicht „Core offline“'), findsOneWidget);
    await tester.tap(find.text('Technische Fehlerdetails'));
    await tester.pumpAndSettle();
    expect(find.text('403'), findsOneWidget);
    expect(
        find.text('Core / Management-Endpunkt nicht erreichbar'), findsNothing);
  });

  testWidgets('Network failure is distinct and retry clears stale error',
      (tester) async {
    final api = FixtureSettingsApi()
      ..settingsFailure =
          const ApiFailure('Offline', code: 'CONNECTION_FAILED');
    await bootstrapSettings(tester, api: api);
    expect(find.text('Core / Management-Endpunkt nicht erreichbar'),
        findsOneWidget);
    api.settingsFailure = null;
    await tester.tap(find.byKey(const Key('settings-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-error-state')), findsNothing);
    expect(find.byKey(const Key('settings-setting-instance_name')),
        findsOneWidget);
  });

  testWidgets('I existing source/device data renders without fake onboarding',
      (tester) async {
    await bootstrapSettings(tester);
    await category(tester, SettingsCategory.infrastructure);
    await section(tester, SettingsSection.sourcesDevices);
    expect(
        find.textContaining('simulated / demo data reported'), findsOneWidget);
    expect(find.textContaining('2 geliefert'), findsWidgets);
    expect(
        find.text('Device onboarding requires local operator administration'),
        findsOneWidget);
    expect(find.text('Gerät hinzufügen'), findsNothing);
  });

  testWidgets(
      'J theme preference actually updates Flutter theme and stays local',
      (tester) async {
    await bootstrapSettings(tester);
    await section(tester, SettingsSection.preferences);
    await tester.tap(find.byKey(const Key('settings-theme-daylight')));
    await tester.pumpAndSettle();
    expect(
        Theme.of(tester.element(find.byKey(const Key('settings-workspace'))))
            .brightness,
        Brightness.light);
    expect(find.text('Nur diese UI-Sitzung'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-theme-graphite')));
    await tester.pumpAndSettle();
    expect(
        Theme.of(tester.element(find.byKey(const Key('settings-workspace'))))
            .brightness,
        Brightness.dark);
  });

  testWidgets(
      'Local preferences remain usable without snapshot or authorization',
      (tester) async {
    final api = FixtureSettingsApi()
      ..settingsFailure = const ApiFailure('Denied',
          code: 'PERMISSION_DENIED', statusCode: 403);
    await bootstrapSettings(tester, api: api, withSnapshot: false);
    expect(find.text('Management-Zugriff nicht autorisiert'), findsOneWidget);
    await section(tester, SettingsSection.preferences);
    await tester.tap(find.byKey(const Key('settings-theme-daylight')));
    await tester.pumpAndSettle();
    expect(
        Theme.of(tester.element(find.byKey(const Key('settings-workspace'))))
            .brightness,
        Brightness.light);
  });

  testWidgets('Session navigation survives module switches while data reloads',
      (tester) async {
    final result = await bootstrapSettings(tester);
    await category(tester, SettingsCategory.mcpAgents);
    await section(tester, SettingsSection.tools);
    await tester.enterText(
        find.byKey(const Key('settings-tool-search')), 'oip_settings_read');
    await tester.pumpAndSettle();
    final before = result.api.managementCalls.length;
    await tester.tap(find.byKey(const Key('nav-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-5')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-tool-oip_settings_read')),
        findsOneWidget);
    expect(result.api.managementCalls.length, greaterThan(before));
  });

  testWidgets('Late management response cannot cross a section change',
      (tester) async {
    final api = FixtureSettingsApi(delay: const Duration(milliseconds: 30));
    await bootstrapSettings(tester, api: api);
    await category(tester, SettingsCategory.mcpAgents);
    await section(tester, SettingsSection.clientConfiguration);
    expect(
        find.byKey(const Key('settings-copy-configuration')), findsOneWidget);
    expect(find.text('local_ipc'), findsNothing);
    expect(api.cancelCalls, greaterThan(0));
  });

  testWidgets('No periodic management polling occurs', (tester) async {
    final result = await bootstrapSettings(tester);
    final calls = result.api.settingsCalls.length;
    await tester.pump(const Duration(seconds: 3));
    expect(result.api.settingsCalls.length, calls);
  });

  testWidgets('Data, diagnostics, security and system retain explicit limits',
      (tester) async {
    await bootstrapSettings(tester);
    await category(tester, SettingsCategory.dataStorage);
    expect(find.text('5'), findsWidgets);
    expect(find.textContaining('unsupported; no data deletion'), findsWidgets);
    await section(tester, SettingsSection.retention);
    expect(find.text('Historie löschen'), findsNothing);
    await category(tester, SettingsCategory.diagnostics);
    expect(find.textContaining('documented markers'), findsWidgets);
    await category(tester, SettingsCategory.securityAccess);
    expect(find.textContaining('RUSTSEC-2024-0449'), findsWidgets);
    expect(find.text('Secure for Production'), findsNothing);
    await category(tester, SettingsCategory.system);
    expect(
        find.text('f9969f0a21f2885a8b6c4695b3c105ad28708d33'), findsOneWidget);
    expect(find.textContaining('no host collector data'), findsOneWidget);
  });

  testWidgets('Keyboard slash focuses search and Escape clears only text input',
      (tester) async {
    await bootstrapSettings(tester);
    await category(tester, SettingsCategory.mcpAgents);
    await section(tester, SettingsSection.tools);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pumpAndSettle();
    expect(
        FocusManager.instance.primaryFocus?.debugLabel, 'settings-tool-search');
    await tester.enterText(
        find.byKey(const Key('settings-tool-search')), 'settings');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-tool-oip_devices_read')),
        findsOneWidget);
  });

  testWidgets('Responsive tool workstation works at 320, 768 and 1920',
      (tester) async {
    for (final width in [320.0, 768.0, 1920.0]) {
      await tester.pumpWidget(const SizedBox());
      await bootstrapSettings(tester,
          size: Size(width, width == 320 ? 740 : 1000));
      await category(tester, SettingsCategory.mcpAgents);
      await section(tester, SettingsSection.tools);
      expect(tester.takeException(), isNull, reason: '$width');
      expect(find.byKey(const Key('settings-workspace')), findsOneWidget);
    }
  });

  test('Fixture DTOs contain 18 tools and validate both JSON schemas', () {
    final data = jsonDecode(
        File('test/fixtures/settings/platform/management-tools.json')
            .readAsStringSync()) as Json;
    final report = ManagementReport.fromJson(data,
        origin: SettingsDataOrigin.contractFixture);
    expect(report.tools, hasLength(18));
    for (final tool in report.tools) {
      expect(jsonDecode(tool.inputSchemaJson), isA<Object>());
      expect(jsonDecode(tool.outputSchemaJson), isA<Object>());
    }
  });

  test('Invalid client configuration JSON is rejected at contract boundary',
      () {
    expect(
      () => ClientConfigurationPreview.fromJson({
        'executable': null,
        'args': const [],
        'usable_without_replacement': false,
        'credential_provisioned': false,
        'configuration_json': '{broken',
      }),
      throwsFormatException,
    );
  });
}
