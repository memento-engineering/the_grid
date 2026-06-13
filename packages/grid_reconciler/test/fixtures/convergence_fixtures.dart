import 'dart:convert';
import 'dart:io';

import 'package:grid_controller/grid_controller.dart';
import 'package:path/path.dart' as p;

/// Loads the version-pinned, gc-produced convergence fixtures
/// (`fixtures/upstream/2026-06-11-bd-1.0.5/convergence/`) — the codec-fidelity
/// oracle for Track I (ADR-0000 A29). Captured from gc's REAL convergence
/// writer, never authored; READ-ONLY (CLAUDE.md: re-capture only via the
/// porting skill).
///
/// Mirrors grid_controller's `test/support/fixtures.dart` directory walk so the
/// suite resolves the repo-root `fixtures/` regardless of whether `dart test`
/// runs from the package or the workspace root.
const fixtureSet = '2026-06-11-bd-1.0.5';
const _convergenceSubdir = 'convergence';

Directory _convergenceDir() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final candidate = Directory(
      p.join(dir.path, 'fixtures', 'upstream', fixtureSet, _convergenceSubdir),
    );
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError(
    'convergence fixtures ($fixtureSet/$_convergenceSubdir) not found '
    'walking up from ${Directory.current.path}',
  );
}

/// Raw text of a pinned convergence fixture file.
String _text(String name) =>
    File(p.join(_convergenceDir().path, name)).readAsStringSync();

/// One pinned `0N-*.json` scenario, decoded.
ConvergenceFixture loadScenario(String fileName) {
  final json = jsonDecode(_text(fileName)) as Map<String, dynamic>;
  return ConvergenceFixture.fromJson(fileName, json);
}

/// Every `0N-*.json` scenario file, in fixture (state-advance) order.
const scenarioFileNames = <String>[
  '01-active-manual.json',
  '02-waiting-manual.json',
  '03-terminated-approved.json',
  '04-gate-pass-terminated.json',
  '05-no-convergence-at-max.json',
  '06-waiting-trigger.json',
];

/// All six scenarios.
List<ConvergenceFixture> loadAllScenarios() => [
  for (final name in scenarioFileNames) loadScenario(name),
];

/// The `bd-export-roundtrip.jsonl` line: 04's metadata written via
/// `bd update --metadata` then `bd export --all` (proves bd preserves every
/// value as a STRING). Single JSON object.
Map<String, dynamic> loadExportRoundtrip() {
  final lines = const LineSplitter()
      .convert(_text('bd-export-roundtrip.jsonl'))
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lines.length != 1) {
    throw StateError('expected one export line, got ${lines.length}');
  }
  return jsonDecode(lines.single) as Map<String, dynamic>;
}

/// A decoded convergence scenario fixture: the root metadata map gc wrote, plus
/// the captured subgraph (root → wisp(molecule) → step), each node carrying
/// id / issue_type / status / parent / metadata / nested children.
class ConvergenceFixture {
  ConvergenceFixture({
    required this.fileName,
    required this.scenario,
    required this.convergenceRoot,
    required this.rootMetadata,
    required this.subgraph,
  });

  factory ConvergenceFixture.fromJson(
    String fileName,
    Map<String, dynamic> json,
  ) {
    return ConvergenceFixture(
      fileName: fileName,
      scenario: json['scenario'] as String,
      convergenceRoot: json['convergence_root'] as String,
      rootMetadata: Map<String, dynamic>.from(
        json['root_metadata'] as Map<String, dynamic>,
      ),
      subgraph: FixtureNode.fromJson(json['subgraph'] as Map<String, dynamic>),
    );
  }

  final String fileName;
  final String scenario;
  final String convergenceRoot;

  /// The convergence root bead's `convergence.*` metadata map, verbatim — the
  /// codec oracle.
  final Map<String, dynamic> rootMetadata;

  /// The captured subgraph tree (root node).
  final FixtureNode subgraph;

  /// Flattens the captured (nested) subgraph into the_grid's snapshot model:
  /// every node becomes a [Bead] and every captured parent (child.parent /
  /// nesting) becomes the parent-child DEPENDENCY edge the projections resolve
  /// through (A15: hierarchy is an edge; child = issue_id, parent =
  /// depends_on_id). The capture nests + sets `parent`; the_grid reads it as an
  /// edge, so we convert here.
  GraphSnapshot toSnapshot({DateTime? capturedAt}) {
    final beads = <Bead>[];
    final deps = <BeadDependency>[];
    subgraph.collect(beads, deps);
    return GraphSnapshot.fromParts(
      beads: beads,
      dependencies: deps,
      readyIds: const <String>{},
      capturedAt: capturedAt ?? fixtureCapturedAt,
    );
  }
}

/// A captured subgraph node (root / wisp / step). Mirrors the JSON shape: id,
/// issue_type, status, optional parent, the verbatim metadata map, and nested
/// children.
class FixtureNode {
  FixtureNode({
    required this.id,
    required this.title,
    required this.issueType,
    required this.status,
    required this.parent,
    required this.metadata,
    required this.children,
  });

  factory FixtureNode.fromJson(Map<String, dynamic> json) {
    final rawChildren = (json['children'] as List<dynamic>?) ?? const [];
    return FixtureNode(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      issueType: json['issue_type'] as String,
      status: json['status'] as String,
      parent: json['parent'] as String?,
      metadata: Map<String, dynamic>.from(
        (json['metadata'] as Map<String, dynamic>?) ?? const {},
      ),
      children: [
        for (final c in rawChildren)
          FixtureNode.fromJson(c as Map<String, dynamic>),
      ],
    );
  }

  final String id;
  final String title;
  final String issueType;
  final String status;
  final String? parent;
  final Map<String, dynamic> metadata;
  final List<FixtureNode> children;

  /// This node as a [Bead]. The capture serializes a bead status string
  /// (`open` / `closed`); map it through grid_controller's converter the same
  /// way `Bead.fromJson` would.
  Bead toBead() => Bead(
    id: id,
    title: title,
    issueType: IssueType(issueType),
    status: _statusFromWire(status),
    ephemeral: issueType == IssueType.molecule.wire,
    metadata: Map<String, dynamic>.from(metadata),
  );

  /// Appends this node (and its subtree) as beads + parent-child edges. The
  /// edge is synthesized from `parent` (gc direction: child = issue_id, parent
  /// = depends_on_id).
  void collect(List<Bead> beads, List<BeadDependency> deps) {
    beads.add(toBead());
    final p = parent;
    if (p != null && p.isNotEmpty) {
      deps.add(
        BeadDependency(
          issueId: id,
          dependsOnId: p,
          type: DependencyType.parentChild,
        ),
      );
    }
    for (final child in children) {
      child.collect(beads, deps);
    }
  }

  /// Depth-first node lookup (the root included).
  FixtureNode? find(String wantId) {
    if (id == wantId) return this;
    for (final child in children) {
      final hit = child.find(wantId);
      if (hit != null) return hit;
    }
    return null;
  }
}

/// gc's bead status wire string → [BeadStatus]. `BeadStatus` is an open-set
/// extension type over the wire string (ADR-0000 A9), so the capture's
/// `open` / `closed` (and any future custom value) map straight through,
/// exactly as `Bead.fromJson`'s `BeadStatusConverter` would.
BeadStatus _statusFromWire(String wire) => BeadStatus(wire);

/// A stable capture timestamp for fixture-derived snapshots (the fixtures carry
/// no per-bead timestamps; the codec/projection assertions do not depend on
/// wall-clock).
final fixtureCapturedAt = DateTime.utc(2026, 6, 13, 16, 17, 31);
