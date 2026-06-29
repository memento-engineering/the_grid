// Track H — the agent + land Capability impls + the git SourceControl (§6).
//
// The agent/land OPINIONS are real [Capability] impls: the agent produces the
// coding-agent spawn config (the full-bead prompt + the local-first working
// agreement), and `land` drives commit → push → PR through the pluggable
// [SourceControl] Service. The toy `verify` capability is GONE (M5 "The Circuit"
// — `verify` is now the adversarial committee; that wiring is proven end-to-end
// by circuit_acceptance_test.dart), so this file is the Agent/Land/GitSourceControl
// capability-UNIT file.
//
// ADR-0008 D2 / M4-P1 §6, Track H. Zero I/O — fakes only.
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

CapabilityContext _capCtx({SourceControl? sourceControl, Bead? beadOverride}) =>
    CapabilityContext(
      params: const {},
      bead: beadOverride ?? bead('tg-1'),
      workspaceDir: '/w/tg-1',
      branch: 'grid/tg-1',
      baseBranch: 'main',
      services: ServiceBundle(sourceControl: sourceControl),
      cancel: CancelToken(),
      nodePath: 'tg-1/agent',
    );

/// A recording [SourceControl] (the land + provision Service, faked).
class _FakeSourceControl implements SourceControl {
  final List<String> calls = [];
  bool prOpens = true;
  bool canProvision = true;

  /// Workspaces this fake "already has" (so provision is idempotent in tests).
  final Set<String> existingWorkspaces = {};

  @override
  bool get canLand => true;

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {
    if (existingWorkspaces.contains(workspaceDir)) {
      calls.add('provision-skip:$beadId');
      return;
    }
    if (!canProvision) return;
    existingWorkspaces.add(workspaceDir);
    calls.add('provision:$beadId:$workspaceDir');
  }

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
      // The local-first working agreement (commit, no push, no PR).
      expect(prompt, contains('/w/tg-1'));
      expect(prompt, contains('branch `grid/tg-1`'));
      expect(prompt, contains('COMMIT'));
      expect(prompt, contains('Do NOT push and do NOT open a pull request'));
      // tg-p9q: completion is OBSERVED via process-exit, never DECLARED — the
      // dangling `grid step --advance` instruction is gone.
      expect(prompt, isNot(contains('grid step --advance')));
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

    test('AgentCapability interpretEvent: clean exit completes, non-zero / death '
        'fails', () {
      const cap = AgentCapability();
      expect(
        cap.interpretEvent(const Exited(name: 'x', exitCode: 0)),
        StepSignal.complete,
      );
      expect(
        cap.interpretEvent(const Exited(name: 'x', exitCode: 1)),
        StepSignal.failed,
      );
      expect(cap.interpretEvent(const Died(name: 'x')), StepSignal.failed);
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

    test('LandCapability no-ops to Ok when a SourceControl is present but land '
        'is NOT wired (canLand=false) — provision-only, commit-only arm', () async {
      // A provision-only GitSourceControl (no gitOps/prOpener) ⇒ canLand false.
      const sc = GitSourceControl();
      expect(sc.canLand, isFalse);
      final outcome = await const LandCapability().run(_capCtx(sourceControl: sc));
      expect(outcome, isA<Ok>(), reason: 'deferred land is Ok, not Failed');
    });

    test('GitSourceControl.provisionWorkspace no-ops when provisioning is not '
        'wired (no provisioner) — never throws', () async {
      await const GitSourceControl().provisionWorkspace(
        beadId: 'tg-1',
        workspaceDir: '/does/not/exist/anywhere',
      );
      // Reaching here without throwing is the assertion (offline no-op).
    });
  });
}
