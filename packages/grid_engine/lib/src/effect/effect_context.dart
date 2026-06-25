import 'package:grid_runtime/grid_runtime.dart';

/// The injected bundle an [EffectSeed] resolves from the tree in ONE inherited
/// lookup (ADR-0007 / M4-P0-BUILD-ORDER Track C).
///
/// The kernel (Track E/F) provides exactly one of these via an
/// `InheritedSeed<EffectContext>` above the work tree, so every mounted effect
/// reaches its process transport ([provider]), its single bd write chokepoint
/// ([writer]), and the owned state rig ([stateRig]) through a single
/// `dependOnInheritedSeedOfExactType` — never three separate lookups, and never
/// a re-query of the store (A39).
///
/// Immutable and value-light: the bundle is a handle to three long-lived
/// collaborators, not state. An effect captures it once in
/// `didChangeDependencies` and uses the captured reference across async gaps so
/// it never touches the `TreeContext` (which throws post-unmount) for I/O.
class EffectContext {
  /// Bundles the process transport [provider], the bd write [writer], and the
  /// owned [stateRig] the effects mint and advance session beads in.
  const EffectContext({
    required this.provider,
    required this.writer,
    required this.stateRig,
  });

  /// The process transport — spawn (`start`), kill (`stop`), and the broadcast
  /// lifecycle [RuntimeProvider.events] stream the effect subscribes to.
  final RuntimeProvider provider;

  /// The single bd write chokepoint — the ONLY path session/lifecycle beads are
  /// written through (`createSession` / `update` / `close`), bd-only,
  /// `--actor grid-controller`, fail-closed on ownership (ADR-0006 Decision 2).
  final GridBeadWriter writer;

  /// The_grid's OWNED state rig (`tgdog`) — the partition session beads are
  /// minted into, kept separate from the read-only work source (A37).
  final String stateRig;
}
