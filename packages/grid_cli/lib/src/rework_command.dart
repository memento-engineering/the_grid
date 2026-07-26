import 'dart:io';

import 'package:args/command_runner.dart';

import 'station_command_client.dart';

/// Retires one rework round through the resident StationControl door.
class ReworkCommand extends Command<int> {
  /// Creates the command with an optional injected resident client.
  ReworkCommand({StationCommandClient? client})
    : _client = client ?? StationCommandClient() {
    argParser
      ..addOption(
        'note',
        help: 'An operator finding to append to the work bead.',
      )
      ..addFlag(
        'beyond-cap',
        negatable: false,
        help: 'Authorize a round beyond the normal cap.',
      )
      ..addOption('actor', help: 'The operator authorizing --beyond-cap.')
      ..addOption(
        'grid-root',
        help: 'The grid HOME containing .grid/station.lock. Required.',
      );
  }

  final StationCommandClient _client;

  @override
  final String name = 'rework';

  @override
  final String description =
      'Retire the current session round through the resident station.';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.length != 1) {
      stderr.writeln(
        args.rest.isEmpty
            ? 'grid rework: a <bead-id> is required.'
            : 'grid rework: rework accepts exactly one bead id.',
      );
      return 64;
    }
    final gridRoot = args.option('grid-root');
    if (gridRoot == null || gridRoot.trim().isEmpty) {
      stderr.writeln('grid rework: --grid-root is required.');
      return 64;
    }
    if (!gridRoot.startsWith('/')) {
      stderr.writeln('grid rework: --grid-root must be an absolute path.');
      return 64;
    }
    final beyondCap = args.flag('beyond-cap');
    final actor = args.option('actor');
    final note = args.option('note');
    if (beyondCap && (actor == null || actor.trim().isEmpty)) {
      stderr.writeln(
        'grid rework: --actor is required with --beyond-cap '
        '(the human ruling must be attributed).',
      );
      return 64;
    }
    if (beyondCap && (note == null || note.trim().isEmpty)) {
      stderr.writeln(
        'grid rework: --note is required with --beyond-cap '
        '(the human ruling must carry a reason).',
      );
      return 64;
    }
    final result = await _client.send(
      gridRoot: gridRoot,
      method: 'grid/rework',
      params: {
        'beadId': args.rest.single,
        'note': note,
        'beyondCap': beyondCap,
        'actor': actor,
      },
    );
    switch (result) {
      case StationCommandCompleted():
        return 0;
      case StationCommandRefused(:final message) ||
          StationCommandUnavailable(:final message):
        stderr.writeln('grid rework: $message');
        return 64;
    }
  }
}
