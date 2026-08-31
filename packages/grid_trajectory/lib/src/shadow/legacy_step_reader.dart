/// The step lane's LEGACY side — an injectable, dependency-free view of one
/// session's step beads.
///
/// Same split as `legacy_session_reader.dart`: this package is a leaf (zero
/// grid_* deps), so the interface lives HERE and the implementation composes
/// in grid_cli over beads_dart's scoped list. The view carries exactly the
/// facts the step bead and `proj_step_cursor` BOTH hold —
/// `grid.step.path`, `grid.step.state`, `grid.step.cooldownUntil` — and
/// nothing else.
///
/// Three step facts are deliberately absent, and their absence is the design,
/// not an omission:
///
///   * **restartCount / incarnation.** §9's unshadowable list names
///     incarnation identity, and `unshadowableMismatchFields` refuses the
///     field AT EMIT. The lane does not route around a landed guard by
///     renaming the column.
///   * **failure_class.** The tg-7ux split (work vs store_unavailable) exists
///     only on the record; `grid.step.failureReason` is capture-only prose
///     that conflates them (stage1-wiring §2.3), so there is no legacy value
///     to compare against.
///   * **startedAt / finishedAt.** Capture-only flow telemetry — clock
///     instants, not dispositions. Comparing them would manufacture a
///     mismatch per step out of formatting and skew.
library;

import 'package:meta/meta.dart';

/// One legacy `type=step` bead, projected to the shadow-comparable facts.
@immutable
class LegacyStepView {
  const LegacyStepView({
    required this.stepPath,
    required this.state,
    this.cooldownUntil,
  });

  /// The engine `nodePath` coordinate (`grid.step.path`) — P2's `step_path`.
  final String stepPath;

  /// The fine `StepState` name (`grid.step.state`): pending / running / ready
  /// / complete / failed / gated — the SAME six-value vocabulary P2's `state`
  /// ENUM carries, which is what makes the axis comparable at all. Null when
  /// the bead carries no fine state yet (a freshly poured step: honest
  /// "nothing has run", never a stamped default).
  final String? state;

  /// The backoff deadline (`grid.step.cooldownUntil`), UTC.
  final DateTime? cooldownUntil;
}

/// The injected legacy step read seam. An empty list means the ledger knows no
/// step beads for that session — which the comparator reports as presence,
/// never swallows.
abstract interface class LegacyStepReader {
  Future<List<LegacyStepView>> stepViews(String sessionId);
}
