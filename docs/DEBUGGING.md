# Debugging & observing a running station

**Status: descriptive tooling doc** (opened 2026-07-05, docs-debt sweep W5). This is the
home for attach/observe material — deliberately **out of the core docs**: exploration is
a dev/test surface, not the production path, and the grid's core stays uncoupled from any
particular debugging client (sweep ruling R1). The wire protocol itself is a genesis-org
seam; any conforming client can attach.

---

## The exploration surface

The VM-service exploration host (`GridExplorationHost`, `grid_exploration`) is an
optional JIT debugging surface, not the station control plane. It has two composition
shapes:

- armDevMode is the station-side dev-mode boundary. A composed station runner passes it
  the VM-service URI exposed by `--enable-vm-service`, then registers the returned
  `DevModeHost`. Without that URI, `armDevMode` returns null.
  In that case there is no exploration host or reassemble tool.
  The reload verb refuses loudly instead of pretending the station is reloadable.
- The standalone grid_cli binary has no station path.
  Its watch command registers its own host directly over the one work store it reads.

In both shapes, the unit of integration is an **extension** (never "plugin"); the wire
key is `extensions` (A33), and the grid's namespace is `grid` (`kGridNamespace`). The
host is JIT-only: it is not an operator or UI dependency.

**Core methods:**

- `ext.leonard.core.handshake` — protocol version, `bindingType`, and the
  `extensions` list: namespace `grid` + its tool names.
- `ext.leonard.core.get_stable_observation` — the live grid state under
  `extensions.grid`, with a `readPath` marker (e.g. `cli`/`sql`) and a `stability`
  block (`refreshing`, `pendingFollowUp`, `refreshCount`, `lastRefreshMs`).

**The five read-only `grid` tools** (invoked via the protocol's `invoke`):

| Tool | Returns |
|---|---|
| `grid.requery` | forces a re-query; sync stats |
| `grid.snapshot` | bead/ready counts + ready summaries + `capturedAt` |
| `grid.ready` | ready-set summaries |
| `grid.events` | recent typed GraphEvents from the ring buffer (optional `limit`) |
| `grid.stats` | per-origin signal counts, refresh count/latency, in-flight, active read path |

The `grid watch` host advertises those five tools. A station-side dev-mode host also
advertises `grid.reload`, contributed by its optional `ReassembleTool`; that tool is
absent from non-dev compositions.

**Reactivity is push, not poll** (A39): the host co-emits an out-of-band event stream
(`developer.postEvent('grid.controller.event', …)`). Closing a bead in a work store
surfaces `beadClosed` · `beadUpdated` · `readySetChanged` over the wire in real time —
no client-side polling loop.

### grid watch is not a station

`grid watch` is a reader over ONE substation work store. It has no RS-2 lock, engine
kernel, or mounting, so it neither starts a resident station nor supervises station
work. A resident station owns those responsibilities and publishes live `TreeSnapshot`
diagnostics through authenticated StationControl /stream.

| Responsibility | `grid watch` | Resident station |
|---|---|---|
| Input | one substation work store | the composed station's owned stores |
| Runtime | reactive work-graph reader | engine kernel and mounted tree |
| RS-2 lock | none | held by the resident |
| Observation wire | VM service and `ext.leonard.*` | authenticated StationControl `/stream` |

The binding decision the_grid#station-control-is-the-operator-and-ui-wire makes
StationControl the operator and UI wire; no operator or UI contract depends on the VM
service. Run `grid watch` beside a station only when you also want its separate
work-graph exploration view. It is not required to see station diagnostics.

## The grid watch exploration attach flow

1. Launch `dart run --enable-vm-service grid_cli:grid watch <substation-root>`; the Dart
   VM prints the service URI.
2. Attach any exploration-conforming client to that URI. (A credential-free driver is
   enough — the protocol requires no inference; clients that demand a model key will
   self-skip unarmed.)
3. `handshake` → confirm the `grid` namespace + 5 tools.
4. `get_stable_observation` → read live state under `extensions.grid`.
5. `invoke` the `grid.*` tools as needed.
6. Subscribe to the event stream and watch the reader react to store mutations.

The attach regression pin is
`grid_exploration/test/leonard_drive_attach_test.dart`.

## Non-goals

- **No coupling to a specific client.** The grid ships the host and the protocol
  conformance; which driver attaches is the operator's business.
- **No inference in the loop.** Attach/observe is model-free; agent harnesses are a
  separate, production concern (`ADR-0008` Decision 10).
- **Not the station diagnostics wire.** The VM service is the interactive JIT debug
  surface. Station tree diagnostics reach operators and UIs through StationControl
  `/stream`; broader metrics, traces, and sinks remain under ADR-0012.

## DevTools

grid_devtools uses both paths: exploration operations over the VM service and live
station data from StationControl /stream. The exploration half renders the handshake,
tools, and graph events; the independent authenticated stream supplies the station's
live tree projection through `grid_station_client`.
