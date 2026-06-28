// Track H — agent/verify/land as Capability impls + the `code` formula (§6).
// The real capabilities produce P0's spawn configs / land orchestration, and the
// `code` formula runs end-to-end over the new path (the no-behavior-change
// proof: a 1-wide frontier, agent → verify → land → session close).
//
// ADR-0008 D2 / M4-P1 §6, Track H. Zero I/O — fakes + the recording chokepoint.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

CapabilityContext _capCtx({SourceControl? sourceControl, Bead? beadOverride}) =>
    CapabilityContext(
      params: const {},
      bead: beadOverride ?? bead('tg-1'),
      workspaceDir: '/w/tg-1',
      branch: 'grid/tg-1',
      baseBranch: 'main',
      services: ServiceBundle(sourceControl: sourceControl),
      cancel: CancelToken(),
    );

/// A recording [SourceControl] (the land Service, faked).
class _FakeSourceControl implements SourceControl {
  final List<String> calls = [];
  bool prOpens = true;

  @override
  Future<void> commitAll({required String workspaceDir, required String message}) async =>
      calls.add('commit:$workspaceDir:$message');

  @override
  Future<void> push({
    required String workspaceDir,
    required String remote,
    required String branch,
  }) async => calls.add('push:$remote:$branch');

  @override
  Future<PrRef?> openPr({
    required String workspaceDir,
    required String branch,
    required String baseBranch,
    required String title,
  }) async {
    calls.add('pr:$branch->$baseBranch:$title');
    return prOpens ? const PrRef('https://github.com/memento/x/pull/7') : null;
  }
}

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

JoinedSnapshot _joined({
  required Map<String, SessionProjection> sessions,
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: [Bead(id: 'tg-1', issueType: IssueType.task, status: BeadStatus.open)],
    dependencies: const [],
    readyIds: const {'tg-1'},
    capturedAt: DateTime(2026),
  ),
  sessionsByWorkBead: sessions,
);

SessionProjection _session(Map<String, NodeCursor> cursor) => SessionProjection(
  workBeadId: 'tg-1',
  sessionId: 'tgdog-s',
  cursor: cursor,
);

const _tgConfig = SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'});

void main() {
  group('Track H — the capabilities reproduce P0 configs/orchestration', () {
    test('AgentCapability spawns headless `claude -p <prompt>` in the worktree',
        () {
      final cfg = const AgentCapability().spawn(_capCtx());
      expect(cfg.command, 'claude');
      // Headless print mode + skip-permissions, then the rich prompt as argv[2].
      expect(cfg.args.length, 3);
      expect(cfg.args[0], '--dangerously-skip-permissions');
      expect(cfg.args[1], '-p');
      expect(cfg.args[2], contains('Bead `tg-1`'));
      expect(cfg.workDir, '/w/tg-1');
      expect(cfg.lifecycle, Lifecycle.oneTurn);
    });

    test('AgentCapability carries the FULL bead + local-first working agreement',
        () {
      final rich = bead('tg-1').copyWith(
        title: 'Wire the federation bus',
        description: 'Connect The Studio to The Dashboard.',
        design: 'Use a lossy inter-station gossip bus.',
        acceptanceCriteria: 'A peer heartbeat surfaces within 1s.',
        notes: 'Coexistence-safe; do not touch gc.',
        metadata: const {'rig': 'tgdog'},
      );
      final prompt = buildAgentPrompt(_capCtx(beadOverride: rich));
      // The full bead — a title-only prompt would starve the agent (A36).
      expect(prompt, contains('# Wire the federation bus'));
      expect(prompt, contains('substation `tgdog`'));
      expect(prompt, contains('## Task\nConnect The Studio to The Dashboard.'));
      expect(prompt, contains('## Design\nUse a lossy inter-station gossip bus.'));
      expect(prompt, contains('## Acceptance criteria'));
      expect(prompt, contains('## Notes\nCoexistence-safe; do not touch gc.'));
      // The local-first working agreement (commit, no push, no PR, advance shim).
      expect(prompt, contains('/w/tg-1'));
      expect(prompt, contains('branch `grid/tg-1`'));
      expect(prompt, contains('COMMIT'));
      expect(prompt, contains('Do NOT push and do NOT open a pull request'));
      expect(prompt, contains('grid step --advance'));
    });

    test('AgentCapability prompt omits empty bead sections + the substation '
        'parenthetical', () {
      // An empty bead: only the header + the working agreement, no Task/Design.
      final prompt = buildAgentPrompt(_capCtx());
      expect(prompt, contains('# work bead tg-1'));
      expect(prompt, contains('Bead `tg-1`.'));
      expect(prompt, isNot(contains('## Task')));
      expect(prompt, isNot(contains('## Design')));
      expect(prompt, isNot(contains('substation `'))); // no rig metadata
      expect(prompt, contains('## Working agreement'));
    });

    test('VerifyCapability spawns `sh -c melos test` (P0 VerifyEffectSeed parity)',
        () {
      final cfg = const VerifyCapability().spawn(_capCtx());
      expect(cfg.command, 'sh');
      expect(cfg.args, const ['-c', 'melos test']);
    });

    test('a clean exit completes a job; a non-zero exit / death fails', () {
      expect(
        const AgentCapability().interpretEvent(const Exited(name: 'x', exitCode: 0)),
        StepSignal.complete,
      );
      expect(
        const AgentCapability().interpretEvent(const Exited(name: 'x', exitCode: 1)),
        StepSignal.failed,
      );
      expect(
        const VerifyCapability().interpretEvent(const Died(name: 'x')),
        StepSignal.failed,
      );
    });

    test('LandCapability drives commit → push → PR and returns Ok(pr_url)', () async {
      final sc = _FakeSourceControl();
      final outcome = await const LandCapability().run(_capCtx(sourceControl: sc));
      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, {'pr_url': 'https://github.com/memento/x/pull/7'});
      expect(sc.calls, [
        'commit:/w/tg-1:grid: land tg-1',
        'push:origin:grid/tg-1',
        'pr:grid/tg-1->main:grid: tg-1',
      ]);
    });

    test('LandCapability with NO source control no-ops to Ok (offline-safe)',
        () async {
      final outcome = await const LandCapability().run(_capCtx());
      expect(outcome, isA<Ok>());
    });

    test('LandCapability fails when the PR does not open', () async {
      final sc = _FakeSourceControl()..prOpens = false;
      final outcome = await const LandCapability().run(_capCtx(sourceControl: sc));
      expect(outcome, isA<Failed>());
    });
  });

  group('Track H — the `code` formula runs end-to-end over the new path (§6)', () {
    test('agent → verify → land → session close, 1-wide frontier throughout',
        () async {
      final f = buildFakes();
      final sc = _FakeSourceControl();
      final registry = buildCodeRegistry(clock: () => DateTime(2026));
      // Pre-seed the session (adopt synchronously); start at an empty cursor.
      final joined = JoinedSnapshotNotifier(
        _joined(sessions: {'tg-1': _session(const {})}),
      );
      final owner = TreeOwner();
      addTearDown(() {
        owner.dispose();
        unawaited(f.provider.close());
      });
      owner.mountRoot(
        InheritedSeed<JoinedSnapshotNotifier>(
          value: joined,
          child: InheritedSeed<EffectContext>(
            value: f.ctx,
            child: StableInheritedSeed<CapabilityRegistry>(
              value: registry,
              child: InheritedSeed<ServiceBundle>(
                value: ServiceBundle(sourceControl: sc),
                child: InheritedSeed<EffectResolver>(
                  value: FormulaResolver((_) => kCodeFormula),
                  child: Station([
                    SubstationScope(
                      configNotifier: SubstationConfigNotifier(_tgConfig),
                      key: const ValueKey('scope.tg'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
      await _pump();

      // 1-wide: only the agent spawned.
      expect(f.provider.started.map((s) => s.name), ['tgdog-s/tg-1/agent']);

      // Agent exits clean → host writes agent=complete; advance the cursor.
      f.provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0));
      await _pump();
      joined.push(_joined(sessions: {
        'tg-1': _session(const {'tg-1/agent': NodeCursor(state: StepState.complete)}),
      }));
      owner.flush();
      await _pump();

      // Verify spawned next (still 1-wide — agent retired).
      expect(f.provider.started.map((s) => s.name),
          ['tgdog-s/tg-1/agent', 'tgdog-s/tg-1/verify']);

      // Verify exits clean → advance to land.
      f.provider.emit(const Exited(name: 'tgdog-s/tg-1/verify', exitCode: 0));
      await _pump();
      joined.push(_joined(sessions: {
        'tg-1': _session(const {
          'tg-1/agent': NodeCursor(state: StepState.complete),
          'tg-1/verify': NodeCursor(state: StepState.complete),
        }),
      }));
      owner.flush();
      await _pump();

      // Land (a ServiceCapability — no spawn) ran the git orchestration.
      expect(sc.calls, isNotEmpty);
      expect(f.provider.started.map((s) => s.name),
          ['tgdog-s/tg-1/agent', 'tgdog-s/tg-1/verify']); // land never spawns

      // Land wrote land=complete; advance — SessionScope closes the session.
      joined.push(_joined(sessions: {
        'tg-1': _session(const {
          'tg-1/agent': NodeCursor(state: StepState.complete),
          'tg-1/verify': NodeCursor(state: StepState.complete),
          'tg-1/land': NodeCursor(state: StepState.complete),
        }),
      }));
      owner.flush();
      await _pump();
      expect(
        f.runner.callsFor('close').where((c) => c[1] == 'tgdog-s'),
        hasLength(1),
        reason: 'the terminal step (land) drives the SessionScope close (§6 parity)',
      );
    });
  });
}
