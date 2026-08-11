@TestOn('vm')
@Tags(['integration'])
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

import 'support/hermetic_workspace.dart';

void main() {
  test(
    'design file transport preserves large and authored text exactly',
    () async {
      final workspace = await HermeticWorkspace.create(
        prefix: 'beads_dart_text_',
      );
      addTearDown(workspace.dispose);
      final service = BdCliService(
        ProcessBdRunner(
          workspaceRoot: workspace.rootPath,
          defaultTimeout: const Duration(seconds: 60),
        ),
      );
      final id = await service.create(title: 'text transport receipt');

      final nulDesign =
          '${List.filled(8191, 'a').join()}'
          '\u0000'
          '${List.filled(8192, 'b').join()}';
      expect(nulDesign.length, 16384);
      await service.update(id, design: nulDesign);
      expect((await service.show([id])).single.design, nulDesign);

      final largeDesign = 'head${List.filled(500000, 'x').join()}';
      expect(largeDesign.length, 500004);
      await service.update(id, design: largeDesign);
      expect((await service.show([id])).single.design, largeDesign);

      const authored = 'head\r\n\ufeff\u200b\u00a0\t\ntrailing  ';
      await service.update(id, design: authored);
      expect((await service.show([id])).single.design, authored);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
