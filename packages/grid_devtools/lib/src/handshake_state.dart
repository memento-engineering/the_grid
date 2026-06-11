import 'protocol/grid_exploration_client.dart';

/// State of the latest `ext.exploration.core.handshake` probe, rendered by
/// the shell via a `ValueListenable<HandshakeState>` so the UI reacts to
/// (re)connects without rebuilding the whole tree.
///
/// Mirrors lenny's `ManifestProbeResult`, scoped to grid_devtools: it carries
/// [GridHandshake] (the wire-shape value type re-declared in
/// `grid_exploration_client.dart`) rather than lenny's
/// `PluginManifestEntry`.
sealed class HandshakeState {
  const HandshakeState();
}

/// Probe is in flight; the shell renders a spinner.
class HandshakeLoading extends HandshakeState {
  const HandshakeLoading();
}

/// Probe succeeded; [handshake] carries the protocol version + advertised
/// plugins/tools.
class HandshakeLoaded extends HandshakeState {
  const HandshakeLoaded(this.handshake);
  final GridHandshake handshake;
}

/// The grid exploration host's extensions are not registered in the
/// attached process (handshake "method not found"). Rendered as a distinct
/// "no grid host detected" banner.
class HandshakeBindingMissing extends HandshakeState {
  const HandshakeBindingMissing();
}

/// Probe failed for some other reason — connection error, malformed
/// response. [message] is the surfaced detail.
class HandshakeFailed extends HandshakeState {
  const HandshakeFailed(this.message);
  final String message;
}
