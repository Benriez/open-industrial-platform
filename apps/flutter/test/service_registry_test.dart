import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/features/devices/service_registry.dart';
import 'package:oip_dashboard/models/infrastructure.dart';

/// The **service registry** of the authorized scope.
///
/// The registry holds what the **operator declared** in the plan of the
/// instance. The Core measures no service: every record carries the provenance
/// `declared`, and the surface says so instead of presenting a declaration as
/// a measurement.
ServiceRecord _service({
  String id = 'svc-a1-opcua',
  String name = 'OPC-UA server of the plant',
  String kind = 'opcua',
  String siteId = 'site-a1',
  String deviceId = 'device-a',
  String state = 'running',
}) =>
    ServiceRecord(
      id: id,
      name: name,
      kind: kind,
      siteId: siteId,
      organizationId: 'org-a',
      infrastructureId: 'infra-a1',
      origin: 'declared',
      state: state,
      deviceId: deviceId,
      endpoint: 'opc.tcp://127.0.0.1:4840',
      port: 4840,
    );

Future<void> _pump(WidgetTester tester, List<ServiceRecord>? services) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: ServiceRegistryPanel(services: services)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the registry shows the declared services of the scope',
      (tester) async {
    await _pump(tester, [_service()]);
    expect(find.byKey(const Key('service-registry')), findsOneWidget);
    expect(find.text('1 Dienste deklariert'), findsOneWidget);
    expect(find.text('OPC-UA server of the plant · svc-a1-opcua'), findsOneWidget);
    expect(find.text('opcua'), findsOneWidget);
    // The state is the claim of the operator, and the surface says so.
    expect(find.text('läuft (deklariert) · declared'), findsOneWidget);
    // The relation to the device is resolved; a declaration without a device
    // names that honestly.
    expect(find.text('device-a'), findsOneWidget);
    await _pump(tester, [_service(deviceId: '')]);
    expect(find.text('Nicht zuordenbar'), findsOneWidget);
  });

  testWidgets('an empty registry is a declaration of the operator',
      (tester) async {
    await _pump(tester, const []);
    expect(find.byKey(const Key('service-registry-empty')), findsOneWidget);
    expect(find.text('Keine Dienste deklariert.'), findsOneWidget);
    // The empty registry is not a measurement of "no services".
    expect(find.textContaining('keine Messung'), findsOneWidget);
  });

  testWidgets('a Core that does not deliver the registry names the absence',
      (tester) async {
    await _pump(tester, null);
    expect(find.byKey(const Key('service-inventory-missing')), findsOneWidget);
    expect(find.text('Kein autorisiertes Service-Inventar verfügbar.'),
        findsOneWidget);
    // No device name or kind is presented as a service.
    expect(find.textContaining('AMD EVO-X2'), findsNothing);
  });
}
