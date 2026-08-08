import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:path/path.dart' as p;

final class FixtureCapture {
  FixtureCapture({required this.gridRunner, required this.sampleRunner});

  final BdRunner gridRunner;
  final BdRunner sampleRunner;

  static final RegExp _refPattern = RegExp(r'^[A-Za-z0-9._-]+$');
  static final RegExp _shaPattern = RegExp(r'^[0-9a-f]{40}$');

  Future<Directory> capture({
    required String ref,
    required String sha,
    required DateTime date,
    required String executable,
    required String sampleId,
    required Directory outputRoot,
  }) async {
    if (!_refPattern.hasMatch(ref)) {
      throw const FormatException('ref must match [A-Za-z0-9._-]+');
    }
    if (!_shaPattern.hasMatch(sha)) {
      throw const FormatException(
        'sha must be 40 lowercase hexadecimal characters',
      );
    }
    final day = date.toIso8601String().substring(0, 10);
    final target = Directory(p.join(outputRoot.path, '$day-bd-$ref'));
    final staging = Directory('${target.path}.staging');
    if (target.existsSync() || staging.existsSync()) {
      throw StateError('capture target already exists: ${target.path}');
    }
    staging.createSync(recursive: true);
    try {
      final commands = <_CaptureCommand>[
        _CaptureCommand('tg-list-all-empty.json', gridRunner, const [
          'list',
          '--json',
          '--all',
          '--limit',
          '0',
        ]),
        _CaptureCommand('tg-statuses.json', gridRunner, const [
          'statuses',
          '--json',
        ]),
        _CaptureCommand('tg-types.json', gridRunner, const ['types', '--json']),
        _CaptureCommand('tg-error-stdout.json', gridRunner, const [
          'dep',
          'list',
          'tg-nonexistent',
          '--json',
        ], expectedError: true),
        _CaptureCommand('fx-session-sample.json', sampleRunner, const [
          'list',
          '--json',
          '--all',
          '--type',
          'session',
          '--limit',
          '3',
        ]),
        _CaptureCommand('fx-message-sample.json', sampleRunner, const [
          'list',
          '--json',
          '--all',
          '--type',
          'message',
          '--limit',
          '3',
        ]),
        _CaptureCommand('fx-molecule-sample.json', sampleRunner, const [
          'list',
          '--json',
          '--all',
          '--type',
          'molecule',
          '--limit',
          '3',
        ]),
        _CaptureCommand('fx-ready-sample.json', sampleRunner, const [
          'ready',
          '--json',
          '--limit',
          '5',
        ]),
        _CaptureCommand('fx-show-sample.json', sampleRunner, [
          'show',
          sampleId,
          '--json',
        ]),
        _CaptureCommand('fx-export-sample.jsonl', sampleRunner, const [
          'export',
          '--include-infra',
        ], firstLines: 25),
      ];
      for (final command in commands) {
        final result = await command.runner.run(command.args);
        if (command.expectedError) {
          if (result.exitCode == 0 ||
              result.stdout.isEmpty ||
              result.stderr.isNotEmpty) {
            throw _CaptureCommandFailure(
              'expected stdout-only failure: ${command.args.join(' ')}',
            );
          }
        } else if (!result.ok) {
          throw _CaptureCommandFailure(
            'capture command failed (${result.exitCode}): '
            '${command.args.join(' ')}; stderr=${result.stderr}',
          );
        }
        var bytes = result.stdout;
        if (command.firstLines case final count?) {
          final lines = const LineSplitter().convert(bytes);
          bytes = '${lines.take(count).join('\n')}\n';
        }
        File(p.join(staging.path, command.fileName)).writeAsStringSync(bytes);
      }
      File(p.join(staging.path, 'README.md')).writeAsStringSync(
        _readme(ref: ref, sha: sha, executable: executable, commands: commands),
      );
      return staging.renameSync(target.path);
    } catch (_) {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      rethrow;
    }
  }

  String _readme({
    required String ref,
    required String sha,
    required String executable,
    required List<_CaptureCommand> commands,
  }) =>
      '''# Upstream fixtures — ${DateTime.now().toUtc().toIso8601String()}

**bd ref:** `$ref` · **resolved SHA:** `$sha` · **executable:** `$executable` · **environment:** `BD_JSON_ENVELOPE=1`, `BD_NON_INTERACTIVE=1` (forced by `ProcessBdRunner`).

The `tg-*` files come from the empty the_grid capture workspace. The `fx-*` files come from the seeded synthetic workspace. Captured output is never hand-edited; repeat the complete grid-porting capture into a new dated directory.

| File | Exact `bd` argv |
|---|---|
${commands.map((c) => '| `${c.fileName}` | `bd ${c.args.join(' ')}` |').join('\n')}

## Findings

Drift from the 1.0.5 set is asserted in `packages/beads_dart/test/tool/fixture_drift_test.dart`: `show --json` adds `revision`, and truncated envelope output adds `pagination`; envelope schema version remains 1.
''';
}

final class _CaptureCommand {
  const _CaptureCommand(
    this.fileName,
    this.runner,
    this.args, {
    this.expectedError = false,
    this.firstLines,
  });
  final String fileName;
  final BdRunner runner;
  final List<String> args;
  final bool expectedError;
  final int? firstLines;
}

final class _CaptureCommandFailure extends StateError {
  _CaptureCommandFailure(super.message);
}

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('ref')
    ..addOption('sha')
    ..addOption('bd')
    ..addOption('grid-root')
    ..addOption('sample-root')
    ..addOption('sample-id')
    ..addOption('output-root')
    ..addOption('date');

  try {
    final options = parser.parse(arguments);
    String requireOption(String name) {
      final value = options.option(name);
      if (value == null || value.isEmpty) {
        throw FormatException('--$name is required');
      }
      return value;
    }

    final ref = requireOption('ref');
    final sha = requireOption('sha');
    final bd = requireOption('bd');
    final gridRoot = requireOption('grid-root');
    final sampleRoot = requireOption('sample-root');
    final sampleId = requireOption('sample-id');
    final outputRoot = requireOption('output-root');
    final dateOption = options.option('date');
    final date = dateOption == null
        ? DateTime.now().toUtc()
        : DateTime.parse(dateOption).toUtc();
    final capture = FixtureCapture(
      gridRunner: ProcessBdRunner(workspaceRoot: gridRoot, executable: bd),
      sampleRunner: ProcessBdRunner(workspaceRoot: sampleRoot, executable: bd),
    );
    final result = await capture.capture(
      ref: ref,
      sha: sha,
      date: date,
      executable: bd,
      sampleId: sampleId,
      outputRoot: Directory(outputRoot),
    );
    stdout.writeln(result.path);
  } on _CaptureCommandFailure catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on ArgParserException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  }
}
