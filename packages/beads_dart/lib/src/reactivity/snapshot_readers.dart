import '../models/bead.dart';
import '../models/graph_snapshot.dart';
import '../services/bd_cli_service.dart';
import '../services/dolt_query_service.dart';
import 'snapshot_reader.dart';

List<Bead> _mergeReadyFallback(Iterable<Bead> broad, Iterable<Bead> ready) {
  final byId = <String, Bead>{for (final bead in broad) bead.id: bead};
  for (final bead in ready) {
    byId.putIfAbsent(bead.id, () => bead);
  }
  return byId.values.toList(growable: false);
}

/// Composes a CLI snapshot with one broad graph query and one dependency read.
class CliSnapshotReader implements SnapshotReader {
  CliSnapshotReader(this._bd, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final BdCliService _bd;
  final DateTime Function() _clock;

  @override
  Future<GraphSnapshot> read() async {
    final broad = await _bd.query(
      'status=open OR status=in_progress OR status=blocked OR '
      'status=deferred OR status=closed',
      includeClosed: true,
    );
    final ready = await _bd.ready();
    final beads = _mergeReadyFallback(broad, ready);
    final dependencies = await _bd.depList(
      beads.map((bead) => bead.id).toList(growable: false),
    );
    return GraphSnapshot.fromParts(
      beads: beads,
      dependencies: dependencies,
      readyIds: ready.map((bead) => bead.id),
      capturedAt: _clock(),
    );
  }
}

/// Composes a snapshot from pooled Dolt SQL (issues ∪ wisps, plus both label
/// and dependency tables — see [SnapshotReader] for the unified inclusion
/// semantics) plus `bd ready` for the ready set (authoritative in M1; M2 ports
/// ready-work to SQL, differential-tested). The heavy read stays on pooled SQL.
///
/// SQL failures propagate: assembly chooses the source once and reads stay loud.
class SqlSnapshotReader implements SnapshotReader {
  SqlSnapshotReader({
    required DoltQueryService dolt,
    required BdCliService bd,
    DateTime Function()? clock,
  }) : _dolt = dolt,
       _bd = bd,
       _clock = clock ?? DateTime.now;

  final DoltQueryService _dolt;
  final BdCliService _bd;
  final DateTime Function() _clock;

  @override
  Future<GraphSnapshot> read() async {
    final parts = await _dolt.snapshotParts();
    final ready = await _bd.ready();
    return GraphSnapshot.fromParts(
      beads: _mergeReadyFallback(parts.beads, ready),
      dependencies: parts.dependencies,
      readyIds: ready.map((bead) => bead.id),
      capturedAt: _clock(),
    );
  }
}

/// Adapts [DoltQueryService.probe] to the [ChangeProbe] seam consumed by the
/// working-set dirty-signal source.
class DoltChangeProbe implements ChangeProbe {
  DoltChangeProbe(this._dolt);
  final DoltQueryService _dolt;

  @override
  Future<String> probe() => _dolt.probe();
}
