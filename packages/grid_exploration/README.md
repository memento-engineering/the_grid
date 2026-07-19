# grid_exploration

The `ext.exploration.*` VM-service host — the layer that makes a running
the_grid station **debuggable from outside**.

`grid_exploration` registers lenny's exploration wire protocol over a
`GridControllerRuntime` via `dart:developer` service extensions — pure Dart, no
Flutter binding, no bespoke `ext.grid.*` namespace (ADR-0001 Decision 6). An
external debugging harness (a stock leonard) attaches to the station's VM
service URI, handshakes, discovers the `grid` namespace, and reads live graph
state.

## The surface

- `ext.exploration.core.handshake` — protocol version `'1'`, host identity, and
  the **`extensions` manifest** (`[{namespace: 'grid', tools: [...]}]`). The
  handshake and the registrar read the SAME tool list, so a registered tool is
  always a discoverable tool.
- `ext.exploration.core.get_stable_observation` — empty semantics/routes,
  sync-loop stability, and the grid fragment under `extensions.grid`: read
  path, bead/ready counts, ready-bead summaries, recent events, stats.
- `ext.exploration.grid.{requery,snapshot,ready,events,stats}` — the closed,
  read-only tool set. Every dispatch returns an `{ok, value|error}` envelope;
  a thrown error becomes a `ServiceExtensionResponse.error`, never a silent
  drop.
- `ext.exploration.grid.reload` — **dev-mode only**. It exists only when a JIT
  station under `--enable-vm-service` composes a `ReassembleTool` (the
  station's `hotReload`/`hotRestart` wired in as plain callbacks, so this
  package never depends on `grid_sdk`); an AOT composition passes none and the
  host is exactly the read-only five. The host REFUSES at construction on a
  tool-name collision.
- The event stream — every typed `GraphEvent` is posted via
  `developer.postEvent('grid.controller.event', ...)` in a compact wire shape
  (`graphEventToWire`, an exhaustive switch over the sealed union, so a new
  event variant forces a wire decision).

`GridExplorationHost` splits into **pure JSON builders** (`handshakeJson` /
`observationJson` / `dispatchTool` — unit-tested with no VM service) and a thin
idempotent `register()` that binds them to `dart:developer`.

## "extension", never "plugin"

The org seam word is **extension**. The wire key is `extensions` in both the
handshake and the stable observation, with **no `plugins` fallback** — leonard
≥0.1.0 reads only `extensions` (ADR-0000 A33, ratified; the `ext.exploration.*`
prefix, method names, and protocol version are unchanged). Keep new code, docs,
and wire fields in extension vocabulary; one legacy class name still carries
the old word — its rename is tracked separately; do not add more.

## Testing — pinned conformance fixtures

Three rings, hermetic to fully live:

1. **Offline fixture replay** (`test/conformance_fixture_test.dart`). The
   pinned bytes in `fixtures/exploration/2026-06-15-leonard-extensions/` (repo
   root) are decoded through a leonard-faithful reader — ONLY `extensions`, no
   fallback — and re-produced by today's builders (normalized for the volatile
   `lastRefreshMs`), so any wire drift — a reintroduced `plugins` key, a
   renamed field, a dropped tool — fails offline. Re-capture via
   `tool/capture_conformance_fixture.dart`; never hand-edit the fixtures.
2. **In-process attach** (`test/attach_conformance_test.dart`,
   `test/vm_service_attach_test.dart`). A real VM-service client attaches to
   the test's own process and exercises handshake → observation → a grid tool
   call. Run `dart test --enable-vm-service -t integration`; self-skips when
   the VM service is absent.
3. **Cross-process, real lenny** (`test/leonard_drive_attach_test.dart`,
   `test/leonard_cli_attach_test.dart`). `tool/attach_target.dart` boots a real
   host under its own VM service; lenny's credential-free `leonard_drive`
   driver (strong assertions, zero model calls) and the full `leonard_cli`
   agent loop attach over ws://. Both self-skip when lenny is not discoverable
   (the CLI also when inference credentials are unarmed), so the offline suite
   (`dart test -x integration`) stays hermetic.
