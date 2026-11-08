import 'package:flutter/material.dart';

import '../../design_system/theme.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'settings_models.dart';
import 'settings_session.dart';

String settingsCategoryLabel(SettingsCategory category) => switch (category) {
      SettingsCategory.general => 'General',
      SettingsCategory.mcpAgents => 'MCP & Agents',
      SettingsCategory.infrastructure => 'Infrastructure',
      SettingsCategory.dataStorage => 'Data & Storage',
      SettingsCategory.diagnostics => 'Diagnostics',
      SettingsCategory.securityAccess => 'Security & Access',
      SettingsCategory.system => 'System',
    };

IconData settingsCategoryIcon(SettingsCategory category) => switch (category) {
      SettingsCategory.general => Icons.tune_outlined,
      SettingsCategory.mcpAgents => Icons.smart_toy_outlined,
      SettingsCategory.infrastructure => Icons.account_tree_outlined,
      SettingsCategory.dataStorage => Icons.storage_outlined,
      SettingsCategory.diagnostics => Icons.fact_check_outlined,
      SettingsCategory.securityAccess => Icons.shield_outlined,
      SettingsCategory.system => Icons.info_outline,
    };

List<SettingsSection> settingsSections(SettingsCategory category) =>
    switch (category) {
      SettingsCategory.general => const [
          SettingsSection.application,
          SettingsSection.preferences,
        ],
      SettingsCategory.mcpAgents => const [
          SettingsSection.mcpServer,
          SettingsSection.clientConfiguration,
          SettingsSection.tools,
          SettingsSection.permissions,
          SettingsSection.connectionDiagnostics,
          SettingsSection.clientSessions,
        ],
      SettingsCategory.infrastructure => const [
          SettingsSection.organizations,
          SettingsSection.infrastructures,
          SettingsSection.sites,
          SettingsSection.sourcesDevices,
        ],
      SettingsCategory.dataStorage => const [
          SettingsSection.sqlite,
          SettingsSection.historicalData,
          SettingsSection.retention,
        ],
      SettingsCategory.diagnostics => const [
          SettingsSection.diagnosticRules,
          SettingsSection.evidence,
          SettingsSection.historyLimits,
        ],
      SettingsCategory.securityAccess => const [
          SettingsSection.currentIdentity,
          SettingsSection.effectivePermissions,
          SettingsSection.auditSecurity,
        ],
      SettingsCategory.system => const [
          SettingsSection.runtime,
          SettingsSection.versions,
          SettingsSection.capabilities,
        ],
    };

String settingsSectionLabel(SettingsSection section) => switch (section) {
      SettingsSection.application => 'Application',
      SettingsSection.preferences => 'Appearance & Preferences',
      SettingsSection.mcpServer => 'MCP Server',
      SettingsSection.clientConfiguration => 'Client Configuration',
      SettingsSection.tools => 'Tools & Capabilities',
      SettingsSection.permissions => 'Permissions & Scopes',
      SettingsSection.connectionDiagnostics => 'Connection Diagnostics',
      SettingsSection.clientSessions => 'Client Sessions',
      SettingsSection.organizations => 'Organizations',
      SettingsSection.infrastructures => 'Infrastructures',
      SettingsSection.sites => 'Sites',
      SettingsSection.sourcesDevices => 'Sources & Devices',
      SettingsSection.sqlite => 'SQLite',
      SettingsSection.historicalData => 'Historical Data',
      SettingsSection.retention => 'Retention',
      SettingsSection.diagnosticRules => 'Rules',
      SettingsSection.evidence => 'Evidence',
      SettingsSection.historyLimits => 'History Limits',
      SettingsSection.currentIdentity => 'Current Identity',
      SettingsSection.effectivePermissions => 'Permissions',
      SettingsSection.auditSecurity => 'Audit & Security',
      SettingsSection.runtime => 'Runtime',
      SettingsSection.versions => 'Versions',
      SettingsSection.capabilities => 'Capabilities',
    };

class SettingsNavigation extends StatelessWidget {
  final SettingsWorkspaceSession session;
  final ValueChanged<SettingsCategory> onCategory;
  final ValueChanged<SettingsSection> onSection;
  const SettingsNavigation({
    super.key,
    required this.session,
    required this.onCategory,
    required this.onSection,
  });

  @override
  Widget build(BuildContext context) {
    return WorkstationPanel(
      padding: const EdgeInsets.all(OipTokens.s2),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const PanelLabel('Settings navigation'),
          for (final category in SettingsCategory.values) ...[
            _category(context, category),
            if (session.category == category)
              for (final section in settingsSections(category))
                _section(context, section),
          ],
        ],
      ),
    );
  }

  Widget _category(BuildContext context, SettingsCategory category) {
    final selected = session.category == category;
    final tone = OipTokens.readableAccent(context, OipTokens.cyan);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Settings-Kategorie ${settingsCategoryLabel(category)}',
      child: Material(
        color: selected ? tone.withOpacity(.11) : Colors.transparent,
        borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
        child: InkWell(
          key: Key('settings-category-${category.name}'),
          borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
          onTap: () => onCategory(category),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
            child: Row(children: [
              Icon(settingsCategoryIcon(category),
                  size: 17, color: selected ? tone : OipTokens.muted(context)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(settingsCategoryLabel(category),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? tone : null)),
              ),
              Icon(selected ? Icons.expand_more : Icons.chevron_right,
                  size: 15, color: OipTokens.muted(context)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, SettingsSection section) {
    final selected = session.section == section;
    final tone = OipTokens.readableAccent(context, OipTokens.blue);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Settings-Bereich ${settingsSectionLabel(section)}',
      child: Material(
        color: selected ? tone.withOpacity(.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
        child: InkWell(
          key: Key('settings-section-${section.name}'),
          borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
          onTap: () => onSection(section),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(35, 8, 8, 8),
            child: Text(settingsSectionLabel(section),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: selected ? tone : OipTokens.muted(context),
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          ),
        ),
      ),
    );
  }
}

class SettingsMetricStrip extends StatelessWidget {
  final List<(String, String, IconData)> values;
  const SettingsMetricStrip(this.values, {super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final columns = box.maxWidth < 430 ? 2 : values.length.clamp(2, 4);
        final width = (box.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values
              .map((entry) => SizedBox(
                    width: width,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: WorkstationTokens.well(context),
                        border: Border.all(
                            color: WorkstationTokens.hairline(context)),
                        borderRadius:
                            BorderRadius.circular(WorkstationTokens.radiusSm),
                      ),
                      child: Row(children: [
                        Icon(entry.$3, size: 16, color: OipTokens.cyan),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry.$1,
                                    style: WorkstationTokens.eyebrow(context)),
                                const SizedBox(height: 2),
                                Text(entry.$2,
                                    overflow: TextOverflow.ellipsis,
                                    style: WorkstationTokens.mono(context,
                                        size: 13, weight: FontWeight.w700)),
                              ]),
                        ),
                      ]),
                    ),
                  ))
              .toList(),
        );
      });
}

class SettingsFacts extends StatelessWidget {
  final List<ManagementFact> facts;
  final Set<String> excluded;
  const SettingsFacts(this.facts, {super.key, this.excluded = const {}});

  @override
  Widget build(BuildContext context) {
    final visible =
        facts.where((fact) => !excluded.contains(fact.name)).toList();
    return KeyValueGrid(
      children: visible.map((fact) => KeyValue(fact.name, fact.value)).toList(),
    );
  }
}

class SettingsLimitations extends StatelessWidget {
  final List<String> limitations;
  const SettingsLimitations(this.limitations, {super.key});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelLabel('Grenzen & Anforderungen'),
          for (final limitation in limitations)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.lock_outline,
                    size: 14, color: OipTokens.muted(context)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(limitation,
                        style: Theme.of(context).textTheme.bodySmall)),
              ]),
            ),
        ],
      );
}

class SettingsJsonBlock extends StatelessWidget {
  final String value;
  final String semanticsLabel;
  final double maxHeight;
  const SettingsJsonBlock(
    this.value, {
    super.key,
    required this.semanticsLabel,
    this.maxHeight = 260,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticsLabel,
        textField: true,
        readOnly: true,
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: WorkstationTokens.well(context),
            border: Border.all(color: WorkstationTokens.line(context)),
            borderRadius: BorderRadius.circular(WorkstationTokens.radiusSm),
          ),
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(value,
                  style: WorkstationTokens.mono(context, size: 10.5)),
            ),
          ),
        ),
      );
}

class SettingsSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String status;
  final Color? statusColor;
  final List<Widget> actions;
  const SettingsSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.status,
    this.statusColor,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          StatusPill(status,
              color: statusColor, icon: Icons.lock_open_outlined),
          ...actions,
        ],
      );
}
