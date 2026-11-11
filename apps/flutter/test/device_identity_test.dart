import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/features/devices/device_detail.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/models/infrastructure.dart';

import 'support.dart';

/// The identity of a device.
///
/// The Core holds the identity of a device in its **inventory**: the
/// manufacturer, the model, the firmware, the serial number and the address.
/// The summary of a device does not carry them. The panel names the facts
/// that the Core holds and names the others as unavailable — it never
/// invents an identity and never shows a placeholder as a fact.
Device _device() => Device.fromJson({
      'id': 'hue-bridge',
      'is_faulted': false,
      'data_source_id': null,
      'name': 'Philips Hue Bridge BSB002',
      'kind': 'NetworkDevice',
      'location': 'site-a1',
      'connection': 'unbekannt',
      'simulated': false,
      'health': {
        'reachability': 'unknown',
        'vpn_transport': 'not_applicable',
        'agent_availability': 'unknown',
        'service_health': 'unknown',
        'telemetry_freshness': 'unknown',
      },
    });

InventoryDevice _record({Map<String, Object?>? metadata}) => InventoryDevice(
      id: 'hue-bridge',
      name: 'Philips Hue Bridge BSB002',
      type: 'network_device',
      siteId: 'site-a1',
      organizationId: 'org-a',
      infrastructureId: 'infra-a1',
      registration: 'registered',
      origin: 'manual_operator',
      connectivity: 'unknown',
      telemetry: 'no_collector',
      health: 'not_evaluated',
      sourceIds: const [],
      revision: 1,
      metadata: metadata,
    );

Future<void> _pump(WidgetTester tester, {InventoryDevice? record}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: DeviceEngineeringWorkspace(
        device: _device(),
        snapshot: Snapshot.fromJson(fixture()),
        sources: const [],
        metrics: const [],
        loading: false,
        error: null,
        connection: 'unbekannt',
        onRetry: () {},
        onClose: () {},
        navigate: (_) {},
        inventoryDevice: record,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the identity of a device comes from the inventory of the Core',
      (tester) async {
    await _pump(tester, record: _record(metadata: const {
      'manufacturer': 'Philips Hue',
      'model': 'BSB002',
      'operating_system': 'Hue firmware 1978545030, API 1.78.0',
      'serial_number': '001788FFFE48E917',
      'mac_address': '00:17:88:48:e9:17',
      'ip_address': '192.168.1.131',
    }));
    expect(find.text('Philips Hue / BSB002'), findsOneWidget);
    expect(find.text('Hue firmware 1978545030, API 1.78.0'), findsOneWidget);
    expect(find.text('001788FFFE48E917'), findsOneWidget);
    expect(find.text('00:17:88:48:e9:17 / 192.168.1.131'), findsOneWidget);
    // The identity of a device is never invented: the Core holds no serial
    // number here, and the panel says so.
    expect(find.text('Nicht verfügbar'), findsWidgets);
  });

  testWidgets('a device without an inventory record names no identity',
      (tester) async {
    await _pump(tester);
    expect(find.text('Nicht verfügbar'), findsWidgets);
    expect(find.text('Philips Hue / BSB002'), findsNothing);
  });
}
