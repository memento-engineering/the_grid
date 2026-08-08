import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

void main() {
  const allStatuses =
      'status=open OR status=in_progress OR status=blocked OR '
      'status=deferred OR status=closed';
  test('CLI snapshot uses one broad graph query', () async {
    final runner = _SnapshotRunner();
    final snapshot = await CliSnapshotReader(BdCliService(runner)).read();

    expect(snapshot.beadsById['tg-gate']?.issueType, const IssueType('gate'));
    expect(snapshot.beadsById['tg-task']?.status, BeadStatus.closed);
    expect(snapshot.dependencies.single.type, DependencyType.blocks);
    expect(snapshot.readyIds, contains('tg-gate'));
    expect(runner.calls, [
      ['query', allStatuses, '--all', '--json', '--limit', '0'],
      ['dep', 'list', 'tg-gate', 'tg-task', '--json'],
      ['ready', '--json', '--limit', '0'],
    ]);
    expect(
      runner.calls.any(
        (args) => const {
          'export',
          'show',
          'statuses',
          'types',
          'list',
        }.contains(args.first),
      ),
      isFalse,
    );
  });

  test('CLI snapshot skips dependency subprocess for an empty graph', () async {
    final runner = _SnapshotRunner()..empty = true;
    final snapshot = await CliSnapshotReader(BdCliService(runner)).read();
    expect(snapshot.beadsById, isEmpty);
    expect(runner.calls, [
      ['query', allStatuses, '--all', '--json', '--limit', '0'],
      ['ready', '--json', '--limit', '0'],
    ]);
  });

  test('CLI snapshot propagates broad-query command failures', () async {
    final runner = _SnapshotRunner()..failQuery = true;
    await expectLater(
      CliSnapshotReader(BdCliService(runner)).read(),
      throwsA(isA<BdCommandFailed>()),
    );
    expect(runner.calls, [
      ['query', allStatuses, '--all', '--json', '--limit', '0'],
    ]);
  });

  test('CLI snapshot reads and derives dependencies for 120 beads', () async {
    final runner = _SnapshotRunner()..largeGraph = true;
    final snapshot = await CliSnapshotReader(BdCliService(runner)).read();

    expect(snapshot.beadsById, hasLength(120));
    expect(snapshot.beadsById.keys, containsAll(['tg-0', 'tg-119']));
    expect(runner.calls.first, [
      'query',
      allStatuses,
      '--all',
      '--json',
      '--limit',
      '0',
    ]);
    final dependencyCalls = runner.calls
        .where(
          (args) => args.length >= 2 && args[0] == 'dep' && args[1] == 'list',
        )
        .toList(growable: false);
    expect(dependencyCalls, hasLength(3));
    final derivedIds = dependencyCalls
        .expand((args) => args.skip(2).takeWhile((arg) => arg != '--json'))
        .toSet();
    expect(derivedIds, hasLength(120));
    expect(derivedIds, containsAll(['tg-0', 'tg-119']));
  });
}

class _SnapshotRunner implements BdRunner {
  final List<List<String>> calls = [];
  bool empty = false;
  bool failQuery = false;
  bool largeGraph = false;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List.unmodifiable(args));
    if (args.first == 'query') {
      if (failQuery) {
        return const BdResult(exitCode: 1, stdout: '', stderr: 'query failed');
      }
      if (largeGraph) {
        return _list([
          for (var i = 0; i < 120; i++)
            {'id': 'tg-$i', 'issue_type': 'task', 'status': 'open'},
        ]);
      }
      return _list(
        empty
            ? const []
            : const [
                {'id': 'tg-gate', 'issue_type': 'gate', 'status': 'open'},
                {'id': 'tg-task', 'issue_type': 'task', 'status': 'closed'},
              ],
      );
    }
    if (args.first == 'dep') {
      if (largeGraph) return _list(const []);
      return _list(const [
        {'issue_id': 'tg-gate', 'depends_on_id': 'tg-task', 'type': 'blocks'},
      ]);
    }
    if (args.first == 'ready') {
      if (largeGraph) return _list(const []);
      return _list(
        empty
            ? const []
            : const [
                {'id': 'tg-gate', 'issue_type': 'gate', 'status': 'open'},
              ],
      );
    }
    throw StateError('unexpected call: $args');
  }

  BdResult _list(List<Map<String, dynamic>> data) => BdResult(
    exitCode: 0,
    stdout: jsonEncode({'schema_version': 1, 'data': data}),
    stderr: '',
  );
}
