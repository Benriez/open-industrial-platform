import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/event_connection.dart';
import '../core/sse.dart';

EventConnection openEvents(Uri uri) {
  final client = http.Client();
  Stream<ServerEvent> read() async* {
    try {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw StateError('SSE rejected');
      yield* decodeEvents(response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter()));
    } finally {
      client.close();
    }
  }

  return EventConnection(read(), client.close);
}
