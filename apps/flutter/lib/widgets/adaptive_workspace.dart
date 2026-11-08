import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../design_system/theme.dart';
import 'components.dart';
import 'workstation.dart';

/// Shared progressive-disclosure primitives. They change presentation only;
/// object authority and data provenance stay in the existing Core contracts.
class AdaptiveWorkspaceHeader extends StatelessWidget {
  final String eyebrow, title, subtitle;
  final Color accent;
  final Widget? primaryAction;
  final List<Widget> status;
  final List<Widget> actions;

  const AdaptiveWorkspaceHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.primaryAction,
    this.status = const [],
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final compact = box.maxWidth < 700;
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow,
              style: WorkstationTokens.eyebrow(context, color: accent)),
          const SizedBox(height: 2),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          if (subtitle.isNotEmpty)
            Text(subtitle,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
        ],
      );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
          spacing: 10,
          runSpacing: 7,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            heading,
            if (primaryAction != null) primaryAction!,
            ...actions,
            if (!compact) ...status,
          ],
        ),
        if (compact && status.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: status),
        ],
      ]);
    });
  }
}

class WorkspacePrimaryAction extends StatelessWidget {
  final String label, tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Key? buttonKey;

  const WorkspacePrimaryAction({
    super.key,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: FilledButton.icon(
          key: buttonKey,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 36),
            maximumSize: const Size(double.infinity, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 17),
          label: Text(label),
        ),
      );
}

/// Inspector visibility is automatic after object selection and explicit for
/// experts through close/open/pin. The parent simply expands into freed space.
class AdaptiveInspector extends StatelessWidget {
  final OipController controller;
  final WorkspaceId workspace;
  final String label;
  final bool hasSelection;
  final Widget child;

  const AdaptiveInspector({
    super.key,
    required this.controller,
    required this.workspace,
    required this.label,
    required this.hasSelection,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final visible = controller.inspectorVisible(workspace, hasSelection);
    if (!visible) {
      return WorkspaceAvailability(
        key: Key('${workspace.name}-inspector-closed'),
        title: 'Inspector geschlossen',
        message: hasSelection
            ? 'Das ausgewählte Objekt bleibt aktiv. Details bei Bedarf öffnen.'
            : 'Ohne Objektauswahl bleibt dieser Bereich geschlossen.',
        action: WorkspacePrimaryAction(
          buttonKey: Key('${workspace.name}-inspector-reveal'),
          label: 'Details öffnen',
          tooltip: 'Kontextsensitiven Inspector öffnen',
          icon: Icons.info_outline,
          onPressed: () => controller.setInspectorOpen(workspace, true),
        ),
      );
    }
    final pinned = controller.workspaces.layout(workspace).inspectorPinned;
    return Column(
      key: Key('${workspace.name}-adaptive-inspector'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 32,
          child: Row(children: [
            Icon(
              hasSelection ? Icons.info_outline : Icons.view_sidebar_outlined,
              size: 15,
              color: OipTokens.muted(context),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WorkstationTokens.eyebrow(context)),
            ),
            ToolButton(
              key: Key('${workspace.name}-inspector-pin'),
              tooltip: pinned
                  ? 'Inspector nicht mehr anheften'
                  : 'Inspector für diese Workstation anheften',
              icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
              active: pinned,
              onPressed: () => controller.toggleInspectorPin(workspace),
            ),
            ToolButton(
              key: Key('${workspace.name}-inspector-close'),
              tooltip:
                  'Inspector schließen · Objekt- und Datenwahl bleibt erhalten',
              icon: Icons.close,
              onPressed: () => controller.setInspectorOpen(workspace, false),
            ),
          ]),
        ),
        const SizedBox(height: 4),
        Expanded(child: child),
      ],
    );
  }
}

class InspectorOpenAction extends StatelessWidget {
  final OipController controller;
  final WorkspaceId workspace;
  final bool hasSelection;
  final VoidCallback? onOpen;
  const InspectorOpenAction({
    super.key,
    required this.controller,
    required this.workspace,
    this.hasSelection = false,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) => ToolButton(
        key: Key('${workspace.name}-inspector-open'),
        tooltip: 'Detail-Inspector manuell öffnen',
        icon: Icons.info_outline,
        active: controller.inspectorVisible(workspace, hasSelection),
        onPressed: () {
          controller.setInspectorOpen(workspace, true);
          onOpen?.call();
        },
      );
}

/// Direct expert entry point. It is intentionally not a beginner/expert mode.
class WorkspaceLayoutAction extends StatelessWidget {
  final OipController controller;
  final WorkspaceId workspace;
  final String label;

  const WorkspaceLayoutAction({
    super.key,
    required this.controller,
    required this.workspace,
    this.label = 'Engineering Workspace',
  });

  @override
  Widget build(BuildContext context) {
    final enabled = controller.workspaces.layout(workspace).expertWorkspace;
    return ToolButton(
      key: Key('${workspace.name}-workspace-toggle'),
      tooltip: enabled
          ? '$label schließen'
          : '$label dauerhaft für diese Sitzung öffnen',
      icon: Icons.dashboard_customize_outlined,
      active: enabled,
      onPressed: () => controller.setExpertWorkspace(workspace, !enabled),
    );
  }
}

class AdvancedWorkspaceSection extends StatelessWidget {
  final String title, summary;
  final bool expanded;
  final ValueChanged<bool> onChanged;
  final List<Widget> children;

  const AdvancedWorkspaceSection({
    super.key,
    required this.title,
    required this.summary,
    required this.expanded,
    required this.onChanged,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => ExpansionTile(
        title: Text(title, style: const TextStyle(fontSize: 12)),
        subtitle: Text(summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10)),
        initiallyExpanded: expanded,
        onExpansionChanged: onChanged,
        dense: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: children,
      );
}

class WorkspaceAvailability extends StatelessWidget {
  final String title, message;
  final IconData icon;
  final Widget? action;
  const WorkspaceAvailability({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
    this.action,
  });

  @override
  Widget build(BuildContext context) => WorkstationPanel(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          WorkstationNote(title, message, icon: icon),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ]),
      );
}

/// Status vocabulary describes one property only; it never summarizes the
/// health of an entire system.
String apiConnectionLabel(OipController controller) =>
    switch (controller.connection) {
      'live' => 'API CONNECTED',
      'connecting' => 'API VERBINDET',
      'identity-required' => 'IDENTITÄT ERFORDERLICH',
      'context-unsupported' => 'KEIN V2-KONTEXT',
      _ => 'API STALE / RECONNECT',
    };

StatusPill apiConnectionStatus(
        BuildContext context, OipController controller) =>
    StatusPill(
      apiConnectionLabel(controller),
      color: OipTokens.statusColor(
          context, controller.connection == 'live' ? 'connected' : 'degraded'),
      showDot: true,
    );
