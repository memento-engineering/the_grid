# grid_devtools

DevTools extension for the_grid — **eyes on a running station**.

grid_devtools has two connection paths. VmServiceGridClient performs
ext.leonard.core.handshake and exploration operations over DevTools' shared
VM-service connection. Independently, LiveConnectionController from
grid_station_client discovers or accepts station credentials, and
WebSocketTreeWireSource opens the authenticated StationControl /stream WebSocket for
live TreeSnapshot data.

The exploration view is a handshake header (the host's advertised protocol version +
extension namespaces/tools) over an events timeline. It seeds from the
`ext.leonard.grid.events` ring buffer and then grows live from the
`grid.controller.event` postEvent stream. The station tree projection comes from the
separate `/stream` connection.

## How it connects

Production reuses DevTools' shared, web-safe `serviceManager.service`
websocket pinned to the main isolate — the extension never opens its own
VM-service socket (`vm_service_io` would pull in `dart:io`, which throws on
web). `VmServiceGridClient` borrows that connection and never disposes it.
When the target has no grid host registered, the handshake's JSON-RPC
"method not found" surfaces as `GridBindingMissing` and the shell renders a
distinct "no grid host detected" banner, re-probing on every reconnect.

The live projection path is independent of that shared VM-service connection.
`LiveConnectionController` from `grid_station_client` discovers a station lock or
accepts an explicit control URL and bearer, and `WebSocketTreeWireSource` connects to
the authenticated StationControl `/stream` WebSocket. Under
the_grid#station-control-is-the-operator-and-ui-wire, the VM service is a JIT debugging
convenience while `/stream` is the operator and UI wire; no operator or UI contract
depends on the VM service.

**The wire constants are hand-pinned, deliberately.**
`lib/src/protocol/grid_exploration_client.dart` re-declares the method names —
`kHandshakeExtension` (`ext.leonard.core.handshake`) and
`kEventsExtension` (`ext.leonard.grid.events`) — plus the minimal response
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

Exploration handshakes and events use `GridExplorationClient` (Futures for acts,
Streams for observations); live projections use `grid_station_client`. Production
wires `VmServiceGridClient` for exploration, while widget tests can inject
`test/fake_grid_exploration_client.dart` with no live VM service in the suite.

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
