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
    Duration flareRateLimit = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _writeLine = writeLine,
       _flareRateLimit = flareRateLimit,
       _now = now ?? DateTime.now,
       treeProjector = treeProjector ?? TreeProjector();

  final DiagnosticLineWriter _writeLine;
  final Duration _flareRateLimit;
  final DateTime Function() _now;
  final Map<String, DateTime> _lastFlareAt = <String, DateTime>{};

  /// Projects the mounted tree for the authenticated `/stream` reporter.
  final TreeProjector treeProjector;

  /// The rate-limit bucket for one flare name about one subject.
  static String _bucketFor(String name, Map<String, String> data) {
    final subject = data['nodePath'] ?? data['bead'] ?? '';
    return '$name\u0000$subject';
  }

  @override
  void flare(String name, Map<String, String> data) {
    final now = _now();
    final bucket = _bucketFor(name, data);
    final last = _lastFlareAt[bucket];
    if (last != null && now.difference(last) < _flareRateLimit) return;
    _lastFlareAt[bucket] = now;
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
