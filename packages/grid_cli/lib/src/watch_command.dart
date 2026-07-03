import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_exploration/grid_exploration.dart';

import 'event_renderer.dart';

/// `grid watch` — stream typed graph events from the live work graph. A
/// generic, asset-agnostic CLI-SDK command (moved out of the reference bin at
/// the repo split so any station runner can assemble it).
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
      'Watch the work graph and print typed events with reaction latency. '
      'Run under `dart run --enable-vm-service` to allow exploration tools to '
      'attach.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final seconds = args.option('for-seconds');
    return runWatch(
      json: args.flag('json'),
      noSql: args.flag('no-sql'),
      runFor: seconds == null ? null : Duration(seconds: int.parse(seconds)),
    );
  }
}

/// Runs `grid watch`: discovers the workspace, builds a reactive runtime,
/// registers the exploration host (so exploration_cli/devtools can attach),
/// prints the VM service URI, and streams typed graph events with measured
/// reaction latency until interrupted.
///
/// Returns a process exit code. [out]/[err] are injectable for testing; the
/// signal wait is skipped when [runForever] is false (tests drive a fixed
/// duration via [runFor]).
Future<int> runWatch({
  bool json = false,
  bool noSql = false,
  void Function(String)? out,
  void Function(String)? err,
  bool runForever = true,
  Duration? runFor,
  BeadsWorkspace? workspaceOverride,
}) async {
  final write = out ?? stdout.writeln;
  final writeErr = err ?? stderr.writeln;

  final workspace = workspaceOverride ?? BeadsWorkspace.discover();
  if (workspace == null) {
    writeErr(
      'grid watch: no .beads/ workspace found from ${Directory.current.path}',
    );
    return 1;
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
    write('grid watch — workspace: ${workspace.root}');
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
