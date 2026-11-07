import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/services/api.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/core/sse.dart';

class SessionApi extends RestApi {
  final Stream<ServerEvent> events;
  SessionApi(http.Client client, this.events)
      : super(Uri.parse('http://127.0.0.1:8080'), client: client);
  @override
  Stream<ServerEvent> stream() => events;
}

void main() {
  test(
      'Expired operator session clears snapshots and invalidates open inspector context',
      () async {
    var sessions = 0;
    final events = StreamController<ServerEvent>();
    final empty = {
      'sources': [],
      'devices': [],
      'observations': [],
      'events': [],
      'locations': []
    };
    final client = MockClient((r) async => http.Response(
        jsonEncode(r.url.path.endsWith('/session')
            ? {
                'authenticated': ++sessions == 1,
                'principal_id': sessions == 1 ? 'a' : null,
                'csrf_token': null,
                'mode':
                    sessions == 1 ? 'local_operator_session' : 'login_required'
              }
            : empty),
        200));
    final controller = OipController(SessionApi(client, events.stream),
        retryDelay: const Duration(milliseconds: 1));
    final running = controller.start();
    for (var i = 0; i < 50 && controller.snapshot == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(controller.snapshot, isNotNull);
    final before = controller.contextRevision;
    await events.close();
    await running;
    expect(controller.loginRequired, isTrue);
    expect(controller.snapshot, isNull);
    expect(controller.history, isEmpty);
    expect(controller.contextRevision, greaterThan(before));
    controller.dispose();
  });
  test(
      'Scoped snapshot cannot invent global counts, health, incidents or topology',
      () {
    final snapshot = Snapshot.fromScopedJson({
      'sources': <dynamic>[],
      'devices': <dynamic>[],
      'observations': <dynamic>[],
      'events': [
        {'id': 'actual-event'}
      ],
      'locations': <dynamic>[],
    });
    expect(snapshot.system.persisted, isNull);
    expect(snapshot.system.generatedMs, isNull);
    expect(snapshot.system.cpu, isNull);
    expect(snapshot.system.lastReceivedMs, isNull);
    expect(snapshot.core.ready, isNull);
    expect(snapshot.incidents, isEmpty);
    expect(snapshot.topology, isEmpty);
    expect(snapshot.system.demoControls, isFalse);
  });
  test(
      'Pairing uses fixed endpoint and CSRF header without identity claims or URL tokens',
      () async {
    final calls = <http.Request>[];
    final api = RestApi(Uri.parse('http://127.0.0.1:8080'),
        client: MockClient((r) async {
      calls.add(r);
      expect(r.url.query.contains('token'), isFalse);
      if (r.url.path == '/api/v2/browser/login') {
        expect(jsonDecode(r.body), {'code': 'one-use-unit-fixture'});
        return http.Response(
            jsonEncode({
              'authenticated': true,
              'principal_id': 'bound-by-server',
              'mode': 'local_operator_session',
              'csrf_token': 'unit-csrf'
            }),
            200);
      }
      if (r.url.path == '/api/v2/browser/session') {
        return http.Response(
            jsonEncode({
              'authenticated': false,
              'principal_id': null,
              'mode': 'login_required',
              'csrf_token': null
            }),
            200);
      }
      expect(r.url.path, '/api/v2/device-connections');
      expect(r.headers['x-oip-csrf'], 'unit-csrf');
      expect((jsonDecode(r.body) as Json).containsKey('principal'), isFalse);
      return http.Response(
          jsonEncode({
            'profiles': [],
            'plan': null,
            'connection': null,
            'last_attempt': null
          }),
          200);
    }));
    expect((await api.session()).authenticated, isFalse);
    expect(api.managed, isTrue);
    expect((await api.login('one-use-unit-fixture')).principalId,
        'bound-by-server');
    await api.configure({'operation': 'cancel', 'plan_id': 'unit-plan'});
    expect(calls.length, 3);
    api.close();
  });
}
