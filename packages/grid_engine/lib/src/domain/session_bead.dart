/// The shared session-bead metadata contract (ADR-0007 / A40).
///
/// The_grid's OWN session/lifecycle beads (`type=session`, in the state store —
/// e.g. `tgdog`) carry the work-bead linkage + the per-node reentrant cursor +
/// the spawned process identity as `metadata`. Every value is string-typed —
/// the `StationBeadWriter` chokepoint's `update` takes `Map<String, String>`.
///
/// This module is the SINGLE definition of those keys + the read projection +
/// the write payloads, so the join bridge (reads) and the capability hosts /
/// restart-reconcile (writes) cannot drift on the schema. Writes go through the
/// chokepoint on the session bead, never a raw `bd` call and never the read-only
/// work source (A37 / invariant 2).
library;

import 'package:beads_dart/beads_dart.dart';

import '../sdk/cursor.dart';
import '../sdk/circuit.dart';
import 'rework.dart';
import 'session_projection.dart';

/// Metadata keys on a the_grid session bead. `work_bead` + `rig` are stamped at
/// mint by `StationBeadWriter.createSession`; the rest are written later through
/// the chokepoint.
abstract final class SessionBeadKeys {
  /// The work bead this session drives (stamped at mint; the JOIN key).
  static const workBead = 'work_bead';

  /// The spawned agent's process-group id (stamped at `SessionStarted`; the
  /// legacy scalar restart orphan-kill fence, kept alongside the per-node
  /// [CursorKeys.pgid]).
  static const pgid = 'pgid';

  /// The spawned agent's pid (diagnostics).
  static const pid = 'pid';

  /// The engine-minted `GRID_INSTANCE_TOKEN` freshness fence (stamped at
  /// `SessionStarted`; drops a stale prior-incarnation completion).
  static const token = 'token';

  /// Capture-only session lifecycle telemetry (FT-1, tg-pez) — the ISO-8601 UTC
  /// instant the session bead was minted, stamped once at birth by
  /// `StationBeadWriter.createSession`. Session-level (NOT under the
  /// `grid.cursor.` namespace), so the cursor projection never misreads it.
  static const startedAt = 'started_at';

  /// Capture-only session lifecycle telemetry — the ISO-8601 UTC instant the
  /// session bead was closed, stamped inside `StationBeadWriter.close`.
  static const closedAt = 'closed_at';

  /// The engine's OWN durable close-outcome marker (I-10, tg-4rw) — stamped in
  /// the chokepoint write that IMMEDIATELY precedes a POSITIVE-TERMINAL
  /// `bd close`, so a later mount can tell "this round finished" from "somebody
  /// closed this session mid-flight" without re-deriving the circuit. Cursor
  /// shape alone cannot: a session closed BETWEEN steps has every WRITTEN node
  /// `complete` while the circuit is nowhere near its terminal. the_grid-internal
  /// (never a codec-boundary key), disjoint from the `grid.cursor.` /
  /// `grid.result.` namespaces so neither projection misreads it.
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

/// The per-node reentrant cursor keys (ADR-0008 D4 / M4-P1 §3, D-3).
///
/// The reentrant engine's progress is a step-graph position, not a 3-value
/// phase enum, so each inflated node carries its own FLAT, merge-safe
/// `grid.cursor.{nodePath}.{field}` metadata on the_grid's OWN session bead.
/// Flatness closes the disjoint-key write race (two concurrent leaf hosts on
/// different nodes never collide); the chokepoint serialization (D-1) closes the
/// same-key race.
///
/// This is the **the_grid-internal** schema on `tgdog` session beads — the codec
/// boundary ([StationBeadWriter.rigKey] `'rig'`, `work_bead`, `IssueType.rig`,
/// `type=convergence`, `kGridNamespace='grid'`, the M2 convergence byte-port)
/// is untouched (A37: gc never reads `tgdog`).
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

  /// The ROUTING rewind-round suffix (tg-o90) — the per-node count of rewind
  /// waves that re-keyed this node. Flat + merge-safe like every other cursor
  /// field; DISJOINT from [restartCount] (the crash-restart budget).
  static const rewindCount = 'rewindCount';

  /// The ADOPTION-REAP counter suffix — the per-node count of station
  /// generations that died while this node was `running`. CAPTURE-ONLY: a THIRD
  /// incarnation axis (A47), disjoint from both [restartCount] (the
  /// crash-restart budget) and [rewindCount] (routing). Nothing gates on it and
  /// it is not in the reconcile key.
  static const reapCount = 'reapCount';

  /// The backoff cooldown-deadline suffix (ISO-8601).
  static const cooldownUntil = 'cooldownUntil';

  /// The restoration log byte-offset suffix (deferred adopt seam — §11).
  static const logOffset = 'logOffset';

  /// Capture-only per-node FLOW-TELEMETRY suffixes (FT-1, tg-pez) — the step's
  /// begin/finish instants (ISO-8601 UTC), the derived duration, and the failure
  /// diagnostic. Written MERGED into the transition's single chokepoint write;
  /// never read on a build/orchestration path (capture-only).

  /// The step-begin instant suffix (the host's kick; ISO-8601 UTC).
  static const startedAt = 'startedAt';

  /// The terminal-transition instant suffix (ISO-8601 UTC).
  static const finishedAt = 'finishedAt';

  /// The derived `finishedAt - startedAt` milliseconds suffix.
  static const durationMs = 'durationMs';

  /// The truncated failure-diagnostic suffix (stamped alongside a `failed`
  /// terminal — the `AllocationFailed.reason`).
  static const failureReason = 'failureReason';

  /// The flat key for [field] of the node at [nodePath]
  /// (`grid.cursor.{nodePath}.{field}`). A `nodePath` is `/`-joined step ids
  /// (e.g. `tg-burn/harnessPeripheral/build`); step ids must not contain `.`
  /// (the field separator).
  static String keyFor(String nodePath, String field) =>
      '$prefix$nodePath.$field';
}

/// The per-node RESULT keys — the payload a positive terminal publishes: a job's
/// [Ok.payload] on `complete` (e.g. the land step's `pr_url`) OR a daemon's
/// rendezvous payload on `ready` (e.g. the burn-follower's `{endpoint, …}`),
/// recorded on the_grid's OWN session bead so a finished/ready step's artifact is
/// durable (ADR-0006 D3: "record the PR on the lifecycle bead"). DISJOINT from
/// the [CursorKeys] namespace (`grid.result.` vs `grid.cursor.`), so
/// [projectCircuitCursor] never misreads a result key as cursor state; flat +
/// merge-safe like the cursor (D-1/D-3). Read back pull-free by a dependent step
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

/// The flat, CAPTURE-ONLY flow-telemetry payload for ONE node (FT-1, tg-pez) —
/// step timing ([startedAt]/[finishedAt]/[durationMs]) + the failure diagnostic
/// ([failureReason]), MERGED into a transition's single chokepoint write (no
/// extra write traffic; disjoint from every other node's keys, so the D-1/D-3
/// merge-safety is unchanged). Every field is OMITTED when null (an honest
/// "unmeasured" rather than a bogus value), so missing telemetry never blocks a
/// transition — the fail-safe posture. Timestamps are ISO-8601 UTC;
/// [failureReason] is truncated to [kMaxReasonChars]. This never gates
/// orchestration — nothing on a build/reconcile path reads these keys.
Map<String, String> nodeTelemetryMetadata(
  String nodePath, {
  DateTime? startedAt,
  DateTime? finishedAt,
  int? durationMs,
  String? failureReason,
}) => {
  if (startedAt != null)
    CursorKeys.keyFor(nodePath, CursorKeys.startedAt): startedAt
        .toUtc()
        .toIso8601String(),
  if (finishedAt != null)
    CursorKeys.keyFor(nodePath, CursorKeys.finishedAt): finishedAt
        .toUtc()
        .toIso8601String(),
  if (durationMs != null)
    CursorKeys.keyFor(nodePath, CursorKeys.durationMs): durationMs.toString(),
  if (failureReason != null)
    CursorKeys.keyFor(nodePath, CursorKeys.failureReason): truncateReason(
      failureReason,
    ),
};

/// The flat metadata payload for ONE node's cursor entry — the merge-safe,
/// disjoint-key write through the chokepoint (D-1/D-3). Only set fields are
/// written ([state] and [restartCount] always; the rest omitted when null, an
/// honest "unset" rather than a bogus value). The capture-only telemetry fields
/// (FT-1) round-trip through [nodeTelemetryMetadata].
Map<String, String> nodeCursorMetadata(String nodePath, NodeCursor node) => {
  CursorKeys.keyFor(nodePath, CursorKeys.state): node.state.name,
  CursorKeys.keyFor(nodePath, CursorKeys.restartCount): node.restartCount
      .toString(),
  CursorKeys.keyFor(nodePath, CursorKeys.rewindCount): node.rewindCount
      .toString(),
  CursorKeys.keyFor(nodePath, CursorKeys.reapCount): node.reapCount.toString(),
  if (node.pgid != null)
    CursorKeys.keyFor(nodePath, CursorKeys.pgid): node.pgid.toString(),
  if (node.pid != null)
    CursorKeys.keyFor(nodePath, CursorKeys.pid): node.pid.toString(),
  if (node.token != null)
    CursorKeys.keyFor(nodePath, CursorKeys.token): node.token!,
  if (node.cooldownUntil != null)
    CursorKeys.keyFor(nodePath, CursorKeys.cooldownUntil): node.cooldownUntil!
        .toIso8601String(),
  if (node.logOffset != null)
    CursorKeys.keyFor(nodePath, CursorKeys.logOffset): node.logOffset
        .toString(),
  ...nodeTelemetryMetadata(
    nodePath,
    startedAt: node.startedAt,
    finishedAt: node.finishedAt,
    durationMs: node.durationMs,
    failureReason: node.failureReason,
  ),
};

/// The targeted metadata payload advancing ONE node's [state] (the merge-safe
/// state-only write a `CapabilityHost` issues on a step terminal — Track E).
/// Disjoint from every other node's keys, so concurrent writes never collide
/// (the flat half of invariant 2; D-1 closes the same-key half).
Map<String, String> nodeStateMetadata(String nodePath, StepState state) => {
  CursorKeys.keyFor(nodePath, CursorKeys.state): state.name,
};

/// The targeted metadata payload for a SUPERVISED FAILURE of ONE node (D-5):
/// `state=failed` + the bumped [restartCount] + the backoff [cooldownUntil]
/// (omitted when the breaker is exhausted — then `restartCount >= maxRestarts`
/// makes the node circuit-broken and SessionScope escalates). Merge-safe.
Map<String, String> nodeFailedMetadata(
  String nodePath, {
  required int restartCount,
  DateTime? cooldownUntil,
}) => {
  CursorKeys.keyFor(nodePath, CursorKeys.state): StepState.failed.name,
  CursorKeys.keyFor(nodePath, CursorKeys.restartCount): restartCount.toString(),
  if (cooldownUntil != null)
    CursorKeys.keyFor(nodePath, CursorKeys.cooldownUntil): cooldownUntil
        .toIso8601String(),
};

/// The targeted metadata payload REWINDING ONE node (tg-o90 — routing, the dual
/// of fan-out): `state=pending` + the bumped [rewindCount] (the incarnation axis
/// — it RE-KEYS the node in `CircuitScope`, so a still-mounted effect is torn
/// down and re-run virgin) + `restartCount=0` (a fresh round gets a fresh
/// supervised-restart budget; and a stale `cooldownUntil` cannot block it — the
/// frontier's cooldown gate only applies to a `failed` node).
///
/// Merge-safe (disjoint per-node keys) exactly like every other cursor write,
/// and written through the ONE chokepoint onto the_grid's OWN session bead —
/// never the foreign work bead (A37). NO gate bead and NO session re-mint ride
/// along: those are `Gate` and the `grid rework` verb respectively.
Map<String, String> nodeRewoundMetadata(
  String nodePath, {
  required int rewindCount,
}) => {
  CursorKeys.keyFor(nodePath, CursorKeys.state): StepState.pending.name,
  CursorKeys.keyFor(nodePath, CursorKeys.rewindCount): rewindCount.toString(),
  CursorKeys.keyFor(nodePath, CursorKeys.restartCount): '0',
};

/// The targeted metadata payload REAPING one ZOMBIE node on ADOPTION:
/// `state=pending` (re-mount, virgin) + the bumped capture-only [reapCount].
///
/// A node a PRIOR station generation left at [StepState.running] whose recorded
/// process is DEAD is a STATION-DEATH SURVIVOR, **not a step failure** — the
/// process never got to report, because the station died with it. So the reap
/// simply RE-MOUNTS it, which is exactly what an operator's manual recovery
/// does (re-run the step; never fail the session).
///
/// **Deliberately does NOT touch `restartCount`** — the ONE place it diverges
/// from its sibling [nodeRewoundMetadata], which writes `restartCount=0`. A
/// REWIND opens a genuinely NEW round of work, bounded by its own `rewindCount`
/// belt, so a fresh round earns a fresh supervised-restart budget. A REAP opens
/// no new round: it resumes the SAME round after a station death, and has no
/// bounding counter that gates. Zeroing the budget here would ERASE the record
/// of the genuine crashes this round already suffered — a step that truly
/// crash-loops could evade the D-5 breaker forever by being bounced. So the reap
/// PRESERVES `restartCount` rather than resetting it, and never bumps it either
/// (charging the D-5 breaker for a bounce would make the operator's recovery
/// lever DESTRUCTIVE: with `maxRestarts: 3`, the third station bounce that
/// caught a long `agent` step mid-run would trip `isStepBroken`, and
/// `SessionScope` would escalate + CLOSE a session whose step never failed).
///
/// **No `rewindCount` either**, so the node's reconcile key
/// (`ValueKey('$path#$restartCount.$rewindCount')` — A47) is UNCHANGED. A re-key
/// exists to tear down a still-mounted effect; the reap runs at boot before the
/// kernel mounts anything, so there is nothing live to displace.
///
/// **No `cooldownUntil` either.** The frontier's cooldown gate applies ONLY to a
/// `failed` node, and a `pending` node mounts immediately — so a cooldown
/// written here would be dead metadata (and a stale one left over from an
/// earlier real failure is inert for the same reason).
///
/// **The stale `pgid`/`pid`/`token` are deliberately LEFT.** The chokepoint has
/// no key-delete affordance, and an empty-string stand-in would be its own small
/// lie. They are INERT on a `pending` node: the restart pass's live-group scan
/// only ever selects `running`/`ready`, the frontier ignores them, and the next
/// spawn overwrites all three via [nodeStartedMetadata]. The `state` field is the
/// node's sole liveness claim, and that is the field this write corrects.
///
/// Merge-safe (disjoint per-node keys) like every other cursor write, and
/// written through the ONE chokepoint onto the_grid's OWN session bead — never
/// the foreign work bead (A37).
Map<String, String> nodeReapedMetadata(
  String nodePath, {
  required int reapCount,
}) => {
  CursorKeys.keyFor(nodePath, CursorKeys.state): StepState.pending.name,
  CursorKeys.keyFor(nodePath, CursorKeys.reapCount): reapCount.toString(),
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
  if (pgid != null)
    CursorKeys.keyFor(nodePath, CursorKeys.pgid): pgid.toString(),
  CursorKeys.keyFor(nodePath, CursorKeys.pid): pid.toString(),
  CursorKeys.keyFor(nodePath, CursorKeys.token): token,
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

/// Projects every `grid.cursor.*` key on [sessionBead] into a [CircuitCursor],
/// keyed by `nodePath` (the read half of [nodeCursorMetadata]). A node's
/// `nodePath` is everything between the prefix and the final `.field` segment.
/// Non-cursor metadata is ignored; a malformed key (no field segment) is
/// skipped.
CircuitCursor projectCircuitCursor(Bead sessionBead) {
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
      // The routing rewind axis (tg-o90) — the second incarnation counter,
      // disjoint from the crash-restart budget above.
      rewindCount: _asInt(fields[CursorKeys.rewindCount]) ?? 0,
      // The ADOPTION-reap axis — the third incarnation counter (A47),
      // capture-only, disjoint from both counters above and absent from the key.
      reapCount: _asInt(fields[CursorKeys.reapCount]) ?? 0,
      cooldownUntil: _parseDate(fields[CursorKeys.cooldownUntil]),
      logOffset: _asInt(fields[CursorKeys.logOffset]),
      // Capture-only flow telemetry (FT-1) — surfaced typed for observers; never
      // read on a build/reconcile path.
      startedAt: _parseDate(fields[CursorKeys.startedAt]),
      finishedAt: _parseDate(fields[CursorKeys.finishedAt]),
      durationMs: _asInt(fields[CursorKeys.durationMs]),
      failureReason: fields[CursorKeys.failureReason]?.toString(),
    );
  });
  return cursor;
}

/// Projects every `grid.result.*` key on [sessionBead] into a per-node result
/// map (the read half of [nodeResultMetadata]). Mirrors [projectCircuitCursor]'s
/// key parsing: `grid.result.{nodePath}.{field}` → results[nodePath][field].
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

/// Projects a the_grid session [Bead] into the [SessionProjection] the tree
/// joins against. The session bead's OWN status is the terminal signal
/// (`closed` ⇒ terminal); the cursor + process identity come from metadata.
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
    // The per-node reentrant cursor (D-3) — threaded down to CircuitScope
    // pull-free (A39). Empty for a legacy/freshly-minted session with no
    // `grid.cursor.*` keys yet.
    cursor: projectCircuitCursor(sessionBead),
    // The per-node result payloads (D-5) — threaded down pull-free so a `route`
    // step reads its siblings' grades. Empty until a step records a result.
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
