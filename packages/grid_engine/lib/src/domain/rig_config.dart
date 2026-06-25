import 'package:freezed_annotation/freezed_annotation.dart';

part 'rig_config.freezed.dart';

/// A rig's configuration — the **config axis** (ADR-0007: config nodes are
/// *ancestors* of work nodes).
///
/// Provided ambiently by `RigScope` via `InheritedSeed<RigConfig>` and read by
/// `Rig`. Distinct from `RuntimeConfig`: this is the static, per-rig shape the
/// work subtree reconciles under, not a runtime-transport handle.
@freezed
abstract class RigConfig with _$RigConfig {
  /// Creates the config for rig [rigId] owning [ownedRigs] (the shared
  /// allow-set the ownership predicate is built from — A32).
  const factory RigConfig({
    /// The rig's id (its issue-id prefix and `metadata.rig` marker).
    required String rigId,

    /// The rig allow-set: the prefixes/markers the_grid owns and may dispatch
    /// against (fail-closed — an empty set owns nothing).
    @Default(<String>{}) Set<String> ownedRigs,
  }) = _RigConfig;
}
