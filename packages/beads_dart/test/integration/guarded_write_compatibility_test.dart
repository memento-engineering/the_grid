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
      final receipts = <({String name, Map<String, String> data})>[];

      await bd.update(
        id,
        ifAssignee: '',
        ifStatus: BeadStatus.open,
        title: 'after',
        onGuardDegraded: (name, data) => receipts.add((name: name, data: data)),
      );

      expect((await bd.show([id])).single.title, 'after');
      final help = await runner.run(const ['update', '--help']);
      final text = '${help.stdout}\n${help.stderr}';
      final lines = text.split('\n');
      final flagRows = lines
          .map((line) => line.trimLeft())
          .where(RegExp(r'^(?:-\w,\s*)?--[a-z0-9][a-z0-9-]*(?:\s|$)').hasMatch)
          .toList();
      expect(lines.any((line) => line.trim() == 'Flags:'), isTrue);
      expect(flagRows, isNotEmpty);
      final supported =
          flagRows.any(
            RegExp(r'^(?:-\w,\s*)?--if-assignee(?:\s|$)').hasMatch,
          ) &&
          flagRows.any(RegExp(r'^(?:-\w,\s*)?--if-status(?:\s|$)').hasMatch);
      if (supported) {
        expect(receipts, isEmpty);
      } else {
        expect(receipts, hasLength(1));
        expect(receipts.single.name, 'bd.guardedWriteDegraded');
        expect(receipts.single.data, {
          'missingCapability': '--if-assignee,--if-status',
          'safetyDropped': 'compare-and-swap defence in depth',
          'primarySafety':
              'StationBeadWriter single-writer chokepoint preserved',
        });
      }
    },
  );
}
