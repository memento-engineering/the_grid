import 'package:beads_dart/beads_dart.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import 'support/runtime_fakes.dart';

void main() {
  const adapter = GraphEventAdapter();

  group('GraphEventAdapter — BeadClosed → wispClosed', () {
    test('a close of a loop active wisp maps to wispClosed', () {
      final loop = activeLoop(rootId: 'A', activeWispId: 'A-w1');
      final source = FakeConvergenceSource(
        snapWith(
          roots: [loop.root],
          children: {
            'A': [loop.closedWisp],
          },
        ),
      );
      final mapped = adapter.adapt(
        beadClosedEvent(loop.closedWisp, loop.closedWisp),
        source.convergences,
      );
      expect(mapped, isNotNull);
      expect(mapped!.event, isA<WispClosedEvent>());
      final wc = mapped.event as WispClosedEvent;
      expect(wc.convergenceBeadId, 'A');
      expect(wc.wispId, 'A-w1');
    });

    test('a close of a NON-active bead maps to null', () {
      final loop = activeLoop(rootId: 'A', activeWispId: 'A-w1');
      final source = FakeConvergenceSource(
        snapWith(
          roots: [loop.root],
          children: {
            'A': [loop.closedWisp],
          },
        ),
      );
      // An ordinary task bead closing — concerns no loop.
      final other = Bead(
        id: 'task-9',
        title: 't',
        issueType: IssueType.task,
        status: BeadStatus.closed,
      );
      expect(
        adapter.adapt(beadClosedEvent(other, other), source.convergences),
        isNull,
      );
    });

    test('a non-close event maps to null', () {
      final loop = activeLoop();
      final source = FakeConvergenceSource(
        snapWith(
          roots: [loop.root],
          children: {
            'root-1': [loop.closedWisp],
          },
        ),
      );
      expect(
        adapter.adapt(GraphEvent.beadCreated(loop.root), source.convergences),
        isNull,
      );
    });
  });

  group('GraphEventAdapter — observedGcCommand (shadow detection)', () {
    Bead conv(Map<String, dynamic> meta) =>
        convergenceBead('c', metadata: meta);

    test('terminal approved by operator → operatorApprove', () {
      final before = conv({ConvergenceFields.state: 'waiting_manual'});
      final after = conv({
        ConvergenceFields.state: 'terminated',
        ConvergenceFields.terminalReason: 'approved',
        ConvergenceFields.terminalActor: 'operator:nico',
      });
      final observed = adapter.observedGcCommand(
        beadUpdatedEvent(before, after),
      );
      expect(observed?.command, GcCommandKind.operatorApprove);
    });

    test('terminal approved by controller → handlerApproved', () {
      final before = conv({ConvergenceFields.state: 'active'});
      final after = conv({
        ConvergenceFields.state: 'terminated',
        ConvergenceFields.terminalReason: 'approved',
        ConvergenceFields.terminalActor: 'controller',
      });
      final observed = adapter.observedGcCommand(
        beadUpdatedEvent(before, after),
      );
      expect(observed?.command, GcCommandKind.handlerApproved);
    });

    test('terminal stopped → operatorStop', () {
      final before = conv({ConvergenceFields.state: 'active'});
      final after = conv({
        ConvergenceFields.state: 'terminated',
        ConvergenceFields.terminalReason: 'stopped',
        ConvergenceFields.terminalActor: 'operator:nico',
      });
      expect(
        adapter.observedGcCommand(beadUpdatedEvent(before, after))?.command,
        GcCommandKind.operatorStop,
      );
    });

    test('waiting_manual → active is operatorIterate', () {
      final before = conv({ConvergenceFields.state: 'waiting_manual'});
      final after = conv({ConvergenceFields.state: 'active'});
      expect(
        adapter.observedGcCommand(beadUpdatedEvent(before, after))?.command,
        GcCommandKind.operatorIterate,
      );
    });

    test('waiting_trigger → active is triggerAdvance', () {
      final before = conv({ConvergenceFields.state: 'waiting_trigger'});
      final after = conv({ConvergenceFields.state: 'active'});
      expect(
        adapter.observedGcCommand(beadUpdatedEvent(before, after))?.command,
        GcCommandKind.triggerAdvance,
      );
    });

    test('a non-convergence update → null', () {
      final before = Bead(id: 'x', title: 't', issueType: IssueType.task);
      final after = Bead(
        id: 'x',
        title: 't',
        issueType: IssueType.task,
        status: BeadStatus.closed,
      );
      expect(
        adapter.observedGcCommand(beadUpdatedEvent(before, after)),
        isNull,
      );
    });
  });
}
