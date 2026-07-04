import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'snapshot_source.dart';

/// One federation member's freshness (tg-nsj, `docs/SCRATCH-multi-root-federation.md`
/// D-F3/D-Z3/D-Z4) — the per-member VECTOR [FederatedSnapshotSource.freshness]
/// exposes instead of collapsing every member into one scalar `capturedAt`.
class MemberFreshness {
  /// Creates the freshness record for one member.
  const MemberFreshness({required this.capturedAt, required this.stale});

  /// The member's last known snapshot capture time, or `null` before its
  /// first baseline arrives.
  final DateTime? capturedAt;

  /// True once the member's stream has errored and not yet recovered — its
  /// last known snapshot is RETAINED (absence ≠ deletion, D-Z3) but mints no
  /// NEW ready ids while stale (D-Z4).
  final bool stale;
}

/// Unions N **local** work [SnapshotSource]s into ONE change-gated
/// [SnapshotSource] — the fan-in that runs BEFORE `StationJoinBridge` (D-F1).
///
/// Scope note (`docs/SCRATCH-grid-alignment.md` §4 rescope, 2026-07-03): a
/// remote substation is **never** a snapshot member (D-A2 — assignment-
/// federation, not observation-federation); every member here is a LOCAL
/// beads workspace this station reads directly. Bead ids are prefix-disjoint
/// across stores (measured 2026-07-03: zero cross-prefix collisions), so
/// member snapshots merge directly — no id-rewrite/namespacing needed.
///
/// Membership is MUTABLE (D-F1/D-Z1/D-Z2): [addMember]/[removeMember] attach
/// or detach a member at runtime; the static `--workspace <substation>=<path>`
/// flags `grid_cli` wires at boot are merely the FIRST membership source — a
/// future zero-conf browser is the second, behind this same seam, with
/// nothing here reshaped.
///
/// Contract (matches [SnapshotSource] exactly, so the bridge cannot tell a
/// federated source from a single runtime): [snapshots] is change-gated
/// (diff-non-empty), broadcast, non-replaying; [current] is the last computed
/// union, or `null` before any member has published a baseline.
class FederatedSnapshotSource implements SnapshotSource {
  /// Builds a union over the initial [members] (substation id → its own
  /// local [SnapshotSource]) and starts following every one of them
  /// immediately.
  FederatedSnapshotSource(
    Map<String, SnapshotSource> members, {
    void Function(String message)? onUnresolvedExternalDep,
  }) : _onUnresolvedExternalDep = onUnresolvedExternalDep {
    members.forEach(_attach);
    _current = _combine();
  }

  final void Function(String message)? _onUnresolvedExternalDep;

  final Map<String, SnapshotSource> _sources = {};
  final Map<String, StreamSubscription<GraphSnapshot>> _subs = {};
  final Map<String, GraphSnapshot?> _latestByMember = {};
  final Map<String, bool> _staleByMember = {};

  final StreamController<GraphSnapshot> _controller =
      StreamController<GraphSnapshot>.broadcast();
  GraphSnapshot? _current;

  @override
  Stream<GraphSnapshot> get snapshots => _controller.stream;

  @override
  GraphSnapshot? get current => _current;

  /// The member substation ids currently unioned (read-only view).
  Set<String> get members => Set.unmodifiable(_sources.keys);

  /// The per-member freshness vector (D-F3) — the union's own `capturedAt`
  /// (on the combined [GraphSnapshot]) is the MAX of these; staleness is
  /// judged per member, never averaged away.
  Map<String, MemberFreshness> get freshness => {
    for (final id in _sources.keys)
      id: MemberFreshness(
        capturedAt: _latestByMember[id]?.capturedAt,
        stale: _staleByMember[id] ?? false,
      ),
  };

  /// Attaches a NEW member at runtime (D-Z1/D-Z2 — mutable membership; a
  /// future zero-conf browser calls this behind the same seam a static
  /// boot-time list uses today). A no-op if [substation] is already a member.
  void addMember(String substation, SnapshotSource source) {
    if (_sources.containsKey(substation)) return;
    _attach(substation, source);
    _recompute();
  }

  /// Detaches a member — an operator un-registering a store, not a network
  /// blip (that's a stream error, handled by [_attach]'s `onError`, which
  /// keeps the member and only marks it stale — absence ≠ deletion, D-Z3).
  /// A no-op if [substation] is not a member.
  void removeMember(String substation) {
    final sub = _subs.remove(substation);
    if (sub == null) return;
    unawaited(sub.cancel());
    _sources.remove(substation);
    _latestByMember.remove(substation);
    _staleByMember.remove(substation);
    _recompute();
  }

  void _attach(String substation, SnapshotSource source) {
    _sources[substation] = source;
    _latestByMember[substation] = source.current;
    _staleByMember[substation] = false;
    _subs[substation] = source.snapshots.listen(
      (snapshot) {
        _latestByMember[substation] = snapshot;
        _staleByMember[substation] = false;
        _recompute();
      },
      onError: (Object _, StackTrace _) {
        // D-Z3 — absence ≠ deletion: RETAIN the last known snapshot frozen;
        // only mark the member stale (D-Z4 handles what staleness costs).
        _staleByMember[substation] = true;
        _recompute();
      },
    );
  }

  void _recompute() {
    final previous = _current;
    final next = _combine();
    _current = next;
    if (next != null && diffSnapshots(previous, next).isNotEmpty) {
      _controller.add(next);
    }
  }

  /// Merges every member's latest known snapshot into one [GraphSnapshot]:
  /// beads/dependencies union directly (ids are prefix-disjoint); readyIds is
  /// the union of FRESH members' ready ids (D-Z4 — a stale member mints no
  /// NEW ready ids, though its already-known beads stay visible above), minus
  /// the external-dep guard (D-F2). Returns `null` while no member has ever
  /// published (no baseline anywhere yet).
  GraphSnapshot? _combine() {
    if (_latestByMember.values.every((s) => s == null)) return null;

    final beadsById = <String, Bead>{};
    final dependencies = <BeadDependency>[];
    DateTime? capturedAt;
    final readyCandidates = <String>{};

    for (final entry in _latestByMember.entries) {
      final snapshot = entry.value;
      if (snapshot == null) continue;
      beadsById.addAll(snapshot.beadsById);
      dependencies.addAll(snapshot.dependencies);
      if (capturedAt == null || snapshot.capturedAt.isAfter(capturedAt)) {
        capturedAt = snapshot.capturedAt;
      }
      if (_staleByMember[entry.key] != true) {
        readyCandidates.addAll(snapshot.readyIds);
      }
    }

    return GraphSnapshot(
      beadsById: beadsById,
      dependencies: dependencies,
      readyIds: _applyExternalDepGuard(
        readyCandidates,
        beadsById,
        dependencies,
      ),
      capturedAt: capturedAt!,
    );
  }

  /// D-F2 — each per-store `bd ready` already excludes a bead blocked by a
  /// dependency target IN ITS OWN store (bd's `is_blocked` maintenance
  /// handles that), but bd's `is_blocked` recompute never reads the
  /// `depends_on_external` column, so a bead blocked by a target in ANOTHER
  /// federation member is reported ready by its own store regardless. This
  /// re-applies the block across the union: a candidate carrying a blocking
  /// edge (`DependencyType.affectsBlocking`) to a DIFFERENT store's bead is
  /// excluded when that target is open, or when the target is not found
  /// anywhere in the federation at all (fail-closed + LOUD — an unresolvable
  /// external dependency must never silently pass as satisfied).
  Set<String> _applyExternalDepGuard(
    Set<String> candidates,
    Map<String, Bead> beadsById,
    List<BeadDependency> dependencies,
  ) {
    if (candidates.isEmpty) return candidates;
    final blockingByIssue = <String, List<BeadDependency>>{};
    for (final dep in dependencies) {
      if (!dep.type.affectsBlocking) continue;
      (blockingByIssue[dep.issueId] ??= <BeadDependency>[]).add(dep);
    }
    if (blockingByIssue.isEmpty) return candidates;

    final result = <String>{};
    for (final id in candidates) {
      final ownStore = BeadOwnershipPredicate.prefixOf(id);
      var blocked = false;
      for (final dep in blockingByIssue[id] ?? const <BeadDependency>[]) {
        final targetStore = BeadOwnershipPredicate.prefixOf(dep.dependsOnId);
        if (targetStore == ownStore) {
          continue; // same-store — the origin store's own `bd ready` already accounts for it.
        }
        final target = beadsById[dep.dependsOnId];
        if (target == null) {
          _onUnresolvedExternalDep?.call(
            'grid: $id carries a cross-store dependency on '
            '"${dep.dependsOnId}", which is not observed by any federated '
            'store — excluding $id from ready (fail-closed).',
          );
          blocked = true;
          break;
        }
        if (!target.isClosed) {
          blocked = true;
          break;
        }
      }
      if (!blocked) result.add(id);
    }
    return result;
  }

  /// Cancels every member subscription and closes the union stream. Does
  /// **not** dispose the member [SnapshotSource]s themselves — the caller
  /// that built them (`buildControllers`) owns their lifecycle.
  Future<void> dispose() async {
    for (final sub in _subs.values) {
      await sub.cancel();
    }
    _subs.clear();
    await _controller.close();
  }
}
