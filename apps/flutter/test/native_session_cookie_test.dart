import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oip_dashboard/services/api.dart';

/// The session cookie of the native client.
///
/// The browser of the web release stores the cookie of the Core on its own.
/// The native application has no browser: the client itself must keep the
/// cookie and send it with every request. Without it the native bundle can
/// never hold a session — the operator would authorize the session and the
/// Core would refuse every following read.
///
/// The server of this test is the contract of the Core: the login answers
/// with the `Set-Cookie` of the session and every other route refuses a
/// request without that cookie.

void main() {
  late HttpServer server;
  late List<String> seenCookies;

  setUp(() async {
    seenCookies = <String>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final cookie = request.headers.value(HttpHeaders.cookieHeader);
      seenCookies.add(cookie ?? '');
      final response = request.response;
      response.headers.contentType = ContentType.json;
      final path = request.uri.path;
      if (path == '/api/v2/browser/login') {
        response.statusCode = 200;
        response.headers.set(HttpHeaders.setCookieHeader,
            'oip_session=the-session-token; HttpOnly; SameSite=Strict; Path=/; Max-Age=1800');
        response.write(jsonEncode({
          'principal_id': 'reader-org-a',
          'authenticated': true,
          'mode': 'managed_local_operator',
          'csrf_token': 'the-csrf-token',
        }));
        await response.close();
        return;
      }
      if (cookie == null || !cookie.contains('oip_session=')) {
        response.statusCode = 403;
        response.write(jsonEncode({
          'code': 'PERMISSION_DENIED',
          'kind': 'permission_denied',
          'message':
              'Browser-Session oder zentrale Policy erlaubt diesen Management-Read nicht.',
          'ok': false,
        }));
        await response.close();
        return;
      }
      response.statusCode = 200;
      response.write(jsonEncode({
        'items': [
          {'id': 'org-a', 'name': 'Organization A', 'parent_id': null},
        ],
      }));
      await response.close();
    });
  });

  tearDown(() async => await server.close(force: true));

  test('The native client keeps the session cookie of the Core', () async {
    final api = RestApi(Uri.parse('http://127.0.0.1:${server.port}'));

    final session = await api.login('the-one-time-code');
    expect(session.authenticated, isTrue);

    // The read after the login must carry the cookie of the session.
    final items = await api.hierarchy('organizations', {});
    expect(items, hasLength(1));
    expect(seenCookies.any((cookie) => cookie.contains('oip_session=')), isTrue,
        reason: 'the request after the login carried no session cookie');
  });

  test('An older session read cannot clear the CSRF token from a newer login',
      () async {
    final pending = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.method == 'GET') return pending.future;
      if (request.url.path == '/api/v2/browser/login') {
        return http.Response(jsonEncode({
          'authenticated': true,
          'mode': 'managed_local_operator',
          'csrf_token': 'fresh-token',
        }), 200);
      }
      expect(request.method, 'DELETE');
      expect(request.headers['x-oip-csrf'], 'fresh-token');
      return http.Response('{}', 200);
    });
    final api = RestApi(Uri.parse('http://127.0.0.1:${server.port}'),
        client: client);
    addTearDown(api.close);
    final staleRead = api.session();
    await api.login('one-time-code');
    pending.complete(http.Response(jsonEncode({
      'authenticated': false,
      'mode': 'managed_local_operator',
    }), 200));
    expect((await staleRead).authenticated, isFalse);

    await api.logout();
  });
}
