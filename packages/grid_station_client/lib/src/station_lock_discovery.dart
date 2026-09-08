import 'dart:convert';

import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart'
    show StationLockRecord;

/// Supplies candidate workspace roots in lookup order.
typedef WorkspaceRootsReader = Future<List<Uri>> Function();

/// Reads a UTF-8 text file through an injected platform adapter.
typedef TextFileReader = Future<String> Function(Uri uri);

/// Reports whether the host can perform station-lock auto-discovery.
///
/// Hosts supply this adapter so the shared client remains platform-neutral in
/// accordance with ADR-0002's package boundary.
typedef StationLockDiscoveryCapabilityProbe = Future<bool> Function();

/// Finds the first usable station lock in candidate-root order.
final class StationLockDiscovery {
  /// Creates discovery over injected capability, root, and text adapters.
  const StationLockDiscovery({
    required this.isCapable,
    required this.workspaceRoots,
    required this.readFile,
  });

  /// Host capability adapter.
  final StationLockDiscoveryCapabilityProbe isCapable;

  /// Candidate-root adapter.
  final WorkspaceRootsReader workspaceRoots;

  /// Text-reading adapter.
  final TextFileReader readFile;

  /// Discovers the first record with non-blank control credentials.
  Future<StationLockRecord> discover() async {
    if (!await isCapable()) {
      throw const StationLockDiscoveryUnavailable();
    }
    final failures = <Object>[];
    try {
      for (final root in await workspaceRoots()) {
        try {
          final text = await readFile(root.resolve('.grid/station.lock'));
          final record = StationLockRecord.fromJson(
            (jsonDecode(text) as Map).cast<String, Object?>(),
          );
          if ((record.controlUrl?.trim().isNotEmpty ?? false) &&
              (record.token?.trim().isNotEmpty ?? false)) {
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

/// Indicates that the current host cannot perform station-lock auto-discovery.
final class StationLockDiscoveryUnavailable implements Exception {
  /// Creates an unavailable discovery outcome.
  const StationLockDiscoveryUnavailable();

  @override
  String toString() => 'Station lock auto-discovery is unavailable';
}

/// Typed aggregate describing why capable local lock discovery failed.
final class StationLockDiscoveryFailure implements Exception {
  /// Creates a failure from the attempts made in candidate-root order.
  const StationLockDiscoveryFailure(this.failures);

  /// Individual root-enumeration, read, or decode failures.
  final List<Object> failures;

  @override
  String toString() => failures.isEmpty
      ? 'No workspace roots are available'
      : 'No usable station lock found: ${failures.join('; ')}';
}
