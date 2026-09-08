import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';

import 'station_lock_discovery.dart';
import 'websocket_tree_wire_source.dart';

part 'live_connection_controller.freezed.dart';

const _manualValidationMessage =
    'Enter host:port or an absolute http(s) control URL with an explicit port '
    'and a non-empty token.';

/// All observable live-connection outcomes.
@freezed
sealed class LiveConnectionState with _$LiveConnectionState {
  /// No connection has been attempted or the user disconnected.
  const factory LiveConnectionState.disconnected() = LiveDisconnected;

  /// Local station discovery is in progress.
  const factory LiveConnectionState.discovering() = LiveDiscovering;

  /// The current host cannot perform local station discovery.
  const factory LiveConnectionState.discoveryUnavailable() =
      LiveDiscoveryUnavailable;

  /// Manual credentials are required.
  const factory LiveConnectionState.manual({String? message}) = LiveManual;

  /// A live connection is being constructed.
  const factory LiveConnectionState.connecting() = LiveConnecting;

  /// Live snapshots are available from [source].
  const factory LiveConnectionState.connected({required TreeSource source}) =
      LiveConnected;

  /// The supplied manual connection details were invalid or failed.
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
  Future<void> autoConnect() async {
    if (_disposed) return;
    value = const LiveConnectionState.discovering();
    try {
      final record = await _discovery.discover();
      final controlUrl = _discoveredControlUrl(record.controlUrl);
      final token = record.token?.trim() ?? '';
      if (token.isEmpty) {
        throw const FormatException('station lock has no control bearer');
      }
      await _connect(controlUrl: controlUrl, token: token);
    } on StationLockDiscoveryUnavailable {
      if (!_disposed) {
        value = const LiveConnectionState.discoveryUnavailable();
      }
    } on Object catch (error) {
      if (!_disposed) {
        value = LiveConnectionState.manual(message: error.toString());
      }
    }
  }

  /// Compatibility spelling for existing DevTools consumers.
  Future<void> autoDiscover() => autoConnect();

  /// Normalizes, validates, and connects with manually supplied credentials.
  Future<void> connect({
    required String controlUrl,
    required String token,
  }) async {
    if (_disposed) return;
    final uri = _manualControlUrl(controlUrl);
    final bearer = token.trim();
    if (uri == null || bearer.isEmpty) {
      value = const LiveConnectionState.failed(
        message: _manualValidationMessage,
      );
      return;
    }
    try {
      await _connect(controlUrl: uri, token: bearer);
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

  Future<void> _connect({
    required Uri controlUrl,
    required String token,
  }) async {
    if (_disposed) return;
    value = const LiveConnectionState.connecting();
    final source = _connectSource(controlUrl: controlUrl, token: token);
    await _replaceSource(source);
    if (!_disposed) value = LiveConnectionState.connected(source: source);
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
      unawaited(source.dispose());
    }
    super.dispose();
  }
}

Uri _discoveredControlUrl(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  if (uri == null ||
      !uri.isAbsolute ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    throw const FormatException('station lock has no valid control URL');
  }
  return uri;
}

Uri? _manualControlUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final normalized = trimmed.contains('://') ? trimmed : 'http://$trimmed';
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      !uri.isAbsolute ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      !uri.hasPort) {
    return null;
  }
  return uri;
}
