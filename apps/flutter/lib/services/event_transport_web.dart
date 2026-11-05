import 'dart:async';
// Dart 3.4 / Flutter 3.22: native EventSource streams immediately, whereas the
// compatible package:http BrowserClient buffers responses until completion.
// Conditional transport adapter; this file is excluded from every native build.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import '../core/event_connection.dart';
import '../core/sse.dart';

EventConnection openEvents(Uri uri) {
  final source = html.EventSource(uri.toString());
  final controller = StreamController<ServerEvent>();
  var closed = false;
  late StreamSubscription<html.Event> offline;
  void onSnapshot(html.Event event) {
    if (!closed && event is html.MessageEvent && event.data is String) {
      controller.add(ServerEvent('snapshot', event.data as String));
    }
  }

  void onError(html.Event event) {
    if (closed) return;
    // The server uses a named `error` SSE event for storage failures. A native
    // EventSource error without message data instead denotes a transport loss.
    if (event is html.MessageEvent && event.data is String) {
      controller.add(ServerEvent('error', event.data as String));
    } else {
      controller.addError(StateError('SSE connection lost'));
    }
  }

  void close() {
    if (closed) return;
    closed = true;
    source.removeEventListener('snapshot', onSnapshot);
    source.removeEventListener('error', onError);
    source.close();
    unawaited(offline.cancel());
    controller.close();
  }

  // Browsers can keep an established SSE socket alive while reporting offline.
  // Treat the browser offline signal as a transport loss independently.
  offline = html.window.onOffline.listen(onError);
  if (html.window.navigator.onLine == false) {
    scheduleMicrotask(() => onError(html.Event('offline')));
  }
  source.addEventListener('snapshot', onSnapshot);
  source.addEventListener('error', onError);
  controller.onCancel = close;
  return EventConnection(controller.stream, close);
}
