import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/features/device_connection_panel.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/services/api.dart';

/// One measurement as the Core serializes it: the snake_case envelope of
/// `ObservationEnvelope` with an externally tagged `MetricValue` and `Unit`.
Json observation({
  required String metricId,
  required Object? value,
  Object unit = 'none',
  String quality = 'good',
  String freshness = 'fresh',
}) =>
    {
      'entity_id': 'unit-device',
      'data_source_id': 'unit-source',
      'metric_id': metricId,
      'value': value,
      'unit': unit,
      'quality': quality,
      'freshness': freshness,
      'timestamps': {
        'source': 1700000000000,
        'server': null,
        'received': 1700000000100
      },
      'status_code': 0,
      'collection_error': null,
      'simulation_origin': null
    };

Json connectionResult({List<Json> observations = const []}) => {
      'profiles': <dynamic>[],
      'plan': null,
      'connection': {
        'device_id': 'unit-device',
        'source_id': 'unit-source',
        'endpoint': {'host': '127.0.0.1', 'port': 22, 'user': 'unit'},
        'fingerprint': 'SHA256:unit-fixture',
        'verified_identity': {
          'hostname': 'unit-fixture',
          'operating_system': 'Darwin',
          'architecture': 'arm64',
          'cpu_info': 'Apple M2',
          'model': 'Mac14,3',
          'memory_total_bytes': 17179869184,
          'memory_used_bytes': 8589934592,
          'uptime_seconds': 12345,
          'disks': '[]',
          'interfaces': '[]',
          'unavailable': <dynamic>[],
          'provenance': 'authenticated SSH host report',
          'captured_at_ms': 1700000000000,
        },
        'verified_at_ms': 1700000000000,
        'monitoring_enabled': true,
        'poll_seconds': 30,
        'revision': 2,
        'last_attempt_ms': 1700000000000,
        'last_success_ms': 1700000000000,
        'error': null,
        'status': 'collecting',
        'observations': observations,
      },
      'last_attempt': null,
    };

Future<OipController> controllerFor(List<Json> observations) async {
  final client = MockClient((r) async {
    expect(r.url.path, '/api/v2/device-connections');
    return http.Response(jsonEncode(connectionResult(observations: observations)),
        200);
  });
  return OipController(
      RestApi(Uri.parse('http://127.0.0.1:8080'), client: client),
      retryDelay: const Duration(milliseconds: 1));
}

Future<void> showPanel(WidgetTester tester, OipController controller) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: DeviceConnectionPanel(
                  controller: controller, deviceId: 'unit-device')))));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets(
      'The connection panel shows the authorized monitoring observations',
      (tester) async {
    final controller = await controllerFor([
      observation(metricId: 'host.os', value: {'text': 'Darwin'}),
      observation(
          metricId: 'host.memory_total_bytes',
          value: {'unsigned_integer': 17179869184},
          unit: {'custom': 'bytes'}),
      observation(
          metricId: 'host.uptime_seconds',
          value: {'float': 12345.5},
          unit: {'custom': 'seconds'}),
    ]);
    await showPanel(tester, controller);
    // The measurement identifier is visible, so an operator can tell which
    // collected value belongs to which metric.
    expect(find.text('host.os'), findsOneWidget);
    expect(find.text('host.memory_total_bytes'), findsOneWidget);
    expect(find.text('host.uptime_seconds'), findsOneWidget);
    // The value, the unit and the state come from the Core response.
    expect(find.textContaining('Darwin · Gut · Aktuell'), findsOneWidget);
    expect(find.textContaining('17179869184 bytes · Gut · Aktuell'),
        findsOneWidget);
    expect(find.textContaining('12345.5 seconds · Gut · Aktuell'),
        findsOneWidget);
    expect(find.textContaining('Gut · Aktuell'), findsNWidgets(3));
    // Disposing the panel ends its refresh timer.
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
      'A missing measurement stays unknown and is never replaced by a substitute',
      (tester) async {
    final controller = await controllerFor([
      observation(
          metricId: 'host.model', value: null, quality: 'unknown',
          freshness: 'unknown'),
    ]);
    await showPanel(tester, controller);
    expect(find.text('host.model'), findsOneWidget);
    expect(find.textContaining('Unbekannt'), findsOneWidget);
    expect(find.textContaining('Ungültiger Wert'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
      'Without any observation the panel keeps the honest empty state',
      (tester) async {
    final controller = await controllerFor([]);
    await showPanel(tester, controller);
    expect(
        find.textContaining(
            'Noch keine aktuellen Messwerte. Verifizierung allein ist kein kontinuierliches Monitoring.'),
        findsOneWidget);
    expect(find.text('host.os'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
