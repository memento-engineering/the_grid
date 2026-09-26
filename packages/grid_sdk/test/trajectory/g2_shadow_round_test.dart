import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

G2ShadowRoundAdapter _adapter(
  DualReadStepObserver observer, {
  int Function()? appendDivergences,
  void Function(String, Map<String, String>)? flare,
  void Function(G2ShadowRoundDiagnostic)? onRound,
}) => G2ShadowRoundAdapter(
  observer: observer,
  appendDivergences: appendDivergences ?? () => 0,
  flare: flare ?? (_, _) {},
  onRound: onRound,
);

void main() {
  test('corroborated crash gap is named', () async {
    final observer = DualReadStepObserver(mode: DualReadMode.observe);
    G2ShadowRoundDiagnostic? diagnostic;
    final result =
        await _adapter(
          observer,
          onRound: (value) => diagnostic = value,
        ).compare(
          sessionId: 'session-1',
          round: 2,
          headEpoch: 10,
          legacyWritePresent: true,
          appendPresent: false,
          attemptIds: const {'attempt-1'},
          corroboration: const ShadowCorroboration(
            attempts: {
              'attempt-1': AttemptEvidence(
                attemptId: 'attempt-1',
                startedSeq: 4,
              ),
            },
          ),
        );

    expect(
      result.mismatches.single.classification,
      ShadowMismatchClass.nonAtomicCrash,
    );
    expect(
      observer.accounting.g2Snapshot.mismatch(
        DualReadDivergenceCause.nonAtomicCrashGap,
      ),
      1,
    );
    expect(
      observer.accounting.g2Snapshot.mismatch(
        DualReadDivergenceCause.unexplained,
      ),
      0,
    );
    expect(
      diagnostic!.mismatches.single.mismatchKey,
      contains('append_presence'),
    );
  });

  test('unexplained never becomes fallback success', () async {
    final observer = DualReadStepObserver(mode: DualReadMode.observe);
    final adapter = _adapter(observer);
    final mismatch = await adapter.compare(
      sessionId: 'session-1',
      round: 2,
      headEpoch: 10,
      legacyWritePresent: true,
      appendPresent: false,
    );
    expect(mismatch.isIncomplete, isFalse);
    expect(
      observer.accounting.g2Snapshot.mismatch(
        DualReadDivergenceCause.unexplained,
      ),
      1,
    );
    expect(observer.accounting.stepUnexplainedDivergences, 0);
    expect(observer.accounting.stepFallbacks, 0);
    expect(
      observer.accounting.g2Snapshot.failure(
        G2ShadowFailureKind.projectionFallback,
      ),
      0,
    );

    final fallback = await adapter.compare(
      sessionId: 'session-2',
      round: 0,
      headEpoch: 10,
      projectionAvailable: false,
    );
    expect(fallback.isIncomplete, isTrue);
    expect(fallback.mismatches, isEmpty);
    expect(
      observer.accounting.g2Snapshot.failure(
        G2ShadowFailureKind.projectionFallback,
      ),
      1,
    );
    expect(
      observer.accounting.g2Snapshot.mismatch(
        DualReadDivergenceCause.unexplained,
      ),
      1,
    );
  });

  test(
    'append fold and comparison failures stay non-fatal diagnostics',
    () async {
      final observer = DualReadStepObserver(mode: DualReadMode.observe);
      final flares = <String>[];
      var appendDivergences = 0;
      var throwComparison = false;
      final adapter = _adapter(
        observer,
        appendDivergences: () {
          if (throwComparison) throw StateError('comparison boom');
          return appendDivergences;
        },
        flare: (name, _) => flares.add(name),
      );
      appendDivergences = 1;
      final fold = await adapter.compare(
        sessionId: 'session-1',
        round: 1,
        headEpoch: 10,
        foldComplete: false,
      );
      expect(fold.isIncomplete, isTrue);
      expect(
        observer.accounting.g2Snapshot.failure(
          G2ShadowFailureKind.appendFailure,
        ),
        1,
      );
      expect(
        observer.accounting.g2Snapshot.failure(G2ShadowFailureKind.foldFailure),
        1,
      );
      expect(flares, contains('trajectory.staleFold'));

      throwComparison = true;
      final comparison = await adapter.compare(
        sessionId: 'session-2',
        round: 1,
        headEpoch: 10,
      );
      expect(comparison.isIncomplete, isTrue);
      expect(
        observer.accounting.g2Snapshot.failure(
          G2ShadowFailureKind.comparisonFailure,
        ),
        1,
      );
      expect(flares, contains('trajectory.g2ShadowComparisonFailure'));
    },
  );
}
