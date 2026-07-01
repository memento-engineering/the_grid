/// The CLI-SDK's de-opinionated station-run base (the Dart runner model — see
/// `docs/SCRATCH-dart-runner-and-cli-sdk.md`).
///
/// `the_grid` is a framework, not a turnkey tool: a station is a user-composed,
/// AOT-compiled runner that assembles the [Command]s it wants. [StationRunCommand]
/// is the reusable base the CLI SDK ships — it owns the STANDARD station flags +
/// the barrier→restart→mount live-wiring (via [runGridTree]) and takes the ASSET
/// TRIO ([resolver] + [registry]) as configuration. It bakes in NO asset: a
/// concrete run command (the code asset's [CodeRunCommand], a future burn's) just
/// supplies its trio + a name/description. This is what dissolves the
/// over-opinionated monolithic `grid run` (Nico's long-standing critique).
library;

import 'package:args/command_runner.dart';
import 'package:grid_engine/grid_engine.dart';

import 'run_command.dart' show RuntimeProviderKind;
import 'run_tree_command.dart' show runGridTree;

/// The reusable, asset-agnostic `run` base. A concrete run command extends this,
/// passing its [resolver] + [registry] (the ADR-0008 D1 asset seam) and its own
/// `name`/`description`. The git/root/land wiring stays the `code` default inside
/// [runGridTree] for now (a non-code asset passes no `--root` ⇒ inert git); its
/// full extraction into an asset `servicesFor` is the repo-split follow-up.
abstract class StationRunCommand extends Command<int> {
  /// Creates the base with the ASSET TRIO — the bead→formula [resolver] and the
  /// capability [registry] the tree mounts. The subclass supplies these + a
  /// `name`/`description`.
  StationRunCommand({required this.resolver, required this.registry}) {
    argParser
      ..addMultiOption(
        'substation',
        abbr: 'r',
        help:
            'An OWNED substation / ownership token (repeatable) — the SINGLE '
            'allow-set feeding both the ownership gate and the dispatch '
            'predicate. The dogfood substation is `tgdog`.',
      )
      ..addMultiOption(
        'owner',
        help: 'Alias for --substation; merged into one shared allow-set.',
      )
      ..addOption(
        'provider',
        allowed: ['subprocess', 'tmux'],
        defaultsTo: 'subprocess',
        help: 'The runtime provider for agent spawns.',
      )
      ..addOption(
        'root',
        help:
            'The registered worktree root checkout. Required to ARM a non-dry '
            'run; never created by the runner.',
      )
      ..addOption(
        'head',
        help:
            'ASSIGN the base branch per-bead worktrees cut from, overriding the '
            'probed origin/HEAD. Omit to probe.',
      )
      ..addOption(
        'workspace',
        abbr: 'w',
        help:
            'The beads workspace to read ready work from (a dir at or above a '
            '`.beads/`). Defaults to discovery from the cwd; read-only under '
            '--dry-run.',
      )
      ..addOption(
        'state-workspace',
        help:
            'A SEPARATE the_grid-owned beads workspace for its own session/'
            'lifecycle beads (A36/A37), so the --workspace source stays '
            'read-only. Omit to write sessions into --workspace.',
      )
      ..addOption(
        'state-substation',
        defaultsTo: 'tgdog',
        help:
            "the_grid's OWNED session partition (the --state-workspace prefix), "
            'unioned into the allow-set. Only used with --state-workspace.',
      )
      ..addMultiOption(
        'bead',
        abbr: 'b',
        help:
            'A specific work-bead id to drive (repeatable) — the blessed '
            'drive-list layered on the allow-set (ADR-0006). REQUIRED for a live '
            '(--no-dry-run) arm; in --dry-run omit to observe every owned bead.',
      )
      ..addFlag(
        'dry-run',
        defaultsTo: true,
        help:
            'Observe-only: NO writes, NO spawns (the SAFE DEFAULT). Pass '
            '--no-dry-run to ARM the live writing arm (requires --root).',
      )
      ..addFlag(
        'land',
        defaultsTo: false,
        negatable: false,
        help:
            'ARM the land step (ADR-0006 D3): on step-complete, commit → push → '
            'open a PR (never auto-merges). OPT-IN, OFF by default; requires '
            '--no-dry-run.',
      )
      ..addOption(
        'for-seconds',
        help: 'Run for a fixed number of seconds then exit (scripted / CI).',
      )
      ..addFlag(
        'no-sql',
        negatable: false,
        help: 'Force the bd-CLI read path even when pooled Dolt SQL is available.',
      );
  }

  /// The bead→formula policy the tree roots (the ADR-0008 D1 asset seam).
  final FormulaResolver resolver;

  /// The capability set + formulas the tree mounts.
  final CapabilityRegistry registry;

  @override
  Future<int> run() async {
    final args = argResults!;
    final seconds = args.option('for-seconds');
    final substations = <String>{
      ...args.multiOption('substation'),
      ...args.multiOption('owner'),
    }..removeWhere((r) => r.trim().isEmpty);

    return runGridTree(
      substations: substations,
      resolver: resolver,
      registry: registry,
      provider: RuntimeProviderKind.parse(args.option('provider')),
      rootPath: args.option('root'),
      head: args.option('head'),
      workspacePath: args.option('workspace'),
      stateWorkspacePath: args.option('state-workspace'),
      stateSubstation: args.option('state-workspace') == null
          ? null
          : args.option('state-substation'),
      targetBeads: <String>{...args.multiOption('bead')}
        ..removeWhere((b) => b.trim().isEmpty),
      dryRun: args.flag('dry-run'),
      land: args.flag('land'),
      noSql: args.flag('no-sql'),
      runFor: seconds == null ? null : Duration(seconds: int.parse(seconds)),
    );
  }
}
