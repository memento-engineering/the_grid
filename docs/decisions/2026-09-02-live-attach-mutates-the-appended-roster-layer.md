---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: ["nico"]
register:
  spec: 1
  slug: live-attach-mutates-the-appended-roster-layer
  surfaces:
    - "packages/grid_sdk/lib/src/roster/**"
    - "packages/grid_sdk/lib/src/work/work_assembly.dart"
    - "packages/grid_runtime/lib/src/lifecycle/bead_ownership.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-wv9
  legacy-id: null
---

# A live attach mutates the APPENDED roster layer, and only that

## Context and Problem Statement

ADR-0014 D-C4 names attach and detach as resident-loop operator one-shots, but
does not say which seats those operations may move, what a detach releases, or
how ADR-0006's coexistence ownership allow-set changes during a boot. A coded
substation is also a literal `Substation(...)` in the station's `build`, while
an operator-attached seat has no corresponding literal in source. Treating
those origins as interchangeable would let the running tree contradict its
own authored configuration.

## Considered Options

* Let detach remove any substation, including a coded seat.
* Restrict attach and detach to the runtime-appended roster layer.
* Persist the attached roster across a bounce and treat it as durable station
  configuration.

## Decision Outcome

The second. ADR-0008 Decision 1 holds that "config layers append/merge onto the
coded base, never replace it." Runtime attach therefore appends a seat beside
the coded base, and detach may remove only a seat in that appended layer. A
request to detach a coded or otherwise unattached seat is refused with
`not_attached`; changing a coded seat remains a source change followed by a
bounce.

A detach releases no lock. ADR-0014 D-A1 gives a substation no lock of its own;
the station lock at `<gridRoot>/.grid/station.lock` belongs to the resident and
remains held. Detach instead releases the federation membership, controller and
its Dolt pool, ownership tokens, command-store rails, and safely reapable
per-bead worktrees.

`RestartReconciler.workRoots` is not re-rooted for an attached seat. Runtime
attach is not durable across a bounce, so a crash while such a seat is attached
can leave its worktrees for a human to reap. Durable attachment and dynamic
restart-reconciler roots are separate work, named here rather than folded into
this control-surface mutation.

The coexistence allow-set becomes mutable within one boot through loud
`admit`/`revoke` operations. This extends ADR-0006 Decision 2 without weakening
it: every chokepoint write still asserts ownership, and the disjointness gate
refuses a colliding name or prefix before the set can widen.

## Review log

* 2026-09-02 — authored by **agent** (specify stage of tg-wv9).
