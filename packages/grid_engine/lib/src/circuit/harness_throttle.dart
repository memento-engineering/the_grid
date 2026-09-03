/// Pure classification and diagnostics for artifact-less harness exits.
library;

/// Prefix persisted on every classified harness-throttle failure.
const String kHarnessThrottleMarker = 'harness-throttled';

/// Non-blocking signal emitted when a harness exit is classified as infra.
const String kHarnessThrottledFlare = 'harness.throttled';

/// An artifact-less failure under this floor is a harness non-result.
const Duration kHarnessSilenceFloor = Duration(seconds: 30);

/// Whether a failure is a fast non-result rather than failed work.
bool isHarnessSilence({required bool nonResult, required Duration? ranFor}) =>
    nonResult && ranFor != null && ranFor < kHarnessSilenceFloor;

/// Recovers the opening instant of a persisted throttle window.
DateTime harnessThrottleSince({
  required String? priorReason,
  required DateTime now,
}) {
  const opener = '$kHarnessThrottleMarker since ';
  final prior = priorReason ?? '';
  if (!prior.startsWith(opener)) return now.toUtc();
  final rest = prior.substring(opener.length);
  final end = rest.indexOf(' ');
  final stamp = end < 0 ? rest : rest.substring(0, end);
  return DateTime.tryParse(stamp)?.toUtc() ?? now.toUtc();
}

/// Builds the durable failure reason for a silent harness exit.
String harnessThrottleReason({
  required DateTime since,
  required int silentExits,
  required String exitOutputHead,
  required String underlying,
}) =>
    '$kHarnessThrottleMarker since ${since.toUtc().toIso8601String()} '
    'after $silentExits silent exit(s) — no artifact, no usage telemetry: '
    '${exitOutputHead.isEmpty ? 'no output captured; $underlying' : exitOutputHead}';

/// Builds the gate reason written when the infra restart budget is spent.
String harnessThrottleGateReason({
  required String sessionId,
  required String nodePath,
  required DateTime since,
  required int silentExits,
  required String exitOutputHead,
}) =>
    'harness throttled: $silentExits model steps exited without artifacts '
    'since ${since.toUtc().toIso8601String()} — session $sessionId, step '
    '$nodePath'
    '${exitOutputHead.isEmpty ? '' : ' — $exitOutputHead'}';
