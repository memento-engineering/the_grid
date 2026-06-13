import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:grid_controller/grid_controller.dart';

import '../convergence/convergence_metadata.dart';
import '../convergence/convergence_state.dart';
import '../convergence/idempotency_key.dart';
import 'wisp.dart';

part 'convergence.freezed.dart';

/// A convergence loop: the root bead, its typed `convergence.*` metadata, and
/// its wisps resolved from the snapshot's parent-child dependency edges.
///
/// Children are resolved **strictly** in gc's direction — child =
/// `issue_id`, parent = `depends_on_id` on a `parent-child` edge (upstream
/// `beads/internal/storage/issueops/blocked.go:60-63`; the `parent_id`
/// column stays null, ADR-0000 A15) — because [closedWispCount] feeds the
/// iteration-derivation invariant (ADR-0003 invariant 4) and must count
/// exactly what gc's `Store.Children` returns.
@freezed
abstract class Convergence with _$Convergence {
  const Convergence._();

  const factory Convergence({
    required String id,
    required String title,
    required BeadStatus status,
    required ConvergenceMetadata metadata,

    /// Wisps: children whose `metadata.idempotency_key` carries this loop's
    /// prefix (`converge:{id}:iter:`), sorted by iteration (unparseable
    /// iterations last), then id.
    @Default(<Wisp>[]) List<Wisp> wisps,

    /// Every parent-child child id (wisp or not), sorted — gc's
    /// `Store.Children` surface for Track C recovery.
    @Default(<String>[]) List<String> childIds,

    /// `idempotency_key` by child id, for **all** children carrying one
    /// (prefix-matched or not) — the [findByIdempotencyKey] scan domain,
    /// byte-faithful to gc's child scan (cmd/gc/convergence_store.go:264-266).
    @Default(<String, String>{}) Map<String, String> childIdempotencyKeys,
    DateTime? closedAt,
    @Default('') String closeReason,
  }) = _Convergence;

  /// Projects a `convergence`-typed [bead] into a [Convergence], resolving
  /// children through [dependencies]/[beadsById] (pass the snapshot's).
  /// Returns a typed [ProjectionError] on issue-type mismatch; metadata
  /// decode is total and never fails the projection (per-field failures
  /// surface on [ConvergenceMetadata.failures]).
  static ProjectionResult<Convergence> project(
    Bead bead, {
    Iterable<BeadDependency> dependencies = const [],
    Map<String, Bead> beadsById = const {},
  }) {
    if (bead.issueType != IssueType.convergence) {
      return ProjectionFailed(
        ProjectionError(
          beadId: bead.id,
          issueType: bead.issueType.wire,
          projection: 'Convergence',
          reason:
              'expected issue_type "convergence", got "${bead.issueType.wire}"',
        ),
      );
    }

    final deps = dependencies.toList(growable: false);
    final prefix = idempotencyKeyPrefix(bead.id);

    // Children: strict gc direction (see class doc).
    final childIds = <String>[];
    for (final dep in deps) {
      if (dep.type != DependencyType.parentChild) continue;
      if (dep.dependsOnId != bead.id) continue;
      childIds.add(dep.issueId);
    }
    childIds.sort();

    final childKeys = <String, String>{};
    final wisps = <Wisp>[];
    for (final childId in childIds) {
      final child = beadsById[childId];
      if (child == null) continue; // dangling edge — snapshot-safe
      final Object? key = child.metadata[wispIdempotencyKeyField];
      if (key is! String || key.isEmpty) continue;
      childKeys[childId] = key;
      if (!key.startsWith(prefix)) continue;
      final result = Wisp.project(
        child,
        dependencies: deps,
        beadsById: beadsById,
      );
      if (result case ProjectionOk<Wisp>(:final value)) wisps.add(value);
    }
    wisps.sort((a, b) {
      final ai = a.iteration;
      final bi = b.iteration;
      if (ai != null && bi != null && ai != bi) return ai.compareTo(bi);
      if (ai == null && bi != null) return 1; // unparseable last
      if (ai != null && bi == null) return -1;
      return a.id.compareTo(b.id);
    });

    return ProjectionOk(
      Convergence(
        id: bead.id,
        title: bead.title,
        status: bead.status,
        metadata: ConvergenceMetadata.decode(bead.metadata),
        wisps: List<Wisp>.unmodifiable(wisps),
        childIds: List<String>.unmodifiable(childIds),
        childIdempotencyKeys: Map<String, String>.unmodifiable(childKeys),
        closedAt: bead.closedAt,
        closeReason: bead.closeReason,
      ),
    );
  }

  bool get isClosed => status == BeadStatus.closed;

  /// The state reading (known / not-adopted / unrecognized).
  ConvergenceStateReading get state => metadata.state;

  /// Closed wisps with this loop's key prefix — the iteration-derivation
  /// input (ADR-0003 invariant 4; gc `deriveIterationCount`,
  /// handler.go:812-825). Counted by prefix + closed status **regardless of
  /// iteration parseability**, exactly like gc.
  int get closedWispCount => wisps.where((w) => w.isClosed).length;

  /// The metadata `active_wisp` resolved against the actual wisps —
  /// dangling-safe: null when the field is absent/empty (gc clears it by
  /// writing `""`) or names a bead that is not one of this loop's wisps.
  Wisp? get activeWisp {
    final id = metadata.activeWisp;
    if (id == null) return null;
    for (final wisp in wisps) {
      if (wisp.id == id) return wisp;
    }
    return null;
  }

  /// Port of `highestClosedWisp` (reconcile.go:627-652): the closed wisp
  /// with the highest **parseable** iteration, or null.
  Wisp? get highestClosedWisp {
    Wisp? best;
    var bestIter = -1;
    for (final wisp in wisps) {
      if (!wisp.isClosed) continue;
      final iter = wisp.iteration;
      if (iter == null) continue; // unparseable keys are skipped here
      if (iter > bestIter) {
        best = wisp;
        bestIter = iter;
      }
    }
    return best;
  }

  /// Port of gc's `FindByIdempotencyKey` as a **pure snapshot scan** (A15 —
  /// no bd spawn): scans every child's `idempotency_key` (not just
  /// prefix-matched wisps, matching gc's child scan —
  /// cmd/gc/convergence_store.go:264-266) and returns the child's bead id,
  /// or null when not found.
  ///
  /// ⚠ **Freshness contract — a hit is trustworthy; a miss is NOT.** This
  /// scan sees only what the snapshot saw: a wisp poured after the
  /// snapshot's capture is invisible here (a fast actuation routinely
  /// beats the Dolt watcher poll), and treating that miss as "unpoured"
  /// pours a duplicate sibling that permanently inflates
  /// `deriveIterationCount` once closed (ADR-0003 invariant 4). gc has no
  /// such gap — `PourWisp` is store-level idempotent and every handler
  /// entry reads fresh metadata — so the duplicate-pour protocol needs
  /// BOTH replacement layers (full contract on `WispPour`):
  ///
  /// 1. Track G serializes per-bead processing and evaluates events
  ///    against post-actuation (write-through) state, never the raw
  ///    snapshot;
  /// 2. the actuator's find-before-pour is a LIVE probe — the Actuator
  ///    seam's `findWispByIdempotencyKey(parentId, key)`
  ///    (cmd/gc/convergence_store.go:248-270 analog) — issued immediately
  ///    before `bd create --graph`.
  ///
  /// Use this scan as the fast path (adopt a snapshot hit without a live
  /// round-trip) and as the shadow-mode conformance read — never as the
  /// sole pre-pour check.
  String? findByIdempotencyKey(String key) {
    for (final entry in childIdempotencyKeys.entries) {
      if (entry.value == key) return entry.key;
    }
    return null;
  }
}
