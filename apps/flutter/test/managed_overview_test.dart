import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/core/sse.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/services/api.dart';
import 'package:oip_dashboard/widgets/trend.dart';

/// One measured value of the authorized projection, exactly as the Core
/// serializes it.
Json scopedObservation({
  required String metricId,
  required Object? value,
  Object unit = 'none',
  int sourceMs = 1700000000000,
  int receivedMs = 1700000000100,
  String freshness = 'fresh',
  String quality = 'good',
}) =>
    {
      'entity_id': 'device-a',
      'data_source_id': 'source-ssh',
      'metric_id': metricId,
      'value': value,
      'unit': unit,
      'quality': quality,
      'freshness': freshness,
      'timestamps': {
        'source': sourceMs,
        'server': null,
        'received': receivedMs,
      },
      'status_code': 0,
      'collection_error': null,
      'simulation_origin': null,
    };

/// The scoped projection of a session that may see exactly one SSH source.
///
/// The shape is the payload of `GET /api/v2/snapshot`: the source registry
/// with the health the Core measured, the device of the source, the
/// observations that were received and the placement of the source.
Json scopedSnapshot({int sourceMs = 1700000000000, int memory = 17179869184}) => {
      'sources': [
        {
          'id': 'source-ssh',
          'name': 'SSH host device-a',
          'entity_id': 'device-a',
          'simulated': false,
          'reachability': 'reachable',
          'connection': 'connected',
          'service': 'healthy',
          'freshness': 'fresh',
          'validity': 'valid',
          'last_received_ms': sourceMs + 100,
          'accepted': 12,
          'duplicates': 0,
          'out_of_order': 0,
          'rejected': 0,
          'reconnect_attempts': 0,
          'dropped': 0,
          'last_error': null,
        }
      ],
      'devices': [
        {
          'id': 'device-a',
          'is_faulted': false,
          'data_source_id': 'source-ssh',
          'name': 'SSH device',
          'kind': 'server',
          'location': 'site-a1',
          'connection': 'SSH',
          'simulated': false,
          'health': {
            'reachability': 'reachable',
            'vpn_transport': 'not_applicable',
            'agent_availability': 'not_applicable',
            'service_health': 'not_evaluated',
            'telemetry_freshness': 'fresh'
          }
        }
      ],
      'observations': [
        scopedObservation(
            metricId: 'host.os', value: {'text': 'Darwin'}, sourceMs: sourceMs),
        scopedObservation(
            metricId: 'host.memory_total_bytes',
            value: {'unsigned_integer': memory},
            unit: {'custom': 'bytes'},
            sourceMs: sourceMs),
        scopedObservation(
            metricId: 'host.uptime_seconds',
            value: {'float': 12345.5},
            unit: {'custom': 'seconds'},
            sourceMs: sourceMs),
      ],
      'events': <dynamic>[],
      'locations': [
        {
          'organization_id': 'org-a',
          'infrastructure_id': 'infra-a1',
          'site_id': 'site-a1',
          'source_id': 'source-ssh'
        }
      ],
    };

class ManagedApi extends RestApi {
  final StreamController<ServerEvent> events;
  ManagedApi(http.Client client, this.events)
      : super(Uri.parse('http://127.0.0.1:8080'), client: client);
  @override
  Stream<ServerEvent> stream() => events.stream;
}

/// A client whose session is valid exactly once, so the controller stops
/// instead of reconnecting forever.
http.Client managedClient(Json Function() snapshot) {
  var sessions = 0;
  return MockClient((request) async {
    if (request.url.path.endsWith('/session')) {
      sessions++;
      return http.Response(
          jsonEncode(sessions == 1
              ? {
                  'authenticated': true,
                  'principal_id': 'bound-by-server',
                  'csrf_token': null,
                  'mode': 'local_operator_session'
                }
              : {
                  'authenticated': false,
                  'principal_id': null,
                  'csrf_token': null,
                  'mode': 'login_required'
                }),
          200);
    }
    return http.Response(jsonEncode(snapshot()), 200);
  });
}

void main() {
  testWidgets(
      'The managed overview shows the authorized source and its real measurement',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    final events = StreamController<ServerEvent>.broadcast();
    final api = ManagedApi(managedClient(scopedSnapshot), events);
    // The session of the server marks the client as managed.
    await api.session();
    final controller = OipController(api,
        retryDelay: const Duration(milliseconds: 1))
      ..snapshot = Snapshot.fromScopedJson(scopedSnapshot())
      ..connection = 'live';
    // The series the controller measured from that projection. The test above
    // proves that the controller derives exactly this series from the Core
    // payload; here it is the input of the rendering.
    controller.series.add(TrendSeries(
        'source-ssh',
        'device-a',
        'host.memory_total_bytes',
        'bytes',
        (scopedSnapshot()['observations'] as List)
            .cast<Json>()
            .where((observation) =>
                observation['metric_id'] == 'host.memory_total_bytes')
            .map(Observation.fromJson)
            .toList()));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    expect(controller.managed, isTrue);
    await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
    await tester.pumpAndSettle();

    // The source registry of the session is shown with its real health.
    expect(find.text('SSH host device-a'), findsWidgets);
    expect(find.textContaining('source-ssh'), findsWidgets);
    expect(find.text('Verbunden'), findsWidgets);
    expect(find.text('Aktuell'), findsWidgets);
    // The placement of the source in the authorized hierarchy is shown.
    expect(find.textContaining('org-a · infra-a1 · site-a1'), findsOneWidget);
    // The measured value of the source is shown with its unit.
    expect(find.textContaining('17179869184 bytes'), findsWidgets);
    // The demo coordinates are gone in the managed mode.
    expect(find.textContaining('Temperatur M-01'), findsNothing);
    expect(find.textContaining('M-01'), findsNothing);
    // The chart names the metric it measured.
    expect(
        find.textContaining('host.memory_total_bytes · SSH host device-a'),
        findsOneWidget);
  });

  test('The managed mode measures one series per authorized source', () async {
    final events = StreamController<ServerEvent>.broadcast();
    var snapshot = scopedSnapshot();
    final controller = OipController(
        ManagedApi(managedClient(() => snapshot), events),
        retryDelay: const Duration(milliseconds: 1));
    final running = controller.start();
    for (var i = 0; i < 100 && controller.snapshot == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(controller.series, hasLength(1));
    final series = controller.series.single;
    expect(series.sourceId, 'source-ssh');
    expect(series.entityId, 'device-a');
    // The measured metric is named, it is never a silent choice.
    expect(series.metricId, 'host.memory_total_bytes');
    expect(series.samples, hasLength(1));
    expect(series.samples.single.value, 17179869184);

    // A later measurement of the same source extends the series.
    snapshot = scopedSnapshot(sourceMs: 1700000030000, memory: 17179860992);
    events.add(ServerEvent('snapshot', jsonEncode(snapshot)));
    for (var i = 0;
        i < 100 && controller.series.single.samples.length < 2;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(controller.series, hasLength(1));
    expect(controller.series.single.samples, hasLength(2));
    expect(controller.series.single.samples.last.sourceMs, 1700000030000);
    await events.close();
    await running;
  });

  test('The measured series of a real cadence is not broken by the demo limit',
      () async {
    // A real source publishes every 30 s. The legacy demo limit of 2.5 s
    // would break the line at every point.
    final samples = [
      Observation.fromJson(scopedObservation(
          metricId: 'host.uptime_seconds',
          value: {'float': 1.0},
          unit: {'custom': 'seconds'},
          sourceMs: 1700000000000,
          receivedMs: 1700000000000)),
      Observation.fromJson(scopedObservation(
          metricId: 'host.uptime_seconds',
          value: {'float': 31.0},
          unit: {'custom': 'seconds'},
          sourceMs: 1700000030000,
          receivedMs: 1700000030000)),
    ];
    expect(seriesGapLimit(samples), 45000);
    expect(
        continuesSeries(samples.first, samples.last, seriesGapLimit(samples)),
        isTrue);
    // The legacy rule keeps its own limit.
    expect(continuesTrend(samples.first, samples.last), isFalse);
  });
}
