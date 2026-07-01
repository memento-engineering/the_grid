/// The_grid's THIRD tree — the **Allocation** (ADR-0009, Accepted 2026-07-01).
///
/// `genesis_tree` stops at `Seed` (config) → `Branch` (element/lifecycle) **on
/// purpose** — to let a consumer define its own third tree (the RenderObject
/// analogue), the way `genesis_typesetting` defines typeset boxes and lenny's
/// perception defines observation nodes. the_grid's third tree is the
/// **Allocation Tree**: an [Allocation] is a persistent, stateful, **addressable**
/// managed object holding a *live effect* — a spawned coding agent, a held
/// federation lease, a tmux session, a running app.
///
/// Before this layer, those effects were smeared into the `Branch`:
/// `initState → unawaited(_run())`, a frozen `_capCtx`, a hand-managed
/// `CancelToken`. The Allocation gives them a home, and with it the four
/// lifecycle verbs (D4) that the two-tree world could not express:
///
///   `startOrAdopt` — spawn fresh OR prove-and-adopt a survivor at the address;
///   `update`       — mutate in place (or decline → the Host replaces);
///   `dispose`      — KILL (the default / floor);
///   `detach`       — LEAVE RUNNING + persist the handle (a per-type opt-in).
///
/// **The effect layer never holds a writer** (invariant 2): an Allocation
/// *reports* transitions to its host through an [AllocationSink]; the Host
/// persists them off-build through the one bd chokepoint. This is layering, not a
/// sandbox wall (D3) — an Allocation may freely depend on the tree; it just may
/// never write.
library;

import 'dart:async';

import 'package:grid_runtime/grid_runtime.dart';

import 'capability.dart';
import 'formula.dart';

/// The lifecycle state of an [Allocation] (ADR-0009 D5:
/// `starting → live → [ready] → dying → gone`, plus `adopting`).
///
/// A pure observation of the effect's phase — distinct from the persisted
/// [StepState] cursor the Host writes (the Host maps reports → cursor states).
/// The Allocation owns this machine; the sink carries the transitions the Host
/// cares about.
enum AllocationState {
  /// `startOrAdopt` in flight, spawning a fresh effect.
  starting,

  /// `startOrAdopt` in flight, proving-and-reattaching a survivor (D4).
  adopting,

  /// The effect is live (pre positive-terminal).
  live,

  /// A daemon signalled it is up — a positive terminal that does NOT retire the
  /// effect (it stays live and may later die).
  ready,

  /// `dispose`/`detach` in flight.
  dying,

  /// Terminal: killed, completed, or detached-and-forgotten by this node.
  gone,
}

/// An [Allocation]'s stable, addressable identity — the node path
/// `<sessionId>/<nodePath>` (ADR-0009 D2: light, *with* identity).
///
/// Reconstructible because the tree rebuilds deterministically from the work
/// source + cursor, so a surviving effect can be re-adopted into a freshly-built
/// tree at the SAME address (D4). Doubles as the runtime provider name (the
/// per-effect event-routing key — every concurrent effect has a disjoint path).
class AllocationAddress {
  /// Creates the address for [nodePath] under [sessionId].
  const AllocationAddress(this.sessionId, this.nodePath);

  /// The_grid's own session bead id this effect's cursor is written onto.
  final String sessionId;

  /// The effect's full path within the formula tree (`beadId/…/stepId`).
  final String nodePath;

  /// The runtime provider name — `<sessionId>/<nodePath>` — the disjoint
  /// event-routing key the transport spawns/stops/filters on.
  String get providerName => '$sessionId/$nodePath';

  @override
  bool operator ==(Object other) =>
      other is AllocationAddress &&
      other.sessionId == sessionId &&
      other.nodePath == nodePath;

  @override
  int get hashCode => Object.hash(sessionId, nodePath);

  @override
  String toString() => providerName;
}

/// The prior incarnation's identity, handed to [Allocation.startOrAdopt] so an
/// adopt-capable effect can run its **no-adopt-on-faith** freshness proof (D4/D5)
/// — pgid still alive ∧ token echoed. Empty (all null) for a fresh mint.
///
/// A minimal value type (not the [StepState] cursor) so the SDK effect layer
/// stays decoupled from the persisted codec: the Host projects it from the
/// node's cursor and hands it down.
class AdoptFence {
  /// Creates a fence carrying the prior [pgid]/[pid]/[token] (all optional).
  const AdoptFence({this.pgid, this.pid, this.token});

  /// The prior process-group id (the kill/liveness target for the proof).
  final int? pgid;

  /// The prior leader pid.
  final int? pid;

  /// The prior engine-minted freshness token (must be echoed by a live effect).
  final String? token;

  /// Whether there is any prior identity to prove against (else: mint fresh).
  bool get hasIdentity => pgid != null || pid != null || token != null;
}

/// What an [Allocation] reports to its host (ADR-0009 D5 — push). The Host maps
/// each to a cursor write OFF-BUILD through the one chokepoint; the Allocation
/// itself is **never handed a writer** (invariant 2 holds at this layer by
/// construction, the same layering as the pure [Capability]).
sealed class AllocationReport {
  const AllocationReport();
}

/// The effect's process group came up — the Host persists `state=running` plus
/// the per-node [pgid]/[pid] (the respawn/liveness fence). The freshness token is
/// the Host's (it minted it), so it is not carried here.
class AllocationStarted extends AllocationReport {
  /// Reports the spawned leader [pid] and (when resolvable) the [pgid].
  const AllocationStarted({required this.pid, this.pgid});

  /// The spawned leader pid.
  final int pid;

  /// The spawned process-group id, or null when pgid resolution failed at spawn.
  final int? pgid;
}

/// A daemon signalled it is up — a POSITIVE TERMINAL that satisfies a `dependsOn`
/// while the daemon stays mounted (OQ-5). The Host persists `state=ready` and
/// does NOT latch (a later death still reports [AllocationFailed]).
class AllocationReady extends AllocationReport {
  /// Reports a daemon reaching ready.
  const AllocationReady();
}

/// A job ran to completion — a POSITIVE TERMINAL that latches. The Host persists
/// `state=complete` merged with the optional [payload] (e.g. a critic's grade or
/// a land step's `pr_url`) under the disjoint result namespace.
class AllocationCompleted extends AllocationReport {
  /// Reports a clean completion, optionally carrying a result [payload].
  const AllocationCompleted([this.payload]);

  /// The optional result payload (recorded on the session bead, never used as a
  /// pipeline signal).
  final Map<String, String>? payload;
}

/// The effect failed — routes to supervision (D5). The Host persists the
/// supervised failure (bumped `restartCount` + backoff cooldown, or the
/// exhausted breaker) and latches.
class AllocationFailed extends AllocationReport {
  /// Reports a failure with an optional diagnostic [reason].
  const AllocationFailed([this.reason = '']);

  /// A human-readable failure reason.
  final String reason;
}

/// The work must PARK at a human gate (D7). The Host persists `state=gated` and
/// mints a real `type=gate` bead in the OWN state store (never the foreign work
/// bead — A37); resolving that gate re-arms the node.
class AllocationGated extends AllocationReport {
  /// Reports a gate park with an optional human-readable [reason].
  const AllocationGated([this.reason = '']);

  /// Why the work parked (recorded on the minted gate bead).
  final String reason;
}

/// The emit-only channel an [Allocation] reports transitions through (ADR-0009
/// D5). The Host supplies a guarded closure that persists each report off-build
/// through the chokepoint — NEVER a writer/notifier handed into the effect layer
/// (invariant 2). Safe to call across async gaps: the Host's closure drops a
/// report reaching an unmounted/cancelled node.
typedef AllocationSink = void Function(AllocationReport report);

/// The engine's pgid-liveness half of the daemon adopt-freshness proof (ADR-0009
/// D4: "pgid alive"). Returns whether the process group at [fence] is STILL a
/// live OS group — bound to a [ProcessGroupController] by the composer (live);
/// the offline default is `false` (no controller ⇒ can't prove liveness ⇒
/// respawn fresh, no-adopt-on-faith). The domain-specific "token echoed over its
/// endpoint" half is [ProcessCapability.proveFreshness].
typedef AllocationLiveness = bool Function(AdoptFence fence);

/// The offline liveness default — no OS controller wired, so nothing proves
/// live, so an adoptable effect respawns fresh (no-adopt-on-faith).
bool _noLiveness(AdoptFence fence) => false;

/// Everything an [Allocation] needs to manage its effect — assembled by the Host
/// and handed to [Capability.createAllocation] (ADR-0009 D5).
///
/// Bundles the sandboxed [CapabilityContext] (params/bead/workspace/services/
/// cancel/siblings — the effect reads its config here), the process [transport]
/// (a [RuntimeProvider] — spawn/kill/events; transport, NOT a writer/notifier),
/// the stable [address], the engine [env] overlay the Host computed (the GRID_*
/// vars incl. the freshness token), the [sink] to report through, and the
/// [fence] (the prior identity for a no-adopt-on-faith proof — D4).
class AllocationContext {
  /// Bundles the effect's [capContext], process [transport], [address], engine
  /// [env] overlay, report [sink], adopt [fence], step [kind], and pgid
  /// [liveness] seam.
  const AllocationContext({
    required this.capContext,
    required this.transport,
    required this.address,
    required this.env,
    required this.sink,
    this.fence = const AdoptFence(),
    this.kind = StepKind.job,
    this.liveness = _noLiveness,
  });

  /// The sandboxed capability context (the effect's read-only config slice).
  final CapabilityContext capContext;

  /// The process transport — `start`/`stop`/`events`. Transport only; holding it
  /// is not a writer/notifier (invariant 1/2 unaffected). A non-process effect
  /// simply never touches it.
  final RuntimeProvider transport;

  /// The stable, addressable identity (`<sessionId>/<nodePath>`).
  final AllocationAddress address;

  /// The engine env overlay the Host computed (`GRID_BEAD_ID`/`GRID_SESSION_ID`/
  /// `GRID_INSTANCE_TOKEN`/`GRID_STEP_PATH`) — layered over the capability's
  /// spawn config so a spawned effect can write its own cursor via the shim.
  final Map<String, String> env;

  /// The report channel (the Host persists each report off-build).
  final AllocationSink sink;

  /// The prior incarnation's identity for the adopt-freshness proof (D4); empty
  /// for a fresh mint.
  final AdoptFence fence;

  /// Whether this effect runs-to-completion ([StepKind.job]) or stays mounted
  /// ([StepKind.daemon]) — the discriminator for adoptability/detachability (D4:
  /// a job is respawn-or-skip; a daemon is adopt-or-respawn + detach-capable).
  final StepKind kind;

  /// The engine pgid-liveness half of the adopt-freshness proof (D4); offline
  /// default `false` (no controller ⇒ no adopt).
  final AllocationLiveness liveness;
}

/// A node of the_grid's third tree — a persistent managed object holding one live
/// effect (ADR-0009 D1). Minted synchronously by [Capability.createAllocation],
/// then driven asynchronously by the Host through the four verbs (D4/D5).
///
/// Subclasses own their effect's state machine + freshness proof and REPORT
/// through [AllocationContext.sink]; they never write. The engine ships the
/// [ProcessAllocation] + [ServiceAllocation] families; an asset may implement a
/// custom [Allocation] for a custom [Capability] (tmux, app, lease).
abstract class Allocation {
  /// Binds the allocation to its [context] (the sync mint half of D4). Stored so
  /// [startOrAdopt]/[update]/[dispose] can reference it without re-plumbing.
  Allocation(this.context);

  /// The effect's context (config/transport/address/env/sink/fence).
  AllocationContext context;

  /// This effect's stable address (`<sessionId>/<nodePath>`).
  AllocationAddress get address => context.address;

  /// The current lifecycle state — a pure observation subclasses advance as
  /// their effect progresses (the Host maps reports → the persisted cursor; this
  /// field never writes).
  AllocationState state = AllocationState.starting;

  /// Whether this effect type can be reattached to a survivor at its [address]
  /// (D4 — a per-type opt-in; a one-shot/service cannot, a daemon/lease can).
  /// When false, [startOrAdopt] always spawns fresh.
  bool get isAdoptable => false;

  /// Whether this effect type is safe to LEAVE RUNNING on unmount and re-adopt
  /// later (D4 — a per-type opt-in; the Host only calls [detach] when true).
  bool get isDetachable => false;

  /// Spawn a fresh effect OR prove-and-adopt a survivor at [address] (D4). The
  /// engine owns only the stable address + **no-adopt-on-faith** (an adoptable
  /// type must return proof of freshness; can't prove → spawn fresh). Reports
  /// lifecycle through [AllocationContext.sink]. The Host guards the single kick.
  Future<void> startOrAdopt();

  /// Whether this allocation can absorb [next]'s config in place, vs. the Host
  /// re-keying (dispose + recreate) — à la RenderObject `canUpdate` (D4).
  /// Update-vs-replace is a DOMAIN choice: a one-shot `-p` coding agent replaces
  /// (false); a tmux session updates (true). Defaults to replace.
  bool canUpdate(Allocation next) => false;

  /// Mutate in place to serve [next]'s config (only called when [canUpdate] is
  /// true). Rebinds [context] to [next]'s. Defaults to a no-op rebind.
  Future<void> update(Allocation next) async {
    context = next.context;
  }

  /// KILL the live effect (the default / floor unmount verb): the effect is
  /// done/invalidated. A process family terminates its group; a service cancels
  /// its body + runs teardown.
  Future<void> dispose();

  /// LEAVE the live effect RUNNING and persist its handle so a later
  /// [startOrAdopt] reattaches it (D4 — a per-type opt-in, [isDetachable]). A
  /// DISTINCT verb, never an overloaded [dispose] (Nico's constraint). The base
  /// throws so a non-detachable effect can never silently leak a process; the
  /// Host only calls it for a detachable type.
  Future<void> detach() {
    throw UnsupportedError(
      '$runtimeType is not detachable (ADR-0009 D4: detach is a per-type '
      'opt-in). The Host must dispose (kill) a non-detachable effect.',
    );
  }
}

/// The **service family** — the [JobAllocation] convenience (ADR-0009 D6):
/// start-runs, no update, no adopt, no detach. Drives a [ServiceCapability]'s
/// async body once and reports its [StepOutcome]. This is literally P0's
/// `Land/route` behavior, split onto the right object.
///
/// Not a process — it holds no group to reap; `dispose` cancels the cooperative
/// token and runs the capability's teardown.
class ServiceAllocation extends Allocation {
  /// Creates the service allocation for [capability] under [context].
  ServiceAllocation(this.capability, super.context);

  /// The pure service capability whose body this drives.
  final ServiceCapability capability;

  @override
  Future<void> startOrAdopt() async {
    state = AllocationState.live;
    // A service body has no adopt path (no survivable external effect) — it
    // simply runs. Its idempotence + the respawn-or-skip cursor make a re-run
    // after a crash safe (D6).
    final outcome = await capability.run(context.capContext);
    // The cooperative token may have been cancelled mid-run (the Host unmounted)
    // — the Host's guarded sink also drops a late report, so this is belt-and-
    // braces.
    if (context.capContext.cancel.isCancelled) {
      state = AllocationState.gone;
      return;
    }
    state = AllocationState.gone;
    context.sink(_reportFor(outcome));
  }

  /// Maps a [ServiceCapability] outcome to the report the Host persists.
  AllocationReport _reportFor(StepOutcome outcome) => switch (outcome) {
    Ok(:final payload) => AllocationCompleted(payload),
    Failed(:final reason) => AllocationFailed(reason),
    Gate(:final reason) => AllocationGated(reason),
  };

  @override
  Future<void> dispose() async {
    state = AllocationState.dying;
    context.capContext.cancel.cancel();
    await capability.teardown(context.capContext);
    state = AllocationState.gone;
  }
}

/// The **process family** — drives a [ProcessCapability] over the process
/// [transport] (ADR-0009 D6). A one-shot (`StepKind.job`) is respawn-or-skip
/// (not adoptable, not detachable — the reconciler + frontier own respawn); a
/// `StepKind.daemon` is adopt-or-respawn + detach-capable (Track C wires the
/// daemon proof/detach; the base here spawns-and-reports, preserving P0's
/// `Agent`/`Verify` behavior exactly).
///
/// Owns its subscription + event→report mapping (via [ProcessCapability.
/// interpretEvent]); reports [AllocationStarted] on `SessionStarted`, then
/// `ready`/`complete`/`failed` per the capability's interpretation. Holds NO
/// writer — the Host persists every report.
class ProcessAllocation extends Allocation {
  /// Creates the process allocation for [capability] under [context].
  ProcessAllocation(this.capability, super.context);

  /// The pure process capability describing what to spawn and how to read it.
  final ProcessCapability capability;

  StreamSubscription<RuntimeEvent>? _sub;
  bool _started = false;
  bool _adopted = false;
  bool _terminal = false;

  /// Whether the spawn was reached (the Host stops the group on unmount only
  /// when true).
  bool get started => _started;

  /// Whether a survivor was reattached instead of spawned (D4).
  bool get adopted => _adopted;

  /// A daemon ([StepKind.daemon]) is adopt-capable + detach-capable; a one-shot
  /// ([StepKind.job]) is respawn-or-skip (never adopts/detaches — D4).
  @override
  bool get isAdoptable => context.kind == StepKind.daemon;

  @override
  bool get isDetachable => context.kind == StepKind.daemon;

  @override
  Future<void> startOrAdopt() async {
    final ctx = context.capContext;

    // ADOPT a proven-fresh survivor (a daemon deliberately detached, or a crash
    // orphan still live) — reattach WITHOUT respawning (D4). **No-adopt-on-faith**
    // (D5): BOTH the engine pgid-liveness AND the capability's endpoint/token
    // proof must hold; either failing → spawn fresh, never adopt blind. (The live
    // cross-process output re-wire is the deferred adopt-a-live-process piece,
    // ADR-0008 D6; the load-bearing part built now is the adopt DECISION + not
    // double-spawning a survivor.)
    if (isAdoptable &&
        context.fence.hasIdentity &&
        context.liveness(context.fence) &&
        await capability.proveFreshness(context.fence, ctx)) {
      if (ctx.cancel.isCancelled) {
        state = AllocationState.gone;
        return;
      }
      state = AllocationState.adopting;
      _sub = context.transport.events
          .where((e) => e.name == address.providerName)
          .listen(_onEvent);
      _adopted = true;
      // The survivor was PROVEN live+ready — surface it as ready with no spawn.
      state = AllocationState.ready;
      context.sink(const AllocationReady());
      return;
    }

    // SPAWN fresh (a job, or a daemon that could not prove freshness).
    // Materialize the workspace BEFORE spawning into it (the effect owns
    // provisioning; ADR-0008 D5). Idempotent — a later step in the same worktree
    // no-ops, and an offline build with no source control no-ops.
    await ctx.services.sourceControl?.provisionWorkspace(
      beadId: ctx.beadId,
      workspaceDir: ctx.workspaceDir,
    );
    if (ctx.cancel.isCancelled) {
      state = AllocationState.gone;
      return;
    }
    state = AllocationState.live;
    final name = address.providerName;
    _sub = context.transport.events
        .where((e) => e.name == name)
        .listen(_onEvent);
    final base = capability.spawn(ctx);
    final config = base.copyWith(env: {...base.env, ...context.env});
    _started = true;
    try {
      await context.transport.start(name, config);
    } on SessionAlreadyExists {
      // A re-fired ready event raced the spawn — fine (the group is already up).
    }
  }

  void _onEvent(RuntimeEvent e) {
    // A terminal (complete/failed) latches the effect: a re-fired terminal
    // event never reads [ProcessCapability.result] twice nor double-reports (the
    // Host also latches, belt-and-braces). A daemon's `ready` is NOT terminal —
    // it may still die later and report `failed`.
    if (_terminal) return;
    if (e is SessionStarted) {
      context.sink(AllocationStarted(pid: e.pid, pgid: e.pgid));
      return;
    }
    final signal = capability.interpretEvent(e);
    switch (signal) {
      case StepSignal.none:
        return;
      case StepSignal.ready:
        state = AllocationState.ready;
        context.sink(const AllocationReady());
      case StepSignal.complete:
        _terminal = true;
        // The optional result payload the capability contributes on a clean
        // completion (read once, off the spawned process's output). Reported
        // WITH the completion so the Host records it in one merged write.
        unawaited(_reportComplete());
      case StepSignal.failed:
        _terminal = true;
        state = AllocationState.gone;
        context.sink(const AllocationFailed());
    }
  }

  Future<void> _reportComplete() async {
    final payload = await capability.result(context.capContext);
    if (context.capContext.cancel.isCancelled) return;
    state = AllocationState.gone;
    context.sink(AllocationCompleted(payload));
  }

  /// Test affordance: deliver [event] straight to the event handler (exercises
  /// the Host's post-dispose guard in isolation from the subscription cancel).
  /// Production events always arrive via the [transport] stream.
  void deliverEventForTest(RuntimeEvent event) => _onEvent(event);

  /// LEAVE the group RUNNING + keep its persisted handle (the per-node
  /// pgid/pid/token cursor already IS the handle) so a later [startOrAdopt]
  /// reattaches it (D4) — a DISTINCT verb from [dispose] (never stops the group,
  /// never tears down side-processes). Only the per-incarnation subscription is
  /// cancelled (this node stops observing); the OS group lives on. The
  /// reconciler's orphan-sweep reaps a detached effect nobody re-adopts (Track D).
  @override
  Future<void> detach() async {
    state = AllocationState.dying;
    unawaited(_sub?.cancel());
    _sub = null;
    state = AllocationState.gone;
  }

  @override
  Future<void> dispose() async {
    state = AllocationState.dying;
    // Cancel the cooperative token FIRST — a racing `startOrAdopt` that has not
    // yet spawned bails at its guard (no orphan spawn after unmount).
    context.capContext.cancel.cancel();
    unawaited(_sub?.cancel());
    _sub = null;
    // Kill the managed group — whether we spawned it (_started) or reattached a
    // survivor (_adopted); dispose is KILL, the floor (D4).
    if (_started || _adopted) {
      unawaited(context.transport.stop(address.providerName));
    }
    await capability.teardown(context.capContext);
    state = AllocationState.gone;
  }
}
