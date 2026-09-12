import 'dart:convert';

import 'package:grid_engine/grid_engine.dart'
    show ExplorationTransport, TreeProjector;

import 'composite_exploration_transport.dart';

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
  }) : _sink = CompositeExplorationTransport([
         _DiagnosticLineTransport(writeLine),
       ]),
       _flareRateLimit = flareRateLimit,
       _now = now ?? DateTime.now,
       treeProjector = treeProjector ?? TreeProjector();

  ExplorationTransport _sink;
  final Duration _flareRateLimit;
  final DateTime Function() _now;
  final Map<String, DateTime> _lastFlareAt = <String, DateTime>{};

  /// Projects the mounted tree for the authenticated `/stream` reporter.
  final TreeProjector treeProjector;

  /// Adds one process-lifetime flare sink after every sink already attached.
  ///
  /// The reporter remains the single rate-limit acceptance point; the
  /// composite contains each child so a failed sink cannot break a later one.
  void addTransport(ExplorationTransport transport) {
    _sink = CompositeExplorationTransport([_sink, transport]);
  }

  /// The rate-limit bucket for one flare name about one subject.
  static String _bucketFor(String name, Map<String, String> data) {
    final subject =
        data['nodePath'] ??
        data['beadId'] ??
        data['workBeadId'] ??
        data['sessionId'] ??
        data['bead'] ??
        '';
    return '$name\u0000$subject';
  }

  @override
  void flare(String name, Map<String, String> data) {
    // Every contained root failure must retain its own stack. Collapsing two
    // occurrences would make a live but repeatedly failing station quieter
    // than the process crash this boundary replaces.
    if (name != 'station.uncaughtError') {
      final now = _now();
      final bucket = _bucketFor(name, data);
      final last = _lastFlareAt[bucket];
      if (last != null && now.difference(last) < _flareRateLimit) return;
      _lastFlareAt[bucket] = now;
    }
    _sink.flare(name, data);
  }

  /// Releases the projection stream after the control socket and grid close.
  void dispose() => treeProjector.dispose();
}

final class _DiagnosticLineTransport implements ExplorationTransport {
  const _DiagnosticLineTransport(this._writeLine);

  final DiagnosticLineWriter _writeLine;

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
}
