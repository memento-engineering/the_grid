import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';

import 'station_lock_discovery.dart';
import 'websocket_tree_wire_source.dart';

part 'live_connection_controller.freezed.dart';

/// All observable live-connection outcomes.
@freezed
sealed class LiveConnectionState with _$LiveConnectionState {
  /// No connection has been attempted or the user disconnected.
  const factory LiveConnectionState.disconnected() = LiveDisconnected;

  /// Local station discovery is in progress.
  const factory LiveConnectionState.discovering() = LiveDiscovering;

  /// Manual credentials are required.
  const factory LiveConnectionState.manual({String? message}) = LiveManual;

  /// A manually supplied connection is being constructed.
  const factory LiveConnectionState.connecting() = LiveConnecting;

  /// Live snapshots are available from [source].
  const factory LiveConnectionState.connected({required TreeSource source}) =
      LiveConnected;

  /// The supplied connection details were invalid.
  const factory LiveConnectionState.failed({required String message}) =
      LiveFailed;
}

/// Constructs an owned live tree source.
typedef LiveTreeSourceConnector =
    TreeSource Function({required Uri controlUrl, required String token});

TreeSource _connectLiveSource({
  required Uri controlUrl,
  required String token,
}) => LiveTreeSource(
  WebSocketTreeWireSource.connect(controlUrl: controlUrl, token: token),
);

/// Owns discovery, validation, connection state, and live-source disposal.
final class LiveConnectionController
    extends ValueNotifier<LiveConnectionState> {
  /// Creates a disconnected controller.
  LiveConnectionController({
    required StationLockDiscovery discovery,
    LiveTreeSourceConnector connectSource = _connectLiveSource,
  }) : _discovery = discovery,
       _connectSource = connectSource,
       super(const LiveConnectionState.disconnected());

  final StationLockDiscovery _discovery;
  final LiveTreeSourceConnector _connectSource;
  TreeSource? _ownedSource;
  bool _disposed = false;

  /// Attempts local lock discovery once, falling back to manual entry.
  Future<void> autoDiscover() async {
    if (_disposed) return;
    value = const LiveConnectionState.discovering();
    try {
      final record = await _discovery.discover();
      await connect(controlUrl: record.controlUrl!, token: record.token!);
    } on Object catch (error) {
      if (!_disposed) {
        value = LiveConnectionState.manual(message: error.toString());
      }
    }
  }

  /// Validates and connects with explicit station credentials.
  Future<void> connect({
    required String controlUrl,
    required String token,
  }) async {
    if (_disposed) return;
    final uri = Uri.tryParse(controlUrl.trim());
    if (uri == null ||
        !uri.isAbsolute ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        token.trim().isEmpty) {
      value = const LiveConnectionState.failed(
        message: 'Enter an absolute http(s) URL and a non-empty token.',
      );
      return;
    }
    value = const LiveConnectionState.connecting();
    try {
      final source = _connectSource(controlUrl: uri, token: token.trim());
      await _replaceSource(source);
      if (!_disposed) value = LiveConnectionState.connected(source: source);
    } on Object catch (error) {
      if (!_disposed) {
        value = LiveConnectionState.failed(message: error.toString());
      }
    }
  }

  /// Disconnects and disposes the currently owned source.
  Future<void> disconnect() async {
    await _replaceSource(null);
    if (!_disposed) value = const LiveConnectionState.disconnected();
  }

  Future<void> _replaceSource(TreeSource? replacement) async {
    final previous = _ownedSource;
    _ownedSource = replacement;
    if (previous != null && !identical(previous, replacement)) {
      await previous.dispose();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final source = _ownedSource;
    _ownedSource = null;
    if (source != null) {
      // ValueNotifier disposal cannot await transport shutdown.
      source.dispose();
    }
    super.dispose();
  }
}
