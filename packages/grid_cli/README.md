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

`--until <predicate> --timeout N` blocks until a named condition holds and then
exits 0 (2 on the timeout). The set is CLOSED: `gate-open`, `gate-closed`,
`session-terminal`, `bead-status=<status>`, `ready-count=0`.

## `grid watch --grid-home <home>`

Watch the STATION instead of a substation work graph: the grid state store at
`<home>/.grid/.beads` (gate and session beads) plus the resident's RS-2 lock at
`<home>/.grid/station.lock`. One typed line per event — `--json` makes each an
NDJSON object:

| Event | Line |
|---|---|
| `gate.opened` | `<gate> <bead> <node>` — a gate bead entered the open-gate shape |
| `gate.closed` | `<gate> <bead> <node>` — closed, stripped, or hard-deleted |
| `session.minted` | `<bead>` (the NDJSON record adds `workBead`) |
| `session.terminal` | `<bead> <disposition>` (`done` / `held` / `voided`) |
| `zero-live` | every live session went terminal, after at least one was live |
| `resident.down` | `<reason> [pid <n>]` — the lock is gone, or its pid is dead |
| `heartbeat` | `gates <g> sessions <s> ready <r>` — the census, every `--heartbeat` minutes (default 5; `0` disables), and once at attach |

`--until` takes its own CLOSED set here: `gate-open`, `gate-closed`,
`session-minted`, `session-terminal`, `zero-live`, `resident-down`, `any`
(the first event of any kind BUT the heartbeat — the heartbeat exists to prove
the watch is alive, so it never ends one). The exit contract is 0 when the
predicate held, 2 on `--timeout`, and **3 when the resident went down and that
was not the awaited event** — so a governor's standing arming

```bash
grid watch --grid-home <home> --until any --timeout 2700
```

re-armed by that one line after every relaunch tells "my work moved" from "I
gave up" from "there is no station any more" without parsing prose, and nothing
lives in a scratchpad. The read path is the same pooled Dolt SQL the verb
already uses; `bd show` is never spawned in the loop. Delivery (an open PR
reaching a terminal state) is NOT this verb.

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

Flags: required absolute `--grid-root <dir>` (the grid home); optional
`--note <finding>` or `--note-file <path|->` (mutually exclusive);
`--beyond-cap` authorizes a round past the normal cap and requires both
`--actor <name>` and a note.

```sh
grid rework tg-abc --grid-root /path/to/grid-home --note committee-missed-the-flaky-test
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
    defaultHarness: 'copilot',
  ))
  ..addCommand(DownCommand(stationName: 'lunar'))
  ..addCommand(StatusCommand(stationName: 'lunar'));
```

`harnessAllowList` decides WHICH harnesses are legal; `defaultHarness` decides
WHICH ONE is ambient. Omit it and `--harness` defaults to the allow list's
alphabetically first armed name; supply it — it must be a member, or the
constructor throws `ArgumentError` — and the station boots on that harness with
every other armed name still reachable as `--harness <name>`.
