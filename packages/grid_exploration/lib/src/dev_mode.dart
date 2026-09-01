/// The reusable host composition for a station's explicit JIT reload trigger.
library;

import 'package:beads_dart/beads_dart.dart'
    show GraphSnapshot, GridControllerRuntime, SnapshotReader;

import 'grid_controller_plugin.dart';
import 'grid_exploration_host.dart';
import 'reassemble_tool.dart';

/// Reads a station's already-joined work graph.
///
/// This opens no second controller over the underlying stores: the station owns
/// the joined graph and supplies its latest snapshot through [latest].
class JoinedWorkReader implements SnapshotReader {
  /// Creates the reader over [latest].
  const JoinedWorkReader(this.latest);

  /// Returns the station's current joined work graph.
  final GraphSnapshot Function() latest;

  @override
  Future<GraphSnapshot> read() async => latest();
}

/// The exploration host, read-only runtime, and advertised VM-service URI for
/// one JIT station.
class DevModeHost {
  DevModeHost._(this.host, this.runtime, this.vmServiceUri);

  /// The sole registrar carrying the optional reassemble contributor.
  final GridExplorationHost host;

  /// The controller observed by the host's read-only tools.
  final GridControllerRuntime runtime;

  /// The authenticated URI a reload client connects to.
  final String vmServiceUri;

  /// Registers the exploration extensions on the VM service.
  void register() => host.register();

  /// Disposes the host subscription before its runtime.
  Future<void> dispose() async {
    await host.dispose();
    await runtime.dispose();
  }
}

/// Deprecated compatibility name for [DevModeHost].
///
/// Use [DevModeHost]. This alias will be removed in 0.4.0.
@Deprecated('Use DevModeHost. DevModeSeat will be removed in 0.4.0.')
typedef DevModeSeat = DevModeHost;

/// Arms a dev-mode host only when this process exposes [vmServiceUri].
///
/// A null URI returns null without reading [latest] or invoking [hotReload] or
/// [hotRestart]. A JIT station adapts its live grid at the composition boundary:
///
/// ```dart
/// armDevMode(
///   vmServiceUri: uri,
///   hotReload: () async => (await grid.hotReload()).toJson(),
///   hotRestart: () async => (await grid.hotRestart()).toJson(),
///   latest: () => stationWork.latest.graph,
///   readPath: () => stationWork.readPath,
/// );
/// ```
Future<DevModeHost?> armDevMode({
  required String? vmServiceUri,
  required StationReassemble hotReload,
  required StationReassemble hotRestart,
  required GraphSnapshot Function() latest,
  required String Function() readPath,
}) async {
  if (vmServiceUri == null) return null;
  final runtime = GridControllerRuntime(
    reader: JoinedWorkReader(latest),
    dirtySources: const [],
  );
  await runtime.start();
  final host = GridExplorationHost(
    runtime,
    plugin: GridControllerPlugin(runtime, readPath: readPath),
    reassemble: ReassembleTool(hotReload: hotReload, hotRestart: hotRestart),
  );
  return DevModeHost._(host, runtime, vmServiceUri);
}
