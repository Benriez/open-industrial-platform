import 'sse.dart';

class EventConnection {
  final Stream<ServerEvent> events;
  final void Function() close;
  EventConnection(this.events, this.close);
}
