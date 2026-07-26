import 'dart:async';
import 'dart:convert';

import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Injectable browser-compatible WebSocket connection seam.
typedef WebSocketConnector =
    WebSocketChannel Function(Uri uri, {required Iterable<String> protocols});

/// A live tree wire source backed by the station's `/stream` door.
final class WebSocketTreeWireSource implements TreeWireSource {
  WebSocketTreeWireSource._(this._channel) {
    _subscription = _channel.stream.listen(
      _onFrame,
      onError: _controller.addError,
      onDone: _controller.close,
    );
  }

  /// Connects to [controlUrl] using the station bearer subprotocol.
  static WebSocketTreeWireSource connect({
    required Uri controlUrl,
    required String token,
    WebSocketConnector connector = WebSocketChannel.connect,
  }) {
    final uri = Uri(
      scheme: controlUrl.scheme == 'https' ? 'wss' : 'ws',
      host: controlUrl.host,
      port: controlUrl.hasPort ? controlUrl.port : null,
      path: '/stream',
    );
    return WebSocketTreeWireSource._(
      connector(
        uri,
        protocols: <String>['$stationTreeBearerProtocolPrefix$token'],
      ),
    );
  }

  final WebSocketChannel _channel;
  final _controller = StreamController<TreeSnapshot>.broadcast(sync: true);
  late final StreamSubscription<Object?> _subscription;
  TreeSnapshot? _latest;
  bool _disposed = false;

  @override
  TreeSnapshot? get latest => _latest;

  @override
  Stream<TreeSnapshot> get snapshots => _controller.stream;

  void _onFrame(Object? frame) {
    try {
      final decoded = jsonDecode(frame as String);
      final snapshot = TreeSnapshot.fromJson(
        (decoded as Map).cast<String, Object?>(),
      );
      _latest = snapshot;
      _controller.add(snapshot);
    } on Object catch (error, stack) {
      _controller.addError(error, stack);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription.cancel();
    await _channel.sink.close();
    if (!_controller.isClosed) await _controller.close();
  }
}
