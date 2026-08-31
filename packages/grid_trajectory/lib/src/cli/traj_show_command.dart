/// `traj show <id>` — one subject's trajectory, in `seq` order.
///
/// The subject is whatever the operator has in hand: a work bead id, a session
/// id, or an attempt id. One query covers all three (§9's forensics shape),
/// because the operator does not always know which kind of id they pasted.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import 'traj_flags.dart';
import 'traj_render.dart';
import 'trajectory_reader.dart';

/// The verb: parse argv, render; every read lives in [TrajectoryLogReader].
///
/// Staleness (§5): when `proj_meta.applied_seq` lags `MAX(seq)` by more than
/// [staleLagLimit] records the verb WARNS rather than refusing — Stage 0 has
/// no real projection readers yet; the strict refusal bound arms with them
/// at Stage 1.
class TrajShowCommand extends Command<int> {
  /// Creates the show verb with an optional injected opener (tests script the
  /// log without a socket).
  TrajShowCommand({TrajectoryOpener? open})
    : _open = open ?? openTrajectoryReader {
    addGridHomeOption(argParser);
    argParser.addOption(
      'limit',
      help: 'Maximum rows to read (default $defaultReadLimit).',
    );
  }

  final TrajectoryOpener _open;

  @override
  final String name = 'show';

  @override
  final String description =
      'Show the trajectory log for one work bead, session, or attempt id.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      stderr.writeln(
        rest.isEmpty
            ? 'traj show: a <bead|session|attempt id> is required.'
            : 'traj show: show accepts exactly one id.',
      );
      return 64;
    }
    final gridHome = gridHomeFrom(argResults!, stderr.writeln, 'show');
    if (gridHome == null) return 64;
    final limit = positiveIntFrom(
      argResults!,
      'limit',
      stderr.writeln,
      'show',
      fallback: defaultReadLimit,
    );
    if (limit == null) return 64;
    return runTrajShow(
      gridHome: gridHome,
      subject: rest.single,
      open: _open,
      limit: limit,
    );
  }
}

/// Renders [subject]'s rows from the log opened by [open].
///
/// An unbootstrapped grid home is reported and exits 0 — the trajectory
/// database is additive, so its absence is a state, not a failure. A server
/// that should answer and does not exits 1.
Future<int> runTrajShow({
  required String gridHome,
  required String subject,
  required TrajectoryOpener open,
  int limit = defaultReadLimit,
  void Function(String)? out,
  void Function(String)? err,
}) async {
  final write = out ?? stdout.writeln;
  final writeErr = err ?? stderr.writeln;
  final opened = await open(gridHome);
  switch (opened) {
    case TrajectoryNotBootstrapped(:final message):
      write('traj show: $message');
      return 0;
    case TrajectoryUnavailable(:final message):
      writeErr('traj show: $message');
      return 1;
    case TrajectoryOpened(:final reader):
      try {
        final staleness = await reader.foldStaleness();
        if (staleness != null && staleness.lag > staleLagLimit) {
          write(
            'traj show: warning — the fold lags the log by ${staleness.lag} '
            'records (applied_seq ${staleness.appliedSeq}, head '
            '${staleness.maxSeq}); §5 bounds staleness at $staleLagLimit. '
            'Stage-1 projection readers refuse here.',
          );
        }
        final rows = await reader.rowsForSubject(subject, limit: limit);
        if (rows.isEmpty) {
          write('traj show $subject — no trajectory records.');
          return 0;
        }
        write(
          'traj show $subject — ${rows.length} record'
          '${rows.length == 1 ? '' : 's'}:',
        );
        for (final row in rows) {
          for (final line in renderTrajectoryRow(row)) {
            write(line);
          }
        }
        if (rows.length >= limit) {
          write('  … stopped at --limit $limit; raise it for the whole log.');
        }
        return 0;
      } finally {
        await reader.close();
      }
  }
}
