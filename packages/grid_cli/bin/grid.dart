import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/src/demo_command.dart';
import 'package:grid_cli/src/gate_command.dart';
import 'package:grid_cli/src/lease_command.dart';
import 'package:grid_cli/src/run_command.dart';
import 'package:grid_cli/src/serve_command.dart';
import 'package:grid_cli/src/watch_command.dart';

Future<void> main(List<String> arguments) async {
  final runner =
      CommandRunner<int>('grid', 'the_grid — a reactive beads controller.')
        ..addCommand(WatchCommand())
        ..addCommand(RunCommand())
        ..addCommand(GateCommand())
        ..addCommand(DemoCommand())
        ..addCommand(ServeCommand())
        ..addCommand(LeaseCommand());

  try {
    final code = await runner.run(arguments);
    if (code != null && code != 0) exitCode = code;
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  }
}

/// `grid watch` — stream typed graph events from the live work graph.
class WatchCommand extends Command<int> {
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
