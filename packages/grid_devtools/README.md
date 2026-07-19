# grid_devtools

DevTools extension for the_grid — **eyes on a running station**.

`grid_devtools` is a Flutter web panel DevTools embeds beside a running grid
process. It attaches over the **exploration protocol only** (ADR-0002
Decision 3): everything it renders arrives through the `ext.exploration.*`
service extensions the `grid_exploration` host registers in the target — it
never links `beads_dart` for live data. The panel is a handshake header (the
host's advertised protocol version + extension namespaces/tools) over an
events timeline that seeds from the `ext.exploration.grid.events` ring buffer
and then grows live off the `grid.controller.event` postEvent stream.

## How it connects

Production reuses DevTools' shared, web-safe `serviceManager.service`
websocket pinned to the main isolate — the extension never opens its own
VM-service socket (`vm_service_io` would pull in `dart:io`, which throws on
web). `VmServiceGridClient` borrows that connection and never disposes it.
When the target has no grid host registered, the handshake's JSON-RPC
"method not found" surfaces as `GridBindingMissing` and the shell renders a
distinct "no grid host detected" banner, re-probing on every reconnect.

**The wire constants are hand-pinned, deliberately.**
`lib/src/protocol/grid_exploration_client.dart` re-declares the method names —
`kHandshakeExtension` (`ext.exploration.core.handshake`) and
`kEventsExtension` (`ext.exploration.grid.events`) — plus the minimal response
shapes as plain value types instead of importing `grid_exploration`: the
contract is the wire JSON, not a Dart symbol. The method-name pin is guarded
by `test/exploration_pin_conformance_test.dart`, which pulls
`grid_exploration` in as a DEV-ONLY dependency (the ship graph is unchanged)
and asserts the pinned literals equal the host's
`coreExtension('handshake')`/`gridExtension('events')` builders. The response
*shapes* are guarded separately, from both sides — this package's
`test/wire_shapes_test.dart` locks the decoders to the `extensions` wire key
(ADR-0000 A33's `plugins`→`extensions` rename; no legacy fallback, matching
leonard's reader), and `grid_exploration`'s
`test/conformance_fixture_test.dart` locks the host's bytes to a pinned
fixture — so drift on either side breaks a test.

Every panel talks through the `GridExplorationClient` seam (Futures for acts,
Streams for observations). Production wires `VmServiceGridClient`; the widget
tests inject `test/fake_grid_exploration_client.dart` — no live VM service
anywhere in the suite.

## Build & run

```sh
flutter test        # offline widget + wire-shape suite (fake client, no VM)

# Compile the web bundle DevTools actually loads (entrypoint lib/main.dart):
dart run devtools_extensions build_and_copy \
  --source=. \
  --dest=extension/devtools
```

DevTools discovers the extension via `extension/devtools/config.yaml` (tab
name `grid`, `requiresConnection: true`) plus the compiled `build/` directory
— see `extension/devtools/README.md` for the layout. A host process surfaces
the tab by referencing this package in its `devtools_options.yaml`; the
target itself must be running `GridExplorationHost.register()` under
`--enable-vm-service` (in `grid_cli`, only the `watch` command registers the
host; the station paths deliberately leave it unregistered), or the panel
shows the binding-missing banner.
