import '../l10n/oip_strings.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../design_system/theme.dart';
import '../models/history.dart';
import '../services/api.dart';
import '../widgets/components.dart';

/// The persisted observation history of one device.
///
/// The samples come from the Core database, not from the live snapshot. Every
/// entry is labelled as history, a stored sample is never drawn as a live
/// value, and the limits the Core states for the answer are shown instead of
/// being hidden.
class DeviceHistorySection extends StatefulWidget {
  final DeviceManagementApi api;
  final String deviceId;
  const DeviceHistorySection(
      {super.key, required this.api, required this.deviceId});

  @override
  State<DeviceHistorySection> createState() => _DeviceHistorySectionState();
}

class _DeviceHistorySectionState extends State<DeviceHistorySection> {
  Timer? timer;

  /// The loaded samples, keyed by the identity the Core gave them. The Core
  /// serves the history from the oldest stored entry; a refresh never
  /// duplicates a sample and never drops one.
  final Map<String, HistoricalObservation> _samples = {};
  String? _cursor;
  bool _truncated = false;
  bool _busy = false;
  bool _failed = false;
  String _error = '';
  List<String> _missing = const [];
  String _timeSemantics = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load(null));
    // The history of a device grows while the collector runs. The section
    // follows the persisted state on a bounded cadence, exactly like the
    // connection panel follows the live observations.
    timer = Timer.periodic(const Duration(seconds: 5), (_) => _load(null));
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load(String? cursor) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final page = await widget.api
          .observationHistory(deviceId: widget.deviceId, cursor: cursor);
      if (!mounted) return;
      setState(() {
        for (final sample in page.observations) {
          _samples[sample.id] = sample;
        }
        // The refresh of the first page keeps the continuation of the
        // operator; only a continuation itself moves the cursor on.
        if (cursor != null || _cursor == null) _cursor = page.nextCursor;
        _truncated = page.truncated;
        _missing = page.missingEvidence;
        _timeSemantics = page.timeSemantics;
        _failed = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _error =
            apiErrorMessage(exception, context.tr("Historie nicht abrufbar."));
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(context.tr("Persistierte Messhistorie"),
              'Aus der Core-Datenbank · gespeicherte Werte, kein Live-Zustand'),
          const SizedBox(height: OipTokens.s3),
          if (_failed && _samples.isEmpty)
            StateMessage(context.tr("Historie nicht verfügbar"), _error,
                compact: true)
          else if (_samples.isEmpty && _busy)
            const Padding(
              padding: EdgeInsets.all(OipTokens.s4),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_samples.isEmpty)
            InlineNotice(
              context.tr("Keine persistierten Messwerte"),
              context.tr(
                  "Der Core hat für dieses Gerät keine gespeicherten Beobachtungen. Das ist kein Nachweis einer lückenlosen Überwachung."),
              icon: Icons.history,
              color: OipTokens.statusColor(context, 'degraded'),
            )
          else ...[
            for (final sample in _samples.values) HistorySampleRow(sample),
            if (_failed)
              Padding(
                padding: const EdgeInsets.only(top: OipTokens.s2),
                child: Text(_error,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: OipTokens.statusColor(context, 'critical'))),
              ),
          ],
          const SizedBox(height: OipTokens.s2),
          if (_truncated && _cursor != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _load(_cursor),
                icon: const Icon(Icons.expand_more),
                label: Text(context.tr("Neuere Einträge laden")),
              ),
            )
          else if (_truncated)
            InlineNotice(
              context.tr("Historie gekürzt"),
              context.tr(
                  "Weitere Einträge liegen vor, die Fortsetzung ist derzeit nicht abrufbar."),
              icon: Icons.more_horiz,
            ),
          if (_missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: OipTokens.s2),
              child: Text(
                  context
                      .tr("Grenzen dieser Historie: {0}", [_missing.join(' ')]),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          if (_timeSemantics.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(context.tr("Zeit- und Herkunftssemantik"),
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(fontSize: 9, letterSpacing: .75)),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_timeSemantics,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
        ],
      );
}

/// One stored measurement.
///
/// The value, its unit, the quality and the freshness come from the stored
/// record of the Core. The row names the sample as history and reports the
/// receive time the Core guarantees for it.
class HistorySampleRow extends StatelessWidget {
  final HistoricalObservation sample;
  const HistorySampleRow(this.sample, {super.key});

  @override
  Widget build(BuildContext context) {
    final observation = sample.observation;
    final value = '${observation.display} ${observation.symbol}'.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OipTokens.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr("{0} · Historie", [observation.metricId]),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(fontSize: 9, letterSpacing: .75)),
          const SizedBox(height: OipTokens.s1),
          Text('$value · ${known(observation.quality)} · '
              '${known(observation.freshness)}'),
          Text(context.tr("Empfangen {0}", [timestamp(sample.receivedMs)]),
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
