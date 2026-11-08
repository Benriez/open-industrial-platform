import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/models/infrastructure.dart';
import 'package:oip_dashboard/services/api.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/models/onboarding.dart';
import 'package:oip_dashboard/core/sse.dart';

import 'infrastructure_support.dart';
import 'support.dart';

class SessionApi extends RestApi {
  final Stream<ServerEvent> events;
  SessionApi(http.Client client, this.events)
      : super(Uri.parse('http://127.0.0.1:8080'), client: client);
  @override
  Stream<ServerEvent> stream() => events;
}

void main() {
  test(
      'An expired operator session clears snapshots and never falls back to the demo dashboard',
      () async {
    // The Core answers the authorized context with an identity failure and the
    // legacy route is not an explicitly marked demo.
    final data = fixture();
    (data['system'] as Json)['simulated'] = false;
    final api = FakeApi()
      ..data = data
      ..infrastructureFailure = const ApiFailure(
          'Browser-Session oder zentrale Policy erlaubt diesen Management-Read nicht.',
          code: 'PERMISSION_DENIED',
          statusCode: 403);
    final controller = OipController(api,
        retryDelay: const Duration(milliseconds: 1));
    final running = controller.start();
    for (var i = 0; i < 50 && !controller.loginRequired; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    // The identity failure is terminal until the operator authorizes a new
    // session. The demo dashboard is never its substitute.
    expect(controller.loginRequired, isTrue);
    expect(controller.snapshot, isNull);
    expect(controller.history, isEmpty);
    expect(controller.infrastructure.ready, isFalse);
    controller.dispose();
    await running;
  });

  test(
      'An infrastructure context change clears the display cache of the previous context',
      () async {
    final api = FakeApi()..infrastructure = infrastructureFixture();
    final controller = OipController(api);
    await controller.resyncInfrastructure();
    expect(controller.snapshot, isNotNull);
    expect(controller.history, isNotEmpty);

    // A narrower authorized context replaces the previous projection and its
    // display cache.
    controller.selectInfrastructure(
        const InfrastructureSelection.infrastructure('org-a', 'infra-a2'));
    expect(controller.snapshot!.devices.single.id, 'device-a2');
    expect(controller.history.where((item) => item.sourceId != 'source-a2'),
        isEmpty);

    // The onboarding scope is a separate seam and advances the revision that
    // open inspectors observe.
    final before = controller.contextRevision;
    controller.setInfrastructureContext(
        const OnboardingScope(organization: 'org-a', infrastructure: 'infra-a2'));
    expect(controller.contextRevision, greaterThan(before));
    controller.dispose();
  });

  test('A different operator principal invalidates the display cache', () async {
    final api = FakeApi()..infrastructure = infrastructureFixture();
    final controller = OipController(api);
    await controller.resyncInfrastructure();
    expect(controller.snapshot, isNotNull);
    expect(controller.history, isNotEmpty);

    // Another principal is a different authorization. The objects of the first
    // one are never carried over.
    api.infrastructure = infrastructureFixture(principal: 'other-operator');
    await controller.resyncInfrastructure();
    expect(controller.infrastructure.principalIdentity, 'other-operator');
    expect(controller.snapshot, isNotNull);
    controller.dispose();
  });

  test(
      'An authorized snapshot cannot invent global counts, health, incidents or topology',
      () {
    // The OIP-009 context projection is the only managed source. It carries
    // no platform-wide counters and no topology.
    final snapshot = AuthorizedSnapshot.fromJson({
      'sources': <dynamic>[],
      'devices': <dynamic>[],
      'observations': <dynamic>[],
      'events': [
        {
          'id': 'actual-event',
          'sequence': 1,
          'context': {'data_source_id': 'source-a'},
          'event': {
            'Reconnected': {'at': 1700000000000}
          }
        }
      ],
      'locations': <dynamic>[],
      'resync_required': false,
      'replay_supported': false,
    }).toSnapshot();
    expect(snapshot.system.persisted, isNull);
    expect(snapshot.system.generatedMs, isNull);
    expect(snapshot.system.cpu, isNull);
    expect(snapshot.system.lastReceivedMs, isNull);
    expect(snapshot.core.ready, isNull);
    expect(snapshot.incidents, isEmpty);
    expect(snapshot.topology, isEmpty);
    expect(snapshot.system.demoControls, isFalse);
    expect(snapshot.incidentsDelivered, isFalse);
    expect(snapshot.topologyDelivered, isFalse);
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
