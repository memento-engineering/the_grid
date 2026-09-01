// §5: every type has a deterministic key; hashing makes truncation
// impossible, but these tests pin the canonical-string builders — including a
// maximum-plausible-length key per type (VARCHAR(512) bound on idem_key_text,
// CHAR(64) on the hash).

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/fixture_support.dart';

void main() {
  test('sha256Hex matches the known empty-string vector', () {
    expect(
      sha256Hex(''),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });

  test('every sample record builds a bounded key and a CHAR(64) hash', () {
    for (final record in sampleRecords()) {
      final text = record.idemKeyText(fixtureContext);
      expect(text, isNotEmpty, reason: record.recordType);
      expect(text.length, lessThanOrEqualTo(512), reason: record.recordType);
      expect(
        record.idemKey(fixtureContext),
        matches(RegExp(r'^[0-9a-f]{64}$')),
        reason: record.recordType,
      );
    }
  });

  test('EVERY grammar row stays inside VARCHAR(512)/CHAR(64) at column '
      'bounds — a maximum-length key per record type (§5)', () {
    final maxed = maxLengthSampleRecords();
    // The max set covers exactly the record types the grammar table names.
    expect(
      maxed.map((record) => record.recordType).toSet(),
      sampleRecords().map((record) => record.recordType).toSet(),
    );
    for (final record in maxed) {
      final text = record.idemKeyText(maxLengthContext);
      expect(text, isNotEmpty, reason: record.recordType);
      expect(
        text.length,
        lessThanOrEqualTo(512),
        reason:
            '${record.recordType}: ${text.length} chars overflows '
            'idem_key_text VARCHAR(512)',
      );
      expect(
        record.idemKey(maxLengthContext),
        matches(RegExp(r'^[0-9a-f]{64}$')),
        reason: record.recordType,
      );
    }
  });

  test('effect identity keys the logical mutation, not the attempt', () {
    EffectIntent intent({String? attemptId}) => EffectIntent(
      sessionId: 'tranquility-5xk',
      round: 0,
      stepPath: 'root.deliver',
      stepRound: 0,
      kind: EffectKind.push,
      targetRepo: 'memento-engineering/the_grid',
      targetBranch: 'grid/tg-9abc',
      posture: const {'delivery_method': 'pr', 'policy_version': 'v2'},
      attemptId: attemptId,
    );

    // A respawned incarnation's retry lands on the SAME effect_id.
    expect(
      intent(attemptId: 'a-one').identity,
      equals(intent(attemptId: 'a-two').identity),
    );
    expect(intent().identity.effectId, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('effectTargetDigest is 16 hex chars and target-sensitive', () {
    final one = effectTargetDigest(
      repo: 'r',
      branch: 'b',
      base: 'main',
      publishSha: 'deadbeef',
    );
    final two = effectTargetDigest(repo: 'r', branch: 'b', base: 'main');
    expect(one, matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(one, isNot(equals(two)));
    // Determinism: the same target always digests identically.
    expect(
      one,
      effectTargetDigest(
        repo: 'r',
        branch: 'b',
        base: 'main',
        publishSha: 'deadbeef',
      ),
    );
  });

  test('the settling terminal takes the resolve-shaped key', () {
    final unsettled = AttemptTerminal(
      attemptId: 'a-one',
      outcome: TerminalOutcome.unknown,
      unknownReason: 'write_timeout',
    );
    final settling = AttemptTerminal(
      attemptId: 'a-one',
      outcome: TerminalOutcome.settled,
      resolvesRecordId: '01J8TERMINAL00000000000001',
    );
    expect(unsettled.idemKeyText(fixtureContext), 'terminal:a-one');
    expect(
      settling.idemKeyText(fixtureContext),
      'terminal-resolve:a-one:01J8TERMINAL00000000000001',
    );
  });

  test('the terminal-reconcile HEAL takes its OWN key grammar (cut-wiring '
      'C2, r8 — V2-B1): it can never dedupe against the real record in '
      'EITHER direction', () {
    final real = AttemptTerminal(
      attemptId: 'a-one',
      outcome: TerminalOutcome.succeeded,
    );
    final heal = AttemptTerminal(
      attemptId: 'a-one',
      outcome: TerminalOutcome.unknown,
      unknownReason: 'external-close',
      healBasis: 'terminal-reconcile',
    );
    expect(real.idemKeyText(fixtureContext), 'terminal:a-one');
    expect(heal.idemKeyText(fixtureContext), 'terminal-reconcile:a-one');
    expect(heal.idemKey(fixtureContext), isNot(real.idemKey(fixtureContext)));
  });

  test('the heal basis rides the payload, and a settling re-authoring carries '
      'it through without changing the settling grammar', () {
    final heal = AttemptTerminal(
      attemptId: 'a-one',
      outcome: TerminalOutcome.unknown,
      unknownReason: 'external-close',
      healBasis: 'terminal-reconcile',
    );
    expect(heal.payloadToJson()['heal_basis'], 'terminal-reconcile');
    final settled =
        heal.settlingForm('01J8TERMINAL00000000000001')! as AttemptTerminal;
    expect(settled.payloadToJson()['heal_basis'], 'terminal-reconcile');
    expect(
      settled.idemKeyText(fixtureContext),
      'terminal-resolve:a-one:01J8TERMINAL00000000000001',
    );
  });

  test('required-field invariants refuse at construction', () {
    expect(
      () => AttemptTerminal(attemptId: 'a', outcome: TerminalOutcome.unknown),
      throwsArgumentError,
    );
    expect(
      () => StepSuperseded(
        sessionId: 's',
        round: 0,
        stepPath: 'p',
        cause: 'restart-budget',
        budgetRemaining: 0,
        oldStepRound: 1,
        newStepRound: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => VerifyRouteVerdict(
        sessionId: 's',
        round: 0,
        stepPath: 'p',
        stepRound: 0,
        verdict: RouteVerdictKind.advance,
        rule: 'decent-grades',
        grades: const {},
        // Neither incarnation (service variant) nor gate/cycle (operator).
      ),
      throwsArgumentError,
    );
  });
}
