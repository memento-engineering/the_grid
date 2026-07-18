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

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../sdk/allocation.dart';
import '../sdk/capability.dart';
import '../sdk/lease.dart';
import 'molecule_schema.dart';

/// A leased process's identity — `pgid`/`pid`/`token` as the OPAQUE handle
/// type `H` a [LeaseCapability<ProcessHandle>] acquires/adopts/releases
/// (Decided item 5). Never written to a [NodeCursor] on the molecule path;
/// only ever carried as this lease family's handle, or encoded into the
/// [LeaseKeys] breadcrumb by [leaseBreadcrumb].
class ProcessHandle {
  /// Creates the handle from a spawned process's [pgid]/[pid] plus the
  /// engine-minted freshness [token] (the SAME three-part identity
  /// [AdoptFence] carries for the flat model's `ProcessAllocation`).
  const ProcessHandle({
    required this.pgid,
    required this.pid,
    required this.token,
  });

  /// The spawned process-group id (the respawn/liveness kill target).
  final int pgid;

  /// The spawned leader pid.
  final int pid;

  /// The engine-minted freshness token a live effect must echo back to be
  /// proven (the domain-specific half of no-adopt-on-faith; the pgid-alive
  /// half is [AllocationLiveness]).
  final String token;

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
    await writer.update(stepBeadId, metadata: leaseBreadcrumb(handle));
    return LeaseBound(handle);
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
    try {
      await request.allocation.transport.stop(
        request.allocation.address.providerName,
      );
    } on Object {
      // Best-effort: an unreachable/already-stopped group never breaks release.
    }
  }
}
