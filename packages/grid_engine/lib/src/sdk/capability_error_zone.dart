import 'dart:async';

/// Runs one capability hook inside the allocation's async-error boundary.
Future<T> runCapabilityGuarded<T>(FutureOr<T> Function() body) {
  final result = Completer<T>();
  runZonedGuarded(
    () async {
      try {
        final value = await body();
        // Let an immediate detached rejection beat a normal hook return.
        await Future<void>.delayed(Duration.zero);
        if (!result.isCompleted) result.complete(value);
      } on Object catch (error, stackTrace) {
        if (!result.isCompleted) result.completeError(error, stackTrace);
      }
    },
    (error, stackTrace) {
      if (!result.isCompleted) result.completeError(error, stackTrace);
      // Once settled, keep absorbing errors from detached work in this zone.
    },
  );
  return result.future;
}
