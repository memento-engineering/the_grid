# EffectContext → StationServices cleanup (build order)

**Status:** READY TO BUILD (offline). **Completes ADR-0008 D5** (SourceControl is a
per-substation responsibility; the engine knows source control in *concept*, not *detail*) and
finishes the ADR-0009 D2/D3 migration (relationships ride scoped `InheritedSeed`s; depend-on-context
is the norm). **No new decision** — it removes a pre-Allocation-Tree grab-bag that the D5 migration
left behind. Not a new ADR; a forward-pointer note lands on ADR-0008 D5 if Nico wants one.

## The finding

`EffectContext` is constructed once (`run_tree_command.dart`) and provided as ONE **station-level**
`InheritedSeed<EffectContext>` at the kernel root — yet it mixes three scopes:

| Field | True scope | Problem |
|---|---|---|
| `provider`, `writer`, `stateSubstation`, `liveness` | **Station** (one per machine) | ✅ genuinely ambient — the legit residue |
| `worktreeRoot`, `workSubstation`, `baseBranch` | **Substation** | duplicates `GitSourceControl._root` (`RootCheckout.path/substation/defaultBranch`) at the `SubstationScope` |
| `gitOps`, `prOpener` | — | dead as a seam — the engine never reads them; laundered through `EffectContext` only to be read back in the same file to build the `ServiceBundle` |
| `worktreeFor()`, `branchFor()` | — | **opinion leak** — the engine hardcodes the git worktree layout `<root>/.grid/worktrees/<sub>/<bead>` + `grid/<bead>`, duplicating `WorktreeLayout` in `grid_runtime` (violates ADR-0007 §1 opinion-free kernel + ADR-0008 D5) |

The "one `dependOn` instead of three" rationale that justified the bundle was retired by ADR-0009 D3
("depending on context is the norm"). The runtime's "build from source (git worktree per bead)"
assumption should be a **SourceControl opinion**, not an engine axiom.

## Target shape

- **Station level** (kernel root): a small **`StationServices`** = `{ provider, writer,
  stateSubstation, liveness }` — the MediaQuery pattern done right (related ambient data, one lookup,
  *only* station concerns). This is `EffectContext` shrunk.
- **Substation level** (`SubstationScope`, beside the existing `ServiceBundle`): the workspace + branch
  a capability runs in come **from `SourceControl`** (new `workspaceFor(beadId)` / `branchFor(beadId)`
  / `baseBranch`), computed by the git impl from its own `RootCheckout` via `WorktreeLayout`. The
  engine's worktree layout is DELETED.
- `gitOps` / `prOpener` are built straight into `GitSourceControl` at composition; they stop touching
  the engine.

Net: `EffectContext` → `StationServices`; the git/worktree/build-from-source opinion moves entirely
behind `SourceControl`. A non-git / non-source effect (a leased remote box, a container) becomes
expressible.

## Tracks (offline, per-commit, behavior-preserving)

- **E1 — SourceControl owns the layout (additive).** Add `workspaceFor(String beadId)` /
  `branchFor(String beadId)` / `String get baseBranch` to the `SourceControl` interface; implement in
  `GitSourceControl` (delegating to `WorktreeLayout.worktreePath(_root.path, _root.substation, beadId)`
  / `WorktreeLayout.branchFor(beadId)` / `_root.defaultBranch` — **verified identical** to
  `EffectContext.worktreeFor`/`branchFor`, so no behavior change). Update every `SourceControl` test
  fake. Green.
- **E2 — shrink EffectContext → StationServices + move derivation.** The Host derives
  `workspaceDir` / `branch` / `baseBranch` from `_services.sourceControl` (a synthetic
  `/grid/worktrees/<bead>` + `grid/<bead>` fallback when no source control is wired — offline tests);
  rename `EffectContext` → `StationServices` and DROP the moved fields (`worktreeRoot`/`workSubstation`/
  `baseBranch`/`gitOps`/`prOpener`/`worktreeFor`/`branchFor`); `run_tree_command` builds
  `GitSourceControl(gitOps:…, prOpener:…, provisioner:git, root:workRoot)` DIRECTLY; update
  `station_kernel` / `session_scope` / `capability_host` / tests. Green.
- **E3 — adversarial review.** A read-only `Explore` refute pass: is the derived workspace/branch
  byte-identical to the old path? does anything still read the deleted fields? did the opinion-leak
  actually leave the engine (no `.grid/worktrees` / `grid/$` literal in `grid_engine/lib`)? Fold.

## Definition of done

1. `StationServices` carries only station ambient (`provider`/`writer`/`stateSubstation`/`liveness`).
2. `SourceControl` owns `workspaceFor`/`branchFor`/`baseBranch`; the engine names no git worktree
   layout (a structural fence: no `.grid/worktrees` / `grid/$` literal in `grid_engine/lib/src`).
3. `gitOps`/`prOpener` never transit the engine.
4. `melos analyze` clean + the full offline suite green across all packages; every prior contract
   (the derived workspace path unchanged) preserved.

## Safety rails (carried)

Offline only (fakes / temp repos; no live `claude`/`git`/`bd`); coexistence (`tg` read-only,
sessions → `tgdog`, never `.beads/hooks/`); the codec boundary + `kGridNamespace` untouched; commit
don't push; the first LIVE arm stays the human gate.
