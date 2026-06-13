// recoveryReportProvider derives the full-reconcile pass from
// graphSnapshotProvider (ADR-0002 D2 — no new IO), mirroring
// convergence_providers_test.dart. The provider is Track G's backstop read
// surface (startup + low-frequency).

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

import 'support/recovery_fakes.dart';

void main() {
  group('recoveryReportProvider', () {
    Future<ProviderContainer> containerFor(GraphSnapshot snapshot) async {
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

    test('reconciles every non-closed convergence in the snapshot', () async {
      final creating = convergenceBead(
        'gt-c1',
        metadata: {ConvergenceFields.state: 'creating'},
      );
      final terminated = convergenceBead(
        'gt-c2',
        metadata: meta(
          state: 'terminated',
          extra: {ConvergenceFields.terminalReason: 'approved'},
        ),
      );
      // A clean active loop with a live wisp → no_action.
      final active = convergenceBead(
        'gt-c3',
        metadata: meta(
          state: 'active',
          extra: {
            ConvergenceFields.activeWisp: 'gt-w3',
            ConvergenceFields.gateMode: 'condition',
            ConvergenceFields.gateCondition: '/gate',
            ConvergenceFields.gateTimeout: '60s',
          },
        ),
      );
      final w3 = wispBead('gt-w3', key: 'converge:gt-c3:iter:1');

      final snapshot = snap(
        [creating, terminated, active, w3],
        deps: [parentChild('gt-w3', 'gt-c3')],
      );
      final c = await containerFor(snapshot);
      final report = c.read(recoveryReportProvider);

      expect(report.scanned, 3);
      expect(report.recovered, 2); // creating + terminated.
      expect(report.errors, 0);
      final byId = {for (final o in report.outcomes) o.convergenceBeadId: o};
      expect(byId['gt-c1']!.action, RecoveryActionLabel.completedTerminal);
      expect(byId['gt-c2']!.action, RecoveryActionLabel.completedTerminal);
      expect(byId['gt-c3']!.action, RecoveryActionLabel.noAction);
    });

    test('an empty snapshot yields an empty report (scanned 0)', () async {
      final c = await containerFor(snap(const []));
      final report = c.read(recoveryReportProvider);
      expect(report.scanned, 0);
      expect(report.outcomes, isEmpty);
    });
  });
}
