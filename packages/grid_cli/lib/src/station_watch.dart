/// `grid watch --grid-home <home>` — the STATION watch.
///
/// The substation-root mode next door (`watch_command.dart` / the predicates in
/// `watch_predicate.dart`) watches ONE substation's WORK graph. This mode
/// watches the STATION: the grid state store at `<grid-home>/.grid/.beads`
/// (gate and session beads) plus the resident's RS-2 lock at
/// `<grid-home>/.grid/station.lock`. It exists so a governor's watch is a
/// VENDED VERB re-armed by one line after every relaunch, instead of a shell
/// loop re-derived from a transcript into a scratchpad the next harness login
/// wipes (tg-9pn1; Nico, 2026-09-13).
///
/// The pieces are separated so the whole mode is testable with FAKES over no
/// store at all: [StationFold] is a pure fold of the typed [GraphEvent] stream
/// (plus a baseline census) into [StationWatchEvent]s, [ResidentProbe] is the
/// injected lock read, and [awaitStationWatch] is the loop that renders them
/// and decides the exit code. The composition over a real store lives in
/// `runStationWatch` (`watch_command.dart`).
///
/// **Delivery is NOT here.** An open PR reaching a terminal state is
/// `pow-07zx`'s half, through the overlay.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart'
    show StationLockRecord;
import 'package:grid_runtime/grid_runtime.dart'
    show
        GateSweepSessionDisposition,
        GridIssueTypes,
        sessionDispositionOfMetadata;

import 'station_lock.dart';
import 'watch_predicate.dart';

/// The station-metadata key naming the node a gate parks.
///
/// A gate minted by `StationBeadWriter.createGate` carries it; a STATION gate
/// (`createStationGate`, which blocks a whole substation rather than a parked
/// node) does not — so this is read as nullable everywhere.
const String kGateNodeKey = 'node';

/// The session-metadata key naming the WORK bead a session drives.
const String kSessionWorkBeadKey = 'work_bead';

/// The typed kind of one station event — the wire name its line and its NDJSON
/// record carry. A CLOSED set: the station watch reports exactly these.
enum StationWatchEventKind {
  /// A gate bead entered the open-gate shape ([isOpenGateBead]).
  gateOpened('gate.opened'),

  /// An open gate stopped being one — closed, stripped, or hard-deleted.
  gateClosed('gate.closed'),

  /// A `type=session` bead was minted.
  sessionMinted('session.minted'),

  /// A `type=session` bead reached its terminal (closed) state.
  sessionTerminal('session.terminal'),

  /// Every live session went terminal, after at least one was live.
  zeroLive('zero-live'),

  /// The resident's lock vanished, or the pid it names is dead.
  residentDown('resident.down'),

  /// The periodic census line: gates, sessions, ready.
  heartbeat('heartbeat');

  const StationWatchEventKind(this.wire);

  /// The name this kind is rendered and matched by.
  final String wire;
}

/// One typed station event — one rendered line.
///
/// Sibling in name only to `StationEvent` (`station_event_log.dart`), which
/// decodes the resident's OWN flares inside the station process. This family is
/// derived from the state STORE by an outside reader that the resident knows
/// nothing about, and carries three kinds no flare can (`zero-live`,
/// `resident.down`, `heartbeat`), so the two stay separate vocabularies.
sealed class StationWatchEvent {
  /// Const base so every variant is a compile-time value.
  const StationWatchEvent();

  /// This event's kind.
  StationWatchEventKind get kind;

  /// The event-specific fields, merged into the NDJSON record under `--json`.
  Map<String, Object?> get fields;

  /// The human line's trailing text, after the kind. Empty when the kind says
  /// everything (`zero-live`).
  String get summary;
}

/// A gate BECAME open: `gate.opened <gate> <bead> <node>`.
final class StationGateOpened extends StationWatchEvent {
  /// Creates the event for gate [gate] blocking [bead] at [node].
  const StationGateOpened({
    required this.gate,
    required this.bead,
    required this.node,
  });

  /// The gate bead's id.
  final String gate;

  /// The bead the gate blocks (the gate's `blocks` stamp — a session id).
  final String bead;

  /// The parked node path, or null on a substation-scoped station gate.
  final String? node;

  @override
  StationWatchEventKind get kind => StationWatchEventKind.gateOpened;

  @override
  Map<String, Object?> get fields => <String, Object?>{
    'gate': gate,
    'bead': bead,
    'node': node,
  };

  @override
  String get summary => '$gate $bead ${node ?? '—'}';
}

/// An open gate stopped being open: `gate.closed <gate> <bead> <node>`.
final class StationGateClosed extends StationWatchEvent {
  /// Creates the event for gate [gate] that blocked [bead] at [node].
  const StationGateClosed({
    required this.gate,
    required this.bead,
    required this.node,
  });

  /// The gate bead's id.
  final String gate;

  /// The bead the gate blocked.
  final String bead;

  /// The parked node path, or null.
  final String? node;

  @override
  StationWatchEventKind get kind => StationWatchEventKind.gateClosed;

  @override
  Map<String, Object?> get fields => <String, Object?>{
    'gate': gate,
    'bead': bead,
    'node': node,
  };

  @override
  String get summary => '$gate $bead ${node ?? '—'}';
}

/// A session was minted: `session.minted <bead>`.
final class StationSessionMinted extends StationWatchEvent {
  /// Creates the event for session [bead] driving [workBead].
  const StationSessionMinted({required this.bead, required this.workBead});

  /// The session bead's id.
  final String bead;

  /// The work bead the session drives (`work_bead`), or null when unstamped.
  final String? workBead;

  @override
  StationWatchEventKind get kind => StationWatchEventKind.sessionMinted;

  @override
  Map<String, Object?> get fields => <String, Object?>{
    'bead': bead,
    'workBead': workBead,
  };

  @override
  String get summary => bead;
}

/// A session reached terminal: `session.terminal <bead> <disposition>`.
final class StationSessionTerminal extends StationWatchEvent {
  /// Creates the event for session [bead] closing as [disposition].
  const StationSessionTerminal({
    required this.bead,
    required this.disposition,
    required this.workBead,
  });

  /// The session bead's id.
  final String bead;

  /// The A48 disposition derived from the session's own metadata.
  final GateSweepSessionDisposition disposition;

  /// The work bead the session drove, or null when unstamped.
  final String? workBead;

  @override
  StationWatchEventKind get kind => StationWatchEventKind.sessionTerminal;

  @override
  Map<String, Object?> get fields => <String, Object?>{
    'bead': bead,
    'disposition': disposition.name,
    'workBead': workBead,
  };

  @override
  String get summary => '$bead ${disposition.name}';
}

/// Every live session went terminal: `zero-live`.
final class StationZeroLive extends StationWatchEvent {
  /// Creates the zero-live event.
  const StationZeroLive();

  @override
  StationWatchEventKind get kind => StationWatchEventKind.zeroLive;

  @override
  Map<String, Object?> get fields => const <String, Object?>{};

  @override
  String get summary => '';
}

/// Why the resident reads as down.
enum ResidentDownReason {
  /// The lock file is gone — the station released it, or never held it.
  lockMissing('lock_missing'),

  /// The lock parses, but the pid it names is not a running process.
  pidDead('pid_dead');

  const ResidentDownReason(this.wire);

  /// The value rendered on the line and in the NDJSON record.
  final String wire;
}

/// The resident went down: `resident.down <reason> [pid <n>]`.
final class StationResidentDown extends StationWatchEvent {
  /// Creates the event for [reason], naming [pid] when the lock had one.
  const StationResidentDown({required this.reason, required this.pid});

  /// Lock gone, or pid dead.
  final ResidentDownReason reason;

  /// The pid the lock named, or null when there was no readable lock.
  final int? pid;

  @override
  StationWatchEventKind get kind => StationWatchEventKind.residentDown;

  @override
  Map<String, Object?> get fields => <String, Object?>{
    'reason': reason.wire,
    'pid': pid,
  };

  @override
  String get summary => pid == null ? reason.wire : '${reason.wire} pid $pid';
}

/// The periodic census: `heartbeat gates <g> sessions <s> ready <r>`.
final class StationHeartbeat extends StationWatchEvent {
  /// Creates a heartbeat carrying the current counts.
  const StationHeartbeat({
    required this.gates,
    required this.sessions,
    required this.ready,
  });

  /// Open gates in the state store.
  final int gates;

  /// Live (open) session beads.
  final int sessions;

  /// The state store's ready count, or null before the baseline snapshot.
  final int? ready;

  @override
  StationWatchEventKind get kind => StationWatchEventKind.heartbeat;

  @override
  Map<String, Object?> get fields => <String, Object?>{
    'gates': gates,
    'sessions': sessions,
    'ready': ready,
  };

  @override
  String get summary => 'gates $gates sessions $sessions ready ${ready ?? '—'}';
}

/// Renders a [StationWatchEvent] as one line — human, or one NDJSON object under
/// `--json` (`ts` + `event` + the event's own [StationWatchEvent.fields]).
class StationWatchEventRenderer {
  /// Creates a renderer; [json] selects NDJSON over the human line.
  StationWatchEventRenderer({required this.json});

  /// Whether to emit NDJSON.
  final bool json;

  /// One line for [event], stamped [at].
  String render(StationWatchEvent event, {required DateTime at}) {
    if (json) {
      return jsonEncode(<String, Object?>{
        'ts': at.toIso8601String(),
        'event': event.kind.wire,
        ...event.fields,
      });
    }
    final summary = event.summary;
    return '${_hms(at)}  ${event.kind.wire}'
        '${summary.isEmpty ? '' : ' $summary'}';
  }

  static String _hms(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.$ms';
  }
}

/// The census a station watch starts from: which gates are already open and
/// which sessions are already live the moment it attaches.
///
/// The baseline `SnapshotInitialized` carries COUNTS ONLY by contract (it does
/// not enumerate beads), so the fold cannot learn the station's standing shape
/// from the event stream alone — it reads it from the snapshot the runtime
/// already holds, or from a Fake in a test.
typedef StationBaseline = ({Set<String> openGates, Set<String> liveSessions});

/// Derives the baseline census from [snapshot] (null before the first read
/// completes — an empty census, which the first real snapshot never is).
StationBaseline stationBaselineOf(GraphSnapshot? snapshot) {
  final openGates = <String>{};
  final liveSessions = <String>{};
  for (final bead in snapshot?.beads ?? const <Bead>[]) {
    if (isOpenGateBead(bead)) openGates.add(bead.id);
    if (_isLiveSession(bead)) liveSessions.add(bead.id);
  }
  return (openGates: openGates, liveSessions: liveSessions);
}

/// A live session: an OPEN `type=session` bead. Terminal is the close.
bool _isLiveSession(Bead bead) =>
    bead.issueType == GridIssueTypes.session && !bead.isClosed;

String? _stringMetadata(Bead bead, String key) {
  final value = bead.metadata[key];
  return value is String && value.isNotEmpty ? value : null;
}

/// Folds the typed [GraphEvent] stream of a GRID STATE STORE into station
/// events, carrying the running census a heartbeat reports.
///
/// STATEFUL by necessity (zero-live is a transition of the live-session SET,
/// and the ready count is a fold of the baseline plus every delta), so ONE fold
/// serves exactly ONE watch and [fold] is called once per event, in arrival
/// order.
class StationFold {
  /// Creates a fold that seeds its census from [baseline] when the stream's
  /// baseline `SnapshotInitialized` arrives — a callback, not a value, because
  /// the runtime's snapshot only exists once that event has been emitted.
  StationFold({required StationBaseline Function() baseline})
    : _baseline = baseline;

  final StationBaseline Function() _baseline;
  final Set<String> _openGates = <String>{};
  final Set<String> _liveSessions = <String>{};
  int? _readyCount;
  bool _everLive = false;
  bool _atZero = true;

  /// Open gates in the station's state store right now.
  int get openGateCount => _openGates.length;

  /// Live (open) session beads right now.
  int get liveSessionCount => _liveSessions.length;

  /// The state store's ready count, or null before the baseline.
  int? get readyCount => _readyCount;

  /// The current census as a heartbeat event.
  StationHeartbeat heartbeat() => StationHeartbeat(
    gates: openGateCount,
    sessions: liveSessionCount,
    ready: _readyCount,
  );

  /// The station events [event] produces, in emission order (usually zero or
  /// one; a close that empties the live set produces its event AND `zero-live`).
  ///
  /// Throws a LOUD [StateError] when a `ReadySetChanged` arrives before the
  /// baseline `SnapshotInitialized` — the same broken-stream contract the
  /// substation-root `ready-count=0` predicate enforces, and the same
  /// [kWatchUntilBrokenStream] exit.
  List<StationWatchEvent> fold(GraphEvent event) {
    final emitted = <StationWatchEvent>[];
    switch (event) {
      case SnapshotInitialized(:final readyCount):
        _seed(readyCount);
        // The baseline census IS a heartbeat: an attaching governor gets the
        // station's standing shape on its first line, not after N minutes.
        emitted.add(heartbeat());
      case BeadCreated(:final bead):
        if (isOpenGateBead(bead)) {
          _openGates.add(bead.id);
          emitted.add(_opened(bead));
        }
        if (_isLiveSession(bead)) {
          _markLive(bead.id);
          emitted.add(
            StationSessionMinted(
              bead: bead.id,
              workBead: _stringMetadata(bead, kSessionWorkBeadKey),
            ),
          );
        }
      case BeadUpdated(:final before, :final after):
        _gateEdges(before: before, after: after, emitted: emitted);
      case BeadReopened(:final before, :final after):
        _gateEdges(before: before, after: after, emitted: emitted);
        // A reopened session is live again — the census must say so. It is not
        // a MINT, so it announces nothing: `session.minted` means born.
        if (_isLiveSession(after)) _markLive(after.id);
      case BeadClosed(:final before, :final after):
        _gateEdges(before: before, after: after, emitted: emitted);
        if (after.issueType == GridIssueTypes.session) {
          _liveSessions.remove(after.id);
          emitted.add(
            StationSessionTerminal(
              bead: after.id,
              disposition: sessionDispositionOfMetadata(after.metadata),
              workBead: _stringMetadata(after, kSessionWorkBeadKey),
            ),
          );
        }
      case BeadDeleted(:final bead):
        // A hard delete ends the bead's EXISTENCE. For a gate that ends the
        // park (the same rule the substation `gate-closed` predicate takes);
        // for a session it is NOT a terminal disposition, so the census
        // shrinks silently and only `zero-live` may follow.
        if (_openGates.remove(bead.id)) emitted.add(_closed(bead));
        _liveSessions.remove(bead.id);
      case ReadySetChanged(:final entered, :final exited):
        _applyReadyDelta(entered: entered, exited: exited);
      case DependencyAdded():
      case DependencyRemoved():
        break;
    }
    _settleZeroLive(emitted);
    return emitted;
  }

  void _seed(int readyCount) {
    final baseline = _baseline();
    _openGates
      ..clear()
      ..addAll(baseline.openGates);
    _liveSessions
      ..clear()
      ..addAll(baseline.liveSessions);
    _readyCount = readyCount;
    _everLive = _liveSessions.isNotEmpty;
    _atZero = _liveSessions.isEmpty;
  }

  void _markLive(String id) {
    _liveSessions.add(id);
    _everLive = true;
  }

  /// Fires only on the EDGE into / out of the open-gate shape, so the mint
  /// (`bd create -t gate` with NO metadata, then the stamping
  /// `blocks=… node=…` update) announces exactly ONE `gate.opened`, and a
  /// later unrelated field change on an already-open gate announces nothing.
  void _gateEdges({
    required Bead before,
    required Bead after,
    required List<StationWatchEvent> emitted,
  }) {
    final wasOpen = isOpenGateBead(before);
    final isOpen = isOpenGateBead(after);
    if (isOpen && !wasOpen) {
      _openGates.add(after.id);
      emitted.add(_opened(after));
    } else if (wasOpen && !isOpen) {
      _openGates.remove(before.id);
      emitted.add(_closed(before));
    }
  }

  void _settleZeroLive(List<StationWatchEvent> emitted) {
    if (_liveSessions.isNotEmpty) {
      _atZero = false;
      return;
    }
    if (!_everLive || _atZero) return;
    _atZero = true;
    emitted.add(const StationZeroLive());
  }

  void _applyReadyDelta({
    required Set<String> entered,
    required Set<String> exited,
  }) {
    final baseline = _readyCount;
    if (baseline == null) {
      throw StateError(
        'grid watch --grid-home: a ReadySetChanged arrived before the '
        'baseline SnapshotInitialized, so there is no ready count to fold. '
        'diffSnapshots emits the baseline first by contract (a null `before` '
        'yields exactly one SnapshotInitialized); this stream did not.',
      );
    }
    _readyCount = baseline - exited.length + entered.length;
  }

  static StationGateOpened _opened(Bead gate) => StationGateOpened(
    gate: gate.id,
    bead: '${gate.metadata[kGateBlocksKey]}',
    node: _stringMetadata(gate, kGateNodeKey),
  );

  static StationGateClosed _closed(Bead gate) => StationGateClosed(
    gate: gate.id,
    bead: '${gate.metadata[kGateBlocksKey]}',
    node: _stringMetadata(gate, kGateNodeKey),
  );
}

/// One terminating condition an operator arms with `--until` in
/// `--grid-home` mode. A CLOSED set, like the substation-root one next door —
/// deliberately not an expression language.
sealed class StationPredicate {
  /// Const base so every variant is a compile-time value.
  const StationPredicate();

  /// The exact literal an operator passes to `--until`.
  String get literal;

  /// Whether [event] satisfies this predicate.
  bool accepts(StationWatchEvent event);

  /// Whether this predicate specifically AWAITS [kind].
  ///
  /// Distinct from [accepts] for exactly one case: `resident.down` is terminal
  /// whatever is armed, and exits [kWatchResidentDown] unless it is the awaited
  /// event. `--until any` accepts it as an event but does not AWAIT it, so a
  /// governor blocking on `any` still learns from the exit code that its
  /// station died rather than that its work moved.
  bool awaits(StationWatchEventKind kind);
}

/// Waits for one named station event kind.
final class UntilStationKind extends StationPredicate {
  /// Creates the predicate for [kind], armed by [literal].
  const UntilStationKind({required this.literal, required this.kind});

  @override
  final String literal;

  /// The awaited kind.
  final StationWatchEventKind kind;

  @override
  bool accepts(StationWatchEvent event) => event.kind == kind;

  @override
  bool awaits(StationWatchEventKind kind) => kind == this.kind;
}

/// Waits for the FIRST station event of any kind but the heartbeat.
///
/// The governor's standing arming (`--until any --timeout 2700`): the
/// heartbeat exists to prove the watch is alive, so a heartbeat satisfying
/// `any` would return the watch to its operator every N minutes with nothing
/// to act on — the exact re-derivation loop this verb exists to end.
final class UntilAnyStationEvent extends StationPredicate {
  /// Creates the any-event predicate.
  const UntilAnyStationEvent();

  @override
  String get literal => 'any';

  @override
  bool accepts(StationWatchEvent event) =>
      event.kind != StationWatchEventKind.heartbeat;

  @override
  bool awaits(StationWatchEventKind kind) => false;
}

/// The CLOSED set of `--grid-home --until` literals, in help order.
const List<String> kStationPredicateLiterals = <String>[
  'gate-open',
  'gate-closed',
  'session-minted',
  'session-terminal',
  'zero-live',
  'resident-down',
  'any',
];

/// Parses a station `--until` [literal] into its predicate.
///
/// Throws [WatchUntilRefusal] (LOUD; never a null return) for anything outside
/// the closed set — including the substation-root literals `bead-status=<s>`
/// and `ready-count=0`, which read a substation's WORK graph and have no
/// meaning over the station's state store.
StationPredicate parseStationPredicate(String literal) => switch (literal) {
  'gate-open' => const UntilStationKind(
    literal: 'gate-open',
    kind: StationWatchEventKind.gateOpened,
  ),
  'gate-closed' => const UntilStationKind(
    literal: 'gate-closed',
    kind: StationWatchEventKind.gateClosed,
  ),
  'session-minted' => const UntilStationKind(
    literal: 'session-minted',
    kind: StationWatchEventKind.sessionMinted,
  ),
  'session-terminal' => const UntilStationKind(
    literal: 'session-terminal',
    kind: StationWatchEventKind.sessionTerminal,
  ),
  'zero-live' => const UntilStationKind(
    literal: 'zero-live',
    kind: StationWatchEventKind.zeroLive,
  ),
  'resident-down' => const UntilStationKind(
    literal: 'resident-down',
    kind: StationWatchEventKind.residentDown,
  ),
  'any' => const UntilAnyStationEvent(),
  _ => throw WatchUntilRefusal(
    'unknown --until predicate "$literal" for --grid-home. The set is '
    'CLOSED: ${kStationPredicateLiterals.join(', ')}.',
  ),
};

/// The validated station `--until` arming: the predicate plus its deadline.
class StationWatchUntil {
  /// Creates an arming from [predicate] and [timeout].
  const StationWatchUntil({required this.predicate, required this.timeout});

  /// The condition that ends the watch.
  final StationPredicate predicate;

  /// The bound after which the watch gives up with [kWatchUntilTimedOut].
  final Duration timeout;
}

/// Arms `--until` for `--grid-home` mode.
///
/// Same three-flag mode selector as the substation-root mode
/// ([validateUntilFlags] — one copy of those rules), a different closed
/// predicate set. Returns null when `--until` was not passed.
StationWatchUntil? armStationWatchUntil({
  String? until,
  String? timeout,
  String? forSeconds,
}) {
  final flags = validateUntilFlags(
    until: until,
    timeout: timeout,
    forSeconds: forSeconds,
  );
  if (flags == null) return null;
  return StationWatchUntil(
    predicate: parseStationPredicate(flags.literal),
    timeout: flags.timeout,
  );
}

/// What one read of the resident's lock says.
sealed class ResidentState {
  /// Const base so every variant is a compile-time value.
  const ResidentState();
}

/// The lock parses and names a LIVE pid.
final class ResidentLive extends ResidentState {
  /// Creates the live state for [pid].
  const ResidentLive(this.pid);

  /// The station pid the lock names.
  final int pid;
}

/// The lock is gone, or names a dead pid — the station is not there.
final class ResidentDown extends ResidentState {
  /// Creates the down state for [reason], naming [pid] when one was read.
  const ResidentDown({required this.reason, this.pid});

  /// Lock gone, or pid dead.
  final ResidentDownReason reason;

  /// The pid the lock named, or null when there was no readable lock.
  final int? pid;
}

/// The lock EXISTS but does not parse.
///
/// Never reported as down: an unreadable lock is a young or mid-populate
/// acquire, not proof of a crash (the same posture `StationLockService` and
/// `traj quiesce` take — a torn lock cannot prove the station is down). The
/// watch keeps watching and the next probe decides.
final class ResidentUnreadable extends ResidentState {
  /// Creates the unreadable state.
  const ResidentUnreadable();
}

/// One read of the resident's liveness — injected so the loop is testable
/// against a Fake lock.
typedef ResidentProbe = Future<ResidentState> Function();

/// The REAL resident probe: read `<gridHome>/.grid/station.lock`, then probe
/// the pid it names ([defaultPidProbe] unless [isPidAlive] is injected).
Future<ResidentState> probeStationResident({
  required String gridHome,
  PidProbe? isPidAlive,
}) async {
  final file = File(StationLockService.lockPath(gridHome));
  if (!await file.exists()) {
    return const ResidentDown(reason: ResidentDownReason.lockMissing);
  }
  final StationLockRecord? record = await readStationLockRecord(file);
  if (record == null) {
    // It vanished between the existence check and the read — that IS gone.
    if (!await file.exists()) {
      return const ResidentDown(reason: ResidentDownReason.lockMissing);
    }
    return const ResidentUnreadable();
  }
  return (isPidAlive ?? defaultPidProbe)(record.pid)
      ? ResidentLive(record.pid)
      : ResidentDown(reason: ResidentDownReason.pidDead, pid: record.pid);
}

/// Runs ONE station watch: folds [events] through [fold], polls [probeResident]
/// every [residentPoll], beats every [heartbeatEvery] (null disables), renders
/// every station event through [render] as it arrives, and returns the exit
/// code.
///
/// Subscribes SYNCHRONOUSLY (before the first suspension), so a caller may arm
/// this ahead of `GridControllerRuntime.start()` and still see the baseline
/// `SnapshotInitialized` — the only event the ready count rides.
///
/// The exit contract:
///
/// * [kWatchUntilSatisfied] — [until]'s predicate held, or [runFor] elapsed, or
///   [interrupt] completed (Ctrl-C);
/// * [kWatchUntilTimedOut] — [until] was armed and its deadline expired first;
/// * [kWatchResidentDown] — the resident went down and that was not the awaited
///   event (`--until resident-down` makes it awaited, and then it is
///   [kWatchUntilSatisfied]).
///
/// Completes with the [StateError] [StationFold.fold] raises when the stream
/// breaks its own ordering contract; the caller maps that to
/// [kWatchUntilBrokenStream].
Future<int> awaitStationWatch({
  required Stream<GraphEvent> events,
  required StationFold fold,
  required ResidentProbe probeResident,
  required void Function(StationWatchEvent event) render,
  StationWatchUntil? until,
  Duration residentPoll = const Duration(seconds: 5),
  Duration? heartbeatEvery,
  Duration? runFor,
  Future<void>? interrupt,
}) {
  final done = Completer<int>();
  final timers = <Timer>[];

  void finish(int code) {
    if (!done.isCompleted) done.complete(code);
  }

  void emit(StationWatchEvent event) {
    if (done.isCompleted) return;
    render(event);
    if (until != null && until.predicate.accepts(event)) {
      finish(kWatchUntilSatisfied);
    }
  }

  void emitResidentDown(ResidentDown state) {
    if (done.isCompleted) return;
    render(StationResidentDown(reason: state.reason, pid: state.pid));
    finish(
      until != null &&
              until.predicate.awaits(StationWatchEventKind.residentDown)
          ? kWatchUntilSatisfied
          : kWatchResidentDown,
    );
  }

  final subscription = events.listen((event) {
    if (done.isCompleted) return;
    final List<StationWatchEvent> emitted;
    try {
      emitted = fold.fold(event);
    } on StateError catch (error) {
      if (!done.isCompleted) done.completeError(error);
      return;
    }
    for (final event in emitted) {
      emit(event);
    }
  });

  var probing = false;
  timers.add(
    Timer.periodic(residentPoll, (_) async {
      if (probing || done.isCompleted) return;
      probing = true;
      try {
        final state = await probeResident();
        if (done.isCompleted) return;
        switch (state) {
          case ResidentDown():
            emitResidentDown(state);
          case ResidentLive():
          case ResidentUnreadable():
            break;
        }
      } on Object catch (error) {
        if (!done.isCompleted) done.completeError(error);
      } finally {
        probing = false;
      }
    }),
  );

  if (heartbeatEvery != null) {
    timers.add(Timer.periodic(heartbeatEvery, (_) => emit(fold.heartbeat())));
  }
  if (until != null) {
    timers.add(Timer(until.timeout, () => finish(kWatchUntilTimedOut)));
  }
  if (runFor != null) {
    timers.add(Timer(runFor, () => finish(kWatchUntilSatisfied)));
  }
  if (interrupt != null) {
    unawaited(_finishOnInterrupt(interrupt, finish));
  }

  return done.future.whenComplete(() async {
    for (final timer in timers) {
      timer.cancel();
    }
    await subscription.cancel();
  });
}

Future<void> _finishOnInterrupt(
  Future<void> interrupt,
  void Function(int code) finish,
) async {
  await interrupt;
  finish(kWatchUntilSatisfied);
}
