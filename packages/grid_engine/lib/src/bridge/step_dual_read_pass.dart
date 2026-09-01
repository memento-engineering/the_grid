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

import 'package:meta/meta.dart';

import '../domain/session_head_read.dart';
import '../domain/session_projection.dart';
import '../domain/step_cursor_read.dart';
import '../domain/trajectory_views.dart';
import '../molecule/molecule_schema.dart' show MoleculeStepKeys;
import '../sdk/cursor.dart';
import 'dual_read_pass.dart' show DualReadFlareSink;

/// ONE session's step-axis overlay, as the pass hands it to the join.
///
/// Two halves because the consumers need both: [cursor] is the STATE the merge
/// serves, [views] is the collapsed P2 row behind each node — the
/// round/step-round/incarnation/supersedes ladder a consumer-site
/// `StepNodeComparison` reports. They are minted from the SAME rows in the
/// same pass, so a projection can never carry a cursor whose ladder came from
/// a different read.
@immutable
final class StepCursorOverlay {
  const StepCursorOverlay({required this.cursor, required this.views});

  final CircuitCursor cursor;
  final Map<String, StepCursorView> views;
}

/// Subscribes to the P2 mirror's published snapshots and returns the remover
/// (house convention) — the step axis's own re-join seam, spelled as a plain
/// function type for the same reason [HeadSnapshotSubscribe] is (the mirror is
/// explicitly not notifier state).
typedef StepSnapshotSubscribe =
    void Function() Function(
      void Function(TrajectoryStepSnapshot snapshot) listener,
    );

final class _StepCompareWindow {
  const _StepCompareWindow({
    required this.legacyState,
    required this.foldLastSeq,
  });

  final String? legacyState;
  final int? foldLastSeq;
}

/// Runs the step-axis comparator and owns everything it accumulates.
///
/// One instance per boot, held by the bridge. `observe` is called once per
/// join, after the session pass has spliced its overlays — so the step axis
/// compares against the projections a decision would actually read.
class DualReadStepObserver {
  DualReadStepObserver({
    // OFF BY DEFAULT (r13) — the session axis's twin rule.
    DualReadMode mode = DualReadMode.off,
    DateTime Function()? clock,
    DualReadFlareSink? onFlare,
    DualReadAccounting? accounting,
  }) : _mode = mode,
       _clock = clock ?? DateTime.now,
       _onFlare = onFlare,
       accounting = accounting ?? DualReadAccounting(clock: clock);

  final DualReadMode _mode;
  final DateTime Function() _clock;
  final DualReadFlareSink? _onFlare;

  /// The boot's counters — SHARED with the session pass when the composition
  /// hands both the same instance, which is the production wiring: one boot,
  /// one durable round summary, both axes.
  final DualReadAccounting accounting;

  final StepLagTracker _stepLag = StepLagTracker();
  final Map<String, _StepCompareWindow> _compareWindowByNode =
      <String, _StepCompareWindow>{};
  final Set<String> _operatorEditedNodes = <String>{};

  /// THE POSTURE, as a served fact: `primary` AND the boot has not disengaged.
  /// The disengage latch lives on the shared accounting, so a boot whose P1
  /// mirror missed an append stops serving the step axis too — one mirror's
  /// health is one station's health.
  bool get stepAxisEngaged =>
      _mode == DualReadMode.primary && !accounting.overlayDisengaged;

  /// Is the comparator ARMED at all? False under [DualReadMode.off] — the
  /// rollback posture, where the pass does not run and the bridge does not
  /// even subscribe to the P2 mirror. See [DualReadMode.off].
  bool get armed => _mode != DualReadMode.off;

  SessionProjection _winningLegacyRoundOf(
    SessionProjection legacy,
    String sessionId,
  ) {
    if (!legacy.isMolecule) return legacy;
    return legacy.copyWith(
      moleculeBeads: [
        for (final bead in legacy.moleculeBeads)
          if (bead.metadata[MoleculeStepKeys.session] == sessionId) bead,
      ],
    );
  }

  /// ONE comparator pass over [sessions] against [snapshot].
  ///
  /// Returns the step overlay entries the join should splice, keyed by the
  /// sessions map's own key — empty under `off` and `observe`, empty while the
  /// boot is disengaged, and empty when the snapshot is not `live`.
  Map<String, StepCursorOverlay> observe(
    Map<String, SessionProjection> sessions,
    TrajectoryStepSnapshot snapshot,
  ) {
    // THE ROLLBACK POSTURE: `off` runs no pass at all — see the session pass's
    // twin guard and [DualReadMode.off].
    if (!armed) return const <String, StepCursorOverlay>{};
    accounting.beginStepPass();
    if (snapshot.health != TrajectorySnapshotHealth.live) {
      // Health non-`live` DISENGAGES the axis for the boot, exactly as on the
      // session axis: every session rides its own bead cursor — still fully
      // written, still authoritative — and every read counts as a fallback.
      // No flares: the compromise already flared once, at the latch.
      accounting.overlayDisengaged = true;
      accounting.stepFallbacks += sessions.length;
      _stepLag.retainOnly(const <String>{});
      _compareWindowByNode.clear();
      _operatorEditedNodes.clear();
      return const <String, StepCursorOverlay>{};
    }
    final engaged = stepAxisEngaged;
    final now = _clock();
    final lagging = <String>{};
    final comparedNodes = <String>{};
    final cursors = <String, StepCursorOverlay>{};

    for (final entry in sessions.entries) {
      final legacy = entry.value;
      final sessionId = legacy.sessionId;
      if (sessionId == null || sessionId.isEmpty) continue;
      if (isRetiredWorkBeadKey(legacy.workBeadId)) continue;
      // A terminal session has nothing left to mount and no cursor a decision
      // reads; comparing it would count its whole node set as lag forever
      // after the last transition record folded.
      if (legacy.isTerminal) continue;
      // THE OVERLAY IDENTITY RULE, step axis (r6 — J10-B2/J11-B2): the
      // same-session lookup, never a `byWorkBead` winner. A session with no
      // same-session rows takes the P2-miss rule per node — the LEGACY BEAD —
      // and never a sibling's rows.
      final rows = snapshot.byP2SessionId(sessionId).toList(growable: false);
      final beadCursor = legacyStepCursorOf(
        _winningLegacyRoundOf(legacy, sessionId),
      );
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
        _observeCompareWindow(node, collapsed[node.stepPath], comparedNodes);
        _recordNode(node, snapshot, now: now, lagging: lagging);
      }
      if (engaged) {
        // What the JOIN splices is P2's OWN cursor, not the merge's output:
        // the merge rules belong to the consumer's `effectiveStepCursor`, so
        // there is exactly one implementation of them and a projection never
        // carries a pre-merged value some other site would merge again. The
        // COLLAPSED rows ride along unchanged — same rows, same pass — so the
        // consumer's own merge reports the same ladder this one did.
        cursors[entry.key] = StepCursorOverlay(
          cursor: trajCursorOf(rows),
          views: collapsed,
        );
        accounting.stepCursorsServed += 1;
      }
    }

    _stepLag.retainOnly(lagging);
    _compareWindowByNode.removeWhere((key, _) => !comparedNodes.contains(key));
    _operatorEditedNodes.retainAll(comparedNodes);
    return cursors;
  }

  void _observeCompareWindow(
    StepNodeComparison node,
    StepCursorView? row,
    Set<String> comparedNodes,
  ) {
    final key = StepLagTracker.keyFor(node.sessionId, node.stepPath);
    comparedNodes.add(key);
    final current = _StepCompareWindow(
      legacyState: node.legacyState,
      foldLastSeq: row?.lastSeq,
    );
    final previous = _compareWindowByNode[key];
    if (previous != null) {
      if (current.foldLastSeq != previous.foldLastSeq) {
        _operatorEditedNodes.remove(key);
      } else if (current.legacyState != previous.legacyState) {
        _operatorEditedNodes.add(key);
      }
    }
    _compareWindowByNode[key] = current;
  }

  DualReadDivergenceCause _causeFor(StepNodeComparison node) =>
      _operatorEditedNodes.contains(
        StepLagTracker.keyFor(node.sessionId, node.stepPath),
      )
      ? DualReadDivergenceCause.operatorStoreEdit
      : DualReadDivergenceCause.unexplained;

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
        final cause = _causeFor(node);
        if (accounting.recordStepDivergence(
          sessionId: node.sessionId,
          stepPath: node.stepPath,
          field: 'state',
          legacyValue: node.legacyState ?? '<no step bead>',
          foldValue: node.foldState ?? '<no P2 row>',
          cause: cause,
        )) {
          _flareStepDivergence(node, snapshot, field: 'state', cause: cause);
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
    final cause = _causeFor(node);
    if (accounting.recordStepDivergence(
      sessionId: node.sessionId,
      stepPath: node.stepPath,
      field: 'stepLag',
      legacyValue: node.legacyState ?? '<no step bead>',
      foldValue: node.foldState ?? '<no P2 row>',
      cause: cause,
    )) {
      _flareStepDivergence(node, snapshot, field: 'stepLag', cause: cause);
    }
  }

  void _flareStepDivergence(
    StepNodeComparison node,
    TrajectoryStepSnapshot snapshot, {
    required String field,
    required DualReadDivergenceCause cause,
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
        'cause': cause.wire,
      });
    } on Object {
      // Emit-only, the flare convention.
    }
  }
}
