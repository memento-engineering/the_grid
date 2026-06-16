# grid_runtime

M3 runtime providers — the layer that gives the_grid **hands**.

`grid_runtime` spawns and supervises a coding agent (a `claude` subprocess) per
ready bead, isolates each bead's work in a git worktree, tracks each session's
lifecycle **as a bead** (bd-only writes through the single write chokepoint,
`--actor grid-controller`, never SQL), and lands finished work as a pushed
branch / PR — **never an auto-merge**. It ports gc's `runtime.Provider` contract
(`gascity/internal/runtime/`) into Dart per **ADR-0004**, consuming
`grid_controller`'s ready-set seam and `grid_reconciler`'s actuator.

See `docs/adr/ADR-0004` (runtime providers, tmux first, tiered) and
`docs/M3-BUILD-ORDER.md` (the dependency-ordered tracks).

## Status — Tracks 2–5 built

The **runtime seam + the subprocess provider** are implemented (offline,
fakes-not-mocks; `dart analyze` clean, the offline suite green). The rest of the
surface lands across M3:

- **Track 2 (built)** — `RuntimeProvider` interface + `RuntimeConfig` /
  `RuntimeEvent` / `RuntimeCapabilities` value types + `SubprocessProvider` (the
  Friday dogfood default): **Futures for acts** (`start`/`stop`/`interrupt`),
  **Streams for observations** (sealed `RuntimeEvent` + live `output`), plus the
  point-in-time queries (`isRunning`/`processAlive`/`peek`/`listRunning`/
  `lastActivity`). `SubprocessProvider` spawns the agent **no-shell**, with
  `includeParentEnvironment:false` and an **explicit env allowlist** (forwards
  the agent's `CLAUDE_CODE_OAUTH_TOKEN`, drops `GC_DOLT_PASSWORD` and every other
  host secret), in a **new process group** (`ProcessStartMode.detachedWithStdio`)
  so `stop()` can SIGTERM→2s grace→SIGKILL the **whole tree** with the
  `pgid<=1`/self-group guard. Per-incarnation `GRID_SESSION_ID`/`GRID_BEAD_ID`/
  `GRID_INSTANCE_TOKEN`/`GRID_RUNTIME_EPOCH` are injected. **CUT (Track 2):** the
  inference-provider abstraction, gc's per-session Unix control socket, the
  `TmuxProvider` adapter (⊣ Track 1), attach/nudge.

  **Spawn-mode choice (`detachedWithStdio`), justified.** Dart exposes no
  `Setpgid`; `setsid` is absent on macOS and a `sh -c` wrapper does not start a
  new group. `detachedWithStdio` is the one mechanism that both `setsid()`s the
  child into a fresh session+group AND keeps stdio connected for the transcript.
  Its cost — `Process.exitCode` is unavailable for detached processes — is paid
  by polling liveness via the `ProcessGroupController` seam (the honest signal: a
  backgrounded grandchild can hold stdout open past the agent's exit). A real
  detached exit therefore surfaces as `RuntimeEvent.died`; a precise
  `RuntimeEvent.exited` with a code is emitted whenever the spawner can read one
  (the fake spawner / any non-detached path).
- **Track 3 (built)** — `GridGitService`: git-worktree-per-bead isolation +
  the three-gate fail-closed reaper + land-to-PR (ADR-0006 Decision 3). All git
  I/O runs through the injectable **`GitRunner`** seam (real impl
  `SystemGitRunner`; tests use the real `git` binary against temp repos, or a
  scripted fake for the probe-error paths). Two layers, copied from gc's rig
  model:
  - **Layer 1 — root-checkout registration** (`registerRootCheckout`): records
    a the_grid-OWNED clone path + the **default branch probed from
    `origin/HEAD`** (a verbatim port of gc's `ProbeDefaultBranch`,
    `internal/git/git.go:92-106`; never hardcodes `main`). It does **not**
    create the real `lenny-tgdog` clone — that is Nico's one-time out-of-band
    step (auto-provision is the gascity#1556 stale-ancestor hazard).
  - **Layer 2 — per-bead worktree** (`provisionWorktree`):
    `git worktree add -b grid/<beadId> <root>/.grid/worktrees/<rig>/<beadId> <base>`
    (mirrors gc's `.gc/worktrees/<rig>/<name>`,
    `internal/workdir/workdir.go:76-86`). The dir name **encodes the bead id**
    so `listBeadWorktrees` re-binds an orphaned worktree to its lifecycle bead
    on restart with no external state.

  **Ported verbatim — the load-bearing safety:** the **three-gate** pre-removal
  check (`reap` refuses if `HasUncommittedWork` OR `HasUnpushedCommits` OR
  `HasStashes`, **all fail-closed on probe error** — a `GateOutcome.probeError`
  blocks exactly like `present`; `git.go:134-213`), with `git worktree remove`
  run from the **root** repo, never inside the worktree; the **GIT_\* env
  blacklist** stripped on every exec by the runner seam (`git.go:285-301`); the
  **stale-ancestor guard** (`validateAncestorWorktreesNotStale`,
  `workdir.go:303-359`) before every `git worktree add`; and the **scope gate**
  (`isStrictlyUnderDir`) so the reaper can only ever act inside the worktrees
  root. **Land DIVERGES from gc** (no prior art): `land` commits on
  `grid/<beadId>` → `git push -u origin grid/<beadId>` → opens a PR via the
  injectable **`PrOpener`** seam → returns the `PullRequestRef` for the caller
  to record on the lifecycle bead. **Never auto-merges.** **CUT (Track 3):**
  per-bead retry-on-new-branch; an offline periodic reaper sweep; registry-
  removal-deletes-disk (registry removal ≠ disk deletion, mirror gc).
- **Track 4 (built)** — lifecycle-as-beads + the single `GridBeadWriter` bd
  write chokepoint. Three pieces:
  - **`session_state.dart`** — a Dart port of gc's session `state` transition
    table (`internal/session/state_machine.go:106-144`):
    `start_pending → spawning → active → {asleep, draining, quarantined,
    closed}`, with `close` legal from any non-none state (gc's `anyState`
    sentinel) and `restart` from `asleep`/`quarantined`/`draining`. A pure,
    total reducer (`transition` / `transitionOrNull` / `allowedCommands`),
    tested before any IO. `LifecycleState` is an extension type over the wire
    string (like `IssueType`) so a gc-written state the_grid does not model is
    preserved verbatim, never dropped (ADR-0000 A14).
  - **`BeadOwnershipPredicate`** — the bead-shaped ownership gate (ADR-0006
    Decision 1; ADR-0000 A32) the chokepoint and (Track 5) the dispatcher share.
    M2's `OwnsRigs.owns(Convergence)` reads `convergence.metadata.rig`, a key gc
    stamps only into convergence beads, so it is structurally uncallable on a
    plain `Bead`; this predicate derives a bead's rig from the **issue-id
    prefix** (primary) and/or `metadata.rig`. **The shared artifact with the M2
    actuator is the rig allow-set `Set<String>`, not the predicate object**
    (seeded `{tgdog}`, A35) so the two gates cannot drift. A no-rig/no-prefix
    bead is **not owned, fail-closed**.
  - **`GridBeadWriter`** — the single bd write chokepoint (ADR-0006 Decision 2)
    wrapping the M2 `BdCliService`. Before **every** `create` / `update
    --metadata` / `close` / `delete` it re-checks ownership fail-closed on the
    target rig and **refuses + logs loudly** ([`OwnershipRefused`]) any write
    whose rig is absent / not owned — the second line of defense behind the
    dispatch predicate (session/recovery writes never flow through a
    `Convergence`, so the `ReconcilerRuntime` convergence gate cannot cover
    them). `createSession` mints + stamps `metadata.rig` **from birth** (the M2
    `BdCliService.create` carries no `--metadata`, so the mint is `create` + a
    stamping merge `update`). `--actor grid-controller`, merge semantics (works
    on closed beads), `batch` only for grouped `close`+`dep`, **never SQL**,
    **never `bd show`** on this path.
  - **`RuntimeActuator`** — consumes Track-2 `RuntimeEvent`s and writes session
    beads **through the chokepoint**: a spawn mints the bead at `start_pending`;
    `SessionStarted`/`ActivityChanged` drive it to `active`; a clean `Exited(0)`
    parks it `asleep`; a crash (`Died` or non-zero `Exited`) trips the crash-loop
    machinery — under the threshold it sets `restart_requested` (a fresh restart,
    bead left **open**, gc `manager.go:867-879`), at/over the threshold it
    quarantines (`state=quarantined`, `quarantine_cycle`, `quarantined_until`, gc
    `lifecycle_transition.go:468-497`). Crash bookkeeping is in-memory (the live
    supervisor); the durable counters it writes mirror it. **CUT (Track 4):** the
    convergence `RecoveryAction` actuator (now Track 4b, off the Friday path).
- **Track 5 (built)** — `DispatchInteractor` (ready bead → spawn) + the
  `ReadyWorkSource` read seam. It attaches as a **SECOND consumer** of the same
  observable surface M2 uses (a `ReadyWorkSource` over `grid_controller`'s
  `GraphEvent` stream + `readyBeads`, mirroring the M2 `ConvergenceSource`) and
  does **not** go through reduce→gate→actuate. Two halves:
  - **Dispatch.** On `GraphEvent.readySetChanged.entered` (and a start-time
    reconcile of the current `readyBeads`), each entered id is resolved to its
    `Bead` and gated on the Track-4 `BeadOwnershipPredicate` (the shared
    `{tgdog}` allow-set). A **non-owned bead is observed read-only, NEVER
    dispatched and NEVER mutated** (`OwnsRigs` is structurally uncallable on a
    plain `Bead`, A32). On accept the pipeline runs
    `GridGitService.provisionWorktree` (Track 3) → `RuntimeProvider.start`
    (Track 2) → `RuntimeActuator.spawnSession` (Track 4, the session bead minted
    through the `GridBeadWriter` chokepoint). **Idempotent + single-flight per
    bead:** a `PerBeadQueue` (reused from the M2 runtime) serializes per
    work-bead id and a synchronous slot **reservation** is taken before the
    first `await`, so a re-fired ready event — even a burst racing the first
    spawn — never double-spawns and concurrent different-bead dispatches cannot
    over-commit the **max-in-flight cap**.
  - **Supervision.** It listens to the actuator's `CrashDecision` stream: a
    `RestartSession` re-spawns the same bead in its existing worktree (the
    session bead is left open); a `QuarantineSession` parks it (no respawn, no
    reap); a `SessionParked` (clean exit) drives the **removal trigger** — close
    the session bead through the chokepoint, then `GridGitService.reap`, which
    only removes the worktree once the three fail-closed gates pass (an
    unpushed/uncommitted/stashed worktree is refused and kept for the land step).
  - **`--dry-run`** is observe-only: no worktree, no spawn, no `bd` write — the
    safe default for the first live run (the live arm is Track 7 + ADR-0006's
    live gate). **CUT (Track 5):** the demand-spawned pool / backpressure beyond
    the max-in-flight cap (the full pool is M4).
- **Track 6** — the exploration-attach (`plugins`→`extensions`) wire-key fix.
- **Track 7** — `grid run` CLI + dogfood wiring (composes the Track-5
  dispatcher with the M2 `ReconcilerRuntime` + the chosen provider).

All Track-4 `bd` calls go through the `GridBeadWriter` chokepoint over the M2
`BdCliService`; the offline suite drives them with a **recording fake bd
runner** (records argv + stdin), asserting the exact `--actor grid-controller` +
metadata-merge commands, no SQL, no `bd show`, and the fail-closed refusal of a
wrong/absent rig. **No live state is touched.**

## Safety (CLAUDE.md, ADR-0003 Decision 6, ADR-0006)

- **Single writer per bead.** the_grid spawns/supervises/actuates only the
  disjoint, prefixed rig set it owns; dispatch and the bd write chokepoint share
  one rig allow-set so they cannot drift. Non-owned ready beads are observed
  read-only, never spawned, never mutated.
- **bd-only writes.** All session/lifecycle/recovery mutations flow through the
  one `GridBeadWriter` over the M2 `BdCliService` (`--actor grid-controller`).
  Never raw SQL; never `bd show` on a controller/re-query path; never touch
  `.beads/hooks/` (gc owns them).
- **Auth: flag-not-extract, explicit allowlist.** The agent OAuth token is an
  inherited env var on an allowlist — never on argv, never read/printed.
- **Tests use fakes**, not mocks; pure logic is tested before IO is wired.
  Process/worktree tests use temp git repos and stub commands, never live repos
  or the real agent.
