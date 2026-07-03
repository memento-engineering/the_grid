import 'package:collection/collection.dart';

import '../models/bead.dart';
import '../models/bead_dependency.dart';
import '../models/graph_snapshot.dart';
import 'graph_event.dart';

const _deepEq = DeepCollectionEquality();
const _setEq = SetEquality<String>();

/// Diffs two snapshots into an ordered, deterministic list of [GraphEvent]s.
///
/// This is the single source of truth for change detection (ADR-0001
/// Decision 5): dirty signals only trigger a re-query; *this* decides what
/// actually changed. Properties:
///
/// * `diffSnapshots(s, s) == []` — a snapshot against itself yields nothing.
/// * `before == null` yields exactly one [SnapshotInitialized] (the baseline;
///   it does not enumerate existing beads).
/// * Output order is stable: created, closed, reopened, updated, deleted,
///   dependencyAdded, dependencyRemoved, then a single readySetChanged.
///   Within each bucket, beads sort by id and edges by [BeadDependency.edgeKey].
List<GraphEvent> diffSnapshots(GraphSnapshot? before, GraphSnapshot after) {
  if (before == null) {
    return [
      GraphEvent.snapshotInitialized(
        beadCount: after.beadCount,
        readyCount: after.readyCount,
      ),
    ];
  }

  final created = <BeadCreated>[];
  final closed = <BeadClosed>[];
  final reopened = <BeadReopened>[];
  final updated = <BeadUpdated>[];
  final deleted = <BeadDeleted>[];

  final beforeIds = before.beadsById.keys.toSet();
  final afterIds = after.beadsById.keys.toSet();

  for (final id in (afterIds.difference(beforeIds)).toList()..sort()) {
    created.add(BeadCreated(after.beadsById[id]!));
  }
  for (final id in (beforeIds.difference(afterIds)).toList()..sort()) {
    deleted.add(BeadDeleted(before.beadsById[id]!));
  }

  for (final id in afterIds.intersection(beforeIds).toList()..sort()) {
    final b = before.beadsById[id]!;
    final a = after.beadsById[id]!;
    if (a == b) continue;
    final changed = _changedFields(b, a);
    if (changed.isEmpty) continue;
    if (!b.isClosed && a.isClosed) {
      closed.add(BeadClosed(before: b, after: a));
    } else if (b.isClosed && !a.isClosed) {
      reopened.add(BeadReopened(before: b, after: a));
    } else {
      updated.add(BeadUpdated(before: b, after: a, changedFields: changed));
    }
  }

  // Dependency edges keyed by the upstream primary-key triple.
  final beforeEdges = {for (final d in before.dependencies) d.edgeKey: d};
  final afterEdges = {for (final d in after.dependencies) d.edgeKey: d};
  final depAdded = <DependencyAdded>[];
  final depRemoved = <DependencyRemoved>[];
  for (final key in (afterEdges.keys.toSet().difference(
    beforeEdges.keys.toSet(),
  )).toList()..sort()) {
    depAdded.add(DependencyAdded(afterEdges[key]!));
  }
  for (final key in (beforeEdges.keys.toSet().difference(
    afterEdges.keys.toSet(),
  )).toList()..sort()) {
    depRemoved.add(DependencyRemoved(beforeEdges[key]!));
  }

  final entered = after.readyIds.difference(before.readyIds);
  final exited = before.readyIds.difference(after.readyIds);

  return [
    ...created,
    ...closed,
    ...reopened,
    ...updated,
    ...deleted,
    ...depAdded,
    ...depRemoved,
    if (entered.isNotEmpty || exited.isNotEmpty)
      GraphEvent.readySetChanged(entered: entered, exited: exited),
  ];
}

/// Names of the modeled fields that differ between two beads of the same id.
/// Excludes `id` (identity) and `comments` (never fetched into a snapshot).
/// Collections compare order-insensitively for `labels` and deeply for
/// `metadata`, matching the normalization snapshot composition guarantees.
Set<String> _changedFields(Bead a, Bead b) {
  final changed = <String>{};
  void check(String name, Object? x, Object? y) {
    if (x != y) changed.add(name);
  }

  check('title', a.title, b.title);
  check('description', a.description, b.description);
  check('design', a.design, b.design);
  check('acceptanceCriteria', a.acceptanceCriteria, b.acceptanceCriteria);
  check('notes', a.notes, b.notes);
  check('specId', a.specId, b.specId);
  check('status', a.status, b.status);
  check('priority', a.priority, b.priority);
  check('issueType', a.issueType, b.issueType);
  check('assignee', a.assignee, b.assignee);
  check('owner', a.owner, b.owner);
  check('estimatedMinutes', a.estimatedMinutes, b.estimatedMinutes);
  check('createdAt', a.createdAt, b.createdAt);
  check('createdBy', a.createdBy, b.createdBy);
  check('updatedAt', a.updatedAt, b.updatedAt);
  check('startedAt', a.startedAt, b.startedAt);
  check('closedAt', a.closedAt, b.closedAt);
  check('closeReason', a.closeReason, b.closeReason);
  check('closedBySession', a.closedBySession, b.closedBySession);
  check('dueAt', a.dueAt, b.dueAt);
  check('deferUntil', a.deferUntil, b.deferUntil);
  check('externalRef', a.externalRef, b.externalRef);
  check('sourceSystem', a.sourceSystem, b.sourceSystem);
  check('ephemeral', a.ephemeral, b.ephemeral);
  check('dependencyCount', a.dependencyCount, b.dependencyCount);
  check('dependentCount', a.dependentCount, b.dependentCount);
  check('commentCount', a.commentCount, b.commentCount);
  if (!_setEq.equals(a.labels.toSet(), b.labels.toSet())) changed.add('labels');
  if (!_deepEq.equals(a.metadata, b.metadata)) changed.add('metadata');
  return changed;
}
