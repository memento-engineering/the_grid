/// The store connections a booted station holds open — the socket half of its
/// stores, vended so the resident shell can close them on the way down.
library;

import 'dart:async';
import 'dart:io' show stderr;

import 'package:beads_dart/beads_dart.dart' show DoltEndpoint, DoltQueryService;

import '../trajectory/trajectory_harness.dart';
import 'settle.dart';

/// The per-store close budget in the resident's unwind — the ONE constant
/// the_grid#resident-unwind-closes-store-sockets names (`kStoreCloseTimeout`,
/// 2 s). A half-open proxy socket can hang its close on the wire forever; past
/// this budget the handle is reported BY NAME with its endpoint and no longer
/// awaited, so the resident exits instead of parking on it (tg-supq).
///
/// Homed here, beside [closeStoreConnections], so the resident shell
/// (grid_cli's `up`) and [StationWorkRuntime.shutdown] share one budget and one
/// primitive; grid_cli re-exports it under the same name.
const Duration kStoreCloseTimeout = Duration(seconds: 2);

/// One open store connection, named for the operator's shutdown narrative.
///
/// Implementations must be idempotent on [close]: the assembly that opened the
/// connection closes it on its own shutdown too, and an unwind may reach a
/// connection another rail already closed.
abstract interface class StoreConnection {
  /// The operator-facing store name — `state` for the grid's own state store,
  /// otherwise the substation's name.
  String get name;

  /// Closes the connection. Never throws for an already-closed connection.
  Future<void> close();
}

/// The endpoint a [StoreConnection] dials, for the unwind narrative: a handle
/// that does not confirm its close is named together with WHERE it points, so
/// the operator is not left to `lsof` the process by hand (tg-supq AC-2/AC-4).
///
/// An extension rather than an interface member so a foreign implementation
/// (a test fake, a station's own connection class) keeps compiling; it renders
/// a designed absence for one that vends no endpoint.
extension StoreConnectionEndpoint on StoreConnection {
  /// `host:port/database` for a pooled Dolt handle; the state server's
  /// coordinates for the trajectory's sessions; a rendered absence otherwise.
  String get endpoint => switch (this) {
    DoltStoreConnection(:final endpoint) => endpoint,
    TrajectoryStoreConnection(:final endpoint) => endpoint,
    _ => '(endpoint not vended)',
  };
}

/// Renders [endpoint] as `host:port/database` — never the credential.
String describeDoltEndpoint(DoltEndpoint endpoint) =>
    '${endpoint.host}:${endpoint.port}/${endpoint.database}';

/// The [StoreConnection] over a pooled [DoltQueryService].
final class DoltStoreConnection implements StoreConnection {
  /// Wraps [service] under the operator-facing [name].
  const DoltStoreConnection(this.name, this._service);

  @override
  final String name;

  final DoltQueryService _service;

  /// The pooled service's `host:port/database`.
  String get endpoint => describeDoltEndpoint(_service.endpoint);

  @override
  Future<void> close() => _service.close();
}

/// The [StoreConnection] over a [TrajectoryHarness]'s own sessions.
///
/// The harness dials the same server the grid's state store runs on (the
/// `trajectory` database is a sibling of the state ledger), so its sockets keep
/// a resident isolate alive exactly as a pooled store socket does. The harness
/// closes them in its own `shutdown()`; this vends the remainder — a corpse
/// whose close threw, or a session that outlived the shutdown budget — to the
/// one closing locus that can await it. A harness that never dialled (disabled,
/// unprovisioned, or dry-run) closes nothing and still vends: `openStores` is
/// captured once at assembly, before `start()` decides.
final class TrajectoryStoreConnection implements StoreConnection {
  /// Wraps [_harness] under the operator-facing name `trajectory`. [endpoint]
  /// names the server its sessions dial — the state store's, when known.
  const TrajectoryStoreConnection(this._harness, {String? endpoint})
    : _endpoint = endpoint;

  final TrajectoryHarness _harness;
  final String? _endpoint;

  @override
  String get name => 'trajectory';

  /// The state-store server's coordinates with the `trajectory` database, or
  /// a rendered absence when the state store opened no socket.
  String get endpoint =>
      _endpoint ?? '(the state-store sql-server, database trajectory)';

  @override
  Future<void> close() => _harness.closeOpenSessions();
}

/// Orders a station's open store connections for shutdown: the state store
/// first (it is the last writer — the session/cursor beads land there), then
/// the [trajectory] harness's own sessions (the same server, the other writer),
/// then each work store by name for a deterministic narrative. A store on the
/// CLI read path opened no socket ([GridRuntimeBundle.dolt] is null) and
/// contributes no connection.
List<StoreConnection> orderedStoreConnections({
  required DoltQueryService? state,
  required Map<String, DoltQueryService?> work,
  TrajectoryHarness? trajectory,
}) => <StoreConnection>[
  if (state != null) DoltStoreConnection('state', state),
  if (trajectory != null)
    TrajectoryStoreConnection(
      trajectory,
      endpoint: state == null
          ? null
          : '${state.endpoint.host}:${state.endpoint.port}/trajectory',
    ),
  for (final name in work.keys.toList()..sort())
    if (work[name] case final service?) DoltStoreConnection(name, service),
];

/// A store handle whose close did not CONFIRM inside its budget — the handle
/// stays open (the_grid#store-handles-are-tracked-until-close-is-confirmed) and
/// is what the operator's `lsof` would show; this is that line, rendered by the
/// resident instead.
final class OutstandingStoreHandle {
  /// Names [name] at [endpoint], outstanding for [reason].
  const OutstandingStoreHandle({
    required this.name,
    required this.endpoint,
    required this.reason,
  });

  /// The operator-facing store name.
  final String name;

  /// Where the handle points (`host:port/database`, or a rendered absence).
  final String endpoint;

  /// Why the close did not confirm: the budget it outlived, or the error its
  /// close threw.
  final String reason;

  /// `"state" (127.0.0.1:49967/tranquility) — close did not confirm within
  /// 2000ms`.
  String describe() => '"$name" ($endpoint) — $reason';

  @override
  String toString() => 'OutstandingStoreHandle(${describe()})';
}

/// What one bounded confirm pass over a station's store handles found.
final class StoreCloseReport {
  /// Reports [closed] confirmed and [outstanding] still open after [budget].
  const StoreCloseReport({
    required this.closed,
    required this.outstanding,
    required this.budget,
  });

  /// The names whose close CONFIRMED, in close order.
  final List<String> closed;

  /// The handles still open after the pass, in close order.
  final List<OutstandingStoreHandle> outstanding;

  /// The per-handle budget the pass ran under.
  final Duration budget;

  /// How many handles the pass attempted.
  int get attempted => closed.length + outstanding.length;

  /// True when every handle confirmed its close.
  bool get allConfirmed => outstanding.isEmpty;

  /// The operator lines: the count, then one line per outstanding handle.
  List<String> get narrative => <String>[
    'store connections closed: ${closed.length}/$attempted',
    for (final handle in outstanding)
      'store handle still outstanding: ${handle.describe()}',
  ];
}

/// Closes every handle in [stores] in order, each under [within], and reports
/// which CONFIRMED and which did not — by name, with endpoint and reason.
///
/// This is the ONE bounded confirm pass of the unwind
/// (the_grid#resident-unwind-closes-store-sockets): the resident shell's store
/// closes and [StationWorkRuntime.shutdown]'s confirm pass both run it, so the
/// budget ([kStoreCloseTimeout]), the step names (`store close (<name>)`) and
/// the narrative (`store connections closed: N/M`) exist once. Each close is a
/// [settle] step: a handle whose close hangs on the wire is awaited for
/// [within] — or for what is left of [deadline] when an unwind's total is
/// supplied, whichever is smaller — then named through [onRefusal] (the settle
/// line, stderr by default) and [onFlare] (`unwind.storeHandleOutstanding`) and
/// NO LONGER awaited, so one half-open proxy socket can delay the exit by its
/// budget but never hold it. A refused close is reported the same way: a
/// refused close is not a confirmed one. The pass itself never throws.
Future<StoreCloseReport> closeStoreConnections(
  List<StoreConnection> stores, {
  Duration within = kStoreCloseTimeout,
  UnwindDeadline? deadline,
  void Function(String message)? onRefusal,
  void Function(String name, Map<String, String> data)? onFlare,
}) async {
  final closed = <String>[];
  final outstanding = <OutstandingStoreHandle>[];
  for (final store in List<StoreConnection>.of(stores)) {
    final budget = deadline?.budget(within) ?? within;
    String? refusal;
    Duration? expired;
    final confirmed = await settle(
      'store close (${store.name})',
      store.close,
      within: budget,
      onRefusal: (message) {
        refusal = message;
        (onRefusal ?? stderr.writeln)(message);
      },
      onTimeout: (_, spent) {
        expired = spent;
      },
    );
    if (confirmed) {
      closed.add(store.name);
      continue;
    }
    final reason = expired != null
        ? 'close did not confirm within ${expired!.inMilliseconds}ms'
        : 'close refused (${refusal ?? 'no reason given'})';
    final handle = OutstandingStoreHandle(
      name: store.name,
      endpoint: store.endpoint,
      reason: reason,
    );
    outstanding.add(handle);
    onFlare?.call('unwind.storeHandleOutstanding', {
      'store': handle.name,
      'endpoint': handle.endpoint,
      'reason': reason,
      'budgetMs': '${budget.inMilliseconds}',
    });
  }
  return StoreCloseReport(
    closed: closed,
    outstanding: outstanding,
    budget: within,
  );
}
