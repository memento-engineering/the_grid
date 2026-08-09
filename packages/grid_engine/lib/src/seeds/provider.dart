import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:meta/meta.dart';

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
/// created. Runs only after the provider's subtree is FULLY unmounted, so a
/// descendant's teardown read (`context.read` from `State.dispose` — the
/// substrate-endorsed last get-lookup) observes a live value, and a [Nest]
/// chain disposes inner-before-outer (reverse creation order — a value built
/// from an ancestor-provided one goes down before its dependency).
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
/// unmount through [ProviderDispose] — AFTER the subtree is fully down, so
/// teardown reads see a live value and a [Nest] chain disposes
/// inner-before-outer. A [Provider.value] provider ADOPTS an
/// instance held by another owner and never disposes it (`docs/STYLE.md` rule
/// 2). The build is pure: it projects the value over the child as an
/// [InheritedSeed] and does nothing else (`docs/STYLE.md` rule 1).
///
/// **Failed mount.** A `create` that throws fails the whole mount, and the
/// unwind strands no owned value: every provider whose own mount encloses the
/// failure — the failing provider itself, each earlier link of the same
/// [Nest] chain, every provider ancestor — disposes what it already created,
/// in reverse creation order, before the error rethrows (see
/// [_ProviderBranch] for the mechanism and its exact extent).
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
/// availability notification is bidirectional; delivery is deferred past the
/// announcing flush pass (see [ProviderScope] for the scheduling contract).
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

  @override
  SingleChildStatefulBranch createBranch() => _ProviderBranch(this);
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
/// unmount to this scope, and the scope notifies the affected dependents
/// (`dependencyChanged` through the owner's rebuild scheduling — never
/// re-entering a build).
///
/// **Scheduling.** A provider mounts and unmounts MID-FLUSH (inside some
/// ancestor's rebuild), and the substrate forbids re-dirtying a branch that
/// was already built in the in-progress flush pass
/// (`TreeOwner.scheduleRebuildFor`). Notification is therefore DEFERRED: the
/// registry queues the affected dependents and delivers `dependencyChanged`
/// from a microtask, after the current pass has drained. The marked branches
/// ride the owner's next flush (the kernel schedules one off the
/// `onNeedsFlush` edge; tests pump the microtask queue and flush again).
///
/// **What each direction observably does on THIS substrate.** genesis_tree
/// has no reparenting, so a live dependent of a provider is always a
/// DESCENDANT of it and unmounts with it. Consequently: the mount-side drain
/// of pending dependents is the load-bearing direction (a parked watcher
/// rebuilds and re-resolves — still null when the new provider is not its
/// ancestor, the value when a remount placed it under one); the unmount-side
/// ping is contract-mandated bidirectional notification whose recipients are,
/// today, always torn down with the provider before delivery — a surviving
/// dependent (should reparenting ever exist) would rebuild, observe the null
/// posture, and re-register pending through its own watch miss. Value
/// transitions across a provider boundary otherwise ride unmount + remount of
/// the dependent subtree by ordinary substrate reconcile rules.
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
  /// notification is bidirectional — mount and unmount announcements both
  /// reach the registered dependents — and DEFERRED: delivery is a microtask
  /// after the flush pass the provider (un)mounted in, so the rebuild lands
  /// in the owner's next flush (see [ProviderScope] for scheduling and for
  /// what each direction observably does on this substrate).
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
    final registry = getInheritedSeedOfExactType<AvailabilityRegistry>();
    if (registry != null) {
      registry._registering = T;
      try {
        dependOnInheritedSeedOfExactType<AvailabilityRegistry>();
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
  ///
  /// NOT run by this state's own `dispose` — `StatefulBranch.unmount` runs
  /// `State.dispose` BEFORE the subtree comes down, which would hand every
  /// descendant's teardown read an already-disposed value and invert the
  /// inner-before-outer order across a [Nest] chain. It is threaded into the
  /// built [_ProviderInherited] and runs in [_ProviderInheritedBranch.unmount]
  /// AFTER the subtree is fully unmounted.
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

  /// The failed-mount unwind (see [_ProviderBranch]): disposes the owned
  /// value NOW, exactly once, because this provider's mount failed and the
  /// substrate will never attach — and therefore never unmount — the branch
  /// that would have carried the disposal. Nulling both fields keeps the
  /// disposal single-shot and unarms the closure threaded into any
  /// already-built [_ProviderInherited].
  void _disposeOwnedForFailedMount() {
    final dispose = _disposeOwned;
    _disposeOwned = null;
    _owned = null;
    dispose?.call();
  }

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    // Pure projection (docs/STYLE.md rule 1): no creation, no registry
    // mutation, no side effects — the value over the child, nothing else.
    // Reading seed._value (not a cached copy) is what propagates a `.value`
    // update through InheritedSeed.updateShouldNotify.
    //
    // The kind guard is BIDIRECTIONAL: the provider's kind (create vs .value)
    // is fixed for the life of a mounted branch, and a flip in either
    // direction is incoherent — value-to-create has no owned value to
    // project; create-to-value would silently shadow the owned value with the
    // adopted one while the unmount disposal stays armed with the original.
    final adopted = seed._value;
    if (adopted != null && _owned != null) {
      throw StateError(
        'Provider<$T> reconciled from create: into .value — the provider kind '
        'is fixed for the life of a mounted branch (same runtimeType + key '
        'updates in place). Change the type or key to remount instead.',
      );
    }
    final value = adopted ?? _owned;
    if (value == null) {
      throw StateError(
        'Provider<$T> reconciled from .value into create: — the provider kind '
        'is fixed for the life of a mounted branch (same runtimeType + key '
        'updates in place). Change the type or key to remount instead.',
      );
    }
    return _ProviderInherited<T>(
      value: value,
      child: child,
      disposeOwned: _disposeOwned,
    );
  }
}

/// The provider's branch: a [SingleChildStatefulBranch] that additionally
/// carries the FAILED-MOUNT unwind.
///
/// **Substrate unwind semantics** (genesis_tree, investigated at 0.2.0): when
/// a mount throws mid-reconcile, `updateChild` propagates the error BEFORE the
/// caller's child-slot assignment, at every level of the failing spine. Every
/// branch mounted within the failed reconcile call is left orphaned — still
/// `mounted == true`, unreachable from the root, its `unmount()` never to be
/// called. For providers that means the disposal site
/// ([_ProviderInheritedBranch.unmount]) is unreachable: an owned value created
/// before the failure would be STRANDED, never disposed.
///
/// The unwind therefore rides the exception's own propagation: the mount-time
/// [performRebuild] frame of a provider encloses its `create` call AND the
/// mount of its entire subtree, so catching there and disposing the owned
/// value covers (a) the failing provider itself (its `create` threw — nothing
/// created, nothing to do), (b) every earlier link of the same [Nest] chain
/// (chain links nest, so each earlier "sibling" is a structural ancestor of
/// the failure — they dispose innermost-first, reverse creation order, the old
/// ProviderScope contract), and (c) any provider ancestor elsewhere up the
/// spine. The error then rethrows unchanged.
///
/// Known extent: a provider subtree that fully mounted under a NON-provider
/// multi-child container before a LATER sibling of that container failed is
/// orphaned by an assignment skipped ABOVE any provider frame; no provider
/// code is on that stack, so its disposal is out of this seam's reach. The
/// multi-provider composition surface is [Nest] (which nests, and is fully
/// covered), so that shape has no production author today.
final class _ProviderBranch extends SingleChildStatefulBranch {
  _ProviderBranch(Provider<Object> super.seed);

  /// True until the first (mount-pass) build completes or fails. Rebuilds of
  /// an ATTACHED provider must not run the unwind: a failure there leaves the
  /// branch attached, its value live, and its normal unmount disposal intact.
  bool _mountBuild = true;

  @override
  void performRebuild() {
    if (!_mountBuild) return super.performRebuild();
    _mountBuild = false;
    try {
      super.performRebuild();
    } catch (error, stackTrace) {
      (state as _ProviderState)._disposeOwnedForFailedMount();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

/// The provider's projection over its child: a plain [InheritedSeed] whose
/// branch additionally announces mount/unmount to the availability registry.
final class _ProviderInherited<T extends Object> extends InheritedSeed<T> {
  const _ProviderInherited({
    required super.value,
    required super.child,
    required this.disposeOwned,
  });

  /// The owned value's disposal (null for an adopted `.value` instance),
  /// stable for the life of the mount — created once in `initState` alongside
  /// the value it pairs with. Run by the branch at unmount, AFTER the subtree
  /// is fully down (see [_ProviderInheritedBranch.unmount]).
  final void Function()? disposeOwned;

  @override
  InheritedBranch<T> createBranch() => _ProviderInheritedBranch<T>(this);
}

final class _ProviderInheritedBranch<T extends Object>
    extends InheritedBranch<T> {
  _ProviderInheritedBranch(_ProviderInherited<T> super.seed);

  /// The registry captured at mount — the unmount announcement must not
  /// re-walk a tree that is already coming down.
  AvailabilityRegistry? _registry;

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
        getInheritedSeedOfExactType<AvailabilityRegistry>();
    registry?.providerMounted(T);
  }

  @override
  void unmount() {
    // Announce BEFORE the subtree comes down. Delivery is deferred (see
    // AvailabilityRegistry): by the time the notification microtask runs, a
    // dependent that unmounted with this subtree — on this no-reparent
    // substrate, all of them — is skipped by its own `mounted` guard; a
    // surviving one would rebuild, observe the null posture, and re-register
    // pending through its own watch miss.
    _registry?.providerUnmounted(T, List.of(_live));
    _live.clear();
    final disposeOwned = (seed as _ProviderInherited<T>).disposeOwned;
    super.unmount();
    // Dispose an OWNED value only now, with the subtree fully down: a
    // descendant's teardown read (`context.read` from `State.dispose`) saw a
    // live value, and across a Nest chain this branch's subtree contained
    // every inner provider — disposal therefore runs inner-before-outer,
    // reverse creation order (an inner value built from an outer one goes
    // down before its dependency).
    disposeOwned?.call();
  }
}

// --- ProviderScope internals ------------------------------------------------

final class _ProviderScopeState extends SingleChildState<ProviderScope> {
  /// The pending-dependents-by-type map — the scope's WHOLE state. Owned by
  /// the state so it survives reconcile; shared with providers and watchers
  /// as a scope-lifetime-stable inherited value (identity-equal across
  /// rebuilds, so InheritedSeed.updateShouldNotify never fires for it).
  final AvailabilityRegistry _registry = AvailabilityRegistry();

  @override
  Seed buildWithChild(TreeContext context, Seed child) =>
      _RegistrySeed(value: _registry, child: child);
}

final class _RegistrySeed extends InheritedSeed<AvailabilityRegistry> {
  const _RegistrySeed({required super.value, required super.child});

  @override
  InheritedBranch<AvailabilityRegistry> createBranch() =>
      _RegistryBranch(this);
}

/// The registry's branch: the substrate's addDependent path doubles as the
/// pending-registration chokepoint. A watcher that misses depends on THIS
/// branch (see [ProviderTreeContext.watch]); the interception below files it
/// under the missed type, and the substrate's unmount bookkeeping calls
/// [removeDependent], auto-releasing the parked registration.
final class _RegistryBranch extends InheritedBranch<AvailabilityRegistry> {
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
///
/// Public ONLY as a test seam (`@visibleForTesting`): the unmount-side
/// notification has no observable end-to-end effect on this no-reparent
/// substrate (every live dependent of an unmounting provider is a descendant
/// and unmounts with it), so its receive-side contract behavior is pinned by
/// direct unit tests against this class, and the provider branch's transmit
/// side through [debugNotifying]. Production code composes [ProviderScope]
/// and never names the registry.
///
/// **Release semantics.** A parked registration (per branch, per type,
/// idempotent) is released by exactly three events:
///
/// 1. **Drain** — a [Provider] mount of the type removes the WHOLE bucket
///    ([providerMounted]); recipients that still miss re-file through their
///    own rebuild's watch miss.
/// 2. **Delivery consumes** — any notification delivered to a branch first
///    drops ALL of that branch's parked registrations (every type): the
///    rebuild the ping triggers re-files the branch's CURRENT interests, so a
///    type the branch stopped watching does not linger past its next
///    notification.
/// 3. **Unmount** — the substrate's own dependency release
///    ([_RegistryBranch.removeDependent], riding the registry-branch edge the
///    watch miss registered) drops the branch from every bucket.
///
/// A mounted branch that rebuilds WITHOUT issuing any watch keeps its prior
/// registrations until the next of these events — there is no substrate hook
/// on a hook-free rebuild — which is bounded (at most one entry per type, all
/// for live branches) and self-corrects at the branch's next ping or unmount.
@visibleForTesting
final class AvailabilityRegistry {
  final Map<Type, Set<Branch>> _pending = {};

  /// Branches queued for a deferred [Branch.dependencyChanged] — provider
  /// (un)mount announcements land here mid-flush and are delivered from a
  /// microtask, after the in-progress pass has drained. Delivering
  /// synchronously would re-dirty a branch the current flush pass already
  /// built, which the substrate forbids (`TreeOwner.scheduleRebuildFor`).
  final Set<Branch> _notifying = {};
  bool _deliveryScheduled = false;

  /// Set by [ProviderTreeContext.watch] around its registry-dependency call so
  /// [_RegistryBranch.addDependent] knows which missed type to file the
  /// dependent under (the capability handle deliberately never exposes its
  /// branch; the substrate's own dependency path is the one place the branch
  /// surfaces).
  Type? _registering;

  void _addPending(Type type, Branch dependent) =>
      (_pending[type] ??= {}).add(dependent);

  /// Drops [dependent] from EVERY bucket — the shared release chokepoint for
  /// rules 2 (delivery consumes) and 3 (unmount, via
  /// [_RegistryBranch.removeDependent]) of the release semantics.
  void _dropPending(Branch dependent) {
    for (final waiting in _pending.values) {
      waiting.remove(dependent);
    }
  }

  /// Queues [dependents] for notification and schedules one delivery
  /// microtask. Delivery guards on [Branch.mounted]: a branch that unmounted
  /// between announcement and delivery is skipped, not retained.
  void _notifyDeferred(Iterable<Branch> dependents) {
    _notifying.addAll(dependents);
    if (_deliveryScheduled || _notifying.isEmpty) return;
    _deliveryScheduled = true;
    scheduleMicrotask(() {
      // Reset FIRST — fail-closed: even if a dependent throws below, a later
      // announcement schedules a fresh delivery instead of wedging behind a
      // stuck flag.
      _deliveryScheduled = false;
      final batch = List.of(_notifying);
      _notifying.clear();
      Object? firstError;
      StackTrace? firstStackTrace;
      for (final dependent in batch) {
        // Delivery CONSUMES the recipient's parked registrations (all types,
        // release semantics rule 2): the rebuild this ping triggers re-files
        // the branch's current interests through its own watch misses, so a
        // stale interest cannot outlive the branch's next notification.
        _dropPending(dependent);
        if (!dependent.mounted) continue;
        try {
          dependent.dependencyChanged();
        } catch (error, stackTrace) {
          // Exception-isolate the batch: one throwing dependent must not
          // swallow the remaining notifications. The first failure is
          // rethrown after the batch drains, so it still reaches the zone's
          // error handler — isolated, never silenced.
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }
      if (firstError != null) {
        Error.throwWithStackTrace(firstError, firstStackTrace!);
      }
    });
  }

  /// A [Provider] of [type] mounted: drain its pending dependents and notify
  /// each through [Branch.dependencyChanged] — mark-needs-rebuild through the
  /// owner, DEFERRED past the flush pass the mount happened in. A notified
  /// dependent rebuilds in the owner's next flush; one that now resolves the
  /// value registers live with the provider's branch (the migration), one
  /// that still misses re-registers pending on its own rebuild.
  void providerMounted(Type type) {
    final waiting = _pending.remove(type);
    if (waiting == null) return;
    _notifyDeferred(waiting);
  }

  /// A [Provider] of [type] unmounted: its live [dependents] are notified
  /// (deferred, like the mount side). They are deliberately NOT re-parked
  /// here: a dependent that unmounts with the provider's subtree — on this
  /// no-reparent substrate, all of them — must not be retained by the
  /// registry, and a surviving one re-registers pending through its own
  /// rebuild's watch miss, which rides the [_RegistryBranch] dependency path
  /// that IS released on unmount.
  void providerUnmounted(Type type, Iterable<Branch> dependents) {
    _notifyDeferred(dependents);
  }

  /// The pending dependents parked under [type] — a read-only test probe
  /// (leak regressions assert no unmounted branch is ever retained here).
  @visibleForTesting
  Set<Branch> debugPendingOf(Type type) =>
      Set.unmodifiable(_pending[type] ?? const <Branch>{});

  /// The branches queued for the next delivery microtask — a read-only test
  /// probe. Pins the TRANSMIT side of the unmount announcement end-to-end:
  /// the provider branch's mirrored live-dependent set has no other
  /// observable outlet on this no-reparent substrate (every recipient is
  /// down before delivery), so tests read the queue between the announcing
  /// flush and the delivery microtask.
  @visibleForTesting
  Set<Branch> get debugNotifying => Set.unmodifiable(_notifying);
}
