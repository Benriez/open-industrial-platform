import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/widgets/workstation.dart';
import 'support.dart';

const String _sim = 'oip-local-simulation-v1';

Json _device(
  String id, {
  String? source,
  String? name,
  String kind = 'Compute',
  String location = 'LAN',
  bool simulated = true,
}) =>
    {
      'id': id,
      'is_faulted': false,
      'data_source_id': source,
      'name': name ?? id,
      'kind': kind,
      'location': location,
      'connection': 'OPC UA',
      'simulated': simulated,
      'health': {
        'reachability': 'reachable',
        'vpn_transport': 'not_applicable',
        'agent_availability': 'unknown',
        'service_health': 'unknown',
        'telemetry_freshness': 'fresh',
      },
    };

Json _source(String id, {String? name}) => {
      'id': id,
      'name': name ?? id,
      'entity_id': 'M-01',
      'simulated': true,
      'reachability': 'reachable',
      'connection': 'connected',
      'service': 'healthy',
      'freshness': 'fresh',
      'validity': 'valid',
      'last_received_ms': 1800000000000,
      'last_error': null,
    };

Json _observation({
  String entity = 'M-01',
  String metric = 'temperature',
  String source = _sim,
  double value = 61.2,
}) =>
    {
      ...observation(),
      'entity_id': entity,
      'metric_id': metric,
      'data_source_id': source,
      'value': {'float': value},
    };

Json _incident({
  String id = 'oip.documented-collection-gap',
  String device = 'M-01',
  String title = 'Dokumentierter Collection-Gap',
}) =>
    {
      'id': id,
      'title': title,
      'category': 'collection',
      'device_id': device,
      'simulated': true,
      'supporting': <dynamic>[],
      'contradicting': <dynamic>[],
      'missing': <dynamic>[],
      'timeline': <dynamic>[],
    };

Json _record({
  String id = 'evt-1',
  String source = _sim,
  int sequence = 1,
  String kind = 'ConnectionLost',
  String? reason,
}) =>
    {
      'id': id,
      'context': {'origin_class': 'oip', 'data_source_id': source},
      'sequence': sequence,
      'event': {
        kind: {
          'at': 1700000000000,
          if (reason != null) 'reason': reason,
        },
      },
    };

class _SlowMetricsApi extends FakeApi {
  _SlowMetricsApi(this.delay);
  final Duration delay;

  @override
  Future<List<Observation>> deviceMetrics(String id) async {
    await Future<void>.delayed(delay);
    return super.deviceMetrics(id);
  }
}

Future<({FakeApi api, OipController controller})> _bootstrap(
  WidgetTester tester, {
  Size size = const Size(1440, 1000),
  Json? data,
  void Function(FakeApi)? configure,
  FakeApi Function()? apiFactory,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  final api = apiFactory?.call() ?? FakeApi();
  if (data != null) api.data = data;
  configure?.call(api);
  final controller = OipController(api)
    ..snapshot = Snapshot.fromJson(api.data)
    ..connection = 'live'
    ..workspaces.setExpertWorkspace(WorkspaceId.devices, true)
    ..workspaces.setInspectorOpen(WorkspaceId.devices, true);
  await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.binding.setSurfaceSize(null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  return (api: api, controller: controller);
}

Future<void> _navigate(WidgetTester tester, double width) async {
  if (width < 1080) {
    await tester.tap(find.byKey(const Key('open-navigation')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('nav-1')));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Finder _within(String key, Finder matching) => find.descendant(
      of: find.byKey(Key(key)),
      matching: matching,
    );

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('A selection and stale telemetry', () {
    testWidgets(
        'Selection drives Explorer, Workspace, Inspector and Related Activity',
        (tester) async {
      final data = fixture();
      data['sources'] = [_source(_sim, name: 'Local OPC-UA Simulation')];
      data['incidents'] = [_incident()];
      data['records'] = [_record(reason: 'Test-Verbindungsverlust')];
      await _bootstrap(tester, data: data);
      await _navigate(tester, 1440);

      // Before selection every pane states its empty scope honestly.
      expect(find.text('Gerät für die technische Untersuchung auswählen'),
          findsOneWidget);
      expect(
          find.byKey(const Key('devices-adaptive-inspector')), findsOneWidget);
      expect(
          find.text(
              'Bis zu vier Geräte über Compare auswählen. Unterschiedliche Messdimensionen werden nicht zu einer gemeinsamen Kennzahl verrechnet.'),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();

      // Engineering Workspace shows the selected device and its telemetry.
      expect(find.text('ENGINEERING WORKSPACE'), findsOneWidget);
      expect(
          _within('device-engineering-workspace',
              find.text('OPC-UA-Sensoren · M-01 · M-01')),
          findsOneWidget);
      expect(
          _within(
              'device-engineering-workspace', find.textContaining('61.2 °C')),
          findsOneWidget);
      expect(find.text('Fünf unabhängige Statusdimensionen'), findsOneWidget);

      // Telemetry tab renders the exact observation identity.
      await tester.tap(find.text('Telemetry'));
      await tester.pumpAndSettle();
      expect(find.text('M-01 · temperature'), findsOneWidget);
      expect(find.text('SIMULATED · OBSERVED · $_sim'), findsOneWidget);
      await tester.tap(find.text('Engineering'));
      await tester.pumpAndSettle();

      // Context Inspector follows the same device ID.
      expect(find.text('CONTEXT INSPECTOR'), findsOneWidget);
      expect(
          _within(
              'device-context-inspector', find.text('OPC-UA-Sensoren · M-01')),
          findsOneWidget);
      expect(find.text('Compute · $_sim'), findsOneWidget);

      // Related Activity lists exact device findings and source events.
      await tester.tap(find.byKey(const Key('device-activity-tab')));
      await tester.pumpAndSettle();
      expect(find.text('Dokumentierter Collection-Gap'), findsOneWidget);
      expect(find.text('ConnectionLost · $_sim'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Switching devices never shows the previous device telemetry',
        (tester) async {
      final app = await _bootstrap(tester);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();
      expect(
          _within(
              'device-engineering-workspace', find.textContaining('61.2 °C')),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('device-evo')));
      await tester.pumpAndSettle();
      expect(find.text('Keine Telemetrie für dieses Gerät verfügbar'),
          findsOneWidget);
      expect(find.textContaining('61.2'), findsNothing);
      expect(app.api.metricRequests, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('In-flight detail response of a deselected device is ignored',
        (tester) async {
      await _bootstrap(tester,
          apiFactory: () => _SlowMetricsApi(const Duration(milliseconds: 150)));
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.tap(find.byKey(const Key('device-evo')));
      await tester.pumpAndSettle();
      expect(find.text('Keine Telemetrie für dieses Gerät verfügbar'),
          findsOneWidget);
      expect(find.textContaining('61.2'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Closing details clears selection and restores empty panes',
        (tester) async {
      await _bootstrap(tester);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();
      expect(find.text('ENGINEERING WORKSPACE'), findsOneWidget);

      await tester.tap(find.byTooltip('Details schließen'));
      await tester.pumpAndSettle();
      expect(find.text('Gerät für die technische Untersuchung auswählen'),
          findsOneWidget);
      expect(find.byKey(const Key('devices-adaptive-inspector')), findsNothing);
      expect(find.text('Kein Gerät ausgewählt'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('B telemetry honesty', () {
    testWidgets('Device without observations shows honest no-telemetry state',
        (tester) async {
      await _bootstrap(tester);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('device-evo')));
      await tester.pumpAndSettle();
      expect(find.text('Keine Telemetrie für dieses Gerät verfügbar'),
          findsOneWidget);
      expect(
          find.text(
              'DeviceDetail enthält keine Observations. Kein Ersatzwert, kein 0 % und kein künstlicher Chart.'),
          findsOneWidget);
      expect(find.byKey(const Key('device-observation-temperature')),
          findsNothing);
      expect(find.text('Keine Observation im DeviceDetail'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Metrics request failure shows explicit error and retry recovers',
        (tester) async {
      final app =
          await _bootstrap(tester, configure: (api) => api.failMetrics = true);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();
      expect(find.text('Metriken nicht erreichbar'), findsWidgets);
      expect(
          find.text(
              'Der DeviceDetail-Request ist fehlgeschlagen. Frühere oder fremde Messwerte werden nicht angezeigt.'),
          findsOneWidget);
      expect(find.textContaining('61.2'), findsNothing);

      app.api.failMetrics = false;
      await tester.tap(find.byKey(const Key('device-metrics-retry-header')));
      await tester.pumpAndSettle();
      expect(
          _within(
              'device-engineering-workspace', find.textContaining('61.2 °C')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('C reachability provenance', () {
    testWidgets(
        'Simulated reachability is labelled reported/simulated, never measured',
        (tester) async {
      final data = fixture();
      data['sources'] = [_source(_sim, name: 'Local OPC-UA Simulation')];
      await _bootstrap(tester, data: data);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();

      expect(find.text('Erreichbar · SIMULATED / REPORTED'), findsWidgets);
      expect(find.text('Unbekannt · kein aktiver Probe ausgeführt'),
          findsOneWidget);
      expect(find.text('Erreichbar · SIMULATED / REPORTED · keine Probe'),
          findsOneWidget);
      expect(
          find.text('Erreichbar · REPORTED, nicht gemessen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Non-simulated reachability stays REPORTED without SIMULATED',
        (tester) async {
      final data = fixture();
      (data['devices'] as List)[0]['simulated'] = false;
      (data['system'] as Json)['simulated'] = false;
      await _bootstrap(tester, data: data);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();
      expect(find.text('Erreichbar · REPORTED'), findsOneWidget);
      expect(find.text('Erreichbar · SIMULATED / REPORTED'), findsNothing);
      expect(find.text('API-INVENTAR'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('D search, filter and sort', () {
    testWidgets('Search filters by name, ID, type and source', (tester) async {
      await _bootstrap(tester);
      await _navigate(tester, 1440);
      await tester.enterText(find.byKey(const Key('device-search')), 'AMD');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-evo')), findsOneWidget);
      expect(find.byKey(const Key('device-M-01')), findsNothing);
      expect(
          find.text('1 von 2 Geräten · Simuliertes Inventar'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('device-search')), 'm-01');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-M-01')), findsOneWidget);
      expect(find.byKey(const Key('device-evo')), findsNothing);

      await tester.enterText(
          find.byKey(const Key('device-search')), 'oip-local-simulation');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-M-01')), findsOneWidget);
      expect(find.byKey(const Key('device-evo')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Source, location, quality and connectivity filters compose',
        (tester) async {
      final data = fixture();
      (data['devices'] as List)[1]['location'] = 'Tailnet';
      await _bootstrap(tester, data: data);
      await _navigate(tester, 1440);

      await tester.tap(find.byKey(const Key('device-source-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keine Source'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-evo')), findsOneWidget);
      expect(find.byKey(const Key('device-M-01')), findsNothing);
      expect(
          find.text('1 von 2 Geräten · Simuliertes Inventar'), findsOneWidget);

      await tester.tap(find.byKey(const Key('device-filter-reset')));
      await tester.pumpAndSettle();
      expect(
          find.text('2 von 2 Geräten · Simuliertes Inventar'), findsOneWidget);

      await tester.tap(find.byKey(const Key('filter-Standort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standort: Tailnet'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-evo')), findsOneWidget);
      expect(find.byKey(const Key('device-M-01')), findsNothing);

      await tester.tap(find.byKey(const Key('device-filter-reset')));
      await tester.pumpAndSettle();

      // Quality and connectivity are secondary filters and live behind the
      // "Weitere Filter" disclosure. They keep their full behaviour.
      await tester.tap(find.byKey(const Key('device-more-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-quality-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unbekannt'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-evo')), findsOneWidget);
      expect(find.byKey(const Key('device-M-01')), findsNothing);

      await tester.tap(find.byKey(const Key('device-filter-reset')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('device-connectivity-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simuliert'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-evo')), findsOneWidget);
      expect(find.byKey(const Key('device-M-01')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Sorting and grouping reorganize the explorer', (tester) async {
      final data = fixture();
      (data['devices'] as List)[1]['location'] = 'Tailnet';
      await _bootstrap(tester, data: data);
      await _navigate(tester, 1440);

      // Default grouping by source renders one header per source.
      expect(find.text('OIP-LOCAL-SIMULATION-V1'), findsOneWidget);
      expect(find.text('KEINE SOURCE-ZUORDNUNG'), findsOneWidget);

      await tester.tap(find.byKey(const Key('device-group')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keine'));
      await tester.pumpAndSettle();
      expect(find.text('OIP-LOCAL-SIMULATION-V1'), findsNothing);
      expect(find.text('KEINE SOURCE-ZUORDNUNG'), findsNothing);

      await tester.tap(find.byKey(const Key('device-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standort'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(const Key('device-M-01'))).dy,
          lessThan(tester.getTopLeft(find.byKey(const Key('device-evo'))).dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Empty filter result shows honest empty state', (tester) async {
      await _bootstrap(tester);
      await _navigate(tester, 1440);
      await tester.enterText(
          find.byKey(const Key('device-search')), 'zzz-missing');
      await tester.pumpAndSettle();
      expect(find.text('Keine Geräte gefunden'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('E services and inventory health', () {
    testWidgets('Services mode states the missing authorized inventory',
        (tester) async {
      await _bootstrap(tester);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('devices-mode-services')));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('service-inventory-missing')), findsOneWidget);
      expect(find.text('SERVICE REGISTRY · AUTHORIZED DATA REQUIRED'),
          findsWidgets);
      expect(find.text('Kein autorisiertes Service-Inventar verfügbar.'),
          findsOneWidget);
      expect(
          find.text(
              'Dieser Core liefert kein autorisiertes Service-Register. Gerätenamen, Device.kind und Registry Connection Type werden nicht als Dienste ausgegeben.'),
          findsOneWidget);
      expect(find.text('Fehlt · Typed Rust Capability erforderlich'),
          findsOneWidget);
      expect(find.text('Fehlt · keine IDs im Device-DTO'), findsOneWidget);
      expect(find.text('Nicht autorisiert geliefert'), findsOneWidget);
      expect(find.text('Keine Service-Route bzw. kein Service-Tool vorhanden'),
          findsOneWidget);
      expect(
          find.textContaining('OIP_DEVICES_SERVICES_2027_CORE_REQUIREMENTS.md'),
          findsOneWidget);
      // No device name or kind is presented as a service.
      expect(find.textContaining('AMD EVO-X2'), findsNothing);
      expect(find.text('Compute'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Inventory health separates registry, source and telemetry coverage',
        (tester) async {
      final data = fixture();
      data['sources'] = [_source(_sim, name: 'Local OPC-UA Simulation')];
      await _bootstrap(tester, data: data);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('devices-mode-health')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('device-inventory-health')), findsOneWidget);
      expect(find.text('2 Geräte im v1-Snapshot'), findsOneWidget);
      expect(find.text('1 / 2'), findsNWidgets(2));
      expect(find.text('2 erreichbar · nicht aktiv gemessen'), findsOneWidget);
      expect(_within('device-inventory-health', find.text('2 Geräte')),
          findsOneWidget);
      expect(find.text('Unbekannt · Capability fehlt'), findsOneWidget);
      expect(find.text('Local OPC-UA Simulation · $_sim'), findsOneWidget);
      expect(find.textContaining('Verbunden · Aktuell'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('F comparison and related activity', () {
    testWidgets('Comparison is bounded at four devices and removable',
        (tester) async {
      final data = fixture();
      data['devices'] = [
        ...data['devices'] as List,
        _device('d-01', name: 'Sensor d-01'),
        _device('d-02', name: 'Sensor d-02'),
        _device('d-03', name: 'Sensor d-03'),
      ];
      await _bootstrap(tester, data: data);
      await _navigate(tester, 1440);

      for (final id in ['M-01', 'evo', 'd-01', 'd-02']) {
        await _tapVisible(tester, find.byKey(Key('device-compare-$id')));
      }
      expect(find.text('Comparison 4/4'), findsOneWidget);

      await _tapVisible(tester, find.byKey(const Key('device-compare-d-03')));
      expect(find.text('Der Vergleich ist auf vier Geräte begrenzt.'),
          findsOneWidget);
      expect(find.text('Comparison 4/4'), findsOneWidget);

      await tester.tap(find.byKey(const Key('device-compare-remove-d-02')));
      await tester.pumpAndSettle();
      expect(find.text('Comparison 3/4'), findsOneWidget);
      expect(find.byKey(const Key('device-compare-column-d-02')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('device-comparison-field-Known Services')),
        100,
        scrollable: find.descendant(
          of: find.byKey(const Key('device-comparison-fields')),
          matching: find.byType(Scrollable),
        ),
      );
      // The Core of this fixture does not deliver the registry: the
      // comparison names that instead of inventing a service.
      expect(find.text('Unbekannt · kein autorisiertes Service-Register'),
          findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Related Activity navigates to Diagnostics with exact IDs',
        (tester) async {
      final data = fixture();
      data['incidents'] = [_incident()];
      data['records'] = [_record()];
      await _bootstrap(tester, data: data);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-activity-tab')));
      await tester.pumpAndSettle();

      expect(find.text('Dokumentierter Collection-Gap'), findsOneWidget);
      expect(
          find.text(
              'oip.documented-collection-gap · exakte Device-ID · SIMULATED'),
          findsOneWidget);
      await tester.tap(find.text('Dokumentierter Collection-Gap'));
      await tester.pumpAndSettle();
      expect(find.text('Diagnose & Ereignisse'), findsWidgets);
      expect(find.text('DEVICES & SERVICES · ENGINEERING WORKSTATION'),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('G cross-module navigation', () {
    testWidgets('Inspector opens real module destinations without deep links',
        (tester) async {
      final data = fixture();
      data['sources'] = [_source(_sim, name: 'Local OPC-UA Simulation')];
      await _bootstrap(tester, data: data);
      await _navigate(tester, 1440);

      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-inspector-network')));
      await tester.pumpAndSettle();
      expect(find.text('Netzwerk & VPN'), findsWidgets);
      expect(find.text('DEVICES & SERVICES · ENGINEERING WORKSTATION'),
          findsNothing);

      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-inspector-opcua')));
      await tester.pumpAndSettle();
      expect(find.text('OPC-UA-Browser'), findsWidgets);

      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-inspector-diagnostics')));
      await tester.pumpAndSettle();
      expect(find.text('Diagnose & Ereignisse'), findsWidgets);

      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-inspector-overview')));
      await tester.pumpAndSettle();
      expect(find.text('Übersicht'), findsWidgets);

      // A device without a source cannot open the OPC-UA module.
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('device-evo')));
      await tester.pumpAndSettle();
      final opcua = tester
          .widget<ToolButton>(find.byKey(const Key('device-inspector-opcua')));
      expect(opcua.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Returning to Devices reloads the persisted selection detail',
        (tester) async {
      final app = await _bootstrap(tester);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();
      expect(app.api.metricRequests, 1);

      await tester.tap(find.byKey(const Key('device-inspector-network')));
      await tester.pumpAndSettle();
      await _navigate(tester, 1440);
      await tester.pumpAndSettle();

      expect(app.api.metricRequests, 2);
      expect(
          _within(
              'device-engineering-workspace', find.textContaining('61.2 °C')),
          findsOneWidget);
      expect(find.text('Keine Telemetrie für dieses Gerät verfügbar'),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('H disconnect and reconnect freshness', () {
    testWidgets(
        'Stale connection marks reported freshness veraltet, live restores it',
        (tester) async {
      final app = await _bootstrap(tester);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();
      expect(find.text('Aktuell'), findsWidgets);
      expect(find.text('Veraltet / unbekannt'), findsNothing);

      app.controller.connection = 'reconnecting';
      app.controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Veraltet / unbekannt'), findsOneWidget);

      app.controller.connection = 'live';
      app.controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Veraltet / unbekannt'), findsNothing);
      expect(find.text('Aktuell'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('I multi-source, scope and inventory sizes', () {
    testWidgets('Multi-source observations stay isolated per source and entity',
        (tester) async {
      final data = fixture();
      data['devices'] = [
        ...data['devices'] as List,
        _device('b:M-01', source: 'b', name: 'Simulation B'),
      ];
      data['metrics'] = [
        _observation(),
        _observation(entity: 'b:M-01', source: 'b', value: 22.0),
      ];
      data['sources'] = [
        _source(_sim, name: 'Local OPC-UA Simulation'),
        _source('b', name: 'Simulation B'),
      ];
      await _bootstrap(tester, data: data);
      await _navigate(tester, 1440);

      // Both rows report their own observed freshness.
      expect(find.byKey(const Key('device-M-01')), findsOneWidget);
      expect(find.byKey(const Key('device-b:M-01')), findsOneWidget);
      expect(find.textContaining('Compute · b · Aktuell'), findsOneWidget);

      // Selecting the second source must never show the first source's value.
      await _tapVisible(tester, find.byKey(const Key('device-b:M-01')));
      expect(find.text('Keine Telemetrie für dieses Gerät verfügbar'),
          findsOneWidget);
      expect(find.textContaining('61.2'), findsNothing);

      await _tapVisible(tester, find.byKey(const Key('device-M-01')));
      expect(
          _within(
              'device-engineering-workspace', find.textContaining('61.2 °C')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Primary source scope change clears selection, pins, recents and compare',
        (tester) async {
      final data = fixture();
      data['sources'] = [_source(_sim, name: 'Local OPC-UA Simulation')];
      final app = await _bootstrap(tester, data: data);
      await _navigate(tester, 1440);

      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-pin-M-01')));
      await tester.tap(find.byKey(const Key('device-compare-M-01')));
      await tester.pumpAndSettle();
      expect(find.text('Comparison 1/4'), findsOneWidget);
      expect(find.text('Pinned 1'), findsOneWidget);
      expect(find.text('Recents 1'), findsOneWidget);

      final scoped = Json.from(data);
      (scoped['system'] as Json)['primary_source_id'] = 'other-scope';
      app.controller.snapshot = Snapshot.fromJson(scoped);
      app.controller.notifyListeners();
      await tester.pumpAndSettle();

      expect(find.text('Gerät für die technische Untersuchung auswählen'),
          findsOneWidget);
      expect(find.text('Comparison 0/4'), findsOneWidget);
      expect(find.text('Pinned 0'), findsOneWidget);
      expect(find.text('Recents 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Live observation replacement requires exact source, entity and metric identity',
        (tester) async {
      final app = await _bootstrap(tester);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();
      expect(
          _within(
              'device-engineering-workspace', find.textContaining('61.2 °C')),
          findsOneWidget);

      (app.api.data['metrics'] as List)[0]['value'] = {'float': 63.5};
      app.controller.snapshot = Snapshot.fromJson(app.api.data);
      app.controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(
          _within(
              'device-engineering-workspace', find.textContaining('63.5 °C')),
          findsOneWidget);
      expect(find.textContaining('61.2'), findsNothing);

      // A different metric of the same entity is never merged into the
      // authorized detail set.
      app.api.data['metrics'] = [
        ...app.api.data['metrics'] as List,
        _observation(metric: 'pressure', value: 320.5),
      ];
      app.controller.snapshot = Snapshot.fromJson(app.api.data);
      app.controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(
          _within(
              'device-engineering-workspace', find.textContaining('63.5 °C')),
          findsOneWidget);
      expect(find.textContaining('pressure'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Zero, one and seventeen device inventories render honestly',
        (tester) async {
      final empty = fixture();
      empty['devices'] = [];
      empty['metrics'] = [];
      await _bootstrap(tester, data: empty);
      await _navigate(tester, 1440);
      expect(
          find.text('0 von 0 Geräten · Simuliertes Inventar'), findsOneWidget);
      expect(find.text('Keine Geräte gefunden'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();

      final single = fixture();
      single['devices'] = [
        ...List<Json>.from(single['devices'] as List).take(1),
      ];
      await _bootstrap(tester, data: single);
      await _navigate(tester, 1440);
      expect(
          find.text('1 von 1 Geräten · Simuliertes Inventar'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();

      final many = fixture();
      many['devices'] = [
        many['devices'][0],
        for (var i = 1; i <= 16; i++)
          _device('sz-${i.toString().padLeft(2, '0')}'),
      ];
      await _bootstrap(tester, data: many);
      await _navigate(tester, 1440);
      expect(find.text('17 von 17 Geräten · Simuliertes Inventar'),
          findsOneWidget);
      expect(find.text('Seite 1 / 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Large inventory paginates fifty rows per page',
        (tester) async {
      final data = fixture();
      data['devices'] = [
        for (var i = 1; i <= 120; i++)
          _device('inv-${i.toString().padLeft(3, '0')}'),
      ];
      data['metrics'] = [];
      await _bootstrap(tester, data: data);
      await _navigate(tester, 1440);

      expect(find.text('120 von 120 Geräten · Simuliertes Inventar'),
          findsOneWidget);
      expect(find.text('Seite 1 / 3'), findsOneWidget);
      expect(find.byKey(const Key('device-inv-001')), findsOneWidget);
      expect(find.byKey(const Key('device-inv-050')), findsOneWidget);
      expect(find.byKey(const Key('device-inv-051')), findsNothing);

      await tester.tap(find.byTooltip('Nächste Geräte'));
      await tester.pumpAndSettle();
      expect(find.text('Seite 2 / 3'), findsOneWidget);
      expect(find.byKey(const Key('device-inv-051')), findsOneWidget);
      expect(find.byKey(const Key('device-inv-100')), findsOneWidget);
      expect(find.byKey(const Key('device-inv-101')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Mobile, tablet and desktop layouts stay usable',
        (tester) async {
      for (final (size, isMobile) in [
        (const Size(320, 740), true),
        (const Size(375, 812), true),
        (const Size(768, 1024), true),
        (const Size(834, 1112), false),
        (const Size(1024, 900), false),
        (const Size(1440, 1000), false),
        (const Size(1920, 1080), false),
      ]) {
        await _bootstrap(tester, size: size);
        await _navigate(tester, size.width);
        expect(find.byKey(const Key('devices-mobile-explorer')),
            isMobile ? findsOneWidget : findsNothing);
        expect(
            find.byKey(const Key('device-inventory-explorer')), findsOneWidget);
        await _tapVisible(tester, find.byKey(const Key('device-M-01')));
        expect(find.text('ENGINEERING WORKSPACE'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('Themes keep the workstation readable', (tester) async {
      await _bootstrap(tester);
      await _navigate(tester, 1440);
      expect(find.text('SPECTRUM'), findsOneWidget);
      await tester.tap(find.byKey(const Key('theme-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('DAYLIGHT'), findsOneWidget);
      expect(_within('devices-page-header', find.text('Geräte & Dienste')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('theme-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('GRAPHITE'), findsOneWidget);
      expect(_within('devices-page-header', find.text('Geräte & Dienste')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('J keyboard and accessibility', () {
    testWidgets('Slash focuses search, arrows and Home/End move selection',
        (tester) async {
      await _bootstrap(tester);
      await _navigate(tester, 1440);
      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.pump();
      final field =
          tester.widget<TextField>(find.byKey(const Key('device-search')));
      expect(field.focusNode!.hasFocus, isTrue);

      // Characters typed while the search field is focused never trigger
      // the page shortcuts.
      await tester.enterText(find.byKey(const Key('device-search')), 'pc');
      await tester.pumpAndSettle();
      expect(field.controller!.text, 'pc');
      expect(find.byTooltip('Pin entfernen'), findsNothing);
      expect(find.text('Comparison 0/4'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('device-search')), '');
      await tester.pumpAndSettle();

      final list = tester.widget<Focus>(find.byWidgetPredicate((widget) =>
          widget is Focus &&
          widget.focusNode?.debugLabel == 'device-inventory-list'));
      list.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(_within('device-context-inspector', find.text('AMD EVO-X2')),
          findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(
          _within(
              'device-context-inspector', find.text('OPC-UA-Sensoren · M-01')),
          findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pin entfernen'), findsOneWidget);
      expect(find.text('Gepinnt'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(find.text('Comparison 1/4'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Gerät für die technische Untersuchung auswählen'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Rows and row actions expose accessible semantics',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _bootstrap(tester);
        await _navigate(tester, 1440);
        expect(
            find.bySemanticsLabel(RegExp(
                r'^Gerät AMD EVO-X2 evo auswählen · Compute · keine Source · keine aktuelle Observation · Reachability Erreichbar reported · simuliert')),
            findsOneWidget);
        expect(find.bySemanticsLabel('Gerät pinnen'), findsWidgets);
        expect(find.bySemanticsLabel('Vergleich hinzufügen'), findsWidgets);
        expect(find.byTooltip('Details schließen'), findsNothing);

        await tester.tap(find.byKey(const Key('device-M-01')));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Details schließen'), findsOneWidget);
        expect(find.byTooltip('Device ID kopieren'), findsOneWidget);
        expect(find.byTooltip('Source ID kopieren'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  });
}
