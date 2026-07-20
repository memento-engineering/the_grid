# ADR-0006 — M3 dogfood rig & live-write authorization

**Status:** **Accepted 2026-06-15** (ratified by Nico; drafted by AI per the ADR-0000 register rule). Ratified concrete inputs in the block below.
**Date:** 2026-06-15
**Deciders:** Nico Spencer (ratifier); drafted by AI per the ADR-0000 register rule
**Context:** M3 (ADR-0004 runtime providers) gives the_grid hands. The Friday 2026-06-19 dogfood
loop requires the_grid to make **real `bd` writes** — session/lifecycle beads, recovery effects —
against a scoped, the_grid-owned set of beads **while the live gc keeps running** and writing its
own convergence/session beads in the same `tg` workspace. ADR-0003 D6 (coexistence partition) and
ADR-0004 (runtime) establish *that* the_grid coexists and *how* it spawns, but neither names the
concrete dogfood rig, the bead namespace the_grid is authorized to mutate, the git-worktree land/
isolation policy (ADR-0004 predates the settled engineering.memento decision and never mentions
worktrees), or the agent OAuth-token handling. Crucially, neither establishes a **dispatch-time
ownership gate**: ADR-0003 D6's `OwnsRigs` predicate is typed `owns(Convergence)` and reads the
`convergence.rig` metadata key, which lives only on convergence beads — a ready **work** bead the
dispatcher must classify is a plain `Bead` with no such key, so the existing predicate cannot gate
spawning. This ADR fills exactly those gaps so the live dogfood can run without a chance of
corrupting gc state. It does **not** re-decide the runtime seam (ADR-0004) or the convergence engine
(ADR-0003); it authorizes their *live use* on a bounded blast radius and adds the missing
bead-shaped ownership gate + write chokepoint.

The binding M2-era safety rules this ADR re-states as enforced constraints: bead writes go through
the **bd CLI only** (`--actor grid-controller`), **never raw SQL** (ADR-0001 D4); **never touch
`.beads/hooks/`** (gc owns them); **never call `bd show` from a controller/re-query path** (it writes
`.beads/last-touched` and self-triggers the watcher); **single writer per bead** — the_grid may only
mutate beads it owns and any observation of live gc convergence is **strictly read-only** (ADR-0003
D6); `GC_DOLT_PASSWORD` is operator-provided and **must not** be extracted from process memory.

---

## Ratified inputs (Nico, 2026-06-15)

The open decisions this ADR carried are pinned (recorded as ADR-0000 **A35**):

- **Rig / allow-set token:** **`tgdog`** — the sole entry in the ownership `Set<String>`; everything else is not-owned, fail-closed.
- **Ownership axis:** **issue-id prefix** (primary), optionally also requiring `metadata.rig == tgdog` (belt-and-suspenders). A no-prefix/no-rig bead is not-owned (A32).
- **Layer-1 root checkout:** **`/Users/nico/development/engineering.memento/lenny-tgdog`** — a real lenny clone, **explicit one-time registration**, default branch probed from `origin/HEAD` (never auto-provisioned; the nested-checkout/stale-ancestor hazard).
- **Agent token:** `CLAUDE_CODE_OAUTH_TOKEN` from an **operator-provided env channel**, forwarded into the child via the **explicit allowlist** (`includeParentEnvironment:false`) — never argv, never the full parent env (so `GC_DOLT_PASSWORD` cannot leak).
- **Permissions:** dogfood agents run **pre-granted** (no approval-prompt handling enters M3).
- **leonard:** attaches with explicit **`--extensions grid`**.

**Held for the first live-arm gate (Nico present):** the **2 specific lenny work beads** the dogfood drives, and the go-ahead for the first real bd writes + agent spawns beside the running gc. The M3 build proceeds **fully offline** (fakes + temp repos + `grid run --dry-run`) up to that threshold.

---

## Decision

### Decision 1 — The dogfood rig prefix, the disjoint namespace, and the bead-shaped ownership gate

the_grid is authorized to **create and mutate** exactly the beads in a single, disjoint, prefixed
**dogfood rig**, proposed prefix **`tgdog`** (pending Nico — see the open decision):

- **Rig identity.** The dogfood rig carries `metadata.rig == <tgdog-rig>` (the exact rig name Nico
  confirms). the_grid's rig **allow-set** (`Set<String>`) contains **only** this rig; everything else
  is not-owned by default.
- **Two predicates, ONE shared allow-set.** The existing `OwnsRigs.owns(Convergence)`
  (`grid_reconciler/lib/src/runtime/ownership.dart:44`) reads `convergence.metadata.rig` and governs
  the **convergence actuator** — it operates on a `Convergence`, not a `Bead`. A ready **work** bead
  carries **no `convergence.rig` key** (gc stamps that key only into convergence beads), so `OwnsRigs`
  **cannot be called on it**. The dispatch path therefore introduces a **new**
  `BeadOwnershipPredicate` / `OwnsBead.owns(Bead)` that derives a bead's rig from the **same axis the
  dogfood rig actually uses** — the **issue-id prefix and/or a `metadata.rig`/label**, per **ADR-0002
  D2** ("issue prefix partitions rigs in one store; labels drive rig scoping"). The **shared artifact
  between the two predicates is the rig allow-set `Set<String>`, not the predicate object**:
  `OwnsRigs(Convergence)` governs actuation and `BeadOwnershipPredicate(Bead)` governs dispatch, both
  constructed from the identical allow-set so they cannot drift. **Which axis the work beads use
  (prefix vs label vs `metadata.rig`) is an open decision for Nico.** A bead with **no rig / no owned
  prefix** is **not-owned, fail-closed** (never dispatched, never mutated). This is the mechanical
  embodiment of ADR-0003 D6's single-writer invariant on the dispatch side. *(Recorded as ADR-0000
  amendment A32 until ratified.)*
- **Disjointness guarantee.** The rig name and any bead prefix the_grid mints are chosen so that the
  allow-set **accepts** the_grid's dogfood beads and gc's reconciler **never** does — a partition, not
  an overlap. gc's convergence/session beads carry their own rigs (e.g. the live `gascity`/HQ rigs).
- **What the_grid mints.** Per the dogfood, the_grid creates the_grid-owned **session beads** (gc's
  session-bead analog — type `session`, `--actor grid-controller`) carrying the runtime lifecycle
  `state`, the worktree path, the branch, and the bead id of the work bead — **each stamped with the
  owned rig marker (`metadata.rig == <tgdog-rig>`) from birth** so the write chokepoint (Decision 2)
  can assert ownership on the very first write. The **work beads** themselves (the real lenny tasks,
  see the open decision) are pre-existing/minted into the dogfood rig by Nico's confirmed procedure so
  they carry the owned rig/prefix from birth.

### Decision 2 — The single bd write chokepoint (live-write authorization, enforced as a gate)

**All the_grid-owned bead writes — session create/update/close AND every recovery write — flow
through one chokepoint (`GridBeadWriter`) that re-checks ownership fail-closed immediately before the
`bd` call**, mirroring how `ReconcilerRuntime` gates convergence actuation on
`_ownership.owns(convergence)`. Because session and recovery writes never flow through a
`Convergence`, the convergence gate cannot cover them — so this chokepoint is the gate that fires for
them, and it is the **second line of defense** behind the dispatch predicate (Decision 1). Before
**every** `create` / `update --metadata` / `close` / `delete`, the chokepoint asserts the target
bead's rig is in the shared allow-set (the same `Set<String>` the dispatch predicate uses) and
**refuses + logs loudly** any write whose target rig is **absent or not owned**.

**ALLOWED** (only on beads matching the owned rig, only through `GridBeadWriter` →
`BdCliService`, `--actor grid-controller`):

- `bd create` of the_grid-owned **session beads** (each stamped `metadata.rig == <tgdog-rig>` at
  birth), and where the recovery path requires it, the persistent wisp pour via `bd cook
  --mode=runtime` + `bd create --graph` **persistent** (A15).
- `bd update --metadata <json>` lifecycle transitions (merge semantics; works on closed beads) — the
  `state` machine + crash-loop quarantine/restart markers (Track 4).
- `bd close` on the_grid-owned session beads (terminal lifecycle); `bd delete` only for **speculative
  wisp burns** in natural post-order (never close-as-burn, A16/A26).
- **Recovery actuation** (the A27 gap, built in M3 Track 4b — required only for a live owned-rig
  **convergence**, which the Friday dogfood does not drive): `RecoveryAction.*Writes` — adopt/
  pour-wisp-1, partial-creation terminate, terminated-but-open close, marker repair — executed through
  the **same chokepoint** (`update --metadata`/`delete`/`close`), respecting the M2 write-ordering +
  idempotency invariants. The chokepoint **refuses any `RecoveryAction` whose target convergence is
  not owned**.
- **Git** writes confined to the the_grid-owned worktrees/branches (Decision 3).

**FORBIDDEN** (hard constraints, enforced structurally, not by convention):

- **No raw SQL writes** of any kind (ADR-0001 D4) — raw SQL would bypass the chokepoint and the gc
  hooks. The only live SQL is the **SELECT-only** idempotency probe / `@@tg_working` change probe
  inside `runReadTransaction` (READ ONLY).
- **No write** to any bead whose rig is not in the allow-set — gc's convergence beads, gc's session
  pool, any HQ bead. The chokepoint refuses these fail-closed. Any observation of gc convergence
  traffic (the Track-I live shadow) constructs **no writer** and is strictly read-only.
- **No `bd show`** from any controller/re-query/dispatch path (self-triggers the watcher) — use
  snapshot reads / `bd export` / the SELECT probe.
- **No touching `.beads/hooks/`** (gc owns them).
- **No second reconciler on a gc-owned convergence bead** — single-writer-per-bead (ADR-0003 D6).
- **No seeding/mutation of the gc-managed `tg` server** outside the owned rig; the live differential/
  shadow halves self-skip without `GC_DOLT_PASSWORD` and never seed gc's server (the M2 partition
  rule, A24).

### Decision 3 — Land / isolation policy

Two-layer isolation, all under `/Users/nico/development/engineering.memento/` (lenny moved to the
memento-engineering org):

- **Layer 1 — the_grid-owned root checkout.** A real clone of lenny that the_grid owns, registered
  once, with `origin` set and its **default branch probed from `origin/HEAD`** (port gc's
  `ProbeDefaultBranch`, `internal/git/git.go:92-133`; never hardcode `main`). This is the_grid's
  "rig" in gc's sense — a clone, not a worktree. (Exact path: open decision.)
- **Layer 2 — per-bead git worktrees** under the root checkout at
  `<root>/.grid/worktrees/<tgdog-rig>/<beadId>`, each on a fresh branch `grid/<beadId>` off the probed
  default (mirrors gc's `.gc/worktrees/<rig>/<name>`, `internal/workdir/workdir.go:76-86`; the bead id
  is encoded in the dir name so an orphaned worktree can be re-bound to its lifecycle bead on restart
  without external state).
- **Branch-per-bead, push-to-PR, never auto-merge.** On session success: commit on `grid/<beadId>` →
  `git push -u origin grid/<beadId>` → `gh pr create` → record the PR on the lifecycle bead (through
  the Decision-2 chokepoint). **Nothing auto-merges to lenny main** — finished work lands as a PR for
  Nico to review.
- **Fail-closed cleanup.** A worktree is removed only when its lifecycle bead is **closed AND** the
  branch is **pushed** (`HasUnpushedCommits==false`), and only after the **three-gate** check passes
  (no uncommitted work, no unpushed commits, no stashes — all fail-closed on probe error,
  `internal/git/git.go:134-213`; `git worktree remove` run from the root repo, never from inside the
  worktree). The GIT_* env blacklist is stripped on every git exec; the stale-ancestor guard
  (`ValidateAncestorWorktreesNotStale`, `internal/workdir/workdir.go:303-359`) runs before every
  `git worktree add` (the_grid is itself a git repo nested under engineering.memento). Registry
  removal ≠ disk deletion (mirror gc — removal can never silently lose in-progress work).

### Decision 4 — OAuth-token handling stance — flag-not-extract, explicit allowlist

- The agent's Claude auth (`CLAUDE_CODE_OAUTH_TOKEN`) is passed to the spawned `claude` subprocess as
  an **inherited environment variable on an explicit allowlist** (gc's correct mechanism,
  `gascity/internal/processenv/provider.go:98-126`, where `ProviderProcessPassthroughEnv` returns a
  fixed map of HOME/USER/LOGNAME/CLAUDE_CONFIG_DIR/XDG_*/`CLAUDE_CODE_OAUTH_TOKEN`/…). For
  `SubprocessProvider`, the child keeps `includeParentEnvironment:false` and receives **only** that
  allowlist — so `GC_DOLT_PASSWORD` and other host secrets are **never** leaked into the agent child.
  For `TmuxProvider`, the same allowlist is injected via tmux `-e KEY=VAL` / `set-environment`. The
  token is **NEVER placed on argv**, structurally avoiding the plaintext-on-argv leak.
- **[Edited 2026-07-20 — tg-8gv.11(g), public-flip redaction directed by Nico: a report-only
  side-finding describing a specific third-party (gascity) process-argv credential-exposure
  weakness was removed here ahead of the public flip — it named a live external system's
  security posture, not a the_grid decision, and is not appropriate for a public repo.]**
  the_grid sources its own agent token from an operator-provided env channel (the same posture
  as `GC_DOLT_PASSWORD`); the exact source env var / path is an open decision for Nico.

---

## Alternatives considered

- **Reuse `OwnsRigs(Convergence)` for dispatch ("same code, second call site")** — **rejected as
  structurally impossible.** `OwnsRigs.owns()` reads `convergence.metadata.rig`, a key gc stamps only
  into convergence beads; a ready work `Bead` has no such key and `readyBeads` returns `List<Bead>`,
  so the predicate cannot be called on the dispatcher's actual input. A non-convergence bead passed to
  it would mis-evaluate. Chosen instead: a new `BeadOwnershipPredicate` deriving rig from the
  prefix/label axis (ADR-0002 D2), **sharing the rig allow-set** with `OwnsRigs` so the two cannot
  drift (Decision 1).
- **No write chokepoint — rely on rig stamping alone** — **rejected.** The Actuator seam "enforces
  nothing by design" and the only existing runtime gate is keyed on a `Convergence`; a bug in rig
  stamping or a config slip could mint/mutate a session bead with a non-owned rig with no second line
  of defense. Chosen instead: a single `GridBeadWriter` chokepoint that re-checks ownership fail-closed
  before every write (Decision 2).
- **Shared rig with an ownership marker (`OwnsMarked`)** vs **a fully disjoint dogfood rig** — chosen
  the **disjoint rig** for the dogfood: a separate `tgdog` rig name is the cleanest partition
  (gc's reconciler can never own it), removes any ambiguity about which writer owns a bead, and keeps
  the allow-set a single confirmed token. `OwnsMarked` (an explicit `convergence.owner` marker) stays
  available as the alternative axis where a rig is not yet assigned, but is not used for M3.
- **Auto-provision the Layer-1 root checkout on first ready bead** vs **explicit one-time
  registration** — chosen **explicit registration** (a `grid rig add`-style step). Nested checkouts
  under engineering.memento are exactly gascity#1556's stale-ancestor hazard; silent auto-provision
  would create that hazard implicitly. The path and provisioning are an open decision for Nico.
- **Forward the full parent environment to the agent child** — **rejected**: it would leak
  `GC_DOLT_PASSWORD` and other host secrets. Chosen: `includeParentEnvironment:false` + an explicit
  allowlist mirroring gc's `processenv` map (Decision 4).

## Consequences

- **Blast radius (bounded by design).** Every live write is gated at two points sharing one rig
  allow-set: the `BeadOwnershipPredicate` at dispatch and the `GridBeadWriter` chokepoint before every
  bd call. gc's beads are structurally unreachable for mutation. Git writes are confined to the_grid-
  owned worktrees/branches under engineering.memento; lenny main is never written without a
  Nico-reviewed PR. The worst credible outcome of a bug is a stray the_grid-owned session bead or an
  orphaned worktree — both inside the partition, both reapable.
- **What could go wrong, and the guard:** (1) *Wrong rig in the allow-set* → the dispatcher could
  spawn against a gc bead — guarded by making the allow-set a single confirmed rig name + the
  no-rig=not-owned rule, and by Nico confirming the rig + the prefix/label axis before live arming.
  (2) *A bug writes outside the rig* → the `GridBeadWriter` chokepoint re-checks ownership fail-closed
  before every create/update/close/delete and refuses; raw SQL (which would bypass it) is forbidden.
  (3) *Worktree reaper deletes unfinished work* → the three-gate fail-closed check + run-from-root
  rule. (4) *Auth leak* → token only ever in env on an explicit allowlist, never argv, never the full
  parent env; secret values never read. (5) *Watcher self-trigger* → no `bd show` on controller
  paths. (6) *Two writers on one convergence* → single-writer partition + read-only live shadow + the
  recovery chokepoint refusing a not-owned convergence.
- **Rollback.** The live dogfood is opt-in behind `grid run` (default `--dry-run` observe-only).
  Disarming = stop `grid run`; the_grid holds no durable lifecycle the gc reconciler depends on.
  *[Superseded (ADR-0014, ratified Nico 2026-07-19): the per-invocation `grid run` posture and
  its drive-list arming clause are retired — the resident `space up` + store-bless (D-R1/D-R4)
  is the live-arm model; `run` was transitional scaffolding, removed at RS-8. Disarming = `space
  down`. This stamp was applied at ADR-0014's ratification, never silently.]* The
  the_grid-owned session beads can be closed/deleted (they are in the partition); worktrees are
  reaped once safe; pushed PR branches are abandoned/closed by Nico. gc is unaffected throughout
  because it never shared a writer with the_grid.
- **Dependencies / sequencing.** This ADR gates the **live writing arm** of M3 Track 7 (and the
  Track-I live shadow). M3 Tracks 1–6 build and test fully offline regardless (mirrors M2's "code
  green, live half gated" posture). Promotion of this ADR + the open decisions below is the
  precondition for the first live run.
- **Ratified-doc interaction (no silent edit).** The M3 Track-6 `plugins`→`extensions` wire-key rename
  makes the_grid emit a shape ADR-0001 Decision 6 (RATIFIED) no longer documents. Per the process rule
  this is recorded as **ADR-0000 amendment A33**, and ADR-0001 D6 gets a one-line amendment **upon
  ratification by Nico**, not before — this ADR-0006 does not touch ADR-0001.
- **Process.** Because every decision here is AI-drafted, the en-route specifics (the bead-ownership
  axis, rig prefix choice, worktree layout, token source) are recorded as **pending ADR-0000
  amendments (A32+)** until Nico ratifies this ADR and confirms the open decisions; nothing here is
  baked into a ratified ADR.
