/// The REAL process transport behind [StationProcessLeaseVendor] (tg-h4u —
/// the A53 follow-up rung): [stationProcessSpawner] + [stationProcessDispatcher]
/// wrap the SAME `RuntimeProvider` machinery `ProcessAllocation` drives on the
/// flat path into the vendor's request-carrying [ProcessSpawner]/
/// [ProcessDispatcher] typedefs, and [defaultProcessLeaseVendor] composes the
/// production vendor over [StationServices] (the kernel-root provision).
///
/// The reader half of the vendor's collaborators —
/// `StationBeadWriter.metadataOf` — lives in grid_runtime: together these are
/// exactly the `grid_engine ──► grid_runtime` "subprocess/git/chokepoint
/// transport" edge **ADR-0002 Decision 1** names (an ALLOWED dependency
/// direction, not a new seam).
///
/// **What is deliberately NOT replicated here (yet):** the flat path's
/// COMPLETION FENCE (`ProcessAllocation`'s no-complete-on-faith proof of an
/// INFERRED exit). Molecule mode is inert until a composition sets
/// `circuitMintMode: molecule` (the live arm, tg-6gi); arming that fence on
/// the leased path is scoped to the live arm, where the work-signal probe is
/// actually wired. The dispatcher takes the capability's event interpretation
/// at face value — exactly the flat path's behavior when no probe is bound.
library;

import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../kernel/station_services.dart';
import '../sdk/allocation.dart';
import '../sdk/capability.dart';
import 'process_lease_vendor.dart';

/// The REAL [ProcessSpawner]: provisions the workspace (idempotent, mirrors
/// `ProcessAllocation.startOrAdopt`), spawns the request's capability config
/// over the request's transport, surfaces `AllocationStarted` through the
/// request's sink (so the host persists `state=running` on the step bead —
/// the SAME report shape the flat path's event subscription produces), and
/// resolves the minted [ProcessHandle] from the spawn's `SessionStarted`
/// pgid/pid + the env overlay's freshness token.
///
/// Fails LOUD (a thrown error) when the process dies or exits before
/// `SessionStarted` — `LeaseAllocation` contains the throw as a supervised
/// `acquire threw` failure (ADR-0008 Decision 10, per-work fail-closed).
Future<ProcessHandle> stationProcessSpawner(
  ProcessLeaseRequest request,
  TreeContext context,
  StepArgs args,
) async {
  final ctx = request.allocation;
  final name = ctx.address.providerName;
  final token = ctx.env['GRID_INSTANCE_TOKEN'] ?? '';
  final started = Completer<ProcessHandle>();
  final sub = ctx.transport.events.where((e) => e.name == name).listen((e) {
    if (started.isCompleted) return;
    switch (e) {
      case SessionStarted(:final pid, :final pgid):
        // Surface the start through the host's sink FIRST (the host persists
        // `state=running`; the vendor — not the cursor — owns pgid/pid/token,
        // which land on `grid.lease.*` right after acquire returns).
        ctx.sink(AllocationStarted(pid: pid, pgid: pgid));
        started.complete(
          ProcessHandle(pgid: pgid ?? pid, pid: pid, token: token),
        );
      case Died():
        started.completeError(
          StateError('process died before SessionStarted ($name)'),
        );
      case Exited(:final exitCode):
        started.completeError(
          StateError(
            'process exited (code $exitCode) before SessionStarted ($name)',
          ),
        );
      default:
        break;
    }
  });
  try {
    // Materialize the workspace BEFORE spawning into it (idempotent; the
    // effect owns provisioning — ADR-0008 D5). Mirrors ProcessAllocation.
    final services =
        context.getInheritedSeedOfExactType<ServiceBundle>() ??
        const ServiceBundle();
    final workspace = context.getInheritedSeedOfExactType<Workspace>();
    final sc = services.sourceControl;
    if (sc != null && workspace != null) {
      await sc.provisionWorkspace(
        beadId: args.beadId,
        workspaceDir: workspace.workspaceDir,
      );
      assertProvisionedCheckout(workspace.workspaceDir);
    }
    if (args.cancel.isCancelled) {
      throw StateError('cancelled before spawn ($name)');
    }
    final base = request.capability.spawn(context, args);
    final config = base.copyWith(env: {...base.env, ...ctx.env});
    try {
      await ctx.transport.start(name, config);
    } on SessionAlreadyExists {
      // A re-fired ready event raced the spawn — fine (the group is up); the
      // SessionStarted event still resolves the handle below.
    }
    return await started.future;
  } finally {
    unawaited(sub.cancel());
  }
}

/// The REAL [ProcessDispatcher]: waits on the SAME process's `RuntimeProvider`
/// events (the wait-for-a-further-event shape) and interprets the FIRST
/// non-`none` signal through the request capability's own `interpretEvent` —
/// `ready` for a daemon's up-signal, `complete` (with the capability's result
/// payload) for a job's clean exit, `failed` for a crash. Never returns on
/// `none`; `LeaseAllocation`'s dispose unwinds a cancelled wait via release.
Future<StepOutcome> stationProcessDispatcher(
  ProcessHandle handle,
  ProcessLeaseRequest request,
  TreeContext context,
  StepArgs args,
) async {
  final ctx = request.allocation;
  final name = ctx.address.providerName;
  final signalled = Completer<StepSignal>();
  final sub = ctx.transport.events.where((e) => e.name == name).listen((e) {
    if (signalled.isCompleted) return;
    final signal = request.capability.interpretEvent(e);
    if (signal != StepSignal.none) signalled.complete(signal);
  });
  try {
    final signal = await signalled.future;
    switch (signal) {
      case StepSignal.none:
        // Unreachable (the listener never completes on none) — but the switch
        // stays exhaustive (house style) and honest.
        return const Failed('dispatch resolved without a signal');
      case StepSignal.ready:
        return const Ok();
      case StepSignal.complete:
        if (args.cancel.isCancelled) return const Ok();
        try {
          return Ok(await request.capability.result(context, args));
        } on Object catch (e) {
          // A completion whose result cannot be read must not advance the
          // circuit silently (mirrors ProcessAllocation._reportComplete).
          return Failed('result threw: $e');
        }
      case StepSignal.failed:
        return const Failed('the spawned process failed');
    }
  } finally {
    unawaited(sub.cancel());
  }
}

/// The production [ProcessLeaseVendor] over [services] — the kernel-root
/// provision (tg-h4u): the chokepoint writer as the sole `grid.lease.*`
/// writer, [stationProcessSpawner]/[stationProcessDispatcher] as the process
/// transport, `StationBeadWriter.metadataOf` as the breadcrumb reader
/// (ADR-0002 Decision 1's named `grid_engine ──► grid_runtime` edge), and the
/// station's adopt-liveness seam (absent ⇒ [neverLive] ⇒ never adopt —
/// no-adopt-on-faith's offline posture, co-wired with the reconciler's
/// `AdoptProof` at the live arm).
StationProcessLeaseVendor defaultProcessLeaseVendor(StationServices services) =>
    StationProcessLeaseVendor(
      writer: services.writer,
      spawn: stationProcessSpawner,
      dispatch: stationProcessDispatcher,
      metadataOf: services.writer.metadataOf,
      liveness: services.liveness ?? neverLive,
    );
