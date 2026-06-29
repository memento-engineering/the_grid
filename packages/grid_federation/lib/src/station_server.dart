/// The lessor side of the bus — a station that OFFERS capacity over HTTP, grants
/// leases (declare-and-check via [LeaseManager]), runs dispatched GENERIC
/// commands on a leased slot, and frees the slot on release/TTL.
///
/// `dart:io` only; the executor is injectable so tests never spawn real
/// processes. Lib stays print-free — the CLI wires [onLog] to stdout.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lease_manager.dart';
import 'protocol.dart';

/// Runs a dispatched command and returns its result. Injectable (default =
/// [_runProcess], a real `Process.run`).
typedef CommandExecutor = Future<CommandResult> Function(DispatchCommand cmd);

/// A station server: an HTTP lessor over a [LeaseManager] + a [CommandExecutor].
class StationServer {
  StationServer._(this._server, this._leases, this._executor, this._token, this._onLog);

  final HttpServer _server;
  final LeaseManager _leases;
  final CommandExecutor _executor;
  final String? _token;
  final void Function(String) _onLog;

  /// The bound port (useful when started on port 0 — an ephemeral port).
  int get port => _server.port;

  /// The lease manager (exposed for presence/tests).
  LeaseManager get leases => _leases;

  /// Binds an HTTP lessor on [host]:[port] offering [offered] slots of [kind]
  /// for [station]. Pass [token] to require `X-Grid-Token`; [executor] to fake
  /// command execution; [onLog] to observe events.
  static Future<StationServer> start({
    required String station,
    required int offered,
    String host = '0.0.0.0',
    int port = 0,
    String kind = 'compute',
    String? token,
    Duration ttl = const Duration(seconds: 300),
    CommandExecutor? executor,
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
      clock: clock,
      idGen: idGen,
    );
    final s = StationServer._(
      server,
      manager,
      executor ?? _runProcess,
      token,
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
        grant = _leases.grant(LeaseRequest.fromJson(body));
      } on LeaseDeniedException catch (e) {
        _onLog('lease DENIED for ${body['lessee']}: ${e.message}');
        return _fail(req, 409, e.message);
      }
      _onLog('lease ${grant.leaseId} GRANTED to ${body['lessee']} '
          '(${_leases.available}/${_leases.offered} free)');
      return _ok(req, grant.toJson());
    }
    // POST /lease/<id>/dispatch  and  POST /lease/<id>/release
    if (method == 'POST' && seg.length == 3 && seg[0] == 'lease') {
      final id = seg[1];
      final verb = seg[2];
      if (verb == 'release') {
        _leases.release(id);
        _onLog('lease $id RELEASED (${_leases.available}/${_leases.offered} free)');
        return _ok(req, {'released': true});
      }
      if (verb == 'dispatch') {
        try {
          _leases.touch(id);
        } on LeaseInvalidException catch (e) {
          return _fail(req, 410, e.message);
        }
        final cmd = DispatchCommand.fromJson(await _readJson(req));
        _onLog('lease $id DISPATCH: ${cmd.command} ${cmd.args.join(' ')}');
        final result = await _executor(cmd);
        _onLog('lease $id RESULT: exit=${result.exitCode} (${result.durationMs}ms)');
        return _ok(req, result.toJson());
      }
    }
    return _fail(req, 404, 'no route for $method ${req.uri.path}');
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

  /// The default executor: a real `Process.run`, timed.
  static Future<CommandResult> _runProcess(DispatchCommand cmd) async {
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
}
