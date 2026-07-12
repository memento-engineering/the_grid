// tg-4rw / I-10 — the pure session DISPOSITION: a CLOSED session is `done`,
// `held`, or a `voided` DEAD KEY — never "unadoptable but blocking". Zero I/O.
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

SessionProjection _closed({
  Map<String, NodeCursor> cursor = const {},
  bool completed = false,
  bool humanHeld = false,
}) => SessionProjection(
  workBeadId: 'tg-1',
  sessionId: 'tgdog-s',
  isTerminal: true,
  completed: completed,
  humanHeld: humanHeld,
  cursor: cursor,
);

void main() {
  group('tg-4rw — sessionDispositionOf', () {
    test('no session → none (mint)', () {
      expect(sessionDispositionOf(null), isA<NoSession>());
    });

    test('an OPEN session → live (adopt)', () {
      const open = SessionProjection(workBeadId: 'tg-1', sessionId: 'tgdog-s');
      expect(sessionDispositionOf(open), isA<LiveSession>());
    });

    test('an OPEN projection naming no session bead → none (nothing to adopt)', () {
      const synthetic = SessionProjection(workBeadId: 'tg-1');
      expect(sessionDispositionOf(synthetic), isA<NoSession>());
    });

    test('CLOSED + the grid.outcome marker → done (the latch: never re-drive '
        'landed work)', () {
      final d = sessionDispositionOf(
        _closed(
          completed: true,
          cursor: const {
            'tg-1/agent': NodeCursor(state: StepState.running), // stale, ignored
          },
        ),
      );
      expect(d, isA<DoneSession>());
      expect(d.blocksMount, isTrue);
    });

    test('CLOSED, NO marker, an all-positive-terminal cursor → done (the LEGACY '
        'fallback for beads closed before the marker shipped)', () {
      final d = sessionDispositionOf(
        _closed(
          cursor: const {
            'tg-1/agent': NodeCursor(state: StepState.complete),
            'tg-1/verify': NodeCursor(state: StepState.complete),
            'tg-1/land': NodeCursor(state: StepState.complete),
          },
        ),
      );
      expect(d, isA<DoneSession>());
      expect(d.blocksMount, isTrue);
    });

    test('CLOSED + a human marker → held (a human owns it; blocks, LOUD)', () {
      final d = sessionDispositionOf(
        _closed(
          humanHeld: true,
          cursor: const {
            'tg-1/agent': NodeCursor(state: StepState.failed, restartCount: 3),
          },
        ),
      );
      expect(d, isA<HeldSession>());
      expect(d.blocksMount, isTrue);
      expect((d as HeldSession).reason, contains('human'));
    });

    test('CLOSED mid-flight (a running node), no marker → voided: NOT blocking, '
        'and the reason NAMES the in-flight node (the I-10 shape)', () {
      final d = sessionDispositionOf(
        _closed(
          cursor: const {
            'tg-1/agent': NodeCursor(state: StepState.complete),
            'tg-1/verify': NodeCursor(state: StepState.running),
          },
        ),
      );
      expect(d, isA<VoidedSession>());
      expect(d.blocksMount, isFalse);
      expect((d as VoidedSession).reason, contains('tg-1/verify=running'));
    });

    test('CLOSED with an EMPTY cursor → voided (nothing ever ran)', () {
      final d = sessionDispositionOf(_closed());
      expect(d, isA<VoidedSession>());
      expect(d.blocksMount, isFalse);
      expect((d as VoidedSession).reason, contains('EMPTY'));
    });

    test('a GATED closed session is voided too — parked is not finished', () {
      final d = sessionDispositionOf(
        _closed(
          cursor: const {'tg-1/route': NodeCursor(state: StepState.gated)},
        ),
      );
      expect(d, isA<VoidedSession>());
    });
  });

  group('tg-4rw — projectSession reads the markers off a real session Bead', () {
    test('grid.outcome=complete → completed; the escalation marker → humanHeld', () {
      final done = projectSession(
        sessionBead(
          id: 'tgdog-a',
          workBeadId: 'tg-1',
          closed: true,
          outcomeComplete: true,
        ),
      );
      expect(done.completed, isTrue);
      expect(done.humanHeld, isFalse);
      expect(sessionDispositionOf(done), isA<DoneSession>());

      final held = projectSession(
        sessionBead(
          id: 'tgdog-b',
          workBeadId: 'tg-1',
          closed: true,
          escalated: true,
        ),
      );
      expect(held.humanHeld, isTrue);
      expect(sessionDispositionOf(held), isA<HeldSession>());

      final dead = projectSession(
        sessionBead(
          id: 'tgdog-c',
          workBeadId: 'tg-1',
          closed: true,
          cursorStates: const {'agent': 'running'},
        ),
      );
      expect(dead.completed, isFalse);
      expect(dead.humanHeld, isFalse);
      expect(sessionDispositionOf(dead), isA<VoidedSession>());
    });

    test('an OPEN session bead carrying the outcome marker is still LIVE — the '
        'marker only disambiguates a CLOSED one', () {
      final open = projectSession(
        sessionBead(id: 'tgdog-d', workBeadId: 'tg-1', outcomeComplete: true),
      );
      expect(open.isTerminal, isFalse);
      expect(sessionDispositionOf(open), isA<LiveSession>());
    });
  });

  group('tg-4rw — staleFences + voidKeyFor', () {
    test('every running/ready node with a pgid+pid becomes a fence; deduped; '
        'the legacy scalar is the fallback', () {
      const s = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tgdog-s',
        isTerminal: true,
        cursor: {
          'tg-1/agent': NodeCursor(state: StepState.running, pgid: 42, pid: 43),
          'tg-1/dup': NodeCursor(state: StepState.ready, pgid: 42, pid: 44),
          'tg-1/done': NodeCursor(state: StepState.complete, pgid: 99, pid: 98),
          'tg-1/nofence': NodeCursor(state: StepState.running),
        },
      );
      final fences = staleFences(s);
      expect(fences, hasLength(1));
      expect(fences.single.pgid, 42);

      const legacy = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tgdog-s',
        isTerminal: true,
        pgid: 7,
        pid: 8,
      );
      expect(staleFences(legacy).single.pgid, 7);
      expect(staleFences(const SessionProjection(workBeadId: 'tg-1')), isEmpty);
    });

    test('a void key is deterministic and is NEVER counted as a rework round '
        '(A47: a round nobody ran is not a round the operator spent)', () {
      expect(voidKeyFor('tg-1di', 'tgdog-bkv'), 'tg-1di#void-tgdog-bkv');
      expect(reworkRoundOf('tg-1di', voidKeyFor('tg-1di', 'tgdog-bkv')), isNull);
      expect(maxReworkRound('tg-1di', [voidKeyFor('tg-1di', 'tgdog-bkv')]), 0);
    });
  });
}
