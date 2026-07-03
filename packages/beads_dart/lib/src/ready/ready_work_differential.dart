import '../models/bead.dart';
import '../services/bd_runner.dart';
import '../codecs/envelope.dart';
import 'ready_work_filter.dart';
import 'ready_work_query.dart';

/// The outcome of one differential run: the ordered ready id list from each
/// side plus the diagnosis. [diverged] is the gate (ADR-0003 Decision 5: fail on
/// ANY divergence).
class ReadyWorkDiff {
  const ReadyWorkDiff({
    required this.sqlIds,
    required this.oracleIds,
    required this.policy,
  });

  /// The ordered ready ids from the SQL port ([ReadyWorkQuery]).
  final List<String> sqlIds;

  /// The ordered ready ids from the `bd ready --json` oracle.
  final List<String> oracleIds;

  /// The sort policy both sides were run under (for the report).
  final ReadyWorkSortPolicy policy;

  /// Ids the SQL port returned that the oracle did not (set difference).
  Set<String> get sqlOnly => sqlIds.toSet().difference(oracleIds.toSet());

  /// Ids the oracle returned that the SQL port did not (set difference).
  Set<String> get oracleOnly => oracleIds.toSet().difference(sqlIds.toSet());

  /// True when the two sides agree on **both** membership and order.
  bool get matches => _listEquals(sqlIds, oracleIds);

  /// True when the two sides disagree on membership and/or order — the gate.
  bool get diverged => !matches;

  /// True when both sides carry the same id set but in a different order (a
  /// pure ordering divergence — usually a sort-policy or tiebreak bug).
  bool get orderOnlyDivergence =>
      !matches && sqlOnly.isEmpty && oracleOnly.isEmpty;

  /// A human-readable divergence report, empty when [matches].
  String describe() {
    if (matches) return 'ready sets agree (${sqlIds.length} ids, $policy)';
    final buf = StringBuffer()
      ..writeln('ready-work divergence under $policy:')
      ..writeln('  SQL    (${sqlIds.length}): ${_preview(sqlIds)}')
      ..writeln('  oracle (${oracleIds.length}): ${_preview(oracleIds)}');
    if (sqlOnly.isNotEmpty) buf.writeln('  SQL-only: $sqlOnly');
    if (oracleOnly.isNotEmpty) buf.writeln('  oracle-only: $oracleOnly');
    if (orderOnlyDivergence) {
      buf.writeln('  (same id set, different order — sort/tiebreak mismatch)');
    }
    return buf.toString().trimRight();
  }

  static String _preview(List<String> ids) {
    const max = 12;
    if (ids.length <= max) return ids.toString();
    return '${ids.sublist(0, max)}… (+${ids.length - max})';
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Raised when a [ReadyWorkDifferential.assertAgreement] run diverges. Carries
/// the [diff] so callers/tests can inspect the per-side id lists.
class ReadyWorkDivergence implements Exception {
  ReadyWorkDivergence(this.diff);

  final ReadyWorkDiff diff;

  @override
  String toString() => 'ReadyWorkDivergence: ${diff.describe()}';
}

/// The ADR-0003 Decision 5 differential test gate.
///
/// Given a workspace, computes the ready set via **both** the SQL port
/// ([ReadyWorkQuery]) and `bd ready --json` (the oracle + production fallback),
/// and diffs ids + order. `bd ready` is authoritative: any divergence is a port
/// bug, not an oracle bug (port spec §10 / trap #17).
///
/// The oracle is invoked as `bd ready --json --limit 0 --sort <policy>` plus the
/// flags the [ReadyWorkFilter] implies (port spec §10): `--limit 0` to defeat
/// the CLI's default 100-row truncation, the explicit `--sort` to defeat the
/// CLI-vs-storage default split (trap #5). Filter knobs the oracle does **not**
/// honor (`LabelsAny`/`MolType`, traps #9/#10) are not modeled on
/// [ReadyWorkFilter] at all, so they cannot drift the two sides apart.
class ReadyWorkDifferential {
  ReadyWorkDifferential({required this.sqlPort, required this.runner});

  /// The SQL port under test.
  final ReadyWorkQuery sqlPort;

  /// The bd runner used to invoke the oracle (`bd ready --json …`).
  final BdRunner runner;

  /// Runs both sides for [filter] and returns the diff. [now] pins the time
  /// basis on the SQL side for deterministic replay; production runs leave it
  /// null. (`bd ready` always uses its own server-side clock, so a pinned [now]
  /// must match wall-clock closely enough that recency banding agrees — tests
  /// keep deferred/hybrid scenarios coarse-grained for this reason.)
  Future<ReadyWorkDiff> run(ReadyWorkFilter filter, {DateTime? now}) async {
    final sqlIds = await sqlPort.readyIds(filter, now: now);
    final oracleIds = await _oracleIds(filter);
    return ReadyWorkDiff(
      sqlIds: sqlIds,
      oracleIds: oracleIds,
      policy: filter.sortPolicy,
    );
  }

  /// Runs the diff and **throws** [ReadyWorkDivergence] on any divergence — the
  /// gate form for tests. Returns the (agreeing) diff otherwise.
  Future<ReadyWorkDiff> assertAgreement(
    ReadyWorkFilter filter, {
    DateTime? now,
  }) async {
    final diff = await run(filter, now: now);
    if (diff.diverged) throw ReadyWorkDivergence(diff);
    return diff;
  }

  /// The argv for the oracle invocation derived from [filter] — exposed so tests
  /// can assert the exact flags and a fake runner can answer deterministically.
  List<String> oracleArgs(ReadyWorkFilter filter) {
    final status = filter.status;
    return [
      'ready',
      '--json',
      '--limit',
      '0',
      '--sort',
      filter.sortPolicy.wire,
      if (filter.includeEphemeral) '--include-ephemeral',
      if (filter.includeDeferred) '--include-deferred',
      if (filter.unassigned) '--unassigned',
      if (!filter.unassigned && filter.assignee != null) ...[
        '--assignee',
        filter.assignee!,
      ],
      if (filter.priority != null) ...['--priority', '${filter.priority}'],
      if (filter.type != null && filter.type!.isNotEmpty) ...[
        '--type',
        filter.type!,
      ],
      for (final label in filter.labels) ...['--label', label],
      for (final label in filter.excludeLabels) ...['--exclude-label', label],
      for (final t in filter.excludeTypes) ...['--exclude-type', t],
      if (filter.parentId != null) ...['--parent', filter.parentId!],
      if (filter.hasMetadataKey != null &&
          filter.hasMetadataKey!.isNotEmpty) ...[
        '--has-metadata-key',
        filter.hasMetadataKey!,
      ],
      for (final e
          in (filter.metadataFields.entries.toList()..sort(
            (a, b) => a.key.compareTo(b.key),
          ))) ...['--metadata-field', '${e.key}=${e.value}'],
      // status is NOT a bd ready flag — the CLI hardcodes Status:'open'. A
      // non-open filter has no oracle and must not be run differentially.
      if (status != null && status.wire != 'open')
        throw ArgumentError(
          'bd ready has no status flag; only status=open is differentiable '
          '(got ${status.wire})',
        ),
    ];
  }

  Future<List<String>> _oracleIds(ReadyWorkFilter filter) async {
    final result = await runner.run(oracleArgs(filter));
    if (result.exitCode != 0) {
      throw StateError(
        'bd ready (oracle) failed (${result.exitCode}): ${result.stderr}',
      );
    }
    final env = BdEnvelope.parse(result.stdout);
    return [for (final row in env.dataList) Bead.fromJson(row).id];
  }
}
