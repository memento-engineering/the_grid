/// The store connections a booted station holds open — the socket half of its
/// stores, vended so the resident shell can close them on the way down.
library;

import 'package:beads_dart/beads_dart.dart' show DoltQueryService;

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

/// The [StoreConnection] over a pooled [DoltQueryService].
final class DoltStoreConnection implements StoreConnection {
  /// Wraps [service] under the operator-facing [name].
  const DoltStoreConnection(this.name, this._service);

  @override
  final String name;

  final DoltQueryService _service;

  @override
  Future<void> close() => _service.close();
}

/// Orders a station's open store connections for shutdown: the state store
/// first (it is the last writer — the session/cursor beads land there), then
/// each work store by name for a deterministic narrative. A store on the CLI
/// read path opened no socket ([GridRuntimeBundle.dolt] is null) and
/// contributes no connection.
List<StoreConnection> orderedStoreConnections({
  required DoltQueryService? state,
  required Map<String, DoltQueryService?> work,
}) => <StoreConnection>[
  if (state != null) DoltStoreConnection('state', state),
  for (final name in work.keys.toList()..sort())
    if (work[name] case final service?) DoltStoreConnection(name, service),
];
