/// M3 runtime providers for the_grid — the layer that gives the_grid hands.
///
/// Ports gc's `runtime.Provider` contract (ADR-0004) into Dart, trimmed to
/// what M3 consumes: **Futures for acts** (`start`/`stop`/`interrupt`),
/// **Streams for observations** (a sealed `RuntimeEvent` stream + live session
/// output). A `SubprocessProvider` (the Friday dogfood default) spawns a
/// `claude` agent per ready bead in a git worktree, supervises it as a process
/// group, and tracks the session **as a the_grid-owned bead** through the
/// single bd write chokepoint (bd-only, `--actor grid-controller`, never SQL).
/// A `TmuxProvider` over the standalone `tmux` package is the gc-compatible
/// alternative. Layering follows predictable-flutter (Services → Repositories
/// → Interactors → View); see docs/adr/ADR-0002 + ADR-0004 and
/// docs/M3-BUILD-ORDER.md.
///
/// **Track 2 built.** The `RuntimeProvider` interface + `RuntimeConfig` /
/// `RuntimeEvent` / `RuntimeCapabilities` value types + the `SubprocessProvider`
/// impl (new-process-group spawn, explicit env allowlist, whole-tree kill) are
/// implemented here.
///
/// **Track 3 built.** `GridGitService` gives git-worktree-per-bead isolation:
/// Layer-1 root-checkout registration (probed default branch from
/// `origin/HEAD`), Layer-2 `git worktree add -b grid/<beadId>` under
/// `<root>/.grid/worktrees/<rig>/<beadId>`, the land step (commit → push → open
/// PR via the injectable `PrOpener`, never auto-merge), and the VERBATIM gc
/// safety: the three-gate fail-closed reaper, the GIT_* env blacklist on every
/// exec, and the stale-ancestor guard.
///
/// **Track 4 built.** Lifecycle-as-beads + the single bd write chokepoint: a
/// Dart port of gc's session `state` transition table (`session_state.dart`),
/// the `BeadOwnershipPredicate` (the bead-shaped ownership gate sharing the rig
/// allow-set with M2's `OwnsRigs`), the `GridBeadWriter` chokepoint (fail-closed
/// ownership re-check before EVERY `create`/`update`/`close`/`delete`, bd-only,
/// `--actor grid-controller`), and the `RuntimeActuator` that consumes Track-2
/// `RuntimeEvent`s and writes session beads THROUGH the chokepoint — including
/// crash detection → restart / crash-loop quarantine.
///
/// **Track 5 built.** The `DispatchInteractor` attaches as a SECOND consumer of
/// the same observable surface M2 uses (a `ReadyWorkSource` over
/// grid_controller's `GraphEvent` stream + `readyBeads`) and does NOT go
/// through reduce→gate→actuate. It gates dispatch on the Track-4
/// `BeadOwnershipPredicate` (the shared `{tgdog}` allow-set) — a non-owned bead
/// is observed read-only, never dispatched — and on accept runs
/// provision-worktree → provider.start → spawnSession, single-flight per bead
/// (a `PerBeadQueue` keyed by bead id, mirroring the M2 runtime) so a re-fired
/// ready event never double-spawns. On a `CrashDecision` it drives restart /
/// quarantine-park / close-then-reap.
library;

// Track 0.1 — package scaffold marker (kept; the wiring asserts the package is
// on the path).
export 'src/runtime_scaffold.dart';

// Track 2 — the runtime seam + the subprocess provider.
export 'src/runtime/env_allowlist.dart'
    show AgentEnvAllowlist, systemEnvironment;
export 'src/runtime/incarnation_env.dart'
    show IncarnationEnv, newInstanceToken;
export 'src/runtime/process_group.dart'
    show
        GroupTerminateResult,
        ProcessGroupController,
        SystemProcessGroupController,
        terminateGroup;
export 'src/runtime/runtime_config.dart'
    show Lifecycle, RuntimeCapabilities, RuntimeConfig;
export 'src/runtime/runtime_event.dart'
    show
        ActivityChanged,
        Died,
        Exited,
        Respawned,
        RuntimeEvent,
        SessionStarted;
export 'src/runtime/runtime_provider.dart'
    show RuntimeProvider, SessionAlreadyExists;
export 'src/runtime/subprocess_provider.dart'
    show
        SpawnedProcess,
        SubprocessProvider,
        SubprocessSpawner,
        SystemSubprocessSpawner;

// Track 3 — git-worktree-per-bead isolation.
export 'src/git/git_runner.dart'
    show
        GitRunResult,
        GitRunner,
        SystemGitRunner,
        cleanGitEnvironment,
        gitEnvBlacklist;
export 'src/git/git_ops.dart'
    show GateOutcome, GitOps, GitWorktree, gateBlocks, parseWorktreeList;
export 'src/git/grid_git_service.dart'
    show
        BeadWorktree,
        GridGitService,
        LandResult,
        ReapOutcome,
        RootCheckout,
        WorktreeLayout,
        isStrictlyUnderDir;
export 'src/git/pr_opener.dart'
    show
        GhPrOpener,
        PrOpenFailure,
        PrOpener,
        PullRequestRef,
        PullRequestResult;
export 'src/git/stale_ancestor_guard.dart'
    show StaleAncestorRejection, validateAncestorWorktreesNotStale;

// Track 4 — lifecycle-as-beads + the single bd write chokepoint.
export 'src/lifecycle/bead_ownership.dart' show BeadOwnershipPredicate;
export 'src/lifecycle/grid_bead_writer.dart'
    show GridBeadWriter, OwnershipRefused;
export 'src/lifecycle/runtime_actuator.dart'
    show
        CrashDecision,
        QuarantineSession,
        RestartSession,
        RuntimeActuator,
        SessionParked;
export 'src/lifecycle/session_state.dart'
    show
        IllegalLifecycleTransition,
        LifecycleCommand,
        LifecycleState,
        allowedCommands,
        transition,
        transitionOrNull;

// Track 5 — the DispatchInteractor (ready bead → spawn) + the ready-work seam.
export 'src/dispatch/dispatch_interactor.dart'
    show DispatchInteractor, DispatchRecord, DispatchRequest;
export 'src/dispatch/ready_work_source.dart'
    show GridReadyWorkSource, ReadyWorkSource;
