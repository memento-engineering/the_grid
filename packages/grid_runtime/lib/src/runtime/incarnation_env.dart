import 'dart:convert';
import 'dart:math';

import 'package:grid_trajectory/grid_trajectory.dart';

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

/// Mints an `attempt_id` — the trajectory log's CHAR(26) name for ONE process
/// incarnation (stage1-wiring §2.1; schema §3's one-attempt-one-incarnation).
///
/// Minted beside [newInstanceToken] at the SAME moment and with the same
/// lifetime: a fresh mount mints both, a re-key mints both again, and adoption
/// mints NEITHER (it continues what the `grid.lease.*` breadcrumb already
/// carries). The two are 1:1 — the token is the freshness fence a live
/// process echoes back, the attempt id is the trajectory's durable name for
/// the same incarnation.
///
/// Lives here rather than in the engine because `grid_trajectory` is a LEAF
/// (zero `grid_*` deps): `grid_runtime → grid_trajectory` is one of the two
/// dep edges Stage 1 adds, and the engine reaches the minter THROUGH this
/// package rather than growing a third edge of its own.
String newAttemptId() => mintUlid();

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
