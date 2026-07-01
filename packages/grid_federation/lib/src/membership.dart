/// **Static** membership — a station's explicitly configured peer list (ADR-0011
/// D4). No discovery this round: each station declares its peers (address +
/// shared token) and grows the federation by editing config. The membership seam
/// is shaped so dynamic discovery drops in BEHIND it later as
/// `zero_conf_grid_assets` (zeroconf/mDNS) — itself the proof that discovery is
/// an asset in its own domain, not engine code.
///
/// Pure value types + an injectable loader: the loader reads through a
/// [ConfigReader] so tests need no real file IO, and the value types carry no
/// transport. `dart:io` is touched only by the default file reader.
library;

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// One configured peer station: where to reach it and the LAN-trust token to
/// present. The address ([host]:[port]) is the identity for the bus; [id] is a
/// human label.
@immutable
class Peer {
  /// Creates a peer config entry.
  const Peer({
    required this.id,
    required this.host,
    required this.port,
    this.token,
  });

  /// The peer's station id / human label (e.g. `the-dashboard`).
  final String id;

  /// The peer's host (e.g. `linux-dashboard.local`).
  final String host;

  /// The peer's port.
  final int port;

  /// The shared secret to present as `X-Grid-Token` (LAN trust, this pass);
  /// `null` when the peer requires no token.
  final String? token;

  /// `host:port`, the bus address.
  String get address => '$host:$port';

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'id': id,
    'host': host,
    'port': port,
    if (token != null) 'token': token,
  };

  /// Parses [j].
  static Peer fromJson(Map<String, dynamic> j) => Peer(
    id: j['id'] as String,
    host: j['host'] as String,
    port: j['port'] as int,
    token: j['token'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is Peer &&
      other.id == id &&
      other.host == host &&
      other.port == port &&
      other.token == token;

  @override
  int get hashCode => Object.hash(id, host, port, token);

  @override
  String toString() => 'Peer($id @ $address${token != null ? ' +token' : ''})';
}

/// A station's static membership: the ordered list of [peers] it federates with.
@immutable
class Membership {
  /// Creates a membership over [peers].
  const Membership({this.peers = const []});

  /// The configured peers, in declaration order.
  final List<Peer> peers;

  /// The peer with [id], or `null` if none is configured.
  Peer? byId(String id) {
    for (final p in peers) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'peers': [for (final p in peers) p.toJson()],
  };

  /// Parses [j] (a `{"peers": [...]}` document).
  static Membership fromJson(Map<String, dynamic> j) => Membership(
    peers: [
      for (final p in (j['peers'] as List? ?? const []))
        Peer.fromJson((p as Map).cast<String, dynamic>()),
    ],
  );

  /// Parses a JSON [source] string (the on-disk membership document).
  static Membership parse(String source) =>
      Membership.fromJson((jsonDecode(source) as Map).cast<String, dynamic>());
}

/// Reads the raw config text at [path]. Injected into [MembershipLoader] so tests
/// supply config inline (no real file IO); the default reads the file.
typedef ConfigReader = String Function(String path);

/// Loads [Membership] from an explicit config path through an injectable
/// [ConfigReader]. The default reader uses `dart:io`; tests pass a fake that
/// returns config text directly.
class MembershipLoader {
  /// Creates a loader; [reader] defaults to a synchronous file read.
  MembershipLoader({ConfigReader? reader}) : _reader = reader ?? _readFile;

  final ConfigReader _reader;

  /// Loads + parses the membership document at [path].
  Membership load(String path) => Membership.parse(_reader(path));

  static String _readFile(String path) => File(path).readAsStringSync();
}
