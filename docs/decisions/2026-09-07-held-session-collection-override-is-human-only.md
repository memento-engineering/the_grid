---
status: accepted
date: 2026-09-07
decision-makers: ["Nico Spencer"]
consulted: []
informed: []
register:
  spec: 1
  slug: held-session-collection-override-is-human-only
  surfaces:
    - "packages/grid_runtime/lib/src/git/station_git_service.dart"
    - "packages/grid_engine/lib/src/restart/restart_reconciler.dart"
    - "packages/grid_sdk/lib/src/command/**"
    - "packages/grid_cli/lib/src/session_command.dart"
  obsoletes: []
  updates:
    - "adr-0006-dogfood-rig-and-live-write-authorization"
  obsoleted-by: null
  updated-by: []
  bead: tg-yz4p
  legacy-id: null
---

# Held-session collection override is human-only

## Context and Problem Statement

Automatic lifecycle and restart cleanup protects preserved work with three git
gates: uncommitted changes, unpushed commits, and stashes. A held session is a
human-dispositioned residual, so deciding to discard its work is an operator
judgement rather than another automatic lifecycle endpoint. The operator needs
one explicit collection path without weakening any automatic cleanup caller.

## Decision Outcome

Automatic lifecycle and restart reaps continue to require all three gates to
be clear. Their default call shape and fail-closed behavior do not change.

Only an explicit operator `session collect --override-unsafe` request may
bypass a known `GateOutcome.present` result. That exception is scoped to held
session collection and does not authorize automatic callers to force removal.
Worktree scope failures remain fail-closed. `GateOutcome.probeError` is never bypassed,
including when the operator supplies the override flag.

Collection is a dry-run by default. `--override-unsafe` authorizes bypassing a
known-present safety gate, while the separate `--act` flag authorizes removal.
Supplying either flag never implies the other.

### Consequences

* A normal lifecycle or restart reap remains byte-for-byte fail-closed.
* An operator can preview both clear and explicitly overridden held-session
  collection without removing the worktree.
* Uncertain scope and failed probes always preserve the worktree.
* Every acted removal still uses the existing `StationGitService.reap` seam,
  which performs one worktree removal and its existing best-effort branch
  cleanup.

## Decision Alignment

This entry narrows ADR-0006's all-three-gates-clear rule only for a deliberate
human command over a session already derived as held. It does not supersede or
relax that rule for lifecycle, restart reconciliation, roster detachment, or
any other automatic caller.

## Review log

* 2026-09-07 — accepted by **Nico Spencer**.
