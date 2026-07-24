import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';

import '../diagnostics/diagnosable.dart';
import 'package:beads_dart/beads_dart.dart';

import '../domain/session_projection.dart';
import '../kernel/session_resolver.dart';

/// One unit of work as a persistent tree node (ADR-0007: a Branch IS the work
/// lifecycle — mount = spawn, unmount = kill; progress is the per-node reentrant
/// cursor advancing the inflated circuit subtree).
///
/// Pure config → child: it resolves the bead's work Seed via the ambient
/// [SessionResolver] (the reentrant `SessionScope` subtree root) and returns it.
/// WorkBead does NOT observe any pipeline (derailment-invariant 1) — its [bead]
/// and [session] are injected by `WorkList` (the lone observer). A cursor
/// advance arrives as a NEW WorkBead config (same bead-id key); the subtree root
/// is re-keyed identically, so reconcile threads the new cursor down in place
/// while THIS branch keeps its identity.
class WorkBead extends StatelessSeed with Diagnosable {
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
  void debugFillProperties(DiagnosticsBuilder builder) {
    super.debugFillProperties(builder);
    builder.add(ReferenceProperty('bead', bead.id, kind: ReferenceKind.bead));
    if (session?.sessionId case final sessionId?) {
      builder.add(
        ReferenceProperty('session', sessionId, kind: ReferenceKind.session),
      );
    }
  }

  @override
  Seed build(TreeContext context) {
    final resolver = context
        .dependOnInheritedSeedOfExactType<SessionResolver>();
    assert(
      resolver != null,
      'WorkBead requires an ambient SessionResolver (the kernel/extension '
      'provides one; tests inject a fake)',
    );
    // Mount the work bead as an AMBIENT value (2026-07-02): an effect below
    // reads it with the non-binding lookup instead of having it threaded
    // through every mount. Bead is a freezed value type, so a re-provide with
    // an unchanged bead never notifies dependents.
    return InheritedSeed<Bead>(
      value: bead,
      child: resolver!.sessionFor(bead: bead, session: session),
    );
  }
}
