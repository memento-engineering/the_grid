/// The bead-scoped eligibility BASIS revision (cut-wiring §W2.4 W2-B item 3).
///
/// The ratified `admission.refused` idempotency key is
/// `refused:<bead>:<clause>:<snapshotRev>` and it is ratified BECAUSE it is
/// level-shaped: the record re-fires exactly when the evaluated basis actually
/// changed, so a bead refused → restored → refused again re-latches (new
/// revision ⇒ new key) while an idle ineligible bead dedupes by construction
/// (same revision ⇒ same key).
///
/// **No such revision existed.** The P1 mirror's publish counter
/// (`TrajectoryHeadSnapshot.version`, "bumped on every published change") is
/// NOT it and is deliberately not used here: it churns on every fold apply, so
/// it would mint a fresh non-dedupable record per candidate per pass and
/// overflow the append queue, while missing a changed bd-side basis whose
/// mirror did not move. This file builds the real thing — a MONOTONE,
/// BEAD-SCOPED revision of the inputs that decide ONE bead's eligibility,
/// which changes when those inputs change and not on every pass.
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:meta/meta.dart';

import 'mount_attempt.dart';
import 'session_projection.dart';
import 'worktree_outstanding.dart';

/// The approval stamp the mount gate reads — an eligibility input, so a
/// re-approval moves the basis.
const String kEligibilityApprovalKey = 'grid.approved_at';

/// The eligibility BASIS of one candidate: every join-side input a mount
/// decision for that bead reads, canonicalized.
///
/// Station-wide inputs (the admission halt, the substation drive list, the
/// resident flag) are deliberately absent: they are not bead-scoped, and a
/// station-wide change that refuses every bead is not a per-bead basis change.
@immutable
final class EligibilityBasis {
  const EligibilityBasis(this.canonical);

  /// Builds the canonical basis text for [bead] out of the joined inputs.
  factory EligibilityBasis.of({
    required Bead bead,
    required bool ready,
    MountAttemptRecord? attempt,
    Iterable<SessionProjection> linkedSessions = const <SessionProjection>[],
    WorktreeOutstandingFinding? worktree,
  }) {
    final sessions = <String>[
      for (final session in linkedSessions)
        '${session.sessionId ?? ''}/${session.isTerminal}/'
            '${session.pauseState.name}/${session.workBeadId}',
    ]..sort();
    final outstanding = <String>[
      for (final row in worktree?.outstanding ?? const <OutstandingWorktree>[])
        '${row.sessionId}/${row.worktree}/${row.basis.wire}',
    ]..sort();
    return EligibilityBasis(
      <String>[
        bead.id,
        bead.issueType.wire,
        '${bead.isClosed}',
        '${bead.metadata[kEligibilityApprovalKey] ?? ''}',
        'ready=$ready',
        'attempts=${attempt?.count ?? 0}',
        'wedged=${worktree?.wedged ?? false}',
        'sessions=${sessions.join(',')}',
        'outstanding=${outstanding.join(',')}',
      ].join('\u0000'),
    );
  }

  /// The canonical text — hashed into the exposed revision, never served raw.
  final String canonical;

  /// A stable 64-bit FNV-1a digest of [canonical], lower-case hex.
  ///
  /// A digest rather than the text because the revision rides a
  /// `VARCHAR(64)` column and an idem-key grammar hole; a non-cryptographic
  /// hash is right here because the value is an equality token for THIS
  /// station's own basis, never a trust boundary.
  String get digest {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    const mask = 0xFFFFFFFFFFFFFFFF;
    for (final unit in canonical.codeUnits) {
      hash = (hash ^ unit) & mask;
      hash = (hash * prime) & mask;
    }
    // Rendered as two unsigned 32-bit halves: Dart's ints are SIGNED, so the
    // 64-bit accumulator's top bit would otherwise print a leading '-' and put
    // a second separator inside a value the revision already delimits with
    // one.
    final high = (hash >> 32) & 0xFFFFFFFF;
    final low = hash & 0xFFFFFFFF;
    return '${high.toRadixString(16).padLeft(8, '0')}'
        '${low.toRadixString(16).padLeft(8, '0')}';
  }
}

/// The monotone per-bead revision ledger — one per join producer.
///
/// LEVEL-SHAPED by construction: [revise] returns the SAME string for as long
/// as the basis digest is unchanged, and a strictly greater ordinal the first
/// pass after it changes. Monotone per bead: the ordinal never decreases, so
/// two refusals of the same bead can never collide on an old key.
final class EligibilityBasisRevisions {
  final Map<String, ({String digest, int ordinal})> _byBeadId =
      <String, ({String digest, int ordinal})>{};

  /// The revision for [workBeadId] at [basis].
  String revise(String workBeadId, EligibilityBasis basis) {
    final digest = basis.digest;
    final current = _byBeadId[workBeadId];
    if (current != null && current.digest == digest) {
      return _render(current.ordinal, digest);
    }
    final ordinal = (current?.ordinal ?? 0) + 1;
    _byBeadId[workBeadId] = (digest: digest, ordinal: ordinal);
    return _render(ordinal, digest);
  }

  /// The current revision for [workBeadId], or null when none was computed.
  String? operator [](String workBeadId) {
    final current = _byBeadId[workBeadId];
    return current == null ? null : _render(current.ordinal, current.digest);
  }

  /// Drops every bead outside [live] — the join's own candidate set, so the
  /// ledger cannot outgrow the graph it tracks.
  void retain(Set<String> live) =>
      _byBeadId.removeWhere((beadId, _) => !live.contains(beadId));

  /// How many beads carry a revision. Diagnostics only.
  int get length => _byBeadId.length;

  static String _render(int ordinal, String digest) => '$ordinal-$digest';
}
