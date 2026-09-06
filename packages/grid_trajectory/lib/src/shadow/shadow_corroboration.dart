/// Corroboration for the §9 shadow comparator's named gaps (tg-ilug).
///
/// A mismatch whose fold side LAGS the ledger has more than one cause, and the
/// station itself can tell them apart:
///
///   * a crash between the legacy write and the trajectory append leaves the
///     attempt's own records lopsided — a `process.started` with no
///     `process.exited` of any provenance, a `lease.swept` written by the
///     SUCCESSOR boot over the predecessor's live breadcrumb, or a
///     `liveness.lost` the tick observed and nothing regained;
///   * a lost append that was NOT a crash is COUNTED by the recorder
///     (`dropped`, `suppressed` — stage1-wiring §2.5/§3) or shows as a claimed
///     boot epoch the log holds zero rows for (the station ran legacy-only);
///   * everything else is unexplained, which §9 already treats as blocking.
///
/// Before this module the classifiers named `non_atomic_crash` on the
/// DIRECTION of the mismatch alone, so the allow-listed, cut-clearing class
/// carried 97% of lunar's mismatch volume on a cause nothing verified. Here the
/// class has to EARN its name: a classifier receives the mismatch as a
/// [ShadowMismatchSubject] carrying the attempts and epochs it is joinable to,
/// and the [ShadowCorroboration] the verb assembled from the log, and it
/// answers with a [ShadowClassification] that names its basis so a reader can
/// audit one row without re-deriving it.
///
/// Pure: no I/O. The verb's reader-touching assembly lives in
/// `cli/shadow_corroboration_reader.dart`, so the folds and the classifier
/// stay drivable from fixtures.
library;

import 'package:meta/meta.dart';

import '../cli/shadow_accounting.dart';
import '../cli/traj_shadow_diff_command.dart';
import '../cli/trajectory_reader.dart';
import '../codec/codec_registry.dart';
import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';

/// The states the step lane can order. `pending` precedes `running`, which
/// precedes every terminal-ish state — enough to answer "is the fold BEHIND
/// the ledger", which is the only ordering question the direction test asks.
/// A state outside the vocabulary orders as unknown and is never called a lag.
const Map<String, int> stepStateProgress = {
  'pending': 0,
  'running': 1,
  'gated': 2,
  'ready': 3,
  'complete': 3,
  'failed': 3,
};

/// The crash shapes an attempt's own records can show, strongest first.
enum CrashShape {
  /// `attempt.process.started` with no `attempt.process.exited` of ANY
  /// provenance for the attempt: the station never observed the exit. An
  /// inferred exit (the one-turn vanish) is still the station's own
  /// observation and refutes this shape.
  startedWithoutExit('started without exit'),

  /// `attempt.lease.swept` for the attempt: the SUCCESSOR boot's sweep found
  /// the predecessor's live breadcrumb, so the predecessor epoch did not clean
  /// down.
  leaseSwept('lease swept by a successor boot'),

  /// `attempt.liveness.lost` the tick observed with no later `regained` and no
  /// exit. WEAK: the tick emits it only for a beat seen in the current epoch,
  /// so the station was alive and recording when it fired — it corroborates a
  /// wedged agent at least as much as a lost append. Ranked last and labelled.
  livenessLost('liveness lost, never regained (weak)');

  const CrashShape(this.label);

  final String label;
}

/// What the log holds about ONE attempt — the join target for the crash
/// shapes. Built by [foldAttemptEvidence] over the attempt's complete record
/// stream (a per-attempt subject read: `lease.swept` and `liveness.*`
/// correlate on `attempt_id` only and are invisible to a session read).
@immutable
final class AttemptEvidence {
  const AttemptEvidence({
    required this.attemptId,
    this.startedSeq,
    this.startedEpoch,
    this.exitedSeq,
    this.leaseSweptSeq,
    this.leaseSweptDisposition,
    this.livenessLostSeq,
    this.livenessRegainedAfterLost = false,
  });

  final String attemptId;
  final int? startedSeq;
  final int? startedEpoch;
  final int? exitedSeq;
  final int? leaseSweptSeq;
  final String? leaseSweptDisposition;
  final int? livenessLostSeq;
  final bool livenessRegainedAfterLost;

  /// The strongest crash shape the records support, or null when the attempt
  /// looks clean (started and exited, no sweep, no unregained loss).
  CrashShape? get crashShape {
    if (startedSeq != null && exitedSeq == null) {
      return CrashShape.startedWithoutExit;
    }
    if (leaseSweptSeq != null) return CrashShape.leaseSwept;
    if (livenessLostSeq != null && !livenessRegainedAfterLost) {
      return CrashShape.livenessLost;
    }
    return null;
  }

  /// The basis fragment a classification prints for this attempt's shape.
  String describe() {
    final shape = crashShape;
    if (shape == null) {
      return 'attempt $attemptId: '
          '${startedSeq == null ? 'no process record' : 'started@$startedSeq'}'
          '${exitedSeq == null ? '' : ', exited@$exitedSeq'}';
    }
    final at = switch (shape) {
      CrashShape.startedWithoutExit => 'started@$startedSeq',
      CrashShape.leaseSwept =>
        'swept@$leaseSweptSeq'
            '${leaseSweptDisposition == null ? '' : ' ($leaseSweptDisposition)'}',
      CrashShape.livenessLost => 'lost@$livenessLostSeq',
    };
    return 'attempt $attemptId: ${shape.label}, $at';
  }
}

/// What the log and the accounting say about ONE claimed boot epoch.
@immutable
final class EpochEvidence {
  const EpochEvidence({
    required this.epoch,
    required this.records,
    this.dropped,
    this.suppressed,
    this.accountingSource,
  });

  final int epoch;

  /// Rows the log holds for this epoch. Zero on a CLAIMED epoch is the
  /// dark-epoch shape: the station ran legacy-only (§3, "trajectory DOWN …
  /// shadow window not counting"), an uncounted loss that is not a crash.
  final int records;

  /// The recorder's own loss counters for this epoch, when they were handed
  /// to the verb FOR this epoch (`--dropped`/`--suppressed` with `--epoch`).
  /// Null means unknown — never zero by assumption.
  final int? dropped;
  final int? suppressed;
  final String? accountingSource;

  bool get dark => records == 0;

  bool get countedLoss => (dropped ?? 0) > 0 || (suppressed ?? 0) > 0;

  /// The basis fragment for a lost-append classification, or null when this
  /// epoch shows no loss.
  String? describeLoss() {
    if (countedLoss) {
      return 'epoch $epoch: recorder counted '
          '${dropped ?? 0} dropped / ${suppressed ?? 0} suppressed'
          '${accountingSource == null ? '' : ' ($accountingSource)'}';
    }
    if (dark) return 'epoch $epoch: claimed but holds zero records (dark)';
    return null;
  }
}

/// Everything the verb assembled that a classifier may join a mismatch to.
@immutable
final class ShadowCorroboration {
  const ShadowCorroboration({this.attempts = const {}, this.epochs = const {}});

  /// Nothing is known — every lag row classifies unexplained, and the basis
  /// says why.
  const ShadowCorroboration.none() : attempts = const {}, epochs = const {};

  final Map<String, AttemptEvidence> attempts;
  final Map<int, EpochEvidence> epochs;

  bool get isEmpty => attempts.isEmpty && epochs.isEmpty;
}

/// One mismatch as a classifier sees it: the values, the attempts and epochs
/// the row is joinable to, and the corroboration to join them against.
@immutable
final class ShadowMismatchSubject {
  const ShadowMismatchSubject({
    required this.field,
    required this.legacyValue,
    required this.foldValue,
    this.attemptIds = const {},
    this.epochs = const {},
    this.foldRecordSeq,
    this.corroboration = const ShadowCorroboration.none(),
  });

  final String field;
  final String? legacyValue;
  final String? foldValue;

  /// The attempts this row can be joined to — every attempt the session's
  /// stream names, plus the head's own.
  final Set<String> attemptIds;

  /// The boot epochs the session's records span.
  final Set<int> epochs;

  /// Set when the fold side is a record that LANDED but lacks the compared
  /// field (the mount lane's shape): a landed record cannot be a lost append,
  /// so the crash class is refuted by construction.
  final int? foldRecordSeq;

  final ShadowCorroboration corroboration;
}

/// A classifier's answer: the class AND the evidence that assigned it.
@immutable
final class ShadowClassification {
  const ShadowClassification(this.classification, this.basis);

  final ShadowMismatchClass classification;
  final String basis;
}

/// Classifies one mismatch against the §9 allow-list. Injectable — the
/// offline suite injects fakes — and widened from `(field, legacy, fold)` so
/// corroboration is possible through it at all (tg-ilug).
typedef ShadowMismatchClassifier =
    ShadowClassification Function(ShadowMismatchSubject subject);

/// The DIRECTION test the crash and lost-append classes both require: the fold
/// missing a fact the ledger already holds. The reverse (the fold ahead of the
/// incumbent) is never either class and stays unexplained.
bool foldLagsLedger(String field, String? legacyValue, String? foldValue) =>
    switch (field) {
      'presence' || 'step_presence' => legacyValue != null && foldValue == null,
      'status' => legacyValue == 'closed' && foldValue == 'open',
      'outcome' => legacyValue != null && foldValue == null,
      'held' => legacyValue == 'true' && foldValue == 'false',
      // The mount lane: the ledger counts remounts, the fold carries none.
      'legacy_attempt_count' => legacyValue != null && foldValue == null,
      'step_state' => switch ((
        stepStateProgress[legacyValue],
        stepStateProgress[foldValue],
      )) {
        (final int legacy, final int fold) => legacy > fold,
        _ => false,
      },
      _ => false,
    };

/// THE CORROBORATED CLASSIFIER — the default for every lane.
///
///   1. not a fold lag ⇒ unexplained;
///   2. the fold side is a LANDED record ⇒ unexplained (rule C — a landed
///      record was not lost);
///   3. any joinable attempt shows a crash shape ⇒ `non_atomic_crash`, basis
///      naming the strongest attempt and shape;
///   4. otherwise any joinable epoch shows a counted or dark loss ⇒
///      `lost_append`, basis naming the epoch and the counter;
///   5. otherwise ⇒ unexplained, basis stating what was checked.
ShadowClassification corroboratedGapClassifier(ShadowMismatchSubject subject) {
  if (!foldLagsLedger(subject.field, subject.legacyValue, subject.foldValue)) {
    return const ShadowClassification(
      ShadowMismatchClass.unexplained,
      'fold is not behind the ledger on this field',
    );
  }
  if (subject.foldRecordSeq case final int seq) {
    return ShadowClassification(
      ShadowMismatchClass.unexplained,
      'the fold record landed at seq $seq without this field — a landed '
      'record is not a lost append',
    );
  }
  final corroboration = subject.corroboration;
  AttemptEvidence? strongest;
  for (final id in subject.attemptIds) {
    final evidence = corroboration.attempts[id];
    final shape = evidence?.crashShape;
    if (evidence == null || shape == null) continue;
    if (strongest == null || shape.index < strongest.crashShape!.index) {
      strongest = evidence;
    }
  }
  if (strongest != null) {
    return ShadowClassification(
      ShadowMismatchClass.nonAtomicCrash,
      strongest.describe(),
    );
  }
  final epochs = subject.epochs.toList()..sort();
  for (final epoch in epochs) {
    final loss = corroboration.epochs[epoch]?.describeLoss();
    if (loss != null) {
      return ShadowClassification(ShadowMismatchClass.lostAppend, loss);
    }
  }
  final checked = <String>[
    if (subject.attemptIds.isEmpty)
      'no attempt to join'
    else
      for (final id in subject.attemptIds)
        corroboration.attempts[id]?.describe() ??
            'attempt $id: no records read',
    if (epochs.isEmpty)
      'no epoch to join'
    else
      'epochs ${epochs.join(',')}: '
          '${epochs.every((e) => corroboration.epochs.containsKey(e)) ? 'no counted loss, none dark' : 'accounting unknown'}',
  ];
  return ShadowClassification(
    ShadowMismatchClass.unexplained,
    corroboration.isEmpty
        ? 'no corroboration supplied'
        : 'no corroboration: ${checked.join('; ')}',
  );
}

/// Folds one attempt's COMPLETE record stream into its [AttemptEvidence].
/// Records for other attempts are ignored, so a session-wide stream can be
/// handed in too; the per-attempt read is what makes the sweep and liveness
/// rows visible at all.
AttemptEvidence foldAttemptEvidence(
  String attemptId,
  Iterable<TrajectoryEnvelope> records,
) {
  int? startedSeq;
  int? startedEpoch;
  int? exitedSeq;
  int? leaseSweptSeq;
  String? leaseSweptDisposition;
  int? livenessLostSeq;
  var regainedAfterLost = false;
  for (final envelope in records) {
    if (envelope.attemptId != attemptId) continue;
    if (envelope.family != TrajectoryFamily.attempt) continue;
    final record = TrajectoryCodec.decode(envelope);
    switch (record) {
      case AttemptProcessStarted():
        startedSeq ??= envelope.seq;
        startedEpoch ??= envelope.bootEpoch;
      case AttemptProcessExited():
        // Any provenance: an inferred exit is still the station's own
        // observation of the vanish.
        exitedSeq ??= envelope.seq;
      case AttemptLeaseTransition(:final phase, :final disposition):
        if (phase == LeasePhase.swept) {
          leaseSweptSeq ??= envelope.seq;
          leaseSweptDisposition ??= disposition?.wire;
        }
      case AttemptLivenessTransition(:final crossing):
        switch (crossing) {
          case LivenessCrossing.lost:
            livenessLostSeq = envelope.seq;
            regainedAfterLost = false;
          case LivenessCrossing.regained:
            if (livenessLostSeq != null) regainedAfterLost = true;
        }
      default:
        break;
    }
  }
  return AttemptEvidence(
    attemptId: attemptId,
    startedSeq: startedSeq,
    startedEpoch: startedEpoch,
    exitedSeq: exitedSeq,
    leaseSweptSeq: leaseSweptSeq,
    leaseSweptDisposition: leaseSweptDisposition,
    livenessLostSeq: livenessLostSeq,
    livenessRegainedAfterLost: regainedAfterLost,
  );
}

/// Folds the claimed epochs (with their record counts) and the run's
/// accounting into the per-epoch evidence. The accounting joins ONE epoch —
/// the one it names — and joins none when it names none: an unepoch'd counter
/// disqualifies the round (that rule is `ShadowRunAccounting`'s and stands)
/// but attributes nothing to a row.
Map<int, EpochEvidence> foldEpochEvidence({
  required List<EpochClaim> claims,
  ShadowRunAccounting? accounting,
}) {
  final epochs = <int, EpochEvidence>{};
  for (final claim in claims) {
    final joinsAccounting =
        accounting != null && accounting.epoch == claim.epoch;
    epochs[claim.epoch] = EpochEvidence(
      epoch: claim.epoch,
      records: claim.records,
      dropped: joinsAccounting ? accounting.dropped : null,
      suppressed: joinsAccounting ? accounting.suppressed : null,
      accountingSource: joinsAccounting ? '--dropped/--suppressed' : null,
    );
  }
  return epochs;
}

/// The attempts a session's stream names — every `attempt_id` on any envelope
/// plus [headAttemptId] when the fold's head carries one.
Set<String> attemptIdsOf(
  Iterable<TrajectoryEnvelope> records, {
  String? headAttemptId,
}) => {
  for (final envelope in records)
    if (envelope.attemptId case final String id) id,
  if (headAttemptId != null) headAttemptId,
};

/// The boot epochs a session's stream spans.
Set<int> epochsOf(Iterable<TrajectoryEnvelope> records) => {
  for (final envelope in records) envelope.bootEpoch,
};
