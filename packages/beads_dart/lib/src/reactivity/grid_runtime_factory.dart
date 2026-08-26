import '../services/bd_cli_service.dart';
import '../services/bd_runner.dart';
import '../services/beads_workspace.dart';
import '../services/bead_probe_reader.dart';
import '../services/dolt_query_service.dart';
import '../models/issue_type.dart';
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
    required this.probeReader,
    required this.readPath,
    required this.shutdown,
  });

  final GridControllerRuntime runtime;
  final BeadProbeReader probeReader;

  /// The active read path: [ReadPath.sql] when pooled Dolt reads are in use,
  /// [ReadPath.cli] when composing via scoped lists (embedded mode, no
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
/// * **SQL path** when the workspace resolver supplies an endpoint with a
///   credential and the pool connects (drift guard passes): pooled Dolt reads
///   plus a `@@<db>_working` probe, with CLI fallback per refresh.
/// * **CLI path** otherwise: scoped-list composition + a polling backstop.
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
    Duration syncFloorInterval = const Duration(seconds: 45),
    BdRunner? runner,
    Set<IssueType> lifecycleTypes = const {},
    void Function(String source)? onDirtySourceClosed,
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
    BeadProbeReader probeReader = CliBeadProbeReader(
      bd,
      lifecycleTypes: lifecycleTypes,
    );

    final endpoint = workspace.endpoint;
    if (preferSql && endpoint != null && endpoint.hasCredential) {
      final candidate = DoltQueryService(endpoint);
      try {
        await candidate.connect(); // runs the schema-drift guard
        dolt = candidate;
        reader = SqlSnapshotReader(dolt: dolt, bd: bd);
        probeReader = SqlBeadProbeReader(dolt);
        dirtySources.add(
          WorkingSetProbeSource(DoltChangeProbe(dolt), interval: probeInterval),
        );
        // The sync FLOOR (tg-zd4v): the probe is edge-triggered — no store
        // write, no hash change, no signal, FOREVER — so a purely quiet (or
        // silently wedged) member never re-captures and its snapshot ages
        // into a stale mint. A coarse ticker bounds the worst-case refresh
        // age on the SQL path too. Correctness, not latency: the refresh is
        // change-gated end to end, so a floor tick against an unchanged
        // store costs one scoped read and emits nothing downstream.
        // Re-entry safe by ORIGIN: `GraphSyncInteractor` drops a pollTicker
        // signal while a refresh is in flight (tg-07y's guard keys on the
        // origin, not the path).
        dirtySources.add(PollingTickerSource(interval: syncFloorInterval));
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
      onDirtySourceClosed: onDirtySourceClosed,
    );

    return GridRuntimeBundle(
      runtime: runtime,
      probeReader: probeReader,
      readPath: readPath,
      shutdown: () async {
        await runtime.dispose();
        await dolt?.close();
      },
    );
  }
}
