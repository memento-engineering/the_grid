import 'dart:io';

import 'package:beads_dart/src/errors/bd_exception.dart';
import 'package:beads_dart/src/services/bd_runner.dart';
import 'package:test/test.dart';

/// tg-hceh — the post-exit pipe drain must be BOUNDED.
///
/// `_runOne` cancels the kill-timer the instant the child exits, then awaits
/// stdout/stderr EOF. EOF only arrives once every fd-INHERITING descendant
/// releases the pipe — a store daemon left behind by a bd op holds it open
/// indefinitely. Before the fix that await was unbounded: `guarded` never
/// released its permit, and a handful of leaks emptied the station-wide
/// 4-permit write semaphore — every later write parked on `acquire()`
/// forever while the VM sat idle (the silent-station latch; three arms in
/// one day, receipts on tg-hceh).
void main() {
  test('a descendant holding the pipe cannot leak the permit — the drain '
      'detaches after drainGrace and returns the buffered output', () async {
    final runner = ProcessBdRunner(
      workspaceRoot: Directory.systemTemp.path,
      executable: '/bin/bash',
      maxConcurrency: 1,
      environment: const {},
    );

    final sw = Stopwatch()..start();
    // The parent writes and exits immediately; the backgrounded sleep
    // inherits stdout and holds the pipe's write end long past the test.
    final result = await runner.run([
      '-c',
      'sleep 30 & echo held-open; exit 0',
    ]);
    sw.stop();

    expect(result.exitCode, 0);
    expect(
      result.stdout.trim(),
      'held-open',
      reason: 'buffered output survives the detach',
    );
    expect(
      sw.elapsed,
      lessThan(const Duration(seconds: 10)),
      reason:
          'the drain must give up after drainGrace, not wait 30s for '
          'the descendant to release the pipe',
    );

    // THE regression claim: the permit was released. With maxConcurrency: 1
    // a leaked permit would park this second run on acquire() forever.
    final second = await runner
        .run(['-c', 'echo again'])
        .timeout(const Duration(seconds: 10));
    expect(second.stdout.trim(), 'again');
  });

  test(
    'a clean child (no descendant) drains to EOF exactly as before',
    () async {
      final runner = ProcessBdRunner(
        workspaceRoot: Directory.systemTemp.path,
        executable: '/bin/bash',
        environment: const {},
      );
      final result = await runner.run(['-c', 'echo out; echo err >&2; exit 3']);
      expect(result.exitCode, 3);
      expect(result.stdout.trim(), 'out');
      expect(result.stderr.trim(), 'err');
    },
  );

  test('the timeout SIGKILL path still throws and still returns promptly '
      'even when a descendant holds the pipe', () async {
    final runner = ProcessBdRunner(
      workspaceRoot: Directory.systemTemp.path,
      executable: '/bin/bash',
      environment: const {},
    );
    final sw = Stopwatch()..start();
    await expectLater(
      runner.run([
        '-c',
        'sleep 30 & sleep 30',
      ], timeout: const Duration(seconds: 1)),
      throwsA(isA<BdTimeoutException>()),
    );
    sw.stop();
    expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
  });
}
