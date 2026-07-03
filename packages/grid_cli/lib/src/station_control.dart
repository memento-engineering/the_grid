/// RS-4 — `StationControl`: the read-only loopback control surface (D-C2,
/// `docs/SCRATCH-resident-station.md` §3, RATIFIED Nico 2026-07-02).
///
/// A DEDICATED, READ-ONLY, loopback-only HTTP surface owned by the runner
/// shell — explicitly NOT the exploration/perception host (D-C1: perception
/// is the debugging surface; `GridExplorationHost` stays untouched). Every
/// route (`/healthz` included — one posture, no unauthenticated liveness
/// probe) requires `Authorization: Bearer <token>`, checked BEFORE routing.
/// The token is minted per boot (secure random) and lives ONLY in the 0600
/// `station.lock` (RS-2's `controlUrl`/`token` fields) — never argv, never
/// env (the ADR-0006 precedent). **NO mutation endpoints, by construction**:
/// the route table below (GET-only, two entries) is the entire surface — this
/// file holds no bd writer and calls no re-query.
///
/// D-C5: this is a floor — it gets re-homed onto the unified-surfaces
/// substrate later (perception / control plane / MCP / CLI+RPC / MQTT, one
/// substrate under the hood). Built small on purpose.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:grid_runtime/grid_runtime.dart';

import 'station_runner.dart';

/// A value-snapshot of the running station — the whole `/status` payload.
/// Composed ONCE per request (never cached, never polled) by
/// [buildStationStatus].
class StationStatus {
  /// Creates an immutable status snapshot.
  const StationStatus({
    required this.substation,
    required this.stateStore,
    required this.workRoot,
    required this.dryRun,
    required this.pid,
    required this.startedAt,
    required this.version,
    required this.ready,
    required this.mounted,
    required this.liveSessions,
    required this.lastSyncAt,
  });

  /// The owned substation allow-set, joined for display.
  final String substation;

  /// The state store root, or null when no split store is wired.
  final String? stateStore;

  /// The registered worktree root checkout, or null (dry-run/no `--root`).
  final String? workRoot;

  /// Whether this station is running dry (observe-only).
  final bool dryRun;

  /// This process's pid.
  final int pid;

  /// When this station's supervisor booted (the lock-acquire moment).
  final DateTime startedAt;

  /// The Dart runtime version this station is running under.
  final String version;

  /// The size of the OWNED ready frontier: `readyIds` filtered by the
  /// ownership predicate and (under resident arming) the driveable-work
  /// boundary — never a raw, workspace-wide `readyCount` (RS-3/D-R4).
  final int ready;

  /// A coarse count of owned work beads currently eligible to be mounted
  /// (ready OR carrying a live, non-terminal session, and not closed) — an
  /// approximation of the tree's real `WorkList` mount set (D-C5: a floor;
  /// it does not replicate the dispatchable-type gate).
  final int mounted;

  /// The count of owned sessions that have not yet reached a terminal cursor.
  final int liveSessions;

  /// The wall-clock capture time of the work snapshot this status was built
  /// from, or null when no work baseline has arrived yet.
  final DateTime? lastSyncAt;

  /// Serializes to the wire shape `/status` returns.
  Map<String, Object?> toJson() => <String, Object?>{
    'station': <String, Object?>{
      'substation': substation,
      'stateStore': stateStore,
      'workRoot': workRoot,
      'dryRun': dryRun,
    },
    'process': <String, Object?>{
      'pid': pid,
      'startedAt': startedAt.toIso8601String(),
      'uptimeSeconds': DateTime.now().difference(startedAt).inSeconds,
      'version': version,
    },
    'work': <String, Object?>{
      'ready': ready,
      'mounted': mounted,
      'liveSessions': liveSessions,
      'lastSyncAt': lastSyncAt?.toIso8601String(),
    },
  };
}

/// Builds a [StationStatus] snapshot from ALREADY-HELD, read-only state:
/// [wiring]'s kernel's join bridge (`bridge.latest` — the PRODUCER-side record
/// of what it last pushed, the SAME seam the kernel's own cooldown scan reads;
/// D-H rule 2). Never subscribes, never triggers [StationSources.requery],
/// never invokes bd.
StationStatus buildStationStatus({
  required StationArgs args,
  required StationSources sources,
  required TreeRunWiring wiring,
  required DateTime startedAt,
}) {
  final joined = wiring.kernel.bridge.latest;
  final graph = joined.graph;
  final sessions = joined.sessionsByWorkBead;
  final ownership = BeadOwnershipPredicate(args.substations);

  var mounted = 0;
  for (final bead in graph.beads) {
    if (bead.isClosed || !ownership.owns(bead)) continue;
    final session = sessions[bead.id];
    if (session?.isTerminal ?? false) continue;
    final inReady = graph.readyIds.contains(bead.id);
    final liveSession = session != null && !session.isTerminal;
    if (inReady || liveSession) mounted++;
  }
  final liveSessions = sessions.values.where((s) => !s.isTerminal).length;

  // The OWNED ready frontier (RS-3/D-R4 semantics): readyIds filtered by the
  // SAME ownership predicate `mounted` applies, PLUS the driveable-work
  // boundary WorkList's own mount gate narrows to under resident arming
  // (A41's `isCore` allow-list, further narrowed to `isDriveable` when
  // resident). Unfiltered `graph.readyCount` is workspace-wide `bd ready` —
  // in a shared store that leaks OTHER substations' ready work and
  // organizational types (epic/milestone/decision) the drive set never
  // mounts; this must match what `up` would actually drive, not `bd ready`.
  var ready = 0;
  for (final id in graph.readyIds) {
    final bead = graph.beadsById[id];
    if (bead == null || !ownership.owns(bead)) continue;
    if (!bead.issueType.isCore) continue;
    if (args.resident && !bead.issueType.isDriveable) continue;
    ready++;
  }

  return StationStatus(
    substation: args.substations.join(','),
    stateStore: sources.stateWorkspace?.root,
    workRoot: args.rootPath,
    dryRun: args.dryRun,
    pid: pid,
    startedAt: startedAt,
    version: Platform.version,
    ready: ready,
    mounted: mounted,
    liveSessions: liveSessions,
    lastSyncAt: graph.capturedAt,
  );
}

/// Mints a fresh per-boot bearer token: 32 secure-random bytes, base64url
/// encoded. The ONLY thing ever done with the result is writing it into the
/// 0600 `station.lock` — never argv, never env.
String mintControlToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes);
}

/// The seam [driveStation] calls through to bind the control surface —
/// injectable for offline tests (no real socket needed to test the wiring
/// order; the real impl is [StationControl.start]).
typedef StationControlStarter =
    Future<StationControl> Function({
      required int port,
      required String token,
      required StationStatus Function() view,
    });

/// The read-only, loopback-only HTTP control surface (D-C2). GET-only,
/// exact-match route table: `/healthz` (liveness) and `/status` (the
/// [StationStatus] snapshot). EVERY route requires
/// `Authorization: Bearer <token>` — checked BEFORE routing, so an
/// unauthenticated caller learns nothing (not even which paths exist). No
/// mutation endpoint exists, by construction: [_routes] IS the whole surface.
class StationControl {
  StationControl._(this._server, this._token, StationStatus Function() view)
    : _routes = <String, Map<String, Object?> Function()>{
        '/healthz': () => const <String, Object?>{'ok': true},
        '/status': () => view().toJson(),
      };

  final HttpServer _server;
  final String _token;
  final Map<String, Map<String, Object?> Function()> _routes;

  /// The bound loopback URL, e.g. `http://127.0.0.1:54321`.
  String get url => 'http://${_server.address.address}:${_server.port}';

  /// Binds a fresh [StationControl] to `127.0.0.1:[port]` (`0` = ephemeral).
  /// [token] is minted by the caller ([mintControlToken]) so the mint stays
  /// visibly tied to the lock file that carries it; [view] is a
  /// value-snapshot getter with NO subscriptions (called fresh per request).
  static Future<StationControl> start({
    required int port,
    required String token,
    required StationStatus Function() view,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final control = StationControl._(server, token, view);
    server.listen(control._handle);
    return control;
  }

  Future<void> _handle(HttpRequest request) async {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header != 'Bearer $_token') {
      await _respond(request, HttpStatus.unauthorized, <String, Object?>{
        'error': 'unauthorized',
      });
      return;
    }
    final route = _routes[request.uri.path];
    if (route == null) {
      await _respond(request, HttpStatus.notFound, <String, Object?>{
        'error': 'not found: ${request.uri.path}',
      });
      return;
    }
    if (request.method != 'GET') {
      await _respond(request, HttpStatus.methodNotAllowed, <String, Object?>{
        'error': 'method not allowed: ${request.method}',
      });
      return;
    }
    await _respond(request, HttpStatus.ok, route());
  }

  Future<void> _respond(
    HttpRequest request,
    int statusCode,
    Map<String, Object?> body,
  ) async {
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  /// Stops accepting connections and releases the bound port. Idempotent in
  /// practice (the graceful path and the start-throw unwind never both run),
  /// but never throws on a second call — `HttpServer.close` is itself
  /// idempotent.
  Future<void> dispose() => _server.close(force: true);
}
