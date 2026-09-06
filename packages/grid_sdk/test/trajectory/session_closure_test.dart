// tg-ffl6 — the ledger's closure answer for the external-close obligation.
//
// One fixture bead per census bucket the lunar orphans fell into (267 closed
// session beads with no trajectory terminal, 2026-09-05), each carrying the
// metadata shape the state store actually held. The derivation must read the
// SAME markers legacy's disposition reads, in legacy's order, so a healed P1
// head dispositions under `primary` as the bead does under legacy.
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

Bead _session({
  required bool closed,
  Map<String, String> metadata = const {},
  String closeReason = '',
  DateTime? closedAt,
}) => Bead(
  id: 'tranquility-1',
  title: 'grid session tg-abc',
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {SessionBeadKeys.workBead: 'tg-abc', ...metadata},
  closeReason: closeReason,
  closedAt: closedAt,
);

void main() {
  test('an OPEN session bead is a live round — null, nothing to heal', () {
    expect(sessionClosureOf(_session(closed: false)), isNull);
  });

  test('a retired rework round (close_reason "reworked", #rN key) is '
      'CANCELLED: no station outcome, legacy voids and re-mints', () {
    final closure = sessionClosureOf(
      _session(
        closed: true,
        closeReason: 'reworked',
        metadata: {SessionBeadKeys.workBead: 'tg-abc#r2'},
        closedAt: DateTime.utc(2026, 9, 5, 20),
      ),
    )!;

    expect(closure.outcome, TerminalOutcome.cancelled);
    expect(closure.reason, 'ledger close: reworked');
    expect(closure.closedAt, DateTime.utc(2026, 9, 5, 20));
    // …and it is flagged as a retired round, which the heal leaves open.
    expect(closure.retiredRound, isTrue);
  });

  test('a void re-key on a retired round is a void, not a retirement', () {
    final closure = sessionClosureOf(
      _session(
        closed: true,
        metadata: {SessionBeadKeys.workBead: 'tg-abc#void-tranquility-1'},
      ),
    )!;
    expect(closure.retiredRound, isFalse);
    expect(closure.outcome, TerminalOutcome.lost);
  });

  test('a hand close with a bare key and no stamp is CANCELLED too, and '
      'carries the operator\'s reason', () {
    final closure = sessionClosureOf(
      _session(closed: true, closeReason: 'boot-2x twin: the bead re-mints'),
    )!;

    expect(closure.outcome, TerminalOutcome.cancelled);
    expect(closure.reason, 'ledger close: boot-2x twin: the bead re-mints');
    expect(closure.closedAt, isNull);
  });

  test('a breaker-exhausted close carries the human marker and is ESCALATED '
      '— legacy reads it HELD, and so must the healed head', () {
    final closure = sessionClosureOf(
      _session(
        closed: true,
        closeReason: 'breaker-exhausted',
        metadata: {SessionBeadKeys.escalation: 'breaker-exhausted'},
      ),
    )!;

    expect(closure.outcome, TerminalOutcome.escalated);
  });

  test('a declined rework is a human marker too', () {
    final closure = sessionClosureOf(
      _session(
        closed: true,
        metadata: {SessionBeadKeys.reworkDeclined: 'operator declined'},
      ),
    )!;

    expect(closure.outcome, TerminalOutcome.escalated);
  });

  test('the engine\'s DONE marker is SUCCEEDED, and it outranks a void key '
      'exactly as legacy orders them', () {
    final closure = sessionClosureOf(
      _session(
        closed: true,
        closeReason: 'landed by hand as power_station#197',
        metadata: {
          SessionBeadKeys.outcome: kSessionOutcomeComplete,
          SessionBeadKeys.workBead: 'tg-abc#void-tranquility-1',
        },
      ),
    )!;

    expect(closure.outcome, TerminalOutcome.succeeded);
  });

  test('a human marker outranks the DONE marker — a held round is never '
      'healed as done', () {
    final closure = sessionClosureOf(
      _session(
        closed: true,
        metadata: {
          SessionBeadKeys.outcome: kSessionOutcomeComplete,
          SessionBeadKeys.escalation: 'breaker-exhausted',
        },
      ),
    )!;

    expect(closure.outcome, TerminalOutcome.escalated);
  });

  test('a void re-key (#void- key or grid.voided_reason) is LOST — a dead '
      'key, never adoptable and never blocking', () {
    final byKey = sessionClosureOf(
      _session(
        closed: true,
        metadata: {SessionBeadKeys.workBead: 'tg-abc#void-tranquility-1'},
      ),
    )!;
    final byReason = sessionClosureOf(
      _session(
        closed: true,
        metadata: {SessionBeadKeys.voidedReason: 'operator void-rekey'},
      ),
    )!;

    expect(byKey.outcome, TerminalOutcome.lost);
    expect(byKey.reason, isNull);
    expect(byReason.outcome, TerminalOutcome.lost);
    expect(byReason.reason, 'ledger void: operator void-rekey');
  });
}
