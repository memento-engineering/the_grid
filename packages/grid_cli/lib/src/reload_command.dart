/// The operator's EXPLICIT hot-reload trigger, and the dev-mode sibling of the
/// `up`/`down`/`status` verbs RS-5b shipped.
///
/// Generic and asset-agnostic (it lives here beside `watch`/`gate`/`rework`); an
/// asset runner binds it into its own `CommandRunner`, so the verb reads e.g.
/// `space reload`.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'station_reload.dart';

/// `reload [--restart]`: hot-reload the resident JIT station.
class ReloadCommand extends Command<int> {
  /// Creates the command; [client] is injected by the offline suite.
  ReloadCommand({StationReload? client}) : _client = client ?? StationReload() {
    argParser
      ..addOption(
        'grid-home',
        mandatory: true,
        help:
            'The grid home whose station to reload — its lock lives at '
            '<grid-home>/.grid/station.lock.',
      )
      ..addFlag(
        'restart',
        help:
            "Hot-RESTART: re-run the station's delegate factory (a fresh "
            'delegate — the Flutter hot-restart shape) instead of re-running '
            'its master build. Live sessions are ADOPTED either way: a running '
            'agent is never killed.',
      )
      ..addOption(
        'vm-service-uri',
        help:
            'Override the VM-service URI the station advertised in its lock '
            '(e.g. the URI the VM printed at boot).',
      );
  }

  final StationReload _client;

  @override
  String get name => 'reload';

  @override
  String get description =>
      'Hot-reload (or --restart) the resident JIT station over its VM service: '
      'landed code changes activate with no down/up/recompile bounce, and live '
      'sessions are adopted, never killed.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final uri = args['vm-service-uri'] as String?;
    final result = await _client.reload(
      gridHome: p.absolute(args['grid-home'] as String),
      restart: args['restart'] as bool,
      vmServiceUri: uri == null ? null : Uri.parse(uri),
    );
    return switch (result) {
      Reloaded(:final mode, :final generation, :final rebuiltBranches) => _ok(
        'reload: $mode OK — generation $generation, $rebuiltBranches branches '
        'rebuilt; live sessions ADOPTED (no agent was killed).',
      ),
      ReloadStationDown() => _refuse(
        'reload: no live station at this grid home — nothing to reload. Start '
        'one with `up`.',
      ),
      ReloadNotDevMode(:final pid) => _refuse(
        'reload: the station (pid $pid) advertises no VM service — it is not '
        'running in dev mode. Start it JIT with '
        '`dart bin/<runner>.dart up ... --enable-vm-service`, or pass '
        '--vm-service-uri.',
      ),
      ReloadRefused(:final reason) => _refuse('reload: REFUSED — $reason'),
    };
  }

  int _ok(String line) {
    stdout.writeln(line);
    return 0;
  }

  int _refuse(String line) {
    stderr.writeln(line);
    return 1;
  }
}
