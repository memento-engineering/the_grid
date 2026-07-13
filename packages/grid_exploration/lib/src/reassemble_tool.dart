/// The dev-mode RELOAD tool — the EXPLICIT operator trigger for a hot-reload /
/// hot-restart of a JIT station.
///
/// It lives HERE, not in `grid_sdk`, because this package owns the
/// `ext.exploration.*` namespace (ADR-0002 Decision 1 — "the minimal pure-Dart
/// host registering the `ext.exploration.*` extensions"; ADR-0001 Decision 6 —
/// "no bespoke `ext.grid.*` namespace"). [GridExplorationHost] stays the SOLE
/// registrar, so the tool is advertised in the handshake like the other five and
/// a stock leonard discovers it (ADR-0000 A33).
///
/// There is deliberately NO filesystem watcher (an auto-reload-on-save would
/// fire mid-build on a resident `--land` station) and NO bare OS signal
/// (un-introspectable). The station's lifecycle (`up`/`down`) still rides
/// signals, and the read-only control surface still carries no mutation route.
library;

import 'dart:developer' as developer;

import 'grid_controller_plugin.dart';

/// One reassemble verb, as the host sees it: a callback returning the wire body
/// of what the re-composition DID.
///
/// This typedef is the SEAM that lets `grid_exploration` host a `grid_sdk`
/// affordance **without depending on `grid_sdk`** — the package's dependency set
/// is unchanged, and ADR-0002's dependency direction (nothing points back at the
/// SDK) holds. A station wires `GridHandle.hotReload` / `hotRestart` in; this
/// package only ever sees a `Future<Map>` Function().
typedef StationReassemble = Future<Map<String, Object?>> Function();

/// Contributes the single dev-mode `reload` tool into the `grid` namespace.
///
/// A station COMPOSES it (ADR-0008 Decision 2 — consumers compose, never
/// subclass):
///
/// ```dart
/// final grid = runGrid(delegate, delegateFactory: buildDelegate);
/// GridExplorationHost(
///   runtime,
///   reassemble: ReassembleTool(
///     hotReload: () async => (await grid.hotReload()).toJson(),
///     hotRestart: () async => (await grid.hotRestart()).toJson(),
///   ),
/// ).register();
/// ```
///
/// An AOT station composes no [ReassembleTool] — it has no VM service to
/// register on — and the host is then byte-for-byte what it always was.
class ReassembleTool {
  /// Creates the tool over the station's two reassemble verbs.
  const ReassembleTool({required this.hotReload, required this.hotRestart});

  /// Re-run the master build on the SAME delegate (new code bodies in place).
  final StationReassemble hotReload;

  /// Re-run the delegate FACTORY and re-compose on a fresh delegate.
  final StationReassemble hotRestart;

  /// The bare tool name — `ext.exploration.grid.reload` once qualified by
  /// [gridExtension]. It collides with none of [GridControllerPlugin.tools]
  /// (`requery`/`snapshot`/`ready`/`events`/`stats`), and [GridExplorationHost]
  /// REFUSES at construction if that ever changes.
  static const String toolName = 'reload';

  /// The accepted `mode` tokens, in wire form. `grid_sdk`'s `ReassembleMode`
  /// enumerates the same two; `grid_cli`'s `reassemble_mode_pin_test.dart` — the
  /// one package that sees both — PINS them equal, so a drift is a loud test
  /// failure rather than a silent wire break.
  static const List<String> modes = <String>['reload', 'restart'];

  /// The declared shape, surfaced in the handshake beside the read-only tools.
  static const tools = <GridToolDescriptor>[
    GridToolDescriptor(
      name: toolName,
      description:
          'DEV MODE. Re-compose the running station so landed code changes '
          'take effect with no down/up bounce. `mode=reload` (default) re-runs '
          'the master build; `mode=restart` re-runs the delegate factory. Live '
          'sessions are ADOPTED — a running agent is never killed.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'mode': {'type': 'string', 'enum': modes},
        },
      },
    ),
  ];

  /// The names this contributor adds to the `grid` namespace (stable order).
  List<String> get toolNames => [for (final t in tools) t.name];

  /// Dispatches the tool. An unknown tool or an unknown `mode` THROWS — the
  /// host's registrar turns a throw into a `ServiceExtensionResponse.error`, so
  /// an operator who fat-fingers the mode gets a LOUD refusal, never a silent
  /// reload (the guard principle).
  Future<Map<String, Object?>> dispatch(
    String name,
    Map<String, String> params,
  ) async {
    if (name != toolName) {
      throw ArgumentError.value(
        name,
        'tool',
        'the reassemble tool serves only `$toolName`',
      );
    }
    final mode = params['mode'] ?? modes.first;
    return switch (mode) {
      'reload' => {'ok': true, 'value': await hotReload()},
      'restart' => {'ok': true, 'value': await hotRestart()},
      _ => throw ArgumentError.value(
        mode,
        'mode',
        'unknown reassemble mode — expected one of $modes',
      ),
    };
  }
}

/// This station's own VM-service URI, or null when it is not running under
/// `--enable-vm-service` (an AOT binary). A JIT runner advertises it in the 0600
/// `station.lock` so the reload client can find the target; an AOT runner never
/// calls it, and the client then classifies the station as not-dev-mode.
Future<String?> stationVmServiceUri() async =>
    (await developer.Service.getInfo()).serverUri?.toString();
