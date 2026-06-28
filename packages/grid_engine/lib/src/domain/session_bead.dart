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

import '../sdk/cursor.dart';
import '../sdk/formula.dart';
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

/// The per-node reentrant cursor keys (ADR-0008 D4 / M4-P1 §3, D-3).
///
/// The reentrant engine's progress is a step-graph position, not a 3-value
/// [WorkPhase] enum, so each inflated node carries its own FLAT, merge-safe
/// `grid.cursor.{nodePath}.{field}` metadata on the_grid's OWN session bead.
/// Flatness closes the disjoint-key write race (two concurrent leaf hosts on
/// different nodes never collide); the chokepoint serialization (D-1) closes the
/// same-key race.
///
/// This is the **the_grid-internal** schema on `tgdog` session beads — the codec
/// boundary ([StationBeadWriter.rigKey] `'rig'`, `work_bead`, `IssueType.rig`,
/// `type=convergence`, `kGridNamespace='grid'`, the M2 convergence byte-port)
/// is untouched (A37: gc never reads `tgdog`). It coexists with the legacy
/// [SessionBeadKeys.phase] cursor through Wave 1–3; the [WorkPhase] path retires
/// in Track H when agent/verify/land move onto the `code` formula.
abstract final class CursorKeys {
  /// The flat-key namespace for the per-node cursor.
  static const prefix = 'grid.cursor.';

  /// The [StepState] name field suffix.
  static const state = 'state';

  /// The spawned process-group id suffix (the per-node respawn fence — D-4).
  static const pgid = 'pgid';

  /// The spawned leader pid suffix.
  static const pid = 'pid';

  /// The engine-minted `GRID_INSTANCE_TOKEN` freshness-fence suffix.
  static const token = 'token';

  /// The supervised-restart counter suffix (gates the breaker — D-5).
  static const restartCount = 'restartCount';

  /// The backoff cooldown-deadline suffix (ISO-8601).
  static const cooldownUntil = 'cooldownUntil';

  /// The restoration log byte-offset suffix (deferred adopt seam — §11).
  static const logOffset = 'logOffset';

  /// The flat key for [field] of the node at [nodePath]
  /// (`grid.cursor.{nodePath}.{field}`). A `nodePath` is `/`-joined step ids
  /// (e.g. `tg-burn/harnessPeripheral/build`); step ids must not contain `.`
  /// (the field separator).
  static String keyFor(String nodePath, String field) =>
      '$prefix$nodePath.$field';
}

/// The flat metadata payload for ONE node's cursor entry — the merge-safe,
/// disjoint-key write through the chokepoint (D-1/D-3). Only set fields are
/// written ([state] and [restartCount] always; the rest omitted when null, an
/// honest "unset" rather than a bogus value).
Map<String, String> nodeCursorMetadata(String nodePath, NodeCursor node) => {
  CursorKeys.keyFor(nodePath, CursorKeys.state): node.state.name,
  CursorKeys.keyFor(nodePath, CursorKeys.restartCount):
      node.restartCount.toString(),
  if (node.pgid != null)
    CursorKeys.keyFor(nodePath, CursorKeys.pgid): node.pgid.toString(),
  if (node.pid != null)
    CursorKeys.keyFor(nodePath, CursorKeys.pid): node.pid.toString(),
  if (node.token != null)
    CursorKeys.keyFor(nodePath, CursorKeys.token): node.token!,
  if (node.cooldownUntil != null)
    CursorKeys.keyFor(nodePath, CursorKeys.cooldownUntil):
        node.cooldownUntil!.toIso8601String(),
  if (node.logOffset != null)
    CursorKeys.keyFor(nodePath, CursorKeys.logOffset): node.logOffset.toString(),
};

/// The targeted metadata payload advancing ONE node's [state] (the merge-safe
/// state-only write a `CapabilityHost` issues on a step terminal — Track E).
/// Disjoint from every other node's keys, so concurrent writes never collide
/// (the flat half of invariant 2; D-1 closes the same-key half).
Map<String, String> nodeStateMetadata(String nodePath, StepState state) => {
  CursorKeys.keyFor(nodePath, CursorKeys.state): state.name,
};

/// The targeted metadata payload stamping ONE node's spawned identity at
/// `SessionStarted` (Track E / D-4): `state=running` + the per-node pgid/pid/
/// token (the respawn fence). [pgid] is omitted when null (an honest "no group
/// kill target" rather than a bogus value).
Map<String, String> nodeStartedMetadata(
  String nodePath, {
  required int? pgid,
  required int pid,
  required String token,
}) => {
  CursorKeys.keyFor(nodePath, CursorKeys.state): StepState.running.name,
  if (pgid != null) CursorKeys.keyFor(nodePath, CursorKeys.pgid): pgid.toString(),
  CursorKeys.keyFor(nodePath, CursorKeys.pid): pid.toString(),
  CursorKeys.keyFor(nodePath, CursorKeys.token): token,
};

/// Projects every `grid.cursor.*` key on [sessionBead] into a [FormulaCursor],
/// keyed by `nodePath` (the read half of [nodeCursorMetadata]). A node's
/// `nodePath` is everything between the prefix and the final `.field` segment.
/// Non-cursor metadata is ignored; a malformed key (no field segment) is
/// skipped.
FormulaCursor projectFormulaCursor(Bead sessionBead) {
  final byPath = <String, Map<String, Object?>>{};
  for (final entry in sessionBead.metadata.entries) {
    final key = entry.key;
    if (!key.startsWith(CursorKeys.prefix)) continue;
    final rest = key.substring(CursorKeys.prefix.length); // {nodePath}.{field}
    final dot = rest.lastIndexOf('.');
    if (dot <= 0 || dot == rest.length - 1) continue; // need a path AND a field
    final nodePath = rest.substring(0, dot);
    final field = rest.substring(dot + 1);
    (byPath[nodePath] ??= {})[field] = entry.value;
  }
  final cursor = <String, NodeCursor>{};
  byPath.forEach((nodePath, fields) {
    cursor[nodePath] = NodeCursor(
      state: _parseStepState(fields[CursorKeys.state]),
      pgid: _asInt(fields[CursorKeys.pgid]),
      pid: _asInt(fields[CursorKeys.pid]),
      token: fields[CursorKeys.token]?.toString(),
      restartCount: _asInt(fields[CursorKeys.restartCount]) ?? 0,
      cooldownUntil: _parseDate(fields[CursorKeys.cooldownUntil]),
      logOffset: _asInt(fields[CursorKeys.logOffset]),
    );
  });
  return cursor;
}

/// Parses a [StepState] name; defaults to [StepState.pending] for a
/// missing/unknown wire value (a node with no state written yet).
StepState _parseStepState(Object? wire) {
  final name = wire?.toString();
  for (final s in StepState.values) {
    if (s.name == name) return s;
  }
  return StepState.pending;
}

DateTime? _parseDate(Object? wire) =>
    wire == null ? null : DateTime.tryParse(wire.toString());

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
    // The per-node reentrant cursor (D-3) — threaded down to FormulaScope
    // pull-free (A39). Empty for a legacy/freshly-minted session with no
    // `grid.cursor.*` keys yet.
    cursor: projectFormulaCursor(sessionBead),
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
