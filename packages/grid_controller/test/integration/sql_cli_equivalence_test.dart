@TestOn('vm')
@Tags(['integration'])
library;

import 'package:grid_controller/src/errors/bd_exception.dart';
import 'package:grid_controller/src/models/bead.dart';
import 'package:grid_controller/src/services/bd_cli_service.dart';
import 'package:grid_controller/src/services/bd_runner.dart';
import 'package:grid_controller/src/services/beads_workspace.dart';
import 'package:grid_controller/src/services/dolt_query_service.dart';
import 'package:test/test.dart';

/// Criterion 4 (PDR §6.4): the SQL-vs-CLI equivalence canary.
///
/// WHEN `GC_DOLT_PASSWORD` is set and a server endpoint is discoverable, this
/// composes the bead set over the SAME live workspace twice — once via the
/// pooled [DoltQueryService] SQL read path, once via [BdCliService.exportAll] —
/// and asserts the two bead sets are identical (sorted-label parity holds,
/// ADR-0000 A11). The per-field equivalence is already unit-proven in
/// `dolt_row_mapper_test.dart`; this is the end-to-end drift canary the
/// schema-version guard backs (ADR-0001 Decisions 4 & 7).
///
/// SELF-SKIPs (via `markTestSkipped`) when no live endpoint/credential is
/// present — exactly like `services/dolt_query_service_live_test.dart` — so the
/// offline suite is unaffected.
void main() {
  test('SQL and CLI snapshot reads agree on the bead set (live, requires '
      'GC_DOLT_PASSWORD)', () async {
    final ws = BeadsWorkspace.discover();
    final endpoint = ws?.endpoint;
    if (ws == null || endpoint == null || !endpoint.hasCredential) {
      markTestSkipped(
        'no live Dolt endpoint with credentials (GC_DOLT_PASSWORD unset) — '
        'SQL-vs-CLI equivalence canary not exercised',
      );
      return;
    }

    final dolt = DoltQueryService(endpoint);
    addTearDown(dolt.close);
    try {
      await dolt.connect();
    } on BdSchemaDriftException catch (e) {
      // Forward drift is the exact signal that flips the controller to the
      // CLI path — an acceptable live outcome, not a failure.
      markTestSkipped('live schema drift: ${e.message}');
      return;
    }

    final bd = BdCliService(ProcessBdRunner(workspaceRoot: ws.root));

    // Compose both bead sets over the same working set. Read SQL first, then
    // the CLI export; if the working set changed between the two reads
    // (cross-workspace write mid-test) the probe will have moved — guard on
    // it and skip rather than flake.
    final probeBefore = await dolt.probe();
    final sqlParts = await dolt.snapshotParts();
    final cliExport = await bd.exportAll();
    final probeAfter = await dolt.probe();
    if (probeBefore != probeAfter) {
      markTestSkipped(
        'working set changed mid-read (cross-workspace write) — equivalence '
        'is only meaningful over a stable working set',
      );
      return;
    }

    final sqlById = {for (final b in sqlParts.beads) b.id: b};
    final cliById = {for (final b in cliExport.beads) b.id: b};

    // 1) Identical id sets.
    expect(
      sqlById.keys.toSet(),
      equals(cliById.keys.toSet()),
      reason: 'the SQL and CLI read paths must see the same beads',
    );

    // 2) Per-bead identity on the diff-relevant fields. The two paths compose
    //    `comments`/`metadata` differently in edge cases, so compare the
    //    fields that drive the structural diff and the sorted-label parity
    //    (ADR-0000 A11) explicitly.
    for (final id in sqlById.keys) {
      final sql = sqlById[id]!;
      final cli = cliById[id]!;
      expect(
        _diffKey(sql),
        _diffKey(cli),
        reason: 'bead $id differs between SQL and CLI read paths',
      );
      expect(
        sql.labels,
        cli.labels,
        reason: 'label parity (sorted) must hold for $id (ADR-0000 A11)',
      );
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}

/// The diff-relevant projection of a [Bead] used to compare the two read paths.
/// Mirrors the fields the structural diff compares; excludes `comments`
/// (never fetched on either path) and `metadata` (path-specific JSON shaping is
/// out of scope for the set-equivalence canary).
Map<String, Object?> _diffKey(Bead b) => {
  'id': b.id,
  'title': b.title,
  'status': b.status.wire,
  'priority': b.priority,
  'issueType': b.issueType.wire,
  'assignee': b.assignee,
  'owner': b.owner,
  'labels': b.labels,
  'dependencyCount': b.dependencyCount,
  'dependentCount': b.dependentCount,
  'ephemeral': b.ephemeral,
};
