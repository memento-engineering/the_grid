// Shared exploration-extension-name conformance guard.
//
// Leonard's pure contract owns the prefix. `grid_exploration` remains a
// dev-only dependency so these derived method names can be compared with the
// host builders without adding the host to the runtime graph.
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_devtools/grid_devtools.dart';
import 'package:grid_exploration/grid_exploration.dart' as grid_exploration;

void main() {
  group('grid_devtools exploration-extension pins match grid_exploration', () {
    test('shared prefix matches the host prefix', () {
      expect(kLeonardExtensionPrefix, grid_exploration.kLeonardExtensionPrefix);
    });

    test('kHandshakeExtension == coreExtension("handshake")', () {
      expect(kHandshakeExtension, grid_exploration.coreExtension('handshake'));
    });

    test('kEventsExtension == gridExtension("events")', () {
      expect(kEventsExtension, grid_exploration.gridExtension('events'));
    });
  });
}
