/// The append-accounting half of a §9 shadow run.
///
/// A shadow run makes TWO statements, not one: "the fold and the ledger agree
/// on every session compared", and "no append that should be in the log is
/// missing from it". The comparator proves only the first. A queue overflow, a
/// server hiccup, or a latched recorder removes records the comparator then
/// never sees — and their absence reads as agreement. That is why
/// stage1-wiring §3 makes it a rule rather than a caveat: **a round with any
/// dropped append cannot count as a clean round.** The window's integrity
/// comes from counting, not from the queue being durable (§2.5).
///
/// The counters live in the RUNNING station's memory and reach the operator
/// through the `/status` trajectory block (§3). This verb runs in a different
/// process, so the numbers arrive one of two ways: the operator passes them
/// (`--dropped` / `--suppressed`, read off `/status`), or a composing runner
/// injects a [ShadowAccountingSource] that reads its own live harness. With
/// neither, accounting is UNKNOWN — and an unknown-accounting run does not
/// count toward the cut criterion, for exactly the reason an INCOMPLETE read
/// does not: the clean round would be unearned.
library;

import 'package:meta/meta.dart';

/// One round's append accounting, as `/status` reports it.
@immutable
class ShadowRunAccounting {
  const ShadowRunAccounting({
    required this.dropped,
    this.suppressed = 0,
    this.mode,
    this.epoch,
  });

  /// Appends lost to queue overflow, server errors, or a failed reconnect —
  /// §2.5's `dropped` counter, the one §3 names in the disqualification rule.
  final int dropped;

  /// Appends short-circuited to a count after a latch (fenced out / halted /
  /// degraded). These are missing records too: the comparator cannot tell a
  /// suppressed append from a fold that agreed, so they disqualify on the
  /// same grounds as [dropped] rather than on a separate rule.
  final int suppressed;

  /// The harness mode string (`live` / `degraded` / `fenced-out` / `halted`),
  /// carried for the report only — the disqualification reads the counters,
  /// never the label.
  final String? mode;

  /// The claimed boot epoch, for the report's cursor back into the log.
  final int? epoch;

  /// Why this run cannot count, or null when the accounting is clean.
  ///
  /// Stated as a reason string rather than a bool because the report prints
  /// it: an operator reading "does NOT count" must be able to see which
  /// counter said so without opening `/status` again.
  String? get disqualification {
    if (dropped > 0 && suppressed > 0) {
      return '$dropped dropped and $suppressed suppressed append'
          '${suppressed == 1 ? '' : 's'}';
    }
    if (dropped > 0) return '$dropped dropped append${dropped == 1 ? '' : 's'}';
    if (suppressed > 0) {
      return '$suppressed suppressed append${suppressed == 1 ? '' : 's'} '
          '(the recorder was latched)';
    }
    return null;
  }

  /// The report's one-line rendering.
  String get summary =>
      'dropped: $dropped, suppressed: $suppressed'
      '${mode == null ? '' : ', mode: $mode'}'
      '${epoch == null ? '' : ', epoch: $epoch'}';
}

/// The clause printed when no accounting reached the verb at all. Named so
/// the report and the tests cannot drift on the wording.
const String unknownAccountingReason =
    'append accounting NOT SUPPLIED — pass --dropped (and --suppressed) from '
    "the station's /status trajectory block, or compose a "
    'ShadowAccountingSource';

/// Reads one round's accounting FOR a grid home — the seam a composing runner
/// uses to reach its own live harness, mirroring `ShadowCompareFactory`.
/// Returning null means "this home has no accounting to offer", which is the
/// unknown case, never a clean one.
typedef ShadowAccountingSource =
    Future<ShadowRunAccounting?> Function(String gridHome);
