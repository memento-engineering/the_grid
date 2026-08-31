/// Identity hashing for the §5 idem-key grammar and the §1 effect key.
///
/// Both keys follow the same discipline: a deterministic canonical string
/// (kept greppable in `idem_key_text` / `effect_id_text`) hashed to a
/// fixed-width SHA-256 hex column, so no key can overflow or
/// truncate-collide.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// SHA-256 of [canonical], lowercase hex — the stored form of every idem/effect
/// key (CHAR(64)).
String sha256Hex(String canonical) =>
    sha256.convert(utf8.encode(canonical)).toString();

/// Service-stamped values some grammar rows interpolate (`<station>`,
/// `<boot_epoch>`) but that no caller supplies on the record itself (§2.6
/// rule 7). Passed to every key build; most types ignore it.
@immutable
class IdemContext {
  const IdemContext({required this.station, required this.bootEpoch});

  final String station;
  final int bootEpoch;
}

/// The logical-mutation key (§1 `effect_id`): SHA-256 of
/// `<session>:<round>:<step_path>:<step_round>:<kind>:<target_digest>`.
///
/// Keys the mutation, not the attempting process — a respawned incarnation's
/// retry lands on the SAME effect_id and dedupes correctly.
@immutable
class EffectIdentity {
  EffectIdentity.build({
    required String sessionId,
    required int round,
    required String stepPath,
    required int stepRound,
    required String kind,
    required String targetDigest,
  }) : effectIdText =
           '$sessionId:$round:$stepPath:$stepRound:$kind:$targetDigest';

  const EffectIdentity.raw(this.effectIdText);

  /// The canonical effect string — non-unique, greppable
  /// (`proj_effects.effect_id_text`).
  final String effectIdText;

  /// SHA-256 hex of [effectIdText] — the envelope/`proj_effects` join key.
  String get effectId => sha256Hex(effectIdText);

  @override
  bool operator ==(Object other) =>
      other is EffectIdentity && other.effectIdText == effectIdText;

  @override
  int get hashCode => effectIdText.hashCode;
}

/// `target_digest` for [EffectIdentity]: SHA-256[:16] of the canonical target.
///
/// Canonical form: repo, branch, base, publish sha joined by newlines, absent
/// parts as empty strings — newline-joined so no field boundary can be forged
/// by a value containing the separator of the outer `:`-joined effect string.
String effectTargetDigest({
  required String repo,
  required String branch,
  String? base,
  String? publishSha,
}) => sha256Hex(
  [repo, branch, base ?? '', publishSha ?? ''].join('\n'),
).substring(0, 16);
