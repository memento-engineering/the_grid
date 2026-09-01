// C8a (cut-wiring) — the STATE bd writer's flares must reach the transport.
//
// The bug this pins: `assembleStationWork` built the state-store
// `StationBeadWriter` with `onRefusal` only, while the per-substation work
// writers below it wired `onFlare` as well. Every derived flare the state
// partition raises — `session.minted`, `gate.autoClosed`,
// `session.workTerminal` — was therefore null-sunk on the ONE store that mints
// every session bead, which is exactly the evidence stream the dual-read soak
// gates read. Silence there does not read as "nothing happened"; it reads as
// "the gate passed".
import 'dart:io';

import 'package:grid_engine/testing.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

/// A minimal resolver — nothing resolves in these offline assemblies.
class _NullResolver implements SessionResolver {
  const _NullResolver();
  @override
  Seed sessionFor({required bead, session}) =>
      throw UnimplementedError('never reached');
}

void _seedStore(String dir, {String? database}) {
  Directory('$dir/.beads').createSync(recursive: true);
  File('$dir/.beads/metadata.json').writeAsStringSync(
    database == null
        ? '{"dolt_mode":"embedded"}'
        : '{"dolt_mode":"embedded","dolt_database":"$database"}',
  );
}

void main() {
  late Directory tmp;
  late RecordingExplorationTransport transport;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('c8a-state-flare-');
    _seedStore('${tmp.path}/proj', database: 'proj');
    _seedStore('${tmp.path}/home/.grid', database: 'tgstate');
    transport = RecordingExplorationTransport();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<StationWorkRuntime> assemble() => assembleStationWork(
    stateStore: GridStateStore.forGridRoot('${tmp.path}/home'),
    substations: [SubstationWorkSpec(name: 'proj', root: '${tmp.path}/proj')],
    resolver: const _NullResolver(),
    dryRun: true,
    transport: transport,
  );

  test('a state-partition flare reaches the assembled transport', () async {
    final work = await assemble();
    // `createSession` is the site whose flare the gates count; the dry-run
    // chokepoint mints end-to-end without touching a store.
    await work.wiring.services.writer.createSession(
      substation: work.stateSubstation,
      title: 'c8a',
      workBeadId: 'proj-1',
    );
    expect(
      transport.flares.map((flare) => flare.name),
      contains('session.minted'),
      reason:
          'the state writer was built with onRefusal only — its flares were '
          'null-sunk on the store that mints every session bead',
    );
    final minted = transport.flares.firstWhere(
      (flare) => flare.name == 'session.minted',
    );
    expect(minted.data['workBeadId'], 'proj-1');
  });

  test('the work-store writers keep theirs — the fix adds a sink, it does '
      'not move one', () {
    // Textual, because the per-substation writers are constructed inside a
    // loop over stores this offline assembly does not drive; the failure mode
    // being pinned is one construction site drifting from the other.
    final source = File('lib/src/work/work_assembly.dart').readAsStringSync();
    expect(
      RegExp('onFlare: transport\\?\\.flare,').allMatches(source).length,
      greaterThanOrEqualTo(2),
      reason: 'the state writer AND the per-substation work writers',
    );
  });
}
