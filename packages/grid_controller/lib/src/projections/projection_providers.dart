import 'package:riverpod/riverpod.dart';

import '../models/bead.dart';
import '../models/graph_snapshot.dart';
import '../models/issue_type.dart';
import '../providers/grid_providers.dart';
import 'agent_session.dart';
import 'message.dart';
import 'molecule.dart';
import 'projection_error.dart';
import 'step.dart';

/// Pure projection selectors over [graphSnapshotProvider].
///
/// These add **no IO** — they watch the snapshot stream and project the beads
/// whose `issue_type` matches each domain. Decode failures are dropped from the
/// success lists (never thrown); the M1 fixtures decode cleanly, so failure
/// surfacing stays a per-projection concern (see [ProjectionResult]).

GraphSnapshot? _snapshot(Ref ref) => ref.watch(graphSnapshotProvider).value;

List<T> _projectAll<T>(
  Iterable<Bead> beads,
  ProjectionResult<T> Function(Bead) project,
) {
  final out = <T>[];
  for (final bead in beads) {
    if (project(bead) case ProjectionOk<T>(:final value)) out.add(value);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

/// All sessions in the current snapshot (open and closed).
final sessionsProvider = Provider<List<AgentSession>>((ref) {
  final snapshot = _snapshot(ref);
  if (snapshot == null) return const [];
  return _projectAll(
    snapshot.beads.where((b) => b.issueType == IssueType.session),
    AgentSession.project,
  );
});

/// Sessions for one durable agent identity (`metadata.agent_name`).
final sessionsForAgentProvider = Provider.family<List<AgentSession>, String>((
  ref,
  agentName,
) {
  return [
    for (final session in ref.watch(sessionsProvider))
      if (session.agentName == agentName) session,
  ];
});

/// Sessions grouped by lifecycle state (open vs closed).
final sessionsByStateProvider = Provider<Map<SessionState, List<AgentSession>>>(
  (ref) {
    final byState = <SessionState, List<AgentSession>>{
      SessionState.open: [],
      SessionState.closed: [],
    };
    for (final session in ref.watch(sessionsProvider)) {
      byState[session.state]!.add(session);
    }
    return byState;
  },
);

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

/// All messages in the current snapshot.
final messagesProvider = Provider<List<Message>>((ref) {
  final snapshot = _snapshot(ref);
  if (snapshot == null) return const [];
  return _projectAll(
    snapshot.beads.where((b) => b.issueType == IssueType.message),
    Message.project,
  );
});

/// An agent's inbox: open (unread) messages addressed to [agent].
final inboxProvider = Provider.family<List<Message>, String>((ref, agent) {
  return [
    for (final message in ref.watch(messagesProvider))
      if (message.recipient == agent && message.isUnread) message,
  ];
});

/// Messages grouped under a `thread:<id>` label.
final threadProvider = Provider.family<List<Message>, String>((ref, threadId) {
  return [
    for (final message in ref.watch(messagesProvider))
      if (message.threadId == threadId) message,
  ];
});

// ---------------------------------------------------------------------------
// Molecules + steps
// ---------------------------------------------------------------------------

/// All molecules in the current snapshot, with child steps resolved from the
/// snapshot's dependency graph.
final moleculesProvider = Provider<List<Molecule>>((ref) {
  final snapshot = _snapshot(ref);
  if (snapshot == null) return const [];
  final out = <Molecule>[];
  for (final bead in snapshot.beads) {
    if (bead.issueType != IssueType.molecule) continue;
    final result = Molecule.project(
      bead,
      dependencies: snapshot.dependencies,
      beadsById: snapshot.beadsById,
    );
    if (result case ProjectionOk<Molecule>(:final value)) out.add(value);
  }
  return out;
});

/// One molecule's projection by id (null if absent or not a molecule).
final moleculeProvider = Provider.family<Molecule?, String>((ref, id) {
  for (final molecule in ref.watch(moleculesProvider)) {
    if (molecule.id == id) return molecule;
  }
  return null;
});

/// Progress (closed / total steps) for one molecule, as a fraction in [0,1].
/// Null when the molecule is absent.
final moleculeProgressProvider = Provider.family<double?, String>((ref, id) {
  return ref.watch(moleculeProvider(id))?.progress;
});

/// The runnable frontier (steps whose `needs` are satisfied) for one molecule.
final runnableStepsProvider = Provider.family<List<Step>, String>((ref, id) {
  return ref.watch(moleculeProvider(id))?.runnableSteps ?? const [];
});
