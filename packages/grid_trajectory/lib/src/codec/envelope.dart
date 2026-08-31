/// The §1 envelope: one immutable row image of the `trajectory` table.
///
/// Column names in JSON are the §4 DDL names verbatim. Per-type required-key
/// invariants live in the sealed record classes (§2.6 rule 6); this type
/// enforces only the cross-cutting CHECKs that are per-row, not per-type
/// (`ck_prov`, `ck_unknown`, `ck_seat`).
library;

import 'package:meta/meta.dart';

/// `family` ENUM — fold dispatch.
enum TrajectoryFamily {
  attempt,
  admission,
  verification,
  effect,
  step;

  static TrajectoryFamily fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

/// `provenance` ENUM (§8 Q18).
enum TrajectoryProvenance {
  observed,
  inferred,
  reconstructed;

  static TrajectoryProvenance fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

/// `outcome` ENUM — the decision-faithful terminal vocabulary, verbatim.
enum TerminalOutcome {
  succeeded,
  failed,
  cancelled,
  lost,
  escalated,
  settled,
  unknown;

  static TerminalOutcome fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

/// One `trajectory` row. `seq` and `epoch_seq` are service-assigned inside the
/// append transaction — absent (null) until the row has landed.
@immutable
class TrajectoryEnvelope {
  TrajectoryEnvelope({
    required this.recordId,
    required this.idemKey,
    required this.idemKeyText,
    required this.family,
    required this.recordType,
    required this.occurredAt,
    required this.recordedAt,
    required this.station,
    required this.authorityId,
    required this.bootEpoch,
    required this.source,
    required this.payload,
    this.typeVersion = 1,
    this.seq,
    this.epochSeq,
    this.seat,
    this.fencingToken,
    this.provenance = TrajectoryProvenance.observed,
    this.provenanceBasis,
    this.resolvesRecordId,
    this.workBeadId,
    this.sessionId,
    this.round,
    this.stepRound,
    this.stepPath,
    this.incarnation,
    this.attemptId,
    this.mountAttemptId,
    this.grantId,
    this.effectId,
    this.gateId,
    this.worktree,
    this.branch,
    this.commitSha,
    this.receipt,
    this.expiresAt,
    this.outcome,
    this.unknownReason,
  }) {
    // Mirrors of the §4 cross-cutting CHECKs, refused at construction so a
    // bad row never reaches the wire.
    if (provenance != TrajectoryProvenance.observed &&
        provenanceBasis == null) {
      throw ArgumentError(
        'ck_prov: provenance ${provenance.wire} requires provenance_basis',
      );
    }
    if (outcome == TerminalOutcome.unknown && unknownReason == null) {
      throw ArgumentError(
        'ck_unknown: outcome unknown requires unknown_reason',
      );
    }
    if (workBeadId != null && seat == null) {
      throw ArgumentError(
        'ck_seat: work_bead_id set requires seat (service-derived from the '
        'store prefix — §2.6 rule 7)',
      );
    }
  }

  factory TrajectoryEnvelope.fromJson(Map<String, Object?> json) {
    DateTime? date(String key) {
      final raw = json[key];
      return raw == null ? null : DateTime.parse(raw as String);
    }

    return TrajectoryEnvelope(
      seq: json['seq'] as int?,
      epochSeq: json['epoch_seq'] as int?,
      recordId: json['record_id'] as String,
      idemKey: json['idem_key'] as String,
      idemKeyText: json['idem_key_text'] as String,
      family: TrajectoryFamily.fromWire(json['family'] as String),
      recordType: json['record_type'] as String,
      typeVersion: json['type_version'] as int? ?? 1,
      occurredAt: date('occurred_at')!,
      recordedAt: date('recorded_at')!,
      station: json['station'] as String,
      seat: json['seat'] as String?,
      authorityId: json['authority_id'] as String,
      bootEpoch: json['boot_epoch'] as int,
      fencingToken: json['fencing_token'] as int?,
      provenance: json['provenance'] == null
          ? TrajectoryProvenance.observed
          : TrajectoryProvenance.fromWire(json['provenance'] as String),
      provenanceBasis: json['provenance_basis'] as String?,
      source: json['source'] as String,
      resolvesRecordId: json['resolves_record_id'] as String?,
      workBeadId: json['work_bead_id'] as String?,
      sessionId: json['session_id'] as String?,
      round: json['round'] as int?,
      stepRound: json['step_round'] as int?,
      stepPath: json['step_path'] as String?,
      incarnation: json['incarnation'] as int?,
      attemptId: json['attempt_id'] as String?,
      mountAttemptId: json['mount_attempt_id'] as String?,
      grantId: json['grant_id'] as String?,
      effectId: json['effect_id'] as String?,
      gateId: json['gate_id'] as String?,
      worktree: json['worktree'] as String?,
      branch: json['branch'] as String?,
      commitSha: json['commit_sha'] as String?,
      receipt: json['receipt'] as String?,
      expiresAt: date('expires_at'),
      outcome: json['outcome'] == null
          ? null
          : TerminalOutcome.fromWire(json['outcome'] as String),
      unknownReason: json['unknown_reason'] as String?,
      payload: (json['payload'] as Map).cast<String, Object?>(),
    );
  }

  final int? seq;
  final int? epochSeq;
  final String recordId;
  final String idemKey;
  final String idemKeyText;
  final TrajectoryFamily family;
  final String recordType;
  final int typeVersion;
  final DateTime occurredAt;
  final DateTime recordedAt;
  final String station;
  final String? seat;
  final String authorityId;
  final int bootEpoch;
  final int? fencingToken;
  final TrajectoryProvenance provenance;
  final String? provenanceBasis;
  final String source;
  final String? resolvesRecordId;
  final String? workBeadId;
  final String? sessionId;
  final int? round;
  final int? stepRound;
  final String? stepPath;
  final int? incarnation;
  final String? attemptId;
  final String? mountAttemptId;
  final String? grantId;
  final String? effectId;
  final String? gateId;
  final String? worktree;
  final String? branch;
  final String? commitSha;
  final String? receipt;
  final DateTime? expiresAt;
  final TerminalOutcome? outcome;
  final String? unknownReason;
  final Map<String, Object?> payload;

  /// The row as JSON, nulls omitted, DDL column names.
  Map<String, Object?> toJson() => {
    if (seq != null) 'seq': seq,
    if (epochSeq != null) 'epoch_seq': epochSeq,
    'record_id': recordId,
    'idem_key': idemKey,
    'idem_key_text': idemKeyText,
    'family': family.wire,
    'record_type': recordType,
    'type_version': typeVersion,
    'occurred_at': occurredAt.toIso8601String(),
    'recorded_at': recordedAt.toIso8601String(),
    'station': station,
    if (seat != null) 'seat': seat,
    'authority_id': authorityId,
    'boot_epoch': bootEpoch,
    if (fencingToken != null) 'fencing_token': fencingToken,
    'provenance': provenance.wire,
    if (provenanceBasis != null) 'provenance_basis': provenanceBasis,
    'source': source,
    if (resolvesRecordId != null) 'resolves_record_id': resolvesRecordId,
    if (workBeadId != null) 'work_bead_id': workBeadId,
    if (sessionId != null) 'session_id': sessionId,
    if (round != null) 'round': round,
    if (stepRound != null) 'step_round': stepRound,
    if (stepPath != null) 'step_path': stepPath,
    if (incarnation != null) 'incarnation': incarnation,
    if (attemptId != null) 'attempt_id': attemptId,
    if (mountAttemptId != null) 'mount_attempt_id': mountAttemptId,
    if (grantId != null) 'grant_id': grantId,
    if (effectId != null) 'effect_id': effectId,
    if (gateId != null) 'gate_id': gateId,
    if (worktree != null) 'worktree': worktree,
    if (branch != null) 'branch': branch,
    if (commitSha != null) 'commit_sha': commitSha,
    if (receipt != null) 'receipt': receipt,
    if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
    if (outcome != null) 'outcome': outcome!.wire,
    if (unknownReason != null) 'unknown_reason': unknownReason,
    'payload': payload,
  };
}
