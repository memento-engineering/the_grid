import 'package:beads_dart/beads_dart.dart';

import 'actuator.dart';

/// The production [IdempotencyProbe]: beads_dart's pooled, SELECT-only
/// `DoltQueryService.findWispByIdempotencyKey` — a LIVE query over the
/// parent-child edge + `metadata.idempotency_key` (ADR-0000 A15/A17).
///
/// This is the find-before-pour probe the [BdActuator] issues immediately
/// before `bd create --graph`: a hit is adopted (no pour), a miss pours. It is
/// deliberately the live path, not the snapshot scan — a fast actuation
/// routinely beats the Dolt watcher poll, so a stale-snapshot miss could pour
/// a duplicate that permanently inflates `deriveIterationCount` (invariant 4).
IdempotencyProbe doltIdempotencyProbe(DoltQueryService dolt) =>
    dolt.findWispByIdempotencyKey;

/// A probe that always misses — for a controller wired without a live SQL
/// path. **Unsafe for real pours** against a workspace where a concurrent
/// writer might race; use only where the snapshot-scan fast path
/// ([Convergence.findByIdempotencyKey]) is the sole guard (shadow mode never
/// pours at all). Exposed so a no-SQL composition is explicit, never an
/// accidental null.
Future<String?> alwaysMissProbe(String parentId, String key) async => null;
