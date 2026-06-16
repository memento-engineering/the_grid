import 'dart:async';

import '../runtime/runtime_event.dart';
import 'grid_bead_writer.dart';
import 'session_state.dart';

/// What [RuntimeActuator] decided to do with a crashed session — surfaced so the
/// dispatcher (Track 5) can re-spawn a restart or leave a quarantined session
/// parked. **Futures for acts, Streams for observations**: this is returned by
/// the act ([onExited]/[onDied]) AND emitted on [decisions] for observers.
sealed class CrashDecision {
  const CrashDecision(this.sessionBeadId);

  /// The session bead this decision concerns.
  final String sessionBeadId;
}

/// The session should be restarted: a fresh incarnation. The bead is NOT
/// closed; `restart_requested` is set so the dispatcher re-spawns (gc's
/// `RequestFreshRestart`, `manager.go:867-879`).
class RestartSession extends CrashDecision {
  const RestartSession(super.sessionBeadId);
}

/// The session crashed too many times in the window — quarantined. The bead is
/// parked at `state=quarantined` with `quarantine_cycle`/`quarantined_until`
/// (gc's `QuarantinePatch`); the dispatcher does NOT re-spawn it.
class QuarantineSession extends CrashDecision {
  const QuarantineSession(super.sessionBeadId, {required this.cycle});

  /// The 1-based quarantine round (gc's `quarantine_cycle`).
  final int cycle;
}

/// The session ended cleanly — no restart, no quarantine. The lifecycle bead is
/// transitioned to `asleep` (a clean exit) or `closed` (the caller's terminal
/// choice via [RuntimeActuator.closeSession]).
class SessionParked extends CrashDecision {
  const SessionParked(super.sessionBeadId);
}

/// The bd write chokepoint consumer (M3 Track 4): turns Track-2 [RuntimeEvent]s
/// into `state` transitions on the_grid-owned **session beads**, written
/// **exclusively** through the [GridBeadWriter] chokepoint (bd-only,
/// `--actor grid-controller`, fail-closed ownership re-check before every
/// write).
///
/// **Lifecycle.** A spawn mints + stamps the session bead and drives it
/// `start_pending → spawning → active`. Activity keeps it `active`; a clean
/// exit parks it `asleep`; a crash (a [Died] or a non-zero [Exited]) trips the
/// crash-loop machinery (gc `lifecycle_transition.go:468-497`,
/// `manager.go:867-879`): under the threshold it sets `restart_requested` (a
/// fresh restart, bead left open); at/over the threshold it quarantines
/// (`state=quarantined`, `quarantine_cycle`, `quarantined_until`).
///
/// **Crash bookkeeping is in-memory** — the actuator is the live supervisor, so
/// the durable `crash_count`/`quarantine_cycle` it writes mirror an in-memory
/// counter keyed by session bead id. gc resets `crash_count` to 0 on
/// reactivate (`ReactivatePatch`); here a clean exit / explicit reset clears
/// the counter.
class RuntimeActuator {
  RuntimeActuator({
    required GridBeadWriter writer,
    int crashThreshold = 3,
    Duration quarantineBackoff = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : assert(crashThreshold >= 1, 'crashThreshold must be >= 1'),
       _writer = writer,
       _crashThreshold = crashThreshold,
       _quarantineBackoff = quarantineBackoff,
       _clock = clock ?? DateTime.now;

  final GridBeadWriter _writer;
  final int _crashThreshold;
  final Duration _quarantineBackoff;
  final DateTime Function() _clock;

  /// In-memory supervisor bookkeeping per session bead.
  final Map<String, _SessionRecord> _records = {};

  final StreamController<CrashDecision> _decisions =
      StreamController<CrashDecision>.broadcast();

  /// Observations of the crash/restart decisions made (Streams for
  /// observations). The dispatcher (Track 5) listens to re-spawn restarts.
  Stream<CrashDecision> get decisions => _decisions.stream;

  /// The current in-memory `metadata.state` of [sessionBeadId] (for tests /
  /// diagnostics), or [LifecycleState.none] if unknown.
  LifecycleState stateOf(String sessionBeadId) =>
      _records[sessionBeadId]?.state ?? LifecycleState.none;

  /// The current in-memory crash count of [sessionBeadId].
  int crashCountOf(String sessionBeadId) =>
      _records[sessionBeadId]?.crashCount ?? 0;

  // ---------------------------------------------------------------------------
  // Spawn — mint the session bead and drive it to active.
  // ---------------------------------------------------------------------------

  /// Mints a the_grid-owned session bead for [workBeadId] in [rig] through the
  /// chokepoint (owned rig stamped from birth), records its lifecycle locally
  /// at `start_pending`, and returns its id. **Futures for acts.**
  ///
  /// The chokepoint refuses ([OwnershipRefused]) when [rig] is not owned — so a
  /// non-owned spawn never even mints a bead.
  Future<String> spawnSession({
    required String rig,
    required String workBeadId,
    String? title,
    String? worktreePath,
    String? branch,
  }) async {
    final id = await _writer.createSession(
      rig: rig,
      title: title ?? 'session for $workBeadId',
      workBeadId: workBeadId,
      metadata: {
        'state': LifecycleState.startPending.wire,
        if (worktreePath != null) 'worktree': worktreePath,
        if (branch != null) 'branch': branch,
      },
    );
    _records[id] = _SessionRecord(state: LifecycleState.startPending);
    return id;
  }

  // ---------------------------------------------------------------------------
  // RuntimeEvent ingestion.
  // ---------------------------------------------------------------------------

  /// Subscribes to a Track-2 [events] stream and drives each session bead's
  /// lifecycle. The event's `name` IS the session bead id (the dispatcher mints
  /// the session bead then names the runtime session by its id). Returns the
  /// subscription so the caller owns teardown.
  StreamSubscription<RuntimeEvent> bind(Stream<RuntimeEvent> events) =>
      events.listen(_onEvent);

  void _onEvent(RuntimeEvent event) {
    // Fire-and-forget on the stream callback (sync); each handler is a single
    // serialized chain of bd writes for one bead. The stream is per-provider;
    // the dispatcher serializes spawns per bead (Track 5's PerBeadQueue), so
    // events for one session arrive in order.
    unawaited(handle(event));
  }

  /// Processes one [RuntimeEvent], writing the resulting transition through the
  /// chokepoint. Exposed (not just via [bind]) so tests drive it directly and
  /// await the write. Returns the [CrashDecision] for an exit/death, else null.
  Future<CrashDecision?> handle(RuntimeEvent event) async {
    switch (event) {
      case SessionStarted(:final name):
        await _onStarted(name);
        return null;
      case ActivityChanged(:final name, :final active):
        await _onActivity(name, active);
        return null;
      case Respawned(:final name, :final epoch):
        await _onRespawned(name, epoch);
        return null;
      case Exited(:final name, :final exitCode):
        // A clean exit (code 0) parks asleep; a non-zero exit is a crash.
        return exitCode == 0
            ? await _onCleanExit(name)
            : await _onCrash(name, 'exit $exitCode');
      case Died(:final name, :final reason):
        return _onCrash(name, reason.isEmpty ? 'died' : reason);
    }
  }

  Future<void> _onStarted(String id) async {
    final record = _records[id];
    if (record == null) return;
    // start_pending → spawning → active. gc splits these; the subprocess
    // provider confirms liveness in one signal (the pid is alive when
    // SessionStarted fires), so we walk both legal edges and persist `active`.
    final spawning = transitionOrNull(record.state, LifecycleCommand.spawn);
    if (spawning != null) record.state = spawning;
    final active = transitionOrNull(record.state, LifecycleCommand.activate);
    if (active == null) return; // illegal from here (already terminal) — skip.
    record.state = active;
    await _writer.update(id, metadata: {'state': active.wire});
  }

  Future<void> _onActivity(String id, bool active) async {
    final record = _records[id];
    if (record == null || !active) return;
    final next = transitionOrNull(record.state, LifecycleCommand.activate);
    // already active / illegal from here — nothing to write.
    if (next == null || next == record.state) return;
    record.state = next;
    await _writer.update(id, metadata: {'state': next.wire});
  }

  Future<void> _onRespawned(String id, int epoch) async {
    final record = _records[id];
    if (record == null) return;
    // A respawn restarts a parked/quarantined session into a fresh incarnation;
    // clear restart_requested + reset the crash counter (gc ReactivatePatch
    // resets crash_count but PRESERVES quarantine_cycle).
    final next = transitionOrNull(record.state, LifecycleCommand.restart);
    record
      ..crashCount = 0
      ..state = next ?? record.state;
    await _writer.update(
      id,
      metadata: {
        'state': (next ?? LifecycleState.spawning).wire,
        'runtime_epoch': '$epoch',
        'restart_requested': '',
        'crash_count': '0',
      },
    );
  }

  Future<CrashDecision> _onCleanExit(String id) async {
    final record = _records[id];
    if (record == null) return SessionParked(id);
    record.crashCount = 0;
    final next = transitionOrNull(record.state, LifecycleCommand.sleep);
    if (next != null) {
      record.state = next;
      await _writer.update(
        id,
        metadata: {'state': next.wire, 'crash_count': '0'},
      );
    }
    final decision = SessionParked(id);
    _decisions.add(decision);
    return decision;
  }

  Future<CrashDecision> _onCrash(String id, String reason) async {
    final record = _records[id] ?? (_records[id] = _SessionRecord());
    record.crashCount++;

    if (record.crashCount >= _crashThreshold) {
      // Crash-loop quarantine (gc QuarantinePatch). quarantine_cycle is a
      // monotonic round counter preserved across reactivations.
      record.quarantineCycle++;
      record.state =
          transitionOrNull(record.state, LifecycleCommand.quarantine) ??
          LifecycleState.quarantined;
      final until = _clock().toUtc().add(_quarantineBackoff);
      await _writer.update(
        id,
        metadata: {
          'state': LifecycleState.quarantined.wire,
          'state_reason': 'crash-loop',
          'quarantine_cycle': '${record.quarantineCycle}',
          'quarantined_until': until.toIso8601String(),
          'crash_reason': reason,
        },
      );
      final decision = QuarantineSession(id, cycle: record.quarantineCycle);
      _decisions.add(decision);
      return decision;
    }

    // Under the threshold: a fresh restart (bead left OPEN — gc
    // RequestFreshRestart). restart_requested drives the dispatcher to re-spawn.
    await _writer.update(
      id,
      metadata: {
        'restart_requested': 'true',
        'continuation_reset_pending': 'true',
        'crash_count': '${record.crashCount}',
        'crash_reason': reason,
      },
    );
    final decision = RestartSession(id);
    _decisions.add(decision);
    return decision;
  }

  // ---------------------------------------------------------------------------
  // Terminal — close the session bead.
  // ---------------------------------------------------------------------------

  /// Closes the_grid-owned session [id] through the chokepoint (terminal
  /// lifecycle), writing `state=closed` then `bd close`. **Futures for acts.**
  Future<void> closeSession(
    String id, {
    String reason = 'session ended',
  }) async {
    final record = _records[id];
    final from = record?.state ?? LifecycleState.active;
    final closed = transitionOrNull(from, LifecycleCommand.close);
    if (closed != null) {
      // The state write merges BEFORE the close; `bd update --metadata` works
      // on a closed bead too, but writing state-then-close mirrors gc's order.
      await _writer.update(id, metadata: {'state': closed.wire});
    }
    await _writer.close(id, reason: reason);
    record?.state = LifecycleState.closed;
  }

  /// Releases the broadcast controller. Idempotent.
  Future<void> dispose() async {
    if (!_decisions.isClosed) await _decisions.close();
  }
}

/// In-memory per-session supervisor bookkeeping (the live half of what the
/// durable `metadata.state`/`crash_count`/`quarantine_cycle` persist).
class _SessionRecord {
  _SessionRecord({this.state = LifecycleState.none});

  LifecycleState state;
  int crashCount = 0;
  int quarantineCycle = 0;
}
