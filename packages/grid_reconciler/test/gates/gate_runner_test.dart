import 'package:grid_reconciler/src/convergence/gate_config.dart';
import 'package:grid_reconciler/src/convergence/gate_mode.dart';
import 'package:grid_reconciler/src/convergence/gate_outcome.dart';
import 'package:grid_reconciler/src/convergence/gate_timeout_action.dart';
import 'package:grid_reconciler/src/convergence/go_duration.dart';
import 'package:grid_reconciler/src/convergence/verdict.dart';
import 'package:grid_reconciler/src/gates/condition_env.dart';
import 'package:grid_reconciler/src/gates/gate_runner_service.dart';
import 'package:grid_reconciler/src/gates/process_runner.dart';
import 'package:test/test.dart';

import 'support/fake_process_runner.dart';

/// Track D outcome + timeout-action + hybrid matrix, driven entirely through
/// the fake [ProcessRunner] (the offline suite never spawns). Ports the
/// behavioral assertions of `condition_test.go` / `hybrid_test.go`
/// (conformance-gate-tests §3.2-§3.3) plus the §5 coverage gaps.
void main() {
  const script = '/city/gates/check.sh';
  final timeout5s = GoDuration.parse('5s')!;

  GateRunnerService runnerWith(FakeProcessRunner fake) => GateRunnerService(
    processRunner: fake,
    ambientEnvironment: const <String, String>{},
    lookPathDir: fakeLookPath(const <String, String>{}),
    tempDir: '/tmp',
  );

  const env = ConditionEnv(beadId: 'b1', cityPath: '/city', wispId: 'w1');

  group('runCondition outcome classification', () {
    test(
      'exit 0 → pass with non-null 0 exit code and captured stdout',
      () async {
        final fake = FakeProcessRunner()
          ..stub(script, FakeRun.pass(stdout: 'ok\n'));
        final result = await runnerWith(fake).runCondition(
          scriptPath: script,
          env: env,
          timeout: timeout5s,
          retryBudget: 0,
        );

        expect(result.outcome, GateOutcome.pass);
        expect(result.exitCode, 0); // non-null zero (trap #3).
        expect(result.stdout, contains('ok'));
        expect(result.retryCount, 0);
      },
    );

    test('exit 1 → fail with exit code 1 and captured stderr', () async {
      final fake = FakeProcessRunner()
        ..stub(script, FakeRun.exited(1, stderr: 'failing\n'));
      final result = await runnerWith(fake).runCondition(
        scriptPath: script,
        env: env,
        timeout: timeout5s,
        retryBudget: 0,
      );

      expect(result.outcome, GateOutcome.fail);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('failing'));
    });

    test('non-0/1 exit code → fail with that code (§5 gap 5)', () async {
      final fake = FakeProcessRunner()..stub(script, FakeRun.exited(42));
      final result = await runnerWith(fake).runCondition(
        scriptPath: script,
        env: env,
        timeout: timeout5s,
        retryBudget: 0,
      );

      expect(result.outcome, GateOutcome.fail);
      expect(result.exitCode, 42);
    });

    test(
      'signal-kill (negative exit) → fail with -1 (§5 gap 5, trap #19)',
      () async {
        final fake = FakeProcessRunner()..stub(script, FakeRun.exited(-1));
        final result = await runnerWith(fake).runCondition(
          scriptPath: script,
          env: env,
          timeout: timeout5s,
          retryBudget: 0,
        );

        expect(result.outcome, GateOutcome.fail);
        expect(result.exitCode, -1);
      },
    );

    test('deadline → timeout with null exit code', () async {
      final fake = FakeProcessRunner()..stub(script, FakeRun.deadline());
      final result = await runnerWith(fake).runCondition(
        scriptPath: script,
        env: env,
        timeout: timeout5s,
        retryBudget: 0,
      );

      expect(result.outcome, GateOutcome.timeout);
      expect(result.exitCode, isNull); // killed, but reported null (not -1).
    });

    test(
      'launch failure → error, launcher string REPLACES stderr (trap #2)',
      () async {
        final fake = FakeProcessRunner()
          ..stub(
            script,
            FakeRun.launchFailure(
              'fork/exec $script: no such file or directory',
            ),
          );
        final result = await runnerWith(fake).runCondition(
          scriptPath: script,
          env: env,
          timeout: timeout5s,
          retryBudget: 0,
        );

        expect(result.outcome, GateOutcome.error);
        expect(result.exitCode, isNull);
        expect(result.stderr, contains('no such file or directory'));
        expect(result.stdout, isEmpty); // stdout dropped on the error path.
      },
    );

    test('timeout carries partial output (§5 gap 11)', () async {
      final fake = FakeProcessRunner()
        ..stub(script, FakeRun.deadline(stdout: 'before-the-hang'));
      final result = await runnerWith(fake).runCondition(
        scriptPath: script,
        env: env,
        timeout: timeout5s,
        retryBudget: 0,
      );

      expect(result.outcome, GateOutcome.timeout);
      expect(result.stdout, contains('before-the-hang'));
    });
  });

  group('timeout-action retry matrix (≤ MaxGateRetries)', () {
    test('budget 0 → 1 attempt, no retry', () async {
      final fake = FakeProcessRunner()..stub(script, FakeRun.deadline());
      final result = await runnerWith(fake).runCondition(
        scriptPath: script,
        env: env,
        timeout: timeout5s,
        retryBudget: 0,
      );

      expect(result.outcome, GateOutcome.timeout);
      expect(result.retryCount, 0);
      expect(fake.calls, hasLength(1));
    });

    test(
      'budget 2, all timeout → 3 attempts, retryCount 2 (retries not attempts)',
      () async {
        final fake = FakeProcessRunner()
          ..stubRepeated(script, FakeRun.deadline(), 3);
        final result = await runnerWith(fake).runCondition(
          scriptPath: script,
          env: env,
          timeout: timeout5s,
          retryBudget: 2,
        );

        expect(result.outcome, GateOutcome.timeout);
        expect(result.retryCount, 2);
        expect(fake.calls, hasLength(3));
      },
    );

    test(
      'budget 3 (MaxGateRetries), all timeout → 4 attempts, retryCount 3',
      () async {
        final fake = FakeProcessRunner()
          ..stubRepeated(script, FakeRun.deadline(), 4);
        final result = await runnerWith(fake).runCondition(
          scriptPath: script,
          env: env,
          timeout: timeout5s,
          retryBudget: GateTimeoutAction.maxGateRetries,
        );

        expect(result.outcome, GateOutcome.timeout);
        expect(result.retryCount, 3);
        expect(fake.calls, hasLength(4));
      },
    );

    test(
      'retry only on timeout: fail returns immediately, retryCount 0',
      () async {
        final fake = FakeProcessRunner()..stub(script, FakeRun.exited(1));
        final result = await runnerWith(fake).runCondition(
          scriptPath: script,
          env: env,
          timeout: timeout5s,
          retryBudget: 3,
        );

        expect(result.outcome, GateOutcome.fail);
        expect(result.retryCount, 0);
        expect(fake.calls, hasLength(1)); // no retries on a non-timeout.
      },
    );

    test('retry-then-success → pass, retryCount 1 (§5 gap 4)', () async {
      final fake = FakeProcessRunner()
        ..stub(script, FakeRun.deadline())
        ..stub(script, FakeRun.pass(stdout: 'ok'));
      final result = await runnerWith(fake).runCondition(
        scriptPath: script,
        env: env,
        timeout: timeout5s,
        retryBudget: 3,
      );

      expect(result.outcome, GateOutcome.pass);
      expect(result.retryCount, 1); // one timed-out attempt before the pass.
      expect(fake.calls, hasLength(2));
    });

    test('error (pre-exec) is NOT retried on the timeout loop', () async {
      final fake = FakeProcessRunner()
        ..stub(script, FakeRun.launchFailure('permission denied'));
      final result = await runnerWith(fake).runCondition(
        scriptPath: script,
        env: env,
        timeout: timeout5s,
        retryBudget: 3,
      );

      expect(result.outcome, GateOutcome.error);
      expect(fake.calls, hasLength(1));
    });
  });

  group('text-file-busy pre-exec retry (condition.go:290-313)', () {
    test('busy then pass → pass, exhausting ≤5 extra attempts (§3a)', () async {
      final fake = FakeProcessRunner()
        ..stub(script, FakeRun.launchFailure('fork/exec: text file busy'))
        ..stub(script, FakeRun.launchFailure('fork/exec: Text File Busy'))
        ..stub(script, FakeRun.pass(stdout: 'ok'));
      final result = await runnerWith(
        fake,
      ).runOnce(scriptPath: script, env: env, timeout: timeout5s);

      expect(result.outcome, GateOutcome.pass); // case-insensitive match.
      expect(fake.calls, hasLength(3));
    });

    test(
      'persistent busy → error after 6 total executions (1 + 5 retries)',
      () async {
        final fake = FakeProcessRunner()
          ..stubRepeated(
            script,
            FakeRun.launchFailure('exec: text file busy'),
            6,
          );
        final result = await runnerWith(
          fake,
        ).runOnce(scriptPath: script, env: env, timeout: timeout5s);

        expect(result.outcome, GateOutcome.error);
        expect(fake.calls, hasLength(6)); // textFileBusyRetryAttempts + 1.
      },
    );

    test('a non-busy launch error is not retried', () async {
      final fake = FakeProcessRunner()
        ..stub(script, FakeRun.launchFailure('no such file or directory'));
      final result = await runnerWith(
        fake,
      ).runOnce(scriptPath: script, env: env, timeout: timeout5s);

      expect(result.outcome, GateOutcome.error);
      expect(fake.calls, hasLength(1));
    });
  });

  group('parent cancellation (trap #3, §1.10)', () {
    test('pre-cancelled parent → error, not timeout, retryCount 0', () async {
      final fake = FakeProcessRunner()
        ..stubRepeated(script, FakeRun.deadline(), 4);
      final result = await runnerWith(fake).runCondition(
        scriptPath: script,
        env: env,
        timeout: timeout5s,
        retryBudget: 3,
        parentCancelled: CancellationToken.cancelled(),
      );

      expect(result.outcome, GateOutcome.error); // never misread as timeout.
      expect(result.retryCount, 0); // no retries against a dead parent.
      expect(fake.calls, hasLength(1));
    });
  });

  group('evaluateHybrid (hybrid.go:8-22)', () {
    GateConfig hybrid({
      String condition = script,
      GateTimeoutAction action = GateTimeoutAction.iterate,
    }) => GateConfig(
      mode: GateMode.hybrid,
      condition: condition,
      timeout: timeout5s,
      timeoutAction: action,
    );

    test(
      'approve + script passes → pass; verdict reaches GC_AGENT_VERDICT',
      () async {
        final fake = FakeProcessRunner()
          ..stub(script, FakeRun.pass(stdout: 'approved'));
        final result = await runnerWith(
          fake,
        ).evaluateHybrid(config: hybrid(), env: env, verdict: Verdict.approve);

        expect(result.outcome, GateOutcome.pass);
        expect(fake.lastEnvironment['GC_AGENT_VERDICT'], 'approve');
      },
    );

    test(
      'approve verdict does NOT override a rejecting script → fail',
      () async {
        final fake = FakeProcessRunner()..stub(script, FakeRun.exited(1));
        final result = await runnerWith(
          fake,
        ).evaluateHybrid(config: hybrid(), env: env, verdict: Verdict.approve);

        expect(
          result.outcome,
          GateOutcome.fail,
        ); // exit code decides, not verdict.
      },
    );

    test(
      'block verdict does NOT override an approving script → pass',
      () async {
        final fake = FakeProcessRunner()..stub(script, FakeRun.pass());
        final result = await runnerWith(
          fake,
        ).evaluateHybrid(config: hybrid(), env: env, verdict: Verdict.block);

        expect(result.outcome, GateOutcome.pass);
        expect(fake.lastEnvironment['GC_AGENT_VERDICT'], 'block');
      },
    );

    test(
      'empty verdict → GC_AGENT_VERDICT omitted (absent, not empty)',
      () async {
        final fake = FakeProcessRunner()..stub(script, FakeRun.exited(1));
        final result = await runnerWith(fake).evaluateHybrid(
          config: hybrid(),
          env: env,
          verdict: const Verdict(''),
        );

        expect(result.outcome, GateOutcome.fail);
        expect(fake.lastEnvironment.containsKey('GC_AGENT_VERDICT'), isFalse);
      },
    );

    test(
      'no condition configured → manual fallback: pass, null exit, no run',
      () async {
        final fake = FakeProcessRunner();
        final result = await runnerWith(fake).evaluateHybrid(
          config: hybrid(condition: ''),
          env: env,
          verdict: Verdict.approve,
        );

        expect(result.outcome, GateOutcome.pass);
        expect(
          result.exitCode,
          isNull,
        ); // GateManualResult — proof nothing ran.
        expect(result.duration, Duration.zero);
        expect(fake.calls, isEmpty);
      },
    );

    test(
      'retry budget wiring: action=retry + timeouts → retryCount 3 (§5 gap 3)',
      () async {
        final fake = FakeProcessRunner()
          ..stubRepeated(script, FakeRun.deadline(), 4);
        final result = await runnerWith(fake).evaluateHybrid(
          config: hybrid(action: GateTimeoutAction.retry),
          env: env,
          verdict: Verdict.approve,
        );

        expect(result.outcome, GateOutcome.timeout);
        expect(result.retryCount, 3); // MaxGateRetries.
        expect(fake.calls, hasLength(4));
      },
    );

    test(
      'retry budget wiring: action=iterate + timeout → retryCount 0 (§5 gap 3)',
      () async {
        final fake = FakeProcessRunner()..stub(script, FakeRun.deadline());
        final result = await runnerWith(fake).evaluateHybrid(
          config: hybrid(action: GateTimeoutAction.iterate),
          env: env,
          verdict: Verdict.approve,
        );

        expect(result.outcome, GateOutcome.timeout);
        expect(result.retryCount, 0);
        expect(fake.calls, hasLength(1));
      },
    );
  });

  group('evaluate (mode dispatch, gates-exec.md §8)', () {
    GateEnvInputs inputs({Verdict verdict = Verdict.block}) =>
        GateEnvInputs(cityPath: '/city', agentVerdict: verdict);

    test('manual mode → GateManualResult, nothing runs', () async {
      final fake = FakeProcessRunner();
      final result = await runnerWith(fake).evaluate(
        config: const GateConfig(
          mode: GateMode.manual,
          condition: '',
          timeout: GoDuration(300000000000),
          timeoutAction: GateTimeoutAction.iterate,
        ),
        env: env,
        inputs: inputs(),
        scriptPath: '',
      );

      expect(result.outcome, GateOutcome.pass);
      expect(result.exitCode, isNull);
      expect(fake.calls, isEmpty);
    });

    test('pure condition mode does NOT export the verdict', () async {
      final fake = FakeProcessRunner()..stub(script, FakeRun.pass());
      await runnerWith(fake).evaluate(
        config: GateConfig(
          mode: GateMode.condition,
          condition: script,
          timeout: timeout5s,
          timeoutAction: GateTimeoutAction.iterate,
        ),
        env: env,
        inputs: inputs(verdict: Verdict.approve),
        scriptPath: script,
      );

      expect(fake.lastEnvironment.containsKey('GC_AGENT_VERDICT'), isFalse);
    });

    test('hybrid mode exports the inputs verdict', () async {
      final fake = FakeProcessRunner()..stub(script, FakeRun.pass());
      await runnerWith(fake).evaluate(
        config: GateConfig(
          mode: GateMode.hybrid,
          condition: script,
          timeout: timeout5s,
          timeoutAction: GateTimeoutAction.iterate,
        ),
        env: env,
        inputs: inputs(verdict: Verdict.approveWithRisks),
        scriptPath: script,
      );

      expect(fake.lastEnvironment['GC_AGENT_VERDICT'], 'approve-with-risks');
    });
  });
}
