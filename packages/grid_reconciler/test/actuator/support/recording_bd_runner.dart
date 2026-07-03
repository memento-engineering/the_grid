import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';

/// A recording [BdRunner] for actuator tests: records every argv (and stdin)
/// in call order, and answers from registered stubs. This is the witness for
/// the exact bd call SEQUENCE the [BdActuator] emits per action — the
/// write-ordering invariant (last_processed_wisp LAST), burn = delete (never
/// close), pour = persistent (no --ephemeral).
///
/// Defaults: an unmatched `update`/`close`/`delete` returns an empty success
/// envelope; `cook`/`create --graph` must be stubbed (their `data` shape is
/// load-bearing). A stub may be registered with [onCook] / [onCreateGraph] /
/// [failOn].
class RecordingBdRunner implements BdRunner {
  RecordingBdRunner();

  /// Every invocation's argv, in call order.
  final List<List<String>> calls = [];

  /// Each invocation's stdin (parallel to [calls]).
  final List<String?> stdins = [];

  /// cook → the resolved `data` map to return (the `steps` DAG).
  Map<String, dynamic> Function(List<String> argv)? onCook;

  /// create --graph → the `ids` map to return.
  Map<String, String> Function(List<String> argv)? onCreateGraph;

  /// A predicate over argv that, when true, makes the call return exit 1 with
  /// an error envelope (to exercise pour-failure / persist-failure paths).
  bool Function(List<String> argv)? failOn;

  /// Convenience views over [calls].
  List<List<String>> get updates => _verb('update');
  List<List<String>> get closes => _verb('close');
  List<List<String>> get deletes => _verb('delete');
  List<List<String>> _verb(String v) =>
      calls.where((c) => c.isNotEmpty && c.first == v).toList();

  /// The flattened verb stream (`update`/`close`/`delete`/`cook`/`create`) in
  /// call order — the ordered-write witness.
  List<String> get verbs => [
    for (final c in calls)
      if (c.isNotEmpty) c.first,
  ];

  /// Each `update`'s `(id, metadataJsonMap)` decoded from `--metadata`. Updates
  /// without `--metadata` (activation type/assignee-only) map to an empty map.
  List<({String id, Map<String, dynamic> metadata})> get metadataWrites {
    final out = <({String id, Map<String, dynamic> metadata})>[];
    for (final c in updates) {
      final mi = c.indexOf('--metadata');
      final meta = mi >= 0
          ? (jsonDecode(c[mi + 1]) as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      out.add((id: c[1], metadata: meta));
    }
    return out;
  }

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    stdins.add(stdin);

    if (failOn?.call(args) ?? false) {
      return BdResult(
        exitCode: 1,
        stdout: jsonEncode({
          'schema_version': 1,
          'data': {'error': 'stubbed failure'},
        }),
        stderr: '',
      );
    }

    final verb = args.isNotEmpty ? args.first : '';
    if (verb == 'cook') {
      final data = onCook?.call(args) ?? const {'steps': <dynamic>[]};
      return _ok(data);
    }
    if (verb == 'create' && args.length > 1 && args[1] == '--graph') {
      final ids = onCreateGraph?.call(args) ?? const {'wisp': 'poured-wisp'};
      return _ok({'ids': ids});
    }
    // update / close / delete / anything else: empty success envelope.
    return _ok(const <String, dynamic>{});
  }

  BdResult _ok(Map<String, dynamic> data) => BdResult(
    exitCode: 0,
    stdout: jsonEncode({'schema_version': 1, 'data': data}),
    stderr: '',
  );
}
