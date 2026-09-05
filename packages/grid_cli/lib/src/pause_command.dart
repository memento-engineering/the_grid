import 'dart:io';

import 'package:args/command_runner.dart';

import 'station_command_client.dart';

/// Shared implementation for the pause/resume resident one-shots.
class _PauseVerb extends Command<int> {
  _PauseVerb({
    required this.name,
    required this.description,
    required String method,
    StationCommandClient? client,
  }) : _method = method,
       _client = client ?? StationCommandClient() {
    argParser.addOption(
      'grid-root',
      help: 'The grid HOME containing .grid/station.lock. Required.',
    );
  }

  final StationCommandClient _client;
  final String _method;

  @override
  final String name;

  @override
  final String description;

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.length != 1) {
      stderr.writeln(
        args.rest.isEmpty
            ? 'grid $name: a <bead-id> is required.'
            : 'grid $name: $name accepts exactly one bead id.',
      );
      return 64;
    }
    final gridRoot = args.option('grid-root');
    if (gridRoot == null || gridRoot.trim().isEmpty) {
      stderr.writeln('grid $name: --grid-root is required.');
      return 64;
    }
    if (!gridRoot.startsWith('/')) {
      stderr.writeln('grid $name: --grid-root must be an absolute path.');
      return 64;
    }
    final result = await _client.send(
      gridRoot: gridRoot,
      method: _method,
      params: {'beadId': args.rest.single},
    );
    switch (result) {
      case StationCommandCompleted(:final value):
        stdout.writeln(
          'grid $name — ${value['sessionId'] ?? args.rest.single}: '
          '${value['pauseState'] ?? name}'
          '${value['changed'] == false ? ' (already)' : ''}',
        );
        return 0;
      case StationCommandRefused(:final message) ||
          StationCommandUnavailable(:final message):
        stderr.writeln('grid $name: $message');
        return 64;
    }
  }
}

/// Parks a live session without retiring its round.
class PauseCommand extends _PauseVerb {
  /// Creates the pause command with an optional injected resident client.
  PauseCommand({super.client})
    : super(
        name: 'pause',
        description:
            'Pause the live session driving a bead: stop its agent, free its '
            'slot, preserve its cursor. Resume with `grid resume`.',
        method: 'grid/session/pause',
      );
}

/// Re-admits a paused session at its preserved cursor.
class ResumeCommand extends _PauseVerb {
  /// Creates the resume command with an optional injected resident client.
  ResumeCommand({super.client})
    : super(
        name: 'resume',
        description:
            'Resume a paused session: re-compete for a slot, then continue '
            'from the preserved cursor. Completed stages do not re-run.',
        method: 'grid/session/resume',
      );
}
