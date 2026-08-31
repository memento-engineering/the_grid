// W1 (tg-zfek Stage 1) — boot-claim-append-drain-down against a hermetic
// dolt, through the harness's DEFAULT wiring: the real listener resolution
// (`.grid/.beads/dolt/config.yaml`), the real secret
// (`.grid/trajectory/trajectory.secret`), the real `trajectory` SQL user, the
// real fenced appender and tick. Nothing is faked but the grid home itself.
//
// FAIL-CLOSED without dolt on PATH (the stage0-guards-gate-prs convention): a
// skipped guard proves nothing at a stage cut.
@Tags(['integration'])
@Timeout(Duration(minutes: 3))
library;

import 'package:grid_sdk/grid_sdk.dart';
import 'package:grid_trajectory/grid_trajectory.dart'
    show AttemptNote, TrajectoryConnection;
import 'package:test/test.dart';

import 'support/hermetic_grid_home.dart';

void main() {
  late HermeticGridHome home;

  setUpAll(() async {
    home = await HermeticGridHome.create();
    await home.provision();
  });

  tearDownAll(() => home.dispose());

  Future<String> scalar(String sql) async {
    final admin = await TrajectoryConnection.connect(
      home.adminEndpointFor('trajectory'),
    );
    try {
      final result = await admin.execute(sql);
      return result.rows.single.values.single ?? '';
    } finally {
      await admin.close();
    }
  }

  TrajectoryAppendRequest note(int ordinal) => TrajectoryAppendRequest(
    AttemptNote(
      sessionId: 'tranquility-w1',
      body: 'shadow note $ordinal',
      channel: 'test',
      noteOrdinal: ordinal,
    ),
  );

  test('boot → claim → append → drain → down, then a successor epoch', () async {
    final flares = <String>[];
    final harness = await TrajectoryHarness.build(
      // `auto` on a provisioned home arms — the artifact IS the switch (§1.3).
      config: const TrajectoryConfig(),
      gridHome: home.homePath,
      station: 'it-station',
      onFlare: (name, data) => flares.add(name),
    );
    expect(harness.mode, TrajectoryHarnessMode.down);

    // Boot: connect as `trajectory` → belt verify (empty log, clean) → claim
    // epoch 1 (fence cell seeded by the claim's UPSERT) → tick boot pass.
    await harness.start();
    expect(harness.mode, TrajectoryHarnessMode.live);
    expect(harness.status.epoch, 1);
    expect(await scalar('SELECT MAX(epoch) FROM traj_epoch'), '1');
    expect(
      await scalar(
        'SELECT fence_state >> 32 FROM traj_fence '
        "WHERE station = 'it-station'",
      ),
      '1',
    );

    // Append through the queue — plus the designed at-least-once dedupe.
    harness.enqueue(note(1));
    harness.enqueue(note(2));
    harness.enqueue(note(2)); // same idem key → AppendDeduped
    final fixpoint = await harness.runToFixpoint();
    expect(fixpoint, isNotNull);
    expect(fixpoint!.reached, isTrue);
    expect(harness.status.appended, 2);
    expect(harness.status.deduped, 1);
    expect(harness.status.dropped, 0);
    expect(
      await scalar(
        'SELECT COUNT(*) FROM trajectory '
        "WHERE station = 'it-station'",
      ),
      '2',
    );
    expect(
      await scalar(
        'SELECT MAX(epoch_seq) FROM trajectory '
        "WHERE station = 'it-station' AND boot_epoch = 1",
      ),
      '2',
      reason: 'the serialized per-epoch stream',
    );

    // Down: drain (already empty) → fixpoint → boundary commit → dispose.
    await harness.shutdown();
    expect(flares, contains('trajectory.shutdown'));
    expect(
      flares.where(
        (name) =>
            name == 'trajectory.appendDropped' ||
            name == 'trajectory.queueOverflow' ||
            name == 'trajectory.halted' ||
            name == 'trajectory.fencedOut',
      ),
      isEmpty,
      reason: 'a clean window: no drop, no latch',
    );

    // A successor boot claims epoch 2 over the same clean log.
    final successor = await TrajectoryHarness.build(
      config: const TrajectoryConfig(),
      gridHome: home.homePath,
      station: 'it-station',
    );
    await successor.start();
    expect(successor.mode, TrajectoryHarnessMode.live);
    expect(successor.status.epoch, 2);
    await successor.shutdown();
  });
}
