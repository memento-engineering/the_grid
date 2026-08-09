/// The reusable resident `status` command.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart' show BeadOwnershipPredicate;

import 'resident_state_workspace.dart';
import 'station_attach.dart';

/// Constructs the one-shot snapshot reader used by the down fallback.
typedef SnapshotReaderFactory =
    SnapshotReader Function(BeadsWorkspace workspace);

/// The real two-spawn CLI snapshot reader.
SnapshotReader cliSnapshotReader(BeadsWorkspace workspace) => CliSnapshotReader(
  BdCliService(ProcessBdRunner(workspaceRoot: workspace.root)),
);

/// Renders live resident status or a read-only store fallback.
class ResidentStatusCommand extends Command<int> {
  /// Creates the command for [stationName].
  ResidentStatusCommand({
    required this.stationName,
    StationAttach? attach,
    SnapshotReaderFactory? snapshotReader,
  }) : _attach = attach ?? StationAttach(),
       _snapshotReader = snapshotReader ?? cliSnapshotReader {
    argParser
      ..addOption('state-workspace', help: residentStateWorkspaceHelp)
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
      ..addMultiOption('owner', help: 'Alias for --substation.');
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
          Up(:final payload) => _renderUp(payload),
          Down() => await _renderDownFallback(args, workspace),
          Stale(:final pid, :final record) => _renderRefusal(
            '$stationName status: station.lock at '
            '$home/.grid/station.lock names pid $pid but it is unreachable '
            '(dead, or alive-but-not-answering — record: $record). '
            '(station: down) — a fresh `$stationName up` steals a dead lock '
            'automatically; if $pid is alive, investigate it directly.',
            1,
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

  int _renderUp(Map<String, Object?> payload) {
    final station = payload['station'] as Map<String, Object?>? ?? const {};
    final process = payload['process'] as Map<String, Object?>? ?? const {};
    final work = payload['work'] as Map<String, Object?>? ?? const {};
    stdout
      ..writeln('station: UP')
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
