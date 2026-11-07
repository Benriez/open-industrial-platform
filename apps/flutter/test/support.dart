import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oip_dashboard/core/sse.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/services/api.dart';

Json observation({Object? value = 61.2}) => {
      'entity_id': 'M-01',
      'metric_id': 'temperature',
      'data_source_id': 'oip-local-simulation-v1',
      'value': value == null ? null : {'float': value},
      'unit': 'celsius',
      'quality': value == null ? 'bad' : 'good',
      'freshness': 'fresh',
      'timestamps': {
        'source': 1700000000000,
        'server': 1700000000000,
        'received': 1800000000000
      },
      'status_code': 0,
      'collection_error': value == null ? 'invalid_measurement' : null,
      'simulation_origin': {'origin_id': 'oip-local-simulation-v1'}
    };
Json fixture() => {
      'system': {
        'primary_source_id': 'oip-local-simulation-v1',
        'scenario': 'normal',
        'opcua_status': 'connected',
        'subscription_status': 'active',
        'network_status': 'unknown',
        'security_blocker': 'RUSTSEC-2023-0071',
        'demo_controls': true,
        'simulated': true,
        'last_received_ms': 1800000000000,
        'generated_at_ms': 1800000000000,
        'persisted_observations': 6,
        'cpu_percent': null,
        'gpu_percent': null,
        'ram_percent': null
      },
      'devices': [
        for (final name in ['M-01', 'evo'])
          {
            'id': name,
            'is_faulted': false,
            'data_source_id': name == 'M-01' ? 'oip-local-simulation-v1' : null,
            'name': name == 'evo' ? 'AMD EVO-X2' : 'OPC-UA-Sensoren · M-01',
            'kind': 'Compute',
            'location': 'LAN',
            'connection': 'OPC UA',
            'simulated': true,
            'health': {
              'reachability': 'reachable',
              'vpn_transport': 'not_applicable',
              'agent_availability': 'unknown',
              'service_health': 'unknown',
              'telemetry_freshness': 'fresh'
            }
          }
      ],
      'metrics': [observation()],
      'incidents': <dynamic>[],
      'topology': [
        {
          'from': 'M-01',
          'to': 'evo',
          'transport': 'LAN',
          'status': 'connected',
          'latency_ms': 1.5,
          'packet_loss_percent': 0.0,
          'simulated': true
        }
      ],
    };

class FakeApi implements OipApi {
  StreamController<ServerEvent> events = StreamController<ServerEvent>();
  int attempts = 0;
  bool fail = false;
  bool failEvents = false;
  bool failMetrics = false;
  bool failNodes = false;
  bool emitAutomatically = true;
  int metricRequests = 0;
  int closeCalls = 0;
  int nodeLimit = 40;
  Object? scenarioFailure;
  String? chosen;
  Json data = fixture();
  @override
  Future<Snapshot> initial() async {
    if (fail) throw Exception('offline');
    return Snapshot.fromJson(data);
  }

  @override
  Stream<ServerEvent> stream() {
    attempts++;
    events = StreamController<ServerEvent>();
    if (emitAutomatically) scheduleMicrotask(() => emit());
    return events.stream;
  }

  void emit() {
    if (!events.isClosed) events.add(ServerEvent('snapshot', jsonEncode(data)));
  }

  @override
  Future<void> scenario(String name) async {
    if (scenarioFailure != null) throw scenarioFailure!;
    chosen = name;
  }

  @override
  Future<NodePage> nodes(String search, String folder, int offset) async {
    if (failNodes) throw Exception('nodes unavailable');
    return NodePage.fromJson({
      'items': [
        {
          'node_id': 'ns=2;s=temperature',
          'name': 'temperature',
          'folder': 'M-01',
          'data_type': 'Double',
          'access': 'Read',
          'namespace': 2,
          'observation': observation()
        }
      ],
      'total': 1006,
      'offset': offset,
      'limit': nodeLimit
    });
  }

  @override
  Future<List<Observation>> deviceMetrics(String id) async {
    metricRequests++;
    if (failMetrics) throw Exception('metrics unavailable');
    return id == 'M-01' ? [Observation.fromJson(observation())] : [];
  }

  @override
  Future<List<CollectionEvent>> collectionEvents() async {
    if (failEvents) throw Exception('events unavailable');
    return [
      CollectionEvent.fromJson({
        'ConnectionLost': {
          'at': 1700000000000,
          'reason': 'Test-Verbindungsverlust'
        }
      }),
      CollectionEvent.fromJson({
        'Reconnected': {
          'at': 1700000002500,
          'gap': {
            'started_at': 1700000000000,
            'ended_at': 1700000002500,
            'reason': 'Test-Reconnect'
          }
        }
      })
    ];
  }

  @override
  void disconnect() {
    if (!events.isClosed) events.close();
  }

  @override
  void close() {
    closeCalls++;
    disconnect();
  }
}

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
  String entityId = 'device-a',
  String sourceId = 'source-ssh',
}) =>
    {
      'entity_id': entityId,
      'data_source_id': sourceId,
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

/// An API client that serves the scoped projection of a managed session.
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
