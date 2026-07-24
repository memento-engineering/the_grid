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
/// the routes below are GET-only — this file holds no bd writer and calls no
/// re-query. `/hooks` resolves declarations but never executes them.
///
/// D-C5: this is a floor — it gets re-homed onto the unified-surfaces
/// substrate later (perception / control plane / MCP / CLI+RPC / MQTT, one
/// substrate under the hood). Built small on purpose.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

// The wedge signal is the STATION's own derivation — this surface only reports
// it. Named through the SDK, never the private engine (ADR-0008 D2).
import 'package:grid_sdk/grid_sdk.dart' show WedgeState, kNotWedged;

import 'hooks_resolver.dart';

/// One owned substation's slice of the station status (tg-7gm) — the
/// per-substation breakdown of [StationStatus.ready]/[StationStatus.mounted],
/// so a multi-root operator can see WHICH substation is actually driving.
class SubstationStatus {
  /// Creates the per-substation slice.
  const SubstationStatus({
    required this.substation,
    required this.root,
    required this.ready,
    required this.mounted,
  });

  /// The owned substation id (an `args.substations` member).
  final String substation;

  /// This substation's registered root path, or null (no root resolved).
  final String? root;

  /// This substation's slice of [StationStatus.ready] (same narrowing).
  final int ready;

  /// This substation's slice of [StationStatus.mounted] (same narrowing).
  final int mounted;

  /// Serializes to the wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'substation': substation,
    'root': root,
    'ready': ready,
    'mounted': mounted,
  };
}

/// A value-snapshot of the running station — the whole `/status` payload.
/// Composed ONCE per request by the runner's own `/status` view (never
/// cached, never polled).
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
    this.perSubstation = const <SubstationStatus>[],
    this.wedge = kNotWedged,
  });

  /// The owned substation allow-set, joined for display.
  final String substation;

  /// The state store root, or null when no split store is wired.
  final String? stateStore;

  /// Every owned substation's root, rendered `name=path` and joined for
  /// display, or null (no root resolved). [perSubstation] carries the
  /// structured per-substation breakdown; this stays a flat string for
  /// backward wire-compat with the pre-multi-root single-path field.
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

  /// The per-substation breakdown (tg-7gm) — one entry per owned substation;
  /// empty when the runner's `/status` view has no multi-substation breakdown
  /// (or a caller constructs [StationStatus] directly without it).
  final List<SubstationStatus> perSubstation;

  /// The station's WEDGE signal (tg-jwh) — derived STATION-side over the
  /// producer-side join (`StationWorkRuntime.wedge`) and reported here as a
  /// first-class value, so a watcher reads ONE truth instead of re-deriving
  /// "is the grid stuck?" from raw sessions. Defaults to [kNotWedged] for a
  /// caller that builds a status without the work runtime — never a phantom
  /// alarm.
  final WedgeState wedge;

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
      'perSubstation': [for (final s in perSubstation) s.toJson()],
    },
    // First-class, top-level — a watcher reads THIS, never the gate list.
    'wedge': wedge.toJson(),
  };
}

/// Mints a fresh per-boot bearer token: 32 secure-random bytes, base64url
/// encoded. The ONLY thing ever done with the result is writing it into the
/// 0600 `station.lock` — never argv, never env.
String mintControlToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes);
}

/// The read-only, loopback-only HTTP control surface (D-C2). GET-only,
/// exact-match routes: `/healthz` (liveness), `/status` (the [StationStatus]
/// snapshot), and `/hooks` (contribution resolution only; it never executes
/// contributions). EVERY route requires
/// `Authorization: Bearer <token>` — checked BEFORE routing, so an
/// unauthenticated caller learns nothing (not even which paths exist). No
/// mutation endpoint exists.
class StationControl {
  StationControl._(
    this._server,
    this._token,
    StationStatus Function() view,
    this._hooksResolver,
  ) : _routes = <String, Map<String, Object?> Function()>{
        '/healthz': () => const <String, Object?>{'ok': true},
        '/status': () => view().toJson(),
      };

  final HttpServer _server;
  final String _token;
  final Map<String, Map<String, Object?> Function()> _routes;
  final HooksResolver _hooksResolver;

  /// The bound loopback URL, e.g. `http://127.0.0.1:54321`.
  String get url => 'http://${_server.address.address}:${_server.port}';

  /// Binds a fresh [StationControl] to `127.0.0.1:[port]` (`0` = ephemeral).
  /// [token] is minted by the caller ([mintControlToken]) so the mint stays
  /// visibly tied to the lock file that carries it; [view] is a
  /// value-snapshot getter with NO subscriptions (called fresh per request).
  /// [hooksResolver] performs read-only hook declaration resolution.
  static Future<StationControl> start({
    required int port,
    required String token,
    required StationStatus Function() view,
    HooksResolver hooksResolver = const HooksResolver(),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final control = StationControl._(server, token, view, hooksResolver);
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
    final isHooks = request.uri.path == '/hooks';
    final route = _routes[request.uri.path];
    if (!isHooks && route == null) {
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
    if (isHooks) {
      await _handleHooks(request);
      return;
    }
    await _respond(request, HttpStatus.ok, route!());
  }

  Future<void> _handleHooks(HttpRequest request) async {
    try {
      final response = await _hooksResolver.resolve(
        event: request.uri.queryParameters['event'] ?? '',
        worktree: request.uri.queryParameters['worktree'] ?? '',
      );
      await _respond(request, HttpStatus.ok, response.toJson());
    } on HooksResolutionException catch (error) {
      await _respond(request, error.statusCode, <String, Object?>{
        'error': error.message,
      });
    }
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
