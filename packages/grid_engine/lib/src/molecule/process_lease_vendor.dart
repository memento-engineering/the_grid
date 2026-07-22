/// `ProcessLeaseVendor` — leased process identity (`DESIGN-tg-pm6.md` §7, R3;
/// Decided item 5: "process identity leased; throw-required if absent").
///
/// On the flat model, a spawned process's `pgid`/`pid`/`token` ride the
/// node's OWN [NodeCursor] (`sdk/cursor.dart`), written by `CapabilityHost` at
/// `SessionStarted` and read back into the next mount's [AdoptFence]. On the
/// molecule model that identity stops being NODE-owned durable state and
/// becomes a LEASE an ambient vendor grants, addressed by the stable step-bead
/// id rather than an in-run `nodePath` — so [ProcessHandle] survives a rework
/// re-key untouched (the step bead never reshapes; only its `nodePath` slot in
/// a fresh incarnation might).
///
/// This file **reuses the lease family verbatim** (`sdk/lease.dart:72`
/// `LeaseCapability`, `:148` `startOrAdopt`'s no-adopt-on-faith contract) —
/// [StationProcessLeaseVendor.leaseFor] vends a [LeaseCapability<ProcessHandle>]
/// per step bead; `LeaseAllocation` (unchanged) drives it exactly as it drives
/// any other lease. The only new surface is: what `H` is ([ProcessHandle]), how
/// `adoptable`/`acquire`/`release` read and write the vendor-owned breadcrumb
/// (`LeaseKeys.*`, `molecule_schema.dart`), and how `proveFresh` proves it —
/// `StationServices.liveness` (`kernel/station_services.dart:49-50`), the SAME
/// pgid-alive seam the flat model's `ProcessAllocation`/the I-10 dead-fence
/// probe use.
///
/// **`grid.lease.*` has exactly one writer.** [StationProcessLeaseVendor.acquire]
/// is the only place this file calls `writer.update` with a lease key, and
/// `release` is the only place it clears one — nothing else in the molecule
/// model (not the codec, not `live_frontier.dart`) ever touches this
/// namespace (`molecule_codec_test.dart`'s structural boundary test proves the
/// read half of that already).
///
/// **A narrow, deliberate exception to "the effect layer holds no writer"**
/// (`sdk/lease.dart`'s own `LeaseCapability` doc: invariant 2, "it REPORTS
/// through the sink; the Host persists off-build"). That invariant guards
/// AUTHOR-supplied capabilities — `LeaseAllocation` is generic over an OPAQUE
/// `H`, so a Host genuinely cannot persist an author's handle shape for them.
/// [StationProcessLeaseVendor] is not author-supplied: it is an ENGINE-owned
/// kernel construct, provided once at the kernel root beside
/// `CapabilityRegistry` — the SAME trust tier as `CapabilityHost` itself,
/// which already holds `StationServices.writer` directly
/// (`circuit/capability_host.dart:300` etc.) rather than reporting through a
/// sink. Holding [StationBeadWriter] here is that same kernel-tier posture,
/// narrowed to a namespace (`grid.lease.*`) nothing else in the molecule
/// model ever writes.
///
/// **The real wiring (tg-h4u, the A53 follow-up rung — DELIVERED).** The REAL
/// [ProcessSpawner]/[ProcessDispatcher] live in `station_process_transport.dart`
/// (a `RuntimeProvider` spawn + event wait, mirroring `ProcessAllocation`);
/// the real [StepMetadataReader] is `StationBeadWriter.metadataOf` (a snapshot
/// read in grid_runtime — the exact `grid_engine ──► grid_runtime`
/// "subprocess/git/chokepoint transport" edge ADR-0002 Decision 1 names, an
/// ALLOWED direction). `kernel/station_kernel.dart` now composes a real
/// [StationProcessLeaseVendor] over `StationServices` by DEFAULT at the kernel
/// root (a composer-supplied vendor overrides it), and
/// `CapabilityHost._createAllocationOrFlare` routes a molecule-mode
/// [ProcessCapability] through [ProcessLeaseVendor.leaseFor] →
/// `LeaseAllocation` instead of the flat `ProcessAllocation` path. Still inert
/// in practice until a composition sets `circuitMintMode: molecule` (the live
/// arm, tg-6gi); the flat path is untouched.
library;

import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../sdk/allocation.dart';
import '../sdk/capability.dart';
import '../sdk/circuit.dart';
import '../sdk/lease.dart';
import 'molecule_schema.dart';

/// A per-incarnation, BUFFERED tap on a transport's broadcast [RuntimeEvent]
/// stream — the ONE subscription spanning acquire→dispatch (tg-uad D1,
/// mirroring `ProcessAllocation`'s hold-one-subscription-for-the-whole-life
/// shape).
///
/// `stationProcessSpawner` opens it BEFORE `transport.start` and hands it to
/// `stationProcessDispatcher` through [ProcessHandle.events]. Because the
/// inner controller BUFFERS, an event emitted while nobody has consumed
/// [stream] yet — the old unobserved acquire→dispatch window an unbuffered
/// broadcast stream dropped events in — is QUEUED, never lost. Closed by
/// whoever finishes with it (the dispatcher when it settles; the lease
/// release when dispatch never ran); [close] is idempotent.
class ProcessEventTap {
  /// Opens the tap: subscribes to [source] filtered to [name] immediately.
  ProcessEventTap.open(Stream<RuntimeEvent> source, String name) {
    _sub = source.where((e) => e.name == name).listen((e) {
      if (!_controller.isClosed) _controller.add(e);
    });
  }

  final StreamController<RuntimeEvent> _controller =
      StreamController<RuntimeEvent>();
  late final StreamSubscription<RuntimeEvent> _sub;
  bool _closed = false;

  /// The buffered, single-subscription view of the session's events from the
  /// instant the tap was opened.
  Stream<RuntimeEvent> get stream => _controller.stream;

  /// Whether [close] has run — the incarnation's lease-lifetime signal (the
  /// tap dies with the lease): the concurrent breadcrumb persist gates its
  /// retries on this, so a retry can never be enqueued after release's
  /// clearing write (release closes the tap BEFORE it clears).
  bool get isClosed => _closed;

  /// Cancels the upstream subscription and closes the buffer. Idempotent.
  Future<void> close() {
    if (_closed) return Future<void>.value();
    _closed = true;
    // Deliberately not awaited: a single-subscription controller that was
    // never listened to parks its close()'s done future forever.
    unawaited(_controller.close());
    return _sub.cancel();
  }
}

/// A leased process's identity — `pgid`/`pid`/`token` as the OPAQUE handle
/// type `H` a [LeaseCapability<ProcessHandle>] acquires/adopts/releases
/// (Decided item 5). Never written to a [NodeCursor] on the molecule path;
/// only ever carried as this lease family's handle, or encoded into the
/// [LeaseKeys] breadcrumb by [leaseBreadcrumb].
class ProcessHandle {
  /// Creates the handle from a spawned process's [pgid]/[pid] plus the
  /// engine-minted freshness [token] (the SAME three-part identity
  /// [AdoptFence] carries for the flat model's `ProcessAllocation`),
  /// optionally carrying the incarnation's [events] tap.
  const ProcessHandle({
    required this.pgid,
    required this.pid,
    required this.token,
    this.events,
  });

  /// The spawned process-group id (the respawn/liveness kill target).
  final int pgid;

  /// The spawned leader pid.
  final int pid;

  /// The engine-minted freshness token a live effect must echo back to be
  /// proven (the domain-specific half of no-adopt-on-faith; the pgid-alive
  /// half is [AllocationLiveness]).
  final String token;

  /// The per-incarnation buffered event tap `stationProcessSpawner` opened for
  /// this handle BEFORE the spawn (tg-uad), or null for a handle that has no
  /// live incarnation to observe (a breadcrumb-parsed adopt survivor, a
  /// test-minted literal). Live plumbing, NOT identity: excluded from
  /// [operator ==]/[hashCode] and never encoded into the [leaseBreadcrumb].
  final ProcessEventTap? events;

  @override
  bool operator ==(Object other) =>
      other is ProcessHandle &&
      other.pgid == pgid &&
      other.pid == pid &&
      other.token == token;

  @override
  int get hashCode => Object.hash(pgid, pid, token);

  @override
  String toString() => 'ProcessHandle(pgid: $pgid, pid: $pid, token: $token)';
}

/// A vendor of process leases, addressed per step bead (Decided item 5). One
/// instance is provided ambient to the whole station tree (deferred to
/// `pm6-r5-drain`'s kernel-root provision, beside `CapabilityRegistry`); every
/// process-backed capability on the molecule path calls [leaseFor] with ITS
/// OWN durable step-bead id to obtain the [LeaseCapability<ProcessHandle>] it
/// mounts.
///
/// Two implementations ship in this file: [StationProcessLeaseVendor] (the
/// real, breadcrumb-persisting vendor) and [SelfManagedProcessVendor] (the
/// explicitly-named degraded fallback — no durable identity, so no adopt is
/// ever possible). A THIRD outcome — no vendor mounted at all — is refused
/// loudly by [requireProcessLeaseVendor], never silently substituted.
abstract class ProcessLeaseVendor {
  /// Vends the lease capability for [request] — keyed by
  /// [ProcessLeaseRequest.stepBeadId], the ADDRESS a crash-restart re-adopts
  /// by (topology-stable; Decided item 2), never an in-run `nodePath`. The
  /// request-carrying shape (tg-h4u round-3 spec): the REAL spawner/dispatcher
  /// need the pure [ProcessCapability] and the host-assembled
  /// [AllocationContext] (transport/env/address/sink), and they are captured
  /// HERE — `LeaseCapability.acquire`'s own `(TreeContext, StepArgs)`
  /// signature cannot carry them.
  LeaseCapability<ProcessHandle> leaseFor(ProcessLeaseRequest request);

  /// **The crash-restart orphan sweep** (tg-eli phase 1; Nico's 2026-07-19
  /// ruling: `grid.lease.*` has ONE owner, so the `RestartReconciler` gets
  /// THIS vendor-exposed sweep and never parses a lease key itself).
  ///
  /// GIVEN the candidate step beads the caller already holds ([candidates] —
  /// the reconciler projects them from its post-barrier state snapshot; this
  /// method issues NO reads of its own), identifies each step whose breadcrumb
  /// records a live process group that NOTHING will re-adopt, kills it through
  /// the caller's guarded [terminate] seam (never a raw process kill), and
  /// clears the breadcrumb (the vendor's own clearing write — release's exact
  /// [kClearedLeaseKeys] payload).
  ///
  /// [alive] is the caller's KILL GATE — the engine pgid-alive probe, bound to
  /// the SAME real `ProcessGroupController` the caller's other kills ride
  /// (never the vendor's own adopt-liveness, which may deliberately stay at
  /// its never-adopt default while adoption is unarmed). Because the caller
  /// cannot reach the sweep without binding it, a wired sweep is ARMED by
  /// construction — it can never be silently inert.
  ///
  /// The orphan predicate is no-adopt-on-faith's mirror image (ADR-0009
  /// D4/D5):
  ///  - a step whose fine state LATCHED (`complete`/`failed`/`gated`) is
  ///    skipped untouched;
  ///  - a breadcrumb that does not parse ([leaseBreadcrumbOf]) is skipped —
  ///    nothing is leased — EXCEPT that a step which already spawned (state
  ///    `running`/`ready`) with its lease keys entirely absent (not the
  ///    cleared sentinel) is reported LOUD through [onOrphan] before the
  ///    skip: that shape means the acquire's concurrent breadcrumb write
  ///    never landed, and a surviving group cannot be found or killed here;
  ///  - a group the caller's [alive] probe cannot PROVE alive is never killed
  ///    (negative evidence only ever WITHHOLDS a kill) and its stale
  ///    breadcrumb is LEFT: it is inert (adoption gates on the vendor's own
  ///    freshness proof, and the next acquire overwrites it), and leaving it
  ///    avoids a per-step boot write-burst;
  ///  - a live DAEMON whose adopt-freshness proof holds — the vendor's OWN
  ///    proof, the same fence `proveFresh` runs — AND whose candidate declares
  ///    [LeaseSweepCandidate.willRemount] is left running for the re-mounting
  ///    tree to adopt ([LeaseSweepDisposition.leftAdoptable]); under a
  ///    TERMINAL session (`willRemount: false`) nothing will ever adopt it, so
  ///    it is an orphan like any other;
  ///  - everything else alive — a job ALWAYS (jobs never adopt), a daemon
  ///    whose proof fails (adoption unarmed ⇒ every daemon), a step with no
  ///    provable daemon kind — is an ORPHAN: killed + cleared, reported LOUD
  ///    through [onOrphan] (the down-path orphan-sweep discipline,
  ///    `docs/OPERATIONS.md` §2.4).
  ///
  /// Every group the sweep acted on (or deliberately preserved) is returned;
  /// a skipped/dead/unparsable candidate is not (nothing happened to it).
  Future<List<SweptLeaseGroup>> sweepOrphanedLeases({
    required Iterable<LeaseSweepCandidate> candidates,
    required LeaseGroupLiveness alive,
    required LeaseGroupTerminator terminate,
    required void Function(String message) onOrphan,
  });
}

/// The per-mount request a [ProcessLeaseVendor] vends against (tg-h4u): the
/// durable step-bead address the lease is keyed by, the pure
/// [ProcessCapability] describing what to spawn and how to read its events,
/// and the [AllocationContext] the host assembled — transport, env overlay
/// (incl. the freshness token), address, and the report sink the REAL spawner
/// surfaces `AllocationStarted` through.
class ProcessLeaseRequest {
  /// Bundles the [stepBeadId] lease address, the pure [capability], and the
  /// host-assembled [allocation] context.
  const ProcessLeaseRequest({
    required this.stepBeadId,
    required this.capability,
    required this.allocation,
  });

  /// The durable step-bead id this lease is keyed by (Decided items 2/5).
  final String stepBeadId;

  /// The pure process capability (spawn config + event interpretation +
  /// optional result payload).
  final ProcessCapability capability;

  /// The host-assembled context — transport/env/address/sink — everything the
  /// REAL spawner/dispatcher need beyond the lease family's `(context, args)`.
  final AllocationContext allocation;
}

/// LOUD-or-GONE (Decided item 5): resolves the ambient [ProcessLeaseVendor], a
/// process-backed `CapabilityHost` on the molecule path MUST consult before
/// mounting — THROWING when none is provided rather than silently falling
/// back to [SelfManagedProcessVendor]. That fallback is a real, usable vendor,
/// but choosing it is the composer's decision to make explicitly (mount one),
/// never this call's decision to make for them.
///
/// Uses the EFFECT verb (`getInheritedSeedOfExactType`), not the tree verb: a
/// `CapabilityHost` consults this OFF `build`, in the async report/persist
/// path (`_persistStarted`, mirroring `_moleculeTarget`'s own
/// `InheritedCircuit` read one method above) — a one-shot presence guard, not
/// a value the host must rebuild on. Registering a `dependOn` there would
/// couple every daemon host that ever reported `AllocationStarted` to the
/// vendor's object identity (no `==` override), so any kernel rebuild that
/// re-instantiates the vendor would fire a spurious `didChangeDependencies`
/// on an already-live process.
ProcessLeaseVendor requireProcessLeaseVendor(TreeContext context) {
  final vendor = context.getInheritedSeedOfExactType<ProcessLeaseVendor>();
  if (vendor == null) {
    throw StateError(
      'No ProcessLeaseVendor is mounted ambient to this branch. A '
      'process-backed capability on the molecule path requires one — mount a '
      'SelfManagedProcessVendor explicitly for the degraded (no-adopt) mode; '
      'there is deliberately no silent default.',
    );
  }
  return vendor;
}

/// The [LeaseKeys] write payload [StationProcessLeaseVendor.acquire] persists
/// through the writer chokepoint — the vendor-owned adopt breadcrumb (Decided
/// item 5). String-encoded because bd metadata is flat `Map<String, String>`
/// (no nested/typed values).
Map<String, String> leaseBreadcrumb(ProcessHandle handle) => {
  LeaseKeys.pgid: '${handle.pgid}',
  LeaseKeys.pid: '${handle.pid}',
  LeaseKeys.token: handle.token,
};

/// The clearing write payload [StationProcessLeaseVendor.release] persists.
/// `bd update --metadata` has no key-DELETE primitive (metadata is
/// `Map<String, String>`, never nullable) — so clearing is an EMPTY-STRING
/// sentinel per key. [leaseBreadcrumbOf] treats a blank value exactly like an
/// absent one, so a cleared breadcrumb never round-trips back into a
/// [ProcessHandle] (a released lease can never be mistaken for a live one).
const Map<String, String> kClearedLeaseKeys = {
  LeaseKeys.pgid: '',
  LeaseKeys.pid: '',
  LeaseKeys.token: '',
};

/// Parses a [ProcessHandle] back off a step bead's current [metadata] — the
/// read half of [leaseBreadcrumb], and what [StationProcessLeaseVendor.adoptable]
/// calls to decide whether the breadcrumb is "re-addressable" (Decided item
/// 5). Returns null when any of the three keys is absent, blank (the
/// [kClearedLeaseKeys] sentinel), or an unparsable pgid/pid — a PARTIAL
/// breadcrumb is not adoptable; no-adopt-on-faith starts at this read, before
/// [StationProcessLeaseVendor.proveFresh] ever runs.
ProcessHandle? leaseBreadcrumbOf(Map<String, String> metadata) {
  final pgidText = metadata[LeaseKeys.pgid];
  final pidText = metadata[LeaseKeys.pid];
  final token = metadata[LeaseKeys.token];
  if (pgidText == null || pgidText.isEmpty) return null;
  if (pidText == null || pidText.isEmpty) return null;
  if (token == null || token.isEmpty) return null;
  final pgid = int.tryParse(pgidText);
  final pid = int.tryParse(pidText);
  if (pgid == null || pid == null) return null;
  return ProcessHandle(pgid: pgid, pid: pid, token: token);
}

/// One candidate step bead for [ProcessLeaseVendor.sweepOrphanedLeases]: the
/// durable step-bead id (the lease ADDRESS) plus that bead's CURRENT metadata,
/// both of which the CALLER already holds — the `RestartReconciler` projects
/// them off its post-barrier state snapshot (the SAME read its cursor
/// projection rides, A39), so the sweep itself issues no bd query and opens no
/// subscription.
///
/// [willRemount] is the CALLER's fact about the step's SESSION, never a lease
/// fact the vendor could read off metadata: true when a tree re-mount for that
/// session is still coming (a NON-terminal session the frontier will drive
/// again), false when the session already reached its terminal and no
/// `startOrAdopt` will ever run against what it left behind. It is REQUIRED,
/// not defaulted: preserving a live daemon nothing will adopt is exactly the
/// leak this field closes, so the caller STATES it rather than inheriting it
/// silently.
typedef LeaseSweepCandidate = ({
  String stepBeadId,
  Map<String, String> metadata,
  bool willRemount,
});

/// The guarded group-terminate seam the sweep kills through — the caller binds
/// it to the REAL `terminateGroup` over its own `ProcessGroupController`, so
/// every kill inherits the load-bearing `pgid <= 1`/own-group safety guard
/// (never bypassed, never a raw process kill).
typedef LeaseGroupTerminator =
    Future<GroupTerminateResult> Function({
      required int pgid,
      required int leaderPid,
    });

/// The caller-bound KILL GATE the sweep proves every group alive on before it
/// terminates — bound to the SAME real `ProcessGroupController` the caller's
/// [LeaseGroupTerminator] rides (`processAlive` over the recorded leader pid,
/// the flat path's exact kill-gate evidence). DISTINCT from the vendor's own
/// adopt-liveness ([StationProcessLeaseVendor.liveness], `proveFresh`'s
/// fence): THIS seam answers only "is the group provably alive at all", so
/// the sweep stays armed while adoption deliberately stays at its never-adopt
/// default (the D4 all-or-nothing wire).
typedef LeaseGroupLiveness =
    bool Function({required int pgid, required int leaderPid});

/// What [ProcessLeaseVendor.sweepOrphanedLeases] did to ONE live lease group.
enum LeaseSweepDisposition {
  /// A live ORPHAN — a group no re-mount will adopt — terminated through the
  /// guarded seam, its breadcrumb cleared. Absorbs the `alreadyGone` outcome
  /// (the group died between the probe and the signal: no signal was sent, but
  /// the no-double-run guarantee holds all the same; the exact
  /// [SweptLeaseGroup.terminateResult] is preserved).
  killed,

  /// The terminate guard refused (`pgid <= 1`/own-group) — NO signal was sent
  /// and the breadcrumb was LEFT (it is the only record an operator has of a
  /// group that may still be running). The documented recycled-pgid/own-group
  /// residual; the guard is never bypassed.
  refusedUnsafe,

  /// A live DAEMON whose freshness proof held — left running, breadcrumb
  /// intact, for the re-mounting tree's `startOrAdopt` to reattach (D4).
  leftAdoptable,
}

/// One lease group the sweep acted on (or deliberately preserved) — enough for
/// a caller/test to assert WHAT happened and WHY without scraping logs (the
/// same posture as the reconciler's own `RestartEntry`).
class SweptLeaseGroup {
  /// Records the sweep's decision for [stepBeadId]'s leased [handle].
  const SweptLeaseGroup({
    required this.stepBeadId,
    required this.handle,
    required this.disposition,
    this.terminateResult,
    this.clearFailure,
  });

  /// The step bead whose breadcrumb recorded this group.
  final String stepBeadId;

  /// The parsed breadcrumb — the group's pgid/pid/token identity.
  final ProcessHandle handle;

  /// What the sweep did.
  final LeaseSweepDisposition disposition;

  /// The exact guarded-terminate outcome; null for
  /// [LeaseSweepDisposition.leftAdoptable] (no kill was attempted).
  final GroupTerminateResult? terminateResult;

  /// Why the breadcrumb-clearing write was DROPPED (a transient bd blip), or
  /// null when it landed / was deliberately left. The kill itself still
  /// happened; the drop is reported LOUD by the sweep.
  final String? clearFailure;

  @override
  String toString() =>
      'SweptLeaseGroup($stepBeadId pgid ${handle.pgid}: ${disposition.name}'
      '${terminateResult == null ? '' : ' (${terminateResult!.name})'}'
      '${clearFailure == null ? '' : ', clear DROPPED: $clearFailure'})';
}

/// Whether a step bead's persisted fine state LATCHED (`complete`/`failed`/
/// `gated`) — the sweep skips such a step entirely (its group is not the
/// sweep's business; killing on a latched marker would be destruction with no
/// respawn story). `ready` is NOT latched: it is a daemon's live positive
/// terminal, whose group must flow through the adopt-or-orphan decision. An
/// absent/unrecognised state reads pending-like (nothing has run yet).
bool _isLatchedStepState(String? wire) {
  StepState? state;
  for (final s in StepState.values) {
    if (s.name == wire) state = s;
  }
  return switch (state) {
    StepState.complete || StepState.failed || StepState.gated => true,
    StepState.pending || StepState.running || StepState.ready || null => false,
  };
}

/// Mints a fresh [ProcessHandle] for the request's incarnation — the real
/// spawn (a `RuntimeProvider.start` + wait for its `SessionStarted` pgid/pid;
/// the freshness token rides the request's env overlay). The REAL
/// implementation is `stationProcessSpawner`
/// (`station_process_transport.dart`); a test supplies a fake with the SAME
/// request-carrying shape.
typedef ProcessSpawner =
    Future<ProcessHandle> Function(
      ProcessLeaseRequest request,
      TreeContext context,
      StepArgs args,
    );

/// Runs the work on the already-bound [handle] and interprets it into a
/// [StepOutcome] — the real dispatch (waiting on the SAME process's
/// `RuntimeProvider` events for `ready`/`complete`/`failed`;
/// `stationProcessDispatcher` in `station_process_transport.dart`). NOT called
/// on adopt (`LeaseCapability`'s own contract, `sdk/lease.dart`).
typedef ProcessDispatcher =
    Future<StepOutcome> Function(
      ProcessHandle handle,
      ProcessLeaseRequest request,
      TreeContext context,
      StepArgs args,
    );

/// Reads a step bead's CURRENT metadata — the real bd lookup
/// [StationProcessLeaseVendor.adoptable] needs to see a prior incarnation's
/// breadcrumb after a station restart (an in-memory recollection would not
/// survive the restart the whole adopt story exists for). Injected; the live
/// composer backs this with a real read (`pm6-r5a`'s join / a direct bd
/// query) at kernel-root provision time. Returns null when the bead carries no
/// metadata at all (never happens for a real step bead, but keeps the seam
/// total for a test double).
typedef StepMetadataReader =
    Future<Map<String, String>?> Function(String stepBeadId);

/// The real, breadcrumb-persisting [ProcessLeaseVendor] (Decided item 5's
/// non-degraded mode). Holds the four collaborators [leaseFor]'s vended lease
/// needs — [writer] (the SAME `StationBeadWriter` chokepoint every other
/// molecule write already rides, Decided conflict 3), [spawn]/[dispatch] (the
/// deferred process transport), [metadataOf] (the deferred breadcrumb read),
/// and [liveness] (`StationServices.liveness`, defaulting to [neverLive] —
/// same offline default the flat model's `AllocationContext.liveness` uses).
class StationProcessLeaseVendor implements ProcessLeaseVendor {
  /// Creates the vendor over its collaborators. [writer] is REQUIRED (there is
  /// no sensible default for the sole writer of `grid.lease.*`); [spawn]/
  /// [dispatch]/[metadataOf] are the deferred-transport seams (§library);
  /// [liveness] defaults to [neverLive] (no controller wired ⇒ never proves
  /// fresh ⇒ always respawns — the safe offline posture, mirroring
  /// `StationServices.liveness`'s own null-to-`neverLive` fallback).
  const StationProcessLeaseVendor({
    required this.writer,
    required this.spawn,
    required this.dispatch,
    required this.metadataOf,
    this.liveness = neverLive,
  });

  /// The single bd write chokepoint — the sole writer (and clearer) of
  /// `grid.lease.*`.
  final StationBeadWriter writer;

  /// Mints a fresh handle on [LeaseCapability.acquire].
  final ProcessSpawner spawn;

  /// Runs the work on a bound handle for [LeaseCapability.dispatchOn].
  final ProcessDispatcher dispatch;

  /// Reads a step bead's current metadata for [LeaseCapability.adoptable].
  final StepMetadataReader metadataOf;

  /// The pgid-alive half of no-adopt-on-faith for [LeaseCapability.proveFresh].
  final AllocationLiveness liveness;

  @override
  LeaseCapability<ProcessHandle> leaseFor(ProcessLeaseRequest request) =>
      _VendedProcessLease(
        request: request,
        writer: writer,
        spawn: spawn,
        dispatch: dispatch,
        metadataOf: metadataOf,
        liveness: liveness,
      );

  /// The real sweep. **Adopt-window safety:** the reconciler runs this BEFORE
  /// the tree re-mounts (`StationWorkRuntime.start()` pins reconcile →
  /// `runGrid`), so no `LeaseAllocation.startOrAdopt` is in flight while it
  /// kills — and even unsequenced, the kill set is disjoint from the adopt set
  /// BY CONSTRUCTION for this vendor: a job is never adoptable
  /// (`LeaseAllocation.isAdoptable` is kind-gated) and a daemon is only ever
  /// killed when the SAME proof that gates its [proveFresh] refuted it — a
  /// daemon a re-mount would legitimately adopt is exactly a daemon this
  /// sweep leaves.
  ///
  /// **A clear that cannot be proven is withheld, a write that fails is LOUD
  /// but non-fatal:** the pass mirrors the reconciler's zombie-reap posture —
  /// a dropped breadcrumb clear (a transient bd blip) is recorded on the
  /// [SweptLeaseGroup.clearFailure] and reported through [onOrphan], and the
  /// pass CONTINUES; it never turns a boot into a new outage.
  @override
  Future<List<SweptLeaseGroup>> sweepOrphanedLeases({
    required Iterable<LeaseSweepCandidate> candidates,
    required LeaseGroupLiveness alive,
    required LeaseGroupTerminator terminate,
    required void Function(String message) onOrphan,
  }) async {
    final swept = <SweptLeaseGroup>[];
    for (final candidate in candidates) {
      // A LATCHED step is untouched — complete/failed/gated is not this
      // sweep's business (the frontier never re-mounts it as-is; killing on a
      // latched marker would be destruction with no respawn story).
      if (_isLatchedStepState(candidate.metadata[MoleculeStepKeys.state])) {
        continue;
      }

      // The vendor-owned breadcrumb — the ONLY lease-key read on this path
      // (the caller stays lease-schema-ignorant). No breadcrumb, or a
      // cleared/partial one ⇒ nothing is leased; the frontier re-mounts and
      // the job lease respawns fresh (respawn-or-skip, D5).
      final handle = leaseBreadcrumbOf(candidate.metadata);
      if (handle == null) {
        // NOT silently (tg-uad D3 repair round 1): a step that already
        // SPAWNED (state running/ready) OWES a breadcrumb. Its lease keys
        // being entirely ABSENT — not the cleared sentinel release writes —
        // means the acquire's concurrent breadcrumb write never landed
        // (dropped, or the station died inside the write window). The sweep
        // has no pgid to key a kill from, so if that incarnation's group
        // survived the crash it CANNOT be found or killed here — say so
        // LOUD instead of skipping like nothing was ever leased.
        final state = candidate.metadata[MoleculeStepKeys.state];
        final spawned =
            state == StepState.running.name || state == StepState.ready.name;
        final keysAbsent =
            !candidate.metadata.containsKey(LeaseKeys.pgid) &&
            !candidate.metadata.containsKey(LeaseKeys.pid) &&
            !candidate.metadata.containsKey(LeaseKeys.token);
        if (spawned && keysAbsent) {
          onOrphan(
            'lease sweep: step "${candidate.stepBeadId}" is $state but '
            'carries NO lease breadcrumb — its acquire\'s breadcrumb write '
            'never landed (dropped, or the station died mid-write). If that '
            'incarnation\'s process group survived the restart, this sweep '
            'cannot find or kill it — inspect and terminate it by hand.',
          );
        }
        continue;
      }

      // The CALLER's kill gate — the same real-controller evidence its other
      // kills ride, NOT this vendor's adopt-liveness (which may deliberately
      // stay never-adopt). A group that cannot be PROVEN alive is never
      // killed (negative evidence only withholds a kill), and its stale
      // breadcrumb is LEFT: it is inert (adoption gates on the freshness
      // proof; the next acquire overwrites it), and leaving it avoids a
      // per-step boot write-burst.
      if (!alive(pgid: handle.pgid, leaderPid: handle.pid)) continue;

      // A live daemon is preserved on TWO conditions, both required. First,
      // this vendor's OWN adopt-freshness proof — the SAME fence [proveFresh]
      // runs, so the preserve set and the adopt set can never drift (D4/D5).
      // Second, a re-mount must actually be COMING
      // ([LeaseSweepCandidate.willRemount]): under a session that already
      // reached its terminal there is no future `startOrAdopt` to hand the
      // survivor to, so preserving it would leak the group across every
      // subsequent boot — it falls through to the kill below exactly like a
      // job. With adoption UNARMED ([liveness] at its [neverLive] default) the
      // proof refutes every daemon anyway, so this second condition only bites
      // once the D4 adopt wire arms.
      if (candidate.willRemount &&
          candidate.metadata[MoleculeStepKeys.kind] == StepKind.daemon.name &&
          liveness(
            AdoptFence(pgid: handle.pgid, pid: handle.pid, token: handle.token),
          )) {
        swept.add(
          SweptLeaseGroup(
            stepBeadId: candidate.stepBeadId,
            handle: handle,
            disposition: LeaseSweepDisposition.leftAdoptable,
          ),
        );
        continue;
      }

      // ORPHAN: a live group nothing will adopt — a job always (jobs never
      // adopt, D5), a daemon whose freshness proof failed (adoption unarmed ⇒
      // all of them), or a step with no provable daemon kind
      // (no-adopt-on-faith starts at the metadata read). Kill through the
      // caller's guarded seam.
      final result = await terminate(pgid: handle.pgid, leaderPid: handle.pid);
      switch (result) {
        case GroupTerminateResult.exitedOnTerm:
        case GroupTerminateResult.killed:
        case GroupTerminateResult.alreadyGone:
          onOrphan(
            'lease sweep: step "${candidate.stepBeadId}" left process group '
            '${handle.pgid} (leader pid ${handle.pid}) ALIVE across the '
            'restart — an orphan nothing re-adopts; terminated '
            '(${result.name}) and cleared its lease breadcrumb',
          );
          String? clearFailure;
          try {
            await writer.update(
              candidate.stepBeadId,
              metadata: kClearedLeaseKeys,
            );
          } on Object catch (error) {
            clearFailure = '$error';
            onOrphan(
              'lease sweep: the breadcrumb clear for step '
              '"${candidate.stepBeadId}" was DROPPED ($error) — grid.lease.* '
              'still records pgid ${handle.pgid} over the group this pass '
              'just terminated',
            );
          }
          swept.add(
            SweptLeaseGroup(
              stepBeadId: candidate.stepBeadId,
              handle: handle,
              disposition: LeaseSweepDisposition.killed,
              terminateResult: result,
              clearFailure: clearFailure,
            ),
          );
        case GroupTerminateResult.refusedUnsafe:
          // The guard is NEVER bypassed — and the breadcrumb is NOT cleared:
          // it is the only record an operator has of a group that may still
          // be running.
          onOrphan(
            'lease sweep: REFUSED to signal process group ${handle.pgid} for '
            'step "${candidate.stepBeadId}" — the terminateGroup guard '
            '(pgid <= 1, or the supervisor\'s own group). It may still be '
            'running; terminate it by hand.',
          );
          swept.add(
            SweptLeaseGroup(
              stepBeadId: candidate.stepBeadId,
              handle: handle,
              disposition: LeaseSweepDisposition.refusedUnsafe,
              terminateResult: result,
            ),
          );
      }
    }
    return swept;
  }
}

/// The backoff for `_VendedProcessLease._persistBreadcrumb`'s retry loop:
/// 25ms doubling per attempt, capped at 2s — fast enough that a transient bd
/// blip costs only milliseconds of sweep/adoption blindness, slow enough not
/// to hammer a chokepoint that is genuinely down.
Duration _breadcrumbRetryDelay(int attempt) {
  final shift = (attempt - 1).clamp(0, 7);
  final ms = (25 << shift).clamp(25, 2000);
  return Duration(milliseconds: ms);
}

/// The [LeaseCapability<ProcessHandle>] [StationProcessLeaseVendor.leaseFor]
/// vends for ONE step bead. Reuses the lease family verbatim — only
/// `adoptable`/`proveFresh`/`acquire`/`release` are overridden;
/// `LeaseAllocation.startOrAdopt` (`sdk/lease.dart:148`) itself is untouched,
/// so daemon-only adopt + no-adopt-on-faith fall out for free.
class _VendedProcessLease extends LeaseCapability<ProcessHandle> {
  const _VendedProcessLease({
    required this.request,
    required this.writer,
    required this.spawn,
    required this.dispatch,
    required this.metadataOf,
    required this.liveness,
  });

  final ProcessLeaseRequest request;
  final StationBeadWriter writer;
  final ProcessSpawner spawn;
  final ProcessDispatcher dispatch;
  final StepMetadataReader metadataOf;
  final AllocationLiveness liveness;

  String get stepBeadId => request.stepBeadId;

  /// Reads the vendor-owned breadcrumb off THIS step bead. Only ever consulted
  /// by `LeaseAllocation` for a daemon (`isAdoptable`, `sdk/lease.dart`) — a
  /// job's `startOrAdopt` never calls this.
  @override
  Future<LeaseBound<ProcessHandle>?> adoptable(
    TreeContext context,
    StepArgs args,
  ) async {
    final metadata = await metadataOf(stepBeadId);
    if (metadata == null) return null;
    final handle = leaseBreadcrumbOf(metadata);
    return handle == null ? null : LeaseBound(handle);
  }

  /// The pgid-alive proof — no-adopt-on-faith's engine-side half. The
  /// domain-specific "token echoed over its endpoint" half [LeaseCapability]
  /// leaves to a subclass has no analogue here: [ProcessHandle.token] is
  /// PROVEN by the SAME pgid-liveness call (a live process group under this
  /// pgid+pid pair could only be the one that echoed back this token when it
  /// was leased, since a fresh spawn always mints a fresh token) rather than a
  /// second round-trip — [liveness] is the whole proof.
  @override
  Future<bool> proveFresh(
    ProcessHandle handle,
    TreeContext context,
    StepArgs args,
  ) async => liveness(
    AdoptFence(pgid: handle.pgid, pid: handle.pid, token: handle.token),
  );

  /// Spawns fresh + writes the breadcrumb — the ONLY write of `grid.lease.*`
  /// this lease issues (adopt never re-persists; it reattaches what is already
  /// there).
  @override
  Future<LeaseResolution<ProcessHandle>> acquire(
    TreeContext context,
    StepArgs args,
  ) async {
    final handle = await spawn(request, context, args);
    // OUT OF THE CRITICAL SECTION (tg-uad D3): the breadcrumb serves RESTART
    // ADOPTION + the restart SWEEP, not the live path — persist it
    // CONCURRENTLY with dispatch instead of awaiting it between spawn and
    // dispatch, where its chokepoint queue latency under unrelated station
    // write load WAS the unobserved-terminal window a fast-exiting lane died
    // inside. Failing a LIVE dispatch over a persistence blip would be
    // strictly worse — but a blip must not be silently forfeited either: a
    // breadcrumb that never lands doesn't just forfeit adoption, it blinds
    // `sweepOrphanedLeases` to this incarnation entirely (an absent
    // breadcrumb reads as "nothing is leased"), so a crash while the process
    // was still alive would leave a live orphan the sweep could never find
    // or kill. [_persistBreadcrumb] therefore RETRIES the write (backoff)
    // until it lands, for as long as the incarnation is live and its lease
    // still held; and the sweep reports LOUD on the residual shape (a
    // spawned step with no lease keys at all). Errors are contained inside
    // the helper (an unhandled rejection here would be a zone error,
    // tg-7ux). Ordering vs release stays safe: the chokepoint serializes per
    // bead id, and every (re)attempt is gated tap-open-then-enqueue
    // synchronously, while release closes the tap BEFORE it enqueues its
    // clearing write — so no retry can ever land after the clear.
    unawaited(_persistBreadcrumb(handle));
    return LeaseBound(handle);
  }

  /// The concurrent breadcrumb persist for [acquire] — retries a failed
  /// write with [_breadcrumbRetryDelay] backoff until it lands, the
  /// incarnation's lease ends ([ProcessEventTap.isClosed] — release owns the
  /// record from there), or the incarnation itself is gone from the
  /// transport (nothing would survive to a restart sweep). Never throws.
  ///
  /// A tap-less handle (a test-minted literal; the production spawner always
  /// taps) has no lease-lifetime signal to gate an open-ended retry on, so
  /// it gets the single attempt — the sweep's missing-breadcrumb report is
  /// the backstop.
  Future<void> _persistBreadcrumb(ProcessHandle handle) async {
    final tap = handle.events;
    final transport = request.allocation.transport;
    final name = request.allocation.address.providerName;
    for (var attempt = 1; ; attempt += 1) {
      // Gate CHECK-THEN-ENQUEUE synchronously (no await between): a tap that
      // is still open here proves release has not yet enqueued its clearing
      // write (it closes the tap first), so this attempt serializes AHEAD of
      // any clear at the per-bead chokepoint — a stale breadcrumb can never
      // overwrite a cleared one.
      if (tap != null && tap.isClosed) return;
      try {
        await writer.update(stepBeadId, metadata: leaseBreadcrumb(handle));
        return;
      } on Object {
        // This attempt dropped — decide whether the retry is still owed.
      }
      if (tap == null) return;
      if (!transport.isRunning(name)) return;
      await Future<void>.delayed(_breadcrumbRetryDelay(attempt));
    }
  }

  @override
  Future<StepOutcome> dispatchOn(
    ProcessHandle handle,
    TreeContext context,
    StepArgs args,
  ) => dispatch(handle, request, context, args);

  /// Frees the SLOT — which for a process lease is the running GROUP plus the
  /// durable breadcrumb: stop the spawned group at the request's transport
  /// (dispose == RELEASE, the kill floor, ADR-0009 D4 — mirrors
  /// `ProcessAllocation.dispose`'s own `transport.stop`; best-effort, a
  /// stop of a never-started/already-reaped name must not break release),
  /// then clear the breadcrumb. Idempotent: the write is the SAME
  /// [kClearedLeaseKeys] payload every time, so a repeated release (the
  /// carrier's own idempotency contract, `sdk/lease.dart`) merges to the exact
  /// same cleared state rather than erroring or double-writing anything new.
  @override
  Future<void> release(ProcessHandle handle) async {
    // The per-incarnation event tap dies with the lease (idempotent — the
    // dispatcher normally closed it already; this covers an acquired handle
    // whose dispatch never ran, e.g. a dispose racing the acquire).
    await handle.events?.close();
    try {
      await request.allocation.transport.stop(
        request.allocation.address.providerName,
      );
    } on Object {
      // Best-effort: an unreachable/already-stopped group never breaks release.
    }
    await writer.update(stepBeadId, metadata: kClearedLeaseKeys);
  }
}

/// The EXPLICITLY-NAMED degraded fallback (Decided item 5): no writer, no
/// metadata read, no breadcrumb — so no adopt is EVER possible (every mount
/// spawns fresh), exactly today's flat-model respawn-or-skip behavior, just
/// expressed through the lease family's shape instead of a `NodeCursor`
/// field. A live station must choose this ON PURPOSE by mounting it — it is
/// never substituted automatically anywhere in this file;
/// [requireProcessLeaseVendor] throws rather than reaching for it.
class SelfManagedProcessVendor implements ProcessLeaseVendor {
  /// Creates the degraded vendor over just the two collaborators it still
  /// needs to do real work (spawn + run) — no [StationBeadWriter], no
  /// [StepMetadataReader]: there is nothing durable for either to touch.
  const SelfManagedProcessVendor({required this.spawn, required this.dispatch});

  /// Mints a fresh handle on every acquire (there is never a prior to adopt).
  final ProcessSpawner spawn;

  /// Runs the work on the freshly-bound handle.
  final ProcessDispatcher dispatch;

  @override
  LeaseCapability<ProcessHandle> leaseFor(ProcessLeaseRequest request) =>
      _SelfManagedProcessLease(
        request: request,
        spawn: spawn,
        dispatch: dispatch,
      );

  /// The degraded sweep — a NO-OP by construction: this vendor persists no
  /// breadcrumb, so there is no durable lease identity to interpret, no group
  /// it could prove orphaned, and nothing to clear. (Any `grid.lease.*`
  /// residue a PRIOR station-vendor incarnation left is not this vendor's to
  /// interpret — its whole contract is "no durable identity", and killing on
  /// another vendor's record would be adopt-on-faith's destructive twin.)
  /// Candidates are accepted and ignored so a composer can swap vendors
  /// without re-wiring the caller.
  @override
  Future<List<SweptLeaseGroup>> sweepOrphanedLeases({
    required Iterable<LeaseSweepCandidate> candidates,
    required LeaseGroupLiveness alive,
    required LeaseGroupTerminator terminate,
    required void Function(String message) onOrphan,
  }) async => const <SweptLeaseGroup>[];
}

/// The self-managed lease: [adoptable] is left at [LeaseCapability]'s own
/// default (always null — never adopt), which IS this vendor's whole degraded
/// story. `release` stops the spawned group (dispose == RELEASE, the kill
/// floor — no durable identity does not mean a leaked process) but persists
/// nothing: there was never a breadcrumb to clear.
class _SelfManagedProcessLease extends LeaseCapability<ProcessHandle> {
  const _SelfManagedProcessLease({
    required this.request,
    required this.spawn,
    required this.dispatch,
  });

  final ProcessLeaseRequest request;
  final ProcessSpawner spawn;
  final ProcessDispatcher dispatch;

  @override
  Future<LeaseResolution<ProcessHandle>> acquire(
    TreeContext context,
    StepArgs args,
  ) async => LeaseBound(await spawn(request, context, args));

  @override
  Future<StepOutcome> dispatchOn(
    ProcessHandle handle,
    TreeContext context,
    StepArgs args,
  ) => dispatch(handle, request, context, args);

  @override
  Future<void> release(ProcessHandle handle) async {
    // Mirrors _VendedProcessLease.release: the incarnation tap dies with the
    // lease (idempotent).
    await handle.events?.close();
    try {
      await request.allocation.transport.stop(
        request.allocation.address.providerName,
      );
    } on Object {
      // Best-effort: an unreachable/already-stopped group never breaks release.
    }
  }
}
