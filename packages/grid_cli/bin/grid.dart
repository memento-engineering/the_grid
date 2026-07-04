import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';

// The MINIMAL generic bin — only the asset-agnostic driving commands. the_grid
// is a framework, not a turnkey tool (the Dart runner model — see
// docs/SCRATCH-dart-runner-and-cli-sdk.md): a REAL station is a user-composed,
// AOT-compiled runner that assembles the CLI-SDK Commands it wants plus its
// assets' exported Commands (CodeRunCommand/DartCommand from power_station's
// packs, and serve/lease — generic, but parameterized by asset closures like
// the compute dispatch handler). memento's such runner is `space_station`
// (bin/space.dart); this bin deliberately carries none of that opinion.
Future<void> main(List<String> arguments) async {
  final runner =
      CommandRunner<int>('grid', 'the_grid — a reactive beads controller.')
        ..addCommand(WatchCommand())
        ..addCommand(GateCommand())
        ..addCommand(ReworkCommand())
        ..addCommand(DemoCommand());

  try {
    final code = await runner.run(arguments);
    if (code != null && code != 0) exitCode = code;
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  }
}
