/// `traj` — the trajectory-log verb group.
///
/// Domain-owned verbs live beside the domain (decision:
/// grid-trajectory-leaf-package); composition into any runner stays an
/// explicit `..addCommand(TrajCommand())`, per runner.
library;

import 'package:args/command_runner.dart';

import 'shadow_accounting.dart';
import 'traj_gc_command.dart';
import 'traj_provision_command.dart';
import 'traj_replay_command.dart';
import 'traj_shadow_diff_command.dart';
import 'traj_show_command.dart';
import 'trajectory_reader.dart';

class TrajCommand extends Command<int> {
  /// Creates the group. [open] and [compare] are injected straight through to
  /// the subcommands so a runner (or a test) can supply its own seams.
  TrajCommand({
    TrajectoryOpener? open,
    ShadowCompare compare = const UncomparableShadow(),
    ShadowCompareFactory? compareFor,
    ShadowAccountingSource? accountingFor,
    ProvisionConnect? connect,
  }) {
    addSubcommand(TrajShowCommand(open: open));
    addSubcommand(
      TrajShadowDiffCommand(
        open: open,
        compare: compare,
        compareFor: compareFor,
        accountingFor: accountingFor,
      ),
    );
    // `provision` is the one WRITING verb in the group — the runbook's step 2
    // (§4). It is composed here rather than in a separate group because an
    // operator who knows `traj show` should not have to learn a second noun
    // to bootstrap the thing it reads.
    addSubcommand(TrajProvisionCommand(connect: connect));
    // The two OPERATOR verbs (cut-wiring C0). `replay` rebuilds the fold and
    // is QUIESCE-ONLY — it fences itself on the station lock. `gc` is
    // reclamation under the gridboot credential, the operator half of the
    // cadence the harness disables on a scoped-grant home (tg-3o6b). Both
    // share `provision`'s connect seam: one SQL shape, three credentials
    // resolved inside the verbs.
    addSubcommand(TrajReplayCommand(connect: connect));
    addSubcommand(TrajGcCommand(connect: connect));
  }

  @override
  final String name = 'traj';

  @override
  final String description =
      'Read the trajectory log: per-subject history and the shadow '
      'comparator; provision it on a fresh grid home; rebuild the fold '
      '(quiesced) and reclaim the database.';

  @override
  Future<int> run() async {
    printUsage();
    return 64;
  }
}
