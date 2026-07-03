import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';

import '../domain/session_projection.dart';

/// The opinion-light seam between the kernel and the running work subtree
/// (ADR-0007 Decision 5 / ADR-0008 D4): given a work [bead] (and its linked
/// session), return the Seed that *runs* it.
///
/// The kernel knows nothing of agents, processes, git, or PRs — the compiled
/// extension contributes the concrete subtree root (the reentrant
/// [CircuitResolver] returns a `SessionScope` that inflates the bead's root
/// circuit); tests inject a fake. This indirection is what keeps the engine
/// landing/VCS/provider-opinion-free.
///
/// The returned Seed MUST be keyed off `bead.id` (the [CircuitResolver] keys it
/// `'<bead.id>:session'`) so that across snapshot ticks keyed reconcile keeps
/// the bead's running subtree while config (the linked session cursor) flows
/// down in place.
abstract class SessionResolver {
  /// Builds the work Seed for [bead]. [session] is the bead's linked session
  /// projection (null when no session exists yet — the resolver's subtree then
  /// mints one); its [SessionProjection.cursor] threads the per-node reentrant
  /// cursor down pull-free (A39), never re-querying the store. See the class doc
  /// for the required key shape.
  Seed sessionFor({required Bead bead, SessionProjection? session});
}
