/// The reader-touching half of shadow corroboration (tg-ilug): assembles the
/// [ShadowCorroboration] the §9 lanes join against, from SELECT-only reads.
/// Kept out of `shadow/shadow_corroboration.dart` so the folds and the
/// classifier stay I/O-free and the offline suite injects fakes.
library;

import 'package:meta/meta.dart';

import '../shadow/shadow_corroboration.dart';
import 'shadow_accounting.dart';
import 'trajectory_reader.dart';

/// One run's epoch ledger: every claimed epoch with its coverage, joined to
/// the run's accounting when that accounting names an epoch.
Future<Map<int, EpochEvidence>> readEpochEvidence(
  TrajectoryLogReader reader, {
  ShadowRunAccounting? accounting,
}) async => foldEpochEvidence(
  claims: await reader.epochClaims(),
  accounting: accounting,
);

/// One session's corroboration: a per-attempt subject read for every attempt
/// the session's stream names (the sweep and liveness rows correlate on
/// `attempt_id` only and are invisible to the session read), folded into
/// [AttemptEvidence], beside the run's epoch ledger.
@immutable
final class SessionCorroboration {
  const SessionCorroboration({
    required this.corroboration,
    required this.attemptsRead,
    this.incompleteAttempts = const [],
  });

  final ShadowCorroboration corroboration;
  final int attemptsRead;

  /// Attempts whose complete read was CUT at the ceiling. Their evidence is
  /// left out entirely — a prefix could deny a crash the tail would show —
  /// and the caller reports the session incomplete.
  final List<String> incompleteAttempts;
}

/// Reads and folds the corroboration for one session's [records].
Future<SessionCorroboration> readSessionCorroboration(
  TrajectoryLogReader reader,
  SubjectRecords records, {
  required Map<int, EpochEvidence> epochs,
  int ceiling = completeReadCeiling,
}) async {
  final attempts = <String, AttemptEvidence>{};
  final incomplete = <String>[];
  final ids = attemptIdsOf(records.records).toList()..sort();
  for (final attemptId in ids) {
    final stream = await reader.allRecordsForSubject(
      attemptId,
      ceiling: ceiling,
    );
    if (!stream.isComplete) {
      incomplete.add(attemptId);
      continue;
    }
    attempts[attemptId] = foldAttemptEvidence(attemptId, stream.records);
  }
  return SessionCorroboration(
    corroboration: ShadowCorroboration(attempts: attempts, epochs: epochs),
    attemptsRead: ids.length,
    incompleteAttempts: incomplete,
  );
}
