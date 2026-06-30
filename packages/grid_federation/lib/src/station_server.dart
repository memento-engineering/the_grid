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
/// map). [computeDispatchHandler] adapts the COMPUTE domain's
/// [DispatchCommand]/[CommandResult] onto it; that compute glue moves to
/// `grid_assets` at the M6 Track D split — the federation core stays kind-free.
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
/// kind-agnostic execution seam. The compute domain supplies one via
/// [computeDispatchHandler]; other domains (burn, …) supply their own.
typedef DispatchHandler =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> payload);

/// Runs a compute [DispatchCommand] and returns its [CommandResult]. Injectable
/// (default = [_runProcess], a real `Process.run`).
typedef CommandExecutor = Future<CommandResult> Function(DispatchCommand cmd);

/// Adapts the COMPUTE domain's typed [CommandExecutor] onto the kind-agnostic
/// [DispatchHandler]: decode [DispatchCommand], run it, encode [CommandResult].
/// Defaults to a real `Process.run`.
DispatchHandler computeDispatchHandler([CommandExecutor? executor]) {
  final exec = executor ?? _runProcess;
  return (payload) async =>
      (await exec(DispatchCommand.fromJson(payload))).toJson();
}

/// The default compute executor: a real `Process.run`, timed.
Future<CommandResult> _runProcess(DispatchCommand cmd) async {
  final sw = Stopwatch()..start();
  final r = await Process.run(
    cmd.command,
    cmd.args,
    workingDirectory: cmd.workdir,
  );
  sw.stop();
  return CommandResult(
    exitCode: r.exitCode,
    stdout: r.stdout.toString(),
    stderr: r.stderr.toString(),
    durationMs: sw.elapsedMilliseconds,
  );
}

/// A station server: an HTTP lessor over a [LeaseManager] + a [DispatchHandler].
class StationServer {
  StationServer._(
    this._server,
    this._leases,
    this._handler,
    this._token,
    this._leaseWait,
    this._onLog,
  );

  final HttpServer _server;
  final LeaseManager _leases;
  final DispatchHandler _handler;
  final String? _token;
  final Duration _leaseWait;
  final void Function(String) _onLog;

  /// In-flight/completed dispatch results keyed by idempotency key. Storing the
  /// FUTURE (not just the result) collapses concurrent retries onto one run.
  final Map<String, Future<Map<String, dynamic>>> _dispatchByKey = {};

  /// The bound port (useful when started on port 0 — an ephemeral port).
  int get port => _server.port;

  /// The lease manager (exposed for presence/tests).
  LeaseManager get leases => _leases;

  /// Binds an HTTP lessor on [host]:[port] offering [offered] slots of [kind]
  /// for [station]. Pass [token] to require `X-Grid-Token`; [handler] to fake
  /// execution; [onLog] to observe events. [leaseWait] (default zero) opts a
  /// full-capacity request into the FIFO wait-queue instead of an immediate deny.
  static Future<StationServer> start({
    required String station,
    required int offered,
    String host = '0.0.0.0',
    int port = 0,
    String kind = 'compute',
    String? token,
    Duration ttl = const Duration(seconds: 300),
    Duration maxLifetime = const Duration(seconds: 3600),
    Duration leaseWait = Duration.zero,
    int maxQueueDepth = 64,
    DispatchHandler? handler,
    DateTime Function()? clock,
    String Function(int seq)? idGen,
    void Function(String)? onLog,
  }) async {
    final server = await HttpServer.bind(host, port);
    final manager = LeaseManager(
      station: station,
      offered: offered,
      kind: kind,
      ttl: ttl,
      maxLifetime: maxLifetime,
      maxQueueDepth: maxQueueDepth,
      clock: clock,
      idGen: idGen,
    );
    final s = StationServer._(
      server,
      manager,
      handler ?? computeDispatchHandler(),
      token,
      leaseWait,
      onLog ?? (_) {},
    );
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

    // GET /presence
    if (method == 'GET' && seg.length == 1 && seg[0] == 'presence') {
      return _ok(req, _leases.presence.toJson());
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

  /// Stops the server.
  Future<void> close() => _server.close(force: true);
}
