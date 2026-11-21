import '../../l10n/oip_strings.dart';
import 'package:flutter/material.dart';

import '../../design_system/theme.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import 'settings_models.dart';
import 'settings_navigation.dart';
import 'settings_session.dart';

String toolAvailabilityLabel(ManagedTool tool) => switch (tool.availability) {
      'available' => 'Available to Principal',
      'denied_by_policy' => 'Denied by Policy',
      'runtime_unavailable' => 'Runtime Unavailable',
      'unsupported' => 'Unsupported',
      _ => tool.availability,
    };

Color toolAvailabilityColor(BuildContext context, ManagedTool tool) =>
    OipTokens.statusColor(
        context,
        switch (tool.availability) {
          'available' => 'connected',
          'denied_by_policy' => 'degraded',
          'runtime_unavailable' => 'unavailable',
          _ => 'unknown',
        });

List<ManagedTool> filteredSettingsTools(
    ManagementReport report, SettingsWorkspaceSession session) {
  final query = session.toolSearch.trim().toLowerCase();
  return report.tools.where((tool) {
    final matchesQuery = query.isEmpty ||
        tool.name.toLowerCase().contains(query) ||
        tool.description.toLowerCase().contains(query) ||
        tool.capability.toLowerCase().contains(query);
    final matchesCapability = session.capabilityFilter == 'all' ||
        tool.capability == session.capabilityFilter;
    final matchesPermission = switch (session.permissionFilter) {
      'available' => tool.availableToPrincipal,
      'denied' => !tool.availableToPrincipal,
      'runtime_unavailable' => !tool.runtimeAvailable,
      _ => true,
    };
    return matchesQuery && matchesCapability && matchesPermission;
  }).toList(growable: false);
}

class SettingsToolExplorer extends StatelessWidget {
  final ManagementReport report;
  final SettingsWorkspaceSession session;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final VoidCallback onFiltersChanged;
  final ValueChanged<ManagedTool> onSelect;
  final void Function(String label, String value) onCopy;
  const SettingsToolExplorer({
    super.key,
    required this.report,
    required this.session,
    required this.searchController,
    required this.searchFocus,
    required this.onFiltersChanged,
    required this.onSelect,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final tools = filteredSettingsTools(report, session);
    final capabilities =
        report.tools.map((tool) => tool.capability).toSet().toList()..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsSectionHeader(
        title: context.tr("MCP Tool & Capability Explorer"),
        subtitle: context.tr(
            "{0} registrierte Tools aus dem autorisierten Core-Mapping. Sichtbarkeit ist keine Ausführungsfreigabe.",
            [report.tools.length]),
        status: context.tr("READ-ONLY CATALOG"),
        actions: [
          ToolButton(
            icon: Icons.copy_outlined,
            tooltip:
                context.tr("Tool-Katalog als technische Textansicht kopieren"),
            onPressed: () => onCopy(
              'Tool-Katalog',
              report.tools
                  .map((tool) =>
                      '${tool.name} | ${tool.capability} | ${toolAvailabilityLabel(tool)} | ${tool.permissions.join(',')}')
                  .join('\n'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, box) {
        final stacked = box.maxWidth < 660;
        final search = TextField(
          key: const Key('settings-tool-search'),
          controller: searchController,
          focusNode: searchFocus,
          onChanged: (_) => onFiltersChanged(),
          decoration: InputDecoration(
            labelText: context.tr("Tool, Capability oder Beschreibung"),
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: searchController.text.isEmpty
                ? null
                : IconButton(
                    key: const Key('settings-tool-search-clear'),
                    tooltip: context.tr("Suche löschen"),
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      searchController.clear();
                      onFiltersChanged();
                      searchFocus.requestFocus();
                    },
                  ),
          ),
        );
        final permission = DropdownButtonFormField<String>(
          key: const Key('settings-permission-filter'),
          isExpanded: true,
          value: session.permissionFilter,
          decoration: InputDecoration(labelText: context.tr("Permission")),
          items: [
            DropdownMenuItem(
                value: 'all', child: Text(context.tr("Alle Berechtigungen"))),
            DropdownMenuItem(
                value: 'available', child: Text(context.tr("Available"))),
            DropdownMenuItem(
                value: 'denied', child: Text(context.tr("Denied by Policy"))),
            DropdownMenuItem(
                value: 'runtime_unavailable',
                child: Text(context.tr("Runtime Unavailable"))),
          ],
          onChanged: (value) {
            session.permissionFilter = value ?? 'all';
            onFiltersChanged();
          },
        );
        final capability = DropdownButtonFormField<String>(
          key: const Key('settings-capability-filter'),
          isExpanded: true,
          value: session.capabilityFilter,
          decoration: InputDecoration(labelText: context.tr("Capability")),
          items: [
            DropdownMenuItem(
                value: 'all', child: Text(context.tr("Alle Capabilities"))),
            for (final value in capabilities)
              DropdownMenuItem(
                  value: value,
                  child: Text(value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (value) {
            session.capabilityFilter = value ?? 'all';
            onFiltersChanged();
          },
        );
        if (stacked) {
          return Column(children: [
            search,
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: permission),
              const SizedBox(width: 8),
              Expanded(child: capability),
            ]),
          ]);
        }
        return Row(children: [
          Expanded(flex: 3, child: search),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: permission),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: capability),
        ]);
      }),
      const SizedBox(height: 8),
      Text(
          context.tr(
              "{0} von {1} Tools · Filter wirken nur auf den gelieferten Katalog",
              [tools.length, report.tools.length]),
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      Expanded(
        child: tools.isEmpty
            ? Center(
                child: WorkstationNote(
                  context.tr("Keine Tools im Filter"),
                  context.tr(
                      "Suche oder Filter ändern. Der Core-Katalog bleibt unverändert."),
                  icon: Icons.filter_alt_off_outlined,
                ),
              )
            : ListView.separated(
                key: const Key('settings-tool-list'),
                itemCount: tools.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final tool = tools[index];
                  final selected = session.selectedTool == tool.name;
                  final tone = toolAvailabilityColor(context, tool);
                  return Semantics(
                    button: true,
                    selected: selected,
                    label: context.tr("MCP Tool {0}. {1}. {2}", [
                      tool.name,
                      toolAvailabilityLabel(tool),
                      tool.classification
                    ]),
                    child: Material(
                      color: selected
                          ? tone.withOpacity(.12)
                          : WorkstationTokens.well(context),
                      borderRadius:
                          BorderRadius.circular(WorkstationTokens.radiusSm),
                      child: InkWell(
                        key: Key('settings-tool-${tool.name}'),
                        onTap: () => onSelect(tool),
                        borderRadius:
                            BorderRadius.circular(WorkstationTokens.radiusSm),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
                          child: Row(children: [
                            Container(
                              width: 3,
                              height: 36,
                              color: selected ? tone : Colors.transparent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(tool.name,
                                        style: WorkstationTokens.mono(context,
                                            size: 12, weight: FontWeight.w700)),
                                    const SizedBox(height: 2),
                                    Text(tool.capability,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                  ]),
                            ),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 150),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                        context.tr(toolAvailabilityLabel(tool)),
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: tone,
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                        tool.classification
                                                .contains('read_only')
                                            ? context.tr("READ ONLY")
                                            : context
                                                .tr("CLASSIFICATION UNKNOWN"),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall),
                                  ]),
                            ),
                            ToolButton(
                              icon: Icons.copy_outlined,
                              tooltip: context
                                  .tr("Tool-Namen {0} kopieren", [tool.name]),
                              onPressed: () => onCopy('Tool-Name', tool.name),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

class SettingsToolInspector extends StatelessWidget {
  final ManagedTool? tool;
  final ManagementReport? server;
  final SettingsWorkspaceSession session;
  final VoidCallback onSchemaChanged;
  final void Function(String label, String value) onCopy;
  const SettingsToolInspector({
    super.key,
    required this.tool,
    required this.server,
    required this.session,
    required this.onSchemaChanged,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final selected = tool;
    if (selected == null) {
      return WorkstationNote(
        context.tr("Tool auswählen"),
        context.tr(
            "Ein registriertes Tool auswählen, um Schema, Permissions, Scopes und effektive Verfügbarkeit zu prüfen."),
        icon: Icons.smart_toy_outlined,
      );
    }
    final tone = toolAvailabilityColor(context, selected);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        PanelLabel(context.tr("Tool Inspector"), color: tone),
        Text(selected.name, style: WorkstationTokens.mono(context, size: 14)),
        const SizedBox(height: 6),
        Text(selected.description,
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          StatusPill(context.tr(toolAvailabilityLabel(selected)), color: tone),
          StatusPill(
              selected.classification.contains('read_only')
                  ? context.tr("READ ONLY")
                  : context.tr("CLASSIFICATION UNKNOWN"),
              icon: Icons.lock_outline),
        ]),
        const Hairline(),
        KeyValue(context.tr("Capability"), selected.capability),
        KeyValue(context.tr("Required Permissions"),
            selected.permissions.join(', ')),
        KeyValue(
            context.tr("Allowed Scopes"), selected.supportedScopes.join(', ')),
        KeyValue(context.tr("Registered"),
            selected.registered ? context.tr("true") : context.tr("false")),
        KeyValue(
            context.tr("Available to Principal"),
            selected.availableToPrincipal
                ? context.tr("true")
                : context.tr("false")),
        KeyValue(
            context.tr("Runtime Available"),
            selected.runtimeAvailable
                ? context.tr("true")
                : context.tr("false")),
        KeyValue(context.tr("Classification"), selected.classification),
        if (server != null) ...[
          KeyValue(
              context.tr("Max Input Bytes"), server!.fact('max_input_bytes')),
          KeyValue(
              context.tr("Max Output Bytes"), server!.fact('max_output_bytes')),
          KeyValue(context.tr("Max Requests / Session"),
              server!.fact('max_requests_per_session')),
        ],
        const Hairline(),
        Wrap(spacing: 6, children: [
          ChoiceChip(
            key: const Key('settings-input-schema'),
            label: Text(context.tr("Input Schema")),
            selected: !session.showOutputSchema,
            showCheckmark: false,
            onSelected: (_) {
              session.showOutputSchema = false;
              onSchemaChanged();
            },
          ),
          ChoiceChip(
            key: const Key('settings-output-schema'),
            label: Text(context.tr("Output Schema")),
            selected: session.showOutputSchema,
            showCheckmark: false,
            onSelected: (_) {
              session.showOutputSchema = true;
              onSchemaChanged();
            },
          ),
        ]),
        const SizedBox(height: 8),
        SettingsJsonBlock(
          selected.prettySchema(output: session.showOutputSchema),
          semanticsLabel:
              '${session.showOutputSchema ? 'Output' : 'Input'} Schema für ${selected.name}',
          maxHeight: 210,
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          OutlinedButton.icon(
            key: const Key('settings-copy-schema'),
            onPressed: () => onCopy(
                '${session.showOutputSchema ? 'Output' : 'Input'} Schema',
                selected.prettySchema(output: session.showOutputSchema)),
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: Text(context.tr("Schema kopieren")),
          ),
          OutlinedButton.icon(
            onPressed: () => onCopy('Tool-Name', selected.name),
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: Text(context.tr("Tool-Namen kopieren")),
          ),
        ]),
        const SizedBox(height: 10),
        WorkstationNote(
          context.tr("Execution & Fehler"),
          context.tr(
              "Schemas gewähren keine Ausführung. Der Core prüft Ziel-Scope und Berechtigung bei jedem Aufruf erneut und liefert strukturierte Capability-Fehler. Diese Workstation führt keine Tools aus."),
          icon: Icons.policy_outlined,
        ),
      ],
    );
  }
}

class SettingsPermissionMatrix extends StatelessWidget {
  final ManagementReport report;
  final SettingsWorkspaceSession session;
  final ValueChanged<ManagedTool> onSelect;
  const SettingsPermissionMatrix({
    super.key,
    required this.report,
    required this.session,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => ListView.separated(
        key: const Key('settings-permission-matrix'),
        itemCount: report.tools.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final tool = report.tools[index];
          final tone = toolAvailabilityColor(context, tool);
          return Semantics(
            button: true,
            label: context.tr("Permission {0}: {1}. Berechtigung {2}", [
              tool.name,
              toolAvailabilityLabel(tool),
              tool.permissions.join(', ')
            ]),
            child: ListTile(
              key: Key('settings-permission-${tool.name}'),
              dense: true,
              onTap: () => onSelect(tool),
              title: Text(tool.name,
                  style: WorkstationTokens.mono(context, size: 11)),
              subtitle: Text(
                  '${tool.capability} · ${tool.permissions.join(', ')} · ${tool.supportedScopes.join(', ')}'),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(context.tr(toolAvailabilityLabel(tool)),
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 10, color: tone)),
              ),
            ),
          );
        },
      );
}
