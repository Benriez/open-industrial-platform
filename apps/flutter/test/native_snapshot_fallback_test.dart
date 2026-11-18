import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/services/api.dart';

void main() {
  for (final sendError in [false, true]) {
    test(
        'macOS polls a fresh snapshot after a stream ${sendError ? 'error' : 'stall'}',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final api = RestApi(Uri.parse('http://127.0.0.1:${server.port}'));
      addTearDown(api.close);
      final requested = <String>[];
      server.listen((request) async {
        requested.add(request.uri.path);
        final response = request.response;
        if (request.uri.path == '/api/v2/stream') {
          response.headers.contentType = ContentType('text', 'event-stream');
          response.write(sendError
              ? 'event: error\ndata: {"code":"temporarily_unavailable"}\n\n'
              : ': connected\n\n');
          await response.flush();
          return;
        }
        // Switching the selected infrastructure cancels workspace reads, not
        // this global authorized snapshot.
        api.cancelContextRequests();
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({'resync_required': true}));
        await response.close();
      });

      final event = await api
          .infrastructureStream()
          .first
          .timeout(const Duration(seconds: 16));
      expect(event.type, 'snapshot');
      expect(jsonDecode(event.data), {'resync_required': true});
      expect(requested, ['/api/v2/stream', '/api/v2/snapshot']);
    });
  }
}
