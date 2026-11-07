import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/sse.dart';
import '../core/event_connection.dart';
import 'event_transport.dart';
import '../models/contracts.dart';
import '../models/onboarding.dart';

abstract class OipApi {
  Future<Snapshot> initial();
  Stream<ServerEvent> stream();
  Future<void> scenario(String name);
  Future<NodePage> nodes(String search, String folder, int offset);
  Future<List<Observation>> deviceMetrics(String id);
  Future<List<CollectionEvent>> collectionEvents();
  void disconnect();
  void close();
}

class ApiFailure implements Exception {
  final String message;
  final String? code;
  final String? path;
  const ApiFailure(this.message, {this.code, this.path});
  @override
  String toString() => code == null ? message : '$message [$code]';
}

/// Public, sanitized error text. Internal exception objects never reach the UI.
String apiErrorMessage(Object error, String fallback) {
  if (error is! ApiFailure) return fallback;
  final code = error.code == null ? '' : ' (${error.code})';
  return '${error.message}$code';
}

abstract class DeviceManagementApi {
  bool get managed;
  Future<BrowserSession> session();
  Future<BrowserSession> login(String code);
  Future<void> logout();
  Future<List<HierarchyItem>> hierarchy(
      String level, Map<String, String> scope);
  Future<Json> inventory(String id);
  Future<void> register(Json device);
  Future<ConnectionResult> connection({String? deviceId, String? planId});
  Future<ConnectionResult> configure(Json action);
}

class RestApi implements OipApi, DeviceManagementApi {
  final Uri base;
  final http.Client _rest;
  EventConnection? _events;
  String? _csrf;
  bool _managed = false;
  @override
  bool get managed => _managed;
  Future<dynamic> _change(String path, Json body, {String method = 'POST'}) =>
      _request(path, () {
        final headers = {
          'Content-Type': 'application/json',
          if (_csrf != null) 'x-oip-csrf': _csrf!
        };
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

  RestApi(this.base, {http.Client? client}) : _rest = client ?? http.Client();
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
      if (response.statusCode != 200) {
        try {
          final body = jsonDecode(response.body) as Json;
          throw ApiFailure(
            body['message'] as String? ?? 'OIP-Server meldet einen Fehler.',
            code: body['code'] as String?,
            path: path,
          );
        } on ApiFailure {
          rethrow;
        } catch (_) {
          throw ApiFailure('OIP-Server meldet einen Fehler.', path: path);
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

  Future<dynamic> _get(String path, [Map<String, String>? query]) =>
      _request(path, () => _rest.get(uri(path, query)));

  @override
  Future<Snapshot> initial() async {
    if (_managed) {
      return _parseContract(
          '/api/v2/snapshot',
          () async =>
              Snapshot.fromScopedJson(await _get('/api/v2/snapshot') as Json));
    }
    final values = await Future.wait([
      _get('/api/v1/system/status'),
      _get('/api/v1/devices'),
      _get('/api/v1/metrics/current'),
      _get('/api/v1/events'),
    ]);
    return _parseContract(
        '/api/v1',
        () async => Snapshot.fromJson({
              'system': values[0],
              'devices': values[1],
              'metrics': values[2],
              'incidents': (values[3] as Json)['incidents'],
              // Topology is supplied by the first SSE snapshot; no REST route exists.
              'topology': <dynamic>[]
            }));
  }

  @override
  Stream<ServerEvent> stream() async* {
    _events?.close();
    final connection =
        openEvents(uri(_managed ? '/api/v2/stream' : '/api/v1/stream'));
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
  Future<NodePage> nodes(String search, String folder, int offset) async {
    if (_managed) {
      throw const ApiFailure(
          'Für OPC UA ist eine explizite autorisierte Source-Auswahl erforderlich.',
          code: 'SOURCE_CONTEXT_REQUIRED');
    }
    return _parseContract('/api/v1/opcua/nodes', () async {
      final value = await _get('/api/v1/opcua/nodes',
          {'q': search, 'folder': folder, 'offset': '$offset', 'limit': '40'});
      return NodePage.fromJson(value as Json);
    });
  }

  @override
  Future<List<Observation>> deviceMetrics(String id) {
    final path =
        '/api/${_managed ? 'v2' : 'v1'}/devices/${Uri.encodeComponent(id)}';
    return _parseContract(path, () async {
      final value = await _get(path) as Json;
      return (value['metrics'] as List)
          .map((v) => Observation.fromJson(v as Json))
          .toList();
    });
  }

  @override
  Future<List<CollectionEvent>> collectionEvents() =>
      _parseContract('/api/v1/events', () async {
        final value =
            await _get(_managed ? '/api/v2/events' : '/api/v1/events') as Json;
        if (value['records'] is List) {
          return (value['records'] as List)
              .map((r) => CollectionEvent.fromRecord(r as Json))
              .toList();
        }
        return (value['collection_events'] as List? ?? const [])
            .map((event) => CollectionEvent.fromJson(event as Json))
            .toList();
      });

  @override
  void disconnect() {
    _events?.close();
    _events = null;
  }

  @override
  void close() {
    disconnect();
    _rest.close();
  }
}
