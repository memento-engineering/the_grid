## 0.2.0-rc.10

- Breaking: process groups are supervised as groups and exit status is preserved — `SessionOrphaned` is a new `RuntimeEvent` variant (emitted once, NOT terminal: the group stays supervised until it empties or the bounded grace elapses and it is signalled), so exhaustive switches over `RuntimeEvent` need an arm (tg-8kye, #290). Migration: add `SessionOrphaned()` to every `switch (event)`; power_station#195 is the consumer fix.
- Adopts grid_trajectory 0.2.0-rc.1 (`substation` column).

## 0.2.0-rc.9

- bd 1.3.0-rc.1 compatibility rails rehearsed against the pinned upstream fixture set; a removed or renamed wire key fails the drift suite loudly (tg-1liv, #272).
- Floors tightened to `beads_dart ^0.2.0-rc.7` and `grid_trajectory ^0.1.2`.

## 0.2.0-rc.8

- Breaking: none new in this candidate — it continues the 0.2.0 candidate
  line; `grid_engine 0.3.0-rc.10` and `grid_sdk 0.3.0-rc.8` were published
  against these fixes.
- Graph applies are serialized within each store-scoped writer so admitted
  pours never overlap, and a failed pour drains without poisoning the queue (#256).
- One-turn spawns close argv-only stdin immediately after binding, before
  process-group resolution, so a slow or failing PGID lookup cannot leave a
  stdin reader waiting forever (#253); a raced stop whose stdin close throws
  still terminates, releases, and cleans the registry (#255).

## 0.2.0-rc.7

- Supervised process sessions: `RuntimeProvider` gains `write(name, bytes)` and `interactionOutput(name)`, so a long-lived process keeps stdin open and exposes a raw byte tap. Only long-lived stdout is routed through that tap — one-turn transcripts no longer accumulate unread chunks (#246).
- Stage-1 trajectory obligations (tg-zfek): the tick's shadow-posture obligation set, the stuck-obligation accountant (`attempt.note(channel='obligation-stuck')` plus an operator flare, leaving the obligation open), and the record-keyed settlement exclusion — a settlement whose session predates Stage 1 has no `attempt_id_basis` and is excluded rather than guessed (#245).

## 0.2.0-rc.6

- `createGate`'s reuse/refresh branch now runs the same terminal sweep as the fresh-mint branch — a reused gate targeting a just-retired session is swept instead of dangling (#228).
- The gate-close path refactor preserves both held-session protections (disposition eligibility and the escalation-marker re-read) while supersession is applied before auto-close (#227).

## 0.2.0-rc.5

- Live sessions settle when their work bead closes (#215).
- Molecule reap orders topologically, so dependents retire before dependencies (#216).
- Session reap also retires the session's open mount-attempt record, un-sticking the remount budget (#220).

## 0.2.0-rc.4

- Guarded write capability negotiation with graceful, LOUD fallback (#205) —
  pairs with `beads_dart 0.2.0-rc.4` (floor tightened; the rc.3 archive did
  not compile against any published beads_dart).
- Boot replays the positive-terminal teardown tail, so sessions completed
  under a dead arm settle instead of stranding (tg-tlea).
- Durable per-bead remount budget: a `mount-attempt` record is written at
  admission and consulted before remounting (tg-zlfu).

## 0.2.0-rc.3

- `StationBeadWriter.closeOpenGatesForTerminal` plus the `GateCloseCause` and
  `GateSweepSessionDisposition` enums: the gate auto-close sweep a terminal
  session runs, returning `GateAutoCloseReceipt`s. Consumed by grid_engine's
  `SessionScope` and `WorkList` (tg-3eeg).
- Guarded-write capability negotiation on the bd chokepoint (tg-j0o0 groundwork).

NOTE: 0.2.0-rc.2 was published BEFORE this API landed, and the package kept
accumulating source without a version bump — so the hosted rc.2 archive and the
in-repo rc.2 sources differ. grid_engine 0.3.0-rc.4 shipped against the in-repo
sources and does not compile against hosted rc.2; grid_engine 0.3.0-rc.5 tightens
its constraint to `^0.2.0-rc.3`.

## 0.2.0-rc.2

- `StationBeadWriter.parkSessionAtGate` — the session-lifecycle park distinct
  from the router's gate mint (tg-aec).
- `reapMolecule` degrades to per-bead closes on proxied-server stores, where
  `bd batch` is unsupported — the reap silently threw on EVERY session close
  there, the mechanism behind 9,389 orphaned step beads (tg-ehht).

## 0.2.0-rc.1

- Breaking: `StationBeadWriter`'s constructor now requires `reader:`, a
  `BeadProbeReader`. Its seven lifecycle probes read through that seam instead of
  `BdCliService.exportAll`, which is gone (see beads_dart 0.2.0-rc.1). Migration:
  pass `CliBeadProbeReader(bd, lifecycleTypes: …)` or the SQL reader.
- Fixed: the best-effort catches around those probes no longer convert a refused
  `bd export` into a silent no-op — the reason `reapMolecule` never reaped and the
  gate mint-dedup probe always read empty.

## 0.1.2

- Family coherence release: `StationBeadWriter` current surface (`onFlare`, `writeSpecifyAuthoredSpec`/marker-gated clear the_grid#136, `BeadOwnershipPredicate.ownedPrefixOf`).

## 0.1.1

- Fixed bead-prefix matching to permit hyphens after an owned prefix
  (the_grid #117).

## 0.1.0

- Initial release: runtime providers that spawn and supervise a coding agent per ready bead, isolating each bead's work in a git worktree.
