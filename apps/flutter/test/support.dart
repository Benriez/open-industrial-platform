import 'dart:async';
import 'dart:convert';
import 'package:oip_dashboard/core/sse.dart';
import 'package:oip_dashboard/features/settings/settings_models.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/models/infrastructure.dart';
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

class FakeApi extends OipApi {
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
  bool failSources = false;
  List<SourceInfo>? availableSources;
  final nodeRequests =
      <({String? source, String search, String folder, int offset})>[];

  /// When set, node pages are generated with this many bulk items per page
  /// (plus the six M-01 process variables on the first page) so list density,
  /// grouping and keyboard navigation can be exercised with real pagination.
  int? generatedBulkNodes;

  /// The folders that the Core delivers with every page. `null` is the
  /// default of the fixture; an empty list is a Core that names no folder.
  List<String>? deliveredFolders;

  /// The folders that the Core delivers for one source. A folder of a
  /// previous source never survives the switch to another one.
  Map<String, List<String>>? deliveredFoldersBySource;
  Object? scenarioFailure;
  String? chosen;
  Json data = fixture();
  InfrastructureBootstrap? infrastructure;
  Object? infrastructureFailure;

  @override
  Future<InfrastructureBootstrap> infrastructureBootstrap() async {
    final failure = infrastructureFailure;
    if (failure != null) throw failure;
    final value = infrastructure;
    if (value == null) {
      throw const ApiFailure('No authorized fixture configured',
          code: 'UNSUPPORTED');
    }
    return value;
  }

  @override
  Stream<ServerEvent> infrastructureStream() {
    attempts++;
    events = StreamController<ServerEvent>();
    if (emitAutomatically) scheduleMicrotask(() => emit());
    return events.stream;
  }

  @override
  Future<List<SourceInfo>> contextSources(
      InfrastructureContext context) async {
    final value = infrastructure;
    if (value == null) return sources();
    return context.project(value.snapshot.toSnapshot()).sources;
  }

  @override
  Future<List<CollectionEvent>> contextCollectionEvents(
      InfrastructureContext context) async {
    final value = infrastructure;
    if (value == null) return collectionEvents();
    return context.project(value.snapshot.toSnapshot()).recentEvents;
  }

  @override
  Future<List<Observation>> contextDeviceMetrics(
      String id, InfrastructureContext context) async {
    final value = infrastructure;
    if (value == null) return deviceMetrics(id);
    return context
        .project(value.snapshot.toSnapshot())
        .metrics
        .where((item) => item.entityId == id)
        .toList();
  }

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
    if (events.isClosed) return;
    final payload = infrastructure?.snapshot.raw ?? data;
    events.add(ServerEvent('snapshot', jsonEncode(payload)));
  }

  @override
  Future<void> scenario(String name) async {
    if (scenarioFailure != null) throw scenarioFailure!;
    chosen = name;
  }

  @override
  Future<List<SourceInfo>> sources() async {
    if (failSources) throw Exception('sources unavailable');
    return availableSources ??
        [
          SourceInfo.fromJson({
            'id': 'oip-local-simulation-v1',
            'name': 'Local OPC-UA Simulation',
            'entity_id': 'M-01',
            'simulated': (data['system'] as Json)['simulated'] as bool,
            'reachability': 'reachable',
            'connection': 'connected',
            'service': 'healthy',
            'freshness': 'fresh',
            'validity': 'valid',
            'last_received_ms': 1800000000000,
            'last_error': null,
          })
        ];
  }

  @override
  Future<NodePage> nodes(String search, String folder, int offset,
      {String? source, int limit = 40}) async {
    if (failNodes) throw Exception('nodes unavailable');
    nodeRequests
        .add((source: source, search: search, folder: folder, offset: offset));
    final generated = generatedBulkNodes;
    if (generated != null) {
      final process = [
        ('alarm_active', 'Boolean', {'boolean': false}),
        ('motor_running', 'Boolean', {'boolean': true}),
        ('operating_mode', 'String', {'text': 'automatic'}),
        ('pressure', 'Double', {'float': 320.5}),
        ('temperature', 'Double', {'float': 61.2}),
        ('units_produced', 'UInt64', {'integer': 3}),
      ];
      final all = <Json>[
        if (folder != 'Bulk')
          for (final (name, type, value) in process)
            {
              'node_id': 'ns=2;s=$name',
              'name': name,
              'folder': 'M-01',
              'data_type': type,
              'access': 'Read',
              'namespace': 2,
              'observation': {
                ...observation(),
                'metric_id': name,
                'data_source_id': source ?? 'oip-local-simulation-v1',
                'value': value,
                'unit': name == 'temperature' ? 'celsius' : 'none'
              }
            },
        if (folder != 'M-01')
          for (var i = 0; i < generated; i++)
            {
              'node_id': 'ns=2;s=bulk.${i.toString().padLeft(4, '0')}',
              'name': 'bulk.${i.toString().padLeft(4, '0')}',
              'folder': 'Bulk',
              'data_type': 'Double',
              'access': 'Read',
              'namespace': 2,
              'observation': {
                ...observation(),
                'metric_id': 'bulk.$i',
                'data_source_id': source ?? 'oip-local-simulation-v1',
                'value': {'float': 1000000.0 + i},
                'unit': 'none'
              }
            },
      ].where((node) => (node['name'] as String).contains(search)).toList();
      return NodePage.fromJson({
        'items': all.skip(offset).take(nodeLimit).toList(),
        'total': all.length,
        'offset': offset,
        'limit': nodeLimit,
        // The Core delivers the folders of the address space with every page.
        'folders': deliveredFoldersBySource?[source ?? ''] ??
            deliveredFolders ??
            const ['Bulk', 'M-01']
      });
    }
    return NodePage.fromJson({
      'folders': deliveredFoldersBySource?[source ?? ''] ??
          deliveredFolders ??
          const ['M-01'],
      'items': [
        {
          'node_id': 'ns=2;s=temperature',
          'name': 'temperature',
          'folder': 'M-01',
          'data_type': 'Double',
          'access': 'Read',
          'namespace': 2,
          'observation': {
            ...observation(),
            'data_source_id': source ?? 'oip-local-simulation-v1',
          }
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
  void cancelDeviceRequests() {}

  @override
  Future<SettingsSnapshot> settings({
    String scope = 'platform',
    String? scopeId,
    String? key,
    bool catalog = false,
  }) async {
    throw const ApiFailure('Settings-Read nicht konfiguriert.',
        code: 'UNSUPPORTED');
  }

  @override
  Future<ManagementReport> management(String section) async {
    throw const ApiFailure('Management-Read nicht konfiguriert.',
        code: 'UNSUPPORTED');
  }

  @override
  void cancelSettingsRequests() {}

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
