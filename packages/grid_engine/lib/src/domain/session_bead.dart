/// The shared session-bead metadata contract (ADR-0007 / A40).
///
/// The_grid's OWN session/lifecycle beads (`type=session`, in the state store —
/// e.g. `tgdog`) carry the work-bead linkage + the phase cursor + the spawned
/// process identity as `metadata`. Every value is string-typed — the
/// `StationBeadWriter` chokepoint's `update` takes `Map<String, String>`.
///
/// This module is the SINGLE definition of those keys + the read projection +
/// the write payloads, so the join bridge (Track B — reads) and the effects /
/// restart-reconcile (Track C/D — writes) cannot drift on the schema. Writes go
/// through the chokepoint on the session bead, never a raw `bd` call and never
/// the read-only work source (A37 / invariant 2).
library;

import 'package:grid_controller/grid_controller.dart';

import 'session_projection.dart';
import 'work_phase.dart';

/// Metadata keys on a the_grid session bead. `work_bead` + `rig` are stamped at
/// mint by `StationBeadWriter.createSession`; the rest are written later through
/// the chokepoint.
abstract final class SessionBeadKeys {
  /// The work bead this session drives (stamped at mint; the JOIN key).
  static const workBead = 'work_bead';

  /// The phase cursor — `implement` | `verify` | `land` (the [WorkPhase] name),
  /// advanced by the effects as their last act + the controller's done-marker.
  static const phase = 'grid.phase';

  /// The spawned agent's process-group id (stamped at `SessionStarted`; the
  /// restart orphan-kill target, Track D).
  static const pgid = 'pgid';

  /// The spawned agent's pid (diagnostics).
  static const pid = 'pid';

  /// The engine-minted `GRID_INSTANCE_TOKEN` freshness fence (stamped at
  /// `SessionStarted`; drops a stale prior-incarnation completion).
  static const token = 'token';
}

/// Parses a `grid.phase` wire value (the [WorkPhase] name); defaults to
/// [WorkPhase.implement] for a missing/unknown value (a freshly minted session
/// with no cursor written yet).
WorkPhase parseWorkPhase(Object? wire) => switch (wire) {
  'implement' => WorkPhase.implement,
  'verify' => WorkPhase.verify,
  'land' => WorkPhase.land,
  _ => WorkPhase.implement,
};

/// Projects a the_grid session [Bead] into the [SessionProjection] the tree
/// joins against. The session bead's OWN status is the terminal signal
/// (`closed` ⇒ terminal); the cursor + process identity come from metadata.
SessionProjection projectSession(Bead sessionBead) {
  final metadata = sessionBead.metadata;
  return SessionProjection(
    workBeadId: (metadata[SessionBeadKeys.workBead] as String?) ?? '',
    sessionId: sessionBead.id,
    phase: parseWorkPhase(metadata[SessionBeadKeys.phase]),
    isTerminal: sessionBead.isClosed,
    pgid: _asInt(metadata[SessionBeadKeys.pgid]),
    pid: _asInt(metadata[SessionBeadKeys.pid]),
    token: metadata[SessionBeadKeys.token] as String?,
  );
}

/// The metadata payload that advances the cursor to [phase] — Track C/D write
/// this through the chokepoint, on the session bead.
Map<String, String> phaseCursorMetadata(WorkPhase phase) => {
  SessionBeadKeys.phase: phase.name,
};

/// The metadata payload stamped at `SessionStarted` (Track D): the process
/// identity for respawn-or-skip + the freshness fence. All string-valued
/// (`bd update --metadata` is `Map<String, String>`).
///
/// [pgid] is nullable — `SessionStarted.pgid` is null when pgid resolution
/// failed at spawn; the key is then omitted (an honest "no group kill target",
/// so restart falls back to a single-process kill) rather than written as a
/// bogus value.
Map<String, String> startedIdentityMetadata({
  required int? pgid,
  required int pid,
  required String token,
}) => {
  if (pgid != null) SessionBeadKeys.pgid: pgid.toString(),
  SessionBeadKeys.pid: pid.toString(),
  SessionBeadKeys.token: token,
};

int? _asInt(Object? value) => switch (value) {
  final int i => i,
  final String s => int.tryParse(s),
  final num n => n.toInt(),
  _ => null,
};
