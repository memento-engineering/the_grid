/// `traj` — the trajectory-log verb group.
///
/// Domain-owned verbs live beside the domain (decision:
/// grid-trajectory-leaf-package); composition into any runner stays an
/// explicit `..addCommand(TrajCommand())`, per runner.
library;

import 'package:args/command_runner.dart';

import 'traj_shadow_diff_command.dart';
import 'traj_show_command.dart';
import 'trajectory_reader.dart';

class TrajCommand extends Command<int> {
  /// Creates the group. [open] and [compare] are injected straight through to
  /// the subcommands so a runner (or a test) can supply its own seams.
  TrajCommand({
    TrajectoryOpener? open,
    ShadowCompare compare = const UncomparableShadow(),
  }) {
    addSubcommand(TrajShowCommand(open: open));
    addSubcommand(TrajShadowDiffCommand(open: open, compare: compare));
  }

  @override
  final String name = 'traj';

  @override
  final String description =
      'Read the trajectory log: per-subject history and the shadow '
      'comparator.';

  @override
  Future<int> run() async {
    printUsage();
    return 64;
  }
}
