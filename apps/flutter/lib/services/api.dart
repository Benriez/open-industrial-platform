import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../core/sse.dart';
import '../core/event_connection.dart';
import 'event_transport.dart';
import 'session_cookie.dart';
import '../models/contracts.dart';
import '../models/diagnostics.dart';
import '../models/history.dart';
import '../models/infrastructure.dart';
import '../models/onboarding.dart';
import '../features/settings/settings_models.dart';

abstract class OipApi {
  Future<Snapshot> initial();
  Stream<ServerEvent> stream();
  Future<void> scenario(String name);
  Future<List<SourceInfo>> sources();
  Future<NodePage> nodes(String search, String folder, int offset,
      {String? source});
  Future<List<Observation>> deviceMetrics(String id);
  Future<List<CollectionEvent>> collectionEvents();

  /// Authorized OIP-008/008.5 global-context reads. Implementations without a
  /// secured v2 transport report UNSUPPORTED; callers may then use only the
  /// explicit demo/v1 path, never an anonymous tenant fallback.
  Future<InfrastructureBootstrap> infrastructureBootstrap() async {
    throw const ApiFailure(
      'Autorisierter Infrastructure Context wird nicht unterstützt.',
      code: 'UNSUPPORTED',
    );
  }

  Stream<ServerEvent> infrastructureStream() async* {
    throw const ApiFailure(
      'Autorisierter v2-SSE wird nicht unterstützt.',
      code: 'UNSUPPORTED',
    );
  }

  /// Context-aware bounded reads. The defaults preserve the explicit legacy
  /// demo contract used by existing fixtures and workstations.
  Future<List<SourceInfo>> contextSources(InfrastructureContext context) =>
      sources();
  Future<NodePage> contextNodes(
    String search,
    String folder,
    int offset,
    InfrastructureContext context, {
    String? source,
  }) =>
      nodes(search, folder, offset, source: source);
  Future<List<Observation>> contextDeviceMetrics(
          String id, InfrastructureContext context) =>
      deviceMetrics(id);
  Future<List<CollectionEvent>> contextCollectionEvents(
          InfrastructureContext context) =>
      collectionEvents();
  Future<ContextEventPage> contextEventPage(InfrastructureContext context,
      {String? cursor}) async {
    return ContextEventPage(
      events: await contextCollectionEvents(context),
      truncated: false,
      nextCursor: null,
      missingEvidence: const [],
      timeSemantics: 'current_window',
    );
  }

  /// Authenticated OIP-008.4 reads. No implementation may add browser tokens,
  /// credential files or legacy-access fallbacks to these methods.
  Future<SettingsSnapshot> settings({
    String scope = 'platform',
    String? scopeId,
    String? key,
    bool catalog = false,
  }) async {
    throw const ApiFailure(
      'Settings-Read wird von diesem API-Client nicht unterstützt.',
      code: 'UNSUPPORTED',
    );
  }

  Future<ManagementReport> management(String section) async {
    throw const ApiFailure(
      'Management-Read wird von diesem API-Client nicht unterstützt.',
      code: 'UNSUPPORTED',
    );
  }

  /// Cancels active Settings/Management reads when supported. Page generations
  /// independently reject every late response.
  void cancelSettingsRequests() {}

  /// Cancels hierarchy/bootstrap reads on identity or authorization changes.
  void cancelContextRequests() {}

  /// Cancels the active device detail request when the implementation supports it.
  /// Page-level generations additionally reject every late response.
  void cancelDeviceRequests() {}
  /// The Core's own answer about the persisted diagnosis history.
  ///
  /// The state is never assumed by the client: the Core names it.
  Future<CollectionEvents> collectionEventsWithStatus() async =>
      CollectionEvents(await collectionEvents(), 'unknown');

  /// The documented gaps of the authorized sources.
  ///
  /// The scope is the session of the principal; no source is preferred and
  /// no global selection payload is invented. The cursor is the opaque
  /// continuation token of the Core.
  Future<DiagnosticPage> diagnosticGaps({int limit = 50, String? cursor}) async {
    throw const ApiFailure(
        'Dokumentierte Lücken werden von diesem API-Client nicht unterstützt.',
        code: 'UNSUPPORTED');
  }

  /// The health transitions of the authorized sources.
  Future<DiagnosticPage> healthHistory({int limit = 50, String? cursor}) async {
    throw const ApiFailure(
        'Der Gesundheitsverlauf wird von diesem API-Client nicht unterstützt.',
        code: 'UNSUPPORTED');
  }

  void disconnect();
  void close();
}

/// The authenticated management boundary of the local Core.
///
/// The session is the only identity. A missing session is an identity
/// problem and never a reason to read anonymous tenant data.
abstract class DeviceManagementApi {
  bool get managed;
  Future<BrowserSession> session();
  Future<BrowserSession> login(String code);
  Future<void> logout();
  Future<List<HierarchyItem>> hierarchy(
      String level, Map<String, String> scope);
  Future<Json> inventory(String id);
  Future<void> register(Json device);

  /// The update of a registered device.
  ///
  /// The revision of the device is the guard of the write: a stale revision
  /// is refused by the Core, so two operators cannot overwrite each other
  /// unnoticed.
  Future<void> update(Json device, {required int expectedRevision});

  /// The archive of a registered device.
  ///
  /// The archive keeps the record of the device and its history. It is not a
  /// deletion and it is guarded by the revision of the device as well.
  Future<void> archive(String id, {required int expectedRevision});
  Future<ConnectionResult> connection({String? deviceId, String? planId});
  Future<ConnectionResult> configure(Json action);

  /// The persisted observation history of one device.
  ///
  /// The scope is the device itself, so no global organization, infrastructure
  /// or site selection is needed and none is invented.
  Future<HistoryPage> observationHistory(
      {required String deviceId, String? cursor, int limit = 20});
}

/// Optional native-only pairing operations, kept separate from the existing
/// management seam so test and legacy clients do not claim Touch ID support.
abstract class TouchIdManagementApi {
  Future<void> pairDeviceCredential(String credential);
  Future<BrowserSession> loginWithDeviceCredential(String credential);
}

class ApiFailure implements Exception {
  final String message;
  final String? code;
  final String? path;
  final int? statusCode;
  const ApiFailure(this.message, {this.code, this.path, this.statusCode});
  @override
  String toString() => code == null ? message : '$message [$code]';
}

/// Public, sanitized error text. Internal exception objects never reach the UI.
String apiErrorMessage(Object error, String fallback) {
  if (error is PlatformException) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) return message;
    return '$fallback (${error.code})';
  }
  if (error is! ApiFailure) return fallback;
  final code = error.code == null ? '' : ' (${error.code})';
  return '${error.message}$code';
}

class RestApi implements OipApi, DeviceManagementApi, TouchIdManagementApi {
  final Uri base;
  final http.Client _rest;
  final bool _dedicatedNodeClients;
  http.Client? _nodesClient;
  http.Client? _deviceClient;
  final Set<http.Client> _settingsClients = <http.Client>{};
  EventConnection? _events;
  String? _csrf;
  bool _managed = false;

  @override
  bool get managed => _managed;

  /// The headers of every request: the CSRF token of the session and, on a
  /// platform without a browser, the cookie of the session.
  Map<String, String> _sessionHeaders([Map<String, String>? extra]) => {
        ...?extra,
        if (_csrf != null) 'x-oip-csrf': _csrf!,
        if (sessionCookieHeader() != null) 'cookie': sessionCookieHeader()!,
        if (sessionOriginHeader(base) != null) 'origin': sessionOriginHeader(base)!,
      };

  Future<dynamic> _change(String path, Json body, {String method = 'POST'}) =>
      _request(path, () {
        final headers = _sessionHeaders({'Content-Type': 'application/json'});
        return method == 'DELETE'
            ? _rest.delete(uri(path), headers: headers)
            : _rest.post(uri(path), headers: headers, body: jsonEncode(body));
      });

  BrowserSession _session(Json value) {
    final s = BrowserSession.fromJson(value);
    _managed = s.mode != 'explicit_legacy_demo';
    _csrf = s.authenticated ? value['csrf_token'] as String? : null;
    return s;
  }

  @override
  Future<BrowserSession> session() async =>
      _session(await _get('/api/v2/browser/session') as Json);

  @override
  Future<BrowserSession> login(String code) async =>
      _session(await _change('/api/v2/browser/login', {'code': code}) as Json);

  @override
  Future<void> pairDeviceCredential(String credential) async {
    await _change('/api/v2/browser/pairing', {'credential': credential});
  }

  @override
  Future<BrowserSession> loginWithDeviceCredential(String credential) async =>
      _session(await _change(
          '/api/v2/browser/device-login', {'credential': credential}) as Json);

  @override
  Future<void> logout() async {
    try {
      await _change('/api/v2/browser/session', {}, method: 'DELETE');
    } finally {
      _csrf = null;
      disconnect();
    }
  }

  @override
  Future<List<HierarchyItem>> hierarchy(
      String level, Map<String, String> scope) async {
    if (!const ['organizations', 'infrastructures', 'sites'].contains(level)) {
      throw const ApiFailure('Unbekannte Hierarchieebene.');
    }
    final items = <HierarchyItem>[];
    for (var offset = 0; offset < 1024; offset += 100) {
      final page = await _get(
              '/api/v2/$level', {...scope, 'offset': '$offset', 'limit': '100'})
          as Json;
      final rows = (page['items'] as List).cast<Json>();
      items.addAll(rows.map(HierarchyItem.fromJson));
      if (rows.length < 100) return items;
    }
    throw const ApiFailure('Hierarchieauswahl benötigt einen engeren Kontext.');
  }

  @override
  Future<Json> inventory(String id) async {
    final page = await _get('/api/v2/inventory/devices', {'id': id}) as Json;
    final items = page['items'] as List;
    if (items.length != 1) throw const ApiFailure('Gerät nicht zugänglich.');
    return items.single as Json;
  }

  @override
  Future<void> register(Json device) async {
    await _change('/api/v2/inventory/apply', {
      'changes': [
        {'operation': 'register', 'device': device}
      ]
    });
  }

  @override
  Future<void> update(Json device, {required int expectedRevision}) async {
    await _change('/api/v2/inventory/apply', {
      'changes': [
        {
          'operation': 'update',
          'device': device,
          'expected_revision': expectedRevision,
        }
      ]
    });
  }

  @override
  Future<void> archive(String id, {required int expectedRevision}) async {
    await _change('/api/v2/inventory/apply', {
      'changes': [
        {
          'operation': 'archive',
          'id': id,
          'expected_revision': expectedRevision,
        }
      ]
    });
  }

  @override
  Future<ConnectionResult> connection(
          {String? deviceId, String? planId}) async =>
      ConnectionResult.fromJson(await _get('/api/v2/device-connections', {
        if (deviceId != null) 'device_id': deviceId,
        if (planId != null) 'plan_id': planId
      }) as Json);

  @override
  Future<ConnectionResult> configure(Json action) async =>
      ConnectionResult.fromJson(
          await _change('/api/v2/device-connections', action) as Json);

  @override
  Future<HistoryPage> observationHistory(
          {required String deviceId, String? cursor, int limit = 20}) =>
      _parseContract('/api/v2/observations/history', () async {
        final value = await _get('/api/v2/observations/history', {
          'device': deviceId,
          'limit': '$limit',
          if (cursor != null) 'cursor': cursor,
        }) as Json;
        return HistoryPage.fromJson(value);
      });

  /// The collection events together with the state that the Core names for the
  /// persisted diagnosis history. The client never invents that state.
  @override
  Future<CollectionEvents> collectionEventsWithStatus() async {
    if (!_managed) {
      return _collectionEvents(await _get('/api/v1/events') as Json);
    }
    final value = await _settingsGet('/api/v2/events', const {});
    return _collectionEvents(value.$1);
  }

  CollectionEvents _collectionEvents(Json value) {
    final events = value['records'] is List
        ? (value['records'] as List)
            .map((r) => CollectionEvent.fromRecord(r as Json))
            .toList()
        : (value['collection_events'] as List? ?? const [])
            .map((e) => CollectionEvent.fromJson(e as Json))
            .toList();
    return CollectionEvents(
      events,
      value['diagnosis_history_status'] as String? ?? 'unknown',
      replaySupported: value['replay_supported'] as bool? ?? false,
      resyncRequired: value['resync_required'] as bool? ?? false,
    );
  }

  @override
  Future<DiagnosticPage> diagnosticGaps({int limit = 50, String? cursor}) async {
    final value = await _settingsGet('/api/v2/diagnostics/gaps', {
      'limit': '$limit',
      if (cursor != null) 'cursor': cursor,
    });
    return DiagnosticPage.fromJson(value.$1);
  }

  @override
  Future<DiagnosticPage> healthHistory({int limit = 50, String? cursor}) async {
    final value = await _settingsGet('/api/v2/diagnostics/health-history', {
      'limit': '$limit',
      if (cursor != null) 'cursor': cursor,
    });
    return DiagnosticPage.fromJson(value.$1);
  }

  RestApi(this.base, {http.Client? client})
      : _rest = client ?? http.Client(),
        _dedicatedNodeClients = client == null;
  Uri uri(String path, [Map<String, String>? query]) {
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return Uri(
      scheme: base.scheme,
      userInfo: base.userInfo,
      host: base.host,
      port: base.port,
      path: '$prefix$path',
      queryParameters: query,
    );
  }

  Future<T> _parseContract<T>(String path, Future<T> Function() parse) async {
    try {
      return await parse();
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw ApiFailure(
        'Die API-Antwort verletzt den erwarteten Datenvertrag.',
        code: 'CONTRACT_ERROR',
        path: path,
      );
    }
  }

  Future<dynamic> _request(
      String path, Future<http.Response> Function() send) async {
    try {
      final response = await send().timeout(const Duration(seconds: 8));
      // The answer of the login carries the cookie of the session. A platform
      // without a browser keeps it for the following requests.
      rememberSessionCookie(response.headers['set-cookie']);
      if (response.statusCode != 200) {
        try {
          final body = jsonDecode(response.body) as Json;
          throw ApiFailure(
            body['message'] as String? ?? 'OIP-Server meldet einen Fehler.',
            code: body['code'] as String?,
            path: path,
            statusCode: response.statusCode,
          );
        } on ApiFailure {
          rethrow;
        } catch (_) {
          throw ApiFailure('OIP-Server meldet einen Fehler.',
              path: path, statusCode: response.statusCode);
        }
      }
      try {
        return jsonDecode(response.body);
      } catch (_) {
        throw ApiFailure(
          'Die API-Antwort ist kein gültiges JSON.',
          code: 'INVALID_RESPONSE',
          path: path,
        );
      }
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw ApiFailure(
        'OIP-Server nicht erreichbar.',
        code: 'CONNECTION_FAILED',
        path: path,
      );
    }
  }

  Future<dynamic> _get(String path, [Map<String, String>? query]) => _request(
      path, () => _rest.get(uri(path, query), headers: _sessionHeaders()));

  @override
  Future<Snapshot> initial() async {
    final values = await Future.wait([
      _get('/api/v1/system/status'),
      _get('/api/v1/devices'),
      _get('/api/v1/metrics/current'),
      _get('/api/v1/events'),
      _get('/api/v1/sources'),
    ]);
    return _parseContract(
        '/api/v1',
        () async => Snapshot.fromJson({
              'system': values[0],
              'devices': values[1],
              'metrics': values[2],
              'incidents': (values[3] as Json)['incidents'],
              'records': (values[3] as Json)['records'],
              'collection_events': (values[3] as Json)['collection_events'],
              'sources': values[4],
              // Topology is supplied by the first SSE snapshot; no REST route exists.
              'topology': <dynamic>[]
            }));
  }

  @override
  Stream<ServerEvent> stream() async* {
    _events?.close();
    final connection =
        openEvents(uri('/api/v1/stream'), cookieHeader: sessionCookieHeader());
    _events = connection;
    try {
      yield* connection.events;
    } finally {
      connection.close();
    }
  }

  @override
  Future<void> scenario(String name) async {
    await _request(
      '/api/v1/demo/scenario',
      () => _rest.post(
        uri('/api/v1/demo/scenario'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'scenario': name}),
      ),
    );
  }

  @override
  Future<List<SourceInfo>> sources() =>
      _parseContract('/api/v1/sources', () async {
        final value = await _get('/api/v1/sources') as List;
        return value.map((item) => SourceInfo.fromJson(item as Json)).toList();
      });

  @override
  Future<NodePage> nodes(String search, String folder, int offset,
      {String? source}) async {
    // A new production client aborts the previous in-flight node request when
    // supported by the platform. The page-level generation guard additionally
    // prevents every stale response from changing UI state. Injected test
    // clients stay shared so existing request/contract tests remain deterministic.
    http.Client? dedicated;
    if (_dedicatedNodeClients) {
      _nodesClient?.close();
      dedicated = http.Client();
      _nodesClient = dedicated;
    }
    final client = dedicated ?? _rest;
    try {
      return await _parseContract('/api/v1/opcua/nodes', () async {
        final value = await _request(
            '/api/v1/opcua/nodes',
            () => client.get(
                uri('/api/v1/opcua/nodes', {
                  'q': search,
                  'folder': folder,
                  'offset': '$offset',
                  'limit': '40',
                  if (source != null) 'source': source,
                }),
                headers: _sessionHeaders()));
        return NodePage.fromJson(value as Json);
      });
    } finally {
      dedicated?.close();
      if (identical(_nodesClient, dedicated)) _nodesClient = null;
    }
  }

  @override
  Future<List<Observation>> deviceMetrics(String id) async {
    final path = '/api/v1/devices/${Uri.encodeComponent(id)}';
    http.Client? dedicated;
    if (_dedicatedNodeClients) {
      _deviceClient?.close();
      dedicated = http.Client();
      _deviceClient = dedicated;
    }
    final client = dedicated ?? _rest;
    try {
      return await _parseContract(path, () async {
        final value = await _request(path, () => client.get(uri(path))) as Json;
        return (value['metrics'] as List)
            .map((v) => Observation.fromJson(v as Json))
            .toList();
      });
    } finally {
      dedicated?.close();
      if (identical(_deviceClient, dedicated)) _deviceClient = null;
    }
  }

  @override
  void cancelDeviceRequests() {
    _deviceClient?.close();
    _deviceClient = null;
  }

  @override
  Future<List<CollectionEvent>> collectionEvents() =>
      _parseContract('/api/v1/events', () async {
        final value = await _get('/api/v1/events') as Json;
        if (value['records'] is List) {
          return (value['records'] as List)
              .map((r) => CollectionEvent.fromRecord(r as Json))
              .toList();
        }
        return (value['collection_events'] as List? ?? const [])
            .map((event) => CollectionEvent.fromJson(event as Json))
            .toList();
      });

  Future<(dynamic, SettingsDataOrigin, String?)> _authorizedGet(
      String path, Map<String, String> query) async {
    http.Client? dedicated;
    final client = _dedicatedNodeClients ? (dedicated = http.Client()) : _rest;
    if (dedicated != null) _settingsClients.add(dedicated);
    try {
      // Deliberately no Authorization header, URL credential, storage token or
      // legacy-access fallback. OIP-009 must provide the secure browser identity.
      final response = await client.get(
        uri(path, query),
        headers: _sessionHeaders(const {'Accept': 'application/json'}),
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        String? serverCode;
        try {
          serverCode = (jsonDecode(response.body) as Json)['code'] as String?;
        } catch (_) {
          // Status mapping below remains deterministic for non-JSON errors.
        }
        final (message, code) = switch (response.statusCode) {
          401 => (
              'Keine autorisierte Browser-Identität für diesen Management-Read.',
              'UNAUTHENTICATED'
            ),
          403 => (
              'Browser-Session oder zentrale Policy erlaubt diesen Management-Read nicht.',
              'PERMISSION_DENIED'
            ),
          409 => (
              'Diese Management-Funktion wird vom Core nicht unterstützt.',
              'UNSUPPORTED'
            ),
          400 => (
              'Die Settings-Anfrage wurde vom Core-Vertrag abgelehnt.',
              'INVALID_REQUEST'
            ),
          _ => (
              'Management-Daten konnten nicht gelesen werden.',
              serverCode ?? 'HTTP_${response.statusCode}'
            ),
        };
        throw ApiFailure(message,
            code: code, path: path, statusCode: response.statusCode);
      }
      final body = jsonDecode(response.body);
      final marker = response.headers['x-oip-contract-fixture'];
      final fixture = marker == 'oip-0084-contract-fixture' ||
          marker == 'oip-009-contract-fixture';
      final fixturePrincipal = fixture
          ? response.headers['x-oip-contract-principal']
          : null;
      return (
        body,
        fixture
            ? SettingsDataOrigin.contractFixture
            : SettingsDataOrigin.liveApi,
        fixturePrincipal,
      );
    } on ApiFailure {
      rethrow;
    } on FormatException {
      throw ApiFailure(
        'Die Management-Antwort ist kein gültiges JSON-Objekt.',
        code: 'INVALID_RESPONSE',
        path: path,
      );
    } catch (_) {
      throw ApiFailure(
        'OIP-Server nicht erreichbar.',
        code: 'CONNECTION_FAILED',
        path: path,
      );
    } finally {
      if (dedicated != null) {
        _settingsClients.remove(dedicated);
        dedicated.close();
      }
    }
  }

  Future<(Json, SettingsDataOrigin, String?)> _settingsGet(
      String path, Map<String, String> query) async {
    final result = await _authorizedGet(path, query);
    if (result.$1 is! Json) {
      throw ApiFailure('Die Management-Antwort ist kein JSON-Objekt.',
          code: 'INVALID_RESPONSE', path: path);
    }
    return (result.$1 as Json, result.$2, result.$3);
  }

  void _checkContextOrigin(InfrastructureContext context,
      SettingsDataOrigin actual, String path) {
    final expected = context.origin == InfrastructureDataOrigin.contractFixture
        ? SettingsDataOrigin.contractFixture
        : SettingsDataOrigin.liveApi;
    if (context.origin == null || actual != expected) {
      throw ApiFailure('Die Provenienz des Kontext-Reads weicht vom Bootstrap ab.',
          code: 'PROVENANCE_MISMATCH', path: path);
    }
  }

  @override
  Future<SettingsSnapshot> settings({
    String scope = 'platform',
    String? scopeId,
    String? key,
    bool catalog = false,
  }) async {
    const scopes = {
      'platform',
      'organization',
      'infrastructure',
      'site',
      'source'
    };
    const keys = {
      null,
      'instance_name',
      'instance_description',
      'history_page_size'
    };
    if (!scopes.contains(scope) || !keys.contains(key)) {
      throw const ApiFailure('Ungültiger Settings-Scope oder Schlüssel.',
          code: 'INVALID_REQUEST');
    }
    final result = await _settingsGet('/api/v2/settings', {
      'scope': scope,
      if (scopeId != null) 'scope_id': scopeId,
      if (key != null) 'key': key,
      if (catalog) 'catalog': 'true',
    });
    try {
      return SettingsSnapshot.fromJson(result.$1, origin: result.$2);
    } catch (_) {
      throw const ApiFailure('Die Settings-Antwort verletzt den Core-Vertrag.',
          code: 'CONTRACT_ERROR', path: '/api/v2/settings');
    }
  }

  @override
  Future<ManagementReport> management(String section) async {
    const sections = {
      'server',
      'tools',
      'permissions',
      'sessions',
      'client_configuration',
      'diagnostics',
      'system',
      'storage',
      'security',
      'diagnostic_rules',
    };
    if (!sections.contains(section)) {
      throw const ApiFailure('Unbekannte Management-Sektion.',
          code: 'INVALID_REQUEST');
    }
    final result =
        await _settingsGet('/api/v2/management', {'section': section});
    try {
      return ManagementReport.fromJson(result.$1, origin: result.$2);
    } catch (_) {
      throw const ApiFailure(
          'Die Management-Antwort verletzt den Core-Vertrag.',
          code: 'CONTRACT_ERROR',
          path: '/api/v2/management');
    }
  }

  @override
  Future<InfrastructureBootstrap> infrastructureBootstrap() async {
    final bootstrap =
        await _parseContract('/api/v2', _readInfrastructureBootstrap);
    _managed = true;
    return bootstrap;
  }

  Future<InfrastructureBootstrap> _readInfrastructureBootstrap() async {
    Future<(List<Json>, SettingsDataOrigin)> page(String path) async {
      final items = <Json>[];
      var offset = 0;
      SettingsDataOrigin? origin;
      while (true) {
        final result = await _settingsGet(path, {
          'offset': '$offset',
          'limit': '100',
        });
        origin ??= result.$2;
        if (origin != result.$2) {
          throw ApiFailure('Gemischte Datenherkunft im Infrastructure Context.',
              code: 'CONTRACT_ERROR', path: path);
        }
        final batch = (result.$1['items'] as List).cast<Json>();
        items.addAll(batch);
        if (result.$1['has_more'] != true) break;
        offset += batch.length;
        if (batch.isEmpty || items.length > 10000) {
          throw ApiFailure(
              'Die autorisierte Hierarchie übersteigt den sicheren UI-Leseumfang.',
              code: 'CONTEXT_PAGE_LIMIT',
              path: path);
        }
      }
      return (items, origin);
    }

    final organizations = await page('/api/v2/organizations');
    final infrastructures = await page('/api/v2/infrastructures');
    final sites = await page('/api/v2/sites');
    final snapshot = await _settingsGet('/api/v2/snapshot', const {});
    for (final origin in [organizations.$2, infrastructures.$2, sites.$2]) {
      if (origin != snapshot.$2) {
        throw const ApiFailure(
            'Hierarchie und Snapshot haben unterschiedliche Provenienz.',
            code: 'CONTRACT_ERROR',
            path: '/api/v2/snapshot');
      }
    }
    List<InventoryDevice>? inventory;
    try {
      final result = await _settingsGet('/api/v2/inventory/devices', const {
        'limit': '100',
        'include_archived': 'false',
      });
      if (result.$2 != snapshot.$2) {
        throw const ApiFailure('Inventory-Provenienz weicht vom Snapshot ab.',
            code: 'CONTRACT_ERROR', path: '/api/v2/inventory/devices');
      }
      inventory = (result.$1['items'] as List)
          .map((item) => InventoryDevice.fromJson(item as Json))
          .toList();
      // OIP-008.5 uses bounded pages. Read every authorized page; has_more is
      // evaluated after filtering, never used as a hidden global total.
      var offset = inventory.length;
      while (result.$1['has_more'] == true) {
        final next = await _settingsGet('/api/v2/inventory/devices', {
          'offset': '$offset',
          'limit': '100',
          'include_archived': 'false',
        });
        final batch = (next.$1['items'] as List)
            .map((item) => InventoryDevice.fromJson(item as Json))
            .toList();
        if (batch.isEmpty) {
          throw const ApiFailure('Inventory-Paginierung ist inkonsistent.',
              code: 'CONTRACT_ERROR', path: '/api/v2/inventory/devices');
        }
        inventory.addAll(batch);
        offset += batch.length;
        if (next.$1['has_more'] != true) break;
        if (inventory.length > 2048) {
          throw const ApiFailure('Inventory überschreitet den Core-Bound.',
              code: 'CONTEXT_PAGE_LIMIT', path: '/api/v2/inventory/devices');
        }
      }
    } on ApiFailure catch (error) {
      // Canonical OIP-008.2 has no independent inventory route. That capability
      // is unknown, not an empty inventory and not a permission fallback.
      final unsupported = error.statusCode == 404 ||
          error.statusCode == 409 ||
          error.code == 'UNSUPPORTED';
      if (!unsupported) rethrow;
      inventory = null;
    }
    // The registry of the services that the operator declared. A Core that does
    // not deliver the route has **no** registry: that is unknown, not an empty
    // registry that would look like a measurement.
    List<ServiceRecord>? services;
    try {
      final result = await _settingsGet('/api/v2/services', const {
        'limit': '100',
      });
      if (result.$2 != snapshot.$2) {
        throw const ApiFailure('Service-Provenienz weicht vom Snapshot ab.',
            code: 'CONTRACT_ERROR', path: '/api/v2/services');
      }
      services = (result.$1['items'] as List)
          .map((item) => ServiceRecord.fromJson(item as Json))
          .toList();
      var offset = services.length;
      while (result.$1['has_more'] == true) {
        final next = await _settingsGet('/api/v2/services', {
          'offset': '$offset',
          'limit': '100',
        });
        final batch = (next.$1['items'] as List)
            .map((item) => ServiceRecord.fromJson(item as Json))
            .toList();
        if (batch.isEmpty) {
          throw const ApiFailure('Service-Paginierung ist inkonsistent.',
              code: 'CONTRACT_ERROR', path: '/api/v2/services');
        }
        services.addAll(batch);
        offset += batch.length;
        if (next.$1['has_more'] != true) break;
        if (services.length > 2048) {
          throw const ApiFailure('Service-Registry überschreitet den Core-Bound.',
              code: 'CONTEXT_PAGE_LIMIT', path: '/api/v2/services');
        }
      }
    } on ApiFailure catch (error) {
      final unsupported = error.statusCode == 404 ||
          error.statusCode == 409 ||
          error.code == 'UNSUPPORTED';
      if (!unsupported) rethrow;
      services = null;
    }
    List<DeterministicFinding>? findings;
    try {
      final loaded = <DeterministicFinding>[];
      var tooMany = false;
      String? cursor;
      while (true) {
        final result = await _settingsGet('/api/v2/diagnostics/findings', {
          'limit': '100',
          if (cursor != null) 'cursor': cursor,
        });
        if (result.$2 != snapshot.$2) {
          throw const ApiFailure('Findings-Provenienz weicht vom Snapshot ab.',
              code: 'CONTRACT_ERROR', path: '/api/v2/diagnostics/findings');
        }
        loaded.addAll((result.$1['items'] as List)
            .where((item) => (item as Json)['category'] == 'finding')
            .map((item) => DeterministicFinding.fromJson(
                (item as Json)['record'] as Json)));
        cursor = result.$1['next_cursor'] as String?;
        if (result.$1['truncated'] != true) break;
        if (cursor == null) {
          throw const ApiFailure('Findings sind ohne Cursor abgeschnitten.',
              code: 'CONTRACT_ERROR', path: '/api/v2/diagnostics/findings');
        }
        if (loaded.length > 1000) {
          tooMany = true;
          break;
        }
      }
      // No unbounded UI aggregate and no incomplete number presented as a
      // global count. The summary shows an overflow as unavailable.
      findings = tooMany ? null : loaded;
    } on ApiFailure catch (error) {
      final unavailable = error.statusCode == 401 ||
          error.statusCode == 403 ||
          error.statusCode == 404 ||
          error.statusCode == 409 ||
          error.code == 'UNSUPPORTED';
      if (!unavailable) rethrow;
      findings = null;
    }
    final authorized = AuthorizedSnapshot.fromJson(snapshot.$1);
    return InfrastructureBootstrap(
      principalIdentity: snapshot.$3,
      hierarchy: AuthorizedHierarchy(
        organizations: organizations.$1
            .map(AuthorizedOrganization.fromJson)
            .toList(),
        infrastructures: infrastructures.$1
            .map(AuthorizedInfrastructure.fromJson)
            .toList(),
        sites: sites.$1.map(AuthorizedSite.fromJson).toList(),
        locations: authorized.locations,
      ),
      snapshot: authorized,
      inventory: inventory,
      services: services,
      findings: findings,
      origin: snapshot.$2 == SettingsDataOrigin.contractFixture
          ? InfrastructureDataOrigin.contractFixture
          : InfrastructureDataOrigin.liveApi,
    );
  }

  @override
  Stream<ServerEvent> infrastructureStream() async* {
    _events?.close();
    final connection =
        openEvents(uri('/api/v2/stream'), cookieHeader: sessionCookieHeader());
    _events = connection;
    try {
      yield* connection.events;
    } finally {
      connection.close();
    }
  }

  @override
  Future<List<SourceInfo>> contextSources(InfrastructureContext context) async {
    if (!context.ready) return sources();
    // SourcesRead returns a bounded array without has_more. Offset paging is
    // therefore read until a short page; no hidden total is inferred.
    final result = <SourceInfo>[];
    var offset = 0;
    while (true) {
      final response = await _authorizedGet('/api/v2/sources', {
        ...context.selection.query,
        'offset': '$offset',
        'limit': '100',
      });
      _checkContextOrigin(context, response.$2, '/api/v2/sources');
      final value = response.$1 as List;
      final batch =
          value.map((item) => SourceInfo.fromJson(item as Json)).toList();
      result.addAll(batch);
      if (batch.length < 100) break;
      offset += batch.length;
      if (result.length > 10000) {
        throw const ApiFailure('Source-Umfang überschreitet den UI-Bound.',
            code: 'CONTEXT_PAGE_LIMIT', path: '/api/v2/sources');
      }
    }
    return result;
  }

  @override
  Future<NodePage> contextNodes(
    String search,
    String folder,
    int offset,
    InfrastructureContext context, {
    String? source,
  }) async {
    final selectedSource = source ?? context.selection.sourceId;
    if (!context.ready) {
      return nodes(search, folder, offset, source: selectedSource);
    }
    if (selectedSource == null) {
      throw const ApiFailure(
          'Für Node-Browsing muss eine eindeutige Source ausgewählt werden.',
          code: 'SOURCE_REQUIRED',
          path: '/api/v2/opcua/nodes');
    }
    const path = '/api/v2/opcua/nodes';
    return _parseContract(path, () async {
      final result = await _authorizedGet(path, {
        'q': search,
        'folder': folder,
        'offset': '$offset',
        'limit': '40',
        'source': selectedSource,
      });
      _checkContextOrigin(context, result.$2, path);
      return NodePage.fromJson(result.$1 as Json);
    });
  }

  @override
  Future<List<Observation>> contextDeviceMetrics(
      String id, InfrastructureContext context) async {
    if (!context.ready) return deviceMetrics(id);
    final path = '/api/v2/devices/${Uri.encodeComponent(id)}';
    final result = await _settingsGet(path, const {});
    _checkContextOrigin(context, result.$2, path);
    return (result.$1['metrics'] as List)
        .map((item) => Observation.fromJson(item as Json))
        .toList();
  }

  @override
  Future<List<CollectionEvent>> contextCollectionEvents(
          InfrastructureContext context) async =>
      (await contextEventPage(context)).events;

  @override
  Future<ContextEventPage> contextEventPage(InfrastructureContext context,
      {String? cursor}) async {
    if (!context.ready) {
      return ContextEventPage(
        events: await collectionEvents(),
        truncated: false,
        nextCursor: null,
        missingEvidence: const [],
        timeSemantics: 'current_window',
      );
    }
    final result = await _settingsGet('/api/v2/events/history', {
      ...context.selection.query,
      'limit': '100',
      if (cursor != null) 'cursor': cursor,
    });
    _checkContextOrigin(context, result.$2, '/api/v2/events/history');
    return ContextEventPage(
      events: (result.$1['items'] as List)
          .where((item) => (item as Json)['category'] == 'event')
          .map((item) => CollectionEvent.fromDiagnostic(item as Json))
          .toList(),
      truncated: result.$1['truncated'] as bool,
      nextCursor: result.$1['next_cursor'] as String?,
      missingEvidence: (result.$1['missing_evidence'] as List)
          .map((item) => item as String)
          .toList(),
      timeSemantics: result.$1['time_semantics'] as String,
    );
  }

  @override
  void cancelContextRequests() => cancelSettingsRequests();

  @override
  void cancelSettingsRequests() {
    for (final client in _settingsClients) {
      client.close();
    }
    _settingsClients.clear();
  }

  @override
  void disconnect() {
    cancelDeviceRequests();
    cancelSettingsRequests();
    _events?.close();
    _events = null;
  }

  @override
  void close() {
    disconnect();
    _nodesClient?.close();
    _nodesClient = null;
    cancelDeviceRequests();
    _rest.close();
  }
}
