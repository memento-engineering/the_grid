import '../errors/bd_exception.dart';
import '../models/bead.dart';
import '../models/bead_dependency.dart';
import '../models/capability.dart';
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
///
/// The broad query is read as a GRAPH, not just as beads: bd embeds each
/// bead's dependency ROWS in its record, and that RECORD surface is the only
/// bd read that carries a cross-project `external:` row — its resolving
/// surfaces answer with the issue record a dependency points at, which such a
/// target has none of. Without those rows a consumer held out by an
/// `external:` blocker would be ADMITTED the moment a store fell back to this
/// path, so both read paths surface them: the SQL path through
/// `depends_on_external` in its target expression, this one through the
/// record surface, and when the record surface stops carrying rows this read
/// REFUSES instead of publishing a snapshot that cannot see them (tg-xh5d).
class CliSnapshotReader implements SnapshotReader {
  CliSnapshotReader(
    this._bd, {
    DateTime Function()? clock,
    void Function(String message)? onRefusal,
  }) : _clock = clock ?? DateTime.now,
       _onRefusal = onRefusal;

  final BdCliService _bd;
  final DateTime Function() _clock;

  /// Where the external-row refusal is REPORTED before it is rethrown. A
  /// refusal that only throws reaches [BeadsRepository.errors], which nothing
  /// in the resident listens to, so the composer hands the reader the
  /// station's cross-store sink.
  final void Function(String message)? _onRefusal;

  /// Rising edge: a store that refuses every refresh says so ONCE, and says it
  /// again if it recovers and refuses anew.
  bool _refusing = false;

  /// The broad graph read — the SAME expression [BdCliService.externalDepRows]
  /// runs, so the frontier and the `link` verb list one set of edges.
  static const String allStatuses = BdCliService.allStatusesQuery;

  @override
  Future<GraphSnapshot> read() async {
    final broad = await _bd.queryGraph(allStatuses, includeClosed: true);
    final ready = await _bd.ready();
    final beads = _mergeReadyFallback(broad.beads, ready);
    final ids = beads.map((bead) => bead.id).toList(growable: false);
    final resolved = await _bd.depList(ids);
    // The control compares LIKE WITH LIKE: only the resolved rows whose
    // consumer the record surface actually returned. `bd ready` can fall back
    // a bead the broad query did not carry (a wisp, say), and its edges must
    // not read as rows the record surface "dropped".
    final recordIds = {for (final bead in broad.beads) bead.id};
    final List<BeadDependency> external;
    try {
      external = externalDepRowsFrom(
        records: broad.dependencies,
        resolved: [
          for (final dep in resolved)
            if (recordIds.contains(dep.issueId)) dep,
        ],
        call: ['bd', ..._bd.queryArgs(allStatuses, includeClosed: true)],
      );
    } on BdExternalDepSurfaceUnavailable catch (refusal) {
      if (!_refusing) {
        _refusing = true;
        _onRefusal?.call(refusal.message);
      }
      rethrow;
    }
    _refusing = false;
    return GraphSnapshot.fromParts(
      beads: beads,
      // Keyed by edge so a row both surfaces return lands once: the resolving
      // read is bd's own view of the local edges, the record surface adds the
      // cross-project rows it cannot express.
      dependencies: {
        for (final dep in [...resolved, ...external]) dep.edgeKey: dep,
      }.values,
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
/// Cross-project rows ride the dependency read with every other edge: the
/// target expression coalesces `depends_on_external`
/// ([DoltQueryService.dependenciesSelectFor]), and the column is REQUIRED by
/// the connect-time shape probe, so a store that cannot express one stands the
/// SQL path down instead of reading a graph with those edges dropped.
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
