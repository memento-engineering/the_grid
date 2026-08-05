import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

void main() {
  test('CLI snapshot composes every discovered type/status scope', () async {
    final runner = _SnapshotRunner();
    final snapshot = await CliSnapshotReader(BdCliService(runner)).read();

    expect(snapshot.beadsById['tg-gate']?.issueType, const IssueType('gate'));
    expect(snapshot.beadsById['tg-task']?.status, BeadStatus.closed);
    expect(snapshot.dependencies, hasLength(1));
    expect(runner.calls.where((args) => args.first == 'list'), hasLength(4));
    expect(
      runner.calls.where((args) => args.first == 'list'),
      everyElement(
        predicate<List<String>>(
          (args) =>
              args.length == 6 &&
              args[1] == '-t' &&
              args[3] == '--status' &&
              args[5] == '--json',
        ),
      ),
    );
    expect(runner.calls.where((args) => args.contains('--all')), isEmpty);
    expect(runner.calls.where((args) => args.first == 'export'), isEmpty);
  });

  test('CLI snapshot refuses malformed discovery loudly', () async {
    final runner = _SnapshotRunner()..malformed = true;
    await expectLater(
      CliSnapshotReader(BdCliService(runner)).read(),
      throwsA(isA<BdParseException>()),
    );
    expect(runner.calls.where((args) => args.first == 'list'), isEmpty);
  });
}

class _SnapshotRunner implements BdRunner {
  final List<List<String>> calls = [];
  bool malformed = false;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List.unmodifiable(args));
    switch (args.first) {
      case 'export':
        return const BdResult(
          exitCode: 1,
          stdout: '',
          stderr: 'Error: export is not supported in proxied-server mode',
        );
      case 'types':
        return _map({
          'core_types': malformed ? 'task' : const ['task'],
          'custom_types': const [
            {'name': 'gate'},
          ],
        });
      case 'statuses':
        return _map({
          'built_in_statuses': const ['open', 'closed'],
          'custom_statuses': const <String>[],
        });
      case 'ready':
        return _list(const []);
      case 'list':
        final type = args[2];
        final status = args[4];
        if (type == 'gate' && status == 'open') {
          return _list([
            {
              'id': 'tg-gate',
              'issue_type': 'gate',
              'status': 'open',
              'dependencies': [
                {
                  'issue_id': 'tg-gate',
                  'depends_on_id': 'tg-task',
                  'type': 'blocks',
                },
              ],
            },
          ]);
        }
        if (type == 'task' && status == 'closed') {
          return _list(const [
            {'id': 'tg-task', 'issue_type': 'task', 'status': 'closed'},
          ]);
        }
        return _list(const []);
      default:
        throw StateError('unexpected call: $args');
    }
  }

  BdResult _map(Map<String, dynamic> data) => BdResult(
    exitCode: 0,
    stdout: jsonEncode({'schema_version': 1, 'data': data}),
    stderr: '',
  );

  BdResult _list(List<Map<String, dynamic>> data) => BdResult(
    exitCode: 0,
    stdout: jsonEncode({'schema_version': 1, 'data': data}),
    stderr: '',
  );
}
