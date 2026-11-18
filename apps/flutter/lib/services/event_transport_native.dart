import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/event_connection.dart';
import '../core/sse.dart';

EventConnection openEvents(Uri uri, {String? cookieHeader}) {
  final client = http.Client();
  Stream<ServerEvent> read() async* {
    try {
      final request = http.Request('GET', uri);
      // The stream carries the identity of the session. The browser sends the
      // cookie on its own; the native client sends the cookie it holds.
      if (cookieHeader != null) request.headers['cookie'] = cookieHeader;
      final response =
          await client.send(request).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw http.ClientException(
            'SSE rejected (HTTP ${response.statusCode})', uri);
      }
      yield* decodeEvents(response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter()));
    } finally {
      client.close();
    }
  }

  return EventConnection(read(), client.close);
}
