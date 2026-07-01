import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_assets/grid_assets.dart'
    show
        CommandResult,
        ComputeBounds,
        DartCommand,
        DispatchCommand,
        computeDispatchHandler,
        kComputeKind;
import 'package:grid_cli/src/code_run_command.dart';
import 'package:grid_cli/src/demo_command.dart';
import 'package:grid_cli/src/gate_command.dart';
import 'package:grid_cli/src/lease_command.dart';
import 'package:grid_cli/src/serve_command.dart';
import 'package:grid_cli/src/watch_command.dart';

// The reference app (the `space_station` template): it ASSEMBLES the Commands it
// wants — the generic CLI-SDK ones (watch/gate/serve/lease) + the code asset's
// CodeRunCommand — over the framework. There is no baked-in `grid run`; a real
// station is a runner like this, AOT-compiled (see docs/SCRATCH-dart-runner-and-
// cli-sdk.md).
Future<void> main(List<String> arguments) async {
  final runner =
      CommandRunner<int>('grid', 'the_grid — a reactive beads controller.')
        ..addCommand(WatchCommand())
        ..addCommand(CodeRunCommand())
        // The FIRST asset-exported Command consumed by a runner (the CLI-SDK
        // model): the DART domain ships it from grid_assets; this app just
        // assembles it.
        ..addCommand(DartCommand())
        ..addCommand(GateCommand())
        ..addCommand(DemoCommand())
        // serve/lease are GENERIC core commands ("leasing is core"); the
        // COMPUTE asset's use (bounded dispatch + its payload/result codec) is
        // assembled in here — the asset owns the "use" (ADR-0011 D3).
        ..addCommand(
          ServeCommand(
            defaultKind: kComputeKind,
            configureFlags: (parser) => parser
              ..addMultiOption(
                'allow',
                defaultsTo: const [
                  'dart',
                  'echo',
                  'flutter',
                  'git',
                  'hostname',
                  'melos',
                  'uname',
                ],
                help:
                    'The executables the lessor will run (the bounded-use '
                    'allow-list). A dispatched command not on this list is '
                    'REFUSED (no shell-as-a-service; ADR-0011 RCE-bounds).',
              )
              ..addOption(
                'exec-timeout',
                defaultsTo: '300',
                help:
                    'Per-command timeout in seconds (the bounded-use upper '
                    'bound).',
              ),
            handlerFor: (args, log) {
              final bounds = ComputeBounds(
                allowedCommands: args.multiOption('allow').toSet(),
                timeout:
                    Duration(seconds: int.parse(args.option('exec-timeout')!)),
              );
              return (
                handler: computeDispatchHandler(bounds: bounds, onLog: log),
                banner:
                    'bounded use: allow-list '
                    '${bounds.allowedCommands.toList()..sort()}  ·  '
                    'timeout ${bounds.timeout.inSeconds}s',
              );
            },
          ),
        )
        ..addCommand(
          LeaseCommand(
            defaultKind: kComputeKind,
            payloadFor: (rest) => DispatchCommand(
              command: rest.first,
              args: rest.skip(1).toList(),
            ).toJson(),
            render: (raw, out, err) {
              final r = CommandResult.fromJson(raw);
              if (r.stdout.isNotEmpty) out(r.stdout);
              if (r.stderr.isNotEmpty) err(r.stderr);
              return r.exitCode;
            },
          ),
        );

  try {
    final code = await runner.run(arguments);
    if (code != null && code != 0) exitCode = code;
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  }
}

/// `grid watch` — stream typed graph events from the live work graph.
class WatchCommand extends Command<int> {
  WatchCommand() {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit NDJSON (one JSON event per line) instead of human output.',
      )
      ..addFlag(
        'no-sql',
        negatable: false,
        help:
            'Force the bd-CLI read path even when pooled Dolt SQL is '
            'available.',
      )
      ..addOption(
        'for-seconds',
        help:
            'Run for a fixed number of seconds then exit (for scripted '
            'demos / CI) instead of until Ctrl-C.',
      );
  }

  @override
  final String name = 'watch';

  @override
  final String description =
      'Watch the work graph and print typed events with reaction latency. '
      'Run under `dart run --enable-vm-service` to allow exploration tools to '
      'attach.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final seconds = args.option('for-seconds');
    return runWatch(
      json: args.flag('json'),
      noSql: args.flag('no-sql'),
      runFor: seconds == null ? null : Duration(seconds: int.parse(seconds)),
    );
  }
}
