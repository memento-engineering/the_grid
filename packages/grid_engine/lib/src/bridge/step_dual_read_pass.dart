/// THE COMPARATOR PASS, step axis (cut-wiring C4) — the stateful half of the
/// step dual read.
///
/// `step_cursor_read.dart` holds the pure functions; this file runs them over
/// one JOIN's sessions map, keeps the step half of the boot's accounting, owns
/// the `stepLag` tracker, and emits — emit-only, never blocking — the
/// axis-tagged divergence flares.
///
/// It is the session pass's twin in every structural respect, deliberately:
/// it is handed into `_join` as a bookkeeper rather than being part of the
/// join's value, it never mutates the sessions map (it RETURNS the
/// `trajCursor` entries and the join splices them, so the map keeps exactly
/// one writer), and it shares the ONE per-boot [DualReadAccounting] so a round
/// summary reports one truth for both axes.
///
/// Under `observe` the returned map is always empty and the pass is pure
/// accounting — which is what makes the observe window a forecast of the flip
/// rather than a different code path.
library;

import '../domain/session_head_read.dart';
import '../domain/session_projection.dart';
import '../domain/step_cursor_read.dart';
import '../domain/trajectory_views.dart';
import '../sdk/cursor.dart';
import 'dual_read_pass.dart' show DualReadFlareSink;

/// Subscribes to the P2 mirror's published snapshots and returns the remover
/// (house convention) — the step axis's own re-join seam, spelled as a plain
/// function type for the same reason [HeadSnapshotSubscribe] is (the mirror is
/// explicitly not notifier state).
typedef StepSnapshotSubscribe =
    void Function() Function(
      void Function(TrajectoryStepSnapshot snapshot) listener,
    );

/// Runs the step-axis comparator and owns everything it accumulates.
///
/// One instance per boot, held by the bridge. `observe` is called once per
/// join, after the session pass has spliced its overlays — so the step axis
/// compares against the projections a decision would actually read.
class DualReadStepObserver {
  DualReadStepObserver({
    DualReadMode mode = DualReadMode.observe,
    DateTime Function()? clock,
    DualReadFlareSink? onFlare,
    DualReadAccounting? accounting,
  }) : _mode = mode,
       _clock = clock ?? DateTime.now,
       _onFlare = onFlare,
       accounting = accounting ?? DualReadAccounting();

  final DualReadMode _mode;
  final DateTime Function() _clock;
  final DualReadFlareSink? _onFlare;

  /// The boot's counters — SHARED with the session pass when the composition
  /// hands both the same instance, which is the production wiring: one boot,
  /// one durable round summary, both axes.
  final DualReadAccounting accounting;

  final StepLagTracker _stepLag = StepLagTracker();

  /// THE POSTURE, as a served fact: `primary` AND the boot has not disengaged.
  /// The disengage latch lives on the shared accounting, so a boot whose P1
  /// mirror missed an append stops serving the step axis too — one mirror's
  /// health is one station's health.
  bool get stepAxisEngaged =>
      _mode == DualReadMode.primary && !accounting.overlayDisengaged;

  /// ONE comparator pass over [sessions] against [snapshot].
  ///
  /// Returns the `trajCursor` entries the join should splice, keyed by the
  /// sessions map's own key — empty under `observe`, empty while the boot is
  /// disengaged, and empty when the snapshot is not `live`.
  Map<String, CircuitCursor> observe(
    Map<String, SessionProjection> sessions,
    TrajectoryStepSnapshot snapshot,
  ) {
    accounting.beginStepPass();
    if (snapshot.health != TrajectorySnapshotHealth.live) {
      // Health non-`live` DISENGAGES the axis for the boot, exactly as on the
      // session axis: every session rides its own bead cursor — still fully
      // written, still authoritative — and every read counts as a fallback.
      // No flares: the compromise already flared once, at the latch.
      accounting.overlayDisengaged = true;
      accounting.stepFallbacks += sessions.length;
      _stepLag.retainOnly(const <String>{});
      return const <String, CircuitCursor>{};
    }
    final engaged = stepAxisEngaged;
    final now = _clock();
    final lagging = <String>{};
    final cursors = <String, CircuitCursor>{};

    for (final entry in sessions.entries) {
      final legacy = entry.value;
      final sessionId = legacy.sessionId;
      if (sessionId == null || sessionId.isEmpty) continue;
      // A terminal session has nothing left to mount and no cursor a decision
      // reads; comparing it would count its whole node set as lag forever
      // after the last transition record folded.
      if (legacy.isTerminal) continue;
      // THE OVERLAY IDENTITY RULE, step axis (r6 — J10-B2/J11-B2): the
      // same-session lookup, never a `byWorkBead` winner. A session with no
      // same-session rows takes the P2-miss rule per node — the LEGACY BEAD —
      // and never a sibling's rows.
      final rows = snapshot.byP2SessionId(sessionId).toList(growable: false);
      final beadCursor = legacyStepCursorOf(legacy);
      if (rows.isEmpty) {
        // No P2 at all for this session: every node is a miss, which is the
        // per-node rule applied wholesale. Counted, never a divergence, and
        // the cursor stays the bead's.
        accounting.stepFallbacks += 1;
        accounting.p2Miss += beadCursor.length;
        continue;
      }
      accounting.stepHits += 1;
      final collapsed = collapseStepCursors(rows);
      final merge = mergeStepCursor(
        sessionId: sessionId,
        legacy: beadCursor,
        traj: trajCursorOf(rows),
        collapsed: collapsed,
      );
      for (final node in merge.nodes) {
        _recordNode(node, snapshot, now: now, lagging: lagging);
      }
      if (engaged) {
        // What the JOIN splices is P2's OWN cursor, not the merge's output:
        // the merge rules belong to the consumer's `effectiveStepCursor`, so
        // there is exactly one implementation of them and a projection never
        // carries a pre-merged value some other site would merge again.
        cursors[entry.key] = trajCursorOf(rows);
        accounting.stepCursorsServed += 1;
      }
    }

    _stepLag.retainOnly(lagging);
    return cursors;
  }

  void _recordNode(
    StepNodeComparison node,
    TrajectoryStepSnapshot snapshot, {
    required DateTime now,
    required Set<String> lagging,
  }) {
    switch (node.classification) {
      case StepNodeClass.match:
        return;
      case StepNodeClass.p2Miss:
        accounting.p2Miss += 1;
        // A miss is ALSO the lag pair's shape (§C4: "bead row present / P2 row
        // absent" counts `stepLag`), so it rides the same tracker and earns
        // the same escalation — a node whose transition append was dropped is
        // exactly what that escalation is for.
        _observeLag(node, snapshot, now: now, lagging: lagging);
      case StepNodeClass.stepLag:
        _observeLag(node, snapshot, now: now, lagging: lagging);
      case StepNodeClass.p2Orphan:
        // Structurally inert for decisions — the overlay never creates on this
        // axis either — but counted, like a `p1Orphan` head.
        accounting.p2Orphan += 1;
      case StepNodeClass.divergence:
        _flareStepDivergence(node, snapshot, field: 'state');
        if (accounting.noteEvent(
          'stepDivergence:${node.sessionId}:${node.stepPath}',
        )) {
          accounting.stepDivergences += 1;
        }
    }
  }

  void _observeLag(
    StepNodeComparison node,
    TrajectoryStepSnapshot snapshot, {
    required DateTime now,
    required Set<String> lagging,
  }) {
    final key = StepLagTracker.keyFor(node.sessionId, node.stepPath);
    lagging.add(key);
    accounting.openStepLag += 1;
    final escalates = _stepLag.observe(node.sessionId, node.stepPath, now: now);
    final age = _stepLag.ageOf(node.sessionId, node.stepPath, now);
    if (age.inMilliseconds > accounting.maxStepLagMs) {
      accounting.maxStepLagMs = age.inMilliseconds;
    }
    if (accounting.noteEvent('stepLag:$key')) accounting.stepLagObserved += 1;
    if (!escalates) return;
    // PAST THE GRACE ACROSS TWO PASSES: this is no longer the bead-first
    // window, it is a transition append that never landed. It becomes a
    // divergence and is counted as one.
    accounting.stepLagEscalations += 1;
    if (accounting.noteEvent(
      'stepDivergence:${node.sessionId}:${node.stepPath}',
    )) {
      accounting.stepDivergences += 1;
    }
    _flareStepDivergence(node, snapshot, field: 'stepLag');
  }

  void _flareStepDivergence(
    StepNodeComparison node,
    TrajectoryStepSnapshot snapshot, {
    required String field,
  }) {
    final sink = _onFlare;
    if (sink == null) return;
    try {
      sink(kDualReadDivergenceFlare, {
        'axis': 'step',
        'session_id': node.sessionId,
        'step_path': node.stepPath,
        'field': field,
        'fold_value': node.foldState ?? '<no P2 row>',
        'legacy_value': node.legacyState ?? '<no step bead>',
        if (node.stepRound != null) 'step_round': '${node.stepRound}',
        if (node.round != null) 'round': '${node.round}',
        'snapshot_version': '${snapshot.version}',
        if (field == 'stepLag')
          'probable_cause': 'a dropped step.transition append',
      });
    } on Object {
      // Emit-only, the flare convention.
    }
  }
}
