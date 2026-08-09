/// The reusable resident `down` command.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import 'state_workspace.dart';
import 'station_attach.dart';

/// Gracefully stops a composed resident station through its lock.
class DownCommand extends Command<int> {
  /// Creates the command for [stationName].
  DownCommand({required this.stationName, StationAttach? attach})
    : _attach = attach ?? StationAttach() {
    argParser.addOption('state-workspace', help: stateWorkspaceHelp);
  }

  /// The composing runner's operator-facing station name.
  final String stationName;
  final StationAttach _attach;

  @override
  String get name => 'down';

  @override
  String get description =>
      'Gracefully stop the resident station with SIGTERM; never SIGKILL.';

  @override
  Future<int> run() async {
    final resolved = resolveStateWorkspace(
      stationName: stationName,
      verb: name,
      stateWorkspacePath: argResults!.option('state-workspace'),
    );
    return switch (resolved) {
      StateWorkspaceRefusal(:final message, :final code) => _refuse(
        message,
        code,
      ),
      StateWorkspaceFound(:final home) => _stop(home),
    };
  }

  int _refuse(String message, int code) {
    stderr.writeln(message);
    return code;
  }

  Future<int> _stop(String home) async {
    return switch (await _attach.stop(stateWorkspaceDir: home)) {
      AlreadyDown() => _alreadyDown(home),
      Stopped(:final pid) => _stopped(pid),
      TimedOut(:final pid) => _timedOut(pid),
    };
  }

  int _alreadyDown(String home) {
    stdout.writeln(
      '$stationName down: already down — no live station at $home.',
    );
    return 0;
  }

  int _stopped(int pid) {
    stdout.writeln(
      '$stationName down: stopped station (pid $pid) — the lock is released.',
    );
    return 0;
  }

  int _timedOut(int pid) {
    stderr.writeln(
      '$stationName down: SIGTERM sent to pid $pid but it did not exit and '
      'release its lock within the grace window — this client never escalates '
      'to SIGKILL. Investigate pid $pid directly.',
    );
    return 1;
  }
}
