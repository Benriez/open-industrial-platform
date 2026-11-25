import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/features/overview.dart';
import 'package:oip_dashboard/features/overview/hue_lights.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/models/hue.dart';
import 'package:oip_dashboard/services/api.dart';

import 'support.dart';

class _Bridge extends FakeApi implements HueApi {
  int reads = 0;
  final bool writable;
  _Bridge({this.writable = true});
  bool on = true;
  final commands = <Json>[];
  @override
  Future<HueLights> hueLights(String source) async {
    reads++;
    return HueLights.fromJson({
      'can_control': writable,
      'lights': [
        {
          'id': 51,
          'name': 'Leselicht',
          'kind': 'Extended color light',
          'on': on,
          'reachable': true,
          'brightness_percent': 72,
          'hue_degrees': 18,
          'saturation_percent': 50
        },
        {
          'id': 99,
          'name': 'Steckdose',
          'kind': 'On/Off plug-in unit',
          'on': true,
          'reachable': true
        },
      ]
    });
  }

  @override
  Future<void> changeHueLight(String source, int id, Json change) async {
    commands.add({'source': source, 'id': id, ...change});
    if (change['kind'] == 'power') on = change['on'] as bool;
  }
}

class _SetupBridge extends _Bridge implements HueSetupApi {
  bool paired = false, found = false;
  int tries = 0;
  final setupActions = <HueSetupAction>[];

  @override
  Future<HueLights> hueLights(String source) async {
    if (!paired) {
      throw const ApiFailure('Hue pairing available',
          code: 'HUE_PAIRING_AVAILABLE');
    }
    return HueLights.fromJson({
      'can_control': true,
      'can_setup': true,
      'lights': [
        if (found)
          {
            'id': 99,
            'name': 'Neue Steckdose',
            'kind': 'On/Off plug-in unit',
            'on': false,
            'reachable': true
          },
      ],
    });
  }

  @override
  Future<void> setupHue(String source, HueSetupAction action) async {
    expect(source, 'hue-own');
    setupActions.add(action);
    if (action == HueSetupAction.searchLights) {
      found = true;
    } else if (++tries == 1) {
      throw const ApiFailure('Link button required',
          code: 'HUE_LINK_BUTTON_REQUIRED');
    } else {
      paired = true;
    }
  }
}

Future<void> open(WidgetTester t, _Bridge bridge) async {
  await t.pumpWidget(MaterialApp(
      home: Scaffold(
          body: HueLightsPanel(
              api: bridge, source: 'hue-own', bridgeName: 'Bridge'))));
  await t.pump();
}

void main() {
  testWidgets('Only the open dashboard mounts and polls lighting controls',
      (t) async {
    final api = _Bridge();
    final data = fixture();
    (data['devices'] as List).first['connection'] = 'Hue HTTPS';
    final controller = OipController(api)..snapshot = Snapshot.fromJson(data);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: OverviewPage(controller, (_) {})))));
    final toggle = find.byKey(const Key('overview-dashboard-toggle'));
    expect(find.byType(HueLightsPanel), findsNothing);
    expect(api.reads, 0);
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(find.text('Leselicht'), findsOneWidget);
    expect(api.reads, 1);
    await t.tap(toggle);
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 20));
    expect(find.byType(HueLightsPanel), findsNothing);
    expect(api.reads, 1);
    await t.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
      'All IDs render with supported controls and commands target the selected light',
      (t) async {
    final api = _Bridge();
    await open(t, api);
    expect(find.byType(Switch), findsNWidgets(2));
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('Lichtfarbe'), findsOneWidget);
    await t.tap(find.text('Lichtfarbe'));
    await t.pumpAndSettle();
    await t.tap(find.text('Übernehmen'));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(api.commands.last, {
      'source': 'hue-own',
      'id': 51,
      'kind': 'color',
      'degrees': 18,
      'saturation': 50
    });
    final slider = t.widget<Slider>(find.byType(Slider));
    slider.onChangeEnd!(42);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(api.commands.last['percent'], 42);
    await t.tap(find.byType(Switch).first);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(api.commands.last,
        {'source': 'hue-own', 'id': 51, 'kind': 'power', 'on': false});
    expect(t.widget<Switch>(find.byType(Switch).first).value, isFalse);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'A bridge can be paired and a new smart plug can be found in the app',
      (t) async {
    final api = _SetupBridge();
    await open(t, api);
    await t.tap(find.text('Hue Bridge verbinden'));
    await t.pumpAndSettle();
    expect(find.textContaining('große Taste in der Mitte'), findsOneWidget);
    await t.tap(find.text('Abbrechen'));
    await t.pumpAndSettle();
    expect(api.setupActions, isEmpty);

    for (var n = 0; n < 2; n++) {
      await t.tap(find.text('Hue Bridge verbinden'));
      await t.pumpAndSettle();
      await t.tap(find.text('Jetzt verbinden'));
      await t.pumpAndSettle();
      if (n == 0) {
        expect(find.textContaining('versuche es erneut'), findsOneWidget);
      }
    }
    expect(find.text('Hue Bridge verbunden.'), findsOneWidget);
    await t.tap(find.text('Lampen und Steckdosen hinzufügen'));
    await t.pumpAndSettle();
    await t.tap(find.text('Suche starten'));
    await t.pump();
    expect(find.textContaining('Die Bridge sucht'), findsOneWidget);
    await t.pump(const Duration(seconds: 45));
    await t.pumpAndSettle();
    expect(find.text('Ein neues Gerät gefunden.'), findsOneWidget);
    expect(find.text('Neue Steckdose'), findsOneWidget);
    expect(api.setupActions, [
      HueSetupAction.pairBridge,
      HueSetupAction.pairBridge,
      HueSetupAction.searchLights,
    ]);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Reader sees the lights with controls disabled', (t) async {
    final api = _Bridge(writable: false);
    await open(t, api);
    expect(find.text('Steckdose'), findsOneWidget);
    expect(t.widget<Switch>(find.byType(Switch).first).onChanged, isNull);
    expect(t.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    await t.pumpWidget(const SizedBox());
  });
}
