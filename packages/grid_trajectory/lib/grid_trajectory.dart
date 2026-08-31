/// Trajectory log substrate (tg-zfek Stage 0).
///
/// The contract is `docs/design/trajectory/trajectory-schema.md`: one
/// append-only `trajectory` table in a separate `trajectory` database, a
/// sealed record codec (§2.6), the §5 idem-key grammar, the T6i counter-CAS
/// fence, and the `traj` verbs. This package is a LEAF — zero grid_*
/// dependencies (decision: grid-trajectory-leaf-package); stations compose it
/// explicitly.
///
/// Later seats append exports under their own SECTION marker; do not reorder
/// or merge the sections.
library;

// SECTION: codec — envelope, sealed record types, idem-key grammar, registry.
export 'src/codec/codec_registry.dart'; // (record_type, type_version) → fromJson dispatch
export 'src/codec/envelope.dart'; // the §1 row image + envelope enums
export 'src/codec/idem_key.dart'; // SHA-256 idem/effect identity builders
export 'src/codec/trajectory_record.dart'; // sealed TrajectoryRecord + all §2 types

// SECTION: ddl — schema DDL + database bootstrap.

// SECTION: append — the fenced append client (§5 write path).

// SECTION: tick — the service tick skeleton (§5).

// SECTION: cli — the traj verbs (traj show / traj shadow-diff).
