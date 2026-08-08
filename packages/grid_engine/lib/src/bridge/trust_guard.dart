import 'package:beads_dart/beads_dart.dart';

import '../sdk/capability.dart';

/// Metadata keys for the intake-authored origin trust stamp.
///
/// These ordinary metadata fields are forgeable by a holder of bead-write
/// authority. Signed stamps and signature verification are outside this guard.
abstract final class OriginTrustKeys {
  /// Opaque producer scheme, such as the intake extension's own scheme name.
  static const scheme = 'grid.origin.scheme';

  /// Opaque actor identifier within [scheme].
  static const actor = 'grid.origin.actor';

  /// A [TrustLevel.name] resolved by intake before the bead reaches the mount.
  static const level = 'grid.origin.trust';
}

/// Narrows [candidates] to origins admitted by [floor], synchronously and
/// without I/O. An entirely absent origin stamp is backward-compatible and
/// admitted. A present but unprovable stamp is refused fail-closed and LOUD.
Set<String> applyTrustGuard({
  required Set<String> candidates,
  required Map<String, Bead> beadsById,
  required TrustFloor floor,
  required bool trustConfigured,
  void Function(String message)? onUnresolved,
}) {
  if (candidates.isEmpty) return candidates;
  final admitted = <String>{};
  for (final id in candidates) {
    final bead = beadsById[id];
    if (bead == null) {
      onUnresolved?.call(
        'grid: trust stamp for $id cannot be checked because the candidate '
        'bead is unobserved — excluding $id from ready (fail-closed).',
      );
      continue;
    }
    final metadata = bead.metadata;
    final stamped =
        metadata.containsKey(OriginTrustKeys.scheme) ||
        metadata.containsKey(OriginTrustKeys.actor) ||
        metadata.containsKey(OriginTrustKeys.level);
    if (!stamped) {
      admitted.add(id);
      continue;
    }
    final scheme = metadata[OriginTrustKeys.scheme];
    final actor = metadata[OriginTrustKeys.actor];
    final encodedLevel = metadata[OriginTrustKeys.level];
    final level = encodedLevel is String ? _trustLevelOf(encodedLevel) : null;
    if (scheme is! String ||
        scheme.isEmpty ||
        actor is! String ||
        actor.isEmpty ||
        level == null) {
      onUnresolved?.call(
        'grid: $id has a malformed origin trust stamp — excluding $id from '
        'ready (fail-closed).',
      );
      continue;
    }
    if (!trustConfigured) {
      onUnresolved?.call(
        'grid: $id has an origin trust stamp but this substation has no trust '
        'resolver — excluding $id from ready (fail-closed).',
      );
      continue;
    }
    if (level.index < floor.level.index) {
      onUnresolved?.call(
        'grid: $id origin trust ${level.name} is below floor '
        '${floor.level.name} — excluding $id from ready.',
      );
      continue;
    }
    admitted.add(id);
  }
  return admitted;
}

TrustLevel? _trustLevelOf(String encoded) {
  for (final level in TrustLevel.values) {
    if (level.name == encoded) return level;
  }
  return null;
}
