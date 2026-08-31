/// The fenced append client — §5's write path, mechanically.
///
/// LOUD EXCEPTION NOTICE (decision: trajectory-direct-sql-scope): this class
/// WRITES a dolt database over direct SQL. That is designed, not an
/// oversight — the bd-CLI-only-writes rule governs the LEDGER database only;
/// the `trajectory` database's sole appender is this service. Do not reroute
/// these writes through bd and do not add a select-only guard.
///
/// One append = one SQL transaction:
///   1. the T6i counter-CAS on `traj_fence` — 0 rows matched is ALWAYS the
///      fenced-out signal (definitive; refuse immediately); 1 row is NEVER
///      proof of holding the fence — 1213 at COMMIT arbitrates the contended
///      interleavings;
///   2. the belt: `boot_epoch` non-decreasing over `seq`; grant expiry on
///      grant-consuming appends — a belt violation is the corruption-halt
///      alarm class;
///   3. INSERT the `trajectory` row (`epoch_seq` service-assigned in the
///      serialized stream);
///   4. `traj_terminal_guard` insert/update for terminals;
///   5. the synchronous fold delta — in Stage 0, `proj_meta.applied_seq`;
///   COMMIT.
///
/// Error contract, exactly §5's three classes: 1213 → fenced out, inert;
/// 1105 branched on the constraint NAMED in the message (`uq_idem` → the
/// designed dedupe, return the original record_id; `uq_epoch_seq` →
/// corruption halt); belt violation → corruption halt. A halted appender
/// refuses every further append until recreated; an inert one appends
/// nothing further, not even its refusal.
library;

import 'dart:convert';

import 'package:mysql_client/exception.dart';

import '../codec/envelope.dart';
import '../codec/idem_key.dart';
import '../codec/trajectory_record.dart';
import '../connect/trajectory_db.dart';
import 'append_outcome.dart';
import 'ulid.dart';

/// Record types that force a dolt commit at the next allowed opportunity
/// (§5 boundary events).
const Set<String> doltCommitBoundaryTypes = {
  'authority.epoch.advanced',
  'authority.epoch.closed',
  'attempt.terminal',
  'attempt.round.retired',
};

/// Guarded-reconnect disposition (§5): a stale epoch goes inert WITHOUT
/// touching the fence cell.
sealed class ReconnectOutcome {
  const ReconnectOutcome();
}

final class ReconnectResumed extends ReconnectOutcome {
  const ReconnectResumed({required this.epoch});

  final int epoch;
}

final class ReconnectInert extends ReconnectOutcome {
  const ReconnectInert({required this.staleEpoch, required this.liveEpoch});

  final int staleEpoch;
  final int liveEpoch;
}

class TrajectoryAppender {
  TrajectoryAppender({
    required TrajectoryDb db,
    required this.station,
    this.source = 'trajectory_service',
    DateTime Function()? clock,
    Duration commitCadence = const Duration(seconds: 30),
    Duration commitMinInterval = const Duration(seconds: 10),
    int commitRowThreshold = 512,
  }) : _db = db,
       _clock = clock ?? DateTime.now,
       _commitCadence = commitCadence,
       _commitMinInterval = commitMinInterval,
       _commitRowThreshold = commitRowThreshold;

  TrajectoryDb _db;
  final String station;
  final String source;
  final DateTime Function() _clock;
  final Duration _commitCadence;
  final Duration _commitMinInterval;
  final int _commitRowThreshold;

  int? _bootEpoch;
  int _epochSeq = 0;
  bool _inert = false;
  bool _halted = false;

  int _pendingRows = 0;
  int? _pendingFromSeq;
  int? _pendingToSeq;
  bool _pendingBoundary = false;
  DateTime? _lastDoltCommitAt;
  int _verifiedDoltCommits = 0;

  int? get bootEpoch => _bootEpoch;
  bool get isInert => _inert;
  bool get isHalted => _halted;
  int get pendingRows => _pendingRows;

  /// Dolt commits VERIFIED via dolt_log growth — `DOLT_COMMIT`'s own return
  /// is never trusted (the T7 measurement trap).
  int get verifiedDoltCommits => _verifiedDoltCommits;

  // ── epoch claim (§5) ─────────────────────────────────────────────────────

  /// Claims the next epoch for [station]. The caller HOLDS the station lock —
  /// the lock supplies mutual exclusion, the epoch row supplies history, the
  /// fence cell supplies enforcement.
  ///
  /// The INSERT computes MAX+1 server-side so a cross-process race lands as
  /// 1213 (dolt's write-write conflict arbitrates — probe T6c), which is
  /// re-read and retried up to [maxAttempts]. 1062 is deliberately NOT
  /// caught: the PK is not the arbiter, and seeing it means something is
  /// structurally wrong.
  Future<EpochClaimOutcome> claimEpoch({
    required int pid,
    required int pgid,
    String cause = 'boot',
    int maxAttempts = 3,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _db.execute(
          'INSERT INTO traj_epoch (station, epoch, pid, pgid, cause, '
          'advanced_at) '
          'SELECT :station, COALESCE(MAX(epoch), 0) + 1, :pid, :pgid, '
          ':cause, :now FROM traj_epoch WHERE station = :station',
          {
            'station': station,
            'pid': pid,
            'pgid': pgid,
            'cause': cause,
            'now': _sqlDate(_clock().toUtc()),
          },
        );
      } on MySQLServerException catch (error) {
        if (!isSerializationFailure(error)) rethrow;
        // Re-read, then retry or refuse — never treat the race as fatal.
        await _readLiveEpoch();
        continue;
      }
      final epoch = await _readLiveEpoch();
      // Fence-cell UPSERT: the claim path is also what SEEDS the row on a
      // fresh grid home or after trap recovery (§5, cert round).
      await _seedFence(epoch);
      _bootEpoch = epoch;
      _epochSeq = 0;
      _inert = false;
      // Anchors the cadence: the first dolt commit lands no sooner than the
      // hard minimum after boot.
      _lastDoltCommitAt = _clock().toUtc();
      return EpochClaimed(epoch: epoch);
    }
    return EpochClaimRefused(attempts: maxAttempts);
  }

  /// Guarded reconnect over [db] (a fresh session after a drop/bounce): the
  /// cell is re-seeded ONLY while `MAX(traj_epoch.epoch)` still equals our
  /// own boot epoch; otherwise this appender is stale and goes inert without
  /// touching the cell — an unguarded reinit would be a stale process's
  /// write into the live authority's fence.
  Future<ReconnectOutcome> reconnect(TrajectoryDb db) async {
    final own = _requireEpoch();
    _db = db;
    final live = await _readLiveEpoch();
    if (live != own) {
      _inert = true;
      return ReconnectInert(staleEpoch: own, liveEpoch: live);
    }
    await _seedFence(own);
    final result = await _db.execute(
      'SELECT COALESCE(MAX(epoch_seq), 0) AS s FROM trajectory '
      'WHERE station = :station AND boot_epoch = :epoch',
      {'station': station, 'epoch': own},
    );
    _epochSeq = int.parse(result.rows.first['s'] ?? '0');
    _lastDoltCommitAt = _clock().toUtc();
    return ReconnectResumed(epoch: own);
  }

  // ── append (§5 steps 1–5) ────────────────────────────────────────────────

  Future<AppendOutcome> append(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? seat,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
    String? source,
  }) async {
    if (_halted) {
      return const AppendCorruptionHalt(
        reason: 'appender is halted; recreate it after operator review',
      );
    }
    if (_inert) return const AppendFencedOut(reason: 'inert');
    final epoch = _requireEpoch();

    final now = _clock().toUtc();
    final context = IdemContext(station: station, bootEpoch: epoch);
    final envelope = _buildEnvelope(
      record,
      context: context,
      now: now,
      occurredAt: occurredAt?.toUtc() ?? now,
      seat: seat,
      provenance: provenance,
      provenanceBasis: provenanceBasis,
      source: source ?? this.source,
    );
    final candidateEpochSeq = _epochSeq + 1;

    try {
      await _db.execute('START TRANSACTION');

      // Step 1 — the counter-CAS. 0 rows = fenced out, definitive.
      final cas = await _db.execute(
        'UPDATE traj_fence SET fence_state = fence_state + 1 '
        'WHERE station = :station AND (fence_state >> 32) = :epoch',
        {'station': station, 'epoch': epoch},
      );
      if (cas.affectedRows == 0) {
        await _rollbackQuietly();
        _inert = true;
        return const AppendFencedOut(reason: 'cas-zero-rows');
      }

      // Step 2 — the belt.
      final previous = await _db.execute(
        'SELECT boot_epoch FROM trajectory WHERE station = :station '
        'ORDER BY seq DESC LIMIT 1',
        {'station': station},
      );
      if (previous.rows.isNotEmpty) {
        final previousEpoch = int.parse(previous.rows.first['boot_epoch']!);
        if (previousEpoch > epoch) {
          return _haltInTransaction(
            'belt: boot_epoch would decrease over seq '
            '($previousEpoch then $epoch) — a higher epoch already committed',
          );
        }
      }
      final grantBelt = await _assertGrantBelt(envelope, now);
      if (grantBelt != null) return grantBelt;

      // Step 3 — the row. seq is dolt-assigned; epoch_seq is ours, in the
      // serialized stream.
      final row = _rowFor(envelope, candidateEpochSeq);
      final columns = row.keys.toList();
      final insert = await _db.execute(
        'INSERT INTO trajectory (${columns.join(', ')}) '
        'VALUES (${columns.map((column) => ':$column').join(', ')})',
        row,
      );
      final seq = insert.lastInsertId;

      // Step 4 — the terminal guard: unsettled terminals INSERT (a second
      // independent terminal dies on the PK); a settling one UPDATEs.
      if (record is AttemptTerminal) {
        if (record.isSettling) {
          await _db.execute(
            'UPDATE traj_terminal_guard SET seq = :seq, '
            'settled_by = :settled_by WHERE attempt_id = :attempt_id',
            {
              'seq': seq,
              'settled_by': envelope.recordId,
              'attempt_id': record.attemptId,
            },
          );
        } else {
          await _db.execute(
            'INSERT INTO traj_terminal_guard (attempt_id, seq, settled_by) '
            'VALUES (:attempt_id, :seq, NULL)',
            {'attempt_id': record.attemptId, 'seq': seq},
          );
        }
      }

      // Step 5 — Stage 0's only synchronous fold delta.
      await _db.execute(
        'INSERT INTO proj_meta (projection, fold_version, applied_seq) '
        "VALUES ('fold', 1, :seq) "
        'ON DUPLICATE KEY UPDATE applied_seq = :seq',
        {'seq': seq},
      );

      await _db.execute('COMMIT');

      _epochSeq = candidateEpochSeq;
      _noteCommitted(
        seq,
        boundary: doltCommitBoundaryTypes.contains(record.recordType),
      );
      await doltCommitIfDue();
      return Appended(
        recordId: envelope.recordId,
        seq: seq,
        epochSeq: candidateEpochSeq,
      );
    } on MySQLServerException catch (error) {
      await _rollbackQuietly();
      if (isSerializationFailure(error)) {
        // 1213 at COMMIT arbitrates the contended interleavings: on the
        // append path this IS the fenced-out signal.
        _inert = true;
        return const AppendFencedOut(reason: 'commit-1213');
      }
      if (isUniqueViolationOn(error, 'uq_idem')) {
        // The designed at-least-once dedupe: hand back the original row.
        return _dedupeOriginal(envelope);
      }
      if (isUniqueViolationOn(error, 'uq_epoch_seq')) {
        _halted = true;
        return AppendCorruptionHalt(
          reason:
              'uq_epoch_seq violation at commit — the belt caught an '
              'interleave the fence missed: $error',
        );
      }
      if (isDuplicateEntry(error)) {
        // Measured on dolt 2.2 (stage-0 cert): a duplicate already visible in
        // the session snapshot dies at STATEMENT time as 1062 naming the
        // duplicate VALUE, not at COMMIT as a constraint-named 1105 — 1105
        // remains the concurrent-commit shape. The value doesn't say which
        // unique key fired, so the log arbitrates: an existing row under our
        // idem_key is the designed dedupe; anything else is the belt's
        // epoch_seq/record_id class — halt.
        final original = await _db.execute(
          'SELECT record_id FROM trajectory WHERE idem_key = :idem_key',
          {'idem_key': envelope.idemKey},
        );
        if (original.rows.isNotEmpty) {
          return AppendDeduped(recordId: original.rows.first['record_id']!);
        }
        _halted = true;
        return AppendCorruptionHalt(
          reason:
              'duplicate key on append with no matching idem_key — '
              'epoch_seq/record_id collision: $error',
        );
      }
      rethrow;
    }
  }

  // ── dolt-commit cadence (§5 dolt-commit policy) ─────────────────────────

  /// Issues a dolt commit when due: [_commitCadence] elapsed, or
  /// [_commitRowThreshold] rows pending, or a boundary event landed — but
  /// NEVER within [_commitMinInterval] of the previous verified commit
  /// (probe T7b: commit COUNT, not row count, is the storage lever).
  ///
  /// The tick calls this on its 30s interval so cadence commits fire even
  /// with no new appends; [append] calls it after every landed row.
  Future<void> doltCommitIfDue() async {
    if (_pendingRows == 0) return;
    final now = _clock().toUtc();
    final last = _lastDoltCommitAt;
    if (last != null && now.difference(last) < _commitMinInterval) return;
    final due =
        _pendingBoundary ||
        _pendingRows >= _commitRowThreshold ||
        last == null ||
        now.difference(last) >= _commitCadence;
    if (!due) return;

    // Branch pin, fail closed (probe T3): committing off main would target a
    // different working set entirely.
    final branch = await _db.execute('SELECT active_branch() AS b');
    final active = branch.rows.isEmpty ? null : branch.rows.first['b'];
    if (active != 'main') {
      _halted = true;
      throw StateError(
        'session branch changed to ${active ?? 'unknown'} — the service pins '
        'main and fails closed',
      );
    }

    final before = await _doltLogCount();
    await _db.execute(
      "CALL DOLT_ADD('trajectory','traj_epoch','traj_terminal_guard')",
    );
    try {
      await _db.execute('CALL DOLT_COMMIT(:flag, :message)', {
        'flag': '-m',
        'message':
            'traj: seq ${_pendingFromSeq ?? 0}..${_pendingToSeq ?? 0} '
            'epoch ${_requireEpoch()}',
      });
    } on MySQLServerException {
      // "nothing to commit" and friends — dolt_log arbitrates below.
    }
    final after = await _doltLogCount();
    if (after > before) {
      _verifiedDoltCommits += 1;
      _lastDoltCommitAt = now;
      _pendingRows = 0;
      _pendingFromSeq = null;
      _pendingToSeq = null;
      _pendingBoundary = false;
    }
  }

  // ── internals ────────────────────────────────────────────────────────────

  int _requireEpoch() {
    final epoch = _bootEpoch;
    if (epoch == null) {
      throw StateError('no epoch claimed — call claimEpoch first');
    }
    return epoch;
  }

  Future<int> _readLiveEpoch() async {
    final result = await _db.execute(
      'SELECT COALESCE(MAX(epoch), 0) AS e FROM traj_epoch '
      'WHERE station = :station',
      {'station': station},
    );
    return int.parse(result.rows.first['e'] ?? '0');
  }

  Future<void> _seedFence(int epoch) async {
    // UPSERT, never a bare UPDATE: the cell is working-set state that a
    // fresh home / trap recovery legitimately lacks (§4 traj_fence comment).
    await _db.execute(
      'INSERT INTO traj_fence (station, fence_state) '
      'VALUES (:station, :state) '
      'ON DUPLICATE KEY UPDATE fence_state = :state',
      {'station': station, 'state': epoch << 32},
    );
  }

  Future<AppendOutcome?> _assertGrantBelt(
    TrajectoryEnvelope envelope,
    DateTime now,
  ) async {
    // Grant-scoped belt (§5 step 2): a consuming append must find its grant
    // unexpired. Issuing/closing records are exempt — expiry is exactly what
    // .expired reports.
    const consuming = {'admission.grant.consumed', 'attempt.session.started'};
    if (!consuming.contains(envelope.recordType)) return null;
    final grantId = envelope.grantId;
    if (grantId == null) return null;
    final grant = await _db.execute(
      'SELECT expires_at FROM trajectory '
      "WHERE record_type = 'admission.grant.issued' AND grant_id = :grant_id "
      'ORDER BY seq DESC LIMIT 1',
      {'grant_id': grantId},
    );
    if (grant.rows.isEmpty) return null;
    final expiresAt = DateTime.parse(
      '${grant.rows.first['expires_at']!.replaceFirst(' ', 'T')}Z',
    );
    if (!expiresAt.isAfter(now)) {
      return _haltInTransaction(
        'belt: grant $grantId expired at $expiresAt — '
        '${envelope.recordType} refused',
      );
    }
    return null;
  }

  Future<AppendOutcome> _dedupeOriginal(TrajectoryEnvelope envelope) async {
    final original = await _db.execute(
      'SELECT record_id FROM trajectory WHERE idem_key = :idem_key',
      {'idem_key': envelope.idemKey},
    );
    if (original.rows.isEmpty) {
      throw StateError(
        'uq_idem fired but no row carries idem_key '
        '${envelope.idemKey} (${envelope.idemKeyText})',
      );
    }
    return AppendDeduped(recordId: original.rows.first['record_id']!);
  }

  Future<AppendOutcome> _haltInTransaction(String reason) async {
    await _rollbackQuietly();
    _halted = true;
    return AppendCorruptionHalt(reason: reason);
  }

  Future<void> _rollbackQuietly() async {
    try {
      await _db.execute('ROLLBACK');
    } on Object {
      // The transaction may already be gone (1213 kills it server-side).
    }
  }

  void _noteCommitted(int seq, {required bool boundary}) {
    _pendingRows += 1;
    _pendingFromSeq ??= seq;
    _pendingToSeq = seq;
    if (boundary) _pendingBoundary = true;
  }

  Future<int> _doltLogCount() async {
    final result = await _db.execute('SELECT COUNT(*) AS c FROM dolt_log');
    return int.parse(result.rows.first['c'] ?? '0');
  }

  TrajectoryEnvelope _buildEnvelope(
    TrajectoryRecord record, {
    required IdemContext context,
    required DateTime now,
    required DateTime occurredAt,
    required String? seat,
    required TrajectoryProvenance provenance,
    required String? provenanceBasis,
    required String source,
  }) {
    final correlation = record.correlationToJson();
    final json = <String, Object?>{
      'record_id': mintUlid(now: now),
      'idem_key': record.idemKey(context),
      'idem_key_text': record.idemKeyText(context),
      'family': record.family.wire,
      'record_type': record.recordType,
      'type_version': record.typeVersion,
      'occurred_at': occurredAt.toIso8601String(),
      'recorded_at': now.toIso8601String(),
      'station': station,
      'authority_id': '$station/${context.bootEpoch}',
      'boot_epoch': context.bootEpoch,
      'provenance': provenance.wire,
      if (provenanceBasis != null) 'provenance_basis': provenanceBasis,
      'source': source,
      'payload': record.payloadToJson(),
      ...correlation,
    };
    // §2.6 rule 7: seat is service-derived from the bead's store prefix —
    // no caller supplies it, so no caller can forget it (ck_seat).
    final workBeadId = json['work_bead_id'] as String?;
    if (workBeadId != null) {
      json['seat'] = seat ?? _seatFor(workBeadId);
    }
    return TrajectoryEnvelope.fromJson(json);
  }

  static String _seatFor(String workBeadId) {
    final dash = workBeadId.indexOf('-');
    return dash <= 0 ? workBeadId : workBeadId.substring(0, dash);
  }

  /// The INSERT parameter map: DDL column names, SQL-formatted datetimes,
  /// JSON-encoded payload, our epoch_seq.
  Map<String, Object?> _rowFor(TrajectoryEnvelope envelope, int epochSeq) {
    final row = envelope.toJson()
      ..remove('seq')
      ..['epoch_seq'] = epochSeq
      ..['payload'] = jsonEncode(envelope.payload);
    for (final key in const ['occurred_at', 'recorded_at', 'expires_at']) {
      final value = row[key];
      if (value is String) row[key] = _sqlDate(DateTime.parse(value));
    }
    return row;
  }

  /// DATETIME(6) literal: dolt refuses ISO-8601's trailing `Z`.
  static String _sqlDate(DateTime value) {
    final utc = value.toUtc();
    String pad(int n, int width) => n.toString().padLeft(width, '0');
    return '${pad(utc.year, 4)}-${pad(utc.month, 2)}-${pad(utc.day, 2)} '
        '${pad(utc.hour, 2)}:${pad(utc.minute, 2)}:${pad(utc.second, 2)}'
        '.${pad(utc.microsecond + utc.millisecond * 1000, 6)}';
  }
}
