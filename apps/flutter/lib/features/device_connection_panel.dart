import 'dart:async';
import 'package:flutter/material.dart';
import '../app/controller.dart';
import '../models/onboarding.dart';
import '../services/api.dart';
import '../widgets/components.dart';
import 'device_onboarding.dart';

class DeviceConnectionPanel extends StatefulWidget {
  final OipController controller;
  final String deviceId;
  const DeviceConnectionPanel(
      {super.key, required this.controller, required this.deviceId});
  @override
  State<DeviceConnectionPanel> createState() => _DeviceConnectionPanelState();
}

class _DeviceConnectionPanelState extends State<DeviceConnectionPanel> {
  Timer? timer;
  ConnectionResult? result;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
    timer = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (busy || !mounted) return;
    busy = true;
    try {
      final value = await widget.controller.management!
          .connection(deviceId: widget.deviceId);
      if (mounted) {
        setState(() {
          result = value;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          result = null;
          error =
              apiErrorMessage(e, 'Verbindungsinformationen nicht zugänglich.');
        });
      }
    } finally {
      busy = false;
    }
  }

  Future<void> toggle(DeviceConnection c, bool enabled) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final value = await widget.controller.management!.configure({
        'operation': 'monitoring',
        'device_id': c.deviceId,
        'expected_revision': c.revision,
        'enabled': enabled,
        'poll_seconds': c.pollSeconds
      });
      if (mounted) {
        setState(() {
          result = value;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() =>
            error = apiErrorMessage(e, 'Monitoring-Änderung fehlgeschlagen.'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = result?.connection;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(),
      Text('Verbindung & Monitoring',
          style: Theme.of(context).textTheme.titleLarge),
      if (error != null) Text(error!),
      if (result == null && error == null) const LinearProgressIndicator(),
      if (result != null && c == null) ...[
        const Text(
            'Registered · Connectivity Unknown · Telemetry NoCollector · Health NotEvaluated'),
        if (result!.lastAttempt != null)
          Text(
              'Letzter Prüfversuch: ${result!.lastAttempt!['at_ms']} · ${result!.lastAttempt!['error']?['message'] ?? result!.lastAttempt!['stage']}'),
        OutlinedButton.icon(
            key: const Key('configure-existing-device'),
            onPressed: () async {
              await showDeviceOnboarding(context, widget.controller,
                  deviceId: widget.deviceId);
              await refresh();
            },
            icon: const Icon(Icons.link),
            label: const Text('Verbindung für dieses Gerät einrichten')),
      ],
      if (c != null) ...[
        Text(
            switch (c.status) {
              'collecting' => 'Collecting · aktuelle Messwerte empfangen',
              'ssh_verified' => 'SSH Verified · Monitoring deaktiviert',
              'unreachable' =>
                'Unreachable · tatsächlicher Verbindungsversuch fehlgeschlagen',
              'stale' => 'Stale · Messwerte veraltet',
              'host_key_changed' => 'Host-Key geändert · Verbindung blockiert',
              'host_key_unknown' =>
                'Host-Key unbekannt · Identität vor der nächsten Verbindung bestätigen',
              _ => c.status
            },
            key: const Key('device-monitoring-status')),
        Text(
            'SSH · ${c.endpoint['user']}@${c.endpoint['host']}:${c.endpoint['port']}'),
        Text('Host-Key: ${c.fingerprint}'),
        Text('Letzter Prüfversuch: ${timestamp(c.lastAttempt)}'),
        Text('Letzte erfolgreiche Erfassung: ${timestamp(c.lastSuccess)}'),
        if (c.error != null)
          Text('${c.error!['code']}: ${c.error!['message']}'),
        ExpansionTile(
            title: const Text('Tatsächlich verifizierte Identität'),
            children: identityWidgets(c.identity)),
        SwitchListTile(
            title: const Text('Read-only Monitoring'),
            subtitle:
                Text('Polling: ${c.pollSeconds} s · Revision ${c.revision}'),
            value: c.enabled,
            onChanged: busy ? null : (v) => toggle(c, v)),
        if (c.observations.isEmpty)
          const Text(
              'Noch keine aktuellen Messwerte. Verifizierung allein ist kein kontinuierliches Monitoring.'),
      ],
    ]);
  }
}
