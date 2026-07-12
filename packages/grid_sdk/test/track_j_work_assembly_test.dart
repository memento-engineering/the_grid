// Track J (tg-yl8) — buildStationWork's fail-closed store binding: EXACT at
// the root, LOUD refusal, never a walk-up. The A37 gate is the load-bearing
// one: a missing `<grid.root>/.grid/.beads` must REFUSE — the old walk-up
// discovery would have silently bound the dual-role repo's WORK store and
// minted sessions into the work source.
import 'dart:io';

import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

/// A minimal resolver — assembly refusals fire before anything resolves.
class _NullResolver implements SessionResolver {
  const _NullResolver();
  @override
  Seed sessionFor({required bead, session}) =>
      throw UnimplementedError('never reached in refusal tests');
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('tg-yl8-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<StationWorkRuntime> build({
    List<SubstationWorkSpec>? substations,
    String? gridRoot,
  }) => buildStationWork(
    stateStore: GridStateStore.forGridRoot(gridRoot ?? '${tmp.path}/home'),
    substations:
        substations ??
        [SubstationWorkSpec(name: 'proj', root: '${tmp.path}/proj')],
    resolver: const _NullResolver(),
    dryRun: true,
  );

  group('Track J — the assembly is fail-closed at the stores', () {
    test('an empty substation list refuses (no default substation)', () {
      expect(
        () => build(substations: []),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a duplicate substation name refuses (two WorkLists would race)', () {
      expect(
        () => build(
          substations: [
            SubstationWorkSpec(name: 'proj', root: '${tmp.path}/a'),
            SubstationWorkSpec(name: 'proj', root: '${tmp.path}/b'),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'CROSS-AXIS identity overlap refuses: one substation\'s prefix colliding '
      'with another\'s name would mount the same bead under BOTH WorkLists '
      '(ownership matches either axis)',
      () {
        expect(
          () => build(
            substations: [
              SubstationWorkSpec(
                name: 'the_grid',
                prefix: 'tg',
                root: '${tmp.path}/a',
              ),
              SubstationWorkSpec(name: 'tg', root: '${tmp.path}/b'),
            ],
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '${e.message}',
              'message',
              contains('"tg"'),
            ),
          ),
        );
        // The clean disjoint pairing sails past the identity guard (and
        // refuses later at the missing stores — the positive control that the
        // guard is not over-broad).
        expect(
          () => build(
            substations: [
              SubstationWorkSpec(
                name: 'the_grid',
                prefix: 'tg',
                root: '${tmp.path}/a',
              ),
              SubstationWorkSpec(
                name: 'power_station',
                prefix: 'pow',
                root: '${tmp.path}/b',
              ),
            ],
          ),
          throwsA(isA<StoreRefusal>()),
        );
      },
    );

    test('a substation root with no .beads refuses LOUD (no walk-up)', () {
      Directory('${tmp.path}/proj').createSync(recursive: true);
      _seedStore('${tmp.path}/home/.grid', database: 'houston');
      expect(() => build(), throwsA(isA<StoreRefusal>()));
    });

    test(
      'THE A37 GATE: a missing grid state store refuses — even when the '
      'dual-role grid root itself holds a work store the old walk-up would '
      'have silently bound (sessions must never land in a work source)',
      () {
        _seedStore('${tmp.path}/proj', database: 'pow');
        // The grid HOME has a work store at its root (the dual-role repo
        // shape) — but NO state store under .grid/. Walk-up discovery from
        // <home>/.grid would find <home>/.beads; the assembly must refuse
        // instead.
        _seedStore('${tmp.path}/home', database: 'space');
        expect(
          () => build(),
          throwsA(
            isA<StoreRefusal>().having(
              (r) => r.message,
              'message',
              contains('.grid'),
            ),
          ),
        );
      },
    );

    test(
      'a state store naming no dolt_database refuses — the owned state '
      'partition derives from the store identity, never a flag (Q5a)',
      () {
        _seedStore('${tmp.path}/proj', database: 'pow');
        _seedStore('${tmp.path}/home/.grid');
        expect(
          () => build(),
          throwsA(
            isA<StoreRefusal>().having(
              (r) => r.message,
              'message',
              contains('dolt_database'),
            ),
          ),
        );
      },
    );

    test('the built runtime sweeps orphans against the OWNED state partition '
        '(the runner has one to hand to runGrid)', () async {
      _seedStore('${tmp.path}/proj', database: 'pow');
      _seedStore('${tmp.path}/home/.grid', database: 'tgstate');
      final work = await build();
      addTearDown(work.shutdown);

      // A dry-run station spawns nothing, so a teardown sweep is CLEAN — and it
      // reconciles the dry transport under the OWNED prefix, never a foreign
      // one.
      final report = await work.sweepOrphans();
      expect(report.isClean, isTrue);
      expect(report.settled, isTrue);
      expect(work.stateSubstation, 'tgstate');
    });
  });
}
