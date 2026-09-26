/// G2's report-only adapter around the station's incumbent dual-read observer.
///
/// This type owns no comparator state beyond the recorder counter cursor. It
/// translates typed G2 round values into [DualReadStepObserver] calls, emits
/// non-fatal flares, and publishes immutable diagnostics. It deliberately has
/// no clean-round streak and produces no certificate artifact.
library;

import 'dart:math' as math;

import 'package:grid_engine/grid_engine.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:meta/meta.dart';

typedef G2ShadowAppendDivergences = int Function();
typedef G2ShadowRoundSink = void Function(G2ShadowRoundDiagnostic diagnostic);

/// Positive counter movement observed during one G2 comparison.
@immutable
final class G2ShadowCounterDelta {
  G2ShadowCounterDelta({
    required Map<G2ShadowFailureKind, int> failures,
    required Map<DualReadDivergenceCause, int> mismatches,
  }) : failures = Map.unmodifiable(failures),
       mismatches = Map.unmodifiable(mismatches);

  final Map<G2ShadowFailureKind, int> failures;
  final Map<DualReadDivergenceCause, int> mismatches;

  bool get isEmpty => failures.isEmpty && mismatches.isEmpty;
}

/// One report row's identity, keyed findings, and positive counter movement.
@immutable
final class G2ShadowRoundDiagnostic {
  G2ShadowRoundDiagnostic({
    required this.sessionId,
    required this.round,
    required this.headEpoch,
    required Iterable<DualReadDivergenceDetail> mismatches,
    required this.delta,
    this.incompleteReason,
  }) : mismatches = List.unmodifiable(mismatches);

  final String sessionId;
  final int round;
  final int headEpoch;
  final List<DualReadDivergenceDetail> mismatches;
  final G2ShadowCounterDelta delta;
  final String? incompleteReason;
}

/// Adapts one G2 round into the existing dual-read accounting and flare path.
final class G2ShadowRoundAdapter {
  G2ShadowRoundAdapter({
    required DualReadStepObserver observer,
    required G2ShadowAppendDivergences appendDivergences,
    required DualReadFlareSink flare,
    G2ShadowRoundSink? onRound,
  }) : _observer = observer,
       _appendDivergences = appendDivergences,
       _flare = flare,
       _onRound = onRound,
       _lastAppendDivergences = appendDivergences();

  final DualReadStepObserver _observer;
  final G2ShadowAppendDivergences _appendDivergences;
  final DualReadFlareSink _flare;
  final G2ShadowRoundSink? _onRound;
  int _lastAppendDivergences;

  /// Compares one round. Every failure remains diagnostic and returns a
  /// partial [ShadowCompareResult]; it never throws into the legacy run.
  Future<ShadowCompareResult> compare({
    required String sessionId,
    required int round,
    required int headEpoch,
    G2MoleculeObservation? molecule,
    Iterable<G2SuccessorObservation> successors = const [],
    bool foldComplete = true,
    bool projectionAvailable = true,
    bool legacyWritePresent = false,
    bool appendPresent = true,
    Set<String> attemptIds = const {},
    Set<int> epochs = const {},
    ShadowCorroboration corroboration = const ShadowCorroboration.none(),
  }) async {
    if (!_observer.armed) return const ShadowCompareResult([]);
    final before = _observer.accounting.g2Snapshot;
    final firstDetail = _observer.accounting.divergenceDetails.length;
    final incomplete = <String>[];

    try {
      final appendNow = _appendDivergences();
      final appendFailures = math.max(0, appendNow - _lastAppendDivergences);
      _lastAppendDivergences = appendNow;
      for (var index = 0; index < appendFailures; index++) {
        _observer.accounting.recordG2Failure(
          G2ShadowFailureKind.appendFailure,
          headEpoch: headEpoch,
        );
      }

      if (!foldComplete) {
        _observer.accounting.recordG2Failure(
          G2ShadowFailureKind.foldFailure,
          headEpoch: headEpoch,
        );
        _emit('trajectory.staleFold', {
          'sessionId': sessionId,
          'round': '$round',
        });
        incomplete.add('the G2 fold is incomplete');
      }
      if (!projectionAvailable) {
        _observer.accounting.recordG2Failure(
          G2ShadowFailureKind.projectionFallback,
          headEpoch: headEpoch,
        );
        incomplete.add('the G2 projection is absent');
      }

      if (legacyWritePresent && !appendPresent) {
        final classification = corroboratedGapClassifier(
          ShadowMismatchSubject(
            field: 'g2_append_presence',
            legacyValue: 'present',
            foldValue: 'absent',
            attemptIds: attemptIds,
            epochs: epochs,
            corroboration: corroboration,
          ),
        );
        final cause =
            classification.classification == ShadowMismatchClass.nonAtomicCrash
            ? DualReadDivergenceCause.nonAtomicCrashGap
            : DualReadDivergenceCause.unexplained;
        _observer.accounting.recordG2Mismatch(
          mismatchKey:
              'g2:molecule:$sessionId:$round:trajectory-append:'
              'record:record:append_presence',
          sessionId: sessionId,
          coordinate: 'trajectory-append',
          field: 'append_presence',
          legacyValue: 'present',
          foldValue: 'absent',
          cause: cause,
          headEpoch: headEpoch,
        );
      }

      if (foldComplete && projectionAvailable) {
        _observer.observeG2Round(molecule, successors, headEpoch: headEpoch);
      }
    } on Object catch (error) {
      _observer.accounting.recordG2Failure(
        G2ShadowFailureKind.comparisonFailure,
        headEpoch: headEpoch,
      );
      _emit('trajectory.g2ShadowComparisonFailure', {
        'sessionId': sessionId,
        'round': '$round',
        'reason': '$error',
      });
      incomplete.add('G2 comparison failed: $error');
    }

    final details = _observer.accounting.divergenceDetails
        .skip(firstDetail)
        .toList(growable: false);
    final after = _observer.accounting.g2Snapshot;
    final diagnostic = G2ShadowRoundDiagnostic(
      sessionId: sessionId,
      round: round,
      headEpoch: headEpoch,
      mismatches: details,
      delta: _delta(before, after),
      incompleteReason: incomplete.isEmpty ? null : incomplete.join('; '),
    );
    try {
      _onRound?.call(diagnostic);
    } on Object {
      // Emit-only diagnostics never break the legacy path.
    }

    final rows = [
      for (final detail in details)
        ShadowMismatch(
          sessionId: detail.sessionId,
          stepPath: detail.activeStepPath,
          field: detail.field,
          legacyValue: detail.legacyValue,
          foldValue: detail.foldValue,
          seq: null,
          classification:
              detail.cause == DualReadDivergenceCause.nonAtomicCrashGap
              ? ShadowMismatchClass.nonAtomicCrash
              : ShadowMismatchClass.unexplained,
          basis: '${detail.cause.wire}; ${detail.mismatchKey}',
        ),
    ];
    if (incomplete.isEmpty) return ShadowCompareResult(rows);
    return ShadowCompareResult.partial(rows, incomplete.join('; '));
  }

  G2ShadowCounterDelta _delta(
    G2ShadowCounterSnapshot before,
    G2ShadowCounterSnapshot after,
  ) => G2ShadowCounterDelta(
    failures: {
      for (final kind in G2ShadowFailureKind.values)
        if (after.failure(kind) - before.failure(kind) > 0)
          kind: after.failure(kind) - before.failure(kind),
    },
    mismatches: {
      for (final cause in DualReadDivergenceCause.values)
        if (after.mismatch(cause) - before.mismatch(cause) > 0)
          cause: after.mismatch(cause) - before.mismatch(cause),
    },
  );

  void _emit(String name, Map<String, String> data) {
    try {
      _flare(name, data);
    } on Object {
      // Emit-only, matching the trajectory harness flare convention.
    }
  }
}
