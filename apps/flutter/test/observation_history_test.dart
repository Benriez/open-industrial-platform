import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oip_dashboard/features/device_history.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/models/history.dart';
import 'package:oip_dashboard/models/onboarding.dart';
import 'package:oip_dashboard/services/api.dart';
import 'support.dart';

/// One stored measurement exactly as the Core serializes it: the envelope of
/// `ObservationEnvelope` with an externally tagged `MetricValue` and `Unit`.
Json storedObservation({
  required String metricId,
  required Object? value,
  String unit = 'none',
  String quality = 'good',
  String freshness = 'stale',
  int receivedMs = 1700000000100,
}) =>
    {
      'entity_id': 'device-a',
      'data_source_id': 'source-a',
      'metric_id': metricId,
      'value': value,
      'unit': unit,
      'quality': quality,
      'freshness': freshness,
      'timestamps': {
        'source': 1700000000000,
        'server': null,
        'received': receivedMs,
      },
      'status_code': 0,
      'collection_error': null,
      'simulation_origin': null,
    };

/// The identity of a stored sample is unique in the Core. The fixture hands
/// out a distinct one for every sample it creates.
int _nextId = 0;

/// One page of the Core history: the tagged `DiagnosticItem` envelope around
/// the stored observation.
Json historyPage({
  List<Json> observations = const [],
  bool truncated = false,
  String? nextCursor,
  List<String> missingEvidence = const [],
  String timeSemantics = '',
}) =>
    {
      'items': [
        for (var index = 0; index < observations.length; index++)
          {
            'category': 'observation',
            'record': {'id': 'obs-${_nextId++}', 'observation': observations[index]},
          }
      ],
      'truncated': truncated,
      'next_cursor': nextCursor,
      'missing_evidence': missingEvidence,
      'time_semantics': timeSemantics,
    };

class HistoryApi extends FakeApi implements DeviceManagementApi {
  final List<String> requests = [];
  final List<HistoryPage> pages = [];
  Object? failure;
  int served = 0;
  @override
  bool get managed => true;

  @override
  Future<BrowserSession> session() async => BrowserSession.fromJson({
        'authenticated': true,
        'principal_id': 'server-bound',
        'mode': 'local_operator_session'
      });

  @override
  Future<BrowserSession> login(String code) => session();

  @override
  Future<void> logout() async {}

  @override
  Future<List<HierarchyItem>> hierarchy(
          String level, Map<String, String> scope) async =>
      [];

  @override
  Future<Json> inventory(String id) async => throw UnimplementedError();

  @override
  Future<void> register(Json device) async {}

  @override
  Future<void> update(Json device, {required int expectedRevision}) async {}

  @override
  Future<void> archive(String id, {required int expectedRevision}) async {}

  @override
  Future<ConnectionResult> connection(
          {String? deviceId, String? planId}) async =>
      ConnectionResult.fromJson({
        'profiles': [],
        'plan': null,
        'connection': null,
        'last_attempt': null
      });

  @override
  Future<ConnectionResult> configure(Json action) async =>
      throw UnimplementedError();

  @override
  Future<HistoryPage> observationHistory(
      {required String deviceId, String? cursor, int limit = 20}) async {
    requests.add('device=$deviceId cursor=${cursor ?? '-'} limit=$limit');
    if (failure != null) throw failure!;
    return pages[served++];
  }
}

Future<void> showSection(WidgetTester tester, HistoryApi api) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: DeviceHistorySection(api: api, deviceId: 'device-a')))));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  test('The history is requested for the device scope without a global scope',
      () async {
    late Uri requested;
    final client = MockClient((r) async {
      requested = r.url;
      return http.Response(
          jsonEncode(historyPage(observations: [
            storedObservation(metricId: 'host.os', value: {'text': 'Darwin'})
          ])),
          200);
    });
    final api = RestApi(Uri.parse('http://127.0.0.1:8080'), client: client);
    final page = await api.observationHistory(deviceId: 'device-a');
    expect(requested.path, '/api/v2/observations/history');
    expect(requested.queryParameters['device'], 'device-a');
    expect(requested.queryParameters['limit'], '20');
    // No organization, infrastructure or site is invented for the history.
    expect(requested.queryParameters.containsKey('organization'), isFalse);
    expect(requested.queryParameters.containsKey('infrastructure'), isFalse);
    expect(requested.queryParameters.containsKey('site'), isFalse);
    expect(requested.queryParameters.containsKey('cursor'), isFalse);
    expect(page.observations, hasLength(1));
    expect(page.observations.single.observation.metricId, 'host.os');
    expect(page.observations.single.observation.freshness, 'stale');
    expect(page.truncated, isFalse);
    expect(page.nextCursor, isNull);
  });

  test('A continuation is requested with the cursor the Core handed out',
      () async {
    late Uri requested;
    final client = MockClient((r) async {
      requested = r.url;
      return http.Response(jsonEncode(historyPage()), 200);
    });
    final api = RestApi(Uri.parse('http://127.0.0.1:8080'), client: client);
    await api.observationHistory(deviceId: 'device-a', cursor: 'cursor-token');
    expect(requested.queryParameters['cursor'], 'cursor-token');
    expect(requested.queryParameters['device'], 'device-a');
  });

  test('A page of another category is counted and never silently dropped',
      () async {
    final client = MockClient((r) async => http.Response(
        jsonEncode({
          'items': [
            {
              'category': 'observation',
              'record': {
                'id': 'obs-1',
                'observation': storedObservation(
                    metricId: 'host.os', value: {'text': 'Darwin'})
              }
            },
            {'category': 'gap', 'record': {'id': 'gap-1'}},
          ],
          'truncated': false,
          'next_cursor': null,
          'missing_evidence': <String>[],
          'time_semantics': '',
        }),
        200));
    final api = RestApi(Uri.parse('http://127.0.0.1:8080'), client: client);
    final page = await api.observationHistory(deviceId: 'device-a');
    expect(page.observations, hasLength(1));
    expect(page.otherItems, 1);
  });

  testWidgets('The stored samples are shown as history and never as live values',
      (tester) async {
    final api = HistoryApi()
      ..pages.add(HistoryPage.fromJson(historyPage(
        observations: [
          storedObservation(metricId: 'host.os', value: {'text': 'Darwin'}),
          storedObservation(
              metricId: 'host.memory_total_bytes',
              value: {'unsigned_integer': 17179869184},
              unit: 'custom'),
        ],
        missingEvidence: ['Samples without receive time are excluded'],
        timeSemantics: 'Observations: received time, stale historical values',
      )));
    await showSection(tester, api);
    // The identifier names the sample as history.
    expect(find.textContaining('host.os · Historie'), findsOneWidget);
    expect(find.textContaining('host.memory_total_bytes · Historie'),
        findsOneWidget);
    // The stored value and its unit come from the stored record.
    expect(find.textContaining('Darwin'), findsOneWidget);
    expect(find.textContaining('17179869184 custom'), findsOneWidget);
    // A stored sample is stale; the Core says so and the client does not
    // upgrade it to a live value.
    expect(find.textContaining('Veraltet'), findsNWidgets(2));
    expect(find.textContaining('Aktuell'), findsNothing);
    // The receive time the Core guarantees for the sample is reported.
    expect(find.textContaining('Empfangen 2023-11-14'), findsNWidgets(2));
    // The limits of the answer are shown, not hidden.
    expect(find.textContaining('Grenzen dieser Historie'), findsOneWidget);
    expect(find.textContaining('Samples without receive time are excluded'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('A truncated page offers the continuation the Core handed out',
      (tester) async {
    final api = HistoryApi()
      ..pages.add(HistoryPage.fromJson(historyPage(
        observations: [
          storedObservation(metricId: 'host.os', value: {'text': 'Darwin'})
        ],
        truncated: true,
        nextCursor: 'cursor-token',
      )))
      ..pages.add(HistoryPage.fromJson(historyPage(
        observations: [
          storedObservation(metricId: 'host.uptime_seconds',
              value: {'float': 12345.5})
        ],
      )));
    await showSection(tester, api);
    expect(find.textContaining('Neuere Einträge laden'), findsOneWidget);
    await tester.tap(find.textContaining('Neuere Einträge laden'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The continuation is requested with the cursor of the Core.
    expect(api.requests, ['device=device-a cursor=- limit=20',
      'device=device-a cursor=cursor-token limit=20']);
    // The second page is appended, the first one is kept.
    expect(find.textContaining('host.os · Historie'), findsOneWidget);
    expect(find.textContaining('host.uptime_seconds · Historie'),
        findsOneWidget);
    expect(find.textContaining('Neuere Einträge laden'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'The section recovers when the Core stores the samples of the device later',
      (tester) async {
    // A device without a source is not accessible yet. The section must not
    // stay on that answer: the collector stores the samples later.
    final api = HistoryApi()
      ..failure = const ApiFailure('Resource is not accessible',
          code: 'RESOURCE_NOT_ACCESSIBLE');
    await showSection(tester, api);
    expect(find.text('Historie nicht verfügbar'), findsOneWidget);
    api
      ..failure = null
      ..pages.add(HistoryPage.fromJson(historyPage(
        observations: [
          storedObservation(metricId: 'host.os', value: {'text': 'Darwin'})
        ],
      )));
    // The bounded refresh picks the stored samples up.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Historie nicht verfügbar'), findsNothing);
    expect(find.textContaining('host.os · Historie'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Without a stored sample the honest empty state is shown',
      (tester) async {
    final api = HistoryApi()..pages.add(HistoryPage.fromJson(historyPage()));
    await showSection(tester, api);
    expect(find.textContaining('Keine persistierten Messwerte'), findsOneWidget);
    expect(find.textContaining('kein Nachweis einer lückenlosen Überwachung'),
        findsOneWidget);
    expect(find.textContaining('host.os'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('A refused history is reported and no sample is invented',
      (tester) async {
    final api = HistoryApi()
      ..failure = const ApiFailure('Historie nicht verfügbar.',
          code: 'HISTORY_UNAVAILABLE');
    await showSection(tester, api);
    expect(find.text('Historie nicht verfügbar'), findsOneWidget);
    expect(find.textContaining('HISTORY_UNAVAILABLE'), findsOneWidget);
    expect(find.textContaining('host.os'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
