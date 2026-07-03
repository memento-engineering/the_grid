import '../services/bd_cli_service.dart';
import '../services/bd_runner.dart';
import '../services/beads_workspace.dart';
import '../services/dolt_query_service.dart';
import 'dirty_signal.dart';
import 'grid_controller_runtime.dart';
import 'snapshot_reader.dart';
import 'snapshot_readers.dart';

/// Which read path a built runtime uses for snapshot composition.
enum ReadPath { sql, cli }

/// A built runtime plus its provenance and a [shutdown] that tears down the
/// runtime *and* any Dolt pool the factory opened.
class GridRuntimeBundle {
  GridRuntimeBundle({
    required this.runtime,
    required this.readPath,
    required this.shutdown,
  });

  final GridControllerRuntime runtime;

  /// The active read path: [ReadPath.sql] when pooled Dolt reads are in use,
  /// [ReadPath.cli] when composing via `bd export` (embedded mode, no
  /// credentials, or SQL unavailable/drifted).
  final ReadPath readPath;

  /// Disposes the runtime and closes the Dolt pool (if any). Idempotent-safe
  /// to call once at shutdown.
  final Future<void> Function() shutdown;
}

/// Assembles a [GridControllerRuntime] for a discovered [BeadsWorkspace],
/// choosing the read path and dirty-signal sources from the workspace's mode
/// and credentials (ADR-0001 Decisions 4 & 5):
///
/// * **SQL path** when the workspace is server-mode with a resolvable endpoint
///   *and* a credential, and the pool connects (drift guard passes): pooled
///   Dolt reads + a `@@<db>_working` probe source, with the CLI reader as the
///   per-refresh fallback.
/// * **CLI path** otherwise: `bd export` composition + a polling backstop.
///
/// Both paths always include the `.beads/` workspace watcher for sub-second
/// local-mutation push.
class GridRuntimeFactory {
  static Future<GridRuntimeBundle> build({
    required BeadsWorkspace workspace,
    bool preferSql = true,
    Duration quietPeriod = const Duration(milliseconds: 150),
    Duration probeInterval = const Duration(seconds: 1),
    Duration pollInterval = const Duration(seconds: 5),
    BdRunner? runner,
  }) async {
    final bd = BdCliService(
      runner ?? ProcessBdRunner(workspaceRoot: workspace.root),
    );
    final cliReader = CliSnapshotReader(bd);
    final dirtySources = <DirtySignalSource>[
      WorkspaceBeadsWatcher(workspace.beadsDir),
    ];

    var readPath = ReadPath.cli;
    DoltQueryService? dolt;
    SnapshotReader reader = cliReader;

    final endpoint = workspace.endpoint;
    if (preferSql &&
        workspace.mode == DoltMode.server &&
        endpoint != null &&
        endpoint.hasCredential) {
      final candidate = DoltQueryService(endpoint);
      try {
        await candidate.connect(); // runs the schema-drift guard
        dolt = candidate;
        reader = SqlSnapshotReader(dolt: dolt, bd: bd, fallback: cliReader);
        dirtySources.add(
          WorkingSetProbeSource(DoltChangeProbe(dolt), interval: probeInterval),
        );
        readPath = ReadPath.sql;
      } on Object {
        // Drift / auth / unreachable → CLI path, polling backstop.
        await candidate.close();
        dolt = null;
        dirtySources.add(PollingTickerSource(interval: pollInterval));
      }
    } else {
      dirtySources.add(PollingTickerSource(interval: pollInterval));
    }

    final runtime = GridControllerRuntime(
      reader: reader,
      dirtySources: dirtySources,
      quietPeriod: quietPeriod,
    );

    return GridRuntimeBundle(
      runtime: runtime,
      readPath: readPath,
      shutdown: () async {
        await runtime.dispose();
        await dolt?.close();
      },
    );
  }
}
