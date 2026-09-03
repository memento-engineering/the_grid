/// `traj replay` — the operator's rebuild of the fold, and the P1 reshape
/// (cut-wiring C0).
///
/// The verb is a WRAPPER: the three replay functions already ship in-tree
/// (`replaySessionHeads`, `replayStepCursors`, `replayProcessIdentities`), and
/// each one is a `DELETE FROM proj_*` + re-insert + `proj_meta` upsert inside
/// ONE `START TRANSACTION`. Replay is per-PROJECTION: `'step_cursor'` and
/// `'process_identity'` keep their own `proj_meta` rows while P1's replay
/// upserts the shared `'fold'` row, so `--projection` is a real partial
/// rebuild and the default runs all three.
///
/// **QUIESCE-ONLY.** The rebuild refuses while a station holds this grid home
/// — see `traj_quiesce.dart` for the fence and why there is no override. The
/// check runs BEFORE any projection table is touched. `--check` is the
/// read-only half: it reports the fold's lag and the full per-projection
/// generation set (and whether the home is quiesced at all) without rebuilding
/// anything, so it is useful against a LIVE station in a way the rebuild can
/// never be.
///
/// **The P1 reshape** rides here as a named step (r7 — V1-B1). Nothing in the
/// tree reshapes an existing table — `applyTrajectorySchema` is
/// CREATE-IF-NOT-EXISTS only and the replays re-INSERT at a fixed shape — so a
/// home provisioned before the cut carries a `proj_session_head` without
/// `terminal_provenance`/`unknown_reason`. When the session-head replay runs
/// on such a home the verb drops and re-creates the table at the new shape
/// first; the replay that follows is what stamps the bumped `fold_version`. An
/// ALTER path is deliberately not built.
///
/// **The journal rename** (tg-j1zn) rides here too, ahead of every projection:
/// `trajectory.seat` became `trajectory.substation`, and a home provisioned
/// before that carries the old column. Unlike the P1 reshape this one IS an
/// ALTER — the journal is the versioned log, not rebuildable projection state.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import '../connect/server_config.dart';
import '../connect/trajectory_connection.dart';
import '../connect/trajectory_db.dart';
import '../ddl/trajectory_provisioning.dart';
import '../ddl/trajectory_schema.dart';
import '../fold/fold_lag.dart';
import '../fold/process_identity_fold.dart';
import '../fold/session_head_fold.dart';
import '../fold/step_cursor_fold.dart';
import 'traj_flags.dart';
import 'traj_provision_command.dart' show ListenerResolver;
import 'traj_quiesce.dart';
import 'trajectory_reader.dart' show trajectoryDatabaseName;

/// The projection names `--projection` accepts, in replay order. The values
/// are the `proj_meta.projection` keys the folds themselves write, except
/// `session_head`, whose replay drives the shared cursor row (`'fold'`).
const String sessionHeadProjection = 'session_head';

/// Every projection the verb can rebuild — the default set.
const List<String> replayProjections = [
  sessionHeadProjection,
  stepCursorProjection,
  processIdentityProjection,
];

Future<TrajectoryDb> _defaultConnect(TrajectoryEndpoint endpoint) =>
    TrajectoryConnection.connect(endpoint);

/// The verb.
class TrajReplayCommand extends Command<int> {
  TrajReplayCommand({
    TrajSqlConnect? connect,
    ListenerResolver? resolve,
    PidLiveness? isPidAlive,
  }) : _connect = connect ?? _defaultConnect,
       _resolve = resolve ?? resolveDoltServerListener,
       _isPidAlive = isPidAlive ?? defaultPidLiveness {
    addGridHomeOption(argParser);
    argParser
      ..addMultiOption(
        'projection',
        allowed: replayProjections,
        help:
            'Which projection(s) to rebuild. Repeatable; the default is all '
            'three. Each keeps its own proj_meta bookkeeping, so a partial '
            'rebuild is a real, supported operation.',
      )
      ..addFlag(
        'check',
        negatable: false,
        help:
            'Report the fold cursor lag and the per-projection generation set '
            '(and whether the home is quiesced) WITHOUT rebuilding anything. '
            'Safe against a live station.',
      );
  }

  final TrajSqlConnect _connect;
  final ListenerResolver _resolve;
  final PidLiveness _isPidAlive;

  @override
  final String name = 'replay';

  @override
  final String description =
      'Rebuild the fold from the log — quiesce-only (station DOWN); '
      '--check reports lag and fold generations without rebuilding.';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      stderr.writeln(
        'traj replay: unexpected argument "${argResults!.rest.first}".',
      );
      return 64;
    }
    final gridHome = gridHomeFrom(argResults!, stderr.writeln, 'replay');
    if (gridHome == null) return 64;
    final selected = argResults!.multiOption('projection');
    return runTrajReplay(
      gridHome: gridHome,
      projections: selected.isEmpty ? replayProjections : selected,
      check: argResults!.flag('check'),
      connect: _connect,
      resolve: _resolve,
      isPidAlive: _isPidAlive,
    );
  }
}

/// Runs the verb and prints what it did.
///
/// 0 on a clean rebuild (or a clean `--check`); 1 on any refusal — a home the
/// service credential cannot open, an ARMED station, or a replay that threw.
Future<int> runTrajReplay({
  required String gridHome,
  List<String> projections = replayProjections,
  bool check = false,
  TrajSqlConnect connect = _defaultConnect,
  ListenerResolver resolve = resolveDoltServerListener,
  PidLiveness isPidAlive = defaultPidLiveness,
  DateTime Function() clock = DateTime.now,
  void Function(String)? out,
  void Function(String)? err,
}) async {
  final void Function(String) write = out ?? stdout.writeln;
  final void Function(String) writeErr = err ?? stderr.writeln;
  write(
    check
        ? 'traj replay --check — fold lag + generations (read-only)'
        : 'traj replay — quiesced rebuild of ${projections.join(', ')}',
  );

  final TrajectoryDb db;
  try {
    final listener = resolve(gridHome);
    final secret = File(trajectorySecretPath(gridHome));
    if (!secret.existsSync()) {
      writeErr(
        'traj replay: no trajectory credential at ${secret.path} — this grid '
        'home was never provisioned (`traj provision`).',
      );
      return 1;
    }
    final password = secret.readAsStringSync().trim();
    if (password.isEmpty) {
      writeErr('traj replay: empty trajectory secret: ${secret.path}');
      return 1;
    }
    db = await connect(
      TrajectoryEndpoint(
        host: listener.host,
        port: listener.port,
        user: trajectoryUser,
        password: password,
        database: trajectoryDatabaseName,
      ),
    );
  } on Object catch (error) {
    writeErr('traj replay: $error');
    return 1;
  }

  try {
    // THE FENCE, first — before any proj_* statement, read or write.
    final quiescence = await probeStationQuiescence(
      gridHome: gridHome,
      db: db,
      isPidAlive: isPidAlive,
    );
    write(
      '  quiesced: ${quiescence is StationQuiesced ? 'yes' : 'NO'} — '
      '${quiescence.detail}',
    );
    if (check) {
      await _writeCheck(db, write, clock);
      return 0;
    }
    if (quiescence is StationArmed) {
      writeErr(
        'traj replay: REFUSED — ${quiescence.detail}. Take the station down '
        '(or disable the trajectory) and re-run; there is no override, and a '
        'live replay would erase fold effects nothing can detect afterwards.',
      );
      return 1;
    }
    return await _rebuild(
      db,
      projections: projections,
      clock: clock,
      write: write,
      writeErr: writeErr,
    );
  } on Object catch (error) {
    writeErr('traj replay: $error');
    return 1;
  } finally {
    await db.close();
  }
}

Future<void> _writeCheck(
  TrajectoryDb db,
  void Function(String) write,
  DateTime Function() clock,
) async {
  final lag = await readFoldLag(db, clock: clock);
  write(
    '  lag: ${lag.records} record(s) behind head ${lag.maxSeq} '
    '(applied ${lag.appliedSeq}), oldest unapplied ${lag.age.inSeconds}s — '
    '${lag.isStale ? 'STALE (a reader refuses this fold)' : 'within bounds'}',
  );
  if (await journalNeedsSubstationRename(db)) {
    write(
      '  migrate: PENDING — the journal still spells the substation identity '
      '`seat`; a quiesced `traj replay` renames it',
    );
  }
  final generations = await readProjectionGenerations(db);
  if (generations.isEmpty) {
    write('  generations: none — no projection has ever been folded');
    return;
  }
  // The FULL row set, not just the cursor row: a mirror's reseed guard
  // watches every (projection, fold_version, rebuilt_at) triple, and P1's own
  // generation rides the shared "$foldCursorProjection" row.
  for (final generation in generations) {
    write(
      '  generation: ${generation.projection} fold_version='
      '${generation.foldVersion} applied_seq=${generation.appliedSeq} '
      'rebuilt_at=${generation.rebuiltAt?.toIso8601String() ?? 'never'}'
      '${generation.skipped == null ? '' : ' skipped=${generation.skipped}'}',
    );
  }
  if (await sessionHeadProjectionNeedsReshape(db)) {
    write(
      '  reshape: PENDING — proj_session_head predates the wave-1 shape '
      '(missing ${projSessionHeadCutColumns.join(', ')}); a quiesced '
      '`traj replay` performs it',
    );
  }
}

Future<int> _rebuild(
  TrajectoryDb db, {
  required List<String> projections,
  required DateTime Function() clock,
  required void Function(String) write,
  required void Function(String) writeErr,
}) async {
  final unknown = projections
      .where((p) => !replayProjections.contains(p))
      .toList(growable: false);
  if (unknown.isNotEmpty) {
    writeErr(
      'traj replay: unknown projection(s) ${unknown.join(', ')} — expected '
      'one of ${replayProjections.join(', ')}.',
    );
    return 1;
  }

  // THE JOURNAL RENAME (tg-j1zn), a named step that runs before any replay:
  // the folds decode the journal through the envelope codec, which reads
  // `substation`. Quiesced by the fence in `runTrajReplay`.
  if (await journalNeedsSubstationRename(db)) {
    await renameJournalSubstationColumn(db);
    write(
      '  migrate: trajectory.seat RENAMEd to trajectory.substation, '
      'ck_seat re-added as ck_substation',
    );
  }

  // Replay order is the declared order, not the caller's, so a partial set
  // and the full set rebuild identically.
  for (final projection in replayProjections) {
    if (!projections.contains(projection)) continue;
    switch (projection) {
      case sessionHeadProjection:
        // THE RESHAPE (r7 — V1-B1), a named step that runs only on a home
        // whose P1 predates the cut. Quiesced by the fence above.
        if (await sessionHeadProjectionNeedsReshape(db)) {
          await reshapeSessionHeadProjection(db);
          write(
            '  reshape: proj_session_head DROPped and re-CREATEd at the '
            'wave-1 shape (+${projSessionHeadCutColumns.join(', +')}) — the '
            'replay below stamps fold_version $sessionHeadFoldVersion',
          );
        }
        final result = await replaySessionHeads(db, clock: clock);
        _writeResult(
          write,
          projection: projection,
          rows: result.rows.length,
          appliedSeq: result.appliedSeq,
          skipped: result.skipped,
          foldVersion: sessionHeadFoldVersion,
        );
      case stepCursorProjection:
        final result = await replayStepCursors(db, clock: clock);
        _writeResult(
          write,
          projection: projection,
          rows: result.rows.length,
          appliedSeq: result.appliedSeq,
          skipped: result.skipped,
          foldVersion: stepCursorFoldVersion,
        );
      case processIdentityProjection:
        final result = await replayProcessIdentities(db, clock: clock);
        _writeResult(
          write,
          projection: projection,
          rows: result.rows.length,
          appliedSeq: result.appliedSeq,
          skipped: result.skipped,
          foldVersion: processIdentityFoldVersion,
        );
    }
  }
  return 0;
}

void _writeResult(
  void Function(String) write, {
  required String projection,
  required int rows,
  required int appliedSeq,
  required Map<String, int> skipped,
  required int foldVersion,
}) => write(
  '  $projection: $rows row(s), applied_seq $appliedSeq, fold_version '
  '$foldVersion'
  '${skipped.isEmpty ? '' : ', skipped $skipped'}',
);
