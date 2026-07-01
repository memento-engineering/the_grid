import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';

import '../domain/session_projection.dart';
import '../kernel/session_resolver.dart';

/// One unit of work as a persistent tree node (ADR-0007: a Branch IS the work
/// lifecycle — mount = spawn, unmount = kill; progress is the per-node reentrant
/// cursor advancing the inflated formula subtree).
///
/// Pure config → child: it resolves the bead's work Seed via the ambient
/// [SessionResolver] (the reentrant `SessionScope` subtree root) and returns it.
/// WorkBead does NOT observe any pipeline (derailment-invariant 1) — its [bead]
/// and [session] are injected by `WorkList` (the lone observer). A cursor
/// advance arrives as a NEW WorkBead config (same bead-id key); the subtree root
/// is re-keyed identically, so reconcile threads the new cursor down in place
/// while THIS branch keeps its identity.
class WorkBead extends StatelessSeed {
  /// Creates a work node for [bead] with its linked [session]. Key it
  /// `ValueKey(bead.id)` at the `WorkList` level so reconcile keeps the branch
  /// across snapshot ticks.
  const WorkBead({required this.bead, this.session, super.key});

  /// The work bead (from the read-only work source).
  final Bead bead;

  /// The bead's linked session projection (null until a session exists);
  /// injected so the subtree can write its cursor pull-free (A39).
  final SessionProjection? session;

  @override
  Seed build(TreeContext context) {
    final resolver = context.dependOnInheritedSeedOfExactType<SessionResolver>();
    assert(
      resolver != null,
      'WorkBead requires an ambient SessionResolver (the kernel/extension '
      'provides one; tests inject a fake)',
    );
    return resolver!.sessionFor(bead: bead, session: session);
  }
}
