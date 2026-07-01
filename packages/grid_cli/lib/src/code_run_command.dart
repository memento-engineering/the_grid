/// The `code` asset's run command — a [StationRunCommand] configured with the
/// `code` trio (ADR-0008 D1 asset seam).
///
/// This is the reusable CLI component the CODE ASSET offers alongside its domain
/// components (`buildCodeRegistry` / `kCodeFormula`). It lives in `grid_cli` for
/// now ONLY because the physical repo split is deferred: exporting it from
/// `grid_assets` today would cycle (`grid_cli` → `grid_assets` → `grid_cli`). At
/// the `power_station` split it moves to the code asset, over the extracted CLI-SDK
/// framework lib — the runner just `..addCommand(CodeRunCommand())`.
library;

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_controller/grid_controller.dart' show Bead;
import 'package:grid_engine/grid_engine.dart';

import 'station_run_command.dart';

/// The bead→formula policy for the `code` asset — all coding work roots the
/// `code` formula (agent → review → land). A top-level tear-off so
/// [FormulaResolver] stays const.
Formula _codeFormula(Bead bead) => kCodeFormula;

/// `grid run` for the `code` asset: the reentrant tree engine spawning a coding
/// agent per ready bead, wired with the `code` formula + [buildCodeRegistry].
class CodeRunCommand extends StationRunCommand {
  /// Creates the code run command (the `code` trio into the de-opinionated base).
  CodeRunCommand()
    : super(
        resolver: const FormulaResolver(_codeFormula),
        registry: buildCodeRegistry(),
      );

  @override
  final String name = 'run';

  @override
  final String description =
      'Run the CODE asset on the tree engine (tree-as-default): the reactive '
      'controller + the reentrant engine that spawns a coding agent per ready '
      'bead, over one shared ownership allow-set. Defaults to --dry-run '
      '(observe-only). Run under `dart run --enable-vm-service` so leonard can '
      'attach.';
}
