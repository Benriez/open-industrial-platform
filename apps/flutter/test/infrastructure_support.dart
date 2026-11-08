import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/models/infrastructure.dart';

/// Sanitized, explicitly marked OIP-009 UI contract fixture. Never used to
/// populate a real Core or to claim a secured browser E2E result.
InfrastructureBootstrap infrastructureFixture({
  bool restricted = false,
  bool empty = false,
  String principal = 'fixture-operator',
}) {
  if (empty) {
    const hierarchy = AuthorizedHierarchy.empty;
    final raw = _scoped([], [], [], [], []);
    return InfrastructureBootstrap(
      principalIdentity: principal,
      hierarchy: hierarchy,
      snapshot: AuthorizedSnapshot.fromJson(raw),
      inventory: const [],
      findings: const [],
      origin: InfrastructureDataOrigin.contractFixture,
    );
  }

  final organizations = [
    const AuthorizedOrganization('org-a', 'Organization A'),
    if (!restricted) const AuthorizedOrganization('org-b', 'Organization B'),
  ];
  final infrastructures = [
    const AuthorizedInfrastructure('infra-a1', 'org-a', 'Infrastructure A1'),
    if (!restricted) ...const [
      AuthorizedInfrastructure('infra-a2', 'org-a', 'Infrastructure A2'),
      AuthorizedInfrastructure('infra-b1', 'org-b', 'Infrastructure B1'),
    ],
  ];
  final sites = [
    const AuthorizedSite('site-a1-1', 'infra-a1', 'Site 1'),
    if (!restricted) ...const [
      AuthorizedSite('site-a1-2', 'infra-a1', 'Site 2'),
      AuthorizedSite('site-a2-1', 'infra-a2', 'Site 3'),
      AuthorizedSite('site-b1-1', 'infra-b1', 'Site 4'),
    ],
  ];
  final locations = [
    _location('org-a', 'infra-a1', 'site-a1-1', 'source-a1'),
    if (!restricted) ...[
      _location('org-a', 'infra-a1', 'site-a1-2', 'source-a1b'),
      _location('org-a', 'infra-a2', 'site-a2-1', 'source-a2'),
      _location('org-b', 'infra-b1', 'site-b1-1', 'source-b1'),
    ],
  ];

  final devices = <_FixtureDevice>[
    const _FixtureDevice('device-a1', 'Pump A1', 'sensor', 'site-a1-1', 'org-a',
        'infra-a1', ['source-a1'], 'receiving'),
    if (!restricted) ...[
      const _FixtureDevice('device-a1-manual', 'Manual Valve A1', 'industrial_device',
          'site-a1-2', 'org-a', 'infra-a1', [], 'no_collector'),
      const _FixtureDevice('device-a2', 'Gateway A2', 'network_device', 'site-a2-1',
          'org-a', 'infra-a2', ['source-a2'], 'stale'),
      const _FixtureDevice('device-b1', 'Sensor B1', 'sensor', 'site-b1-1', 'org-b',
          'infra-b1', ['source-b1'], 'receiving'),
      const _FixtureDevice('device-b1-manual', 'Manual Drive B1', 'industrial_device',
          'site-b1-1', 'org-b', 'infra-b1', [], 'no_collector'),
    ],
  ];
  final deviceIds = devices.map((item) => item.id).toSet();
  // A source remains a registry object even when no device is associated.
  final visibleLocations = locations;
  final sourceIds = visibleLocations.map((item) => item.sourceId).toList();
  final sources = [
    for (final id in sourceIds)
      _source(id, stale: id == 'source-a2'),
  ];
  final observations = [
    for (final device in devices)
      if (device.sourceIds.isNotEmpty)
        _observation(device.id, device.sourceIds.single,
            stale: device.telemetry == 'stale'),
  ];
  final events = [
    for (final (index, id) in sourceIds.indexed)
      _event(id, index + 1,
          id == 'source-a2' ? 'DataLoss' : 'Reconnected'),
  ];
  final raw = _scoped(sources, devices, observations, events, visibleLocations);
  final inventory = devices.map((item) => item.toInventory()).toList();
  final findings = <DeterministicFinding>[
    if (sourceIds.contains('source-a2'))
      DeterministicFinding.fromJson({
        'id': 'finding-a2-gap',
        'rule_id': 'collection-gap',
        'rule_version': 1,
        'statement': 'Dokumentierte Collection-Lücke in Infrastructure A2',
        'status': 'documented',
        'evaluated_start_ms': 1800000000000,
        'evaluated_end_ms': 1800000001000,
        'evidence': [
          {'category': 'gap', 'id': 'gap-a2', 'source': 'source-a2'}
        ],
        'missing_evidence': const [],
      }),
  ];
  assert(deviceIds.length == devices.length);
  return InfrastructureBootstrap(
    principalIdentity: principal,
    hierarchy: AuthorizedHierarchy(
      organizations: organizations,
      infrastructures: infrastructures,
      sites: sites,
      locations: visibleLocations,
    ),
    snapshot: AuthorizedSnapshot.fromJson(raw),
    inventory: inventory,
    findings: findings,
    origin: InfrastructureDataOrigin.contractFixture,
  );
}

class _FixtureDevice {
  final String id,
      name,
      type,
      siteId,
      organizationId,
      infrastructureId,
      telemetry;
  final List<String> sourceIds;
  const _FixtureDevice(this.id, this.name, this.type, this.siteId,
      this.organizationId, this.infrastructureId, this.sourceIds, this.telemetry);

  Json json() => {
        'id': id,
        'name': name,
        'kind': type,
        'location': physicalLocation,
        'connection': sourceIds.isEmpty ? 'No collector' : 'OPC UA',
        'simulated': false,
        'is_faulted': false,
        'data_source_id': sourceIds.firstOrNull,
        'health': {
          'reachability': 'unknown',
          'vpn_transport': 'unknown',
          'agent_availability': 'unknown',
          'service_health': 'not_evaluated',
          'telemetry_freshness': telemetry,
        },
      };

  String get physicalLocation => '$siteId / test fixture';

  InventoryDevice toInventory() => InventoryDevice.fromJson({
        'record': {
          'device': {
            'id': id,
            'display_name': name,
            'device_type': type,
            'site_id': siteId,
            'metadata': {'physical_location': physicalLocation},
          },
          'registration': 'registered',
          'origin': 'manual_operator',
          'created_ms': 1800000000000,
          'updated_ms': 1800000000000,
          'registered_by': 'fixture-operator',
          'revision': 1,
        },
        'organization_id': organizationId,
        'infrastructure_id': infrastructureId,
        'sources': sourceIds,
        'connectivity': 'unknown',
        'telemetry': telemetry,
        'health': 'not_evaluated',
        'monitoring_simulated': sourceIds.isEmpty ? false : null,
      });
}

HierarchyLocation _location(
        String org, String infra, String site, String source) =>
    HierarchyLocation(
        organizationId: org,
        infrastructureId: infra,
        siteId: site,
        sourceId: source);

Json _source(String id, {bool stale = false}) => {
      'id': id,
      'name': 'Collector ${id.toUpperCase()}',
      'entity_id': 'device-${id.split('-').last}',
      'simulated': false,
      'reachability': stale ? 'unknown' : 'reachable',
      'connection': stale ? 'disconnected' : 'connected',
      'service': 'unknown',
      'freshness': stale ? 'stale' : 'fresh',
      'validity': 'valid',
      'last_received_ms': 1800000000000,
      'last_error': stale ? 'fixture disconnected source' : null,
    };

Json _observation(String device, String source, {bool stale = false}) => {
      'entity_id': device,
      'metric_id': 'temperature',
      'data_source_id': source,
      'value': {'float': 61.2},
      'unit': 'celsius',
      'quality': 'good',
      'freshness': stale ? 'stale' : 'fresh',
      'timestamps': {
        'source': 1800000000000,
        'server': 1800000000001,
        'received': 1800000000002,
      },
      'status_code': 0,
      'collection_error': null,
      'simulation_origin': null,
    };

Json _event(String source, int sequence, String kind) => {
      'id': 'event-$source-$sequence',
      'sequence': sequence,
      'context': {'origin_class': 'external', 'data_source_id': source},
      'event': {
        kind: {
          'at': 1800000000000 + sequence * 1000,
          'reason': 'sanitized fixture event',
          if (kind == 'DataLoss')
            'gap': {
              'started_at': 1800000000000,
              'ended_at': 1800000001000,
              'reason': 'documented fixture gap',
            },
        },
      },
    };

Json _scoped(
  List<Json> sources,
  List<_FixtureDevice> devices,
  List<Json> observations,
  List<Json> events,
  List<HierarchyLocation> locations,
) =>
    {
      'sources': sources,
      'devices': devices.map((item) => item.json()).toList(),
      'observations': observations,
      'events': events,
      'locations': locations
          .map((item) => {
                'organization_id': item.organizationId,
                'infrastructure_id': item.infrastructureId,
                'site_id': item.siteId,
                'source_id': item.sourceId,
              })
          .toList(),
      'resync_required': true,
      'replay_supported': false,
    };
