import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:dtd/dtd.dart';
import 'package:flutter/material.dart';

import 'src/grid_devtools_shell.dart';
import 'src/live/live_connection_controller.dart';
import 'src/live/station_lock_discovery.dart';
import 'src/protocol/grid_exploration_client.dart';
import 'src/protocol/vm_service_grid_client.dart';

void main() => runApp(const GridDevToolsExtension());

/// Top-level extension widget. Wraps [GridDevToolsShell] in [DevToolsExtension]
/// so DevTools provides Material theming and the VM service connection.
///
/// `serviceManager` is a top-level getter that throws until
/// `DevToolsExtension`'s State.initState has run, so any read at or above
/// `DevToolsExtension` fails on the first frame. The [Builder] below pushes
/// the reads into a descendant build call that runs only after
/// `DevToolsExtension` has initialized (the pattern devtools_extensions's own
/// README prescribes, mirrored from lenny's exploration_devtools).
///
/// grid_devtools rides the exploration protocol ONLY (ADR-0002 Decision 3):
/// it reuses DevTools' live, web-safe `serviceManager.service` connection
/// (a `package:web` JS websocket) pinned to the main isolate — it never opens
/// its own VM-service socket (`vm_service_io` would pull in `dart:io`, which
/// throws on web). When the service / main isolate aren't ready, the shell
/// shows the binding-missing state and re-probes on reconnect.
class GridDevToolsExtension extends StatelessWidget {
  const GridDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) => DevToolsExtension(
    child: Builder(
      builder: (BuildContext context) {
        final vm = serviceManager.service;
        final isolateId = serviceManager.isolateManager.mainIsolate.value?.id;
        final GridExplorationClient client = (vm == null || isolateId == null)
            ? const _UnavailableGridClient()
            : VmServiceGridClient(vm, isolateId);
        return _LiveGridDevToolsShell(
          client: client,
          // Reconnects (hot-restart of the target) flip connectedState;
          // the main isolate may appear slightly after. Re-probe on
          // either so the handshake header reflects the live process.
          retrigger: Listenable.merge(<Listenable?>[
            serviceManager.connectedState,
            serviceManager.isolateManager.mainIsolate,
          ]),
        );
      },
    ),
  );
}

class _LiveGridDevToolsShell extends StatefulWidget {
  const _LiveGridDevToolsShell({required this.client, required this.retrigger});

  final GridExplorationClient client;
  final Listenable retrigger;

  @override
  State<_LiveGridDevToolsShell> createState() => _LiveGridDevToolsShellState();
}

class _LiveGridDevToolsShellState extends State<_LiveGridDevToolsShell> {
  late final LiveConnectionController _live = LiveConnectionController(
    discovery: StationLockDiscovery(
      workspaceRoots: () async =>
          (await dtdManager.workspaceRoots())?.ideWorkspaceRoots ??
          const <Uri>[],
      readFile: (uri) async {
        final dtd = dtdManager.connection.value;
        if (dtd == null) {
          throw StateError('Dart Tooling Daemon is not connected');
        }
        final response = await dtd.readFileAsString(uri);
        return response.content ??
            (throw FormatException('DTD returned no text for $uri'));
      },
    ),
  );

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _live.autoDiscover();
  }

  @override
  void dispose() {
    _live.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GridDevToolsShell(
    client: widget.client,
    retrigger: widget.retrigger,
    liveConnection: _live,
  );
}

/// Placeholder client used before the VM service / main isolate are ready.
/// Its handshake reports the host as missing so the shell renders the
/// binding-missing banner rather than crashing; the [retrigger] swaps in a
/// real [VmServiceGridClient] once the connection lands.
class _UnavailableGridClient implements GridExplorationClient {
  const _UnavailableGridClient();

  @override
  Future<GridHandshake> handshake() async => throw const GridBindingMissing(
    'VM service / main isolate not available yet',
  );

  @override
  Future<GridEventsPage> fetchEvents({int? limit}) async =>
      const GridEventsPage(count: 0, events: []);

  @override
  Stream<GridEventRecord> get eventStream =>
      const Stream<GridEventRecord>.empty();
}
