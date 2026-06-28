import 'package:freezed_annotation/freezed_annotation.dart';

import '../sdk/cursor.dart';
import 'work_phase.dart';

part 'session_projection.freezed.dart';

/// The_grid's projection of ONE work bead's owned session/lifecycle bead — the
/// JOIN row A40 reconciles against.
///
/// Read from the STATE store (`tgdog`), never from the read-only work source
/// (A37): the cursor lives on the_grid's own bead, so respawn-or-skip works
/// even for a foreign, unwritable work bead.
///
/// Track A populates [phase] + [isTerminal]. The process-identity fields
/// ([pgid] / [token] / [pid]) are stamped at `SessionStarted` by Track C/D for
/// respawn-or-skip and the freshness fence; they are null until then.
@freezed
abstract class SessionProjection with _$SessionProjection {
  /// Creates a projection of one session bead's cursor for [workBeadId].
  const factory SessionProjection({
    /// The work bead this session drives (`metadata.work_bead`).
    required String workBeadId,

    /// The session/lifecycle bead's OWN id in the state store — the target the
    /// verify/land effects advance the cursor on (injected pull-free so an
    /// effect never re-queries the store; A39). Null only in synthetic/test
    /// projections — the join bridge always populates it.
    String? sessionId,

    /// The cursor phase (`metadata.grid.phase`): implement | verify | land.
    required WorkPhase phase,

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
    /// pull-free (A39). Empty for a legacy/freshly-minted session (the linear
    /// agent/verify/land path still rides the [phase] cursor until Track H).
    @Default(<String, NodeCursor>{}) FormulaCursor cursor,
  }) = _SessionProjection;
}
