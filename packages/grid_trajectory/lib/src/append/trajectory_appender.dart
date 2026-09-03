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
///   2. the belt: `boot_epoch` non-decreasing over `seq` and seq order
///      agreeing with `(boot_epoch, epoch_seq)` order — the corruption-halt
///      alarm class, §5's exact scope: both predicates can only fail if
///      something already committed out of order. Grant-scoped appends also
///      match the grant row's `fencing_token` and `expires_at > NOW(6)` —
///      a failed grant predicate is a per-append REFUSAL, never a halt;
///   2c. the RESOLVING PRE-READ for terminals (cut-wiring §0.3, r9–r11):
///      the attempt's `traj_terminal_guard` row joined to its record's
///      provenance decides, BEFORE the insert, whether this terminal converts
///      to settling form (observed/inferred over reconstructed testimony), is
///      refused as redundant testimony, or appends normally. Authoring the
///      final shape here is what keeps the log, the live fold, and
///      `traj replay` in agreement;
///   3. INSERT the `trajectory` row (`epoch_seq` service-assigned in the
///      serialized stream);
///   4. `traj_terminal_guard` insert/update for terminals;
///   5. the synchronous fold delta — in Stage 0, `proj_meta.applied_seq`;
///   COMMIT.
///
/// Error contract, exactly §5's three classes: 1213 → fenced out, inert;
/// 1105 branched on the constraint NAMED in the message (`uq_idem` → the
/// designed dedupe, return the original record_id; `uq_epoch_seq` →
/// corruption halt); belt order violation → corruption halt. A halted
/// appender refuses every further append until recreated; an inert one
/// appends nothing further, not even its refusal. Any non-classified
/// throwable rolls the transaction back and surfaces as [AppendInternalError]
/// — no open transaction and no raw throwable escapes the sealed hierarchy.
/// That holds for the WHOLE of [append], not merely its transaction: the
/// pre-transaction branch pin is inside the classification boundary too, so a
/// dead connection is an [AppendInternalError] and an off-main session is an
/// [AppendCorruptionHalt] (M4's recorded gap, closed). A DIRECT
/// [doltCommitIfDue] call still throws — that path has no outcome to carry.
///
/// The dolt-commit cadence runs AFTER the append's outcome is decided: once
/// COMMIT succeeded the append IS [Appended], and a cadence failure is its
/// own non-fatal [TrajectoryServiceEventKind.cadenceFailure] signal (retried
/// at the next cadence), never a rewrite of the append's disposition.
///
/// EXTRACTION BOUNDARY (decision: grid-trajectory-leaf-package, "Long-term
/// direction"): this file is MECHANICS. It knows `TrajectoryRecord`,
/// `TrajectoryEnvelope`, the promoted envelope columns, and the interface
/// properties on the sealed base — `isTerminal`, `isSettling`,
/// `forcesDoltCommitBoundary`, `grantBeltIssuerType`. It names no concrete
/// record class and no `record_type` literal, in Dart or in SQL: the
/// vocabulary is handed in. `test/architecture/extraction_boundary_test.dart`
/// enforces it, so a new special case belongs on the base class, not here.
library;

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:mysql_client/exception.dart';

import '../codec/envelope.dart';
import '../codec/idem_key.dart';
import '../codec/trajectory_record.dart';
import '../connect/trajectory_db.dart';
import '../ddl/column_bounds.dart';
import 'append_outcome.dart';
import 'service_event.dart';
import 'ulid.dart';

/// One registered synchronous fold delta — §5 step 5's registration seam
/// (stage1-wiring §2.4/W6). The composition hands these IN fully constructed
/// (the vocabulary side dispatches on record types; `kStage1FoldDeltas` is
/// the Stage-1 set); the mechanics run the returned statements inside the
/// append transaction — after the row INSERT assigns `seq`, before COMMIT —
/// and never know which projection they maintain. An empty list means "this
/// record touches none of my rows".
typedef TrajectoryFoldDelta =
    List<({String sql, Map<String, Object?> params})> Function(
      TrajectoryEnvelope envelope,
      TrajectoryRecord record, {
      required int seq,
    });

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
    TrajectoryEventSink onEvent = stdoutTrajectoryEventSink,
    List<TrajectoryFoldDelta> folds = const [],
    bool resolveTerminals = false,
  }) : _db = db,
       _clock = clock ?? DateTime.now,
       _commitCadence = commitCadence,
       _commitMinInterval = commitMinInterval,
       _commitRowThreshold = commitRowThreshold,
       _onEvent = onEvent,
       _folds = folds,
       _resolveTerminals = resolveTerminals;

  TrajectoryDb _db;
  final String station;
  final String source;
  final DateTime Function() _clock;
  final Duration _commitCadence;
  final Duration _commitMinInterval;
  final int _commitRowThreshold;
  final TrajectoryEventSink _onEvent;

  /// THE RESOLVING PRE-READ'S POSTURE (cut-wiring §0.3, gated r13).
  ///
  /// The pre-read exists to convert a terminal landing on an already-present
  /// RECONSTRUCTED terminal into its settling form, and reconstructed
  /// terminals are appended only where the dual read is armed. Default FALSE
  /// — off is the rollback and the pre-Stage-1 semantics: no in-transaction
  /// `traj_terminal_guard` SELECT per terminal on the serialized writer lane,
  /// and a guard-PK collision propagates to §5's ordinary duplicate contract
  /// exactly as it did on mainline.
  ///
  /// The ONE caveat, documented on `TrajectoryConfig.dualRead`: downgrading a
  /// home to `off` AFTER an observe-era soak left reconstructed rows means a
  /// late REAL terminal for such an attempt is no longer converted, so it
  /// halts loudly on the guard PK instead. Bounce back to `observe` once to
  /// convert those rows.
  final bool _resolveTerminals;

  /// §5 step 5's registered synchronous folds, in registration order.
  final List<TrajectoryFoldDelta> _folds;

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
  /// The INSERT computes MAX+1 server-side and the claim adopts its OWN row:
  /// the epoch is read back inside the same transaction snapshot, where a
  /// rival claim landing after our INSERT is invisible and surfaces as 1213
  /// at COMMIT (dolt's write-write conflict arbitrates — probe T6c) — never
  /// as a re-read of another authority's MAX. 1213 is re-read and retried up
  /// to [maxAttempts]. 1062 is deliberately NOT caught: the PK is not the
  /// arbiter, and seeing it means something is structurally wrong.
  Future<EpochClaimOutcome> claimEpoch({
    required int pid,
    required int pgid,
    String cause = 'boot',
    int maxAttempts = 3,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final int epoch;
      try {
        await _db.execute('START TRANSACTION');
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
        // Same-transaction snapshot: this is the row WE inserted.
        epoch = await _readLiveEpoch();
        await _db.execute('COMMIT');
      } on MySQLServerException catch (error) {
        await _rollbackQuietly();
        if (!isSerializationFailure(error)) rethrow;
        // Re-read, then retry or refuse — never treat the race as fatal.
        await _readLiveEpoch();
        continue;
      }
      // Fence-cell UPSERT: the claim path is also what SEEDS the row on a
      // fresh grid home or after trap recovery (§5, cert round).
      await _seedFence(epoch);
      _bootEpoch = epoch;
      // The epoch_seq stream is in-memory, serialized, and tied to THIS
      // claim — it restarts at 0 with the epoch.
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
      _emit(
        TrajectoryServiceEventKind.reconnectInert,
        'stale epoch $own (live $live) — inert without touching the fence',
      );
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

  // ── belt full-scan (§1: "full-scanned at boot") ──────────────────────────

  /// The boot-time belt: full-scans this station's log in `seq` order and
  /// verifies what the per-append belt asserts incrementally — `boot_epoch`
  /// non-decreasing over `seq`, and `seq` order agreeing with
  /// `(boot_epoch, epoch_seq)` order. A violation is the corruption-halt
  /// alarm class (something already committed out of order): the appender
  /// halts and the returned outcome names the offending pair. Null = clean.
  Future<AppendCorruptionHalt?> verifyBeltAtBoot() async {
    final result = await _db.execute(
      'SELECT seq, boot_epoch, epoch_seq FROM trajectory '
      'WHERE station = :station ORDER BY seq',
      {'station': station},
    );
    int? prevSeq;
    var prevEpoch = 0;
    var prevEpochSeq = 0;
    for (final row in result.rows) {
      final seq = int.parse(row['seq']!);
      final epoch = int.parse(row['boot_epoch']!);
      final epochSeq = int.parse(row['epoch_seq']!);
      if (prevSeq != null &&
          !_ordered(prevEpoch, prevEpochSeq, epoch, epochSeq)) {
        return _haltNow(
          'belt full-scan: seq $prevSeq ($prevEpoch/$prevEpochSeq) then '
          'seq $seq ($epoch/$epochSeq) — seq order disagrees with '
          '(boot_epoch, epoch_seq) order',
        );
      }
      prevSeq = seq;
      prevEpoch = epoch;
      prevEpochSeq = epochSeq;
    }
    return null;
  }

  // ── append (§5 steps 1–5) ────────────────────────────────────────────────

  /// [fencingToken] rides grant-scoped appends: the belt matches it against
  /// the grant row's `fencing_token` (§5 step 2).
  Future<AppendOutcome> append(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
    String? source,
    int? fencingToken,
  }) async {
    if (_halted) {
      return const AppendCorruptionHalt(
        reason: 'appender is halted; recreate it after operator review',
      );
    }
    if (_inert) return const AppendFencedOut(reason: 'inert');
    final epoch = _requireEpoch();
    // §5's branch pin holds on the append path too, not only at cadence
    // time: asserted before the transaction so an off-main session surfaces
    // as the named fail-closed refusal, not a missing-table crash (T3).
    //
    // It runs INSIDE append()'s classification boundary (M4's recorded gap):
    // the assertion itself talks to the server, so with the connection dead
    // it used to throw a raw MySQLClientException past the sealed hierarchy —
    // exactly what §5's error contract forbids. Nothing here rethrows.
    try {
      await _assertBranchPin();
    } on Object catch (error) {
      // _assertBranchPin HALTS before it throws, so `_halted` is what tells
      // the pin's own fail-closed refusal apart from a transport failure on
      // the way to it. Fail-closed is preserved either way — the halt latch
      // is already set and every later append refuses.
      return _halted
          ? AppendCorruptionHalt(reason: '$error')
          : AppendInternalError(cause: error);
    }

    final now = _clock().toUtc();
    final context = IdemContext(station: station, bootEpoch: epoch);
    // The envelope builder, not just the envelope: the resolving pre-read
    // (§0.3's TESTIMONY YIELDS TO OBSERVATION) may re-author the record in its
    // settling form INSIDE the transaction, and the rebuilt row must be
    // stamped from exactly these inputs — same clock instant, same substation, same
    // provenance — with only the record's own identity and correlation
    // changing. A re-mint of `record_id` is part of that (V5 build note).
    TrajectoryEnvelope build(TrajectoryRecord subject) => _buildEnvelope(
      subject,
      context: context,
      now: now,
      occurredAt: occurredAt?.toUtc() ?? now,
      substation: substation,
      provenance: provenance,
      provenanceBasis: provenanceBasis,
      source: source ?? this.source,
      fencingToken: fencingToken,
    );
    final envelope = build(record);

    final outcome = await _appendInTransaction(
      record,
      envelope,
      rebuild: build,
    );
    if (outcome is Appended) {
      // Post-COMMIT the row IS durable: a cadence failure is its own
      // non-fatal signal, retried at the next cadence — it never rewrites
      // the append's disposition and never loses the Appended result.
      try {
        await doltCommitIfDue();
      } on Object catch (error) {
        _emit(
          TrajectoryServiceEventKind.cadenceFailure,
          'dolt cadence commit failed after seq ${outcome.seq} '
          '(retried next cadence): $error',
        );
      }
    }
    return outcome;
  }

  Future<AppendOutcome> _appendInTransaction(
    TrajectoryRecord incomingRecord,
    TrajectoryEnvelope incomingEnvelope, {
    required TrajectoryEnvelope Function(TrajectoryRecord) rebuild,
  }) async {
    // Both are re-bindable: the resolving pre-read below can replace the pair
    // with the settling re-authoring BEFORE the row insert, and everything
    // downstream — the row, the guard arm, the folds, the outcome — reads the
    // rebound pair, so the log holds the shape the fold and `traj replay` see.
    var record = incomingRecord;
    var envelope = incomingEnvelope;
    final epoch = _requireEpoch();
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
        _emit(
          TrajectoryServiceEventKind.fencedOut,
          'fence CAS matched 0 rows at epoch $epoch — a successor holds the '
          'authority; going inert',
        );
        return const AppendFencedOut(reason: 'cas-zero-rows');
      }

      // Step 2 — the belt. The previous row anchors both order predicates.
      final previous = await _db.execute(
        'SELECT seq, boot_epoch, epoch_seq FROM trajectory '
        'WHERE station = :station ORDER BY seq DESC LIMIT 1',
        {'station': station},
      );
      int? prevSeq;
      var prevEpoch = 0;
      var prevEpochSeq = 0;
      if (previous.rows.isNotEmpty) {
        final row = previous.rows.first;
        prevSeq = int.parse(row['seq']!);
        prevEpoch = int.parse(row['boot_epoch']!);
        prevEpochSeq = int.parse(row['epoch_seq']!);
        if (prevEpoch > epoch) {
          return await _haltInTransaction(
            'belt: boot_epoch would decrease over seq '
            '($prevEpoch then $epoch) — a higher epoch already committed',
          );
        }
      }
      final grantBelt = await _assertGrantBelt(
        envelope,
        issuerType: record.grantBeltIssuerType,
      );
      if (grantBelt != null) return grantBelt;

      // Step 2c — THE RESOLVING PRE-READ (cut-wiring §0.3, r9–r11): a
      // terminal's disposition against an EXISTING terminal for the same
      // attempt is decided here, at the top of the serialized transaction and
      // BEFORE the row insert, because the record must be AUTHORED in its
      // final shape — a conversion after the insert would leave the log
      // holding one shape while the live fold applied another, and `traj
      // replay` would then diverge from the incremental fold (V4-B1).
      //
      // The trichotomy is EXHAUSTIVE over the INCOMING provenance:
      //   (a) guard row exists, its record is reconstructed TESTIMONY, and
      //       this append is not — observed AND inferred both convert: the
      //       envelope is rebuilt in settling form carrying the incoming
      //       outcome, so the guard takes its UPDATE arm (no PK contention)
      //       and the delta writes the real outcome;
      //   (b) guard row exists and THIS append is the reconstructed one — the
      //       real terminal already landed: refused, counted, no insert;
      //   (c) no guard row — the ordinary non-settling append.
      // Everything else (two observed terminals) stays the corruption class.
      //
      // THE PRE-READ IS DETERMINISTIC UNDER RETRY (r12). The conversion in (a)
      // re-authors the record, and re-authoring MOVES the idem key
      // (`terminal:<attempt>` → `terminal-resolve:<attempt>:<healed>`), so the
      // key the caller computed is never written and §5's at-least-once
      // dedupe has nothing to match on a re-presentation. The cure is
      // determinism, not a second key: once the guard is SETTLED it still
      // names the record that was healed (`settled_by` says settled,
      // `resolves_record_id` says of what), so a retry re-derives the SAME
      // settling envelope and therefore the SAME idem key — and the settled
      // arm answers it as the dedupe-shaped no-op it is, without an insert.
      // Falling through instead is what turned an ordinary retry into a
      // guard-PK corruption halt that suppressed every later append.
      //
      // AND IT IS POSTURE-GATED (r13): under `DualReadMode.off` nothing
      // appends a reconstructed terminal, so the answer here is structurally
      // always null and the read is a pure round trip on the serialized
      // writer lane. `off` takes the pre-Stage-1 collision semantics instead
      // — see [_resolveTerminals].
      _TerminalGuardState? preRead;
      if (_resolveTerminals && record.isTerminal && !record.isSettling) {
        final subject = envelope.attemptId;
        final existing = subject == null
            ? null
            : await _readTerminalGuard(subject);
        preRead = existing;
        if (existing != null && subject != null) {
          if (envelope.provenance == TrajectoryProvenance.reconstructed) {
            await _rollbackQuietly();
            return AppendRefusedTestimony(
              attemptId: subject,
              existingRecordId: existing.recordId,
              reason:
                  'terminal guard: attempt $subject already carries a '
                  '${existing.provenance.wire} terminal '
                  '(${existing.recordId}) — reconstructed testimony yields '
                  'to it and is not appended',
            );
          }
          if (existing.isSettled) {
            // (a′) THE RETRY ARM: this attempt's reconstructed terminal has
            // ALREADY been settled. Re-author against the same subject the
            // landed settlement healed — same guard state, same converted
            // envelope, same settling idem key — and answer from the log.
            final subjectRecordId = _settledSubjectOf(existing);
            final settling = record.settlingForm(subjectRecordId);
            if (settling == null) {
              return await _haltInTransaction(
                'terminal guard: ${envelope.recordType} must settle the '
                'terminal $subjectRecordId for attempt $subject but declares '
                'no settling form',
              );
            }
            final settled = rebuild(settling);
            final original = await _recordIdForIdemKey(settled.idemKey);
            if (original != null) {
              // The at-least-once re-presentation of the very append that
              // settled this guard: byte-identical work, already committed.
              await _rollbackQuietly();
              return AppendDeduped(recordId: original);
            }
            // A non-reconstructed terminal arriving after a settlement that it
            // did NOT author. The guard permits a chain, not a second
            // independent terminal, and there is no idem row to yield to —
            // corruption class, named for what it is.
            return await _haltInTransaction(
              'terminal guard: attempt $subject is already settled by '
              '${existing.settledBy} (healing $subjectRecordId) and this '
              '${envelope.provenance.wire} ${envelope.recordType} settles '
              'nothing that landed — a second independent terminal',
            );
          }
          if (existing.provenance == TrajectoryProvenance.reconstructed) {
            final settling = record.settlingForm(existing.recordId);
            if (settling == null) {
              return await _haltInTransaction(
                'terminal guard: ${envelope.recordType} must settle the '
                'reconstructed terminal ${existing.recordId} for attempt '
                '$subject but declares no settling form',
              );
            }
            record = settling;
            envelope = rebuild(settling);
          }
        }
      }

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

      // Step 2's second predicate, checkable only once seq exists: the §5
      // alarm — seq order must agree with (boot_epoch, epoch_seq) order.
      if (prevSeq != null &&
          (seq <= prevSeq ||
              !_ordered(prevEpoch, prevEpochSeq, epoch, candidateEpochSeq))) {
        return await _haltInTransaction(
          'belt: seq $prevSeq ($prevEpoch/$prevEpochSeq) then seq $seq '
          '($epoch/$candidateEpochSeq) — seq order disagrees with '
          '(boot_epoch, epoch_seq) order',
        );
      }

      // Step 4 — the terminal guard: unsettled terminals INSERT (a second
      // independent terminal dies on the PK); a settling one UPDATEs. The
      // subject is the PROMOTED `attempt_id` column, and the two branches are
      // interface properties on the sealed base — the mechanics never name
      // the terminal record type.
      if (record.isTerminal) {
        final attemptId = envelope.attemptId;
        if (attemptId == null) {
          // Structurally unreachable: the guard's subject is exactly what
          // makes a record terminal. Fail closed rather than guess a key.
          return await _haltInTransaction(
            'terminal guard: ${envelope.recordType} declares isTerminal but '
            'carries no attempt_id — the guard row has no subject',
          );
        }
        if (record.isSettling) {
          await _db.execute(
            'UPDATE traj_terminal_guard SET seq = :seq, '
            'settled_by = :settled_by WHERE attempt_id = :attempt_id',
            {
              'seq': seq,
              'settled_by': envelope.recordId,
              'attempt_id': attemptId,
            },
          );
        } else {
          try {
            await _db.execute(
              'INSERT INTO traj_terminal_guard (attempt_id, seq, settled_by) '
              'VALUES (:attempt_id, :seq, NULL)',
              {'attempt_id': attemptId, 'seq': seq},
            );
          } on MySQLServerException catch (error) {
            if (!isDuplicateEntry(error)) rethrow;
            // PRE-STAGE-1 SEMANTICS AT `off` (r13): with no resolving
            // pre-read there is no evidence to name a shape with, so the
            // duplicate propagates to §5's ordinary 1062 contract below —
            // byte-identical to mainline, which never caught it here.
            if (!_resolveTerminals) rethrow;
            // TWO CORRUPTION SHAPES, and the halt reason is the operator's
            // only evidence — so it must name the one that actually happened
            // (r12). The pre-read above ran in THIS serialized transaction:
            //   * it SAW a guard row and no branch claimed it ⇒ the genuine
            //     two-independent-OBSERVED-terminals class, which the design
            //     says falls through to the insert by design;
            //   * it saw NOTHING ⇒ a PK collision is only reachable if the
            //     single-writer serialization invariant itself broke.
            final seen = preRead;
            return await _haltInTransaction(
              seen == null
                  ? 'terminal guard: PK collision on attempt $attemptId after '
                        'a clean resolving pre-read — the serialized '
                        'single-writer invariant broke: $error'
                  : 'terminal guard: attempt $attemptId already carries a '
                        '${seen.provenance.wire} terminal (${seen.recordId}) '
                        'and this ${envelope.provenance.wire} '
                        '${envelope.recordType} settles nothing — two '
                        'independent terminals for one attempt: $error',
            );
          }
        }
      }

      // Step 5 — the synchronous fold deltas: the registered projections
      // first (Stage 1 hands in the P1+P2+P6 set), then the applied_seq
      // cursor. A registered fold's statements ride the SAME transaction and
      // the same error contract — a failure rolls the append back whole.
      for (final fold in _folds) {
        for (final statement in fold(envelope, record, seq: seq)) {
          await _db.execute(statement.sql, statement.params);
        }
      }
      await _db.execute(
        'INSERT INTO proj_meta (projection, fold_version, applied_seq) '
        "VALUES ('fold', 1, :seq) "
        'ON DUPLICATE KEY UPDATE applied_seq = :seq',
        {'seq': seq},
      );

      await _db.execute('COMMIT');

      _epochSeq = candidateEpochSeq;
      // §5's boundary set is a property of the record type, declared on the
      // vocabulary side; the cadence only asks.
      _noteCommitted(seq, boundary: record.forcesDoltCommitBoundary);
      return Appended(
        recordId: envelope.recordId,
        seq: seq,
        epochSeq: candidateEpochSeq,
        // The COMMITTED envelope rides back (§0.2's post-ACK mirror seam):
        // an in-process fold mirror applies the same pure delta the
        // registered folds just applied, at this same ordinal.
        envelope: envelope,
      );
    } on MySQLServerException catch (error) {
      await _rollbackQuietly();
      if (isSerializationFailure(error)) {
        // 1213 at COMMIT arbitrates the contended interleavings: on the
        // append path this IS the fenced-out signal.
        _inert = true;
        _emit(
          TrajectoryServiceEventKind.fencedOut,
          '1213 at commit — a successor won the interleaving; going inert',
        );
        return const AppendFencedOut(reason: 'commit-1213');
      }
      if (isUniqueViolationOn(error, 'uq_idem')) {
        // The designed at-least-once dedupe: hand back the original row.
        return _dedupeOriginal(envelope);
      }
      if (isUniqueViolationOn(error, 'uq_epoch_seq')) {
        return _haltNow(
          'uq_epoch_seq violation at commit — the belt caught an '
          'interleave the fence missed: $error',
        );
      }
      if (isDuplicateEntry(error)) {
        // Measured on dolt 2.2 (stage-0 cert; §5 error-contract amendment):
        // a duplicate already visible in the session snapshot dies at
        // STATEMENT time as 1062 naming the duplicate VALUE, not at COMMIT
        // as a constraint-named 1105 — 1105 remains the concurrent-commit
        // shape. The value doesn't say which unique key fired, so the log
        // arbitrates: an existing row under our idem_key is the designed
        // dedupe; anything else is the belt's epoch_seq/record_id class —
        // halt.
        final original = await _db.execute(
          'SELECT record_id FROM trajectory WHERE idem_key = :idem_key',
          {'idem_key': envelope.idemKey},
        );
        if (original.rows.isNotEmpty) {
          return AppendDeduped(recordId: original.rows.first['record_id']!);
        }
        return _haltNow(
          'duplicate key on append with no matching idem_key — '
          'epoch_seq/record_id collision: $error',
        );
      }
      // Non-classified server error: still typed, still rolled back — the
      // sealed hierarchy is the whole surface (§5 error contract).
      return AppendInternalError(cause: error);
    } on Object catch (error) {
      // Catch-all: no throwable may escape with the transaction open.
      await _rollbackQuietly();
      return AppendInternalError(cause: error);
    }
  }

  // ── dolt-commit cadence (§5 dolt-commit policy) ─────────────────────────

  /// Issues a dolt commit when due: [_commitCadence] elapsed, or
  /// [_commitRowThreshold] rows pending, or a boundary event landed — but
  /// NEVER within [_commitMinInterval] of the previous verified commit
  /// (probe T7b: commit COUNT, not row count, is the storage lever).
  ///
  /// The tick calls this on its 30s interval so cadence commits fire even
  /// with no new appends; [append] calls it after every landed row and
  /// downgrades a failure here to a [TrajectoryServiceEventKind
  /// .cadenceFailure] signal — the committed row's outcome is already
  /// decided. A branch-pin violation throws out of a DIRECT call,
  /// deliberately: fail closed.
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

    await _assertBranchPin();

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

  /// Lexicographic (boot_epoch, epoch_seq) order — must be strictly
  /// increasing wherever seq increases (§5's alarm predicate).
  static bool _ordered(
    int prevEpoch,
    int prevEpochSeq,
    int epoch,
    int epochSeq,
  ) => epoch > prevEpoch || (epoch == prevEpoch && epochSeq > prevEpochSeq);

  /// Branch pin, fail closed (probe T3): committing — or appending — off
  /// main would target a different working set entirely.
  Future<void> _assertBranchPin() async {
    final branch = await _db.execute('SELECT active_branch() AS b');
    final active = branch.rows.isEmpty ? null : branch.rows.first['b'];
    if (active != 'main') {
      _halted = true;
      _emit(
        TrajectoryServiceEventKind.corruptionHalt,
        'session branch changed to ${active ?? 'unknown'} — the service pins '
        'main and fails closed',
      );
      throw StateError(
        'session branch changed to ${active ?? 'unknown'} — the service pins '
        'main and fails closed',
      );
    }
  }

  void _emit(TrajectoryServiceEventKind kind, String reason) =>
      _onEvent(TrajectoryServiceEvent(kind, reason));

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

  /// Grant-scoped belt (§5 step 2): a consuming append must match the grant
  /// row's `fencing_token` and find it unexpired against the SERVER's NOW(6)
  /// — never the client clock. A failed predicate is a per-append REFUSAL
  /// (rolled back, service live): §5 scopes the corruption-halt class to the
  /// two out-of-order predicates only. Issuing/closing records are exempt —
  /// expiry is exactly what `.expired` reports.
  ///
  /// [issuerType] IS the exemption, and it arrives from the record
  /// ([TrajectoryRecord.grantBeltIssuerType]): null means "this record
  /// consumes no grant", and a non-null value names the row to match against.
  /// The belt therefore enforces the predicates without knowing which record
  /// types they belong to (the extraction boundary).
  Future<AppendOutcome?> _assertGrantBelt(
    TrajectoryEnvelope envelope, {
    required String? issuerType,
  }) async {
    if (issuerType == null) return null;
    final grantId = envelope.grantId;
    if (grantId == null) return null;
    final grant = await _db.execute(
      'SELECT expires_at, fencing_token, NOW(6) AS server_now FROM trajectory '
      'WHERE record_type = :issuer_type AND grant_id = :grant_id '
      'ORDER BY seq DESC LIMIT 1',
      {'issuer_type': issuerType, 'grant_id': grantId},
    );
    if (grant.rows.isEmpty) return null;
    final row = grant.rows.first;
    final grantToken = row['fencing_token'];
    if (grantToken != null && '${envelope.fencingToken}' != grantToken) {
      return _refuseGrant(
        grantId: grantId,
        predicate: 'fencing_token',
        reason:
            'belt: grant $grantId fencing_token $grantToken does not match '
            'the append\'s ${envelope.fencingToken} — '
            '${envelope.recordType} refused',
      );
    }
    final expiresAt = _parseServerInstant(row['expires_at']!);
    final serverNow = _parseServerInstant(row['server_now']!);
    if (!expiresAt.isAfter(serverNow)) {
      return _refuseGrant(
        grantId: grantId,
        predicate: 'expires_at',
        reason:
            'belt: grant $grantId expired at $expiresAt (server now '
            '$serverNow) — ${envelope.recordType} refused',
      );
    }
    return null;
  }

  Future<AppendOutcome> _refuseGrant({
    required String grantId,
    required String predicate,
    required String reason,
  }) async {
    await _rollbackQuietly();
    _emit(TrajectoryServiceEventKind.grantRefused, reason);
    return AppendGrantRefused(
      grantId: grantId,
      predicate: predicate,
      reason: reason,
    );
  }

  /// The resolving pre-read's ONE statement: the attempt's
  /// `traj_terminal_guard` row joined to the record it points at.
  ///
  /// The guard row carries no provenance of its own — it carries the `seq` —
  /// so the JOIN is the stated read (r10, V4 note 1). Null means no terminal
  /// has landed for this attempt.
  ///
  /// `settledBy` and `resolvesRecordId` come back too, because the SETTLED
  /// state is a distinct pre-read answer (r12): once a settling record landed,
  /// the guard's `seq` points at IT, and the record it healed is named by its
  /// own `resolves_record_id`. Without those two columns the pre-read cannot
  /// re-derive the conversion it already performed, and an at-least-once retry
  /// of the settling append reads as a brand-new terminal.
  Future<_TerminalGuardState?> _readTerminalGuard(String attemptId) async {
    final result = await _db.execute(
      'SELECT t.record_id AS record_id, t.provenance AS provenance, '
      't.resolves_record_id AS resolves_record_id, '
      'g.settled_by AS settled_by '
      'FROM traj_terminal_guard g JOIN trajectory t ON t.seq = g.seq '
      'WHERE g.attempt_id = :attempt_id',
      {'attempt_id': attemptId},
    );
    if (result.rows.isEmpty) return null;
    final row = result.rows.first;
    final recordId = row['record_id'];
    final provenance = row['provenance'];
    // A guard row whose record vanished is not evidence of a terminal; the
    // append proceeds and the guard's own PK arbitrates.
    if (recordId == null || provenance == null) return null;
    return _TerminalGuardState(
      recordId: recordId,
      provenance: TrajectoryProvenance.fromWire(provenance),
      settledBy: row['settled_by'],
      resolvesRecordId: row['resolves_record_id'],
    );
  }

  /// The record id a retry's conversion must point at, for a guard row that is
  /// already SETTLED: the record the landed settling record healed.
  ///
  /// Falls back to the settling record's own id only if `resolves_record_id`
  /// is somehow absent — a shape `isSettling` forbids, kept so the pre-read is
  /// total.
  String _settledSubjectOf(_TerminalGuardState guard) =>
      guard.resolvesRecordId ?? guard.recordId;

  /// Does a row already carry [idemKey]? The explicit half of the settled-state
  /// dedupe — the retry is answered without ever attempting an insert.
  Future<String?> _recordIdForIdemKey(String idemKey) async {
    final existing = await _db.execute(
      'SELECT record_id FROM trajectory WHERE idem_key = :idem_key',
      {'idem_key': idemKey},
    );
    return existing.rows.isEmpty ? null : existing.rows.first['record_id'];
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
    return _haltNow(reason);
  }

  AppendCorruptionHalt _haltNow(String reason) {
    _halted = true;
    _emit(TrajectoryServiceEventKind.corruptionHalt, reason);
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

  /// DATETIME(6) text (no zone) → UTC instant — the appender writes UTC.
  static DateTime _parseServerInstant(String value) =>
      DateTime.parse('${value.replaceFirst(' ', 'T')}Z');

  TrajectoryEnvelope _buildEnvelope(
    TrajectoryRecord record, {
    required IdemContext context,
    required DateTime now,
    required DateTime occurredAt,
    required String? substation,
    required TrajectoryProvenance provenance,
    required String? provenanceBasis,
    required String source,
    required int? fencingToken,
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
    // The caller's grant token never clobbers a record-carried one (issuing
    // records stamp their own).
    if (fencingToken != null) json['fencing_token'] ??= fencingToken;
    // §2.6 rule 7: substation is service-derived from the bead's store prefix —
    // no caller supplies it, so no caller can forget it (ck_substation).
    final workBeadId = json['work_bead_id'] as String?;
    if (workBeadId != null) {
      json['substation'] = substation ?? _substationFor(workBeadId);
    }
    return TrajectoryEnvelope.fromJson(json);
  }

  static String _substationFor(String workBeadId) {
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
    // The log row's own free-text reason is bounded for the same reason the
    // fold's is: an oversized value would 1105 this INSERT and lose the record
    // entirely. Only `*_reason` columns are touched — `payload` (JSON) keeps
    // the whole text, and `idem_key_text` is identity, never reshaped.
    return boundReasonColumns(kTrajectoryTable, row);
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

/// What the resolving pre-read found for one attempt's `traj_terminal_guard`
/// row — the guard joined to the record it points at.
///
/// Four facts, because the pre-read has to answer three different questions
/// with them: what landed ([recordId] / [provenance]), whether it has since
/// been settled ([settledBy]), and — when it has — WHICH record the settlement
/// healed ([resolvesRecordId]), so a retry re-derives the same settling
/// envelope instead of authoring a fresh terminal.
@immutable
final class _TerminalGuardState {
  const _TerminalGuardState({
    required this.recordId,
    required this.provenance,
    required this.settledBy,
    required this.resolvesRecordId,
  });

  /// The record the guard's `seq` points at — the reconstructed testimony
  /// before a settlement, the SETTLING record after one.
  final String recordId;
  final TrajectoryProvenance provenance;

  /// The settling record's id, or null while the guard is unsettled.
  final String? settledBy;

  /// `resolves_record_id` of the record at the guard's `seq` — non-null
  /// exactly when that record is itself a settlement.
  final String? resolvesRecordId;

  bool get isSettled => settledBy != null;
}
