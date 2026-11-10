import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/features/opcua_value.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/services/api.dart';
import 'support.dart';

void main() {
  group('Value Intelligence', () {
    test('Large double keeps original and exact digit-based display modes', () {
      final observation = _observation(9935886781761.9);
      expect(originalObservationValue(observation), '9935886781761.9');
      expect(formatObservationValue(observation, OpcValueFormat.localized),
          '9.935.886.781.761,9');
      expect(formatObservationValue(observation, OpcValueFormat.scientific),
          '9,9358867817619e12');
      expect(formatObservationValue(observation, OpcValueFormat.engineering),
          '9,9358867817619e12');
    });

    test('UInt64 above IEEE-754 exact-double range never converts to double',
        () {
      final observation = _observation(9007199254740993);
      expect(originalObservationValue(observation), '9007199254740993');
      expect(formatObservationValue(observation, OpcValueFormat.localized),
          '9.007.199.254.740.993');
      expect(formatObservationValue(observation, OpcValueFormat.scientific),
          '9,007199254740993e15');
    });

    test('Small, negative, exponent and zero values retain their meaning', () {
      final cases = {
        0.00125: ['0,00125', '1,25e-3', '1,25e-3'],
        -12345.0: ['-12.345,0', '-1,23450e4', '-12,3450e3'],
        0.0: ['0', '0e0', '0e0'],
      };
      cases.forEach((value, expected) {
        final observation = _observation(value);
        expect(formatObservationValue(observation, OpcValueFormat.localized),
            expected[0]);
        expect(formatObservationValue(observation, OpcValueFormat.scientific),
            expected[1]);
        expect(formatObservationValue(observation, OpcValueFormat.engineering),
            expected[2]);
      });
    });

    test('Strings, booleans, missing, invalid and non-finite stay explicit',
        () {
      for (final value in ['1234', true, false]) {
        for (final mode in OpcValueFormat.values) {
          expect(formatObservationValue(_observation(value), mode),
              value.toString());
        }
      }
      expect(
          formatObservationValue(null, OpcValueFormat.localized), 'Unbekannt');
      expect(
          formatObservationValue(_observation(null), OpcValueFormat.scientific),
          'Unbekannt');
      final invalid = observation()..['value'] = 'not-an-envelope';
      expect(
          formatObservationValue(
              Observation.fromJson(invalid), OpcValueFormat.scientific),
          'Ungültiger Wert');
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity
      ]) {
        expect(
            formatObservationValue(
                _observation(value), OpcValueFormat.engineering),
            value.toString());
      }
    });

    testWidgets(
        'Inspector switches notation and copies only the original value',
        (tester) async {
      await _bootstrap(tester, const Size(1440, 1000),
          configure: (api) => api.generatedBulkNodes = 40);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('folder-Bulk')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('node-bulk.0000')));
      await tester.pumpAndSettle();
      expect(_nodeValue(tester), '1000000.0');
      await tester.tap(find.byKey(const Key('value-format')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lokalisiert').last);
      await tester.pumpAndSettle();
      expect(_nodeValue(tester), '1.000.000,0');
      String? copied;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.tap(find.byKey(const Key('copy-original-value')));
      await tester.pumpAndSettle();
      expect(copied, '1000000.0');
      expect(tester.takeException(), isNull);
    });
  });

  group('Source, search and compare workflows', () {
    testWidgets('Source switch scopes requests, pins and observations',
        (tester) async {
      await _bootstrap(tester, const Size(1440, 1000), configure: (api) {
        api.generatedBulkNodes = 6;
        api.availableSources = [_source('source-a'), _source('source-b')];
      });
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('pin-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('1/8'), findsOneWidget);
      await _selectSource(tester, 'source-b');
      expect(find.text('1006 Nodes · Seite 1'), findsNothing);
      // The scope of the operator is the whole catalogue of the Core: the
      // six process variables and the six bulk nodes of the source.
      expect(find.text('12 Nodes · Seite 1'), findsOneWidget);
      expect(find.text('6 Nodes · Seite 1'), findsNothing);
      await tester.tap(find.byKey(const Key('pin-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('2/8'), findsOneWidget);
      await tester.tap(find.byKey(const Key('compare-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('compare-workspace')), findsOneWidget);
      expect(find.text('source-b'), findsWidgets);
      await tester.tap(find.byKey(const Key('compare-close')));
      await tester.pumpAndSettle();
      await _selectSource(tester, 'source-a');
      await tester.tap(find.byKey(const Key('compare-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('2/4 · quellenbezogen · sitzungslokal'), findsOneWidget);
      expect(find.text('source-a'), findsWidgets);
      expect(find.text('source-b'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Compare adds, removes and clears real nodes with C shortcut',
        (tester) async {
      await _bootstrap(tester, const Size(1440, 1000),
          configure: (api) => api.generatedBulkNodes = 40);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('node-temperature')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(find.text('1/4 · quellenbezogen · sitzungslokal'), findsOneWidget);
      expect(find.text('Unabhängige Messzeitpunkte'), findsOneWidget);
      await tester.tap(find.byKey(const Key('compare-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('node-pressure')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(find.text('2/4 · quellenbezogen · sitzungslokal'), findsOneWidget);
      expect(find.text('temperature'), findsWidgets);
      expect(find.text('pressure'), findsWidgets);
      expect(find.text('SourceTimestamp'), findsWidgets);
      await tester.tap(find.byKey(const Key('compare-remove-temperature')));
      await tester.pumpAndSettle();
      expect(find.text('1/4 · quellenbezogen · sitzungslokal'), findsOneWidget);
      await tester.tap(find.byKey(const Key('compare-clear')));
      await tester.pumpAndSettle();
      expect(find.text('Noch keine Nodes im Vergleich'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Type and quality filters are explicitly page-local',
        (tester) async {
      await _bootstrap(tester, const Size(1440, 1000),
          configure: (api) => api.generatedBulkNodes = 6);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('filters-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Typ/Quality: nur geladene Seite'),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('type-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Typ: Boolean').last);
      await tester.pumpAndSettle();
      expect(find.text('2/12 auf dieser Seite'), findsOneWidget);
      expect(find.text('12 Nodes · Seite 1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('quality-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quality: bad').last);
      await tester.pumpAndSettle();
      expect(find.text('0/12 auf dieser Seite'), findsOneWidget);
      expect(find.text('Keine Seiten-Treffer'), findsOneWidget);
      await tester.tap(find.byKey(const Key('clear-page-filters')));
      await tester.pumpAndSettle();
      expect(find.text('12/12 auf dieser Seite'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Server search covers the full source before pagination',
        (tester) async {
      final app = await _bootstrap(tester, const Size(1440, 1000),
          configure: (api) => api.generatedBulkNodes = 1000);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('folder-all')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('node-search')), 'bulk.0999');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('1 Nodes · Seite 1'), findsOneWidget);
      expect(find.byKey(const Key('node-bulk.0999')), findsOneWidget);
      expect(find.textContaining('SERVERWEITE NAMENSSUCHE'), findsOneWidget);
      expect(app.api.nodeRequests.last.search, 'bulk.0999');
      expect(tester.takeException(), isNull);
    });
  });

  group('Engineering inspector and analysis', () {
    testWidgets('Technical details and history remain honestly unavailable',
        (tester) async {
      await _bootstrap(tester, const Size(1440, 1000));
      await _navigate(tester, 1440);
      expect(find.byKey(const Key('history-unavailable')), findsOneWidget);
      expect(find.text('Historische API nicht verfügbar'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('technical-details')));
      await tester.tap(find.byKey(const Key('technical-details')));
      await tester.pumpAndSettle();
      expect(find.text('ValueRank'), findsOneWidget);
      expect(find.text('Nicht von API geliefert'), findsWidgets);
      expect(find.text('Parent / References'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Quality changes and timing use real session samples',
        (tester) async {
      final app = await _bootstrap(tester, const Size(1440, 1000));
      await _navigate(tester, 1440);
      final data = fixture();
      final bad = observation(value: null);
      bad['timestamps'] = {
        'source': 1700000001000,
        'server': 1700000001000,
        'received': 1800000001000,
      };
      data['metrics'] = [bad];
      app.controller.snapshot = Snapshot.fromJson(data);
      app.controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('2'), findsWidgets);
      expect(find.text('1'), findsWidgets);
      expect(find.text('Quality-Wechsel'), findsOneWidget);
      expect(find.text('Größter Sample-Abstand · kein Datenlückenbeweis'),
          findsOneWidget);
      expect(find.text('1000 ms'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    for (final size in const [
      Size(1440, 1000),
      Size(768, 1024),
      Size(390, 844)
    ]) {
      testWidgets('Compare workspace stays usable at ${size.width}',
          (tester) async {
        await _bootstrap(tester, size,
            configure: (api) => api.generatedBulkNodes = 40);
        await _navigate(tester, size.width);
        await tester.ensureVisible(find.byKey(const Key('node-temperature')));
        await tester.tap(find.byKey(const Key('node-temperature')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('compare-toggle')));
        await tester.tap(find.byKey(const Key('compare-toggle')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('compare-workspace')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('REST sends source scope and parses actual source metadata', () async {
    late Uri nodeUri;
    final api = RestApi(Uri.parse('http://127.0.0.1:8080'),
        client: MockClient((request) async {
      if (request.url.path == '/api/v1/sources') {
        return http.Response(jsonEncode([_sourceJson('source-b')]), 200);
      }
      nodeUri = request.url;
      return http.Response(
          jsonEncode({'items': [], 'total': 0, 'offset': 0, 'limit': 40}), 200);
    }));
    final sources = await api.sources();
    expect(sources.single.id, 'source-b');
    expect(sources.single.validity, 'valid');
    await api.nodes('temperature', 'M-01', 0, source: 'source-b');
    expect(nodeUri.queryParameters['source'], 'source-b');
    expect(nodeUri.queryParameters['q'], 'temperature');
    api.close();
  });
}

Observation _observation(Object? value) =>
    Observation.fromJson(observation(value: value));

String _nodeValue(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('node-value'))).data!;

SourceInfo _source(String id) => SourceInfo.fromJson(_sourceJson(id));

Json _sourceJson(String id) => {
      'id': id,
      'name': id == 'source-a' ? 'Source A' : 'Source B',
      'entity_id': 'M-01',
      'simulated': true,
      'reachability': 'reachable',
      'connection': 'connected',
      'service': 'healthy',
      'freshness': 'fresh',
      'validity': 'valid',
      'last_received_ms': 1800000000000,
      'last_error': null,
    };

Future<void> _selectSource(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(const Key('source-select')));
  await tester.pumpAndSettle();
  await tester.tap(
      find.text('${id == 'source-a' ? 'Source A' : 'Source B'} · $id').last);
  await tester.pumpAndSettle();
}

Future<_TestApp> _bootstrap(
  WidgetTester tester,
  Size size, {
  void Function(FakeApi)? configure,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  final api = FakeApi();
  configure?.call(api);
  final controller = OipController(api)
    ..snapshot = Snapshot.fromJson(api.data)
    ..connection = 'live'
    ..workspaces.setInspectorOpen(WorkspaceId.opcua, true);
  await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.binding.setSurfaceSize(null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  return _TestApp(api, controller);
}

Future<void> _navigate(WidgetTester tester, double width) async {
  if (width < 1080) {
    await tester.tap(find.byKey(const Key('open-navigation')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('nav-3')));
  await tester.pumpAndSettle();
}

class _TestApp {
  final FakeApi api;
  final OipController controller;
  const _TestApp(this.api, this.controller);
}
