# SCRATCH — one station, many roots + federated work sources

**Status: SUPERSEDED-IN-PART (2026-07-03) — see `SCRATCH-grid-alignment.md`. §3's D-M1..M7
design FOLDED FORWARD (2026-07-19) into ADR-0011's ratified amendment, with verified build
status (partially landed via the v3 SDK rail).** The realignment
session ruled the remote half of §4b WRONG for the target model: remote substations are never
snapshot members (D-Z7 is dead) — federation is by WORK ASSIGNMENT (claim-first-local →
broadcast-unclaimed → capability-matched claim → lease), designed in the alignment surface. The
LOCAL content SURVIVES and resumes under that frame: §3 multi-root (tg-7gm, D-M1..M7) and §4's
local multi-store half (tg-nsj re-scoped to local stores, D-F1..F7) plus §4b's durable pieces
(absence ≠ deletion, staleness fail-closed, discovered ≠ blessed, membership-as-observed-state).
§5's OQ-1..6 still want rulings when this pass resumes (alignment ladder AL-2/AL-3).

**Was: discovery surface (2026-07-03), awaiting Nico's rulings.** Refines the two deferred P0
beads filed at the first live boot — **tg-7gm** (multi-root) and **tg-nsj** (federated work
sources, dep: tg-7gm). Written from a read-only discovery pass (two seam scouts + operator
verification against the live stores). Doc-before-code: nothing here is built until the rulings
land and the beads are blessed. Rulings log in §6.

## 1. The ask

Nico (2026-07-03): *boot the space station with all of memento-engineering, butane_flutter, and
.dashboard.* Today the runner binds ONE work workspace + ONE root per boot, so the first live boot
covered exactly (tg store × the_grid repo). The gap is two orthogonal axes:

- **Many roots** (tg-7gm): memento work alone spans ≥4 repos (the_grid, power_station,
  space_station, genesis). A bead must build in a worktree cut from *its* repo.
- **Many stores** (tg-nsj): the three targets are three separate bead stores —
  `tg` (server mode, city Dolt at `127.0.0.1:34947`), `butane_flutter` (server mode, db
  `butane_flutter` on the SAME city server — a gc rig, `gc.endpoint_origin: inherited_city`,
  `dolt.auto-start: false`), `dash` (`.dashboard`, embedded mode, db `dash`).

One station per machine (Nico's D-A1-adjacent ruling) — so both axes land in ONE resident station,
one state store (`tgdog`), one lock.

## 2. Ground truths (evidence)

### The engine is already multi-substation; the composition layer collapses it

- `Station` is a `MultiChildSeed` of `SubstationScope`s; **each scope provides its own
  `ServiceBundle` + `SubstationConfig`** (`substation_scope.dart:91-98`) and builds one `WorkList`
  that filters the shared snapshot by **its own `ownedSubstations`**
  (`work_list.dart:79-99` via `BeadOwnershipPredicate`; prefix = leading dash segment,
  `bead_ownership.dart:78-82`).
- `SubstationConfig.substationId` is identity/keying only (scope key, session partition, worktree
  dir segment); **`ownedSubstations` alone gates mounting**.
- **Per-scope source control is proven**: `substation_service_bundle_test.dart:108-154` boots two
  scopes with two bundles and asserts each bead provisions through ITS scope's `SourceControl`.
- Production collapses it: `code_run_command.dart:155-161` / `up_command.dart:178-186` compose
  **one** `SubstationConfig` (`substationId: first, ownedSubstations: ALL`), and `composeStation`
  hands **the same `ServiceBundle` instance to every scope** (`station_runner.dart:696,704-712`).
- Provisioning resolves the **nearest** `ServiceBundle` (`session_scope.dart:266-275`,
  `allocation.dart:504-524`) → `GitSourceControl._root` → worktrees at
  `<root>/.grid/worktrees/<substation>/<bead>` (`station_git_service.dart:165-169,305-316`).
- `RootCheckout` is **already substation-keyed** (`station_git_service.dart:19-42`);
  `registerRootCheckout` validates the repo + probes/assigns head, never clones (`:261-294`).
  Today `buildLiveWiring` registers exactly one, stamped `substation: args.substations.first`
  (`station_runner.dart:589-608`).

### The two real breaks multi-root must fix

- **`devRoot` (pub-link absolutization) is station-wide.** `AgentCapability._devRoot` is baked by
  `buildCodeRegistry(devRoot: live.workRoot.path)` and provided ONCE above `Station`
  (`station_kernel.dart:100-103`; `pub_links.dart:203-247` fail-closed absolutization;
  `code_capabilities.dart:131-145`). With N roots, a bead in substation B would absolutize its
  relative `dev_path`s against substation A's root → wrong `path:` overrides. The one genuine
  capability-plumbing change.
- **`RestartReconciler` is single-root** (`restart_reconciler.dart:246-259,294,336`): it lists and
  reaps only under its one root's `.grid/worktrees`. With N roots, survivors under other roots are
  never reconciled → orphan-worktree leak + double-run risk.
- Also: **overlapping `ownedSubstations` double-mounts** — each `WorkList` filters the full graph
  independently; nothing de-dups a bead across scopes. Safe today only because there is one scope.

### The snapshot/read path is per-workspace; nothing unions stores

- `GridRuntimeFactory` picks per workspace: server mode + endpoint + credential + connect/drift OK
  → SQL (pool **clamped ≤2**, 30s-reap-aware, `dolt_query_service.dart:75,236-242,445-457`);
  otherwise bd-CLI + 5s polling ticker. Both paths add a `.beads/` breadcrumb watcher.
  Change probe is **database-scoped**: `SELECT @@<db>_working` at 1s (`dolt_query_service.dart:91`).
- **`readyIds` always comes from `bd ready`** — on the SQL path too
  (`snapshot_readers.dart:32-37,59-69`).
- `BeadsWorkspace` captures root/mode/db/endpoint — **no prefix** (`beads_workspace.dart:20-40`);
  `discoverWorkspaces` resolves exactly one work + one state workspace.
- **`bd ready` is blind to cross-store deps**: a cross-prefix target is stored as
  `depends_on_external` (`dependencies.go:54-62,22-31`) and the `is_blocked` recompute **never
  reads that column** (`blocked_state.go:123-165,229-271`) — a bead blocked by a foreign store is
  reported ready regardless. `routes.jsonl` is only a lazy per-id resolver (`routed.go:134-214`),
  never a graph federation. **Measured 2026-07-03: zero cross-prefix deps exist in any of the
  three stores.**
- `StationJoinBridge` is **the lone pipeline subscription** (A39/inv-1): two axes (work + state),
  state projected to `sessionsByWorkBead` — never merged into the graph; producer-side
  `latest`+`repush` intact (`station_join_bridge.dart:99-125,153-166`). The `SnapshotSource`
  contract a union must honor: change-gated, broadcast, non-replaying, `current`, one push per
  real change. **Fan-in must happen BEFORE the bridge.**
- **bd-native federation exists but doesn't fit**: `bd repo add` + `bd repo sync` (bd-307)
  hydrates N repos into one db — but it is pull-based over `issues.jsonl` (staleness = sync
  cadence), **requires direct database mode** (`repo.go` `ensureDirectMode` — the tg store is
  server-mode), and would materialize foreign beads inside the db gc watches. Considered, rejected
  for now (recorded, not a dead end forever).

### Store facts for the three targets

| store | prefix/db | mode | expected read path | notes |
|---|---|---|---|---|
| the_grid | `tg` | server (city 34947) | SQL when creds resolve; observed CLI at first live boot | gc coexists on this server |
| butane_flutter | `butane_flutter` | server (SAME city server) | SQL when creds resolve, else CLI | a gc rig; **reads only**; its 11 open beads deferred 2026-07-03 pending grooming |
| .dashboard | `dash` | embedded | CLI + polling | standalone; its 8 open beads deferred 2026-07-03 pending grooming |

## 3. Proposed decisions — multi-root (tg-7gm)

- **D-M1 — Root granularity = per-substation (the scope), not per-bead.** A bead inherits its root
  from the scope it mounts under; ownership routing already does the bead→scope half. No new
  per-bead axis.
- **D-M2 — Symmetric pairing grammar.** Repeatable `--root <substation>=<path>`; bare
  `--root <path>` stays as the single-substation shorthand (back-compat). `--head` becomes
  per-root: `--root <substation>=<path>@<head>`; the global `--head` is refused when >1 root
  (ambiguous). The same `<substation>=` pairing is reused by `--workspace` in §4 — one grammar,
  one join key.
- **D-M3 — One scope per substation; disjointness fail-closed.** Composition builds one
  `SubstationConfig` per owned work substation with `ownedSubstations: {itself}`;
  `composeStation` refuses overlapping owned-sets LOUD (the double-mount guard — protects a named
  invariant: one bead, one agent). The WRITER's allow-set stays the union (+ state substation),
  unchanged.
- **D-M4 — Rooting is a DRIVEN-SET obligation** *(amended §4b)*. A live arm refuses at
  `validateArming` when any OWNED work substation lacks a registered root — you own it, you root
  it. Deterministic, and per the §5 failure-discrimination principle
  (SCRATCH-orchestration-determinism): a configuration defect is an arming refusal, never a
  mount-time surprise or a gate. Under dynamic membership the same gate applies at JOIN time to
  the driven set only — an observed-not-owned member needs no root (D-Z5).
- **D-M5 — `devRoot` resolves per scope.** Pub-link absolutization reads the root off the ambient
  per-scope `ServiceBundle.sourceControl` (expose the root path on the `SourceControl` surface)
  instead of a station-wide constructor bake. `buildCodeRegistry(devRoot:)` loses the parameter
  (or keeps it as an explicit override for tests). The one plumbing change at depth.
- **D-M6 — One `RestartReconciler`, fanning out over N roots.** List+reap per root (each root gets
  its own scope gate), project session cursors ONCE (one state store), one freshness barrier, one
  pass in the pinned start ordering. N independent reconcilers would multiply barriers and
  ordering for no gain.
- **D-M7 — Roots multiply; the state store and lock do not.** N work roots ride ONE `tgdog` state
  store, ONE session partition, ONE RS-2 lock. Unchanged.

## 4. Proposed decisions — federated work sources (tg-nsj)

- **D-F1 — `FederatedSnapshotSource`, fan-in before the bridge — with MUTABLE membership**
  *(amended §4b)*. A union source owns the member subscriptions internally and exposes ONE
  change-gated `SnapshotSource`. The bridge keeps its two axes and its lone-subscription invariant
  untouched (A39/inv-1). NOT fixed-N at construction: the union observes a membership set and
  attaches/detaches member sources at runtime (§4b) — static flags are merely the first membership
  source.
- **D-F2 — Ready semantics: union + the external-dep guard.** `readyIds` = union of per-store
  `bd ready` sets, THEN: for any bead carrying an external dep whose target IS in the federation,
  apply the block in Dart (resolve it — we have both stores); whose target is OUTSIDE the
  federation, exclude the bead from ready **fail-closed + LOUD** (a false negative an operator can
  see beats a false positive that spawns unprerequisited work). Zero cross-store deps exist today
  (measured), so this guard costs nothing until someone creates one — and then it is already
  correct.
- **D-F3 — Union identity + coalescing: a per-member freshness vector** *(amended §4b)*.
  Per-member `latest` retained; any member emission rebuilds the union; the union emits only when
  `diffSnapshots(previous, next)` is non-empty (the honest change gate). The union carries a
  freshness VECTOR ({member → capturedAt, presence}) rather than one `capturedAt` — the scalar
  `capturedAt` = max of the parts for the existing field, but staleness is judged per member
  (§4b). The freshness barrier re-queries ALL live members (requery fans out).
- **D-F4 — Store membership is an OBSERVED SET; explicit flags are its first source — never
  `routes.jsonl`** *(amended §4b)*. Repeatable `--workspace <substation>=<path>` (bare
  `--workspace <path>` = single-store shorthand) populates a static `MembershipSource` — the same
  posture as `grid_federation`'s deliberately-static `Membership` (ADR-0011 D4), and the same
  promise: zero-conf discovery drops in BEHIND the seam later as `zero_conf_grid_assets`, it does
  not reshape it. Routes are bd's lazy id-resolver, not an observation opt-in; entry into the
  observed set is ALWAYS a policy decision (§4b trust gate). The `<substation>` key is the join
  key across `--workspace` / `--root` / `--substation` — one triple per covered store.
- **D-F5 — Probe cardinality: N-per-store as built, optimization deferred.** N watchers + N probes
  (1s SQL probe or 5s CLI ticker per store) + ≤2 pooled connections per SQL store. The
  single-connection multi-`@@<db>_working` probe (one round-trip for N same-server dbs) is a
  follow-up optimization bead, not P0. gc coexistence bound: the city server carries tg AND
  butane_flutter — worst case 4 pooled connections + 2 probes against it; acceptable, monitored.
- **D-F6 — Federation of work sources is strictly READ-ONLY, per store.** A37 holds for every
  foreign source; sessions/cursors write only to `tgdog` through the chokepoint. Explicitly
  distinct from ADR-0011/M6 (asset/lease federation): this SCRATCH federates *observation of work
  graphs*, nothing else. The butane_flutter store is a live gc rig — reads only, pool bounds per
  D-F5, never mutate beads gc owns.
- **D-F7 — bd-native hydration (bd-307) rejected for now.** Direct-mode requirement vs our
  server-mode tg store; JSONL pull staleness; foreign beads materialized in the gc-watched db.
  Revisit only if bd grows server-mode, live hydration.

## 4b. Dynamic membership — the zero-conf forward-compat frame (added 2026-07-03, Nico's check)

Nico's challenge while reading v1: *make sure we operate under future assumptions w.r.t.
zero-conf/mDNS federations — v1 smelled of static remote-station configuration.* Audit result:
three static assumptions were embedded (fixed-N union, boot-time-only scope list, boot-time-only
rooting gate). The codebase already points the way — `grid_federation`'s membership is
**deliberately static by ratified decision** (ADR-0011 D4) with the dynamic seam named:
*"shaped so dynamic discovery drops in BEHIND it later as `zero_conf_grid_assets`"* — and
`Presence` already carries the **capability-durable / capacity-ephemeral** split. This section
applies the same discipline to work-source observation, so tg-7gm/tg-nsj build against seams
zero-conf can drop behind without reshaping anything.

- **D-Z1 — Membership is observed state, not constructor config.** A `MembershipSource` notifier
  holds the observed member set {substation → (workspace | remote endpoint, root?)}. The static
  flag triples (D-F4) are the FIRST source impl; a zero-conf browser is the SECOND, behind the
  same seam. Consumers never know which produced the set.
- **D-Z2 — Scopes reconcile from membership.** `Station` is already a `MultiChildSeed` of keyed
  `SubstationScope`s; the scope list derives from the observed membership set, so a member
  joining/leaving mounts/unmounts exactly that scope by keyed reconcile — the M4 doctrine
  ("config nodes are observed ancestors of work nodes") applied to membership. The substation
  prefix is the reconcile KEY, so identity is stable across disappear/reappear. With the static
  source this degenerates to today's boot-time list; no behavioral change until a dynamic source
  exists.
- **D-Z3 — Absence ≠ deletion (the durable/ephemeral split, applied to snapshots).** Work-graph
  truth is DURABLE (dolt); presence is EPHEMERAL. A member going dark (mDNS goodbye, partition,
  connection reap) is a presence event: its last snapshot is RETAINED frozen and marked stale in
  the freshness vector (D-F3). The union NEVER synthesizes bead-disappearance from lost
  connectivity — the tree must not see a network flap as a mass bead-deletion.
- **D-Z4 — Staleness is fail-closed for NEW work only.** A stale member's ready set stops minting
  NEW mounts (its truth can't be refreshed — fail-closed, LOUD in status); in-flight sessions
  continue untouched (A40 positive-terminal-only unmount already protects them). Reappearance
  refreshes the member snapshot and re-opens minting — one gated union emission either way.
- **D-Z5 — Ownership (drive) ⊥ membership (observe).** Owning a substation = intent to DRIVE it =
  must be rooted (D-M4 applies at the moment it joins the DRIVEN set — arming time for static
  members, join time for dynamic ones). A member observed but not owned (e.g. a discovered peer's
  store) mounts NO work here — its work is visible (status, future topology views), never driven
  (claim-in-own-store stays with the owning station, per the parked ADR-0011 sketch). This
  dissolves OQ-2's tension: refusal guards the DRIVEN set; observe-only needs no root.
- **D-Z6 — Discovered ≠ blessed: the trust gate.** Entry from DISCOVERED (a zero-conf answer) to
  OBSERVED (a mounted member) passes a Trust decision — allow-list now (LAN trust, the same
  posture as `Peer.token`), reputation/ledger impls later (ADR-0008's `Trust` seam). Exactly the
  store-hygiene shape: ready=in needed grooming; discovered=in needs a gate. The gate is LOUD both
  ways (admitted / refused, with the claimed identity named) per the guard principle.
- **D-Z7 — A remote member is just another `SnapshotSource` impl.** The union consumes the same
  contract (change-gated, broadcast, non-replay, `current`, one push per real change) whether the
  member is a local bd/SQL workspace or a future remote station surfacing its work graph over the
  bus/control-plane transport (D-C5's unified-substrate want; ADR-0012's exploration transport).
  Nothing in the union changes when members go remote — that is the test the seam must pass.
- **D-Z8 — `zero_conf_grid_assets` is designed as its own surface, consumed twice.** One discovery
  asset (mDNS/DNS-SD advertise + browse; service instance carrying station id, control endpoint,
  offered substation prefixes, trust hints) slots behind BOTH existing seams: `grid_federation`'s
  `Membership` (the lease bus) and D-Z1's `MembershipSource` (work-source observation). Designing
  it belongs to the ADR-0011 orbit (Nico's parked ADR) — this SCRATCH only pins the contracts it
  must drop behind; a companion `SCRATCH-zero-conf-membership.md` is drafted on Nico's word
  (OQ-7). Build order unchanged: tg-7gm/tg-nsj ship with the static source; zero-conf is the
  second source, not a prerequisite.

## 5. Open questions for Nico

- **OQ-1 — Substation keys.** The foreign substations enter the allow-set as their id prefixes:
  `butane_flutter` and `dash`. Confirm (they become worktree dir segments + scope keys + flag
  grammar keys).
- **OQ-2 — D-M4 strictness.** Live arm REFUSES when an owned substation lacks a root (proposed) —
  vs. loud mount-time skip. Refusal is stricter and can't silently under-cover; skip lets a
  partially-rooted station run. Which? *(Reframed by D-Z5: refusal guards only the DRIVEN set —
  an observed-not-owned member needs no root, so strictness costs nothing at the federation
  boundary.)*
- **OQ-3 — The pairing grammar** (`--workspace/--root <substation>=<path>[@head]`, D-M2/D-F4) —
  bless the shape? (It lands twice by hand: `addStationFlags` + the `up` hand-mirror.)
- **OQ-4 — Landing surface for foreign repos.** The land step would open PRs on
  `nicholasspencer/.dashboard` and `nicholasspencer/butane_flutter` (gh auth already spans them?).
  OK, or commit-only (no `--land`) for foreign substations at first?
- **OQ-5 — The circuit for foreign work.** Same `code` circuit + committee rubrics for dash/butane
  beads? Grooming must stamp a worktree-relative `validation_plan` on every blessed bead (the I-3
  lesson; OP-1 preflight will enforce once landed).
- **OQ-6 — Scope of the first build.** tg-7gm alone already unlocks all-of-memento (4 repos, one
  store). tg-nsj adds the two foreign stores. Build strictly in that order (proposed), or demand
  both before the next boot?
- **OQ-7 — The zero-conf companion.** Bless drafting `SCRATCH-zero-conf-membership.md` (the
  `zero_conf_grid_assets` design surface, feeding the parked ADR-0011: mDNS/DNS-SD service shape,
  what the TXT record carries, the D-Z6 trust-gate default, and the two consuming seams)? Design
  only — build order stays static-first (D-Z8). And confirm the LAN-trust default for the gate:
  allow-list-only this round (matching `Peer.token`)?

## 6. Rulings log

*(awaiting Nico)*

## 7. The ladder (sketch, filed after ratification)

- **tg-7gm** (parent) → MR-1 pairing grammar + `StationArgs` map + `validateArming` (D-M2/D-M4);
  MR-2 `buildLiveWiring` N-root registration + `composeStation` per-substation
  config/bundle pairs + disjointness guard (D-M1/D-M3); MR-3 `devRoot` per scope (D-M5); MR-4
  restart fan-out (D-M6); MR-5 the `up` hand-mirror + status view per-substation counts (folds
  tg-8p9's display fix).
- **tg-nsj** (parent, dep tg-7gm) → FS-1 multi-workspace discovery + N controller runtimes; FS-2
  `FederatedSnapshotSource` (D-F1/D-F3) + the external-dep guard (D-F2); FS-3 runner wiring +
  banner/status per store; FS-4 (optional, deferred) the single-connection multi-db probe.
