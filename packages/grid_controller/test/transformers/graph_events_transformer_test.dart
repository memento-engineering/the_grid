import 'package:grid_controller/grid_controller.dart';
import 'package:test/test.dart';

import '../support/reactivity_fakes.dart';

void main() {
  group('GraphEventsTransformer', () {
    test('first ingest yields a single SnapshotInitialized baseline', () {
      final t = GraphEventsTransformer();
      final events = t.ingest(snap([bead('a'), bead('b')], ready: {'a'}));
      expect(events, [isA<SnapshotInitialized>()]);
      expect(t.previous, isNotNull);
    });

    test('subsequent ingests diff against the prior snapshot', () {
      final t = GraphEventsTransformer();
      t.ingest(snap([bead('a')]));
      final events = t.ingest(snap([bead('a'), bead('b')]));
      expect(events, [isA<BeadCreated>()]);
      expect((events.single as BeadCreated).bead.id, 'b');
    });

    test('an unchanged ingest yields no events', () {
      final t = GraphEventsTransformer();
      t.ingest(snap([bead('a')]));
      expect(t.ingest(snap([bead('a')])), isEmpty);
    });

    test('reset re-emits a baseline on the next ingest', () {
      final t = GraphEventsTransformer();
      t.ingest(snap([bead('a')]));
      t.reset();
      expect(t.ingest(snap([bead('a')])), [isA<SnapshotInitialized>()]);
    });
  });
}
