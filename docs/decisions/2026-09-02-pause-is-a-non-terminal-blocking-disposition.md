---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: ["nico"]
register:
  spec: 1
  slug: pause-is-a-non-terminal-blocking-disposition
  surfaces:
    - "packages/grid_engine/lib/src/domain/session_disposition.dart"
    - "packages/grid_engine/lib/src/domain/session_bead.dart"
    - "packages/grid_engine/lib/src/domain/linked_sessions.dart"
    - "packages/grid_engine/lib/src/kernel/station_admission_authority.dart"
    - "packages/grid_engine/lib/src/seeds/work_list.dart"
    - "packages/grid_engine/lib/src/circuit/unclaimed_frontier.dart"
    - "packages/grid_sdk/lib/src/command/station_command_handler.dart"
    - "packages/grid_cli/lib/src/pause_command.dart"
  obsoletes: []
  updates:
    - "a43-the-concurrency-governor-where-the-station-default-lives"
    - "a48-a-closed-session-is-dispositioned-done-held-voided-not-b"
    - "adr-0011-federation-and-asset-management"
    - "admission-authority-boundary"
  obsoleted-by: null
  updated-by: []
  bead: tg-5kb
  legacy-id: null
---

# Pause is a non-terminal blocking disposition; resume re-competes for a slot

## Context and Problem Statement

The only way to stop a live session was `grid rework`, which re-keyed the
session and minted a fresh round from the beginning. The durable step beads
already preserve the cursor, and the frontier already prunes completed jobs.
What was missing was an operator state meaning “stop, but do not retire.”

## Considered Options

* Add a terminal close reason and mint a new round on resume.
* Add a paused state to every step bead in the molecule.
* Add `paused` to `grid_runtime`'s process-oriented `LifecycleState`.
* Add one session marker and a non-terminal blocking `SessionDisposition`.

## Decision Outcome

Use one session marker and a non-terminal blocking disposition. The mount
boundary already unmounts a branch whose disposition blocks, and unmounting
already disposes its allocation. Pausing therefore kills the live allocation,
releases the mounted slot, and leaves the session id, work-bead key, gates, and
step beads unchanged. Resuming adopts that same session, so the existing
frontier continues from the first non-complete step.

The operator marker is distinct from `grid_runtime`'s `LifecycleState`, which
models the lifecycle of an individual process and is not consumed by the
engine's mount boundary. A per-step pause was rejected because it would require
multiple writes for a session-level fact and would collide with the step state
used for restart supervision.

The marker has three values: absent/`none`, `paused`, and `resumed`. The public
session-bead update merges metadata and exposes no key removal, so resume must
overwrite the marker. `resumed` also records that a formerly unmounted session
must pass through the ordinary budget-gated pending bin before mounting again.
Once admitted, the branch adopts its preserved session rather than minting.

This extends A43 with a second unmount trigger. It is not a budget eviction:
only an authenticated operator command can park live work. The governor still
never evicts a live branch to make room. A paused session occupies no
concurrency capacity, while resume competes under the same admission rules as
other pending work.

This also extends A48's disposition model to the open half of a session. The
terminal `done`, `held`, and `voided` arms remain unchanged, and terminal state
is evaluated before the pause marker so a stale marker can never resurrect a
closed session.

ADR-0011's unclaimed-frontier hook is narrowed to genuinely live branches. A
paused branch mounts nothing, so broadcasting its capability requirements
would allow peers to claim work for a branch that does not exist. The change
adds no federation transport or claim mechanism. The wedge sampler applies the
same definition of live work so a parked session neither creates a phantom
stall nor masks a real one.

The pause marker is written by the resident command handler through the
existing state chokepoint. It adds neither a branch-owned mint site nor another
admission authority. `StationAdmissionAuthority` owns the release and
readmission decisions: paused rows release their reservation, and resumed rows
join its ordinary priority and capacity competition. An unmounted resumed row
is excluded from capacity use until the authority synchronously admits it; the
authority then charges it before considering the next candidate, so the durable
snapshot row is neither double-counted nor a source of same-flush overshoot.
`WorkList` only projects the authority's admitted, waiting, and refused answers.

`defer` does not pause a session. Deferral remains a scheduled hold, while
pausing is an explicit session-lifecycle operation. Coupling them would restore
the retired defer-as-staging behavior.

## Review log

* 2026-09-02 — authored by **agent** (specify stage of tg-5kb).
