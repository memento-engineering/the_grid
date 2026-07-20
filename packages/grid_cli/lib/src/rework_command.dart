import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart'
    show DirectoryProbe, GridStateStore, StoreRefusal, SubstationWorkStore;

import 'station_stores.dart';

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
/// verb: it clears stale specify-authored fields on the WORK bead, re-keys the
/// session, optionally appends the operator's finding to the WORK bead's notes,
/// reports the round number, and enforces the ~3-round cap (the factoryskills
/// precedent) — refusing LOUD beyond it (a human decides).
///
/// **The OPEN-session refusal.** A session that is still OPEN is a live round
/// — rekeying it out from under an ACTIVELY RUNNING step would silently
/// abandon a live process. This command refuses LOUD unless the open session's
/// per-node cursor shows it PARKED AT A GATE with nothing running — the one
/// case `SessionScope`'s v2 gate-resolve transition (grid_engine,
/// `SessionScopeState`) is built to observe and re-arm reactively, with no
/// runner restart (the round-1-GATED case tg-ucz found live). The cursor is
/// a MOLECULE session's (`grid.session.model=molecule`) `type=step` beads in
/// the same store snapshot (`projectMoleculeCursor`). A HISTORICAL FLAT
/// session's `grid.cursor.*` keys no longer project (tg-eli phase 2 retired
/// the flat model): an OPEN flat session reads an EMPTY cursor and takes the
/// refusal path — moot by construction, since the engine can no longer drive
/// it anyway (a CLOSED flat session still reworks fine; round N+1 mints
/// molecule).
///
/// **Re-seated on the store-at-roots model (v3).** The session lives in the_grid's
/// OWN **state store** at `<grid.root>/.grid/.beads/` (`--grid-root`; Q5a) — never
/// `--state-workspace` / cwd discovery. The state-store ownership prefix is a
/// supplied value (`--prefix`), not the retired `--state-substation`.
/// `--note-root` points at the WORK bead's substation work store at
/// `<note-root>/.beads/` — a SEPARATE store, scoped to the WORK bead's own
/// prefix, never the state store, and never raw SQL/`bd show` on a controller
/// path.
class ReworkCommand extends Command<int> {
  ReworkCommand() {
    argParser
      ..addOption(
        'note',
        help:
            'The operator finding to append to the WORK bead\'s notes, under '
            'a ROUND N header. Requires --note-root (the WORK bead\'s '
            'substation root).',
      )
      ..addOption(
        'note-root',
        help:
            'The substation ROOT whose `.beads/` work store holds the WORK '
            'bead (an absolute path; the store is at `<note-root>/.beads/`). '
            'REQUIRED - rework clears stale specify-authored design and '
            'acceptance before retiring the current round.',
      )
      ..addOption(
        'grid-root',
        help:
            'The grid HOME (an absolute path). The state store the session bead '
            'lives in is derived at `<grid.root>/.grid/.beads/` (Q5a). '
            'REQUIRED — rework is a write, never discovered implicitly.',
      )
      ..addOption(
        'prefix',
        help:
            'the_grid\'s OWNED session/gate id-prefix (the state store\'s '
            'adopted prefix, e.g. the grid\'s own name). Seeds the ownership '
            'allow-set the chokepoint re-checks fail-closed. REQUIRED.',
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
      'grid rework <bead-id> --grid-root <dir> --prefix <name> '
      '--note-root <dir> [--note <finding>]';

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

    final gridRoot = args.option('grid-root');
    if (gridRoot == null || gridRoot.trim().isEmpty) {
      stderr.writeln(
        'grid rework: --grid-root is required (the grid HOME; the session bead '
        'lives in the state store at <grid.root>/.grid/.beads/). rework is a '
        'write — it never discovers a store implicitly.',
      );
      return 64;
    }
    final GridStateStore stateStore;
    try {
      stateStore = GridStateStore.forGridRoot(gridRoot);
    } on ArgumentError catch (e) {
      stderr.writeln('grid rework: --grid-root ${e.message}');
      return 64;
    }

    final prefix = args.option('prefix');
    if (prefix == null || prefix.trim().isEmpty) {
      stderr.writeln(
        'grid rework: --prefix is required (the state store\'s owned id-prefix '
        '— the ownership allow-set the chokepoint re-checks).',
      );
      return 64;
    }

    final noteRoot = args.option('note-root');
    if (noteRoot == null || noteRoot.trim().isEmpty) {
      stderr.writeln(
        'grid rework: --note-root is required (the WORK bead\'s substation '
        'root, whose `.beads/` work store holds the bead). rework clears '
        'stale specify-authored design and acceptance before retiring a round.',
      );
      return 64;
    }
    final SubstationWorkStore noteStore;
    try {
      noteStore = SubstationWorkStore.forRoot(noteRoot);
    } on ArgumentError catch (e) {
      stderr.writeln('grid rework: --note-root ${e.message}');
      return 64;
    }

    return runRework(
      beadId: rest.single,
      note: args.option('note'),
      stateStore: stateStore,
      stateStorePrefix: prefix,
      noteStore: noteStore,
    );
  }
}

// The round cap (`kMaxReworkRounds`) and the retired-round key shape
// (`reworkKeyFor`/`reworkKeyPattern`) live in the engine's rework contract
// (`grid_engine`, `src/domain/rework.dart`, tg-o90) — this verb and the engine's
// `Rewind` arm share ONE definition, so they admit exactly the same number of
// rounds and cannot drift on the key.

/// Runs `grid rework <beadId>`: clears stale specify-authored `design` and
/// `acceptance_criteria` on the WORK bead through the [StationBeadWriter]
/// chokepoint, then re-keys [beadId]'s terminated session through the state
/// store [StationBeadWriter], optionally appends [note] to the WORK bead's
/// notes after the re-key succeeds, and reports the round number.
///
/// **Fail-closed (non-zero exit, ZERO writes)** unless exactly one session is
/// found for [beadId] and it is either CLOSED, or OPEN-and-parked-at-a-gate
/// with nothing running; the round cap is not yet reached; and [noteStore] is
/// provided and openable. The WORK store is required even when [note] is absent
/// because every rework clears stale spec fields before session retirement.
/// `--note` only adds a second work-bead write after the state re-key succeeds.
/// Seams ([stateWorkspaceOverride]/[workspaceOverride]/[bdOverride]/
/// [stateBdOverride]/[dirExists]/[now]) are injectable so an offline test drives
/// it with fake stores.
Future<int> runRework({
  required String beadId,
  required GridStateStore stateStore,
  required String stateStorePrefix,
  String? note,
  SubstationWorkStore? noteStore,
  void Function(String)? out,
  void Function(String)? err,
  BeadsWorkspace? stateWorkspaceOverride,
  BeadsWorkspace? workspaceOverride,
  BdCliService? bdOverride,
  BdCliService? stateBdOverride,
  DirectoryProbe? dirExists,
  DateTime Function()? now,
}) async {
  final void Function(String) write = out ?? (m) => stdout.writeln(m);
  final void Function(String) writeErr = err ?? (m) => stderr.writeln(m);
  final DateTime Function() clock = now ?? DateTime.now;

  final BeadsWorkspace stateWorkspace;
  if (stateWorkspaceOverride != null) {
    stateWorkspace = stateWorkspaceOverride;
  } else {
    try {
      stateWorkspace = openStateStore(stateStore, dirExists: dirExists);
    } on StoreRefusal catch (e) {
      writeErr('grid rework: ${e.message}');
      return 1;
    }
  }
  final stateBd =
      stateBdOverride ??
      BdCliService(ProcessBdRunner(workspaceRoot: stateWorkspace.root));

  final wantsNote = note != null && note.isNotEmpty;
  final BeadsWorkspace workWorkspace;
  if (workspaceOverride != null) {
    workWorkspace = workspaceOverride;
  } else if (noteStore != null) {
    try {
      workWorkspace = openWorkStore(noteStore, dirExists: dirExists);
    } on StoreRefusal catch (e) {
      writeErr(
        'grid rework: the WORK store is unreachable - ${e.message} - '
        'refusing before the session is retired.',
      );
      return 1;
    }
  } else {
    writeErr(
      'grid rework: --note-root is required (the WORK bead\'s substation root, '
      'whose `.beads/` work store holds the bead) - refusing before the '
      'session is retired.',
    );
    return 64;
  }
  final workBd =
      bdOverride ??
      BdCliService(ProcessBdRunner(workspaceRoot: workWorkspace.root));

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
  final roundSuffix = reworkKeyPattern(beadId);
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
    // The per-node cursor: a MOLECULE session's state lives on its own
    // `type=step` beads — already in the complete-graph snapshot read above,
    // no second query. A HISTORICAL FLAT session (`SessionBeadKeys.model`
    // absent — the flat model retired, tg-eli phase 2) has NO projectable
    // cursor: it reads EMPTY below, so an OPEN flat session always takes the
    // not-parked-at-a-gate refusal — moot by construction (the engine can no
    // longer drive it; a CLOSED flat session still reworks, and round N+1
    // mints molecule).
    final CircuitCursor cursor;
    if (_stringMeta(session, SessionBeadKeys.model) == kSessionModelMolecule) {
      // The supersedes edges (A52 rework rounds) resolve the ACTIVE
      // incarnation per path; projectMoleculeCursor drops any edge whose
      // endpoints are not both in the passed step set, so the full export
      // edge list is safe to hand over unfiltered.
      final steps = export.beads.where(
        (b) =>
            b.issueType == IssueType.step &&
            _stringMeta(b, MoleculeStepKeys.session) == session.id,
      );
      cursor = projectMoleculeCursor(
        steps,
        dependencies: export.dependencies,
      ).cursor;
    } else {
      cursor = const {};
    }
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

  final workOwnership = BeadOwnershipPredicate({
    BeadOwnershipPredicate.prefixOf(beadId) ?? beadId,
  });
  final workWriter = StationBeadWriter(
    bd: workBd,
    ownership: workOwnership,
    onRefusal: writeErr,
    clock: clock,
  );
  try {
    await workWriter.clearSpecifyAuthoredSpec(beadId);
  } on OwnershipRefused catch (e) {
    writeErr('grid rework: work bead spec clear refused: $e');
    return 64;
  } on Object catch (e) {
    writeErr('grid rework: work bead spec clear failed: $e');
    return 1;
  }

  final ownership = BeadOwnershipPredicate({stateStorePrefix});
  final stateWriter = StationBeadWriter(
    bd: stateBd,
    ownership: ownership,
    onRefusal: writeErr,
    clock: clock,
  );
  try {
    await stateWriter.update(
      session.id,
      metadata: {'work_bead': reworkKeyFor(beadId, round)},
    );
  } on OwnershipRefused catch (e) {
    writeErr('grid rework: $e');
    return 64;
  }

  if (wantsNote) {
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
