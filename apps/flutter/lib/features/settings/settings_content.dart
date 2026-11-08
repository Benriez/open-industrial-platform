import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../design_system/theme.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'settings_models.dart';
import 'settings_navigation.dart';
import 'settings_session.dart';
import 'settings_tool_explorer.dart';

class SettingsSectionContent extends StatelessWidget {
  final SettingsSection section;
  final SettingsWorkspaceSession session;
  final SettingsSnapshot? settings;
  final ManagementReport? report;
  final ManagementReport? secondary;
  final ManagementReport? extra;
  final OipController controller;
  final OipThemeVariant themeVariant;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final VoidCallback onFiltersChanged;
  final VoidCallback onSchemaChanged;
  final ValueChanged<ManagedTool> onSelectTool;
  final ValueChanged<String> onSelectSetting;
  final ValueChanged<OipThemeVariant> onTheme;
  final void Function(String label, String value) onCopy;

  const SettingsSectionContent({
    super.key,
    required this.section,
    required this.session,
    required this.settings,
    required this.report,
    required this.secondary,
    required this.extra,
    required this.controller,
    required this.themeVariant,
    required this.searchController,
    required this.searchFocus,
    required this.onFiltersChanged,
    required this.onSchemaChanged,
    required this.onSelectTool,
    required this.onSelectSetting,
    required this.onTheme,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) => switch (section) {
        SettingsSection.application => _application(context),
        SettingsSection.preferences => _preferences(context),
        SettingsSection.mcpServer => _server(context),
        SettingsSection.clientConfiguration => _clientConfiguration(context),
        SettingsSection.tools => SettingsToolExplorer(
            report: report!,
            session: session,
            searchController: searchController,
            searchFocus: searchFocus,
            onFiltersChanged: onFiltersChanged,
            onSelect: onSelectTool,
            onCopy: onCopy,
          ),
        SettingsSection.permissions ||
        SettingsSection.effectivePermissions =>
          _permissions(context),
        SettingsSection.connectionDiagnostics => _diagnostics(context),
        SettingsSection.clientSessions => _sessions(context),
        SettingsSection.organizations ||
        SettingsSection.infrastructures ||
        SettingsSection.sites =>
          _hierarchy(context),
        SettingsSection.sourcesDevices => _sourcesDevices(context),
        SettingsSection.sqlite => _storage(context),
        SettingsSection.historicalData => _historical(context),
        SettingsSection.retention => _retention(context),
        SettingsSection.diagnosticRules ||
        SettingsSection.evidence =>
          _diagnosticRules(context),
        SettingsSection.historyLimits => _historyLimits(context),
        SettingsSection.currentIdentity ||
        SettingsSection.auditSecurity =>
          _security(context),
        SettingsSection.runtime || SettingsSection.versions => _system(context),
        SettingsSection.capabilities => _capabilities(context),
      };

  Widget _application(BuildContext context) {
    final snapshot = settings!;
    // A settings form is small and fully materialized; this keeps every row in
    // the widget tree so keyboard/screen-reader navigation reaches all of them.
    return SingleChildScrollView(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SettingsSectionHeader(
        title: 'Application Settings',
        subtitle:
            'Drei validierte Core-Schlüssel. Effektiver Wert, Default, Persistenz und Apply-Status bleiben getrennt.',
        status: 'OFFLINE ADMINISTRATION REQUIRED',
        statusColor: OipTokens.yellow,
      ),
      const SizedBox(height: 12),
      const WorkstationNote(
        'Kein Browser-Save',
        'Der Core besitzt keinen HTTP-/MCP-Schreibpfad. Änderungen erfordern den exklusiven lokalen Operator-CLI-Prozess und werden erst beim nächsten validierten Core-Start aktiv.',
        icon: Icons.offline_bolt_outlined,
        color: OipTokens.yellow,
      ),
      const SizedBox(height: 12),
      for (final definition in snapshot.definitions) ...[
        _settingRow(
            context,
            definition,
            snapshot.settings
                .where((setting) => setting.key == definition.key)
                .firstOrNull),
        const SizedBox(height: 6),
      ],
      const Hairline(),
      KeyValue('Inheritance', snapshot.inheritance, mono: false),
      KeyValue('Startup snapshot loaded at',
          snapshot.loadedAtMs?.toString() ?? 'Redacted / not delivered'),
      const WorkstationNote(
        'Requires Restart',
        'active_startup_snapshot beschreibt den laufenden Snapshot. persisted_requires_restart wäre ein Offline-Ergebnis, kein aktiver Runtime-Wert. Ein exakter Scope-Datensatz und ein geerbter effektiver Wert sind nicht dasselbe.',
        icon: Icons.restart_alt_outlined,
      ),
    ]));
  }

  Widget _settingRow(BuildContext context, SettingDefinition definition,
      EffectiveSetting? effective) {
    final selected = session.selectedSetting == definition.key;
    final tone = OipTokens.readableAccent(context, OipTokens.cyan);
    return Semantics(
      button: true,
      selected: selected,
      label:
          'Setting ${definition.key}. Effektiver Wert ${effective?.effective.display ?? 'Unknown'}. Offline Administration Required.',
      child: Material(
        color:
            selected ? tone.withOpacity(.1) : WorkstationTokens.well(context),
        borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
        child: InkWell(
          key: Key('settings-setting-${definition.key}'),
          borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
          onTap: () => onSelectSetting(definition.key),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(definition.key,
                      style: WorkstationTokens.mono(context,
                          size: 13, weight: FontWeight.w700)),
                ),
                const StatusPill('READ ONLY', icon: Icons.lock_outline),
              ]),
              const SizedBox(height: 4),
              Text(definition.description,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              LayoutBuilder(builder: (context, box) {
                final compact = box.maxWidth < 520;
                final values = [
                  ('EFFECTIVE', effective?.effective.display ?? 'Unknown'),
                  ('TYPE', definition.dataType),
                  (
                    'SOURCE SCOPE',
                    effective?.origin?.display ?? 'built_in_default'
                  ),
                  ('APPLY', effective?.applyStatus ?? 'Unknown'),
                ];
                final width = compact ? box.maxWidth : (box.maxWidth - 16) / 4;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: values
                      .map((value) => SizedBox(
                            width: width,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(value.$1,
                                      style:
                                          WorkstationTokens.eyebrow(context)),
                                  Text(value.$2,
                                      style: WorkstationTokens.mono(context,
                                          size: 11)),
                                ]),
                          ))
                      .toList(),
                );
              }),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _preferences(BuildContext context) {
    const themes = [
      (
        OipThemeVariant.spectrum,
        'Spectrum',
        'Near-black · präzise Spektral-Akzente'
      ),
      (
        OipThemeVariant.graphite,
        'Graphite',
        'Neutral dunkel · reduzierte Farbwirkung'
      ),
      (
        OipThemeVariant.daylight,
        'Daylight',
        'Helle Oberflächen · hohe Lesbarkeit'
      ),
    ];
    return ListView(children: [
      const SettingsSectionHeader(
        title: 'Appearance & Preferences',
        subtitle: 'Tatsächlich unterstützte Flutter-Theme-Varianten.',
        status: 'CLIENT LOCAL',
        statusColor: OipTokens.cyan,
      ),
      const SizedBox(height: 12),
      const WorkstationNote(
        'Nur diese UI-Sitzung',
        'Die Auswahl ändert das laufende Flutter-Designsystem sofort. Sie ist keine serverweite Core-Konfiguration und wird nicht als solche persistiert.',
        icon: Icons.palette_outlined,
      ),
      const SizedBox(height: 12),
      for (final theme in themes)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Semantics(
            button: true,
            selected: themeVariant == theme.$1,
            label: 'Theme ${theme.$2}. Lokale UI-Präferenz.',
            child: Material(
              color: themeVariant == theme.$1
                  ? OipTokens.cyan.withOpacity(.11)
                  : WorkstationTokens.well(context),
              borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
              child: RadioListTile<OipThemeVariant>(
                key: Key('settings-theme-${theme.$1.name}'),
                value: theme.$1,
                groupValue: themeVariant,
                onChanged: (value) {
                  if (value != null) onTheme(value);
                },
                title: Text(theme.$2),
                subtitle: Text(theme.$3),
              ),
            ),
          ),
        ),
      const Hairline(),
      const KeyValue('Server preference synchronization', 'unsupported'),
      const KeyValue('Additional density/language controls',
          'not exposed by this design system'),
    ]);
  }

  Widget _server(BuildContext context) {
    final value = report!;
    final system = secondary;
    final tools = extra;
    return ListView(children: [
      const SettingsSectionHeader(
        title: 'MCP Server',
        subtitle:
            'Reale Core-Komposition, lokale stdio-Bridges und Unix-IPC. Kein Remote-MCP-Listener.',
        status: 'LOCAL STDIO / IPC',
      ),
      const SizedBox(height: 12),
      SettingsMetricStrip([
        ('RUNTIME', value.fact('runtime_mode'), Icons.settings_ethernet),
        (
          'TOOLS',
          tools?.tools.length.toString() ?? 'Unknown',
          Icons.smart_toy_outlined
        ),
        (
          'CAPABILITIES',
          system?.fact('registered_core_capabilities') ?? 'Unknown',
          Icons.hub_outlined
        ),
        (
          'LIFECYCLE',
          value.fact('core_lifecycle'),
          Icons.monitor_heart_outlined
        ),
      ]),
      const SizedBox(height: 12),
      SettingsFacts(value.facts),
      const Hairline(),
      const WorkstationNote(
        'Read-only / Mutation Policy',
        'Der Katalog enthält keine mutierenden MCP-Tools. Enable/Disable, Remote MCP und per-tool Freigaben bleiben unsupported; geschützte Startup-Konfiguration ist maßgeblich.',
        icon: Icons.policy_outlined,
      ),
      const SizedBox(height: 10),
      SettingsLimitations(value.limitations),
    ]);
  }

  Widget _clientConfiguration(BuildContext context) {
    final config = report!.clientConfiguration!;
    return ListView(children: [
      const SettingsSectionHeader(
        title: 'MCP Client Configuration',
        subtitle:
            'Generisches mcpServers-Template aus dem Core-Vertrag. Keine Client-spezifische Konvertierung.',
        status: 'UNRESOLVED TEMPLATE',
        statusColor: OipTokens.yellow,
      ),
      const SizedBox(height: 12),
      SettingsMetricStrip([
        ('JSON', 'VALID', Icons.data_object),
        (
          'PLACEHOLDERS',
          config.usableWithoutReplacement ? 'NONE' : 'REQUIRED',
          Icons.edit_note
        ),
        (
          'CREDENTIAL',
          config.credentialProvisioned ? 'PROVISIONED' : 'NOT PROVISIONED',
          Icons.key_off_outlined
        ),
      ]),
      const SizedBox(height: 12),
      SettingsJsonBlock(
        config.prettyConfiguration,
        semanticsLabel:
            'MCP Client JSON Konfigurationsvorschau mit Platzhaltern',
        maxHeight: 290,
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          key: const Key('settings-copy-configuration'),
          onPressed: () =>
              onCopy('MCP-Konfiguration', config.prettyConfiguration),
          icon: const Icon(Icons.copy_outlined, size: 17),
          label: const Text('Copy Configuration'),
        ),
        OutlinedButton.icon(
          key: const Key('settings-copy-cli'),
          onPressed: () => onCopy('MCP-CLI-Template', config.cliTemplate),
          icon: const Icon(Icons.terminal, size: 17),
          label: const Text('Copy CLI Template'),
        ),
      ]),
      const SizedBox(height: 12),
      const WorkstationNote(
        'Vor Verwendung ersetzen',
        'Executable, privater Socket und Credential-Datei müssen aus einem bereits autorisierten lokalen Profil stammen. Platzhalter sind keine installierte Verbindung. Kopieren führt keinen Befehl aus und erzeugt keine Grants.',
        icon: Icons.warning_amber_outlined,
        color: OipTokens.yellow,
      ),
      const SizedBox(height: 12),
      const PanelLabel('Setup im MCP-Client'),
      ...const [
        '1. OIP Core mit geschützter lokaler IPC-Konfiguration starten.',
        '2. Vorhandenes autorisiertes Credential-Profil bereitstellen; die UI provisioniert nichts.',
        '3. Generische mcpServers-Konfiguration im geeigneten Client ergänzen.',
        '4. Verbindung ausschließlich durch diesen Client herstellen.',
        '5. Dort Tools entdecken; Sichtbarkeit und Ausführung bleiben policy-abhängig.',
      ].map((step) => Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text(step, style: const TextStyle(fontSize: 12)),
          )),
      SettingsLimitations(report!.limitations),
    ]);
  }

  Widget _permissions(BuildContext context) {
    final security = secondary;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SettingsSectionHeader(
        title: 'MCP Permissions & Scopes',
        subtitle:
            'Zentrale, read-only Permission-Matrix. Keine Selbstfreigabe und keine Rollenableitung.',
        status: 'POLICY READ ONLY',
      ),
      const SizedBox(height: 10),
      if (security != null)
        KeyValueGrid(children: [
          KeyValue('Current Principal', security.fact('principal')),
          const KeyValue('Role', 'Nicht im Management-Vertrag geliefert'),
          const KeyValue('Organization / Infrastructure / Site / Source',
              'Kein Principal-Scope-Inventar geliefert'),
          const KeyValue('Credential Management', 'unsupported'),
        ]),
      Expanded(
        child: SettingsPermissionMatrix(
          report: report!,
          session: session,
          onSelect: onSelectTool,
        ),
      ),
    ]);
  }

  Widget _diagnostics(BuildContext context) {
    final tools = secondary;
    final config = extra?.clientConfiguration;
    final technical = {
      'facts': {for (final fact in report!.facts) fact.name: fact.value},
      'tool_catalog_available': tools != null,
      'registered_tools': tools?.tools.length,
      'configuration_contract':
          config == null ? 'Unknown' : 'generic mcpServers JSON',
      'limitations': report!.limitations,
      'probe': 'none; authorized read-only status only',
    };
    return ListView(children: [
      SettingsSectionHeader(
        title: 'MCP Connection Diagnostics',
        subtitle:
            'Beobachtet ausschließlich die eigene autorisierte Core-Runtime. Kein Credential-, Datei-, Remote- oder Handshake-Test.',
        status: 'STATUS READ ONLY',
        actions: [
          ToolButton(
            icon: Icons.copy_outlined,
            tooltip: 'Technische Diagnoseinformationen kopieren',
            onPressed: () => onCopy('MCP-Diagnose',
                const JsonEncoder.withIndent('  ').convert(technical)),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SettingsFacts(report!.facts),
      const Hairline(),
      KeyValueGrid(children: [
        KeyValue(
            'Tool Catalog Availability',
            tools == null
                ? 'Unknown'
                : '${tools.tools.length} registrierte Tools geliefert'),
        KeyValue(
            'Config Contract',
            config == null
                ? 'Unknown'
                : 'Valides generisches JSON; Platzhalter erforderlich'),
        const KeyValue('Connection Test', 'Nicht durchgeführt'),
        const KeyValue('Credential / File Probe', 'Nicht durchgeführt'),
      ]),
      const SizedBox(height: 10),
      const WorkstationNote(
        'Kein Verbindungsnachweis',
        'Ein erfolgreicher Status-Read ist kein erfolgreicher MCP-Client-Handshake. Refresh wiederholt nur autorisierte GET-Reads.',
        icon: Icons.network_check_outlined,
      ),
      const SizedBox(height: 10),
      SettingsLimitations(report!.limitations),
    ]);
  }

  Widget _sessions(BuildContext context) => ListView(children: [
        const SettingsSectionHeader(
          title: 'MCP Client Sessions',
          subtitle:
              'Der Core besitzt keine verlässlich abfragbare initialized-client Registry.',
          status: 'UNSUPPORTED',
          statusColor: OipTokens.yellow,
        ),
        const SizedBox(height: 16),
        const Icon(Icons.cloud_off_outlined, size: 30, color: OipTokens.yellow),
        const SizedBox(height: 10),
        Text(
            'Aktive MCP-Client-Sessions können derzeit nicht zentral aufgelistet werden.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SettingsFacts(report!.facts),
        const WorkstationNote(
          'Keine Ersatzwerte',
          'Keine Client-Namen, Session-IDs, Connected-Zustände, Last-Activity-Werte oder Connection Counts. Ein konfiguriertes Clientprofil ist keine aktive Session.',
          icon: Icons.do_not_disturb_on_outlined,
        ),
        const SizedBox(height: 10),
        const KeyValue('Future backend requirement',
            'Typed, authorized initialized-session registry with lifecycle timestamps and explicit scope/redaction semantics'),
        SettingsLimitations(report!.limitations),
      ]);

  Widget _hierarchy(BuildContext context) => ListView(children: [
        SettingsSectionHeader(
          title: settingsSectionLabel(section),
          subtitle:
              'Bestehende autorisierte Hierarchie-Reads bleiben maßgeblich; Browser-Admin-Mutationen sind nicht verfügbar.',
          status: 'READ-ONLY / LIMITED BROWSER IDENTITY',
        ),
        const SizedBox(height: 12),
        if (!controller.infrastructure.ready)
          const WorkstationNote(
            'Kein autorisiertes Hierarchie-Inventar in dieser Browser-Ansicht',
            'Der aktuelle Lauf liefert keine autorisierten Organizations, Infrastructures oder Sites. Es werden weder Namen geraten noch Nullbestände behauptet.',
            icon: Icons.account_tree_outlined,
          )
        else ...[
          WorkstationNote(
            controller.infrastructure.selectedBreadcrumb,
            'Dieselbe globale Auswahl gilt in allen Workstations. Sie ist keine administrative Berechtigung.',
            icon: Icons.account_tree_outlined,
            color: OipTokens.cyan,
          ),
          if (section == SettingsSection.organizations)
            for (final item in controller.infrastructure.hierarchy.organizations.where(
                (item) => controller.infrastructure.selection.organizationId == null ||
                    item.id == controller.infrastructure.selection.organizationId))
              ListTile(
                dense: true,
                leading: const Icon(Icons.business_outlined),
                title: Text(item.name),
                subtitle: Text(item.id),
              ),
          if (section == SettingsSection.infrastructures)
            for (final item in controller.infrastructure.hierarchy.infrastructures.where(
                (item) => controller.infrastructure.selection.matches(
                    organizationId: item.organizationId,
                    infrastructureId: item.id)))
              ListTile(
                dense: true,
                leading: const Icon(Icons.hub_outlined),
                title: Text(item.name),
                subtitle: Text('${item.id} · Organization ${item.organizationId}'),
              ),
          if (section == SettingsSection.sites)
            for (final item in controller.infrastructure.hierarchy.sites.where(
                (item) => controller.infrastructure.selection.matches(
                    infrastructureId: item.infrastructureId, siteId: item.id)))
              ListTile(
                dense: true,
                leading: const Icon(Icons.location_on_outlined),
                title: Text(item.name),
                subtitle: Text('${item.id} · Infrastructure ${item.infrastructureId}'),
              ),
          if (controller.infrastructure.isFixture)
            const StatusPill('CONTRACT FIXTURE · NICHT LIVE',
                color: OipTokens.yellow, icon: Icons.science_outlined),
        ],
        const SizedBox(height: 12),
        const KeyValue('Browser administration',
            'offline operator administration required'),
        const KeyValue(
            'OIP-008.5 integration', 'not consumed; no unfinished API assumed'),
        const KeyValue('Required future contract',
            'Scoped typed list/detail DTOs, stable IDs, parent references, explicit availability and permission states'),
        const KeyValue('Creation / mutation',
            'unsupported in this UI; no unprotected REST writes'),
      ]);

  Widget _sourcesDevices(BuildContext context) {
    final snapshot = controller.snapshot;
    final sources = controller.operationalSources.isNotEmpty
        ? controller.operationalSources
        : snapshot?.sources ?? const [];
    return ListView(children: [
      SettingsSectionHeader(
        title: 'Sources & Devices',
        subtitle:
            controller.infrastructure.ready
                ? 'Autorisierter v2-Kontext inklusive Devices ohne Collector. Keine Browser-Mutation.'
                : 'Nur bereits vorhandene autorisierte v1-Snapshot-Daten. Keine konkurrierende Geräteverwaltung.',
        status: 'EXISTING READ CONTRACT',
      ),
      const SizedBox(height: 12),
      const WorkstationNote(
        'Device onboarding requires local operator administration',
        'Kein Browser-Onboarding, keine Demo-Datenlöschung und kein Source-Reconfigure. OIP-008.5 wird nicht verändert oder vorweggenommen.',
        icon: Icons.admin_panel_settings_outlined,
        color: OipTokens.yellow,
      ),
      const SizedBox(height: 12),
      if (snapshot == null)
        const WorkstationNote('Snapshot nicht verfügbar',
            'Sources, Devices und Demo/Real-Modus sind Unknown; keine Nullwerte werden ersetzt.')
      else ...[
        KeyValueGrid(children: [
          KeyValue(
              'Demo / Real Mode',
              snapshot.system.simulated
                  ? 'simulated / demo data reported'
                  : 'non-simulated inventory reported'),
          KeyValue('Sources', '${sources.length} geliefert'),
          KeyValue('Devices', '${snapshot.devices.length} geliefert'),
          KeyValue('Devices ohne Source / NoCollector',
              '${snapshot.devices.where((device) => device.sourceId == null).length}'),
          const KeyValue('Monitoring Configuration',
              'existing read capabilities only; browser mutation unsupported'),
        ]),
        const Hairline(),
        const PanelLabel('Gelieferte Source-IDs'),
        for (final source in sources)
          ListTile(
            dense: true,
            leading: const Icon(Icons.sensors_outlined, size: 18),
            title: Text(source.id,
                style: WorkstationTokens.mono(context, size: 11)),
            subtitle: Text(
                '${source.name} · ${source.simulated ? 'simulated' : 'not marked simulated'}'),
            trailing: Text(
                '${snapshot.devices.where((device) => device.sourceId == source.id).length} Devices'),
          ),
        if (sources.isEmpty)
          const WorkstationNote('Keine Source-DTOs geliefert',
              'Das ist ein gelieferter leerer Snapshot, kein abgeleiteter Real-Mode- oder Registry-Zustand.'),
      ],
    ]);
  }

  Widget _storage(BuildContext context) => ListView(children: [
        const SettingsSectionHeader(
          title: 'SQLite & Data Storage',
          subtitle:
              'Technische Storage-Fakten aus dem Management-Read. Datenbankpfade werden nicht exportiert.',
          status: 'READ ONLY',
        ),
        const SizedBox(height: 12),
        SettingsFacts(report!.facts),
        const Hairline(),
        const KeyValue('Persisted Settings',
            'instance_name, instance_description, history_page_size; startup snapshot'),
        const KeyValue('Migration Status',
            'Schema wird vom Core geliefert; keine Migration durch Flutter'),
        const KeyValue('Retention Cleanup', 'unsupported; no data deletion'),
        SettingsLimitations(report!.limitations),
      ]);

  Widget _historical(BuildContext context) => ListView(children: [
        const SettingsSectionHeader(
          title: 'Historical Data',
          subtitle:
              'Vorhandene deterministische History-/Evidence-Verträge; keine Retention- oder Root-Cause-Funktion.',
          status: 'READ ONLY',
        ),
        const SizedBox(height: 12),
        if (secondary != null) SettingsFacts(secondary!.facts),
        const Hairline(),
        if (settings != null)
          for (final setting in settings!.settings)
            KeyValue(setting.key,
                '${setting.effective.display} · ${setting.applyStatus}'),
        const KeyValue('Explicit Query Limit',
            'Wins over configured default; existing Core request bounds remain authoritative'),
        const KeyValue('Health History',
            'Nur tatsächlich beobachtete Transitionen gemäß Core-Report'),
      ]);

  Widget _retention(BuildContext context) => ListView(children: [
        const SettingsSectionHeader(
          title: 'Retention',
          subtitle: 'Der Core stellt keinen Retention-Cleanup bereit.',
          status: 'UNSUPPORTED',
          statusColor: OipTokens.yellow,
        ),
        const SizedBox(height: 12),
        SettingsFacts(report!.facts),
        const WorkstationNote(
          'Keine Datenlöschung',
          'Es gibt keinen aktiven Button Historie löschen und keinen Management-Export. Offline-Backups und mögliche zukünftige Retention-Funktionen bleiben Operator-/Core-Aufgaben.',
          icon: Icons.delete_outline,
          color: OipTokens.yellow,
        ),
      ]);

  Widget _diagnosticRules(BuildContext context) => ListView(children: [
        SettingsSectionHeader(
          title: section == SettingsSection.evidence
              ? 'Evidence Capabilities'
              : 'Deterministic Diagnostic Rules',
          subtitle:
              'Unveränderliche Core-Regelmetadaten. Keine visuelle Rule Engine und keine KI-Kausalität.',
          status: 'IMMUTABLE CORE RULES',
        ),
        const SizedBox(height: 12),
        SettingsFacts(report!.facts),
        const Hairline(),
        const WorkstationNote(
          'Data Gap Semantics',
          'Nur dokumentierte Gap-Marker. Ein Intervall mit Länge null beweist keine Kontinuität; Unknown bleibt von gesund, gestört und unsupported getrennt.',
          icon: Icons.rule_outlined,
        ),
        SettingsLimitations(report!.limitations),
      ]);

  Widget _historyLimits(BuildContext context) => ListView(children: [
        const SettingsSectionHeader(
          title: 'History Limits',
          subtitle:
              'Konfigurierter Default und tatsächliche Query-Semantik ohne Browser-Mutation.',
          status: 'OFFLINE ADMINISTRATION REQUIRED',
          statusColor: OipTokens.yellow,
        ),
        const SizedBox(height: 12),
        if (settings != null)
          for (final setting in settings!.settings)
            _settingRow(
                context,
                settings!.definitions.firstWhere(
                    (item) => item.key == setting.key,
                    orElse: () => settings!.definitions.first),
                setting),
        if (secondary != null) ...[
          const Hairline(),
          SettingsFacts(secondary!.facts),
        ],
        const SizedBox(height: 10),
        const KeyValue('history_page_size validation', '4..100 inclusive'),
        const KeyValue('Explicit request limit',
            'existing request range 1..100; Evidence requires at least 4'),
        const KeyValue('Scope resolution',
            'Source > Site > Infrastructure > Organization > Platform > built-in default'),
      ]);

  Widget _security(BuildContext context) => ListView(children: [
        const SettingsSectionHeader(
          title: 'Security & Access',
          subtitle:
              'Aktuelle lokale Identität und dokumentierte Produktionsgrenzen. Keine Sicherheitszertifizierung.',
          status: 'PRODUCTION BLOCKERS OPEN',
          statusColor: OipTokens.yellow,
        ),
        const SizedBox(height: 12),
        SettingsFacts(report!.facts),
        const Hairline(),
        const KeyValue('Credential Management', 'unsupported in browser'),
        const KeyValue('Role Inventory / Editor', 'unsupported'),
        const KeyValue('Self Grants',
            'not possible; central provisioning remains authoritative'),
        const WorkstationNote(
          'Nicht „Secure for Production“',
          'RUSTSEC-2023-0071, RUSTSEC-2023-0089, RUSTSEC-2024-0449 sowie Remote-/Browser-Identity, feindliche Same-UID-Isolation, manipulationssicheres Audit und OT-Safety-Nachweise bleiben offen.',
          icon: Icons.gpp_maybe_outlined,
          color: OipTokens.yellow,
        ),
        SettingsLimitations(report!.limitations),
      ]);

  Widget _system(BuildContext context) => ListView(children: [
        const SettingsSectionHeader(
          title: 'System Information',
          subtitle:
              'Build-, Runtime- und Capability-Fakten ohne erfundene Host-Metriken.',
          status: 'CORE REPORTED',
        ),
        const SizedBox(height: 12),
        SettingsFacts(report!.facts),
        if (secondary != null) ...[
          const Hairline(),
          KeyValueGrid(children: [
            KeyValue('MCP Transport', secondary!.fact('transport')),
            KeyValue('MCP Runtime', secondary!.fact('runtime_mode')),
            KeyValue('Protocol', secondary!.fact('protocol')),
            KeyValue('SDK', secondary!.fact('sdk')),
          ]),
        ],
        const Hairline(),
        const KeyValue('CPU / RAM / GPU',
            'Unknown — no host collector data in this contract'),
        SettingsLimitations(report!.limitations),
      ]);

  Widget _capabilities(BuildContext context) {
    final tools = extra;
    return ListView(children: [
      const SettingsSectionHeader(
        title: 'Core Capabilities',
        subtitle:
            'Registrierte Capability-Anzahl und tatsächliches MCP-Mapping; keine Ausführung über Settings.',
        status: 'REGISTRY READ ONLY',
      ),
      const SizedBox(height: 12),
      SettingsMetricStrip([
        (
          'CORE CAPABILITIES',
          report!.fact('registered_core_capabilities'),
          Icons.hub_outlined
        ),
        (
          'MCP TOOLS',
          tools?.tools.length.toString() ?? 'Unknown',
          Icons.smart_toy_outlined
        ),
        (
          'SQLITE SCHEMA',
          report!.fact('sqlite_schema'),
          Icons.storage_outlined
        ),
        (
          'RUNTIME SOURCES',
          report!.fact('runtime_sources'),
          Icons.sensors_outlined
        ),
      ]),
      const SizedBox(height: 12),
      if (tools != null)
        for (final tool in tools.tools)
          ListTile(
            dense: true,
            title: Text(tool.capability,
                style: WorkstationTokens.mono(context, size: 11)),
            subtitle: Text(tool.name),
            trailing: Text(tool.classification.contains('read_only')
                ? 'READ ONLY'
                : 'UNKNOWN'),
          ),
      const WorkstationNote(
        'Supported / Unsupported',
        '25 Reads, legacy SimulationScenarioSet und offline-only SettingsChange sind Core-Vertragsbestand. Mutierende MCP-Tools, Remote MCP, Browser-Administration und aktive Session-Inventarisierung werden nicht angeboten.',
        icon: Icons.fact_check_outlined,
      ),
    ]);
  }
}
