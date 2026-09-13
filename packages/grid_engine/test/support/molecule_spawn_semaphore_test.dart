import 'package:test/test.dart';

import 'molecule_spawn_semaphore.dart';

final class _FakeProbeProcessRunner {
  const _FakeProbeProcessRunner({
    required this.exitCode,
    this.stdout,
    this.stderr,
  });

  final int exitCode;
  final List<int>? stdout;
  final List<int>? stderr;

  Future<int> call(
    void Function(List<int>) onStdout,
    void Function(List<int>) onStderr,
  ) async {
    if (stdout case final stdout?) onStdout(stdout);
    if (stderr case final stderr?) onStderr(stderr);
    return exitCode;
  }
}

void main() {
  test('run serializes concurrent bodies', () async {
    var inFlight = 0;
    var maximumInFlight = 0;

    final results = await Future.wait([
      for (var value = 0; value < 8; value++)
        MoleculeSpawnSemaphore.run(() async {
          inFlight += 1;
          maximumInFlight = maximumInFlight < inFlight
              ? inFlight
              : maximumInFlight;
          await Future<void>.delayed(Duration.zero);
          inFlight -= 1;
          return value;
        }),
    ]);

    expect(maximumInFlight, 1);
    expect(results.toSet(), {0, 1, 2, 3, 4, 5, 6, 7});
  });

  test('probe returns the injected first-output latency', () async {
    const runner = _FakeProbeProcessRunner(exitCode: 0, stdout: [1]);

    final budget = await MoleculeSpawnStartBudget.probe(
      processRunner: runner.call,
      elapsed: () => const Duration(milliseconds: 5),
    );

    expect(budget.probeLatency, const Duration(milliseconds: 5));
    expect(budget.timeout, const Duration(seconds: 30));
  });

  test('probe rejects a non-zero exit', () async {
    const runner = _FakeProbeProcessRunner(exitCode: 17, stderr: [1]);

    await expectLater(
      MoleculeSpawnStartBudget.probe(
        processRunner: runner.call,
        elapsed: () => const Duration(milliseconds: 5),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Dart spawn probe exited with code 17',
        ),
      ),
    );
  });

  test('probe rejects an empty output stream', () async {
    const runner = _FakeProbeProcessRunner(exitCode: 0);

    await expectLater(
      MoleculeSpawnStartBudget.probe(
        processRunner: runner.call,
        elapsed: () => const Duration(milliseconds: 5),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Dart spawn probe produced no output',
        ),
      ),
    );
  });
}
