import 'package:freezed_annotation/freezed_annotation.dart';

import '../sdk/cursor.dart';

part 'session_projection.freezed.dart';

/// The_grid's projection of ONE work bead's owned session/lifecycle bead — the
/// JOIN row A40 reconciles against.
///
/// Read from the STATE store (`tgdog`), never from the read-only work source
/// (A37): the cursor lives on the_grid's own bead, so respawn-or-skip works
/// even for a foreign, unwritable work bead.
///
/// [isTerminal] gates unmount; the per-node reentrant [cursor] (D-3) carries
/// progress. The process-identity fields ([pgid] / [token] / [pid]) are the
/// legacy scalar restart fence stamped at `SessionStarted`; they are null until
/// then (the reentrant path stamps per-node identity inside [cursor] instead).
@freezed
abstract class SessionProjection with _$SessionProjection {
  /// Creates a projection of one session bead's cursor for [workBeadId].
  const factory SessionProjection({
    /// The work bead this session drives (`metadata.work_bead`).
    required String workBeadId,

    /// The session/lifecycle bead's OWN id in the state store — the target the
    /// capability hosts advance the cursor on (injected pull-free so a host
    /// never re-queries the store; A39). Null only in synthetic/test
    /// projections — the join bridge always populates it.
    String? sessionId,

    /// True once the session reached a positive terminal (the session bead
    /// `closed`, or the cursor advanced past `land`). A terminal session means
    /// the work node unmounts — never respawns.
    @Default(false) bool isTerminal,

    /// The spawned agent's process-group id, stamped at `SessionStarted` for
    /// orphan-kill on restart (Track D).
    int? pgid,

    /// The engine-minted `GRID_INSTANCE_TOKEN`, stamped at `SessionStarted` —
    /// the freshness fence against a stale prior-incarnation completion
    /// (Track C/D).
    String? token,

    /// The spawned agent's pid (diagnostics).
    int? pid,

    /// The per-node reentrant cursor (ADR-0008 D4 / D-3) — every inflated
    /// node's [NodeCursor] keyed by its `nodePath`, projected from the session
    /// bead's `grid.cursor.*` metadata and threaded down to `FormulaScope`
    /// pull-free (A39). Empty for a freshly-minted session (no node has written
    /// its cursor yet — the root formula's frontier mounts from `pending`).
    @Default(<String, NodeCursor>{}) FormulaCursor cursor,
  }) = _SessionProjection;
}
