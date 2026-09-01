/// THE DUAL READ, step axis — the pure half (cut-wiring §C4).
///
/// The session axis's `session_head_read.dart`, one ladder down. Everything
/// here is a total function over values the caller already holds: the LEGACY
/// cursor a consumer recomputes from its own step beads, and the pre-fetched
/// P2 rows the harness mirrored out of `proj_step_cursor`. Nothing awaits,
/// nothing reads a store, nothing writes one.
///
/// **The step axis is the session axis's exact analogue**, because the tree
/// writes the step BEAD first and enqueues the transition record after,
/// fire-and-forget, at every persist site — `_persistReady`,
/// `_persistComplete`, `_persistFailureClassed` — and the join recomputes ON
/// that bd write. So at every transition the compare sees legacy AHEAD of P2
/// by construction, and C3's three protections come across verbatim-adapted
/// (r5 — J8-B2):
///
///   * **MONOTONE NO-DEMOTION ON CURSOR STATE** — a bead-terminal step state
///     (`complete`/`ready`, and a bead `failed` with its restart bookkeeping)
///     is never overridden by an older or absent P2 state. A P2 value that
///     would demote a bead-carried step state is a lag signal, never served.
///   * **THE P2-MISS RULE, PER NODE** — a node with NO P2 row (the GUARANTEED
///     state of every step for the whole append round-trip after it
///     transitions) reads the LEGACY BEAD for that node and bumps `p2Miss`:
///     never a default, never an OMISSION from the effective cursor. An
///     omitted node reads as unclaimed at the frontier and at the mount
///     scope, and would be re-claimed and re-mounted — a double-run, the
///     exact I-10 class.
///   * **`stepLag`** — the step axis's named lag class, excluded from the
///     `divergence` count, required zero at round end, escalating to
///     `dualReadDivergence{axis:'step'}` past the grace.
///
/// And one rule the session axis states for BOTH axes (r6 — J10-B2/J11-B2):
/// **THE OVERLAY IDENTITY RULE** applies to the step axis VERBATIM. P2 facts
/// merge onto a session projection only when the rows' `session_id` equals
/// that projection's own; the `byWorkBead` winner NEVER feeds `trajCursor`. A
/// cross-session splice is a PROMOTION the monotone rule cannot catch, which
/// is why identity — not monotonicity — is the guard there.
library;

import 'package:meta/meta.dart';

import '../molecule/molecule_codec.dart' show projectMoleculeCursor;
import '../sdk/circuit.dart';
import '../sdk/cursor.dart';
import 'session_projection.dart';
import 'trajectory_views.dart';

/// The grace a `stepLag` entry gets before it escalates to a divergence.
///
/// **90 s, not the C4 text's 60 s** — C4 itself defines the class as
/// "`terminalLag`'s arithmetic, step-shaped (§0.3 gate arithmetic)", and r8
/// (V2-B2) collapsed every lag grace onto §0.3's ONE escalation arithmetic:
/// three tick intervals, an order of magnitude past the post-ACK apply
/// window, across at least two comparator passes. The step axis has no heal
/// (none is specified for it — a transition record has no `terminal-reconcile`
/// twin), so the grace expiring IS the escalation rather than the trigger for
/// a repair.
const Duration kStepLagGrace = Duration(seconds: 90);

/// What the step comparator resolved for ONE node.
enum StepNodeClass {
  /// The bead state and the collapsed P2 state agree.
  match,

  /// No P2 row for a node the BEAD carries — the guaranteed state of every
  /// step for the whole append round-trip. The legacy bead is read for that
  /// node (never a default, never an omission) and `p2Miss` is bumped.
  p2Miss,

  /// P2 would DEMOTE the bead-carried state — the bead-first/append-later
  /// window. The bead is served and `stepLag` is counted.
  stepLag,

  /// P2 claims a state the bead does not, in a direction that is not a
  /// demotion. Under the bead-first invariant P2 can only be BEHIND, so this
  /// is the genuine fold-vs-ledger disagreement the gates count.
  divergence,

  /// A P2 row for a node path the legacy session does not carry. The overlay
  /// NEVER CREATES on the step axis either: the node is dropped from the
  /// effective cursor and counted, exactly like a `p1Orphan` head.
  p2Orphan,
}

/// One node's compared pair, rendered for the flare payload and the summary.
@immutable
final class StepNodeComparison {
  const StepNodeComparison({
    required this.sessionId,
    required this.stepPath,
    required this.classification,
    this.foldState,
    this.legacyState,
    this.round,
    this.stepRound,
    this.incarnation,
    this.supersededByStepRound,
  });

  final String sessionId;
  final String stepPath;
  final StepNodeClass classification;

  /// The collapsed P2 state's wire word — null when there is no P2 row.
  final String? foldState;

  /// The bead-carried state's wire word — null for a [StepNodeClass.p2Orphan].
  final String? legacyState;

  /// P2's own ladder columns. They have NO `NodeCursor` home — the in-memory
  /// cursor carries neither a round nor a step_round nor a supersedes link —
  /// so C4's "stepRound, incarnation, supersededByStepRound from P2" lands
  /// HERE, as compare-only telemetry on the same footing as the session
  /// axis's pgid/pid presence pair. `incarnation` in particular must NOT be
  /// served: its `NodeCursor` analogue is `restartCount`, which is the
  /// breaker's input and stays bead-read for all of wave 1 (B-M2).
  final int? round;
  final int? stepRound;
  final int? incarnation;
  final int? supersededByStepRound;

  bool get isDivergence => classification == StepNodeClass.divergence;

  @override
  String toString() =>
      'StepNodeComparison($sessionId/$stepPath: ${classification.name}, '
      'fold=$foldState, legacy=$legacyState)';
}

/// THE COLLAPSE RULE (r7 — V1-M5): one P2 row per `step_path`.
///
/// P2's PK is the TWO-LADDER key `(session_id, round, step_path, step_round)`,
/// so one node path holds a row per rework round AND per gate-cleared rearm.
/// The newest incarnation is the row with the lexicographically greatest
/// `(round, step_round)` — the supersedes ladder's OWN ordering, which is why
/// this is a collapse and not a heuristic: `superseded_by_step_round` is
/// written on the PREDECESSOR by every bump, so the greatest pair is exactly
/// the row nothing supersedes.
///
/// [rows] must already be identity-filtered to ONE session (the
/// `byP2SessionId` lookup) — the collapse does not read `session_id` and will
/// happily collapse a cross-session mixture, which is precisely the splice the
/// OVERLAY IDENTITY RULE forbids.
Map<String, StepCursorView> collapseStepCursors(Iterable<StepCursorView> rows) {
  final newest = <String, StepCursorView>{};
  for (final row in rows) {
    final incumbent = newest[row.stepPath];
    if (incumbent == null || _laddersAfter(row, incumbent)) {
      newest[row.stepPath] = row;
    }
  }
  return newest;
}

/// Is [candidate] later on the two-ladder than [incumbent]? `round` first,
/// then `step_round` — the ladder's own precedence.
bool _laddersAfter(StepCursorView candidate, StepCursorView incumbent) {
  if (candidate.round != incumbent.round) {
    return candidate.round > incumbent.round;
  }
  return candidate.stepRound > incumbent.stepRound;
}

/// The engine's [StepState] for a P2 `state` wire word, or null when the
/// column carries something this engine has no state for.
///
/// The two vocabularies are the same six names by design (the record enum and
/// the cursor enum were authored against one DDL), so a null here is a schema
/// drift signal rather than an expected shape — and it is treated as a MISS,
/// never as a default, so drift can never silently demote a node.
StepState? stepStateFromWire(String wire) {
  for (final state in StepState.values) {
    if (state.name == wire) return state;
  }
  return null;
}

/// P2's own cursor for one session — the collapsed rows as [NodeCursor]s.
///
/// STATE ONLY. Every other `NodeCursor` field stays at its default here and is
/// never read: the merge takes them from the bead, because
/// `restartCount`/`cooldownUntil`/`pgid`/`pid`/`token` stay bead-read for all
/// of wave 1 (B-M2 — the breaker's read never moves). This map is what the
/// bridge fills [SessionProjection.trajCursor] with: P2's facts, unmerged, so
/// the merge rules live in exactly one place ([effectiveStepCursor]) rather
/// than being pre-applied by whoever happened to fill the field.
CircuitCursor trajCursorOf(Iterable<StepCursorView> sessionRows) {
  final cursor = <String, NodeCursor>{};
  collapseStepCursors(sessionRows).forEach((stepPath, row) {
    final state = stepStateFromWire(row.stepState);
    if (state == null) return;
    cursor[stepPath] = NodeCursor(state: state);
  });
  return cursor;
}

/// The BEAD-CARRIED cursor for [session] — the legacy truth on the step axis.
///
/// A molecule session's cursor exists ONLY as `projectMoleculeCursor`'s
/// recompute over its own `type=step` beads: `projectSession` deliberately
/// leaves [SessionProjection.cursor] empty (tg-eli phase 2) and the join never
/// attaches it. A non-molecule (historical flat) session has no step beads at
/// all, so its projection's own cursor field is the honest read — empty in
/// production, populated only in synthetic projections.
CircuitCursor legacyStepCursorOf(SessionProjection session) =>
    session.isMolecule
    ? projectMoleculeCursor(
        session.moleculeBeads,
        dependencies: session.moleculeDependencies,
      ).cursor
    : session.cursor;

/// MONOTONE NO-DEMOTION's predicate (§C4, adapted from F-B4 verbatim).
///
/// A bead-terminal step state is never overridden by a DIFFERENT P2 state:
/// `complete` and `ready` are the positive terminals a `dependsOn` reads, and
/// `failed` carries the supervised-restart bookkeeping the breaker spends —
/// the three share a rank, so they are alternatives at one depth rather than a
/// ladder, and a swap between them is refused like any demotion. For the
/// non-terminal states the ordering is the lifecycle's own: a P2 value EARLIER
/// on it is the append-in-flight window, never a decision.
bool demotesStepState(StepState bead, StepState fold) =>
    bead != fold && _stepProgress(fold) <= _stepProgress(bead);

/// The step axis's OWN hazard, which the monotone rule alone cannot catch: a
/// P2 state that looks like a PROMOTION but is a prior incarnation's row.
///
/// A bead sitting at `pending` was put there by a gate-cleared REARM or a
/// rewind — the only two writers of that transition — and both BUMP the
/// two-ladder. So while the rearm's own `step.transition` is still in flight,
/// the collapse's newest row is the PREVIOUS rung, whose state (`gated`,
/// `complete`, …) sits above `pending` on the ordering and would read as a
/// promotion. Serving it re-parks a node the ledger just re-armed: the I-14
/// stale-join loop, re-created by the very read meant to retire it.
bool staleRungPromotion(StepState bead, StepState fold) =>
    bead == StepState.pending && fold != StepState.pending;

/// The merge's rule in ONE predicate: P2's state is served only when it
/// neither demotes the bead nor promotes off a stale rung.
///
/// Note what this implies, and it is the same honest reading C3 wrote for the
/// session axis: every step persist site writes the BEAD first and appends
/// after, so P2 can never legitimately be ahead — which means a healthy round
/// under `primary` serves the bead's state at every node, and this predicate
/// returning true is itself the definition of a step-axis divergence. What the
/// flip buys is a CERTIFIED CARRIER for wave 2, not different decisions.
bool servesFoldStepState(StepState bead, StepState fold) =>
    !demotesStepState(bead, fold) && !staleRungPromotion(bead, fold);

/// The step lifecycle's progress ordering — pending → running → gated →
/// terminal. `gated` sits above `running` because a node reaches its gate by
/// running into it, and the three terminals share a rank because they are
/// alternatives at the same depth, not a ladder.
int _stepProgress(StepState state) => switch (state) {
  StepState.pending => 0,
  StepState.running => 1,
  StepState.gated => 2,
  StepState.failed || StepState.ready || StepState.complete => 3,
};

/// The result of merging P2 over one session's bead-carried cursor.
@immutable
final class StepCursorMerge {
  const StepCursorMerge({required this.cursor, required this.nodes});

  /// The EFFECTIVE cursor a consumer reads. Its node SET is the bead's,
  /// always: the P2-miss rule keeps a P2-less node, and the never-creates rule
  /// drops a bead-less P2 row.
  final CircuitCursor cursor;

  /// One entry per compared node, in bead order then orphan order.
  final List<StepNodeComparison> nodes;

  /// True when the merge changed a state — under `primary` the entries the
  /// station actually decided differently on.
  bool get changed =>
      nodes.any((node) => node.classification == StepNodeClass.divergence);
}

/// THE MERGE — P2 over the bead-carried cursor for ONE session, with the three
/// step-axis protections applied per node.
///
/// [legacy] is the bead-carried cursor ([legacyStepCursorOf] at every
/// in-tree site). [traj] is that session's OWN P2 cursor ([trajCursorOf] over
/// the `byP2SessionId` rows) — a null [traj] is "the step axis is not
/// engaged", and the merge is then the identity on [legacy] with no
/// comparisons at all.
StepCursorMerge mergeStepCursor({
  required String sessionId,
  required CircuitCursor legacy,
  required CircuitCursor? traj,
  Map<String, StepCursorView> collapsed = const <String, StepCursorView>{},
}) {
  if (traj == null) {
    return StepCursorMerge(cursor: legacy, nodes: const <StepNodeComparison>[]);
  }
  final merged = <String, NodeCursor>{};
  final nodes = <StepNodeComparison>[];
  legacy.forEach((stepPath, beadNode) {
    final row = collapsed[stepPath];
    final foldNode = traj[stepPath];
    if (foldNode == null) {
      // THE P2-MISS RULE: the legacy bead, kept in the cursor. Never a
      // default, never an omission — an omitted node reads as unclaimed and is
      // re-mounted (I-10).
      merged[stepPath] = beadNode;
      nodes.add(
        StepNodeComparison(
          sessionId: sessionId,
          stepPath: stepPath,
          classification: StepNodeClass.p2Miss,
          legacyState: beadNode.state.name,
        ),
      );
      return;
    }
    final comparison = StepNodeComparison(
      sessionId: sessionId,
      stepPath: stepPath,
      classification: foldNode.state == beadNode.state
          ? StepNodeClass.match
          : servesFoldStepState(beadNode.state, foldNode.state)
          ? StepNodeClass.divergence
          : StepNodeClass.stepLag,
      foldState: foldNode.state.name,
      legacyState: beadNode.state.name,
      round: row?.round,
      stepRound: row?.stepRound,
      incarnation: row?.incarnation,
      supersededByStepRound: row?.supersededByStepRound,
    );
    nodes.add(comparison);
    // The STATE is the only field P2 serves: everything else on the node —
    // restartCount, cooldownUntil, the fence identity triple — is bead-read
    // for all of wave 1, so the served node is the BEAD's with P2's state
    // spliced, never a node built out of P2. A refused state serves the bead
    // whole (`stepLag`), which is also what makes the node set stable: the
    // same key is present either way.
    merged[stepPath] = servesFoldStepState(beadNode.state, foldNode.state)
        ? beadNode.copyWith(state: foldNode.state)
        : beadNode;
  });
  // THE OVERLAY NEVER CREATES, step axis: a P2 node the ledger does not carry
  // is counted and dropped. Mounting one would be the mirror image of the
  // session axis's "a P1 row with no legacy counterpart never becomes a
  // sessions-map entry".
  traj.forEach((stepPath, foldNode) {
    if (legacy.containsKey(stepPath)) return;
    nodes.add(
      StepNodeComparison(
        sessionId: sessionId,
        stepPath: stepPath,
        classification: StepNodeClass.p2Orphan,
        foldState: foldNode.state.name,
        round: collapsed[stepPath]?.round,
        stepRound: collapsed[stepPath]?.stepRound,
      ),
    );
  });
  return StepCursorMerge(cursor: merged, nodes: nodes);
}

/// THE SHARED HELPER the cursor consumers adopt (§C4's
/// `effectiveCursor(session, stepBeads)`).
///
/// **Renamed off the design's `effectiveCursor`**: that name is already taken
/// in this package by R4's supersedes-generation collapse
/// (`live_frontier.dart`), which `SessionScope` calls two lines from where
/// this one lands. Two different functions under one name in one file would be
/// a genuine hazard, so the step-axis helper carries the axis in its name.
///
/// [siteCursor] is what the calling site reads TODAY, returned UNCHANGED
/// whenever the step axis is not engaged. That parameter is how "config off =
/// today" is PINNED per site (the r4 OPEN CARRY, J6-M1/J7-M5): the frontier
/// and the cooldown scan iterate the structurally-empty
/// `SessionProjection.cursor`, so adoption there is a behavior CHANGE and not
/// a pure read swap — and the non-engaged branch has to return the empty field
/// rather than a recompute, or the rollback claim would be false.
///
/// [beadCursor] is the bead-carried truth used as the P2-miss fallback and the
/// monotone floor; it defaults to [legacyStepCursorOf] and is passed
/// explicitly by the sites that already computed it (never recomputed twice).
///
/// ENGAGEMENT IS STRUCTURAL: the axis is engaged for a session exactly when
/// the bridge filled [SessionProjection.trajCursor], and the bridge fills it
/// only under `primary` + snapshot health `live` + a boot that has not
/// disengaged. So no consumer reads a config, and under `observe` every one of
/// them is byte-identical to today by construction.
CircuitCursor effectiveStepCursor(
  SessionProjection session, {
  required CircuitCursor siteCursor,
  CircuitCursor? beadCursor,
}) {
  final traj = session.trajCursor;
  if (traj == null) return siteCursor;
  return mergeStepCursor(
    sessionId: session.sessionId ?? '',
    legacy: beadCursor ?? legacyStepCursorOf(session),
    traj: traj,
  ).cursor;
}

/// THE STEP-LAG TRACKER — `stepLag`'s escalation arithmetic, step-shaped.
///
/// Tracks each lagging `(session, node)` across comparator passes and answers
/// one question per pass: has this entry earned its divergence? The rule is
/// [kStepLagGrace] across at least TWO passes, so a normal transition's
/// transit through the bead-first/append-later window can never trigger
/// anything — the same shape `TerminalLagTracker` has on the session axis,
/// minus the heal (the step axis has none).
///
/// It owns no clock: the caller supplies `now`, which is a fact about the
/// world a pure tracker cannot have.
class StepLagTracker {
  StepLagTracker({this.grace = kStepLagGrace});

  final Duration grace;
  final Map<String, _StepLagEntry> _entries = <String, _StepLagEntry>{};

  /// The nodes currently lagging.
  int get openEntries => _entries.length;

  /// The tracker's key for one node — session id and step path, because the
  /// same path under two sessions is two independent lags.
  static String keyFor(String sessionId, String stepPath) =>
      '$sessionId $stepPath';

  /// Observes one lagging node at [now]; returns true exactly ONCE, on the
  /// pass where the entry earns its escalation.
  bool observe(String sessionId, String stepPath, {required DateTime now}) {
    final key = keyFor(sessionId, stepPath);
    final entry = _entries.putIfAbsent(key, () => _StepLagEntry(now));
    entry.passes += 1;
    if (entry.escalated) return false;
    if (entry.passes < 2) return false;
    if (now.difference(entry.firstSeenAt) < grace) return false;
    entry.escalated = true;
    return true;
  }

  /// The age of one node's lag at [now] — zero for a node not tracked.
  Duration ageOf(String sessionId, String stepPath, DateTime now) {
    final entry = _entries[keyFor(sessionId, stepPath)];
    return entry == null ? Duration.zero : now.difference(entry.firstSeenAt);
  }

  /// Drops every entry not observed in the pass that just ran — a node that
  /// stopped lagging healed on its own, which is what the window does.
  void retainOnly(Set<String> seen) =>
      _entries.removeWhere((key, _) => !seen.contains(key));
}

class _StepLagEntry {
  _StepLagEntry(this.firstSeenAt);

  final DateTime firstSeenAt;
  int passes = 0;
  bool escalated = false;
}
