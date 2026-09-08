import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'station_command_client.dart';

/// Lists and explicitly collects held sessions through the resident station.
class SessionCommand extends Command<int> {
  /// Creates the session noun-domain with its `ls` and `collect` verbs.
  SessionCommand({StationCommandClient? client})
    : _client = client ?? StationCommandClient() {
    addSubcommand(SessionLsCommand(client: _client));
    addSubcommand(SessionCollectCommand(client: _client));
  }

  final StationCommandClient _client;

  @override
  final String name = 'session';

  @override
  final String description =
      'List held sessions and collect their preserved worktrees.';

  @override
  Future<int> run() async {
    printUsage();
    return 64;
  }
}

/// `grid session ls` lists held sessions with preserved worktrees.
class SessionLsCommand extends Command<int> {
  /// Creates the held-session list verb.
  SessionLsCommand({StationCommandClient? client})
    : _client = client ?? StationCommandClient() {
    _addGridRootOption(argParser);
  }

  final StationCommandClient _client;

  @override
  final String name = 'ls';

  @override
  final String description =
      'List closed held sessions whose preserved worktree still exists.';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      stderr.writeln('grid session ls: ls accepts no positional arguments.');
      return 64;
    }
    final root = _gridRoot(argResults!, stderr.writeln, 'ls');
    if (root == null) return 64;
    return runSessionLs(gridRoot: root, client: _client);
  }
}

/// `grid session collect <session-id>...` previews or acts on held sessions.
class SessionCollectCommand extends Command<int> {
  /// Creates the explicit held-session collection verb.
  SessionCollectCommand({StationCommandClient? client})
    : _client = client ?? StationCommandClient() {
    _addGridRootOption(argParser);
    argParser
      ..addFlag(
        'act',
        negatable: false,
        help: 'Remove the preflighted worktree; absent means preview only.',
      )
      ..addFlag(
        'bulk',
        negatable: false,
        help: 'Authorize collection of more than one named session.',
      )
      ..addFlag(
        'override-unsafe',
        negatable: false,
        help: 'Permit known-present git gates; probe failures still refuse.',
      );
  }

  final StationCommandClient _client;

  @override
  final String name = 'collect';

  @override
  final String description =
      'Preview held-session worktree collection; pass --act to remove.';

  @override
  Future<int> run() async {
    final root = _gridRoot(argResults!, stderr.writeln, 'collect');
    if (root == null) return 64;
    return runSessionCollect(
      gridRoot: root,
      sessionIds: argResults!.rest,
      act: argResults!.flag('act'),
      bulk: argResults!.flag('bulk'),
      overrideUnsafe: argResults!.flag('override-unsafe'),
      client: _client,
    );
  }
}

void _addGridRootOption(ArgParser parser) {
  parser.addOption(
    'grid-root',
    help: 'The grid HOME containing .grid/station.lock. Required.',
  );
}

String? _gridRoot(
  ArgResults args,
  void Function(String) writeErr,
  String verb,
) {
  final value = args.option('grid-root');
  if (value == null || value.trim().isEmpty) {
    writeErr('grid session $verb: --grid-root is required.');
    return null;
  }
  if (!value.startsWith('/')) {
    writeErr('grid session $verb: --grid-root must be an absolute path.');
    return null;
  }
  return value;
}

/// Lists held sessions through [client] and renders every preserved artifact.
Future<int> runSessionLs({
  required String gridRoot,
  required StationCommandClient client,
  void Function(String)? out,
  void Function(String)? err,
}) async {
  final write = out ?? stdout.writeln;
  final writeErr = err ?? stderr.writeln;
  final result = await client.send(
    gridRoot: gridRoot,
    method: 'grid/session/ls',
    params: const {},
  );
  switch (result) {
    case StationCommandRefused(:final message) ||
        StationCommandUnavailable(:final message):
      writeErr('grid session ls: $message');
      return 64;
    case StationCommandCompleted(:final value):
      final sessions = _rows(value);
      write(
        'grid session ls — ${sessions.length} held session'
        '${sessions.length == 1 ? '' : 's'} with preserved worktrees:',
      );
      for (final row in sessions) {
        write(
          '  ${row['sessionId']}  work ${row['workBeadId']}\n'
          '    worktree: ${row['worktree']}\n'
          '    branch: ${row['branch']}\n'
          '    held reason: ${row['heldReason']}',
        );
      }
      return 0;
  }
}

/// Collects named held sessions through [client], previewing unless [act].
Future<int> runSessionCollect({
  required String gridRoot,
  required List<String> sessionIds,
  required StationCommandClient client,
  bool act = false,
  bool bulk = false,
  bool overrideUnsafe = false,
  void Function(String)? out,
  void Function(String)? err,
}) async {
  final write = out ?? stdout.writeln;
  final writeErr = err ?? stderr.writeln;
  if (sessionIds.isEmpty || sessionIds.any((id) => id.trim().isEmpty)) {
    writeErr('grid session collect: at least one <session-id> is required.');
    return 64;
  }
  if (sessionIds.toSet().length != sessionIds.length) {
    writeErr('grid session collect: duplicate session ids are not allowed.');
    return 64;
  }
  if (sessionIds.length > 1 && !bulk) {
    writeErr('grid session collect: more than one session requires --bulk.');
    return 64;
  }
  final result = await client.send(
    gridRoot: gridRoot,
    method: 'grid/session/collect',
    params: {
      'sessionIds': List<String>.of(sessionIds),
      'act': act,
      'bulk': bulk,
      'overrideUnsafe': overrideUnsafe,
    },
  );
  switch (result) {
    case StationCommandRefused(:final message) ||
        StationCommandUnavailable(:final message):
      writeErr('grid session collect: $message');
      return 64;
    case StationCommandCompleted(:final value):
      for (final row in _rows(value)) {
        final preview = row['status'] == 'would_collect';
        write(
          '${preview ? 'WOULD collect' : 'collected'} '
          '${row['sessionId']} (${row['workBeadId']})\n'
          '  worktree: ${row['worktree']}\n'
          '  branch: ${row['branch']}\n'
          '  held reason: ${row['heldReason']}',
        );
      }
      return 0;
  }
}

List<Map<String, Object?>> _rows(Map<String, Object?> value) {
  final raw = value['sessions'];
  return raw is List
      ? raw
            .whereType<Map<Object?, Object?>>()
            .map((row) => row.cast<String, Object?>())
            .toList(growable: false)
      : <Map<String, Object?>>[];
}
