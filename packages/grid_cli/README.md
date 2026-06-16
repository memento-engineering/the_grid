# grid_cli

The management CLI for the_grid. Run it under `dart run --enable-vm-service` so
exploration tools (DevTools, `exploration_cli`, leonard) can attach over
`ext.exploration.*`.

```
dart run grid_cli:grid <command> [flags]
```

## Subcommands

### `grid watch`

Stream typed graph events (`BeadCreated` / `ReadySetChanged` / `BeadUpdated` /
`BeadClosed`) from the live work graph, each with its measured reaction latency.
Read-only. Flags: `--json` (NDJSON), `--no-sql` (force the bd-CLI read path),
`--for-seconds N`.

### `grid demo`

A zero-setup reactivity proof: spins up a throwaway `bd init` workspace, drives a
scripted mutation sequence, and tears it down — no credentials, no live server.

### `grid run`

The M3 dogfood composition (M3-BUILD-ORDER Track 7). One process that wires
together the three the_grid loops over a **single shared ownership allow-set**:

1. **the M1 reactive controller** — exactly what `grid watch` builds (workspace
   discover → `GridRuntimeFactory.build` → `GridExplorationHost.register()` →
   `runtime.start`), so leonard can attach and observe live grid state;
2. **the M2 convergence reconciler** (`ReconcilerRuntime` over
   `GridConvergenceSource` + `BdActuator` + `GateEvaluator` + `OwnsRigs`) — the
   reduce→gate→actuate spine for owned convergence loops;
3. **the M3 dispatcher** (`DispatchInteractor` over a `ReadyWorkSource` + the
   chosen `RuntimeProvider`) — a ready work bead → a `claude` subprocess in a git
   worktree, tracked as a session bead through the single `GridBeadWriter`
   bd-write chokepoint.

**One source of truth for ownership.** The `--rig`/`--owner` allow-set is parsed
into ONE `Set<String>` that seeds BOTH the M2 `OwnsRigs` convergence-actuation
gate AND the Track-4 `BeadOwnershipPredicate` (dispatch + the write chokepoint) —
never two copies, so the two gates cannot drift (ADR-0006 Decision 1 / ADR-0000
A32).

**`--dry-run` is the SAFE DEFAULT (observe-only).** A dry run constructs the full
wiring but performs **no writes and no spawns**: the dispatcher short-circuits
before any worktree/spawn/bd write, and the reconciler is wired with
`OwnsNothing` so it actuates nothing (it still reduces every owned loop for
diagnostics). A non-dry (**live**) run is the writing arm and is gated behind
explicit `--no-dry-run` **plus** a registered `--root`; it is never armed
automatically.

| Flag | Default | Meaning |
| --- | --- | --- |
| `--rig`, `-r` (repeatable) | — (required) | An owned rig / ownership token. The dogfood rig is `tgdog`. |
| `--owner` (repeatable) | — | Alias for `--rig`; merged into the same shared set. |
| `--provider` | `subprocess` | `subprocess` (the Friday dogfood default) or `tmux` (the gc-compatible alternative). |
| `--root` | — | The registered worktree root checkout under `engineering.memento` (e.g. `…/lenny-tgdog`). Required to arm a non-dry run; never created by `grid run`. |
| `--dry-run` / `--no-dry-run` | `--dry-run` | Observe-only vs the live writing arm. |
| `--for-seconds N` | — | Run for a fixed duration then exit (scripted demos / CI). |
| `--no-sql` | off | Force the bd-CLI read path. |

```sh
# Safe observe-only run against the tgdog allow-set (the default):
dart run --enable-vm-service grid_cli:grid run --rig tgdog

# The live writing arm (requires ADR-0006 ratification + a registered root):
dart run --enable-vm-service grid_cli:grid run \
  --rig tgdog --no-dry-run \
  --root /Users/nico/development/engineering.memento/lenny-tgdog
```

#### Safety boundaries

- **bd-only writes through one chokepoint** (`GridBeadWriter`,
  `--actor grid-controller`, never raw SQL, never `bd show` on a controller
  path); every session/recovery write is ownership-re-checked fail-closed.
- **The agent token rides the env allowlist, never argv** — the
  `SubprocessProvider` forwards `CLAUDE_CODE_OAUTH_TOKEN` (and the rest of the
  allowlist) into the child while keeping `GC_DOLT_PASSWORD` and other host
  secrets out.
- **Worktrees are containment-scoped** under the registered root; the three-gate
  reaper refuses to remove a worktree with uncommitted/unpushed/stashed work.
- Non-owned ready beads and gc-owned convergence loops are observed read-only,
  never dispatched, never mutated (`.beads/hooks/` untouched).
