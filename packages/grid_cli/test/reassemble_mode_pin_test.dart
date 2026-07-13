// The mode pin: grid_sdk's ReassembleMode and grid_exploration's wire tokens are
// two enumerations of ONE protocol. This test is why keeping them in their
// owning packages is safe — a drift is a loud failure, not a silent wire break.
// grid_cli is the only package that sees both.
import 'package:grid_exploration/grid_exploration.dart' show ReassembleTool;
import 'package:grid_sdk/grid_sdk.dart' show ReassembleMode;
import 'package:test/test.dart';

void main() {
  test('the wire modes and the SDK modes are the same two, in order', () {
    expect(ReassembleTool.modes, [
      for (final mode in ReassembleMode.values) mode.wire,
    ]);
    expect(ReassembleTool.modes, ['reload', 'restart']);
  });
}
