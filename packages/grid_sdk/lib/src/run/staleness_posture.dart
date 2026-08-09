/// The staleness posture a station delegate chooses over the inspected
/// primary-checkout freshness vector — a station opinion (relocated from the
/// command's inline refusal, tg-1fa2.4), rendered by the shell.
sealed class StalenessPosture {
  const StalenessPosture();
}

/// Every checkout fresh — proceed silently.
final class StalenessClear extends StalenessPosture {
  /// Const-constructible.
  const StalenessClear();
}

/// Stale but accepted (`--allow-stale`): the shell warns with [message] on
/// stderr and proceeds.
final class StalenessWarned extends StalenessPosture {
  /// Creates the warning posture.
  const StalenessWarned(this.message);

  /// The warning line (the shell prefixes `<station> up: `).
  final String message;
}

/// Stale and refused: the shell writes [message] on stderr and exits 64.
final class StalenessRefused extends StalenessPosture {
  /// Creates the refusal posture.
  const StalenessRefused(this.message);

  /// The refusal line (the shell prefixes `<station> up: `).
  final String message;
}
