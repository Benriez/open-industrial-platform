import '../../l10n/oip_strings.dart';
import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import '../../models/infrastructure.dart';
import '../../widgets/workstation.dart';

/// Compact, authorized multi-infrastructure summary for Unified View.
/// Selecting a row changes the one global context; there is no local filter.
class UnifiedInfrastructureSummary extends StatelessWidget {
  final OipController controller;
  const UnifiedInfrastructureSummary({super.key, required this.controller});

  InfrastructureContext get model => controller.infrastructure;
  Snapshot get snapshot => controller.snapshot!;

  @override
  Widget build(BuildContext context) {
    final hierarchy = model.hierarchy;
    final sources = snapshot.sources;
    final connected =
        sources.where((item) => item.connection == 'connected').length;
    final staleOrUnknown =
        sources.where((item) => item.freshness != 'fresh').length;
    final covered = snapshot.devices
        .where((device) => snapshot.metrics.any((observation) =>
            observation.entityId == device.id &&
            observation.sourceId == device.sourceId))
        .length;
    final collectionProblems = snapshot.recentEvents
        .where((event) =>
            event.kind == 'DataLoss' ||
            event.kind == 'SubscriptionError' ||
            event.gapStartedMs != null)
        .length;
    final findings = model.findings;
    final facts = <(String, String)>[
      ('ORGANIZATIONS', '${hierarchy.organizations.length}'),
      ('INFRASTRUCTURES', '${hierarchy.infrastructures.length}'),
      ('SITES', '${hierarchy.sites.length}'),
      ('DEVICES', '${snapshot.devices.length}'),
      ('SOURCES', '${sources.length} · $connected CONNECTED'),
      ('STALE / UNKNOWN SOURCES', '$staleOrUnknown'),
      (
        'DETERMINISTIC FINDINGS',
        findings == null ? 'NICHT VERFÜGBAR' : '${findings.length}'
      ),
      ('COLLECTION PROBLEMS', '$collectionProblems'),
      ('DATA COVERAGE', '$covered / ${snapshot.devices.length} DEVICES'),
    ];
    return WorkstationPanel(
      key: const Key('unified-infrastructure-summary'),
      accent: OipTokens.cyan,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelLabel(context.tr("Unified Infrastructure View"), bottom: 6),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: facts
              .map((fact) => Semantics(
                    label: '${fact.$1}: ${fact.$2}',
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fact.$1,
                              style: WorkstationTokens.eyebrow(context)),
                          Text(fact.$2,
                              style: WorkstationTokens.mono(context,
                                  size: 11, weight: FontWeight.w700)),
                        ]),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        if (hierarchy.infrastructures.isEmpty)
          WorkstationNote(
            context.tr("No infrastructure configured"),
            context.tr(
                "Der autorisierte Principal sieht aktuell keine Infrastructure. Es wird keine Demo-Organization angelegt."),
            icon: Icons.account_tree_outlined,
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 184),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final infrastructure in hierarchy.infrastructures)
                  _infrastructureRow(context, infrastructure),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Text(
          context.tr(
              "Nur tatsächlich autorisierte Rows · keine globale Health-Severity · Unknown ≠ Offline · NoCollector ≠ Fehler"),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ]),
    );
  }

  Widget _infrastructureRow(
      BuildContext context, AuthorizedInfrastructure infrastructure) {
    final organization =
        model.hierarchy.organization(infrastructure.organizationId);
    final sites = model.hierarchy.sites
        .where((item) => item.infrastructureId == infrastructure.id)
        .length;
    final devices = snapshot.devices.where((device) {
      final placement = model.devicePlacement(device);
      return placement?.infrastructureId == infrastructure.id;
    }).length;
    final sourceIds = model.hierarchy.locations
        .where((item) => item.infrastructureId == infrastructure.id)
        .map((item) => item.sourceId)
        .toSet();
    final sources =
        snapshot.sources.where((item) => sourceIds.contains(item.id)).toList();
    final fresh = sources.where((item) => item.freshness == 'fresh').length;
    final available =
        sources.where((item) => item.connection == 'connected').length;
    final findings = model.findings
        ?.where((finding) => finding.evidenceSourceIds.any(sourceIds.contains))
        .length;
    final selection = InfrastructureSelection.infrastructure(
        infrastructure.organizationId, infrastructure.id);
    return Semantics(
      button: true,
      label: context.tr("Infrastructure {0} {1} global auswählen", [
        organization?.name ?? infrastructure.organizationId,
        infrastructure.name
      ]),
      child: ListTile(
        key: Key('unified-infrastructure-${infrastructure.id}'),
        dense: true,
        minTileHeight: 52,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(Icons.hub_outlined,
            size: 18, color: OipTokens.readableAccent(context, OipTokens.cyan)),
        title: Text(
          '${organization?.name ?? infrastructure.organizationId} / ${infrastructure.name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          context.tr(
              "{0} Sites · {1} Devices · {2} Sources · Freshness {3}/{4} · Availability {5}/{6} · Findings {7}",
              [
                sites,
                devices,
                sources.length,
                fresh,
                sources.length,
                available,
                sources.length,
                findings?.toString() ?? 'unbekannt'
              ]),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.arrow_forward, size: 16),
        onTap: () => controller.selectInfrastructure(selection),
      ),
    );
  }
}
