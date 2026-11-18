import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/controller.dart';
import '../../design_system/theme.dart';
import '../../services/api.dart';
import '../../widgets/adaptive_workspace.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'settings_content.dart';
import 'settings_models.dart';
import 'settings_navigation.dart';
import 'settings_session.dart';
import 'settings_tool_explorer.dart';

class SettingsPage extends StatefulWidget {
  final OipController controller;
  final SettingsWorkspaceSession session;
  final OipThemeVariant themeVariant;
  final ValueChanged<OipThemeVariant> onTheme;
  const SettingsPage({
    super.key,
    required this.controller,
    required this.session,
    required this.themeVariant,
    required this.onTheme,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController searchController;
  final FocusNode searchFocus = FocusNode(debugLabel: 'settings-tool-search');
  final FocusNode pageFocus = FocusNode(debugLabel: 'settings-workstation');
  SettingsSnapshot? settings;
  /// The categories of the Core with their administration status. They
  /// describe the instance and not a section, so they are kept when a section
  /// is loaded that does not read the settings.
  List<SettingsCategoryDefinition> coreCategories = const [];
  ManagementReport? report;
  ManagementReport? secondary;
  ManagementReport? extra;
  Object? loadError;
  bool loading = true;
  int generation = 0;
  String? scopeSignature;
  bool inspectorSelectionExplicit = false;

  bool get _backendFree =>
      widget.session.section == SettingsSection.preferences ||
      widget.session.section == SettingsSection.organizations ||
      widget.session.section == SettingsSection.infrastructures ||
      widget.session.section == SettingsSection.sites ||
      widget.session.section == SettingsSection.sourcesDevices ||
      widget.session.section == SettingsSection.versions;

  SettingsDataOrigin? get dataOrigin =>
      settings?.origin ?? report?.origin ?? secondary?.origin ?? extra?.origin;

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController(text: widget.session.toolSearch);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    generation++;
    widget.controller.api.cancelSettingsRequests();
    searchController.dispose();
    searchFocus.dispose();
    pageFocus.dispose();
    super.dispose();
  }

  void _reconcileScope() {
    final signature = widget.controller.contextScopeSignature;
    if (scopeSignature != null && scopeSignature != signature) {
      generation++;
      widget.controller.api.cancelSettingsRequests();
      widget.session.clearAuthorizedContext();
      settings = null;
      report = null;
      secondary = null;
      extra = null;
      loadError = null;
      loading = !_backendFree;
      inspectorSelectionExplicit = false;
      searchController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    scopeSignature = signature;
  }

  Future<void> _load() async {
    final request = ++generation;
    final section = widget.session.section;
    widget.controller.api.cancelSettingsRequests();
    setState(() {
      settings = null;
      report = null;
      secondary = null;
      extra = null;
      loadError = null;
      loading = !_backendFree;
    });
    if (_backendFree) return;
    SettingsSnapshot? loadedSettings;
    ManagementReport? loadedReport;
    ManagementReport? loadedSecondary;
    ManagementReport? loadedExtra;
    try {
      final api = widget.controller.api;
      // Optional supporting reads must never hide a successfully authorized
      // primary read. Missing context is shown as Unknown, never inferred.
      Future<ManagementReport?> optional(Future<ManagementReport> value) async {
        try {
          return await value;
        } catch (_) {
          return null;
        }
      }

      switch (section) {
        case SettingsSection.application:
          loadedSettings = await api.settings();
        case SettingsSection.historyLimits:
        case SettingsSection.historicalData:
          final target = widget.controller.infrastructure.ready
              ? widget.controller.infrastructure.selection.settingsTarget
              : ('platform', null);
          loadedSettings = await api.settings(
              key: 'history_page_size', scope: target.$1, scopeId: target.$2);
          loadedSecondary = await optional(api.management('diagnostic_rules'));
        case SettingsSection.mcpServer:
          loadedReport = await api.management('server');
          loadedSecondary = await optional(api.management('system'));
          loadedExtra = await optional(api.management('tools'));
        case SettingsSection.clientConfiguration:
          loadedReport = await api.management('client_configuration');
        case SettingsSection.tools:
          loadedReport = await api.management('tools');
          loadedSecondary = await optional(api.management('server'));
        case SettingsSection.permissions:
        case SettingsSection.effectivePermissions:
          loadedReport = await api.management('permissions');
          loadedSecondary = await optional(api.management('security'));
        case SettingsSection.connectionDiagnostics:
          loadedReport = await api.management('diagnostics');
          loadedSecondary = await optional(api.management('tools'));
          loadedExtra = await optional(api.management('client_configuration'));
        case SettingsSection.clientSessions:
          loadedReport = await api.management('sessions');
        case SettingsSection.sqlite:
        case SettingsSection.retention:
          loadedReport = await api.management('storage');
        case SettingsSection.diagnosticRules:
        case SettingsSection.evidence:
          loadedReport = await api.management('diagnostic_rules');
        case SettingsSection.currentIdentity:
        case SettingsSection.auditSecurity:
          loadedReport = await api.management('security');
        case SettingsSection.runtime:
          loadedReport = await api.management('system');
          loadedSecondary = await optional(api.management('server'));
        case SettingsSection.capabilities:
          loadedReport = await api.management('system');
          loadedSecondary = await optional(api.management('server'));
          loadedExtra = await optional(api.management('tools'));
        case SettingsSection.preferences:
        case SettingsSection.organizations:
        case SettingsSection.infrastructures:
        case SettingsSection.sites:
        case SettingsSection.sourcesDevices:
        case SettingsSection.versions:
          break;
      }
      if (!mounted ||
          request != generation ||
          section != widget.session.section) {
        return;
      }
      final tools = loadedReport?.tools ?? const <ManagedTool>[];
      if (tools.isNotEmpty) {
        final visible = filteredSettingsTools(
          loadedReport!,
          widget.session,
        );
        final selectedExists =
            visible.any((tool) => tool.name == widget.session.selectedTool);
        if (!selectedExists) {
          widget.session.selectedTool = visible.firstOrNull?.name;
        }
      }
      if (loadedSettings != null && loadedSettings.definitions.isNotEmpty) {
        final exists = loadedSettings.definitions
            .any((item) => item.key == widget.session.selectedSetting);
        if (!exists) {
          widget.session.selectedSetting = loadedSettings.definitions.first.key;
        }
      }
      setState(() {
        settings = loadedSettings;
        if (loadedSettings != null && loadedSettings.categories.isNotEmpty) {
          coreCategories = loadedSettings.categories;
        }
        report = loadedReport;
        secondary = loadedSecondary;
        extra = loadedExtra;
        loadError = null;
        loading = false;
      });
    } catch (error) {
      if (!mounted ||
          request != generation ||
          section != widget.session.section) {
        return;
      }
      setState(() {
        settings = null;
        report = null;
        secondary = null;
        extra = null;
        loadError = error;
        loading = false;
      });
    }
  }

  void _selectCategory(SettingsCategory category) {
    setState(() => widget.session.selectCategory(category));
    _load();
  }

  void _selectSection(SettingsSection section) {
    setState(() {
      widget.session.section = section;
      inspectorSelectionExplicit = false;
      widget.session.mobilePane = SettingsMobilePane.workspace;
    });
    _load();
  }

  void _selectTool(ManagedTool tool) {
    widget.controller.revealInspector(WorkspaceId.settings);
    setState(() {
      widget.session.selectedTool = tool.name;
      inspectorSelectionExplicit = true;
      if (MediaQuery.sizeOf(context).width < OipTokens.tablet) {
        widget.session.mobilePane = SettingsMobilePane.inspector;
      }
    });
  }

  void _selectSetting(String key) {
    widget.controller.revealInspector(WorkspaceId.settings);
    setState(() {
      widget.session.selectedSetting = key;
      inspectorSelectionExplicit = true;
      if (MediaQuery.sizeOf(context).width < OipTokens.tablet) {
        widget.session.mobilePane = SettingsMobilePane.inspector;
      }
    });
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label kopiert.')));
  }

  KeyEventResult _pageKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (searchFocus.hasFocus) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        searchController.clear();
        widget.session.toolSearch = '';
        searchFocus.unfocus();
        setState(() {});
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.slash &&
        widget.session.section == SettingsSection.tools) {
      searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    _reconcileScope();
    return Focus(
      focusNode: pageFocus,
      autofocus: true,
      onKeyEvent: _pageKey,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(),
          const SizedBox(height: 8),
          _contextBar(),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, box) {
            final navigation = SettingsNavigation(
              session: widget.session,
              onCategory: _selectCategory,
              onSection: _selectSection,
              categories: coreCategories,
            );
            final workspace = WorkstationPanel(
              key: const Key('settings-workspace'),
              padding: const EdgeInsets.all(12),
              child: _workspace(),
            );
            final hasSelection = inspectorSelectionExplicit &&
                (widget.session.selectedSetting != null ||
                    widget.session.selectedTool != null);
            final showInspector = widget.controller
                .inspectorVisible(WorkspaceId.settings, hasSelection);
            final inspector = AdaptiveInspector(
              controller: widget.controller,
              workspace: WorkspaceId.settings,
              label: 'Einstellung, Berechtigung & Provenienz',
              hasSelection: hasSelection,
              child: WorkstationPanel(
                key: const Key('settings-inspector'),
                padding: const EdgeInsets.all(12),
                child: _inspector(),
              ),
            );
            if (box.maxWidth >= 1120) {
              return SizedBox(
                height: 660,
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 224, child: navigation),
                      const SizedBox(width: 8),
                      Expanded(child: workspace),
                      if (showInspector) ...[
                        const SizedBox(width: 8),
                        SizedBox(width: 310, child: inspector),
                      ],
                    ]),
              );
            }
            if (box.maxWidth >= OipTokens.tablet) {
              return Column(children: [
                SizedBox(
                  height: 600,
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 214, child: navigation),
                        const SizedBox(width: 8),
                        Expanded(child: workspace),
                      ]),
                ),
                if (showInspector) ...[
                  const SizedBox(height: 8),
                  SizedBox(height: 500, child: inspector),
                ],
              ]);
            }
            return Column(children: [
              _mobileSelector(),
              const SizedBox(height: 8),
              SizedBox(
                height: 640,
                child: switch (widget.session.mobilePane) {
                  SettingsMobilePane.navigation => navigation,
                  SettingsMobilePane.workspace => workspace,
                  SettingsMobilePane.inspector => inspector,
                },
              ),
            ]);
          }),
        ]),
      ),
    );
  }

  Widget _header() {
    final fixture = dataOrigin == SettingsDataOrigin.contractFixture;
    final live = dataOrigin == SettingsDataOrigin.liveApi;
    return AdaptiveWorkspaceHeader(
      key: const Key('settings-page-header'),
      eyebrow: 'SETTINGS · APPLICATION MANAGEMENT',
      title: 'Einstellungen',
      subtitle:
          'Effektive Werte verstehen · Änderbarkeit und Berechtigung prüfen',
      accent: OipTokens.cyan,
      primaryAction: !_backendFree
          ? WorkspacePrimaryAction(
              buttonKey: const Key('settings-refresh'),
              label: 'Status aktualisieren',
              tooltip: 'Autorisierten Management-Read erneut prüfen',
              icon: Icons.refresh,
              onPressed: loading ? null : _load,
            )
          : null,
      actions: [
        InspectorOpenAction(
          controller: widget.controller,
          workspace: WorkspaceId.settings,
          hasSelection: inspectorSelectionExplicit &&
              (widget.session.selectedSetting != null ||
                  widget.session.selectedTool != null),
          onOpen: () => setState(() {
            if (MediaQuery.sizeOf(context).width < OipTokens.tablet) {
              widget.session.mobilePane = SettingsMobilePane.inspector;
            }
          }),
        ),
      ],
      status: [
        const StatusPill('AGENT-FIRST',
            color: OipTokens.lime, icon: Icons.smart_toy_outlined),
        const StatusPill('READ-ONLY / OFFLINE ADMIN', icon: Icons.lock_outline),
        if (fixture)
          const StatusPill('CONTRACT FIXTURE · NICHT LIVE',
              color: OipTokens.yellow, icon: Icons.science_outlined),
        if (live)
          const StatusPill('AUTHORIZED API READ',
              color: OipTokens.cyan, icon: Icons.verified_outlined),
        if (loadError != null)
          const StatusPill('AUTH / CONNECTION LIMITED',
              color: OipTokens.yellow, icon: Icons.warning_amber_outlined),
      ],
    );
  }

  Widget _contextBar() {
    final origin = switch (dataOrigin) {
      SettingsDataOrigin.contractFixture => 'OIP-008.4 TESTDATEN',
      SettingsDataOrigin.liveApi => 'AUTHORIZED LIVE API',
      null => _backendFree ? 'LOCAL / EXISTING SNAPSHOT' : 'NO AUTHORIZED DATA',
    };
    return AdvancedWorkspaceSection(
      title: 'Technischer Kontext & Vertragsdetails',
      summary: widget.controller.infrastructure.ready
          ? widget.controller.infrastructure.selectedBreadcrumb
          : 'Effektiver Scope, Provenienz und Offline-Change-Channel',
      expanded: widget.controller.workspaces
          .layout(WorkspaceId.settings)
          .advancedFilters,
      onChanged: (value) =>
          widget.controller.setAdvancedFilters(WorkspaceId.settings, value),
      children: [
        WorkstationPanel(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: LayoutBuilder(builder: (context, box) {
            final values = [
              (
                'SECTION',
                '${settingsCategoryLabel(widget.session.category)} / ${settingsSectionLabel(widget.session.section)}'
              ),
              (
                'EFFECTIVE SCOPE',
                widget.controller.infrastructure.ready
                    ? widget.controller.infrastructure.selectedBreadcrumb
                    : 'Platform management / explicit target'
              ),
              ('PROVENANCE', origin),
              (
                'BROWSER IDENTITY',
                widget.controller.infrastructure.principalIdentity ??
                    'vom Core nicht geliefert / Session-Vertrag offen'
              ),
              ('CHANGE CHANNEL', 'exclusive_local_operator_cli'),
            ];
            final columns = box.maxWidth < 520
                ? 2
                : box.maxWidth < 900
                    ? 3
                    : 5;
            final width = (box.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 7,
              children: values
                  .map((value) => SizedBox(
                        width: width,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(value.$1,
                                  style: WorkstationTokens.eyebrow(context)),
                              Text(value.$2,
                                  overflow: TextOverflow.ellipsis,
                                  style: WorkstationTokens.mono(context,
                                      size: 10)),
                            ]),
                      ))
                  .toList(),
            );
          }),
        )
      ],
    );
  }

  Widget _mobileSelector() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final entry in const [
            (SettingsMobilePane.navigation, 'Kategorien', Icons.list_outlined),
            (SettingsMobilePane.workspace, 'Workspace', Icons.tune_outlined),
            (SettingsMobilePane.inspector, 'Inspector', Icons.info_outline),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: Key('settings-mobile-${entry.$1.name}'),
                avatar: Icon(entry.$3, size: 15),
                label: Text(entry.$2),
                selected: widget.session.mobilePane == entry.$1,
                showCheckmark: false,
                onSelected: (_) =>
                    setState(() => widget.session.mobilePane = entry.$1),
              ),
            ),
        ]),
      );

  Widget _workspace() {
    if (loading) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Autorisierte Core-Daten werden gelesen …'),
          SizedBox(height: 4),
          Text('Keine Hintergrund-Polls; nur dieser bounded Read.'),
        ]),
      );
    }
    final error = loadError;
    if (error != null) return _error(error);
    return SettingsSectionContent(
      section: widget.session.section,
      session: widget.session,
      settings: settings,
      report: report,
      secondary: secondary,
      extra: extra,
      controller: widget.controller,
      themeVariant: widget.themeVariant,
      searchController: searchController,
      searchFocus: searchFocus,
      onFiltersChanged: () => setState(() {
        widget.session.toolSearch = searchController.text;
        final current = report;
        if (current != null) {
          final visible = filteredSettingsTools(current, widget.session);
          if (!visible
              .any((tool) => tool.name == widget.session.selectedTool)) {
            widget.session.selectedTool = visible.firstOrNull?.name;
          }
        }
      }),
      onSchemaChanged: () => setState(() {}),
      onSelectTool: _selectTool,
      onSelectSetting: _selectSetting,
      onTheme: widget.onTheme,
      onCopy: _copy,
    );
  }

  Widget _error(Object error) {
    final code = error is ApiFailure ? error.code : null;
    final missingSession = code == 'UNAUTHENTICATED';
    final unauthorized = code == 'PERMISSION_DENIED' || missingSession;
    final connection = code == 'CONNECTION_FAILED';
    final unsupported = code == 'UNSUPPORTED';
    // HTTP 400 / INVALID_REQUEST: the Core rejected the request against the
    // management contract (bad scope/key or an unsupported read). That is a
    // request-side rejection — distinct from an unauthorized session, an offline
    // transport, an unsupported function, a malformed response or unavailable
    // data — so it needs its own precise wording instead of collapsing into the
    // generic fallback, whose title and message previously disagreed.
    final invalidRequest = code == 'INVALID_REQUEST';
    final title = unauthorized
        ? (missingSession
            ? 'Anmeldung für Management erforderlich'
            : 'Management-Zugriff nicht autorisiert')
        : connection
            ? 'Core / Management-Endpunkt nicht erreichbar'
            : unsupported
                ? 'Management-Funktion nicht unterstützt'
                : invalidRequest
                    ? 'Management-Anfrage abgelehnt'
                    : code == 'CONTRACT_ERROR' || code == 'INVALID_RESPONSE'
                        ? 'Core-Vertrag nicht erfüllt'
                        : 'Management-Daten nicht verfügbar';
    final message = unauthorized
        ? (missingSession
            ? 'Melde dich an, um diese Management-Ansicht aufzurufen.'
            : 'Die aktuelle Sitzung hat keine Freigabe für diese Ansicht.')
        : connection
            ? 'Netzwerk- oder Transportfehler. Keine Management-Werte werden aus dem v1-Snapshot oder aus Fixtures ersetzt.'
            : unsupported
                ? 'Dieser API-Client oder Core unterstützt den Read nicht. Es wird keine Ersatzfunktion vorgetäuscht.'
                : invalidRequest
                    ? 'HTTP 400: Der Core hat diese Anfrage gegen den Management-Vertrag abgelehnt. Es wird kein Ersatzwert geraten und kein v1-Snapshot verwendet.'
                    : code == 'CONTRACT_ERROR' || code == 'INVALID_RESPONSE'
                        ? 'Die Antwort wird nicht als gültiger OIP-008.4-Vertrag akzeptiert. Es werden keine Teilwerte geraten.'
                        : 'Die autorisierte Management-Antwort fehlt oder ist unvollständig. Kein v1-Snapshot und keine Fixture ersetzen den gelesenen Wert.';
    return ListView(
      key: const Key('settings-error-state'),
      children: [
        Icon(
            unauthorized
                ? Icons.lock_outline
                : connection
                    ? Icons.cloud_off_outlined
                    : Icons.error_outline,
            size: 30,
            color: OipTokens.yellow),
        const SizedBox(height: 12),
        Text(title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 12),
        WorkstationNote(
          'Fachlicher Status',
          apiErrorMessage(error, 'Unbekannter Management-Fehler.'),
          icon: unauthorized
              ? Icons.admin_panel_settings_outlined
              : Icons.info_outline,
          color: OipTokens.yellow,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('settings-retry'),
          onPressed: _load,
          icon: const Icon(Icons.refresh, size: 17),
          label: const Text('Autorisierten Read erneut versuchen'),
        ),
        if (unauthorized) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('settings-open-local-versions'),
            onPressed: () {
              widget.session.selectCategory(SettingsCategory.system);
              _selectSection(SettingsSection.versions);
            },
            icon: const Icon(Icons.system_update_alt_outlined, size: 17),
            label: const Text('App-Version und Updates öffnen'),
          ),
        ],
        const SizedBox(height: 8),
        ExpansionTile(
          key: const Key('settings-error-details'),
          title: const Text('Technische Fehlerdetails'),
          subtitle: const Text('Sanitized · keine Credentials'),
          children: [
            KeyValue('Code', code ?? 'Unknown'),
            KeyValue('Endpoint',
                error is ApiFailure ? error.path ?? 'Unknown' : 'Unknown'),
            KeyValue(
                'HTTP Status',
                error is ApiFailure
                    ? error.statusCode?.toString() ?? 'not received'
                    : 'not received'),
            const KeyValue('Authorization fallback',
                'none; no token in URL, storage or web assets'),
          ],
        ),
      ],
    );
  }

  Widget _inspector() {
    if (widget.session.section == SettingsSection.tools && report != null) {
      final selected = report!.tools
          .where((tool) => tool.name == widget.session.selectedTool)
          .firstOrNull;
      return SettingsToolInspector(
        tool: selected,
        server: secondary,
        session: widget.session,
        onSchemaChanged: () => setState(() {}),
        onCopy: _copy,
      );
    }
    if ((widget.session.section == SettingsSection.permissions ||
            widget.session.section == SettingsSection.effectivePermissions) &&
        report != null &&
        widget.session.selectedTool != null) {
      final selected = report!.tools
          .where((tool) => tool.name == widget.session.selectedTool)
          .firstOrNull;
      return SettingsToolInspector(
        tool: selected,
        server: null,
        session: widget.session,
        onSchemaChanged: () => setState(() {}),
        onCopy: _copy,
      );
    }
    final selectedDefinition = settings?.definitions
        .where((item) => item.key == widget.session.selectedSetting)
        .firstOrNull;
    if (selectedDefinition != null) {
      final effective = settings!.settings
          .where((item) => item.key == selectedDefinition.key)
          .firstOrNull;
      return _settingInspector(selectedDefinition, effective);
    }
    return ListView(children: [
      const PanelLabel('Context / Help'),
      KeyValue(
          'Effective Scope',
          widget.controller.infrastructure.ready
              ? widget.controller.infrastructure.selectedBreadcrumb
              : _backendFree
                  ? 'Local UI / existing v1 snapshot'
                  : 'Platform management or explicit authorized target'),
      KeyValue(
          'Permissions',
          loadError == null
              ? 'Evaluated per authorized read; category metadata is not a grant'
              : 'Restricted / not available'),
      KeyValue(
          'Provenance',
          switch (dataOrigin) {
            SettingsDataOrigin.contractFixture =>
              'Sanitized OIP-008.4 contract fixture; not live status',
            SettingsDataOrigin.liveApi => 'Authorized Core DTO',
            null => 'No management response',
          }),
      const KeyValue('Apply Status',
          'Reads: active_startup_snapshot where delivered; writes: offline only, requires restart'),
      const Hairline(),
      if (report?.clientConfiguration != null) ...[
        KeyValue('Executable',
            report!.clientConfiguration!.executable ?? 'Placeholder required'),
        KeyValue('Arguments', report!.clientConfiguration!.args.join(' ')),
        const KeyValue('Credential Contents', 'Never read or exported'),
        const Hairline(),
      ],
      if (report != null) SettingsLimitations(report!.limitations),
      if (report == null)
        const WorkstationNote(
          'Kontextsensitiver Inspector',
          'Setting oder Tool auswählen. Der Inspector zeigt nur gelieferte Vertragsdaten, Permission-Grenzen und konkrete Backend-Anforderungen.',
          icon: Icons.info_outline,
        ),
    ]);
  }

  Widget _settingInspector(
      SettingDefinition definition, EffectiveSetting? effective) {
    return ListView(children: [
      const PanelLabel('Setting Inspector'),
      Text(definition.key, style: WorkstationTokens.mono(context, size: 14)),
      const SizedBox(height: 6),
      Text(definition.description,
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      const StatusPill('OFFLINE ADMINISTRATION REQUIRED',
          color: OipTokens.yellow, icon: Icons.lock_outline),
      const Hairline(),
      KeyValue('Effective Value', effective?.effective.display ?? 'Unknown'),
      KeyValue('Default', definition.defaultValue.display),
      KeyValue('Type', definition.dataType),
      KeyValue(
          'Requested Scope', effective?.requestedScope.display ?? 'Unknown'),
      KeyValue(
          'Origin Scope', effective?.origin?.display ?? 'built_in_default'),
      KeyValue(
          'Persisted Exact Scope',
          effective?.persisted == null
              ? 'No exact-scope record; default/inherited value'
              : 'revision ${effective!.persisted!.revision}'),
      KeyValue('Effective Revision',
          effective?.effectiveRevision.toString() ?? 'Unknown'),
      KeyValue('Apply Status', effective?.applyStatus ?? 'Unknown'),
      KeyValue('Apply Mode', definition.applyMode),
      KeyValue('Validation', definition.validation, mono: false),
      KeyValue('Supported Scopes', definition.scopes.join(' > ')),
      KeyValue('Inherited', definition.inherited ? 'true' : 'false'),
      KeyValue('Read / Write Permission',
          '${definition.readPermission} / ${definition.writePermission}'),
      KeyValue('Sensitivity', definition.sensitivity, mono: false),
      KeyValue('Persistence', definition.persistence),
      KeyValue('Change Channel', definition.changeChannel),
      const WorkstationNote(
        'Kein Browser-Speichern',
        'expected_revision bezieht sich beim Offline-CLI auf den exakten Scope-Datensatz (0 bei Abwesenheit), nicht auf eine geerbte effective_revision. Die UI führt keine Mutation aus.',
        icon: Icons.offline_bolt_outlined,
      ),
    ]);
  }
}
