/// The lessor's lease bookkeeping — the owner-authoritative serialization point
/// (ADR-0011 D5). It bakes in the four hard-earned federation hazards:
///
/// 1. **Fencing** — every grant carries an owner-issued monotonically increasing
///    [LeaseGrant.fencingToken]; a dispatch/release with a stale token is refused
///    ([LeaseInvalidException]). No zombie double-use after reap+reissue.
/// 2. **Max lifetime + a FIFO wait-queue** — a lease has a hard lifetime (caps
///    total TTL renewal → no incumbent monopoly); when capacity is full, requests
///    enqueue FIFO (bounded) and are granted in arrival order as slots free → a
///    starvation bound, no priority/aging.
/// 3. **Owner-clock reaping** — ALL expiry/lifetime math uses the owner's
///    injectable [clock]; no cross-machine timestamp arithmetic. Fencing uses the
///    owner's monotonic version counter, never wall-time.
/// 4. **Idempotency** — a [LeaseRequest.idempotencyKey] dedups: a retried request
///    returns the SAME live grant, never a second grant.
///
/// Pure, synchronous, injectable clock + id generator so it is fully testable
/// without a wall-clock, randomness, or real IO.
library;

import 'dart:async';

import 'protocol.dart';

/// One held lease: its kind, the idle-TTL expiry (renewed by [LeaseManager.touch]),
/// the immovable max-lifetime deadline, the fencing token, and the (optional)
/// idempotency key it was granted under.
class _Held {
  _Held({
    required this.kind,
    required this.expiry,
    required this.hardDeadline,
    required this.fencingToken,
    required this.idempotencyKey,
  });

  final String kind;
  DateTime expiry;
  final DateTime hardDeadline;
  final int fencingToken;
  final String idempotencyKey;
}

/// A queued lease request awaiting capacity (FIFO). [deadline] is the
/// owner-clock instant after which the wait is denied.
class _Waiter {
  _Waiter(this.req, this.completer, this.deadline);

  final LeaseRequest req;
  final Completer<LeaseGrant> completer;
  final DateTime deadline;
}

/// Tracks offered vs held slots for a single station and arbitrates leases.
class LeaseManager {
  /// Creates a manager offering [offered] slots of [kind] for [station].
  ///
  /// [ttl] is the idle-renewal window (each [touch] extends it). [maxLifetime] is
  /// the immovable cap on a lease's total life (renewal cannot push past it).
  /// [maxQueueDepth] bounds the FIFO wait-queue. [clock] and [idGen] are
  /// injectable for deterministic tests.
  LeaseManager({
    required this.station,
    required this.offered,
    this.kind = 'compute',
    this.ttl = const Duration(seconds: 300),
    this.maxLifetime = const Duration(seconds: 3600),
    this.maxQueueDepth = 64,
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

  /// The immovable cap on a lease's total life (TTL renewal cannot exceed it).
  final Duration maxLifetime;

  /// The maximum number of requests that may wait in the FIFO queue.
  final int maxQueueDepth;

  final DateTime Function() _clock;
  final String Function(int seq) _idGen;
  final Map<String, _Held> _held = {};
  final Map<String, LeaseGrant> _grantsByKey = {};
  final List<_Waiter> _queue = [];
  int _seq = 0;
  int _fence = 0;

  /// Free slots right now (after reaping expired leases and draining the queue).
  ///
  /// Reading liveness also drives the queue: a slot freed by TTL/lifetime expiry
  /// is handed to the FIFO head here, so a waiter is released without a separate
  /// ticker (the spike already reaped on this read; this extends it to pump).
  int get available {
    _pump();
    return offered - _held.length;
  }

  /// The number of requests currently waiting in the FIFO queue.
  int get queued {
    _pump();
    return _queue.length;
  }

  /// A presence snapshot.
  Presence get presence => Presence(
    station: station,
    kinds: [kind],
    offered: offered,
    available: available,
  );

  /// Grants a lease for [req] IMMEDIATELY, or throws [LeaseDeniedException] if the
  /// kind is not offered or there is no free capacity (the synchronous
  /// declare-and-check; no queueing). Use [acquire] to opt into the FIFO wait.
  LeaseGrant grant(LeaseRequest req) {
    final g = _tryGrantNow(req);
    if (g == null) throw const LeaseDeniedException('no capacity');
    return g;
  }

  /// Requests a lease, optionally WAITING up to [maxWait] in the FIFO queue when
  /// capacity is full.
  ///
  /// - Free capacity (and no one ahead in the queue) → granted now.
  /// - Full + [maxWait] null/zero → denied immediately ([LeaseDeniedException]).
  /// - Full + the queue is already at [maxQueueDepth] → denied ('wait-queue
  ///   full').
  /// - Otherwise enqueued FIFO; granted in arrival order as slots free, or denied
  ///   ('wait expired') once [maxWait] passes by the owner clock.
  ///
  /// Idempotent: a retried [req] (same non-empty [LeaseRequest.idempotencyKey])
  /// returns the live grant, or attaches to the existing waiter — never a second
  /// grant.
  Future<LeaseGrant> acquire(LeaseRequest req, {Duration? maxWait}) {
    final LeaseGrant? now;
    try {
      now = _tryGrantNow(req);
    } on LeaseDeniedException catch (e) {
      return Future.error(e); // permanent deny (e.g. kind not offered)
    }
    if (now != null) return Future.value(now);

    if (maxWait == null || maxWait == Duration.zero) {
      return Future.error(const LeaseDeniedException('no capacity'));
    }
    // Idempotent retry that lands on an already-queued waiter.
    if (req.idempotencyKey.isNotEmpty) {
      for (final w in _queue) {
        if (w.req.idempotencyKey == req.idempotencyKey) {
          return w.completer.future;
        }
      }
    }
    if (_queue.length >= maxQueueDepth) {
      return Future.error(const LeaseDeniedException('wait-queue full'));
    }
    final w = _Waiter(req, Completer<LeaseGrant>(), _clock().add(maxWait));
    _queue.add(w);
    return w.completer.future;
  }

  /// Whether [leaseId] is currently a live (non-expired) lease.
  bool isValid(String leaseId) {
    _reap();
    return _held.containsKey(leaseId);
  }

  /// Extends [leaseId]'s idle TTL on activity (a dispatch), capped at the lease's
  /// max lifetime. Throws [LeaseInvalidException] if the lease is unknown/expired
  /// or [token] is stale (fencing).
  void touch(String leaseId, int token) {
    _validate(leaseId, token);
    final h = _held[leaseId]!;
    final renewed = _clock().add(ttl);
    h.expiry = renewed.isBefore(h.hardDeadline) ? renewed : h.hardDeadline;
    _pump();
  }

  /// Releases [leaseId], freeing its slot and draining the FIFO queue.
  ///
  /// Idempotent for the rightful holder: releasing an unknown/already-reaped lease
  /// is a no-op. But a [token] that does not match a STILL-LIVE lease is rejected
  /// ([LeaseInvalidException]) so a zombie cannot free the new holder's slot
  /// (fencing). Pass `null` only for internal/trusted cleanup.
  void release(String leaseId, {int? token}) {
    _reap();
    final h = _held[leaseId];
    if (h == null) {
      _pump();
      return; // idempotent
    }
    if (token != null && h.fencingToken != token) {
      throw LeaseInvalidException(
        'stale fencing token $token for lease "$leaseId" '
        '(current ${h.fencingToken})',
      );
    }
    _remove(leaseId, h);
    _pump();
  }

  /// Advances time-driven state: reap expired leases/lifetimes by the owner clock,
  /// expire overdue waiters, then grant freed slots to the FIFO head. Idempotent.
  void tick() => _pump();

  /// Validates a lease handle + fencing [token] for the given [leaseId].
  void _validate(String leaseId, int token) {
    _reap();
    final h = _held[leaseId];
    if (h == null) {
      throw LeaseInvalidException('lease "$leaseId" is unknown or expired');
    }
    if (h.fencingToken != token) {
      throw LeaseInvalidException(
        'stale fencing token $token for lease "$leaseId" '
        '(current ${h.fencingToken})',
      );
    }
  }

  /// The synchronous declare-and-check core: idempotency dedup, kind check, and a
  /// capacity check that yields to any FIFO waiter. Returns the grant, or `null`
  /// when there is no free capacity. Throws [LeaseDeniedException] for a permanent
  /// refusal (the kind is not offered).
  LeaseGrant? _tryGrantNow(LeaseRequest req) {
    _pump(); // reap + hand freed slots to the queue FIRST (fairness)
    if (req.kind != kind) {
      throw LeaseDeniedException(
        'kind "${req.kind}" not offered (offers "$kind")',
      );
    }
    if (req.idempotencyKey.isNotEmpty) {
      final existing = _grantsByKey[req.idempotencyKey];
      if (existing != null && _held.containsKey(existing.leaseId)) {
        return existing; // dedup: the live grant, never a second
      }
    }
    // Full — any FIFO waiters are ahead of a fresh direct grant.
    if (_held.length >= offered) return null;
    return _issue(req);
  }

  /// Mints a fresh lease + fencing token and records it.
  LeaseGrant _issue(LeaseRequest req) {
    final id = _idGen(_seq++);
    final token = ++_fence; // monotonic owner version (1, 2, 3, …)
    final now = _clock();
    _held[id] = _Held(
      kind: kind,
      expiry: now.add(ttl),
      hardDeadline: now.add(maxLifetime),
      fencingToken: token,
      idempotencyKey: req.idempotencyKey,
    );
    final grant = LeaseGrant(
      leaseId: id,
      station: station,
      ttlSeconds: ttl.inSeconds,
      fencingToken: token,
      kind: kind,
    );
    if (req.idempotencyKey.isNotEmpty) _grantsByKey[req.idempotencyKey] = grant;
    return grant;
  }

  void _remove(String leaseId, _Held h) {
    _held.remove(leaseId);
    if (h.idempotencyKey.isNotEmpty) _grantsByKey.remove(h.idempotencyKey);
  }

  /// Reap by the OWNER clock: a lease dies when its idle TTL OR its max lifetime
  /// passes (whichever first).
  void _reap() {
    final now = _clock();
    final dead = <String>[];
    _held.forEach((id, h) {
      if (!h.expiry.isAfter(now) || !h.hardDeadline.isAfter(now)) dead.add(id);
    });
    for (final id in dead) {
      _remove(id, _held[id]!);
    }
  }

  /// Reap, expire overdue waiters, then grant freed slots to the FIFO head.
  void _pump() {
    _reap();
    final now = _clock();
    _queue.removeWhere((w) {
      if (w.deadline.isAfter(now)) return false;
      if (!w.completer.isCompleted) {
        w.completer.completeError(const LeaseDeniedException('wait expired'));
      }
      return true;
    });
    while (_queue.isNotEmpty && _held.length < offered) {
      final w = _queue.removeAt(0);
      w.completer.complete(_issue(w.req));
    }
  }
}
