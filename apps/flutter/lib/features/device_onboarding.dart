import '../l10n/oip_strings.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../app/controller.dart';
import '../models/contracts.dart';
import '../models/onboarding.dart';
import '../services/api.dart';
import '../widgets/device_kind.dart';

Future<String?> showDeviceOnboarding(
        BuildContext context, OipController controller,
        {String? deviceId, bool forOpcua = false}) =>
    showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DeviceOnboarding(
            controller: controller, deviceId: deviceId, forOpcua: forOpcua));

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
  final bool forOpcua;
  const DeviceOnboarding({
    super.key,
    required this.controller,
    this.deviceId,
    this.forOpcua = false,
  });
  @override
  State<DeviceOnboarding> createState() => _DeviceOnboardingState();
}

class _DeviceOnboardingState extends State<DeviceOnboarding> {
  final name = TextEditingController(),
      host = TextEditingController(),
      port = TextEditingController(text: '22'),
      user = TextEditingController(),
      interval = TextEditingController(text: '30'),
      organizationName = TextEditingController(),
      infrastructureName = TextEditingController(),
      siteName = TextEditingController();
  OrganizationSetupApi? get organizationApi {
    final transport = widget.controller.api;
    return transport is OrganizationSetupApi
        ? transport as OrganizationSetupApi
        : null;
  }

  bool canCreateOrganization = false, creatingOrganization = false;
  String? organizationRequestId;
  OnboardingScope? createdPlacement;
  late final DeviceManagementApi api = widget.controller.management!;
  final registrationId = _id();
  List<HierarchyItem> organizations = [], infrastructures = [], sites = [];
  List<SshProfile> profiles = [];
  String? organization, infrastructure, site, profile, error;
  (String, String)? preparedTarget;
  bool manualSsh = false;

  List<(SshProfile, String)> get preparedTargets => [
        for (final option in profiles)
          for (final alias in option.aliases) (option, alias)
      ];
  bool get usesPreparedTarget => preparedTargets.isNotEmpty && !manualSsh;
  bool get active => mounted && !_scopeInvalidated;
  String kind = 'other', method = 'ssh';
  int step = 0, revision = 0;
  bool busy = true, consent = false, monitor = false, done = false;
  ConnectionPlan? plan;
  DeviceConnection? savedConnection;
  Timer? timer;
  bool polling = false;
  late final int _contextRevision;
  late final String _scopeSignature;
  bool _scopeInvalidated = false;

  void contextChanged() {
    if (!mounted ||
        _scopeInvalidated ||
        (_contextRevision == widget.controller.contextRevision &&
            _scopeSignature == widget.controller.contextScopeSignature)) {
      return;
    }
    _scopeInvalidated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || route.isFirst || !route.isActive) return;
      final navigator = route.navigator;
      if (navigator == null) return;
      if (route.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(route);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void initState() {
    super.initState();
    if (widget.forOpcua) {
      method = 'manual';
      kind = 'industrial_device';
    }
    _contextRevision = widget.controller.contextRevision;
    _scopeSignature = widget.controller.contextScopeSignature;
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
    for (final c in [
      name,
      host,
      port,
      user,
      interval,
      organizationName,
      infrastructureName,
      siteName,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function() operation) async {
    if (busy || _scopeInvalidated) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
    } catch (e) {
      if (active) {
        setState(() => error = apiErrorMessage(
            e,
            context.tr(
                "Vorgang fehlgeschlagen. Es wurde keine erfolgreiche Verbindung bestätigt.")));
      }
    } finally {
      if (active) setState(() => busy = false);
    }
  }

  Future<void> load() async {
    try {
      final ctx = widget.controller.onboardingScope;
      organizations = await api.hierarchy('organizations', {});
      if (!mounted || _scopeInvalidated) return;
      organization = organizations.any((o) => o.id == ctx.organization)
          ? ctx.organization
          : organizations.firstOrNull?.id;
      await loadInfrastructure(ctx.infrastructure, ctx.site);
      if (!mounted || _scopeInvalidated) return;
      if (widget.deviceId != null) {
        final item = await api.inventory(widget.deviceId!);
        if (!mounted || _scopeInvalidated) return;
        final record = item['record'] as Json,
            device = record['device'] as Json;
        name.text = device['display_name'] as String;
        kind = device['device_type'] as String;
        revision = record['revision'] as int;
        organization = item['organization_id'] as String;
        await loadInfrastructure(
            item['infrastructure_id'] as String, device['site_id'] as String);
      }
      if (!mounted || _scopeInvalidated) return;
      if (widget.deviceId == null) {
        try {
          canCreateOrganization =
              await organizationApi?.canCreateOrganization() ?? false;
        } on ApiFailure {
          // The installed Core may predate organization creation.
        }
      }
      if (!active || widget.forOpcua) return;
      final options = await api.connection(deviceId: widget.deviceId);
      if (!active) return;
      profiles = options.profiles;
      profile = profiles.firstOrNull?.id;
      final preset = preparedTargets.singleOrNull;
      if (preset != null) preparedTarget = (preset.$1.id, preset.$2);
    } catch (e) {
      if (!mounted || _scopeInvalidated) return;
      error = apiErrorMessage(
          e,
          context
              .tr("Autorisierte Konfiguration konnte nicht geladen werden."));
    } finally {
      if (active) setState(() => busy = false);
    }
  }

  Future<void> createOrganization() async {
    final management = organizationApi;
    if (management == null || !canCreateOrganization) return;
    final labels = [
      organizationName.text.trim(),
      infrastructureName.text.trim(),
      siteName.text.trim(),
    ];
    if (labels.any((label) => label.isEmpty)) {
      throw ApiFailure(context.tr(
          'Gib einen Namen für Organisation, Infrastruktur und Standort ein.'));
    }
    final placement = createdPlacement ??= await management.createOrganization(
      requestId: organizationRequestId ??= _id(),
      organization: labels[0],
      infrastructure: labels[1],
      site: labels[2],
    );
    if (!active) return;
    final newOrganizations = await api.hierarchy('organizations', {});
    final newInfrastructures = await api.hierarchy(
        'infrastructures', {'organization': placement.organization!});
    final newSites = await api
        .hierarchy('sites', {'infrastructure': placement.infrastructure!});
    if (!active) return;
    if (!newOrganizations.any((row) => row.id == placement.organization) ||
        !newInfrastructures.any((row) => row.id == placement.infrastructure) ||
        !newSites.any((row) => row.id == placement.site)) {
      throw ApiFailure(
          context.tr('Die neue Organisation konnte nicht ausgewählt werden.'));
    }
    setState(() {
      organizations = newOrganizations;
      infrastructures = newInfrastructures;
      sites = newSites;
      organization = placement.organization;
      infrastructure = placement.infrastructure;
      site = placement.site;
      creatingOrganization = false;
      organizationRequestId = null;
      createdPlacement = null;
      organizationName.clear();
      infrastructureName.clear();
      siteName.clear();
    });
    unawaited(widget.controller
        .resyncInfrastructure()
        .then<void>((_) {}, onError: (Object _) {}));
  }

  Future<void> loadInfrastructure(
      [String? preferred, String? preferredSite]) async {
    infrastructures = organization == null
        ? []
        : await api
            .hierarchy('infrastructures', {'organization': organization!});
    if (!mounted || _scopeInvalidated) return;
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
    if (site == null || name.text.trim().isEmpty) {
      throw ApiFailure(
          context.tr("Gib einen Gerätenamen ein und wähle einen Standort."));
    }
    if (method == 'manual') {
      setState(() => step = 3);
      return;
    }
    final selected = usesPreparedTarget ? preparedTarget : null;
    final selectedProfile = usesPreparedTarget ? selected?.$1 : profile;
    if (selectedProfile == null) {
      throw ApiFailure(context.tr("Wähle einen vorbereiteten Gerätezugang."));
    }
    final parsed = selected == null ? int.tryParse(port.text) : 22;
    if (parsed == null || parsed < 1 || parsed > 65535) {
      throw ApiFailure(
          context.tr('SSH-Port muss zwischen 1 und 65535 liegen.'));
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
        'host': selected == null ? host.text.trim() : '',
        'port': parsed,
        'user': selected == null ? user.text.trim() : '',
        'identity_profile': selectedProfile,
        'alias': selected?.$2
      }
    });
    if (!active) {
      final id = result.plan?.id;
      if (id != null) {
        unawaited(api
            .configure({'operation': 'cancel', 'plan_id': id}).then<void>(
                (_) {},
                onError: (Object _) {}));
      }
      return;
    }
    setState(() {
      plan = result.plan;
      step = 2;
    });
    timer = Timer.periodic(const Duration(milliseconds: 600), (_) => poll());
  }

  Future<void> poll() async {
    if (polling || plan == null || !active) return;
    polling = true;
    final id = plan!.id;
    try {
      final result = await api.connection(planId: id);
      if (!active || step != 2 || plan?.id != id) return;
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
      if (active && step == 2 && plan?.id == id) {
        setState(() => error = apiErrorMessage(
            e, context.tr("Verbindungsstatus konnte nicht gelesen werden.")));
        timer?.cancel();
      }
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
    if (!active) return;
    final r = await api.configure({'operation': 'verify', 'plan_id': plan!.id});
    if (active && step == 2) setState(() => plan = r.plan);
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
        'enable_monitoring': usesPreparedTarget,
        'poll_seconds': n
      });
      savedConnection = saved.connection;
      monitor = savedConnection?.enabled == true;
    }
    if (!active) return;
    if (widget.forOpcua) {
      done = true;
      Navigator.pop(context, registrationId);
      widget.controller.reconnect();
      return;
    }
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

  Future<void> editConnection() async {
    timer?.cancel();
    final id = plan?.id;
    if (id != null) {
      try {
        await api.configure({'operation': 'cancel', 'plan_id': id});
      } on ApiFailure catch (failure) {
        if (failure.statusCode != 404) rethrow;
      }
    }
    if (!active) return;
    setState(() {
      consent = false;
      plan = null;
      step = 1;
    });
  }

  Widget select(String label, String? value, List<HierarchyItem> values,
          void Function(String?) changed, {bool locked = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
              key: ValueKey('$label-$value'),
              value: values.any((v) => v.id == value) ? value : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.tr(label)),
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
              decoration: InputDecoration(labelText: context.tr(label))));
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
                            ? context
                                .tr("Verbindung für dieses Gerät einrichten")
                            : context.tr(widget.forOpcua
                                ? "OPC-UA-Gerät registrieren"
                                : "Gerät hinzufügen"),
                        style: Theme.of(context).textTheme.headlineSmall)),
                IconButton(
                    tooltip: context.tr("Einrichtung schließen"),
                    onPressed: busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close))
              ]),
              if (!widget.forOpcua)
                Text(context.tr("Schritt {0}/5 · {1}", [
                  step + 1,
                  [
                    'Infrastruktur auswählen',
                    'Verbindung konfigurieren',
                    'Verbindung testen',
                    'Gerät bestätigen',
                    method == 'manual'
                        ? 'Inventar gespeichert'
                        : 'Monitoring aktivieren'
                  ][step]
                ])),
              const SizedBox(height: 16),
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(error!,
                        key: const Key('onboarding-error'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              if (step == 0 && creatingOrganization) ...[
                field('Name der Organisation', organizationName,
                    'organization-name',
                    locked: createdPlacement != null),
                field('Name der Infrastruktur', infrastructureName,
                    'infrastructure-name',
                    locked: createdPlacement != null),
                field('Name des ersten Standorts', siteName, 'site-name',
                    locked: createdPlacement != null),
                FilledButton(
                  key: const Key('save-new-organization'),
                  onPressed: busy ? null : () => run(createOrganization),
                  child: Text(context.tr(createdPlacement == null
                      ? 'Organisation erstellen'
                      : 'Auswahl neu laden')),
                ),
                TextButton(
                  onPressed: busy || createdPlacement != null
                      ? null
                      : () => setState(() {
                            creatingOrganization = false;
                            error = null;
                          }),
                  child: Text(context.tr('Zurück')),
                ),
              ],
              if (step == 0 && !creatingOrganization) ...[
                select(
                    'Organisation',
                    organization,
                    organizations,
                    (v) => run(() async {
                          organization = v;
                          await loadInfrastructure();
                        }),
                    locked: existing),
                select(
                    'Infrastruktur',
                    infrastructure,
                    infrastructures,
                    (v) => run(() async {
                          infrastructure = v;
                          await loadSites();
                        }),
                    locked: existing),
                select('Standort', site, sites, (v) => setState(() => site = v),
                    locked: existing),
                if (canCreateOrganization)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('create-organization'),
                      onPressed: busy
                          ? null
                          : () => setState(() {
                                creatingOrganization = true;
                                error = null;
                              }),
                      icon: const Icon(Icons.add),
                      label: Text(context.tr('Neue Organisation')),
                    ),
                  ),
                field('Anzeigename', name, 'device-name', locked: existing),
                if (!existing)
                  DropdownButtonFormField<String>(
                      key: const Key('onboarding-type'),
                      isExpanded: true,
                      value: kind,
                      decoration:
                          InputDecoration(labelText: context.tr("Gerätetyp")),
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
                          .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text(context.tr(deviceKindName(v)))))
                          .toList(),
                      onChanged: (v) => setState(() => kind = v!)),
                const SizedBox(height: 12),
                FilledButton(
                    key: const Key('onboarding-scope-next'),
                    onPressed: busy || site == null
                        ? null
                        : widget.forOpcua
                            ? () => run(start)
                            : () => setState(() => step = 1),
                    child: Text(context.tr(widget.forOpcua
                        ? "Registrierung prüfen"
                        : "Verbindungsmethode wählen"))),
              ],
              if (step == 1) ...[
                DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: method,
                    decoration: InputDecoration(
                        labelText: context.tr("Verbindungsmethode")),
                    items: [
                      DropdownMenuItem(
                          value: 'ssh',
                          child: Text(context.tr(preparedTargets.isEmpty
                              ? "SSH — Linux / macOS"
                              : "Computer oder Router verbinden"))),
                      if (!existing)
                        DropdownMenuItem(
                            value: 'manual',
                            child: Text(
                                context.tr("Nur Inventar, keine Verbindung"))),
                    ],
                    onChanged:
                        busy ? null : (v) => setState(() => method = v!)),
                const SizedBox(height: 12),
                if (method == 'ssh') ...[
                  if (preparedTargets.isNotEmpty) ...[
                    if (usesPreparedTarget)
                      DropdownButtonFormField<(String, String)>(
                          key: const Key('prepared-ssh-target'),
                          isExpanded: true,
                          value: preparedTarget,
                          decoration: InputDecoration(
                              labelText: context.tr("Vorbereitetes Gerät")),
                          items: preparedTargets
                              .map((item) => DropdownMenuItem(
                                  value: (item.$1.id, item.$2),
                                  child: Text(item.$2,
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: busy
                              ? null
                              : (value) =>
                                  setState(() => preparedTarget = value)),
                    TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => manualSsh = !manualSsh),
                        child: Text(context.tr(usesPreparedTarget
                            ? "Verbindungsdaten selbst eingeben"
                            : "Vorbereitetes Gerät auswählen"))),
                  ],
                  if (!usesPreparedTarget) ...[
                    if (profiles.isEmpty)
                      Text(context.tr(
                          "Für diesen Bereich ist noch kein Gerätezugang freigegeben. Wende dich an die Person, die deine OIP-Installation verwaltet.")),
                    if (profiles.isNotEmpty)
                      DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: profile,
                          decoration: InputDecoration(
                              labelText: context.tr("Lokale SSH-Identität")),
                          items: profiles
                              .map((p) => DropdownMenuItem(
                                  value: p.id, child: Text(p.label)))
                              .toList(),
                          onChanged:
                              busy ? null : (v) => setState(() => profile = v)),
                    if (profiles.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      field('Hostname oder IP-Adresse', host, 'ssh-host'),
                      field('SSH-Port', port, 'ssh-port'),
                      field('SSH-Benutzer (kein root)', user, 'ssh-user'),
                    ],
                  ],
                ],
                const SizedBox(height: 12),
                FilledButton(
                    key: const Key('ssh-test'),
                    onPressed: busy ||
                            (method == 'ssh' &&
                                (usesPreparedTarget
                                    ? preparedTarget == null
                                    : profile == null))
                        ? null
                        : () => run(start),
                    child: Text(method == 'manual'
                        ? context.tr("Inventarregistrierung prüfen")
                        : context.tr(usesPreparedTarget
                            ? "Gerät prüfen"
                            : "SSH-Verbindung testen"))),
              ],
              if (step == 2) ...[
                Text(switch (stage) {
                  'connecting' => context.tr(usesPreparedTarget
                      ? "Die App sucht das ausgewählte Gerät."
                      : "Connecting · SSH-Handshake"),
                  'awaiting_host_key' => context.tr(usesPreparedTarget
                      ? "Für dieses Gerät ist keine bestätigte Identität hinterlegt. Wende dich an die Person, die deine OIP-Installation verwaltet."
                      : "Unbekannter Host-Key · Bestätigung erforderlich"),
                  'ready_for_authentication' => context.tr(usesPreparedTarget
                      ? "Das Gerät hat sich mit seinem bekannten Schlüssel gemeldet."
                      : "Host-Key bereits vertrauenswürdig"),
                  'authenticating' => context.tr(usesPreparedTarget
                      ? "Die App meldet sich am Gerät an."
                      : "Authenticating"),
                  'reading_device_information' => context.tr(usesPreparedTarget
                      ? "Die App liest Geräteinformationen."
                      : "Reading device information"),
                  'failed' => context.tr(usesPreparedTarget
                      ? "Das Gerät konnte nicht geprüft werden."
                      : "Verification failed"),
                  _ => stage ?? context.tr("Prüfung läuft")
                }),
                if (!usesPreparedTarget && plan?.fingerprint != null)
                  Semantics(
                      container: true,
                      child: SelectionArea(
                          child: Text(plan!.fingerprint!,
                              key: const Key('host-key-fingerprint')))),
                if (stage == 'awaiting_host_key' && !usesPreparedTarget) ...[
                  Text(context.tr(
                      "Vergleiche diesen Fingerprint über einen unabhängigen vertrauenswürdigen Weg mit dem Zielgerät. Der Handshake allein beweist keine Geräteidentität.")),
                  FilledButton(
                      key: const Key('trust-host-key'),
                      onPressed:
                          busy ? null : () => run(() => verify(trust: true)),
                      child: Text(context.tr(
                          "Fingerprint geprüft · diesem Host-Key vertrauen"))),
                ],
                if (stage == 'ready_for_authentication')
                  FilledButton(
                      onPressed: busy ? null : () => run(verify),
                      child: Text(context.tr(usesPreparedTarget
                          ? "Geräteinformationen abrufen"
                          : "Authentifizieren und Hostdaten lesen"))),
                if (stage == 'failed' ||
                    (stage == 'awaiting_host_key' && usesPreparedTarget) ||
                    error != null)
                  TextButton(
                      onPressed: busy ? null : () => run(editConnection),
                      child: Text(context.tr("Verbindungsauswahl ändern"))),
              ],
              if (step == 3) ...[
                if (method == 'manual')
                  Text(context.tr(
                    widget.forOpcua
                        ? "Gerät {0} am Standort {1} registrieren. Danach kannst du die OPC-UA-Verbindung einrichten."
                        : "Nur Inventar: Registered · Connectivity Unknown · Telemetry NoCollector · Health NotEvaluated. Es wird keine Verbindung aufgebaut.",
                    widget.forOpcua
                        ? [
                            name.text.trim(),
                            sites
                                    .where((row) => row.id == site)
                                    .firstOrNull
                                    ?.name ??
                                ''
                          ]
                        : const [],
                  ))
                else ...[
                  Text(context.tr(
                      "Verification complete · tatsächlich gelesene Geräteidentität")),
                  if (usesPreparedTarget) ...[
                    Text(context
                        .tr("Gerätename: {0}", [plan!.identity!['hostname']])),
                    Text(context.tr("Betriebssystem: {0}",
                        [plan!.identity!['operating_system']])),
                    ExpansionTile(
                        title: Text(context.tr("Technische Gerätedaten")),
                        children: identityWidgets(plan!.identity!)),
                  ] else
                    ...identityWidgets(plan!.identity!),
                  Text(context.tr(
                      "Vergleiche diese Informationen mit deinem erwarteten Gerät. Ein gleicher Anzeigename ist kein Identitätsnachweis.")),
                  Text(context.tr(usesPreparedTarget
                      ? "Nach deiner Bestätigung beginnt die App mit der Überwachung."
                      : "Monitoring wird erst nach der Identitätsbestätigung separat aktiviert.")),
                ],
                CheckboxListTile(
                    key: const Key('confirm-device-identity'),
                    value: consent,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => consent = v ?? false),
                    title: Text(method == 'manual'
                        ? context.tr(
                            "Ich bestätige die reine Inventarregistrierung ohne Verbindung.")
                        : context.tr(
                            "Diese ermittelte Identität gehört zum ausgewählten Gerät."))),
                FilledButton(
                    key: const Key('persist-device-connection'),
                    onPressed: busy || !consent ? null : () => run(confirm),
                    child: Text(method == 'manual'
                        ? context.tr("Nur im Inventar registrieren")
                        : context.tr(
                            "Identität bestätigen und Verbindung speichern"))),
                if (widget.forOpcua)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                              step = 0;
                              consent = false;
                            }),
                    child: Text(context.tr('Zurück')),
                  ),
              ],
              if (step == 4) ...[
                Text(method == 'manual'
                    ? context.tr(
                        "Inventar gespeichert. Keine Verbindung und keine Telemetrie.")
                    : monitor
                        ? context.tr(
                            "SSH-Identität verifiziert und Collector aktiviert. Collecting wird erst nach tatsächlich empfangenen Messwerten angezeigt.")
                        : context.tr(
                            "SSH Verified. Monitoring bleibt deaktiviert.")),
                if (method == 'ssh' && !monitor) ...[
                  Text(context.tr(
                      "Optional: Feste read-only Systemabfragen. Keine Remote-Installation.")),
                  field('Polling-Intervall in Sekunden (10–3600)', interval,
                      'poll-seconds'),
                  FilledButton(
                      key: const Key('enable-device-monitoring'),
                      onPressed: busy ? null : () => run(enableMonitoring),
                      child: Text(context.tr("Monitoring aktivieren"))),
                  Text(context.tr(
                      "Du kannst Monitoring auch später im Geräte-Inspector einschalten.")),
                ],
                if (!usesPreparedTarget || method == 'manual')
                  Text(context.tr("Geräte-ID: {0}",
                      [widget.deviceId ?? plan?.deviceId ?? registrationId])),
                FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.tr("Zum Geräteinventar"))),
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
