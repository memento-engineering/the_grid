/// `traj certify` — the §W2.5 soak certificate plus report-only diagnostics.
///
/// Read-only and cross-session, like `traj committee-report`: it reads the
/// `traj_epoch` ledger, takes the last `--boots N` claims, reads each one's
/// window off the trajectory database, and prints one row per certificate item
/// that is machine-checkable. Nothing here decides anything — the fold in
/// `soak_certificate.dart` does — and nothing here writes.
///
/// Exit codes are the point of the verb: `0` certified, `2` a row failed, `3`
/// fewer than N boots exist. An unbootstrapped grid home is `3` rather than
/// `traj show`'s `0`: the trajectory database's absence is still an ordinary
/// state of the world, but a station with no boots has not failed the
/// certificate, it simply has nothing to certify yet. Every disposition prints
/// the UNKNOWN checklist, including the two that measure nothing — the reader
/// who gets no rows is the one most likely to assume the verb covered the
/// whole table.
///
/// TWO reads per boot, not one. The window read is the evidence; a SECOND,
/// bounded per-session read attributes the round summaries the window cannot,
/// because a note carries no substation of its own and its session may have
/// been mounted in an earlier epoch (a bounce mid-round is routine). Without
/// it the shape-coverage row scores a real soak off a join artifact.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import 'soak_certificate.dart';
import 'soak_certificate_render.dart';
import 'traj_flags.dart';
import 'trajectory_reader.dart';

/// The soak's own count (`wave-2-flip-scope-soak-and-kill-date`, Q1): three
/// consecutive clean boots.
const int kDefaultCertifyBoots = 3;

/// How far into a session's own history the substation lookup reads.
///
/// A bounded WINDOW on purpose ([TrajectoryLogReader.rowsForSubject], `seq`
/// ascending): the attribution rides the session's earliest records — the ones
/// carrying a `work_bead_id`, which is the only column `ck_substation` makes
/// the substation mandatory beside — so the answer is at the head of the
/// stream or it is not in the log at all. A session whose first
/// [kSubstationLookupRows] rows name no substation stays UNJOINED and is
/// counted as such rather than guessed at.
const int kSubstationLookupRows = defaultReadLimit;

/// The verb.
class TrajCertifyCommand extends Command<int> {
  /// Creates the certify verb with an optional injected opener (tests script
  /// the log without a socket).
  TrajCertifyCommand({TrajectoryOpener? open})
    : _open = open ?? openTrajectoryReader {
    addGridHomeOption(argParser);
    argParser
      ..addOption(
        'boots',
        help:
            'How many of the most recent boot epochs to certify (default '
            '$kDefaultCertifyBoots).',
      )
      ..addMultiOption(
        'seat',
        help:
            'A seat the shape-coverage row requires a round on; repeatable. '
            'Defaults to the ruling\'s scope (${kSoakTargetSeats.join(', ')}). '
            'A seat matches a substation exactly or as its leading segment.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit one JSON object instead of the operator table.',
      )
      ..addOption(
        'limit',
        help:
            'Ceiling on each boot\'s window read (default '
            '$completeReadCeiling). Not a window: a boot that reaches it is '
            'reported TRUNCATED and certifies nothing.',
      );
  }

  final TrajectoryOpener _open;

  @override
  final String name = 'certify';

  @override
  final String description =
      'Certify the last N boot epochs against the §W2.5 soak table — posture, '
      'clean counters, shape coverage, would-refuse, consecutive — and report '
      'G2 round diagnostics without gating the verdict.';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      stderr.writeln(
        'traj certify: unexpected argument "${argResults!.rest.first}"; the '
        'window rides --boots.',
      );
      return 64;
    }
    final gridHome = gridHomeFrom(argResults!, stderr.writeln, 'certify');
    if (gridHome == null) return 64;
    final boots = positiveIntFrom(
      argResults!,
      'boots',
      stderr.writeln,
      'certify',
      fallback: kDefaultCertifyBoots,
    );
    if (boots == null) return 64;
    final limit = positiveIntFrom(
      argResults!,
      'limit',
      stderr.writeln,
      'certify',
      fallback: completeReadCeiling,
    );
    if (limit == null) return 64;
    final seats = argResults!.multiOption('seat');
    return runTrajCertify(
      gridHome: gridHome,
      open: _open,
      boots: boots,
      seats: seats.isEmpty ? kSoakTargetSeats : seats.toSet(),
      asJson: argResults!.flag('json'),
      limit: limit,
    );
  }
}

/// Reads the ledger and the counted windows, folds the certificate, prints it.
Future<int> runTrajCertify({
  required String gridHome,
  required TrajectoryOpener open,
  int boots = kDefaultCertifyBoots,
  Set<String> seats = kSoakTargetSeats,
  bool asJson = false,
  int limit = completeReadCeiling,
  void Function(String)? out,
  void Function(String)? err,
}) async {
  final write = out ?? stdout.writeln;
  final writeErr = err ?? stderr.writeln;
  final opened = await open(gridHome);
  switch (opened) {
    case TrajectoryNotBootstrapped(:final message):
      write('traj certify: $message — no boot has been counted.');
      // Nothing was measured, so the checklist matters MORE, not less: an
      // exit-3 line on its own reads as "the verb found nothing wrong".
      for (final line in renderCertificateChecklist()) {
        write(line);
      }
      return 3;
    case TrajectoryUnavailable(:final message):
      writeErr('traj certify: $message');
      return 1;
    case TrajectoryOpened(:final reader):
      try {
        final claims = await reader.epochClaims();
        final stationOf = <int, String>{};
        for (final claim in claims) {
          stationOf.update(
            claim.epoch,
            (station) => station == claim.station
                ? station
                : '$station+${claim.station}',
            ifAbsent: () => claim.station,
          );
        }
        final ledger = stationOf.keys.toList()..sort();
        final counted = countedEpochs(ledger, boots);
        final windows = <BootWindow>[];
        if (ledger.length >= boots) {
          for (final epoch in counted) {
            final window = await reader.recordsInWindow(
              bootEpoch: epoch,
              ceiling: limit,
            );
            windows.add(
              await _attributed(
                reader,
                BootWindow(
                  epoch: epoch,
                  station: stationOf[epoch] ?? '',
                  records: window.records,
                  truncated: !window.isComplete,
                ),
              ),
            );
          }
        }
        final certificate = foldSoakCertificate(
          requestedBoots: boots,
          claimedEpochs: ledger,
          windows: windows,
          seats: seats,
        );
        if (asJson) {
          write(renderSoakCertificateJson(certificate));
        } else {
          for (final line in renderSoakCertificate(certificate)) {
            write(line);
          }
        }
        return certificate.exitCode;
      } finally {
        await reader.close();
      }
  }
}

/// [window] with every round summary it could not attribute resolved against
/// the session's OWN records elsewhere in the log.
///
/// One bounded read per unattributed session and no read at all when the
/// window attributed everything, which is the common case on a scoped soak
/// boot.
Future<BootWindow> _attributed(
  TrajectoryLogReader reader,
  BootWindow window,
) async {
  final pending = sessionsNeedingWiderRead(window);
  if (pending.isEmpty) return window;
  final resolved = <String, String>{};
  for (final session in pending) {
    final rows = await reader.rowsForSubject(
      session,
      limit: kSubstationLookupRows,
    );
    for (final row in rows) {
      if (row.substation case final String substation) {
        resolved[session] = substation;
        break;
      }
    }
  }
  return window.withSubstations(resolved);
}
