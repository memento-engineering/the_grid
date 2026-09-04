/// Structural pins for the two operator READ verbs.
///
/// The verbs must reach exactly TWO outward seams — the resident door
/// (`StationCommandClient`) and the trajectory reader `traj show` owns — and
/// never grow a third store-read path of their own.
library;

import 'dart:io';

import 'package:grid_cli/grid_cli.dart';
import 'package:test/test.dart';

void main() {
  test('bead_command.dart opens no store path of its own', () {
    final source = File('lib/src/bead_command.dart').readAsStringSync();
    for (final banned in const <String>[
      'station_stores.dart',
      'BeadsWorkspace',
      'openWorkStore',
      'openStateStore',
      'StoreLocator',
      'BdCliService',
      'ProcessBdRunner',
      'DoltQueryService',
      'CliSnapshotReader',
    ]) {
      expect(
        source,
        isNot(contains(banned)),
        reason:
            '$banned would be a THIRD store-read path; the verbs read through '
            'the resident door and the trajectory reader only.',
      );
    }
    expect(source, contains("import 'station_command_client.dart';"));
    expect(
      source,
      contains("import 'package:grid_trajectory/grid_trajectory.dart'"),
    );
  });

  test('a no-argument BeadCommand vends all three verbs', () {
    expect(
      BeadCommand().subcommands.keys,
      containsAll(const <String>['set', 'board', 'round']),
    );
  });

  test('the dev bin composes BeadCommand', () {
    expect(File('bin/grid.dart').readAsStringSync(), contains('BeadCommand()'));
  });
}
