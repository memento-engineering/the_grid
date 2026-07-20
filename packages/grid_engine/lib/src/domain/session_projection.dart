import 'package:beads_dart/beads_dart.dart';
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

    /// True once the session bead is CLOSED. NOT on its own a statement that the
    /// work is DONE — three different things close a session, and only the
    /// disposition (`sessionDispositionOf`) tells them apart (I-10, tg-4rw). Read
    /// it with [completed] / [humanHeld], never alone.
    @Default(false) bool isTerminal,

    /// True when the_grid's OWN close path stamped the durable positive-terminal
    /// marker (`grid.outcome=complete`) before `bd close` — the engine's own
    /// evidence that THIS round FINISHED (I-10). It is what separates a closed
    /// session that is `done` (never re-drive: the work source is read-only, so a
    /// landed bead stays open+ready and this latch is all that stops a resident
    /// station re-running it) from one somebody closed MID-FLIGHT (a dead key).
    /// False for a legacy bead closed before the marker shipped — the disposition
    /// falls back to the cursor shape there.
    @Default(false) bool completed,

    /// True when the session carries a HUMAN marker (`grid.escalation` from
    /// breaker exhaustion, or `grid.rework_declined`) — a human owns this round.
    /// The grid never re-drives it: an auto re-mint would loop
    /// escalate→close→re-mint→fail→escalate, spawning agents forever.
    @Default(false) bool humanHeld,

    /// The spawned agent's process-group id, stamped at `SessionStarted` for
    /// orphan-kill on restart (Track D).
    int? pgid,

    /// The engine-minted `GRID_INSTANCE_TOKEN`, stamped at `SessionStarted` —
    /// the freshness fence against a stale prior-incarnation completion
    /// (Track C/D).
    String? token,

    /// The spawned agent's pid (diagnostics).
    int? pid,

    /// The per-node reentrant cursor SLOT (ADR-0008 D4 / D-3) — every
    /// inflated node's [NodeCursor] keyed by its `nodePath`.
    ///
    /// Since tg-eli phase 2 (the flat `grid.cursor.*` model retired),
    /// `projectSession` NEVER fills this: it keeps its empty default for
    /// every projected session bead, including a historical flat one still
    /// bearing `grid.cursor.*` metadata (those keys are ignored, never
    /// parsed). The live circuit cursor is computed at the consumer from
    /// [moleculeBeads] via `projectMoleculeCursor`. The field survives as the
    /// projection's in-memory cursor shape — synthetic/test projections
    /// populate it directly.
    @Default(<String, NodeCursor>{}) CircuitCursor cursor,

    /// The per-node `grid.result.*` payloads, threaded down pull-free so a
    /// `route` step reads its siblings' grades — D-5. Keyed by `nodePath`; empty
    /// until a step records a result.
    @Default(<String, Map<String, String>>{})
    Map<String, Map<String, String>> results,

    /// The nodePaths with an OPEN `type=gate` bead blocking this session (D-7) —
    /// scanned from the state snapshot by the join bridge, not from this session
    /// bead. A node leaves this set when its gate bead closes, which re-arms the
    /// parked node (`SessionScope` flips it back to `pending`).
    @Default(<String>{}) Set<String> openGateNodes,

    /// Capture-only session lifecycle telemetry (FT-1, tg-pez) — the wall-clock
    /// instant the session bead was minted (its `started_at` metadata, stamped
    /// once at first spawn through the chokepoint); null for a legacy bead minted
    /// before the stamp shipped. Never gates orchestration.
    DateTime? startedAt,

    /// Capture-only session lifecycle telemetry — the wall-clock instant the
    /// session bead was closed (its `closed_at` metadata, stamped inside the
    /// chokepoint's `close`); null while the session is still open.
    DateTime? closedAt,

    /// True when the session bead carries the EXPLICIT `grid.session.model=
    /// molecule` discriminator (`SessionBeadKeys.model`, `DESIGN-tg-pm6.md`
    /// §10, R5a) — this session mints on the molecule model rather than the
    /// legacy flat `grid.cursor.*` model. **False for ABSENT** (every session
    /// minted before this key existed, and every ordinary flat session), so
    /// an in-flight session stays on the flat path by construction (the drain
    /// guarantee, §12's "Drain proof"). Never derived from [moleculeBeads]
    /// being non-empty — a molecule pour that crashed before its first step
    /// bead landed must still read `true` here, or a restart would mis-adopt
    /// it down the flat path (Decided item 8 / §3 conflict 2).
    @Default(false) bool isMolecule,

    /// This session's OWN `type=molecule`/`type=step` beads (R1's schema),
    /// bucketed by the join off their `grid.circuit.session`/
    /// `grid.step.session` stamp — the read-path substrate neither original
    /// proposal specified (`DESIGN-tg-pm6.md` §2, §10/R5a). Always empty for
    /// a flat session ([isMolecule] false). Raw beads, not yet a
    /// [CircuitCursor] — projecting these into the in-memory shape
    /// `CircuitScope` consumes is `projectMoleculeCursor`'s job
    /// (`molecule_codec.dart`), run once over exactly this list by a LATER
    /// rung (R5, the drain seam).
    @Default(<Bead>[]) List<Bead> moleculeBeads,

    /// This session's OWN dependency edges whose issue and target are both in
    /// [moleculeBeads]. A52 (Ratified a2, ADR-0000) makes `supersedes` edges
    /// the durable incarnation-round structure, so `live_frontier.dart` derives
    /// generation from graph structure rather than from mutable metadata.
    @Default(<BeadDependency>[]) List<BeadDependency> moleculeDependencies,
  }) = _SessionProjection;
}
