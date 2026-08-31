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

// SECTION: connect — the write-capable SQL seam to the underlying server.
export 'src/connect/server_config.dart'; // dolt sql-server listener resolution (never bd's proxy)
export 'src/connect/trajectory_connection.dart'; // real session + connect-time guards (force-commit ban, branch pin)
export 'src/connect/trajectory_db.dart'; // TrajectoryDb seam + §5 error-code classification

// SECTION: ddl — schema DDL + database bootstrap.
export 'src/ddl/trajectory_provisioning.dart'; // write-capable SQL user, secret under .grid/trajectory/
export 'src/ddl/trajectory_schema.dart'; // §4 verbatim DDL, dolt_ignore-first, idempotent

// SECTION: append — the fenced append client (§5 write path).
export 'src/append/append_outcome.dart'; // sealed append/claim dispositions
export 'src/append/trajectory_appender.dart'; // the fenced service core: epoch claim, CAS, error contract
export 'src/append/ulid.dart'; // CHAR(26) identity minting

// SECTION: tick — the service tick skeleton (§5).

// SECTION: cli — the traj verbs (traj show / traj shadow-diff).
export 'src/cli/traj_command.dart'; // the `traj` group; runners compose it explicitly
export 'src/cli/traj_flags.dart'; // the shared exact-root grid-home flag
export 'src/cli/traj_render.dart'; // typed row rendering (opaque rows stay opaque)
export 'src/cli/traj_shadow_diff_command.dart'; // §9 comparator + injectable strategy
export 'src/cli/traj_show_command.dart'; // per-subject history
export 'src/cli/trajectory_reader.dart'; // read-only log seam + sealed open result
