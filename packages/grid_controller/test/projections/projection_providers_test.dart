import 'package:grid_controller/grid_controller.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';
import '../support/reactivity_fakes.dart';

List<Bead> _beads(String fixture) {
  final env = BdEnvelope.parse(fixtureText(fixture));
  return [for (final json in env.dataList) Bead.fromJson(json)];
}

void main() {
  group('projection providers derive from graphSnapshotProvider (no new IO)', () {
    // Compose a snapshot from the three pinned fixtures plus a synthetic
    // molecule + steps, and drive the providers through an overridden runtime.
    late GraphSnapshot snapshot;

    setUp(() {
      final sessions = _beads('hq-session-sample.json');
      final messages = _beads('hq-message-sample.json');
      final molecules = _beads('hq-molecule-sample.json');

      // Synthetic molecule with two steps (no step fixture exists in M1).
      const synthMolId = 'mol-syn';
      final synthMol = Bead(
        id: synthMolId,
        title: 'synthetic',
        issueType: IssueType.molecule,
      );
      const s1 = Bead(
        id: 'st1',
        issueType: IssueType.step,
        status: BeadStatus.closed,
      );
      const s2 = Bead(id: 'st2', issueType: IssueType.step);
      final deps = [
        const BeadDependency(
          issueId: 'st1',
          dependsOnId: synthMolId,
          type: DependencyType.parentChild,
        ),
        const BeadDependency(
          issueId: 'st2',
          dependsOnId: synthMolId,
          type: DependencyType.parentChild,
        ),
        const BeadDependency(
          issueId: 'st2',
          dependsOnId: 'st1',
          type: DependencyType.blocks,
        ),
      ];

      snapshot = GraphSnapshot.fromParts(
        beads: [...sessions, ...messages, ...molecules, synthMol, s1, s2],
        dependencies: deps,
        readyIds: const {},
        capturedAt: fakeClock,
      );
    });

    Future<ProviderContainer> container() async {
      final runtime = GridControllerRuntime(
        reader: FakeSnapshotReader(() => snapshot),
        dirtySources: const [],
      );
      await runtime.start();
      final c = ProviderContainer(
        overrides: [gridRuntimeProvider.overrideWithValue(runtime)],
      );
      c.listen(graphSnapshotProvider, (_, __) {});
      await c.read(graphSnapshotProvider.future);
      addTearDown(() async {
        c.dispose();
        await runtime.dispose();
      });
      return c;
    }

    test('sessionsProvider projects every session bead', () async {
      final c = await container();
      final sessions = c.read(sessionsProvider);
      expect(sessions, hasLength(3));
      expect(sessions.every((s) => s.isClosed), isTrue);
      expect(
        sessions.map((s) => s.id),
        containsAll(['ga-dvt2', 'ga-vd2l', 'ga-kzkc']),
      );
    });

    test('sessionsForAgentProvider filters by durable agent name', () async {
      final c = await container();
      final forAgent = c.read(
        sessionsForAgentProvider('lenny/pack.critique-1'),
      );
      expect(forAgent, hasLength(1));
      expect(forAgent.single.id, 'ga-dvt2');
    });

    test('sessionsByStateProvider groups open vs closed', () async {
      final c = await container();
      final byState = c.read(sessionsByStateProvider);
      expect(byState[SessionState.open], isEmpty);
      expect(byState[SessionState.closed], hasLength(3));
    });

    test(
      'inboxProvider returns open messages addressed to the agent',
      () async {
        final c = await container();
        final inbox = c.read(inboxProvider('mayor'));
        expect(inbox, hasLength(3));
        expect(inbox.every((m) => m.isUnread), isTrue);
        expect(inbox.every((m) => m.recipient == 'mayor'), isTrue);
        // A non-recipient sees nothing.
        expect(c.read(inboxProvider('nobody')), isEmpty);
      },
    );

    test('threadProvider groups messages by thread:<id> label', () async {
      final c = await container();
      final thread = c.read(threadProvider('thread-067ce293d2d4'));
      expect(thread, hasLength(1));
      expect(thread.single.id, 'ga-wisp-y9uqd9');
    });

    test(
      'moleculesProvider projects molecules and resolves their steps',
      () async {
        final c = await container();
        final molecules = c.read(moleculesProvider);
        // fixture molecule (ga-dda, no steps) + synthetic (2 steps).
        expect(molecules.map((m) => m.id), containsAll(['ga-dda', 'mol-syn']));
        final synth = molecules.firstWhere((m) => m.id == 'mol-syn');
        expect(synth.steps.map((s) => s.id), ['st1', 'st2']);
      },
    );

    test('moleculeProgressProvider returns closed/total', () async {
      final c = await container();
      // st1 closed, st2 open → 0.5.
      expect(c.read(moleculeProgressProvider('mol-syn')), closeTo(0.5, 1e-9));
      // fixture molecule has no steps → 1.0.
      expect(c.read(moleculeProgressProvider('ga-dda')), 1.0);
      expect(c.read(moleculeProgressProvider('absent')), isNull);
    });

    test(
      'runnableStepsProvider returns steps whose needs are satisfied',
      () async {
        final c = await container();
        // st1 closed → st2 (needs st1) is runnable.
        final runnable = c.read(runnableStepsProvider('mol-syn'));
        expect(runnable.map((s) => s.id), ['st2']);
      },
    );

    test('providers return empty before any snapshot (no IO)', () {
      // No runtime override → graphSnapshotProvider has no value; selectors are
      // pure and return empty rather than throwing.
      final c = ProviderContainer(
        overrides: [
          graphSnapshotProvider.overrideWith(
            (ref) => const Stream<GraphSnapshot>.empty(),
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(sessionsProvider), isEmpty);
      expect(c.read(messagesProvider), isEmpty);
      expect(c.read(moleculesProvider), isEmpty);
    });
  });
}
