import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_runtime/grid_runtime.dart';

/// `grid gate` — list and resolve the committee gates The Circuit parks (D-7).
///
/// The Circuit's route step parks a work circuit at a `type=gate` bead when the
/// committee blocks (a gating-F, a grade spread ≥ 3 across the lanes, or any
/// non-gating critic at D/F). The gate bead lives in the_grid's OWN state store
/// (the `--state-substation`, e.g. `tgdog`); it carries `metadata.blocks` (the
/// session id), `metadata.node` (the parked node path), and `metadata.reason`.
/// `StationJoinBridge._attachOpenGates` folds every OPEN gate into the matching
/// session's `openGateNodes`, and `SessionScope` re-arms the parked node
/// (`gated → pending`) on the next snapshot ONLY once that gate bead is CLOSED.
///
/// This command is a CLI-only shim over the EXISTING re-arm mechanic — closing
/// the gate bead is already sufficient. It groups two subcommands:
///
///  * `grid gate ls`            — list open gates (read-only);
///  * `grid gate resolve <id>`  — close one gate THROUGH the [StationBeadWriter]
///    chokepoint (`--actor grid-controller`), fail-closed on ownership + type.
///
/// **Coexistence safety.** Only the_grid's OWN state store (the
/// `--state-substation`) is ever written; the read work source is never touched.
/// All writes flow through the bd-only chokepoint — never raw SQL, never
/// `bd show` from this controller path (it self-triggers the watcher).
class GateCommand extends Command<int> {
  GateCommand() {
    addSubcommand(GateLsCommand());
    addSubcommand(GateResolveCommand());
  }

  @override
  final String name = 'gate';

  @override
  final String description =
      'List and resolve the committee gates The Circuit parks (ADR-0008 D-7). '
      'A gate bead lives in the_grid\'s OWN state store (--state-substation); '
      'closing it re-arms the parked circuit node (gated → pending) on the next '
      '`grid run` snapshot.';

  @override
  Future<int> run() async {
    // Reached only when `grid gate` is invoked with no subcommand.
    printUsage();
    return 64;
  }
}

/// Adds the `--state-workspace` / `--state-substation` options shared by both
/// subcommands — the SAME store `grid run` writes its session/gate beads to.
void _addStateOptions(ArgParser parser) {
  parser
    ..addOption(
      'state-workspace',
      help:
          'the_grid\'s OWN beads state store (the directory at or above the '
          '`.beads/` `grid run` writes session/gate beads to). `resolve` '
          'REQUIRES it; `ls` defaults to discovery from the cwd.',
    )
    ..addOption(
      'state-substation',
      defaultsTo: 'tgdog',
      help:
          'the_grid\'s OWNED session/gate partition (the prefix of the state '
          'store, e.g. `tgdog`). Seeds the ownership allow-set the resolve '
          'chokepoint re-checks fail-closed.',
    );
}

/// `grid gate ls` — list every OPEN `type=gate` bead in the state store.
class GateLsCommand extends Command<int> {
  GateLsCommand() {
    _addStateOptions(argParser);
  }

  @override
  final String name = 'ls';

  @override
  final String description =
      'List the OPEN committee gates parked in the_grid\'s state store '
      '(read-only: no writes). Each line shows the gate id, the session it '
      'blocks, the parked node path, the reason, and the gate\'s age.';

  @override
  Future<int> run() async {
    final args = argResults!;
    return runGateLs(
      stateWorkspacePath: args.option('state-workspace'),
      stateSubstation: args.option('state-substation') ?? 'tgdog',
    );
  }
}

/// `grid gate resolve <gate-id>` — close one gate through the chokepoint.
class GateResolveCommand extends Command<int> {
  GateResolveCommand() {
    _addStateOptions(argParser);
  }

  @override
  final String name = 'resolve';

  @override
  final String description =
      'Resolve (close) ONE committee gate through the StationBeadWriter '
      'chokepoint (--actor grid-controller), re-arming the parked circuit node. '
      'Fail-closed: refuses (non-zero, zero writes) unless the id names a found, '
      'OPEN, owned type=gate bead. REQUIRES --state-workspace.';

  @override
  String get invocation => 'grid gate resolve <gate-id> [--state-workspace …]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;
    if (rest.isEmpty) {
      stderr.writeln(
        'grid gate resolve: a <gate-id> is required (the gate bead to close).',
      );
      return 64;
    }
    if (rest.length > 1) {
      stderr.writeln(
        'grid gate resolve: resolve closes ONE gate at a time — got '
        '${rest.length} ids (${rest.join(', ')}).',
      );
      return 64;
    }
    return runGateResolve(
      gateId: rest.single,
      stateWorkspacePath: args.option('state-workspace'),
      stateSubstation: args.option('state-substation') ?? 'tgdog',
    );
  }
}

/// Runs `grid gate ls`: discovers the state store, reads OPEN `type=gate` beads
/// via the snapshot read path the controller already uses
/// ([BdCliService.exportAll] — never `bd show` in a loop), and prints each.
///
/// Read-only — performs NO writes. Seams ([workspaceOverride]/[bdOverride]/[now])
/// are injectable so an offline test drives it with a fake store.
Future<int> runGateLs({
  String? stateWorkspacePath,
  String stateSubstation = 'tgdog',
  void Function(String)? out,
  void Function(String)? err,
  BeadsWorkspace? workspaceOverride,
  BdCliService? bdOverride,
  DateTime? now,
}) async {
  final void Function(String) write = out ?? (m) => stdout.writeln(m);
  final void Function(String) writeErr = err ?? (m) => stderr.writeln(m);

  final workspace =
      workspaceOverride ?? BeadsWorkspace.discover(start: stateWorkspacePath);
  if (workspace == null) {
    writeErr(
      'grid gate ls: no .beads/ state store found from '
      '${stateWorkspacePath ?? Directory.current.path}',
    );
    return 1;
  }

  final bd =
      bdOverride ?? BdCliService(ProcessBdRunner(workspaceRoot: workspace.root));

  // The COMPLETE-graph snapshot read (issues ∪ wisps, all statuses, gate-typed
  // beads included). `exportAll` is the safe snapshot path — unlike `bd show`,
  // it does not write `.beads/last-touched` and self-trigger the watcher.
  final export = await bd.exportAll();
  final gates =
      export.beads
          .where((b) => b.issueType == IssueType.gate && !b.isClosed)
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));

  if (gates.isEmpty) {
    write('grid gate ls — no open gates in ${workspace.root}.');
    return 0;
  }

  final clock = now ?? DateTime.now();
  write(
    'grid gate ls — ${gates.length} open gate'
    '${gates.length == 1 ? '' : 's'} in ${workspace.root}:',
  );
  for (final gate in gates) {
    final blocks = _meta(gate, 'blocks') ?? '<no session>';
    final node = _meta(gate, 'node') ?? '<no node>';
    final reason = _meta(gate, 'reason') ?? '';
    final age = _humanAge(gate.createdAt, clock);
    write(
      '  ${gate.id}  blocks $blocks  node $node  age $age'
      '${reason.isEmpty ? '' : '\n    reason: $reason'}',
    );
  }
  return 0;
}

/// Runs `grid gate resolve <gateId>`: closes the named gate THROUGH the
/// [StationBeadWriter] chokepoint, re-arming the parked circuit node.
///
/// **Fail-closed (non-zero exit, ZERO writes)** unless [gateId] names a bead
/// that is (a) found in the store, (b) `type=gate`, (c) OPEN, and (d) owned by
/// [stateSubstation]. The chokepoint re-checks ownership independently; this
/// command adds the found/type/open guards on top before the close ever runs.
///
/// REQUIRES a state store: an explicit `--state-workspace` (or [workspaceOverride]
/// in tests) — resolve is a write and never discovers a store implicitly.
Future<int> runGateResolve({
  required String gateId,
  String? stateWorkspacePath,
  String stateSubstation = 'tgdog',
  void Function(String)? out,
  void Function(String)? err,
  BeadsWorkspace? workspaceOverride,
  BdCliService? bdOverride,
}) async {
  final void Function(String) write = out ?? (m) => stdout.writeln(m);
  final void Function(String) writeErr = err ?? (m) => stderr.writeln(m);

  // resolve is a WRITE — it never discovers a store implicitly (the read work
  // source must stay untouched). The state store must be named explicitly.
  if (stateWorkspacePath == null && workspaceOverride == null) {
    writeErr(
      'grid gate resolve: --state-workspace is required (the_grid\'s OWN state '
      'store where the gate bead lives). resolve is a write — it never defaults '
      'to the read --workspace.',
    );
    return 64;
  }

  final workspace =
      workspaceOverride ?? BeadsWorkspace.discover(start: stateWorkspacePath);
  if (workspace == null) {
    writeErr(
      'grid gate resolve: no .beads/ state store found from $stateWorkspacePath',
    );
    return 1;
  }

  final bd =
      bdOverride ?? BdCliService(ProcessBdRunner(workspaceRoot: workspace.root));

  // Locate the named bead via the safe snapshot read (NOT `bd show`).
  final export = await bd.exportAll();
  Bead? bead;
  for (final candidate in export.beads) {
    if (candidate.id == gateId) {
      bead = candidate;
      break;
    }
  }

  // The shared ownership allow-set — the SAME Set<String> the chokepoint
  // re-checks fail-closed (ADR-0000 A32). One instance, no drift.
  final ownership = BeadOwnershipPredicate({stateSubstation});

  // --- fail-closed guards (zero writes on any refusal) -----------------------
  if (bead == null) {
    writeErr(
      'grid gate resolve: no bead "$gateId" in ${workspace.root} — nothing '
      'closed.',
    );
    return 1;
  }
  if (bead.issueType != IssueType.gate) {
    writeErr(
      'grid gate resolve: "$gateId" is type ${bead.issueType.wire}, not a gate '
      '— refused (this command only resolves committee gates).',
    );
    return 64;
  }
  if (bead.isClosed) {
    writeErr(
      'grid gate resolve: gate "$gateId" is already closed (resolved) — its '
      'parked node has already re-armed.',
    );
    return 64;
  }
  if (!ownership.owns(bead)) {
    writeErr(
      'grid gate resolve: gate "$gateId" is not owned by state substation '
      '"$stateSubstation" — refused (fail-closed, ADR-0006 Decision 2).',
    );
    return 64;
  }

  // Close through the chokepoint (bd-only, --actor grid-controller). The
  // chokepoint re-asserts ownership before the write — a second line of
  // defense behind the guards above.
  final writer = StationBeadWriter(
    bd: bd,
    ownership: ownership,
    onRefusal: writeErr,
  );
  try {
    await writer.close(gateId, reason: 'resolved via grid gate resolve');
  } on OwnershipRefused catch (e) {
    writeErr('grid gate resolve: $e');
    return 64;
  }

  final blocks = _meta(bead, 'blocks') ?? '<no session>';
  final node = _meta(bead, 'node') ?? '<no node>';
  write('grid gate resolve — closed gate $gateId (blocks $blocks @ $node).');
  write(
    'The next/running `grid run` re-arms the parked node (gated → pending) on '
    'its next snapshot.',
  );
  return 0;
}

/// Reads a string metadata value off a gate bead, or null when absent/empty.
String? _meta(Bead bead, String key) {
  final value = bead.metadata[key];
  if (value is String && value.isNotEmpty) return value;
  return null;
}

/// A compact human age for a gate (`5s`, `12m`, `2h3m`, `1d4h`). `?` when the
/// bead carries no `created_at`.
String _humanAge(DateTime? createdAt, DateTime now) {
  if (createdAt == null) return '?';
  var d = now.difference(createdAt);
  if (d.isNegative) d = Duration.zero;
  if (d.inDays > 0) return '${d.inDays}d${d.inHours % 24}h';
  if (d.inHours > 0) return '${d.inHours}h${d.inMinutes % 60}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}
