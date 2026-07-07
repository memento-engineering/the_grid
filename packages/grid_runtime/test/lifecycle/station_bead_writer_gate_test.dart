import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
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

  test('mint-dedup (tg-i08): an existing OPEN gate for the SAME (session, node) '
      'is REFRESHED, not re-minted', () async {
    // Stage an already-open gate blocking the same session+node.
    runner.exportBeads = [
      Bead(
        id: 'tgdog-gopen',
        title: 'grid gate tgdog-s@tg-1/review/route',
        issueType: IssueType.gate,
        status: BeadStatus.open,
        metadata: const {
          'rig': 'tgdog',
          'blocks': 'tgdog-s',
          'node': 'tg-1/review/route',
          'reason': 'first gate',
          'regate_count': '1',
        },
      ),
    ];

    final id = await writer().createGate(
      substation: 'tgdog',
      sessionId: 'tgdog-s',
      nodePath: 'tg-1/review/route',
      reason: 'second gate (re-gate)',
    );

    // Returns the EXISTING id — one stable gate the operator keeps watching.
    expect(id, 'tgdog-gopen');
    // NO fresh gate bead was minted.
    expect(runner.callsFor('create'), isEmpty);
    // Exactly one update — the REFRESH on the existing bead.
    final updates = runner.callsFor('update');
    expect(updates, hasLength(1));
    expect(updates.single, containsAllInOrder(['update', 'tgdog-gopen']));
    final refresh =
        jsonDecode(runner.metadataOfUpdate(0)!) as Map<String, dynamic>;
    expect(refresh['reason'], 'second gate (re-gate)');
    // The re-gate marker: count bumped (1 → 2) + a fresh `regated_at` stamp.
    expect(refresh['regate_count'], '2');
    expect(refresh['regated_at'], isA<String>());
    // Never `bd show` on a controller path.
    expect(runner.neverCalledShow, isTrue);
    expect(runner.everyMutationHasActor, isTrue);
  });

  test('mint-dedup does NOT reuse a CLOSED gate (open-only) — mints fresh',
      () async {
    runner.exportBeads = [
      Bead(
        id: 'tgdog-gclosed',
        title: 'grid gate tgdog-s@tg-1/review/route',
        issueType: IssueType.gate,
        status: BeadStatus.closed,
        metadata: const {
          'rig': 'tgdog',
          'blocks': 'tgdog-s',
          'node': 'tg-1/review/route',
        },
      ),
    ];

    final id = await writer().createGate(
      substation: 'tgdog',
      sessionId: 'tgdog-s',
      nodePath: 'tg-1/review/route',
      reason: 'fresh gate after a prior resolve',
    );

    // A closed gate is inert — a fresh mint happens (createdId).
    expect(id, 'tgdog-gate1');
    expect(runner.callsFor('create'), hasLength(1));
  });

  test('mint-dedup keys on (session, node): an open gate for a DIFFERENT node '
      'does not dedup', () async {
    runner.exportBeads = [
      Bead(
        id: 'tgdog-gother',
        title: 'grid gate tgdog-s@tg-1/review/other',
        issueType: IssueType.gate,
        status: BeadStatus.open,
        metadata: const {
          'rig': 'tgdog',
          'blocks': 'tgdog-s',
          'node': 'tg-1/review/other',
        },
      ),
    ];

    final id = await writer().createGate(
      substation: 'tgdog',
      sessionId: 'tgdog-s',
      nodePath: 'tg-1/review/route',
      reason: 'a gate for a different node',
    );

    expect(id, 'tgdog-gate1');
    expect(runner.callsFor('create'), hasLength(1));
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
