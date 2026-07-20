import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';

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
/// `--metadata {…}`, never `show`, never SQL). A canned envelope reply is
/// matched by the invocation's leading subcommand; `create` returns a synthetic
/// id the caller controls so the chokepoint's mint+stamp can be exercised
/// end-to-end with no real `bd`.
class RecordingBdRunner implements BdRunner {
  RecordingBdRunner({String createdId = 'tgdog-sess1'})
    : _createdId = createdId;

  String _createdId;

  /// Every invocation's argv, in call order.
  final List<List<String>> calls = <List<String>>[];

  /// Each invocation's piped stdin (null when none), parallel to [calls].
  final List<String?> stdins = <String?>[];

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
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    calls.add(List<String>.unmodifiable(args));
    stdins.add(stdin);
    final sub = args.isNotEmpty ? args.first : '';
    if (sub == 'export') {
      // `bd export --all` emits RAW JSONL (one issue object per line), NOT an
      // envelope — the snapshot read path `exportAll` parses.
      final depsByIssue = <String, List<Map<String, dynamic>>>{};
      for (final dep in exportDependencies) {
        (depsByIssue[dep.issueId] ??= <Map<String, dynamic>>[]).add(
          dep.toJson(),
        );
      }
      final jsonl = exportBeads
          .map((b) {
            final json = b.toJson();
            final deps = depsByIssue[b.id];
            if (deps != null) json['dependencies'] = deps;
            return jsonEncode(json);
          })
          .join('\n');
      return Future<BdResult>.value(
        BdResult(exitCode: 0, stdout: jsonl, stderr: ''),
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
  List<List<String>> callsFor(String sub) =>
      calls.where((c) => c.isNotEmpty && c.first == sub).toList();

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

  /// The JSON string passed to `--metadata` on the call at [index] of the
  /// `update` calls, or null if that update carried no metadata.
  String? metadataOfUpdate(int index) {
    final updates = callsFor('update');
    if (index >= updates.length) return null;
    final c = updates[index];
    final i = c.indexOf('--metadata');
    return (i >= 0 && i + 1 < c.length) ? c[i + 1] : null;
  }
}
