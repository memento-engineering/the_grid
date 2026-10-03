import 'dart:async';
import 'dart:io';

/// Runs one named teardown [action] without letting its failure abort unwind.
///
/// A future action is bounded by [within] when supplied. Failures are rendered
/// as a stable named-step refusal and sent to [onRefusal], or to stderr when no
/// sink is provided. Returns whether the action completed successfully.
///
/// [onTimeout] fires — in addition to [onRefusal] — ONLY when the budget
/// [within] expired before the action completed. An expired step is no longer
/// awaited: the unwind moves on and the caller that wants to NAME what it
/// stopped waiting for (tg-supq — a resident that parks after its final flare
/// tells nobody what it is waiting on) records the step here.
///
/// An action that itself THROWS a [TimeoutException] (a close whose own
/// internal timer fired after one second under a five-second budget) is a
/// FAILURE, not a budget expiry: it is refused like any other error, carries
/// the action's own exception text, and never fires [onTimeout]. The expiry is
/// detected by the budget's own `onTimeout` callback rather than by catching
/// the exception type, so the two can never be confused (tg-supq review).
Future<bool> settle(
  String step,
  FutureOr<void> Function() action, {
  Duration? within,
  void Function(String message)? onRefusal,
  void Function(String step, Duration within)? onTimeout,
}) async {
  final refuse = onRefusal ?? stderr.writeln;
  try {
    final pending = action();
    if (pending is Future<void>) {
      if (within == null) {
        await pending;
      } else {
        var expired = false;
        await pending.timeout(
          within,
          onTimeout: () {
            expired = true;
          },
        );
        if (expired) {
          refuse(
            'unwind step "$step" failed: budget of ${within.inMilliseconds}ms '
            'expired — no longer awaited',
          );
          onTimeout?.call(step, within);
          return false;
        }
      }
    }
    return true;
  } on Object catch (error) {
    refuse('unwind step "$step" failed: $error');
    return false;
  }
}

/// One TOTAL deadline an unwind draws every step's budget from (tg-supq).
///
/// Per-step budgets alone sum with the roster; this caps the sum. [budget]
/// hands a step the smaller of its own bound and what is left — and
/// [Duration.zero] once the deadline has passed, so a late step is still
/// STARTED (its close requested) but never awaited.
final class UnwindDeadline {
  /// Starts the clock on a [total] budget now.
  UnwindDeadline(this.total) : _watch = Stopwatch()..start();

  /// The total the unwind may spend.
  final Duration total;

  final Stopwatch _watch;

  /// Wall-clock spent since the clock started.
  Duration get elapsed => _watch.elapsed;

  /// What is left of [total]; never negative.
  Duration get remaining {
    final left = total - _watch.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// True once [total] has been spent.
  bool get expired => remaining == Duration.zero;

  /// The budget for a step whose own bound is [own]: the smaller of [own] and
  /// [remaining] less [reserve] (a share held back for the steps after it).
  Duration budget(Duration own, {Duration reserve = Duration.zero}) {
    final left = remaining - reserve;
    final available = left.isNegative ? Duration.zero : left;
    return own < available ? own : available;
  }
}
