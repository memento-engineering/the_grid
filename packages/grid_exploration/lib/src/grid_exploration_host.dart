import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:beads_dart/beads_dart.dart';

import 'grid_controller_plugin.dart';
import 'grid_exploration_protocol.dart';
import 'reassemble_tool.dart';

/// Minimal pure-Dart exploration host for the_grid (ADR-0001 Decision 6).
///
/// Registers exactly the exploration protocol over a [GridControllerRuntime]
/// via `dart:developer` — no bespoke `ext.grid.*` namespace, no Flutter
/// binding:
///
/// * `ext.exploration.core.handshake`
/// * `ext.exploration.core.get_stable_observation` (empty semantics/routes,
///   grid state under `extensions.grid`, stability from the sync loop)
/// * `ext.exploration.grid.{requery,snapshot,ready,events,stats}`
/// * `ext.exploration.grid.reload` — ONLY when a dev-mode station composes a
///   [ReassembleTool] (see [reassemble]); absent otherwise.
///
/// and streams each [GraphEvent] via `developer.postEvent('grid.controller.
/// event', ...)`. The JSON builders ([handshakeJson], [observationJson],
/// [dispatchTool]) are pure and unit-tested; [register] is the thin glue that
/// binds them to the VM service.
class GridExplorationHost {
  GridExplorationHost(
    this.runtime, {
    GridControllerPlugin? plugin,
    this.reassemble,
    this.eventStreamId = 'grid.controller.event',
  }) : plugin = plugin ?? GridControllerPlugin(runtime) {
    // A colliding name would make `register` call registerExtension TWICE on
    // the same method and the VM would throw at station boot. Refuse at
    // construction, naming the method (LOUD or gone).
    final observation = this.plugin.toolNames.toSet();
    for (final tool in reassemble?.toolNames ?? const <String>[]) {
      if (observation.contains(tool)) {
        throw ArgumentError.value(
          tool,
          'reassemble',
          'dev-mode tool name collides with a GridControllerPlugin tool — '
              '`register()` would register ${gridExtension(tool)} twice',
        );
      }
    }
  }

  final GridControllerRuntime runtime;
  final GridControllerPlugin plugin;

  /// The OPTIONAL dev-mode tool contributor. Null on every AOT / non-dev
  /// composition — and with it null this host is EXACTLY what it was: the same
  /// five read-only tools, the same handshake, no new transport seam. A JIT
  /// station under `--enable-vm-service` passes one; that is the only way
  /// `reload` exists.
  final ReassembleTool? reassemble;

  final String eventStreamId;

  /// Every tool this host advertises AND registers: [GridControllerPlugin]'s
  /// closed, read-only observation set, plus the dev-mode contributor's when a
  /// station composed one. The handshake and the registrar read the SAME list —
  /// a registered tool is always a discoverable tool (ADR-0001 Decision 6's
  /// tool-discovery contract).
  List<String> get toolNames => [
    ...plugin.toolNames,
    ...?reassemble?.toolNames,
  ];

  bool _registered = false;
  StreamSubscription<GraphEvent>? _eventSub;

  // ---------- pure JSON builders (testable without a VM service) ----------

  Map<String, Object?> handshakeJson() => {
    'protocolVersion': kProtocolVersion,
    'bindingType': 'GridControllerHost',
    'hostType': 'dart',
    kExtensionsKey: [
      {'namespace': plugin.namespace, 'tools': toolNames},
    ],
  };

  Map<String, Object?> observationJson() {
    final stats = runtime.stats;
    return {
      'type': 'Observation',
      'value': {
        'semantics': const <Object?>[],
        'routes': const <Object?>[],
        'stability': {
          'refreshing': stats.refreshing,
          'pendingFollowUp': stats.pendingFollowUp,
          'refreshCount': stats.refreshCount,
          'lastRefreshMs': stats.lastRefresh?.inMilliseconds,
        },
        kExtensionsKey: {plugin.namespace: plugin.observe()},
      },
    };
  }

  /// Routes a tool to its OWNER: the dev-mode contributor when it declares the
  /// name, the read-only observation plugin otherwise.
  Future<Map<String, Object?>> dispatchTool(
    String tool,
    Map<String, String> params,
  ) {
    final dev = reassemble;
    if (dev != null && dev.toolNames.contains(tool)) {
      return dev.dispatch(tool, params);
    }
    return plugin.dispatch(tool, params);
  }

  // ---------- VM-service registration ----------

  /// Registers the extensions and starts streaming events. Idempotent.
  /// Safe to call only under `--enable-vm-service`; the JSON builders work
  /// regardless.
  void register() {
    if (_registered) return;
    _registered = true;

    developer.registerExtension(coreExtension('handshake'), (
      method,
      params,
    ) async {
      return developer.ServiceExtensionResponse.result(
        jsonEncode(handshakeJson()),
      );
    });

    developer.registerExtension(coreExtension('get_stable_observation'), (
      method,
      params,
    ) async {
      return developer.ServiceExtensionResponse.result(
        jsonEncode(observationJson()),
      );
    });

    for (final tool in toolNames) {
      developer.registerExtension(gridExtension(tool), (method, params) async {
        try {
          final result = await dispatchTool(tool, params);
          return developer.ServiceExtensionResponse.result(jsonEncode(result));
        } on Object catch (error) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            jsonEncode({'ok': false, 'error': '$error'}),
          );
        }
      });
    }

    _eventSub = runtime.events.listen((event) {
      developer.postEvent(eventStreamId, graphEventToWire(event));
    });
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
  }
}
