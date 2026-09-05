import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_trajectory/grid_trajectory.dart' show TrajCommand;

// The MINIMAL generic bin — only the asset-agnostic driving commands. the_grid
// is a framework, not a turnkey tool (the Dart runner model — see
// docs/adr/ADR-0008-authoring-sdk-and-reentrant-engine.md): a REAL station is a user-composed,
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
        ..addCommand(SubstationCommand())
        ..addCommand(ReworkCommand())
        ..addCommand(BeadCommand())
        ..addCommand(DemoCommand())
        // Stage 0's forensics verbs. Composed here for local measurement; a
        // station runner needs its own explicit ..addCommand(TrajCommand()).
        // The factory arms the REAL §9 comparator: shadow-diff opens the grid
        // home's ledger beside the trajectory store and degrades gracefully
        // when the home carries only one of them.
        ..addCommand(TrajCommand(compareFor: legacyShadowCompareFor));

  try {
    final code = await runner.run(arguments);
    if (code != null && code != 0) exitCode = code;
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  }
}
