import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart' show GridIssueTypes;

import '../molecule/molecule_schema.dart';
import 'rework.dart';
import 'session_bead.dart';

/// The immutable, deterministic scope for one state-store prune.
///
/// [targetIds] is the union of complete old closed session graphs that passed
/// the work-exposure fence. [protectedIds] is every state-store id outside
/// that union. Both lists are defensive copies in stable lexical order and
/// cannot be mutated by callers.
final class StateStorePrunePlan {
  StateStorePrunePlan({
    required Iterable<String> targetIds,
    required Iterable<String> protectedIds,
  }) : targetIds = List<String>.unmodifiable(
         targetIds.toList(growable: false)..sort(),
       ),
       protectedIds = List<String>.unmodifiable(
         protectedIds.toList(growable: false)..sort(),
       );

  final List<String> targetIds;
  final List<String> protectedIds;
}

/// Derives the fail-closed scope for pruning old closed session step graphs.
///
/// This is a value-only snapshot read: no notifier, tree dependency, service,
/// clock, timer, or body inflation enters the planner. A graph is eligible
/// only when its closed session is strictly older than [now] minus [age], its
/// work link is no longer exposed, and every collected molecule/step child is
/// likewise non-ephemeral, closed, and strictly old. Any ambiguity protects
/// the whole graph.
StateStorePrunePlan planStateStorePrune({
  required GraphSnapshot state,
  required GraphSnapshot work,
  required Duration age,
  required DateTime now,
}) {
  if (age <= Duration.zero) {
    throw ArgumentError.value(age, 'age', 'must be positive');
  }
  final cutoff = now.subtract(age);
  final targets = <String>{};

  for (final session in state.beads) {
    if (session.issueType != GridIssueTypes.session ||
        !_isOldClosed(session, cutoff)) {
      continue;
    }
    final workKey = session.metadata[SessionBeadKeys.workBead];
    if (workKey is! String ||
        workKey.isEmpty ||
        !_isExposureCleared(
          sessionId: session.id,
          workKey: workKey,
          work: work,
        )) {
      continue;
    }

    final graph = <Bead>[session];
    for (final bead in state.beads) {
      final belongsToSession =
          (bead.issueType == GridIssueTypes.molecule &&
              bead.metadata[MoleculeCircuitKeys.session] == session.id) ||
          (bead.issueType == GridIssueTypes.step &&
              bead.metadata[MoleculeStepKeys.session] == session.id);
      if (belongsToSession) graph.add(bead);
    }
    if (graph.every((bead) => _isOldClosed(bead, cutoff))) {
      targets.addAll(graph.map((bead) => bead.id));
    }
  }

  return StateStorePrunePlan(
    targetIds: targets,
    protectedIds: state.beadsById.keys.where((id) => !targets.contains(id)),
  );
}

bool _isOldClosed(Bead bead, DateTime cutoff) {
  final closedAt = bead.closedAt;
  return !bead.ephemeral &&
      bead.isClosed &&
      closedAt != null &&
      closedAt.isBefore(cutoff);
}

bool _isExposureCleared({
  required String sessionId,
  required String workKey,
  required GraphSnapshot work,
}) {
  final direct = work.bead(workKey);
  if (direct != null && direct.isClosed) return true;

  for (final candidate in work.beads) {
    if (candidate.isClosed && reworkRoundOf(candidate.id, workKey) != null) {
      return true;
    }
  }

  final suffix = '#void-$sessionId';
  if (!workKey.endsWith(suffix)) return false;
  final baseWorkId = workKey.substring(0, workKey.length - suffix.length);
  return baseWorkId.isNotEmpty && workKey == voidKeyFor(baseWorkId, sessionId);
}
