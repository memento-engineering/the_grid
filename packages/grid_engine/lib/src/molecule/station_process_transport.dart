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
/// The leased dispatcher uses the SAME work-signal probe as `ProcessAllocation`
/// for [CompletionContract.committedWorkspace] capabilities, with the SAME A49
/// scope: only an `Exited(inferred: true)` event that the capability interprets
/// as [StepSignal.complete] is proven before the circuit advances. An observed
/// exit code is already evidence and is not fenced.
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
///
/// **One subscription per incarnation (tg-uad D1).** The spawner opens a
/// buffered [ProcessEventTap] BEFORE `transport.start` and hands it to the
/// dispatcher through [ProcessHandle.events] — the single subscription
/// spanning acquire→dispatch, mirroring `ProcessAllocation`'s
/// subscribe-once-before-start shape. The spawner's own handle-resolution
/// listener below is separate plumbing; cancelling it at return no longer
/// disconnects the live path, because every event since the tap opened —
/// including a terminal that fires inside the acquire→dispatch window — sits
/// buffered in the tap.
Future<ProcessHandle> stationProcessSpawner(
  ProcessLeaseRequest request,
  TreeContext context,
  StepArgs args, {
  Duration reservationDeadline = const Duration(seconds: 15),
  Duration reservationPollPeriod = const Duration(milliseconds: 50),
}) async {
  final ctx = request.allocation;
  final name = ctx.address.providerName;
  final token = ctx.env['GRID_INSTANCE_TOKEN'] ?? '';
  final tap = ProcessEventTap.open(ctx.transport.events, name);
  final started = Completer<ProcessHandle>();
  ProcessHandle mint({required int pid, int? pgid}) =>
      ProcessHandle(pgid: pgid ?? pid, pid: pid, token: token, events: tap);
  final sub = ctx.transport.events.where((e) => e.name == name).listen((e) {
    if (started.isCompleted) return;
    switch (e) {
      case SessionStarted(:final pid, :final pgid):
        // Surface the start through the host's sink FIRST (the host persists
        // `state=running`; the vendor — not the cursor — owns pgid/pid/token,
        // which land on `grid.lease.*` right after acquire returns).
        ctx.sink(AllocationStarted(pid: pid, pgid: pgid));
        started.complete(mint(pid: pid, pgid: pgid));
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
  var handedOff = false;
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
      // A duplicate acquire raced an EXISTING incarnation of this name (a
      // re-fired ready event). What happens next depends on how far the
      // original got — resolve from the transport's SYNCHRONOUS surfaces
      // (tg-090/D5: for a session that already stamped its identity,
      // `SessionStarted` fired before this incarnation subscribed and will
      // NEVER re-fire — waiting on it hung acquire forever, unbounded and
      // silent):
      //  - a stamped identity ⇒ the session is LIVE: bind it synchronously;
      //  - a retained terminal ⇒ the incarnation is OVER: fail LOUD (the
      //    frontier respawns fresh);
      //  - neither, but the transport still HOLDS the name ⇒ the original
      //    spawn is IN FLIGHT (the name is reserved synchronously; pid is
      //    stamped only when the spawn lands): its `SessionStarted` has NOT
      //    fired yet and WILL reach this incarnation's already-open
      //    subscription — WAIT for it (the race the pre-D5 code correctly
      //    tolerated; tg-090 repair round 1), bounded by
      //    [reservationDeadline] and polled every [reservationPollPeriod]
      //    so a spawn that fails (the reservation vanishes with no event)
      //    or a transport that can never stamp an identity still fails
      //    LOUD, never an unbounded silent wait (the D5 posture, kept);
      //  - the name is not even held ⇒ fail LOUD immediately.
      if (!started.isCompleted) {
        _resolveAlreadyExisting(
          ctx,
          name,
          started,
          mint,
          deadline: reservationDeadline,
          pollPeriod: reservationPollPeriod,
        );
      }
    }
    final handle = await started.future;
    handedOff = true;
    return handle;
  } finally {
    // Only the spawner's own resolution listener is cancelled — NEVER the
    // incarnation tap, which the dispatcher (or the lease release) consumes
    // and closes. On a failed acquire nothing will ever consume the tap, so
    // it is closed here.
    unawaited(sub.cancel());
    if (!handedOff) unawaited(tap.close());
  }
}

/// Resolves a `SessionAlreadyExists` acquire from the transport's synchronous
/// surfaces — the decision table is at the call site in
/// [stationProcessSpawner]. Completes [started] exactly once: both this
/// resolution and the spawner's own event listener guard on `isCompleted`,
/// and every check-then-complete below is a synchronous block (no interleave
/// is possible between a passed guard and its completion).
void _resolveAlreadyExisting(
  AllocationContext ctx,
  String name,
  Completer<ProcessHandle> started,
  ProcessHandle Function({required int pid, int? pgid}) mint, {
  required Duration deadline,
  required Duration pollPeriod,
}) {
  final identity = ctx.transport.identityOf(name);
  if (identity != null) {
    // Still LIVE: surface running + mint the handle synchronously.
    ctx.sink(AllocationStarted(pid: identity.pid, pgid: identity.pgid));
    started.complete(mint(pid: identity.pid, pgid: identity.pgid));
    return;
  }
  final terminal = ctx.transport.terminalOf(name);
  if (terminal != null) {
    // Already DEAD: its retained terminal proves the incarnation is over —
    // an acquire cannot bind it, so fail LOUD and let the frontier respawn
    // fresh.
    started.completeError(
      StateError(
        'session "$name" already existed and already ended '
        '($terminal) — acquire cannot bind a dead incarnation',
      ),
    );
    return;
  }
  if (!ctx.transport.isRunning(name)) {
    started.completeError(
      StateError(
        'session "$name" reported SessionAlreadyExists but the transport '
        'holds neither a live identity, nor a retained terminal, nor even '
        'the reservation — failing acquire LOUD rather than waiting on a '
        'SessionStarted that will never re-fire',
      ),
    );
    return;
  }
  // MID-SPAWN (tg-090 repair round 1): the name is reserved but no identity
  // is stamped yet — the original spawn is in flight, and this incarnation's
  // subscription (opened before its own `start`) will receive the
  // `SessionStarted` when it lands. Wait for it, and poll the synchronous
  // surfaces so every way the wait could otherwise dangle resolves LOUD:
  // the reservation vanishing without an event (the in-flight spawn threw),
  // a terminal latching first, or the deadline closing (a transport that
  // never stamps an identity for a held name — e.g. a dry-run duplicate).
  unawaited(() async {
    final clock = Stopwatch()..start();
    while (!started.isCompleted) {
      await Future<void>.delayed(pollPeriod);
      if (started.isCompleted) return;
      final identity = ctx.transport.identityOf(name);
      if (identity != null) {
        // The spawn landed but our listener lost the wake-up race — bind
        // from state (belt-and-braces; normally the listener wins).
        ctx.sink(AllocationStarted(pid: identity.pid, pgid: identity.pgid));
        started.complete(mint(pid: identity.pid, pgid: identity.pgid));
        return;
      }
      final terminal = ctx.transport.terminalOf(name);
      if (terminal != null) {
        started.completeError(
          StateError(
            'session "$name" already existed and ended mid-acquire '
            '($terminal) — acquire cannot bind a dead incarnation',
          ),
        );
        return;
      }
      if (!ctx.transport.isRunning(name)) {
        started.completeError(
          StateError(
            'session "$name" was reserved mid-spawn when this duplicate '
            'acquire raced it, but the reservation vanished without an '
            'event — the in-flight spawn failed; failing this acquire LOUD '
            'so the frontier respawns fresh',
          ),
        );
        return;
      }
      if (clock.elapsed >= deadline) {
        started.completeError(
          StateError(
            'session "$name" reported SessionAlreadyExists and still holds '
            'the name, but stamped neither an identity nor a terminal '
            'within $deadline — a transport that can never stamp one, or a '
            'wedged spawn; failing acquire LOUD rather than waiting '
            'forever',
          ),
        );
        return;
      }
    }
  }());
}

/// The REAL [ProcessDispatcher]: CHECK-THEN-SUBSCRIBE (tg-uad D1/D2 — the
/// standard state-then-stream pattern). It consults the transport's RETAINED
/// terminal first: a terminal that fired between acquire and this dispatch
/// (the breadcrumb-write window) reached zero listeners on the unbuffered
/// broadcast stream, but it is held STATE now, not a lost instant — so a late
/// dispatcher settles instead of deadlocking (and the watchdog cancelled at
/// that emit is harmless). Otherwise it waits on the incarnation's buffered
/// [ProcessEventTap] (opened by the spawner BEFORE `transport.start`; a
/// tap-less handle falls back to a fresh subscription) and interprets the
/// FIRST non-`none` signal through the request capability's own
/// `interpretEvent` — `ready` for a daemon's up-signal, `complete` (with the
/// capability's result payload) for a job's clean exit, `failed` for a crash.
/// Never returns on `none`; `LeaseAllocation`'s dispose unwinds a cancelled
/// wait via release.
Future<StepOutcome> stationProcessDispatcher(
  ProcessHandle handle,
  ProcessLeaseRequest request,
  TreeContext context,
  StepArgs args,
) async {
  final ctx = request.allocation;
  final name = ctx.address.providerName;

  // STATE first: the retained terminal (RuntimeProvider.terminalOf).
  ({StepSignal signal, RuntimeEvent event})? resolved;
  final held = ctx.transport.terminalOf(name);
  if (held != null) {
    final signal = request.capability.interpretEvent(held);
    if (signal != StepSignal.none) {
      resolved = (signal: signal, event: held);
      // The incarnation is over; nothing further arrives on the tap.
      unawaited(handle.events?.close());
    }
  }

  // STREAM second: the incarnation tap (buffered across the acquire→dispatch
  // window), or a fresh subscription for a tap-less handle.
  if (resolved == null) {
    final source =
        handle.events?.stream ??
        ctx.transport.events.where((e) => e.name == name);
    final signalled = Completer<({StepSignal signal, RuntimeEvent event})>();
    final sub = source.listen((e) {
      if (signalled.isCompleted) return;
      final signal = request.capability.interpretEvent(e);
      if (signal != StepSignal.none) {
        signalled.complete((signal: signal, event: e));
      }
    });
    try {
      resolved = await signalled.future;
    } finally {
      unawaited(sub.cancel());
      unawaited(handle.events?.close());
    }
  }

  switch (resolved.signal) {
    case StepSignal.none:
      // Unreachable (neither path resolves on none) — but the switch stays
      // exhaustive (house style) and honest.
      return const Failed('dispatch resolved without a signal');
    case StepSignal.ready:
      return const Ok();
    case StepSignal.complete:
      if (args.cancel.isCancelled) return const Ok();
      if (_mustFenceLeasedCompletion(request.capability, resolved.event)) {
        final signal = await _probeLeasedWorkSignal(context, ctx);
        switch (signal) {
          case GateOutcome.clear:
            break;
          case GateOutcome.present:
            return const Failed('interrupted: uncommitted work remains');
          case GateOutcome.probeError:
            return const Failed('interrupted: work-signal probe failed');
        }
      }
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
}

bool _mustFenceLeasedCompletion(
  ProcessCapability capability,
  RuntimeEvent event,
) {
  if (capability.completionContract != CompletionContract.committedWorkspace) {
    return false;
  }
  return event is Exited && event.inferred;
}

Future<GateOutcome> _probeLeasedWorkSignal(
  TreeContext context,
  AllocationContext ctx,
) {
  final services =
      context.getInheritedSeedOfExactType<ServiceBundle>() ??
      const ServiceBundle();
  final workspace = context.getInheritedSeedOfExactType<Workspace>();
  if (services.sourceControl == null || workspace == null) {
    return Future<GateOutcome>.value(GateOutcome.clear);
  }
  return ctx
      .workSignal(workspace.workspaceDir)
      .timeout(ctx.workSignalTimeout, onTimeout: () => GateOutcome.probeError);
}

/// The production [ProcessLeaseVendor] over [services] — the kernel-root
/// provision (tg-h4u): the chokepoint writer as the sole `grid.lease.*`
/// writer, [stationProcessSpawner]/[stationProcessDispatcher] as the process
/// transport, `StationBeadWriter.metadataOf` as the breadcrumb reader
/// (ADR-0002 Decision 1's named `grid_engine ──► grid_runtime` edge), and the
/// station's adopt-liveness seam (absent ⇒ [neverLive] ⇒ never adopt —
/// no-adopt-on-faith's offline posture, co-wired with the reconciler's
/// `AdoptProof` at the live arm). The crash-restart lease sweep does NOT ride
/// this seam: its kill gate is the caller-bound [LeaseGroupLiveness] the
/// reconciler binds to its own real controller, so leaving adoption unarmed
/// never blinds the sweep.
StationProcessLeaseVendor defaultProcessLeaseVendor(StationServices services) =>
    StationProcessLeaseVendor(
      writer: services.writer,
      spawn: stationProcessSpawner,
      dispatch: stationProcessDispatcher,
      metadataOf: services.writer.metadataOf,
      liveness: services.liveness ?? neverLive,
    );
