import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('SDK and CLI barrels vend the live roster commands', () {
    final sdk = File('lib/grid_sdk.dart').readAsStringSync();
    for (final path in const [
      'src/roster/roster_composition.dart',
      'src/roster/roster_outcome.dart',
      'src/roster/roster_seat.dart',
      'src/roster/substation_roster.dart',
    ]) {
      expect(sdk, contains("export '$path';"));
    }
    final cli = File('../grid_cli/lib/grid_cli.dart').readAsStringSync();
    expect(cli, contains("export 'src/substation_command.dart';"));
  });

  test('grid_cli no longer claims the control plane is GET-only', () {
    final sources = Directory('../grid_cli/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    expect(
      sources.any(
        (file) => file.readAsStringSync().contains('GET-only by construction'),
      ),
      isFalse,
    );
  });
}
