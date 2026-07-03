import 'package:freezed_annotation/freezed_annotation.dart';

import '../models/bead.dart';
import '../models/bead_dependency.dart';

part 'graph_event.freezed.dart';

/// A typed change emitted by `diffSnapshots`. Consumers pattern-match
/// exhaustively over this sealed hierarchy (the house style).
///
/// `BeadDeleted` extends the ratified ADR-0001 Decision 5 set
/// (SnapshotInitialized, BeadCreated/Updated/Closed/Reopened,
/// DependencyAdded/Removed, ReadySetChanged) so a hard `bd delete` is not a
/// silently-missed change class — recorded as ADR-0000 amendment A10.
@freezed
sealed class GraphEvent with _$GraphEvent {
  const GraphEvent._();

  /// The baseline load. Carries counts only — it does not enumerate a
  /// `BeadCreated` per existing bead (that would be thousands of events on
  /// startup). Per-bead events flow from subsequent diffs.
  const factory GraphEvent.snapshotInitialized({
    required int beadCount,
    required int readyCount,
  }) = SnapshotInitialized;

  const factory GraphEvent.beadCreated(Bead bead) = BeadCreated;

  /// A non-lifecycle change. [changedFields] names the differing fields (e.g.
  /// `{priority, assignee}`); status changes that aren't a close/reopen appear
  /// here too.
  const factory GraphEvent.beadUpdated({
    required Bead before,
    required Bead after,
    required Set<String> changedFields,
  }) = BeadUpdated;

  /// Status transitioned into `closed`.
  const factory GraphEvent.beadClosed({
    required Bead before,
    required Bead after,
  }) = BeadClosed;

  /// Status transitioned out of `closed`.
  const factory GraphEvent.beadReopened({
    required Bead before,
    required Bead after,
  }) = BeadReopened;

  /// A bead disappeared from the graph (hard delete). See class doc / A10.
  const factory GraphEvent.beadDeleted(Bead bead) = BeadDeleted;

  const factory GraphEvent.dependencyAdded(BeadDependency dependency) =
      DependencyAdded;

  const factory GraphEvent.dependencyRemoved(BeadDependency dependency) =
      DependencyRemoved;

  const factory GraphEvent.readySetChanged({
    required Set<String> entered,
    required Set<String> exited,
  }) = ReadySetChanged;

  /// The primary bead id this event concerns, where one applies (null for
  /// snapshot/ready aggregate events).
  String? get beadId => switch (this) {
    BeadCreated(:final bead) => bead.id,
    BeadUpdated(:final after) => after.id,
    BeadClosed(:final after) => after.id,
    BeadReopened(:final after) => after.id,
    BeadDeleted(:final bead) => bead.id,
    DependencyAdded(:final dependency) => dependency.issueId,
    DependencyRemoved(:final dependency) => dependency.issueId,
    SnapshotInitialized() => null,
    ReadySetChanged() => null,
  };
}
