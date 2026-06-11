import 'dart:async';

import 'package:grid_devtools/grid_devtools.dart';

/// In-memory [GridExplorationClient] for widget/unit tests — fakes not mocks.
///
/// Drives the panels with no live VM service: [seedEvents] is what
/// [fetchEvents] returns, [emit] pushes a record onto [eventStream], and
/// [handshakeResult]/[handshakeError] control the probe outcome. Records
/// every call for assertions.
class FakeGridExplorationClient implements GridExplorationClient {
  FakeGridExplorationClient({
    GridHandshake? handshake,
    this.handshakeError,
    List<GridEventRecord> seedEvents = const [],
  }) : handshakeResult =
           handshake ??
           const GridHandshake(
             protocolVersion: '1',
             plugins: [
               GridPlugin(
                 namespace: 'grid',
                 tools: ['requery', 'snapshot', 'ready', 'events', 'stats'],
               ),
             ],
           ),
       _seedEvents = List<GridEventRecord>.unmodifiable(seedEvents);

  GridHandshake handshakeResult;

  /// When non-null, [handshake] throws this instead of returning a result.
  Object? handshakeError;

  final List<GridEventRecord> _seedEvents;

  final _controller = StreamController<GridEventRecord>.broadcast();

  int handshakeCalls = 0;
  final List<int?> fetchEventsLimits = <int?>[];

  @override
  Future<GridHandshake> handshake() async {
    handshakeCalls++;
    final error = handshakeError;
    if (error != null) throw error;
    return handshakeResult;
  }

  @override
  Future<GridEventsPage> fetchEvents({int? limit}) async {
    fetchEventsLimits.add(limit);
    return GridEventsPage(count: _seedEvents.length, events: _seedEvents);
  }

  @override
  Stream<GridEventRecord> get eventStream => _controller.stream;

  /// Push a record onto the live stream as the host would.
  void emit(GridEventRecord record) => _controller.add(record);

  Future<void> dispose() => _controller.close();
}
