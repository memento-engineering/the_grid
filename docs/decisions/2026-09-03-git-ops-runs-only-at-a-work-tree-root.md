---
status: accepted
date: 2026-09-03
decision-makers:
  - "specify"
consulted: []
informed: ["nico"]
register:
  spec: 1
  slug: git-ops-runs-only-at-a-work-tree-root
  surfaces:
    - "packages/grid_runtime/lib/src/git/git_ops.dart"
    - "packages/grid_sdk/lib/src/work/work_assembly.dart"
    - "packages/grid_engine/lib/src/testing/engine_fakes.dart"
  obsoletes: []
  updates:
    - adr-0006-dogfood-rig-and-live-write-authorization
  obsoleted-by: null
  updated-by: []
  bead: tg-amwa
  legacy-id: null
---

# A git op runs only at its own work-tree root, and no seam is exempt

## Context and Problem Statement

A `git` command run from a directory that is not a checkout does not fail: git
walks up and operates on the enclosing repository. A workspace path that held
the engine's `.grid` scaffold and no `.git` entry let a delivery step's
`commitAll` and `push` act on the substation's PRIMARY checkout — a commit on
local `main` and three branches pushed from it. Nothing noticed: the commit
no-opped on a clean tree, the work probe reported clear, and the push succeeded.
ADR-0006 Decision 3 already installs two pre-exec guards for this hazard class
(the GIT_* env blacklist, the stale-ancestor walk) but both address a different
redirection than the cwd.

`the_grid#a49-no-complete-on-faith-an-inferred-one-shot-exit-is-proven`
(A49)'s completion fence also depends on
`GitOps.hasUncommittedWork({excluding})`: only that caller excludes grid-owned
residue, while the reap gate passes no exclusion. The root guard composes in
front of the status probe and leaves the exclusion filter and stderr
fail-closed behavior unchanged.

## Considered Options

* Stat `.git` in the workspace before each op.
* Guard inside `SystemGitRunner`, below the ops.
* Guard at `GitOps`, the seam every op already routes through.

## Decision Outcome

The third. `GitOps` gains one guard that runs
`git rev-parse --show-toplevel --show-prefix` in the workDir and refuses unless
the prefix is empty (the cwd IS the work-tree root, a linked worktree root
included), returning a failed `GitRunResult` that names the workDir and the
repository git resolved. It covers every mutating op and the three reap gates
plus `headSha`; the discovery probes (`isRepo` and the freshness chain,
`worktreeList`, `branchExists`) stay unguarded because they ask whether a path
is INSIDE a repository, which is the opposite question. Asking git beats
stat-ing `.git`: a `.git` file can name a gitdir that no longer exists, and the
prefix answer needs no path canonicalisation. The guard stays at `GitOps` rather
than in the runner because which ops require root-ness is policy, and because a
fake runner must remain able to model a non-root directory. No seam is exempt:
the dry runner and the test fakes answer the probe faithfully rather than
bypassing the check, so it reads the same dry as live.

### Consequences

* Good, because a stray commit can no longer reach the primary checkout every
  later worktree is cut from, and a refusal names both paths instead of
  succeeding silently.
* Good, because every consumer inherits it — `StationGitService` forwards to
  `GitOps`, so both delivery methods and the landing circuit are covered with no
  change of their own.
* Good, because A49's `excluding` parameter still governs only which porcelain
  entries count as work after the workspace has passed the root check; the new
  guard neither replaces the residue filter nor changes reap behavior.
* Bad, because each guarded op pays one extra `git` invocation.
* Bad, because a `GitRunner` fake that does not model the probe makes its
  guarded op unreachable rather than failing loudly, which is why all five
  in-repo fakes were updated with it.
