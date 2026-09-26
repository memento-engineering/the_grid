import 'dart:async';
import 'dart:io';

/// Runs one named teardown [action] without letting its failure abort unwind.
///
/// A future action is bounded by [within] when supplied. Failures are rendered
/// as a stable named-step refusal and sent to [onRefusal], or to stderr when no
/// sink is provided. Returns whether the action completed successfully.
///
/// [onTimeout] fires — in addition to [onRefusal] — when the bounded action
/// did not complete inside [within]. An expired step is no longer awaited: the
/// unwind moves on and the caller that wants to NAME what it stopped waiting
/// for (tg-supq — a resident that parks after its final flare tells nobody
/// what it is waiting on) records the step here.
Future<bool> settle(
  String step,
  FutureOr<void> Function() action, {
  Duration? within,
  void Function(String message)? onRefusal,
  void Function(String step, Duration within)? onTimeout,
}) async {
  try {
    final pending = action();
    if (pending is Future<void>) {
      await (within == null ? pending : pending.timeout(within));
    }
    return true;
  } on TimeoutException catch (error) {
    final message = 'unwind step "$step" failed: $error';
    (onRefusal ?? stderr.writeln)(message);
    if (within != null) onTimeout?.call(step, within);
    return false;
  } on Object catch (error) {
    final message = 'unwind step "$step" failed: $error';
    (onRefusal ?? stderr.writeln)(message);
    return false;
  }
}
