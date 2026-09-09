import 'dart:async';
import 'dart:io';

/// Runs one named teardown [action] without letting its failure abort unwind.
///
/// A future action is bounded by [within] when supplied. Failures are rendered
/// as a stable named-step refusal and sent to [onRefusal], or to stderr when no
/// sink is provided. Returns whether the action completed successfully.
Future<bool> settle(
  String step,
  FutureOr<void> Function() action, {
  Duration? within,
  void Function(String message)? onRefusal,
}) async {
  try {
    final pending = action();
    if (pending is Future<void>) {
      await (within == null ? pending : pending.timeout(within));
    }
    return true;
  } on Object catch (error) {
    final message = 'unwind step "$step" failed: $error';
    (onRefusal ?? stderr.writeln)(message);
    return false;
  }
}
