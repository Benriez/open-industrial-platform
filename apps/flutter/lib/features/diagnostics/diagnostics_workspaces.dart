import '../../l10n/oip_strings.dart';
import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../design_system/theme.dart';
import '../../models/contracts.dart';
import '../../widgets/components.dart';
import '../../widgets/workstation.dart';
import '../devices.dart';
import 'diagnostics_model.dart';

class DiagnosticsEventsOverview extends StatelessWidget {
  final List<DiagnosticEvent> all, filtered;
  final bool transportLive;
  const DiagnosticsEventsOverview(
      {super.key,
      required this.all,
      required this.filtered,
      required this.transportLive});

  @override
  Widget build(BuildContext context) {
    final withRecords = all.where((item) => item.recordId != null).length;
    final timestamped = all.where((item) => item.hasTimestamp).length;
    final duplicates =
        all.fold<int>(0, (sum, item) => sum + item.deliveryCount - 1);
    final kinds = all.map((item) => item.event.kind).toSet().toList()..sort();
    return WorkstationPanel(
      accent: OipTokens.cyan,
      child: ListView(children: [
        Text(context.tr("EVENTS · UNTERSUCHUNGSKONTEXT"),
            style: WorkstationTokens.eyebrow(context, color: OipTokens.cyan)),
        const SizedBox(height: 4),
        Text(context.tr("Aktuelles Evidenzfenster"),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(context.tr(
            "Entdecken, auswählen und vergleichen Sie tatsächlich gelieferte Collection-Ereignisse. Die API bietet keine vollständige historische Suche.")),
        const SizedBox(height: 14),
        KeyValueGrid(children: [
          KeyValue(context.tr("Gelieferte fachliche Records"), '${all.length}'),
          KeyValue(context.tr("Davon im lokalen Filter"), '${filtered.length}'),
          KeyValue(context.tr("Mit Source + Sequenz"), '$withRecords'),
          KeyValue(context.tr("Mit EventTimestamp"), '$timestamped'),
          KeyValue(
              context.tr("Konsolidierte Mehrfachlieferungen"), '$duplicates'),
          KeyValue(
              context.tr("UI Transport"),
              transportLive
                  ? context.tr("Live · kein Source-Health-Beweis")
                  : context.tr("Stale / Reconnecting")),
        ]),
        const Hairline(),
        PanelLabel(context.tr("Vorhandene Eventtypen"), color: OipTokens.cyan),
        if (kinds.isEmpty)
          Text(context.tr("Keine Eventtypen geliefert."))
        else
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final kind in kinds)
              Chip(
                  label: Text(
                      '${diagnosticEventTitle(kind)} · ${all.where((item) => item.event.kind == kind).length}'))
          ]),
        const Hairline(),
        WorkstationNote(
          context.tr("Observed Evidence ≠ Rule-derived Finding ≠ Hypothesis"),
          context.tr(
              "Collection-Ereignisse sind Transport-/Collection-Beobachtungen. Incidents werden separat ausgewiesen. Zeitliche Nähe erzeugt weder Korrelationsnachweis noch Ursache."),
          icon: Icons.rule_outlined,
        ),
        const SizedBox(height: 10),
        WorkstationNote(
          context.tr("Nur aktuell verfügbare Ereignisse"),
          context.tr(
              "GET /api/v1/events liefert maximal 100 aktuelle Kontrollereignisse je Source. Keine vollständige Serverhistorie, kein Replay; nach SSE-Reconnect ist Resync erforderlich."),
          icon: Icons.history_toggle_off_outlined,
          color: OipTokens.yellow,
        ),
      ]),
    );
  }
}

class DiagnosticsIncidentsWorkspace extends StatelessWidget {
  final Snapshot snapshot;
  final OipController controller;
  final bool embedded;
  const DiagnosticsIncidentsWorkspace(
      {super.key,
      required this.snapshot,
      required this.controller,
      this.embedded = false});

  @override
  Widget build(BuildContext context) {
    if (snapshot.incidents.isEmpty) {
      return WorkstationPanel(
        accent: OipTokens.violet,
        child: WorkstationNote(
          snapshot.system.simulated
              ? context.tr("Kein aktiver Demo-Vorfall")
              : context.tr("Kein aktiver Vorfall"),
          snapshot.system.demoControls
              ? context.tr(
                  "Normalbetrieb liefert bewusst keinen Incident. Es wird kein Befund für visuelle Vollständigkeit erzeugt.")
              : context.tr(
                  "Das Backend liefert aktuell keine Incidents. Collection-Ereignisse bleiben separat verfügbar."),
          icon: Icons.verified_user_outlined,
        ),
      );
    }
    final children = [
      for (final incident in snapshot.incidents)
        Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _IncidentFinding(
                incident: incident,
                snapshot: snapshot,
                controller: controller)),
    ];
    if (embedded) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }
    return ListView(children: children);
  }
}

class _IncidentFinding extends StatelessWidget {
  final Incident incident;
  final Snapshot snapshot;
  final OipController controller;
  const _IncidentFinding(
      {required this.incident,
      required this.snapshot,
      required this.controller});

  @override
  Widget build(BuildContext context) {
    final critical = snapshot.hasAlarm(deviceId: incident.deviceId);
    final tone =
        OipTokens.statusColor(context, critical ? 'alarm' : 'degraded');
    final affected = snapshot.devices
        .where((device) => device.id == incident.deviceId)
        .firstOrNull;
    return WorkstationPanel(
      accent: tone,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, runSpacing: 5, children: [
          StatusPill(
              incident.simulated
                  ? context.tr("SIMULIERTER VORFALL")
                  : context.tr("BACKEND-VORFALL"),
              color: tone,
              showDot: true),
          StatusPill(context.tr("KEINE REGEL-ID / VERSION GELIEFERT"),
              color: OipTokens.blue),
        ]),
        const SizedBox(height: 7),
        Text(incident.title, style: Theme.of(context).textTheme.titleLarge),
        Text(
            context.tr("{0} · Device {1} · ID {2}",
                [incident.category, incident.deviceId, incident.id]),
            style: WorkstationTokens.mono(context,
                size: 10.5, color: OipTokens.muted(context))),
        const SizedBox(height: 8),
        InlineNotice(
          context.tr("Korrelation ist keine bewiesene Ursache"),
          context.tr(
              "Observed Evidence, regelbasierte Befunde und Hypothesen bleiben getrennt. Dieser Incident enthält freie Evidenztexte und keine autoritative Regel-Evaluation."),
          icon: Icons.rule_outlined,
        ),
        if (affected != null)
          Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                      onPressed: () =>
                          showDevice(context, controller, affected),
                      icon: const Icon(Icons.dns_outlined, size: 17),
                      label: Text(context
                          .tr("Betroffenes Gerät: {0}", [affected.name]))))),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, box) {
          final columns = box.maxWidth > 760 ? 3 : 1;
          final width = columns == 3 ? (box.maxWidth - 16) / 3 : box.maxWidth;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(
                width: width,
                child: _EvidenceBucket(
                    title: 'Unterstützende Evidenz',
                    subtitle: incident.simulated
                        ? 'Demo-/Szenarioaussagen, nicht unabhängig verifiziert'
                        : 'Vom Backend gelieferte Aussagen',
                    icon: Icons.fact_check_outlined,
                    values: incident.supporting,
                    empty: 'Keine unterstützende Evidenz geliefert.')),
            SizedBox(
                width: width,
                child: _EvidenceBucket(
                    title: 'Widersprechende Evidenz',
                    subtitle: 'Alternative Erklärungen aktiv prüfen',
                    icon: Icons.compare_arrows_outlined,
                    values: incident.contradicting,
                    empty: 'Keine widersprechende Evidenz geliefert.',
                    tone: OipTokens.blue)),
            SizedBox(
                width: width,
                child: _EvidenceBucket(
                    title: 'Fehlende Messwerte',
                    subtitle: 'Hypothesis / Unknown',
                    icon: Icons.help_outline,
                    values: incident.missing,
                    empty: 'Keine offenen Prüfschritte geliefert.',
                    tone: OipTokens.yellow)),
          ]);
        }),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: WorkstationTokens.well(context),
              borderRadius: BorderRadius.circular(8)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr("ZEITLICHE EREIGNISKETTE"),
                style: WorkstationTokens.eyebrow(context,
                    color: OipTokens.violet)),
            Text(
                context.tr("{0} · keine realen Ereigniszeiten", [
                  incident.simulated
                      ? 'Deterministische Demo-Chronologie'
                      : 'Backend-Chronologie'
                ]),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 5),
            if (incident.timeline.isEmpty)
              Text(context.tr("Keine Chronologie geliefert."))
            else
              for (var index = 0; index < incident.timeline.length; index++)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('${index + 1}. ${incident.timeline[index]}')),
          ]),
        ),
        const SizedBox(height: 8),
        Text(
            snapshot.system.simulated
                ? context.tr("Diagnosehistorie: demo_only")
                : context.tr("Diagnosehistorie: nicht verfügbar"),
            style: WorkstationTokens.mono(context,
                size: 10.5, color: OipTokens.yellow)),
        Text(
            context.tr(
                "Kein persistierter Diagnoselauf, keine Regelversion und keine strukturierten Evidenzreferenzen. Keine Flutter-Rekonstruktion als Core-Befund."),
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

class _EvidenceBucket extends StatelessWidget {
  final String title, subtitle, empty;
  final IconData icon;
  final List<String> values;
  final Color? tone;
  const _EvidenceBucket(
      {required this.title,
      required this.subtitle,
      required this.icon,
      required this.values,
      required this.empty,
      this.tone});
  @override
  Widget build(BuildContext context) {
    final color = OipTokens.readableAccent(context, tone ?? OipTokens.cyan);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: WorkstationTokens.well(context),
          border: Border.all(color: WorkstationTokens.hairline(context)),
          borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleSmall))
        ]),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 7),
        if (values.isEmpty)
          Text(empty)
        else
          for (final value in values)
            Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('· ', style: TextStyle(color: color)),
                      Expanded(
                          child: Text(value,
                              style: Theme.of(context).textTheme.bodySmall))
                    ])),
      ]),
    );
  }
}

class DiagnosticsCollectionHealth extends StatelessWidget {
  final List<SourceInfo> sources;
  final Object? sourcesError;
  final List<DiagnosticEvent> events;
  final bool transportLive;
  final ValueChanged<DiagnosticEvent> onSelect;
  const DiagnosticsCollectionHealth(
      {super.key,
      required this.sources,
      required this.sourcesError,
      required this.events,
      required this.transportLive,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final gapEvents = events.where((item) => item.hasGapBounds).toList();
    return WorkstationPanel(
      accent: OipTokens.cyan,
      child: ListView(children: [
        Text(context.tr("COLLECTION HEALTH"),
            style: WorkstationTokens.eyebrow(context, color: OipTokens.cyan)),
        const SizedBox(height: 3),
        Text(context.tr("Source-Diagnostik & dokumentierte Datenlücken"),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 5),
        Text(
            context.tr(
                "Aktuelle Source-Datensätze + {0} geladene Kontrollereignisse. Keine Source-Health-Historie.",
                [events.length]),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        if (!transportLive)
          Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: WorkstationNote(
                  context.tr("UI-Transport nicht live"),
                  context.tr(
                      "Letzte Source-Werte können veraltet sein. UI-Reconnect, Source-Reconnect und frische Messwerte sind verschiedene Zustände."),
                  color: OipTokens.yellow)),
        if (sourcesError != null)
          WorkstationNote(
              context.tr("Source-Zustände nicht verfügbar"),
              context.tr(
                  "Die bestehende Source-API konnte nicht gelesen werden. Geladene Events bleiben separat und werden nicht als aktueller Gesundheitszustand interpretiert."),
              color: OipTokens.red)
        else if (sources.isEmpty)
          WorkstationNote(
              context.tr("Keine Source-Datensätze"),
              context.tr(
                  "Die API liefert keine Sources; daraus folgt kein Fehlerzustand und keine vollständige Abdeckung."))
        else
          for (final source in sources)
            _SourceHealthCard(
                source: source,
                events: events
                    .where((item) => item.event.sourceId == source.id)
                    .toList()),
        const Hairline(),
        PanelLabel(context.tr("DATA GAP INSPECTOR · GELADENES FENSTER"),
            color: OipTokens.yellow),
        if (gapEvents.isEmpty)
          Text(context.tr(
              "Keine Gap-Datensätze im geladenen Fenster. Das beweist keine lückenlose Historie."))
        else
          for (final item in gapEvents)
            Card(
              key: Key('collection-gap-${item.key}'),
              child: ListTile(
                title: Text(
                    '${diagnosticEventTitle(item.event.kind)} · ${item.sourceLabel}'),
                subtitle: Text(context.tr("Beginn {0}\nEnde {1}\n{2}", [
                  timestamp(item.event.gapStartedMs),
                  timestamp(item.event.gapEndedMs),
                  item.event.gapMs == null
                      ? 'Dauer unbekannt / inkonsistent / nicht bestimmbar'
                      : 'Dokumentierte Dauer ${item.event.gapMs} ms'
                ])),
                trailing: const Icon(Icons.open_in_new, size: 17),
                onTap: () => onSelect(item),
              ),
            ),
        const SizedBox(height: 8),
        WorkstationNote(
            context.tr("Null-Dauer und Recovery"),
            context.tr(
                "0 ms ist ein dokumentierter Wert, kein Beweis für fehlende Unterbrechung. Reconnected bedeutet nicht, dass alle Messwerte frisch oder Lücken geschlossen sind. Gap-Gründe sind im aktuellen Flutter-DTO nicht verfügbar."),
            icon: Icons.info_outline,
            color: OipTokens.yellow),
      ]),
    );
  }
}

class _SourceHealthCard extends StatelessWidget {
  final SourceInfo source;
  final List<DiagnosticEvent> events;
  const _SourceHealthCard({required this.source, required this.events});
  @override
  Widget build(BuildContext context) {
    final reconnects =
        events.where((item) => item.event.kind == 'Reconnected').length;
    final losses =
        events.where((item) => item.event.kind == 'ConnectionLost').length;
    final gaps = events.where((item) => item.hasGapBounds).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
          color: WorkstationTokens.well(context),
          border: Border.all(color: WorkstationTokens.hairline(context)),
          borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.sensors_outlined,
              size: 18,
              color: OipTokens.statusColor(context, source.connection)),
          const SizedBox(width: 7),
          Expanded(
              child: Text(source.name,
                  style: Theme.of(context).textTheme.titleSmall)),
          Text(source.id, style: WorkstationTokens.mono(context, size: 10))
        ]),
        const SizedBox(height: 6),
        KeyValueGrid(children: [
          KeyValue(context.tr("Reachability"),
              context.tr(known(source.reachability))),
          KeyValue(
              context.tr("Connection"), context.tr(known(source.connection))),
          KeyValue(context.tr("Service"), context.tr(known(source.service))),
          KeyValue(context.tr("Freshness / Validity"),
              '${known(source.freshness)} / ${known(source.validity)}'),
          KeyValue(
              context.tr("Letzter Empfang"), timestamp(source.lastReceivedMs)),
          KeyValue(context.tr("Collection Error"),
              source.lastError ?? context.tr("Nicht geliefert")),
        ]),
        Text(
            context.tr(
                "Im geladenen Eventfenster: {0} Verbindungsverluste · {1} Reconnects · {2} Gap-Datensätze",
                [losses, reconnects, gaps]),
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

class DiagnosticsCompareWorkspace extends StatelessWidget {
  final List<DiagnosticEvent> events;
  final ValueChanged<DiagnosticEvent> onRemove, onSelect;
  final VoidCallback onClear;
  const DiagnosticsCompareWorkspace(
      {super.key,
      required this.events,
      required this.onRemove,
      required this.onSelect,
      required this.onClear});

  @override
  Widget build(BuildContext context) {
    return WorkstationPanel(
      accent: OipTokens.violet,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(context.tr("INVESTIGATION · COMPARE"),
                    style: WorkstationTokens.eyebrow(context,
                        color: OipTokens.violet)),
                Text(
                    context.tr(
                        "{0}/4 Ereignisse · session-lokal", [events.length]),
                    style: Theme.of(context).textTheme.titleMedium)
              ])),
          TextButton(
              onPressed: events.isEmpty ? null : onClear,
              child: Text(context.tr("Vergleich schließen"))),
        ]),
        Text(context.tr(
            "Unabhängige EventTimestamps und Quellen. Keine Synchronisation, Interpolation, Incident-ID oder Kausalbehauptung.")),
        const SizedBox(height: 8),
        Expanded(
          child: events.isEmpty
              ? Center(
                  child: WorkstationNote(
                      context.tr("Keine Ereignisse im Vergleich"),
                      context.tr(
                          "Im Explorer oder Inspector C beziehungsweise Compare wählen. Maximal vier; keine dauerhafte Investigation-API."),
                      icon: Icons.compare_arrows_outlined))
              : ListView.separated(
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = events[index];
                    final event = item.event;
                    return Container(
                      key: Key('compare-event-${item.key}'),
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                          color: WorkstationTokens.well(context),
                          border: Border.all(
                              color: WorkstationTokens.hairline(context)),
                          borderRadius: BorderRadius.circular(8)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: InkWell(
                                      onTap: () => onSelect(item),
                                      child: Text(
                                          '${index + 1} · ${diagnosticEventTitle(event.kind)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall))),
                              IconButton(
                                  tooltip: context.tr("Aus Compare entfernen"),
                                  onPressed: () => onRemove(item),
                                  icon: const Icon(Icons.close, size: 17))
                            ]),
                            KeyValueGrid(children: [
                              KeyValue(
                                  context.tr("Event ID"),
                                  item.recordId ??
                                      context.tr("Nicht geliefert")),
                              KeyValue(context.tr("Source"), item.sourceLabel),
                              KeyValue(context.tr("Type"), event.kind),
                              KeyValue(context.tr("Timestamp"),
                                  timestamp(event.atMs)),
                              KeyValue(context.tr("Severity"),
                                  context.tr("Nicht geliefert")),
                              KeyValue(
                                  context.tr("Provenance"),
                                  context.tr(
                                      "Empfangenes API-Collection-Ereignis")),
                              KeyValue(context.tr("Collection State"),
                                  context.tr(_compareState(event.kind))),
                              KeyValue(
                                  context.tr("Data Gap"),
                                  event.gapMs == null
                                      ? item.hasGapBounds
                                          ? context.tr(
                                              "Vorhanden; Dauer unbekannt/inkonsistent")
                                          : context.tr("Kein Gap-Datensatz")
                                      : context.tr("{0} ms", [event.gapMs])),
                              KeyValue(
                                  context.tr("Evidence"),
                                  event.reason ??
                                      event.dropped?.toString() ??
                                      context.tr(
                                          "Keine zusätzliche Reason/Dropped-Evidenz")),
                            ]),
                          ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

String _compareState(String kind) => switch (kind) {
      'ConnectionLost' => 'Connection Lost gemeldet',
      'Reconnected' => 'Reconnect gemeldet',
      'SubscriptionError' => 'Subscription Error gemeldet',
      'DataLoss' => 'Data Loss gemeldet',
      _ => 'Unbekannt',
    };
