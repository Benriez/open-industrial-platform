import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../app/controller.dart';
import '../models/contracts.dart';
import '../models/onboarding.dart';
import '../services/api.dart';

Future<void> showDeviceOnboarding(
        BuildContext context, OipController controller, {String? deviceId}) =>
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            DeviceOnboarding(controller: controller, deviceId: deviceId));

String _id() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class DeviceOnboarding extends StatefulWidget {
  final OipController controller;
  final String? deviceId;
  const DeviceOnboarding({super.key, required this.controller, this.deviceId});
  @override
  State<DeviceOnboarding> createState() => _DeviceOnboardingState();
}

class _DeviceOnboardingState extends State<DeviceOnboarding> {
  final name = TextEditingController(),
      host = TextEditingController(),
      port = TextEditingController(text: '22'),
      user = TextEditingController(),
      interval = TextEditingController(text: '30');
  late final DeviceManagementApi api = widget.controller.management!;
  final registrationId = _id();
  List<HierarchyItem> organizations = [], infrastructures = [], sites = [];
  List<SshProfile> profiles = [];
  String? organization, infrastructure, site, profile, alias, error;
  String kind = 'other', method = 'ssh';
  int step = 0, revision = 0;
  bool busy = true, consent = false, monitor = false, done = false;
  ConnectionPlan? plan;
  DeviceConnection? savedConnection;
  Timer? timer;
  bool polling = false;
  late final int contextRevision = widget.controller.contextRevision;
  void contextChanged() {
    if (mounted && contextRevision != widget.controller.contextRevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(contextChanged);
    unawaited(load());
  }

  @override
  void dispose() {
    widget.controller.removeListener(contextChanged);
    timer?.cancel();
    if (!done &&
        plan != null &&
        !const ['committing', 'committed'].contains(plan!.stage)) {
      unawaited(api
          .configure({'operation': 'cancel', 'plan_id': plan!.id}).then<void>(
              (_) {},
              onError: (Object _) {}));
    }
    for (final c in [name, host, port, user, interval]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function() operation) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
    } catch (e) {
      if (mounted) {
        setState(() => error = apiErrorMessage(e,
            'Vorgang fehlgeschlagen. Es wurde keine erfolgreiche Verbindung bestätigt.'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() async {
    try {
      final ctx = widget.controller.onboardingScope;
      organizations = await api.hierarchy('organizations', {});
      organization = organizations.any((o) => o.id == ctx.organization)
          ? ctx.organization
          : organizations.firstOrNull?.id;
      await loadInfrastructure(ctx.infrastructure, ctx.site);
      if (widget.deviceId != null) {
        final item = await api.inventory(widget.deviceId!);
        final record = item['record'] as Json,
            device = record['device'] as Json;
        name.text = device['display_name'] as String;
        kind = device['device_type'] as String;
        revision = record['revision'] as int;
        organization = item['organization_id'] as String;
        await loadInfrastructure(
            item['infrastructure_id'] as String, device['site_id'] as String);
      }
      profiles = (await api.connection(deviceId: widget.deviceId)).profiles;
      profile = profiles.firstOrNull?.id;
    } catch (e) {
      error = apiErrorMessage(
          e, 'Autorisierte Konfiguration konnte nicht geladen werden.');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> loadInfrastructure(
      [String? preferred, String? preferredSite]) async {
    infrastructures = organization == null
        ? []
        : await api
            .hierarchy('infrastructures', {'organization': organization!});
    infrastructure = infrastructures.any((i) => i.id == preferred)
        ? preferred
        : infrastructures.firstOrNull?.id;
    await loadSites(preferredSite);
  }

  Future<void> loadSites([String? preferred]) async {
    sites = infrastructure == null
        ? []
        : await api.hierarchy('sites', {'infrastructure': infrastructure!});
    site =
        sites.any((s) => s.id == preferred) ? preferred : sites.firstOrNull?.id;
  }

  Json get draft => {
        'display_name': name.text.trim(),
        'device_type': kind,
        'site_id': site,
        'metadata': <String, dynamic>{}
      };
  Future<void> start() async {
    if (site == null ||
        name.text.trim().isEmpty ||
        (method == 'ssh' && profile == null)) {
      throw const ApiFailure(
          'Name, autorisierter Standort und SSH-Profil sind erforderlich.');
    }
    if (method == 'manual') {
      setState(() => step = 3);
      return;
    }
    final parsed = int.tryParse(port.text);
    if (parsed == null || parsed < 1 || parsed > 65535) {
      throw const ApiFailure('SSH-Port muss zwischen 1 und 65535 liegen.');
    }
    final result = await api.configure({
      'operation': 'start',
      'target': widget.deviceId == null
          ? {'kind': 'new', 'device': draft}
          : {
              'kind': 'existing',
              'id': widget.deviceId,
              'expected_revision': revision
            },
      'endpoint': {
        'host': host.text.trim(),
        'port': parsed,
        'user': user.text.trim(),
        'identity_profile': profile,
        'alias': alias
      }
    });
    if (!mounted) return;
    setState(() {
      plan = result.plan;
      step = 2;
    });
    timer = Timer.periodic(const Duration(milliseconds: 600), (_) => poll());
  }

  Future<void> poll() async {
    if (polling || plan == null || !mounted) return;
    polling = true;
    try {
      final result = await api.connection(planId: plan!.id);
      if (!mounted) return;
      setState(() {
        plan = result.plan;
        if (plan?.stage == 'verification_complete') {
          step = 3;
          timer?.cancel();
        }
        if (plan?.stage == 'failed') {
          error = plan!.error?['message'] as String?;
          timer?.cancel();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = apiErrorMessage(
            e, 'Verbindungsstatus konnte nicht gelesen werden.'));
      }
      timer?.cancel();
    } finally {
      polling = false;
    }
  }

  Future<void> verify({bool trust = false}) async {
    if (trust) {
      await api.configure({
        'operation': 'trust_host_key',
        'plan_id': plan!.id,
        'fingerprint': plan!.fingerprint
      });
    }
    final r = await api.configure({'operation': 'verify', 'plan_id': plan!.id});
    if (mounted) setState(() => plan = r.plan);
  }

  Future<void> confirm() async {
    if (!consent) {
      throw const ApiFailure(
          'Identität beziehungsweise reine Inventarregistrierung ausdrücklich bestätigen.');
    }
    if (method == 'manual') {
      await api.register({'id': registrationId, ...draft});
    } else {
      final n = int.tryParse(interval.text);
      if (n == null || n < 10 || n > 3600) {
        throw const ApiFailure('Polling-Intervall: 10–3600 Sekunden.');
      }
      final saved = await api.configure({
        'operation': 'confirm',
        'plan_id': plan!.id,
        'identity_confirmed': true,
        'enable_monitoring': false,
        'poll_seconds': n
      });
      savedConnection = saved.connection;
    }
    if (!mounted) return;
    setState(() {
      done = true;
      step = 4;
    });
    widget.controller.reconnect();
  }

  Future<void> enableMonitoring() async {
    final c = savedConnection;
    final n = int.tryParse(interval.text);
    if (c == null || n == null || n < 10 || n > 3600) {
      throw const ApiFailure(
          'Gespeicherte Verbindung und Intervall von 10–3600 Sekunden erforderlich.');
    }
    final response = await api.configure({
      'operation': 'monitoring',
      'device_id': c.deviceId,
      'expected_revision': c.revision,
      'enabled': true,
      'poll_seconds': n
    });
    if (mounted) {
      setState(() {
        savedConnection = response.connection;
        monitor = response.connection?.enabled == true;
      });
    }
  }

  Widget select(String label, String? value, List<HierarchyItem> values,
          void Function(String?) changed, {bool locked = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
              key: ValueKey('$label-$value'),
              value: values.any((v) => v.id == value) ? value : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: label),
              items: values
                  .map((v) => DropdownMenuItem(
                      value: v.id,
                      child: Text(v.name, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: locked || busy ? null : changed));
  Widget field(String label, TextEditingController c, String key,
          {bool locked = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
              key: Key(key),
              controller: c,
              enabled: !busy && !locked,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 253,
              decoration: InputDecoration(labelText: label)));
  @override
  Widget build(BuildContext context) {
    final existing = widget.deviceId != null;
    final stage = plan?.stage;
    return Dialog(
        child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                    child: Text(
                        existing
                            ? 'Verbindung für dieses Gerät einrichten'
                            : 'Gerät hinzufügen',
                        style: Theme.of(context).textTheme.headlineSmall)),
                IconButton(
                    tooltip: 'Onboarding schließen',
                    onPressed: busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close))
              ]),
              Text('Schritt ${step + 1}/5 · ${[
                'Infrastruktur auswählen',
                'Verbindung konfigurieren',
                'Verbindung testen',
                'Gerät bestätigen',
                method == 'manual'
                    ? 'Inventar gespeichert'
                    : 'Monitoring aktivieren'
              ][step]}'),
              const SizedBox(height: 16),
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(error!,
                        key: const Key('onboarding-error'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              if (step == 0) ...[
                select(
                    'Organization',
                    organization,
                    organizations,
                    (v) => run(() async {
                          organization = v;
                          await loadInfrastructure();
                        }),
                    locked: existing),
                select(
                    'Infrastructure',
                    infrastructure,
                    infrastructures,
                    (v) => run(() async {
                          infrastructure = v;
                          await loadSites();
                        }),
                    locked: existing),
                select('Site', site, sites, (v) => setState(() => site = v),
                    locked: existing),
                field('Anzeigename', name, 'device-name', locked: existing),
                if (!existing)
                  DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: kind,
                      decoration: const InputDecoration(labelText: 'Gerätetyp'),
                      items: const [
                        'server',
                        'desktop',
                        'laptop',
                        'single_board_computer',
                        'network_device',
                        'industrial_device',
                        'sensor',
                        'other'
                      ]
                          .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)))
                          .toList(),
                      onChanged: (v) => setState(() => kind = v!)),
                const SizedBox(height: 12),
                FilledButton(
                    key: const Key('onboarding-scope-next'),
                    onPressed: busy || site == null
                        ? null
                        : () => setState(() => step = 1),
                    child: const Text('Verbindungsmethode wählen')),
              ],
              if (step == 1) ...[
                DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: method,
                    decoration:
                        const InputDecoration(labelText: 'Verbindungsmethode'),
                    items: [
                      const DropdownMenuItem(
                          value: 'ssh', child: Text('SSH — Linux / macOS')),
                      if (!existing)
                        const DropdownMenuItem(
                            value: 'manual',
                            child: Text('Nur Inventar, keine Verbindung')),
                    ],
                    onChanged:
                        busy ? null : (v) => setState(() => method = v!)),
                const SizedBox(height: 12),
                const Text(
                    'OPC UA: separater autorisierter Source-Provisioning-Pfad. SNMP, Windows, Android und VPN-Monitoring sind hier nicht implementiert.'),
                const SizedBox(height: 12),
                if (method == 'ssh') ...[
                  if (profiles.isEmpty)
                    const Text(
                        'Kein freigegebenes SSH-Profil. Der lokale Operator muss eine SSH-Identität und den erlaubten Endpoint im Core-Profil konfigurieren. Keine privaten Schlüssel im Browser.'),
                  DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: profile,
                      decoration: const InputDecoration(
                          labelText: 'Lokale SSH-Identität'),
                      items: profiles
                          .map((p) => DropdownMenuItem(
                              value: p.id, child: Text(p.label)))
                          .toList(),
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                                profile = v;
                                alias = null;
                              })),
                  const SizedBox(height: 12),
                  field('Hostname oder IP-Adresse', host, 'ssh-host'),
                  field('SSH-Port', port, 'ssh-port'),
                  field('SSH-Benutzer (kein root)', user, 'ssh-user'),
                  if (profiles
                          .where((p) => p.id == profile)
                          .firstOrNull
                          ?.aliases
                          .isNotEmpty ==
                      true)
                    DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: alias,
                        decoration: const InputDecoration(
                            labelText: 'Optionaler autorisierter Hostalias'),
                        items: profiles
                            .firstWhere((p) => p.id == profile)
                            .aliases
                            .map((a) =>
                                DropdownMenuItem(value: a, child: Text(a)))
                            .toList(),
                        onChanged:
                            busy ? null : (v) => setState(() => alias = v)),
                  const Text(
                      'Der Core prüft ausschließlich diesen expliziten Endpoint. Es findet kein Netzwerkscan statt.'),
                ],
                const SizedBox(height: 12),
                FilledButton(
                    key: const Key('ssh-test'),
                    onPressed: busy || (method == 'ssh' && profile == null)
                        ? null
                        : () => run(start),
                    child: Text(method == 'manual'
                        ? 'Inventarregistrierung prüfen'
                        : 'SSH-Verbindung testen')),
              ],
              if (step == 2) ...[
                Text(switch (stage) {
                  'connecting' => 'Connecting · SSH-Handshake',
                  'awaiting_host_key' =>
                    'Unbekannter Host-Key · Bestätigung erforderlich',
                  'ready_for_authentication' =>
                    'Host-Key bereits vertrauenswürdig',
                  'authenticating' => 'Authenticating',
                  'reading_device_information' => 'Reading device information',
                  'failed' => 'Verification failed',
                  _ => stage ?? 'Prüfung läuft'
                }),
                if (plan?.fingerprint != null)
                  Semantics(
                      container: true,
                      child: SelectionArea(
                          child: Text(plan!.fingerprint!,
                              key: const Key('host-key-fingerprint')))),
                if (stage == 'awaiting_host_key') ...[
                  const Text(
                      'Vergleiche diesen Fingerprint über einen unabhängigen vertrauenswürdigen Weg mit dem Zielgerät. Der Handshake allein beweist keine Geräteidentität.'),
                  FilledButton(
                      key: const Key('trust-host-key'),
                      onPressed:
                          busy ? null : () => run(() => verify(trust: true)),
                      child: const Text(
                          'Fingerprint geprüft · diesem Host-Key vertrauen')),
                ],
                if (stage == 'ready_for_authentication')
                  FilledButton(
                      onPressed: busy ? null : () => run(verify),
                      child:
                          const Text('Authentifizieren und Hostdaten lesen')),
                if (stage == 'failed')
                  const Text(
                      'Inventar und bisherige Identität bleiben erhalten. Schließe den Dialog und korrigiere Endpoint oder Identität für einen neuen Versuch.'),
              ],
              if (step == 3) ...[
                if (method == 'manual')
                  const Text(
                      'Nur Inventar: Registered · Connectivity Unknown · Telemetry NoCollector · Health NotEvaluated. Es wird keine Verbindung aufgebaut.')
                else ...[
                  const Text(
                      'Verification complete · tatsächlich gelesene Geräteidentität'),
                  ...identityWidgets(plan!.identity!),
                  const Text(
                      'Vergleiche diese Informationen mit deinem erwarteten Gerät. Ein gleicher Anzeigename ist kein Identitätsnachweis.'),
                  const Text(
                      'Monitoring wird erst nach der Identitätsbestätigung separat aktiviert.'),
                ],
                CheckboxListTile(
                    key: const Key('confirm-device-identity'),
                    value: consent,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => consent = v ?? false),
                    title: Text(method == 'manual'
                        ? 'Ich bestätige die reine Inventarregistrierung ohne Verbindung.'
                        : 'Diese ermittelte Identität gehört zum ausgewählten Gerät.')),
                FilledButton(
                    key: const Key('persist-device-connection'),
                    onPressed: busy || !consent ? null : () => run(confirm),
                    child: Text(method == 'manual'
                        ? 'Nur im Inventar registrieren'
                        : 'Identität bestätigen und Verbindung speichern')),
              ],
              if (step == 4) ...[
                Text(method == 'manual'
                    ? 'Inventar gespeichert. Keine Verbindung und keine Telemetrie.'
                    : monitor
                        ? 'SSH-Identität verifiziert und Collector aktiviert. Collecting wird erst nach tatsächlich empfangenen Messwerten angezeigt.'
                        : 'SSH Verified. Monitoring bleibt deaktiviert.'),
                if (method == 'ssh' && !monitor) ...[
                  const Text(
                      'Optional: Feste read-only Systemabfragen. Keine Remote-Installation.'),
                  field('Polling-Intervall in Sekunden (10–3600)', interval,
                      'poll-seconds'),
                  FilledButton(
                      key: const Key('enable-device-monitoring'),
                      onPressed: busy ? null : () => run(enableMonitoring),
                      child: const Text('Monitoring aktivieren')),
                  const Text(
                      'Du kannst Monitoring auch später im Geräte-Inspector einschalten.'),
                ],
                Text(
                    'Geräte-ID: ${widget.deviceId ?? plan?.deviceId ?? registrationId}'),
                FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Zum Geräteinventar')),
              ],
            ],
          )),
    ));
  }
}

List<Widget> identityWidgets(Json info) => [
      for (final pair in [
        ('Hostname', 'hostname'),
        ('Betriebssystem', 'operating_system'),
        ('Architektur', 'architecture'),
        ('CPU', 'cpu_info'),
        ('Modell', 'model'),
        ('RAM gesamt (Bytes)', 'memory_total_bytes'),
        ('RAM belegt (Bytes)', 'memory_used_bytes'),
        ('Uptime (Sekunden)', 'uptime_seconds'),
        ('Erfasst um', 'captured_at_ms')
      ])
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
                '${pair.$1}: ${info[pair.$2] ?? 'Unbekannt / nicht verfügbar'}')),
      Text('Datenträger: ${info['disks']}'),
      Text('Netzwerk-Interfaces (vom Host gemeldet): ${info['interfaces']}'),
      Text('Nicht verfügbar: ${(info['unavailable'] as List).join(', ')}'),
      Text('Provenienz: ${info['provenance']}'),
    ];
