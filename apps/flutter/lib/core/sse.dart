import 'dart:async';

class ServerEvent {
  final String type, data;
  const ServerEvent(this.type, this.data);
}

/// Parses the SSE wire format after UTF-8 and line decoding. CRLF, chunk
/// boundaries, comments and multiline data are handled without platform APIs.
Stream<ServerEvent> decodeEvents(Stream<String> lines) async* {
  var type = 'message';
  final data = <String>[];
  await for (final line in lines) {
    if (line.isEmpty) {
      if (data.isNotEmpty) yield ServerEvent(type, data.join('\n'));
      type = 'message';
      data.clear();
    } else if (!line.startsWith(':')) {
      final colon = line.indexOf(':');
      final field = colon < 0 ? line : line.substring(0, colon);
      var value = colon < 0 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      if (field == 'event') type = value;
      if (field == 'data') data.add(value);
    }
  }
}
