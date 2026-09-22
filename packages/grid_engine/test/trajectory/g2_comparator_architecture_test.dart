import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'G2 extends the incumbent comparator without a second gate artifact',
    () {
      final root = Directory.current.path.endsWith('grid_engine')
          ? Directory.current.parent.parent.path
          : Directory.current.path;
      final stepPass = File(
        '$root/packages/grid_engine/lib/src/bridge/step_dual_read_pass.dart',
      ).readAsStringSync();
      final leafShadow = File(
        '$root/packages/grid_trajectory/lib/src/shadow/composite_shadow.dart',
      ).readAsStringSync();
      final cliAdapter = File(
        '$root/packages/grid_cli/lib/src/traj_legacy_session_reader.dart',
      ).readAsStringSync();
      final adapter = File(
        '$root/packages/grid_sdk/lib/src/trajectory/g2_shadow_round.dart',
      ).readAsStringSync();
      final engineFiles = Directory('$root/packages/grid_engine/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      expect(stepPass, contains('observeG2Round'));
      expect(leafShadow, contains('G2ShadowRoundCompare'));
      expect(leafShadow, isNot(contains('implements G2ShadowRoundCompare')));
      expect(cliAdapter, contains('G2ShadowRoundAdapter'));
      expect(cliAdapter, contains('BdLegacyG2Reader'));
      expect(adapter, isNot(contains('class G2Certificate')));
      expect(adapter, isNot(contains('cleanRoundStreak')));
      for (final file in engineFiles) {
        expect(
          file.readAsStringSync(),
          isNot(contains('package:grid_trajectory/')),
          reason: file.path,
        );
      }
    },
  );
}
