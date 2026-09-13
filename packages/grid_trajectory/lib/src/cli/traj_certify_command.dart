/// `traj certify` — the §W2.5 soak certificate as a PASS/FAIL verb.
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
/// certificate, it simply has nothing to certify yet.
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
      'clean counters, shape coverage, would-refuse, consecutive.';

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
              BootWindow(
                epoch: epoch,
                station: stationOf[epoch] ?? '',
                records: window.records,
                truncated: !window.isComplete,
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
