/// One in-memory image of a `proj_session_head` row — P1, the §7 head summary.
///
/// Column vocabulary is the §4 DDL verbatim; the DDL is the letter. P1
/// deliberately carries NO worktree/lease/liveness fields (those are P6's),
/// so the Family-1 fold's worktree/lease records produce no P1 delta — a
/// consequence this type makes structural: there is nowhere to put them.
library;

import 'package:meta/meta.dart';

import '../codec/envelope.dart';
import '../connect/trajectory_db.dart';

/// `proj_session_head.status` — the two-value ENUM, wire strings.
enum SessionHeadStatus {
  open,
  closed;

  static SessionHeadStatus fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

/// One P1 row. Immutable; the fold advances a session by [applying] a column
/// map — the SAME column vocabulary the incremental SQL UPDATE uses, so the
/// two application modes cannot drift on semantics.
@immutable
class SessionHeadRow {
  const SessionHeadRow({
    required this.sessionId,
    required this.workBeadId,
    required this.startedAt,
    required this.headEpoch,
    required this.lastSeq,
    this.round = 0,
    this.status = SessionHeadStatus.open,
    this.outcome,
    this.workTerminalReason,
    this.terminalProvenance,
    this.unknownReason,
    this.held = false,
    this.heldReason,
    this.pgid,
    this.pid,
    this.attemptId,
    this.rig,
    this.model,
    this.substation,
    this.closedAt,
  });

  /// One `SELECT * FROM proj_session_head` row, read back.
  ///
  /// The inverse of [toSqlParams] — a boot seed decodes what a replay wrote,
  /// and the round-trip is pinned by test. Values arrive as the `assoc()`
  /// shape's strings from a real server, but the map is typed [Object?] so the
  /// in-memory params map round-trips directly (an `int` `held`, a DATETIME(6)
  /// literal): every non-null value is read through its own string form.
  factory SessionHeadRow.fromSqlRow(Map<String, Object?> row) {
    String? text(String column) {
      final value = row[column];
      return value == null ? null : '$value';
    }

    int? number(String column) {
      final raw = text(column);
      return raw == null ? null : int.parse(raw);
    }

    return SessionHeadRow(
      sessionId: text('session_id') ?? '',
      workBeadId: text('work_bead_id') ?? '',
      round: number('round') ?? 0,
      status: SessionHeadStatus.fromWire(text('status') ?? 'open'),
      outcome: switch (text('outcome')) {
        final String wire => TerminalOutcome.fromWire(wire),
        _ => null,
      },
      workTerminalReason: text('work_terminal_reason'),
      terminalProvenance: switch (text('terminal_provenance')) {
        final String wire => TrajectoryProvenance.fromWire(wire),
        _ => null,
      },
      unknownReason: text('unknown_reason'),
      held: (number('held') ?? 0) != 0,
      heldReason: text('held_reason'),
      pgid: number('pgid'),
      pid: number('pid'),
      attemptId: text('attempt_id'),
      rig: text('rig'),
      model: text('model'),
      substation: text('substation'),
      // NOT NULL in the DDL; a row without it is unreadable, not defaultable.
      startedAt: parseSqlDateTime6(text('started_at'))!,
      closedAt: parseSqlDateTime6(text('closed_at')),
      headEpoch: number('head_epoch') ?? 0,
      lastSeq: number('last_seq') ?? 0,
    );
  }

  final String sessionId;

  /// §7: immutable — set at mint, never re-keyed (`#rN`/`#void-` retire).
  final String workBeadId;
  final int round;
  final SessionHeadStatus status;
  final TerminalOutcome? outcome;
  final String? workTerminalReason;

  /// The wave-1 cut's durable terminal provenance (cut-wiring §0.3, r6–r11):
  /// `reconstructed` marks a head whose terminal is TESTIMONY — a close the
  /// station reconstructed rather than observed. The `reconstructedTerminal`
  /// suppressor reads THIS column, so it survives every boot; process memory
  /// never carries it.
  ///
  /// TRUTH MONOTONICITY (the one rule): the mark is set by a reconstructed
  /// terminal landing on a terminal-less head; a later OBSERVED terminal
  /// overwrites the outcome and CLEARS the mark. Testimony never overwrites
  /// truth, and an `inferred` settlement leaves the mark intact.
  final TrajectoryProvenance? terminalProvenance;

  /// The schema's explicit-unknown vocabulary word behind an
  /// `outcome='unknown'` head (`ck_unknown`'s subject, carried onto P1 so a
  /// reader can say WHY a head is unknown without joining the log).
  final String? unknownReason;

  /// `outcome` and `held` are SEPARATE axes (§6 row 4).
  final bool held;
  final String? heldReason;
  final int? pgid;
  final int? pid;
  final String? attemptId;
  final String? rig;
  final String? model;
  final String? substation;
  final DateTime startedAt;
  final DateTime? closedAt;

  /// §7's ledger-side fence seed. Stage 0 stamps the minting record's
  /// `boot_epoch`; the Stage-1 bd head-stamp obligation advances it on every
  /// successful read-back (§5). That seeding is PROVISIONAL — the value is a
  /// FLOOR (the head is no older than the minting epoch), never the ledger's
  /// real head epoch, until the head-stamp obligation ships.
  final int headEpoch;
  final int lastSeq;

  /// The row with [columns] applied — DDL column names, an EXPLICIT null
  /// value means SET NULL (absent keys are untouched), mirroring the
  /// incremental `UPDATE ... SET` exactly. Unknown column names throw: a
  /// delta naming a column this row cannot hold is a fold bug, never data.
  SessionHeadRow applying(
    Map<String, Object?> columns, {
    required int lastSeq,
  }) {
    var round = this.round;
    var status = this.status;
    var outcome = this.outcome;
    var workTerminalReason = this.workTerminalReason;
    var terminalProvenance = this.terminalProvenance;
    var unknownReason = this.unknownReason;
    var held = this.held;
    var heldReason = this.heldReason;
    var pgid = this.pgid;
    var pid = this.pid;
    var attemptId = this.attemptId;
    var closedAt = this.closedAt;
    for (final entry in columns.entries) {
      final value = entry.value;
      switch (entry.key) {
        case 'round':
          round = value! as int;
        case 'status':
          status = SessionHeadStatus.fromWire(value! as String);
        case 'outcome':
          outcome = value == null
              ? null
              : TerminalOutcome.fromWire(value as String);
        case 'work_terminal_reason':
          workTerminalReason = value as String?;
        case 'terminal_provenance':
          terminalProvenance = value == null
              ? null
              : TrajectoryProvenance.fromWire(value as String);
        case 'unknown_reason':
          unknownReason = value as String?;
        case 'held':
          held = (value! as int) != 0;
        case 'held_reason':
          heldReason = value as String?;
        case 'pgid':
          pgid = value as int?;
        case 'pid':
          pid = value as int?;
        case 'attempt_id':
          attemptId = value as String?;
        case 'closed_at':
          closedAt = value as DateTime?;
        default:
          throw ArgumentError(
            'proj_session_head has no fold-updatable column ${entry.key}',
          );
      }
    }
    return SessionHeadRow(
      sessionId: sessionId,
      workBeadId: workBeadId,
      round: round,
      status: status,
      outcome: outcome,
      workTerminalReason: workTerminalReason,
      terminalProvenance: terminalProvenance,
      unknownReason: unknownReason,
      held: held,
      heldReason: heldReason,
      pgid: pgid,
      pid: pid,
      attemptId: attemptId,
      rig: rig,
      model: model,
      substation: substation,
      startedAt: startedAt,
      closedAt: closedAt,
      headEpoch: headEpoch,
      lastSeq: lastSeq,
    );
  }

  /// The full-row INSERT parameter map — §4 column names, SQL-typed values
  /// (`held` as TINYINT, datetimes as DATETIME(6) literals).
  Map<String, Object?> toSqlParams() => {
    'session_id': sessionId,
    'work_bead_id': workBeadId,
    'round': round,
    'status': status.wire,
    'outcome': outcome?.wire,
    'work_terminal_reason': workTerminalReason,
    'terminal_provenance': terminalProvenance?.wire,
    'unknown_reason': unknownReason,
    'held': held ? 1 : 0,
    'held_reason': heldReason,
    'pgid': pgid,
    'pid': pid,
    'attempt_id': attemptId,
    'rig': rig,
    'model': model,
    'substation': substation,
    'started_at': sqlDateTime6(startedAt),
    'closed_at': closedAt == null ? null : sqlDateTime6(closedAt!),
    'head_epoch': headEpoch,
    'last_seq': lastSeq,
  };

  @override
  bool operator ==(Object other) =>
      other is SessionHeadRow &&
      other.sessionId == sessionId &&
      other.workBeadId == workBeadId &&
      other.round == round &&
      other.status == status &&
      other.outcome == outcome &&
      other.workTerminalReason == workTerminalReason &&
      other.terminalProvenance == terminalProvenance &&
      other.unknownReason == unknownReason &&
      other.held == held &&
      other.heldReason == heldReason &&
      other.pgid == pgid &&
      other.pid == pid &&
      other.attemptId == attemptId &&
      other.rig == rig &&
      other.model == model &&
      other.substation == substation &&
      other.startedAt == startedAt &&
      other.closedAt == closedAt &&
      other.headEpoch == headEpoch &&
      other.lastSeq == lastSeq;

  @override
  int get hashCode => Object.hash(
    sessionId,
    workBeadId,
    round,
    status,
    outcome,
    workTerminalReason,
    terminalProvenance,
    unknownReason,
    held,
    heldReason,
    pgid,
    pid,
    attemptId,
    rig,
    model,
    substation,
    startedAt,
    closedAt,
    headEpoch,
    lastSeq,
  );

  @override
  String toString() => 'SessionHeadRow(${toSqlParams()})';
}

/// The whole of P1, read in one SELECT — the mirror's BOOT SEED (cut-wiring
/// C1 / §0.2).
///
/// One statement, on the caller's already-serialized connection: P1 is bounded
/// by sessions, so the seed is a single scan and never a paged read. The rows
/// come back in `session_id` order for a deterministic seed.
const String scanSessionHeadsSql =
    'SELECT * FROM proj_session_head ORDER BY session_id';

/// Reads every `proj_session_head` row off [db] via [scanSessionHeadsSql].
Future<List<SessionHeadRow>> scanSessionHeads(TrajectoryDb db) async {
  final result = await db.execute(scanSessionHeadsSql);
  return [for (final row in result.rows) SessionHeadRow.fromSqlRow(row)];
}

/// [sqlDateTime6]'s inverse: a DATETIME(6) column read back as UTC.
///
/// The column carries no zone and every writer here writes UTC, so the value
/// is re-read as UTC rather than reinterpreted as local time — the same rule
/// `envelopeFromRow` applies to the log's own instants. Null/blank in, null
/// out (the columns are nullable).
DateTime? parseSqlDateTime6(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;
  if (text.endsWith('Z') || text.contains('+')) return DateTime.parse(text);
  return DateTime.parse('${text.replaceFirst(' ', 'T')}Z');
}

/// DATETIME(6) literal — dolt refuses ISO-8601's trailing `Z`; the fold, like
/// the appender, writes UTC.
String sqlDateTime6(DateTime value) {
  final utc = value.toUtc();
  String pad(int n, int width) => n.toString().padLeft(width, '0');
  return '${pad(utc.year, 4)}-${pad(utc.month, 2)}-${pad(utc.day, 2)} '
      '${pad(utc.hour, 2)}:${pad(utc.minute, 2)}:${pad(utc.second, 2)}'
      '.${pad(utc.microsecond + utc.millisecond * 1000, 6)}';
}
