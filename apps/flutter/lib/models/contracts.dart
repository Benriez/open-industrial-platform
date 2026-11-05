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

class Observation {
  final String entityId, metricId, quality, freshness, unit;
  final String? sourceId;
  final Object? value;
  final bool valueValid;
  final int? sourceMs;
  final int? serverMs, receivedMs, statusCode;
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
  final int generatedMs, persisted;
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
        generatedMs = j['generated_at_ms'] as int,
        persisted = j['persisted_observations'] as int,
        cpu = (j['cpu_percent'] as num?)?.toDouble(),
        gpu = (j['gpu_percent'] as num?)?.toDouble(),
        ram = (j['ram_percent'] as num?)?.toDouble();
}

class CollectionEvent {
  final String kind;
  final int? atMs, gapStartedMs, gapEndedMs;
  final String? reason, sourceId;
  final int? sequence, dropped;

  CollectionEvent.fromJson(Json j)
      : sourceId = null,
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
      : sourceId = (record['context'] as Json)['data_source_id'] as String,
        sequence = record['sequence'] as int,
        kind = (record['event'] as Json).keys.firstOrNull ?? 'unknown',
        atMs = _eventBody(record['event'] as Json)?['at'] as int?,
        reason = _eventBody(record['event'] as Json)?['reason'] as String?,
        dropped = _eventBody(record['event'] as Json)?['dropped'] as int?,
        gapStartedMs = _gapField(record['event'] as Json, 'started_at'),
        gapEndedMs = _gapField(record['event'] as Json, 'ended_at');

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
      : core = CoreHealthView.fromJson(
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
        topology = (j['topology'] as List)
            .map((v) => NetworkLink.fromJson(v as Json))
            .toList();
}

extension SnapshotAlarm on Snapshot {
  /// Presentation of the authoritative Rust classification, scoped by registry ID.
  /// Raw alarm samples never bypass source, freshness or quality rules in the Core.
  bool hasAlarm({String? deviceId}) => devices.any((device) =>
      (deviceId == null || device.id == deviceId) &&
      device.health.service == 'alarm');
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
