// Exploration-extension-name pin guard.
//
// `GridExplorationClient` (lib/src/protocol/grid_exploration_client.dart)
// deliberately does NOT import `grid_exploration` at runtime (ADR-0002
// Decision 3: grid_devtools rides the exploration protocol only, never links
// beads_dart or its host transitively) — so `kHandshakeExtension` and
// `kEventsExtension` are hand-retyped string literals with no compile-time
// link back to the host's `coreExtension`/`gridExtension` builders in
// `packages/grid_exploration/lib/src/grid_exploration_protocol.dart`. This
// test is the enforcement: it pulls `grid_exploration` in as a DEV-ONLY
// dependency (pubspec.yaml `dev_dependencies` — the ship graph is
// unchanged) purely so the pinned literals can be asserted equal to the
// live protocol constants.
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_devtools/grid_devtools.dart';
import 'package:grid_exploration/grid_exploration.dart';

void main() {
  group('grid_devtools exploration-extension pins match grid_exploration', () {
    test('kHandshakeExtension == coreExtension("handshake")', () {
      expect(kHandshakeExtension, coreExtension('handshake'));
    });

    test('kEventsExtension == gridExtension("events")', () {
      expect(kEventsExtension, gridExtension('events'));
    });
  });
}
