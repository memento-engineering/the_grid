import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

import 'support/dispatch_fakes.dart';

/// The dispatch read seam (M3 Track 5) — the [FakeReadyWorkSource] resolves
/// entered ids to full [Bead]s, mirroring grid_reconciler's `ConvergenceSource`
/// pattern. The seam carries only ids on a `readySetChanged`, so the lookup is
/// the load-bearing part: an entered id must resolve to its bead (the ownership
/// axis reads the id prefix + metadata.rig).
void main() {
  test('bead(id) resolves a staged ready bead; readyBeads lists them', () {
    final source = FakeReadyWorkSource()
      ..addReady(Bead(id: 'tgdog-1', title: 'one'))
      ..addReady(Bead(id: 'tgdog-2', title: 'two'));

    expect(source.bead('tgdog-1')?.title, 'one');
    expect(source.bead('missing'), isNull);
    expect(
      source.readyBeads.map((b) => b.id).toSet(),
      equals({'tgdog-1', 'tgdog-2'}),
    );
  });

  test('events stream carries the fired readySetChanged', () async {
    final source = FakeReadyWorkSource();
    final received = <GraphEvent>[];
    final sub = source.events.listen(received.add);

    source.fireReady({'tgdog-1'}, exited: {'tgdog-0'});
    await pumpEventQueue();

    expect(received, hasLength(1));
    final event = received.single as ReadySetChanged;
    expect(event.entered, equals({'tgdog-1'}));
    expect(event.exited, equals({'tgdog-0'}));

    await sub.cancel();
    await source.close();
  });
}
