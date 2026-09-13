import 'dart:io';

/// A probe-derived wall-clock budget for a molecule process to report START.
///
/// The 30-second floor preserves the historical isolated-suite budget. The
/// multiplier lets a suite process account for the machine's measured Dart
/// spawn-to-first-output latency before it enters any START window.
final class MoleculeSpawnStartBudget {
  const MoleculeSpawnStartBudget({
    required this.probeLatency,
    required this.timeout,
  });

  static const minimum = Duration(seconds: 30);
  static const multiplier = 20;

  final Duration probeLatency;
  final Duration timeout;

  factory MoleculeSpawnStartBudget.derive(Duration probeLatency) {
    final scaled = probeLatency * multiplier;
    return MoleculeSpawnStartBudget(
      probeLatency: probeLatency,
      timeout: scaled > minimum ? scaled : minimum,
    );
  }

  static Future<MoleculeSpawnStartBudget> probe() async {
    final stopwatch = Stopwatch()..start();
    final process = await Process.start(Platform.resolvedExecutable, const [
      '--version',
    ]);
    Duration? firstOutputLatency;

    void observeOutput(List<int> chunk) {
      if (chunk.isNotEmpty && firstOutputLatency == null) {
        firstOutputLatency = stopwatch.elapsed;
      }
    }

    final stdoutDone = process.stdout.listen(observeOutput).asFuture<void>();
    final stderrDone = process.stderr.listen(observeOutput).asFuture<void>();
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    stopwatch.stop();

    if (exitCode != 0) {
      throw StateError('Dart spawn probe exited with code $exitCode');
    }
    final latency = firstOutputLatency;
    if (latency == null) {
      throw StateError('Dart spawn probe produced no output');
    }
    return MoleculeSpawnStartBudget.derive(latency);
  }

  String get diagnostic =>
      'probe latency=${probeLatency.inMilliseconds}ms; '
      'derived START budget=${timeout.inMilliseconds}ms; '
      'minimum=${minimum.inMilliseconds}ms; multiplier=${multiplier}x';
}

/// A shared cross-process spawn semaphore for molecule tests.
///
/// The single permit covers only the state trigger through verification of the
/// exact `START`. It never covers the running/completion phase. A suite derives
/// that START wait as max(30 seconds, 20 x measured first-output latency).
/// Binding a fixed loopback port makes the permit visible to package:test
/// isolates and to independent Dart test runner processes; process-level file
/// locks do not serialize sibling isolates reliably.
abstract final class MoleculeSpawnSemaphore {
  static const _permitPort = 54281;

  static Future<T> run<T>(Future<T> Function() action) async {
    ServerSocket? permit;
    while (permit == null) {
      try {
        permit = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          _permitPort,
          shared: false,
        );
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    try {
      return await action();
    } finally {
      await permit.close();
    }
  }
}
