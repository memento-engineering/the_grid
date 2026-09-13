import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_exploration/grid_exploration.dart';
import 'package:grid_sdk/grid_sdk.dart'
    show DirectoryProbe, StoreRefusal, SubstationWorkStore;

import 'event_renderer.dart';
import 'state_workspace.dart';
import 'station_lock.dart';
import 'station_stores.dart';
import 'station_watch.dart';
import 'watch_predicate.dart';

/// `grid watch` — TWO modes over one verb.
///
/// * `grid watch <substation-root>` — stream typed graph events from a
///   substation's live work graph. A generic, asset-agnostic CLI-SDK command
///   re-seated on the code-as-config store model
///   (`SCRATCH-station-config-model.md` v3): it watches the work store at ONE
///   substation **root** (`<root>/.beads/`), never the cwd (the ambience
///   fossil, §7 item 9). The composed runner (`space`) supplies the root it
///   authored in its `GridDelegate`; the standalone reference bin takes it
///   explicitly.
/// * `grid watch --grid-home <home>` — watch the STATION instead: the grid
///   state store at `<home>/.grid/.beads` (gate and session beads) plus the
///   resident's RS-2 lock. See `station_watch.dart` for the event set, the
///   closed `--until` set, and the exit contract.
///
/// The two are mutually exclusive: a positional root names a substation's work
/// graph, `--grid-home` names a station, and no invocation watches both.
class WatchCommand extends Command<int> {
  /// Creates the watch command with its flags.
  WatchCommand() {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit NDJSON (one JSON event per line) instead of human output.',
      )
      ..addFlag(
        'no-sql',
        negatable: false,
        help:
            'Force the bd-CLI read path even when pooled Dolt SQL is '
            'available.',
      )
      ..addOption(
        'for-seconds',
        help:
            'Run for a fixed number of seconds then exit (for scripted '
            'demos / CI) instead of until Ctrl-C.',
      )
      ..addOption(
        'grid-home',
        help:
            'Watch the STATION at this grid home — the state store at '
            '<home>/.grid/.beads and the resident lock — instead of a '
            'substation work graph. Mutually exclusive with <substation-root>.',
      )
      ..addOption(
        'heartbeat',
        help:
            'Minutes between station heartbeat lines (gates/sessions/ready) '
            'in --grid-home mode; 0 disables. Default '
            '$kDefaultStationHeartbeatMinutes.',
      )
      ..addOption(
        'until',
        help:
            'Block until a named condition holds, then exit 0. The set is '
            'CLOSED: ${kWatchPredicateLiterals.join(', ')} — or, with '
            '--grid-home, ${kStationPredicateLiterals.join(', ')}. Requires '
            '--timeout; mutually exclusive with --for-seconds.',
      )
      ..addOption(
        'timeout',
        help:
            'Seconds to wait for --until before giving up with exit '
            '$kWatchUntilTimedOut. Required whenever --until is passed.',
      );
  }

  @override
  final String name = 'watch';

  @override
  final String description =
      'Watch a substation work graph and print typed events with reaction '
      'latency. Takes the substation ROOT (its `.beads/` work store lives at '
      '`<root>/.beads/`) — no cwd discovery. With --grid-home, watches the '
      'STATION instead: state-store gates and sessions, zero-live, and '
      'resident liveness. Run under `dart run --enable-vm-service` to allow '
      'exploration tools to attach.';

  @override
  String get invocation =>
      'grid watch <substation-root> [--json] [--for-seconds N] '
      '[--until <predicate> --timeout N]\n'
      '       grid watch --grid-home <home> [--json] [--heartbeat N] '
      '[--until <predicate> --timeout N]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;
    final gridHome = args.option('grid-home');
    if (gridHome != null) return _runStationMode(args, gridHome, rest);
    if (args.option('heartbeat') != null) {
      stderr.writeln(
        'grid watch: --heartbeat only paces the STATION watch — pass '
        '--grid-home <home> too, or drop it (a substation work graph has no '
        'census to beat).',
      );
      return 64;
    }
    if (rest.isEmpty) {
      stderr.writeln(
        'grid watch: a <substation-root> is required (the substation whose '
        '`.beads/` work graph to watch), or --grid-home <home> to watch the '
        'STATION. There is no cwd discovery — name the root the delegate '
        'authored.',
      );
      return 64;
    }
    if (rest.length > 1) {
      stderr.writeln(
        'grid watch: watches ONE substation at a time — got ${rest.length} '
        'roots (${rest.join(', ')}).',
      );
      return 64;
    }
    final WatchUntil? until;
    try {
      until = armWatchUntil(
        until: args.option('until'),
        timeout: args.option('timeout'),
        forSeconds: args.option('for-seconds'),
      );
    } on WatchUntilRefusal catch (e) {
      stderr.writeln('grid watch: ${e.message}');
      return 64;
    }
    final SubstationWorkStore store;
    try {
      store = SubstationWorkStore.forRoot(rest.single);
    } on ArgumentError catch (e) {
      stderr.writeln('grid watch: ${e.message}');
      return 64;
    }
    final seconds = args.option('for-seconds');
    return runWatch(
      store: store,
      json: args.flag('json'),
      noSql: args.flag('no-sql'),
      runFor: seconds == null ? null : Duration(seconds: int.parse(seconds)),
      until: until,
    );
  }

  /// The `--grid-home` half of [run]: the two modes are exclusive, so a
  /// positional root here is a refusal rather than a silently ignored argument.
  Future<int> _runStationMode(
    ArgResults args,
    String gridHome,
    List<String> rest,
  ) async {
    if (rest.isNotEmpty) {
      stderr.writeln(
        'grid watch: --grid-home watches the STATION and <substation-root> '
        'watches ONE substation work graph — got both (--grid-home $gridHome, '
        'roots ${rest.join(', ')}). Pass exactly one.',
      );
      return 64;
    }
    final StationWatchUntil? until;
    final Duration? heartbeat;
    try {
      until = armStationWatchUntil(
        until: args.option('until'),
        timeout: args.option('timeout'),
        forSeconds: args.option('for-seconds'),
      );
      heartbeat = parseStationHeartbeat(args.option('heartbeat'));
    } on WatchUntilRefusal catch (e) {
      stderr.writeln('grid watch: ${e.message}');
      return 64;
    }
    final seconds = args.option('for-seconds');
    return runStationWatch(
      gridHome: gridHome,
      json: args.flag('json'),
      noSql: args.flag('no-sql'),
      runFor: seconds == null ? null : Duration(seconds: int.parse(seconds)),
      until: until,
      heartbeatEvery: heartbeat,
    );
  }
}

/// The default station heartbeat cadence, in minutes.
const int kDefaultStationHeartbeatMinutes = 5;

/// Parses `--heartbeat <minutes>`: null (the default cadence), `0` (disabled —
/// a null [Duration]), or a positive whole number of minutes. Throws a
/// [WatchUntilRefusal] on anything else, so a typo cannot silently mute the
/// only line that proves a background watch is alive.
Duration? parseStationHeartbeat(String? minutes) {
  if (minutes == null) {
    return const Duration(minutes: kDefaultStationHeartbeatMinutes);
  }
  final parsed = int.tryParse(minutes);
  if (parsed == null || parsed < 0) {
    throw WatchUntilRefusal(
      '--heartbeat must be a whole number of minutes (0 disables) — got '
      '"$minutes".',
    );
  }
  return parsed == 0 ? null : Duration(minutes: parsed);
}

/// Runs `grid watch`: opens the substation work store [store] at its exact root
/// (`<root>/.beads/`, no walk-up — a LOUD [StoreRefusal] if absent), builds a
/// reactive runtime, registers the exploration host (so exploration_cli/devtools
/// can attach), prints the VM service URI, and streams typed graph events with
/// measured reaction latency until interrupted.
///
/// Returns a process exit code. [out]/[err] are injectable for testing; the
/// signal wait is skipped when [runForever] is false (tests drive a fixed
/// duration via [runFor]). [workspaceOverride] bypasses store opening entirely
/// (offline tests over a fake store); [dirExists] injects the existence probe.
/// When [until] is armed the watch TERMINATES on the first event satisfying
/// its predicate ([kWatchUntilSatisfied]), or on the arming's deadline
/// ([kWatchUntilTimedOut]); [until] is mutually exclusive with [runFor], which
/// the CLI enforces through `armWatchUntil`.
Future<int> runWatch({
  required SubstationWorkStore store,
  bool json = false,
  bool noSql = false,
  void Function(String)? out,
  void Function(String)? err,
  bool runForever = true,
  Duration? runFor,
  WatchUntil? until,
  BeadsWorkspace? workspaceOverride,
  DirectoryProbe? dirExists,
}) async {
  final write = out ?? stdout.writeln;
  final writeErr = err ?? stderr.writeln;

  final BeadsWorkspace workspace;
  if (workspaceOverride != null) {
    workspace = workspaceOverride;
  } else {
    try {
      workspace = openWorkStore(store, dirExists: dirExists);
    } on StoreRefusal catch (e) {
      writeErr('grid watch: ${e.message}');
      return 1;
    }
  }

  final bundle = await GridRuntimeFactory.build(
    workspace: workspace,
    preferSql: !noSql,
  );
  final runtime = bundle.runtime;
  final host = GridExplorationHost(
    runtime,
    plugin: GridControllerPlugin(runtime, readPath: () => bundle.readPath.name),
  );
  host.register();

  final renderer = EventRenderer(json: json);
  void renderEvent(GraphEvent event) {
    write(
      renderer.render(
        event,
        reaction: runtime.stats.lastReaction,
        at: DateTime.now(),
      ),
    );
  }

  StreamSubscription<GraphEvent>? subscription;
  Future<int>? untilExit;
  if (until != null) {
    // Armed BEFORE `runtime.start()`: `awaitPredicate` subscribes
    // synchronously, so the baseline `SnapshotInitialized` is not missed.
    untilExit = awaitPredicate(
      events: runtime.events,
      evaluator: PredicateEvaluator(until.predicate),
      timeout: until.timeout,
      render: renderEvent,
    );
  } else {
    subscription = runtime.events.listen(renderEvent);
  }

  if (!json) {
    write('grid watch — substation work store: ${workspace.root}');
    write(
      'read path: ${bundle.readPath.name}  '
      '(${workspace.mode.name} mode, db ${workspace.database ?? '—'})',
    );
    if (until != null) {
      write(
        'until: ${until.predicate.literal}  ·  timeout '
        '${until.timeout.inSeconds}s',
      );
    }
    final info = await developer.Service.getInfo();
    final uri = info.serverUri;
    write(
      uri != null
          ? 'VM service: $uri  ·  attach exploration_cli/devtools here'
          : 'VM service: not enabled — re-run with `dart run --enable-vm-service`',
    );
    write('—' * 64);
  }

  await runtime.start(); // baseline snapshot + begin reacting

  Future<void> shutdown() async {
    await subscription?.cancel();
    await host.dispose();
    await bundle.shutdown();
  }

  if (until != null) {
    final int code;
    try {
      code = await untilExit!;
    } on StateError catch (e) {
      writeErr('grid watch: ${e.message}');
      await shutdown();
      return kWatchUntilBrokenStream;
    }
    if (!json) {
      write(
        code == kWatchUntilSatisfied
            ? '\ngrid watch: --until ${until.predicate.literal} satisfied.'
            : '\ngrid watch: --until ${until.predicate.literal} did NOT hold '
                  'within ${until.timeout.inSeconds}s.',
      );
    }
    await shutdown();
    return code;
  }

  if (runFor != null) {
    await Future<void>.delayed(runFor);
    await shutdown();
    return 0;
  }
  if (!runForever) {
    await shutdown();
    return 0;
  }

  // Block until Ctrl-C.
  final interrupt = Completer<void>();
  late final StreamSubscription<ProcessSignal> sigint;
  sigint = ProcessSignal.sigint.watch().listen((_) {
    if (!interrupt.isCompleted) interrupt.complete();
  });
  await interrupt.future;
  await sigint.cancel();
  if (!json) write('\ngrid watch: shutting down…');
  await shutdown();
  return 0;
}

/// Runs `grid watch --grid-home <gridHome>`: opens the grid STATE store at its
/// exact root (`<gridHome>/.grid/.beads`, no walk-up — a LOUD refusal if
/// absent), builds a reactive runtime over the pooled Dolt read path the verb
/// already has, and streams typed STATION events (gates, sessions, zero-live,
/// resident liveness, heartbeat) until [until] holds, [runFor] elapses, the
/// resident goes down, or Ctrl-C.
///
/// The read path is the runtime's — `bd show` is never spawned in the loop.
/// Returns a process exit code (see [awaitStationWatch] for the contract).
/// [out]/[err] are injectable for testing; [probeResident] overrides the real
/// lock probe; [residentPoll] paces it; [heartbeatEvery] paces the census line
/// (null disables it).
Future<int> runStationWatch({
  required String gridHome,
  bool json = false,
  bool noSql = false,
  void Function(String)? out,
  void Function(String)? err,
  bool runForever = true,
  Duration? runFor,
  StationWatchUntil? until,
  Duration? heartbeatEvery = const Duration(
    minutes: kDefaultStationHeartbeatMinutes,
  ),
  Duration residentPoll = const Duration(seconds: 5),
  ResidentProbe? probeResident,
}) async {
  final void Function(String) write = out ?? stdout.writeln;
  final void Function(String) writeErr = err ?? stderr.writeln;

  switch (resolveStateWorkspace(
    stationName: 'grid',
    verb: 'watch',
    stateWorkspacePath: gridHome,
  )) {
    case StateWorkspaceRefusal(:final message, :final code):
      writeErr(message);
      return code;
    case StateWorkspaceFound(:final home, :final workspace):
      return _runStationWatchOn(
        home: home,
        workspace: workspace,
        json: json,
        noSql: noSql,
        write: write,
        writeErr: writeErr,
        runForever: runForever,
        runFor: runFor,
        until: until,
        heartbeatEvery: heartbeatEvery,
        residentPoll: residentPoll,
        probeResident:
            probeResident ?? () => probeStationResident(gridHome: home),
      );
  }
}

Future<int> _runStationWatchOn({
  required String home,
  required BeadsWorkspace workspace,
  required bool json,
  required bool noSql,
  required void Function(String) write,
  required void Function(String) writeErr,
  required bool runForever,
  required Duration? runFor,
  required StationWatchUntil? until,
  required Duration? heartbeatEvery,
  required Duration residentPoll,
  required ResidentProbe probeResident,
}) async {
  final bundle = await GridRuntimeFactory.build(
    workspace: workspace,
    preferSql: !noSql,
  );
  final runtime = bundle.runtime;
  final host = GridExplorationHost(
    runtime,
    plugin: GridControllerPlugin(runtime, readPath: () => bundle.readPath.name),
  );
  host.register();

  final renderer = StationWatchEventRenderer(json: json);
  // The baseline census is read from the runtime's own snapshot when the
  // baseline event arrives — `SnapshotInitialized` carries counts only, so the
  // standing gates and live sessions cannot come from the stream.
  final fold = StationFold(baseline: () => stationBaselineOf(runtime.current));

  // Ctrl-C only ends the modes that would otherwise block forever; an armed
  // `--until` or `--for-seconds` keeps the default signal behavior, exactly as
  // the substation-root mode does.
  final wantsInterrupt = runForever && until == null && runFor == null;
  final interrupted = Completer<void>();
  StreamSubscription<ProcessSignal>? sigint;
  if (wantsInterrupt) {
    sigint = ProcessSignal.sigint.watch().listen((_) {
      if (!interrupted.isCompleted) interrupted.complete();
    });
  }

  // Armed BEFORE `runtime.start()`: `awaitStationWatch` subscribes
  // synchronously, so the baseline `SnapshotInitialized` is not missed.
  final exit = awaitStationWatch(
    events: runtime.events,
    fold: fold,
    probeResident: probeResident,
    render: (event) => write(renderer.render(event, at: DateTime.now())),
    until: until,
    residentPoll: residentPoll,
    heartbeatEvery: heartbeatEvery,
    runFor: runFor ?? (runForever ? null : Duration.zero),
    interrupt: wantsInterrupt ? interrupted.future : null,
  );

  if (!json) {
    write('grid watch — station state store: ${workspace.root}');
    write(
      'read path: ${bundle.readPath.name}  '
      '(${workspace.mode.name} mode, db ${workspace.database ?? '—'})',
    );
    write('resident lock: ${StationLockService.lockPath(home)}');
    if (until != null) {
      write(
        'until: ${until.predicate.literal}  ·  timeout '
        '${until.timeout.inSeconds}s',
      );
    }
    write('—' * 64);
  }

  await runtime.start(); // baseline snapshot + begin reacting

  Future<void> shutdown() async {
    await sigint?.cancel();
    await host.dispose();
    await bundle.shutdown();
  }

  final int code;
  try {
    code = await exit;
  } on StateError catch (e) {
    writeErr('grid watch: ${e.message}');
    await shutdown();
    return kWatchUntilBrokenStream;
  } on Object catch (e) {
    writeErr('grid watch: the station watch failed: $e');
    await shutdown();
    return kWatchUntilBrokenStream;
  }
  if (!json && until != null) {
    write(switch (code) {
      kWatchUntilSatisfied =>
        '\ngrid watch: --until ${until.predicate.literal} satisfied.',
      kWatchUntilTimedOut =>
        '\ngrid watch: --until ${until.predicate.literal} did NOT hold '
            'within ${until.timeout.inSeconds}s.',
      kWatchResidentDown =>
        '\ngrid watch: the RESIDENT went down while waiting for --until '
            '${until.predicate.literal}.',
      _ => '\ngrid watch: exiting $code.',
    });
  } else if (!json && code == kWatchResidentDown) {
    write('\ngrid watch: the RESIDENT went down.');
  }
  await shutdown();
  return code;
}
