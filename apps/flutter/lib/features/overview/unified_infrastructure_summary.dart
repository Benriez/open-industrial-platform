import '../../l10n/oip_strings.dart';
import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import '../../models/infrastructure.dart';
import '../../widgets/workstation.dart';

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
        sources.where((source) => source.connection == 'connected').length;
    final observedDevices = {
      for (final observation in snapshot.metrics)
        (observation.sourceId, observation.entityId),
    };
    final covered = snapshot.devices
        .where(
            (device) => observedDevices.contains((device.sourceId, device.id)))
        .length;
    final collectionProblems = snapshot.recentEvents
        .where((event) =>
            event.kind == 'DataLoss' ||
            event.kind == 'SubscriptionError' ||
            event.gapStartedMs != null)
        .length;

    return WorkstationPanel(
      key: const Key('unified-infrastructure-summary'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          header: true,
          child: Text(context.tr("Infrastrukturübersicht"),
              style: Theme.of(context).textTheme.titleMedium),
        ),
        if (hierarchy.infrastructures.isEmpty) ...[
          const SizedBox(height: OipTokens.s2),
          Text(context
              .tr("In diesem Kontext sind keine Infrastrukturen verfügbar.")),
          const SizedBox(height: OipTokens.s2),
        ] else ...[
          const SizedBox(height: OipTokens.s3),
          _SummaryFacts(
            prominent: true,
            facts: [
              (context.tr("Geräte"), '${snapshot.devices.length}'),
              (
                context.tr("Verbundene Quellen"),
                context.tr("{0} von {1}", [connected, sources.length]),
              ),
              (
                context.tr("Geräte mit Messwerten"),
                context.tr("{0} von {1}", [covered, snapshot.devices.length]),
              ),
            ],
          ),
          const Hairline(vertical: OipTokens.s2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: ListView.separated(
              primary: false,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: hierarchy.infrastructures.length,
              separatorBuilder: (_, __) => const Hairline(vertical: 0),
              itemBuilder: (context, index) =>
                  _infrastructureRow(context, hierarchy.infrastructures[index]),
            ),
          ),
        ],
        const Hairline(vertical: 0),
        ExpansionTile(
          key: const Key('unified-infrastructure-details'),
          tilePadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(context.tr("Weitere Kennzahlen"),
              style: Theme.of(context).textTheme.bodyMedium),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          childrenPadding: const EdgeInsets.only(bottom: OipTokens.s3),
          children: [
            _SummaryFacts(facts: [
              (
                context.tr("Organisationen"),
                '${hierarchy.organizations.length}'
              ),
              (
                context.tr("Infrastrukturen"),
                '${hierarchy.infrastructures.length}'
              ),
              (context.tr("Standorte"), '${hierarchy.sites.length}'),
              (
                context.tr("Quellen ohne aktuelle Daten"),
                '${sources.where((source) => source.freshness != 'fresh').length}',
              ),
              (
                context.tr("Befunde"),
                model.findings?.length.toString() ??
                    context.tr("Nicht verfügbar"),
              ),
              (
                context.tr("Probleme bei der Datenerfassung"),
                '$collectionProblems'
              ),
            ]),
            const SizedBox(height: OipTokens.s2),
            Text(
              context.tr(
                  "Bei unbekanntem Status ist offen, ob die Quelle offline ist. Fehlende Datenerfassung sagt nichts über die Verbindung aus."),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ]),
    );
  }

  Widget _infrastructureRow(
      BuildContext context, AuthorizedInfrastructure infrastructure) {
    final organization =
        model.hierarchy.organization(infrastructure.organizationId);
    final organizationName =
        organization?.name ?? infrastructure.organizationId;
    final sites = model.hierarchy.sites
        .where((item) => item.infrastructureId == infrastructure.id)
        .length;
    final devices = snapshot.devices
        .where((device) =>
            model.devicePlacement(device)?.infrastructureId ==
            infrastructure.id)
        .length;
    final sourceIds = model.hierarchy.locations
        .where((item) => item.infrastructureId == infrastructure.id)
        .map((item) => item.sourceId)
        .toSet();
    final sources =
        snapshot.sources.where((source) => sourceIds.contains(source.id));
    final connected =
        sources.where((source) => source.connection == 'connected').length;
    final selection = InfrastructureSelection.infrastructure(
        infrastructure.organizationId, infrastructure.id);

    return Semantics(
      button: true,
      label: context.tr("Infrastructure {0} {1} global auswählen",
          [organizationName, infrastructure.name]),
      child: ListTile(
        key: Key('unified-infrastructure-${infrastructure.id}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        leading: Icon(Icons.hub_outlined,
            color: OipTokens.readableAccent(context, OipTokens.cyan)),
        title: Text(infrastructure.name,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(organizationName,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Wrap(spacing: 14, runSpacing: 2, children: [
              Text(context.tr("Standorte {0}", [sites])),
              Text(context.tr("Geräte {0}", [devices])),
              Text(context.tr(
                  "Quellen verbunden {0}/{1}", [connected, sources.length])),
            ]),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => controller.selectInfrastructure(selection),
      ),
    );
  }
}

class _SummaryFacts extends StatelessWidget {
  const _SummaryFacts({required this.facts, this.prominent = false});

  final List<(String, String)> facts;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final valueStyle = prominent ? text.titleLarge : text.titleSmall;
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 480 ? 3 : 1;
      final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: prominent ? 6 : 12,
        children: [
          for (final (label, value) in facts)
            SizedBox(
              width: width,
              child: Semantics(
                label: '$label: $value',
                excludeSemantics: true,
                child: columns == 1
                    ? Row(children: [
                        Expanded(child: Text(label, style: text.bodySmall)),
                        const SizedBox(width: 12),
                        Text(value, style: valueStyle),
                      ])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(value, style: valueStyle),
                          Text(label, style: text.bodySmall),
                        ],
                      ),
              ),
            ),
        ],
      );
    });
  }
}
