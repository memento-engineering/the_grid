import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';

import '../domain/work_phase.dart';

/// The opinion-light seam between the kernel and capabilities (ADR-0007
/// Decision 5): given a work [bead] and its live [WorkPhase], return the Seed
/// that *effects* that phase.
///
/// The kernel knows nothing of agents, processes, git, or PRs — an extension
/// (Track E/F `DefaultExtension`) contributes the concrete effect Seeds; tests
/// inject a fake. This indirection is what keeps the engine landing/VCS/
/// provider-opinion-free.
///
/// The returned Seed MUST be keyed `'<bead.id>.<phase.capId>'` so a phase
/// advance swaps the effect child — unmount the old capability (its `dispose`
/// kills), mount the new (its `initState` spawns) — while the owning `WorkBead`
/// branch keeps its identity.
abstract class EffectResolver {
  /// Builds the effect Seed for [bead] in [phase]. See the class doc for the
  /// required key shape.
  Seed effectFor({required Bead bead, required WorkPhase phase});
}
