import 'dart:convert';

import 'package:grid_engine/grid_engine.dart'
    show ExplorationTransport, TreeProjector;

/// Writes one already-encoded resident diagnostic line.
typedef DiagnosticLineWriter = void Function(String line);

/// Runner-shell diagnostics composition shared by `/stream` and engine flares.
final class StationDiagnosticsReporter implements ExplorationTransport {
  /// Creates the reporter over [writeLine].
  StationDiagnosticsReporter({
    required DiagnosticLineWriter writeLine,
    TreeProjector? treeProjector,
  }) : _writeLine = writeLine,
       treeProjector = treeProjector ?? TreeProjector();

  final DiagnosticLineWriter _writeLine;

  /// Projects the mounted tree for the authenticated `/stream` reporter.
  final TreeProjector treeProjector;

  @override
  void flare(String name, Map<String, String> data) {
    _writeLine(
      jsonEncode(<String, Object?>{
        'type': 'flare',
        'name': name,
        'data': data,
      }),
    );
  }

  /// Releases the projection stream after the control socket and grid close.
  void dispose() => treeProjector.dispose();
}
