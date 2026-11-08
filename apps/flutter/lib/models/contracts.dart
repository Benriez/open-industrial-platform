typedef Json = Map<String, dynamic>;

class Health {
  final String reachability, vpn, agent, service, freshness;
  Health.fromJson(Json j)
      : reachability = j['reachability'] as String,
        vpn = j['vpn_transport'] as String,
        agent = j['agent_availability'] as String,
        service = j['service_health'] as String,
        freshness = j['telemetry_freshness'] as String;
}

class Device {
  final String id, name, kind, location, connection;
  final bool simulated;
  final bool? faulted;
  final String? sourceId;
  final Health health;
  Device.fromJson(Json j)
      : id = j['id'] as String,
        name = j['name'] as String,
        kind = j['kind'] as String,
        location = j['location'] as String,
        connection = j['connection'] as String,
        simulated = j['simulated'] as bool,
        faulted = j['is_faulted'] as bool?,
        sourceId = j['data_source_id'] as String?,
        health = Health.fromJson(j['health'] as Json);
  // Absence remains unknown; classification belongs to the Rust service.
  bool get isFaulted => faulted == true;
}

String observationKey(Observation observation) =>
    '${observation.sourceId ?? ''}\u001f${observation.entityId}\u001f${observation.metricId}';

class Observation {
  final String entityId, metricId, quality, freshness, unit;
  final String? sourceId;
  final Object? value;
  final bool valueValid;
  final int? sourceMs;
  final int? serverMs, receivedMs, statusCode;
  final int? virtualTimeMs;
  final String? collectionError;
  final bool simulated;
  Observation.fromJson(Json j)
      : sourceId = j['data_source_id'] as String?,
        entityId = j['entity_id'] as String,
        metricId = j['metric_id'] as String,
        quality = j['quality'] as String,
        freshness = j['freshness'] as String,
        value = _parseValue(j['value']),
        valueValid = j['value'] == null ||
            (j['value'] is Json && (j['value'] as Json).length == 1),
        unit = _parseUnit(j['unit']),
        sourceMs = _timestamp(j, 'source'),
        serverMs = _timestamp(j, 'server'),
        receivedMs = _timestamp(j, 'received'),
        statusCode = j['status_code'] as int?,
        virtualTimeMs = j['simulation_origin'] is Json
            ? (j['simulation_origin'] as Json)['virtual_time_ms'] as int?
            : null,
        collectionError = j['collection_error'] as String?,
        simulated = j['simulation_origin'] != null;

  static Object? _parseValue(Object? raw) =>
      raw is Json ? raw.values.firstOrNull : null;

  static int? _timestamp(Json json, String key) {
    final timestamps = json['timestamps'];
    if (timestamps is! Json) return null;
    final value = timestamps[key];
    return value is int &&
            value >= -8640000000000000 &&
            value <= 8640000000000000
        ? value
        : null;
  }

  static String _parseUnit(Object? raw) {
    if (raw is String) return raw;
    if (raw is Json && raw.length == 1 && raw.values.single is String) {
      return raw.values.single as String;
    }
    // Keep the remaining snapshot usable while making the violation visible.
    return 'invalid';
  }

  double? get number => valueValid && value is num && (value as num).isFinite
      ? (value as num).toDouble()
      : null;
  String get symbol => switch (unit) {
        'celsius' => '°C',
        'kilo_pascal' => 'kPa',
        'count' => 'Stk.',
        'none' => '',
        'invalid' => 'Einheit ungültig',
        _ => unit
      };
  String get display => !valueValid
      ? 'Ungültiger Wert'
      : value == null
          ? 'Unbekannt'
          : value is double
              ? (value as double).toStringAsFixed(1)
              : value.toString();
}

class Incident {
  final String id, title, category, deviceId;
  final bool simulated;
  final List<String> supporting, contradicting, missing, timeline;
  Incident.fromJson(Json j)
      : id = j['id'] as String,
        title = j['title'] as String,
        category = j['category'] as String,
        deviceId = j['device_id'] as String,
        simulated = j['simulated'] as bool,
        supporting = List<String>.from(j['supporting'] as List),
        contradicting = List<String>.from(j['contradicting'] as List),
        missing = List<String>.from(j['missing'] as List),
        timeline = List<String>.from(j['timeline'] as List);
}

class NetworkLink {
  final String from, to, transport, status;
  final double? latency, loss;
  final bool simulated;
  NetworkLink.fromJson(Json j)
      : from = j['from'] as String,
        to = j['to'] as String,
        transport = j['transport'] as String,
        status = j['status'] as String,
        latency = (j['latency_ms'] as num?)?.toDouble(),
        loss = (j['packet_loss_percent'] as num?)?.toDouble(),
        simulated = j['simulated'] as bool;
}

class SystemStatus {
  final String scenario, opcua, subscription, network, blocker;
  final String? primarySourceId;
  final bool demoControls, simulated;
  final int? lastReceivedMs;

  /// Platform lifecycle facts are absent from a tenant ScopedSnapshot. Null is
  /// intentional: a context projection must never synthesize a timestamp or a
  /// tenant-wide persisted-observation count.
  final int? generatedMs, persisted;
  final double? cpu, gpu, ram;
  SystemStatus.fromJson(Json j)
      : primarySourceId = j['primary_source_id'] as String?,
        scenario = j['scenario'] as String,
        opcua = j['opcua_status'] as String,
        subscription = j['subscription_status'] as String,
        network = j['network_status'] as String,
        blocker = j['security_blocker'] as String,
        demoControls = j['demo_controls'] as bool,
        simulated = j['simulated'] as bool,
        lastReceivedMs = j['last_received_ms'] as int?,
        generatedMs = j['generated_at_ms'] as int?,
        persisted = j['persisted_observations'] as int?,
        cpu = (j['cpu_percent'] as num?)?.toDouble(),
        gpu = (j['gpu_percent'] as num?)?.toDouble(),
        ram = (j['ram_percent'] as num?)?.toDouble();

  SystemStatus projected({required String? primarySourceId}) =>
      SystemStatus.fromJson({
        'primary_source_id': primarySourceId,
        'scenario': scenario,
        'opcua_status': primarySourceId == null ? 'unknown' : opcua,
        'subscription_status': subscription,
        'network_status': network,
        'security_blocker': blocker,
        'demo_controls': demoControls,
        'simulated': simulated,
        'last_received_ms': lastReceivedMs,
        'generated_at_ms': generatedMs,
        'persisted_observations': persisted,
        'cpu_percent': cpu,
        'gpu_percent': gpu,
        'ram_percent': ram,
      });
}

class CollectionEvent {
  final String kind;
  final String? id, originClass;
  final int? atMs, gapStartedMs, gapEndedMs;
  final String? reason, sourceId;
  final int? sequence, dropped;

  CollectionEvent.fromJson(Json j)
      : id = null,
        originClass = null,
        sourceId = null,
        sequence = null,
        dropped = _eventBody(j)?['dropped'] as int?,
        kind = j.keys.firstOrNull ?? 'unknown',
        atMs = _eventBody(j)?['at'] as int?,
        reason = _eventBody(j)?['reason'] as String?,
        gapStartedMs = _gapField(j, 'started_at'),
        gapEndedMs = _gapField(j, 'ended_at');

  static int? _gapField(Json json, String key) {
    final gap = _eventBody(json)?['gap'];
    final value = gap is Json ? gap[key] : null;
    return value is int ? value : null;
  }

  CollectionEvent.fromRecord(Json record)
      : id = record['id'] as String?,
        originClass = (record['context'] as Json)['origin_class'] as String?,
        sourceId = (record['context'] as Json)['data_source_id'] as String,
        sequence = record['sequence'] as int,
        kind = (record['event'] as Json).keys.firstOrNull ?? 'unknown',
        atMs = _eventBody(record['event'] as Json)?['at'] as int?,
        reason = _eventBody(record['event'] as Json)?['reason'] as String?,
        dropped = _eventBody(record['event'] as Json)?['dropped'] as int?,
        gapStartedMs = _gapField(record['event'] as Json, 'started_at'),
        gapEndedMs = _gapField(record['event'] as Json, 'ended_at');

  /// OIP-008.2 DiagnosticItem(category=event) projection. Diagnostic events
  /// have a stable evidence ID but no source-local sequence field.
  factory CollectionEvent.fromDiagnostic(Json item) =>
      CollectionEvent.fromDiagnosticRecord(item['record'] as Json);

  CollectionEvent.fromDiagnosticRecord(Json record)
      : id = record['id'] as String,
        originClass = record['origin'] as String,
        sourceId = record['source'] as String,
        sequence = null,
        kind = _diagnosticKind(record['kind'] as String),
        atMs = record['at_ms'] as int?,
        reason = _eventBody(record['event'] as Json)?['reason'] as String?,
        dropped = _eventBody(record['event'] as Json)?['dropped'] as int?,
        gapStartedMs = _gapField(record['event'] as Json, 'started_at'),
        gapEndedMs = _gapField(record['event'] as Json, 'ended_at');

  static String _diagnosticKind(String value) => switch (value) {
        'connection_lost' => 'ConnectionLost',
        'reconnected' => 'Reconnected',
        'subscription_error' => 'SubscriptionError',
        'data_loss' => 'DataLoss',
        'observation' => 'Observation',
        _ => value,
      };

  static Json? _eventBody(Json json) {
    final key = json.keys.firstOrNull;
    final value = key == null ? null : json[key];
    return value is Json ? value : null;
  }

  int? get gapMs => kind == 'DataLoss' ||
          gapStartedMs == null ||
          gapEndedMs == null ||
          gapEndedMs! < gapStartedMs!
      ? null
      : gapEndedMs! - gapStartedMs!;
}

enum CoreLifecycle {
  initializing,
  ready,
  degraded,
  stopping,
  stopped,
  failed,
  unknown
}

/// Display projection of the existing Rust CoreHealth DTO; never inferred from transport.
class CoreHealthView {
  final CoreLifecycle lifecycle;
  final bool? live, ready, persistenceHealthy;
  CoreHealthView.fromJson(Json json)
      : lifecycle = CoreLifecycle.values.firstWhere(
            (value) => value.name == json['lifecycle'],
            orElse: () => CoreLifecycle.unknown),
        live = json['live'] is bool ? json['live'] as bool : null,
        ready = json['ready'] is bool ? json['ready'] as bool : null,
        persistenceHealthy = json['persistence_healthy'] is bool
            ? json['persistence_healthy'] as bool
            : null;
}

class Snapshot {
  final CoreHealthView core;
  final SystemStatus system;
  final List<Device> devices;
  final List<Observation> metrics;
  final List<Incident> incidents;
  final List<NetworkLink> topology;
  final List<SourceInfo> sources;
  final List<CollectionEvent> recentEvents;

  /// ScopedSnapshot does not carry findings or topology. Absence of a wire
  /// collection must not be presented as a measured zero.
  final bool incidentsDelivered, topologyDelivered;
  String? get primarySourceId =>
      system.primarySourceId ??
      (metrics.map((o) => o.sourceId).toSet().length == 1
          ? metrics.firstOrNull?.sourceId
          : null);
  Observation? get primaryTemperature => metrics
      .where((o) =>
          primarySourceId != null &&
          o.sourceId == primarySourceId &&
          o.entityId == 'M-01' &&
          o.metricId == 'temperature')
      .firstOrNull;
  Snapshot.fromJson(Json j)
      : incidentsDelivered = j['_incidents_delivered'] as bool? ??
            j['incidents'] is List,
        topologyDelivered =
            j['_topology_delivered'] as bool? ?? j['topology'] is List,
        core = CoreHealthView.fromJson(
            j['core'] is Json ? j['core'] as Json : const {}),
        system = SystemStatus.fromJson(j['system'] as Json),
        devices = (j['devices'] as List)
            .map((v) => Device.fromJson(v as Json))
            .toList(),
        metrics = (j['metrics'] as List)
            .map((v) => Observation.fromJson(v as Json))
            .toList(),
        incidents = (j['incidents'] as List)
            .map((v) => Incident.fromJson(v as Json))
            .toList(),
        topology = (j['topology'] as List? ?? const [])
            .map((v) => NetworkLink.fromJson(v as Json))
            .toList(),
        sources = (j['sources'] as List? ?? const [])
            .map((v) => SourceInfo.fromJson(v as Json))
            .toList(),
        recentEvents = j['records'] is List
            ? (j['records'] as List)
                .map((v) => CollectionEvent.fromRecord(v as Json))
                .toList()
            : (j['collection_events'] as List? ?? const [])
                .map((v) => CollectionEvent.fromJson(v as Json))
                .toList();

  Snapshot._({
    required this.core,
    required this.system,
    required this.devices,
    required this.metrics,
    required this.incidents,
    required this.topology,
    required this.sources,
    required this.recentEvents,
    required this.incidentsDelivered,
    required this.topologyDelivered,
  });

  /// Restricts the existing presentation DTO to a selected, already authorized
  /// UI context. This is not an authorization boundary.
  Snapshot project({
    List<Device>? devices,
    List<Observation>? metrics,
    List<Incident>? incidents,
    List<NetworkLink>? topology,
    List<SourceInfo>? sources,
    List<CollectionEvent>? recentEvents,
  }) {
    final projectedSources = sources ?? this.sources;
    return Snapshot._(
      core: core,
      system: system.projected(
        primarySourceId: projectedSources.length == 1
            ? projectedSources.single.id
            : null,
      ),
      devices: devices ?? this.devices,
      metrics: metrics ?? this.metrics,
      incidents: incidents ?? this.incidents,
      topology: topology ?? this.topology,
      sources: projectedSources,
      recentEvents: recentEvents ?? this.recentEvents,
      incidentsDelivered: incidentsDelivered,
      topologyDelivered: topologyDelivered,
    );
  }
}

extension SnapshotAlarm on Snapshot {
  /// Presentation of the authoritative Rust classification, scoped by registry ID.
  /// Raw alarm samples never bypass source, freshness or quality rules in the Core.
  bool hasAlarm({String? deviceId}) => devices.any((device) =>
      (deviceId == null || device.id == deviceId) &&
      device.health.service == 'alarm');
}

class SourceInfo {
  final String id, name, entityId;
  final bool simulated;
  final String reachability, connection, service, freshness, validity;
  final int? lastReceivedMs;
  final String? lastError;

  SourceInfo._({
    required this.id,
    required this.name,
    required this.entityId,
    required this.simulated,
    required this.reachability,
    required this.connection,
    required this.service,
    required this.freshness,
    required this.validity,
    required this.lastReceivedMs,
    required this.lastError,
  });

  SourceInfo withPrimarySnapshotStatus(
          String liveConnection, String liveFreshness, int? receivedMs) =>
      SourceInfo._(
        id: id,
        name: name,
        entityId: entityId,
        simulated: simulated,
        reachability: reachability,
        connection: liveConnection,
        service: service,
        freshness: liveFreshness,
        validity: validity,
        lastReceivedMs: receivedMs,
        lastError: lastError,
      );

  SourceInfo.fromJson(Json j)
      : id = j['id'] as String,
        name = j['name'] as String,
        entityId = j['entity_id'] as String,
        simulated = j['simulated'] as bool,
        reachability = j['reachability'] as String,
        connection = j['connection'] as String,
        service = j['service'] as String,
        freshness = j['freshness'] as String,
        validity = j['validity'] as String,
        lastReceivedMs = j['last_received_ms'] as int?,
        lastError = j['last_error'] as String?;
}

class OpcNode {
  final String id, name, folder, dataType, access;
  final int namespace;
  final Observation? observation;
  OpcNode.fromJson(Json j)
      : id = j['node_id'] as String,
        name = j['name'] as String,
        folder = j['folder'] as String,
        dataType = j['data_type'] as String,
        access = j['access'] as String,
        namespace = j['namespace'] as int,
        observation = j['observation'] == null
            ? null
            : Observation.fromJson(j['observation'] as Json);
}

class NodePage {
  final List<OpcNode> items;
  final int total, offset, limit;
  NodePage.fromJson(Json j)
      : items = (j['items'] as List)
            .map((v) => OpcNode.fromJson(v as Json))
            .toList(),
        total = j['total'] as int,
        offset = j['offset'] as int,
        limit = j['limit'] as int;
}
