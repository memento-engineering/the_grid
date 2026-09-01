/// THE WINNER RULE (cut-wiring §0.2, r3 form) — the partitioned `byWorkBead`
/// resolution, exhaustively.
///
/// The rule's whole point is that RETIREMENT IS LEGIBLE in the fold: the engine
/// closes a retired session's bd bead while emitting only `roundRetired`, so
/// its P1 row stays `status='open'` forever — by schema design, not as a gap —
/// and `round > 0` is what says so. A rework storm must therefore never look
/// like a double-mount, and a genuine double-mount must never be swallowed as
/// a rework. Both directions are pinned here.
library;

import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

/// A plain [SessionHeadView] the rule can be driven over — the interface is
/// the seam, so a test needs no fold row and no SQL.
final class _Head implements SessionHeadView {
  _Head({
    required this.sessionId,
    this.round = 0,
    this.isOpen = true,
    this.outcome,
    this.lastSeq = 0,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.utc(2026, 8, 31, 10);

  @override
  final String sessionId;

  /// Every row in this suite is on ONE bead — `byWorkBead` has already
  /// grouped by the time the rule runs.
  @override
  String get workBeadId => 'tg-9abc';

  @override
  final int round;
  @override
  final bool isOpen;
  @override
  final SessionHeadOutcome? outcome;
  @override
  final int lastSeq;
  @override
  final DateTime startedAt;
  // The winner rule reads NONE of these — it partitions on status/round and
  // ranks on last_seq/started_at, and nothing else. Fixed here so that stays
  // visibly true.
  @override
  DateTime? get closedAt => isOpen ? null : startedAt;
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
}

_Head _closed(String id, {required int lastSeq, DateTime? startedAt}) => _Head(
  sessionId: id,
  isOpen: false,
  outcome: SessionHeadOutcome.succeeded,
  lastSeq: lastSeq,
  startedAt: startedAt,
);

void main() {
  group('sessionHeadWinnerOf', () {
    test('no rows at all serves nothing, and says no retirement was seen', () {
      final winner = sessionHeadWinnerOf(const []);
      expect(winner, isA<SessionHeadNone>());
      expect((winner as SessionHeadNone).retiredOpenRows, 0);
    });

    test('case 1: exactly one CURRENT open row wins', () {
      final winner = sessionHeadWinnerOf([_Head(sessionId: 's-1')]);
      expect(winner, isA<SessionHeadWon>());
      expect((winner as SessionHeadWon).row.sessionId, 's-1');
      expect(winner.fromClosedLadder, isFalse);
    });

    test('a RETIRED open row (round > 0) never competes — the successor wins '
        'alone, which is what makes a rework storm not a breach', () {
      final winner = sessionHeadWinnerOf([
        // The retired head: closed on the bd side, still `open` in P1 with
        // its retired-INTO round.
        _Head(sessionId: 's-1', round: 1),
        _Head(sessionId: 's-2'),
      ]);
      expect((winner as SessionHeadWon).row.sessionId, 's-2');
    });

    test('case 2: two CURRENT open rows are a genuine cardinality breach — a '
        'real double-mount, never a rework', () {
      final winner = sessionHeadWinnerOf([
        _Head(sessionId: 's-1'),
        _Head(sessionId: 's-2'),
      ]);
      expect(winner, isA<SessionHeadCardinalityBreach>());
      expect(
        (winner as SessionHeadCardinalityBreach).rows.map((r) => r.sessionId),
        ['s-1', 's-2'],
      );
    });

    test('a retired row does not turn one live head into a breach even at '
        'round 3 (the ladder can be arbitrarily deep)', () {
      final winner = sessionHeadWinnerOf([
        _Head(sessionId: 's-1', round: 1),
        _Head(sessionId: 's-2', round: 2),
        _Head(sessionId: 's-3', round: 3),
        _Head(sessionId: 's-4'),
      ]);
      expect((winner as SessionHeadWon).row.sessionId, 's-4');
    });

    test('the rework WINDOW — only retired-open rows, successor not yet '
        'minted — serves nothing and reports the retirement count', () {
      final winner = sessionHeadWinnerOf([
        _Head(sessionId: 's-1', round: 1),
        _Head(sessionId: 's-2', round: 2),
      ]);
      expect(winner, isA<SessionHeadNone>());
      expect((winner as SessionHeadNone).retiredOpenRows, 2);
    });

    test('case 3: zero CURRENT open rows ⇒ the closed row with the highest '
        'last_seq — the monotone fold-activity cursor', () {
      final winner = sessionHeadWinnerOf([
        _closed('s-1', lastSeq: 12),
        _closed('s-2', lastSeq: 41),
        _closed('s-3', lastSeq: 7),
      ]);
      expect(winner, isA<SessionHeadWon>());
      expect((winner as SessionHeadWon).row.sessionId, 's-2');
      expect(winner.fromClosedLadder, isTrue);
    });

    test('case 3 ties on last_seq break by the LATEST started_at', () {
      final winner = sessionHeadWinnerOf([
        _closed('s-old', lastSeq: 9, startedAt: DateTime.utc(2026, 8, 30)),
        _closed('s-new', lastSeq: 9, startedAt: DateTime.utc(2026, 8, 31)),
      ]);
      expect((winner as SessionHeadWon).row.sessionId, 's-new');
    });

    test('a CURRENT open row beats every closed row, whatever its last_seq — '
        'the closed ladder is only consulted when nothing is current', () {
      final winner = sessionHeadWinnerOf([
        _closed('s-closed', lastSeq: 999),
        _Head(sessionId: 's-live', lastSeq: 1),
      ]);
      expect((winner as SessionHeadWon).row.sessionId, 's-live');
      expect(winner.fromClosedLadder, isFalse);
    });

    test('a retired-open row alongside closed rows still does not compete — '
        'the closed ladder decides', () {
      final winner = sessionHeadWinnerOf([
        _Head(sessionId: 's-retired', round: 1, lastSeq: 500),
        _closed('s-done', lastSeq: 20),
      ]);
      expect((winner as SessionHeadWon).row.sessionId, 's-done');
      expect(winner.fromClosedLadder, isTrue);
    });

    test('a full rework storm resolves at EVERY intermediate state and never '
        'breaches', () {
      // re-key → roundRetired → successor insert → successor terminal, as the
      // mirror would hold it at each step.
      final retired = _Head(sessionId: 's-1');
      final states = <(String, List<SessionHeadView>)>[
        ('mounted', [retired]),
        ('retired', [_Head(sessionId: 's-1', round: 1)]),
        (
          'successor minted',
          [_Head(sessionId: 's-1', round: 1), _Head(sessionId: 's-2')],
        ),
        (
          'successor closed',
          [_Head(sessionId: 's-1', round: 1), _closed('s-2', lastSeq: 30)],
        ),
      ];
      for (final (label, rows) in states) {
        expect(
          sessionHeadWinnerOf(rows),
          isNot(isA<SessionHeadCardinalityBreach>()),
          reason: 'a rework is never a cardinality breach ($label)',
        );
      }
      expect(
        (sessionHeadWinnerOf(states.last.$2) as SessionHeadWon).row.sessionId,
        's-2',
      );
    });
  });

  group('the enum vocabularies mirror the §4 DDL', () {
    test('every outcome word round-trips through its wire form', () {
      for (final outcome in SessionHeadOutcome.values) {
        expect(SessionHeadOutcome.fromWire(outcome.wire), outcome);
      }
      // The decision-faithful terminal vocabulary, verbatim.
      expect(SessionHeadOutcome.values.map((o) => o.wire), [
        'succeeded',
        'failed',
        'cancelled',
        'lost',
        'escalated',
        'settled',
        'unknown',
      ]);
    });

    test('provenance carries exactly the three words the column allows', () {
      expect(SessionHeadProvenance.values.map((p) => p.wire), [
        'observed',
        'inferred',
        'reconstructed',
      ]);
      for (final value in SessionHeadProvenance.values) {
        expect(SessionHeadProvenance.fromWire(value.wire), value);
      }
    });
  });
}
