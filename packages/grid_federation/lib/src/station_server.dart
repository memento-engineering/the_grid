/// The lessor side of the bus — a station that OFFERS capacity over HTTP, grants
/// leases (the owner-authoritative serialization point, via [LeaseManager]), runs
/// a dispatched OPAQUE payload on a leased slot, and frees the slot on
/// release/TTL.
///
/// The server enforces the hazard bake-ins on the wire: a dispatch/release must
/// carry the lease's fencing token (`X-Grid-Fence`), and an `X-Grid-Idem` key
/// dedups a dispatch so a retried/dup message never re-runs (ADR-0011 Hazards).
///
/// The dispatch handler is kind-agnostic ([DispatchHandler]: opaque map → opaque
/// map). What a payload MEANS + what "use" executes lives in the asset domain
/// that owns the kind (ADR-0011 D3) — an asset in `grid_assets` supplies a
/// handler that decodes + runs its own payload; the federation core stays
/// kind-free and only sees the opaque envelope.
///
/// `dart:io` only; the handler is injectable so tests never spawn real processes.
/// Lib stays print-free — the CLI wires [onLog] to stdout.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lease_manager.dart';
import 'protocol.dart';

/// Runs a dispatched OPAQUE payload and returns an opaque result — the
/// kind-agnostic execution seam. Each asset domain supplies its own (decoding
/// the payload its kind defines and running that kind's bounded "use").
typedef DispatchHandler =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> payload);

/// A station server: an HTTP lessor over a [LeaseManager] + a [DispatchHandler].
class StationServer {
  StationServer._(
    this._server,
    this._leases,
    this._handler,
    this._token,
    this._leaseWait,
    this._profile,
    this._onLog,
  );

  final HttpServer _server;
  final LeaseManager _leases;
  final DispatchHandler _handler;
  final String? _token;
  final Duration _leaseWait;
  final Map<String, Object?> _profile;
  final void Function(String) _onLog;

  /// The owner-clock reap ticker (when [start] is given a `reapInterval`); drives
  /// heartbeat-loss + TTL reaping without waiting for traffic.
  Timer? _reapTimer;

  /// In-flight/completed dispatch results keyed by idempotency key. Storing the
  /// FUTURE (not just the result) collapses concurrent retries onto one run.
  final Map<String, Future<Map<String, dynamic>>> _dispatchByKey = {};

  /// The bound port (useful when started on port 0 — an ephemeral port).
  int get port => _server.port;

  /// The lease manager (exposed for presence/tests).
  LeaseManager get leases => _leases;

  /// Binds an HTTP lessor on [host]:[port] offering [offered] slots of [kind]
  /// for [station]. [handler] runs a dispatched OPAQUE payload (the asset domain
  /// that owns the kind supplies it — the core has no built-in execution). Pass
  /// [token] to require `X-Grid-Token`; [onLog] to observe events. [leaseWait]
  /// (default zero) opts a full-capacity request into the FIFO wait-queue instead
  /// of an immediate deny.
  ///
  /// [profile] is the station's advertised **capability profile** (durable facts)
  /// echoed in `GET /presence` beside the ephemeral capacity. [heartbeat] (when
  /// set) enables liveness heartbeat: the owner reaps a held lease missing a
  /// heartbeat past [missedHeartbeatThreshold] intervals. [reapInterval] (when
  /// set) drives an owner-clock reap ticker so a disconnected lease frees its slot
  /// — and any FIFO waiter advances — without waiting for the next request; leave
  /// it `null` (the default) for tests that drive the injected [clock] manually.
  static Future<StationServer> start({
    required String station,
    required int offered,
    required DispatchHandler handler,
    String host = '0.0.0.0',
    int port = 0,
    String kind = kDefaultKind,
    String? token,
    Duration ttl = const Duration(seconds: 300),
    Duration maxLifetime = const Duration(seconds: 3600),
    Duration leaseWait = Duration.zero,
    int maxQueueDepth = 64,
    Map<String, Object?> profile = const {},
    Duration? heartbeat,
    int missedHeartbeatThreshold = 3,
    Duration? reapInterval,
    DateTime Function()? clock,
    String Function(int seq)? idGen,
    void Function(String)? onLog,
    void Function(String leaseId)? onLeaseEnded,
  }) async {
    final server = await HttpServer.bind(host, port);
    final manager = LeaseManager(
      station: station,
      offered: offered,
      kind: kind,
      ttl: ttl,
      maxLifetime: maxLifetime,
      maxQueueDepth: maxQueueDepth,
      heartbeat: heartbeat,
      missedHeartbeatThreshold: missedHeartbeatThreshold,
      // The lessor teardown hook (ADR-0011 Hazards): fires on explicit
      // release AND every reap path, so work launched under the lease
      // (e.g. the burn's follower app) never outlives it.
      onLeaseEnded: onLeaseEnded,
      clock: clock,
      idGen: idGen,
    );
    final s = StationServer._(
      server,
      manager,
      handler,
      token,
      leaseWait,
      profile,
      onLog ?? (_) {},
    );
    if (reapInterval != null) {
      s._reapTimer = Timer.periodic(reapInterval, (_) => manager.tick());
    }
    unawaited(s._serve());
    return s;
  }

  Future<void> _serve() async {
    await for (final req in _server) {
      // Each request is handled independently; a handler error becomes a 500
      // rather than tearing down the listener.
      unawaited(_handle(req).catchError((Object e) => _fail(req, 500, '$e')));
    }
  }

  Future<void> _handle(HttpRequest req) async {
    if (_token != null && req.headers.value('X-Grid-Token') != _token) {
      return _fail(req, 401, 'unauthorized');
    }
    final seg = req.uri.pathSegments;
    final method = req.method;

    // GET /presence — capacity (ephemeral) from the manager + the station's
    // capability profile (durable) overlaid here.
    if (method == 'GET' && seg.length == 1 && seg[0] == 'presence') {
      return _ok(req, _leases.presence.copyWith(profile: _profile).toJson());
    }
    // POST /lease
    if (method == 'POST' && seg.length == 1 && seg[0] == 'lease') {
      final body = await _readJson(req);
      final LeaseGrant grant;
      try {
        grant = await _leases.acquire(
          LeaseRequest.fromJson(body),
          maxWait: _leaseWait,
        );
      } on LeaseDeniedException catch (e) {
        _onLog('lease DENIED for ${body['lessee']}: ${e.message}');
        return _fail(req, 409, e.message);
      }
      _onLog(
        'lease ${grant.leaseId} GRANTED to ${body['lessee']} '
        '(fence ${grant.fencingToken}; ${_leases.available}/${_leases.offered} '
        'free)',
      );
      return _ok(req, grant.toJson());
    }
    // POST /lease/<id>/dispatch  and  POST /lease/<id>/release
    if (method == 'POST' && seg.length == 3 && seg[0] == 'lease') {
      final id = seg[1];
      final verb = seg[2];
      final fence = int.tryParse(req.headers.value('X-Grid-Fence') ?? '');
      if (fence == null) {
        return _fail(
          req,
          400,
          'missing or invalid X-Grid-Fence (fencing token)',
        );
      }

      if (verb == 'release') {
        try {
          _leases.release(id, token: fence);
        } on LeaseInvalidException catch (e) {
          return _fail(req, 410, e.message); // stale token
        }
        _onLog(
          'lease $id RELEASED (${_leases.available}/${_leases.offered} free)',
        );
        return _ok(req, {'released': true});
      }

      if (verb == 'heartbeat') {
        try {
          _leases.beat(id, fence); // validates liveness + fencing, renews
        } on LeaseInvalidException catch (e) {
          return _fail(req, 410, e.message); // unknown/expired/stale token
        }
        _onLog('lease $id HEARTBEAT');
        return _ok(req, {'alive': true});
      }

      if (verb == 'dispatch') {
        try {
          _leases.touch(id, fence); // validates liveness + fencing token
        } on LeaseInvalidException catch (e) {
          return _fail(req, 410, e.message);
        }
        final idem = req.headers.value('X-Grid-Idem') ?? '';
        final payload = await _readJson(req);
        final result = await _runDispatch(id, idem, payload);
        return _ok(req, result);
      }
    }
    return _fail(req, 404, 'no route for $method ${req.uri.path}');
  }

  /// Runs (or replays) a dispatch. With a non-empty [idem] key the run is
  /// memoized so a retried/dup message returns the SAME result, never re-running.
  Future<Map<String, dynamic>> _runDispatch(
    String leaseId,
    String idem,
    Map<String, dynamic> payload,
  ) {
    if (idem.isEmpty) {
      _onLog('lease $leaseId DISPATCH (no idem key)');
      return _handler(payload);
    }
    final existing = _dispatchByKey[idem];
    if (existing != null) {
      _onLog('lease $leaseId DISPATCH idem "$idem" → replayed (deduped)');
      return existing;
    }
    _onLog('lease $leaseId DISPATCH idem "$idem"');
    return _dispatchByKey[idem] = _handler(payload);
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest req) async {
    final text = await utf8.decoder.bind(req).join();
    if (text.isEmpty) return const {};
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<void> _ok(HttpRequest req, Map<String, dynamic> body) async {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  }

  Future<void> _fail(HttpRequest req, int code, String reason) async {
    req.response
      ..statusCode = code
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'error': reason}));
    await req.response.close();
  }

  /// Stops the server (and the reap ticker, if one was started).
  Future<void> close() {
    _reapTimer?.cancel();
    return _server.close(force: true);
  }
}
