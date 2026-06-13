import 'dart:convert';

import 'package:grid_controller/grid_controller.dart';
import 'package:test/test.dart';

import '../support/fake_bd_runner.dart';

/// Part 1 (Track E) — the actuation surface BdCliService grew for the M2
/// pour/burn/transition writes. The pour invariants are load-bearing
/// (ADR-0000 A15/A16): the graph-apply pour is PERSISTENT (no `--ephemeral`),
/// `--metadata` carries a JSON object (merge semantics), burn is `bd delete`
/// (never close), and `cook` resolves with `--mode=runtime`.
void main() {
  BdReply okObject([Map<String, dynamic>? data]) => BdReply(
    stdout: jsonEncode({
      'schema_version': 1,
      'data': data ?? <String, dynamic>{},
    }),
  );

  void expectActor(List<String> argv) {
    final i = argv.indexOf('--actor');
    expect(i, greaterThanOrEqualTo(0), reason: 'no --actor in $argv');
    expect(argv[i + 1], 'grid-controller');
  }

  group('update(--metadata) — the convergence transition write channel', () {
    test(
      'emits --metadata as a single JSON object and stamps the actor',
      () async {
        final runner = FakeBdRunner()..stubCommand('update', okObject());
        final service = BdCliService(runner);

        await service.update(
          'tg-conv',
          metadata: const {
            'convergence.state': 'terminated',
            'convergence.last_processed_wisp': 'tg-w3',
          },
        );

        final argv = runner.calls.single;
        expect(argv.first, 'update');
        expect(argv[1], 'tg-conv');
        expectActor(argv);
        final mi = argv.indexOf('--metadata');
        expect(mi, greaterThanOrEqualTo(0), reason: 'no --metadata in $argv');
        // The value is ONE JSON object string (merge semantics, A16) — not a
        // batch of key=value flags. Decode it back to assert the shape.
        final decoded = jsonDecode(argv[mi + 1]) as Map<String, dynamic>;
        expect(decoded, {
          'convergence.state': 'terminated',
          'convergence.last_processed_wisp': 'tg-w3',
        });
      },
    );

    test('an empty metadata map omits the --metadata flag entirely', () async {
      final runner = FakeBdRunner()..stubCommand('update', okObject());
      final service = BdCliService(runner);

      await service.update('tg-1', metadata: const {}, priority: 1);

      final argv = runner.calls.single;
      expect(argv, isNot(contains('--metadata')));
      expect(argv, containsAllInOrder(['--priority', '1']));
    });

    test(
      'update() remains backward-compatible: title/status/priority still work',
      () async {
        final runner = FakeBdRunner()..stubCommand('update', okObject());
        final service = BdCliService(runner);

        await service.update(
          'tg-7',
          status: BeadStatus.inProgress,
          priority: 0,
        );

        final argv = runner.calls.single;
        expect(argv, containsAllInOrder(['--status', 'in_progress']));
        expect(argv, containsAllInOrder(['--priority', '0']));
        expect(argv, isNot(contains('--metadata')));
      },
    );

    test(
      'activation channel: --type and --assignee promote a deferred node',
      () async {
        final runner = FakeBdRunner()..stubCommand('update', okObject());
        final service = BdCliService(runner);

        await service.update(
          'tg-step',
          type: IssueType.task,
          assignee: 'rig/polisher',
          metadata: const {'gc.routed_to': 'rig/polisher'},
        );

        final argv = runner.calls.single;
        expect(argv, containsAllInOrder(['--type', 'task']));
        expect(argv, containsAllInOrder(['--assignee', 'rig/polisher']));
        final mi = argv.indexOf('--metadata');
        expect(jsonDecode(argv[mi + 1]), {'gc.routed_to': 'rig/polisher'});
      },
    );
  });

  group('applyGraph — the PERSISTENT pour (ADR-0000 A15)', () {
    test(
      'default pour has NO --ephemeral and returns the key→id map',
      () async {
        // bd reads the plan from a file path, so we cannot assert the plan via
        // argv — but we CAN assert the `bd create --graph <file>` shape and the
        // absence of --ephemeral, which is the load-bearing A15 invariant.
        final runner = FakeBdRunner()
          ..stub(
            (args) =>
                args.length >= 2 && args[0] == 'create' && args[1] == '--graph',
            BdReply(
              stdout: jsonEncode({
                'schema_version': 1,
                'data': {
                  'ids': {
                    'wisp': 'tg-w1',
                    'work': 'tg-s1',
                    'evaluate': 'tg-s2',
                  },
                },
              }),
            ),
          );
        final service = BdCliService(runner);

        final plan = const GraphApplyPlan(
          commitMessage: 'pour wisp converge:tg-root:iter:1',
          nodes: [
            GraphNode(
              key: 'wisp',
              title: 'Convergence wisp iter 1',
              type: 'epic',
              parentId: 'tg-root',
              metadata: {'idempotency_key': 'converge:tg-root:iter:1'},
            ),
            GraphNode(key: 'work', title: 'work', parentKey: 'wisp'),
            GraphNode(key: 'evaluate', title: 'evaluate', parentKey: 'wisp'),
          ],
          edges: [GraphEdge(fromKey: 'evaluate', toKey: 'work')],
        );

        final ids = await service.applyGraph(plan);

        expect(ids, {'wisp': 'tg-w1', 'work': 'tg-s1', 'evaluate': 'tg-s2'});
        final argv = runner.calls.single;
        expect(argv.first, 'create');
        expect(argv[1], '--graph');
        expect(argv, contains('--json'));
        expectActor(argv);
        // THE pour invariant: a convergence pour is PERSISTENT.
        expect(
          argv,
          isNot(contains('--ephemeral')),
          reason: 'A15: convergence pours must drop --ephemeral (persistent)',
        );
      },
    );

    test('ephemeral:true is opt-in and adds --ephemeral', () async {
      final runner = FakeBdRunner()
        ..stub(
          (args) => args.length >= 2 && args[0] == 'create',
          BdReply(
            stdout: jsonEncode({
              'schema_version': 1,
              'data': {
                'ids': {'wisp': 'tg-w9'},
              },
            }),
          ),
        );
      final service = BdCliService(runner);

      await service.applyGraph(
        const GraphApplyPlan(
          commitMessage: 'm',
          nodes: [GraphNode(key: 'wisp', title: 'w')],
        ),
        ephemeral: true,
      );

      expect(runner.calls.single, contains('--ephemeral'));
    });

    test('the plan written to the temp file is the canonical JSON', () {
      // The plan's wire shape is what bd reads from the file — assert it
      // directly (the parent_id, parent_key, idempotency_key, and blocks edge).
      final plan = const GraphApplyPlan(
        commitMessage: 'pour wisp converge:tg-root:iter:2',
        nodes: [
          GraphNode(
            key: 'wisp',
            title: 'Convergence wisp iter 2',
            type: 'gate',
            parentId: 'tg-root',
            metadata: {
              'idempotency_key': 'converge:tg-root:iter:2',
              'gc.deferred_type': 'epic',
            },
          ),
          GraphNode(
            key: 'work',
            title: 'work',
            type: 'gate',
            parentKey: 'wisp',
            priority: 1,
            metadata: {'gc.deferred_type': 'task'},
          ),
        ],
        edges: [
          GraphEdge(fromKey: 'work', toKey: 'wisp', type: 'parent-child'),
        ],
      );

      final decoded = jsonDecode(plan.toJsonString()) as Map<String, dynamic>;
      expect(decoded['commit_message'], 'pour wisp converge:tg-root:iter:2');
      final nodes = decoded['nodes'] as List;
      final wisp = nodes[0] as Map<String, dynamic>;
      expect(wisp['parent_id'], 'tg-root');
      expect(
        (wisp['metadata'] as Map)['idempotency_key'],
        'converge:tg-root:iter:2',
      );
      final work = nodes[1] as Map<String, dynamic>;
      expect(work['parent_key'], 'wisp');
      expect(work['priority'], 1);
      expect((work['metadata'] as Map)['gc.deferred_type'], 'task');
      final edges = decoded['edges'] as List;
      expect((edges[0] as Map)['from_key'], 'work');
      expect((edges[0] as Map)['type'], 'parent-child');
    });
  });

  group('delete — the burn primitive (A16: delete, NEVER close)', () {
    test('delete() spawns `bd delete <id> --force` with the actor', () async {
      final runner = FakeBdRunner()..stubCommand('delete', okObject());
      final service = BdCliService(runner);

      await service.delete('tg-wisp-r2');

      final argv = runner.calls.single;
      expect(argv.first, 'delete');
      expect(argv[1], 'tg-wisp-r2');
      expect(argv, contains('--force'));
      expectActor(argv);
      // A burn must NEVER route through close.
      expect(argv, isNot(contains('close')));
    });
  });

  group('cook — formula resolve (A15 step 1; a READ)', () {
    test(
      'cook() emits --mode=runtime + repeated --var, carries NO actor',
      () async {
        final runner = FakeBdRunner()
          ..stubCommand(
            'cook',
            BdReply(
              stdout: jsonEncode({
                'schema_version': 1,
                'data': {
                  'proto_id': 'mol-converge-probe',
                  'steps': [
                    {'id': 'work', 'title': 'iterate on tron', 'type': 'task'},
                    {
                      'id': 'evaluate',
                      'title': 'evaluate tron',
                      'type': 'task',
                      'needs': ['work'],
                    },
                  ],
                },
              }),
            ),
          );
        final service = BdCliService(runner);

        final resolved = await service.cook(
          'mol-converge-probe.formula.json',
          vars: const {'target': 'tron'},
        );

        expect((resolved['steps'] as List), hasLength(2));
        final argv = runner.calls.single;
        expect(argv.first, 'cook');
        expect(argv[1], 'mol-converge-probe.formula.json');
        expect(argv, contains('--mode=runtime'));
        expect(argv, containsAllInOrder(['--var', 'target=tron']));
        expect(argv, contains('--json'));
        // A resolve writes nothing — no actor, and crucially no --persist.
        expect(argv, isNot(contains('--actor')));
        expect(argv, isNot(contains('--persist')));
      },
    );
  });
}
