/// `traj committee-report` — per-lane committee effectiveness from the log.
///
/// Read-only and cross-session: it reads one TIME/EPOCH window off the
/// trajectory database through [TrajectoryLogReader.recordsInWindow] (never
/// the bd CLI, never a per-bead loop) and folds it into per-lane grade counts,
/// gate-causing verdicts, override-vs-uphold, respec convergence, mean cost
/// and duration, and per-bead rounds and dollars.
///
/// `.usage.json` files are consulted ONLY through `--telemetry-root`, and only
/// for a (bead, lane) pair the log carried no `verify.usage.telemetry` row
/// for.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import 'committee_report.dart';
import 'committee_report_render.dart';
import 'committee_report_usage.dart';
import 'traj_flags.dart';
import 'trajectory_reader.dart';

/// How the verb recovers fallback usage samples; injected so the fixture test
/// drives the fallback without a filesystem.
typedef UsageFallbackSource = List<UsageSample> Function(String root);

/// The verb.
class TrajCommitteeReportCommand extends Command<int> {
  /// Creates the report verb with optional injected seams (tests script the
  /// log and the fallback without a socket or a directory).
  TrajCommitteeReportCommand({
    TrajectoryOpener? open,
    UsageFallbackSource? usageFallback,
  }) : _open = open ?? openTrajectoryReader,
       _usageFallback = usageFallback ?? scanUsageFallback {
    addGridHomeOption(argParser);
    argParser
      ..addOption(
        'since',
        help:
            'ISO-8601 instant; only records at or after it are folded. '
            'Omitted reads the whole log.',
      )
      ..addOption(
        'epoch',
        help: 'Restrict the window to one boot epoch (boot_epoch).',
      )
      ..addOption(
        'telemetry-root',
        help:
            'A directory scanned recursively for <bead>_<lane>.usage.json '
            'harness envelopes. FALLBACK only: a sample is folded solely '
            'where the log carried no verify.usage.telemetry row for that '
            'bead and lane.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit one JSON object instead of the operator table.',
      )
      ..addOption(
        'limit',
        help:
            'Ceiling on the window read (default $completeReadCeiling). Not a '
            'window: a log that reaches it is reported TRUNCATED, never '
            'printed as a total.',
      );
  }

  final TrajectoryOpener _open;
  final UsageFallbackSource _usageFallback;

  @override
  final String name = 'committee-report';

  @override
  final String description =
      'Report per-lane committee effectiveness — grade counts, gate-causing '
      'verdicts, overrides, respec convergence, and dollars per round.';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      stderr.writeln(
        'traj committee-report: unexpected argument '
        '"${argResults!.rest.first}"; the window rides --since/--epoch.',
      );
      return 64;
    }
    final gridHome = gridHomeFrom(
      argResults!,
      stderr.writeln,
      'committee-report',
    );
    if (gridHome == null) return 64;
    final limit = positiveIntFrom(
      argResults!,
      'limit',
      stderr.writeln,
      'committee-report',
      fallback: completeReadCeiling,
    );
    if (limit == null) return 64;
    DateTime? since;
    if (argResults!.option('since') case final String raw) {
      since = DateTime.tryParse(raw);
      if (since == null) {
        stderr.writeln(
          'traj committee-report: --since must be an ISO-8601 instant '
          '(got "$raw").',
        );
        return 64;
      }
    }
    final epoch = positiveIntFrom(
      argResults!,
      'epoch',
      stderr.writeln,
      'committee-report',
      fallback: 0,
    );
    if (epoch == null) return 64;
    return runTrajCommitteeReport(
      gridHome: gridHome,
      open: _open,
      usageFallback: _usageFallback,
      since: since,
      bootEpoch: epoch == 0 ? null : epoch,
      telemetryRoot: argResults!.option('telemetry-root'),
      asJson: argResults!.flag('json'),
      limit: limit,
    );
  }
}

/// Reads the window, folds it, prints it.
///
/// An unbootstrapped grid home is reported and exits 0 — the trajectory
/// database is additive, so its absence is a state, not a failure (the rule
/// `traj show` already follows). A server that should answer and does not
/// exits 1.
Future<int> runTrajCommitteeReport({
  required String gridHome,
  required TrajectoryOpener open,
  required UsageFallbackSource usageFallback,
  DateTime? since,
  int? bootEpoch,
  String? telemetryRoot,
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
      write('traj committee-report: $message');
      return 0;
    case TrajectoryUnavailable(:final message):
      writeErr('traj committee-report: $message');
      return 1;
    case TrajectoryOpened(:final reader):
      try {
        final window = await reader.recordsInWindow(
          since: since,
          bootEpoch: bootEpoch,
          ceiling: limit,
        );
        final report = foldCommitteeReport(
          window.records,
          fallback: telemetryRoot == null
              ? const []
              : usageFallback(telemetryRoot),
          truncated: !window.isComplete,
        );
        if (asJson) {
          write(renderCommitteeReportJson(report));
        } else {
          for (final line in renderCommitteeReport(report)) {
            write(line);
          }
        }
        return 0;
      } finally {
        await reader.close();
      }
  }
}
