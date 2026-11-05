import 'dart:async';
import 'dart:convert';
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
