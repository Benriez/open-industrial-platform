import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/features/overview/hue_lights.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/models/hue.dart';
import 'package:oip_dashboard/services/api.dart';

class _Bridge implements HueApi {
  final bool writable;
  _Bridge({this.writable = true});
  bool on = true;
  final commands = <Json>[];
  @override
  Future<HueLights> hueLights(String source) async => HueLights.fromJson({
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
  @override
  Future<void> changeHueLight(String source, int id, Json change) async {
    commands.add({'source': source, 'id': id, ...change});
    if (change['kind'] == 'power') on = change['on'] as bool;
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
  testWidgets('Reader sees the lights with controls disabled', (t) async {
    final api = _Bridge(writable: false);
    await open(t, api);
    expect(find.text('Steckdose'), findsOneWidget);
    expect(t.widget<Switch>(find.byType(Switch).first).onChanged, isNull);
    expect(t.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    await t.pumpWidget(const SizedBox());
  });
}
