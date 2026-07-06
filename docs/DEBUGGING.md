# Debugging & observing a running station

**Status: descriptive tooling doc** (opened 2026-07-05, docs-debt sweep W5). This is the
home for attach/observe material — deliberately **out of the core docs**: exploration is
a dev/test surface, not the production path, and the grid's core stays uncoupled from any
particular debugging client (sweep ruling R1). The wire protocol itself is a genesis-org
seam; any conforming client can attach.

---

## The exploration surface

A running station registers a VM-service host (`GridExplorationHost`,
`grid_exploration`) under the org's exploration protocol. Vocabulary: the unit of
integration is an **extension** (never "plugin"); the wire key is `extensions` (A33);
the grid's namespace is `grid` (`kGridNamespace`).

**Core methods:**

- `ext.exploration.core.handshake` — protocol version, `bindingType`, and the
  `extensions` list: namespace `grid` + its tool names.
- `ext.exploration.core.get_stable_observation` — the live grid state under
  `extensions.grid`, with a `readPath` marker (e.g. `cli`/`sql`) and a `stability`
  block (`refreshing`, `pendingFollowUp`, `refreshCount`, `lastRefreshMs`).

**The five `grid` tools** (invoked via the protocol's `invoke`):

| Tool | Returns |
|---|---|
| `grid.requery` | forces a re-query; sync stats |
| `grid.snapshot` | bead/ready counts + ready summaries + `capturedAt` |
| `grid.ready` | ready-set summaries |
| `grid.events` | recent typed GraphEvents from the ring buffer (optional `limit`) |
| `grid.stats` | per-origin signal counts, refresh count/latency, in-flight, active read path |

**Reactivity is push, not poll** (A39): the host co-emits an out-of-band event stream
(`developer.postEvent('grid.controller.event', …)`). Closing a bead in a work store
surfaces `beadClosed` · `beadUpdated` · `readySetChanged` over the wire in real time —
no client-side polling loop.

## The attach flow

1. Boot the station (a dry-run works; each run prints its live VM-service URI).
2. Attach any exploration-conforming client to that URI. (A credential-free driver is
   enough — the protocol requires no inference; clients that demand a model key will
   self-skip unarmed.)
3. `handshake` → confirm the `grid` namespace + 5 tools.
4. `get_stable_observation` → read live state under `extensions.grid`.
5. `invoke` the `grid.*` tools as needed.
6. Subscribe the event stream and watch the kernel react to store mutations.

Proven live 2026-06-18 (tg-e28, A40): a stock external driver attached to a real
`grid run --dry-run`, completed the handshake, observed live state, invoked all tools,
and watched reactivity events arrive as beads changed — coexistence-safe (self-owned
temp store, nothing live touched). The regression pin is
`grid_exploration/test/leonard_drive_attach_test.dart`.

## Non-goals

- **No coupling to a specific client.** The grid ships the host and the protocol
  conformance; which driver attaches is the operator's business.
- **No inference in the loop.** Attach/observe is model-free; agent harnesses are a
  separate, production concern (`ADR-0008` Decision 10).
- **Not the observability story.** Metrics/traces/sinks are reserved for ADR-0012
  (observable-source first-class; OTel and perception as co-emitted sinks). This doc is
  the interactive debug surface only.

## DevTools

`grid_devtools` (the only Flutter package) rides the exploration protocol exclusively —
it never links the beads client directly for live data (ADR-0002 D3). Same wire, same
tools, rendered.
