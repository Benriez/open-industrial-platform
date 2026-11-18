import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'contracts.dart';

/// Transport provenance for the global context. A fixture is never promoted to
/// an authorized live read by the presentation layer.
enum InfrastructureDataOrigin { liveApi, contractFixture }

enum InfrastructureContextStatus {
  idle,
  loading,
  ready,
  unavailable,
  unauthenticated,
  permissionDenied,
}

enum InfrastructureSelectionKind {
  unified,
  organization,
  infrastructure,
  site,
  source,
}

/// The operator's selected presentation scope. It never grants authority.
///
/// Parent IDs are denormalized only after they have been resolved through the
/// authorized Core hierarchy. They make the complete cache/query key explicit.
class InfrastructureSelection {
  final InfrastructureSelectionKind kind;
  final String? organizationId;
  final String? infrastructureId;
  final String? siteId;
  final String? sourceId;

  const InfrastructureSelection._(
    this.kind, {
    this.organizationId,
    this.infrastructureId,
    this.siteId,
    this.sourceId,
  });

  const InfrastructureSelection.unified()
      : this._(InfrastructureSelectionKind.unified);

  const InfrastructureSelection.organization(String id)
      : this._(InfrastructureSelectionKind.organization, organizationId: id);

  const InfrastructureSelection.infrastructure(
      String organizationId, String infrastructureId)
      : this._(InfrastructureSelectionKind.infrastructure,
            organizationId: organizationId,
            infrastructureId: infrastructureId);

  const InfrastructureSelection.site(
      String organizationId, String infrastructureId, String siteId)
      : this._(InfrastructureSelectionKind.site,
            organizationId: organizationId,
            infrastructureId: infrastructureId,
            siteId: siteId);

  const InfrastructureSelection.source(String organizationId,
      String infrastructureId, String siteId, String sourceId)
      : this._(InfrastructureSelectionKind.source,
            organizationId: organizationId,
            infrastructureId: infrastructureId,
            siteId: siteId,
            sourceId: sourceId);

  bool get isUnified => kind == InfrastructureSelectionKind.unified;

  String get id => switch (kind) {
        InfrastructureSelectionKind.unified => 'all',
        InfrastructureSelectionKind.organization => organizationId!,
        InfrastructureSelectionKind.infrastructure => infrastructureId!,
        InfrastructureSelectionKind.site => siteId!,
        InfrastructureSelectionKind.source => sourceId!,
      };

  String get scopeKey => [
        kind.name,
        organizationId ?? '-',
        infrastructureId ?? '-',
        siteId ?? '-',
        sourceId ?? '-',
      ].map(Uri.encodeComponent).join('/');

  /// Typed Core query fields. Empty unified queries mean the full authorized
  /// scope; they do not mean an anonymous/global installation query.
  Map<String, String> get query => {
        if (organizationId != null) 'organization': organizationId!,
        if (infrastructureId != null) 'infrastructure': infrastructureId!,
        if (siteId != null) 'site': siteId!,
        if (sourceId != null) 'source': sourceId!,
      };

  (String, String?) get settingsTarget => switch (kind) {
        InfrastructureSelectionKind.organization =>
          ('organization', organizationId),
        InfrastructureSelectionKind.infrastructure =>
          ('infrastructure', infrastructureId),
        InfrastructureSelectionKind.site => ('site', siteId),
        InfrastructureSelectionKind.source => ('source', sourceId),
        InfrastructureSelectionKind.unified => ('platform', null),
      };

  bool matches({
    String? organizationId,
    String? infrastructureId,
    String? siteId,
    String? sourceId,
  }) {
    if (isUnified) return true;
    if (this.organizationId != null && organizationId != this.organizationId) {
      return false;
    }
    if (this.infrastructureId != null &&
        infrastructureId != this.infrastructureId) {
      return false;
    }
    if (this.siteId != null && siteId != this.siteId) return false;
    if (this.sourceId != null && sourceId != this.sourceId) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is InfrastructureSelection && other.scopeKey == scopeKey;

  @override
  int get hashCode => scopeKey.hashCode;
}

class AuthorizedOrganization {
  final String id, name;
  const AuthorizedOrganization(this.id, this.name);
  factory AuthorizedOrganization.fromJson(Json json) =>
      AuthorizedOrganization(json['id'] as String, json['name'] as String);
}

class AuthorizedInfrastructure {
  final String id, organizationId, name;
  const AuthorizedInfrastructure(this.id, this.organizationId, this.name);
  factory AuthorizedInfrastructure.fromJson(Json json) =>
      AuthorizedInfrastructure(json['id'] as String,
          json['organization_id'] as String, json['name'] as String);
}

class AuthorizedSite {
  final String id, infrastructureId, name;
  const AuthorizedSite(this.id, this.infrastructureId, this.name);
  factory AuthorizedSite.fromJson(Json json) => AuthorizedSite(
      json['id'] as String, json['infrastructure_id'] as String, json['name'] as String);
}

class HierarchyLocation {
  final String organizationId, infrastructureId, siteId, sourceId;
  const HierarchyLocation({
    required this.organizationId,
    required this.infrastructureId,
    required this.siteId,
    required this.sourceId,
  });
  factory HierarchyLocation.fromJson(Json json) => HierarchyLocation(
        organizationId: json['organization_id'] as String,
        infrastructureId: json['infrastructure_id'] as String,
        siteId: json['site_id'] as String,
        sourceId: json['source_id'] as String,
      );
}

class DevicePlacement {
  final String organizationId, infrastructureId, siteId;
  final List<String> sourceIds;
  const DevicePlacement({
    required this.organizationId,
    required this.infrastructureId,
    required this.siteId,
    this.sourceIds = const [],
  });
}

/// OIP-008.5 InventoryDevice projection. Registration and monitoring are
/// deliberately independent facts.
class InventoryDevice {
  final String id,
      name,
      type,
      siteId,
      organizationId,
      infrastructureId,
      registration,
      origin,
      connectivity,
      telemetry,
      health;
  final List<String> sourceIds;
  final int revision;
  final int? createdMs, updatedMs;
  final String? registeredBy, physicalLocation;
  final bool? monitoringSimulated;

  /// The metadata of the device as the Core holds it.
  ///
  /// An update of a device is a full replacement: the Core does not merge a
  /// partial device, so the client sends the metadata it read back.
  final Json? metadata;

  const InventoryDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.siteId,
    required this.organizationId,
    required this.infrastructureId,
    required this.registration,
    required this.origin,
    required this.connectivity,
    required this.telemetry,
    required this.health,
    required this.sourceIds,
    required this.revision,
    this.createdMs,
    this.updatedMs,
    this.registeredBy,
    this.physicalLocation,
    this.monitoringSimulated,
    this.metadata,
  });

  factory InventoryDevice.fromJson(Json json) {
    final record = json['record'] as Json;
    final device = record['device'] as Json;
    final metadata = device['metadata'] as Json? ?? const <String, dynamic>{};
    return InventoryDevice(
      id: device['id'] as String,
      name: device['display_name'] as String,
      type: device['device_type'] as String,
      siteId: device['site_id'] as String,
      organizationId: json['organization_id'] as String,
      infrastructureId: json['infrastructure_id'] as String,
      registration: record['registration'] as String,
      origin: record['origin'] as String,
      connectivity: json['connectivity'] as String,
      telemetry: json['telemetry'] as String,
      health: json['health'] as String,
      sourceIds:
          (json['sources'] as List).map((item) => item as String).toList(),
      revision: record['revision'] as int,
      createdMs: record['created_ms'] as int?,
      updatedMs: record['updated_ms'] as int?,
      registeredBy: record['registered_by'] as String?,
      physicalLocation: metadata['physical_location'] as String?,
      metadata: metadata,
      monitoringSimulated: json['monitoring_simulated'] as bool?,
    );
  }

  DevicePlacement get placement => DevicePlacement(
        organizationId: organizationId,
        infrastructureId: infrastructureId,
        siteId: siteId,
        sourceIds: sourceIds,
      );
}

class AuthorizedHierarchy {
  final List<AuthorizedOrganization> organizations;
  final List<AuthorizedInfrastructure> infrastructures;
  final List<AuthorizedSite> sites;
  final List<HierarchyLocation> locations;

  const AuthorizedHierarchy({
    required this.organizations,
    required this.infrastructures,
    required this.sites,
    required this.locations,
  });

  static const empty = AuthorizedHierarchy(
    organizations: [],
    infrastructures: [],
    sites: [],
    locations: [],
  );

  AuthorizedOrganization? organization(String id) =>
      organizations.where((item) => item.id == id).firstOrNull;
  AuthorizedInfrastructure? infrastructure(String id) =>
      infrastructures.where((item) => item.id == id).firstOrNull;
  AuthorizedSite? site(String id) => sites.where((item) => item.id == id).firstOrNull;
  HierarchyLocation? sourceLocation(String id) =>
      locations.where((item) => item.sourceId == id).firstOrNull;

  String organizationName(String? id) => id == null
      ? 'Nicht geliefert'
      : organization(id)?.name ?? 'Nicht autorisiert / nicht mehr vorhanden';
  String infrastructureName(String? id) => id == null
      ? 'Nicht geliefert'
      : infrastructure(id)?.name ?? 'Nicht autorisiert / nicht mehr vorhanden';
  String siteName(String? id) => id == null
      ? 'Nicht geliefert'
      : site(id)?.name ?? 'Nicht autorisiert / nicht mehr vorhanden';

  bool isValid(InfrastructureSelection selection) {
    if (selection.isUnified) return true;
    final organization = selection.organizationId == null
        ? null
        : this.organization(selection.organizationId!);
    if (organization == null) return false;
    final infrastructure = selection.infrastructureId == null
        ? null
        : this.infrastructure(selection.infrastructureId!);
    if (selection.infrastructureId != null &&
        (infrastructure == null ||
            infrastructure.organizationId != selection.organizationId)) {
      return false;
    }
    final site = selection.siteId == null ? null : this.site(selection.siteId!);
    if (selection.siteId != null &&
        (site == null || site.infrastructureId != selection.infrastructureId)) {
      return false;
    }
    if (selection.sourceId != null) {
      final location = sourceLocation(selection.sourceId!);
      return location != null &&
          location.organizationId == selection.organizationId &&
          location.infrastructureId == selection.infrastructureId &&
          location.siteId == selection.siteId;
    }
    return true;
  }

  String selectionLabel(InfrastructureSelection selection) {
    if (selection.isUnified) return 'Alle berechtigten Infrastrukturen';
    return switch (selection.kind) {
      InfrastructureSelectionKind.organization =>
        organizationName(selection.organizationId),
      InfrastructureSelectionKind.infrastructure =>
        infrastructureName(selection.infrastructureId),
      InfrastructureSelectionKind.site => siteName(selection.siteId),
      InfrastructureSelectionKind.source => selection.sourceId!,
      InfrastructureSelectionKind.unified => 'Alle berechtigten Infrastrukturen',
    };
  }

  String breadcrumb(InfrastructureSelection selection) {
    if (selection.isUnified) return selectionLabel(selection);
    final parts = <String>[
      if (selection.organizationId != null)
        organizationName(selection.organizationId),
      if (selection.infrastructureId != null)
        infrastructureName(selection.infrastructureId),
      if (selection.siteId != null) siteName(selection.siteId),
      if (selection.sourceId != null) selection.sourceId!,
    ];
    return parts.join(' / ');
  }
}

/// The v2 ScopedSnapshot is a distinct wire contract. The adapter below creates
/// a presentation Snapshot without pretending that platform-only system facts
/// were delivered by a tenant read.
class AuthorizedSnapshot {
  final List<SourceInfo> sources;
  final List<Device> devices;
  final List<Observation> observations;
  final List<CollectionEvent> events;
  final List<HierarchyLocation> locations;
  final List<NetworkLink> topology;
  final bool resyncRequired, replaySupported;
  final Json raw;

  const AuthorizedSnapshot({
    required this.sources,
    required this.devices,
    required this.observations,
    required this.events,
    required this.locations,
    required this.topology,
    required this.resyncRequired,
    required this.replaySupported,
    required this.raw,
  });

  factory AuthorizedSnapshot.fromJson(Json json) => AuthorizedSnapshot(
        sources: (json['sources'] as List)
            .map((item) => SourceInfo.fromJson(item as Json))
            .toList(),
        devices: (json['devices'] as List)
            .map((item) => Device.fromJson(item as Json))
            .toList(),
        observations: (json['observations'] as List)
            .map((item) => Observation.fromJson(item as Json))
            .toList(),
        events: (json['events'] as List)
            .map((item) => CollectionEvent.fromRecord(item as Json))
            .toList(),
        locations: (json['locations'] as List)
            .map((item) => HierarchyLocation.fromJson(item as Json))
            .toList(),
        topology: (json['topology'] as List? ?? const [])
            .map((item) => NetworkLink.fromJson(item as Json))
            .toList(),
        resyncRequired: json['resync_required'] as bool,
        replaySupported: json['replay_supported'] as bool,
        raw: json,
      );

  Snapshot toSnapshot() {
    final received = <int>[
      for (final source in sources)
        if (source.lastReceivedMs != null) source.lastReceivedMs!,
      for (final observation in observations)
        if (observation.receivedMs != null) observation.receivedMs!,
    ];
    final lastReceived = received.isEmpty ? null : received.reduce(math.max);
    final singleSource = sources.length == 1 ? sources.single : null;
    final simulated = sources.any((item) => item.simulated) ||
        devices.any((item) => item.simulated) ||
        observations.any((item) => item.simulated);
    return Snapshot.fromJson({
      'system': {
        'primary_source_id': singleSource?.id,
        'scenario': 'authorized_context',
        'opcua_status': singleSource?.connection ?? 'unknown',
        'subscription_status': 'unknown',
        'network_status': 'unknown',
        'security_blocker': 'unknown',
        'demo_controls': false,
        'simulated': simulated,
        'last_received_ms': lastReceived,
        'generated_at_ms': null,
        'persisted_observations': null,
        'cpu_percent': null,
        'gpu_percent': null,
        'ram_percent': null,
      },
      'devices': devices.map(_deviceJson).toList(),
      'metrics': observations.map(_observationJson).toList(),
      'incidents': const [],
      'topology': topology
          .map((link) => {
                'from': link.from,
                'to': link.to,
                'transport': link.transport,
                'latency_ms': link.latency,
                'packet_loss_percent': link.loss,
                'status': link.status,
                'simulated': link.simulated,
              })
          .toList(),
      '_incidents_delivered': false,
      '_topology_delivered': raw.containsKey('topology'),
      'sources': sources.map(_sourceJson).toList(),
      'records': events.map(_eventJson).toList(),
    });
  }

  static Json _deviceJson(Device value) => {
        'id': value.id,
        'name': value.name,
        'kind': value.kind,
        'location': value.location,
        'connection': value.connection,
        'simulated': value.simulated,
        'is_faulted': value.faulted,
        'data_source_id': value.sourceId,
        'health': {
          'reachability': value.health.reachability,
          'vpn_transport': value.health.vpn,
          'agent_availability': value.health.agent,
          'service_health': value.health.service,
          'telemetry_freshness': value.health.freshness,
        },
      };

  static Json _sourceJson(SourceInfo value) => {
        'id': value.id,
        'name': value.name,
        'entity_id': value.entityId,
        'simulated': value.simulated,
        'reachability': value.reachability,
        'connection': value.connection,
        'service': value.service,
        'freshness': value.freshness,
        'validity': value.validity,
        'last_received_ms': value.lastReceivedMs,
        'last_error': value.lastError,
      };

  static Json _observationJson(Observation value) => {
        'data_source_id': value.sourceId,
        'entity_id': value.entityId,
        'metric_id': value.metricId,
        'quality': value.quality,
        'freshness': value.freshness,
        'value': switch (value.value) {
          null => null,
          final bool item => {'boolean': item},
          final int item => {'integer': item},
          final num item => {'float': item.toDouble()},
          final item => {'text': item.toString()},
        },
        'unit': value.unit,
        'timestamps': {
          'source': value.sourceMs,
          'server': value.serverMs,
          'received': value.receivedMs,
        },
        'status_code': value.statusCode,
        'collection_error': value.collectionError,
        if (value.simulated)
          'simulation_origin': {'origin_id': value.sourceId},
      };

  static Json _eventJson(CollectionEvent value) => {
        'id': value.id,
        'sequence': value.sequence,
        'context': {
          'origin_class': value.originClass ?? 'unknown',
          'data_source_id': value.sourceId,
        },
        'event': {
          value.kind: {
            'at': value.atMs,
            'reason': value.reason,
            'dropped': value.dropped,
            if (value.gapStartedMs != null || value.gapEndedMs != null)
              'gap': {
                'started_at': value.gapStartedMs,
                'ended_at': value.gapEndedMs,
              },
          }
        },
      };
}

class DeterministicFinding {
  final String id, ruleId, ruleVersion, statement, status;
  final int evaluatedStartMs, evaluatedEndMs;
  final List<String> evidenceSourceIds;
  final List<String> missingEvidence;
  const DeterministicFinding({
    required this.id,
    required this.ruleId,
    required this.ruleVersion,
    required this.statement,
    required this.status,
    required this.evaluatedStartMs,
    required this.evaluatedEndMs,
    required this.evidenceSourceIds,
    required this.missingEvidence,
  });

  factory DeterministicFinding.fromJson(Json json) => DeterministicFinding(
        id: json['id'] as String,
        ruleId: json['rule_id'] as String,
        ruleVersion: '${json['rule_version']}',
        statement: json['statement'] as String,
        status: json['status'] as String,
        evaluatedStartMs: json['evaluated_start_ms'] as int,
        evaluatedEndMs: json['evaluated_end_ms'] as int,
        evidenceSourceIds: (json['evidence'] as List)
            .map((item) => (item as Json)['source'] as String)
            .toList(),
        missingEvidence: (json['missing_evidence'] as List)
            .map((item) => item as String)
            .toList(),
      );
}

class ContextEventPage {
  final List<CollectionEvent> events;
  final bool truncated;
  final String? nextCursor;
  final List<String> missingEvidence;
  final String timeSemantics;
  const ContextEventPage({
    required this.events,
    required this.truncated,
    required this.nextCursor,
    required this.missingEvidence,
    required this.timeSemantics,
  });
}

/// A service of the registry that the **operator declared**.
///
/// The Core measures no service: every record carries the provenance
/// `declared`, and the device of a record is resolved against the inventory —
/// a device that the Core does not hold leaves the relation unknown.
class ServiceRecord {
  final String id,
      name,
      kind,
      siteId,
      organizationId,
      infrastructureId,
      origin;
  final String? deviceId, endpoint;
  final int? port;
  final String state;

  const ServiceRecord({
    required this.id,
    required this.name,
    required this.kind,
    required this.siteId,
    required this.organizationId,
    required this.infrastructureId,
    required this.origin,
    required this.state,
    this.deviceId,
    this.endpoint,
    this.port,
  });

  factory ServiceRecord.fromJson(Json json) {
    final service = (json['service'] as Json?) ?? const {};
    return ServiceRecord(
      id: '${service['id'] ?? ''}',
      name: '${service['name'] ?? ''}',
      kind: '${service['kind'] ?? ''}',
      siteId: '${service['site_id'] ?? ''}',
      organizationId: '${json['organization_id'] ?? ''}',
      infrastructureId: '${json['infrastructure_id'] ?? ''}',
      origin: '${json['origin'] ?? 'unknown'}',
      state: '${service['state'] ?? 'unknown'}',
      deviceId: json['device_id'] as String?,
      endpoint: service['endpoint'] as String?,
      port: (service['port'] as num?)?.toInt(),
    );
  }

  /// Whether the Core could resolve the device of the declaration.
  bool get deviceIsResolved => deviceId != null && deviceId!.isNotEmpty;
}

class InfrastructureBootstrap {
  final String? principalIdentity;
  final AuthorizedHierarchy hierarchy;
  final AuthorizedSnapshot snapshot;
  final List<InventoryDevice>? inventory;
  final List<ServiceRecord>? services;
  final List<DeterministicFinding>? findings;
  final InfrastructureDataOrigin origin;

  const InfrastructureBootstrap({
    required this.principalIdentity,
    required this.hierarchy,
    required this.snapshot,
    required this.inventory,
    this.services,
    this.findings,
    required this.origin,
  });
}

/// One application-wide context owner. There are no page-local infrastructure
/// selections. Authorization data and selected presentation scope are separate.
class InfrastructureContext extends ChangeNotifier {
  InfrastructureContextStatus status = InfrastructureContextStatus.idle;
  AuthorizedHierarchy hierarchy = AuthorizedHierarchy.empty;
  InfrastructureSelection selection = const InfrastructureSelection.unified();
  String? principalIdentity;
  InfrastructureDataOrigin? origin;
  Object? error;
  bool reloading = false;
  int contextRevision = 0;
  int sessionGeneration = 0;
  List<InventoryDevice>? inventory = const [];
  /// The services of the authorized scope.
  ///
  /// `null` means that the Core does not deliver the registry at all: the
  /// surface names the absence instead of showing an empty registry that
  /// looks like a measurement.
  List<ServiceRecord>? services;
  List<DeterministicFinding>? findings = const [];

  bool get ready => status == InfrastructureContextStatus.ready;
  bool get hasInfrastructure => hierarchy.infrastructures.isNotEmpty;
  bool get isFixture => origin == InfrastructureDataOrigin.contractFixture;
  String get scopeSignature =>
      '${principalIdentity ?? 'unreported'}@$sessionGeneration/${selection.scopeKey}';
  String get selectedLabel => hierarchy.selectionLabel(selection);
  String get selectedBreadcrumb => hierarchy.breadcrumb(selection);

  void markLoading() {
    // Re-bootstrap must not expand a valid selected scope. Keep ready and its
    // projection intact while fresh authorization evidence is being read.
    reloading = true;
    if (!ready) status = InfrastructureContextStatus.loading;
    error = null;
    contextRevision++;
    notifyListeners();
  }

  /// Accepts a new authorized bootstrap.
  ///
  /// The identity of the session is the evidence of the principal. The Core
  /// has no whoami route, so the authorized session of the browser carries it.
  /// Without any identity evidence a new bootstrap is an unknown
  /// authorization generation and the selection resets to Unified: that is
  /// safer than carrying a selection across an unverifiable principal
  /// transition.
  void accept(InfrastructureBootstrap bootstrap, {String? sessionPrincipal}) {
    final identity = bootstrap.principalIdentity ?? sessionPrincipal;
    final identityChanged =
        origin != null && principalIdentity != null && identity != principalIdentity;
    final previousSignature = scopeSignature;
    final unverifiableIdentity =
        identity == null && principalIdentity == null && origin != null;
    var invalidate = identityChanged || unverifiableIdentity;
    if (identityChanged) selection = const InfrastructureSelection.unified();
    hierarchy = bootstrap.hierarchy;
    principalIdentity = identity;
    origin = bootstrap.origin;
    inventory = bootstrap.inventory;
    services = bootstrap.services;
    findings = bootstrap.findings;
    if (!hierarchy.isValid(selection)) {
      // Authorization revocation invalidates the selected UI context. No old
      // scoped data may survive as if it were still selected.
      selection = const InfrastructureSelection.unified();
      invalidate = true;
    }
    status = InfrastructureContextStatus.ready;
    reloading = false;
    error = null;
    contextRevision++;
    if (invalidate || previousSignature != scopeSignature) sessionGeneration++;
    notifyListeners();
  }

  /// Accepts a new authorized SSE payload without changing the selected scope.
  /// The payload itself is already filtered by the Core for this principal.
  void acceptData() {
    if (!ready) return;
    contextRevision++;
    notifyListeners();
  }

  void select(InfrastructureSelection next) {
    if (!ready) {
      throw StateError('No authorized infrastructure context is available');
    }
    if (!hierarchy.isValid(next)) {
      throw ArgumentError('The requested context is not authorized');
    }
    if (selection == next) return;
    selection = next;
    contextRevision++;
    notifyListeners();
  }

  void markUnavailable([Object? cause]) {
    status = InfrastructureContextStatus.unavailable;
    reloading = false;
    error = cause;
    hierarchy = AuthorizedHierarchy.empty;
    inventory = null;
    services = null;
    findings = null;
    origin = null;
    selection = const InfrastructureSelection.unified();
    contextRevision++;
    notifyListeners();
  }

  void markIdentityFailure(Object cause) {
    final unauthenticated = cause.toString().contains('UNAUTHENTICATED');
    status = unauthenticated
        ? InfrastructureContextStatus.unauthenticated
        : InfrastructureContextStatus.permissionDenied;
    error = cause;
    reloading = false;
    hierarchy = AuthorizedHierarchy.empty;
    inventory = null;
    services = null;
    findings = null;
    origin = null;
    principalIdentity = null;
    selection = const InfrastructureSelection.unified();
    sessionGeneration++;
    contextRevision++;
    notifyListeners();
  }

  DevicePlacement? devicePlacement(Device device) {
    final record = inventory
        ?.where((item) => item.id == device.id && item.registration == 'registered')
        .firstOrNull;
    if (record != null) {
      final site = hierarchy.site(record.siteId);
      final infrastructure = site == null
          ? null
          : hierarchy.infrastructure(site.infrastructureId);
      if (site == null ||
          infrastructure == null ||
          infrastructure.id != record.infrastructureId ||
          infrastructure.organizationId != record.organizationId) {
        return null;
      }
      return record.placement;
    }
    final source = device.sourceId;
    if (source == null) return null;
    final location = hierarchy.sourceLocation(source);
    if (location == null) return null;
    return DevicePlacement(
      organizationId: location.organizationId,
      infrastructureId: location.infrastructureId,
      siteId: location.siteId,
      sourceIds: [source],
    );
  }

  DevicePlacement? sourcePlacement(String? sourceId) {
    if (sourceId == null) return null;
    final location = hierarchy.sourceLocation(sourceId);
    if (location == null) return null;
    final site = hierarchy.site(location.siteId);
    final infrastructure = site == null
        ? null
        : hierarchy.infrastructure(site.infrastructureId);
    if (site == null ||
        infrastructure == null ||
        infrastructure.id != location.infrastructureId ||
        infrastructure.organizationId != location.organizationId) {
      return null;
    }
    return DevicePlacement(
      organizationId: location.organizationId,
      infrastructureId: location.infrastructureId,
      siteId: location.siteId,
      sourceIds: [sourceId],
    );
  }

  List<InventoryDevice> get selectedInventory => (inventory ?? const [])
      .where((item) => selection.matches(
            organizationId: item.organizationId,
            infrastructureId: item.infrastructureId,
            siteId: item.siteId,
            sourceId: selection.sourceId == null
                ? null
                : item.sourceIds.contains(selection.sourceId)
                    ? selection.sourceId
                    : null,
          ))
      .toList();

  /// Presentation-only projection of an already authorized snapshot. Scoped
  /// REST reads remain mandatory for bounded/scalable detail queries.
  Snapshot project(Snapshot authorized) {
    if (!ready || selection.isUnified) return authorized;
    bool placed(DevicePlacement? placement) => placement != null &&
        selection.matches(
          organizationId: placement.organizationId,
          infrastructureId: placement.infrastructureId,
          siteId: placement.siteId,
          sourceId: selection.sourceId == null
              ? null
              : placement.sourceIds.contains(selection.sourceId)
                  ? selection.sourceId
                  : null,
        );
    final devices = authorized.devices
        .where((device) => placed(devicePlacement(device)))
        .toList();
    final deviceIds = devices.map((item) => item.id).toSet();
    final sources = authorized.sources
        .where((source) => placed(sourcePlacement(source.id)))
        .toList();
    final sourceIds = sources.map((item) => item.id).toSet();
    return authorized.project(
      devices: devices,
      sources: sources,
      metrics: authorized.metrics
          .where((item) => item.sourceId != null && sourceIds.contains(item.sourceId))
          .toList(),
      incidents: authorized.incidents
          .where((item) => deviceIds.contains(item.deviceId))
          .toList(),
      topology: authorized.topology
          .where((item) =>
              deviceIds.contains(item.from) && deviceIds.contains(item.to))
          .toList(),
      recentEvents: authorized.recentEvents
          .where((item) => item.sourceId != null && sourceIds.contains(item.sourceId))
          .toList(),
    );
  }
}
