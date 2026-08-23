# grid_cli

the_grid's **CLI SDK** plus a minimal reference bin. the_grid is a framework,
not a turnkey tool: a real station is a composed runner that assembles the
`Command`s it wants from this package (plus its assets' exported Commands) into
its own `CommandRunner`. The `grid` bin here registers only the generic,
asset-agnostic driving verbs — `watch`, `gate`, `rework`, `demo` — and
deliberately carries no composition opinion (there is no baked-in `grid run`;
the compose-never-subclass rule).

```
dart run grid_cli:grid <command> [flags]
```

Run long-lived commands under `dart run --enable-vm-service` so exploration
tools (DevTools, `exploration_cli`, leonard) can attach over
`ext.leonard.*`.

### Reloading a resident

A resident started through `dart run` may execute
`.dart_tool/pub/bin/.../*.snapshot`. That pub App-JIT snapshot is not reloadable
because it has no incremental compiler, even when its VM service is enabled.
`reload` refuses before sending a source-load request; bounce the station
(down, then up) to activate landed code.

A source-launched resident (for example, `dart --enable-vm-service
bin/<runner>.dart up ...`) remains hot-reloadable.

**Stores are addressed at their roots — never cwd discovery.** A substation's
work store lives at `<root>/.beads/` (a positional root or `--note-root`); the
grid's OWN state store — session and gate beads — lives at
`<grid.root>/.grid/.beads/` (`--grid-root`). Writes flow only through the
`StationBeadWriter` chokepoint (`--actor grid-controller`, bd-only, never raw
SQL, never `bd show` on a controller path), ownership-checked fail-closed
against the `--prefix` allow-set.

## `grid watch <substation-root>`

Stream typed graph events (`BeadCreated` / `ReadySetChanged` / `BeadUpdated` /
`BeadClosed`) from ONE substation's live work graph, each with its measured
reaction latency. Read-only; registers the exploration host and prints the VM
service URI. Flags: `--json` (NDJSON, one event per line), `--no-sql` (force
the bd-CLI read path even when pooled Dolt SQL is available),
`--for-seconds N` (fixed duration instead of until Ctrl-C).

## `grid gate`

List and resolve the committee gates The Circuit parks. A gate bead lives in
the state store; closing it re-arms the parked circuit node (gated → pending)
on the next snapshot.

- `grid gate ls --grid-root <dir>` — list every OPEN `type=gate` bead
  (read-only): id, blocked session, parked node, reason, age, and a
  `re-gated Nx` marker on re-gated gates.
- `grid gate resolve <gate-id> --grid-root <dir> --prefix <name>
  [--grade <lane>=<A-F> --rationale <why>]` — close ONE gate through the
  chokepoint. Fail-closed (non-zero exit, zero writes) unless the id names a
  found, OPEN, owned `type=gate` bead. A gate fed by a persisted lane `F` is
  refused LOUD unless you RULE the lane: `--grade` (repeatable, requires
  `--rationale`) writes the corrected grade + `transport=operator-ruling` onto
  the session bead first, so the route re-reads it instead of re-gating. A bare
  `<lane>` resolves to a sibling of the parked node; a token containing `/` is
  a full node path.

## `grid rework <bead-id>`

Mint a fresh rework round for a bead whose session has terminated: clear the
stale specify-authored `design`/`acceptance_criteria` on the WORK bead, re-key
the session's `work_bead` → `<bead>#r<N>` through the chokepoint (a fresh
session mints on the next projection, same worktree), optionally append the
operator's finding to the work bead's notes under a `ROUND N` header, and
report the round number. Refuses LOUD (zero writes) on a live session that is
open and not parked at a gate, and beyond the round cap the engine's rework
contract defines (a human decides past it).

Flags: `--grid-root <dir>` (state store home), `--prefix <name>` (the state
store's owned id-prefix), `--note-root <dir>` (the WORK bead's substation
root — REQUIRED, the spec clear writes there), `--note <finding>` (optional).

```sh
grid rework tg-abc --grid-root /path/to/grid-home --prefix tg \
  --note-root /path/to/substation --note "committee missed the flaky test"
```

## `grid demo`

A zero-setup reactivity proof: spins up a throwaway `bd init` workspace,
watches it, drives a scripted mutation sequence, and tears it down — no
credentials, no live server. No flags.

## Not in this bin

The library also exports `ReloadCommand` and the resident-station surfaces
(`StationControl`, `StationAttach`, `StationLock`, `StationReload`) for a
composed runner to bind; they are deliberately not registered in the reference
bin while the resident-station work is in flight.
# Station composition (running resident)

`grid_cli` vends the `up`, `down`, and `status` verbs for base stations
composed directly on the_grid, running resident in the foreground. A station
supplies its own authored `GridDelegate` factory (grid_sdk's ONE delegate
class, tg-at3r; config-only construction — assembly, circuit resolution, and
the capability registry are the delegate's `boot` concern), roster, and
harness security policy; no subclass or environment registry is imposed:

```dart
final runner = CommandRunner<int>('lunar', 'Lunar station')
  ..addCommand(UpCommand(
    stationName: 'lunar',
    delegateFactory: ({required config}) => LunarDelegate(config: config),
    codedRoster: lunarRoster,
    harnessAllowList: lunarHarnesses.names.toSet(),
    validateHarness: (name) => lunarHarnesses.resolve(name).validate(),
  ))
  ..addCommand(DownCommand(stationName: 'lunar'))
  ..addCommand(StatusCommand(stationName: 'lunar'));
```
