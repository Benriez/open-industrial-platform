import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/controller.dart';
import '../design_system/theme.dart';
import '../models/infrastructure.dart';
import 'components.dart';
import 'workstation.dart';

/// Global infrastructure selector. The hierarchy comes only from authorized
/// Core reads; the scenario selector is a separate, demo-only control.
class InfrastructureSelector extends StatelessWidget {
  final OipController controller;
  final bool narrow;
  const InfrastructureSelector({
    super.key,
    required this.controller,
    this.narrow = false,
  });

  @override
  Widget build(BuildContext context) {
    final model = controller.infrastructure;
    final label = switch (model.status) {
      InfrastructureContextStatus.ready => model.selectedLabel,
      InfrastructureContextStatus.loading => 'Kontext wird autorisiert …',
      InfrastructureContextStatus.unauthenticated =>
        'Browser-Identität fehlt',
      InfrastructureContextStatus.permissionDenied =>
        'Kontext nicht autorisiert',
      InfrastructureContextStatus.unavailable => 'Lokaler Demo-Kontext',
      InfrastructureContextStatus.idle => 'Infrastructure Context',
    };
    final accent = model.ready
        ? OipTokens.readableAccent(context, OipTokens.cyan)
        : OipTokens.muted(context);
    return Tooltip(
      message: model.ready
          ? model.selectedBreadcrumb
          : 'Globaler Infrastructure Context · keine Szenarioauswahl',
      child: Semantics(
        button: true,
        label: 'Infrastructure Context: $label',
        child: InkWell(
          key: const Key('infrastructure-context-selector'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => InfrastructureContextDialog(controller: controller),
          ),
          child: Container(
            width: narrow ? 136 : 306,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: WorkstationTokens.well(context),
              border: Border.all(color: WorkstationTokens.hairline(context)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(
                model.ready
                    ? Icons.account_tree_outlined
                    : model.status == InfrastructureContextStatus.unavailable
                        ? Icons.science_outlined
                        : Icons.lock_outline,
                size: 16,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: accent)),
              ),
              if (model.isFixture) ...[
                const SizedBox(width: 5),
                Text('TEST',
                    style: WorkstationTokens.mono(context,
                        size: 8.5, color: OipTokens.yellow)),
              ],
              const SizedBox(width: 4),
              Icon(Icons.expand_more, size: 16, color: accent),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ContextOption {
  final InfrastructureSelection selection;
  final String label, path;
  final int depth;
  final IconData icon;
  const _ContextOption(
      this.selection, this.label, this.path, this.depth, this.icon);
}

class InfrastructureContextDialog extends StatefulWidget {
  final OipController controller;
  const InfrastructureContextDialog({super.key, required this.controller});

  @override
  State<InfrastructureContextDialog> createState() =>
      _InfrastructureContextDialogState();
}

class _InfrastructureContextDialogState
    extends State<InfrastructureContextDialog> {
  final search = TextEditingController();
  final searchFocus = FocusNode(debugLabel: 'infrastructure-context-search');
  final listFocus = FocusNode(debugLabel: 'infrastructure-context-list');
  final scroll = ScrollController();
  int cursor = 0;

  InfrastructureContext get model => widget.controller.infrastructure;

  @override
  void dispose() {
    search.dispose();
    searchFocus.dispose();
    listFocus.dispose();
    scroll.dispose();
    super.dispose();
  }

  List<_ContextOption> get options {
    final hierarchy = model.hierarchy;
    final result = <_ContextOption>[
      const _ContextOption(
        InfrastructureSelection.unified(),
        'Alle berechtigten Infrastrukturen',
        'Unified View · gesamter autorisierter Principal-Scope',
        0,
        Icons.all_inclusive,
      ),
    ];
    for (final organization in hierarchy.organizations) {
      result.add(_ContextOption(
        InfrastructureSelection.organization(organization.id),
        organization.name,
        organization.id,
        0,
        Icons.business_outlined,
      ));
      for (final infrastructure in hierarchy.infrastructures.where(
          (item) => item.organizationId == organization.id)) {
        final infrastructurePath = '${organization.name} / ${infrastructure.name}';
        result.add(_ContextOption(
          InfrastructureSelection.infrastructure(
              organization.id, infrastructure.id),
          infrastructure.name,
          '$infrastructurePath · ${infrastructure.id}',
          1,
          Icons.hub_outlined,
        ));
        for (final site in hierarchy.sites
            .where((item) => item.infrastructureId == infrastructure.id)) {
          final sitePath = '$infrastructurePath / ${site.name}';
          result.add(_ContextOption(
            InfrastructureSelection.site(
                organization.id, infrastructure.id, site.id),
            site.name,
            '$sitePath · ${site.id}',
            2,
            Icons.location_on_outlined,
          ));
          final seen = <String>{};
          for (final location in hierarchy.locations
              .where((item) => item.siteId == site.id)) {
            if (!seen.add(location.sourceId)) continue;
            result.add(_ContextOption(
              InfrastructureSelection.source(organization.id, infrastructure.id,
                  site.id, location.sourceId),
              location.sourceId,
              '$sitePath / ${location.sourceId}',
              3,
              Icons.sensors_outlined,
            ));
          }
        }
      }
    }
    final query = search.text.trim().toLowerCase();
    if (query.isEmpty) return result;
    return result
        .where((option) =>
            '${option.label} ${option.path} ${option.selection.scopeKey}'
                .toLowerCase()
                .contains(query))
        .toList();
  }

  void _choose(_ContextOption option) {
    try {
      widget.controller.selectInfrastructure(option.selection);
      Navigator.of(context).pop();
    } on Object {
      // A concurrent authorization refresh can remove an option between render
      // and activation. Fail closed and let the current hierarchy re-render.
      setState(() => cursor = 0);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Der Kontext ist nicht mehr autorisiert. Daten werden neu gelesen.'),
      ));
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final items = options;
    if (items.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (searchFocus.hasFocus) {
        // Leave the editor before list navigation; text cursor keys are never
        // reinterpreted repeatedly while the operator types.
        listFocus.requestFocus();
        setState(() => cursor = 0);
      } else {
        setState(() => cursor = (cursor + 1).clamp(0, items.length - 1));
      }
    } else if (key == LogicalKeyboardKey.arrowUp && !searchFocus.hasFocus) {
      setState(() => cursor = cursor <= 0 ? 0 : cursor - 1);
    } else if (key == LogicalKeyboardKey.home && !searchFocus.hasFocus) {
      setState(() => cursor = 0);
    } else if (key == LogicalKeyboardKey.end && !searchFocus.hasFocus) {
      setState(() => cursor = items.length - 1);
    } else if (key == LogicalKeyboardKey.enter) {
      _choose(items[cursor.clamp(0, items.length - 1)]);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    if (scroll.hasClients) {
      final target = (cursor * 52.0)
          .clamp(0.0, scroll.position.maxScrollExtent);
      scroll.animateTo(target,
          duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final items = options;
    cursor = cursor.clamp(0, items.isEmpty ? 0 : items.length - 1);
    final width = MediaQuery.sizeOf(context).width;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
          horizontal: width < 600 ? 12 : 32,
          vertical: width < 600 ? 16 : 40),
      child: SizedBox(
        width: (width - (width < 600 ? 24 : 64)).clamp(0.0, 660.0),
        height: (MediaQuery.sizeOf(context).height -
                (width < 600 ? 32 : 80))
            .clamp(0.0, 720.0),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Focus(
            onKeyEvent: _key,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Icon(Icons.account_tree_outlined,
                      color: OipTokens.readableAccent(context, OipTokens.cyan)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Infrastructure Context',
                              style: Theme.of(context).textTheme.titleLarge),
                          Text('Global für alle OIP-Workstations',
                              style: Theme.of(context).textTheme.bodySmall),
                        ]),
                  ),
                  if (model.isFixture && width >= 600)
                    const StatusPill('CONTRACT FIXTURE · NICHT LIVE',
                        color: OipTokens.yellow, icon: Icons.science_outlined),
                  if (model.isFixture && width < 600)
                    Text('TEST',
                        style: WorkstationTokens.mono(context,
                            size: 9, color: OipTokens.yellow)),
                  IconButton(
                    tooltip: 'Infrastructure Context schließen',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ]),
                const SizedBox(height: 10),
                if (width < 600)
                  Text(
                    'Authorization Scope ≠ Selected UI Context. Auswahl erteilt keine Berechtigung.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  const WorkstationNote(
                    'Authorization Scope ≠ Selected UI Context',
                    'Der Core bestimmt den autorisierten Principal-Scope. Die Auswahl grenzt nur bereits autorisierte Daten ein und erteilt keine Berechtigung.',
                    icon: Icons.verified_user_outlined,
                  ),
                const SizedBox(height: 10),
                if (!model.ready)
                  Expanded(child: _unavailable(context))
                else ...[
                  TextField(
                    key: const Key('infrastructure-context-search'),
                    controller: search,
                    focusNode: searchFocus,
                    autofocus: true,
                    onChanged: (_) => setState(() => cursor = 0),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Organization, Infrastructure, Site oder Source …',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: Text(
                        model.hasInfrastructure
                            ? '${hierarchyCount(model.hierarchy)} · Pfeile / Enter'
                            : 'No infrastructure configured',
                        style: WorkstationTokens.mono(context, size: 9.5),
                      ),
                    ),
                    Text('REV ${model.contextRevision}',
                        style: WorkstationTokens.mono(context, size: 9.5)),
                  ]),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Focus(
                      focusNode: listFocus,
                      child: items.isEmpty
                          ? const Center(
                              child: Text('Kein autorisierter Kontext passt zur Suche.'))
                          : ListView.builder(
                              key: const Key('infrastructure-context-options'),
                              controller: scroll,
                              itemCount: items.length,
                              itemBuilder: (context, index) =>
                                  _option(context, items[index], index),
                            ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Principal: ${model.principalIdentity ?? 'vom Core nicht geliefert'} · keine Credentials in URL oder LocalStorage',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: WorkstationTokens.mono(context, size: 9),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _option(BuildContext context, _ContextOption option, int index) {
    final selected = model.selection == option.selection;
    final accent = OipTokens.readableAccent(context, OipTokens.cyan);
    return Padding(
      padding: EdgeInsets.only(left: option.depth * 14.0, bottom: 2),
      child: Material(
        color: selected
            ? accent.withOpacity(.14)
            : index == cursor
                ? WorkstationTokens.well(context)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: Semantics(
          button: true,
          selected: selected,
          label: 'Kontext ${option.path} auswählen',
          child: ListTile(
            key: Key(
                'context-option-${option.selection.kind.name}-${option.selection.id}'),
            dense: true,
            minTileHeight: 44,
            leading: Icon(option.icon,
                size: 17, color: selected ? accent : OipTokens.muted(context)),
            title: Text(option.label,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(option.path,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: selected ? Icon(Icons.check, size: 17, color: accent) : null,
            onTap: () => _choose(option),
          ),
        ),
      ),
    );
  }

  Widget _unavailable(BuildContext context) {
    final (title, message, icon) = switch (model.status) {
      InfrastructureContextStatus.unauthenticated => (
          'Sichere Browser-Identität erforderlich',
          'Der Core hat keine Browser-Session akzeptiert. Es werden keine Tokens in URLs, Webassets oder LocalStorage ergänzt und keine anonymen Tenant-Daten geladen.',
          Icons.lock_outline,
        ),
      InfrastructureContextStatus.permissionDenied => (
          'Kein autorisierter Infrastructure Scope',
          'Die zentrale Policy erlaubt keinen Hierarchie-Read für diese Browser-Identität. Das ist keine leere Installation und kein Netzwerkfehler.',
          Icons.admin_panel_settings_outlined,
        ),
      InfrastructureContextStatus.loading => (
          'Autorisierte Hierarchie wird gelesen',
          'Organizations, Infrastructures, Sites und Scoped Snapshot werden vom Core geladen.',
          Icons.sync,
        ),
      _ => (
          'Expliziter Demo-/Legacy-Kontext',
          'Dieser Lauf liefert keine autorisierte Mehrinfrastruktur-Hierarchie. Der Simulator bleibt eine Szenarioauswahl und wird nicht als Infrastructure-Switcher ausgegeben.',
          Icons.science_outlined,
        ),
    };
    return Center(
      child: SingleChildScrollView(
        child: WorkstationNote(title, message, icon: icon),
      ),
    );
  }
}

String hierarchyCount(AuthorizedHierarchy hierarchy) =>
    '${hierarchy.organizations.length} ORG · '
    '${hierarchy.infrastructures.length} INFRA · '
    '${hierarchy.sites.length} SITES · '
    '${hierarchy.locations.map((item) => item.sourceId).toSet().length} SOURCES';
