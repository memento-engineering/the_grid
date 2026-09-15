import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'station_command_client.dart';

/// Operates the resident station's admission budget.
class AdmissionCommand extends Command<int> {
  /// Creates the admission noun-domain with its `set` verb.
  AdmissionCommand({
    StationCommandClient? client,
    void Function(String)? out,
    void Function(String)? err,
  }) {
    addSubcommand(AdmissionSetCommand(client: client, out: out, err: err));
  }

  @override
  final String name = 'admission';

  @override
  final String description = 'Operate the resident admission budget.';

  @override
  Future<int> run() async {
    printUsage();
    return 64;
  }
}

/// `grid admission set <max-agents>` changes the live station ceiling.
class AdmissionSetCommand extends Command<int> {
  /// Creates the admission-ceiling setter with injectable command I/O.
  AdmissionSetCommand({
    StationCommandClient? client,
    void Function(String)? out,
    void Function(String)? err,
  }) : _client = client ?? StationCommandClient(),
       _out = out,
       _err = err {
    argParser.addOption(
      'grid-root',
      help: 'The grid HOME containing .grid/station.lock. Required.',
    );
  }

  final StationCommandClient _client;
  final void Function(String)? _out;
  final void Function(String)? _err;

  @override
  final String name = 'set';

  @override
  final String description =
      'Set the live station-wide maximum number of admitted agents.';

  @override
  Future<int> run() => runAdmissionSet(
    gridRoot: argResults!.option('grid-root'),
    arguments: argResults!.rest,
    client: _client,
    out: _out,
    err: _err,
  );
}

/// Validates and sends one live admission-ceiling change.
Future<int> runAdmissionSet({
  required String? gridRoot,
  required List<String> arguments,
  required StationCommandClient client,
  void Function(String)? out,
  void Function(String)? err,
}) async {
  final write = out ?? stdout.writeln;
  final writeErr = err ?? stderr.writeln;
  if (arguments.length != 1) {
    writeErr(
      arguments.isEmpty
          ? 'grid admission set: a <positive-max-agents> value is required.'
          : 'grid admission set: exactly one <positive-max-agents> value is '
                'required.',
    );
    return 64;
  }
  final token = arguments.single;
  if (!RegExp(r'^-?[0-9]+$').hasMatch(token)) {
    writeErr(
      'grid admission set: max agents must be a positive decimal integer.',
    );
    return 64;
  }
  final maxAgents = int.tryParse(token);
  if (maxAgents == null || maxAgents <= 0) {
    writeErr(
      'grid admission set: max agents must be greater than zero and fit in '
      'a Dart integer.',
    );
    return 64;
  }
  if (gridRoot == null || gridRoot.trim().isEmpty) {
    writeErr('grid admission set: --grid-root is required.');
    return 64;
  }
  if (!p.isAbsolute(gridRoot)) {
    writeErr('grid admission set: --grid-root must be an absolute path.');
    return 64;
  }

  final result = await client.send(
    gridRoot: gridRoot,
    method: 'grid/admission/set',
    params: {'maxAgents': maxAgents},
  );
  switch (result) {
    case StationCommandCompleted(:final value):
      write(
        'grid admission set — max agents: ${value['maxAgents']} '
        '(source: ${value['maxAgentsSource']}).',
      );
      return 0;
    case StationCommandRefused(:final message) ||
        StationCommandUnavailable(:final message):
      writeErr('grid admission set: $message');
      return 64;
  }
}
