/// RS-4 — `StationControl`: the authenticated HTTP/WS station surface (D-C2).
///
/// One surface owned by the runner shell, bound to loopback by default with an
/// explicit LAN-address composition option. It is NOT the exploration/debug
/// host (D-C1: `GridExplorationHost` stays a separate JIT-only channel). Every route
/// (`/healthz` included — one posture, no unauthenticated liveness probe)
/// requires `Authorization: Bearer <token>`, checked BEFORE routing.
/// The token is minted per boot (secure random) and lives ONLY in the 0600
/// `station.lock` (RS-2's `controlUrl`/`token` fields) — never argv, never
/// env (the ADR-0006 precedent).
///
/// ADR-0014 D-C4 (Nico-ratified 2026-07-24):
/// the control plane cannot be a WORK trigger (`bd` stays the only work intake).
/// operator one-shots ARE control-plane requests.
/// `/healthz`, `/status`, `/hooks`, and the diagnostics WebSocket `/stream`
/// remain read-only; fenced `POST /command` is the sole scoped mutation. This file
/// holds no bd writer and calls no re-query. `/hooks` resolves declarations
/// but never executes them.
///
/// D-C5: this is a floor — it gets re-homed onto the unified-surfaces
/// substrate later (perception / control plane / MCP / CLI+RPC / MQTT, one
/// substrate under the hood). Built small on purpose.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:genesis_foundation/genesis_foundation.dart' show TreeSnapshot;
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart'
    show stationTreeBearerProtocolPrefix;
import 'package:grid_engine/grid_engine.dart' show TreeProjector;
import 'package:grid_runtime/grid_runtime.dart' show OperatorBeadTextField;
// The wedge signal is the STATION's own derivation — this surface only reports
// it. Named through the SDK, never the private engine (ADR-0008 D2).
import 'package:grid_sdk/grid_sdk.dart'
    show
        GridCommandCompleted,
        GridCommandHandler,
        GridCommandRefused,
        GridCommandRequest,
        GridCommandResult,
        WedgeState,
        kNotWedged;

import 'hooks_resolver.dart';

const _commandPath = '/command';
const _streamPath = '/stream';
const _fenceHeader = 'X-Grid-Fence';
const _idempotencyHeader = 'Idempotency-Key';

final class _CommandResponse {
  const _CommandResponse(this.statusCode, this.body);
  final int statusCode;
  final Map<String, Object?> body;
}

final class _IdempotentCommand {
  const _IdempotentCommand(this.fingerprint, this.response);
  final String fingerprint;
  final Future<_CommandResponse> response;
}

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
    required this.live,
  });

  /// The owned substation id (an `args.substations` member).
  final String substation;

  /// This substation's registered root path, or null (no root resolved).
  final String? root;

  /// This substation's slice of [StationStatus.ready] (same narrowing).
  final int ready;

  /// This substation's slice of [StationStatus.mounted] (same narrowing).
  final int mounted;

  /// This substation's live non-terminal session count.
  final int live;

  /// Serializes to the wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'substation': substation,
    'root': root,
    'ready': ready,
    'mounted': mounted,
    'live': live,
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
    this.sync = const <String, Object?>{},
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

  /// The sync-loop observability payload (tg-zd4v LOUD): per-store
  /// `GraphSyncStats` (`stats`) + the federation's per-member freshness
  /// vector (`freshness`), already JSON-shaped by the runner's view. Today's
  /// status says WHEN the last sync happened; this says WHY a sync did or did
  /// not happen — per-origin signal counts, refresh latency, in-flight state,
  /// and which member has gone stale by age. Empty when the runner has no
  /// work runtime (or an older runner predates the field).
  final Map<String, Object?> sync;

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
    if (sync.isNotEmpty) 'sync': sync,
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

/// One authenticated HTTP/WS station surface (D-C2), loopback by default with
/// explicit LAN binding. Read-only exact-match routes
/// are `/healthz` (liveness), `/status` (the [StationStatus] snapshot), and
/// `/hooks` (contribution resolution only; it never executes contributions);
/// `/stream` is the read-only diagnostics WebSocket. The VM exploration/debug
/// surface remains separate.
/// ADR-0014 D-C4 (Nico-ratified 2026-07-24):
/// the control plane cannot be a WORK trigger (`bd` stays the only work intake).
/// operator one-shots ARE control-plane requests.
/// Fenced `POST /command` is the sole scoped mutation.
/// EVERY route requires
/// `Authorization: Bearer <token>` — checked BEFORE routing, so an
/// unauthenticated caller learns nothing (not even which paths exist).
class StationControl {
  StationControl._(
    this._server,
    this._token,
    StationStatus Function() view,
    this._hooksResolver,
    this._commandHandler,
    this._treeProjector,
  ) : _routes = <String, Map<String, Object?> Function()>{
        '/healthz': () => const <String, Object?>{'ok': true},
        '/status': () => view().toJson(),
      };

  final HttpServer _server;
  final String _token;
  final Map<String, Map<String, Object?> Function()> _routes;
  final HooksResolver _hooksResolver;
  final GridCommandHandler _commandHandler;
  final TreeProjector? _treeProjector;
  final Set<WebSocket> _webSockets = <WebSocket>{};
  final Map<WebSocket, StreamSubscription<TreeSnapshot>>
  _snapshotSubscriptions = <WebSocket, StreamSubscription<TreeSnapshot>>{};
  final Map<String, _IdempotentCommand> _commands = {};
  int _highestFence = -1;

  /// The bound URL, e.g. `http://127.0.0.1:54321`.
  String get url => 'http://${_server.address.address}:${_server.port}';

  /// Binds a fresh [StationControl] to [address], defaulting to loopback
  /// (`0` = an ephemeral port).
  /// [token] is minted by the caller ([mintControlToken]) so the mint stays
  /// visibly tied to the lock file that carries it; [view] is a
  /// value-snapshot getter with NO subscriptions (called fresh per request).
  /// [hooksResolver] performs read-only hook declaration resolution.
  /// [treeProjector] enables `/stream`; this control does not dispose it.
  static Future<StationControl> start({
    required int port,
    required String token,
    required StationStatus Function() view,
    required GridCommandHandler commandHandler,
    HooksResolver hooksResolver = const HooksResolver(),
    InternetAddress? address,
    TreeProjector? treeProjector,
  }) async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    final control = StationControl._(
      server,
      token,
      view,
      hooksResolver,
      commandHandler,
      treeProjector,
    );
    server.listen(control._handle);
    return control;
  }

  Future<void> _handle(HttpRequest request) async {
    if (!_isAuthorized(request)) {
      await _respond(request, HttpStatus.unauthorized, <String, Object?>{
        'error': 'unauthorized',
      });
      return;
    }
    if (request.uri.path == _streamPath) {
      await _handleStream(request);
      return;
    }
    if (request.uri.path == _commandPath && request.method == 'POST') {
      await _handleCommand(request);
      return;
    }
    if (request.uri.path == _commandPath) {
      await _respond(request, HttpStatus.methodNotAllowed, <String, Object?>{
        'error': 'method not allowed: ${request.method}',
      });
      return;
    }
    final isHooks = request.uri.path == '/hooks';
    final route = _routes[request.uri.path];
    final isKnownPath =
        request.uri.path == _commandPath || isHooks || route != null;
    if (!isKnownPath) {
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

  bool _isAuthorized(HttpRequest request) {
    if (request.headers.value(HttpHeaders.authorizationHeader) ==
        'Bearer $_token') {
      return true;
    }
    if (request.uri.path != _streamPath ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      return false;
    }
    final requested =
        request.headers['sec-websocket-protocol'] ?? const <String>[];
    final hasBearerProtocol = requested
        .expand((value) => value.split(','))
        .map((value) => value.trim())
        .contains('$stationTreeBearerProtocolPrefix$_token');
    if (hasBearerProtocol) return true;
    return request.uri.queryParameters['token'] == _token;
  }

  Future<void> _handleStream(HttpRequest request) async {
    final projector = _treeProjector;
    if (projector == null) {
      await _respond(request, HttpStatus.serviceUnavailable, const {
        'error': 'diagnostics unavailable',
      });
      return;
    }
    if (request.method != 'GET' ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      await _respond(request, HttpStatus.upgradeRequired, const {
        'error': 'websocket upgrade required',
      });
      return;
    }
    final bearerProtocol = '$stationTreeBearerProtocolPrefix$_token';
    final socket = await WebSocketTransformer.upgrade(
      request,
      protocolSelector: (protocols) =>
          protocols.contains(bearerProtocol) ? bearerProtocol : null,
    );
    _webSockets.add(socket);
    final latest = projector.latest;
    final subscription = projector.snapshots.listen(
      (snapshot) => socket.add(jsonEncode(snapshot.toJson())),
      onError: socket.addError,
    );
    _snapshotSubscriptions[socket] = subscription;
    if (latest != null) {
      socket.add(jsonEncode(latest.toJson()));
    }
    unawaited(
      socket.done.whenComplete(() async {
        _webSockets.remove(socket);
        await _snapshotSubscriptions.remove(socket)?.cancel();
      }),
    );
  }

  Future<void> _handleCommand(HttpRequest request) async {
    final fenceText = request.headers.value(_fenceHeader);
    final fence = fenceText == null ? null : int.tryParse(fenceText);
    if (fence == null || fence < 0) {
      await _respond(request, HttpStatus.badRequest, const {
        'error': 'invalid or missing X-Grid-Fence',
      });
      return;
    }
    final key = request.headers.value(_idempotencyHeader)?.trim();
    if (key == null || key.isEmpty) {
      await _respond(request, HttpStatus.badRequest, const {
        'error': 'missing Idempotency-Key',
      });
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(await utf8.decoder.bind(request).join());
    } on FormatException {
      await _respond(request, HttpStatus.badRequest, const {
        'id': null,
        'error': {'code': 'invalid_request', 'message': 'Malformed JSON.'},
      });
      return;
    }
    final parsed = _decodeCommand(decoded);
    if (parsed case _CommandResponse()) {
      await _respond(request, parsed.statusCode, parsed.body);
      return;
    }
    final (id, command, fingerprint) =
        parsed as (Object, GridCommandRequest, String);
    final existing = _commands[key];
    if (existing != null && existing.fingerprint != fingerprint) {
      await _respond(request, HttpStatus.badRequest, {
        'id': id,
        'error': {
          'code': 'idempotency_key_reused',
          'message': 'Idempotency-Key was already used for another command.',
        },
      });
      return;
    }
    if (existing != null) {
      final response = await existing.response;
      await _respond(request, response.statusCode, response.body);
      return;
    }
    if (fence < _highestFence) {
      await _respond(request, HttpStatus.badRequest, const {
        'error': 'stale X-Grid-Fence',
      });
      return;
    }
    _highestFence = fence;
    final entry = _commands.putIfAbsent(
      key,
      () => _IdempotentCommand(
        fingerprint,
        _dispatchCommand(id: id, command: command),
      ),
    );
    final response = await entry.response;
    await _respond(request, response.statusCode, response.body);
  }

  Object _decodeCommand(Object? decoded) {
    if (decoded is! Map<String, Object?>) {
      return const _CommandResponse(HttpStatus.badRequest, {
        'id': null,
        'error': {
          'code': 'invalid_request',
          'message': 'Command body must be a JSON object.',
        },
      });
    }
    final id = decoded['id'];
    final method = decoded['method'];
    final params = decoded['params'];
    if (id == null || method is! String || params is! Map<String, Object?>) {
      return _CommandResponse(HttpStatus.badRequest, {
        'id': id,
        'error': {
          'code': 'invalid_request',
          'message': 'Command requires id, method, and object params.',
        },
      });
    }
    GridCommandRequest? command;
    if (method == 'grid/rework') {
      final beadId = params['beadId'];
      final note = params['note'];
      final beyondCap = params['beyondCap'] ?? false;
      final actor = params['actor'];
      if (beadId is String &&
          beadId.isNotEmpty &&
          (note == null || note is String) &&
          beyondCap is bool &&
          (actor == null || actor is String)) {
        command = GridCommandRequest.rework(
          beadId: beadId,
          note: note as String?,
          beyondCap: beyondCap,
          actor: actor as String?,
        );
      }
    } else if (method == 'grid/gate/ls') {
      if (params.isEmpty) {
        command = const GridCommandRequest.listGates();
      }
    } else if (method == 'grid/gate/resolve') {
      final gateId = params['gateId'];
      final grades = params['grades'] ?? const <String, Object?>{};
      final rationale = params['rationale'];
      if (gateId is String &&
          gateId.isNotEmpty &&
          grades is Map<String, Object?> &&
          grades.values.every((value) => value is String) &&
          (rationale == null || rationale is String)) {
        command = GridCommandRequest.resolveGate(
          gateId: gateId,
          grades: grades.cast<String, String>(),
          rationale: rationale as String?,
        );
      }
    } else if (method == 'grid/bead/set') {
      final beadId = params['beadId'];
      final field = params['field'];
      final content = params['content'];
      final append = params['append'];
      final fieldValue = switch (field) {
        'description' => OperatorBeadTextField.description,
        'design' => OperatorBeadTextField.design,
        'acceptance' => OperatorBeadTextField.acceptance,
        'notes' => OperatorBeadTextField.notes,
        _ => null,
      };
      if (beadId is String &&
          beadId.isNotEmpty &&
          content is String &&
          append is bool &&
          fieldValue != null) {
        command = GridCommandRequest.setBeadText(
          beadId: beadId,
          field: fieldValue,
          content: content,
          append: append,
        );
      }
    } else if (method == 'grid/bead/board') {
      final stores = params['stores'] ?? const <Object?>[];
      final statuses = params['statuses'] ?? const <Object?>[];
      final blocked = params['blocked'] ?? false;
      final approved = params['approved'];
      if (stores is List &&
          stores.every((value) => value is String) &&
          statuses is List &&
          statuses.every((value) => value is String) &&
          blocked is bool &&
          (approved == null || approved is bool)) {
        command = GridCommandRequest.board(
          stores: stores.cast<String>().toSet(),
          statuses: statuses.cast<String>().toSet(),
          blockedOnly: blocked,
          approved: approved as bool?,
        );
      }
    } else if (method == 'grid/bead/round') {
      final beadId = params['beadId'];
      if (beadId is String && beadId.isNotEmpty) {
        command = GridCommandRequest.beadRound(beadId: beadId);
      }
    }
    if (command == null) {
      return _CommandResponse(HttpStatus.badRequest, {
        'id': id,
        'error': {
          'code': 'invalid_request',
          'message': 'Unknown method or invalid command params.',
        },
      });
    }
    return (id, command, jsonEncode(decoded));
  }

  Future<_CommandResponse> _dispatchCommand({
    required Object id,
    required GridCommandRequest command,
  }) async {
    try {
      final GridCommandResult result = await _commandHandler(command);
      return switch (result) {
        GridCommandCompleted(:final value) => _CommandResponse(HttpStatus.ok, {
          'id': id,
          'result': value,
        }),
        GridCommandRefused(:final code, :final message) => _CommandResponse(
          HttpStatus.ok,
          {
            'id': id,
            'error': {'code': code, 'message': message},
          },
        ),
      };
    } on Object catch (error) {
      // Carry the actual failure (bounded) — a bare 'Command handler failed.'
      // swallowed a live rework's reap exception whole (2026-08-07); the
      // operator could not diagnose it without instrumenting the resident.
      final detail = '$error';
      return _CommandResponse(HttpStatus.internalServerError, {
        'id': id,
        'error': {
          'code': 'internal_error',
          'message':
              'Command handler failed: '
              '${detail.length > 500 ? detail.substring(0, 500) : detail}',
        },
      });
    }
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
  Future<void> dispose() async {
    final subscriptions = _snapshotSubscriptions.values.toList();
    final sockets = _webSockets.toList();
    _snapshotSubscriptions.clear();
    _webSockets.clear();
    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );
    await Future.wait(sockets.map((socket) => socket.close()));
    await _server.close(force: true);
  }
}
