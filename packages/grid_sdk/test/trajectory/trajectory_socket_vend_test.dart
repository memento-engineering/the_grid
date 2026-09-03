// The harness's sockets are tracked until their close is confirmed, and the
// vended StoreConnection retires whatever shutdown could not.
import 'dart:async';
import 'dart:io';

import 'package:grid_sdk/grid_sdk.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

/// A [TrajectoryDb] that lives in a shared ledger of open handles. It leaves
/// the ledger only when its own [close] completes.
final class _LedgerDb implements TrajectoryDb {
  _LedgerDb(this._ledger) {
    _ledger.add(this);
  }

  final Set<_LedgerDb> _ledger;

  /// Refuses the next [failCloses] close attempts.
  int failCloses = 0;

  /// Hangs the next [hangCloses] close attempts forever.
  int hangCloses = 0;

  @override
  Future<SqlResult> execute(String sql, [Map<String, dynamic>? params]) async =>
      const SqlResult();

  @override
  Future<void> close() async {
    if (hangCloses > 0) {
      hangCloses -= 1;
      await Completer<void>().future;
    }
    if (failCloses > 0) {
      failCloses -= 1;
      throw StateError('close refused');
    }
    _ledger.remove(this);
  }
}

/// Every append fails internally: the result sets the reconnect flag, and the
/// next append dials fresh and retires the dead session.
final class _FakeAppender extends TrajectoryAppender {
  _FakeAppender(TrajectoryDb db) : super(db: db, station: 'tranquility');

  @override
  Future<AppendCorruptionHalt?> verifyBeltAtBoot() async => null;

  @override
  Future<EpochClaimOutcome> claimEpoch({
    required int pid,
    required int pgid,
    String cause = 'boot',
    int maxAttempts = 3,
  }) async => const EpochClaimed(epoch: 1);

  @override
  Future<AppendOutcome> append(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
    String? source,
    int? fencingToken,
  }) async => AppendInternalError(cause: StateError('socket died'));

  @override
  Future<void> doltCommitIfDue() async {}

  @override
  Future<ReconnectOutcome> reconnect(TrajectoryDb db) async =>
      const ReconnectResumed(epoch: 1);
}

final class _FakeTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => false;

  @override
  int get tick => 0;
}

TrajectoryAppendRequest _note(int ordinal) => TrajectoryAppendRequest(
  AttemptNote(
    sessionId: 's-1',
    body: 'note $ordinal',
    channel: 'test',
    noteOrdinal: ordinal,
  ),
);

void main() {
  late Directory tmp;
  late Set<_LedgerDb> ledger;
  late List<_LedgerDb> dialled;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('trajectory-socket-vend-');
    ledger = <_LedgerDb>{};
    dialled = <_LedgerDb>[];
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<TrajectoryHarness> harness({
    Duration drain = const Duration(milliseconds: 200),
  }) => TrajectoryHarness.build(
    config: TrajectoryConfig(
      mode: TrajectoryConfigMode.required,
      shutdownDrainTimeout: drain,
    ),
    gridHome: tmp.path,
    station: 'tranquility',
    connect: () async {
      final db = _LedgerDb(ledger);
      dialled.add(db);
      return db;
    },
    appenderFactory: _FakeAppender.new,
    scheduleTimer: (duration, callback) => _FakeTimer(),
    clock: () => DateTime.utc(2026, 9, 3, 12),
    identity: (pid: 41, pgid: 42),
  );

  test('a clean down leaves no socket open', () async {
    final h = await harness();
    await h.start();
    await h.shutdown();
    expect(dialled, hasLength(1));
    expect(ledger, isEmpty);
  });

  test(
    'a reconnect corpse stays tracked until the vended connection closes it',
    () async {
      final h = await harness();
      await h.start();
      // Refuses twice: once when reconnect retires it, once inside shutdown's
      // drain. Before the ledger, the first refusal lost the handle.
      dialled.single.failCloses = 2;
      h.enqueue(_note(1));
      h.enqueue(_note(2));
      await h.runToFixpoint();
      expect(dialled, hasLength(2), reason: 'sanity: reconnect dialled');

      await h.shutdown();
      expect(
        ledger,
        hasLength(1),
        reason: 'the corpse outlived its own closes',
      );

      await TrajectoryStoreConnection(h).close();
      expect(ledger, isEmpty, reason: 'the vend finally retires the corpse');
    },
  );

  test(
    'a close that hangs past the budget is bounded, never abandoned',
    () async {
      final h = await harness(drain: const Duration(milliseconds: 50));
      await h.start();
      dialled.single.hangCloses = 1;
      final watch = Stopwatch()..start();
      await h.shutdown();
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(ledger, hasLength(1), reason: 'bounded, and still tracked');

      await TrajectoryStoreConnection(h).close();
      expect(ledger, isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
