/// The lessor's lease bookkeeping — **declare-and-check** capacity (ADR-0008
/// resource governance) plus TTL reaping. Pure, synchronous, injectable clock +
/// id generator so it is fully testable without wall-clock or randomness.
library;

import 'protocol.dart';

/// One held lease: its kind + the instant after which it is reaped.
class _Held {
  _Held(this.kind, this.expiry);
  final String kind;
  DateTime expiry;
}

/// Tracks offered vs held slots for a single station and arbitrates leases.
class LeaseManager {
  /// Creates a manager offering [offered] slots of [kind] for [station], with a
  /// per-lease [ttl]. [clock] and [idGen] are injectable for tests.
  LeaseManager({
    required this.station,
    required this.offered,
    this.kind = 'compute',
    this.ttl = const Duration(seconds: 300),
    DateTime Function()? clock,
    String Function(int seq)? idGen,
  }) : _clock = clock ?? DateTime.now,
       _idGen = idGen ?? ((seq) => '$station-lease-$seq');

  /// The station id this manager speaks for.
  final String station;

  /// Total slots offered.
  final int offered;

  /// The resource-asset kind offered.
  final String kind;

  /// How long a lease lives without activity before it is reaped.
  final Duration ttl;

  final DateTime Function() _clock;
  final String Function(int seq) _idGen;
  final Map<String, _Held> _held = {};
  int _seq = 0;

  /// Free slots right now (after reaping expired leases).
  int get available {
    _reap();
    return offered - _held.length;
  }

  /// A presence snapshot.
  Presence get presence => Presence(
    station: station,
    kinds: [kind],
    offered: offered,
    available: available,
  );

  /// Grants a lease for [req], or throws [LeaseDeniedException] if the kind is
  /// not offered or there is no free capacity (fail-closed declare-and-check).
  LeaseGrant grant(LeaseRequest req) {
    _reap();
    if (req.kind != kind) {
      throw LeaseDeniedException('kind "${req.kind}" not offered (offers "$kind")');
    }
    if (_held.length >= offered) {
      throw const LeaseDeniedException('no capacity');
    }
    final id = _idGen(_seq++);
    _held[id] = _Held(kind, _clock().add(ttl));
    return LeaseGrant(
      leaseId: id,
      station: station,
      ttlSeconds: ttl.inSeconds,
      kind: kind,
    );
  }

  /// Whether [leaseId] is currently a live (non-expired) lease.
  bool isValid(String leaseId) {
    _reap();
    return _held.containsKey(leaseId);
  }

  /// Extends [leaseId]'s TTL on activity (a dispatch). Throws
  /// [LeaseInvalidException] if the lease is unknown/expired.
  void touch(String leaseId) {
    if (!isValid(leaseId)) {
      throw LeaseInvalidException('lease "$leaseId" is unknown or expired');
    }
    _held[leaseId]!.expiry = _clock().add(ttl);
  }

  /// Releases [leaseId], freeing its slot. Idempotent (releasing an
  /// unknown/already-released lease is a no-op).
  void release(String leaseId) => _held.remove(leaseId);

  void _reap() {
    final now = _clock();
    _held.removeWhere((_, h) => !h.expiry.isAfter(now));
  }
}
