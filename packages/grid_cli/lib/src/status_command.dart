/// The reusable resident `status` command.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart' show BeadOwnershipPredicate;

import 'state_workspace.dart';
import 'station_attach.dart';

/// Constructs the one-shot snapshot reader used by the down fallback.
typedef SnapshotReaderFactory =
    SnapshotReader Function(BeadsWorkspace workspace);

/// The real two-spawn CLI snapshot reader.
SnapshotReader cliSnapshotReader(BeadsWorkspace workspace) => CliSnapshotReader(
  BdCliService(ProcessBdRunner(workspaceRoot: workspace.root)),
);

/// Renders live resident status or a read-only store fallback.
class StatusCommand extends Command<int> {
  /// Creates the command for [stationName].
  StatusCommand({
    required this.stationName,
    StationAttach? attach,
    SnapshotReaderFactory? snapshotReader,
  }) : _attach = attach ?? StationAttach(),
       _snapshotReader = snapshotReader ?? cliSnapshotReader {
    argParser
      ..addOption('state-workspace', help: stateWorkspaceHelp)
      ..addOption(
        'workspace',
        abbr: 'w',
        help: 'Work-store root used only while the station is down.',
      )
      ..addMultiOption(
        'substation',
        abbr: 'r',
        help: 'Owned substation token used by the down fallback.',
      )
      ..addMultiOption('owner', help: 'Alias for --substation.')
      ..addFlag(
        'json',
        negatable: false,
        help: 'Write the complete resident status payload as JSON.',
      );
  }

  /// The composing runner's operator-facing station name.
  final String stationName;
  final StationAttach _attach;
  final SnapshotReaderFactory _snapshotReader;

  @override
  String get name => 'status';

  @override
  String get description =>
      'Show live resident status or a read-only owned-ready fallback.';

  @override
  Future<int> run() async {
    final args = argResults!;
    return switch (resolveStateWorkspace(
      stationName: stationName,
      verb: name,
      stateWorkspacePath: args.option('state-workspace'),
    )) {
      StateWorkspaceRefusal(:final message, :final code) => _renderRefusal(
        message,
        code,
      ),
      StateWorkspaceFound(:final home, :final workspace) =>
        switch (await _attach.status(stateWorkspaceDir: home)) {
          Up(:final payload) => _renderUp(payload, json: args.flag('json')),
          SlowUp(:final payload, :final elapsed) => _renderUp(
            payload,
            slowElapsed: elapsed,
            json: args.flag('json'),
          ),
          Down() => await _renderDownFallback(args, workspace),
          Starting(:final pid) => _renderRefusal(
            '$stationName status: station is BOOTING (pid $pid).',
            1,
          ),
          DeadPid(:final pid) => _renderDeadPid(
            pid: pid,
            home: home,
            json: args.flag('json'),
          ),
          final Unreachable unreachable => _renderUnreachable(
            unreachable,
            json: args.flag('json'),
          ),
          Unauthorized(:final record) => _renderRefusal(
            '$stationName status: the station at ${record.controlUrl} rejected '
            "this client's bearer token (401) — the lock may be stale or "
            'foreign. Investigate directly; refusing to guess.',
            1,
          ),
        },
    };
  }

  int _renderRefusal(String message, int code) {
    stderr.writeln(message);
    return code;
  }

  int _renderDeadPid({
    required int pid,
    required String home,
    required bool json,
  }) {
    if (json) {
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'classification': 'pid_dead',
          'process': <String, Object?>{'pid': pid, 'alive': false},
        }),
      );
      return 1;
    }
    return _renderRefusal(
      '$stationName status: station.lock at $home/.grid/station.lock names '
      'pid $pid, but the pid probe found no live process. (station: down)',
      1,
    );
  }

  int _renderUnreachable(Unreachable result, {required bool json}) {
    final statusUrl = switch (result.record.controlUrl) {
      final String controlUrl => '$controlUrl/status',
      null => null,
    };
    if (json) {
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'classification': 'control_door_unavailable',
          'process': <String, Object?>{'pid': result.pid, 'alive': true},
          'controlDoor': <String, Object?>{
            'url': statusUrl,
            'failure': switch (result.failure) {
              DoorFailure.releasing => 'station_releasing',
              DoorFailure.notAdvertised => 'not_advertised',
              DoorFailure.connectionFailed => 'connection_failed',
              DoorFailure.timedOut => 'timed_out',
              DoorFailure.invalidResponse => 'invalid_response',
            },
            'hardBoundMilliseconds': result.hardBound.inMilliseconds,
          },
        }),
      );
      return 1;
    }

    final seconds = (result.hardBound.inMilliseconds / 1000).toStringAsFixed(1);
    final door = statusUrl == null
        ? 'the control door'
        : 'the control door at $statusUrl';
    final detail = switch (result.failure) {
      DoorFailure.releasing =>
        'process pid ${result.pid} is alive and releasing; $door was not '
            'probed. (station: alive; control door: not probed — releasing)',
      DoorFailure.notAdvertised =>
        'process pid ${result.pid} is alive, but station.lock advertises no '
            'usable control door${statusUrl == null ? '' : ' at $statusUrl'}. '
            '(station: alive; control door: not advertised)',
      DoorFailure.connectionFailed =>
        'process pid ${result.pid} is alive, but $door failed to connect '
            'before the $seconds s hard bound. '
            '(station: alive; control door: connection failed)',
      DoorFailure.timedOut =>
        'process pid ${result.pid} is alive, but $door did not answer within '
            'the $seconds s hard bound. '
            '(station: alive; control door: timed out)',
      DoorFailure.invalidResponse =>
        'process pid ${result.pid} is alive, but $door did not return a valid '
            'status response within the $seconds s hard bound. '
            '(station: alive; control door: invalid response)',
    };
    return _renderRefusal(
      '$stationName status: $detail — check the door, not the process',
      1,
    );
  }

  int _renderUp(
    Map<String, Object?> payload, {
    Duration? slowElapsed,
    required bool json,
  }) {
    if (json) {
      stdout.writeln(jsonEncode(payload));
      return 0;
    }
    final station = payload['station'] as Map<String, Object?>? ?? const {};
    final process = payload['process'] as Map<String, Object?>? ?? const {};
    final work = payload['work'] as Map<String, Object?>? ?? const {};
    final firstLine = slowElapsed == null
        ? 'station: UP'
        : 'station: UP — alive but slow '
              '(${(slowElapsed.inMilliseconds / 1000).toStringAsFixed(1)} s)';
    stdout
      ..writeln(firstLine)
      ..writeln('  substation: ${station['substation']}')
      ..writeln('  state store: ${station['stateStore']}')
      ..writeln('  work root: ${station['workRoot']}')
      ..writeln(
        '  mode: '
        '${(station['dryRun'] as bool? ?? true) ? 'DRY-RUN' : 'LIVE'}',
      )
      ..writeln(
        '  pid: ${process['pid']}  ·  uptime: '
        '${process['uptimeSeconds']}s  ·  version: ${process['version']}',
      )
      ..writeln(
        '  ready: ${work['ready']}  ·  mounted: ${work['mounted']}  ·  '
        'live sessions: ${work['liveSessions']}  ·  last sync: '
        '${work['lastSyncAt']}',
      );
    final admission = payload['admission'];
    if (admission is Map<String, Object?>) {
      final maxAgents = admission['maxAgents'];
      final reservations = admission['reservations'];
      if (maxAgents is int && reservations is List<Object?>) {
        stdout.writeln('  budget: ${reservations.length}/$maxAgents');
      }
    }
    return 0;
  }

  Future<int> _renderDownFallback(
    ArgResults args,
    BeadsWorkspace stateWorkspace,
  ) async {
    stdout
      ..writeln('station: DOWN  (station: down)')
      ..writeln('  state store: ${stateWorkspace.root}');
    final workspace = BeadsWorkspace.discover(start: args.option('workspace'));
    if (workspace == null) {
      stdout.writeln(
        '  (pass --workspace to see the owned ready count — none '
        'discoverable from '
        '${args.option('workspace') ?? Directory.current.path})',
      );
      return 0;
    }
    final owners = <String>{
      ...args.multiOption('substation'),
      ...args.multiOption('owner'),
    }..removeWhere((value) => value.trim().isEmpty);
    if (owners.isEmpty) {
      stdout.writeln(
        '  work root: ${workspace.root}  '
        '(pass --substation to see the owned ready count)',
      );
      return 0;
    }
    final snapshot = await _snapshotReader(workspace).read();
    final ownership = BeadOwnershipPredicate(owners);
    final ready = snapshot.readyIds.where((id) {
      final bead = snapshot.beadsById[id];
      return bead != null && ownership.owns(bead) && bead.issueType.isCore;
    }).length;
    stdout
      ..writeln(
        '  substation: ${owners.join(',')}  ·  work root: ${workspace.root}',
      )
      ..writeln('  ready (owned): $ready');
    return 0;
  }
}
