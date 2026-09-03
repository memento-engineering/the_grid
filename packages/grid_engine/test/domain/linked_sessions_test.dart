// tg-83k1 — the ONE ordering and verdict over a work bead's MANY linked session
// rows. Pure: no tree, no I/O, no fakes needed.
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

SessionProjection _row(
  String id, {
  bool terminal = true,
  bool completed = false,
  bool humanHeld = false,
  DateTime? closedAt,
  DateTime? startedAt,
}) => SessionProjection(
  workBeadId: 'tg-1',
  sessionId: id,
  isTerminal: terminal,
  completed: completed,
  humanHeld: humanHeld,
  closedAt: closedAt,
  startedAt: startedAt,
);

void main() {
  group('orderLinkedSessions', () {
    test('an OPEN row outranks every terminal one', () {
      final ordered = orderLinkedSessions([
        _row('a', completed: true, closedAt: DateTime.utc(2026, 9, 3, 12)),
        _row('b', terminal: false),
      ]);
      expect(ordered.map((row) => row.sessionId), ['b', 'a']);
    });

    test(
      'a BLOCKING terminal outranks a dead key, however new the dead key is',
      () {
        final ordered = orderLinkedSessions([
          _row('dead', closedAt: DateTime.utc(2026, 9, 3, 23)),
          _row('done', completed: true, closedAt: DateTime.utc(2026, 9, 3, 1)),
        ]);
        expect(ordered.first.sessionId, 'done');
      },
    );

    test('within one rank the NEWEST wins, and a timestamp-free snapshot is '
        'still deterministic', () {
      expect(
        orderLinkedSessions([
          _row('old', closedAt: DateTime.utc(2026, 9, 3, 1)),
          _row('new', closedAt: DateTime.utc(2026, 9, 3, 2)),
        ]).first.sessionId,
        'new',
      );
      final bare = [_row('aaa'), _row('zzz')];
      expect(orderLinkedSessions(bare).first.sessionId, 'zzz');
      expect(orderLinkedSessions(bare.reversed).first.sessionId, 'zzz');
    });
  });

  group('linkedSessionVerdictOf', () {
    test('no rows: none', () {
      expect(
        linkedSessionVerdictOf(const <SessionProjection>[]),
        isA<NoLinkedSession>(),
      );
    });

    test('an open row: adopt, and a SECOND open row is a reported rival', () {
      final verdict = linkedSessionVerdictOf([
        _row('live-old', terminal: false, startedAt: DateTime.utc(2026, 9, 1)),
        _row('live-new', terminal: false, startedAt: DateTime.utc(2026, 9, 2)),
      ]);
      expect(
        verdict,
        isA<AdoptLinkedSession>()
            .having((v) => v.session.sessionId, 'session', 'live-new')
            .having((v) => v.rivals.map((row) => row.sessionId), 'rivals', [
              'live-old',
            ]),
      );
      expect(verdict.winner?.sessionId, 'live-new');
    });

    test('a done or held row blocks, even beside a dead key', () {
      for (final blocking in [
        _row('done', completed: true),
        _row('held', humanHeld: true),
      ]) {
        expect(
          linkedSessionVerdictOf([_row('dead'), blocking]),
          isA<BlockedLinkedSession>().having(
            (v) => v.session.sessionId,
            'session',
            blocking.sessionId,
          ),
        );
      }
    });

    test('all-terminal dead keys: remint the newest, demote the rest', () {
      expect(
        linkedSessionVerdictOf([
          _row('old', closedAt: DateTime.utc(2026, 9, 3, 1)),
          _row('new', closedAt: DateTime.utc(2026, 9, 3, 2)),
        ]),
        isA<RemintLinkedSession>()
            .having((v) => v.session.sessionId, 'session', 'new')
            .having((v) => v.surplus.map((row) => row.sessionId), 'surplus', [
              'old',
            ]),
      );
    });
  });
}
