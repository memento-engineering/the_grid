/// The `code` extension — agent/verify/land as Capability impls + the linear
/// `code` formula (ADR-0008 D2 / M4-P1 §6, Track H).
///
/// The agent/verify/land OPINIONS live here as opaque [Capability] leaves (never
/// a `Seed`), composed into a linear [Formula] whose always-1-wide frontier
/// reproduces the original agent→verify→land sequence. The kernel/effect core
/// references none of this — only this extension does (the opinion-free kernel
/// invariant, ADR-0007 §1; a structural fence keeps it here).
///
/// This is the LIVE work path: `composeRunTree` wires it via the
/// [buildCodeRegistry] registry + a [FormulaResolver] that roots the `code`
/// formula per coding bead.
library;

import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart';

import '../formula/default_capability_registry.dart';
import '../sdk/capability.dart';
import '../sdk/formula.dart';

/// agent → verify → land — the degenerate linear formula (§6). Its 1-wide
/// frontier (agent dep-free; verify after agent; land after verify) mounts ONE
/// `CapabilityHost` at a time, reproducing P0's `EffectSeed` swap behavior.
const Formula kCodeFormula = Formula(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    CapabilityStep(stepId: 'verify', capabilityId: 'verify', dependsOn: {'agent'}),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'verify'}),
  ],
);

/// The IMPLEMENT capability — spawn the coding agent in the bead's workspace
/// (migrated from `AgentEffectSeed`). `claude -p` (non-interactive print mode);
/// `--dangerously-skip-permissions` so a headless dogfood agent runs without an
/// approval prompt. The prompt carries the **full** bead (title + description +
/// design + acceptance + notes — a title-only prompt starves the agent of the
/// load-bearing instructions, A36 pre-flight) plus a **local-first working
/// agreement**: work in the worktree, COMMIT, do NOT push, do NOT open a PR.
/// Landing is an explicit OPT-IN (`grid run --land`; ADR-0006 D3) and OFF by
/// default — the AGENT always stops at a local commit; only the separate `land`
/// step (after `verify`) pushes + opens the PR, and only when armed. Unarmed,
/// the `land` capability no-ops, so the loop produces inspectable local commits
/// with zero GitHub side effects. (The agent-token/auth seam is the macOS
/// keychain — A38; nothing rides argv.)
class AgentCapability extends ProcessCapability {
  /// Creates the agent capability.
  const AgentCapability();

  @override
  RuntimeConfig spawn(CapabilityContext ctx) => RuntimeConfig(
    workDir: ctx.workspaceDir,
    command: 'claude',
    args: ['--dangerously-skip-permissions', '-p', buildAgentPrompt(ctx)],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => _jobSignal(event);
}

/// Assembles the agent's full-bead prompt + local-first working agreement (the
/// live dogfood contract — exposed for unit tests). The host layers
/// `GRID_BEAD_ID`/`GRID_SESSION_ID`/`GRID_STEP_PATH` over the env (so the
/// `grid step --advance` shim can advance the OWN session cursor through the
/// chokepoint); this is the human-readable instruction half.
String buildAgentPrompt(CapabilityContext ctx) {
  final bead = ctx.bead;
  final title = bead.title.isNotEmpty ? bead.title : 'work bead ${bead.id}';
  final substation = bead.metadata['rig'];
  final p = StringBuffer()
    ..writeln('# $title')
    ..writeln()
    ..writeln(
      substation is String && substation.isNotEmpty
          ? 'Bead `${bead.id}` (substation `$substation`).'
          : 'Bead `${bead.id}`.',
    );
  void section(String heading, String body) {
    if (body.trim().isEmpty) return;
    p
      ..writeln()
      ..writeln('## $heading')
      ..writeln(body.trim());
  }

  section('Task', bead.description);
  section('Design', bead.design);
  section('Acceptance criteria', bead.acceptanceCriteria);
  section('Notes', bead.notes);
  p
    ..writeln()
    ..writeln('## Working agreement')
    ..writeln(
      '- Work ONLY inside this worktree (${ctx.workspaceDir}); it is on branch '
      '`${ctx.branch}`, a throwaway branch the_grid provisioned for this bead.',
    )
    ..writeln('- Implement the task and COMMIT your work on that branch.')
    ..writeln(
      '- Do NOT push and do NOT open a pull request — leave the commit for '
      'human review.',
    )
    ..writeln(
      '- When committed, run `grid step --advance` to mark this step done, then '
      "exit. (This advances your OWN session cursor through the_grid's "
      'chokepoint-mediated shim. It is NOT a free-form `bd` call: do not write '
      'beads directly from the worktree.)',
    )
    ..writeln('- When the work is committed you are done; exit.');
  return p.toString();
}

/// The VERIFY capability — run the check in the bead's workspace (migrated from
/// `VerifyEffectSeed`; deliberately NOT the M2 convergence gate). `sh -c 'melos
/// test'`: a green exit completes, a non-zero exit fails.
class VerifyCapability extends ProcessCapability {
  /// Creates the verify capability.
  const VerifyCapability();

  @override
  RuntimeConfig spawn(CapabilityContext ctx) => RuntimeConfig(
    workDir: ctx.workspaceDir,
    command: 'sh',
    args: const ['-c', 'melos test'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => _jobSignal(event);
}

/// A job's terminal mapping: a clean `Exited(0)` completes; any other terminal
/// (non-zero exit or a `Died`) fails (routes to supervision).
StepSignal _jobSignal(RuntimeEvent event) => switch (event) {
  Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
  Exited() || Died() => StepSignal.failed,
  _ => StepSignal.none,
};

/// The LAND capability — commit → push → open the PR via the pluggable
/// [SourceControl] Service (migrated from `LandEffectSeed`; the positive
/// terminal). Offline-safe: when no [SourceControl] is wired it no-ops to [Ok]
/// (it never touches real git/GitHub); a PR that does not open is [Failed]
/// (an honest "land did not complete"). The pr url rides the [Ok] payload, which
/// the engine records on the session bead — never used as a pipeline signal.
class LandCapability extends ServiceCapability {
  /// Creates the land capability.
  const LandCapability();

  @override
  Future<StepOutcome> run(CapabilityContext ctx) async {
    final sc = ctx.services.sourceControl;
    // Land not wired (no SourceControl, or provisioning-only for an early arm
    // whose working agreement is commit-only) — no-op rather than touch real
    // git. `canLand` distinguishes "deferred" (Ok) from "tried + failed" (Failed).
    if (sc == null || !sc.canLand) return const Ok();

    await sc.commitAll(
      workspaceDir: ctx.workspaceDir,
      message: 'grid: land ${ctx.beadId}',
    );
    if (ctx.cancel.isCancelled) return const Failed('cancelled');

    await sc.push(
      workspaceDir: ctx.workspaceDir,
      remote: 'origin',
      branch: ctx.branch,
    );
    if (ctx.cancel.isCancelled) return const Failed('cancelled');

    final pr = await sc.openPr(
      workspaceDir: ctx.workspaceDir,
      branch: ctx.branch,
      baseBranch: ctx.baseBranch,
      title: 'grid: ${ctx.beadId}',
    );
    // Check cancellation after EVERY async gap (P0 LandEffectSeed parity) — a
    // dispose mid-land must not record a stale terminal.
    if (ctx.cancel.isCancelled) return const Failed('cancelled');
    if (pr == null) return const Failed('pr open did not complete');
    return Ok({'pr_url': pr.url});
  }
}

/// The git [SourceControl] impl over grid_runtime (the detail the engine knows
/// only in CONCEPT — ADR-0008 D5; ships in the extension). Two independent
/// halves:
///  - **provisioning** — [provisioner] ([StationGitService]) + [root]
///    ([RootCheckout]) cut the per-bead worktree. Provided whenever a root is
///    registered (live), so the host can materialize the workspace before the
///    agent spawns. Absent ⇒ `provisionWorkspace` no-ops (offline).
///  - **land** — [gitOps] (commit/push) + [prOpener] (PR). Absent ⇒ [canLand] is
///    false and [LandCapability] no-ops (the early-arm commit-only posture).
class GitSourceControl implements SourceControl {
  /// Wraps the optional land ops ([gitOps]/[prOpener]) and the optional
  /// provisioning seam ([provisioner]/[root]).
  const GitSourceControl({
    GitOps? gitOps,
    PrOpener? prOpener,
    StationGitService? provisioner,
    RootCheckout? root,
  }) : _gitOps = gitOps,
       _prOpener = prOpener,
       _provisioner = provisioner,
       _root = root;

  final GitOps? _gitOps;
  final PrOpener? _prOpener;
  final StationGitService? _provisioner;
  final RootCheckout? _root;

  @override
  bool get canLand => _gitOps != null && _prOpener != null;

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {
    final provisioner = _provisioner;
    final root = _root;
    // Provisioning not wired (offline) — nothing to do.
    if (provisioner == null || root == null) return;
    // Idempotent: a later step (verify/land) reuses the agent's worktree.
    if (Directory(workspaceDir).existsSync()) return;
    await provisioner.provisionWorktree(root: root, beadId: beadId);
  }

  @override
  Future<void> commitAll({
    required String workspaceDir,
    required String message,
  }) => _gitOps!.commitAll(workDir: workspaceDir, message: message);

  @override
  Future<void> push({
    required String workspaceDir,
    required String remote,
    required String branch,
  }) => _gitOps!.pushSetUpstream(
    workDir: workspaceDir,
    remote: remote,
    branch: branch,
  );

  @override
  Future<PrRef?> openPr({
    required String workspaceDir,
    required String branch,
    required String baseBranch,
    required String title,
  }) async {
    final result = await _prOpener!.open(
      workDir: workspaceDir,
      branch: branch,
      baseBranch: baseBranch,
      title: title,
    );
    return result.isOpened ? PrRef(result.ref!.url) : null;
  }
}

/// Builds the `code` registry: the agent/verify/land capabilities + the `code`
/// formula, with an optional injected [clock] (the backoff seam). The composer
/// provides it as a stable `InheritedSeed<CapabilityRegistry>` above `Station`,
/// alongside a `FormulaResolver((_) => kCodeFormula)`.
DefaultCapabilityRegistry buildCodeRegistry({DateTime Function()? clock}) =>
    DefaultCapabilityRegistry(
      capabilities: const {
        'agent': AgentCapability(),
        'verify': VerifyCapability(),
        'land': LandCapability(),
      },
      formulas: const {'code': kCodeFormula},
      clock: clock,
    );
