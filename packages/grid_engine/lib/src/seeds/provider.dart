import 'package:genesis_tree/genesis_tree.dart';

/// Creates the value a [Provider] OWNS, from ambient tree state.
///
/// Runs exactly once per mount, inside `initState`. Lookups through [TreeContext]
/// here must be dependency-free — use the [ProviderTreeContext.read] verb (the
/// substrate asserts on a build-binding `dependOn` lookup in `initState`). This
/// is how a provider constructs its value from ambient configuration provided
/// by an ancestor.
typedef ProviderCreate<T extends Object> = T Function(TreeContext context);

/// Disposes a value a [Provider] CREATED.
///
/// Never called for an adopted ([Provider.value]) instance — ownership follows
/// construction (`docs/STYLE.md` rule 2): the tree disposes only what the tree
/// created.
typedef ProviderDispose<T extends Object> = void Function(T value);

/// A MOUNTED SEED providing an ambient value of type [T] to its subtree.
///
/// `Provider` sits on the single-child ancestry ([SingleChildStatefulSeed]),
/// so it composes both ways:
///
/// - standalone, wrapping its own `child:`;
/// - as a link in a [Nest] — the multi-provider sugar; there is deliberately
///   no dedicated wrapper type:
///
/// ```dart
/// Nest(
///   children: [
///     Provider<GitOps>(create: (context) => GitOps(...)),
///     Provider<PrOpener>(create: (context) => PrOpener(...)),
///   ],
///   child: SubstationWork(),
/// )
/// ```
///
/// **Lifecycle.** A create-provider runs [ProviderCreate] exactly once per
/// mount, in `initState`; the tree owns the created value and disposes it at
/// unmount through [ProviderDispose]. A [Provider.value] provider ADOPTS an
/// instance held by another owner and never disposes it (`docs/STYLE.md` rule
/// 2). The build is pure: it projects the value over the child as an
/// [InheritedSeed] and does nothing else (`docs/STYLE.md` rule 1).
///
/// **Reconcile.** Same runtimeType + key updates in place: a `.value` update
/// propagates to dependents through [InheritedSeed.updateShouldNotify]; a
/// create-provider never re-runs `create` on update. A type or key change is
/// unmount + remount by substrate rules — the provider's kind (create vs
/// `.value`) is therefore fixed for the life of a mounted branch.
///
/// **Availability.** Descendants bind with [ProviderTreeContext.watch] —
/// nullable always; absence is a designed posture (`docs/STYLE.md` rules 3-4).
/// Mount and unmount are announced to the enclosing [ProviderScope] so
/// availability notification is bidirectional.
final class Provider<T extends Object> extends SingleChildStatefulSeed {
  /// A provider whose value the TREE creates and owns: [create] runs once per
  /// mount and [dispose] (if any) runs at unmount with the created value.
  ///
  /// Never pass a pre-built instance through [create] — that falsely assigns
  /// ownership to the tree (`docs/STYLE.md` rule 2); adopt it with
  /// [Provider.value] instead.
  const Provider({
    required ProviderCreate<T> create,
    ProviderDispose<T>? dispose,
    super.child,
    super.key,
  }) : _create = create,
       _dispose = dispose,
       _value = null;

  /// A provider ADOPTING [value] — an instance held by another owner. The tree
  /// never disposes it; a changed value on reconcile propagates to dependents.
  const Provider.value(T value, {super.child, super.key})
    : _value = value,
      _create = null,
      _dispose = null;

  final ProviderCreate<T>? _create;
  final ProviderDispose<T>? _dispose;
  final T? _value;

  @override
  SingleChildState<Provider<T>> createState() => _ProviderState<T>();
}

/// The AVAILABILITY REGISTRY — one per tree, near the station root.
///
/// It owns ONLY a pending-dependents-by-type map, and exists because the
/// substrate cannot register a dependency on a branch that does not exist:
/// `dependOnInheritedSeedOfExactType` returns null on a miss BEFORE any
/// dependent is added, so an absent [Provider] would otherwise leave no edge
/// to notify when it mounts.
///
/// [ProviderTreeContext.watch] resolves through the normal inherited ancestor
/// walk (nearest provider shadows); on a MISS it registers the calling branch
/// here, keyed by the missed type. A [Provider] announces its mount and
/// unmount to this scope: on mount, pending dependents of the type are
/// notified (`dependencyChanged` through the owner's rebuild scheduling —
/// never re-entering a build) and rebuild — the ones that now resolve the
/// value migrate their registration onto the provider's `InheritedBranch`; on
/// unmount, the provider's live dependents are re-registered as pending and
/// notified, rebuilding into the null posture.
final class ProviderScope extends SingleChildStatefulSeed {
  /// Creates the registry over [child] (null when placed in a [Nest]).
  const ProviderScope({super.child, super.key});

  @override
  SingleChildState<ProviderScope> createState() => _ProviderScopeState();
}

/// Adds nullable provider lookup verbs to [TreeContext] (ADR-0008 D3/D-H —
/// two verbs, one lookup system).
extension ProviderTreeContext on TreeContext {
  /// The build-time BINDING verb: the nearest [T], registering the dependency
  /// edge UNCONDITIONALLY — with the provider's branch on a hit, or with the
  /// enclosing [ProviderScope]'s pending map on a miss.
  ///
  /// Nullable ALWAYS, and deliberately without a throwing variant:
  /// unavailability is a designed posture (`docs/STYLE.md` rule 3). The
  /// notification is bidirectional — a provider mounting rebuilds this branch
  /// from null to value; a provider unmounting rebuilds it from value to null.
  ///
  /// Use [read] for a non-binding snapshot lookup from an effect path.
  T? watch<T extends Object>() {
    final value = dependOnInheritedSeedOfExactType<T>();
    if (value != null) return value;
    // MISS: the walk found no provider, so no branch holds the edge. Park the
    // registration with the availability registry. The registration rides the
    // substrate's own addDependent path (see _RegistryBranch): the registry
    // branch never notifies (its value is scope-lifetime stable), and the
    // dependency edge auto-releases when this branch unmounts.
    final registry = getInheritedSeedOfExactType<_AvailabilityRegistry>();
    if (registry != null) {
      registry._registering = T;
      try {
        dependOnInheritedSeedOfExactType<_AvailabilityRegistry>();
      } finally {
        registry._registering = null;
      }
    }
    return null;
  }

  /// The effect-path SNAPSHOT verb: the nearest [T] without registering any
  /// dependency — neither live nor pending. A later change, mount, or unmount
  /// of the provider does not rebuild this branch.
  T? read<T extends Object>() => getInheritedSeedOfExactType<T>();
}

// --- Provider internals -----------------------------------------------------

final class _ProviderState<T extends Object>
    extends SingleChildState<Provider<T>> {
  /// The tree-created value, null for a `.value` provider. Created exactly
  /// once per mount, in [initState]; never touched by reconcile.
  T? _owned;

  /// The unmount disposal, captured AT CREATION (ownership follows
  /// construction): a created value pairs with the dispose it was authored
  /// with; an adopted value captures nothing and is never tree-disposed.
  void Function()? _disposeOwned;

  @override
  void initState() {
    final create = seed._create;
    if (create == null) return;
    final value = create(context);
    _owned = value;
    final dispose = seed._dispose;
    if (dispose != null) _disposeOwned = () => dispose(value);
  }

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    // Pure projection (docs/STYLE.md rule 1): no creation, no registry
    // mutation, no side effects — the value over the child, nothing else.
    // Reading seed._value (not a cached copy) is what propagates a `.value`
    // update through InheritedSeed.updateShouldNotify.
    final value = seed._value ?? _owned;
    if (value == null) {
      throw StateError(
        'Provider<$T> reconciled from .value into create: — the provider kind '
        'is fixed for the life of a mounted branch (same runtimeType + key '
        'updates in place). Change the type or key to remount instead.',
      );
    }
    return _ProviderInherited<T>(value: value, child: child);
  }

  @override
  void dispose() {
    _disposeOwned?.call();
  }
}

/// The provider's projection over its child: a plain [InheritedSeed] whose
/// branch additionally announces mount/unmount to the availability registry.
final class _ProviderInherited<T extends Object> extends InheritedSeed<T> {
  const _ProviderInherited({required super.value, required super.child});

  @override
  InheritedBranch<T> createBranch() => _ProviderInheritedBranch<T>(this);
}

final class _ProviderInheritedBranch<T extends Object>
    extends InheritedBranch<T> {
  _ProviderInheritedBranch(_ProviderInherited<T> super.seed);

  /// The registry captured at mount — the unmount announcement must not
  /// re-walk a tree that is already coming down.
  _AvailabilityRegistry? _registry;

  /// Live dependents, mirrored through the addDependent/removeDependent
  /// chokepoints (the base class set is a test-only surface).
  final Set<Branch> _live = {};

  @override
  void addDependent(Branch branch) {
    _live.add(branch);
    super.addDependent(branch);
  }

  @override
  void removeDependent(Branch branch) {
    _live.remove(branch);
    super.removeDependent(branch);
  }

  @override
  void mount(Branch? parent, Object? slot) {
    // super.mount reconciles the child subtree first: descendants that watch
    // this type register live against THIS branch (it is mounted before they
    // build); only then are the scope's parked dependents notified.
    super.mount(parent, slot);
    final registry = _registry =
        getInheritedSeedOfExactType<_AvailabilityRegistry>();
    registry?.providerMounted(T);
  }

  @override
  void unmount() {
    // Announce BEFORE the subtree comes down: the live dependents re-register
    // as pending while their branches are still mounted, and the notification
    // rides the owner's scheduling (a dependent that unmounts with this
    // subtree is drained as a no-op; one that survives rebuilds and observes
    // the null posture).
    _registry?.providerUnmounted(T, List.of(_live));
    _live.clear();
    super.unmount();
  }
}

// --- ProviderScope internals ------------------------------------------------

final class _ProviderScopeState extends SingleChildState<ProviderScope> {
  /// The pending-dependents-by-type map — the scope's WHOLE state. Owned by
  /// the state so it survives reconcile; shared with providers and watchers
  /// as a scope-lifetime-stable inherited value (identity-equal across
  /// rebuilds, so InheritedSeed.updateShouldNotify never fires for it).
  final _AvailabilityRegistry _registry = _AvailabilityRegistry();

  @override
  Seed buildWithChild(TreeContext context, Seed child) =>
      _RegistrySeed(value: _registry, child: child);
}

final class _RegistrySeed extends InheritedSeed<_AvailabilityRegistry> {
  const _RegistrySeed({required super.value, required super.child});

  @override
  InheritedBranch<_AvailabilityRegistry> createBranch() =>
      _RegistryBranch(this);
}

/// The registry's branch: the substrate's addDependent path doubles as the
/// pending-registration chokepoint. A watcher that misses depends on THIS
/// branch (see [ProviderTreeContext.watch]); the interception below files it
/// under the missed type, and the substrate's unmount bookkeeping calls
/// [removeDependent], auto-releasing the parked registration.
final class _RegistryBranch extends InheritedBranch<_AvailabilityRegistry> {
  _RegistryBranch(_RegistrySeed super.seed);

  @override
  void addDependent(Branch branch) {
    final type = value._registering;
    if (type != null) value._addPending(type, branch);
    super.addDependent(branch);
  }

  @override
  void removeDependent(Branch branch) {
    value._dropPending(branch);
    super.removeDependent(branch);
  }
}

/// The pending-dependents-by-type map ([ProviderScope]'s only possession).
final class _AvailabilityRegistry {
  final Map<Type, Set<Branch>> _pending = {};

  /// Set by [ProviderTreeContext.watch] around its registry-dependency call so
  /// [_RegistryBranch.addDependent] knows which missed type to file the
  /// dependent under (the capability handle deliberately never exposes its
  /// branch; the substrate's own dependency path is the one place the branch
  /// surfaces).
  Type? _registering;

  void _addPending(Type type, Branch dependent) =>
      (_pending[type] ??= {}).add(dependent);

  void _dropPending(Branch dependent) {
    for (final waiting in _pending.values) {
      waiting.remove(dependent);
    }
  }

  /// A [Provider] of [type] mounted: drain its pending dependents and notify
  /// each through [Branch.dependencyChanged] — mark-needs-rebuild through the
  /// owner, never a re-entered build. A rebuilt dependent that now resolves
  /// the value registers live with the provider's branch (the migration); one
  /// that still misses re-registers pending on its own rebuild.
  void providerMounted(Type type) {
    final waiting = _pending.remove(type);
    if (waiting == null) return;
    for (final dependent in waiting) {
      if (dependent.mounted) dependent.dependencyChanged();
    }
  }

  /// A [Provider] of [type] unmounted: its live [dependents] return to the
  /// pending map and are notified — they rebuild and observe the null posture.
  void providerUnmounted(Type type, Iterable<Branch> dependents) {
    for (final dependent in dependents) {
      if (!dependent.mounted) continue;
      _addPending(type, dependent);
      dependent.dependencyChanged();
    }
  }
}
