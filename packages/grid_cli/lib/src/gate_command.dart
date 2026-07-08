import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart'
    show DirectoryProbe, GridStateStore, StoreRefusal;

import 'station_stores.dart';

/// `grid gate` — list and resolve the committee gates The Circuit parks (D-7).
///
/// The Circuit's route step parks a work circuit at a `type=gate` bead when the
/// committee blocks (a gating-F, a grade spread ≥ 3 across the lanes, or any
/// non-gating critic at D/F). The gate bead lives in the_grid's OWN **state
/// store** — under `<grid.root>/.grid/.beads/` (Q5a; the code-as-config store
/// model, `SCRATCH-station-config-model.md` v3). It carries `metadata.blocks`
/// (the session id), `metadata.node` (the parked node path), and
/// `metadata.reason`. `StationJoinBridge._attachOpenGates` folds every OPEN gate
/// into the matching session's `openGateNodes`, and `SessionScope` re-arms the
/// parked node (`gated → pending`) on the next snapshot ONLY once that gate bead
/// is CLOSED.
///
/// This command is a CLI-only shim over the EXISTING re-arm mechanic — closing
/// the gate bead is already sufficient. It groups two subcommands:
///
///  * `grid gate ls`            — list open gates (read-only);
///  * `grid gate resolve <id>`  — close one gate THROUGH the [StationBeadWriter]
///    chokepoint (`--actor grid-controller`), fail-closed on ownership + type,
///    optionally RULING the lane grades that fed it first (tg-i08).
///
/// **Re-seated on the store-at-roots model (v3).** The grid state store is
/// addressed from the **grid root** (`--grid-root`) at `<grid.root>/.grid/.beads/`,
/// exactly — never `--state-workspace` / cwd discovery (the killed ambience). The
/// state-store ownership prefix is a supplied **value** (`--prefix`), not the
/// retired `--state-substation` flag (the `tgdog` home dies with the rebuild).
///
/// **Coexistence safety.** Only the_grid's OWN state store is ever written; the
/// read work source is never touched. All writes flow through the bd-only
/// chokepoint — never raw SQL, never `bd show` from this controller path (it
/// self-triggers the watcher).
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
      'A gate bead lives in the_grid\'s OWN state store '
      '(<grid.root>/.grid/.beads/); closing it re-arms the parked circuit node '
      '(gated → pending) on the next snapshot.';

  @override
  Future<int> run() async {
    // Reached only when `grid gate` is invoked with no subcommand.
    printUsage();
    return 64;
  }
}

/// Adds the `--grid-root` option both subcommands share — the grid home from
/// which the state store (`<grid.root>/.grid/.beads/`) is derived.
void _addGridRootOption(ArgParser parser) {
  parser.addOption(
    'grid-root',
    help:
        'The grid HOME (an absolute path). The state store `grid run`/`space up` '
        'writes session/gate beads to is derived at `<grid.root>/.grid/.beads/` '
        '(Q5a) — no cwd discovery, no walk-up.',
  );
}

/// Resolves the grid state store from a `--grid-root` value, or writes a refusal
/// and returns null (the caller returns the exit code).
GridStateStore? _stateStoreFromArgs(
  ArgResults args,
  void Function(String) writeErr,
  String verb,
) {
  final gridRoot = args.option('grid-root');
  if (gridRoot == null || gridRoot.trim().isEmpty) {
    writeErr(
      'grid $verb: --grid-root is required (the grid HOME; the state store is '
      'at <grid.root>/.grid/.beads/). There is no cwd discovery.',
    );
    return null;
  }
  try {
    return GridStateStore.forGridRoot(gridRoot);
  } on ArgumentError catch (e) {
    writeErr('grid $verb: --grid-root ${e.message}');
    return null;
  }
}

/// `grid gate ls` — list every OPEN `type=gate` bead in the state store.
class GateLsCommand extends Command<int> {
  GateLsCommand() {
    _addGridRootOption(argParser);
  }

  @override
  final String name = 'ls';

  @override
  final String description =
      'List the OPEN committee gates parked in the_grid\'s state store '
      '(read-only: no writes). Each line shows the gate id, the session it '
      'blocks, the parked node path, the reason, and the gate\'s age.';

  @override
  String get invocation => 'grid gate ls --grid-root <dir>';

  @override
  Future<int> run() async {
    final args = argResults!;
    final store = _stateStoreFromArgs(args, stderr.writeln, 'gate ls');
    if (store == null) return 64;
    return runGateLs(stateStore: store);
  }
}

/// `grid gate resolve <gate-id>` — close one gate through the chokepoint,
/// optionally RULING the lane grades that fed it first (tg-i08).
class GateResolveCommand extends Command<int> {
  GateResolveCommand() {
    _addGridRootOption(argParser);
    argParser
      ..addOption(
        'prefix',
        help:
            'the_grid\'s OWNED session/gate id-prefix (the state store\'s '
            'adopted prefix, e.g. the grid\'s own name). Seeds the ownership '
            'allow-set the resolve chokepoint re-checks fail-closed. REQUIRED.',
      )
      ..addMultiOption(
        'grade',
        help:
            'Rule a committee lane grade BEFORE closing: <lane>=<A-F> '
            '(repeatable). Writes the corrected grade + transport='
            'operator-ruling through the chokepoint onto the session bead so '
            'the route re-reads it instead of re-gating on the persisted F '
            '(the I-14 no-op loop). A bare <lane> resolves to a sibling of the '
            'parked node; pass a full node path to target elsewhere. Requires '
            '--rationale.',
      )
      ..addOption(
        'rationale',
        help:
            'Why you are overriding the lane grade(s) — REQUIRED with --grade. '
            'Recorded on the session bead as the ruling audit trail.',
      );
  }

  @override
  final String name = 'resolve';

  @override
  final String description =
      'Resolve (close) ONE committee gate through the StationBeadWriter '
      'chokepoint (--actor grid-controller), re-arming the parked circuit node. '
      'Fail-closed: refuses (non-zero, zero writes) unless the id names a found, '
      'OPEN, owned type=gate bead. A gate born from a persisted lane F is '
      'refused LOUD unless you RULE the lane (--grade/--rationale) — a plain '
      'resolve would re-gate on the next snapshot. REQUIRES --grid-root and '
      '--prefix.';

  @override
  String get invocation =>
      'grid gate resolve <gate-id> [--grade <lane>=<A-F> --rationale <why>] '
      '--grid-root <dir> --prefix <name>';

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
    final store = _stateStoreFromArgs(args, stderr.writeln, 'gate resolve');
    if (store == null) return 64;
    final prefix = args.option('prefix');
    if (prefix == null || prefix.trim().isEmpty) {
      stderr.writeln(
        'grid gate resolve: --prefix is required (the state store\'s owned '
        'id-prefix — the ownership allow-set the chokepoint re-checks).',
      );
      return 64;
    }
    return runGateResolve(
      gateId: rest.single,
      grades: args.multiOption('grade'),
      rationale: args.option('rationale'),
      stateStore: store,
      stateStorePrefix: prefix,
    );
  }
}

/// Runs `grid gate ls`: opens the grid state store at [stateStore]
/// (`<grid.root>/.grid/.beads/`, exact — LOUD [StoreRefusal] if absent), reads
/// OPEN `type=gate` beads via the snapshot read path the controller already uses
/// ([BdCliService.exportAll] — never `bd show` in a loop), and prints each.
///
/// Read-only — performs NO writes. Seams
/// ([workspaceOverride]/[bdOverride]/[dirExists]/[now]) are injectable so an
/// offline test drives it with a fake store.
Future<int> runGateLs({
  required GridStateStore stateStore,
  void Function(String)? out,
  void Function(String)? err,
  BeadsWorkspace? workspaceOverride,
  BdCliService? bdOverride,
  DirectoryProbe? dirExists,
  DateTime? now,
}) async {
  final void Function(String) write = out ?? (m) => stdout.writeln(m);
  final void Function(String) writeErr = err ?? (m) => stderr.writeln(m);

  final BeadsWorkspace workspace;
  if (workspaceOverride != null) {
    workspace = workspaceOverride;
  } else {
    try {
      workspace = openStateStore(stateStore, dirExists: dirExists);
    } on StoreRefusal catch (e) {
      writeErr('grid gate ls: ${e.message}');
      return 1;
    }
  }

  final bd =
      bdOverride ??
      BdCliService(ProcessBdRunner(workspaceRoot: workspace.root));

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
    // A re-gated gate (mint-dedup, tg-i08) shows a RESET age (from its last
    // re-gate, not its birth) + a `re-gated Nx` marker, so a re-gate is visible
    // on the same stable gate id instead of hidden behind an old creation date.
    final regateCount =
        int.tryParse(
          '${gate.metadata[StationBeadWriter.gateRegateCountKey] ?? ''}',
        ) ??
        0;
    final regatedAt = DateTime.tryParse(
      '${gate.metadata[StationBeadWriter.gateRegatedAtKey] ?? ''}',
    );
    final age = _humanAge(regatedAt ?? gate.createdAt, clock);
    final regateMark = regateCount > 0 ? '  re-gated ${regateCount}x' : '';
    write(
      '  ${gate.id}  blocks $blocks  node $node  age $age$regateMark'
      '${reason.isEmpty ? '' : '\n    reason: $reason'}',
    );
  }
  return 0;
}

/// Runs `grid gate resolve <gateId>`: optionally RULES the lane grades that fed
/// the gate, then closes it THROUGH the [StationBeadWriter] chokepoint,
/// re-arming the parked circuit node (tg-i08).
///
/// **Fail-closed (non-zero exit, ZERO writes)** unless [gateId] names a bead
/// that is (a) found in the store, (b) `type=gate`, (c) OPEN, and (d) owned by
/// [stateStorePrefix]. The chokepoint re-checks ownership independently; this
/// command adds the found/type/open guards on top before the close ever runs.
///
/// **The ruling verb (I-14 loop fix).** The route step gates on the PERSISTED
/// lane grades on the session bead (`grid.result.<lane>.grade`), not the fresh
/// verdict files. So closing a gate born from a persisted `F` re-arms the node,
/// the route re-reads the SAME `F`, and it re-gates seconds later — a plain
/// resolve is a guaranteed no-op loop. This verb breaks it two ways:
///
///  * with [grades] (`<lane>=<A-F>`, requires [rationale]) it writes the
///    corrected grade + `transport=operator-ruling` + the rationale through the
///    chokepoint onto the session bead FIRST, so the route re-reads the
///    corrected grade and advances instead of re-gating; then it closes;
///  * WITHOUT a correction, if the parked node still has a feeding lane at `F`,
///    it REFUSES LOUD (nothing written) — naming the offending lanes + their
///    transport provenance — rather than silently looping.
///
/// A bare `<lane>` resolves to a sibling of the parked node (the committee
/// shape: `route` and its critics share a parent); a `<lane>` containing `/` is
/// used as a full node path verbatim. A non-committee gate (no feeding lane
/// grades) resolves plainly, as before.
///
/// Opens the state store at [stateStore] (`<grid.root>/.grid/.beads/`, exact —
/// LOUD [StoreRefusal] if absent). The state store is the grid's OWN store,
/// distinct from any work source (A37) — resolve never touches the read work
/// source.
Future<int> runGateResolve({
  required String gateId,
  List<String> grades = const [],
  String? rationale,
  required GridStateStore stateStore,
  required String stateStorePrefix,
  void Function(String)? out,
  void Function(String)? err,
  BeadsWorkspace? workspaceOverride,
  BdCliService? bdOverride,
  DirectoryProbe? dirExists,
}) async {
  final void Function(String) write = out ?? (m) => stdout.writeln(m);
  final void Function(String) writeErr = err ?? (m) => stderr.writeln(m);

  final BeadsWorkspace workspace;
  if (workspaceOverride != null) {
    workspace = workspaceOverride;
  } else {
    try {
      workspace = openStateStore(stateStore, dirExists: dirExists);
    } on StoreRefusal catch (e) {
      writeErr('grid gate resolve: ${e.message}');
      return 1;
    }
  }

  final bd =
      bdOverride ??
      BdCliService(ProcessBdRunner(workspaceRoot: workspace.root));

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
  final ownership = BeadOwnershipPredicate({stateStorePrefix});

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
      'grid gate resolve: gate "$gateId" is not owned by state prefix '
      '"$stateStorePrefix" — refused (fail-closed, ADR-0006 Decision 2).',
    );
    return 64;
  }

  final node = _meta(bead, 'node');
  final sessionId = _meta(bead, 'blocks');

  // --- parse the operator's --grade rulings (before ANY write) ---------------
  final rulings = <_Ruling>[];
  for (final raw in grades) {
    final eq = raw.indexOf('=');
    if (eq <= 0 || eq == raw.length - 1) {
      writeErr('grid gate resolve: --grade must be <lane>=<A-F> (got "$raw").');
      return 64;
    }
    final lane = raw.substring(0, eq).trim();
    final letter = raw.substring(eq + 1).trim().toUpperCase();
    if (!_isGrade(letter)) {
      writeErr(
        'grid gate resolve: --grade "$raw" — "$letter" is not a grade A–F.',
      );
      return 64;
    }
    final lanePath = _resolveLanePath(lane: lane, node: node);
    if (lanePath == null) {
      writeErr(
        'grid gate resolve: cannot resolve lane "$lane" — gate "$gateId" '
        'carries no node path; pass a full node path instead of a bare lane.',
      );
      return 64;
    }
    rulings.add(_Ruling(lane: lane, lanePath: lanePath, grade: letter));
  }
  if (rulings.isNotEmpty && (rationale == null || rationale.trim().isEmpty)) {
    writeErr(
      'grid gate resolve: --grade requires --rationale — a ruling must record '
      'WHY you are overriding the lane grade (it is the audit trail).',
    );
    return 64;
  }
  if (rulings.isNotEmpty && sessionId == null) {
    writeErr(
      'grid gate resolve: gate "$gateId" carries no session (blocks) — cannot '
      'record a ruling on a session bead.',
    );
    return 64;
  }

  // --- the re-gate-loop guard: which feeding lanes still grade F? ------------
  // The route re-reads the parked node's SIBLING result-nodes; any at `F`
  // re-gates the instant this gate closes. Detect them off the session bead,
  // subtracting the lanes this resolve rules away from F.
  Bead? sessionBead;
  if (sessionId != null) {
    for (final candidate in export.beads) {
      if (candidate.id == sessionId) {
        sessionBead = candidate;
        break;
      }
    }
  }
  final ruledAwayFromF = <String>{
    for (final r in rulings)
      if (r.grade != 'F') r.lanePath,
  };
  final unresolvedF = <_FeedingF>[];
  if (sessionBead != null && node != null) {
    final results = projectCircuitResults(sessionBead);
    final parent = node.contains('/')
        ? node.substring(0, node.lastIndexOf('/'))
        : '';
    results.forEach((path, fields) {
      if (path == node || !_isSiblingOf(path, parent)) return;
      if ((fields[ResultKeys.grade] ?? '').toUpperCase() != 'F') return;
      if (ruledAwayFromF.contains(path)) return; // ruled away this resolve
      unresolvedF.add(
        _FeedingF(path: path, transport: fields[ResultKeys.transport]),
      );
    });
    unresolvedF.sort((a, b) => a.path.compareTo(b.path));
  }

  if (unresolvedF.isNotEmpty) {
    // Closing now would re-gate — refuse LOUD, ZERO writes.
    final lines = unresolvedF
        .map(
          (f) =>
              '    - ${f.path}: grade F'
              '${(f.transport == null || f.transport!.isEmpty) ? '' : ' (transport: ${f.transport})'}',
        )
        .join('\n');
    if (rulings.isEmpty) {
      final workBead = _meta(sessionBead!, 'work_bead') ?? '<bead>';
      writeErr(
        'grid gate resolve: REFUSED — gate "$gateId" parks $node, and the route '
        'gates on these persisted lane grades on session $sessionId; closing '
        'the gate alone re-arms the node and it RE-GATES on the next snapshot '
        '(the I-14 no-op loop):\n$lines\n'
        'Rule a false/transport gate: `grid gate resolve $gateId '
        '--grade <lane>=<A-E> --rationale "<why>"`. For a TRUE code failure, fix '
        'it and `grid rework $workBead`. Nothing written.',
      );
    } else {
      writeErr(
        'grid gate resolve: REFUSED — these feeding lanes still grade F after '
        'your ruling, so closing would still re-gate:\n$lines\n'
        'Rule them too (--grade <lane>=<A-E>) or rework. Nothing written.',
      );
    }
    return 64;
  }

  // --- apply the rulings, THEN close (bd-only, --actor grid-controller) -------
  // The chokepoint re-asserts ownership before every write — a second line of
  // defense behind the guards above.
  final writer = StationBeadWriter(
    bd: bd,
    ownership: ownership,
    onRefusal: writeErr,
  );
  try {
    for (final r in rulings) {
      await writer.update(
        sessionId!,
        metadata: operatorRulingMetadata(
          r.lanePath,
          grade: r.grade,
          rationale: rationale!.trim(),
        ),
      );
      write(
        'grid gate resolve — ruled ${r.lanePath} → grade ${r.grade} '
        '(transport=$kOperatorRulingTransport).',
      );
    }
    await writer.close(
      gateId,
      reason: rulings.isEmpty
          ? 'resolved via grid gate resolve'
          : 'resolved via grid gate resolve (operator ruling)',
    );
  } on OwnershipRefused catch (e) {
    writeErr('grid gate resolve: $e');
    return 64;
  }

  final blocks = sessionId ?? '<no session>';
  final nodeLabel = node ?? '<no node>';
  write(
    'grid gate resolve — closed gate $gateId (blocks $blocks @ $nodeLabel).',
  );
  write(
    'The next/running station re-arms the parked node (gated → pending) on '
    'its next snapshot.',
  );
  return 0;
}

/// One parsed `--grade <lane>=<A-F>` ruling: the operator's lane token, its
/// resolved full node path (`grid.result.<lanePath>.grade`), and the corrected
/// letter grade (uppercased A–F).
class _Ruling {
  const _Ruling({
    required this.lane,
    required this.lanePath,
    required this.grade,
  });

  final String lane;
  final String lanePath;
  final String grade;
}

/// A feeding lane still grading `F` on the session bead — a re-gate cause. Its
/// [transport] provenance (when present) is surfaced in the refusal so the
/// operator sees WHY it is F (a fail-closed transport artifact vs a real F).
class _FeedingF {
  const _FeedingF({required this.path, this.transport});

  final String path;
  final String? transport;
}

/// Whether [s] is a single letter grade A–F.
bool _isGrade(String s) =>
    s.length == 1 && s.codeUnitAt(0) >= 0x41 && s.codeUnitAt(0) <= 0x46;

/// Resolves an operator lane token to a full node path. A token containing `/`
/// is a full node path (verbatim); a bare lane resolves to a SIBLING of the
/// parked [node] (the committee shape: `route` and its critics share a parent).
/// Null when a bare lane is given but the gate carries no [node] to anchor it.
String? _resolveLanePath({required String lane, required String? node}) {
  if (lane.contains('/')) return lane;
  if (node == null) return null;
  final slash = node.lastIndexOf('/');
  if (slash <= 0) return lane; // parked node is top-level; sibling == bare lane
  return '${node.substring(0, slash)}/$lane';
}

/// Whether [path] is a DIRECT child of [parent] (a sibling of the parked node).
/// An empty [parent] means top-level nodes (no `/`).
bool _isSiblingOf(String path, String parent) {
  if (parent.isEmpty) return !path.contains('/');
  if (!path.startsWith('$parent/')) return false;
  return !path.substring(parent.length + 1).contains('/');
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
