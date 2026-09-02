@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:beads_dart/src/errors/bd_exception.dart';
import 'package:beads_dart/src/services/bd_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/hermetic_workspace.dart';

/// The MIGRATION-FREEZE write gate (bd 1.3, exit 14) over a hermetic `bd init`
/// workspace — never the live store. SELF-SKIPS on a bd that predates the gate:
/// such a binary ignores `BD_MIGRATION_FREEZE_FILE` and the create SUCCEEDS
/// (verified on HEAD-a45199a), which is the crisp, non-vacuous discriminator.
void main() {
  test(
    'a frozen workspace refuses a write as a typed BdMigrationFrozen',
    () async {
      final ws = await HermeticWorkspace.create(prefix: 'grid_freeze_');
      addTearDown(ws.dispose);

      final marker = File(p.join(ws.rootPath, 'MIGRATION-FREEZE'))
        ..writeAsStringSync('operator=grid-test\n');

      final runner = ProcessBdRunner(
        workspaceRoot: ws.rootPath,
        environment: {
          ...Platform.environment,
          'BD_MIGRATION_FREEZE_FILE': marker.path,
        },
      );
      final result = await runner.run(const [
        'create',
        '--json',
        '--title',
        'frozen write',
        '--type',
        'task',
        '--priority',
        '2',
      ]);

      if (result.exitCode == 0) {
        markTestSkipped(
          'bd on PATH predates the 1.3 migration-freeze gate; the refusal is '
          'asserted offline in test/errors/bd_exception_contract_test.dart',
        );
        return;
      }

      expect(result.exitCode, 14, reason: result.stderr);
      final error = BdException.fromOutput(
        command: const ['bd', 'create'],
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
      );
      expect(error, isA<BdMigrationFrozen>());
      expect((error as BdMigrationFrozen).markerPath, marker.path);
    },
  );
}
