import 'dart:io';

import 'package:args/command_runner.dart';

import 'station_command_client.dart';

/// `grid substation attach|detach` live-roster commands.
class SubstationCommand extends Command<int> {
  /// Creates the command group with an optional resident client.
  SubstationCommand({StationCommandClient? client})
    : _client = client ?? StationCommandClient() {
    addSubcommand(SubstationAttachCommand(client: _client));
    addSubcommand(SubstationDetachCommand(client: _client));
  }

  final StationCommandClient _client;

  @override
  final String name = 'substation';

  @override
  final String description =
      'Attach or detach a live substation without bouncing the station.';

  @override
  Future<int> run() async {
    printUsage();
    return 64;
  }
}

/// `grid substation attach <name>[@<prefix>]=<root>`.
class SubstationAttachCommand extends Command<int> {
  /// Creates the attach verb.
  SubstationAttachCommand({StationCommandClient? client})
    : _client = client ?? StationCommandClient() {
    argParser.addOption(
      'grid-root',
      help: 'The grid HOME containing .grid/station.lock. Required.',
    );
  }

  final StationCommandClient _client;

  @override
  final String name = 'attach';

  @override
  final String description =
      'Attach <name>[@<prefix>]=<root> to the running station.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      stderr.writeln(
        'grid substation attach: exactly one <name>[@<prefix>]=<root> is '
        'required.',
      );
      return 64;
    }
    final root = argResults!.option('grid-root');
    if (root == null || !root.startsWith('/')) {
      stderr.writeln(
        'grid substation attach: --grid-root is required and absolute.',
      );
      return 64;
    }
    return runSubstationAttach(
      gridRoot: root,
      spec: rest.single,
      client: _client,
    );
  }
}

/// `grid substation detach <name> [--force]`.
class SubstationDetachCommand extends Command<int> {
  /// Creates the detach verb.
  SubstationDetachCommand({StationCommandClient? client})
    : _client = client ?? StationCommandClient() {
    argParser
      ..addOption(
        'grid-root',
        help: 'The grid HOME containing .grid/station.lock. Required.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Drain instead of refusing when sessions are live.',
      );
  }

  final StationCommandClient _client;

  @override
  final String name = 'detach';

  @override
  final String description =
      'Detach an idle substation; --force drains live sessions.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      stderr.writeln('grid substation detach: exactly one <name> is required.');
      return 64;
    }
    final root = argResults!.option('grid-root');
    if (root == null || !root.startsWith('/')) {
      stderr.writeln(
        'grid substation detach: --grid-root is required and absolute.',
      );
      return 64;
    }
    return runSubstationDetach(
      gridRoot: root,
      name: rest.single,
      force: argResults!.flag('force'),
      client: _client,
    );
  }
}

/// Parses `<name>[@<prefix>]=<root>`, returning null for any other shape.
({String name, String? prefix, String root})? parseSubstationSpec(String raw) {
  final equals = raw.indexOf('=');
  if (equals <= 0 || equals == raw.length - 1) return null;
  final identity = raw.substring(0, equals);
  final root = raw.substring(equals + 1);
  final at = identity.indexOf('@');
  if (at == 0 || at == identity.length - 1) return null;
  return at < 0
      ? (name: identity, prefix: null, root: root)
      : (
          name: identity.substring(0, at),
          prefix: identity.substring(at + 1),
          root: root,
        );
}

/// Attaches [spec] through [client].
Future<int> runSubstationAttach({
  required String gridRoot,
  required String spec,
  required StationCommandClient client,
  void Function(String)? out,
  void Function(String)? err,
}) async {
  final write = out ?? stdout.writeln;
  final writeErr = err ?? stderr.writeln;
  final parsed = parseSubstationSpec(spec);
  if (parsed == null) {
    writeErr(
      'grid substation attach: "$spec" must be '
      '<name>[@<prefix>]=<root>.',
    );
    return 64;
  }
  final result = await client.send(
    gridRoot: gridRoot,
    method: 'grid/substation/attach',
    params: {
      'name': parsed.name,
      'root': parsed.root,
      if (parsed.prefix != null) 'prefix': parsed.prefix,
    },
  );
  switch (result) {
    case StationCommandCompleted(:final value):
      write(
        'grid substation attach — attached ${value['name']} '
        '(prefix ${value['prefix']}) at ${value['root']}.',
      );
      return 0;
    case StationCommandRefused(:final message) ||
        StationCommandUnavailable(:final message):
      writeErr('grid substation attach: $message');
      return 64;
  }
}

/// Detaches [name] through [client].
Future<int> runSubstationDetach({
  required String gridRoot,
  required String name,
  required bool force,
  required StationCommandClient client,
  void Function(String)? out,
  void Function(String)? err,
}) async {
  final write = out ?? stdout.writeln;
  final writeErr = err ?? stderr.writeln;
  final result = await client.send(
    gridRoot: gridRoot,
    method: 'grid/substation/detach',
    params: {'name': name, 'force': force},
  );
  switch (result) {
    case StationCommandCompleted(:final value):
      write(
        value['draining'] == true
            ? 'grid substation detach — draining $name; '
                  '${(value['inFlight'] as List?)?.length ?? 0} bead(s) in '
                  'flight.'
            : 'grid substation detach — detached $name '
                  '(${value['reapedWorktrees']} worktree(s) reaped).',
      );
      return 0;
    case StationCommandRefused(:final message) ||
        StationCommandUnavailable(:final message):
      writeErr('grid substation detach: $message');
      return 64;
  }
}
