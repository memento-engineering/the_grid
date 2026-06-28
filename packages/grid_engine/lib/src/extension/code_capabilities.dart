/// The `code` extension — agent/verify/land as Capability impls + the linear
/// `code` formula (ADR-0008 D2 / M4-P1 §6, Track H).
///
/// The agent/verify/land OPINIONS migrate here from `default_extension.dart`'s
/// `AgentEffectSeed`/`VerifyEffectSeed`/`LandEffectSeed` — now opaque
/// [Capability] leaves (never a `Seed`), composed into a linear [Formula] whose
/// always-1-wide frontier reproduces P0 byte-for-byte (§6). The kernel/effect
/// core references none of this — only this extension does (the opinion-free
/// kernel invariant, ADR-0007 §1; a structural fence keeps it here).
///
/// This is the ADDITIVE migration: the new path runs the `code` formula via the
/// [buildCodeRegistry] registry + [FormulaResolver]. Swapping the live
/// `composeRunTree` wiring onto it + retiring the `WorkPhase`/`EffectSeed` path
/// is the live-arm/cleanup follow-on (the byte-for-byte behavior is proven here).
library;

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
/// the exact argv (model/effort/prompt) is a live-arm concern.
class AgentCapability extends ProcessCapability {
  /// Creates the agent capability.
  const AgentCapability();

  @override
  RuntimeConfig spawn(CapabilityContext ctx) => RuntimeConfig(
    workDir: ctx.workspaceDir,
    command: 'claude',
    args: const ['-p'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => _jobSignal(event);
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
    // Land not wired (an offline build) — no-op rather than touch real git.
    if (sc == null) return const Ok();

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

/// The git [SourceControl] impl over grid_runtime's [GitOps] + [PrOpener] (the
/// detail the engine knows only in CONCEPT — ADR-0008 D5; ships in the
/// extension). Null ops ⇒ this is simply not provided (the bundle's
/// `sourceControl` stays null and [LandCapability] no-ops).
class GitSourceControl implements SourceControl {
  /// Wraps [gitOps] (commit/push) + [prOpener] (PR).
  const GitSourceControl({required GitOps gitOps, required PrOpener prOpener})
    : _gitOps = gitOps,
      _prOpener = prOpener;

  final GitOps _gitOps;
  final PrOpener _prOpener;

  @override
  Future<void> commitAll({
    required String workspaceDir,
    required String message,
  }) => _gitOps.commitAll(workDir: workspaceDir, message: message);

  @override
  Future<void> push({
    required String workspaceDir,
    required String remote,
    required String branch,
  }) => _gitOps.pushSetUpstream(
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
    final result = await _prOpener.open(
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
