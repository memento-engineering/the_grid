/// The opaque capability leaves + the pluggable Service seam (ADR-0008 D2/D5 /
/// M4-P1 §3, Track E).
///
/// The author implements a [Capability] (a [ProcessCapability] over a spawned
/// process, or a [ServiceCapability] over async collaborators) and NEVER a
/// `Seed`. A capability sees only the sandboxed [CapabilityContext] — no
/// `TreeContext`, no writer, no notifier, no `markNeedsRebuild` — so the four
/// derailment-invariants hold AT DEPTH by construction. The engine-private
/// `CapabilityHost` carrier owns the tree lifecycle (mount=spawn, dispose=kill);
/// the capability just describes what to run and how to read its events.
library;

import 'package:grid_runtime/grid_runtime.dart';

/// A leaf the engine mounts — either a [ProcessCapability] or a
/// [ServiceCapability]. Sealed so the carrier's dispatch is exhaustive; the two
/// flavors are open for an asset to implement.
sealed class Capability {
  const Capability();
}

/// A capability backed by a spawned, supervised process (generalizes P0's
/// `AgentEffectSeed`/`VerifyEffectSeed`). The carrier owns `provider.start/stop`;
/// the capability is PURE description.
abstract class ProcessCapability extends Capability {
  /// Const-constructible (capabilities are stateless description).
  const ProcessCapability();

  /// Describes the process to spawn for [ctx] — PURE; the host owns the actual
  /// `provider.start` (and layers the per-incarnation env over the config).
  RuntimeConfig spawn(CapabilityContext ctx);

  /// Maps a runtime [event] to a [StepSignal] (a job's clean exit → `complete`;
  /// a daemon's up-signal → `ready`; a crash → `failed`; anything else →
  /// `none`). The host writes the resulting cursor state through the chokepoint.
  StepSignal interpretEvent(RuntimeEvent event);

  /// Idempotent belt-and-braces cleanup on unmount (TEARDOWN-11/12) — e.g.
  /// `pkill` a detached side-process by token. Defaults to a no-op (the host's
  /// `provider.stop` kills the managed group).
  Future<void> teardown(CapabilityContext ctx) async {}
}

/// A capability backed by an async body driving [ServiceBundle] collaborators
/// (generalizes P0's `LandEffectSeed`: git/PR orchestration, the Burn
/// coordinator). No process lifecycle; its [run] resolves to a [StepOutcome].
abstract class ServiceCapability extends Capability {
  /// Const-constructible.
  const ServiceCapability();

  /// Runs the capability body for [ctx], resolving to its outcome. The host maps
  /// the outcome to a cursor write through the chokepoint.
  Future<StepOutcome> run(CapabilityContext ctx);

  /// Idempotent cleanup on unmount. Defaults to a no-op.
  Future<void> teardown(CapabilityContext ctx) async {}
}

/// What a runtime event means to a [ProcessCapability]. `ready` and `complete`
/// are POSITIVE TERMINALS (satisfy a `dependsOn`); `none` is "no cursor change".
enum StepSignal { none, ready, complete, failed }

/// The outcome of a [ServiceCapability.run].
sealed class StepOutcome {
  const StepOutcome();
}

/// The capability succeeded, optionally carrying a [payload] (e.g. a PR url) the
/// engine may record. Maps to `StepState.complete`.
class Ok extends StepOutcome {
  /// Creates a success, optionally carrying [payload].
  const Ok([this.payload]);

  /// An optional result payload (recorded on the session bead, never used as a
  /// pipeline signal).
  final Map<String, String>? payload;
}

/// The capability failed (routes to supervision). Maps to `StepState.failed`.
class Failed extends StepOutcome {
  /// Creates a failure with an optional [reason] (diagnostics).
  const Failed([this.reason = '']);

  /// A human-readable failure reason.
  final String reason;
}

/// A cooperative cancellation flag a [Capability] polls across async gaps — set
/// when the host unmounts. The engine never force-kills a `ServiceCapability`
/// body; the capability checks [isCancelled] and unwinds.
class CancelToken {
  bool _cancelled = false;

  /// Whether the owning host has unmounted (the capability should unwind).
  bool get isCancelled => _cancelled;

  /// Marks cancelled (called by the host on dispose).
  void cancel() => _cancelled = true;
}

/// The narrow, sandboxed projection a [Capability] leaf gets (M4-P1 §3): NO
/// `TreeContext`, NO writer, NO notifier, NO `markNeedsRebuild` — a read-only
/// slice. This is what holds invariants 1/2 at depth by construction.
class CapabilityContext {
  /// Bundles the step [params], the work [beadId], the [workspaceDir] the
  /// capability runs in (OQ-6: the stable home — was "worktree"), the [branch] /
  /// [baseBranch], the pluggable [services], the [cancel] token, and the
  /// restoration [logFile] seam (deferred).
  const CapabilityContext({
    required this.params,
    required this.beadId,
    required this.workspaceDir,
    required this.branch,
    required this.baseBranch,
    required this.services,
    required this.cancel,
    this.logFile,
  });

  /// The step's opaque params (from the `CapabilityStep`/`SubFormulaStep`).
  final Map<String, String> params;

  /// The work bead this capability serves.
  final String beadId;

  /// The stable home directory the capability runs in (the cwd default;
  /// per-spawn overridable via `RuntimeConfig.workingDirectory`). OQ-6: the
  /// engine concept is `workspace`; "git worktree" is the git `SourceControl`
  /// impl's way of provisioning it.
  final String workspaceDir;

  /// The branch the work is on (`grid/<beadId>`).
  final String branch;

  /// The base branch a land opens its PR against.
  final String baseBranch;

  /// The pluggable collaborators (source control, trust, transport).
  final ServiceBundle services;

  /// The cooperative cancellation token (set when the host unmounts).
  final CancelToken cancel;

  /// The durable log file for the deferred adopt-a-live-process seam (§11);
  /// null until restoration ships.
  final String? logFile;
}

/// The pluggable collaborators a [Capability] drives (ADR-0008 D5) — ONE
/// concrete bundle (genesis's exact-type inherited lookup can't resolve an
/// abstract `<SourceControl>`), provided stably above `Station`. Impls ship in
/// assets (Track H wires the git `SourceControl`).
class ServiceBundle {
  /// Creates a bundle of optional collaborators.
  const ServiceBundle({this.sourceControl, this.trust, this.transport});

  /// Source control (commit/push/PR) — today's git ops migrate IN (Track H).
  final SourceControl? sourceControl;

  /// Reserved (OQ-7) — local/reputation/ledger trust, distinct from
  /// `genesis_consent`. Designed-to-be-lifted; null in P1.
  final Trust? trust;

  /// Reserved — the outbound exploration sink (no inbound pipeline handle);
  /// null in P1.
  final ExplorationTransport? transport;
}

/// The first [Service] — commit/push/open-PR, abstracted so the engine knows it
/// in CONCEPT, not detail (the git impl ships in `station_grid_assets`, Track H).
/// Clean + dependency-free so a future genesis-shared home is a move, not a
/// rewrite (designed-to-be-lifted).
abstract interface class SourceControl {
  /// Commits all changes in [workspaceDir] with [message].
  Future<void> commitAll({required String workspaceDir, required String message});

  /// Pushes [branch] to [remote] from [workspaceDir], setting upstream.
  Future<void> push({
    required String workspaceDir,
    required String remote,
    required String branch,
  });

  /// Opens a PR for [branch] against [baseBranch]; returns the ref, or null on
  /// failure (an honest "did not complete" — never throws for a normal refusal).
  Future<PrRef?> openPr({
    required String workspaceDir,
    required String branch,
    required String baseBranch,
    required String title,
  });
}

/// A reference to an opened pull request.
class PrRef {
  /// Wraps the PR [url].
  const PrRef(this.url);

  /// The PR url.
  final String url;
}

/// Reserved trust abstraction (OQ-7) — local/reputation/ledger; designed to be
/// lifted to a genesis-shared home. No members in P1.
abstract interface class Trust {}

/// Reserved outbound exploration transport — an emit-only sink, never an inbound
/// pipeline handle (invariant 1). No members in P1.
abstract interface class ExplorationTransport {}
