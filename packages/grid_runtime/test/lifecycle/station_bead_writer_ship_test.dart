// tg-xh5d (`the_grid#capability-edges-are-bd-native-and-link-is-sugar`): the
// chokepoint SHIPS every capability a closing bead exports — one `bd ship`
// per `export:<capability>` label, and nothing when it carries none.
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/recording_bd_runner.dart';

Bead _work(
  String id, {
  List<String> labels = const [],
  BeadStatus status = BeadStatus.open,
}) => Bead(
  id: id,
  title: id,
  issueType: IssueType.task,
  status: status,
  labels: labels,
  metadata: const {StationBeadWriter.rigKey: 'tgdog'},
);

void main() {
  late RecordingBdRunner runner;
  late BdCliService bd;
  late List<({String name, Map<String, String> data})> flares;

  StationBeadWriter writer() => StationBeadWriter(
    bd: bd,
    reader: runner,
    ownership: BeadOwnershipPredicate({'tgdog'}),
    onFlare: (name, data) => flares.add((name: name, data: data)),
  );

  setUp(() {
    BdCliService.resetGuardedWriteCapabilityForTesting();
    runner = RecordingBdRunner();
    bd = BdCliService(runner);
    flares = [];
  });

  test(
    'close ships exactly one capability per export: label, after the close',
    () async {
      runner.exportBeads = [
        _work(
          'tgdog-1',
          labels: const ['export:tgdog-1', 'export:release-gate'],
        ),
      ];

      await writer().close('tgdog-1', reason: 'done');

      expect(runner.callsFor('ship'), [
        ['ship', 'tgdog-1', '--json', '--actor', 'grid-controller'],
        ['ship', 'release-gate', '--json', '--actor', 'grid-controller'],
      ]);
      final verbs = [for (final call in runner.calls) call.first];
      expect(
        verbs.indexOf('close') < verbs.indexOf('ship'),
        isTrue,
        reason: 'bd ship validates that the exporting bead is CLOSED',
      );
      expect(flares.single.data['capabilities'], 'tgdog-1,release-gate');
    },
  );

  test('a bead carrying no export: label spawns no ship at all', () async {
    runner.exportBeads = [_work('tgdog-1')];

    await writer().close('tgdog-1');

    expect(runner.callsFor('ship'), isEmpty);
    expect(flares, isEmpty);
  });

  test('shipExports is driven by the bead STATE, so a hand-closed bead ships '
      'through the same path', () async {
    runner.exportBeads = [
      _work(
        'tgdog-1',
        labels: const ['export:tgdog-1'],
        status: BeadStatus.closed,
      ),
    ];

    final shipped = await writer().shipExports('tgdog-1');

    expect(shipped, ['tgdog-1']);
    expect(runner.callsFor('close'), isEmpty);
    expect(runner.callsFor('ship'), hasLength(1));
  });

  test('a capability the bead ALREADY provides is not re-shipped — the '
      'observer can run every flush', () async {
    runner.exportBeads = [
      _work(
        'tgdog-1',
        labels: const [
          'export:tgdog-1',
          'provides:tgdog-1',
          'export:release-gate',
        ],
        status: BeadStatus.closed,
      ),
    ];

    expect(await writer().shipExports('tgdog-1'), ['release-gate']);
    expect(runner.callsFor('ship'), [
      ['ship', 'release-gate', '--json', '--actor', 'grid-controller'],
    ]);
  });

  test('a fully shipped bead spawns no process at all', () async {
    runner.exportBeads = [
      _work(
        'tgdog-1',
        labels: const ['export:tgdog-1', 'provides:tgdog-1'],
        status: BeadStatus.closed,
      ),
    ];

    expect(await writer().shipExports('tgdog-1'), isEmpty);
    expect(runner.callsFor('ship'), isEmpty);
    expect(flares, isEmpty);
  });

  test(
    'shipExports is fail-closed on ownership and silent on an absent bead',
    () async {
      expect(
        () => writer().shipExports('other-1'),
        throwsA(isA<OwnershipRefused>()),
      );
      expect(await writer().shipExports('tgdog-missing'), isEmpty);
      expect(runner.callsFor('ship'), isEmpty);
    },
  );
}
