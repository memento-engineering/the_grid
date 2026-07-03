import 'package:beads_dart/beads_dart.dart';

import 'grid_exploration_protocol.dart';

/// Declared shape of a grid tool — its bare name, description, and input
/// schema — surfaced in the handshake and (eventually) to the exploration
/// agent's tool catalog.
class GridToolDescriptor {
  const GridToolDescriptor({
    required this.name,
    required this.description,
    this.inputSchema = const {'type': 'object', 'properties': {}},
  });

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;
}

/// The grid plugin: namespace `grid`, contributing the read/observe tools over
/// a [GridControllerRuntime]. Pure — every method returns plain JSON maps, so
/// the whole plugin is unit-testable without a VM service. The host
/// ([GridExplorationHost]) wires these into `dart:developer` extensions.
class GridControllerPlugin {
  GridControllerPlugin(this.runtime, {String Function()? readPath})
    : _readPath = readPath ?? (() => 'unknown');

  final GridControllerRuntime runtime;
  final String Function() _readPath;

  String get namespace => kGridNamespace;

  /// The tools this plugin exposes (stable order).
  static const tools = <GridToolDescriptor>[
    GridToolDescriptor(
      name: 'requery',
      description:
          'Force an immediate re-query of the work graph and return '
          'the resulting sync stats.',
    ),
    GridToolDescriptor(
      name: 'snapshot',
      description:
          'Current graph snapshot summary: bead/ready counts, ready '
          'bead summaries, and capture time.',
    ),
    GridToolDescriptor(
      name: 'ready',
      description: 'Beads currently in the ready set, as compact summaries.',
    ),
    GridToolDescriptor(
      name: 'events',
      description:
          'Recent typed graph events from the ring buffer. Optional '
          'integer `limit` parameter.',
    ),
    GridToolDescriptor(
      name: 'stats',
      description:
          'Sync-loop stats: per-origin signal counts, refresh count '
          'and latency, in-flight state, and the active read path.',
    ),
  ];

  List<String> get toolNames => [for (final t in tools) t.name];

  /// The plugin's observation fragment (lives under `extensions.grid` in the
  /// stable observation). Bounded by [eventLimit]/[readyLimit].
  Map<String, Object?> observe({int eventLimit = 32, int readyLimit = 64}) {
    final snapshot = runtime.current;
    final recent = runtime.recentEvents;
    final ready = runtime.readyBeads;
    return {
      'readPath': _readPath(),
      'beadCount': snapshot?.beadCount ?? 0,
      'readyCount': ready.length,
      'readyBeads': [
        for (final bead in ready.take(readyLimit)) beadSummary(bead),
      ],
      'recentEvents': [
        for (final event in _tail(recent, eventLimit)) graphEventToWire(event),
      ],
      'stats': statsToWire(runtime.stats),
      'capturedAt': snapshot?.capturedAt.toIso8601String(),
    };
  }

  /// Dispatches a grid tool by bare [name] with string [params] (VM-extension
  /// parameters are always string→string). Returns a `{ok, value|error}`
  /// result map. Unknown tools yield `{ok:false, error:...}`.
  Future<Map<String, Object?>> dispatch(
    String name,
    Map<String, String> params,
  ) async {
    switch (name) {
      case 'requery':
        await runtime.requery();
        return _ok({'refreshed': true, 'stats': statsToWire(runtime.stats)});
      case 'snapshot':
        final snapshot = runtime.current;
        return _ok({
          'beadCount': snapshot?.beadCount ?? 0,
          'readyCount': runtime.readyBeads.length,
          'readyBeads': [
            for (final bead in runtime.readyBeads) beadSummary(bead),
          ],
          'capturedAt': snapshot?.capturedAt.toIso8601String(),
        });
      case 'ready':
        final ready = runtime.readyBeads;
        return _ok({
          'count': ready.length,
          'beads': [for (final bead in ready) beadSummary(bead)],
        });
      case 'events':
        final limit = int.tryParse(params['limit'] ?? '') ?? 64;
        final recent = _tail(runtime.recentEvents, limit);
        return _ok({
          'count': recent.length,
          'events': [for (final event in recent) graphEventToWire(event)],
        });
      case 'stats':
        return _ok(statsToWire(runtime.stats));
      default:
        return {'ok': false, 'error': 'unknown grid tool: $name'};
    }
  }

  Map<String, Object?> _ok(Object? value) => {'ok': true, 'value': value};

  static List<T> _tail<T>(List<T> list, int limit) =>
      limit >= list.length ? list : list.sublist(list.length - limit);
}
