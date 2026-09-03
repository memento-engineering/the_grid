---
status: accepted
date: 2026-09-03
decision-makers: [agent]
consulted: []
informed: [nico]
register:
  spec: 1
  slug: pgid-liveness-is-supervision-evidence
  surfaces:
    - "packages/grid_runtime/lib/src/runtime/process_group.dart"
    - "packages/grid_runtime/lib/src/runtime/subprocess_provider.dart"
    - "packages/grid_runtime/lib/src/runtime/runtime_event.dart"
    - "packages/grid_runtime/lib/src/lifecycle/runtime_actuator.dart"
  obsoletes: []
  updates:
    - a49-no-complete-on-faith-an-inferred-one-shot-exit-is-proven
  obsoleted-by: null
  updated-by: []
  bead: tg-8kye
  legacy-id: null
---

# PGID liveness is supervision EVIDENCE; the reaper parent supplies the real exit status

## Context and Problem Statement

`SubprocessProvider` detaches work into a process group but polls only the
leader pid. A leader that backgrounds a descendant and exits was reported as an
inferred success, and `terminateGroup` refused to signal the pgid once the leader
was gone — so descendants kept consuming resources and mutating the worktree
after the circuit advanced. A49 named the same wound from the other side ("a
MURDERED agent vanishes IDENTICALLY to a finished one") and fenced the
COMPLETION; nothing made the runtime's own EVIDENCE honest. ADR-0014 D-R2 already
records the cost of a leaked group ("a bare `kill`/`launchctl stop` previously
bypassed the spawned-group kill and leaked agent process groups") and makes the
spawned-group kill a hard prerequisite for supervision — but that kill still
refused a group whose leader had already exited.

## Decision Outcome

1. **The reaper parent is grid_runtime-OWNED.** `SystemSubprocessSpawner`
   composes `kReaperScript` around whatever argv it is handed: the wrapper is the
   group leader, runs the harness as its child in the SAME group, waits, writes
   the real code to a per-session status file (`GRID_EXIT_STATUS_FILE`,
   atomically), and exits with it. A caller's own wrapper runs unchanged inside
   it, so power_station is not edited. Cost: one extra `sh` per session. The
   status file lives in a provider-owned temp dir, never in the agent's
   worktree, so A49's `committedWorkspace` fence still sees a clean tree.
2. **The seam probe returns MEMBERS, not a bool.** `groupMembers(pgid)` shells
   `pgrep -g <pgid>`. The member COUNT rides `RuntimeEvent.sessionOrphaned`, so
   one probe answers both liveness and the count; a second seam method beside it
   would duplicate the same syscall.
3. **Leader gone + live members is NOT terminal.** One `sessionOrphaned` event, a
   bounded `kOrphanGrace` (30 s, injectable), then the owned pgid is signalled
   through the existing guarded `terminateGroup`. The resulting terminal is a
   `Died` carrying `orphaned descendants killed` — never a clean success,
   whatever the leader's own status was. A group that empties on its own inside
   the grace takes the ordinary terminal path with no kill.
4. **`terminateGroup`'s refusals are PGID-based only.** `alreadyGone` now means
   leader gone AND group empty; `pgid <= 1` and the caller's own group remain the
   only refusals. A dead leader with live members is precisely the case the
   primitive must handle — and precisely the leak ADR-0014 D-R2 names.
5. **Authority does not move.** PGID liveness is reconciliation EVIDENCE for the
   runtime's terminal event. The session bead's explicit result and the engine's
   completion fence (`CompletionContract.committedWorkspace`) still decide
   advancement. No engine fence code is touched by this entry.

### Consequences

* Good, because the inferred path survives ONLY where no status file was
  written, which keeps A49's fence load-bearing rather than dead, and because
  ADR-0014 D-R2's spawned-group kill can no longer be skipped by a dead leader.
* Bad, because every session now costs one extra `sh` process, and a spurious
  `sessionOrphaned` is possible in the sub-poll window between a leader's exit
  and the OS reaping the group — it costs one event and no terminal change,
  because the next poll finds the group empty.
* Bad, because the recycled-pgid exposure widens: ADR-0007 Decision 4 already
  accepts it ("distinguishing a *recycled* pgid from a genuine surviving orphan
  requires reading the live process's `GRID_INSTANCE_TOKEN` from its environ —
  the same process-table scan the **deferred ADOPT** track owns"), and this
  entry adds no token read, so a dead leader over a recycled pgid can now be
  signalled where before it was skipped. The `pgid <= 1` / own-group guard, the
  freshness barrier and the per-bead worktree remain the whole fence, exactly as
  Decision 4 scoped them.
* Bad, because `RuntimeEvent` gains a sixth variant, so the four exhaustive
  `switch`es over it (`runtime_actuator.dart`, `engine_fakes.dart`,
  `runtime_types_test.dart`, `station_process_transport_protocol_event_test.dart`)
  each gain a case.
