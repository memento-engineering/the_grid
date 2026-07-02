/// The **lease family** — a held lease as a first-class core [Capability]
/// (ADR-0009 D6 / the "leasing is core" decision, 2026-07-01).
///
/// Leasing is a CORE scheduling primitive, not an asset concern: even a single
/// station leases time to its substations. So the lease family lives in the
/// engine beside [ProcessAllocation] (respawn-or-skip) and [ServiceAllocation]
/// (start-runs) — a lease is **adopt-or-reacquire**. It is **transport-agnostic**:
/// the engine names no bus. A [LeaseCapability] carries an OPAQUE handle type `H`
/// (the concrete lease binding — e.g. a federation `(StationClient, LeaseGrant)`,
/// or a local `LeaseManager` slot) and wires the acquire/dispatch/heartbeat/
/// release through its own hooks; `grid_federation` + the assets supply the
/// transport, the engine never sees it.
///
/// The four lifecycle verbs (D4), with the handle held as a [LeaseAllocation]
/// instance field:
///   `startOrAdopt` — acquire a fresh handle + dispatch, OR prove-and-adopt a
///                    still-valid prior handle WITHOUT re-acquiring (no-adopt-on-
///                    faith: [LeaseCapability.proveFresh] must hold);
///   `dispose`      — RELEASE the handle (kill / the floor);
///   `detach`       — LEAVE the handle held + keep it for re-adoption (daemon-only);
///   `update`       — declined (a lease is left running on a dependency change).
///
/// A **daemon** lease (`context.kind == StepKind.daemon`) reports `ready` (a
/// positive terminal that STAYS LIVE, publishing its rendezvous payload) and is
/// adopt/detach-capable; a **job** lease reports `complete` (latches) —
/// respawn-or-skip. The discriminator is the formula step's kind, threaded down
/// on [AllocationContext.kind], exactly as [ProcessAllocation].
///
/// **The effect layer holds no writer** (invariant 2): it REPORTS through the
/// sink; the Host persists off-build. It may freely hold its transport (D3).
library;

import 'package:genesis_tree/genesis_tree.dart';

import 'allocation.dart';
import 'capability.dart';
import 'formula.dart';

/// The outcome of a [LeaseCapability.acquire] (or an adopt resolution): a live
/// binding carrying the opaque handle [H], or a fail-closed reason. Sealed so a
/// consumer's dispatch is exhaustive (house style).
sealed class LeaseResolution<H> {
  const LeaseResolution();
}

/// A live lease binding carrying the concrete [handle] (opaque to the engine —
/// the capability's own binding: a bus client + grant, a local slot, …).
class LeaseBound<H> extends LeaseResolution<H> {
  /// Binds the opaque [handle] the capability acquired.
  const LeaseBound(this.handle);

  /// The concrete lease handle (the capability heartbeats/releases it).
  final H handle;
}

/// No lease was possible — fail-closed with a [reason] (no peer satisfies the
/// requirements, capacity denied). The allocation reports it as a failure.
class LeaseUnavailable<H> extends LeaseResolution<H> {
  /// Creates an unavailable resolution carrying [reason].
  const LeaseUnavailable(this.reason);

  /// Why no lease could be bound (recorded on the failure).
  final String reason;
}

/// A [Capability] backed by a HELD lease (ADR-0009 lease family). The author
/// implements the transport-specific hooks over an opaque handle [H] and NEVER a
/// `Seed`; the [LeaseAllocation] carrier owns the tree lifecycle. The engine
/// names no bus — a federation lease supplies `H = (StationClient, LeaseGrant)`
/// and wires the bus inside these hooks; a local single-station lease supplies a
/// local slot handle.
abstract class LeaseCapability<H> extends Capability {
  /// Const-constructible (capabilities are stateless description).
  const LeaseCapability();

  /// Resolve + acquire a FRESH lease, returning its opaque handle (or a
  /// [LeaseUnavailable] when none can be bound — fail-closed). MUST poll
  /// [StepArgs.cancel] across its own async gaps; a dispose racing the
  /// acquire is unwound by the carrier (it calls [release] on the bound handle).
  Future<LeaseResolution<H>> acquire(TreeContext context, StepArgs args);

  /// Dispatch the work on the leased slot [handle] and interpret the result into
  /// a [StepOutcome] — [Ok] (with the payload a daemon publishes on `ready` / a
  /// job records on `complete`), [Failed], or [Gate]. Called once after a
  /// successful [acquire]; NOT called on adopt.
  Future<StepOutcome> dispatchOn(H handle, TreeContext context, StepArgs args);

  /// **No-adopt-on-faith** freshness proof (D4/D5): confirm [handle] is still a
  /// live lease we hold (the owner-side check — e.g. a fenced heartbeat). Only
  /// consulted for a daemon with an [adoptable] prior handle. Defaults to `false`
  /// (never adopt blind); a real daemon lease overrides it. MUST be idempotent /
  /// side-effect-free beyond the liveness check.
  Future<bool> proveFresh(H handle, TreeContext context, StepArgs args) async =>
      false;

  /// Release [handle], freeing the leased slot. **MUST be idempotent** and must
  /// not throw for an already-reaped/invalid lease (the carrier calls it on
  /// dispose + on a cancel-race, possibly more than once across incarnations).
  Future<void> release(H handle);

  /// A prior handle this node held, to attempt RE-ADOPTING instead of acquiring
  /// fresh (a detached daemon lease / crash survivor). Returns null → always
  /// acquire fresh (the offline P1 posture; the live arm wires it to the
  /// persisted handle). Only consulted for a daemon, and only reattached when
  /// [proveFresh] holds.
  Future<LeaseBound<H>?> adoptable(TreeContext context, StepArgs args) async =>
      null;

  @override
  Allocation createAllocation(AllocationContext ctx) => LeaseAllocation<H>(this, ctx);
}

/// The carrier for a HELD lease (ADR-0009 D6). Holds the bound handle as an
/// instance field, drives the [capability]'s hooks, and REPORTS through the sink
/// — never writes. Transport-agnostic: it never names a bus.
class LeaseAllocation<H> extends Allocation {
  /// Creates the allocation driving [capability] under [context].
  LeaseAllocation(this.capability, super.context);

  /// The pure lease capability describing what to lease and how to run on it.
  final LeaseCapability<H> capability;

  H? _handle;
  bool _hasHandle = false;
  bool _adopted = false;
  bool _terminal = false;
  bool _released = false;

  /// The bound handle (for tests / introspection), or null before acquire/adopt.
  H? get handle => _handle;

  /// Whether a still-valid prior handle was reattached instead of freshly
  /// acquired (D4).
  bool get adopted => _adopted;

  /// A daemon lease is adopt-capable + detach-capable; a job lease is
  /// respawn-or-skip (never adopts/detaches — D6). Keyed off the formula step's
  /// kind on [AllocationContext.kind].
  @override
  bool get isAdoptable => context.kind == StepKind.daemon;

  @override
  bool get isDetachable => context.kind == StepKind.daemon;

  @override
  Future<void> startOrAdopt() async {
    final tree = context.treeContext;
    final args = context.args;

    // ADOPT a still-valid prior handle (a detached daemon lease or a crash
    // survivor) — reattach WITHOUT re-acquiring or re-dispatching (D4).
    // **No-adopt-on-faith** (D5): [proveFresh] must confirm it live+ours; can't
    // prove → acquire fresh. The daemon's rendezvous payload persists on the
    // node's cursor from the prior incarnation, so a bare `ready` re-surfaces it.
    if (isAdoptable) {
      final prior = await capability.adoptable(tree, args);
      if (args.cancel.isCancelled) {
        state = AllocationState.gone;
        return;
      }
      if (prior != null &&
          await capability.proveFresh(prior.handle, tree, args)) {
        if (args.cancel.isCancelled) {
          // A dispose raced the adopt proof: release the proven handle so it
          // isn't orphaned (the immediate-release contract the fresh path honors).
          await _release(prior.handle);
          state = AllocationState.gone;
          return;
        }
        state = AllocationState.adopting;
        _bind(prior.handle);
        _adopted = true;
        state = AllocationState.ready;
        context.sink(const AllocationReady());
        return;
      }
    }

    // ACQUIRE a fresh lease. A THROWING hook routes to supervision as a
    // failure — never an unhandled zone error (the per-work fail-closed
    // posture, ADR-0008 Decision 10).
    final LeaseResolution<H> resolution;
    try {
      resolution = await capability.acquire(tree, args);
    } on Object catch (e) {
      state = AllocationState.gone;
      if (!args.cancel.isCancelled) {
        _reportTerminal(AllocationFailed('acquire threw: $e'));
      }
      return;
    }
    if (args.cancel.isCancelled) {
      // A dispose raced the acquire: release the just-bound slot + skip dispatch.
      if (resolution is LeaseBound<H>) await _release(resolution.handle);
      state = AllocationState.gone;
      return;
    }
    switch (resolution) {
      case LeaseUnavailable<H>(:final reason):
        _reportTerminal(AllocationFailed(reason));
        return;
      case LeaseBound<H>(:final handle):
        _bind(handle); // dispose releases this on unmount
        state = AllocationState.live;
    }

    // DISPATCH the work on the leased slot + interpret the outcome. A throwing
    // dispatch fails the work (supervision); the held lease is still released
    // by dispose on unmount.
    final StepOutcome outcome;
    try {
      outcome = await capability.dispatchOn(_handle as H, tree, args);
    } on Object catch (e) {
      state = AllocationState.gone;
      if (!args.cancel.isCancelled) {
        _reportTerminal(AllocationFailed('dispatch threw: $e'));
      }
      return;
    }
    if (args.cancel.isCancelled) {
      state = AllocationState.gone;
      return;
    }
    _reportOutcome(outcome);
  }

  void _bind(H handle) {
    _handle = handle;
    _hasHandle = true;
  }

  /// Maps a dispatch [outcome] to the report the Host persists — a daemon
  /// publishes on `ready` (positive terminal, stays live, does NOT latch); a job
  /// `complete`s (latches). Both positive terminals carry the payload.
  void _reportOutcome(StepOutcome outcome) {
    switch (outcome) {
      case Ok(:final payload):
        if (context.kind == StepKind.daemon) {
          state = AllocationState.ready;
          context.sink(AllocationReady(payload)); // non-latching (OQ-5)
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

  /// Reports a LATCHING terminal (complete/failed/gated) exactly once. A daemon
  /// `ready` deliberately bypasses this (it does not latch).
  void _reportTerminal(AllocationReport report) {
    if (_terminal) return;
    _terminal = true;
    context.sink(report);
  }

  @override
  Future<void> detach() async {
    // A job lease is not detachable — the base throws so a non-detachable effect
    // can never silently leak a held lease (the Host disposes it instead).
    if (!isDetachable) return super.detach();
    // LEAVE the lease HELD + keep the handle for a later re-adopt (D4) — a
    // DISTINCT verb from dispose (never releases). _released stays false so a
    // later dispose can still release if adoption is abandoned.
    state = AllocationState.dying;
    state = AllocationState.gone;
  }

  @override
  Future<void> dispose() async {
    state = AllocationState.dying;
    // Cancel FIRST — a racing startOrAdopt that hasn't bound a handle bails at
    // its guard (no orphan lease after unmount).
    context.args.cancel.cancel();
    // dispose == RELEASE (the floor, D4): free the slot whether we acquired it or
    // reattached a survivor. Once-only + idempotent.
    if (_hasHandle && !_released) {
      _released = true;
      await _release(_handle as H);
    }
    state = AllocationState.gone;
  }

  /// Releases [handle] through the capability, swallowing any error so release
  /// stays idempotent for the holder (the capability's [LeaseCapability.release]
  /// is contracted idempotent; this is belt-and-braces so a throw never breaks
  /// unmount).
  Future<void> _release(H handle) async {
    try {
      await capability.release(handle);
    } on Object {
      // Already reaped/invalid/unreachable — release is idempotent for the holder.
    }
  }
}
