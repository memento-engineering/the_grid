/// A composition-time refusal (a live lock holder, a lost steal race, an
/// unarmable roster) — the runner prints [message] and exits with [code]. The
/// one arming gate the station shell and the delegate's roster resolution
/// throw (the old `station_runner` assembly that also raised it is deleted;
/// the boot path moved to the asset's own runner + `runGrid`).
class StationRefusal implements Exception {
  /// Creates the refusal with its user-facing [message] and exit [code].
  const StationRefusal(this.message, {this.code = 64});

  /// The user-facing refusal text.
  final String message;

  /// The process exit code (64 = usage, 1 = environment).
  final int code;

  @override
  String toString() => message;
}
