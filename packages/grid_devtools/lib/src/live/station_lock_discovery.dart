import 'dart:convert';

import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';

/// Reads IDE workspace roots from the connected tooling daemon.
typedef WorkspaceRootsReader = Future<List<Uri>> Function();

/// Reads a UTF-8 text file through the tooling daemon.
typedef TextFileReader = Future<String> Function(Uri uri);

/// Finds the first usable station lock in IDE workspace order.
final class StationLockDiscovery {
  /// Creates a discovery service over injected DTD adapters.
  const StationLockDiscovery({
    required this.workspaceRoots,
    required this.readFile,
  });

  /// Workspace-root adapter.
  final WorkspaceRootsReader workspaceRoots;

  /// File-reading adapter.
  final TextFileReader readFile;

  /// Discovers the first record with both control fields.
  Future<StationLockRecord> discover() async {
    final failures = <Object>[];
    try {
      for (final root in await workspaceRoots()) {
        try {
          final text = await readFile(root.resolve('.grid/station.lock'));
          final record = StationLockRecord.fromJson(
            (jsonDecode(text) as Map).cast<String, Object?>(),
          );
          if ((record.controlUrl?.isNotEmpty ?? false) &&
              (record.token?.isNotEmpty ?? false)) {
            return record;
          }
          failures.add(
            const FormatException('station lock has no control credentials'),
          );
        } on Object catch (error) {
          failures.add(error);
        }
      }
    } on Object catch (error) {
      failures.add(error);
    }
    throw StationLockDiscoveryFailure(failures);
  }
}

/// Typed aggregate describing why local lock discovery was unavailable.
final class StationLockDiscoveryFailure implements Exception {
  /// Creates a failure from the attempts made in workspace order.
  const StationLockDiscoveryFailure(this.failures);

  /// Individual workspace or DTD failures.
  final List<Object> failures;

  @override
  String toString() => failures.isEmpty
      ? 'No IDE workspace roots are available'
      : 'No usable station lock found: ${failures.join('; ')}';
}
