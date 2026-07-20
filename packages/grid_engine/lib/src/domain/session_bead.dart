/// The shared session-bead metadata contract (ADR-0007 / A40).
///
/// The_grid's OWN session/lifecycle beads (`type=session`, in the state store —
/// e.g. `tgdog`) carry the work-bead linkage + the session-level markers as
/// `metadata`. Every value is string-typed — the `StationBeadWriter`
/// chokepoint's `update` takes `Map<String, String>`.
///
/// This module is the SINGLE definition of those keys + the read projection +
/// the write payloads, so the join bridge (reads) and the capability hosts /
/// restart-reconcile (writes) cannot drift on the schema. Writes go through the
/// chokepoint on the session bead, never a raw `bd` call and never the read-only
/// work source (A37 / invariant 2).
///
/// **The flat `grid.cursor.*` model retired (tg-eli phase 2).** Per-node
/// circuit state now lives on each step's OWN `type=step` bead
/// (`molecule_schema.dart` / `molecule_codec.dart`); the [ResultKeys]
/// namespace survives, reused VERBATIM on the step bead (R1). A HISTORICAL
/// session bead still bearing `grid.cursor.*` metadata is INERT: no surviving
/// read parses those keys ([projectSession] leaves the projection's `cursor`
/// empty), and nothing here throws on one.
library;

import 'package:beads_dart/beads_dart.dart';

import 'rework.dart' show voidKeyFor;
import 'session_projection.dart';

/// Metadata keys on a the_grid session bead. `work_bead` + `rig` are stamped at
/// mint by `StationBeadWriter.createSession`; the rest are written later through
/// the chokepoint.
abstract final class SessionBeadKeys {
  /// The work bead this session drives (stamped at mint; the JOIN key).
  static const workBead = 'work_bead';

  /// The spawned agent's process-group id (stamped at `SessionStarted`; the
  /// legacy scalar restart orphan-kill fence).
  static const pgid = 'pgid';

  /// The spawned agent's pid (diagnostics).
  static const pid = 'pid';

  /// The engine-minted `GRID_INSTANCE_TOKEN` freshness fence (stamped at
  /// `SessionStarted`; drops a stale prior-incarnation completion).
  static const token = 'token';

  /// Capture-only session lifecycle telemetry (FT-1, tg-pez) — the ISO-8601 UTC
  /// instant the session bead was minted, stamped once at birth by
  /// `StationBeadWriter.createSession`.
  static const startedAt = 'started_at';

  /// Capture-only session lifecycle telemetry — the ISO-8601 UTC instant the
  /// session bead was closed, stamped inside `StationBeadWriter.close`.
  static const closedAt = 'closed_at';

  /// The engine's OWN durable close-outcome marker (I-10, tg-4rw) — stamped in
  /// the chokepoint write that IMMEDIATELY precedes a POSITIVE-TERMINAL
  /// `bd close`, so a later mount can tell "this round finished" from "somebody
  /// closed this session mid-flight" without re-deriving the circuit.
  /// the_grid-internal (never a codec-boundary key), disjoint from the
  /// `grid.result.` namespace so the result projection never misreads it.
  /// Since tg-eli phase 2 this marker is the ONLY "done" evidence the mount
  /// boundary has — the retired flat cursor can no longer corroborate.
  static const outcome = 'grid.outcome';

  /// The human-escalation marker `SessionScope` writes on breaker exhaustion
  /// (D-5) — a human picks the session up. Was a private literal in
  /// `SessionScope`; the read projection needs it now, so it lives with the rest
  /// of the schema (same string — live beads carry it).
  static const escalation = 'grid.escalation';

  /// The capture-only escalation diagnostic (FT-1) written beside [escalation].
  static const escalationReason = 'grid.escalation_reason';

  /// The REWORK-DECLINE marker (tg-x1j) — a rework re-key orphaned a session
  /// this scope never observed parked at a gate; a human must investigate.
  static const reworkDeclined = 'grid.rework_declined';

  /// The capture-only decline diagnostic written beside [reworkDeclined].
  static const reworkDeclinedReason = 'grid.rework_declined_reason';

  /// The capture-only diagnostic stamped on a VOIDED session when the engine
  /// retires its dead JOIN key (I-10): WHY it was voided, written in the SAME
  /// chokepoint update as the re-keyed [workBead].
  static const voidedReason = 'grid.voided_reason';

  /// The EXPLICIT mint-mode discriminator (`DESIGN-tg-pm6.md` §10, R5a,
  /// Decided item 8 / §3 conflict 2): [kSessionModelFlat] or
  /// [kSessionModelMolecule]. Stamped ONCE, in the SAME `createSession` mint
  /// metadata as [workBead] — never rewritten after mint. **ABSENT ⇒ flat**:
  /// every session minted before this key existed, and every session minted
  /// on the legacy path, projects flat BY CONSTRUCTION (the drain guarantee —
  /// `DESIGN-tg-pm6.md` §12's "Drain proof").
  ///
  /// Deliberately explicit rather than sniffed from whether a `type=molecule`
  /// child bead exists: a molecule pour that crashes AFTER `createSession`
  /// lands but BEFORE its first step bead pours would sniff as "no molecule
  /// child" and mis-adopt down the flat path. This key is stamped in the same
  /// write as [workBead], so it is never absent for a session that intended to
  /// mint molecule.
  static const model = 'grid.session.model';
}

/// The [SessionBeadKeys.model] value a LEGACY / flat-cursor session carries —
/// written here for symmetry with [kSessionModelMolecule] even though the
/// read side ([projectSession]) treats ABSENT the same as this value; a
/// later rung (R5/R6) may stamp it explicitly rather than omitting the key.
const String kSessionModelFlat = 'flat';

/// The [SessionBeadKeys.model] value a MOLECULE-MINTED session carries,
/// stamped once at `createSession` time by a later rung (R5) in the SAME
/// write as [SessionBeadKeys.workBead].
const String kSessionModelMolecule = 'molecule';

/// The per-node RESULT keys — the payload a positive terminal publishes: a job's
/// [Ok.payload] on `complete` (e.g. the land step's `pr_url`) OR a daemon's
/// rendezvous payload on `ready` (e.g. the burn-follower's `{endpoint, …}`),
/// recorded on the step's OWN `type=step` bead so a finished/ready step's
/// artifact is durable (ADR-0006 D3: "record the PR on the lifecycle bead";
/// R1 re-homed the write from the session bead to the step bead — the keys
/// are unchanged). Flat + merge-safe (D-1/D-3). Read back pull-free by a
/// dependent step
/// via [projectCircuitResults] → `SessionProjection.results` → the `SiblingView`
/// (a `route`/`burn-host` reads a sibling's grade/endpoint — never a re-query,
/// A39). Also the human-/audit-facing record of what a step produced.
abstract final class ResultKeys {
  /// The flat-key namespace for the per-node step result.
  static const prefix = 'grid.result.';

  /// The flat key for [field] of the node at [nodePath]
  /// (`grid.result.{nodePath}.{field}`).
  static String keyFor(String nodePath, String field) =>
      '$prefix$nodePath.$field';

  /// The committee VERDICT payload fields the code asset's `route` step reads
  /// off each critic lane's result node (`grid.result.<lane>.<field>`). the_grid
  /// does NOT own the committee schema (it ships in the code asset), but the
  /// operator-ruling verb (`grid gate resolve --grade`, tg-i08) writes these to
  /// override a false/transport gate, and the route re-reads them — so the field
  /// NAMES are a shared contract pinned in ONE place to keep the ruling verb and
  /// the route's read from drifting.

  /// The letter grade A–F a critic lane records — the field `route` gates on
  /// (a persisted `F` re-gates the parked node on every re-arm; that is the
  /// I-14 no-op-resolve loop the ruling verb breaks).
  static const grade = 'grade';

  /// The verdict PROVENANCE — how the grade arrived (a critic's file/envelope,
  /// the fail-closed default, or [kOperatorRulingTransport] for a human
  /// override). Distinguishes a transport/false F from a true ran-and-failed F.
  static const transport = 'transport';

  /// The human-readable justification a critic — or an operator ruling — records
  /// alongside a grade.
  static const rationale = 'rationale';

  /// The DELIVERY METHOD id a terminal advance actuated (M5 D-4a) — the audit
  /// record of HOW the work left the station (`pr`, `export`, …). Written beside
  /// the method's own receipt keys under `grid.result.<nodePath>.*`.
  static const delivery = 'delivery';
}

/// The [ResultKeys.transport] provenance an OPERATOR RULING stamps on a lane
/// result (tg-i08) — the marker distinguishing a human override from an
/// automated verdict. A lane graded through the chokepoint with this transport
/// is a deliberate operator decision, never a fail-closed/transport artifact.
const String kOperatorRulingTransport = 'operator-ruling';

/// The metadata payload of an OPERATOR RULING on ONE lane node (tg-i08): the
/// corrected [grade] + the [kOperatorRulingTransport] provenance + the
/// [rationale], namespaced under `grid.result.<nodePath>`. Written through the
/// chokepoint on the_grid's OWN session bead — BEFORE the gate closes — so the
/// route re-reads the corrected grade instead of the persisted fail-closed `F`
/// (the I-14 loop where plain `gate resolve` re-gates seconds after re-arming).
/// Merge-safe (disjoint per-node keys), like every other result write.
Map<String, String> operatorRulingMetadata(
  String nodePath, {
  required String grade,
  required String rationale,
}) => {
  ResultKeys.keyFor(nodePath, ResultKeys.grade): grade,
  ResultKeys.keyFor(nodePath, ResultKeys.transport): kOperatorRulingTransport,
  ResultKeys.keyFor(nodePath, ResultKeys.rationale): rationale,
};

/// The max persisted length of a capture-only failure/escalation diagnostic
/// (FT-1, tg-pez) — a pathological multi-KB stderr is truncated so telemetry
/// never bloats the session bead's metadata (fail-safe).
const int kMaxReasonChars = 500;

/// Truncates [reason] to [kMaxReasonChars] (capture-only telemetry is never
/// allowed to grow unbounded, and never blocks a transition).
String truncateReason(String reason) => reason.length <= kMaxReasonChars
    ? reason
    : reason.substring(0, kMaxReasonChars);

/// The [SessionBeadKeys.outcome] value a POSITIVE-TERMINAL close stamps (I-10).
const String kSessionOutcomeComplete = 'complete';

/// The metadata payload the positive-terminal close writes through the
/// chokepoint IMMEDIATELY BEFORE `bd close` (I-10) — the durable "this round
/// finished" evidence the mount boundary reads. Merge-safe (one disjoint key).
Map<String, String> sessionCompleteMetadata() => <String, String>{
  SessionBeadKeys.outcome: kSessionOutcomeComplete,
};

/// The metadata payload that RETIRES a VOIDED session's dead JOIN key (I-10) —
/// the mechanized form of the operator's hand re-key (`work_bead=tg-1di#void-i8`),
/// and the FOURTH (engine-automatic) member of A47's re-run taxonomy.
///
/// Re-keys `work_bead` to [voidKeyFor] so the dead session drops out of the join
/// (the join holds ONE session per work bead — two would make the winner
/// map-order-dependent, and `grid rework` would refuse the bead as ambiguous),
/// and records WHY, capture-only. Written through the ONE chokepoint onto
/// the_grid's OWN session bead — never the foreign work source (A37).
Map<String, String> voidRetireMetadata({
  required String workBeadId,
  required String deadSessionId,
  required String reason,
}) => <String, String>{
  SessionBeadKeys.workBead: voidKeyFor(workBeadId, deadSessionId),
  SessionBeadKeys.voidedReason: truncateReason(reason),
};

/// The targeted metadata payload recording ONE node's step RESULT — the
/// optional [Ok.payload] (e.g. the land step's `{pr_url: …}`) namespaced under
/// [ResultKeys] so it merges alongside the node's terminal `state=complete`
/// write without colliding with any cursor key. An empty/absent payload yields
/// an empty map (nothing extra is written). Merge-safe (disjoint keys).
Map<String, String> nodeResultMetadata(
  String nodePath,
  Map<String, String>? payload,
) => {
  if (payload != null)
    for (final entry in payload.entries)
      ResultKeys.keyFor(nodePath, entry.key): entry.value,
};

/// Projects every `grid.result.*` key on [sessionBead] into a per-node result
/// map (the read half of [nodeResultMetadata]):
/// `grid.result.{nodePath}.{field}` → results[nodePath][field].
/// Values are stringified; a malformed key (no field segment) is skipped.
Map<String, Map<String, String>> projectCircuitResults(Bead sessionBead) {
  final results = <String, Map<String, String>>{};
  for (final entry in sessionBead.metadata.entries) {
    final key = entry.key;
    if (!key.startsWith(ResultKeys.prefix)) continue;
    final rest = key.substring(ResultKeys.prefix.length); // {nodePath}.{field}
    final dot = rest.lastIndexOf('.');
    if (dot <= 0 || dot == rest.length - 1) continue; // need a path AND a field
    final nodePath = rest.substring(0, dot);
    final field = rest.substring(dot + 1);
    (results[nodePath] ??= <String, String>{})[field] = entry.value.toString();
  }
  return results;
}

DateTime? _parseDate(Object? wire) =>
    wire == null ? null : DateTime.tryParse(wire.toString());

/// Projects a the_grid session [Bead] into the [SessionProjection] the tree
/// joins against. The session bead's OWN status is the terminal signal
/// (`closed` ⇒ terminal); the markers + legacy scalar process identity come
/// from metadata.
///
/// **`SessionProjection.cursor` is NEVER filled here** (tg-eli phase 2): the
/// flat `grid.cursor.*` projection retired with the flat model, so the field
/// keeps its empty default for EVERY session bead — including a historical
/// one still bearing `grid.cursor.*` metadata (those keys are simply ignored,
/// never parsed, never thrown on). The in-memory circuit cursor now exists
/// only as `projectMoleculeCursor`'s projection over the session's OWN
/// `type=step` beads (`SessionProjection.moleculeBeads`), computed at the
/// consumer (`SessionScope.build` / `sampleWedge` / `grid rework`). The field
/// itself survives as the projection's in-memory cursor SLOT (synthetic/test
/// projections populate it directly).
SessionProjection projectSession(Bead sessionBead) {
  final metadata = sessionBead.metadata;
  return SessionProjection(
    workBeadId: (metadata[SessionBeadKeys.workBead] as String?) ?? '',
    sessionId: sessionBead.id,
    isTerminal: sessionBead.isClosed,
    // I-10: the engine's own close-outcome evidence + the human-held markers —
    // what the mount boundary's disposition reads (never re-derived from the
    // circuit, which the mount boundary does not have).
    completed: metadata[SessionBeadKeys.outcome] == kSessionOutcomeComplete,
    humanHeld:
        metadata.containsKey(SessionBeadKeys.escalation) ||
        metadata.containsKey(SessionBeadKeys.reworkDeclined),
    // R5a's read-path substrate (DESIGN-tg-pm6.md §10): the EXPLICIT
    // discriminator, never sniffed from [moleculeBeads] presence — a
    // molecule-mode session with no molecule beads yet (a crashed pour) must
    // still read true here (Decided item 8 / §3 conflict 2). Any value other
    // than [kSessionModelMolecule] — including ABSENT — projects false.
    isMolecule: metadata[SessionBeadKeys.model] == kSessionModelMolecule,
    pgid: _asInt(metadata[SessionBeadKeys.pgid]),
    pid: _asInt(metadata[SessionBeadKeys.pid]),
    token: metadata[SessionBeadKeys.token] as String?,
    // `cursor` is deliberately NOT filled — see the function doc (tg-eli
    // phase 2: the flat `grid.cursor.*` projection retired; the molecule
    // cursor is projected at the consumer from `moleculeBeads`).
    // The per-node result payloads (D-5) — threaded down pull-free so a `route`
    // step reads its siblings' grades. Empty until a step records a result
    // (molecule sessions carry results on their step beads; this session-bead
    // slice survives for legacy reads and stays harmless when empty).
    results: projectCircuitResults(sessionBead),
    // Capture-only session lifecycle telemetry (FT-1) — surfaced typed; null
    // for a legacy bead / an open session.
    startedAt: _parseDate(metadata[SessionBeadKeys.startedAt]),
    closedAt: _parseDate(metadata[SessionBeadKeys.closedAt]),
  );
}

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
