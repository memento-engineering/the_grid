/// Per-pass tick telemetry — the value objects the owner reads and flares.
///
/// A pass is reportable even when it did nothing: "skipped, fenced out" is the
/// answer to "why did this station repair nothing", and the clean-down path
/// (§5) needs the outstanding count to put in `authority.epoch.closed`.
library;

import 'package:meta/meta.dart';

/// Why a pass did or did not run.
enum TickPassDisposition {
  /// Ran the obligation set (which is empty at Stage 0).
  ran,

  /// The appender is inert — a fenced-out tick repairs nothing, correctly.
  skippedFencedOut,

  /// The appender is halted on the corruption-halt alarm class.
  skippedHalted,

  /// A pass was already in flight; the interval does not stack passes.
  skippedBusy,

  /// The tick is disposed.
  skippedDisposed,
}

/// What kept a repair from landing.
enum TickRefusalKind {
  /// The append came back `AppendFencedOut` — the fence changed hands
  /// mid-pass.
  fencedOut,

  /// The append came back `AppendCorruptionHalt`.
  corruptionHalt,

  /// The obligation's own SQL or repair action threw.
  queryFailed,

  /// The pass itself threw outside a query (e.g. the branch-pin fail-closed).
  passFailed,
}

/// One refusal inside a pass.
@immutable
final class TickRefusal {
  const TickRefusal({
    required this.kind,
    required this.query,
    required this.reason,
    this.recordType,
  });

  final TickRefusalKind kind;

  /// The obligation that produced it, or `'<pass>'` for [TickRefusalKind.passFailed].
  final String query;

  final String reason;

  /// The record that would have been appended, when there was one.
  final String? recordType;

  @override
  String toString() =>
      'TickRefusal(${kind.name}, $query'
      '${recordType == null ? '' : ', $recordType'}: $reason)';
}

/// One tick pass, as a value.
@immutable
final class TrajectoryTickPass {
  const TrajectoryTickPass({
    required this.startedAt,
    required this.disposition,
    this.queriesRun = 0,
    this.recordsAppended = 0,
    this.recordsDeduped = 0,
    this.refusals = const [],
  });

  final DateTime startedAt;
  final TickPassDisposition disposition;
  final int queriesRun;

  /// Rows that landed. Deduped repairs are counted separately: an
  /// at-least-once repeat is success, but it is not progress.
  final int recordsAppended;
  final int recordsDeduped;
  final List<TickRefusal> refusals;

  bool get ran => disposition == TickPassDisposition.ran;

  /// Nothing appended and nothing refused — this pass found no work. The
  /// fixpoint predicate.
  bool get quiet => recordsAppended == 0 && refusals.isEmpty;

  int get outstanding => refusals.length;

  @override
  String toString() =>
      'TrajectoryTickPass(${disposition.name}, queries: $queriesRun, '
      'appended: $recordsAppended, deduped: $recordsDeduped, '
      'refusals: ${refusals.length})';
}

/// The result of driving the tick to fixpoint (§5's clean-down path).
///
/// [reached] false is not a crash: a fenced-out or pass-capped run is exactly
/// the case where `authority.epoch.closed` carries [outstanding] in its
/// payload and flares, leaving the remainder to the successor's boot tick.
@immutable
final class TrajectoryTickFixpoint {
  const TrajectoryTickFixpoint({required this.passes, required this.reached});

  final List<TrajectoryTickPass> passes;
  final bool reached;

  int get recordsAppended =>
      passes.fold(0, (total, pass) => total + pass.recordsAppended);

  /// What the last pass could not repair — 0 on a reached fixpoint.
  int get outstanding => passes.isEmpty ? 0 : passes.last.outstanding;

  @override
  String toString() =>
      'TrajectoryTickFixpoint(reached: $reached, passes: ${passes.length}, '
      'appended: $recordsAppended, outstanding: $outstanding)';
}
