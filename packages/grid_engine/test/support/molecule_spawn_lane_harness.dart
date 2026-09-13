import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'molecule_spawn_semaphore.dart';

final class _TestRun {
  const _TestRun({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

final class _RunningTest {
  const _RunningTest({required this.started, required this.completed});

  final Future<void> started;
  final Future<_TestRun> completed;
}

Future<_RunningTest> _startTest(List<String> arguments) async {
  final process = await Process.start(Platform.resolvedExecutable, [
    'test',
    '-r',
    'compact',
    ...arguments,
  ], workingDirectory: Directory.current.path);
  final started = Completer<void>();
  final stdoutOutput = StringBuffer();
  final stderrOutput = StringBuffer();
  final stdoutDone = process.stdout.transform(utf8.decoder).listen((chunk) {
    stdoutOutput.write(chunk);
    if (!started.isCompleted) started.complete();
  }).asFuture<void>();
  final stderrDone = process.stderr.transform(utf8.decoder).listen((chunk) {
    stderrOutput.write(chunk);
    if (!started.isCompleted) started.complete();
  }).asFuture<void>();
  final completed = () async {
    final childExitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    if (!started.isCompleted) started.complete();
    return _TestRun(
      exitCode: childExitCode,
      stdout: stdoutOutput.toString(),
      stderr: stderrOutput.toString(),
    );
  }();
  return _RunningTest(started: started.future, completed: completed);
}

void _reportFailure(_TestRun run) {
  stderr.write(run.stdout);
  stderr.write(run.stderr);
}

Future<void> _runLane({required bool reportProbe}) async {
  final contenders = await Future.wait(
    List.generate(6, (_) => _startTest(const [])),
  );
  await Future.wait(contenders.map((contender) => contender.started));
  final budget = reportProbe ? await MoleculeSpawnStartBudget.probe() : null;
  final drainRuns = <_TestRun>[];
  for (var run = 0; run < 10; run++) {
    final drain = await _startTest(const [
      'test/molecule/drain_seam_test.dart',
    ]);
    drainRuns.add(await drain.completed);
  }
  final contenderRuns = await Future.wait(
    contenders.map((contender) => contender.completed),
  );

  final failures = [
    ...drainRuns,
    ...contenderRuns,
  ].where((run) => run.exitCode != 0).toList();
  if (failures.isNotEmpty) {
    for (final failure in failures) {
      _reportFailure(failure);
    }
    exitCode = 1;
    return;
  }

  if (budget != null) {
    stdout.writeln(
      'molecule spawn probe lane: '
      'latency=${budget.probeLatency.inMilliseconds}ms; '
      'budget=${budget.timeout.inMilliseconds}ms',
    );
  }
  stdout.writeln(
    'molecule spawn lane load: 10/10 drain runs passed; '
    '6/6 full-suite contenders passed',
  );
}

Future<void> main(List<String> arguments) async {
  switch (arguments) {
    case []:
      await _runLane(reportProbe: false);
    case ['--probe-only']:
      final budget = await MoleculeSpawnStartBudget.probe();
      stdout.writeln(
        'molecule spawn probe alone: '
        'latency=${budget.probeLatency.inMilliseconds}ms; '
        'budget=${budget.timeout.inMilliseconds}ms',
      );
    case ['--report-probe']:
      await _runLane(reportProbe: true);
    default:
      throw ArgumentError.value(arguments, 'arguments', 'unsupported mode');
  }
}
