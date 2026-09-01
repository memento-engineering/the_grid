/// The §5 tick skeleton: interval firing, the fenced-out skip (a fenced tick
/// repairs nothing), fixpoint termination on the clean-down path, and dispose.
library;

import 'dart:async';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_db.dart';
import '../support/tick_fakes.dart';

AttemptNote _note(int ordinal) => AttemptNote(
  sessionId: 'tranquility-1',
  body: 'repair $ordinal',
  channel: 'obligation',
  noteOrdinal: ordinal,
);

ObligationAppend _repair(int ordinal) => ObligationAppend(_note(ordinal));

class _Harness {
  _Harness({List<ObligationQuery> queries = kStage0ObligationQueries}) {
    tick = TrajectoryTick(
      appender: appender,
      db: db,
      queries: queries,
      clock: clock.call,
      scheduleTimer: timers.schedule,
      onPass: passes.add,
    );
  }

  final db = ScriptedDb();
  final appender = FakeTickAppender();
  final clock = FakeClock();
  final timers = ManualTimers();
  final passes = <TrajectoryTickPass>[];
  late final TrajectoryTick tick;
}

void main() {
  group('Stage 0 shape', () {
    test(
      'wires no obligation queries — the families arm with their stages',
      () async {
        final harness = _Harness();
        expect(harness.tick.queries, isEmpty);

        final pass = await harness.tick.runPass();

        expect(pass.disposition, TickPassDisposition.ran);
        expect(pass.queriesRun, 0);
        expect(pass.recordsAppended, 0);
        expect(pass.quiet, isTrue);
        expect(harness.appender.appended, isEmpty);
      },
    );

    test('a quiet pass still fires the dolt-commit cadence', () async {
      final harness = _Harness();

      await harness.tick.runPass();

      expect(harness.appender.doltCommits, 1);
    });

    test('surfaces the pass as telemetry — lastPass and the sink', () async {
      final harness = _Harness();

      final pass = await harness.tick.runPass();

      expect(harness.tick.lastPass, same(pass));
      expect(harness.passes, [same(pass)]);
    });

    test('a throwing telemetry sink never breaks the pass', () async {
      final harness = _Harness();
      final tick = TrajectoryTick(
        appender: harness.appender,
        db: harness.db,
        clock: harness.clock.call,
        scheduleTimer: harness.timers.schedule,
        onPass: (_) => throw StateError('sink is down'),
      );

      final pass = await tick.runPass();

      expect(pass.ran, isTrue);
    });
  });

  group('interval', () {
    test('start runs the boot pass and arms the interval', () async {
      final harness = _Harness();

      final pass = await harness.tick.start();

      expect(pass.ran, isTrue);
      expect(harness.tick.isArmed, isTrue);
      expect(harness.timers.scheduled, [kDefaultTickInterval]);
    });

    test(
      'each firing runs one pass and re-arms — passes never stack',
      () async {
        final harness = _Harness();
        await harness.tick.start();

        await harness.timers.fire();
        await harness.timers.fire();

        expect(harness.passes, hasLength(3));
        expect(harness.tick.isArmed, isTrue);
        expect(harness.timers.scheduled, hasLength(3));
      },
    );

    test('a fenced boot pass still arms — a successor claim un-fences the '
        'appender', () async {
      final harness = _Harness()..appender.isInert = true;

      final pass = await harness.tick.start();

      expect(pass.disposition, TickPassDisposition.skippedFencedOut);
      expect(harness.tick.isArmed, isTrue);
    });

    test(
      'an interval firing into a live pass is dropped, not queued',
      () async {
        final gate = Completer<List<ObligationAppend>>();
        final query = StubObligationQuery(onRepair: (_) => gate.future);
        final harness = _Harness(queries: [query]);

        final first = harness.tick.runPass();
        final second = await harness.tick.runPass();
        expect(second.disposition, TickPassDisposition.skippedBusy);

        gate.complete(const []);
        expect((await first).ran, isTrue);
        expect(query.runs, 1);
      },
    );

    test(
      'a pass that throws surfaces as a refusal, and the timer re-arms',
      () async {
        final harness = _Harness();
        await harness.tick.start();
        harness.appender.commitThrows = StateError('branch changed to feature');

        await harness.timers.fire();

        final pass = harness.tick.lastPass!;
        expect(pass.refusals.single.kind, TickRefusalKind.passFailed);
        expect(pass.refusals.single.reason, contains('branch changed'));
        expect(harness.tick.isArmed, isTrue);
      },
    );
  });

  group('fenced out', () {
    test(
      'an inert appender skips the pass entirely — no query, no commit',
      () async {
        final query = StubObligationQuery(onRepair: (_) async => [_repair(1)]);
        final harness = _Harness(queries: [query])..appender.isInert = true;

        final pass = await harness.tick.runPass();

        expect(pass.disposition, TickPassDisposition.skippedFencedOut);
        expect(pass.queriesRun, 0);
        expect(query.runs, 0);
        expect(harness.appender.doltCommits, 0);
        expect(harness.db.log, isEmpty);
      },
    );

    test('a halted appender skips the pass', () async {
      final harness = _Harness()..appender.isHalted = true;

      final pass = await harness.tick.runPass();

      expect(pass.disposition, TickPassDisposition.skippedHalted);
      expect(harness.appender.doltCommits, 0);
    });

    test('losing the fence mid-pass stops the remaining obligations', () async {
      final second = StubObligationQuery(
        name: 'second',
        onRepair: (_) async => [_repair(2)],
      );
      final harness = _Harness(
        queries: [
          StubObligationQuery(
            name: 'first',
            onRepair: (_) async => [_repair(1), _repair(2)],
          ),
          second,
        ],
      );
      harness.appender.outcomes = [
        const AppendFencedOut(reason: 'cas-zero-rows'),
      ];

      final pass = await harness.tick.runPass();

      expect(pass.queriesRun, 1);
      expect(second.runs, 0);
      expect(pass.recordsAppended, 0);
      expect(pass.refusals.single.kind, TickRefusalKind.fencedOut);
      expect(pass.refusals.single.reason, 'cas-zero-rows');
      expect(pass.refusals.single.recordType, 'attempt.note');
      expect(harness.appender.appended, hasLength(1));
    });

    test('a corruption halt refusal ends the pass', () async {
      final harness = _Harness(
        queries: [
          StubObligationQuery(onRepair: (_) async => [_repair(1)]),
        ],
      );
      harness.appender.outcomes = [
        const AppendCorruptionHalt(reason: 'uq_epoch_seq'),
      ];

      final pass = await harness.tick.runPass();

      expect(pass.refusals.single.kind, TickRefusalKind.corruptionHalt);
      expect(pass.quiet, isFalse);
    });
  });

  group('obligations', () {
    test('counts landed and deduped repairs apart — a repeat is success, '
        'not progress', () async {
      final harness = _Harness(
        queries: [
          StubObligationQuery(onRepair: (_) async => [_repair(1), _repair(2)]),
        ],
      );
      harness.appender.outcomes = [
        fakeAppended(recordId: 'a', seq: 7, epochSeq: 1),
        const AppendDeduped(recordId: 'a'),
      ];

      final pass = await harness.tick.runPass();

      expect(pass.recordsAppended, 1);
      expect(pass.recordsDeduped, 1);
      expect(pass.quiet, isFalse);
    });

    test(
      'a throwing obligation is a refusal, and the next one still runs',
      () async {
        final healthy = StubObligationQuery(
          name: 'healthy',
          onRepair: (_) async => const [],
        );
        final harness = _Harness(
          queries: [
            StubObligationQuery(
              name: 'broken',
              onRepair: (_) async => throw StateError('bd unreachable'),
            ),
            healthy,
          ],
        );

        final pass = await harness.tick.runPass();

        expect(pass.queriesRun, 2);
        expect(healthy.runs, 1);
        expect(pass.refusals.single.kind, TickRefusalKind.queryFailed);
        expect(pass.refusals.single.query, 'broken');
      },
    );

    test('runs the standing SQL over the projections', () async {
      final query = StubObligationQuery(
        sql: 'SELECT session_id FROM proj_sessions',
        onRepair: (_) async => const [],
      );
      final harness = _Harness(queries: [query]);

      await harness.tick.runPass();

      expect(harness.db.matching('proj_sessions'), hasLength(1));
    });
  });

  group('runToFixpoint', () {
    test('Stage 0 reaches fixpoint in one pass', () async {
      final harness = _Harness();

      final result = await harness.tick.runToFixpoint();

      expect(result.reached, isTrue);
      expect(result.passes, hasLength(1));
      expect(result.outstanding, 0);
    });

    test('repeats until a pass finds no work', () async {
      var remaining = 2;
      final harness = _Harness(
        queries: [
          StubObligationQuery(
            onRepair: (_) async =>
                remaining-- > 0 ? [_repair(remaining)] : const [],
          ),
        ],
      );

      final result = await harness.tick.runToFixpoint();

      expect(result.reached, isTrue);
      expect(result.passes, hasLength(3));
      expect(result.recordsAppended, 2);
    });

    test(
      'a self-renewing obligation stops at the pass cap, not forever',
      () async {
        final harness = _Harness(
          queries: [
            StubObligationQuery(onRepair: (_) async => [_repair(1)]),
          ],
        );

        final result = await harness.tick.runToFixpoint(maxPasses: 3);

        expect(result.reached, isFalse);
        expect(result.passes, hasLength(3));
        expect(result.recordsAppended, 3);
      },
    );

    test('a fenced-out service reports no fixpoint — down records the '
        'outstanding count and the successor inherits it', () async {
      final harness = _Harness(
        queries: [
          StubObligationQuery(onRepair: (_) async => [_repair(1)]),
        ],
      );
      harness.appender.isInert = true;

      final result = await harness.tick.runToFixpoint();

      expect(result.reached, isFalse);
      expect(
        result.passes.single.disposition,
        TickPassDisposition.skippedFencedOut,
      );
    });

    test('a refusing pass is not a fixpoint', () async {
      final harness = _Harness(
        queries: [
          StubObligationQuery(
            onRepair: (_) async => throw StateError('bd unreachable'),
          ),
        ],
      );

      final result = await harness.tick.runToFixpoint(maxPasses: 2);

      expect(result.reached, isFalse);
      expect(result.outstanding, 1);
    });
  });

  group('dispose', () {
    test('cancels the interval and makes further passes no-ops', () async {
      final harness = _Harness();
      await harness.tick.start();

      harness.tick.dispose();

      expect(harness.tick.isArmed, isFalse);
      expect(harness.timers.isArmed, isFalse);
      final pass = await harness.tick.runPass();
      expect(pass.disposition, TickPassDisposition.skippedDisposed);
      expect(harness.appender.doltCommits, 1);
    });

    test('is idempotent, and start after dispose stays inert', () async {
      final harness = _Harness();
      harness.tick
        ..dispose()
        ..dispose();

      final pass = await harness.tick.start();

      expect(pass.disposition, TickPassDisposition.skippedDisposed);
      expect(harness.tick.isArmed, isFalse);
    });

    test(
      'disposing during an in-flight pass never re-arms the interval',
      () async {
        final gates = <Completer<List<ObligationAppend>>>[];
        final harness = _Harness(
          queries: [
            StubObligationQuery(
              onRepair: (_) {
                final gate = Completer<List<ObligationAppend>>();
                gates.add(gate);
                return gate.future;
              },
            ),
          ],
        );
        final boot = harness.tick.start();
        await harness.timers.pump();
        gates.single.complete(const []);
        await boot;

        await harness.timers.fire(); // the pass blocks on its second gate
        harness.tick.dispose();
        gates[1].complete(const []);
        await harness.timers.pump();

        expect(harness.tick.isArmed, isFalse);
        expect(harness.timers.isArmed, isFalse);
      },
    );
  });
}
