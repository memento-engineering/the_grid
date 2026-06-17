import 'dart:async';

import 'package:grid_controller/grid_controller.dart';

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

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    calls.add(List<String>.unmodifiable(args));
    stdins.add(stdin);
    final sub = args.isNotEmpty ? args.first : '';
    if (sub == 'create' && failCreateError != null) {
      return Future<BdResult>.value(
        BdResult(
          exitCode: 1,
          stdout:
              '{"schema_version":1,"data":{"error":"$failCreateError"}}',
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

  /// All calls whose leading subcommand is [sub].
  List<List<String>> callsFor(String sub) =>
      calls.where((c) => c.isNotEmpty && c.first == sub).toList();

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
