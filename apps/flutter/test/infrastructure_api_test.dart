import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/models/infrastructure.dart';
import 'package:oip_dashboard/services/api.dart';

import 'infrastructure_support.dart';

void main() {
  test('v2 bootstrap parses hierarchy, scoped snapshot and source-less inventory',
      () async {
    final fixture = infrastructureFixture();
    final requests = <http.Request>[];
    Json page(List<Map<String, dynamic>> items) => {
          'items': items,
          'offset': 0,
          'limit': 100,
          'has_more': false,
        };
    final api = RestApi(
      Uri.parse('http://127.0.0.1:8080'),
      client: MockClient((request) async {
        requests.add(request);
        final body = switch (request.url.path) {
          '/api/v2/organizations' => page([
              for (final item in fixture.hierarchy.organizations)
                {'id': item.id, 'name': item.name},
            ]),
          '/api/v2/infrastructures' => page([
              for (final item in fixture.hierarchy.infrastructures)
                {
                  'id': item.id,
                  'organization_id': item.organizationId,
                  'name': item.name,
                },
            ]),
          '/api/v2/sites' => page([
              for (final item in fixture.hierarchy.sites)
                {
                  'id': item.id,
                  'infrastructure_id': item.infrastructureId,
                  'name': item.name,
                },
            ]),
          '/api/v2/snapshot' => fixture.snapshot.raw,
          '/api/v2/inventory/devices' => {
            'items': [
              {
                'record': {
                  'device': {
                    'id': 'device-a1-manual',
                    'display_name': 'Manual Valve A1',
                    'device_type': 'industrial_device',
                    'site_id': 'site-a1-2',
                    'metadata': <String, dynamic>{},
                  },
                  'registration': 'registered',
                  'origin': 'manual_operator',
                  'created_ms': 1800000000000,
                  'updated_ms': 1800000000000,
                  'registered_by': 'fixture-operator',
                  'revision': 1,
                },
                'organization_id': 'org-a',
                'infrastructure_id': 'infra-a1',
                'sources': <String>[],
                'connectivity': 'unknown',
                'telemetry': 'no_collector',
                'health': 'not_evaluated',
                'monitoring_simulated': false,
              },
            ],
            'offset': 0,
            'limit': 100,
            'has_more': false,
            'status': 'Devices registered · Telemetry unavailable',
            'management_channel': 'offline_requires_restart',
          },
          '/api/v2/services' => {
            'items': [
              {
                'service': {
                  'id': 'svc-a1-opcua',
                  'name': 'OPC-UA server of the plant',
                  'site_id': 'site-a1-2',
                  'device_id': 'device-a1-manual',
                  'kind': 'opcua',
                  'endpoint': 'opc.tcp://127.0.0.1:4840',
                  'port': 4840,
                  'state': 'running',
                },
                'organization_id': 'org-a',
                'infrastructure_id': 'infra-a1',
                'device_id': 'device-a1-manual',
                'origin': 'declared',
              },
            ],
            'offset': 0,
            'limit': 100,
            'has_more': false,
            'status': 'Services declared · Measured by the operator',
            'management_channel': 'authenticated_local_operator',
          },
          '/api/v2/diagnostics/findings' => {
            'items': <dynamic>[],
            'truncated': false,
            'next_cursor': null,
            'missing_evidence': <dynamic>[],
            'time_semantics': 'event_time',
          },
          _ => <String, dynamic>{},
        };
        return http.Response(jsonEncode(body), 200, headers: {
          'content-type': 'application/json',
          'x-oip-contract-fixture': 'oip-009-contract-fixture',
          'x-oip-contract-principal': 'fixture-operator',
        });
      }),
    );
    final result = await api.infrastructureBootstrap();
    expect(result.principalIdentity, 'fixture-operator');
    expect(result.origin, InfrastructureDataOrigin.contractFixture);
    expect(result.hierarchy.organizations, hasLength(2));
    expect(result.hierarchy.infrastructures, hasLength(3));
    expect(result.snapshot.devices, hasLength(5));
    expect(result.inventory!.single.telemetry, 'no_collector');
    expect(result.inventory!.single.monitoringSimulated, isFalse);
    // The registry of the services that the operator declared: every record
    // carries the provenance `declared`, and the device of the record is the
    // device of the inventory.
    expect(result.services!.single.id, 'svc-a1-opcua');
    expect(result.services!.single.origin, 'declared');
    expect(result.services!.single.deviceId, 'device-a1-manual');
    expect(result.services!.single.deviceIsResolved, isTrue);
    expect(result.snapshot.toSnapshot().system.generatedMs, isNull);
    expect(result.snapshot.toSnapshot().system.persisted, isNull);
    expect(result.snapshot.toSnapshot().system.demoControls, isFalse);
    expect(requests.every((request) => !request.url.query.contains('token')), isTrue);
    expect(requests.every((request) => request.headers['authorization'] == null),
        isTrue);
    api.close();
  });

  test('Context reads carry full scope and never merge OPC-UA namespaces',
      () async {
    final fixture = infrastructureFixture();
    final requests = <http.Request>[];
    final source = (fixture.snapshot.raw['sources'] as List)
        .cast<Json>()
        .firstWhere((item) => item['id'] == 'source-a2');
    final api = RestApi(
      Uri.parse('http://127.0.0.1:8080'),
      client: MockClient((request) async {
        requests.add(request);
        final body = switch (request.url.path) {
          '/api/v2/sources' => [source],
          '/api/v2/events/history' => {
            'items': [
              {
                'category': 'event',
                'record': {
                  'id': 'evidence-event-a2',
                  'source': 'source-a2',
                  'origin': 'external',
                  'at_ms': 1800000000000,
                  'kind': 'data_loss',
                  'event': {
                    'DataLoss': {
                      'at': 1800000000000,
                      'reason': 'documented fixture gap',
                      'gap': {
                        'started_at': 1800000000000,
                        'ended_at': 1800000001000,
                      },
                    },
                  },
                  'observation_id': null,
                  'gap_id': 'gap-a2',
                },
              },
            ],
            'truncated': true,
            'next_cursor':
                '0000000000000000000000000000000000000000000000000000000000000064',
            'missing_evidence': <dynamic>[],
            'time_semantics': 'event_time',
          },
          '/api/v2/devices/device-a2' => {
            'device': fixture.snapshot.raw['devices']![2],
            'metrics': <dynamic>[],
          },
          '/api/v2/opcua/nodes' => {
            'items': <dynamic>[],
            'total': 0,
            'offset': 0,
            'limit': 40,
          },
          _ => <String, dynamic>{},
        };
        return http.Response(jsonEncode(body), 200, headers: {
          'content-type': 'application/json',
          'x-oip-contract-fixture': 'oip-009-contract-fixture',
        });
      }),
    );
    final context = InfrastructureContext();
    context.accept(fixture);
    context.select(const InfrastructureSelection.source(
        'org-a', 'infra-a2', 'site-a2-1', 'source-a2'));
    final sources = await api.contextSources(context);
    expect(sources.single.id, 'source-a2');
    final eventPage = await api.contextEventPage(context);
    expect(eventPage.truncated, isTrue);
    expect(eventPage.nextCursor, isNotNull);
    final events = eventPage.events;
    expect(events.single.id, 'evidence-event-a2');
    expect(events.single.kind, 'DataLoss');
    expect(events.single.gapStartedMs, 1800000000000);
    expect(events.single.gapEndedMs, 1800000001000);
    expect(events.single.gapMs, isNull,
        reason: 'DataLoss does not infer a duration from gap bounds');
    expect(await api.contextDeviceMetrics('device-a2', context), isEmpty);
    await api.contextNodes('', 'all', 0, context, source: 'source-a2');
    for (final request in requests) {
      if (request.url.path == '/api/v2/opcua/nodes') {
        expect(request.url.queryParameters['source'], 'source-a2');
      } else if (request.url.path != '/api/v2/devices/device-a2') {
        expect(request.url.queryParameters['organization'], 'org-a');
        expect(request.url.queryParameters['infrastructure'], 'infra-a2');
        expect(request.url.queryParameters['site'], 'site-a2-1');
        expect(request.url.queryParameters['source'], 'source-a2');
      }
      expect(request.headers['authorization'], isNull);
    }
    context.dispose();
    api.close();
  });
}
