/// The reentrant resolver (ADR-0008 D4 / M4-P1 §4, Track D).
///
/// Drops in at the `SessionResolver` seam (`sessionFor` is typed `Seed`, so it
/// roots a subtree with no change to `WorkBead`): instead of a single effect
/// leaf, it returns an engine-private `SessionScope` that adopt-or-mints the
/// session and inflates the work bead's root circuit. This is the live work
/// path — the per-node reentrant cursor (D-3) replaced the 3-value `WorkPhase`.
library;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';

import '../domain/session_projection.dart';
import '../kernel/session_resolver.dart';
import '../sdk/circuit.dart';
import 'session_scope.dart';

/// Picks the root [Circuit] for a work [bead] — the bead→circuit policy (P1: all
/// coding work → the `code` circuit; the Burn bead → the `burn` circuit). The
/// composing extension supplies it (Track H); tests inject a fake.
typedef RootCircuitFor = Circuit Function(Bead bead);

/// An [SessionResolver] that roots a reentrant `SessionScope` subtree per work
/// bead (Track D).
class CircuitResolver implements SessionResolver {
  /// Creates the resolver over the [rootCircuitFor] policy.
  const CircuitResolver(this.rootCircuitFor);

  /// The bead→root-circuit policy.
  final RootCircuitFor rootCircuitFor;

  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      SessionScope(
        bead: bead,
        circuit: rootCircuitFor(bead),
        existingSession: session,
        key: ValueKey('${bead.id}:session'),
      );
}
