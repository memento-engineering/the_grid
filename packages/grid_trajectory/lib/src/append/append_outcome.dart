/// Typed results for the §5 append/claim contract.
///
/// The contract's named dispositions are RESULTS, not exceptions — a caller
/// switches on the sealed hierarchy; only genuinely unexpected server errors
/// propagate as thrown exceptions.
library;

import 'package:meta/meta.dart';

import '../codec/envelope.dart';

/// One append's disposition.
@immutable
sealed class AppendOutcome {
  const AppendOutcome();
}

/// The row landed. [seq] is dolt-assigned inside the transaction;
/// [epochSeq] is the service-assigned logical position.
final class Appended extends AppendOutcome {
  const Appended({
    required this.recordId,
    required this.seq,
    required this.epochSeq,
    required this.envelope,
  });

  final String recordId;
  final int seq;
  final int epochSeq;

  /// THE POST-ACK MIRROR SEAM (cut-wiring §0.2, r4 — J6-B4): the envelope the
  /// transaction actually COMMITTED, handed back so an in-process fold mirror
  /// can apply the same pure delta the SQL fold applied — at ordinal [seq],
  /// which the same transaction wrote as `proj_meta.applied_seq`, so
  /// `mirrorOrdinal ≡ applied_seq` is earned rather than reconstructed.
  ///
  /// This is the COMMITTED shape, not the caller's intent: when the resolving
  /// pre-read rebuilds a terminal into settling form
  /// ([AppendRefusedTestimony]'s sibling arm), THIS is the rebuilt envelope —
  /// the one the log holds and `traj replay` decodes.
  ///
  /// `seq`/`epoch_seq` are read off this outcome's own fields; the envelope
  /// carries the row's identity, correlation, and provenance.
  final TrajectoryEnvelope envelope;
}

/// TESTIMONY YIELDS TO OBSERVATION (cut-wiring §0.3, r9–r10): an incoming
/// RECONSTRUCTED terminal met an existing `traj_terminal_guard` row for the
/// same attempt — the real terminal already landed, so the testimony is
/// refused before any insert.
///
/// Benign and counted, never a halt and never a drop: the record it would
/// have written is redundant by construction. [existingRecordId] names the
/// terminal that won.
final class AppendRefusedTestimony extends AppendOutcome {
  const AppendRefusedTestimony({
    required this.attemptId,
    required this.existingRecordId,
    required this.reason,
  });

  final String attemptId;
  final String existingRecordId;
  final String reason;
}

/// `1105` naming `uq_idem`: the DESIGNED at-least-once dedupe. [recordId] is
/// the ORIGINAL row's id — to the caller this is success, not an error.
final class AppendDeduped extends AppendOutcome {
  const AppendDeduped({required this.recordId});

  final String recordId;
}

/// Fenced out (§5): a 0-row fence-CAS match (always definitive) or 1213 at
/// COMMIT. The appender has gone INERT — it appends nothing further, not even
/// its own refusal; a successor authority owns the settlements.
final class AppendFencedOut extends AppendOutcome {
  const AppendFencedOut({required this.reason});

  /// Which signal fenced us: `cas-zero-rows`, `commit-1213`, `inert`,
  /// `stale-epoch` (guarded reconnect).
  final String reason;
}

/// The grant belt refused this append (§5 step 2): the grant row's
/// `fencing_token` did not match, or `expires_at` was not after the server's
/// NOW(6). A per-append REFUSAL, not corruption — the transaction is rolled
/// back and the service stays live: §5 scopes the corruption-halt class to
/// its two out-of-order predicates only.
final class AppendGrantRefused extends AppendOutcome {
  const AppendGrantRefused({
    required this.grantId,
    required this.predicate,
    required this.reason,
  });

  final String grantId;

  /// Which belt predicate failed: `fencing_token` or `expires_at`.
  final String predicate;
  final String reason;
}

/// The corruption-halt alarm class — §5's exact scope: a non-decreasing
/// `boot_epoch` violation or a seq/epoch_seq order disagreement (including
/// `1105` naming `uq_epoch_seq`, and a statement-time 1062 with no matching
/// idem_key). Both can only fail if something already committed out of
/// order. The service HALTS — every further append refuses with this same
/// outcome until the appender is recreated by the operator.
final class AppendCorruptionHalt extends AppendOutcome {
  const AppendCorruptionHalt({required this.reason});

  final String reason;
}

/// A non-classified failure inside the append transaction (a client/protocol
/// error, a malformed read, anything outside §5's named classes): the
/// transaction is rolled back and the failure surfaces typed — no raw
/// throwable escapes with a transaction open. Not a latch: the next append
/// runs normally.
final class AppendInternalError extends AppendOutcome {
  const AppendInternalError({required this.cause});

  final Object cause;
}

/// One epoch claim's disposition.
@immutable
sealed class EpochClaimOutcome {
  const EpochClaimOutcome();
}

final class EpochClaimed extends EpochClaimOutcome {
  const EpochClaimed({required this.epoch});

  final int epoch;
}

/// The claim lost its 1213 races past the retry budget — the caller refuses
/// to boot rather than fighting a live authority.
final class EpochClaimRefused extends EpochClaimOutcome {
  const EpochClaimRefused({required this.attempts});

  final int attempts;
}
