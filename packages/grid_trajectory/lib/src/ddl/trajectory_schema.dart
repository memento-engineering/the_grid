/// The §4 DDL as an executable, idempotent bootstrap.
///
/// Statement text is the schema doc's §4 verbatim (verified verbatim-accepted
/// by dolt 2.2.2, probe T1) with `IF NOT EXISTS` discipline added so re-boots
/// are no-ops. Order is load-bearing: the `dolt_ignore` registration runs
/// FIRST (§4 STEP 0 — probe T3), before any table exists to be committed.
///
/// Everything here targets the `trajectory` database — a sibling of the
/// ledger database on the same bd-owned server (storage call, ratified
/// 2026-08-31). Direct SQL writes are the DESIGNED exception to the
/// bd-CLI-only orthodoxy, scoped to this database alone (decision:
/// trajectory-direct-sql-scope).
library;

import '../connect/trajectory_db.dart';

/// §4 STEP 0 — before anything else. `traj_fence` and `traj_pulse` are
/// working-set state; `proj_%` covers every projection.
const String doltIgnoreSeedSql =
    "INSERT INTO dolt_ignore VALUES ('proj_%', true), ('traj_pulse', true), "
    "('traj_fence', true)";

/// P1's CREATE TABLE, named separately because it is the ONE projection the
/// wave-1 cut reshapes (cut-wiring C0, r6/r7 — J11-B1/V1-B1): the fold gains
/// `terminal_provenance` + `unknown_reason`, so the durable head can say
/// whether a terminal is observed testimony or a reconstructed close, and
/// which explicit-unknown vocabulary word an `outcome='unknown'` carries.
///
/// The migration is a DROP + re-CREATE at this shape plus a full replay
/// ([reshapeSessionHeadProjection]) — never an ALTER: nothing in the tree
/// reshapes an existing table, `applyTrajectorySchema` is CREATE-IF-NOT-EXISTS
/// only, and `proj_%` is `dolt_ignore`'d, so the drop is journal-invisible and
/// costs one replay.
const String projSessionHeadDdl = '''
CREATE TABLE IF NOT EXISTS proj_session_head (
  session_id VARCHAR(40) NOT NULL PRIMARY KEY,
  work_bead_id VARCHAR(40) NOT NULL,
  round INT NOT NULL DEFAULT 0,
  status ENUM('open','closed') NOT NULL,
  outcome ENUM('succeeded','failed','cancelled','lost','escalated','settled','unknown') NULL,
  work_terminal_reason VARCHAR(255) NULL,
  terminal_provenance ENUM('observed','inferred','reconstructed') NULL,
  unknown_reason VARCHAR(32) NULL,
  held TINYINT(1) NOT NULL DEFAULT 0, held_reason VARCHAR(512) NULL,
  pgid INT NULL, pid INT NULL, attempt_id CHAR(26) NULL,
  rig VARCHAR(64) NULL, model VARCHAR(32) NULL,
  substation VARCHAR(64) NULL,
  started_at DATETIME(6) NOT NULL, closed_at DATETIME(6) NULL,
  head_epoch BIGINT NOT NULL,
  last_seq BIGINT NOT NULL,
  KEY ix_bead (work_bead_id, status)
)''';

/// The columns added or renamed across P1 projection-shape cuts. A home
/// provisioned before any listed column fails
/// [sessionHeadProjectionNeedsReshape] and is rebuilt from the journal.
const List<String> projSessionHeadCutColumns = [
  'terminal_provenance',
  'unknown_reason',
  'substation',
];

/// Every §4 CREATE TABLE, in the doc's order.
const List<String> trajectoryTableDdl = [
  '''
CREATE TABLE IF NOT EXISTS traj_epoch (
  station     VARCHAR(64)  NOT NULL,
  epoch       BIGINT       NOT NULL,
  pid INT NOT NULL, pgid INT NOT NULL,
  cause       ENUM('boot','steal') NOT NULL,
  advanced_at DATETIME(6)  NOT NULL,
  PRIMARY KEY (station, epoch)
)''',
  '''
CREATE TABLE IF NOT EXISTS traj_fence (
  station     VARCHAR(64) NOT NULL PRIMARY KEY,
  fence_state BIGINT      NOT NULL
)''',
  '''
CREATE TABLE IF NOT EXISTS trajectory (
  seq              BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
  boot_epoch       BIGINT       NOT NULL,
  epoch_seq        BIGINT       NOT NULL,
  record_id        CHAR(26)     NOT NULL,
  idem_key         CHAR(64)     NOT NULL,
  idem_key_text    VARCHAR(512) NOT NULL,
  family           ENUM('attempt','admission','verification','effect','step') NOT NULL,
  record_type      VARCHAR(48)  NOT NULL,
  type_version     SMALLINT     NOT NULL DEFAULT 1,
  occurred_at      DATETIME(6)  NOT NULL,
  recorded_at      DATETIME(6)  NOT NULL,
  station          VARCHAR(64)  NOT NULL,
  substation       VARCHAR(64)  NULL,
  authority_id     VARCHAR(64)  NOT NULL,
  fencing_token    BIGINT       NULL,
  provenance       ENUM('observed','inferred','reconstructed') NOT NULL DEFAULT 'observed',
  provenance_basis VARCHAR(128) NULL,
  source           VARCHAR(160) NOT NULL,
  resolves_record_id CHAR(26)   NULL,
  work_bead_id     VARCHAR(40)  NULL,
  session_id       VARCHAR(40)  NULL,
  round            INT          NULL,
  step_round       INT          NULL,
  step_path        VARCHAR(255) NULL,
  incarnation      INT          NULL,
  attempt_id       CHAR(26)     NULL,
  mount_attempt_id CHAR(26)     NULL,
  grant_id         CHAR(26)     NULL,
  effect_id        CHAR(64)     NULL,
  gate_id          VARCHAR(64)  NULL,
  worktree         VARCHAR(255) NULL,
  branch           VARCHAR(160) NULL,
  commit_sha       CHAR(40)     NULL,
  receipt          VARCHAR(255) NULL,
  expires_at       DATETIME(6)  NULL,
  outcome          ENUM('succeeded','failed','cancelled','lost','escalated','settled','unknown') NULL,
  unknown_reason   VARCHAR(32)  NULL,
  payload          JSON         NOT NULL,
  UNIQUE KEY uq_record_id (record_id),
  UNIQUE KEY uq_idem      (idem_key),
  UNIQUE KEY uq_epoch_seq (station, boot_epoch, epoch_seq),
  KEY ix_bead    (work_bead_id, seq),
  KEY ix_session (session_id, seq),
  KEY ix_attempt (attempt_id, seq),
  KEY ix_step    (session_id, round, step_path, step_round, seq),
  KEY ix_type    (record_type, seq),
  KEY ix_effect  (effect_id),
  KEY ix_gate    (gate_id, seq),
  KEY ix_sha     (commit_sha),
  KEY ix_receipt (receipt),
  KEY ix_fence_token (fencing_token),
  CONSTRAINT ck_prov      CHECK (provenance = 'observed' OR provenance_basis IS NOT NULL),
  CONSTRAINT ck_terminal  CHECK (record_type <> 'attempt.terminal' OR outcome IS NOT NULL),
  CONSTRAINT ck_unknown   CHECK (outcome IS NULL OR outcome <> 'unknown' OR unknown_reason IS NOT NULL),
  CONSTRAINT ck_provision CHECK (record_type <> 'worktree.provisioned'
                                 OR (commit_sha IS NOT NULL AND branch IS NOT NULL)),
  CONSTRAINT ck_grant     CHECK (record_type <> 'admission.grant.issued'
                                 OR (grant_id IS NOT NULL AND expires_at IS NOT NULL
                                     AND fencing_token IS NOT NULL)),
  CONSTRAINT ck_grant_link CHECK (record_type NOT IN
                                  ('admission.grant.consumed','admission.grant.expired',
                                   'admission.grant.released','attempt.session.started')
                                 OR grant_id IS NOT NULL),
  CONSTRAINT ck_substation CHECK (work_bead_id IS NULL OR substation IS NOT NULL)
)''',
  '''
CREATE TABLE IF NOT EXISTS traj_terminal_guard (
  attempt_id CHAR(26) NOT NULL PRIMARY KEY,
  seq        BIGINT   NOT NULL,
  settled_by CHAR(26) NULL
)''',
  '''
CREATE TABLE IF NOT EXISTS traj_pulse (
  subject_id  VARCHAR(64) NOT NULL,
  kind        ENUM('attempt','lease') NOT NULL,
  boot_epoch  BIGINT      NOT NULL,
  beat_at     DATETIME(6) NOT NULL,
  observed_via ENUM('runtime','worktree-mtime','vm-service','wire') NOT NULL,
  PRIMARY KEY (subject_id, kind)
)''',
  '''
CREATE TABLE IF NOT EXISTS proj_meta (
  projection   VARCHAR(32) NOT NULL PRIMARY KEY,
  fold_version INT         NOT NULL,
  applied_seq  BIGINT      NOT NULL,
  skipped      JSON        NULL,
  rebuilt_at   DATETIME(6) NULL
)''',
  projSessionHeadDdl,
  '''
CREATE TABLE IF NOT EXISTS proj_step_cursor (
  session_id VARCHAR(40) NOT NULL, round INT NOT NULL,
  step_path VARCHAR(255) NOT NULL, step_round INT NOT NULL,
  state ENUM('pending','running','ready','complete','failed','gated') NOT NULL,
  incarnation INT NOT NULL, attempt_id CHAR(26) NULL,
  superseded_by_step_round INT NULL,
  cooldown_until DATETIME(6) NULL, restart_budget INT NULL,
  started_at DATETIME(6) NULL, ready_at DATETIME(6) NULL, completed_at DATETIME(6) NULL,
  failure_class VARCHAR(24) NULL, result JSON NULL, last_seq BIGINT NOT NULL,
  PRIMARY KEY (session_id, round, step_path, step_round),
  KEY ix_state (state, cooldown_until)
)''',
  '''
CREATE TABLE IF NOT EXISTS proj_step_edges (
  session_id VARCHAR(40) NOT NULL, round INT NOT NULL,
  from_path VARCHAR(255) NOT NULL, to_path VARCHAR(255) NOT NULL,
  kind ENUM('blocks','validates') NOT NULL,
  PRIMARY KEY (session_id, round, from_path, to_path, kind)
)''',
  '''
CREATE TABLE IF NOT EXISTS proj_verification (
  session_id VARCHAR(40) NOT NULL, round INT NOT NULL,
  step_path VARCHAR(255) NOT NULL, step_round INT NOT NULL,
  lane VARCHAR(64) NOT NULL,
  attempt_id CHAR(26) NULL, incarnation INT NULL,
  grade CHAR(1) NULL, transport VARCHAR(16) NULL,
  rationale_digest CHAR(64) NULL, source_record_id CHAR(26) NULL,
  verdict_sha CHAR(40) NULL, pinned_head_sha CHAR(40) NULL, sha_drift TINYINT(1) NULL,
  gating_rc INT NULL, gating_plan_digest CHAR(64) NULL, gating_head_sha CHAR(40) NULL,
  route_verdict VARCHAR(16) NULL, route_rule VARCHAR(64) NULL,
  pr_url VARCHAR(255) NULL, pr_number INT NULL, reused TINYINT(1) NULL,
  auto_merge VARCHAR(24) NULL, validation_rc INT NULL,
  ci_conclusion VARCHAR(24) NULL, ci_head_sha CHAR(40) NULL,
  tokens_in INT NULL, tokens_out INT NULL, cost_usd DECIMAL(10,4) NULL,
  last_seq BIGINT NOT NULL,
  PRIMARY KEY (session_id, round, step_path, step_round, lane),
  KEY ix_session_round (session_id, round)
)''',
  '''
CREATE TABLE IF NOT EXISTS proj_admission (
  work_bead_id VARCHAR(40) NOT NULL PRIMARY KEY,
  open_grant_id CHAR(26) NULL,
  grant_expires_at DATETIME(6) NULL,
  fencing_token BIGINT NULL,
  mount_attempts INT NOT NULL DEFAULT 0,
  mint_attempts INT NOT NULL DEFAULT 0,
  cap_release_seq BIGINT NULL,
  capped TINYINT(1) NOT NULL DEFAULT 0,
  last_seq BIGINT NOT NULL
)''',
  '''
CREATE TABLE IF NOT EXISTS proj_admission_clause (
  work_bead_id VARCHAR(40) NOT NULL,
  clause VARCHAR(48) NOT NULL,
  refused TINYINT(1) NOT NULL,
  snapshot_rev VARCHAR(64) NULL,
  refusal_record_id CHAR(26) NULL,
  last_seq BIGINT NOT NULL,
  PRIMARY KEY (work_bead_id, clause)
)''',
  '''
CREATE TABLE IF NOT EXISTS proj_gate (
  gate_id VARCHAR(64) NOT NULL PRIMARY KEY,
  session_id VARCHAR(40) NOT NULL, work_bead_id VARCHAR(40) NULL,
  step_path VARCHAR(255) NOT NULL, step_round INT NOT NULL, attempt_id CHAR(26) NULL,
  state ENUM('open','closed') NOT NULL,
  opened_at DATETIME(6) NOT NULL, closed_at DATETIME(6) NULL,
  close_cause VARCHAR(32) NULL, close_actor VARCHAR(64) NULL,
  regate_count INT NOT NULL DEFAULT 0, regated_at DATETIME(6) NULL,
  reason_digest CHAR(64) NULL,
  ledger_ack_seq BIGINT NULL,
  last_seq BIGINT NOT NULL,
  KEY ix_session (session_id, state)
)''',
  '''
CREATE TABLE IF NOT EXISTS proj_gate_cycles (
  gate_id VARCHAR(64) NOT NULL, cycle INT NOT NULL,
  opened_record_id CHAR(26) NOT NULL,
  opened_at DATETIME(6) NOT NULL, closed_at DATETIME(6) NULL,
  close_cause VARCHAR(32) NULL, reason_digest CHAR(64) NULL,
  PRIMARY KEY (gate_id, cycle)
)''',
  '''
CREATE TABLE IF NOT EXISTS proj_process_identity (
  attempt_id CHAR(26) NOT NULL PRIMARY KEY,
  session_id VARCHAR(40) NOT NULL, round INT NOT NULL,
  step_path VARCHAR(255) NOT NULL, step_round INT NOT NULL, incarnation INT NOT NULL,
  pid INT NULL, pgid INT NULL,
  lease_state ENUM('held','released','swept') NULL,
  worktree VARCHAR(255) NULL, branch VARCHAR(160) NULL,
  base_sha CHAR(40) NULL, adopted_existing TINYINT(1) NULL,
  worktree_state ENUM('live','reaped','held') NULL,
  predecessor_attempt_id CHAR(26) NULL,
  last_seq BIGINT NOT NULL,
  UNIQUE KEY uq_incarnation (session_id, round, step_path, step_round, incarnation),
  KEY ix_session (session_id), KEY ix_worktree (worktree)
)''',
  '''
CREATE TABLE IF NOT EXISTS proj_effects (
  effect_id CHAR(64) NOT NULL PRIMARY KEY,
  effect_id_text VARCHAR(512) NOT NULL,
  kind VARCHAR(24) NOT NULL, intent_seq BIGINT NOT NULL,
  target_repo VARCHAR(160) NULL, target_branch VARCHAR(160) NULL,
  ack_seq BIGINT NULL,
  outcome VARCHAR(16) NULL, unknown_reason VARCHAR(32) NULL,
  settled_by CHAR(26) NULL, resolve_count INT NOT NULL DEFAULT 0,
  pr_url VARCHAR(255) NULL, pr_number INT NULL, pushed_sha CHAR(40) NULL,
  KEY ix_outstanding (ack_seq)
)''',
  '''
CREATE TABLE IF NOT EXISTS proj_leases (
  lease_id VARCHAR(64) NOT NULL PRIMARY KEY,
  lessee VARCHAR(64) NOT NULL,
  kind VARCHAR(24) NOT NULL,
  fencing_token BIGINT NOT NULL,
  granted_seq BIGINT NOT NULL,
  expires_at DATETIME(6) NOT NULL,
  state ENUM('granted','reaped','expired') NOT NULL,
  KEY ix_lessee (lessee, state)
)''',
  '''
CREATE TABLE IF NOT EXISTS proj_command_dedupe (
  wire_key VARCHAR(160) NOT NULL PRIMARY KEY,
  fingerprint VARCHAR(128) NOT NULL,
  fence BIGINT NOT NULL, seq BIGINT NOT NULL,
  conflict_count INT NOT NULL DEFAULT 0
)''',
  '''
CREATE TABLE IF NOT EXISTS proj_telemetry (
  session_id VARCHAR(40) NOT NULL, round INT NOT NULL,
  step_path VARCHAR(255) NOT NULL, step_round INT NOT NULL,
  model VARCHAR(32) NULL, tokens_in BIGINT NULL, tokens_out BIGINT NULL,
  cost_usd DECIMAL(10,4) NULL, premium_requests INT NULL,
  num_turns INT NULL, duration_ms BIGINT NULL,
  last_seq BIGINT NOT NULL,
  PRIMARY KEY (session_id, round, step_path, step_round)
)''',
];

/// Creates the sibling `trajectory` database. [serverConn] is a
/// server-level session (no database selected).
Future<void> createTrajectoryDatabase(TrajectoryDb serverConn) async {
  await serverConn.execute('CREATE DATABASE IF NOT EXISTS trajectory');
}

/// Applies the full §4 schema on [db] (a session with `USE trajectory`).
///
/// Idempotent: the `dolt_ignore` seed inserts only missing patterns
/// (dolt_ignore's PK is the pattern — a verbatim re-INSERT would 1062), and
/// every CREATE TABLE carries IF NOT EXISTS.
Future<void> applyTrajectorySchema(TrajectoryDb db) async {
  // STEP 0 first, always: tables registered before any of them can exist.
  final existing = await db.execute(
    'SELECT pattern FROM dolt_ignore WHERE pattern IN '
    "('proj_%', 'traj_pulse', 'traj_fence')",
  );
  if (existing.rows.isEmpty) {
    await db.execute(doltIgnoreSeedSql);
  } else {
    final present = {for (final row in existing.rows) row['pattern']};
    for (final pattern in const ['proj_%', 'traj_pulse', 'traj_fence']) {
      if (present.contains(pattern)) continue;
      await db.execute('INSERT INTO dolt_ignore VALUES (:pattern, true)', {
        'pattern': pattern,
      });
    }
  }

  for (final statement in trajectoryTableDdl) {
    await db.execute(statement);
  }

  // Bootstrap commit: the ignore registration and the table schemas would
  // otherwise sit dirty forever (the append cadence stages only its three
  // named tables), failing the status-clean guard. Plain -A never captures
  // dolt_ignore'd tables (probe T3) — `dolt add --force` stays banned.
  // --skip-empty keeps the re-run idempotent; nothing reads the call's
  // return, so the T7 trap does not apply.
  await db.execute("CALL DOLT_ADD('-A')");
  await db.execute(
    "CALL DOLT_COMMIT('--skip-empty', '-m', 'traj: schema bootstrap')",
  );
}

/// The live column set of `proj_session_head` on [db], read from
/// `information_schema` under an explicit alias (the column's own name comes
/// back cased differently across servers; the alias does not).
const String projSessionHeadColumnsSql =
    'SELECT column_name AS name FROM information_schema.columns '
    'WHERE table_schema = DATABASE() AND table_name = :table';

/// True when this home's `proj_session_head` predates the current cut shape —
/// it is missing one of [projSessionHeadCutColumns], or it does not exist at
/// all. Read-only; the caller decides whether it is quiesced enough to fix.
Future<bool> sessionHeadProjectionNeedsReshape(TrajectoryDb db) async {
  final result = await db.execute(projSessionHeadColumnsSql, {
    'table': 'proj_session_head',
  });
  final columns = {for (final row in result.rows) row['name']?.toLowerCase()};
  return !projSessionHeadCutColumns.every(columns.contains);
}

/// THE P1 projection-shape migration, as a named step (cut-wiring C0, r7 —
/// V1-B1): `DROP TABLE proj_session_head` + re-CREATE at
/// [projSessionHeadDdl]. An ALTER path is deliberately not built.
///
/// Destructive by design and safe only because P1 is REBUILDABLE state: the
/// caller runs it QUIESCED and follows it with a full `replaySessionHeads`,
/// which is also what stamps the bumped `fold_version`. `proj_%` is
/// `dolt_ignore`'d, so neither the drop nor the re-create stages dolt history.
Future<void> reshapeSessionHeadProjection(TrajectoryDb db) async {
  // DDL cannot ride a transaction (the same reason the replays DELETE rather
  // than TRUNCATE); the two statements are the whole step.
  await db.execute('DROP TABLE IF EXISTS proj_session_head');
  await db.execute(projSessionHeadDdl);
}

/// The live column set of the `trajectory` JOURNAL.
///
/// Deliberately a table-LITERAL statement rather than
/// [projSessionHeadColumnsSql]'s parameterized form: the two probes run under
/// different rules — the projection probe is dual-read-gated, this one is
/// unconditional — and both a human tailing the SQL log and every scripted
/// fake in the tree key on statement TEXT, never on parameters.
const String journalColumnsSql =
    'SELECT column_name AS name FROM information_schema.columns '
    "WHERE table_schema = DATABASE() AND table_name = 'trajectory'";

/// True when this home's journal still spells the substation identity `seat`
/// — the pre-tg-j1zn column name.
///
/// Reads the LIVE column set and tests for the OLD name, so a home already at
/// the current shape, and a home with no `trajectory` table at all, both
/// answer false: the migration is never run speculatively.
Future<bool> journalNeedsSubstationRename(TrajectoryDb db) async {
  final result = await db.execute(journalColumnsSql);
  final columns = {for (final row in result.rows) row['name']?.toLowerCase()};
  return columns.contains('seat');
}

/// THE tg-j1zn journal migration, as a named step beside
/// [reshapeSessionHeadProjection]: `trajectory.seat` becomes
/// `trajectory.substation` and `ck_seat` returns as `ck_substation`.
///
/// An in-place ALTER, and deliberately NOT the P1 shape. P1 may DROP because
/// `proj_%` is `dolt_ignore`'d, rebuildable state; the journal IS the
/// dolt-versioned log, so a drop would destroy the only copy of every recorded
/// fact. Renaming a promoted envelope COLUMN is a schema migration and is
/// distinct from §2.6's "the log is never migrated" rule, which governs
/// payload `type_version` evolution — no record's payload changes here.
/// Verified against dolt 2.2.2: `DROP CHECK`, `RENAME COLUMN`, and
/// `ADD CONSTRAINT` all apply, and the re-added CHECK refuses by its new name.
///
/// Quiesced by the same fence as the reshape (`traj replay`): DDL cannot ride
/// a transaction, and an append mid-rename would target a column that exists
/// under neither name.
Future<void> renameJournalSubstationColumn(TrajectoryDb db) async {
  await db.execute('ALTER TABLE trajectory DROP CHECK ck_seat');
  await db.execute('ALTER TABLE trajectory RENAME COLUMN seat TO substation');
  await db.execute(
    'ALTER TABLE trajectory ADD CONSTRAINT ck_substation '
    'CHECK (work_bead_id IS NULL OR substation IS NOT NULL)',
  );
}
