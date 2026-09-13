library;

import 'package:beads_dart/beads_dart.dart';

import 'mount_eligibility.dart';
import 'session_bead.dart';
import 'session_disposition.dart';
import 'session_projection.dart';

/// One open, mount-eligible work bead blocked by a terminal linked session.
///
/// [workBeadId] names the stranded work, [blockingSessionId] and [disposition]
/// name the durable blocker, and [deliveryMethod]/[deliveryReference] carry the
/// first stored delivery receipt when the session recorded one.
typedef StrandedWork = ({
  String workBeadId,
  String blockingSessionId,
  String disposition,
  String? deliveryMethod,
  String? deliveryReference,
});

/// Derives the read-only stranded-work diagnostic from current projections.
///
/// This is deliberately downstream of the canonical mount-eligibility verdict:
/// it classifies only an open, eligible work bead blocked by a terminal `done`
/// or `held` session. It performs no write or remote delivery lookup.
StrandedWork? strandedWorkOf({
  required Bead workBead,
  required SessionProjection session,
  required MountEligibilityDecision eligibility,
}) {
  final sessionId = session.sessionId;
  if (workBead.status != BeadStatus.open ||
      eligibility is! MountEligible ||
      !session.isTerminal ||
      sessionId == null ||
      sessionId.trim().isEmpty) {
    return null;
  }

  final disposition = switch (sessionDispositionOf(session)) {
    DoneSession() => 'done',
    HeldSession() => 'held',
    NoSession() || LiveSession() || VoidedSession() || PausedSession() => null,
  };
  if (disposition == null) return null;

  String? deliveryMethod;
  String? deliveryReference;
  final results = session.results.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  for (final result in results) {
    final method = _nonBlank(result.value[ResultKeys.delivery]);
    if (method == null) continue;
    deliveryMethod = method;
    deliveryReference = _nonBlank(result.value['pr_url']);
    break;
  }

  return (
    workBeadId: workBead.id,
    blockingSessionId: sessionId,
    disposition: disposition,
    deliveryMethod: deliveryMethod,
    deliveryReference: deliveryReference,
  );
}

String? _nonBlank(String? value) =>
    value != null && value.trim().isNotEmpty ? value : null;
