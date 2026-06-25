import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';

import '../domain/session_projection.dart';
import '../domain/work_phase.dart';
import '../kernel/effect_resolver.dart';

/// One unit of work as a persistent tree node (ADR-0007: a Branch IS the work
/// lifecycle — mount = spawn, unmount = kill, a phase advance = swap the
/// effect).
///
/// Pure config → child: it resolves its current [phase]'s effect Seed via the
/// ambient [EffectResolver] and returns it. WorkBead does NOT observe any
/// pipeline (derailment-invariant 1) — its [bead] and [phase] are injected by
/// `WorkList` (the lone observer). A phase advance arrives as a NEW WorkBead
/// config (same bead-id key) and swaps the effect child while THIS branch
/// keeps its identity.
class WorkBead extends StatelessSeed {
  /// Creates a work node for [bead] in [phase] with its linked [session]. Key it
  /// `ValueKey(bead.id)` at the `WorkList` level so reconcile keeps the branch
  /// across snapshot ticks.
  const WorkBead({
    required this.bead,
    required this.phase,
    this.session,
    super.key,
  });

  /// The work bead (from the read-only work source).
  final Bead bead;

  /// The live phase, derived by `phaseOf` (the JOIN of bead + session cursor).
  final WorkPhase phase;

  /// The bead's linked session projection (null until a session exists);
  /// injected so the effect can write its cursor pull-free (A39).
  final SessionProjection? session;

  @override
  Seed build(TreeContext context) {
    final resolver = context.dependOnInheritedSeedOfExactType<EffectResolver>();
    assert(
      resolver != null,
      'WorkBead requires an ambient EffectResolver (the kernel/extension '
      'provides one; tests inject a fake)',
    );
    return resolver!.effectFor(bead: bead, phase: phase, session: session);
  }
}
