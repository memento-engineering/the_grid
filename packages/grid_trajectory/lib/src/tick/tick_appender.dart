/// The narrow appender seam the tick runs over.
///
/// The tick needs four things from the §5 write path: whether the authority is
/// still ours ([isInert] / [isHalted]), the fenced append itself, and the
/// cadence commit that must fire on the interval even when a pass appends
/// nothing. Keeping the seam this small is what lets the tick's own contract
/// (skip when fenced, run to fixpoint) be tested without a SQL session.
library;

import '../append/append_outcome.dart';
import '../append/trajectory_appender.dart';
import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';

/// What the tick is allowed to ask of the fenced appender.
abstract interface class TickAppender {
  /// Fenced out (§5) — the pass repairs nothing. Not permanent: a successor
  /// `claimEpoch` clears it, so the tick keeps its timer armed.
  bool get isInert;

  /// The corruption-halt alarm class — the appender refuses everything until
  /// an operator recreates it.
  bool get isHalted;

  Future<AppendOutcome> append(
    TrajectoryRecord record, {
    String? substation,
    TrajectoryProvenance provenance,
    String? provenanceBasis,
  });

  /// The §5 dolt-commit cadence. The tick calls it once per pass so cadence
  /// commits land on a quiet station too; the hard minimum interval lives in
  /// the appender, not here.
  Future<void> doltCommitIfDue();
}

/// Binds the concrete [TrajectoryAppender] to [TickAppender].
///
/// An adapter rather than an `implements` clause on the appender: the append
/// path owns its own full signature (substation, occurred_at, source), and the tick
/// has no business widening it.
final class AppenderTickPort implements TickAppender {
  const AppenderTickPort(this._appender);

  final TrajectoryAppender _appender;

  @override
  bool get isInert => _appender.isInert;

  @override
  bool get isHalted => _appender.isHalted;

  @override
  Future<AppendOutcome> append(
    TrajectoryRecord record, {
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) async => _appender.append(
    record,
    substation: substation,
    provenance: provenance,
    provenanceBasis: provenanceBasis,
  );

  @override
  Future<void> doltCommitIfDue() async => _appender.doltCommitIfDue();
}
