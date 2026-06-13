/// Byte-faithful port of gc's convergence idempotency keys
/// (`gascity/internal/convergence/handler.go:11-39`).
///
/// Keys have the shape `converge:{beadID}:iter:{N}` (N is 1-based for real
/// wisps; the functions themselves do not validate that). They are stored in
/// the wisp root bead's `metadata.idempotency_key` (gc
/// `cmd/gc/convergence_store.go`, "idempotency_key"; the_grid pours them the
/// same way per ADR-0000 A15).
library;

import 'go_scalars.dart';

/// The metadata key on a **wisp** bead that carries its idempotency key.
/// Bead-level (no `convergence.` namespace) — `cmd/gc/convergence_store.go`
/// reads `b.Metadata["idempotency_key"]`.
const String wispIdempotencyKeyField = 'idempotency_key';

/// Port of `IdempotencyKeyPrefix` (handler.go:13-15): the prefix shared by
/// every convergence wisp key belonging to [beadId].
String idempotencyKeyPrefix(String beadId) => 'converge:$beadId:iter:';

/// Port of `IdempotencyKey` (handler.go:19-21): the key for a specific
/// [iteration]. Like Go's `%d`, a negative iteration formats with a minus
/// sign (`converge:x:iter:-1`) — the function does not validate.
String idempotencyKey(String beadId, int iteration) =>
    'converge:$beadId:iter:$iteration';

/// Port of `ParseIterationFromKey` (handler.go:26-39). Returns the iteration
/// or null (Go's `(0, false)`).
///
/// Faithful behavior, including the odd corners:
///
/// * Finds the **last** `:iter:` marker (`strings.LastIndex`), so bead IDs
///   containing `:` — even containing `:iter:` themselves — parse correctly:
///   `converge:a:iter:b:iter:3` → 3.
/// * The suffix is parsed with `strconv.Atoi` semantics ([goAtoi]): optional
///   sign then decimal digits only. So `:iter:+5` → 5 and `:iter:-0` → 0
///   (both genuine Go behaviors), while `:iter: 5`, `:iter:0x10`,
///   `:iter:5a`, and an empty suffix all fail.
/// * Negative results are rejected **after** parsing (`n < 0`, handler.go:35),
///   so 0 succeeds but `-1` returns null.
/// * Values overflowing int64 fail (Atoi `ErrRange`).
int? parseIterationFromKey(String key) {
  const marker = ':iter:';
  final idx = key.lastIndexOf(marker);
  if (idx < 0) return null;
  final numStr = key.substring(idx + marker.length);
  final n = goAtoi(numStr);
  if (n == null || n < 0) return null;
  return n;
}
