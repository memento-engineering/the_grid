@Tags(<String>['integration'])
library;

import 'package:grid_reconciler/src/convergence/gate_outcome.dart';
import 'package:grid_reconciler/src/convergence/go_duration.dart';
import 'package:grid_reconciler/src/gates/condition_env.dart';
import 'package:grid_reconciler/src/gates/gate_runner_service.dart';
import 'package:grid_reconciler/src/gates/output_capture.dart';
import 'package:grid_reconciler/src/gates/process_runner.dart';
import 'package:test/test.dart';

import 'support/script_fixtures.dart';

/// Real-subprocess gate execution against [SystemProcessRunner] with hermetic
/// `#!/bin/sh` gates in a temp dir. These exercise the OS compatibility surface
/// (ADR-0003 D3) — kept out of the offline suite via the `integration` tag.
void main() {
  late ScriptFixtures fx;

  setUp(() => fx = ScriptFixtures.create());
  tearDown(() => fx.dispose());

  GateRunnerService runner({
    Map<String, String> ambient = const <String, String>{},
  }) => GateRunnerService(
    processRunner: const SystemProcessRunner(),
    ambientEnvironment: ambient,
    lookPathDir: systemLookPathDir,
    tempDir: '/tmp',
  );

  ConditionEnv envFor(String cityPath) => ConditionEnv(
    beadId: 'b1',
    cityPath: cityPath,
    wispId: 'w1',
    iteration: 7,
  );

  final fiveSeconds = GoDuration.parse('5s')!;

  test('exit 0 → pass with captured stdout, real duration > 0', () async {
    final script = fx.writeScript('pass.sh', shScript(<String>['echo ok']));
    final result = await runner().runCondition(
      scriptPath: script,
      env: envFor(fx.root.path),
      timeout: fiveSeconds,
      retryBudget: 0,
    );

    expect(result.outcome, GateOutcome.pass);
    expect(result.exitCode, 0);
    expect(result.stdout.trim(), 'ok');
    expect(result.duration, greaterThan(Duration.zero));
  });

  test('exit 1 → fail with captured stderr', () async {
    final script = fx.writeScript(
      'fail.sh',
      shScript(<String>['echo failing >&2', 'exit 1']),
    );
    final result = await runner().runCondition(
      scriptPath: script,
      env: envFor(fx.root.path),
      timeout: fiveSeconds,
      retryBudget: 0,
    );

    expect(result.outcome, GateOutcome.fail);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('failing'));
  });

  test('exit 42 → fail with exit code 42', () async {
    final script = fx.writeScript('e42.sh', shScript(<String>['exit 42']));
    final result = await runner().runCondition(
      scriptPath: script,
      env: envFor(fx.root.path),
      timeout: fiveSeconds,
      retryBudget: 0,
    );

    expect(result.outcome, GateOutcome.fail);
    expect(result.exitCode, 42);
  });

  test('sleep past a 100ms deadline → timeout, null exit code', () async {
    final script = fx.writeScript('slow.sh', shScript(<String>['sleep 60']));
    final result = await runner().runCondition(
      scriptPath: script,
      env: envFor(fx.root.path),
      timeout: GoDuration.parse('100ms')!,
      retryBudget: 0,
    );

    expect(result.outcome, GateOutcome.timeout);
    expect(result.exitCode, isNull);
  });

  test('timeout with budget 2 → 3 attempts, retryCount 2', () async {
    final script = fx.writeScript('slow.sh', shScript(<String>['sleep 60']));
    final result = await runner().runCondition(
      scriptPath: script,
      env: envFor(fx.root.path),
      timeout: GoDuration.parse('100ms')!,
      retryBudget: 2,
    );

    expect(result.outcome, GateOutcome.timeout);
    expect(result.retryCount, 2);
  });

  test(
    'nonexistent script → error (pre-exec failure class, not fail)',
    () async {
      final result = await runner().runCondition(
        scriptPath: '${fx.root.path}/nope.sh',
        env: envFor(fx.root.path),
        timeout: fiveSeconds,
        retryBudget: 0,
      );

      expect(result.outcome, GateOutcome.error);
      expect(result.exitCode, isNull);
    },
  );

  test('stdout/stderr captured, not truncated for small output', () async {
    final script = fx.writeScript(
      'cap.sh',
      shScript(<String>['echo stdout-data', 'echo stderr-data >&2']),
    );
    final result = await runner().runCondition(
      scriptPath: script,
      env: envFor(fx.root.path),
      timeout: fiveSeconds,
      retryBudget: 0,
    );

    expect(result.stdout, contains('stdout-data'));
    expect(result.stderr, contains('stderr-data'));
    expect(result.truncated, isFalse);
  });

  test('5096-byte stdout → pass, stdout ≤ 4096, truncated', () async {
    final script = fx.writeScript(
      'big.sh',
      shScript(<String>["printf '%0*d' 5096 0"]),
    );
    final result = await runner().runCondition(
      scriptPath: script,
      env: envFor(fx.root.path),
      timeout: fiveSeconds,
      retryBudget: 0,
    );

    expect(result.outcome, GateOutcome.pass);
    expect(result.stdout.length, lessThanOrEqualTo(maxOutputBytes));
    expect(result.truncated, isTrue);
  });

  test(
    'the child observes the whitelist env (GC_BEAD_ID/GC_ITERATION/PATH)',
    () async {
      final script = fx.writeScript(
        'env.sh',
        shScript(<String>[
          r'echo "BEAD=$GC_BEAD_ID"',
          r'echo "ITER=$GC_ITERATION"',
          r'echo "PATH=$PATH"',
        ]),
      );
      final result = await runner().runCondition(
        scriptPath: script,
        env: envFor(fx.root.path),
        timeout: fiveSeconds,
        retryBudget: 0,
      );

      expect(result.outcome, GateOutcome.pass);
      expect(result.stdout, contains('BEAD=b1'));
      expect(result.stdout, contains('ITER=7'));
      expect(result.stdout, contains('PATH='));
      // The whitelist sandbox: the controller token is never leaked to the child.
      expect(result.stdout.contains('GC_CONTROLLER_TOKEN'), isFalse);
    },
  );

  test(
    'WorkDir is the cwd; BEADS_DIR derives from CityPath (precedence)',
    () async {
      final cityPath = fx.mkdir('city');
      final workDir = fx.mkdir('city/work');
      fx.writeFile('city/work/target.txt', 'ok');
      final script = fx.writeScript(
        'wd.sh',
        shScript(<String>['pwd', r'echo "$BEADS_DIR"', 'cat target.txt']),
      );
      final result = await runner().runCondition(
        scriptPath: script,
        env: ConditionEnv(
          beadId: 'b1',
          cityPath: cityPath,
          wispId: 'w1',
          workDir: workDir,
        ),
        timeout: fiveSeconds,
        retryBudget: 0,
      );

      expect(result.outcome, GateOutcome.pass);
      // pwd resolves through /private on macOS — compare the basename tail.
      expect(result.stdout, contains('work'));
      expect(result.stdout, contains('$cityPath/.beads'));
      expect(result.stdout, contains('ok'));
    },
  );

  test('hybrid: the verdict reaches the script via GC_AGENT_VERDICT', () async {
    final script = fx.writeScript(
      'hybrid.sh',
      shScript(<String>[
        r'if [ "$GC_AGENT_VERDICT" = "approve" ]; then',
        '  echo approved; exit 0',
        'else',
        r'  echo "rejected: $GC_AGENT_VERDICT" >&2; exit 1',
        'fi',
      ]),
    );
    final approve = await runner().runCondition(
      scriptPath: script,
      env: envFor(fx.root.path).withAgentVerdict('approve'),
      timeout: fiveSeconds,
      retryBudget: 0,
    );
    final block = await runner().runCondition(
      scriptPath: script,
      env: envFor(fx.root.path).withAgentVerdict('block'),
      timeout: fiveSeconds,
      retryBudget: 0,
    );

    expect(approve.outcome, GateOutcome.pass);
    expect(approve.stdout, contains('approved'));
    expect(block.outcome, GateOutcome.fail);
  });
}
