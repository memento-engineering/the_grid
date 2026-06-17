import 'dart:async';

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart' show PerBeadQueue;

import '../git/grid_git_service.dart';
import '../lifecycle/bead_ownership.dart';
import '../lifecycle/runtime_actuator.dart';
import '../runtime/runtime_config.dart';
import '../runtime/runtime_provider.dart';
import 'ready_work_source.dart';

/// One spawned dispatch — the in-memory record the interactor keeps per work
/// bead so a re-fired ready event is idempotent and the exit path can find the
/// worktree to reap. Plain value type.
class DispatchRecord {
  DispatchRecord({
    required this.workBeadId,
    required this.sessionBeadId,
    required this.worktree,
  });

  /// The ready work bead this dispatch serves.
  final String workBeadId;

  /// The the_grid-owned session bead minted for it (the runtime session name).
  final String sessionBeadId;

  /// The provisioned per-bead worktree (the reap target on exit).
  final BeadWorktree worktree;
}

/// The dispatcher's second-consumer attach point (M3 Track 5; ADR-0006
/// Decision 1; ADR-0000 A32): a ready work bead → an agent spawned in a
/// worktree, tracked as a session bead.
///
/// **It attaches as a SECOND consumer of the same observable surface M2 uses**
/// (a [ReadyWorkSource] over grid_controller's `GraphEvent` stream +
/// `readyBeads`), and it does **NOT** go through reduce→gate→actuate — the M2
/// `ReconcilerRuntime` owns that path for convergence beads; this is the
/// dispatch path for plain ready work beads.
///
/// **The ownership gate is the Track-4 [BeadOwnershipPredicate]**, seeded with
/// the shared `{tgdog}` allow-set (ADR-0000 A32/A35). A non-owned bead is
/// **observed read-only, NEVER dispatched** — `OwnsRigs.owns(Convergence)`
/// is structurally uncallable on a plain `Bead`, so this bead-shaped predicate
/// is the gate, sharing the identical `Set<String>` with M2's actuator so they
/// cannot drift.
///
/// **On accept** (the pipeline; **Futures for acts**):
///  1. [GridGitService.provisionWorktree] (Track 3) — the per-bead worktree on
///     a fresh `grid/<beadId>` branch off the probed default;
///  2. [RuntimeProvider.start] (Track 2) — a `claude` subprocess in that
///     worktree, env via the explicit allowlist (token never argv);
///  3. [RuntimeActuator.spawnSession] (Track 4) — the session bead minted +
///     stamped through the [GridBeadWriter] chokepoint.
///
/// **Idempotent + single-flight per bead.** A re-fired ready event for an
/// already-dispatched (or in-flight) bead never double-spawns: a [PerBeadQueue]
/// serializes per work-bead id (mirrors the M2 runtime), and an
/// already-dispatched record short-circuits inside the critical section. So the
/// id round-trip is exactly-once even under a re-fire that races the first
/// spawn.
///
/// **On exit / crash** (the supervision half): the interactor listens to the
/// actuator's [CrashDecision] stream. A clean park / quarantine drives the
/// removal TRIGGER — the lifecycle bead is closed AND, once the branch is
/// pushed (`HasUnpushedCommits==false`), [GridGitService.reap] removes the
/// worktree behind the three fail-closed gates. A [RestartSession] re-spawns
/// the same bead (the actuator already left the session bead open). A
/// [QuarantineSession] leaves it parked — no reap, no respawn.
///
/// **CUT (M4): the demand-spawned pool / backpressure beyond [maxInFlight].**
/// M3 enforces only a simple max-in-flight cap; the full pool is M4.
class DispatchInteractor {
  DispatchInteractor({
    required ReadyWorkSource source,
    required BeadOwnershipPredicate ownership,
    required GridGitService git,
    required RootCheckout root,
    required RuntimeProvider provider,
    required RuntimeActuator actuator,
    required RuntimeConfig Function(DispatchRequest request) configBuilder,
    int maxInFlight = 8,
    bool dryRun = false,
    Set<String> driveList = const {},
    String? sessionRig,
    void Function(String message)? onObserve,
    void Function(Object error, StackTrace stack)? onError,
  }) : assert(maxInFlight >= 1, 'maxInFlight must be >= 1'),
       _source = source,
       _ownership = ownership,
       _git = git,
       _root = root,
       _provider = provider,
       _actuator = actuator,
       _configBuilder = configBuilder,
       _maxInFlight = maxInFlight,
       _dryRun = dryRun,
       _driveList = driveList,
       _sessionRig = sessionRig,
       _onObserve = onObserve,
       _onError = onError;

  final ReadyWorkSource _source;
  final BeadOwnershipPredicate _ownership;
  final GridGitService _git;
  final RootCheckout _root;
  final RuntimeProvider _provider;
  final RuntimeActuator _actuator;
  final RuntimeConfig Function(DispatchRequest) _configBuilder;
  final int _maxInFlight;
  final bool _dryRun;

  /// The operational drive-list — an OPTIONAL second, narrower selector layered
  /// **on top of** [_ownership] (ADR-0000 A36). Ownership answers "may I touch
  /// this?" (the security/coexistence invariant); the drive-list answers "which
  /// owned beads do I drive in this run?". When **empty** it imposes no filter
  /// (the prefix allow-set scopes on its own — the original `tgdog` posture).
  /// When **non-empty**, a bead must be **both owned AND listed** to dispatch —
  /// the mechanical embodiment of ADR-0006/A35's "bless the 2 specific work
  /// beads" gate, needed for the genesis arm where `{genesis}` owns the whole
  /// repo prefix. Fail-safe: an owned-but-unlisted bead is observed read-only.
  final Set<String> _driveList;

  /// The owned partition the SESSION beads are minted into, when the_grid's
  /// lifecycle state lives in a different store than the work it reads (A36
  /// choice B — split read/write). Null = sessions share the work bead's rig
  /// (the single-DB arm). See [_dispatch].
  final String? _sessionRig;
  final void Function(String message)? _onObserve;
  final void Function(Object, StackTrace)? _onError;

  /// Per-work-bead serialization — the single-flight mutex (mirror the M2
  /// runtime's `PerBeadQueue`). Tasks for the SAME work bead run strictly in
  /// arrival order; different beads proceed concurrently.
  final PerBeadQueue _queue = PerBeadQueue();

  /// The live dispatch records keyed by **work** bead id (idempotency: a
  /// re-fired ready event for a present key short-circuits).
  final Map<String, DispatchRecord> _dispatched = {};

  /// The live dispatch records keyed by **session** bead id (the exit path
  /// resolves a `CrashDecision.sessionBeadId` back to its worktree).
  final Map<String, DispatchRecord> _bySession = {};

  /// Work-bead ids whose dispatch slot is RESERVED (the cap + idempotency are
  /// counted over this set, updated synchronously before any await so a
  /// concurrent different-bead consider cannot over-commit the cap). A reserved
  /// id is either in flight or recorded in [_dispatched]; it is cleared when the
  /// session is reaped.
  final Set<String> _reserved = {};

  StreamSubscription<GraphEvent>? _eventSub;
  StreamSubscription<CrashDecision>? _decisionSub;
  bool _started = false;
  bool _disposed = false;

  /// The work beads observed-but-not-dispatched because they are not owned
  /// (read-only observation; for tests/diagnostics). A non-owned bead is NEVER
  /// dispatched and NEVER mutated.
  final Set<String> observedNonOwned = {};

  /// Owned work beads observed-but-not-dispatched because a non-empty
  /// [_driveList] does not list them (read-only; for tests/diagnostics).
  final Set<String> observedOutOfScope = {};

  /// The live dispatch records (read-only view, for tests/diagnostics).
  Map<String, DispatchRecord> get dispatched =>
      Map<String, DispatchRecord>.unmodifiable(_dispatched);

  /// How many sessions are currently in flight (recorded dispatches) — the
  /// quantity the max-in-flight cap is measured against (see [_reserved]).
  int get inFlight => _dispatched.length;

  /// Subscribes the ready-set event stream + the actuator's crash-decision
  /// stream, then reconciles the CURRENT ready set (so a bead already ready at
  /// start is dispatched, not only ones that enter later). Idempotent.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _decisionSub = _actuator.decisions.listen(
      _onDecision,
      onError: _reportError,
    );
    _eventSub = _source.events.listen(_onEvent, onError: _reportError);
    // Reconcile the current ready set — dispatch every owned bead already ready.
    await reconcileReadySet();
  }

  /// Re-scans `readyBeads` and dispatches every owned bead not already in
  /// flight — the start-time reconcile and a manual nudge. Each candidate goes
  /// through the same per-bead single-flight path as an event, so a concurrent
  /// `readySetChanged` for the same bead cannot double-spawn.
  Future<void> reconcileReadySet() async {
    final futures = <Future<void>>[];
    for (final bead in _source.readyBeads) {
      futures.add(_consider(bead.id));
    }
    await Future.wait(futures);
  }

  void _onEvent(GraphEvent event) {
    // Only readySetChanged.entered drives a spawn — the second-consumer filter.
    if (event is! ReadySetChanged) return;
    for (final id in event.entered) {
      unawaited(_consider(id));
    }
  }

  /// Considers one entered/ready work-bead [id] for dispatch — the per-bead
  /// single-flight entry point. Resolves the id to its [Bead], gates on
  /// ownership, and (if owned + under the cap + not already dispatched) runs the
  /// spawn pipeline. All of it inside the per-bead queue so a re-fire is a
  /// no-op once the first spawn has recorded the bead.
  ///
  /// **The cap + reservation are evaluated SYNCHRONOUSLY** — the slot is
  /// reserved ([_reserved]) before the first `await` in the pipeline, so two
  /// DIFFERENT beads (each on its own per-bead queue, dispatched concurrently by
  /// [reconcileReadySet]'s `Future.wait`) cannot both pass the cap and
  /// over-commit. The reservation is released on a failed dispatch so the next
  /// ready event can retry.
  Future<void> _consider(String id) {
    return _queue.run<void>(id, () async {
      if (_disposed) return;
      // Idempotency: already dispatched OR reserved (in flight this turn).
      if (_dispatched.containsKey(id) || _reserved.contains(id)) return;

      final bead = _source.bead(id);
      if (bead == null) return; // gone from the snapshot — nothing to dispatch.

      // The ownership gate — a non-owned bead is observed read-only, NEVER
      // dispatched, NEVER mutated.
      if (!_ownership.owns(bead)) {
        observedNonOwned.add(id);
        _onObserve?.call(
          'observe (not owned, read-only): $id '
          'rig=${_ownership.rigOf(bead) ?? '<none>'}',
        );
        return;
      }

      // The operational drive-list — a SECOND, narrower scope on top of
      // ownership (A36). Empty = no filter; non-empty = only listed beads
      // dispatch. An owned-but-unlisted bead is observed read-only.
      if (_driveList.isNotEmpty && !_driveList.contains(id)) {
        observedOutOfScope.add(id);
        _onObserve?.call('observe (owned, not in drive-list): $id');
        return;
      }

      // The max-in-flight cap (M3's simple backpressure; the full pool is M4).
      // Counted over reservations (synchronous) so concurrent different-bead
      // considers cannot both slip past it before either records.
      if (_reserved.length >= _maxInFlight) {
        _onObserve?.call(
          'defer (max-in-flight $_maxInFlight reached): $id',
        );
        return;
      }

      // Reserve the slot synchronously, BEFORE any await in _dispatch.
      _reserved.add(id);
      try {
        await _dispatch(bead);
      } on Object catch (error, stack) {
        // A failed dispatch releases the reservation so a later ready event can
        // retry, and is REPORTED — never rethrown. One bead's failure (e.g. a
        // bd validation reject or a git error) must not tear down the whole
        // controller: `reconcileReadySet`'s `Future.wait` and `_onEvent`'s
        // `unawaited` both sit upstream, so a rethrow here would crash the live
        // run. Report-and-continue keeps the other ready beads dispatching.
        _reserved.remove(id);
        _reportError(error, stack);
      }
    });
  }

  /// The accept pipeline: provision worktree → provider.start → spawn session
  /// bead through the chokepoint. Runs inside the per-bead queue (so it is
  /// single-flight). On any failure the partial state is unwound conservatively
  /// (no session record is retained), so the next ready event can retry.
  Future<void> _dispatch(Bead bead) async {
    final workRig = _ownership.rigOf(bead);
    if (workRig == null) return; // owns() was true; defensive.
    // The SESSION bead's owned partition. When [_sessionRig] is set (the
    // split-DB arm: session beads live in a separate the_grid-owned store, e.g.
    // `tgdog`, while work is read from another rig like `genesis`), the session
    // bead is minted into that partition — its id prefix and `metadata.rig` are
    // `_sessionRig`, so the chokepoint owns it by prefix across its whole
    // lifecycle (A36 choice B). Default (single-DB tgdog arm): the session
    // shares the work bead's rig.
    final sessionRig = _sessionRig ?? workRig;

    // --dry-run: observe-only, no worktree, no spawn, no writes.
    if (_dryRun) {
      _onObserve?.call('dry-run (would dispatch): ${bead.id} rig=$workRig');
      return;
    }

    // 1. Provision the per-bead worktree (Track 3).
    final worktree = await _git.provisionWorktree(root: _root, beadId: bead.id);

    // Everything after provisioning is wrapped so a post-provision failure (a
    // bd-create reject, a provider spawn failure) leaves NO orphan. Without
    // this, the just-minted worktree/branch survives — the bead can then NEVER
    // re-dispatch (`worktree add` fails "branch exists") — and a half-written
    // `_dispatched`/`_bySession` record wedges the idempotency guard, with the
    // session bead left open. The agent has not started yet (provider.start IS
    // the start), so the worktree is always clean → reap removes it.
    String? sessionBeadId;
    try {
      // 2. Mint the session bead through the chokepoint (Track 4) BEFORE the
      //    spawn, so the runtime session is named by the session bead id and
      //    the actuator's RuntimeEvent ingestion can find its record.
      sessionBeadId = await _actuator.spawnSession(
        rig: sessionRig,
        workBeadId: bead.id,
        title: bead.title.isNotEmpty ? bead.title : 'session for ${bead.id}',
        worktreePath: worktree.path,
        branch: worktree.branch,
      );

      final record = DispatchRecord(
        workBeadId: bead.id,
        sessionBeadId: sessionBeadId,
        worktree: worktree,
      );
      // Record BEFORE the spawn act so a re-fire that races the await is a
      // no-op.
      _dispatched[bead.id] = record;
      _bySession[sessionBeadId] = record;

      // 3. Start the agent subprocess in the worktree (Track 2). The provider
      //    emits SessionStarted, which the actuator (already bound) ingests.
      final config = _configBuilder(
        DispatchRequest(
          // The prompt describes the WORK bead's rig (e.g. genesis) to the
          // agent, not the_grid's internal session partition.
          bead: bead,
          rig: workRig,
          sessionBeadId: sessionBeadId,
          worktree: worktree,
        ),
      );
      await _provider.start(sessionBeadId, config);
    } on Object {
      // Conservative unwind: drop the records, close any minted (orphan)
      // session bead, and reap the clean worktree so a later ready event can
      // re-provision. Then rethrow — `_consider` releases the reservation and
      // reports (it never re-crashes the controller, A37).
      _dispatched.remove(bead.id);
      if (sessionBeadId != null) {
        _bySession.remove(sessionBeadId);
        try {
          await _actuator.closeSession(sessionBeadId, reason: 'spawn failed');
        } on Object {
          // best-effort: the session bead may already be unreachable.
        }
      }
      try {
        await _git.reap(root: _root, worktree: worktree);
      } on Object {
        // best-effort: a reap failure must not mask the original error.
      }
      rethrow;
    }
  }

  /// Reacts to a [CrashDecision] from the actuator's supervision stream. A
  /// restart re-spawns; a quarantine parks; a clean park drives the
  /// close-then-reap removal trigger.
  void _onDecision(CrashDecision decision) {
    final record = _bySession[decision.sessionBeadId];
    if (record == null) return; // not one of ours (or already removed).
    switch (decision) {
      case RestartSession():
        unawaited(_restart(record));
      case QuarantineSession():
        // Parked — no respawn, no reap. The session bead stays quarantined.
        _onObserve?.call('quarantined (parked): ${record.sessionBeadId}');
      case SessionParked():
        unawaited(_finishAndReap(record));
    }
  }

  /// A crash under the threshold: re-spawn the same bead in its existing
  /// worktree (the actuator left the session bead OPEN with restart_requested).
  Future<void> _restart(DispatchRecord record) {
    return _queue.run<void>(record.workBeadId, () async {
      if (_disposed) return;
      try {
        await _provider.stop(record.sessionBeadId); // ensure no stale process.
        final config = _configBuilder(
          DispatchRequest(
            bead:
                _source.bead(record.workBeadId) ??
                Bead(id: record.workBeadId),
            rig: _root.rig,
            sessionBeadId: record.sessionBeadId,
            worktree: record.worktree,
          ),
        );
        await _provider.start(record.sessionBeadId, config);
      } on Object catch (e, st) {
        _reportError(e, st);
      }
    });
  }

  /// The removal TRIGGER (Track 3 + Track 5): the lifecycle bead is closed, then
  /// — once the branch is pushed (HasUnpushedCommits==false) — the three-gate
  /// reaper removes the worktree. The land step (commit→push→PR) is the caller's
  /// (Track 7) so an unpushed worktree is REFUSED by the reaper, fail-closed.
  /// Here the dispatcher closes the session bead and ATTEMPTS the reap; the
  /// gates keep an unpushed/uncommitted worktree in place.
  Future<void> _finishAndReap(DispatchRecord record) {
    return _queue.run<void>(record.workBeadId, () async {
      if (_disposed) return;
      try {
        // Close the lifecycle bead through the chokepoint (bd-only).
        await _actuator.closeSession(
          record.sessionBeadId,
          reason: 'session ended',
        );
        // The removal trigger: reap only fires behind the three fail-closed
        // gates — an unpushed/uncommitted/stashed worktree is REFUSED and left
        // in place for the land step / a later sweep.
        final outcome = await _git.reap(root: _root, worktree: record.worktree);
        if (outcome.refused) {
          _onObserve?.call(
            'reap refused (kept): ${record.worktree.path} '
            '— ${outcome.refusedReason}',
          );
        }
      } on Object catch (e, st) {
        _reportError(e, st);
      } finally {
        // Drop the record + release the slot either way — a refused reap leaves
        // the worktree on disk but the session is closed; re-readiness would
        // re-provision (and re-reserve).
        _dispatched.remove(record.workBeadId);
        _bySession.remove(record.sessionBeadId);
        _reserved.remove(record.workBeadId);
      }
    });
  }

  void _reportError(Object error, StackTrace stack) {
    _onError?.call(error, stack);
  }

  /// Cancels the subscriptions. Idempotent. Does NOT stop running agents (the
  /// caller owns provider/actuator teardown) — the dispatcher only owns its own
  /// stream subscriptions and its in-memory records.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventSub?.cancel();
    await _decisionSub?.cancel();
  }
}

/// The inputs the [DispatchInteractor] hands the [RuntimeConfig] builder so the
/// caller (Track 7's `grid run` wiring) constructs the `claude` invocation —
/// the command, the permission flag, the prompt, the per-incarnation env — for
/// THIS bead in THIS worktree. Plain value type. The builder owns the agent
/// invocation contract (executable + argv + env allowlist); the dispatcher owns
/// only ready→worktree→session.
class DispatchRequest {
  const DispatchRequest({
    required this.bead,
    required this.rig,
    required this.sessionBeadId,
    required this.worktree,
  });

  /// The ready work bead being dispatched (its title/description seed the
  /// prompt; its id is the worktree/branch key).
  final Bead bead;

  /// The owned rig (e.g. `tgdog`).
  final String rig;

  /// The minted session bead id (the runtime session name; also the
  /// `GRID_SESSION_ID`/`GRID_BEAD_ID` env source).
  final String sessionBeadId;

  /// The provisioned worktree — its `path` is the [RuntimeConfig.workDir].
  final BeadWorktree worktree;
}
