import 'dart:convert';
import 'dart:math';

/// The per-incarnation environment a live agent session receives from the
/// controller — the_grid's `GRID_*` analog of gc's `session.RuntimeEnv`
/// (`gascity/internal/session/lifecycle.go:30-67`), trimmed to the four vars
/// M3 needs (M3-BUILD-ORDER Track 2).
///
/// Renamed `GC_*` → `GRID_*` so a the_grid-spawned agent never collides with a
/// gc-spawned one sharing the same host (coexistence; CLAUDE.md). gc's
/// `RuntimeEnv` carries five vars and the alias/template/origin extensions
/// (`lifecycle.go:42-67`); the_grid's M3 dogfood needs only:
///
/// * `GRID_SESSION_ID`     — the session bead id (the session's identity);
/// * `GRID_BEAD_ID`        — the **work** bead this incarnation is working;
/// * `GRID_INSTANCE_TOKEN` — a cryptographically random fence for stop/async
///   delivery against a stale incarnation (gc's `NewInstanceToken`,
///   `lifecycle.go:21-27`);
/// * `GRID_RUNTIME_EPOCH`  — the restart generation (gc's `GC_RUNTIME_EPOCH`,
///   `lifecycle.go:35`; first incarnation = 1).
///
/// A value type (a plain record of strings) — it carries no IO and no
/// classifier (predictable-flutter).
class IncarnationEnv {
  IncarnationEnv({
    required this.sessionId,
    required this.beadId,
    required this.instanceToken,
    this.runtimeEpoch = defaultGeneration,
  });

  /// Mints an [IncarnationEnv] with a fresh random [instanceToken].
  factory IncarnationEnv.mint({
    required String sessionId,
    required String beadId,
    int runtimeEpoch = defaultGeneration,
    Random? random,
  }) => IncarnationEnv(
    sessionId: sessionId,
    beadId: beadId,
    instanceToken: newInstanceToken(random),
    runtimeEpoch: runtimeEpoch,
  );

  /// The first runtime epoch for a newly created session (gc's
  /// `DefaultGeneration`, `lifecycle.go:13`).
  static const int defaultGeneration = 1;

  /// `GRID_SESSION_ID` — the session bead id.
  final String sessionId;

  /// `GRID_BEAD_ID` — the work bead this incarnation is working.
  final String beadId;

  /// `GRID_INSTANCE_TOKEN` — the random fence (gc's instance token).
  final String instanceToken;

  /// `GRID_RUNTIME_EPOCH` — the restart generation (>= 1).
  final int runtimeEpoch;

  /// The env vars to inject, last over the allowlist (gc layers these on the
  /// runtime env after the passthrough). Keys are stable so a process-table
  /// scan / a future reaper can recover the session identity.
  Map<String, String> toEnv() => <String, String>{
    'GRID_SESSION_ID': sessionId,
    'GRID_BEAD_ID': beadId,
    'GRID_INSTANCE_TOKEN': instanceToken,
    'GRID_RUNTIME_EPOCH': runtimeEpoch.toString(),
  };

  @override
  String toString() =>
      'IncarnationEnv(session=$sessionId, bead=$beadId, epoch=$runtimeEpoch)';
}

/// A cryptographically random 16-byte hex token for fencing drain/stop and
/// async delivery against a stale session incarnation — gc's
/// `session.NewInstanceToken` (`lifecycle.go:21-27`).
///
/// Uses [Random.secure] by default; tests inject a deterministic [Random] for
/// reproducible tokens (the fence value itself is never security-load-bearing
/// in a test).
String newInstanceToken([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return const HexEncoder().convert(bytes);
}

/// Minimal lowercase-hex encoder (avoids a `convert` dependency surface beyond
/// `dart:convert`'s `Codec`).
class HexEncoder extends Converter<List<int>, String> {
  const HexEncoder();

  @override
  String convert(List<int> input) {
    final sb = StringBuffer();
    for (final b in input) {
      sb.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
