import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/services/api.dart';
import 'support.dart';

Json withSources({bool stale = false, int at = 2000}) {
  final data = fixture();
  (data['system'] as Json)['primary_source_id'] = 'a';
  final a = observation(value: 61.0);
  a['data_source_id'] = 'a';
  (a['timestamps'] as Json)['source'] = at;
  a['freshness'] = stale ? 'stale' : 'fresh';
  final b = observation(value: 22.0);
  b['data_source_id'] = 'b';
  (b['timestamps'] as Json)['source'] = at;
  data['metrics'] = [b, a]; // Ordering must never select another source.
  return data;
}

void main() {
  test(
      'Primary source, device identity and unknown classification survive JSON',
      () {
    final data = withSources();
    final value = Snapshot.fromJson(data);
    expect(value.primaryTemperature?.sourceId, 'a');
    expect(value.primaryTemperature?.number, 61.0);
    final device = ((data['devices'] as List).first as Json);
    device['data_source_id'] = 'a';
    device['is_faulted'] = true;
    expect(Device.fromJson(device).isFaulted, isTrue);
    device.remove('is_faulted');
    expect(Device.fromJson(device).faulted, isNull);
    expect(Device.fromJson(device).sourceId, 'a');
    (data['system'] as Json).remove('primary_source_id');
    expect(Snapshot.fromJson(data).primaryTemperature, isNull);
  });
  test(
      'Trend isolates sources, excludes restored stale samples and resets clock epochs',
      () async {
    final api = FakeApi();
    api.data = withSources(stale: true);
    final controller = OipController(api);
    final running = controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.history, isEmpty);
    api.data = withSources();
    api.emit();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.history.map((o) => o.sourceId), ['a']);
    api.data = withSources(at: 3000);
    api.emit();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.history.length, 2);
    api.data = withSources(at: 1000);
    api.emit();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.history.length, 1);
    expect(controller.history.single.sourceMs, 1000);
    (api.data['system'] as Json)['primary_source_id'] = 'b';
    api.emit();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.history.single.sourceId, 'b');
    controller.dispose();
    await running;
  });
  test(
      'REST contextual records preserve source, sequence and unknown loss interval',
      () async {
    final client = MockClient((request) async => http.Response(
        jsonEncode({
          'records': [
            {
              'sequence': 12,
              'context': {'data_source_id': 'b'},
              'event': {
                'DataLoss': {
                  'at': 2000,
                  'dropped': 9,
                  'gap': {
                    'started_at': 2000,
                    'ended_at': 2000,
                    'reason': 'interval unknown'
                  }
                }
              }
            }
          ],
          'collection_events': []
        }),
        200));
    final api = RestApi(Uri.parse('http://127.0.0.1:8080'), client: client);
    final events = await api.collectionEvents();
    expect(events.single.sourceId, 'b');
    expect(events.single.sequence, 12);
    expect(events.single.dropped, 9);
    expect(events.single.gapMs, isNull);
    api.close();
  });
  test('Malformed source times never crash the reconciled controller',
      () async {
    final api = FakeApi();
    api.data = withSources();
    final controller = OipController(api);
    final running = controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final before = controller.history.length;
    for (final time in [null, 'invalid', 9000000000000001]) {
      api.data = withSources();
      final primary = (api.data['metrics'] as List).last as Json;
      primary['timestamps'] = <String, dynamic>{
        ...primary['timestamps'] as Json,
        'source': time
      };
      api.emit();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(controller.connection, 'live');
      expect(controller.history.length, before);
      expect(controller.snapshot!.primaryTemperature!.sourceMs, isNull);
    }
    controller.dispose();
    await running;
  });

  testWidgets(
      'OPC UA live selection cannot display another source with the same metric',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    final api = FakeApi()..data = withSources();
    final controller = OipController(api)
      ..snapshot = Snapshot.fromJson(api.data)
      ..connection = 'live';
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-3')));
    await tester.pumpAndSettle();
    expect(find.text('61.0 °C'), findsWidgets);
    expect(find.text('22.0 °C'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
