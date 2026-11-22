import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/contracts.dart';
import '../models/infrastructure.dart';
import '../models/onboarding.dart';
import '../services/api.dart';
import '../services/touch_id.dart';
import 'workspaces.dart';

export 'workspaces.dart' show WorkspaceId;

String _primaryFreshness(Snapshot snapshot, String sourceId) {
  final observations =
      snapshot.metrics.where((item) => item.sourceId == sourceId).toList();
  if (observations.isEmpty) return 'unknown';
  if (observations.every((item) => item.freshness == 'fresh')) return 'fresh';
  if (observations.any((item) => item.freshness == 'fresh')) return 'mixed';
  if (observations.any((item) => item.freshness == 'stale')) return 'stale';
  return 'unknown';
}

enum _TransportMode { unknown, legacyDemo, authorized }

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
  bool _loggingOut = false;
  int _epoch = 0;
  DateTime? lastMessage;
  final List<Observation> history = [];
  String? telemetryKey;
  bool telemetrySelectionExplicit = false;
  List<SourceInfo> operationalSources = const [];
  List<CollectionEvent> operationalEvents = const [];

  /// The single application-wide infrastructure context. The authorization
  /// snapshot is kept separately from the selected presentation projection.
  final InfrastructureContext infrastructure = InfrastructureContext();

  /// Memory-only layout preferences survive workstation navigation and context
  /// changes, but never carry object data, credentials or authorization.
  final AdaptiveWorkspaces workspaces = AdaptiveWorkspaces();
  Snapshot? _authorizedSnapshot;
  _TransportMode _transport = _TransportMode.unknown;
  String? _contextScopeSignature;

  Observation? get selectedTelemetry {
    final metrics = snapshot?.metrics;
    if (metrics == null || telemetryKey == null) return null;
    for (final observation in metrics) {
      if (observationKey(observation) == telemetryKey) return observation;
    }
    return null;
  }

  OipController(
    this.api, {
    this.retryDelay = const Duration(seconds: 1),
    // The managed Core emits one authorized snapshot per second. Give the
    // tunneled stream room for brief SSH/Tailscale stalls before treating the
    // connection as closed and starting another stream.
    this.streamTimeout = const Duration(seconds: 20),
  }) {
    infrastructure.addListener(_infrastructureChanged);
  }

  bool get stale =>
      connection == 'reconnecting' ||
      (connection == 'live' &&
          !infrastructure.ready &&
          snapshot?.system.opcua != 'connected');

  bool get hasAuthorizedContext => infrastructure.ready;

  /// The authorized transport is the only managed mode. A client that never
  /// reached an authorized v2 context stays in the explicit legacy demo.
  bool get managed => _transport == _TransportMode.authorized;

  /// The authenticated management boundary, if this client has one.
  ///
  /// A client without a session boundary never offers a management action.
  DeviceManagementApi? get management =>
      api is DeviceManagementApi ? api as DeviceManagementApi : null;

  /// An authorized read needs a session. The state is terminal until the
  /// operator authorizes a new one; it is never a transport outage and never
  /// a reason to show demo data.
  bool get loginRequired =>
      connection == 'identity-required' || connection == 'login_required';

  /// The placement of a device that the operator registers.
  ///
  /// This is not a second global switcher: the global context is
  /// [infrastructure]. The onboarding scope only names where a newly
  /// registered device belongs and is invalidated with [contextRevision].
  OnboardingScope onboardingScope = const OnboardingScope();

  /// Advances with every change of the onboarding scope. Open inspectors
  /// observe it and close themselves.
  int contextRevision = 0;

  void setInfrastructureContext(OnboardingScope scope) {
    onboardingScope = scope;
    contextRevision++;
    // The caller owns the selection. A previous context's display cache is
    // never retained.
    history.clear();
    telemetryKey = null;
    telemetrySelectionExplicit = false;
    operationalSources = const [];
    operationalEvents = const [];
    snapshot = null;
    reconnect();
  }

  /// Authorizes the local operator session with a single-use code.
  Future<void> login(String code, {bool enableTouchId = false}) async {
    final boundary = management;
    if (boundary == null) {
      throw const ApiFailure(
          'Die lokale Anmeldung wird von diesem Client nicht unterstützt.',
          code: 'UNSUPPORTED');
    }
    final session = await boundary.login(code);
    String? touchIdWarning;
    if (enableTouchId) {
      try {
        await this.enableTouchId();
      } catch (exception) {
        touchIdWarning = apiErrorMessage(
            exception, 'Touch ID konnte nicht eingerichtet werden.');
      }
    }
    await _completeLogin(session);
    if (touchIdWarning != null) {
      error =
          'Angemeldet, aber Touch ID wurde nicht eingerichtet: $touchIdWarning';
      notifyListeners();
    }
  }

  /// Pairs a random credential stored behind this Mac's biometric policy.
  /// The credential itself is never persisted by Flutter or the Core.
  Future<void> enableTouchId() async {
    final boundary =
        api is TouchIdManagementApi ? api as TouchIdManagementApi : null;
    if (boundary == null) throw const ApiFailure('Touch ID nicht verfügbar.');
    final credential = await createTouchIdCredential();
    if (credential == null) throw const ApiFailure('Touch ID nicht verfügbar.');
    try {
      await boundary.pairDeviceCredential(credential);
    } catch (_) {
      try {
        await deleteTouchIdCredential();
      } catch (_) {
        // Preserve the pairing failure. The selected Keychain item may itself
        // be unavailable if the enrolled biometric set changed.
      }
      rethrow;
    }
  }

  Future<void> loginWithTouchId() async {
    final boundary =
        api is TouchIdManagementApi ? api as TouchIdManagementApi : null;
    if (boundary == null) throw const ApiFailure('Touch ID nicht verfügbar.');
    final credential = await readTouchIdCredential();
    if (credential == null) {
      throw const ApiFailure('Für diesen Mac ist Touch ID nicht eingerichtet.');
    }
    await _completeLogin(await boundary.loginWithDeviceCredential(credential));
  }

  Future<void> _completeLogin(BrowserSession session) async {
    if (_closed || _loggingOut) return;
    _sessionPrincipal = session.authenticated ? session.principalId : null;
    contextRevision++;
    history.clear();
    telemetryKey = null;
    telemetrySelectionExplicit = false;
    operationalSources = const [];
    operationalEvents = const [];
    snapshot = null;
    error = null;
    unawaited(start());
  }

  /// Revokes the local operator session and drops every authorized object.
  Future<void> logout() async {
    if (_closed || _loggingOut) return;
    _loggingOut = true;
    _epoch++;
    api.disconnect();
    final boundary = management;
    String? failure;
    try {
      if (boundary != null) await boundary.logout();
    } catch (exception) {
      failure = apiErrorMessage(exception,
          'Der Core konnte die Abmeldung nicht bestätigen. Verbinde dich erneut und wiederhole die Abmeldung.');
    } finally {
      _loggingOut = false;
    }
    if (_closed) return;
    _clearAuthorizedState();
    connection = 'identity-required';
    error = failure ?? 'Die lokale Operator-Sitzung wurde beendet.';
    infrastructure.markIdentityFailure(_operatorLoginRequired);
    notifyListeners();
  }

  void _clearAuthorizedState() {
    contextRevision++;
    onboardingScope = const OnboardingScope();
    _transport = _TransportMode.unknown;
    _sessionPrincipal = null;
    _contextScopeSignature = null;
    snapshot = null;
    _authorizedSnapshot = null;
    lastMessage = null;
    workspaces.invalidateObjects();
    history.clear();
    telemetryKey = null;
    telemetrySelectionExplicit = false;
    operationalSources = const [];
    operationalEvents = const [];
  }

  /// Composite invalidation key for every context-bound workstation. The old
  /// primarySourceId-only key could not detect a parent-only scope change.
  String get contextScopeSignature => infrastructure.ready
      ? infrastructure.scopeSignature
      : 'legacy/${snapshot?.primarySourceId ?? 'unscoped-snapshot'}';

  void selectInfrastructure(InfrastructureSelection selection) {
    infrastructure.select(selection);
  }

  bool inspectorVisible(WorkspaceId id, bool hasSelection) =>
      workspaces.inspectorVisible(id, hasSelection);

  void revealInspector(WorkspaceId id) {
    workspaces.revealInspector(id);
    notifyListeners();
  }

  void setInspectorOpen(WorkspaceId id, bool open) {
    workspaces.setInspectorOpen(id, open);
    notifyListeners();
  }

  void toggleInspectorPin(WorkspaceId id) {
    workspaces.toggleInspectorPin(id);
    notifyListeners();
  }

  void setExpertWorkspace(WorkspaceId id, bool open) {
    workspaces.setExpertWorkspace(id, open);
    notifyListeners();
  }

  void setAdvancedFilters(WorkspaceId id, bool open) {
    workspaces.setAdvancedFilters(id, open);
    notifyListeners();
  }

  void setWorkspaceView(WorkspaceId id, String? view) {
    workspaces.setView(id, view);
    notifyListeners();
  }

  void setWorkspaceDensity(WorkspaceId id, bool dense) {
    workspaces.setDensity(id, dense);
    notifyListeners();
  }

  void setWorkspaceOption(WorkspaceId id, String key, String? value) {
    workspaces.setOption(id, key, value);
    notifyListeners();
  }

  /// Performs one authorized bootstrap without claiming an active SSE channel.
  /// Useful for an explicit resync and for deterministic contract-fixture UI
  /// tests; production startup continues into [start] after the same read.
  Future<void> resyncInfrastructure() async {
    if (_closed || _loggingOut || loginRequired) return;
    final epoch = _epoch;
    final principal = await _readSessionPrincipal();
    if (!_isCurrent(epoch)) return;
    final bootstrap = await api.infrastructureBootstrap();
    if (!_isCurrent(epoch)) return;
    _sessionPrincipal = principal;
    _transport = _TransportMode.authorized;
    _acceptBootstrap(bootstrap);
    notifyListeners();
  }

  bool _isCurrent(int epoch) => !_closed && epoch == _epoch;

  Future<void> start() async {
    if (_closed || _loggingOut) return;
    final epoch = ++_epoch;
    var attempt = 0;
    while (_isCurrent(epoch)) {
      try {
        connection = snapshot == null ? 'connecting' : 'reconnecting';
        notifyListeners();

        if (_transport != _TransportMode.legacyDemo) {
          if (!await _preflightBrowserSession(epoch)) return;
          if (!_isCurrent(epoch)) return;
          try {
            infrastructure.markLoading();
            final bootstrap = await api.infrastructureBootstrap();
            if (!_isCurrent(epoch)) return;
            _transport = _TransportMode.authorized;
            _acceptBootstrap(bootstrap);
          } on ApiFailure catch (exception) {
            if (!_isCurrent(epoch)) return;
            if (exception.code == 'UNSUPPORTED' ||
                exception.statusCode == 404 ||
                exception.statusCode == 405) {
              if (managed || management?.managed == true) {
                throw _unsupportedContext;
              }
              await _acceptLegacyDemo(epoch);
            } else if (_isIdentityFailure(exception) &&
                _transport == _TransportMode.unknown &&
                management?.managed != true) {
              if (!await _tryExplicitDemo(epoch)) rethrow;
            } else {
              rethrow;
            }
          }
        } else {
          await _acceptLegacyDemo(epoch);
        }
        if (!_isCurrent(epoch)) return;
        // A REST/bootstrap resync starts a new display window; SSE has no full
        // replay and Last-Event-ID is never an authorization selector.
        history.clear();
        notifyListeners();
        final events = _transport == _TransportMode.authorized
            ? api.infrastructureStream()
            : api.stream();
        await for (final event in events.timeout(streamTimeout)) {
          if (!_isCurrent(epoch)) return;
          if (event.type == 'error') {
            throw ApiFailure(
              'Live-Daten vorübergehend nicht verfügbar.',
              code: 'SSE_ERROR',
              path: _transport == _TransportMode.authorized
                  ? '/api/v2/stream'
                  : '/api/v1/stream',
            );
          }
          if (event.type == 'snapshot') {
            if (_transport == _TransportMode.authorized) {
              _acceptAuthorized(_decodeAuthorizedSnapshot(event.data));
            } else {
              _accept(_decodeSnapshot(event.data));
            }
            connection = 'live';
            error = null;
            lastMessage = DateTime.now();
            attempt = 0;
            // One notification per accepted snapshot; context listeners only
            // mutate the projection and never emit a second notification.
            notifyListeners();
          }
        }
        throw const ApiFailure('Live-Verbindung geschlossen.');
      } catch (exception) {
        if (!_isCurrent(epoch)) return;
        if (exception is ApiFailure &&
            (_isIdentityFailure(exception) ||
                exception.code == 'UNSUPPORTED_CONTEXT')) {
          // Identity/policy failures are terminal until an explicit retry. They
          // are neither a transport outage nor a reason for an endless poll.
          _epoch++;
          api.disconnect();
          _clearAuthorizedState();
          error = _connectionError(exception);
          if (exception.code == 'UNSUPPORTED_CONTEXT') {
            connection = 'context-unsupported';
            infrastructure.markUnavailable(exception);
          } else {
            connection = 'identity-required';
            infrastructure.markIdentityFailure(exception);
          }
          notifyListeners();
          return;
        }
        api.disconnect();
        connection = 'reconnecting';
        error = _connectionError(exception);
        notifyListeners();
        await Future<void>.delayed(retryDelay * (1 << attempt.clamp(0, 3)));
        attempt++;
      }
    }
  }

  /// Check identity before requesting protected tenant data. On a fresh app
  /// launch the session can be absent even though the API itself is healthy;
  /// treating that 403 as a connection failure hides the login and Touch ID
  /// controls behind an endless reconnect state.
  Future<bool> _preflightBrowserSession(int epoch) async {
    final boundary = management;
    if (boundary == null) return true;
    try {
      final session = await boundary.session();
      if (!_isCurrent(epoch)) return false;
      if (session.mode == 'explicit_legacy_demo') return true;
      if (!session.authenticated) {
        _epoch++;
        api.disconnect();
        _clearAuthorizedState();
        connection = 'login_required';
        error = null;
        infrastructure.markIdentityFailure(_operatorLoginRequired);
        notifyListeners();
        return false;
      }
      _sessionPrincipal = session.principalId;
      return true;
    } on ApiFailure catch (exception) {
      // Older explicit demo cores do not implement browser sessions. Preserve
      // the existing version negotiation for those cores.
      if (exception.statusCode == 404 ||
          exception.statusCode == 405 ||
          exception.code == 'UNSUPPORTED') {
        return true;
      }
      rethrow;
    }
  }

  static const _operatorLoginRequired = ApiFailure(
    'Für diese Installation ist eine Operator-Anmeldung erforderlich.',
    code: 'UNAUTHENTICATED',
    path: '/api/v2/browser/session',
    statusCode: 401,
  );

  bool _isIdentityFailure(ApiFailure error) =>
      error.statusCode == 401 ||
      error.statusCode == 403 ||
      error.code == 'UNAUTHENTICATED' ||
      error.code == 'PERMISSION_DENIED' ||
      error.code == 'PRINCIPAL_REQUIRED';

  /// Is the Core an **explicit** legacy demo?
  ///
  /// The flag `simulated` says that a source of the Core is simulated: a
  /// real instance with one simulated source is not a demo, and the demo
  /// dashboard must never appear in its place (R7 of the baseline). The Core
  /// states its demo mode with the scenario controls it offers — they exist
  /// only in the demo. Without that statement the client refuses.
  bool _isExplicitDemo(Snapshot initial) =>
      initial.system.simulated && initial.system.demoControls;

  static const _unsupportedContext = ApiFailure(
    'Dieser Core bietet keinen autorisierten v2-Kontext; reale v1-Daten werden nicht anonym übernommen.',
    code: 'UNSUPPORTED_CONTEXT',
    statusCode: 409,
  );

  Future<void> _acceptLegacyDemo(int epoch) async {
    final initial = await api.initial();
    if (!_isCurrent(epoch)) return;
    if (!_isExplicitDemo(initial)) {
      throw _unsupportedContext;
    }
    _transport = _TransportMode.legacyDemo;
    if (infrastructure.status != InfrastructureContextStatus.unavailable) {
      infrastructure.markUnavailable();
    }
    _authorizedSnapshot = null;
    _accept(initial);
  }

  Future<bool> _tryExplicitDemo(int epoch) async {
    try {
      final initial = await api.initial();
      if (!_isCurrent(epoch) || !_isExplicitDemo(initial)) {
        return false;
      }
      _transport = _TransportMode.legacyDemo;
      if (infrastructure.status != InfrastructureContextStatus.unavailable) {
        infrastructure.markUnavailable();
      }
      _authorizedSnapshot = null;
      _accept(initial);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The principal of the authorized session.
  ///
  /// The Core has no whoami route. The session of the browser is the
  /// evidence of the identity, and it is what keeps the selected scope of the
  /// operator across a refresh of the authorized projection.
  String? _sessionPrincipal;

  Future<String?> _readSessionPrincipal() async {
    final boundary = management;
    if (boundary == null) return null;
    try {
      final session = await boundary.session();
      return session.authenticated ? session.principalId : null;
    } catch (_) {
      return null;
    }
  }

  void _acceptBootstrap(InfrastructureBootstrap bootstrap) {
    _authorizedSnapshot = bootstrap.snapshot.toSnapshot();
    _accept(_authorizedSnapshot!);
    infrastructure.accept(bootstrap, sessionPrincipal: _sessionPrincipal);
  }

  void _acceptAuthorized(AuthorizedSnapshot value) {
    _authorizedSnapshot = value.toSnapshot();
    infrastructure.acceptData();
  }

  void _infrastructureChanged() {
    if (_transport != _TransportMode.authorized ||
        _authorizedSnapshot == null) {
      return;
    }
    final nextSignature = infrastructure.scopeSignature;
    final scopeChanged = _contextScopeSignature != nextSignature;
    if (scopeChanged) {
      _contextScopeSignature = nextSignature;
      workspaces.invalidateObjects();
      api.cancelContextRequests();
      api.cancelDeviceRequests();
      api.cancelSettingsRequests();
      history.clear();
      telemetryKey = null;
      telemetrySelectionExplicit = false;
      operationalSources = const [];
      operationalEvents = const [];
    }
    final projected = infrastructure.project(_authorizedSnapshot!);
    _accept(projected);
    // Unlike legacy SSE, an authorized projection is authoritative even when
    // its selected source/event list is empty.
    operationalSources = projected.sources;
    operationalEvents = projected.recentEvents;
    if (scopeChanged) notifyListeners();
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

  AuthorizedSnapshot _decodeAuthorizedSnapshot(String data) {
    try {
      return AuthorizedSnapshot.fromJson(jsonDecode(data) as Json);
    } catch (_) {
      throw const ApiFailure(
        'Der autorisierte Live-Snapshot verletzt den v2-Datenvertrag.',
        code: 'CONTRACT_ERROR',
        path: '/api/v2/stream',
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
      final retention = snapshot == null
          ? 'Keine vorherigen Kontextdaten werden angezeigt.'
          : 'Letzte Daten sind veraltet.';
      final reconnect = _isIdentityFailure(exception) ||
              exception.code == 'UNSUPPORTED_CONTEXT'
          ? 'Kein automatischer Retry; eine neue Session oder ein unterstützter Vertrag ist erforderlich.'
          : 'Automatischer Reconnect läuft.';
      return 'API-Endpunkt $endpoint'
          '${apiErrorMessage(exception, 'Daten konnten nicht geladen werden.')} '
          '$reconnect $retention';
    }
    return 'OIP-Server nicht erreichbar. Automatischer Reconnect läuft. '
        'Letzte Daten sind veraltet.';
  }

  void _accept(Snapshot value) {
    final scopeChanged = snapshot?.primarySourceId != value.primarySourceId;
    if (scopeChanged) {
      history.clear();
      telemetryKey = null;
      telemetrySelectionExplicit = false;
      operationalSources = const [];
      operationalEvents = const [];
    }
    if (value.sources.isNotEmpty) operationalSources = value.sources;
    if (value.recentEvents.isNotEmpty) operationalEvents = value.recentEvents;
    final primarySource = value.primarySourceId;
    if (primarySource != null && operationalSources.isNotEmpty) {
      final observedFreshness = _primaryFreshness(value, primarySource);
      operationalSources = operationalSources
          .map((source) => source.id == primarySource
              ? source.withPrimarySnapshotStatus(value.system.opcua,
                  observedFreshness, value.system.lastReceivedMs)
              : source)
          .toList();
    }
    snapshot = value;

    final selected = selectedTelemetry;
    if (telemetryKey != null && selected == null) {
      history.clear();
    }
    if (!telemetrySelectionExplicit &&
        (selected == null || !value.metrics.contains(selected))) {
      final preferred = _defaultTelemetry(value);
      telemetryKey = preferred == null ? null : observationKey(preferred);
    }
    _recordSelectedTelemetry(value);
  }

  /// The measurement the chart shows when nothing was selected explicitly.
  ///
  /// The legacy demo keeps its rule: the temperature of the entity `M-01` of
  /// the primary source. The managed mode never prefers a demo entity and
  /// never a fallback source: the metric with the most received samples wins
  /// and a tie is broken by the metric identifier.
  Observation? _defaultTelemetry(Snapshot value) {
    if (!managed) {
      return value.primaryTemperature ??
          value.metrics
              .where((item) => item.number != null && item.sourceMs != null)
              .firstOrNull ??
          value.metrics.firstOrNull;
    }
    final groups = <String, List<Observation>>{};
    for (final item in value.metrics) {
      if (item.sourceId == null ||
          item.number == null ||
          item.sourceMs == null) {
        continue;
      }
      groups
          .putIfAbsent(
              '${item.sourceId}|${item.entityId}|${item.metricId}', () => [])
          .add(item);
    }
    if (groups.isEmpty) return value.metrics.firstOrNull;
    final ranked = groups.values.toList()
      ..sort((a, b) {
        final byCount = b.length.compareTo(a.length);
        return byCount != 0
            ? byCount
            : a.first.metricId.compareTo(b.first.metricId);
      });
    return ranked.first.firstOrNull;
  }

  void _recordSelectedTelemetry(Snapshot value) {
    for (final observation in value.metrics) {
      if (observationKey(observation) != telemetryKey ||
          observation.freshness != 'fresh' ||
          observation.sourceMs == null) {
        continue;
      }
      if (history.isNotEmpty &&
          observation.sourceMs! < history.last.sourceMs!) {
        history.clear();
      }
      if (history.isEmpty ||
          history.last.sourceMs != observation.sourceMs ||
          history.last.value != observation.value) {
        history.add(observation);
        if (history.length > 60) history.removeAt(0);
      }
    }
  }

  void selectTelemetry(String key) {
    telemetrySelectionExplicit = true;
    if (telemetryKey == key) return;
    telemetryKey = key;
    history.clear();
    final current = snapshot;
    if (current != null) _recordSelectedTelemetry(current);
    notifyListeners();
  }

  /// An explicit entity without observations must not retain another entity's chart.
  void clearTelemetry() {
    telemetrySelectionExplicit = true;
    telemetryKey = null;
    history.clear();
    notifyListeners();
  }

  Future<void> setScenario(String value) async {
    if (scenarioBusy || _transport == _TransportMode.authorized) return;
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
    infrastructure.removeListener(_infrastructureChanged);
    infrastructure.dispose();
    api.close();
    super.dispose();
  }
}
