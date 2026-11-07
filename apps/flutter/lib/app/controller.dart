import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/contracts.dart';
import '../models/onboarding.dart';
import '../services/api.dart';

class OipController extends ChangeNotifier {
  final OipApi api;
  final Duration retryDelay;
  final Duration streamTimeout;
  Snapshot? snapshot;
  String connection = 'connecting';
  BrowserSession? browserSession;
  int contextRevision = 0;
  OnboardingScope onboardingScope = const OnboardingScope();
  DeviceManagementApi? get management =>
      api is DeviceManagementApi ? api as DeviceManagementApi : null;
  bool get managed => management?.managed == true;
  bool get loginRequired => connection == 'login_required';
  void setInfrastructureContext(OnboardingScope scope) {
    onboardingScope = scope;
    contextRevision++;
    // Caller OIP-009 owns selection. Never retain a previous context's display cache.
    series.clear();
    snapshot = null;
    reconnect();
  }

  Future<void> login(String code) async {
    browserSession = await management!.login(code);
    contextRevision++;
    series.clear();
    snapshot = null;
    error = null;
    reconnect();
  }

  Future<void> logout() async {
    contextRevision++;
    _epoch++;
    api.disconnect();
    String? failure;
    try {
      await management!.logout();
    } catch (e) {
      failure = apiErrorMessage(e,
          'Lokale Ansicht abgemeldet. Serverseitige Abmeldung nicht bestätigt; die Sitzung läuft spätestens nach 30 Minuten ab.');
    } finally {
      series.clear();
      snapshot = null;
      browserSession = null;
      connection = 'login_required';
      error = failure;
      if (!_closed) notifyListeners();
    }
  }

  String? error;
  String? scenarioError;
  bool scenarioBusy = false;
  bool _closed = false;
  int _epoch = 0;
  DateTime? lastMessage;

  /// The measured series of the live projection.
  ///
  /// The legacy demo measures exactly one series. The managed mode measures
  /// one series per authorized source, so no source is preferred and no
  /// fallback primary is invented.
  final List<TrendSeries> series = [];

  /// The first measured series. The legacy view and the regression tests use
  /// it; it stays empty while no measurement was received.
  List<Observation> get history =>
      series.isEmpty ? const <Observation>[] : series.first.samples;

  /// The key the current series belong to. A change of the key starts a new
  /// display window, exactly like a change of the primary source did.
  String? _seriesKey;
  OipController(
    this.api, {
    this.retryDelay = const Duration(seconds: 1),
    this.streamTimeout = const Duration(seconds: 6),
  });
  bool get stale =>
      connection != 'live' ||
      (!managed && snapshot?.system.opcua != 'connected');

  Future<void> start() async {
    final epoch = ++_epoch;
    var attempt = 0;
    while (!_closed && epoch == _epoch) {
      try {
        connection = snapshot == null ? 'connecting' : 'reconnecting';
        notifyListeners();
        if (management != null) {
          final previousPrincipal = browserSession?.principalId;
          browserSession = await management!.session();
          if (_closed || epoch != _epoch) return;
          if (previousPrincipal != null &&
              previousPrincipal != browserSession?.principalId) {
            contextRevision++;
            snapshot = null;
            series.clear();
          }
          if (managed && !browserSession!.authenticated) {
            contextRevision++;
            snapshot = null;
            series.clear();
            connection = 'login_required';
            error = null;
            notifyListeners();
            return;
          }
        }
        final initial = await api.initial();
        if (_closed || epoch != _epoch) return;
        // A REST resync starts a new display window; SSE has no full replay.
        series.clear();
        _accept(initial);
        notifyListeners();
        await for (final event in api.stream().timeout(streamTimeout)) {
          if (_closed || epoch != _epoch) return;
          if (event.type == 'error') {
            throw const ApiFailure(
              'Live-Daten vorübergehend nicht verfügbar.',
              code: 'SSE_ERROR',
              path: '/api/v1/stream',
            );
          }
          if (event.type == 'snapshot') {
            _accept(_decodeSnapshot(event.data));
            connection = 'live';
            error = null;
            lastMessage = DateTime.now();
            attempt = 0;
            // One notification per accepted snapshot; _accept only mutates state.
            notifyListeners();
          }
        }
        throw const ApiFailure('Live-Verbindung geschlossen.');
      } catch (exception) {
        if (_closed || epoch != _epoch) return;
        api.disconnect();
        connection = 'reconnecting';
        error = _connectionError(exception);
        notifyListeners();
        await Future<void>.delayed(retryDelay * (1 << attempt.clamp(0, 3)));
        attempt++;
      }
    }
  }

  Snapshot _decodeSnapshot(String data) {
    try {
      return managed
          ? Snapshot.fromScopedJson(jsonDecode(data) as Json)
          : Snapshot.fromJson(jsonDecode(data) as Json);
    } catch (_) {
      throw const ApiFailure(
        'Der Live-Snapshot verletzt den erwarteten Datenvertrag.',
        code: 'CONTRACT_ERROR',
        path: '/api/v1/stream',
      );
    }
  }

  String _connectionError(Object exception) {
    if (exception is ApiFailure) {
      if (exception.code == 'CONNECTION_FAILED') {
        return 'OIP-Server nicht erreichbar (${exception.path ?? 'API'}). '
            'Automatischer Reconnect läuft. Letzte Daten sind veraltet.';
      }
      final endpoint = exception.path == null ? '' : '${exception.path}: ';
      return 'API-Endpunkt $endpoint'
          '${apiErrorMessage(exception, 'Daten konnten nicht geladen werden.')} '
          'Automatischer Reconnect läuft. Letzte Daten sind veraltet.';
    }
    return 'OIP-Server nicht erreichbar. Automatischer Reconnect läuft. '
        'Letzte Daten sind veraltet.';
  }

  void _accept(Snapshot value) {
    final key = _seriesKeyOf(value);
    if (_seriesKey != key) {
      _seriesKey = key;
      series.clear();
    }
    snapshot = value;
    _accumulate(value);
  }

  /// The key the measured series belong to.
  ///
  /// The legacy demo measures the temperature of its primary source; the
  /// managed mode measures every authorized source of the session.
  String _seriesKeyOf(Snapshot value) {
    if (!managed) return value.primarySourceId ?? '';
    final ids = value.sources.map((s) => s.id).toList()..sort();
    return ids.join('|');
  }

  /// The measurements of the projection that may extend a series.
  ///
  /// The legacy rule stays exactly as it was: the temperature of the entity
  /// `M-01` of the primary source. The managed rule takes the numeric
  /// measurements of the authorized sources; a stale or unknown measurement
  /// never extends a series.
  List<Observation> _measurements(Snapshot value) => managed
      ? value.metrics
          .where((o) =>
              o.sourceId != null &&
              o.freshness == 'fresh' &&
              o.sourceMs != null &&
              o.number != null)
          .toList()
      : value.metrics
          .where((o) =>
              o.sourceId == value.primarySourceId &&
              value.primarySourceId != null &&
              o.entityId == 'M-01' &&
              o.metricId == 'temperature' &&
              o.freshness == 'fresh' &&
              o.sourceMs != null)
          .toList();

  void _accumulate(Snapshot value) {
    final groups = <String, List<Observation>>{};
    for (final o in _measurements(value)) {
      groups
          .putIfAbsent('${o.sourceId}|${o.entityId}|${o.metricId}', () => [])
          .add(o);
    }
    final chosen = _chosen(groups);
    final bySource = <String, String>{};
    for (final group in chosen) {
      bySource[group.sourceId] = group.key;
      final existing = series.where((s) => s.key == group.key).firstOrNull;
      final target = existing ??
          TrendSeries(group.sourceId, group.entityId, group.metricId,
              group.unit, <Observation>[]);
      if (existing == null) series.add(target);
      for (final o in group.samples) {
        // A source time that moves backwards starts a new display window.
        if (target.samples.isNotEmpty &&
            o.sourceMs! < target.samples.last.sourceMs!) {
          target.samples.clear();
        }
        if (target.samples.isEmpty ||
            target.samples.last.sourceMs != o.sourceMs ||
            target.samples.last.value != o.value) {
          target.samples.add(o);
          if (target.samples.length > 60) target.samples.removeAt(0);
        }
      }
    }
    // A source shows exactly one series. A series of a source that is not
    // measured in this projection keeps its received points.
    final keep = bySource.values.toSet();
    series.removeWhere(
        (s) => bySource.containsKey(s.sourceId) && !keep.contains(s.key));
  }

  /// The series that are drawn.
  ///
  /// The legacy demo measures one series. The managed mode draws one series
  /// per authorized source: the metric with the most received samples, a tie
  /// is broken by the metric identifier. No source and no metric of another
  /// scope is preferred.
  List<_SeriesGroup> _chosen(Map<String, List<Observation>> groups) {
    final result = <_SeriesGroup>[];
    final bySource = <String, List<_SeriesGroup>>{};
    for (final entry in groups.entries) {
      final parts = entry.key.split('|');
      final group = _SeriesGroup(parts[0], parts[1], parts[2],
          entry.value.firstOrNull?.symbol ?? '', entry.value);
      bySource.putIfAbsent(group.sourceId, () => []).add(group);
    }
    for (final candidates in bySource.values) {
      candidates.sort((a, b) {
        final byCount = b.samples.length.compareTo(a.samples.length);
        return byCount != 0 ? byCount : a.metricId.compareTo(b.metricId);
      });
      result.add(candidates.first);
    }
    return result;
  }

  Future<void> setScenario(String value) async {
    if (scenarioBusy) return;
    scenarioBusy = true;
    scenarioError = null;
    notifyListeners();
    try {
      await api.scenario(value);
    } catch (exception) {
      scenarioError = apiErrorMessage(
        exception,
        'Szenariowechsel fehlgeschlagen. Bitte erneut versuchen.',
      );
    } finally {
      if (!_closed) {
        scenarioBusy = false;
        notifyListeners();
      }
    }
  }

  void reconnect() {
    api.disconnect();
    unawaited(start());
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    api.close();
    super.dispose();
  }
}

/// One measured group of the projection: the measurements of one source, one
/// entity and one metric.
class _SeriesGroup {
  final String sourceId, entityId, metricId, unit;
  final List<Observation> samples;
  _SeriesGroup(this.sourceId, this.entityId, this.metricId, this.unit,
      this.samples);
  String get key => '$sourceId|$entityId|$metricId';
}
