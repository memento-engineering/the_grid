/// The **lease family** of the_grid's third tree — a held federation lease as an
/// [Allocation] (ADR-0009 D6 / Track E, the deferral coming due in M6).
///
/// ADR-0009 names `lease` alongside `tmux`/`app` as an ASSET-level custom
/// [Allocation] (never an engine-shipped family) — so it lives here, in the
/// shared asset home, over `grid_federation`'s lease client. It is the third
/// per-family default beside [ProcessAllocation] (respawn-or-skip) and
/// [ServiceAllocation] (start-runs): a lease is **adopt-or-reacquire**.
///
/// The lease IS the live effect (the RenderObject-analogue). Before this layer
/// the two consumers (the burn-follower, the compute bounded-use) smeared their
/// grant into an `Expando<_Hold>` keyed by the `CapabilityContext` — the exact
/// ADR-0009 D1 smell (mutable per-mount state jammed into the wrong tree, because
/// a `Capability` must stay a stateless description). The [LeaseAllocation] gives
/// the grant a home (a plain instance field) and, with it, the four lifecycle
/// verbs (D4) the two-tree world could not express:
///
///   `startOrAdopt` — acquire a fresh grant + dispatch the work, OR prove-and-
///                    adopt a still-valid prior grant WITHOUT re-acquiring (D4);
///   `dispose`      — RELEASE the grant (KILL / the floor);
///   `detach`       — LEAVE the grant HELD on the owner + keep the handle so a
///                    later `startOrAdopt` re-adopts it (a daemon-only opt-in);
///   `update`       — declined (replace): a lease is left running on a dependency
///                    change, never churned in place.
///
/// A **daemon** lease (the burn-follower) holds its grant for the mounted
/// lifetime and reports `ready` (a positive terminal that stays live) — it is
/// adopt- and detach-capable. A **job** lease (the compute bounded-use) dispatches
/// a bounded command that runs to completion and reports `complete` (latches) —
/// respawn-or-skip, never adopted/detached. The discriminator is the FORMULA
/// step's [AllocationContext.kind] (already threaded down), exactly as
/// [ProcessAllocation] keys adoptability off `StepKind` (D6).
///
/// **Respecting the sealed `Capability`.** `Capability` is a sealed hierarchy
/// ({[ProcessCapability], [ServiceCapability]}) — an asset can't add a third
/// subtype. A lease effect is an async body over a collaborator (the bus), which
/// is what [ServiceCapability] models; so a lease capability `extends
/// ServiceCapability with `[LeasePlan]. The mixin swaps the default
/// [ServiceAllocation] for a [LeaseAllocation] via `createAllocation` and fences
/// off the run-to-completion `run` path (unreachable by construction).
///
/// **The effect layer holds no writer** (invariant 2): the allocation REPORTS
/// through [AllocationContext.sink]; the Host persists off-build through the one
/// chokepoint. It may freely depend on the bus (D3) — it just never writes.
library;

import 'package:grid_engine/grid_engine.dart';
import 'package:grid_federation/grid_federation.dart';

/// The outcome of a lease [LeasePlan.acquire] (or an adopt resolution): a live
/// binding, or a fail-closed reason (no matching peer / denied capacity). Sealed
/// so a consumer's dispatch is exhaustive (house style).
sealed class LeaseResolution {
  const LeaseResolution();
}

/// A live lease binding — the bus [client] to the owner and the held [grant].
class LeaseBound extends LeaseResolution {
  /// Binds [client] (the bus to the grant's owner) to the held [grant].
  const LeaseBound(this.client, this.grant);

  /// The bus to the lessor peer (the pluggable, kind-agnostic transport seam).
  final StationClient client;

  /// The held grant (carries the fencing token every dispatch/release rides).
  final LeaseGrant grant;
}

/// No lease was possible — fail-closed with a [reason] (no peer satisfies the
/// requirements, or capacity was denied). The allocation reports it as a failure.
class LeaseUnavailable extends LeaseResolution {
  /// Creates an unavailable resolution carrying [reason].
  const LeaseUnavailable(this.reason);

  /// Why no lease could be bound (recorded on the failure).
  final String reason;
}

/// The domain hooks a [LeaseAllocation] drives — the variable parts of "hold a
/// lease + run work on it" (ADR-0009 lease family). Mixed into a
/// [ServiceCapability] (the sealed `Capability` is respected: a lease capability
/// `extends ServiceCapability with LeasePlan`); the mixin swaps in a
/// [LeaseAllocation] and fences off the plain-service `run` path.
///
/// Two consumers use it: the burn-follower (a `StepKind.daemon` — lease a peer,
/// launch a long-lived app, publish its endpoint) and the compute bounded-use (a
/// `StepKind.job` — lease a slot, dispatch a bounded command, complete).
mixin LeasePlan on ServiceCapability {
  /// Resolve the bus + acquire a FRESH grant for [ctx] — the burn-follower
  /// matches a peer by containment then requests a lease; the compute use returns
  /// its fixed client's grant. Returns a [LeaseUnavailable] (fail-closed) when no
  /// grant can be bound. MUST poll [CapabilityContext.cancel] across its own async
  /// gaps (a dispose racing the acquire is unwound by the carrier).
  Future<LeaseResolution> acquire(CapabilityContext ctx);

  /// Dispatch the work on the leased slot ([grant] over [client]) and interpret
  /// the opaque bus result into a [StepOutcome] — an [Ok] (with the payload a
  /// daemon publishes on `ready` / a job records on `complete`), a [Failed], or a
  /// [Gate]. Called once after a successful [acquire]; NOT called on adopt.
  Future<StepOutcome> dispatchOn(
    StationClient client,
    LeaseGrant grant,
    CapabilityContext ctx,
  );

  /// A prior grant this node held, to attempt RE-ADOPTING instead of acquiring
  /// fresh (a detached daemon lease, or a crash survivor) — the lease analogue of
  /// the process adopt fence. Returns null → always acquire fresh. Only consulted
  /// for a daemon; the returned binding is proven still-valid over the bus
  /// (no-adopt-on-faith) before it is reattached.
  ///
  /// Defaults to null — the OFFLINE posture (P1), exactly as the process liveness
  /// seam defaults to `neverLive`. The live arm wires it to the persisted lease
  /// handle (co-wired with the process adopt at the human gate).
  Future<LeaseBound?> adoptable(CapabilityContext ctx) async => null;

  /// Mint the [LeaseAllocation] carrier instead of the default [ServiceAllocation]
  /// — the ADR-0009 D4 `createRenderObject` analogue for a held lease.
  @override
  Allocation createAllocation(AllocationContext ctx) =>
      LeaseAllocation(this, ctx);

  /// A lease capability is ALWAYS driven as a [LeaseAllocation] ([createAllocation]
  /// above), never as a plain [ServiceAllocation] — so the run-to-completion [run]
  /// path is UNREACHABLE by construction. Fenced with a throw (rather than a
  /// silent no-op or a grant-leaking fallback) so any future code that bypasses
  /// `createAllocation` fails loudly instead of double-acquiring a lease.
  @override
  Future<StepOutcome> run(CapabilityContext ctx) => throw StateError(
    'A lease capability is driven as a LeaseAllocation (ADR-0009 D6), never a '
    'ServiceAllocation — run() is unreachable by construction (createAllocation '
    'is overridden). Something bypassed createAllocation.',
  );
}

/// The carrier for a HELD lease (ADR-0009 D6). Holds the bound `client`/`grant`
/// as instance fields (the [Expando] smell dissolved), drives the [plan]'s
/// acquire/dispatch/adopt hooks, and REPORTS through the sink — never writes.
class LeaseAllocation extends Allocation {
  /// Creates the allocation driving [plan] under [context].
  LeaseAllocation(this.plan, super.context);

  /// The pure lease plan describing what to lease and how to run on it.
  final LeasePlan plan;

  StationClient? _client;
  LeaseGrant? _grant;
  bool _adopted = false;
  bool _terminal = false;
  bool _released = false;

  /// The bound grant (for tests / introspection), or null before acquire/adopt.
  LeaseGrant? get grant => _grant;

  /// Whether a still-valid prior grant was reattached instead of freshly acquired
  /// (D4).
  bool get adopted => _adopted;

  /// A daemon lease is adopt-capable + detach-capable; a job lease is
  /// respawn-or-skip (never adopts/detaches — D6). Keyed off the formula step's
  /// kind, threaded down on [AllocationContext.kind].
  @override
  bool get isAdoptable => context.kind == StepKind.daemon;

  @override
  bool get isDetachable => context.kind == StepKind.daemon;

  @override
  Future<void> startOrAdopt() async {
    final ctx = context.capContext;

    // ADOPT a still-valid prior grant (a detached daemon lease or a crash
    // survivor) — reattach WITHOUT re-acquiring or re-dispatching (D4).
    // **No-adopt-on-faith** (D5): the OWNER must confirm the grant is still live
    // AND ours (fencing) over the bus; can't prove → acquire fresh, never adopt
    // blind. The daemon's rendezvous payload persists on the node's cursor from
    // the prior incarnation, so a bare `ready` re-surfaces it (the Host's write is
    // merge-safe — it never clears the recorded result).
    if (isAdoptable) {
      final prior = await plan.adoptable(ctx);
      if (ctx.cancel.isCancelled) {
        state = AllocationState.gone;
        return;
      }
      if (prior != null && await _proveFresh(prior.client, prior.grant)) {
        if (ctx.cancel.isCancelled) {
          // A dispose raced the adopt PROOF: `_proveFresh` just heartbeat-renewed
          // the prior grant's TTL, but `_grant` is not bound yet, so the racing
          // `dispose` released nothing. Release the proven grant here so it isn't
          // orphaned for its full (just-renewed) TTL — the same immediate-release
          // contract the fresh-acquire cancel path honors (invariant 4).
          await _safeRelease(prior.client, prior.grant);
          state = AllocationState.gone;
          return;
        }
        state = AllocationState.adopting;
        _client = prior.client;
        _grant = prior.grant;
        _adopted = true;
        state = AllocationState.ready;
        context.sink(const AllocationReady());
        return;
      }
    }

    // ACQUIRE a fresh grant.
    final resolution = await plan.acquire(ctx);
    if (ctx.cancel.isCancelled) {
      // A dispose raced the acquire: release the just-bound slot now (the carrier
      // saw no grant to release in dispose) and skip the dispatch.
      if (resolution is LeaseBound) {
        await _safeRelease(resolution.client, resolution.grant);
      }
      state = AllocationState.gone;
      return;
    }
    switch (resolution) {
      case LeaseUnavailable(:final reason):
        _reportTerminal(AllocationFailed(reason));
        return;
      case LeaseBound(:final client, :final grant):
        _client = client;
        _grant = grant; // dispose releases this on unmount
        state = AllocationState.live;
    }

    // DISPATCH the work on the leased slot + interpret the outcome.
    final outcome = await plan.dispatchOn(_client!, _grant!, ctx);
    if (ctx.cancel.isCancelled) {
      state = AllocationState.gone;
      return;
    }
    _reportOutcome(outcome);
  }

  /// Maps a dispatch [outcome] to the report the Host persists — a daemon
  /// publishes on `ready` (positive terminal, stays live, does NOT latch); a job
  /// `complete`s (latches). Both positive terminals carry the payload.
  void _reportOutcome(StepOutcome outcome) {
    switch (outcome) {
      case Ok(:final payload):
        if (context.kind == StepKind.daemon) {
          state = AllocationState.ready;
          // Non-latching: a later death (live arm) still reports failed.
          context.sink(AllocationReady(payload));
        } else {
          state = AllocationState.gone;
          _reportTerminal(AllocationCompleted(payload));
        }
      case Failed(:final reason):
        state = AllocationState.gone;
        _reportTerminal(AllocationFailed(reason));
      case Gate(:final reason):
        state = AllocationState.gone;
        _reportTerminal(AllocationGated(reason));
    }
  }

  /// Reports a LATCHING terminal (complete/failed/gated) exactly once — a re-fired
  /// resolution never double-reports (the Host also latches, belt-and-braces). A
  /// daemon `ready` deliberately bypasses this (it does not latch).
  void _reportTerminal(AllocationReport report) {
    if (_terminal) return;
    _terminal = true;
    context.sink(report);
  }

  /// **No-adopt-on-faith** freshness proof (D4/D5): ask the OWNER whether [grant]
  /// is still valid AND ours. A [StationClient.heartbeat] propagates the fencing
  /// token; it SUCCEEDS only for a live grant we still hold — a stale/reissued
  /// token or a reaped lease throws [LeaseInvalidException], and an unreachable
  /// owner throws [FederationException]. Either → false → acquire fresh. This is
  /// the lease analogue of the process pgid-liveness proof.
  Future<bool> _proveFresh(StationClient client, LeaseGrant grant) async {
    try {
      await client.heartbeat(grant);
      return true;
    } on FederationException {
      return false;
    }
  }

  @override
  Future<void> detach() async {
    // A job lease is not detachable — the base throws so a non-detachable effect
    // can never silently leak a held grant (the Host disposes it instead).
    if (!isDetachable) return super.detach();
    // LEAVE the grant HELD on the owner (do NOT release) + keep the handle so a
    // later `startOrAdopt` re-adopts it (D4) — a DISTINCT verb from dispose. The
    // grant stays valid on the owner (its TTL/heartbeat governs reaping); the
    // reconciler persists the handle + resumes the heartbeat at the live arm.
    // _released stays false so a later dispose can still release if adoption is
    // abandoned.
    state = AllocationState.dying;
    state = AllocationState.gone;
  }

  @override
  Future<void> dispose() async {
    state = AllocationState.dying;
    // Cancel the cooperative token FIRST — a racing `startOrAdopt` that has not
    // yet bound a grant bails at its guard (no orphan lease after unmount).
    context.capContext.cancel.cancel();
    final client = _client;
    final grant = _grant;
    // dispose == RELEASE (the floor, D4): free the slot whether we acquired it or
    // reattached a survivor. Once-only + idempotent (a re-reaped lease is fine).
    if (client != null && grant != null && !_released) {
      _released = true;
      await _safeRelease(client, grant);
    }
    state = AllocationState.gone;
  }

  /// Releases [grant] over [client], swallowing a federation error so release
  /// stays idempotent for the holder (an already-reaped/invalid lease is not an
  /// error). Releasing the lease is what triggers the owner to reap whatever the
  /// dispatch launched (the guaranteed teardown crosses the bus).
  Future<void> _safeRelease(StationClient client, LeaseGrant grant) async {
    try {
      await client.release(grant);
    } on FederationException {
      // Already reaped/invalid — release is idempotent for the holder.
    }
  }
}
