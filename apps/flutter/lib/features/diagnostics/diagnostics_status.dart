import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../design_system/theme.dart';
import '../../l10n/oip_strings.dart';
import '../../models/contracts.dart';
import '../../widgets/workstation.dart';
import '../devices.dart';
import 'diagnostics_model.dart';
import 'support_package.dart';

enum _SourceState {
  unreachable,
  disconnected,
  invalid,
  stale,
  degraded,
  unknown,
  current;

  static _SourceState fromSource(SourceInfo source) {
    if (source.reachability == 'unreachable') return unreachable;
    if (source.connection == 'disconnected') return disconnected;
    if (source.validity == 'invalid') return invalid;
    if (source.freshness == 'stale') return stale;
    if (source.service == 'degraded') return degraded;
    if (source.connection == 'connected' &&
        source.freshness == 'fresh' &&
        source.validity == 'valid') {
      return current;
    }
    return unknown;
  }

  String get title => switch (this) {
        unreachable => 'Quelle nicht erreichbar',
        disconnected => 'Verbindung getrennt',
        invalid => 'Ungültige Messwerte gemeldet',
        stale => 'Messwerte sind veraltet',
        degraded => 'Datenerfassung eingeschränkt',
        unknown => 'Status noch unbekannt',
        current => 'Verbindung und Messwerte aktuell',
      };

  String get nextStep => switch (this) {
        unreachable =>
          'Prüfe, ob das Gerät eingeschaltet und mit dem Netzwerk verbunden ist.',
        disconnected => 'Öffne das Gerät und prüfe seine Verbindung.',
        invalid =>
          'Öffne das Gerät und vergleiche die Messwerte mit der Anzeige am Gerät.',
        stale =>
          'Prüfe am Gerät, ob die Überwachung eingeschaltet ist und neue Werte eintreffen.',
        degraded =>
          'Prüfe die Überwachung am Gerät und sieh dir die letzten Ereignisse an.',
        unknown =>
          'Öffne das Gerät, um seine Verbindung und Überwachung zu prüfen.',
        current => '',
      };
}

class DiagnosticsStatus extends StatelessWidget {
  const DiagnosticsStatus({
    super.key,
    required this.controller,
    required this.sources,
    required this.sourcesLoading,
    required this.sourcesFailed,
    required this.onRefresh,
    required this.onTechnicalView,
  });

  final OipController controller;
  final List<SourceInfo> sources;
  final bool sourcesLoading, sourcesFailed;
  final VoidCallback? onRefresh;
  final VoidCallback onTechnicalView;

  @override
  Widget build(BuildContext context) {
    final bySource = {
      for (final source in [...controller.operationalSources, ...sources])
        source.id: source,
    };
    final devices = <String, List<Device>>{};
    for (final device in controller.snapshot!.devices) {
      for (final sourceId in _deviceSources(device)) {
        (devices[sourceId] ??= []).add(device);
      }
    }
    final events = filterDiagnosticEvents(
      diagnosticEventsFromApi(controller.operationalEvents),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkstationPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(context.tr('Aktueller Zustand'),
                      style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                    tooltip: context.tr('Zustand aktualisieren'),
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                  ),
                  SupportPackageButton(controller),
                ],
              ),
              _status(context, devices),
            ],
          ),
        ),
        const SizedBox(height: OipTokens.s3),
        WorkstationPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(context.tr('Letzte Ereignisse'),
                      style: Theme.of(context).textTheme.titleLarge),
                  TextButton.icon(
                    key: const Key('diagnostics-show-technical'),
                    onPressed: onTechnicalView,
                    icon: const Icon(Icons.tune_outlined, size: 17),
                    label: Text(context.tr('Technische Ansicht')),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (controller.connection != 'live')
                Text(context.tr(
                    'Keine Live-Verbindung. Der Ereignisstand kann veraltet sein.')),
              if (events.isEmpty && controller.connection == 'live')
                Text(context.tr(
                    'Für die gewählte Infrastruktur sind keine kürzlichen Ereignisse verfügbar.')),
              for (final item in events.take(5)) ...[
                const Hairline(),
                _eventRow(context, item, bySource, devices),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _status(BuildContext context, Map<String, List<Device>> devices) {
    if (sourcesLoading && sources.isEmpty) {
      return Text(context.tr('Der aktuelle Zustand wird abgefragt.'));
    }
    if (sourcesFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('Der aktuelle Zustand konnte nicht geladen werden.')),
          TextButton(
            onPressed: onRefresh,
            child: Text(context.tr('Erneut laden')),
          ),
        ],
      );
    }
    if (sources.isEmpty) {
      return Text(context.tr(
          'Für die gewählte Infrastruktur sind keine Datenquellen verfügbar.'));
    }
    final entries = sources
        .map((source) => (source, _SourceState.fromSource(source)))
        .toList()
      ..sort((a, b) {
        final byState = a.$2.index.compareTo(b.$2.index);
        return byState != 0 ? byState : a.$1.name.compareTo(b.$1.name);
      });
    final needsAttention = entries
        .where((item) =>
            item.$2 != _SourceState.current && item.$2 != _SourceState.unknown)
        .toList();
    final unknown =
        entries.where((item) => item.$2 == _SourceState.unknown).toList();
    final currentCount =
        sources.length - needsAttention.length - unknown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(
              '{0} von {1} Quellen sind verbunden und liefern aktuelle Messwerte.',
              [currentCount, sources.length]),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (needsAttention.isNotEmpty) ...[
          const Hairline(),
          Text(context.tr('Jetzt prüfen'),
              style: Theme.of(context).textTheme.titleMedium),
          for (final (source, state) in needsAttention.take(5))
            _sourceRow(context, source, state, devices[source.id] ?? const []),
          if (needsAttention.length > 5)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(context.tr(
                  'Weitere Quellen prüfen ({0})', [needsAttention.length - 5])),
              children: [
                for (final (source, state) in needsAttention.skip(5))
                  _sourceRow(
                      context, source, state, devices[source.id] ?? const []),
              ],
            ),
        ],
        if (unknown.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(context.tr('Status unbekannt ({0})', [unknown.length])),
            children: [
              for (final (source, state) in unknown)
                _sourceRow(
                    context, source, state, devices[source.id] ?? const []),
            ],
          ),
      ],
    );
  }

  Widget _sourceRow(BuildContext context, SourceInfo source, _SourceState state,
      List<Device> devices) {
    final device = devices.length == 1 ? devices.single : null;
    final step = device != null
        ? state.nextStep
        : 'Prüfe die Verbindung und Überwachung der Geräte an dieser Quelle.';
    final received = source.lastReceivedMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            state == _SourceState.unknown
                ? Icons.help_outline
                : Icons.info_outline,
            color: state == _SourceState.unknown
                ? null
                : OipTokens.statusColor(context, 'degraded'),
          ),
          title: Text(
              '${device?.name ?? source.name} · ${context.tr(state.title)}'),
          subtitle: Text([
            context.tr(step),
            if (received != null)
              context
                  .tr('Letzter Messwert: {0}', [_eventTime(context, received)]),
          ].join('\n')),
          trailing: device == null ? null : const Icon(Icons.chevron_right),
          onTap: device == null
              ? null
              : () => showDevice(context, controller, device),
        ),
        if (devices.length > 1)
          Wrap(
            children: [
              for (final device in devices)
                TextButton(
                  onPressed: () => showDevice(context, controller, device),
                  child: Text(device.name),
                ),
            ],
          ),
      ],
    );
  }

  Widget _eventRow(
    BuildContext context,
    DiagnosticEvent item,
    Map<String, SourceInfo> sources,
    Map<String, List<Device>> devices,
  ) {
    final affected = devices[item.sourceId] ?? const <Device>[];
    final device = affected.length == 1 ? affected.single : null;
    final source = device?.name ??
        sources[item.sourceId]?.name ??
        context.tr('Quelle unbekannt');
    final title = context.tr(switch (item.event.kind) {
      'SubscriptionError' => 'Messwerte konnten nicht abgerufen werden',
      'DataLoss' => 'Messwerte fehlen',
      _ => diagnosticEventTitle(item.event.kind),
    });
    final time = _eventTime(context, item.timestampMs);
    final detail = context.tr(switch (item.event.kind) {
      'ConnectionLost' => 'Die Verbindung zur Datenquelle wurde unterbrochen.',
      'Reconnected' => 'Die Datenquelle hat sich wieder verbunden.',
      'SubscriptionError' =>
        'Beim Abruf der Messwerte ist ein Fehler aufgetreten.',
      'DataLoss' => 'Die Datenquelle hat fehlende Messwerte gemeldet.',
      _ => 'Die Datenquelle hat ein Ereignis gemeldet.',
    });
    return ListTile(
      key: Key('diagnostics-recent-${item.key}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(item.event.kind == 'Reconnected'
          ? Icons.link
          : Icons.history_outlined),
      title: Text(title),
      subtitle: Text('$source · $time'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final openDevice = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text('$source · $time\n\n$detail'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.tr('Schließen')),
              ),
              if (device != null)
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(context.tr('Gerät öffnen')),
                ),
            ],
          ),
        );
        if (openDevice == true && context.mounted && device != null) {
          final current = controller.snapshot?.devices
              .where((value) =>
                  value.id == device.id &&
                  _deviceSources(value).contains(item.sourceId))
              .firstOrNull;
          if (current != null) await showDevice(context, controller, current);
        }
      },
    );
  }

  Set<String> _deviceSources(Device device) => {
        if (device.sourceId case final sourceId?) sourceId,
        ...?controller.infrastructure.devicePlacement(device)?.sourceIds,
      };

  String _eventTime(BuildContext context, int? milliseconds) {
    if (milliseconds == null ||
        milliseconds < -8640000000000000 ||
        milliseconds > 8640000000000000) {
      return context.tr('Zeitpunkt unbekannt');
    }
    final local = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final format = MaterialLocalizations.of(context);
    final time = format.formatTimeOfDay(TimeOfDay.fromDateTime(local),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));
    return '${format.formatShortDate(local)} · $time';
  }
}
