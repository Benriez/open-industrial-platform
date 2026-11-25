import '../../l10n/oip_strings.dart';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../design_system/theme.dart';
import '../../l10n/language_picker.dart';
import '../../models/app_metadata.dart';
import '../../services/api.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'settings_models.dart';
import 'settings_navigation.dart';
import 'ota_update_control.dart';
import 'settings_session.dart';
import 'settings_tool_explorer.dart';
import 'paired_device_sign_ins.dart';

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
        SettingsSection.runtime => _system(context),
        SettingsSection.versions => ListView(children: [_about(context)]),
        SettingsSection.capabilities => _capabilities(context),
      };

  Widget _application(BuildContext context) {
    final snapshot = settings!;
    // A settings form is small and fully materialized; this keeps every row in
    // the widget tree so keyboard/screen-reader navigation reaches all of them.
    return SingleChildScrollView(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsSectionHeader(
        title: context.tr("Application Settings"),
        subtitle: context.tr(
            "Drei validierte Core-Schlüssel. Effektiver Wert, Default, Persistenz und Apply-Status bleiben getrennt."),
        status: context.tr("OFFLINE ADMINISTRATION REQUIRED"),
        statusColor: OipTokens.yellow,
      ),
      const SizedBox(height: 12),
      WorkstationNote(
        context.tr("Kein Browser-Save"),
        context.tr(
            "Der Core besitzt keinen HTTP-/MCP-Schreibpfad. Änderungen erfordern den exklusiven lokalen Operator-CLI-Prozess und werden erst beim nächsten validierten Core-Start aktiv."),
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
      KeyValue(context.tr("Inheritance"), snapshot.inheritance, mono: false),
      KeyValue(
          context.tr("Startup snapshot loaded at"),
          snapshot.loadedAtMs?.toString() ??
              context.tr("Redacted / not delivered")),
      WorkstationNote(
        context.tr("Requires Restart"),
        context.tr(
            "active_startup_snapshot beschreibt den laufenden Snapshot. persisted_requires_restart wäre ein Offline-Ergebnis, kein aktiver Runtime-Wert. Ein exakter Scope-Datensatz und ein geerbter effektiver Wert sind nicht dasselbe."),
        icon: Icons.restart_alt_outlined,
      ),
      const Hairline(),
      _about(context),
    ]));
  }

  /// The client identity: name, version/build, the software license and a
  /// local-first data note.
  ///
  /// A store-ready surface names the application the way it ships. The version
  /// and build mirror `pubspec.yaml`, the license names the SPDX identifier the
  /// client is released under (`LICENSE`); nothing here is a Core fact and
  /// nothing here is invented.
  Widget _about(BuildContext context) {
    const info = kOipApplication;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SettingsSectionHeader(
        title: context.tr("About"),
        subtitle: context.tr(
            "App-Identität, Build-Nummer, Lizenz und Datenschutzerklärung. Keine Core-Konfiguration."),
        status: context.tr("CLIENT IDENTITY"),
        statusColor: OipTokens.cyan,
      ),
      const SizedBox(height: 12),
      Semantics(
        label: context.tr("{0}, Version {1}, Build {2}",
            [info.name, info.version, info.build]),
        child: Text(
          info.name,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(height: 10),
      KeyValue(
        context.tr("Version"),
        info.version,
        mono: false,
        key: const Key('settings-about-version'),
      ),
      KeyValue(
        context.tr("Build"),
        info.build,
        mono: false,
        key: const Key('settings-about-build'),
      ),
      KeyValue(
        context.tr("Shell"),
        info.shellIdentity,
        mono: false,
        key: const Key('settings-about-shell'),
      ),
      KeyValue(
        context.tr("Lizenz"),
        info.license,
        mono: false,
        key: const Key('settings-about-license'),
      ),
      const OipOtaUpdateControl(),
      const SizedBox(height: 10),
      WorkstationNote(
        context.tr("Lokal · keine Telemetrie"),
        info.privacyNote,
        icon: Icons.shield_outlined,
        color: OipTokens.cyan,
      ),
    ]);
  }

  Widget _settingRow(BuildContext context, SettingDefinition definition,
      EffectiveSetting? effective) {
    final selected = session.selectedSetting == definition.key;
    final tone = OipTokens.readableAccent(context, OipTokens.cyan);
    return Semantics(
      button: true,
      selected: selected,
      label: context.tr(
          "Setting {0}. Effektiver Wert {1}. Offline Administration Required.",
          [definition.key, effective?.effective.display ?? 'Unknown']),
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
                StatusPill(context.tr("READ ONLY"), icon: Icons.lock_outline),
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
      SettingsSectionHeader(
        title: context.tr("Appearance & Preferences"),
        subtitle: context.tr("Sprache und Darstellung dieser App wählen."),
        status: context.tr("CLIENT LOCAL"),
        statusColor: OipTokens.cyan,
      ),
      const SizedBox(height: 12),
      const OipLanguagePicker(),
      const SizedBox(height: 12),
      WorkstationNote(
        context.tr("Nur diese UI-Sitzung"),
        context.tr(
            "Die Theme-Auswahl gilt bis zum Ende der laufenden App-Sitzung."),
        icon: Icons.palette_outlined,
      ),
      const SizedBox(height: 12),
      for (final theme in themes)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Semantics(
            button: true,
            selected: themeVariant == theme.$1,
            label: context.tr("Theme {0}. Lokale UI-Präferenz.", [theme.$2]),
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
                subtitle: Text(context.tr(theme.$3)),
              ),
            ),
          ),
        ),
      const Hairline(),
      KeyValue(context.tr("Server preference synchronization"),
          context.tr("unsupported")),
    ]);
  }

  Widget _server(BuildContext context) {
    final value = report!;
    final system = secondary;
    final tools = extra;
    return ListView(children: [
      SettingsSectionHeader(
        title: context.tr("MCP Server"),
        subtitle: context.tr(
            "Reale Core-Komposition, lokale stdio-Bridges und Unix-IPC. Kein Remote-MCP-Listener."),
        status: context.tr("LOCAL STDIO / IPC"),
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
      WorkstationNote(
        context.tr("Read-only / Mutation Policy"),
        context.tr(
            "Der Katalog enthält keine mutierenden MCP-Tools. Enable/Disable, Remote MCP und per-tool Freigaben bleiben unsupported; geschützte Startup-Konfiguration ist maßgeblich."),
        icon: Icons.policy_outlined,
      ),
      const SizedBox(height: 10),
      SettingsLimitations(value.limitations),
    ]);
  }

  Widget _clientConfiguration(BuildContext context) {
    final config = report!.clientConfiguration!;
    return ListView(children: [
      SettingsSectionHeader(
        title: context.tr("MCP Client Configuration"),
        subtitle: context.tr(
            "Generisches mcpServers-Template aus dem Core-Vertrag. Keine Client-spezifische Konvertierung."),
        status: context.tr("UNRESOLVED TEMPLATE"),
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
          label: Text(context.tr("Copy Configuration")),
        ),
        OutlinedButton.icon(
          key: const Key('settings-copy-cli'),
          onPressed: () => onCopy('MCP-CLI-Template', config.cliTemplate),
          icon: const Icon(Icons.terminal, size: 17),
          label: Text(context.tr("Copy CLI Template")),
        ),
      ]),
      const SizedBox(height: 12),
      WorkstationNote(
        context.tr("Vor Verwendung ersetzen"),
        context.tr(
            "Executable, privater Socket und Credential-Datei müssen aus einem bereits autorisierten lokalen Profil stammen. Platzhalter sind keine installierte Verbindung. Kopieren führt keinen Befehl aus und erzeugt keine Grants."),
        icon: Icons.warning_amber_outlined,
        color: OipTokens.yellow,
      ),
      const SizedBox(height: 12),
      PanelLabel(context.tr("Setup im MCP-Client")),
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
      SettingsSectionHeader(
        title: context.tr("MCP Permissions & Scopes"),
        subtitle: context.tr(
            "Zentrale, read-only Permission-Matrix. Keine Selbstfreigabe und keine Rollenableitung."),
        status: context.tr("POLICY READ ONLY"),
      ),
      const SizedBox(height: 10),
      if (security != null)
        KeyValueGrid(children: [
          KeyValue(context.tr("Current Principal"), security.fact('principal')),
          KeyValue(context.tr("Role"),
              context.tr("Nicht im Management-Vertrag geliefert")),
          KeyValue(context.tr("Organization / Infrastructure / Site / Source"),
              context.tr("Kein Principal-Scope-Inventar geliefert")),
          KeyValue(
              context.tr("Credential Management"), context.tr("unsupported")),
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
        title: context.tr("MCP Connection Diagnostics"),
        subtitle: context.tr(
            "Beobachtet ausschließlich die eigene autorisierte Core-Runtime. Kein Credential-, Datei-, Remote- oder Handshake-Test."),
        status: context.tr("STATUS READ ONLY"),
        actions: [
          ToolButton(
            icon: Icons.copy_outlined,
            tooltip: context.tr("Technische Diagnoseinformationen kopieren"),
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
            context.tr("Tool Catalog Availability"),
            tools == null
                ? context.tr("Unknown")
                : context.tr(
                    "{0} registrierte Tools geliefert", [tools.tools.length])),
        KeyValue(
            context.tr("Config Contract"),
            config == null
                ? context.tr("Unknown")
                : context
                    .tr("Valides generisches JSON; Platzhalter erforderlich")),
        KeyValue(
            context.tr("Connection Test"), context.tr("Nicht durchgeführt")),
        KeyValue(context.tr("Credential / File Probe"),
            context.tr("Nicht durchgeführt")),
      ]),
      const SizedBox(height: 10),
      WorkstationNote(
        context.tr("Kein Verbindungsnachweis"),
        context.tr(
            "Ein erfolgreicher Status-Read ist kein erfolgreicher MCP-Client-Handshake. Refresh wiederholt nur autorisierte GET-Reads."),
        icon: Icons.network_check_outlined,
      ),
      const SizedBox(height: 10),
      SettingsLimitations(report!.limitations),
    ]);
  }

  Widget _sessions(BuildContext context) => ListView(children: [
        SettingsSectionHeader(
          title: context.tr("MCP Client Sessions"),
          subtitle: context.tr(
              "Der Core besitzt keine verlässlich abfragbare initialized-client Registry."),
          status: context.tr("UNSUPPORTED"),
          statusColor: OipTokens.yellow,
        ),
        const SizedBox(height: 16),
        const Icon(Icons.cloud_off_outlined, size: 30, color: OipTokens.yellow),
        const SizedBox(height: 10),
        Text(
            context.tr(
                "Aktive MCP-Client-Sessions können derzeit nicht zentral aufgelistet werden."),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SettingsFacts(report!.facts),
        WorkstationNote(
          context.tr("Keine Ersatzwerte"),
          context.tr(
              "Keine Client-Namen, Session-IDs, Connected-Zustände, Last-Activity-Werte oder Connection Counts. Ein konfiguriertes Clientprofil ist keine aktive Session."),
          icon: Icons.do_not_disturb_on_outlined,
        ),
        const SizedBox(height: 10),
        KeyValue(
            context.tr("Future backend requirement"),
            context.tr(
                "Typed, authorized initialized-session registry with lifecycle timestamps and explicit scope/redaction semantics")),
        SettingsLimitations(report!.limitations),
      ]);

  Widget _hierarchy(BuildContext context) => ListView(children: [
        SettingsSectionHeader(
          title: context.tr(settingsSectionLabel(section)),
          subtitle: context.tr(
              "Bestehende autorisierte Hierarchie-Reads bleiben maßgeblich; Browser-Admin-Mutationen sind nicht verfügbar."),
          status: context.tr("READ-ONLY / LIMITED BROWSER IDENTITY"),
        ),
        const SizedBox(height: 12),
        if (!controller.infrastructure.ready)
          WorkstationNote(
            context.tr(
                "Kein autorisiertes Hierarchie-Inventar in dieser Browser-Ansicht"),
            context.tr(
                "Der aktuelle Lauf liefert keine autorisierten Organizations, Infrastructures oder Sites. Es werden weder Namen geraten noch Nullbestände behauptet."),
            icon: Icons.account_tree_outlined,
          )
        else ...[
          WorkstationNote(
            controller.infrastructure.selectedBreadcrumb,
            context.tr(
                "Dieselbe globale Auswahl gilt in allen Workstations. Sie ist keine administrative Berechtigung."),
            icon: Icons.account_tree_outlined,
            color: OipTokens.cyan,
          ),
          if (section == SettingsSection.organizations)
            for (final item in controller.infrastructure.hierarchy.organizations
                .where((item) =>
                    controller.infrastructure.selection.organizationId ==
                        null ||
                    item.id ==
                        controller.infrastructure.selection.organizationId))
              ListTile(
                dense: true,
                leading: const Icon(Icons.business_outlined),
                title: Text(item.name),
                subtitle: Text(item.id),
              ),
          if (section == SettingsSection.infrastructures)
            for (final item in controller
                .infrastructure.hierarchy.infrastructures
                .where((item) => controller.infrastructure.selection.matches(
                    organizationId: item.organizationId,
                    infrastructureId: item.id)))
              ListTile(
                dense: true,
                leading: const Icon(Icons.hub_outlined),
                title: Text(item.name),
                subtitle: Text(context.tr(
                    "{0} · Organization {1}", [item.id, item.organizationId])),
              ),
          if (section == SettingsSection.sites)
            for (final item in controller.infrastructure.hierarchy.sites.where(
                (item) => controller.infrastructure.selection.matches(
                    infrastructureId: item.infrastructureId, siteId: item.id)))
              ListTile(
                dense: true,
                leading: const Icon(Icons.location_on_outlined),
                title: Text(item.name),
                subtitle: Text(context.tr("{0} · Infrastructure {1}",
                    [item.id, item.infrastructureId])),
              ),
          if (controller.infrastructure.isFixture)
            StatusPill(context.tr("CONTRACT FIXTURE · NICHT LIVE"),
                color: OipTokens.yellow, icon: Icons.science_outlined),
        ],
        const SizedBox(height: 12),
        KeyValue(context.tr("Browser administration"),
            context.tr("offline operator administration required")),
        KeyValue(context.tr("OIP-008.5 integration"),
            context.tr("not consumed; no unfinished API assumed")),
        KeyValue(
            context.tr("Required future contract"),
            context.tr(
                "Scoped typed list/detail DTOs, stable IDs, parent references, explicit availability and permission states")),
        KeyValue(context.tr("Creation / mutation"),
            context.tr("unsupported in this UI; no unprotected REST writes")),
      ]);

  Widget _sourcesDevices(BuildContext context) {
    final snapshot = controller.snapshot;
    final sources = controller.operationalSources.isNotEmpty
        ? controller.operationalSources
        : snapshot?.sources ?? const [];
    return ListView(children: [
      SettingsSectionHeader(
        title: context.tr("Sources & Devices"),
        subtitle: controller.infrastructure.ready
            ? context.tr(
                "Autorisierter v2-Kontext inklusive Devices ohne Collector. Keine Inventar- oder Geräteverwaltung in diesem Bereich.")
            : context.tr(
                "Nur bereits vorhandene autorisierte v1-Snapshot-Daten. Keine konkurrierende Geräteverwaltung."),
        status: context.tr("EXISTING READ CONTRACT"),
      ),
      const SizedBox(height: 12),
      WorkstationNote(
        context.tr("Device onboarding requires local operator administration"),
        context.tr(
            "Kein Browser-Onboarding, keine Demo-Datenlöschung und kein Source-Reconfigure. OIP-008.5 wird nicht verändert oder vorweggenommen."),
        icon: Icons.admin_panel_settings_outlined,
        color: OipTokens.yellow,
      ),
      const SizedBox(height: 12),
      if (snapshot == null)
        WorkstationNote(
            context.tr("Snapshot nicht verfügbar"),
            context.tr(
                "Sources, Devices und Demo/Real-Modus sind Unknown; keine Nullwerte werden ersetzt."))
      else ...[
        KeyValueGrid(children: [
          KeyValue(
              context.tr("Demo / Real Mode"),
              snapshot.system.simulated
                  ? context.tr("simulated / demo data reported")
                  : context.tr("non-simulated inventory reported")),
          KeyValue(context.tr("Sources"),
              context.tr("{0} geliefert", [sources.length])),
          KeyValue(context.tr("Devices"),
              context.tr("{0} geliefert", [snapshot.devices.length])),
          KeyValue(context.tr("Devices ohne Source / NoCollector"),
              '${snapshot.devices.where((device) => device.sourceId == null).length}'),
          KeyValue(
              context.tr("Monitoring Configuration"),
              context.tr(
                  "OPC-UA writes are limited to server-enabled nodes in the OPC-UA workstation")),
        ]),
        const Hairline(),
        PanelLabel(context.tr("Gelieferte Source-IDs")),
        for (final source in sources)
          ListTile(
            dense: true,
            leading: const Icon(Icons.sensors_outlined, size: 18),
            title: Text(source.id,
                style: WorkstationTokens.mono(context, size: 11)),
            subtitle: Text(
                '${source.name} · ${source.simulated ? 'simulated' : 'not marked simulated'}'),
            trailing: Text(context.tr("{0} Devices", [
              snapshot.devices
                  .where((device) => device.sourceId == source.id)
                  .length
            ])),
          ),
        if (sources.isEmpty)
          WorkstationNote(
              context.tr("Keine Source-DTOs geliefert"),
              context.tr(
                  "Das ist ein gelieferter leerer Snapshot, kein abgeleiteter Real-Mode- oder Registry-Zustand.")),
      ],
    ]);
  }

  Widget _storage(BuildContext context) => ListView(children: [
        SettingsSectionHeader(
          title: context.tr("SQLite & Data Storage"),
          subtitle: context.tr(
              "Technische Storage-Fakten aus dem Management-Read. Datenbankpfade werden nicht exportiert."),
          status: context.tr("READ ONLY"),
        ),
        const SizedBox(height: 12),
        SettingsFacts(report!.facts),
        const Hairline(),
        KeyValue(
            context.tr("Persisted Settings"),
            context.tr(
                "instance_name, instance_description, history_page_size; startup snapshot")),
        KeyValue(
            context.tr("Migration Status"),
            context.tr(
                "Schema wird vom Core geliefert; keine Migration durch Flutter")),
        KeyValue(context.tr("Retention Cleanup"),
            context.tr("unsupported; no data deletion")),
        SettingsLimitations(report!.limitations),
      ]);

  Widget _historical(BuildContext context) => ListView(children: [
        SettingsSectionHeader(
          title: context.tr("Historical Data"),
          subtitle: context.tr(
              "Vorhandene deterministische History-/Evidence-Verträge; keine Retention- oder Root-Cause-Funktion."),
          status: context.tr("READ ONLY"),
        ),
        const SizedBox(height: 12),
        if (secondary != null) SettingsFacts(secondary!.facts),
        const Hairline(),
        if (settings != null)
          for (final setting in settings!.settings)
            KeyValue(setting.key,
                '${setting.effective.display} · ${setting.applyStatus}'),
        KeyValue(
            context.tr("Explicit Query Limit"),
            context.tr(
                "Wins over configured default; existing Core request bounds remain authoritative")),
        KeyValue(
            context.tr("Health History"),
            context.tr(
                "Nur tatsächlich beobachtete Transitionen gemäß Core-Report")),
      ]);

  Widget _retention(BuildContext context) => ListView(children: [
        SettingsSectionHeader(
          title: context.tr("Retention"),
          subtitle:
              context.tr("Der Core stellt keinen Retention-Cleanup bereit."),
          status: context.tr("UNSUPPORTED"),
          statusColor: OipTokens.yellow,
        ),
        const SizedBox(height: 12),
        SettingsFacts(report!.facts),
        WorkstationNote(
          context.tr("Keine Datenlöschung"),
          context.tr(
              "Es gibt keinen aktiven Button Historie löschen und keinen Management-Export. Offline-Backups und mögliche zukünftige Retention-Funktionen bleiben Operator-/Core-Aufgaben."),
          icon: Icons.delete_outline,
          color: OipTokens.yellow,
        ),
      ]);

  Widget _diagnosticRules(BuildContext context) => ListView(children: [
        SettingsSectionHeader(
          title: section == SettingsSection.evidence
              ? context.tr("Evidence Capabilities")
              : context.tr("Deterministic Diagnostic Rules"),
          subtitle: context.tr(
              "Unveränderliche Core-Regelmetadaten. Keine visuelle Rule Engine und keine KI-Kausalität."),
          status: context.tr("IMMUTABLE CORE RULES"),
        ),
        const SizedBox(height: 12),
        SettingsFacts(report!.facts),
        const Hairline(),
        WorkstationNote(
          context.tr("Data Gap Semantics"),
          context.tr(
              "Nur dokumentierte Gap-Marker. Ein Intervall mit Länge null beweist keine Kontinuität; Unknown bleibt von gesund, gestört und unsupported getrennt."),
          icon: Icons.rule_outlined,
        ),
        SettingsLimitations(report!.limitations),
      ]);

  Widget _historyLimits(BuildContext context) => ListView(children: [
        SettingsSectionHeader(
          title: context.tr("History Limits"),
          subtitle: context.tr(
              "Konfigurierter Default und tatsächliche Query-Semantik ohne Browser-Mutation."),
          status: context.tr("OFFLINE ADMINISTRATION REQUIRED"),
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
        KeyValue(context.tr("history_page_size validation"),
            context.tr("4..100 inclusive")),
        KeyValue(
            context.tr("Explicit request limit"),
            context.tr(
                "existing request range 1..100; Evidence requires at least 4")),
        KeyValue(
            context.tr("Scope resolution"),
            context.tr(
                "Source > Site > Infrastructure > Organization > Platform > built-in default")),
      ]);

  Widget _security(BuildContext context) {
    final securityReport = report;
    final api = controller.api;
    return ListView(children: [
      if (section == SettingsSection.currentIdentity &&
          controller.managed &&
          api is PairedDeviceManagementApi) ...[
        PairedDeviceSignIns(
          key: ValueKey(controller.contextRevision),
          api: api as PairedDeviceManagementApi,
          onCurrentRevoked: controller.deviceSignInRevoked,
        ),
        if (securityReport != null) const Hairline(),
      ],
      if (securityReport != null) ...[
        SettingsSectionHeader(
          title: context.tr("Security & Access"),
          subtitle: context.tr(
              "Aktuelle lokale Identität und dokumentierte Produktionsgrenzen. Keine Sicherheitszertifizierung."),
          status: context.tr("PRODUCTION BLOCKERS OPEN"),
          statusColor: OipTokens.yellow,
        ),
        const SizedBox(height: 12),
        SettingsFacts(securityReport.facts),
        const Hairline(),
        KeyValue(
            context.tr("Role Inventory / Editor"), context.tr("unsupported")),
        KeyValue(
            context.tr("Self Grants"),
            context.tr(
                "not possible; central provisioning remains authoritative")),
        WorkstationNote(
          context.tr("Nicht „Secure for Production“"),
          context.tr(
              "Offen sind RUSTSEC-2024-0449, die Absicherung externer Browser-Anmeldungen und des lokalen Systemkontos, ein extern abgesichertes Audit und der Nachweis der Betriebssicherheit."),
          icon: Icons.gpp_maybe_outlined,
          color: OipTokens.yellow,
        ),
        SettingsLimitations(securityReport.limitations),
      ],
    ]);
  }

  Widget _system(BuildContext context) => ListView(children: [
        SettingsSectionHeader(
          title: context.tr("System Information"),
          subtitle: context.tr(
              "Build-, Runtime- und Capability-Fakten ohne erfundene Host-Metriken."),
          status: context.tr("CORE REPORTED"),
        ),
        const SizedBox(height: 12),
        SettingsFacts(report!.facts),
        if (secondary != null) ...[
          const Hairline(),
          KeyValueGrid(children: [
            KeyValue(context.tr("MCP Transport"), secondary!.fact('transport')),
            KeyValue(
                context.tr("MCP Runtime"), secondary!.fact('runtime_mode')),
            KeyValue(context.tr("Protocol"), secondary!.fact('protocol')),
            KeyValue(context.tr("SDK"), secondary!.fact('sdk')),
          ]),
        ],
        const Hairline(),
        KeyValue(context.tr("CPU / RAM / GPU"),
            context.tr("Unknown — no host collector data in this contract")),
        SettingsLimitations(report!.limitations),
      ]);

  Widget _capabilities(BuildContext context) {
    final tools = extra;
    return ListView(children: [
      SettingsSectionHeader(
        title: context.tr("Core Capabilities"),
        subtitle: context.tr(
            "Registrierte Capability-Anzahl und tatsächliches MCP-Mapping; keine Ausführung über Settings."),
        status: context.tr("REGISTRY READ ONLY"),
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
                ? context.tr("READ ONLY")
                : context.tr("UNKNOWN")),
          ),
      WorkstationNote(
        context.tr("Supported / Unsupported"),
        context.tr(
            "25 Reads, legacy SimulationScenarioSet und offline-only SettingsChange sind Core-Vertragsbestand. Mutierende MCP-Tools, Remote MCP, Browser-Administration und aktive Session-Inventarisierung werden nicht angeboten."),
        icon: Icons.fact_check_outlined,
      ),
    ]);
  }
}
