import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/core/sse.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/services/api.dart';
import 'support.dart';

void main() {
  test('Missing observations and hardware metrics never become zero', () {
    final o = Observation.fromJson(observation(value: null));
    expect(o.value, isNull);
    expect(o.number, isNull);
    expect(o.display, 'Unbekannt');
    expect(Snapshot.fromJson(fixture()).system.gpu, isNull);
  });
  test('SSE parses fragmented UTF8, CRLF, comments and multiline events',
      () async {
    final bytes = utf8.encode(
        ': keepalive\r\nevent: snapshot\r\ndata: {"name":\r\ndata: "Gerät"}\r\n\r\n');
    final events = await decodeEvents(Stream.fromIterable(bytes.map((b) => [b]))
            .transform(utf8.decoder)
            .transform(const LineSplitter()))
        .toList();
    expect(events.single.type, 'snapshot');
    expect(jsonDecode(events.single.data), {'name': 'Gerät'});
  });
  test('REST rejects non-success status without creating fallback data',
      () async {
    final api = RestApi(Uri.parse('http://127.0.0.1:8080'),
        client: MockClient((_) async => http.Response('failed', 503)));
    await expectLater(api.initial(), throwsA(isA<ApiFailure>()));
    api.close();
  });
  test('REST preserves structured public API error codes', () async {
    final api = RestApi(Uri.parse('http://127.0.0.1:8080'),
        client: MockClient((_) async => http.Response.bytes(
            utf8.encode(jsonEncode({
              'ok': false,
              'message': 'Demo ist für dieses Gerät deaktiviert',
              'code': 'DEMO_DISABLED'
            })),
            403,
            headers: {'content-type': 'application/json'})));
    await expectLater(
      api.initial(),
      throwsA(isA<ApiFailure>()
          .having((error) => error.code, 'code', 'DEMO_DISABLED')
          .having((error) => error.message, 'message',
              'Demo ist für dieses Gerät deaktiviert')),
    );
    api.close();
  });

  test('Controller reconnects after stream failure and replaces stale state',
      () async {
    final api = FakeApi();
    final c = OipController(api, retryDelay: const Duration(milliseconds: 5));
    final running = c.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.connection, 'live');
    api.fail = true;
    api.events.addError(Exception('disconnect'));
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(c.stale, isTrue);
    expect(c.error, isNotNull);
    expect(c.snapshot, isNotNull);
    api.fail = false;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(c.connection, 'live');
    expect(api.attempts, greaterThan(1));
    expect(c.error, isNull);
    c.dispose();
    await running;
  });

  test('One SSE snapshot produces one notification and history remains capped',
      () async {
    final api = FakeApi();
    final controller = OipController(api);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final running = controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.connection, 'live');
    notifications = 0;

    api.data = fixture();
    final metric = (api.data['metrics'] as List).first as Json;
    (metric['timestamps'] as Json)['source'] = 1700000001000;
    (metric['value'] as Json)['float'] = 61.3;
    api.emit();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(notifications, 1);

    for (var index = 0; index < 65; index++) {
      api.data = fixture();
      final item = (api.data['metrics'] as List).first as Json;
      (item['timestamps'] as Json)['source'] = 1700000100000 + index * 1000;
      (item['value'] as Json)['float'] = 60 + index / 10;
      api.emit();
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(controller.history.length, 60);
    expect(controller.history.last.sourceMs, 1700000164000);
    controller.dispose();
    await running;
  });

  test('Malformed or missing units stay explicit without aborting a snapshot',
      () {
    for (final unit in [
      null,
      <String, dynamic>{},
      {'custom': 7}
    ]) {
      final data = observation();
      data['unit'] = unit;
      final parsed = Observation.fromJson(data);
      expect(parsed.unit, 'invalid');
      expect(parsed.symbol, 'Einheit ungültig');
    }
    final custom = observation();
    custom['unit'] = {'custom': 'bar'};
    expect(Observation.fromJson(custom).symbol, 'bar');
    final data = fixture();
    ((data['metrics'] as List).first as Json)['unit'] = null;
    expect(Snapshot.fromJson(data).metrics.single.unit, 'invalid');
  });

  test('Unknown and partial collection events remain structurally readable',
      () {
    final unknown = CollectionEvent.fromJson({'FutureEvent': 'not-a-map'});
    expect(unknown.kind, 'FutureEvent');
    expect(unknown.atMs, isNull);
    final gap = CollectionEvent.fromJson({
      'Reconnected': {
        'gap': {'started_at': 10, 'ended_at': 25}
      }
    });
    expect(gap.atMs, isNull);
    expect(gap.gapMs, 15);
  });

  test('REST initial assembly, node query and collection payload use API data',
      () async {
    final requests = <http.Request>[];
    final data = fixture();
    final api = RestApi(
      Uri.parse('http://127.0.0.1:8080'),
      client: MockClient((request) async {
        requests.add(request);
        switch (request.url.path) {
          case '/api/v1/system/status':
            return http.Response.bytes(
                utf8.encode(jsonEncode(data['system'])), 200);
          case '/api/v1/devices':
            return http.Response.bytes(
                utf8.encode(jsonEncode(data['devices'])), 200);
          case '/api/v1/metrics/current':
            return http.Response.bytes(
                utf8.encode(jsonEncode(data['metrics'])), 200);
          case '/api/v1/events':
            return http.Response(
              jsonEncode({
                'incidents': data['incidents'],
                'collection_events': [
                  {
                    'SubscriptionError': {'at': 42, 'reason': 'test'}
                  }
                ]
              }),
              200,
            );
          case '/api/v1/sources':
            return http.Response(
              jsonEncode([
                {
                  'id': 'oip-local-simulation-v1',
                  'name': 'Local OPC-UA Simulation',
                  'entity_id': 'M-01',
                  'simulated': true,
                  'reachability': 'unknown',
                  'connection': 'connected',
                  'service': 'healthy',
                  'freshness': 'fresh',
                  'validity': 'valid',
                  'last_received_ms': 1800000000000,
                  'last_error': null,
                }
              ]),
              200,
            );
          case '/api/v1/opcua/nodes':
            return http.Response(
              jsonEncode({
                'items': <dynamic>[],
                'total': 0,
                'offset': 80,
                'limit': 40,
                // The Core delivers the folders of the address space.
                'folders': <String>['M-01']
              }),
              200,
            );
          default:
            return http.Response('not found', 404);
        }
      }),
    );
    final initial = await api.initial();
    expect(initial.devices, hasLength(2));
    expect(initial.topology, isEmpty);
    expect(initial.sources.single.id, 'oip-local-simulation-v1');
    expect(initial.recentEvents.single.kind, 'SubscriptionError');
    final nodes = await api.nodes('bulk', 'Bulk', 80);
    expect(nodes.offset, 80);
    expect(nodes.limit, 40);
    // The Core names the folders of its address space with every page.
    expect(nodes.folders, ['M-01']);
    final nodeRequest = requests.last;
    expect(nodeRequest.url.queryParameters,
        {'q': 'bulk', 'folder': 'Bulk', 'offset': '80', 'limit': '40'});
    final events = await api.collectionEvents();
    expect(events.single.kind, 'SubscriptionError');
    expect(events.single.atMs, 42);
    api.close();
  });

  test('Scenario POST preserves structured DEMO_DISABLED failure', () async {
    final api = RestApi(
      Uri.parse('http://127.0.0.1:8080'),
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'ok': false,
              'message': 'Demo deaktiviert',
              'code': 'DEMO_DISABLED'
            }),
            403,
          )),
    );
    await expectLater(
      api.scenario('sensor'),
      throwsA(isA<ApiFailure>()
          .having((error) => error.code, 'code', 'DEMO_DISABLED')
          .having((error) => error.path, 'path', '/api/v1/demo/scenario')
          .having((error) => error.message, 'message', 'Demo deaktiviert')),
    );
    api.close();
  });

  test('Server SSE error event enters stale reconnect state', () async {
    final api = FakeApi();
    final controller =
        OipController(api, retryDelay: const Duration(milliseconds: 50));
    final running = controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    api.events.add(const ServerEvent('error', 'storage unavailable'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.stale, isTrue);
    expect(controller.error, contains('/api/v1/stream'));
    expect(controller.error, contains('SSE_ERROR'));
    controller.dispose();
    await running;
  });

  test('Silent SSE stream times out and reconnects', () async {
    final api = FakeApi()..emitAutomatically = false;
    final controller = OipController(
      api,
      retryDelay: const Duration(milliseconds: 1),
      streamTimeout: const Duration(milliseconds: 5),
    );
    final running = controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(api.attempts, greaterThan(1));
    expect(controller.stale, isTrue);
    controller.dispose();
    await running;
  });

  test('Backend alarm classification is scoped to its registry entity', () {
    final data = fixture();
    final alarm = observation(value: true);
    alarm['metric_id'] = 'alarm_active';
    alarm['value'] = {'boolean': true};
    alarm['unit'] = 'none';
    data['metrics'] = [alarm];
    expect(Snapshot.fromJson(data).hasAlarm(), isFalse);
    (((data['devices'] as List).first as Json)['health']
        as Json)['service_health'] = 'alarm';
    final snapshot = Snapshot.fromJson(data);
    expect(snapshot.hasAlarm(deviceId: 'M-01'), isTrue);
    expect(snapshot.hasAlarm(deviceId: 'evo'), isFalse);
    expect(snapshot.hasAlarm(), isTrue);
  });

  test('Malformed values and timestamps remain explicit and non-fatal', () {
    final data = observation();
    data['value'] = 'not-an-envelope';
    data['timestamps'] = {'server': 20};
    final parsed = Observation.fromJson(data);
    expect(parsed.valueValid, isFalse);
    expect(parsed.display, 'Ungültiger Wert');
    expect(parsed.sourceMs, isNull);
    expect(parsed.serverMs, 20);
    final gap = CollectionEvent.fromJson({
      'Reconnected': {'gap': 'unknown'}
    });
    expect(gap.gapMs, isNull);
  });

  test('REST preserves base path and classifies DTO violations', () async {
    late http.Request first;
    final api = RestApi(
      Uri.parse('http://127.0.0.1:8080/oip/?leak=remove'),
      client: MockClient((request) async {
        first = request;
        return http.Response(jsonEncode({'collection_events': 'invalid'}), 200);
      }),
    );
    await expectLater(
      api.collectionEvents(),
      throwsA(isA<ApiFailure>()
          .having((error) => error.code, 'code', 'CONTRACT_ERROR')),
    );
    expect(first.url.path, '/oip/api/v1/events');
    expect(first.url.hasQuery, isFalse);
    api.close();
  });
}
