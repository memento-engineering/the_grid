import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

DualReadComparison _comparison({
  required String sessionId,
  required DualReadClass classification,
  String? field,
}) => DualReadComparison(
  sessionId: sessionId,
  workBeadId: 'bead-$sessionId',
  classification: classification,
  mismatches: field == null
      ? const <DualReadFieldMismatch>[]
      : <DualReadFieldMismatch>[
          DualReadFieldMismatch(
            field: field,
            foldValue: 'fold',
            legacyValue: 'legacy',
          ),
        ],
);

void _recordDivergences(DualReadAccounting accounting) {
  const epochs = <int>[9, 10, 11];
  for (final epoch in epochs) {
    for (final cause in <DualReadDivergenceCause>[
      DualReadDivergenceCause.operatorStoreEdit,
      DualReadDivergenceCause.foldBackedMountFacts,
      DualReadDivergenceCause.unexplained,
    ]) {
      accounting.record(
        _comparison(
          sessionId: 'session-${cause.name}-$epoch',
          classification: DualReadClass.divergence,
          field: cause.name,
        ),
        cause: cause,
        headEpoch: epoch,
      );
    }
    for (final cause in <DualReadDivergenceCause>[
      DualReadDivergenceCause.operatorStoreEdit,
      DualReadDivergenceCause.foldAheadOfLegacy,
      DualReadDivergenceCause.unexplained,
    ]) {
      accounting.recordStepDivergence(
        sessionId: 'step-session-${cause.name}-$epoch',
        stepPath: 'step-${cause.name}-$epoch',
        field: 'state',
        legacyValue: 'running',
        foldValue: 'complete',
        cause: cause,
        headEpoch: epoch,
      );
    }
  }
}

final class _EmptySnapshot implements TrajectoryHeadSnapshot {
  const _EmptySnapshot({this.firstEpochClaimedAt});

  @override
  int get version => 1;

  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;

  @override
  DateTime? get seededAt => null;

  @override
  final DateTime? firstEpochClaimedAt;

  @override
  SessionHeadView? bySessionId(String sessionId) => null;

  @override
  SessionHeadWinner byWorkBead(String workBeadId) =>
      const SessionHeadNone(retiredOpenRows: 0);

  @override
  Iterable<SessionHeadView> get rows => const <SessionHeadView>[];
}

final class _EpochHead implements EpochScopedSessionHeadView {
  const _EpochHead({required this.sessionId, required this.headEpoch});

  @override
  final String sessionId;
  @override
  final int headEpoch;
  @override
  String get workBeadId => 'shared-bead';
  @override
  int get round => 0;
  @override
  bool get isOpen => true;
  @override
  SessionHeadOutcome? get outcome => null;
  @override
  bool get held => false;
  @override
  String? get heldReason => null;
  @override
  String? get workTerminalReason => null;
  @override
  int? get pgid => null;
  @override
  int? get pid => null;
  @override
  String? get attemptId => null;
  @override
  SessionHeadProvenance? get terminalProvenance => null;
  @override
  String? get unknownReason => null;
  @override
  DateTime get startedAt => DateTime.utc(2026, 9, 1);
  @override
  DateTime? get closedAt => null;
  @override
  int get lastSeq => 1;
}

final class _RowsSnapshot implements TrajectoryHeadSnapshot {
  const _RowsSnapshot(this._rows);

  final List<SessionHeadView> _rows;
  @override
  int get version => 1;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => null;
  @override
  DateTime? get firstEpochClaimedAt => DateTime.utc(2026, 9, 1);
  @override
  SessionHeadView? bySessionId(String sessionId) {
    for (final row in _rows) {
      if (row.sessionId == sessionId) return row;
    }
    return null;
  }

  @override
  SessionHeadWinner byWorkBead(String workBeadId) =>
      sessionHeadWinnerOf(_rows.where((row) => row.workBeadId == workBeadId));
  @override
  Iterable<SessionHeadView> get rows => _rows;
}

void main() {
  test('zero window preserves every existing counter', () {
    final implicit = DualReadAccounting()..beginPass();
    final explicit = DualReadAccounting(soakWindowEpoch: 0)..beginPass();
    _recordDivergences(implicit);
    _recordDivergences(explicit);
    for (final accounting in <DualReadAccounting>[implicit, explicit]) {
      accounting
        ..recordPostEpochMiss('missing-session')
        ..beginStepPass()
        ..recordP2Misses(
          sessionId: 'missing-step-session',
          count: 3,
          headEpoch: 72,
        );
    }

    final implicitJson = implicit.toCertificationJson();
    final explicitJson = explicit.toCertificationJson();
    const existingKeys = <String>[
      'passes',
      'hits',
      'miss_post_epoch',
      'miss_legacy_era',
      'fallbacks',
      'divergences',
      'operator_store_edit_divergences',
      'fold_backed_mount_fact_divergences',
      'unexplained_divergences',
      'p2_miss',
      'step_divergences',
      'step_operator_store_edit_divergences',
      'step_unexplained_divergences',
      'step_fold_ahead_of_legacy_divergences',
    ];
    for (final key in existingKeys) {
      expect(explicitJson[key], implicitJson[key], reason: key);
    }
    expect(explicitJson['divergences_in_window'], explicit.divergences);
    expect(explicitJson['divergences_historical'], 0);
    expect(
      explicitJson['step_divergences_in_window'],
      explicit.stepDivergences,
    );
    expect(explicitJson['step_divergences_historical'], 0);
    expect(explicit.p2MissTotal, explicit.p2Miss);
  });

  test('three epochs partition every cumulative divergence counter', () {
    final accounting = DualReadAccounting(soakWindowEpoch: 10);
    _recordDivergences(accounting);
    final json = accounting.toCertificationJson();
    const totals = <String, int>{
      'divergences': 9,
      'operator_store_edit_divergences': 3,
      'fold_backed_mount_fact_divergences': 3,
      'unexplained_divergences': 3,
      'step_divergences': 9,
      'step_operator_store_edit_divergences': 3,
      'step_unexplained_divergences': 3,
      'step_fold_ahead_of_legacy_divergences': 3,
    };
    for (final entry in totals.entries) {
      final inWindow = json['${entry.key}_in_window']! as int;
      final historical = json['${entry.key}_historical']! as int;
      expect(json[entry.key], entry.value, reason: entry.key);
      expect(inWindow + historical, entry.value, reason: entry.key);
      expect(inWindow, entry.value * 2 ~/ 3, reason: entry.key);
    }

    final allFields = json['divergences_by_field']! as Map<String, int>;
    final windowFields =
        json['divergences_by_field_in_window']! as Map<String, int>;
    final historicalFields =
        json['divergences_by_field_historical']! as Map<String, int>;
    for (final entry in allFields.entries) {
      expect(windowFields[entry.key], 2, reason: entry.key);
      expect(historicalFields[entry.key], 1, reason: entry.key);
      expect(
        windowFields[entry.key]! + historicalFields[entry.key]!,
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('miss totals survive pass resets and dedupe by session', () {
    final accounting = DualReadAccounting(soakWindowEpoch: 10)
      ..beginPass()
      ..beginStepPass()
      ..recordPostEpochMiss('session-a')
      ..recordPostEpochMiss('session-a')
      ..recordP2Misses(sessionId: 'p2-a', count: 3, headEpoch: 10)
      ..recordP2Misses(sessionId: 'p2-a', count: 3, headEpoch: 10);
    expect(accounting.missPostEpoch, 2);
    expect(accounting.missPostEpochTotal, 1);
    expect(accounting.p2Miss, 6);
    expect(accounting.p2MissTotal, 3);

    accounting
      ..beginPass()
      ..beginStepPass()
      ..recordPostEpochMiss('session-a')
      ..recordPostEpochMiss('session-b')
      ..recordP2Misses(sessionId: 'p2-a', count: 3, headEpoch: 10)
      ..recordP2Misses(sessionId: 'p2-b', count: 2, headEpoch: 11)
      ..recordP2Misses(sessionId: 'p2-historical', count: 7, headEpoch: 9);
    expect(accounting.missPostEpoch, 2);
    expect(accounting.missPostEpochTotal, 2);
    expect(accounting.p2Miss, 12);
    expect(accounting.p2MissTotal, 5);
  });

  test('lag and cardinality rows partition at the soak epoch', () {
    final accounting = DualReadAccounting(soakWindowEpoch: 10)..beginPass();
    for (final epoch in <int>[9, 10, 11]) {
      accounting
        ..record(
          _comparison(
            sessionId: 'terminal-$epoch',
            classification: DualReadClass.terminalLag,
          ),
          headEpoch: epoch,
        )
        ..record(
          _comparison(
            sessionId: 'retirement-$epoch',
            classification: DualReadClass.retirementLag,
          ),
          headEpoch: epoch,
        )
        ..record(
          _comparison(
            sessionId: 'cardinality-$epoch',
            classification: DualReadClass.cardinality,
          ),
          headEpoch: epoch,
        );
    }
    final json = accounting.toCertificationJson();
    for (final key in <String>[
      'terminal_lag_open',
      'retirement_lag_open',
      'cardinality_breaches',
    ]) {
      expect(json[key], 3, reason: key);
      expect(json['${key}_in_window'], 2, reason: key);
      expect(json['${key}_historical'], 1, reason: key);
    }

    accounting.beginPass();
    final reset = accounting.toCertificationJson();
    expect(reset['terminal_lag_open_in_window'], 0);
    expect(reset['terminal_lag_open_historical'], 0);
    expect(reset['retirement_lag_open_in_window'], 0);
    expect(reset['retirement_lag_open_historical'], 0);
    expect(reset['cardinality_breaches'], 3, reason: 'cumulative survives');

    final mixed = DualReadAccounting(soakWindowEpoch: 10);
    DualReadSessionObserver(
      mode: DualReadMode.observe,
      accounting: mixed,
    ).observe(
      const <String, SessionProjection>{
        'first': SessionProjection(
          workBeadId: 'shared-bead',
          sessionId: 'first',
        ),
        'second': SessionProjection(
          workBeadId: 'shared-bead',
          sessionId: 'second',
        ),
      },
      const _RowsSnapshot(<SessionHeadView>[
        _EpochHead(sessionId: 'first', headEpoch: 9),
        _EpochHead(sessionId: 'second', headEpoch: 10),
      ]),
    );
    expect(mixed.cardinalityBreaches, 1);
    expect(
      mixed.cardinalityBreachesInWindow,
      1,
      reason: 'the maximum implicated current-head epoch scopes the breach',
    );
  });

  test('null startedAt and unseeded anchor stay visible', () {
    final epochAt = DateTime.utc(2026, 9, 1);
    final accounting = DualReadAccounting();
    final observer = DualReadSessionObserver(
      mode: DualReadMode.observe,
      accounting: accounting,
    );
    observer.observe(const <String, SessionProjection>{
      'tg-1': SessionProjection(workBeadId: 'tg-1', sessionId: 'session-1'),
    }, _EmptySnapshot(firstEpochClaimedAt: epochAt));
    expect(accounting.nullStartedAt, 1);
    expect(accounting.missLegacyEra, 1);
    expect(accounting.missPostEpoch, 0);

    final unseeded = classifyDualReadMiss(
      SessionProjection(
        workBeadId: 'tg-2',
        sessionId: 'session-2',
        startedAt: epochAt.add(const Duration(hours: 1)),
      ),
      null,
    );
    expect(unseeded.era, DualReadMissClass.legacyEra);
    expect(accounting.toCertificationJson()['first_epoch_claimed_at'], isNull);
    expect(
      accounting.toCertificationJson(
        firstEpochClaimedAt: epochAt,
      )['first_epoch_claimed_at'],
      epochAt.toIso8601String(),
    );
  });

  test('summary exposes the complete certification shape', () {
    final json = DualReadAccounting(soakWindowEpoch: 10).toJson(
      mode: DualReadMode.observe,
      health: TrajectorySnapshotHealth.live,
      snapshotVersion: 1,
    );
    expect(
      json.keys,
      containsAll(<String>[
        'soak_window_epoch',
        'miss_post_epoch_total',
        'p2_miss_total',
        'divergences_in_window',
        'divergences_historical',
        'divergences_by_field_in_window',
        'divergences_by_field_historical',
        'operator_store_edit_divergences_in_window',
        'operator_store_edit_divergences_historical',
        'fold_backed_mount_fact_divergences_in_window',
        'fold_backed_mount_fact_divergences_historical',
        'unexplained_divergences_in_window',
        'unexplained_divergences_historical',
        'terminal_lag_open_in_window',
        'terminal_lag_open_historical',
        'retirement_lag_open_in_window',
        'retirement_lag_open_historical',
        'cardinality_breaches_in_window',
        'cardinality_breaches_historical',
        'step_divergences_in_window',
        'step_divergences_historical',
        'step_operator_store_edit_divergences_in_window',
        'step_operator_store_edit_divergences_historical',
        'step_unexplained_divergences_in_window',
        'step_unexplained_divergences_historical',
        'step_fold_ahead_of_legacy_divergences_in_window',
        'step_fold_ahead_of_legacy_divergences_historical',
        'null_started_at',
        'first_epoch_claimed_at',
        'append_ack_p99_ms',
      ]),
    );
    final semantics = json['counter_semantics']! as Map<String, String>;
    expect(semantics['divergences_by_field'], 'cumulative');
    expect(
      semantics,
      isNot(containsPair('divergences_by_field_in_window', anything)),
      reason: 'the scoped maps inherit the legacy map row semantics',
    );
    expect(
      semantics,
      isNot(containsPair('divergences_by_field_historical', anything)),
      reason: 'the scoped maps inherit the legacy map row semantics',
    );
  });
}
