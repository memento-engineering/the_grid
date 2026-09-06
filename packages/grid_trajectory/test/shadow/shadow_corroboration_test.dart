// tg-ilug — the named-gap classes earn their names.
//
// Pure: fixture envelopes in, evidence and classifications out. The crash
// class is assigned only on an attempt's own records; the lost-append class
// only on a counted or dark epoch; everything else is unexplained WITH a basis
// that says what was checked.
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';

const String _session = 'tranquility-5xk';
const String _attempt = '01J8ATTEMPT000000000000002';

TrajectoryEnvelope _started({
  int seq = 1,
  int epoch = 3,
  String attemptId = _attempt,
  String stepPath = 'root.implement',
}) => envelope(
  recordType: 'attempt.process.started',
  family: TrajectoryFamily.attempt,
  seq: seq,
  bootEpoch: epoch,
  sessionId: _session,
  attemptId: attemptId,
  incarnation: 1,
  stepPath: stepPath,
  payload: const {'pid': 4242, 'pgid': 4242},
);

TrajectoryEnvelope _exited({
  int seq = 2,
  int epoch = 3,
  String attemptId = _attempt,
  bool inferred = false,
}) => envelope(
  recordType: 'attempt.process.exited',
  family: TrajectoryFamily.attempt,
  seq: seq,
  bootEpoch: epoch,
  sessionId: _session,
  attemptId: attemptId,
  provenance: inferred
      ? TrajectoryProvenance.inferred
      : TrajectoryProvenance.observed,
  payload: {
    'pid': 4242,
    'exit_code': 0,
    'exit_kind': 'exited',
    'inferred': inferred,
  },
);

TrajectoryEnvelope _swept({int seq = 5, int epoch = 4}) => envelope(
  recordType: 'attempt.lease.swept',
  family: TrajectoryFamily.attempt,
  seq: seq,
  bootEpoch: epoch,
  attemptId: _attempt,
  payload: const {'token': _attempt, 'disposition': 'killed'},
);

TrajectoryEnvelope _liveness(String crossing, {required int seq}) => envelope(
  recordType: 'attempt.liveness.$crossing',
  family: TrajectoryFamily.attempt,
  seq: seq,
  bootEpoch: 3,
  attemptId: _attempt,
  payload: const {
    'last_beat_at': '2026-08-31T11:58:03.000250Z',
    'threshold_ms': 90000,
  },
);

ShadowMismatchSubject _lag({
  String field = 'status',
  String? legacyValue = 'closed',
  String? foldValue = 'open',
  Set<String> attemptIds = const {_attempt},
  Set<int> epochs = const {3},
  int? foldRecordSeq,
  ShadowCorroboration corroboration = const ShadowCorroboration.none(),
}) => ShadowMismatchSubject(
  field: field,
  legacyValue: legacyValue,
  foldValue: foldValue,
  attemptIds: attemptIds,
  epochs: epochs,
  foldRecordSeq: foldRecordSeq,
  corroboration: corroboration,
);

void main() {
  group('foldAttemptEvidence', () {
    test('started with no exit of any provenance is the strongest crash '
        'shape', () {
      final evidence = foldAttemptEvidence(_attempt, [_started()]);
      expect(evidence.startedSeq, 1);
      expect(evidence.startedEpoch, 3);
      expect(evidence.exitedSeq, isNull);
      expect(evidence.crashShape, CrashShape.startedWithoutExit);
      expect(evidence.describe(), contains('started without exit'));
    });

    test('an INFERRED exit still refutes it — the vanish was observed', () {
      final evidence = foldAttemptEvidence(_attempt, [
        _started(),
        _exited(inferred: true),
      ]);
      expect(evidence.exitedSeq, 2);
      expect(evidence.crashShape, isNull);
    });

    test('a lease swept by the successor boot corroborates a crash', () {
      final evidence = foldAttemptEvidence(_attempt, [
        _started(),
        _exited(),
        _swept(),
      ]);
      expect(evidence.crashShape, CrashShape.leaseSwept);
      expect(evidence.leaseSweptDisposition, 'killed');
      expect(evidence.describe(), contains('killed'));
    });

    test('liveness lost and never regained is the WEAK shape; regained '
        'afterwards is nothing', () {
      final lost = foldAttemptEvidence(_attempt, [
        _started(),
        _exited(),
        _liveness('lost', seq: 3),
      ]);
      expect(lost.crashShape, CrashShape.livenessLost);
      expect(lost.describe(), contains('weak'));
      final regained = foldAttemptEvidence(_attempt, [
        _started(),
        _exited(),
        _liveness('lost', seq: 3),
        _liveness('regained', seq: 4),
      ]);
      expect(regained.crashShape, isNull);
    });

    test('records of OTHER attempts are ignored', () {
      final evidence = foldAttemptEvidence(_attempt, [
        _started(attemptId: '01J8ATTEMPT000000000000009'),
      ]);
      expect(evidence.startedSeq, isNull);
      expect(evidence.crashShape, isNull);
    });
  });

  group('foldEpochEvidence', () {
    const claims = [
      EpochClaim(station: 'lunar', epoch: 3, records: 40),
      EpochClaim(station: 'lunar', epoch: 4, records: 0),
      EpochClaim(station: 'lunar', epoch: 5, records: 7),
    ];

    test('a claimed epoch with zero rows is dark', () {
      final epochs = foldEpochEvidence(claims: claims);
      expect(epochs[4]!.dark, isTrue);
      expect(epochs[4]!.describeLoss(), contains('dark'));
      expect(epochs[3]!.dark, isFalse);
      expect(epochs[3]!.describeLoss(), isNull);
    });

    test('the accounting joins ONLY the epoch it names', () {
      final epochs = foldEpochEvidence(
        claims: claims,
        accounting: const ShadowRunAccounting(
          dropped: 2,
          suppressed: 0,
          epoch: 5,
        ),
      );
      expect(epochs[5]!.countedLoss, isTrue);
      expect(epochs[5]!.describeLoss(), contains('2 dropped'));
      expect(epochs[3]!.dropped, isNull, reason: 'unknown, never zero');
    });

    test('an un-epoch\'d accounting joins no row', () {
      final epochs = foldEpochEvidence(
        claims: claims,
        accounting: const ShadowRunAccounting(dropped: 2),
      );
      expect(epochs.values.every((e) => e.dropped == null), isTrue);
    });
  });

  group('corroboratedGapClassifier', () {
    test('a fold that is NOT behind the ledger is unexplained regardless of '
        'evidence', () {
      final subject = _lag(
        legacyValue: 'open',
        foldValue: 'closed',
        corroboration: ShadowCorroboration(
          attempts: {
            _attempt: foldAttemptEvidence(_attempt, [_started()]),
          },
        ),
      );
      final verdict = corroboratedGapClassifier(subject);
      expect(verdict.classification, ShadowMismatchClass.unexplained);
      expect(verdict.basis, contains('not behind'));
    });

    test('a crash shape on a joinable attempt earns non_atomic_crash, and '
        'the basis names the attempt', () {
      final verdict = corroboratedGapClassifier(
        _lag(
          corroboration: ShadowCorroboration(
            attempts: {
              _attempt: foldAttemptEvidence(_attempt, [_started()]),
            },
          ),
        ),
      );
      expect(verdict.classification, ShadowMismatchClass.nonAtomicCrash);
      expect(verdict.basis, contains(_attempt));
      expect(verdict.basis, contains('started without exit'));
    });

    test('the STRONGEST shape across the joinable attempts is the basis', () {
      const other = '01J8ATTEMPT000000000000009';
      final verdict = corroboratedGapClassifier(
        _lag(
          attemptIds: const {_attempt, other},
          corroboration: ShadowCorroboration(
            attempts: {
              _attempt: foldAttemptEvidence(_attempt, [
                _started(),
                _exited(),
                _liveness('lost', seq: 3),
              ]),
              other: foldAttemptEvidence(other, [
                _started(seq: 9, attemptId: other),
              ]),
            },
          ),
        ),
      );
      expect(verdict.basis, contains(other));
      expect(verdict.basis, contains('started without exit'));
    });

    test('no crash shape but a counted loss in a joinable epoch is '
        'lost_append', () {
      final verdict = corroboratedGapClassifier(
        _lag(
          corroboration: ShadowCorroboration(
            attempts: {
              _attempt: foldAttemptEvidence(_attempt, [_started(), _exited()]),
            },
            epochs: foldEpochEvidence(
              claims: const [
                EpochClaim(station: 'lunar', epoch: 3, records: 12),
              ],
              accounting: const ShadowRunAccounting(
                dropped: 0,
                suppressed: 4,
                epoch: 3,
              ),
            ),
          ),
        ),
      );
      expect(verdict.classification, ShadowMismatchClass.lostAppend);
      expect(verdict.basis, contains('4 suppressed'));
    });

    test('a dark epoch in the session\'s span is lost_append too', () {
      final verdict = corroboratedGapClassifier(
        _lag(
          epochs: const {3, 4},
          corroboration: ShadowCorroboration(
            epochs: foldEpochEvidence(
              claims: const [
                EpochClaim(station: 'lunar', epoch: 3, records: 12),
                EpochClaim(station: 'lunar', epoch: 4, records: 0),
              ],
            ),
          ),
        ),
      );
      expect(verdict.classification, ShadowMismatchClass.lostAppend);
      expect(verdict.basis, contains('epoch 4'));
      expect(verdict.basis, contains('dark'));
    });

    test('a crash shape outranks a counted loss', () {
      final verdict = corroboratedGapClassifier(
        _lag(
          corroboration: ShadowCorroboration(
            attempts: {
              _attempt: foldAttemptEvidence(_attempt, [_started()]),
            },
            epochs: foldEpochEvidence(
              claims: const [
                EpochClaim(station: 'lunar', epoch: 3, records: 0),
              ],
            ),
          ),
        ),
      );
      expect(verdict.classification, ShadowMismatchClass.nonAtomicCrash);
    });

    test('a clean attempt and a clean epoch is UNEXPLAINED, and the basis '
        'says what was checked', () {
      final verdict = corroboratedGapClassifier(
        _lag(
          corroboration: ShadowCorroboration(
            attempts: {
              _attempt: foldAttemptEvidence(_attempt, [_started(), _exited()]),
            },
            epochs: foldEpochEvidence(
              claims: const [
                EpochClaim(station: 'lunar', epoch: 3, records: 12),
              ],
              accounting: const ShadowRunAccounting(dropped: 0, epoch: 3),
            ),
          ),
        ),
      );
      expect(verdict.classification, ShadowMismatchClass.unexplained);
      expect(verdict.basis, contains('exited@2'));
      expect(verdict.basis, contains('no counted loss'));
    });

    test('no corroboration at all is unexplained with a basis saying so', () {
      final verdict = corroboratedGapClassifier(_lag());
      expect(verdict.classification, ShadowMismatchClass.unexplained);
      expect(verdict.basis, 'no corroboration supplied');
    });

    test('a row with nothing to join says so', () {
      final verdict = corroboratedGapClassifier(
        _lag(
          field: 'presence',
          legacyValue: 'present',
          foldValue: null,
          attemptIds: const {},
          epochs: const {},
          corroboration: ShadowCorroboration(
            epochs: foldEpochEvidence(
              claims: const [
                EpochClaim(station: 'lunar', epoch: 3, records: 12),
              ],
            ),
          ),
        ),
      );
      expect(verdict.classification, ShadowMismatchClass.unexplained);
      expect(verdict.basis, contains('no attempt to join'));
      expect(verdict.basis, contains('no epoch to join'));
    });

    test('a LANDED record missing the field is never a lost append (the '
        'mount lane\'s shape)', () {
      final verdict = corroboratedGapClassifier(
        _lag(
          field: 'presence',
          legacyValue: '3',
          foldValue: null,
          foldRecordSeq: 17,
          corroboration: ShadowCorroboration(
            attempts: {
              _attempt: foldAttemptEvidence(_attempt, [_started()]),
            },
          ),
        ),
      );
      expect(verdict.classification, ShadowMismatchClass.unexplained);
      expect(verdict.basis, contains('landed at seq 17'));
    });

    test('the direction test covers every lane\'s lag fields', () {
      expect(foldLagsLedger('status', 'closed', 'open'), isTrue);
      expect(foldLagsLedger('status', 'open', 'closed'), isFalse);
      expect(foldLagsLedger('outcome', 'succeeded', null), isTrue);
      expect(foldLagsLedger('held', 'true', 'false'), isTrue);
      expect(foldLagsLedger('presence', 'present', null), isTrue);
      expect(foldLagsLedger('presence', null, 'present'), isFalse);
      expect(foldLagsLedger('step_presence', 'present', null), isTrue);
      expect(foldLagsLedger('step_state', 'complete', 'running'), isTrue);
      expect(foldLagsLedger('step_state', 'running', 'complete'), isFalse);
      expect(foldLagsLedger('step_state', 'weird', 'running'), isFalse);
      expect(foldLagsLedger('legacy_attempt_count', '3', null), isTrue);
      expect(foldLagsLedger('cooldown_until', 'a', 'b'), isFalse);
    });
  });
}
