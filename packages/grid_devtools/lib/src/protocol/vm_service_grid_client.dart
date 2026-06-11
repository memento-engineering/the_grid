import 'dart:async';

import 'package:vm_service/vm_service.dart';

import 'grid_exploration_client.dart';

/// JSON-RPC "method not found" — what the VM service returns when an
/// extension is not registered (the grid exploration host is absent).
const int _kMethodNotFoundRpc = -32601;

/// Production [GridExplorationClient] over an already-connected [VmService].
///
/// Built from a BORROWED connection (DevTools' shared `serviceManager.service`
/// pinned to the main isolate) — it never opens or disposes the websocket,
/// so a DevTools teardown does not kill the link, and the web build never
/// touches `dart:io` (no `vm_service_io`). The `serviceManager` plumbing
/// lives in `main.dart`; this class only knows about [VmService] + the
/// isolate id, so it can be exercised against a fake `VmService` if ever
/// needed (the widget tests use a fake `GridExplorationClient` instead).
class VmServiceGridClient implements GridExplorationClient {
  VmServiceGridClient(
    this._vm,
    this._isolateId, {
    String eventStreamId = kGridEventStreamId,
  }) : _eventStreamId = eventStreamId;

  final VmService _vm;
  final String _isolateId;
  final String _eventStreamId;

  StreamController<GridEventRecord>? _events;
  StreamSubscription<Event>? _extSub;

  @override
  Future<GridHandshake> handshake() async {
    final Map<String, Object?> json = await _call(kHandshakeExtension);
    return GridHandshake.fromWire(json);
  }

  @override
  Future<GridEventsPage> fetchEvents({int? limit}) async {
    final Map<String, Object?> json = await _call(
      kEventsExtension,
      args: {if (limit != null) 'limit': '$limit'},
    );
    return GridEventsPage.fromWire(json);
  }

  @override
  Stream<GridEventRecord> get eventStream {
    final existing = _events;
    if (existing != null) return existing.stream;
    // Broadcast so multiple panels can listen; subscribe to the VM
    // `Extension` stream lazily on first listen and tear down on cancel.
    final controller = StreamController<GridEventRecord>.broadcast(
      onListen: _subscribe,
      onCancel: _unsubscribe,
    );
    _events = controller;
    return controller.stream;
  }

  Future<void> _subscribe() async {
    // Idempotent: the VM rejects a second listen on the same stream, so
    // swallow the already-subscribed error (kStreamAlreadySubscribed).
    try {
      await _vm.streamListen(EventStreams.kExtension);
    } on RPCError {
      // already subscribed by DevTools or a prior listen — fine.
    }
    _extSub = _vm.onExtensionEvent.listen((event) {
      if (event.extensionKind != _eventStreamId) return;
      final data = event.extensionData?.data;
      if (data == null) return;
      final record = GridEventRecord.fromWire(data);
      if (record != null) _events?.add(record);
    });
  }

  Future<void> _unsubscribe() async {
    await _extSub?.cancel();
    _extSub = null;
  }

  Future<Map<String, Object?>> _call(
    String extension, {
    Map<String, dynamic> args = const {},
  }) async {
    try {
      final Response r = await _vm.callServiceExtension(
        extension,
        isolateId: _isolateId,
        args: args,
      );
      return r.json ?? const <String, Object?>{};
    } on RPCError catch (e) {
      if (extension == kHandshakeExtension && e.code == _kMethodNotFoundRpc) {
        throw const GridBindingMissing();
      }
      rethrow;
    }
  }

  /// Releases the local event subscription. Does NOT dispose the borrowed
  /// [VmService] — DevTools owns its lifetime.
  Future<void> dispose() async {
    await _extSub?.cancel();
    _extSub = null;
    await _events?.close();
    _events = null;
  }
}
