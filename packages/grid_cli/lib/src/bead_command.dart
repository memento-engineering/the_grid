import 'dart:io';

import 'package:args/command_runner.dart';

import 'operator_text_file.dart';
import 'station_command_client.dart';

/// Operator bead commands serviced by the resident station.
final class BeadCommand extends Command<int> {
  BeadCommand({StationCommandClient? client, Stream<List<int>>? input}) {
    addSubcommand(BeadSetCommand(client: client, input: input));
  }

  @override
  String get name => 'bead';

  @override
  String get description => 'Operate on resident-owned beads.';
}

/// Writes bead prose exclusively from a file or stdin.
final class BeadSetCommand extends Command<int> {
  BeadSetCommand({StationCommandClient? client, Stream<List<int>>? input})
    : _client = client ?? StationCommandClient(),
      _input = input {
    argParser
      ..addOption('bead', mandatory: true)
      ..addOption(
        'field',
        mandatory: true,
        allowed: const ['description', 'design', 'acceptance', 'notes'],
      )
      ..addOption('file', mandatory: true)
      ..addFlag('append', negatable: false)
      ..addOption('grid-root', mandatory: true);
  }

  final StationCommandClient _client;
  final Stream<List<int>>? _input;

  @override
  String get name => 'set';

  @override
  String get description => 'Write bead prose from a UTF-8 file or stdin.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final root = args.option('grid-root')!;
    final field = args.option('field')!;
    final append = args.flag('append');
    if (!root.startsWith('/')) {
      stderr.writeln('grid bead set: --grid-root must be an absolute path.');
      return 64;
    }
    if (append && field != 'notes') {
      stderr.writeln('grid bead set: --append is valid only for notes.');
      return 64;
    }
    String content;
    try {
      content = (await selectOperatorText(
        inlineFlag: '--text',
        fileFlag: '--file',
        inlineValue: null,
        filePath: args.option('file'),
        input: _input,
      ))!;
    } on FileSystemException catch (error) {
      stderr.writeln(
        'grid bead set: cannot read --file ${args.option('file')}: ${error.message}',
      );
      return 64;
    } on FormatException catch (error) {
      stderr.writeln(
        'grid bead set: --file ${args.option('file')} is not valid UTF-8: ${error.message}',
      );
      return 64;
    }
    final result = await _client.send(
      gridRoot: root,
      method: 'grid/bead/set',
      params: {
        'beadId': args.option('bead')!,
        'field': field,
        'content': content,
        'append': append,
      },
    );
    switch (result) {
      case StationCommandCompleted():
        return 0;
      case StationCommandRefused(:final message):
        stderr.writeln('grid bead set: $message');
        return 1;
      case StationCommandUnavailable(:final message):
        stderr.writeln(
          'grid bead set: $message No direct fallback was attempted. '
          'Without the resident, description/design may use bd update '
          '--body-file, --design-file, or --stdin; acceptance/notes require the resident.',
        );
        return 69;
    }
  }
}
