import 'dart:async';
import 'package:flutter/material.dart';
import '../app/controller.dart';
import '../design_system/theme.dart';
import '../models/contracts.dart';
import '../models/onboarding.dart';
import '../services/api.dart';
import '../widgets/components.dart';
import 'device_onboarding.dart';

class DeviceConnectionPanel extends StatefulWidget {
  final OipController controller;
  final String deviceId;
  final ValueChanged<List<Observation>>? onObservations;
  const DeviceConnectionPanel(
      {super.key,
      required this.controller,
      required this.deviceId,
      this.onObservations});
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
        final observations = value.connection?.observations ?? const [];
        if (observations.isNotEmpty) widget.onObservations?.call(observations);
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
              // The monitoring is armed and the host has not delivered a
              // measurement yet: the state says so, and not that the
              // connection works.
              'collector_configured' =>
                'Überwachung konfiguriert · noch keine Messwerte empfangen',
              // The Core refused the connection and the identity of the host
              // could not be confirmed: the state names the refusal.
              'verification_failed' =>
                'Verifikation fehlgeschlagen · Identität nicht bestätigt',
              // A state that the client does not know is **named**, never
              // shown as the wire name of the Core: the surface speaks to the
              // operator.
              _ => 'Verbindungsstatus unbekannt'
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
        const SizedBox(height: OipTokens.s4),
        const SectionTitle('Aktuelle Messwerte',
            'Vom autorisierten Gerät tatsächlich gelesene Werte · keine Ersatzwerte'),
        if (c.observations.isEmpty)
          const Text(
              'Noch keine aktuellen Messwerte. Verifizierung allein ist kein kontinuierliches Monitoring.')
        else
          ...c.observations.map((o) => MeasurementRow(o)),
      ],
    ]);
  }
}

/// One authorized measurement that the Core actually received from the device.
///
/// The value, its unit, the quality, the freshness and the capture time come
/// from the Core response. Nothing is derived, rounded up or substituted here.
class MeasurementRow extends StatelessWidget {
  final Observation observation;
  const MeasurementRow(this.observation, {super.key});

  /// Longer texts (disk and interface reports) stay collapsed until the
  /// operator opens them; the preview is never shown as the complete value.
  static const int previewLength = 120;

  @override
  Widget build(BuildContext context) {
    final value = '${observation.display} ${observation.symbol}'.trim();
    final caption = '${known(observation.quality)} · '
        '${known(observation.freshness)} · ${timestamp(observation.sourceMs)}';
    if (value.length <= previewLength) {
      return Fact(observation.metricId, '$value · $caption');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OipTokens.s2),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: OipTokens.s2),
        title: Text(observation.metricId,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(fontSize: 9, letterSpacing: .75)),
        subtitle: Text('${value.substring(0, previewLength)}… · $caption'),
        children: [SelectableText(value)],
      ),
    );
  }
}
