import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_exploration/grid_exploration.dart';
import 'package:grid_sdk/grid_sdk.dart'
    show DirectoryProbe, StoreRefusal, SubstationWorkStore;

import 'event_renderer.dart';
import 'station_stores.dart';

/// `grid watch <substation-root>` — stream typed graph events from a
/// substation's live work graph. A generic, asset-agnostic CLI-SDK command
/// re-seated on the code-as-config store model
/// (`SCRATCH-station-config-model.md` v3): it watches the work store at ONE
/// substation **root** (`<root>/.beads/`), never the cwd (the ambience fossil,
/// §7 item 9). The composed runner (`space`) supplies the root it authored in
/// its `GridDelegate`; the standalone reference bin takes it explicitly.
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
      );
  }

  @override
  final String name = 'watch';

  @override
  final String description =
      'Watch a substation work graph and print typed events with reaction '
      'latency. Takes the substation ROOT (its `.beads/` work store lives at '
      '`<root>/.beads/`) — no cwd discovery. Run under `dart run '
      '--enable-vm-service` to allow exploration tools to attach.';

  @override
  String get invocation =>
      'grid watch <substation-root> [--json] [--for-seconds N]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;
    if (rest.isEmpty) {
      stderr.writeln(
        'grid watch: a <substation-root> is required (the substation whose '
        '`.beads/` work graph to watch). There is no cwd discovery — name the '
        'root the delegate authored.',
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
    );
  }
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
Future<int> runWatch({
  required SubstationWorkStore store,
  bool json = false,
  bool noSql = false,
  void Function(String)? out,
  void Function(String)? err,
  bool runForever = true,
  Duration? runFor,
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
  final subscription = runtime.events.listen((event) {
    write(
      renderer.render(
        event,
        reaction: runtime.stats.lastReaction,
        at: DateTime.now(),
      ),
    );
  });

  if (!json) {
    write('grid watch — substation work store: ${workspace.root}');
    write(
      'read path: ${bundle.readPath.name}  '
      '(${workspace.mode.name} mode, db ${workspace.database ?? '—'})',
    );
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
    await subscription.cancel();
    await host.dispose();
    await bundle.shutdown();
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
