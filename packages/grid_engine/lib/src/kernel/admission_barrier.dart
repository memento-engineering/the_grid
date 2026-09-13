/// The worktree-outstanding barrier's OBSERVER — the counting arm under
/// shadow, and the `admission.refused` derivation under the cut.
///
/// The clause itself ([worktreeOutstandingClause]) is pure: it evaluates a
/// finding and, under the observe form, returns eligible regardless. THIS is
/// what the finding is handed to, and it owns the two things a clause must not:
/// the per-boot counter the §W2.5 soak table reads, and the record derivation.
///
/// **Arming.** `cut` false is the observe form: the clause is composed, its
/// predicate runs, would-refuse decisions are COUNTED, eligibility changes for
/// no candidate, and no record is appended at all. `cut` true arms both the
/// refusal and its record. The flip boot is therefore the clause's SECOND
/// execution, not its first.
library;

import 'package:grid_runtime/grid_runtime.dart';

import '../domain/session_head_read.dart';
import '../domain/worktree_outstanding.dart';

/// The per-bead refusal dedupe window, KEPT until the basis revision is proven
/// level-shaped in production (cut-wiring §W2.4 W2-B item 3).
///
/// The ratified key dedupes an idle ineligible bead BY CONSTRUCTION once the
/// revision holds level; this window is the belt beside that brace, and it is
/// what keeps a churning revision from minting a record per candidate per pass
/// and overflowing the bounded append queue.
const Duration kAdmissionRefusalDedupeWindow = Duration(seconds: 30);

/// The §W2.5 soak row the observe form feeds — REPORTED, never gating.
const String kBarrierWouldRefuseCounter = 'barrier_would_refuse';

/// The barrier's observer: counts always, records only under the cut.
final class AdmissionBarrier {
  /// Creates the observer over the station's one [recorder].
  ///
  /// [accounting] is the boot's dual-read bookkeeper — the round summary the
  /// counter rides. Null simply leaves the count unreported.
  AdmissionBarrier({
    required StationTrajectoryRecorder recorder,
    this.cut = false,
    DualReadAccounting? accounting,
    DateTime Function()? clock,
    this.dedupeWindow = kAdmissionRefusalDedupeWindow,
  }) : _recorder = recorder,
       _accounting = accounting,
       _clock = clock ?? DateTime.now;

  final StationTrajectoryRecorder _recorder;
  final DualReadAccounting? _accounting;
  final DateTime Function() _clock;

  /// The barrier's clock, PUBLISHED so both `composeMountEligibility` sites
  /// evaluate the clause's three-tick heartbeat rule against the same instant
  /// the barrier stamps its dedupe window with.
  ///
  /// The offline composition has no clock of its own — without this the clause
  /// there would silently fall back to `DateTime.now`, which is what made the
  /// barrier's two call-site tests refuse through the WEDGED branch instead of
  /// the P6 → P1 join.
  DateTime Function() get clock => _clock;

  /// Whether the station has crossed the cut: the single arming lever for the
  /// refusal AND for its record.
  final bool cut;

  /// How long one bead's refusal on one revision suppresses a repeat append.
  final Duration dedupeWindow;

  final Map<String, ({String? snapshotRev, DateTime at})> _appended =
      <String, ({String? snapshotRev, DateTime at})>{};

  /// Whether the clause runs in its counting form (shadow) rather than armed.
  bool get observeForm => !cut;

  /// Records appended this boot. Diagnostics and tests.
  int get refusalsAppended => _refusalsAppended;
  int _refusalsAppended = 0;

  /// Would-refuse decisions counted this boot (distinct beads).
  int get wouldRefuse => _accounting?.barrierWouldRefuse ?? _wouldRefuse;
  int _wouldRefuse = 0;

  /// Takes one finding from the clause.
  void observe(WorktreeOutstandingFinding finding) {
    if (!finding.refuse) {
      // The bead is clear: forget the suppression so a later refusal on a
      // fresh basis appends again rather than being eaten by the window.
      _appended.remove(_key(finding));
      return;
    }
    _wouldRefuse += 1;
    _accounting?.recordBarrierWouldRefuse(finding.workBeadId);
    if (!cut) return;
    final snapshotRev = finding.snapshotRev;
    // The record does not arm without the bead-scoped basis revision: an
    // unkeyed refusal cannot dedupe, and a non-dedupable refusal per candidate
    // per pass is exactly the append-queue overflow the ratified key exists to
    // prevent.
    if (snapshotRev == null || snapshotRev.isEmpty) return;
    final now = _clock().toUtc();
    final previous = _appended[_key(finding)];
    if (previous != null &&
        previous.snapshotRev == snapshotRev &&
        now.difference(previous.at) <= dedupeWindow) {
      return;
    }
    _appended[_key(finding)] = (snapshotRev: snapshotRev, at: now);
    _refusalsAppended += 1;
    _recorder.admissionRefused(
      workBeadId: finding.workBeadId,
      clause: finding.clause,
      snapshotRev: snapshotRev,
      detail: <String, Object?>{
        if (finding.wedged) 'wedged': true,
        if (finding.outstanding.isNotEmpty) ...<String, Object?>{
          'sessions': <String>[
            for (final row in finding.outstanding) row.sessionId,
          ],
          'worktrees': <String>[
            for (final row in finding.outstanding) row.worktree,
          ],
          'terminal_basis': finding.outstanding.first.basis.wire,
        },
      },
    );
  }

  static String _key(WorktreeOutstandingFinding finding) =>
      '${finding.workBeadId}\u0000${finding.clause}';
}
