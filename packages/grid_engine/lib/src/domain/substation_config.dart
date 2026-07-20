import 'package:freezed_annotation/freezed_annotation.dart';

part 'substation_config.freezed.dart';

/// A substation's configuration — the **config axis** (ADR-0007: config nodes are
/// *ancestors* of work nodes).
///
/// Provided ambiently by `SubstationScope` via `InheritedSeed<SubstationConfig>` and read by
/// `Substation`. Distinct from `RuntimeConfig`: this is the static, per-substation shape the
/// work subtree reconciles under, not a runtime-transport handle.
@freezed
abstract class SubstationConfig with _$SubstationConfig {
  /// Creates the config for substation [substationId] owning [ownedSubstations] (the shared
  /// allow-set the ownership predicate is built from — A32).
  const factory SubstationConfig({
    /// The rig's id (its issue-id prefix and `metadata.rig` marker).
    required String substationId,

    /// The substation allow-set: the prefixes/markers the_grid owns and may dispatch
    /// against (fail-closed — an empty set owns nothing).
    @Default(<String>{}) Set<String> ownedSubstations,

    /// The blessed-bead **drive-list** (ADR-0006): when non-empty, ONLY these
    /// bead ids mount a work node + spawn an agent (`WorkList` enforces it at the
    /// mount boundary). Empty = no per-bead restriction (dev / dry-run observes
    /// all owned dispatchable work); a LIVE (non-resident) run refuses an
    /// empty drive-list upstream (`SubstationWork`/`StationWork` gating), so
    /// this gate is active whenever armed.
    /// Orthogonal to [ownedSubstations]: ownership says *whose* beads, the
    /// drive-list says *which specific* beads Nico has blessed for this arm.
    @Default(<String>{}) Set<String> driveList,

    /// Resident all-ready arming (RS-3/D-R4): when true, `WorkList` narrows
    /// the mount boundary to the DRIVEABLE-WORK types (`task`/`bug`/
    /// `feature`/`chore`) ON TOP of the existing A41 `isCore` allow-list — a
    /// resident station's ready frontier must never auto-mount an
    /// organizational bead (epic/milestone/decision) just because it surfaced
    /// ready. Orthogonal to [driveList]: under resident arming the drive-list
    /// is always empty (`validateArming` refuses a `--bead`) — this narrows
    /// WHICH TYPES of the all-ready frontier are driveable, not which ids.
    @Default(false) bool resident,

    /// The concurrency governor's PER-SUBSTATION override (tg-42f,
    /// declare-and-check): the most `WorkList` will mount concurrently for
    /// THIS substation. Null (the default) falls back to the station-wide
    /// default (`StationServices.maxConcurrentWork`). Either way the
    /// station-wide TOTAL across every substation is a hard ceiling this
    /// override cannot raise — it only narrows within it. A bead beyond the
    /// budget stays ready-unmounted (no session, no spawn, no cost) and mounts
    /// on the next reconcile once a slot frees.
    int? maxConcurrentWork,
  }) = _SubstationConfig;
}
