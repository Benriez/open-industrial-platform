import 'package:flutter/material.dart';
import '../app/controller.dart';
import '../design_system/theme.dart';
import '../models/contracts.dart';
import '../services/api.dart';
import '../widgets/components.dart';
import 'devices.dart';

const scenarios = {
  'normal': 'Normalbetrieb',
  'gpu': 'Hohe GPU-Last',
  'inference': 'Langsame Inferenz',
  'vpn': 'VPN-Störung',
  'sensor': 'Sensoralarm',
  'agent': 'Remote-Agent fehlt',
  'offline': 'Offline & Reconnect'
};

class DiagnosticsPage extends StatefulWidget {
  final OipController controller;
  const DiagnosticsPage(this.controller, {super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  List<CollectionEvent>? events;
  Object? eventsError;
  int generation = 0;
  bool showTimeline = true;
  String? selectedEventId;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final current = ++generation;
    try {
      final result = await widget.controller.api.collectionEvents();
      if (!mounted || current != generation) return;
      setState(() {
        events = result;
        eventsError = null;
      });
    } catch (error) {
      if (!mounted || current != generation) return;
      setState(() => eventsError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.snapshot!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('Diagnose & Ereignisse',
            'Deterministische Regeln · keine KI und keine unbelegte Kausalität',
            accent: OipTokens.yellow,
            action: IconButton(
              tooltip: 'Diagnosedaten aktualisieren',
              onPressed: _loadEvents,
              icon: const Icon(Icons.refresh),
            )),
        Wrap(
          spacing: OipTokens.s2,
          runSpacing: OipTokens.s2,
          children: scenarios.entries
              .map((entry) => ChoiceChip(
                    key: Key('scenario-${entry.key}'),
                    label: Text(entry.value),
                    materialTapTargetSize:
                        MediaQuery.sizeOf(context).width < OipTokens.mobile
                            ? MaterialTapTargetSize.padded
                            : MaterialTapTargetSize.shrinkWrap,
                    selected: snapshot.system.scenario == entry.key,
                    onSelected: !snapshot.system.demoControls ||
                            widget.controller.scenarioBusy
                        ? null
                        : (_) async {
                            await widget.controller.setScenario(entry.key);
                            await _loadEvents();
                          },
                  ))
              .toList(),
        ),
        const SizedBox(height: OipTokens.s5),
        if (events != null && events!.isNotEmpty)
          SectionContainer(
            title: 'Evidence Timeline',
            subtitle:
                'Nur zeitgestempelte Collection-Ereignisse · zeitliche Nähe beweist keine Ursache',
            accent: OipTokens.yellow,
            icon: Icons.timeline_outlined,
            action: TextButton.icon(
              onPressed: () => setState(() {
                showTimeline = !showTimeline;
                if (!showTimeline) selectedEventId = null;
              }),
              icon: Icon(showTimeline
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              label: Text(showTimeline ? 'Spuren ausblenden' : 'Spuren zeigen'),
            ),
            child: showTimeline
                ? _timelineWorkspace(context)
                : const InlineNotice(
                    'Klassische Ereignisliste aktiv',
                    'Alle Collection-Ereignisse bleiben unterhalb vollständig bedienbar.',
                    icon: Icons.list_alt_outlined,
                  ),
          ),
        if (events != null && events!.isNotEmpty)
          const SizedBox(height: OipTokens.s5),
        if (snapshot.incidents.isEmpty)
          StateMessage(
            snapshot.system.simulated
                ? 'Kein aktiver Demo-Vorfall'
                : 'Kein aktiver Vorfall',
            snapshot.system.demoControls
                ? 'Ein Szenario auswählen, um Evidenz und offene Fragen zu untersuchen.'
                : 'Das Backend liefert aktuell keine Incidents. Collection-Ereignisse bleiben separat verfügbar.',
            icon: Icons.verified_user_outlined,
          ),
        ...snapshot.incidents.map((incident) => _incident(context, incident,
            snapshot, snapshot.hasAlarm(deviceId: incident.deviceId))),
        const SizedBox(height: OipTokens.s6),
        Panel(
          accent: OipTokens.blue,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle('Collection-Ereignisse',
                  'Verbindungsverluste, Reconnects und dokumentierte Datenlücken aus GET /api/v1/events',
                  action: StatusPill('GETRENNT VON DER DIAGNOSE',
                      color: OipTokens.statusColor(context, 'info'))),
              if (eventsError != null)
                StateMessage(
                  'Collection-Ereignisse nicht verfügbar',
                  apiErrorMessage(
                    eventsError!,
                    'Collection-Ereignisse konnten nicht geladen werden.',
                  ),
                  compact: true,
                  action: TextButton(
                      onPressed: _loadEvents,
                      child: const Text('Erneut laden')),
                )
              else if (events == null)
                const Padding(
                  padding: EdgeInsets.all(OipTokens.s6),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (events!.isEmpty)
                const InlineNotice(
                  'Keine Collection-Ereignisse geliefert',
                  'Das bedeutet nur, dass die API aktuell keine Einträge zurückgibt; es ist kein Nachweis einer lückenlosen Historie.',
                )
              else
                ...events!.map((event) => _CollectionEventRow(event: event)),
            ],
          ),
        ),
        const SizedBox(height: OipTokens.s4),
        InlineNotice(
          'Diagnosehistorie: demo_only',
          'Noch kein persistierter Diagnoselauf. Die aktuellen ${snapshot.system.simulated ? 'Demo-' : ''}Befunde werden vom Rust-Backend erzeugt. Collection-Ereignisse werden separat dargestellt und nicht als Ursache interpretiert.',
          icon: Icons.history_edu_outlined,
          color: OipTokens.statusColor(context, 'degraded'),
        ),
      ],
    );
  }

  String _eventId(CollectionEvent event) =>
      '${event.sourceId ?? 'collection'}-${event.sequence ?? event.atMs ?? 0}-${event.kind}';

  String _eventTitle(String kind) => switch (kind) {
        'ConnectionLost' => 'Verbindung verloren',
        'Reconnected' => 'Verbindung wiederhergestellt',
        'SubscriptionError' => 'Subscription-Fehler',
        'DataLoss' => 'Datenverlust gemeldet',
        _ => 'Unbekanntes Collection-Ereignis',
      };

  List<SpectrumTimelineEntry> _timelineEntries(BuildContext context) => events!
      .map((event) => SpectrumTimelineEntry(
            id: _eventId(event),
            track: 'Telemetry',
            label: _eventTitle(event.kind),
            detail: event.reason ?? 'Kein Grund vom API-Ereignis geliefert',
            atMs: event.atMs,
            color: OipTokens.statusColor(
              context,
              event.kind == 'ConnectionLost'
                  ? 'alarm'
                  : event.kind == 'Reconnected'
                      ? 'connected'
                      : 'degraded',
            ),
          ))
      .toList();

  Widget _timelineWorkspace(BuildContext context) {
    final entries = _timelineEntries(context);
    final selectedEntry =
        entries.where((entry) => entry.id == selectedEventId).firstOrNull;
    final selectedEvent = events
        ?.where((event) => _eventId(event) == selectedEventId)
        .firstOrNull;
    final timeline = DataTimeline(
      entries: entries,
      selectedId: selectedEventId,
      onSelected: (entry) => setState(() => selectedEventId = entry.id),
    );
    final inspector = selectedEntry == null || selectedEvent == null
        ? const InlineNotice(
            'Ereignis auswählen',
            'Die farbigen Clips öffnen Quelle, Zeitpunkt, Grund und dokumentierte Datenlücke.',
            icon: Icons.touch_app_outlined,
            color: OipTokens.yellow,
          )
        : GradientCard(
            accent: selectedEntry.color,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccentHeader(
                  selectedEntry.label,
                  'COLLECTION EVENT · KEINE KAUSALBEHAUPTUNG',
                  accent: selectedEntry.color,
                ),
                Fact('Zeitpunkt', timestamp(selectedEvent.atMs)),
                Fact('Quelle', selectedEvent.sourceId ?? 'Unbekannt'),
                Fact('Sequenz',
                    selectedEvent.sequence?.toString() ?? 'Unbekannt'),
                Fact('Grund', selectedEvent.reason ?? 'Nicht geliefert'),
                Fact(
                    'Dokumentierte Lücke',
                    selectedEvent.gapMs == null
                        ? 'Unbekannt / nicht zutreffend'
                        : '${selectedEvent.gapMs} ms'),
              ],
            ),
          );
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= OipTokens.desktop) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: timeline),
          const SizedBox(width: OipTokens.s4),
          Expanded(flex: 2, child: inspector),
        ]);
      }
      return Column(children: [
        timeline,
        const SizedBox(height: OipTokens.s3),
        inspector,
      ]);
    });
  }

  Widget _incident(BuildContext context, Incident incident, Snapshot snapshot,
      bool critical) {
    final tone = critical
        ? OipTokens.statusColor(context, 'alarm')
        : OipTokens.statusColor(context, 'degraded');
    final affected = snapshot.devices
        .where((device) => device.id == incident.deviceId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(OipTokens.s6),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              tone.withOpacity(.13),
              Theme.of(context).colorScheme.surface,
            ]),
            border: Border.all(color: tone.withOpacity(.45)),
            borderRadius: BorderRadius.circular(OipTokens.radius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: tone.withOpacity(.12),
                      borderRadius: BorderRadius.circular(OipTokens.radius),
                    ),
                    child: Icon(
                        critical
                            ? Icons.emergency_outlined
                            : Icons.troubleshoot_outlined,
                        color: tone,
                        size: 28),
                  ),
                  const SizedBox(width: OipTokens.s4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusPill(
                            incident.simulated
                                ? 'SIMULIERTER VORFALL'
                                : 'BACKEND-VORFALL',
                            color: tone,
                            showDot: true),
                        const SizedBox(height: OipTokens.s3),
                        Text(incident.title,
                            style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: OipTokens.s2),
                        Text('${incident.category} / ${incident.deviceId}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: OipTokens.s4),
              InlineNotice(
                'Korrelation ist keine bewiesene Ursache',
                'Diese Beobachtungen grenzen Hypothesen ein. Eine Ursache ist damit nicht nachgewiesen. Widersprüche und fehlende Informationen bleiben gleichrangig sichtbar.',
                icon: Icons.rule_outlined,
                color: tone,
              ),
              if (affected != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: OipTokens.s3),
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          showDevice(context, widget.controller, affected),
                      icon: const Icon(Icons.dns_outlined, size: 17),
                      label: Text('Betroffenes Gerät: ${affected.name}'),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: OipTokens.s4),
        ResponsiveGrid(
          minWidth: 285,
          maxColumns: 3,
          children: [
            _EvidencePanel(
              title: 'Unterstützende Evidenz',
              subtitle: 'Beobachtungen und ihre Aussagegrenze',
              icon: Icons.fact_check_outlined,
              values: incident.supporting,
              empty: 'Keine unterstützende Evidenz geliefert.',
            ),
            _EvidencePanel(
              title: 'Widersprechende Evidenz',
              subtitle: 'Alternative Erklärungen aktiv prüfen',
              icon: Icons.compare_arrows_outlined,
              values: incident.contradicting,
              empty: 'Keine widersprechende Evidenz geliefert.',
              tone: OipTokens.statusColor(context, 'info'),
            ),
            _EvidencePanel(
              title: 'Fehlende Messwerte',
              subtitle: 'Unbekannt bleibt unbekannt',
              icon: Icons.help_outline,
              values: incident.missing,
              empty: 'Keine offenen Prüfschritte geliefert.',
              tone: OipTokens.statusColor(context, 'degraded'),
            ),
          ],
        ),
        const SizedBox(height: OipTokens.s4),
        Panel(
          accent: OipTokens.violet,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle('Zeitliche Ereigniskette',
                  '${incident.simulated ? 'Deterministische Demo-Chronologie' : 'Backend-Chronologie'} · keine realen Ereigniszeiten'),
              if (incident.timeline.isEmpty)
                const Text('Keine Chronologie geliefert.')
              else
                ...incident.timeline.asMap().entries.map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: OipTokens.s3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(.12),
                            child: Text('${entry.key + 1}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        Theme.of(context).colorScheme.primary)),
                          ),
                          const SizedBox(width: OipTokens.s3),
                          Expanded(child: Text(entry.value)),
                        ],
                      ),
                    )),
            ],
          ),
        ),
        const SizedBox(height: OipTokens.s4),
      ],
    );
  }
}

class _EvidencePanel extends StatelessWidget {
  final String title, subtitle, empty;
  final IconData icon;
  final List<String> values;
  final Color? tone;
  const _EvidencePanel({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.values,
    required this.empty,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final color = tone ?? Theme.of(context).colorScheme.primary;
    return Panel(
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: OipTokens.s2),
            Expanded(
                child:
                    Text(title, style: Theme.of(context).textTheme.titleSmall)),
          ]),
          const SizedBox(height: OipTokens.s1),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: OipTokens.s3),
          if (values.isEmpty)
            Text(empty, style: Theme.of(context).textTheme.bodySmall)
          else
            ...values.map((value) => Padding(
                  padding: const EdgeInsets.only(bottom: OipTokens.s3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle)),
                      ),
                      const SizedBox(width: OipTokens.s2),
                      Expanded(
                          child: Text(value,
                              style: Theme.of(context).textTheme.bodyMedium)),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class _CollectionEventRow extends StatelessWidget {
  final CollectionEvent event;
  const _CollectionEventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final lost = event.kind == 'ConnectionLost';
    final reconnected = event.kind == 'Reconnected';
    final tone = lost
        ? OipTokens.statusColor(context, 'alarm')
        : reconnected
            ? Theme.of(context).colorScheme.primary
            : OipTokens.statusColor(context, 'degraded');
    final title = switch (event.kind) {
      'ConnectionLost' => 'Verbindung verloren',
      'Reconnected' => 'Verbindung wiederhergestellt',
      'SubscriptionError' => 'Subscription-Fehler',
      'DataLoss' => 'Datenverlust gemeldet',
      _ => 'Unbekanntes Collection-Ereignis',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: OipTokens.s2),
      padding: const EdgeInsets.all(OipTokens.s3),
      decoration: BoxDecoration(
        color: OipTokens.subtleSurface(context),
        borderRadius: BorderRadius.circular(OipTokens.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(lost ? Icons.link_off : Icons.link, size: 19, color: tone),
          const SizedBox(width: OipTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: OipTokens.s1),
                if (event.sourceId != null)
                  Text('Quelle: ${event.sourceId}',
                      style: Theme.of(context).textTheme.bodySmall),
                if (event.dropped != null)
                  Text('${event.dropped} Samples verloren · Zeitraum unbekannt',
                      style: Theme.of(context).textTheme.bodySmall),
                Text(timestamp(event.atMs),
                    style: Theme.of(context).textTheme.bodySmall),
                if (event.reason != null)
                  Text(event.reason!,
                      style: Theme.of(context).textTheme.bodySmall),
                if (event.gapMs != null)
                  Text('Dokumentierte Lücke: ${event.gapMs} ms',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: tone)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
