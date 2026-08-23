import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';

final class OpenBeadsCall {
  const OpenBeadsCall({
    required this.types,
    required this.metadataAll,
    required this.metadataAny,
  });

  final Set<IssueType> types;
  final Map<String, String> metadataAll;
  final Map<String, String> metadataAny;
}

// DRIFT NOTE (tg-8gv.11(e)): this class has a twin,
// `package:grid_engine/src/testing/engine_fakes.dart`'s `RecordingBdRunner`.
// The duplication is dependency-direction-forced — grid_runtime's test
// support cannot depend on grid_engine — and is accepted as-is rather than
// factored out. If you change the recorded-call shape or add coverage here,
// check whether the grid_engine twin needs the same change.

/// A recording [BdRunner] for offline Track-4 tests (Fakes, not mocks).
///
/// Records the full argv + piped stdin of every `bd` invocation so tests can
/// assert the EXACT commands the chokepoint issued (`--actor grid-controller`,
/// `--set-metadata key=value`, never `show`, never SQL). A canned envelope reply is
/// matched by the invocation's leading subcommand; `create` returns a synthetic
/// id the caller controls so the chokepoint's mint+stamp can be exercised
/// end-to-end with no real `bd`.
class RecordingBdRunner implements BdRunner, BeadProbeReader {
  RecordingBdRunner({
    String createdId = 'tgdog-sess1',
    this.guardedWriteHelp = '--if-assignee --if-status',
  }) : _createdId = createdId;

  final String guardedWriteHelp;

  String _createdId;

  /// Every invocation's argv, in call order.
  final List<List<String>> calls = <List<String>>[];

  /// Each invocation's piped stdin (null when none), parallel to [calls].
  final List<String?> stdins = <String?>[];

  final List<OpenBeadsCall> _openBeadCalls = [];

  List<OpenBeadsCall> get openBeadCalls => List.unmodifiable(_openBeadCalls);

  /// Sets the id the next `bd create` reports (so a test can mint two sessions
  /// with distinct ids).
  set nextCreatedId(String id) => _createdId = id;

  /// When non-null, every `bd create` returns a FAILED envelope carrying this
  /// error (exit 1, error-on-stdout) — reproducing a real bd validation reject
  /// (e.g. `invalid issue type: session`) so a test can prove the dispatcher
  /// survives a create failure instead of crashing the controller.
  String? failCreateError;

  /// The beads the `export` (snapshot) read returns as JSONL — the store the
  /// chokepoint's mint-dedup probe (`createGate`, tg-i08) reads. Default empty
  /// (a fresh store with no gates → every gate mints). Stage an OPEN gate here
  /// to exercise the reuse-and-refresh path.
  List<Bead> exportBeads = const <Bead>[];
  List<BeadDependency> exportDependencies = const <BeadDependency>[];

  /// The `key → id` map the next `bd create --graph` invocation reports
  /// (`applyGraph`'s `data.ids`; mirrors `FakeBdRunner`'s stubbed-envelope
  /// pattern in `bd_cli_service_actuator_test.dart`'s own `applyGraph`
  /// coverage) — `StationBeadWriter.createMolecule`'s pour reads this back
  /// through `BdCliService.applyGraph`. A test stages the ids it expects
  /// `instantiateMolecule`'s plan-local keys to receive.
  Map<String, String> graphApplyIds = const <String, String>{};

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async {
    final matches = exportBeads.where(
      (bead) => bead.id == id && types.contains(bead.issueType),
    );
    return matches.isEmpty ? null : matches.single;
  }

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) async {
    _openBeadCalls.add(
      OpenBeadsCall(
        types: Set.unmodifiable(types),
        metadataAll: Map.unmodifiable(metadataAll),
        metadataAny: Map.unmodifiable(metadataAny),
      ),
    );
    return exportBeads.where((bead) {
      if (bead.isClosed || !types.contains(bead.issueType)) return false;
      if (!metadataAll.entries.every((e) => bead.metadata[e.key] == e.value)) {
        return false;
      }
      return metadataAny.isEmpty ||
          metadataAny.entries.any((e) => bead.metadata[e.key] == e.value);
    }).toList();
  }

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) async {
    final ids = exportDependencies
        .where(
          (edge) =>
              edge.type == DependencyType.supersedes &&
              priorIds.contains(edge.dependsOnId),
        )
        .map((edge) => edge.issueId)
        .toSet();
    return exportBeads
        .where((bead) => ids.contains(bead.id) && !bead.isClosed)
        .toList();
  }

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    calls.add(List<String>.unmodifiable(args));
    stdins.add(stdin);
    if (args case ['update', '--help']) {
      return Future<BdResult>.value(
        BdResult(exitCode: 0, stdout: guardedWriteHelp, stderr: ''),
      );
    }
    final sub = args.isNotEmpty ? args.first : '';
    if (sub == 'dep' && args.length > 1 && args[1] == 'list') {
      return Future<BdResult>.value(
        BdResult(
          exitCode: 0,
          stdout: jsonEncode({
            'schema_version': 1,
            'data': [
              for (final dependency in exportDependencies) dependency.toJson(),
            ],
          }),
          stderr: '',
        ),
      );
    }
    if (sub == 'export') {
      return Future<BdResult>.value(
        const BdResult(
          exitCode: 1,
          stdout: '',
          stderr: 'Error: export is not supported in proxied-server mode',
        ),
      );
    }
    if (sub == 'create' && failCreateError != null) {
      return Future<BdResult>.value(
        BdResult(
          exitCode: 1,
          stdout: '{"schema_version":1,"data":{"error":"$failCreateError"}}',
          stderr: '',
        ),
      );
    }
    if (sub == 'create' && args.length > 1 && args[1] == '--graph') {
      // `bd create --graph <plan-file> [--ephemeral] --json` — a graph-apply
      // pour reports a `key → id` MAP (`data.ids`), never a single `data.id`.
      return Future<BdResult>.value(
        BdResult(
          exitCode: 0,
          stdout: jsonEncode({
            'schema_version': 1,
            'data': {'ids': graphApplyIds},
          }),
          stderr: '',
        ),
      );
    }
    final data = switch (sub) {
      'create' => '{"id":"$_createdId"}',
      // update/close/delete/batch — bd returns the affected bead; an object
      // envelope with the id suffices for the chokepoint (it ignores the body).
      _ => '{"id":"${_idArg(args)}"}',
    };
    return Future<BdResult>.value(
      BdResult(
        exitCode: 0,
        stdout: '{"schema_version":1,"data":$data}',
        stderr: '',
      ),
    );
  }

  /// The id argument of a mutation (`update <id>`, `close <id>`, `delete <id>`)
  /// — the second argv element for those forms, else empty.
  static String _idArg(List<String> args) => args.length >= 2 ? args[1] : '';

  // ---- assertion helpers --------------------------------------------------

  /// All calls whose leading subcommand is [sub]. For `'create'`, this
  /// INCLUDES graph-apply pours (`create --graph …`) — use [graphApplyCalls]
  /// to isolate those from a plain single-bead `create`.
  List<List<String>> callsFor(String sub) => calls
      .where(
        (c) =>
            c.isNotEmpty &&
            c.first == sub &&
            !(c.length == 2 && c[0] == 'update' && c[1] == '--help'),
      )
      .toList();

  /// The `bd create --graph <plan-file> …` pours only (`StationBeadWriter
  /// .createMolecule`'s mint) — disjoint from [callsFor]`('create')`'s plain
  /// single-bead creates, which never carry `--graph`.
  List<List<String>> get graphApplyCalls => calls
      .where((c) => c.length > 1 && c[0] == 'create' && c[1] == '--graph')
      .toList();

  /// True if EVERY mutation carried `--actor grid-controller`.
  bool get everyMutationHasActor {
    const mutations = {'create', 'update', 'close', 'delete', 'batch'};
    for (final c in calls) {
      if (c.isEmpty || !mutations.contains(c.first)) continue;
      if (c.length == 2 && c[0] == 'update' && c[1] == '--help') continue;
      final i = c.indexOf('--actor');
      if (i < 0 || i + 1 >= c.length || c[i + 1] != 'grid-controller') {
        return false;
      }
    }
    return true;
  }

  /// True if no call was `bd show` (forbidden on a controller path).
  bool get neverCalledShow =>
      calls.every((c) => c.isEmpty || c.first != 'show');

  /// A JSON test view of the merge operations on the indexed update call.
  String? metadataOfUpdate(int index) {
    final call = callsFor('update')[index];
    final metadata = <String, String>{};
    for (var i = 0; i < call.length - 1; i++) {
      if (call[i] != '--set-metadata') continue;
      final assignment = call[i + 1];
      final separator = assignment.indexOf('=');
      if (separator < 0) continue;
      metadata[assignment.substring(0, separator)] = assignment.substring(
        separator + 1,
      );
    }
    return metadata.isEmpty ? null : jsonEncode(metadata);
  }
}
