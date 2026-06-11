import 'dart:async';

import 'package:grid_controller/src/services/bd_runner.dart';

/// A programmable [BdRunner] for offline tests (ADR-0001 D7: Fakes, not mocks).
///
/// Replies are matched against an invocation's args by a [BdMatcher]
/// predicate; the first matching reply wins. Every call is recorded in [calls]
/// (the full argv) so tests can assert exact flags (`--actor grid-controller`,
/// `--json`, multi-id forms). A reply may carry a delay (to exercise the
/// runner-level timeout) and a non-zero exit (to exercise the failure path).
///
/// Concurrency is observable: [maxConcurrent] records the high-water mark of
/// in-flight [run] calls, which the semaphore test asserts.
class FakeBdRunner implements BdRunner {
  FakeBdRunner({List<BdReply>? replies}) : _replies = replies ?? <BdReply>[];

  final List<BdReply> _replies;

  /// Every invocation's argv, in call order.
  final List<List<String>> calls = <List<String>>[];

  /// Each invocation's piped stdin (null when none), parallel to [calls].
  final List<String?> stdins = <String?>[];

  /// In-flight call count and its high-water mark.
  int _inFlight = 0;
  int maxConcurrent = 0;

  /// Registers a [reply] returned when [matcher] accepts an invocation. Replies
  /// are matched in registration order. Returns `this` for chaining.
  FakeBdRunner stub(BdMatcher matcher, BdReply reply) {
    _replies.add(reply.withMatcher(matcher));
    return this;
  }

  /// Convenience: reply for any invocation whose first arg equals [command].
  FakeBdRunner stubCommand(String command, BdReply reply) =>
      stub((args) => args.isNotEmpty && args.first == command, reply);

  /// Convenience: reply for an exact subcommand pair (e.g. `dep`/`list`).
  FakeBdRunner stubSub(String a, String b, BdReply reply) =>
      stub((args) => args.length >= 2 && args[0] == a && args[1] == b, reply);

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    stdins.add(stdin);
    _inFlight++;
    if (_inFlight > maxConcurrent) maxConcurrent = _inFlight;
    try {
      final reply = _match(args);
      if (reply.delay > Duration.zero) {
        await Future<void>.delayed(reply.delay);
      }
      return BdResult(
        exitCode: reply.exitCode,
        stdout: reply.stdout,
        stderr: reply.stderr,
      );
    } finally {
      _inFlight--;
    }
  }

  BdReply _match(List<String> args) {
    for (final reply in _replies) {
      final matcher = reply.matcher;
      if (matcher == null) continue;
      if (matcher(args)) return reply;
    }
    throw StateError('FakeBdRunner: no stubbed reply for ${args.join(' ')}');
  }
}

/// Predicate over an invocation's argv.
typedef BdMatcher = bool Function(List<String> args);

/// A canned [BdRunner] reply.
class BdReply {
  const BdReply({
    this.stdout = '',
    this.stderr = '',
    this.exitCode = 0,
    this.delay = Duration.zero,
    this.matcher,
  });

  final String stdout;
  final String stderr;
  final int exitCode;
  final Duration delay;
  final BdMatcher? matcher;

  BdReply withMatcher(BdMatcher matcher) => BdReply(
    stdout: stdout,
    stderr: stderr,
    exitCode: exitCode,
    delay: delay,
    matcher: matcher,
  );
}
