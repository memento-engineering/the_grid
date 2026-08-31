/// The mount-ordinal lane's LEGACY side — the durable remount-attempt count
/// carried by one work bead's `type=mount-attempt` bead.
///
/// stage1-wiring §2.2 (r2, major 8) exists because of a join problem:
/// `mount_attempt_id` is a recorder-minted ULID, so it has no legacy
/// counterpart and cannot be shadowed. The legacy bead's `grid.attempt.count`
/// CAN be — it is merged in place, one bead per work bead, and the recorder
/// copies it onto the record as `legacy_attempt_count`. §4 names it
/// explicitly: it "exists precisely to keep the mint ordinal in the shared
/// set" of the cut's evidence pack.
///
/// Leaf discipline as everywhere else in `shadow/`: the interface here, the
/// beads_dart implementation in grid_cli.
library;

/// The injected legacy read seam, keyed by the ORIGINAL (never re-keyed) work
/// bead id. Null means the ledger carries no mount-attempt bead for it —
/// which is the ordinary state of a bead that mounted first try, not an
/// error.
abstract interface class LegacyMountAttemptReader {
  Future<int?> attemptCount(String workBeadId);
}
