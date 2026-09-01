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
export 'src/append/service_event.dart'; // the stdout+flare notification seam (§5 clause c)
export 'src/append/trajectory_appender.dart'; // the fenced service core: epoch claim, CAS, error contract
export 'src/append/ulid.dart'; // CHAR(26) identity minting

// SECTION: tick — the service tick skeleton (§5).
export 'src/tick/obligation_query.dart'; // the obligation seam + Stage 0's empty set
export 'src/tick/tick_appender.dart'; // the narrow appender seam the tick runs over
export 'src/tick/tick_telemetry.dart'; // per-pass telemetry + the fixpoint result
export 'src/tick/trajectory_tick.dart'; // the interval loop, fence skip, runToFixpoint

// SECTION: cli — the traj verbs (traj show / traj shadow-diff / traj provision).
export 'src/cli/shadow_accounting.dart'; // per-round append accounting + its disqualification rule
export 'src/cli/traj_command.dart'; // the `traj` group; runners compose it explicitly
export 'src/cli/traj_flags.dart'; // the shared exact-root grid-home flag
export 'src/cli/traj_gc_command.dart'; // operator reclamation under the gridboot credential
export 'src/cli/traj_provision_command.dart'; // runbook §4 step 2: database + DDL + scoped user
export 'src/cli/traj_quiesce.dart'; // the station-lock/fence quiesce check + its SQL seams
export 'src/cli/traj_render.dart'; // typed row rendering (opaque rows stay opaque)
export 'src/cli/traj_replay_command.dart'; // quiesce-only fold rebuild + the P1 reshape + --check
export 'src/cli/traj_shadow_diff_command.dart'; // §9 comparator + injectable strategy
export 'src/cli/traj_show_command.dart'; // per-subject history
export 'src/cli/trajectory_reader.dart'; // read-only log seam + sealed open result

// SECTION: fold — the Family-1 P1 fold (§6 row 1 / §7 head summary).
export 'src/fold/fold_lag.dart'; // the reader lag rule + the proj_meta generation set
export 'src/fold/session_head_delta.dart'; // THE delta fn + its two appliers (SQL / in-memory)
export 'src/fold/session_head_fold.dart'; // replay: fold a stream, truncate + rewrite, proj_meta
export 'src/fold/session_head_row.dart'; // the proj_session_head row image

// SECTION: fold, Stage 1 — the P2 + P6 incremental folds (stage1-wiring W6).
export 'src/fold/process_identity_delta.dart'; // P6 delta fn + its two appliers (SQL / in-memory)
export 'src/fold/process_identity_fold.dart'; // P6 replay: fold, truncate + rewrite, proj_meta
export 'src/fold/process_identity_row.dart'; // the proj_process_identity row image
export 'src/fold/stage1_folds.dart'; // kStage1FoldDeltas — the appender step-5 registration set
export 'src/fold/step_cursor_delta.dart'; // P2 delta fn + its two appliers (SQL / in-memory)
export 'src/fold/step_cursor_fold.dart'; // P2 replay: fold, truncate + rewrite, proj_meta
export 'src/fold/step_cursor_row.dart'; // the proj_step_cursor row image + two-ladder key

// SECTION: shadow — the §9 comparator over the injected legacy read seam.
export 'src/shadow/attempt_lifecycle_shadow.dart'; // the real Family-1 ShadowCompare + allow-list seam
export 'src/shadow/legacy_session_reader.dart'; // dependency-free legacy session view + reader interface

// SECTION: shadow, Stage 1 — the step + mount-ordinal lanes (stage1-wiring W8).
export 'src/shadow/composite_shadow.dart'; // lane composition behind one ShadowCompare
export 'src/shadow/legacy_mount_attempt_reader.dart'; // the grid.attempt.count read seam
export 'src/shadow/legacy_step_reader.dart'; // dependency-free legacy step view + reader interface
export 'src/shadow/mount_ordinal_shadow.dart'; // the legacy_attempt_count join (§2.2)
export 'src/shadow/step_transition_shadow.dart'; // the Family-5 step-fact lane + named-gap classifier
