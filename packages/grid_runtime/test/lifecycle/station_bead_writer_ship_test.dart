import 'dart:io';

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
    'core close publishes own id plus explicit exports in one atomic update',
    () async {
      runner.exportBeads = [
        _work(
          'tgdog-1',
          labels: const ['export:tgdog-1', 'export:release-gate'],
        ),
      ];

      await writer().close('tgdog-1', reason: 'done');

      final update = runner.callsFor('update').single;
      expect(
        update,
        containsAllInOrder([
          '--status',
          'closed',
          '--set-metadata',
          startsWith('closed_at='),
          '--add-label',
          'provides:tgdog-1',
          '--add-label',
          'provides:release-gate',
        ]),
      );
      expect(runner.callsFor('close'), isEmpty);
      expect(runner.callsFor('ship'), isEmpty);
      expect(flares.single.name, 'external.shipped');
      expect(flares.single.data['capabilities'], 'tgdog-1,release-gate');
    },
  );

  test(
    'core close publishes its own id without an explicit export label',
    () async {
      runner.exportBeads = [_work('tgdog-1')];

      await writer().close('tgdog-1');

      expect(
        runner.callsFor('update').single,
        containsAllInOrder(['--add-label', 'provides:tgdog-1']),
      );
      expect(runner.callsFor('close'), isEmpty);
      expect(runner.callsFor('ship'), isEmpty);
      expect(flares.single.data['capabilities'], 'tgdog-1');
    },
  );

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
    expect(
      runner.callsFor('update').single,
      containsAllInOrder(['--add-label', 'provides:tgdog-1']),
    );
    expect(flares.single.name, 'external.shipped');
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
    expect(
      runner.callsFor('update').single,
      containsAllInOrder(['--add-label', 'provides:release-gate']),
    );
  });

  test(
    'explicit healer input is stable-deduplicated and needs no export label',
    () async {
      runner.exportBeads = [_work('tgdog-1', status: BeadStatus.closed)];

      expect(
        await writer().shipExports('tgdog-1', const [
          'tgdog-1',
          'release-gate',
          'tgdog-1',
        ]),
        ['tgdog-1', 'release-gate'],
      );
      expect(
        runner.callsFor('update').single,
        containsAllInOrder([
          '--add-label',
          'provides:tgdog-1',
          '--add-label',
          'provides:release-gate',
        ]),
      );
      expect(flares.single.data['capabilities'], 'tgdog-1,release-gate');
    },
  );

  test('a fully shipped bead spawns no process at all', () async {
    runner.exportBeads = [
      _work(
        'tgdog-1',
        labels: const ['export:tgdog-1', 'provides:tgdog-1'],
        status: BeadStatus.closed,
      ),
    ];

    expect(await writer().shipExports('tgdog-1'), isEmpty);
    expect(runner.callsFor('update'), isEmpty);
    expect(flares, isEmpty);
  });

  test(
    'an open bead is not published even with explicit healer input',
    () async {
      runner.exportBeads = [_work('tgdog-1')];

      expect(await writer().shipExports('tgdog-1', const ['tgdog-1']), isEmpty);
      expect(runner.callsFor('update'), isEmpty);
      expect(flares, isEmpty);
    },
  );

  test(
    'shipExports is fail-closed on ownership and silent on an absent bead',
    () async {
      expect(
        () => writer().shipExports('other-1'),
        throwsA(isA<OwnershipRefused>()),
      );
      expect(await writer().shipExports('tgdog-missing'), isEmpty);
      expect(runner.callsFor('update'), isEmpty);
    },
  );

  test('a throwing external.shipped sink cannot fail publication', () async {
    runner.exportBeads = [_work('tgdog-1', status: BeadStatus.closed)];
    final protectedWriter = StationBeadWriter(
      bd: bd,
      reader: runner,
      ownership: BeadOwnershipPredicate({'tgdog'}),
      onFlare: (_, __) => throw StateError('sink unavailable'),
    );

    expect(await protectedWriter.shipExports('tgdog-1', const ['tgdog-1']), [
      'tgdog-1',
    ]);
    expect(runner.callsFor('update'), hasLength(1));
  });

  test('the writer never calls the proxied-mode-refused bd ship verb', () {
    final source = File(
      'lib/src/lifecycle/station_bead_writer.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('_bd.ship(')));
  });
}
