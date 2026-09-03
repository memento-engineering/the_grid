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
/// **Track 3 built.** `StationGitService` gives git-worktree-per-bead isolation:
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
/// allow-set with M2's `OwnsSubstations`), the `StationBeadWriter` chokepoint (fail-closed
/// ownership re-check before EVERY `create`/`update`/`close`/`delete`, bd-only,
/// `--actor grid-controller`), and the `RuntimeActuator` that consumes Track-2
/// `RuntimeEvent`s and writes session beads THROUGH the chokepoint — including
/// crash detection → restart / crash-loop quarantine.
library;

export 'src/models/grid_issue_types.dart'
    show GridIssueTypes, GridIssueTypeClassification;

// Track 0.1 — package scaffold marker (kept; the wiring asserts the package is
// on the path).
export 'src/runtime_scaffold.dart';

// Track 2 — the runtime seam + the subprocess provider.
export 'src/runtime/env_allowlist.dart'
    show AgentEnvAllowlist, systemEnvironment;
export 'src/runtime/incarnation_env.dart'
    show IncarnationEnv, newAttemptId, newInstanceToken;
export 'src/runtime/process_group.dart'
    show
        GroupTerminateResult,
        ProcessGroupController,
        SetSidCall,
        SystemProcessGroupController,
        establishStationProcessGroup,
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
        SessionOrphaned,
        SessionStarted;
export 'src/runtime/runtime_provider.dart'
    show RuntimeProvider, SessionAlreadyExists, SessionNotWritable;
export 'src/runtime/subprocess_provider.dart'
    show
        SpawnedProcess,
        SubprocessProvider,
        SubprocessSpawner,
        SystemSubprocessSpawner,
        kExitStatusFileEnv,
        kOrphanGrace,
        kReaperScript;

// Track 3 — git-worktree-per-bead isolation.
export 'src/git/git_runner.dart'
    show
        GitRunResult,
        GitRunner,
        SystemGitRunner,
        cleanGitEnvironment,
        gitEnvBlacklist;
export 'src/git/git_ops.dart'
    show
        GateOutcome,
        GitOps,
        GitWorktree,
        PrimaryCheckoutFreshness,
        PrimaryCheckoutState,
        gateBlocks,
        parseWorktreeList;
export 'src/git/station_git_service.dart'
    show
        BeadWorktree,
        StationGitService,
        LandResult,
        ReapOutcome,
        RootCheckout,
        WorktreeLayout,
        isStrictlyUnderDir;
export 'src/git/pr_opener.dart'
    show GhPrOpener, PrOpenFailure, PrOpener, PullRequestRef, PullRequestResult;
export 'src/git/stale_ancestor_guard.dart'
    show StaleAncestorRejection, validateAncestorWorktreesNotStale;

// Track 4 — lifecycle-as-beads + the single bd write chokepoint.
export 'src/lifecycle/bead_ownership.dart' show BeadOwnershipPredicate;
export 'src/lifecycle/station_bead_writer.dart'
    show
        StationBeadWriter,
        OperatorBeadTextField,
        OwnershipRefused,
        OwnershipGuardRefused,
        SessionClosedRefused,
        GateCloseCause,
        GateSweepSessionDisposition,
        GateAutoCloseReceipt,
        gateCloseCauseOf,
        sessionDispositionOfMetadata;
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

// Track 5 — the ready-work read seam (a second consumer of beads_dart's
// GraphEvent stream + readyBeads, alongside M2's ConvergenceSource).
export 'src/dispatch/ready_work_source.dart'
    show GridReadyWorkSource, ReadyWorkSource;

// Stage 1 (tg-zfek) — the slice of the record VOCABULARY the engine's
// derivation call sites have to name when they hand the recorder an
// observation (§2.3's cause/phase/disposition discriminators). Re-exported
// HERE so grid_engine reaches it over the edge it already has (grid_engine →
// grid_runtime, ADR-0002 D1) instead of growing a third inbound edge to the
// leaf package — the design allows exactly two (grid_runtime, grid_sdk).
//
// `StepState` is DELIBERATELY absent: grid_engine has one of its own, and a
// re-export would collide at every engine import site. That is exactly why
// the step family's recorder API is intent-named (`stepRunning`, `stepFailed`,
// …) instead of state-parameterized.
// `TrajectoryRecord` and `TrajectoryProvenance` are here for a second reason:
// they appear in `TrajectoryRecordSink`'s own method signature, so exporting
// the interface without them would ship an implementable-in-name-only API —
// no consumer outside this package could write the `enqueue` override.
export 'package:grid_trajectory/grid_trajectory.dart'
    show
        AdoptOutcome,
        LeaseDisposition,
        MintPhase,
        RoundRetireCause,
        TrajectoryProvenance,
        TrajectoryRecord;
// Stage 1 (tg-zfek) — the trajectory derivation layer: the ONLY code that
// names concrete Stage-1 record classes; enqueue-only into the harness's
// single writer (stage1-wiring §2).
export 'src/trajectory/station_trajectory_recorder.dart'
    show
        DerivedRecord,
        StationTrajectoryRecorder,
        TrajectoryRecordSink,
        TrajectoryRecorderFlare,
        TrajectoryRecorderStats,
        kDualReadRoundSummaryChannel,
        kExternalCloseUnknownReason,
        kLegacyAttemptCountKey,
        kObligationStuckChannel,
        kPreStage3GrantBasis,
        kReconcilerMintedAttemptBasis,
        kRecorderCacheBound,
        kRecorderMintedAttemptBasis,
        kRestartReconcilerBasis,
        kTeardownReplayUnknownReason,
        kTerminalReconcileBasis,
        kTickReapedBackfillBasis,
        kTickUnknownSettlementBasis,
        kUnownedSubstation,
        kUnownedSubstationBasis;
// Stage 1 (tg-zfek, chunk W7) — the tick's shadow-posture obligation set and
// its two real liveness surfaces. The harness composes these; nothing here
// writes bd or the filesystem (stage1-wiring §2.4).
export 'src/trajectory/stage1_obligations.dart'
    show
        LastActivityPoll,
        LivenessDetectorObligation,
        UnknownTerminalSettlementObligation,
        WorktreeReapedBackfillObligation,
        buildStage1ObligationQueries,
        kDefaultLivenessThreshold,
        kDefaultPulseCoalesce,
        kLivenessDetectorObligation,
        kObligationBatchSize,
        kPulseViaRuntime,
        kPulseViaWorktreeMtime,
        kUnknownTerminalSettlementObligation,
        kWorktreeReapedBackfillObligation;
export 'src/trajectory/stuck_obligation_accountant.dart'
    show
        StuckObligationAccountant,
        kStuckObligationThreshold,
        stationNoteSubject;
export 'src/trajectory/worktree_pulse_scanner.dart'
    show
        WorktreePulseScanner,
        WorktreeScan,
        WorktreeScanCost,
        kWorktreeStateDirName;
