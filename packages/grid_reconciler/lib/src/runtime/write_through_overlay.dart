import 'package:grid_controller/grid_controller.dart';

import '../convergence/convergence_metadata.dart';
import '../convergence/reconciler_action.dart';
import '../projections/convergence.dart';

/// The per-bead write-through metadata overlay — the FIRST line of defense
/// against the duplicate-pour race (ADR-0000 A17, load-bearing).
///
/// **The race.** The grid reads convergence state from a [GraphSnapshot] that
/// the controller re-captures only after a Dolt dirty signal (the `@@tg_working`
/// probe, ~1s, ADR-0000 A21). An actuation — a `bd update --metadata`, a close,
/// a pour — routinely completes in milliseconds, far ahead of the next
/// snapshot. So a second event for the same bead (a re-delivered `triggerPassed`,
/// a fast gate completion, a closure that beats the watcher) reducing over the
/// **raw** snapshot sees PRE-actuation state: `last_processed_wisp` not yet
/// advanced, `gate_outcome_wisp` not yet stamped, `pending_next_wisp` not yet
/// recorded — and re-fires a transition gc would have deduped (handler.go:177-201
/// monotonic dedup; :233-234 the gate-replay marker), pouring a duplicate wisp
/// that permanently inflates `deriveIterationCount` (invariant 4).
///
/// gc has no such gap: it is single-writer on one event loop and **re-reads
/// fresh store metadata at every handler entry** (handler.go:162-168,
/// trigger.go:52-56, manual.go:125-130). The overlay reconstructs that "read
/// post-actuation state" property: every metadata write the actuator performs is
/// recorded here and **layered over** the snapshot's metadata before the next
/// reduce for that bead, so the reducer's own dedup/replay guards fire exactly as
/// gc's would. The live actuator probe (ADR-0000 A26 `findWispByIdempotencyKey`)
/// is the SECOND line of defense; this overlay is the first.
///
/// **Lifecycle.** Writes accumulate per bead and are layered on every
/// projection until a fresh snapshot is observed whose capture supersedes them.
/// Because the grid cannot cheaply know which writes a given snapshot already
/// reflects, the overlay is conservative: it keeps writes until
/// [reconcileWithSnapshot] confirms the snapshot AGREES with each overlaid key
/// (the snapshot caught up), then drops the agreeing keys. A key the snapshot
/// has not yet caught up to stays overlaid — never dropped early — so the guard
/// holds across the whole watcher lag.
class WriteThroughOverlay {
  /// Pending overlay writes per bead id: metadata key → wire value (the empty
  /// string is a clear, exactly as gc's `SetMetadata(id, k, "")`).
  final Map<String, Map<String, String>> _byBead = {};

  /// Records the metadata writes [action] performs against its bead, so the
  /// next reduce reads post-actuation state. Pour/close/burn effects that are
  /// not plain metadata writes are handled by the snapshot + the live probe;
  /// this overlay carries only the `convergence.*` write sequence that drives
  /// the reducer's guards.
  void recordAction(ReconcilerAction action) {
    final writes = _writesOf(action);
    if (writes.isEmpty) return;
    final bead = action.convergenceBeadId;
    final overlay = _byBead.putIfAbsent(bead, () => {});
    for (final w in writes) {
      overlay[w.key] = w.value;
    }
  }

  /// Records explicit [writes] for [beadId] (the recovery-action path, whose
  /// effects are not [ReconcilerAction]s).
  void recordWrites(String beadId, Iterable<MetadataWrite> writes) {
    if (writes.isEmpty) return;
    final overlay = _byBead.putIfAbsent(beadId, () => {});
    for (final w in writes) {
      overlay[w.key] = w.value;
    }
  }

  /// Whether any overlay write is pending for [beadId].
  bool hasOverlay(String beadId) => _byBead[beadId]?.isNotEmpty ?? false;

  /// The pending overlay metadata for [beadId] (empty when none).
  Map<String, String> overlayFor(String beadId) =>
      Map.unmodifiable(_byBead[beadId] ?? const {});

  /// Re-projects [convergence] with the pending overlay layered on top of its
  /// metadata — the post-actuation view the next reduce must run over. Pours
  /// and closes are NOT replayed here (the live probe + the snapshot carry
  /// those); only the metadata guard fields (`last_processed_wisp`,
  /// `gate_outcome_wisp`, `state`, `pending_next_wisp`, `active_wisp`, …) are
  /// overlaid, which is exactly what the reducer's dedup/replay/validate logic
  /// reads.
  Convergence apply(Convergence convergence) {
    final overlay = _byBead[convergence.id];
    if (overlay == null || overlay.isEmpty) return convergence;
    final mergedRaw = <String, dynamic>{
      ...convergence.metadata.raw,
      ...overlay,
    };
    return convergence.copyWith(
      metadata: ConvergenceMetadata.decode(mergedRaw),
    );
  }

  /// Drops overlay keys for [beadId] that the freshly-observed
  /// [snapshotMetadata] (the bead's raw metadata in the new snapshot) now
  /// agrees with — the snapshot caught up. Keys the snapshot has not caught up
  /// to are KEPT (the watcher is still lagging that write). Called when a new
  /// snapshot is captured.
  void reconcileWithSnapshot(
    String beadId,
    Map<String, dynamic> snapshotMetadata,
  ) {
    final overlay = _byBead[beadId];
    if (overlay == null) return;
    overlay.removeWhere((key, value) {
      final snapValue = snapshotMetadata[key];
      // A cleared key ('') agrees when the snapshot also reads empty/absent.
      if (value.isEmpty) {
        return snapValue == null || snapValue == '';
      }
      return snapValue == value;
    });
    if (overlay.isEmpty) _byBead.remove(beadId);
  }

  /// Drops the entire overlay for [beadId] (e.g. the loop terminated and was
  /// removed). Use sparingly — prefer [reconcileWithSnapshot].
  void clear(String beadId) => _byBead.remove(beadId);

  /// The metadata-write sequence an [action] commits, in the order the actuator
  /// applies it — the union of the variant's ordered write getters. The exact
  /// ordering does not matter for the overlay (it is a key→value map), but
  /// every guard-relevant key must be captured.
  static List<MetadataWrite> _writesOf(ReconcilerAction action) =>
      switch (action) {
        IterateAction() => action.preWrites + action.postPourWritesForOverlay,
        ApprovedAction() =>
          action.terminalWrites + action.commitWritesForOverlay,
        NoConvergenceAction() =>
          action.terminalWrites + action.commitWritesForOverlay,
        WaitingManualAction() => action.orderedWrites,
        WaitingTriggerAction() => action.orderedWrites,
        StoppedAction() => action.orderedWrites + action.commitWritesForOverlay,
        // The gate-replay marker (`gate_outcome_wisp` LAST) is the A17 guard
        // for a fast-gate duplicate: once persisted, a re-delivered closure
        // reducing over the overlaid state takes the replay branch
        // (skipGateEval) instead of re-running the gate. Capture all eight.
        PersistGateOutcomeAction() => action.orderedWrites,
        // The iteration self-heal — advancing the stored counter pre-snapshot
        // keeps a re-entry from re-emitting a redundant repair.
        RepairIterationAction() => [action.write],
        SkippedAction() ||
        PourSpeculativeAction() ||
        EvaluateGateAction() ||
        FailedAction() ||
        RequeueAction() => const [],
      };
}

/// Overlay-only helpers that expose each transition action's metadata-write
/// sequence as a flat list the [WriteThroughOverlay] can record without
/// threading the runtime pour id (the overlay only needs the guard KEYS; the
/// `nextWispId`/`forceClose` value-bearing writes are best-effort here and the
/// live probe is the authority on the wisp itself).
extension _OverlayWrites on ReconcilerAction {
  // Iterate: the post-pour writes use a placeholder wisp id — the overlay does
  // not need the exact `active_wisp` value (the snapshot/live probe carry the
  // wisp), only the guard keys that change (`last_processed_wisp`,
  // `waiting_reason`, `state`). Pass the empty string for the wisp id slot.
  List<MetadataWrite> get postPourWritesForOverlay => switch (this) {
    final IterateAction a => a.postPourWrites(a.adoptWispId ?? ''),
    _ => const [],
  };

  // Terminal/stop commit marker (`last_processed_wisp`, written LAST). Exposed
  // for the overlay so the dedup baseline advances post-actuation.
  List<MetadataWrite> get commitWritesForOverlay {
    final MetadataWrite? commit = switch (this) {
      final ApprovedAction a => a.commitWrite,
      final NoConvergenceAction a => a.commitWrite,
      final StoppedAction a => a.commitWrite,
      _ => null,
    };
    return commit == null ? const [] : [commit];
  }
}
