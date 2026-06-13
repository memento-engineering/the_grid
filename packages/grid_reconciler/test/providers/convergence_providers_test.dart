import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';

void main() {
  group(
    'convergence providers derive from graphSnapshotProvider (no new IO)',
    () {
      // Three loops over a fake snapshot source: one active with wisps, one
      // waiting_manual, one not yet adopted (no state key), plus an
      // unrecognized-state loop and a non-convergence bead.
      late GraphSnapshot snapshot;

      setUp(() {
        final active = convergenceBead(
          'gt-c1',
          metadata: const {
            'convergence.state': 'active',
            'convergence.active_wisp': 'gt-w2',
            'convergence.formula': 'mol-polish',
          },
        );
        final w1 = wispBead(
          'gt-w1',
          key: 'converge:gt-c1:iter:1',
          status: BeadStatus.closed,
        );
        final w2 = wispBead('gt-w2', key: 'converge:gt-c1:iter:2');

        final waiting = convergenceBead(
          'gt-c2',
          metadata: const {
            'convergence.state': 'waiting_manual',
            'convergence.waiting_reason': 'manual',
          },
        );
        final unadopted = convergenceBead('gt-c3'); // no convergence.state key
        final weird = convergenceBead(
          'gt-c4',
          metadata: const {'convergence.state': 'limbo'},
        );
        const task = Bead(id: 'gt-t1', issueType: IssueType.task);

        snapshot = snap(
          [active, w1, w2, waiting, unadopted, weird, task],
          deps: [parentChild('gt-w1', 'gt-c1'), parentChild('gt-w2', 'gt-c1')],
        );
      });

      Future<ProviderContainer> container() async {
        final c = ProviderContainer(
          overrides: [
            graphSnapshotProvider.overrideWith((ref) => Stream.value(snapshot)),
          ],
        );
        c.listen(graphSnapshotProvider, (_, _) {});
        await c.read(graphSnapshotProvider.future);
        addTearDown(c.dispose);
        return c;
      }

      test('convergencesProvider projects every convergence bead with wisps '
          'resolved from the snapshot edges', () async {
        final c = await container();
        final convergences = c.read(convergencesProvider);
        expect(
          convergences.map((cv) => cv.id),
          containsAll(['gt-c1', 'gt-c2', 'gt-c3', 'gt-c4']),
        );
        expect(convergences, hasLength(4)); // the task bead never projects
        final c1 = convergences.firstWhere((cv) => cv.id == 'gt-c1');
        expect(c1.wisps.map((w) => w.id), ['gt-w1', 'gt-w2']);
        expect(c1.closedWispCount, 1);
      });

      test('convergenceProvider resolves by id, null for absent or '
          'non-convergence ids', () async {
        final c = await container();
        expect(c.read(convergenceProvider('gt-c2'))!.id, 'gt-c2');
        expect(c.read(convergenceProvider('gt-t1')), isNull);
        expect(c.read(convergenceProvider('nope')), isNull);
      });

      test(
        'convergencesByStateProvider groups by state reading — known '
        'states, notAdopted, and unrecognized each their own group',
        () async {
          final c = await container();
          final byState = c.read(convergencesByStateProvider);
          expect(
            byState[const ConvergenceStateReading.known(
                  ConvergenceState.active,
                )]!
                .map((cv) => cv.id),
            ['gt-c1'],
          );
          expect(
            byState[const ConvergenceStateReading.known(
                  ConvergenceState.waitingManual,
                )]!
                .map((cv) => cv.id),
            ['gt-c2'],
          );
          expect(
            byState[const ConvergenceStateReading.notAdopted()]!.map(
              (cv) => cv.id,
            ),
            ['gt-c3'],
          );
          expect(
            byState[const ConvergenceStateReading.unrecognized('limbo')]!.map(
              (cv) => cv.id,
            ),
            ['gt-c4'],
          );
        },
      );

      test('activeWispProvider resolves the active wisp; null when dangling '
          'or absent', () async {
        final c = await container();
        expect(c.read(activeWispProvider('gt-c1'))!.id, 'gt-w2');
        expect(c.read(activeWispProvider('gt-c2')), isNull); // no active_wisp
        expect(c.read(activeWispProvider('nope')), isNull); // no such loop
      });

      test('providers return empty before any snapshot (pure selectors, '
          'never throw)', () {
        final c = ProviderContainer(
          overrides: [
            graphSnapshotProvider.overrideWith(
              (ref) => const Stream<GraphSnapshot>.empty(),
            ),
          ],
        );
        addTearDown(c.dispose);
        expect(c.read(convergencesProvider), isEmpty);
        expect(c.read(convergencesByStateProvider), isEmpty);
        expect(c.read(activeWispProvider('gt-c1')), isNull);
      });
    },
  );
}
