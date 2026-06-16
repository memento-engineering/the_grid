import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('grid_runtime scaffold', () {
    test('barrel exports the scaffold marker', () {
      expect(gridRuntimeScaffold, 'grid_runtime');
    });
  });
}
