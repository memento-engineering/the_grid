import 'package:beads_dart/beads_dart.dart' show GraphSnapshot;
import 'package:grid_engine/grid_engine.dart' show planStateStorePrune;

import 'state_store_gc.dart';

/// Refreshes and returns the station state and federated work snapshots used
/// by one state-store prune pass.
typedef FreshStateStorePruneSnapshots =
    Future<({GraphSnapshot? state, GraphSnapshot? work})> Function();

/// Executes one bulk state-store prune behind the station writer's protection
/// shield.
typedef StateStorePruneExecutor =
    Future<({int beadsRemoved, int dependencyRowsRemoved})> Function({
      required Iterable<String> protectedIds,
      required int olderThanDays,
    });

/// Plans and executes one fail-closed closed-session-graph prune.
final class StateStorePruner {
  /// Creates a pruner whose I/O collaborators are injected by station
  /// assembly.
  StateStorePruner({
    required Duration age,
    required FreshStateStorePruneSnapshots freshSnapshots,
    required StateStorePruneExecutor execute,
    MaintenanceClock? now,
    required MaintenanceSink out,
  }) : _age = age,
       _freshSnapshots = freshSnapshots,
       _execute = execute,
       _now = now ?? DateTime.now,
       _out = out;

  final Duration _age;
  final FreshStateStorePruneSnapshots _freshSnapshots;
  final StateStorePruneExecutor _execute;
  final MaintenanceClock _now;
  final MaintenanceSink _out;

  /// Runs one idempotent prune pass and emits exactly one receipt.
  Future<void> run() async {
    final startedAt = _now();
    String line;
    try {
      final snapshots = await _freshSnapshots();
      final state = snapshots.state;
      final work = snapshots.work;
      if (state == null || work == null) {
        throw const _StateStorePruneSkipped(
          'state or work snapshot unavailable',
        );
      }
      final plan = planStateStorePrune(
        state: state,
        work: work,
        age: _age,
        now: _now(),
      );
      final receipt = plan.targetIds.isEmpty
          ? (beadsRemoved: 0, dependencyRowsRemoved: 0)
          : await _execute(
              protectedIds: plan.protectedIds,
              olderThanDays: _age.inDays,
            );
      line =
          'grid: state-store prune complete '
          'beads_removed=${receipt.beadsRemoved} '
          'dependency_rows_removed=${receipt.dependencyRowsRemoved} '
          'elapsed_ms=${_now().difference(startedAt).inMilliseconds}';
    } on Object catch (error) {
      final reason = switch (error) {
        _StateStorePruneSkipped(:final reason) => reason,
        _ => error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ').trim(),
      };
      line =
          'grid: state-store prune skipped beads_removed=0 '
          'dependency_rows_removed=0 '
          'elapsed_ms=${_now().difference(startedAt).inMilliseconds} '
          'reason=$reason';
    }
    _out(line);
  }
}

final class _StateStorePruneSkipped implements Exception {
  const _StateStorePruneSkipped(this.reason);

  final String reason;
}
