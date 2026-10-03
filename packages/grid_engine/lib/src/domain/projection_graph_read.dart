/// The G2 projection graph read model over P2, semantic edges, and P6 leases.
library;

import 'package:meta/meta.dart';

import '../sdk/circuit.dart';
import '../sdk/cursor.dart';
import 'trajectory_views.dart';

@immutable
sealed class ProjectionAttemptLeaseRead {
  const ProjectionAttemptLeaseRead();
}

final class ProjectionAttemptLeaseAbsent extends ProjectionAttemptLeaseRead {
  const ProjectionAttemptLeaseAbsent();

  @override
  bool operator ==(Object other) => other is ProjectionAttemptLeaseAbsent;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class ProjectionAttemptLeaseHeld extends ProjectionAttemptLeaseRead {
  const ProjectionAttemptLeaseHeld({
    required this.attemptId,
    required this.pid,
    required this.pgid,
  });

  final String attemptId;
  final int pid;
  final int pgid;

  @override
  bool operator ==(Object other) =>
      other is ProjectionAttemptLeaseHeld &&
      other.attemptId == attemptId &&
      other.pid == pid &&
      other.pgid == pgid;

  @override
  int get hashCode => Object.hash(attemptId, pid, pgid);
}

@immutable
sealed class ProjectionStepRead {
  const ProjectionStepRead(this.path);

  final String path;
  bool get isMaterialized;
  bool get isPending;
  bool get isComplete;
  bool get isSuperseded;

  /// Missing P2 is a materialization state, never a missing-graph verdict.
  bool get isGraphMissing => false;
}

final class ProjectionStepNotMaterialized extends ProjectionStepRead {
  const ProjectionStepNotMaterialized(super.path);

  @override
  bool get isMaterialized => false;
  @override
  bool get isPending => true;
  @override
  bool get isComplete => false;
  @override
  bool get isSuperseded => false;
}

final class ProjectionStepMaterialized extends ProjectionStepRead {
  ProjectionStepMaterialized({
    required String path,
    required this.active,
    required Iterable<StepCursorView> chain,
    required Iterable<String> blockers,
    required Iterable<String> validates,
    required this.lease,
  }) : chain = List<StepCursorView>.unmodifiable(chain),
       blockers = List<String>.unmodifiable(blockers),
       validates = List<String>.unmodifiable(validates),
       super(path);

  final StepCursorView active;
  final List<StepCursorView> chain;
  final List<String> blockers;
  final List<String> validates;
  final ProjectionAttemptLeaseRead lease;

  int get depth => chain.length - 1;
  int get spentResultCount => chain
      .whereType<StepTransitionCursorView>()
      .where((row) => row.result != null && row.result!.isNotEmpty)
      .length;
  Map<String, Object?>? get result => active is StepTransitionCursorView
      ? (active as StepTransitionCursorView).result
      : null;
  DateTime? get cooldownUntil => active.cooldownUntil;
  int get incarnation => active.incarnation;
  int? get restartBudget => active.restartBudget;

  NodeCursor get cursor => NodeCursor(
    state: StepState.values.byName(active.stepState),
    restartCount: active.incarnation,
    cooldownUntil: active.cooldownUntil,
    startedAt: active.startedAt,
    finishedAt: active.completedAt,
    failureReason: active.failureClass,
    pid: switch (lease) {
      ProjectionAttemptLeaseHeld(:final pid) => pid,
      ProjectionAttemptLeaseAbsent() => null,
    },
    pgid: switch (lease) {
      ProjectionAttemptLeaseHeld(:final pgid) => pgid,
      ProjectionAttemptLeaseAbsent() => null,
    },
    token: switch (lease) {
      ProjectionAttemptLeaseHeld(:final attemptId) => attemptId,
      ProjectionAttemptLeaseAbsent() => null,
    },
  );

  @override
  bool get isMaterialized => true;
  @override
  bool get isPending => active.stepState == StepState.pending.name;
  @override
  bool get isComplete => active.stepState == StepState.complete.name;
  @override
  bool get isSuperseded => chain.length > 1;
}

/// One session-round projection assembled without reading graph beads.
@immutable
final class ProjectionGraphRead {
  ProjectionGraphRead({
    required this.sessionId,
    required this.round,
    required TrajectoryStepSnapshot steps,
    required TrajectoryStepEdgeSnapshot edges,
    required TrajectoryProcessIdentitySnapshot processIdentities,
    this.isAuthoritative = false,
  }) : _processIdentities = processIdentities {
    for (final edge in edges.bySessionId(sessionId)) {
      if (edge.round != round) continue;
      switch (edge.kind) {
        case 'blocks':
          (_blockers[edge.fromPath] ??= <String>[]).add(edge.toPath);
        case 'validates':
          (_validates[edge.fromPath] ??= <String>[]).add(edge.toPath);
        default:
          throw StateError('unsupported proj_step_edges kind "${edge.kind}"');
      }
    }
    for (final paths in _blockers.values) {
      paths.sort();
    }
    for (final paths in _validates.values) {
      paths.sort();
    }
    final byPath = <String, List<StepCursorView>>{};
    for (final row in steps.byP2SessionId(sessionId)) {
      if (row.round != round) continue;
      (byPath[row.stepPath] ??= <StepCursorView>[]).add(row);
    }
    for (final entry in byPath.entries) {
      final chain = entry.value
        ..sort((a, b) => a.stepRound.compareTo(b.stepRound));
      for (var index = 0; index < chain.length; index += 1) {
        final expected = index + 1 < chain.length
            ? chain[index + 1].stepRound
            : null;
        if (chain[index].supersededByStepRound != expected) {
          throw StateError(
            'proj_step_cursor supersedes chain hole for $sessionId '
            '${entry.key}: round ${chain[index].stepRound} points to '
            '${chain[index].supersededByStepRound}, expected $expected',
          );
        }
      }
      _steps[entry.key] = ProjectionStepMaterialized(
        path: entry.key,
        active: chain.last,
        chain: chain,
        blockers: _blockers[entry.key] ?? const <String>[],
        validates: _validates[entry.key] ?? const <String>[],
        lease: _leaseFor(chain.last),
      );
    }
  }

  final String sessionId;
  final int round;
  final bool isAuthoritative;
  final TrajectoryProcessIdentitySnapshot _processIdentities;
  final Map<String, ProjectionStepMaterialized> _steps = {};
  final Map<String, List<String>> _blockers = {};
  final Map<String, List<String>> _validates = {};

  ProjectionStepRead stepAt(String path) =>
      _steps[path] ?? ProjectionStepNotMaterialized(path);

  List<String>? blockersFor(String path) => switch (_blockers[path]) {
    final paths? => List<String>.unmodifiable(paths),
    null => null,
  };

  List<String>? validatesFor(String path) => switch (_validates[path]) {
    final paths? => List<String>.unmodifiable(paths),
    null => null,
  };

  CircuitCursor get cursor => {
    for (final entry in _steps.entries) entry.key: entry.value.cursor,
  };

  Map<String, Map<String, String>> get results => {
    for (final entry in _steps.entries)
      if (entry.value.result != null)
        entry.key: {
          for (final value in entry.value.result!.entries)
            value.key: '${value.value}',
        },
  };

  Map<String, int> get supersedesDepthByPath => {
    for (final entry in _steps.entries) entry.key: entry.value.depth,
  };

  Map<String, int> get spentResultCountByPath => {
    for (final entry in _steps.entries) entry.key: entry.value.spentResultCount,
  };

  Map<String, ProjectionAttemptLeaseRead> get leasesByPath => {
    for (final entry in _steps.entries) entry.key: entry.value.lease,
  };

  ProjectionAttemptLeaseRead _leaseFor(StepCursorView active) {
    final attemptId = active.attemptId;
    if (attemptId == null) return const ProjectionAttemptLeaseAbsent();
    for (final row in _processIdentities.bySessionId(sessionId)) {
      if (row.attemptId == attemptId &&
          row.round == round &&
          row.stepPath == active.stepPath &&
          row.stepRound == active.stepRound &&
          row.incarnation == active.incarnation &&
          row.leaseState == 'held' &&
          row.pid != null &&
          row.pgid != null) {
        return ProjectionAttemptLeaseHeld(
          attemptId: attemptId,
          pid: row.pid!,
          pgid: row.pgid!,
        );
      }
    }
    return const ProjectionAttemptLeaseAbsent();
  }
}
