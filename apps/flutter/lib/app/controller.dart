import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/contracts.dart';
import '../services/api.dart';

class OipController extends ChangeNotifier {
  final OipApi api;
  final Duration retryDelay;
  final Duration streamTimeout;
  Snapshot? snapshot;
  String connection = 'connecting';
  String? error;
  String? scenarioError;
  bool scenarioBusy = false;
  bool _closed = false;
  int _epoch = 0;
  DateTime? lastMessage;
  final List<Observation> history = [];
  OipController(
    this.api, {
    this.retryDelay = const Duration(seconds: 1),
    this.streamTimeout = const Duration(seconds: 6),
  });
  bool get stale =>
      connection != 'live' || snapshot?.system.opcua != 'connected';

  Future<void> start() async {
    final epoch = ++_epoch;
    var attempt = 0;
    while (!_closed && epoch == _epoch) {
      try {
        connection = snapshot == null ? 'connecting' : 'reconnecting';
        notifyListeners();
        final initial = await api.initial();
        if (_closed || epoch != _epoch) return;
        // A REST resync starts a new display window; SSE has no full replay.
        history.clear();
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
      return Snapshot.fromJson(jsonDecode(data) as Json);
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
    if (snapshot?.primarySourceId != value.primarySourceId) history.clear();
    snapshot = value;
    for (final o in value.metrics.where((o) =>
        o.sourceId == value.primarySourceId &&
        value.primarySourceId != null &&
        o.entityId == 'M-01' &&
        o.metricId == 'temperature' &&
        o.freshness == 'fresh' &&
        o.sourceMs != null)) {
      if (history.isNotEmpty && o.sourceMs! < history.last.sourceMs!) {
        history.clear();
      }
      if (history.isEmpty ||
          history.last.sourceMs != o.sourceMs ||
          history.last.value != o.value) {
        history.add(o);
        if (history.length > 60) history.removeAt(0);
      }
    }
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
