import 'dart:convert';

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/recording_bd_runner.dart';

/// Tests for `StationBeadWriter.createGate` (D-7): the_grid mints a `type=gate`
/// bead in its OWN store to functionally block parked work — NEVER a mutation of
/// the foreign work bead (A37). Fail-closed on ownership exactly like
/// `createSession`. Offline: a recording BdRunner, no live `bd`.
void main() {
  late RecordingBdRunner runner;
  late BdCliService bd;
  late List<String> refusals;

  BeadOwnershipPredicate predicate() => BeadOwnershipPredicate({'tgdog'});

  StationBeadWriter writer() =>
      StationBeadWriter(bd: bd, ownership: predicate(), onRefusal: refusals.add);

  setUp(() {
    runner = RecordingBdRunner(createdId: 'tgdog-gate1');
    bd = BdCliService(runner);
    refusals = <String>[];
  });

  test('mints a type=gate bead + stamps {rig, blocks, node, reason} from birth',
      () async {
    final id = await writer().createGate(
      substation: 'tgdog',
      sessionId: 'tgdog-s',
      nodePath: 'tg-1/review/route',
      reason: 'code-validation failed: hard block',
    );
    expect(id, 'tgdog-gate1');

    // 1) a `bd create … --type gate --actor grid-controller`.
    final creates = runner.callsFor('create');
    expect(creates, hasLength(1));
    expect(creates.single, containsAllInOrder(['--type', 'gate']));
    expect(creates.single, containsAllInOrder(['--actor', 'grid-controller']));

    // 2) immediately followed by the stamping `update --metadata`.
    final stamp = jsonDecode(runner.metadataOfUpdate(0)!) as Map<String, dynamic>;
    expect(stamp['rig'], 'tgdog');
    expect(stamp['blocks'], 'tgdog-s');
    expect(stamp['node'], 'tg-1/review/route');
    expect(stamp['reason'], 'code-validation failed: hard block');

    // Safety invariants — bd-only, actor-stamped, never `bd show`.
    expect(runner.everyMutationHasActor, isTrue);
    expect(runner.neverCalledShow, isTrue);
  });

  test('fail-closed: a gate in a NON-owned substation is refused before any bd '
      'create', () async {
    await expectLater(
      writer().createGate(
        substation: 'gascity',
        sessionId: 'gascity-s',
        nodePath: 'gascity-1/route',
        reason: 'x',
      ),
      throwsA(
        isA<OwnershipRefused>()
            .having((e) => e.operation, 'operation', 'create'),
      ),
    );
    // NOT ONE bd call was issued (refused before the wire) — the foreign work
    // source is never touched (A37).
    expect(runner.calls, isEmpty);
    expect(refusals, hasLength(1));
  });
}
