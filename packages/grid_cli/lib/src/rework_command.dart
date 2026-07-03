import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

/// `grid rework <bead>` — mint a fresh rework round for a bead whose prior
/// session has terminated (tg-x1j).
///
/// **The gap this closes.** Re-arming a POSITIVELY-CLOSED bead is a designed
/// NO-OP: `SessionScope` is keyed `'<bead.id>:session'`, so a closed session's
/// linkage must be moved OFF `bead.id` before a fresh mint can happen under the
/// same key. The operator mechanic (proven live, session `tgdog-7yw` →
/// `tgdog-4it`): re-key the session's `work_bead` → `'<bead>#r<N>'` through the
/// chokepoint — the live tree re-projects, finds no session at `bead.id`, and
/// mints round N+1 in the SAME worktree. This command makes that mechanic a
/// verb: it re-keys, appends the operator's finding to the WORK bead's notes,
/// reports the round number, and enforces the ~3-round cap (the factoryskills
/// precedent) — refusing LOUD beyond it (a human decides).
///
/// **The OPEN-session refusal.** A session that is still OPEN is a live round
/// — rekeying it out from under an ACTIVELY RUNNING step would silently
/// abandon a live process. This command refuses LOUD unless the open session's
/// per-node cursor shows it PARKED AT A GATE with nothing running — the one
/// case `SessionScope`'s v2 gate-resolve transition (grid_engine,
/// `SessionScopeState`) is built to observe and re-arm reactively, with no
/// runner restart (the round-1-GATED case tg-ucz found live).
///
/// **Coexistence safety.** Session writes flow through the [StationBeadWriter]
/// chokepoint into the_grid's OWN state store (`--state-workspace`); the note
/// append flows through a SEPARATE chokepoint instance scoped to the WORK
/// bead's own prefix, into the WORK workspace (`--workspace`) — never the
/// state store, and never raw SQL/`bd show` on a controller path.
class ReworkCommand extends Command<int> {
  ReworkCommand() {
    argParser
      ..addOption(
        'note',
        help:
            'The operator finding to append to the WORK bead\'s notes, under '
            'a ROUND N header. Requires the work bead be reachable via '
            '--workspace (or cwd discovery).',
      )
      ..addOption(
        'workspace',
        abbr: 'w',
        help:
            'The WORK bead\'s home (a dir at or above a `.beads/`). Defaults '
            'to discovery from the cwd. Only touched when --note is given.',
      )
      ..addOption(
        'state-workspace',
        help:
            'the_grid\'s OWN beads state store (the directory at or above the '
            '`.beads/` session beads live in). REQUIRED — rework is a write, '
            'never discovered implicitly.',
      )
      ..addOption(
        'state-substation',
        defaultsTo: 'tgdog',
        help:
            'the_grid\'s OWNED session/gate partition (the prefix of the '
            'state store, e.g. `tgdog`). Seeds the ownership allow-set the '
            'chokepoint re-checks fail-closed.',
      );
  }

  @override
  final String name = 'rework';

  @override
  final String description =
      'Mint a fresh rework round for <bead>: re-key its terminated (closed, '
      'or open-but-GATED) session through the StationBeadWriter chokepoint, '
      'optionally append an operator finding to the work bead\'s notes, and '
      'report the round number. Refuses LOUD (zero writes) on a live '
      '(open, non-gated) session or beyond the ~3-round cap.';

  @override
  String get invocation =>
      'grid rework <bead-id> [--note <finding>] --state-workspace <dir>';

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;
    if (rest.isEmpty) {
      stderr.writeln(
        'grid rework: a <bead-id> is required (the bead to rework).',
      );
      return 64;
    }
    if (rest.length > 1) {
      stderr.writeln(
        'grid rework: reworks ONE bead at a time — got ${rest.length} ids '
        '(${rest.join(', ')}).',
      );
      return 64;
    }
    return runRework(
      beadId: rest.single,
      note: args.option('note'),
      workspacePath: args.option('workspace'),
      stateWorkspacePath: args.option('state-workspace'),
      stateSubstation: args.option('state-substation') ?? 'tgdog',
    );
  }
}

/// The max rework rounds a bead may accumulate (~3, the factoryskills
/// precedent) before `grid rework` refuses LOUD — a human decides beyond it.
const int kMaxReworkRounds = 3;

/// Matches a RETIRED session's `work_bead` value for [beadId] exactly
/// (`'<beadId>#r<N>'`) — anchored full-string so a DIFFERENT bead id that
/// merely starts with [beadId] (e.g. `tg-x1j2`) is never mistaken for one of
/// its rounds.
RegExp _roundSuffixFor(String beadId) =>
    RegExp('^${RegExp.escape(beadId)}#r(\\d+)\$');

/// Runs `grid rework <beadId>`: re-keys [beadId]'s terminated session through
/// the [StationBeadWriter] chokepoint (state store), optionally appends
/// [note] to the WORK bead's notes (work workspace), and reports the round
/// number.
///
/// **Fail-closed (non-zero exit, ZERO writes)** unless exactly one session is
/// found for [beadId] and it is either CLOSED, or OPEN-and-parked-at-a-gate
/// with nothing running; the round cap is not yet reached; and (when [note] is
/// given) the work workspace is discoverable. Seams
/// ([workspaceOverride]/[stateWorkspaceOverride]/[bdOverride]/
/// [stateBdOverride]/[now]) are injectable so an offline test drives it with
/// fake stores.
Future<int> runRework({
  required String beadId,
  String? note,
  String? workspacePath,
  String? stateWorkspacePath,
  String stateSubstation = 'tgdog',
  void Function(String)? out,
  void Function(String)? err,
  BeadsWorkspace? workspaceOverride,
  BeadsWorkspace? stateWorkspaceOverride,
  BdCliService? bdOverride,
  BdCliService? stateBdOverride,
  DateTime Function()? now,
}) async {
  final void Function(String) write = out ?? (m) => stdout.writeln(m);
  final void Function(String) writeErr = err ?? (m) => stderr.writeln(m);
  final DateTime Function() clock = now ?? DateTime.now;

  // rework is a WRITE — the state store is never discovered implicitly (the
  // read work source stays untouched by accident).
  if (stateWorkspacePath == null && stateWorkspaceOverride == null) {
    writeErr(
      'grid rework: --state-workspace is required (the_grid\'s OWN state '
      'store where session beads live). rework is a write — it never '
      'defaults to the read --workspace.',
    );
    return 64;
  }
  final stateWorkspace =
      stateWorkspaceOverride ??
      BeadsWorkspace.discover(start: stateWorkspacePath);
  if (stateWorkspace == null) {
    writeErr(
      'grid rework: no .beads/ state store found from $stateWorkspacePath '
      '(--state-workspace)',
    );
    return 1;
  }
  final stateBd =
      stateBdOverride ??
      BdCliService(ProcessBdRunner(workspaceRoot: stateWorkspace.root));

  // --note needs the WORK workspace — resolved (and verified reachable) up
  // front, BEFORE any write, so a missing workspace never leaves the re-key
  // half done and the note half silently dropped.
  BeadsWorkspace? workWorkspace;
  BdCliService? workBd;
  if (note != null && note.isNotEmpty) {
    workWorkspace =
        workspaceOverride ?? BeadsWorkspace.discover(start: workspacePath);
    if (workWorkspace == null) {
      writeErr(
        'grid rework: --note given but no .beads/ work workspace found from '
        '${workspacePath ?? Directory.current.path} (--workspace) — refusing '
        '(the note would silently drop).',
      );
      return 1;
    }
    workBd =
        bdOverride ??
        BdCliService(ProcessBdRunner(workspaceRoot: workWorkspace.root));
  }

  // The complete-graph snapshot read (never `bd show` on this controller
  // path — it self-triggers the watcher).
  final export = await stateBd.exportAll();
  final sessions = export.beads
      .where((b) => b.issueType == IssueType.session)
      .toList();

  // The CURRENT (un-retired) session — `work_bead` matches EXACTLY.
  final current = sessions
      .where((b) => _stringMeta(b, 'work_bead') == beadId)
      .toList();
  if (current.isEmpty) {
    writeErr(
      'grid rework: no session found for "$beadId" — nothing to rework (run '
      'the bead through the_grid first).',
    );
    return 1;
  }
  if (current.length > 1) {
    writeErr(
      'grid rework: ${current.length} sessions carry work_bead == "$beadId" '
      '(${current.map((b) => b.id).join(', ')}) — refused (an ambiguous '
      'store; this should never happen under D-2\'s one-mint invariant).',
    );
    return 64;
  }
  final session = current.single;

  // Every RETIRED round already on record for this bead (`work_bead ==
  // '<beadId>#r<N>'`) — the round-cap + next-round-number source.
  final roundSuffix = _roundSuffixFor(beadId);
  var maxRound = 0;
  for (final s in sessions) {
    final workBead = _stringMeta(s, 'work_bead');
    if (workBead == null) continue;
    final match = roundSuffix.firstMatch(workBead);
    if (match == null) continue;
    final n = int.parse(match.group(1)!);
    if (n > maxRound) maxRound = n;
  }
  if (maxRound >= kMaxReworkRounds) {
    writeErr(
      'grid rework: "$beadId" already has $maxRound rework rounds (cap '
      '$kMaxReworkRounds) — refused (fail-closed; a human decides beyond the '
      'cap).',
    );
    return 64;
  }
  final round = maxRound + 1;

  if (!session.isClosed) {
    final cursor = projectCircuitCursor(session);
    final states = cursor.values.map((n) => n.state);
    final hasRunning = states.contains(StepState.running);
    final hasGated = states.contains(StepState.gated);
    if (hasRunning || !hasGated) {
      writeErr(
        'grid rework: session "${session.id}" for "$beadId" is OPEN and not '
        'parked at a gate — a live round may be running; refused (fail-closed '
        '— wait for it to gate or terminate, or restart the runner).',
      );
      return 64;
    }
    // OPEN and gated, nothing running: safe to retire — SessionScope's v2
    // gate-resolve transition observes this re-key and re-arms in place (no
    // runner restart needed).
  }

  final ownership = BeadOwnershipPredicate({stateSubstation});
  final stateWriter = StationBeadWriter(
    bd: stateBd,
    ownership: ownership,
    onRefusal: writeErr,
    clock: clock,
  );
  try {
    await stateWriter.update(
      session.id,
      metadata: {'work_bead': '$beadId#r$round'},
    );
  } on OwnershipRefused catch (e) {
    writeErr('grid rework: $e');
    return 64;
  }

  if (note != null && note.isNotEmpty && workBd != null) {
    final workOwnership = BeadOwnershipPredicate({
      BeadOwnershipPredicate.prefixOf(beadId) ?? beadId,
    });
    final workWriter = StationBeadWriter(
      bd: workBd,
      ownership: workOwnership,
      onRefusal: writeErr,
      clock: clock,
    );
    final header =
        '--- grid rework ROUND $round '
        '(${clock().toUtc().toIso8601String()}) ---';
    try {
      await workWriter.update(
        beadId,
        metadata: const {},
        appendNotes: '$header\n$note',
      );
    } on OwnershipRefused catch (e) {
      writeErr('grid rework: note append refused: $e');
      return 64;
    }
  }

  write(
    'grid rework — round $round: retired session "${session.id}" '
    '(work_bead -> "$beadId#r$round"); a fresh session mints on the next '
    'projection.',
  );
  return 0;
}

/// Reads a string metadata value off a bead, or null when absent/empty.
String? _stringMeta(Bead bead, String key) {
  final value = bead.metadata[key];
  if (value is String && value.isNotEmpty) return value;
  return null;
}
