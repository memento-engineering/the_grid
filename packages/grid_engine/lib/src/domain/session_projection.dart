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
  const SessionProjection._();

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
    /// bead's `grid.cursor.*` metadata and threaded down to `CircuitScope`
    /// pull-free (A39). Empty for a freshly-minted session (no node has written
    /// its cursor yet — the root circuit's frontier mounts from `pending`).
    @Default(<String, NodeCursor>{}) CircuitCursor cursor,

    /// The per-node `grid.result.*` payloads, threaded down pull-free so a
    /// `route` step reads its siblings' grades — D-5. Keyed by `nodePath`; empty
    /// until a step records a result.
    @Default(<String, Map<String, String>>{})
    Map<String, Map<String, String>> results,

    /// The OPEN `type=gate` beads blocking this session (D-7), keyed by the
    /// parked `nodePath` — scanned from the state snapshot by the join bridge,
    /// not from this session bead. A node leaves this map when its gate bead
    /// closes, which re-arms the parked node (`SessionScope` flips it back to
    /// `pending`). Each entry carries the gate bead's OWN id + reason, so
    /// `SessionScope` can BOTH decide whether the park is machine-actionable AND
    /// close that exact bead through the chokepoint (tg-b3k) — pull-free (A39):
    /// a tree node never re-queries the store.
    @Default(<String, OpenGate>{}) Map<String, OpenGate> openGates,

    /// The highest REWORK round already retired for this work bead (0 = none) —
    /// computed by the join bridge off every session's `work_bead` key
    /// (`<workBeadId>#r<N>`). The auto-respec transition mints round
    /// `reworkRounds + 1` and refuses at `kMaxReworkRounds` (tg-b3k).
    @Default(0) int reworkRounds,

    /// Capture-only session lifecycle telemetry (FT-1, tg-pez) — the wall-clock
    /// instant the session bead was minted (its `started_at` metadata, stamped
    /// once at first spawn through the chokepoint); null for a legacy bead minted
    /// before the stamp shipped. Never gates orchestration.
    DateTime? startedAt,

    /// Capture-only session lifecycle telemetry — the wall-clock instant the
    /// session bead was closed (its `closed_at` metadata, stamped inside the
    /// chokepoint's `close`); null while the session is still open.
    DateTime? closedAt,
  }) = _SessionProjection;

  /// The nodePaths with an OPEN gate blocking this session (D-7) — the re-arm
  /// signal `SessionScope` reads. DERIVED from [openGates], so the signal and
  /// the gate records can never drift apart (one source of truth).
  Set<String> get openGateNodes => openGates.keys.toSet();
}

/// One OPEN `type=gate` bead blocking a session at [nodePath] (D-7) — the join's
/// projection of that bead's identity + reason, threaded down pull-free (A39) so
/// `SessionScope` can auto-resolve a machine-actionable park (tg-b3k) without
/// ever re-querying the store from a tree node.
@freezed
abstract class OpenGate with _$OpenGate {
  /// Creates the projection of the gate bead [gateId] parking [nodePath].
  const factory OpenGate({
    /// The gate bead's own id in the state store — the close target.
    required String gateId,

    /// The parked node's path (the gate bead's `metadata.node`).
    required String nodePath,

    /// Why the work parked (the gate bead's `metadata.reason`). A reason
    /// carrying `kRespecGatePrefix` is MACHINE-ACTIONABLE; anything else is a
    /// human gate.
    @Default('') String reason,
  }) = _OpenGate;
}
