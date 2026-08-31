/// The §2.6 codec registry: `(record_type, type_version)` → `fromJson`.
///
/// Rules 2–3, load-bearing: old decoders are KEPT FOREVER (the log is never
/// migrated — a breaking change ADDS a `(type, version+1)` entry, it never
/// replaces one), and an unknown pair — or a row a known decoder refuses —
/// decodes to [OpaqueRecord] so replay never throws.
library;

import 'envelope.dart';
import 'trajectory_record.dart';

typedef RecordDecoder =
    TrajectoryRecord Function(
      TrajectoryEnvelope envelope,
      Map<String, Object?> payload,
    );

abstract final class TrajectoryCodec {
  /// Every decoder that has ever shipped, keyed `(record_type, type_version)`.
  static const Map<(String, int), RecordDecoder> decoders = {
    // Family 1 — attempt lifecycle.
    ('attempt.session.started', 1): AttemptSessionStarted.fromJson,
    ('attempt.process.started', 1): AttemptProcessStarted.fromJson,
    ('attempt.process.exited', 1): AttemptProcessExited.fromJson,
    ('attempt.liveness.lost', 1): AttemptLivenessTransition.fromJson,
    ('attempt.liveness.regained', 1): AttemptLivenessTransition.fromJson,
    ('attempt.lease.acquired', 1): AttemptLeaseTransition.fromJson,
    ('attempt.lease.released', 1): AttemptLeaseTransition.fromJson,
    ('attempt.lease.swept', 1): AttemptLeaseTransition.fromJson,
    ('attempt.adopt.proved', 1): AttemptAdoptProved.fromJson,
    ('attempt.terminal', 1): AttemptTerminal.fromJson,
    ('attempt.round.retired', 1): AttemptRoundRetired.fromJson,
    ('attempt.rework_declined', 1): AttemptReworkDeclined.fromJson,
    ('attempt.mint.outcome', 1): AttemptMintOutcome.fromJson,
    ('attempt.note', 1): AttemptNote.fromJson,
    ('worktree.provisioned', 1): WorktreeProvisioned.fromJson,
    ('worktree.reaped', 1): WorktreeReaped.fromJson,
    ('worktree.held', 1): WorktreeHeld.fromJson,
    // Family 2 — admission grants and authority.
    ('admission.grant.issued', 1): AdmissionGrantIssued.fromJson,
    ('admission.grant.consumed', 1): AdmissionGrantConsumed.fromJson,
    ('admission.grant.expired', 1): AdmissionGrantClosed.fromJson,
    ('admission.grant.released', 1): AdmissionGrantClosed.fromJson,
    ('admission.refused', 1): AdmissionRefused.fromJson,
    ('admission.restored', 1): AdmissionRestored.fromJson,
    ('admission.drive.approved', 1): AdmissionDriveApproved.fromJson,
    ('authority.epoch.advanced', 1): AuthorityEpochTransition.fromJson,
    ('authority.epoch.closed', 1): AuthorityEpochTransition.fromJson,
    ('federation.lease.granted', 1): FederationLeaseTransition.fromJson,
    ('federation.lease.reaped', 1): FederationLeaseTransition.fromJson,
    ('federation.lease.expired', 1): FederationLeaseTransition.fromJson,
    // Family 3 — verification bindings.
    ('verify.scope.pinned', 1): VerifyScopePinned.fromJson,
    ('verify.verdict.recorded', 1): VerifyVerdictRecorded.fromJson,
    ('verify.verdict.recovered', 1): VerifyVerdictRecovered.fromJson,
    ('verify.gating.rc', 1): VerifyGatingRc.fromJson,
    ('verify.completion.fence', 1): VerifyCompletionFence.fromJson,
    ('verify.route.verdict', 1): VerifyRouteVerdict.fromJson,
    // Two live versions, the rule-2 shape in the flesh: the I1 gen_ai rename
    // (§15) minted v2 and the v1 decoder stays FOREVER — same class, old key
    // names — so pre-alignment rows never migrate and never go opaque.
    ('verify.usage.telemetry', 1): VerifyUsageTelemetry.fromJsonV1,
    ('verify.usage.telemetry', 2): VerifyUsageTelemetry.fromJson,
    ('verify.ci.concluded', 1): VerifyCiConcluded.fromJson,
    // Family 4 — effect intent / acknowledgement.
    ('effect.intent', 1): EffectIntent.fromJson,
    ('effect.ack', 1): EffectAck.fromJson,
    ('effect.unarmed', 1): EffectUnarmed.fromJson,
    ('effect.observation.claimed', 1): EffectObservationClaimed.fromJson,
    ('effect.command.received', 1): EffectCommandReceived.fromJson,
    ('effect.command.refused', 1): EffectCommandRefused.fromJson,
    ('effect.ci.rework.commanded', 1): EffectCiReworkCommanded.fromJson,
    // Family 5 — step and molecule transitions.
    ('molecule.poured', 1): MoleculePoured.fromJson,
    ('step.transition', 1): StepTransition.fromJson,
    ('step.superseded', 1): StepSuperseded.fromJson,
    ('gate.opened', 1): GateOpened.fromJson,
    ('gate.regated', 1): GateRegated.fromJson,
    ('gate.closed', 1): GateClosed.fromJson,
  };

  /// Decodes [envelope]'s payload to its typed record.
  ///
  /// Never throws: an unregistered pair, or a row whose registered decoder
  /// refuses it, returns an [OpaqueRecord] (with [OpaqueRecord.decodeFailure]
  /// set in the second case) for the fold to count in `proj_meta.skipped`.
  static TrajectoryRecord decode(TrajectoryEnvelope envelope) {
    final decoder = decoders[(envelope.recordType, envelope.typeVersion)];
    if (decoder == null) {
      return OpaqueRecord(
        recordType: envelope.recordType,
        typeVersion: envelope.typeVersion,
        family: envelope.family,
        rawPayload: envelope.payload,
      );
    }
    try {
      return decoder(envelope, envelope.payload);
    } on Object catch (error) {
      return OpaqueRecord(
        recordType: envelope.recordType,
        typeVersion: envelope.typeVersion,
        family: envelope.family,
        rawPayload: envelope.payload,
        decodeFailure: '$error',
      );
    }
  }
}
