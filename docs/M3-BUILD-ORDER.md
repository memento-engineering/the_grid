# M3 build order — dependency-ordered tracks

Orchestration breakdown of **ADR-0004** (Accepted — runtime providers, tmux first, tiered)
plus the M3-specific decisions still pending in **ADR-0006** (Proposed — the dogfood rig +
live-write authorization). M3 gives the_grid **hands**: it spawns and supervises a Claude Code
subprocess per ready bead, tracks each session's lifecycle **as a bead** (bd-only writes,
`--actor grid-controller`), isolates each bead's work in a **git worktree**, and lands finished
work as a **pushed branch / PR** for Nico — never an auto-merge. The other half of the loop:
**leonard debugs the_grid's pure-Dart VM** over `ext.exploration.*` once the wire-key mismatch is
fixed. Tracks run in parallel where inputs allow; ⊣ marks a hard dependency. AI decisions made
en route: ADR-0000 amendments (A32+), never silent.

> **Track labeling note.** M3 numbers tracks **1–7 by build order** (the dependency spine reads top
> to bottom), where M2-BUILD-ORDER lettered its tracks A–I. This is a deliberate sibling-doc
> divergence: M3's value is the order, so the numbers *are* the order. Off-spine work keeps named
> tracks (Track I live shadow, `grid top`). DoD STATUS markers (✅/◐, as M2 carries) **fill in as
> tracks land** — nothing is built yet, so every criterion below is forward-looking.

**Conventions:** CLAUDE.md. **Source spec on disk** (gascity = the Go prior art, `~/development/com.gastownhall/gascity/`):

- **Runtime port:** `internal/runtime/tmux/` (tmux.go ~5.9k LOC + ~8.1k test LOC = the conformance
  oracle, ADR-0004 D5) and `internal/runtime/subprocess/` (subprocess.go, the process supervision
  pattern).
- **Worktree / auth / reaper prior art (TOP-LEVEL `internal/` packages, not under `internal/runtime/`):**
  `internal/git/git.go` (ProbeDefaultBranch, HasUncommittedWork/HasUnpushedCommits/HasStashes — the
  three gates), `internal/workdir/workdir.go` (`.gc/worktrees/<rig>/<name>` layout +
  ValidateAncestorWorktreesNotStale), `internal/processgroup/processgroup_unix.go` (Setpgid + the
  whole-tree SIGTERM→SIGKILL), `internal/processenv/provider.go` (the OAuth-token env allowlist), and
  `internal/session/{lifecycle.go,state_machine.go,lifecycle_transition.go}` (the lifecycle state
  machine). The bead-worktree reaper and rig registration live in
  `cmd/gc/{bead_worktree_reaper.go,session_worktree_prune.go,cmd_rig.go}`.

**Scope (ADR-0004 + settled decisions):** subprocess-first dispatch of a Claude Code agent per
ready bead, supervision, lifecycle-as-beads, git-worktree-per-bead isolation, and the
leonard-attach fix. A dedicated **inference-provider package is DEFERRED** (not designed, not
required for M3 — inference stays anthropic + swift-infer at the agent CLI level). Topology/city
config stays **M4** (ADR-0003 D1); M3 ports only the session half it needs to dispatch.

## The Friday dogfood loop (target 2026-06-19), stated concretely

Two halves, both must be green for M3 acceptance. **The Friday acceptance path is
`SubprocessProvider`-only** (DoD criterion 2; `--provider subprocess` is the dogfood default).
TmuxProvider + the full tmux Tier-1 surface are the gc-compatible *alternative* and are **off the
Friday critical path** (see the spine).

1. **the_grid BUILDS lenny.** `grid run --rig <tgdog-rig> --provider subprocess` is started against
   a the_grid-owned, **disjoint, prefixed** set of lenny work beads (ADR-0006). For each *owned*
   ready bead — owned per the **new `BeadOwnershipPredicate`** that shares the rig allow-set with M2's
   `OwnsRigs` (Track 5; ADR-0006 Decision 1) — the DispatchInteractor allocates a git worktree under
   the the_grid-owned lenny root checkout in `/Users/nico/development/engineering.memento/`, spawns a
   `claude` subprocess in that worktree (auth via an **inherited env var on an explicit allowlist**,
   never argv), supervises it (process-group kill on stop, crash → quarantine/requeue), tracks the
   session **as a the_grid-owned bead** through the single **bd write chokepoint** (Track 4;
   ADR-0006 Decision 2), and on completion commits → `git push -u origin grid/<beadId>` → opens a PR.
   **Nothing auto-merges to lenny main.** This half **does not** exercise gc-style convergence
   recovery — it spawns agents on work beads and tracks session lifecycle beads only.
2. **leonard DEBUGS the_grid's Dart VM.** the_grid runs as a pure-Dart process under
   `--enable-vm-service`; stock `leonard_cli --vm-uri ws://… --extensions grid --goal '…'` attaches
   over `ext.exploration.*` (the prefix is already aligned), the handshake returns the `grid`
   namespace with its 5 tools, and `pullObservation` carries live grid state — **after** the
   `plugins`→`extensions` wire-key rename ships (Track 6). leonard executes at least one grid tool
   (e.g. `grid.ready`).

Acceptance proves the_grid can *do real work it dispatches* and *be debugged by lenny's debugger* —
the gc-replacement dogfood rung on the fs adoption ladder (drive-one-rig; M4-SCOPING).

## Track 0 — serial preconditions

1. **`grid_runtime` scaffold + standalone `tmux` scaffold**: two new pubspecs added to the root pub
   workspace + melos. `tmux` has **zero grid dependencies** (ADR-0002, pub.dev candidate);
   `grid_runtime` depends on `grid_controller` (for the bd-write seam + `GraphEvent` stream) +
   `tmux`. Green: `melos bootstrap` + `dart analyze`.
2. **ADR-0006 ratification gate** — the live dogfood **writes** are blocked until Nico ratifies
   ADR-0006 (rig prefix, the new bead-ownership axis, live-write authorization scope, land/isolation
   policy, OAuth stance) and confirms the open decisions below. Tracks 1–6 **build and test offline**
   with no live writes regardless; Track 7's live arming is what waits on this gate. (Mirrors M2's
   "code green, live shadow gated" split — A29.)

## Parallel tracks (after Track 0.1)

- **Track 1 — standalone `tmux` package** ⊣ 0.1 *(pure, fakeable; the zero-dep transport — NOT on the
  Friday critical path; the SubprocessProvider dogfood needs only Track 2)*:
  Port gc's argv-only tmux client (`gascity/internal/runtime/tmux/tmux.go`) into a Dart package
  with the gc architecture: a fakeable **`TmuxExecutor`** seam (the only thing that shells out;
  mirrors gc's `executor` interface — the entire 87KB gc test file uses a fake), a `run`/`runCtx`
  argv builder that prepends `-u` then `-L <socket>` and wraps **every** call in a per-call timeout
  (gc's load-bearing 30s cap, `tmux.go:182-212,277-294`), and a `wrapTmuxError` mapping stderr
  substrings → sealed errors `TmuxNoServer`/`TmuxSessionExists`/`TmuxSessionNotFound` with the
  **absent-as-not-error** caller convention (has-session→false, list→empty; `tmux.go:297-320`).
  **Tier-1 verbs (ADR-0004 D3) — the minimum the dogfood-alternative needs:** `newSession` (always
  `-d`, `-c <workdir>`, `-e KEY=VAL` env, command-as-initial-process; `tmux.go:366-475`),
  `killSession`, `hasSession` (exact `-t =name`), `listSessions`, `capturePane` (`-p -t <session>:^.0
  -S -<N>` — first-pane addressing robust to `base-index`, `tmux.go:2260`), `displayMessage` probes
  (`#{pane_pid}`/`#{pane_current_command}`/`#{pane_dead}`/`#{session_attached}`/`#{pane_in_mode}`,
  `tmux.go:1915-1973`), `sendKeys` literal `-l` (payload as one argv element, **no shell quoting**) +
  separate `Enter` with the "not in a mode" retry loop (exp backoff 500ms→2s). **v1 stream surfaces
  (ADR-0004 D2):** `paneOutput(target)` = `mkfifo` + `pipe-pane -o 'cat >> fifo'` read as a Dart
  stream (push, no capture-pane polling); `events()` = poll+diff of `list-sessions`/`list-panes` on
  our isolated socket (~1s, cheap because the socket is ours — same sufficient-signal→authoritative-
  diff as ADR-0001 D5). **Session-name validation `^[a-zA-Z0-9_-]+$`** + bead-id sanitize (`/`,`.`,`:`
  → `--`) before any target use. **Inputs:** gc tmux source + 8.1k-LOC test suite. **Outputs:** the
  `tmux` package + a `FakeTmuxExecutor` (recorded-args, canned stdout/exit). **DoD:** Tier-1 verbs +
  stream surfaces pass offline against the fake; the integration tier (see Tier-1.5) creates/probes/
  kills a real session on an isolated socket and never touches the developer's tmux.
  **Moved to Tier-1.5 (post-Friday, off the dogfood critical path — these are tmux robustness, not
  spawn-correctness):** the verbatim **long-input load-buffer/paste-buffer/delete-buffer fallback**
  for prompts past ~4KB (`tmux.go:1496-1554`), the **named-socket clobber guard** (`has-session
  -t =<dead>` probe + `TmuxServerDegraded` refuse-on-timeout, `tmux.go:322-363` — only relevant once
  `-L grid-<hash>` isolation is in use), and the `tmux -V`-guarded **integration tier** porting gc's
  3-layer `tmuxtest/guard.go` cleanup with pre/post orphan sweeps. **CUT to Tier-2/3** (sequenced by
  observed failure, not built up front): copy-mode probe+cancel, nudge mutex, poke-activity
  discounting, WakePane resize, find-agent-pane process-tree match, respawn-pane, tmux-hooks push
  upgrade for `events()`, and the full kill hygiene ladder.

- **Track 2 — `RuntimeProvider` + `SubprocessProvider`** ⊣ 0.1 *(the runtime seam; ADR-0004 D1 — the
  SubprocessProvider half is the Friday critical path and depends ONLY on the scaffold, not on Track
  1; the `TmuxProvider` adapter half ⊣ 1)*:
  Define the Dart `RuntimeProvider` interface ported from gc's `runtime.Provider`
  (`internal/runtime/runtime.go:107,460`), trimmed to M3 — **Futures for acts** (`start(name,
  RuntimeConfig)`, `stop`, `interrupt`), **Streams for observations** (`events` = sealed
  `RuntimeEvent` SessionStarted/Exited/Died/Respawned/ActivityChanged; `output(name)` = live
  transcript), plus the cheap point-in-time queries (`isRunning`/`processAlive`/`peek`/`listRunning`/
  `lastActivity`) and a `RuntimeCapabilities` record so providers degrade explicitly. `RuntimeConfig`
  mirrors gc's `Config` (WorkDir = the per-bead worktree, Command, Lifecycle long-lived-vs-one-turn,
  **Env map** carrying the inherited agent token, startup hints). **`SubprocessProvider`** is the
  dogfood-default impl: port the in-tree `SystemProcessRunner` pattern
  (`grid_reconciler/lib/src/gates/process_runner.dart:147-254` — no-shell `Process.start`,
  deadline→SIGKILL, `CancellationToken`) and **keep `includeParentEnvironment:false`**. The env policy
  is NOT inverted to forward the whole parent env: the child gets **only an explicit allowlist**
  mirroring gc's `processenv` map (`internal/processenv/provider.go:98-126` — HOME/USER/LOGNAME/
  CLAUDE_CONFIG_DIR/XDG_*/`CLAUDE_CODE_OAUTH_TOKEN`/…), so the agent token is forwarded but
  `GC_DOLT_PASSWORD` and other host secrets are **never leaked** into the agent child. Add long-lived
  streamed output (don't capture the controller pipe; route stdout/stderr to a per-bead log file or
  `/dev/null` and read Claude's native `~/.claude` session JSONL keyed by the injected session id, per
  gc `internal/runtime/subprocess/transcript` discovery). Spawn in a **new process group** (gc
  `internal/processgroup/processgroup_unix.go:46-90` Setpgid; in Dart via
  `ProcessStartMode.detachedWithStdio` or a small `setsid`/`sh -c` wrapper — see open question) so
  `stop()` can SIGTERM→2s grace→SIGKILL the **whole tree** (incl. the pgid≤1/self-group guard). Inject
  per-incarnation env `GRID_SESSION_ID`/`GRID_BEAD_ID`/`GRID_INSTANCE_TOKEN` (random fence)/
  `GRID_RUNTIME_EPOCH` (gc `internal/session/lifecycle.go:30-67`). **`TmuxProvider`** is a thin adapter
  over the Track-1 `tmux` package (attach/survival come free; agent token via tmux `-e`, **not**
  argv) — built when Track 1 lands, not required for Friday. **Agent invocation contract:** executable
  `claude`; args = permission flag (`--dangerously-skip-permissions` or a pre-granted
  `--permission-mode`), optional `--model`/`--effort`, `-p` for non-interactive print mode, + the
  bead's prompt (positional or prompt-file for long prompts) — referenced from gc
  `worker/builtin/profiles.go:89-155`, **not** the 16-provider catalog. **DoD (Tier-1 MVP gate, Friday
  critical path):** dispatch a real `claude` subprocess into a worktree, feed a prompt, stream output,
  observe death as a `RuntimeEvent`, kill the whole group cleanly; a test asserts the child env
  contains the agent token allowlist entries and **does not** contain `GC_DOLT_PASSWORD`. **CUT:**
  inference-provider abstraction (settled-deferred); gc's per-session Unix control socket (an
  in-process registry holding Process handles suffices for Tier-1); attach/nudge semantics beyond what
  `TmuxProvider` gives free.

- **Track 3 — git-worktree-per-bead isolation** ⊣ 0.1 *(new ground vs ADR-0004 → ADR-0006)*:
  A `GridGitService` in `grid_runtime` (do the git ops directly — the_grid is subprocess-first with
  no t3 daemon; reference only gc's RPC **param shape** cwd/branch/newBranch/path, not its transport).
  **Two layers, copied from gc's rig model:** Layer 1 = a the_grid-OWNED **root checkout** of lenny
  under `/Users/nico/development/engineering.memento/` (a real clone with `origin` set, registered
  once — analogous to a gc rig, *not* a worktree; default branch recorded by porting gc's
  `ProbeDefaultBranch` from `origin/HEAD`, `internal/git/git.go:92-133`). Layer 2 = per-bead
  `git worktree add -b grid/<beadId> <root>/.grid/worktrees/<rig>/<beadId> <baseBranch>` (mirror gc's
  `.gc/worktrees/<rig>/<name>` layout, `internal/workdir/workdir.go:76-86`, so the dir name encodes
  the bead id and a split-on-dash recovers it for restart reconciliation, gc
  `cmd/gc/bead_worktree_reaper.go:157-173`). **Port verbatim — the load-bearing safety:** (a) the
  **three-gate pre-removal check** — refuse to remove a worktree if `HasUncommittedWork` OR
  `HasUnpushedCommits` OR `HasStashes`, **all fail-closed on probe error**
  (`internal/git/git.go:134-213`); run `git worktree remove` from the **root** repo, never from inside
  the worktree; (b) the **GIT_* env blacklist** (strip `GIT_DIR`/`GIT_WORK_TREE`/`GIT_COMMON_DIR`/…
  before every git exec — the_grid is itself a git repo invoked from melos/hooks); (c) the
  **stale-ancestor guard** (`ValidateAncestorWorktreesNotStale`, `internal/workdir/workdir.go:303-359`
  — nested checkouts under engineering.memento reproduce gascity#1556). **DIVERGE from gc — the land
  step (NEW, no gc prior art):** on session success, commit on `grid/<beadId>` → `git push -u origin
  grid/<beadId>` → `gh pr create` → record the PR on the lifecycle bead. After push,
  `HasUnpushedCommits` is false, so the existing three-gate reaper then considers the worktree safe to
  remove — push and cleanup compose cleanly. **Removal trigger (DIVERGE):** the_grid has no gc drain
  protocol; reap a worktree only when the **lifecycle bead is closed AND the branch is pushed**
  (HasUnpushedCommits==false), then `git worktree remove` after the three gates pass. **Inputs:** the
  registered root checkout path (open decision), the rig prefix (ADR-0006). **Outputs:**
  `GridGitService` (provision/list/reap) + worktree-path/branch recorded on the lifecycle bead's
  metadata via the bd chokepoint. **DoD:** allocate a worktree on a fresh branch off the probed
  default, push-to-PR on success, and the reaper provably refuses to delete a worktree with
  uncommitted/unpushed/stashed work (fail-closed tests). **CUT:** per-bead retry-on-new-branch (one
  worktree per bead); offline periodic reaper sweep (inline reap at finish suffices for Tier-1);
  registry-removal-deletes-disk (mirror gc: registry removal ≠ disk deletion).

- **Track 4 — lifecycle-as-beads + the bd write chokepoint** ⊣ 2, grid_controller *(reuses the M2
  bd-only writer; this is the Friday-required half of the old Track 4)*:
  Model a `state` metadata field on the_grid-owned **session bead** driven by a Dart port of gc's
  transition table (`internal/session/state_machine.go:106-144`): `start_pending → spawning → active →
  {idle/asleep, draining, quarantined, closed}`. The read-back already exists — M1's `AgentSession`
  projection over `session`-typed beads (`grid_controller/.../projections/agent_session.dart:86-138`;
  `SessionState {open,closed}` from bead STATUS; gc's finer lifecycle string preserved verbatim on
  `metadata.state`, A14).
  **The single bd write chokepoint (ADR-0006 Decision 2; NEW — the second line of defense).** All
  the_grid-owned bead writes — session create/update/close **and** every recovery write — flow through
  one `GridBeadWriter` wrapping the M2 `BdCliService`. Before **every** `create`/`update --metadata`/
  `close`/`delete`, the chokepoint **re-checks ownership fail-closed on the bead/rig being written**
  using the shared rig allow-set (the same `Set<String>` Track 5's `BeadOwnershipPredicate` and M2's
  `OwnsRigs` consume; ADR-0006 Decision 1): it asserts the target bead carries the owned rig marker
  (`metadata.rig == <tgdog-rig>`, or the prefix axis Nico confirms) and **refuses + logs loudly** any
  write whose target rig is absent or not in the allow-set. This mirrors how `ReconcilerRuntime` gates
  convergence actuation on `_ownership.owns(convergence)` — but because session/recovery writes never
  flow through a `Convergence`, the convergence gate cannot cover them, so this chokepoint is the gate
  that fires for them. **Every minted session bead carries the owned rig marker from birth** (the
  `bd create` sets `metadata.rig`/the owned prefix), so the chokepoint can assert it on the very first
  write. `--actor grid-controller`, merge semantics, grouped via `batch` only for incidental
  `close`+`dep` (NEVER SQL, NEVER `bd show` on a controller path, A16/A26). Crash detection + restart:
  an active bead with no live process → restart; repeated crashes trip a **crash-loop quarantine**
  (`state=quarantined`, `quarantine_cycle`, `quarantined_until`) and a fresh restart sets
  `restart_requested` rather than closing the bead (gc
  `internal/session/lifecycle_transition.go:468-497`). **Inputs:** Track-2 `RuntimeEvent` stream; the
  M2 `Actuator`/`BdActuator`; the shared rig allow-set. **Outputs:** a `RuntimeActuator` (or extended
  `Actuator`) writing session beads **through `GridBeadWriter`**. **DoD:** a spawn writes a session
  bead and its `state` transitions on start/activity/exit through bd-only writes; a crash
  quarantines+requeues; **a session-bead write with a wrong or absent rig is refused by the chokepoint
  (fail-closed test).** **CUT:** the convergence RecoveryAction actuator (now **Track 4b**, off the
  Friday critical path); the inference-/pool-/city-config materialization, skill catalogs, overlay
  staging, ACP/T3 transports (reference only).

- **Track 4b — convergence RecoveryAction actuator (A27 gap)** ⊣ 4 *(OFF the Friday critical path —
  required only if/when the_grid drives a CONVERGENCE on the owned rig, which the session-spawn
  dogfood does not)*:
  The Friday dogfood spawns agents on lenny **work** beads and tracks **session** lifecycle beads; it
  never pours convergence wisps or runs the convergence recovery paths, so the A27 recovery actuator
  is **not** exercised by either half of the acceptance loop. Build it here, alongside Track I, so the
  owned rig is convergence-recovery-ready, but **do not let it gate Friday.** Walk
  `RecoveryAction.*Writes` (adopt/pour-wisp-1, partial-creation terminate, terminated-but-open close,
  marker repair) through the **same `GridBeadWriter` chokepoint** (`update --metadata`/`delete`/
  `close`), respecting the M2 write-ordering + idempotency invariants — never a second writer. The
  chokepoint **refuses any `RecoveryAction` whose target convergence is not owned** (fail-closed),
  giving the recovery path the same ownership re-check as session writes. **Outputs:** a
  `RecoveryActuator`. **DoD:** the recovery actuator bd-executes every `RecoveryAction` shape offline
  against a fake bd; **a RecoveryAction whose convergence is not in the owned allow-set is refused.**

- **Track 5 — DispatchInteractor (ready bead → spawn)** ⊣ 2, 3, 4 *(the ready-set→spawn glue)*:
  A `DispatchInteractor` in `grid_runtime` that attaches as a **SECOND consumer** of the same
  observable surface M2 uses (it does **not** go through reduce→gate→actuate). It subscribes to
  `GridControllerRuntime.events` (filter `GraphEvent.readySetChanged.entered`,
  `grid_controller/.../diff/graph_event.dart:59`) and/or polls `runtime.readyBeads` (which returns
  `List<Bead>`, `beads_repository.dart:54`).
  **The ownership gate for dispatch is a NEW predicate, not a reuse of `OwnsRigs(Convergence)`
  (ADR-0006 Decision 1; A32).** A ready **work** bead is a plain `Bead` with a free-form `metadata`
  map and **no `convergence.rig` key** — that key is stamped by gc's `withEventRig` only into
  convergence beads, and `OwnsRigs.owns()` reads exactly `convergence.metadata.rig`
  (`ownership.dart:51`). So `OwnsRigs` **cannot be called on a `Bead`** and the "same code, second
  call site" claim does not hold. Instead define a `BeadOwnershipPredicate` / `OwnsBead.owns(Bead)`
  that derives the bead's rig from the **same axis the dogfood rig actually uses** — issue-id prefix
  and/or a `metadata.rig`/label, per **ADR-0002 D2** ("issue prefix partitions rigs… labels drive rig
  scoping"; the exact axis is an open decision for Nico) — and gate dispatch on it. **The shared
  artifact between dispatch and the M2 actuator is the rig allow-set `Set<String>`, not the
  predicate object:** `OwnsRigs(Convergence)` governs the convergence **actuator** and
  `BeadOwnershipPredicate(Bead)` governs **dispatch**, and both are constructed from the **identical
  allow-set** so they cannot drift. A no-rig / no-prefix bead is **not-owned, fail-closed**. On
  accept: allocate a worktree (Track 3) → `provider.start(...)` (Track 2) → write the session bead via
  the Track-4 chokepoint. **Idempotent + single-flight per bead:** mirror M2's `PerBeadQueue` (a
  dedup/mutex keyed by bead id) so a re-fired ready event never double-spawns. On
  `RuntimeEvent.exited`: write the metadata transition / close the session bead and trigger the land
  step. **Inputs:** the M1 ready-set seam + the shared ownership allow-set (ADR-0006). **Outputs:** the
  dispatcher + the `BeadOwnershipPredicate` + a narrow `ReadyWorkSource` read seam (fakeable, mirroring
  M2's `ConvergenceSource` pattern). **DoD:** an owned-rig ready bead spawns exactly one agent in a
  worktree with a session bead; **a ready bead whose prefix/label is NOT the owned rig is observed
  read-only and never dispatched (a test mirroring the existing `OwnsRigs` unit tests);** a re-fired
  event does not double-spawn. **CUT:** demand-spawned pool / backpressure model beyond a max-in-flight
  cap (defer the full pool to M4).

- **Track 6 — exploration-attach fix (leonard truly attaches)** ⊣ 0.1 *(self-contained, entirely
  in the_grid; the prompt's required explicit track)*:
  The mismatch is a precise **wire KEY-NAME** rename, **not** a prefix or method-name problem — the
  `ext.exploration.*` prefix and the `core.handshake`/`core.get_stable_observation`/`<ns>.<tool>`
  method names and protocol version `'1'` are **already aligned** with leonard main. lenny's 0.1.0
  rebrand renamed the serialized map `plugins`→`extensions`; the_grid's host still emits `plugins`,
  and leonard's reader reads **only** `extensions` with **no fallback** — so leonard attaches to the
  VM but sees zero extensions and empty grid state. **Edits, all in the_grid:** (1)
  `grid_exploration_host.dart:46` handshake — rename `'plugins'`→`'extensions'` (keep each entry's
  `{namespace, tools}`; drop the unread `pluginCount`); (2) `grid_exploration_host.dart:64`
  observation — rename `'plugins': {ns: observe()}`→`'extensions': {ns: observe()}` (leave the
  `value` envelope, `semantics:[]`, `routes:[]`, `stability` as-is — all protocol-correct); (3)
  centralize as `kExtensionsKey` in `grid_exploration_protocol.dart` (mirrors `kExplorationPrefix`)
  and fix the `plugins.grid` doc comments; (4) **lockstep** — `grid_devtools/.../grid_exploration_
  client.dart:70` reads `json['plugins']` and must move too (+ rebuild the compiled DevTools
  `main.dart.js`), else the_grid's own panel breaks; (5) flip the the_grid tests asserting the old key
  (`grid_exploration/test/vm_service_attach_test.dart`, `grid_exploration_host_test.dart`,
  `tool/criterion3_attach.dart`).
  **Ratified-doc note (no silent edit).** ADR-0001 **Decision 6 is RATIFIED** and documents the wire
  shape as `plugins: [{namespace, tools}]` with "grid state under `plugins.grid`" (lines 64-65).
  Renaming the host output to `extensions` makes the code emit a shape ADR-0001 D6 no longer describes.
  Per the CLAUDE.md process rule we **do not edit ADR-0001 to match** — the rename is recorded as
  **ADR-0000 amendment A33** (converging onto leonard 0.1.0's published `extensions` read contract, no
  protocol-version bump), and ADR-0001 D6's documented key (`plugins`/`plugins.grid`) gets a **one-line
  amendment upon ratification by Nico**, not before. **No leonard change, no exploration_contract
  change, no protocol version bump.** **Inputs:** leonard main's read contract
  (`leonard_agent/.../vm_service_client.dart:114`, `observation/models.dart:52`). **Outputs:** the
  renamed host + DevTools client + flipped tests + a **cross-repo conformance fixture** (one real
  leonard handshake+observation parse against a live the_grid VM, pinned — mirrors the M2 codec-
  fidelity fixture discipline). **DoD (acceptance, the cross-process analog of the in-process
  `vm_service_attach_test`):** run the_grid under `--enable-vm-service` with `register()` called; point
  stock `leonard_cli --vm-uri ws://… --extensions grid --goal '…'` at it; PASS = (a) handshake
  `extensions` contains `namespace=='grid'` with its 5 tools; (b) `pullObservation` yields
  `extensions['grid'].data` with `beadCount`/`readyCount`/`readyBeads`; (c) leonard executes
  `grid.ready` and gets `{ok:true,…}`. **CUT:** any genesis-Perception observation shape (leonard's
  read path is a flat bare map, no `genesis_perception` dep; A30/A31 keep genesis at the render edge).

- **Track 7 — `grid run` CLI + dogfood wiring** ⊣ 2, 4, 5, 6; live-arm ⊣ 0.2 *(the composition)*:
  A new `grid run` subcommand in `grid_cli/bin/grid.dart` (today only `watch`+`demo` are registered).
  It composes what `runWatch` already does (workspace discover → `GridRuntimeFactory.build` →
  `GridExplorationHost.register()` → `runtime.start`, `grid_cli/.../watch_command.dart:38-76`) **plus**
  the M2 `ReconcilerRuntime` (`GridConvergenceSource` + `BdActuator` + `GateEvaluator` + `OwnsRigs`)
  **plus** the Track-5 `DispatchInteractor` + chosen `RuntimeProvider`. `grid_cli` gains deps on
  `grid_reconciler` and `grid_runtime`. Flags: `--rig`/`--owner` (the ownership allow-set — feeds
  **both** `OwnsRigs` and the `BeadOwnershipPredicate`, one source of truth),
  `--provider tmux|subprocess` (default `subprocess` for the dogfood), `--root` (worktree root under
  engineering.memento), `--dry-run` (observe-only, no writes/no spawns — the safe default for the
  first run). **Inputs:** ADR-0006 ratified (for the live writing arm) + all upstream tracks.
  **Outputs:** `grid run`; the green dogfood loop. **DoD = the M3 acceptance loop** (see "Definition
  of done" below). **CUT:** the `grid top` genesis-TUI inspector (A31 — parallel, off the critical
  path; see below).

## Tracks explicitly OFF the Tier-1 / Friday critical path (in M3 but parallel / after)

- **Track 4b convergence RecoveryAction actuator** — see Track 4b above (the A27 gap; required only
  for a live owned-rig **convergence**, which the Friday dogfood does not drive).
- **tmux Tier-1.5 + TmuxProvider** — see Track 1's Tier-1.5 bucket (long-input fallback, clobber
  guard, integration cleanup) and Track 2's `TmuxProvider` adapter. The Friday dogfood is
  SubprocessProvider-only; these make the gc-compatible path ship but do not gate acceptance.
- **Track I live shadow (A29 carry).** The M2 codec-fidelity half is closed offline vs real gc
  bytes; the **live-traffic diff** needs gc driving ≥1 convergence on a the_grid-owned disjoint rig
  (gc writes, the_grid reads **strictly read-only**). It rides ADR-0006's owned-rig authorization +
  `GC_DOLT_PASSWORD` and is **independent of the build-lenny half** — it does not gate the Friday
  dogfood acceptance (see open decisions). Author a convergence formula+gate, bind the rig, diff.
- **Track grid_tui / `grid top` (A31, future ADR-0005).** A genesis-adoption spike: a bead/
  convergence inspector on `genesis_typesetting` + `genesis_tree` drawing into a tmux pane
  `grid_runtime` supervises. Depends on `grid_runtime` existing but is **not** on the
  build-lenny + leonard-debugs-grid critical path; it is its own ADR-0005, properly M3-surface.

## Dependency spine

**The Friday critical path is `0.1 → 2(Subprocess) → {3,4} → 5 → 7`**, with `6` parallel from 0.1.
Track 1 (tmux), Track 2's `TmuxProvider` half, Track 4b (recovery actuator), Track I, and `grid top`
are all parallel/after and **do not gate Friday**.

```
                 ┌─ 2(SubprocessProvider) ─┬─ 4 (lifecycle + bd write chokepoint) ─┐
0.1 ─────────────┤   [Friday critical path]└─ 3 (worktree isolation) ──────────────┼─ 5 (Dispatch) ─ 7 (grid run)
     │           └─ 6 (exploration-attach fix) ───────────────────────────────────────────────────────────┘
     │
     ├─ 1 (tmux Tier-1) ── 2(TmuxProvider adapter) ·· [parallel; NOT Friday-required]
     ├─ 4b (recovery actuator) ·· ⊣ 4 [parallel; needed only for a live owned-rig convergence]
     └─ tmux Tier-1.5 (long-input, clobber guard, integration cleanup) ·· [post-Friday]
0.2 (ADR-0006 ratified) ──────────────── live-arm of 7 + Track I live shadow
```

## What is explicitly CUT from the Tier-1 MVP

- **tmux long-input fallback + clobber guard + integration cleanup** → Tier-1.5, post-Friday (above).
- **tmux Tier 2 + Tier 3** (ADR-0004 D3): copy-mode probe/cancel, nudge mutex+lock, paste-buffer
  >8KB beyond the basic long-input fallback, poke-activity discounting, WakePane SIGWINCH,
  find-agent-pane process-tree match, respawn-pane, tmux-hooks push for `events()`, and the full
  reparented-orphan kill hygiene ladder. Sequenced by **observed** failure, gc's 8.1k-LOC suite as
  the map. (Tier-1 supervision uses single-pane sessions + the basic process-group kill.)
- The five ADR-0004 **deferred** TUI features: approval-prompt detect/respond, startup-dialog
  dismissal, Gemini turn-rewind / Codex abort markers, state caching, themes. (Dogfood agents run in
  a **pre-granted-permissions** mode so no approval prompts appear — see open decisions.)
- **Inference-provider package** — settled-deferred; not designed, not required.
- **The convergence RecoveryAction actuator (A27)** off the Friday critical path — Track 4b.
- gc's **city/agent/pool/rig config** model, skill catalogs, overlay materialization, ACP/k8s/cloud
  providers, the per-session Unix control socket, native-transcript normalization stack — reference
  only.
- **Demand-spawned pool / backpressure** beyond a max-in-flight cap — defer the full pool to M4.
- **Topology reconciliation** — M4 (ADR-0003 D1); M3 ports only the session half it dispatches.
- **`grid top` genesis-TUI** and the **Track I live shadow** — in M3 but off the Friday critical
  path (above).

## Definition of done (ADR-0004 + ADR-0006 + PDR §5 M3 row)

> STATUS markers (✅ done / ◐ partial) — **filled in 2026-06-15: the M3 build is delivered to the
> live-arm threshold.** The offline workspace is GREEN — **951 tests pass, 0 failures, `melos analyze`
> clean** across all 6 packages (`grid_runtime` is new). Per criterion below:
> **(1) ◐** tmux relocated to `genesis_tmux` (A34) — reference survey done, build handoff staged at
> `genesis/packages/tmux/HANDOFF.md`, build not started (off the Friday path).
> **(2) ◐** `SubprocessProvider` proven offline vs an `sh` stub — token forwarded, `GC_DOLT_PASSWORD`
> filtered, whole-tree process-group kill, output stream, `RuntimeEvent.exited`; the literal real-`claude`
> spawn is the live arm.
> **(3) ✅** lifecycle-as-beads + the fail-closed `GridBeadWriter` chokepoint, proven offline vs fake bd
> (refusal of a non-owned/absent-rig write; crash-loop quarantine + restart). Recovery actuator (4b) deferred.
> **(4) ◐** `GridGitService` worktree + three-gate reaper, proven offline vs real temp repos + a fake PR
> seam (provision; land commit→push→PR; reaper refuses uncommitted/unpushed/stashed + fail-closed on probe
> error). Real `lenny-tgdog` clone + real push/PR = live arm.
> **(5) ✅** leonard attaches — `vm_service_attach` + `attach_conformance` green vs a real the_grid VM;
> conformance fixtures pinned; ADR-0001 D6 amended. (Cross-process `leonard_cli` self-skips until inference
> creds are armed.)
> **(6) ✅** coexistence partition enforced + proven — ONE shared `{tgdog}` allow-set across dispatch + the
> chokepoint; non-owned beads observed read-only, never dispatched.
> **(7) ✅** ADR-0006 **Accepted** (Nico, 2026-06-15); A32/A33 ratified; A34/A35 recorded.
> **Remaining = the live arm only** (real `claude` + real bd writes + real lenny PRs), gated on Nico.

1. **Standalone `tmux` package (NOT Friday-gating)** — Tier-1 verbs + v1 stream surfaces green
   offline against `FakeTmuxExecutor`; the Tier-1.5 integration tier drives a real tmux server on an
   isolated `-L grid-test-*` socket and never touches the developer's tmux (Track 1 DoD; ADR-0004 D5).
2. **Subprocess-first dispatch (Friday critical path)** — `grid run --provider subprocess` spawns a
   real `claude` per owned ready bead in a per-bead worktree, streams its output, observes death as a
   `RuntimeEvent`, and kills the whole process group cleanly on stop; the child env carries the agent
   token allowlist and **not** `GC_DOLT_PASSWORD` (ADR-0004 D3 Tier-1 exit; auth via inherited env on
   an explicit allowlist, never argv).
3. **Lifecycle-as-beads, bd-only, through the write chokepoint** — each session is tracked as a
   the_grid-owned bead whose `state` transitions via the `GridBeadWriter` chokepoint over
   `BdCliService` (`--actor grid-controller`, merge semantics, never SQL, never `bd show` on a
   controller path); the chokepoint re-checks ownership fail-closed and **refuses any write whose rig
   is absent / not owned**; a crash quarantines+requeues. **(Off Friday critical path:** the
   convergence **recovery actuator** (Track 4b, A27 gap) bd-executes every `RecoveryAction` shape and
   refuses a not-owned convergence — required only when the_grid drives a live owned-rig convergence,
   which the Friday dogfood does not.)
4. **Worktree isolation + land-to-PR** — work runs in `grid/<beadId>` worktrees off the probed
   default branch under the the_grid-owned root checkout in engineering.memento; finished work lands
   as a **pushed branch / PR** (never auto-merge to lenny main); the three-gate reaper provably
   refuses to delete unsafe worktrees.
5. **leonard attaches** — stock `leonard_cli --extensions grid` against the_grid's pure-Dart VM under
   `--enable-vm-service` discovers the `grid` namespace + 5 tools, reads live grid state, and executes
   `grid.ready` → `{ok:true}`; a pinned cross-repo conformance fixture locks the `extensions` shape.
6. **Coexistence partition respected** — the dispatcher gates every spawn through the
   `BeadOwnershipPredicate` built from the **same rig allow-set** as the M2 `OwnsRigs` actuator; the
   bd write chokepoint re-checks ownership before every session/recovery write; non-owned ready beads
   are observed read-only and never dispatched; any live-shadow observation of gc convergence is
   read-only; `.beads/hooks/` untouched; the OAuth-token mechanism is reported but no secret value is
   read/printed.
7. **Every en-route AI decision sits in ADR-0000 as pending (A32+)** and ADR-0006 is ratified by
   Nico before the live writing arm runs.

**Carried to M4 (do not block M3 acceptance):** full topology reconciler (ADR-0003 D1); demand-
spawned pool; tmux Tier 2/3 heuristics as failures surface; per-rig cutover (M4f).

## How coexistence safety + the ownership partition are enforced in M3

- **Single writer per bead (ADR-0003 D6 / A7), enforced at TWO gates.** the_grid spawns/supervises/
  actuates **only** the disjoint, prefixed rig set it owns (ADR-0006). The two gates share **one rig
  allow-set `Set<String>`** so they cannot drift: (1) **dispatch** is gated by the new
  `BeadOwnershipPredicate.owns(Bead)` (ADR-0006 Decision 1) — `OwnsRigs(Convergence)` reads
  `convergence.metadata.rig` and **cannot** be called on a plain ready `Bead`, so the new predicate
  derives the bead's rig from the issue-prefix/label axis (ADR-0002 D2) and a no-rig bead is
  not-owned, fail-closed; (2) **actuation** is gated twice — `OwnsRigs.owns(convergence)` in
  `ReconcilerRuntime` for convergence writes, and the `GridBeadWriter` chokepoint (ADR-0006 Decision 2)
  re-checks the target rig fail-closed before **every** session/recovery `create`/`update`/`close`/
  `delete`. A non-owned ready bead is reduced for diagnostics only, never spawned, never mutated.
- **bd-only writes, single chokepoint.** All session/lifecycle/recovery mutations flow through the one
  `GridBeadWriter` over the M2 writer (`BdCliService`, `--actor grid-controller`); **never raw SQL**,
  **never `bd show`** on a controller/re-query path (it self-triggers the watcher), **never touch
  `.beads/hooks/`** (gc owns them). Every minted session bead carries the owned rig marker from birth
  so the chokepoint can assert ownership on the first write.
- **Read-only live observation.** The Track-I live shadow and any observation of gc convergence
  traffic construct **no writer** (mirrors M2's structurally read-only `ShadowRuntime`).
- **Auth, flag-not-extract, explicit allowlist.** The agent's `CLAUDE_CODE_OAUTH_TOKEN` is forwarded
  as an **inherited environment variable on an explicit allowlist** into the child
  (`SubprocessProvider` keeps `includeParentEnvironment:false` and forwards only the allowlist
  mirroring gc's `internal/processenv/provider.go:98-126` — HOME/USER/LOGNAME/CLAUDE_CONFIG_DIR/XDG_*/
  `CLAUDE_CODE_OAUTH_TOKEN`/…), so `GC_DOLT_PASSWORD` and other host secrets are **never leaked** into
  the agent child — **never on argv** (which is the plaintext leak flagged on gc's separate
  control-dispatcher). That argv leak is the **standalone side-finding recorded in CLAUDE.md** (it is
  **not** A29 — A29 is the M2 codec-fidelity capture); reported here as a mechanism only, no secret
  value read. `GC_DOLT_PASSWORD` stays operator-provided and is never extracted from process memory.
- **Worktree containment.** the_grid's worktrees + root checkout live entirely under
  `/Users/nico/development/engineering.memento/` on a grid-prefixed set; the reaper mirrors gc's
  strictly-under-dir scope gate so it can only ever delete inside the_grid's own worktrees root, and
  the three-gate fail-closed check guarantees no uncommitted/unpushed/stashed work is lost.
