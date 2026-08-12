@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

import 'support/hermetic_workspace.dart';

void main() {
  test(
    'installed bd completes a guarded update or receipts degradation',
    () async {
      try {
        await Process.run('bd', const ['version']);
      } on ProcessException {
        markTestSkipped('bd executable is not installed');
        return;
      }

      final workspace = await HermeticWorkspace.create(
        prefix: 'guarded_write_compatibility_',
      );
      addTearDown(workspace.dispose);
      BdCliService.resetGuardedWriteCapabilityForTesting();
      final runner = ProcessBdRunner(workspaceRoot: workspace.rootPath);
      final bd = BdCliService(runner);
      final id = await bd.create(title: 'before');
      final receipts = <String>[];

      await bd.update(
        id,
        ifAssignee: '',
        ifStatus: BeadStatus.open,
        title: 'after',
        onGuardDegraded: (name, data) => receipts.add(name),
      );

      expect((await bd.show([id])).single.title, 'after');
      final help = await runner.run(const ['update', '--help']);
      final text = '${help.stdout}\n${help.stderr}';
      final supported =
          text.contains('--if-assignee') && text.contains('--if-status');
      expect(receipts, supported ? isEmpty : ['bd.guardedWriteDegraded']);
    },
  );
}
