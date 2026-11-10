import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/core/sse.dart';
import 'package:oip_dashboard/features/device_connection_panel.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/models/history.dart';
import 'package:oip_dashboard/models/infrastructure.dart';
import 'package:oip_dashboard/models/onboarding.dart';
import 'package:oip_dashboard/services/api.dart';

/// The honest states of the connection of a device.
///
/// The gate G5 names the honest connection states. The Core derives **eight**
/// of them (`crates/oip-server/src/connection_service.rs`): `host_key_changed`,
/// `host_key_unknown`, `unreachable`, `verification_failed`, `collecting`,
/// `stale`, `collector_configured` and `ssh_verified`. This suite pins what
/// the **surface** shows for every one of them — a state that the client does
/// not know is named, never shown as the wire name of the Core. A regression
/// that showed a blocked connection as connected would break the promise of
/// the gate.

class _ConnectionApi extends OipApi implements DeviceManagementApi {
  _ConnectionApi(this.device);
  final DeviceConnection device;

  @override
  Future<ConnectionResult> connection({String? deviceId, String? planId}) async =>
      ConnectionResult.fromJson({
        'profiles': const [],
        'plan': null,
        'connection': {
          'device_id': device.deviceId,
          'status': device.status,
          'fingerprint': device.fingerprint,
          'endpoint': device.endpoint,
          'verified_identity': device.identity,
          'error': device.error,
          'monitoring_enabled': device.enabled,
          'revision': device.revision,
          'poll_seconds': device.pollSeconds,
          'last_attempt_ms': device.lastAttempt,
          'last_success_ms': device.lastSuccess,
          'observations': const [],
        },
        'last_attempt': null,
      });

  @override
  Future<ConnectionResult> configure(Json action) async =>
      throw UnimplementedError('the test changes nothing');

  @override
  Future<HistoryPage> observationHistory(
          {required String deviceId, String? cursor, int limit = 20}) =>
      throw UnimplementedError('the test reads no history');

  @override
  Future<Snapshot> initial() async => throw UnimplementedError();

  @override
  Stream<ServerEvent> stream() => const Stream<ServerEvent>.empty();

  @override
  Future<void> scenario(String name) async {}

  @override
  Future<List<SourceInfo>> sources() async => const [];

  @override
  Future<NodePage> nodes(String search, String folder, int offset,
          {String? source}) =>
      throw UnimplementedError();

  @override
  Future<List<Observation>> deviceMetrics(String id) async => const [];

  @override
  Future<List<CollectionEvent>> collectionEvents() async => const [];

  @override
  Future<BrowserSession> login(String code) => throw UnimplementedError();

  @override
  Future<List<HierarchyItem>> hierarchy(String level, Map<String, String> scope) =>
      throw UnimplementedError();

  @override
  Future<Json> inventory(String id) => throw UnimplementedError();

  @override
  Future<void> register(Json device) => throw UnimplementedError();

  @override
  Future<void> update(Json device, {required int expectedRevision}) =>
      throw UnimplementedError();

  @override
  Future<void> archive(String id, {required int expectedRevision}) =>
      throw UnimplementedError();

  @override
  Future<BrowserSession> session() => throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  bool get managed => true;

  @override
  void close() {}

  @override
  void disconnect() {}
}

DeviceConnection _connection(String status, {Json? error}) => DeviceConnection.fromJson({
      'device_id': 'existing-pi',
      'status': status,
      'fingerprint': 'SHA256:the-fingerprint-of-the-host',
      'endpoint': {'host': '127.0.0.1', 'port': 2222, 'user': 'operator'},
      'verified_identity': {
        'hostname': 'host-1',
        'operating_system': 'Darwin',
        'architecture': 'arm64',
        'cpu_info': 'Apple M1 Pro',
        'model': 'MacBookPro',
        'memory_total_bytes': 17179869184,
        'memory_used_bytes': 8589934592,
        'uptime_seconds': 3600,
        'captured_at_ms': 1800000000000,
        'disks': [
          {'filesystem': '/dev/disk3s1', 'mount': '/', 'total_bytes': 994662584320,
           'used_bytes': 100000000000, 'available_bytes': 894662584320}
        ],
        'interfaces': [
          {'name': 'en0', 'addresses': ['192.168.1.10']}
        ],
        'unavailable': ['gpu', 'temperature', 'cpu_utilization'],
        'provenance': 'authenticated SSH host report; fixed read-only query',
      },
      'error': error,
      'monitoring_enabled': true,
      'revision': 3,
      'poll_seconds': 10,
      'last_attempt_ms': 1800000000000,
      'last_success_ms': 1800000000000,
      'observations': const [],
    });

Future<void> _pumpPanel(
    WidgetTester tester, DeviceConnection connection) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 1000);
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final api = _ConnectionApi(connection);
  final controller = OipController(api);
  addTearDown(controller.dispose);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: DeviceConnectionPanel(controller: controller, deviceId: 'existing-pi'),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('A collecting connection is shown as collecting', (tester) async {
    await _pumpPanel(tester, _connection('collecting'));
    expect(find.text('Collecting · aktuelle Messwerte empfangen'), findsOneWidget);
    expect(find.text('Host-Key: SHA256:the-fingerprint-of-the-host'), findsOneWidget);
    expect(find.text('Read-only Monitoring'), findsOneWidget);
  });

  testWidgets('A verified connection without monitoring is shown as verified',
      (tester) async {
    await _pumpPanel(tester, _connection('ssh_verified'));
    expect(find.text('SSH Verified · Monitoring deaktiviert'), findsOneWidget);
  });

  testWidgets('A changed host key blocks the connection and is named',
      (tester) async {
    await _pumpPanel(tester, _connection('host_key_changed', error: {
          'code': 'HOST_KEY_CHANGED',
          'message': 'Der Host-Key des Hosts hat sich geändert.',
        }));
    expect(find.text('Host-Key geändert · Verbindung blockiert'), findsOneWidget);
    expect(find.textContaining('HOST_KEY_CHANGED'), findsOneWidget);
  });

  testWidgets('An unknown host key asks for the confirmation of the identity',
      (tester) async {
    await _pumpPanel(tester, _connection('host_key_unknown'));
    expect(
        find.text('Host-Key unbekannt · Identität vor der nächsten Verbindung bestätigen'),
        findsOneWidget);
  });

  testWidgets('An unreachable host is shown as unreachable', (tester) async {
    await _pumpPanel(tester, _connection('unreachable', error: {
          'code': 'SSH_CONNECTION_FAILED',
          'message': 'Die Verbindung ist fehlgeschlagen.',
        }));
    expect(
        find.text('Unreachable · tatsächlicher Verbindungsversuch fehlgeschlagen'),
        findsOneWidget);
    expect(find.textContaining('SSH_CONNECTION_FAILED'), findsOneWidget);
  });

  testWidgets('A stale measurement is shown as stale', (tester) async {
    await _pumpPanel(tester, _connection('stale'));
    expect(find.text('Stale · Messwerte veraltet'), findsOneWidget);
  });

  testWidgets('A monitoring without a measurement is shown as configured',
      (tester) async {
    await _pumpPanel(tester, _connection('collector_configured'));
    expect(find.text('Überwachung konfiguriert · noch keine Messwerte empfangen'),
        findsOneWidget);
  });

  testWidgets('A failed verification is shown as a failure', (tester) async {
    await _pumpPanel(tester, _connection('verification_failed', error: {
          'code': 'SSH_HOST_KEY_UNKNOWN',
          'message': 'Die Identität des Hosts konnte nicht bestätigt werden.',
        }));
    expect(find.text('Verifikation fehlgeschlagen · Identität nicht bestätigt'),
        findsOneWidget);
    expect(find.textContaining('SSH_HOST_KEY_UNKNOWN'), findsOneWidget);
  });

  testWidgets('A state that the client does not know is named, never shown as '
      'the wire name', (tester) async {
    await _pumpPanel(tester, _connection('a_state_of_the_future'));
    expect(find.text('Verbindungsstatus unbekannt'), findsOneWidget);
    expect(find.text('a_state_of_the_future'), findsNothing);
  });
}
