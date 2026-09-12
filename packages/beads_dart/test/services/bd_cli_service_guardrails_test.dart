import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

import '../support/fake_bd_runner.dart';

void main() {
  group('typed positive-control queries', () {
    String variant(BdQueryResult result) => switch (result) {
      BdQueryRows() => 'rows',
      BdQueryVerifiedEmpty() => 'verified-empty',
      BdQueryUnavailable() => 'unavailable',
    };

    test('returns rows immediately without running the control', () async {
      final runner = FakeBdRunner(
        queuedReplies: [
          BdReply(stdout: _beads(const [Bead(id: 'tg-1')])),
        ],
      );

      final result = await BdCliService(runner).queryWithPositiveControl(
        'status:open',
        positiveControlExpression: 'id:*',
      );

      expect(variant(result), 'rows');
      expect(switch (result) {
        BdQueryRows(:final rows) => rows.single.id,
        BdQueryVerifiedEmpty() || BdQueryUnavailable() => null,
      }, 'tg-1');
      expect(runner.calls, hasLength(1));
    });

    test('returns verified empty only after a non-empty control', () async {
      final runner = FakeBdRunner(
        queuedReplies: [
          BdReply(stdout: _beads()),
          BdReply(stdout: _beads(const [Bead(id: 'tg-control')])),
        ],
      );

      final result = await BdCliService(runner).queryWithPositiveControl(
        'id:absent',
        positiveControlExpression: 'id:tg-control',
        includeClosed: true,
      );

      expect(variant(result), 'verified-empty');
      final verified = result as BdQueryVerifiedEmpty;
      expect(verified.targetCall, [
        'bd',
        'query',
        'id:absent',
        '--all',
        '--json',
        '--limit',
        '0',
      ]);
      expect(verified.positiveControlCall, [
        'bd',
        'query',
        'id:tg-control',
        '--all',
        '--json',
        '--limit',
        '0',
      ]);
    });

    test(
      'failed target, failed control, and double-empty are unavailable',
      () async {
        final cases = <List<BdReply>>[
          const [BdReply(exitCode: 1, stderr: 'target failed')],
          [
            BdReply(stdout: _beads()),
            const BdReply(exitCode: 1, stderr: 'control failed'),
          ],
          [BdReply(stdout: _beads()), BdReply(stdout: _beads())],
        ];

        for (final replies in cases) {
          final result =
              await BdCliService(
                FakeBdRunner(queuedReplies: replies),
              ).queryWithPositiveControl(
                'id:absent',
                positiveControlExpression: 'id:control',
              );
          expect(variant(result), 'unavailable');
          final unavailable = result as BdQueryUnavailable;
          expect(unavailable.targetCall, [
            'bd',
            'query',
            'id:absent',
            '--json',
            '--limit',
            '0',
          ]);
          expect(unavailable.positiveControlCall, [
            'bd',
            'query',
            'id:control',
            '--json',
            '--limit',
            '0',
          ]);
          expect(unavailable.reason, isNotEmpty);
          expect(unavailable.remedy, contains('store is reachable'));
        }
      },
    );
  });

  group('silent-success refusals', () {
    test(
      'export tombstone refuses proxied mode without a runner call',
      () async {
        final runner = FakeBdRunner();

        await expectLater(
          BdCliService(runner, doltMode: DoltMode.proxiedServer).exportAll(),
          throwsA(
            isA<BdGuardrailRefused>()
                .having((error) => error.call, 'call', [
                  'bd',
                  'export',
                  '--all',
                ])
                .having(
                  (error) => error.reason,
                  'reason',
                  contains('exit zero'),
                )
                .having(
                  (error) => error.remedy,
                  'remedy',
                  allOf(
                    contains('listScope'),
                    contains('queryWithPositiveControl'),
                  ),
                ),
          ),
        );
        expect(runner.calls, isEmpty);
      },
    );

    test(
      'proxied ephemeral graph refuses before runner and keeps direct path',
      () async {
        const plan = GraphApplyPlan(
          commitMessage: 'wisp',
          nodes: [GraphNode(key: 'root', title: 'root')],
        );
        final proxied = FakeBdRunner();
        await expectLater(
          BdCliService(
            proxied,
            doltMode: DoltMode.proxiedServer,
          ).applyGraph(plan, ephemeral: true),
          throwsA(
            isA<BdGuardrailRefused>()
                .having(
                  (error) => error.call,
                  'call',
                  containsAllInOrder([
                    'bd',
                    'create',
                    '--graph',
                    '<plan>',
                    '--ephemeral',
                  ]),
                )
                .having(
                  (error) => error.remedy,
                  'remedy',
                  contains('ephemeral: false'),
                ),
          ),
        );
        expect(proxied.calls, isEmpty);

        final direct = FakeBdRunner(
          queuedReplies: [
            BdReply(
              stdout: jsonEncode({
                'schema_version': 1,
                'data': {
                  'ids': {'root': 'tg-root'},
                },
              }),
            ),
          ],
        );
        await BdCliService(
          direct,
          doltMode: DoltMode.direct,
        ).applyGraph(plan, ephemeral: true);
        expect(direct.calls.single, contains('--ephemeral'));
        expect(direct.timeouts.single, BdCliService.pourTimeout);
      },
    );

    test(
      'non-empty notes refuse by byte count and opt-in preserves replacement',
      () async {
        const existing = 'éx';
        const replacement = 'new notes';
        final refusedRunner = FakeBdRunner(
          queuedReplies: [
            BdReply(
              stdout: _beads(const [Bead(id: 'tg-1', notes: existing)]),
            ),
          ],
        );

        await expectLater(
          BdCliService(refusedRunner).update('tg-1', notes: replacement),
          throwsA(
            isA<BdGuardrailRefused>()
                .having((error) => error.call, 'call', contains('--notes'))
                .having(
                  (error) => error.reason,
                  'reason',
                  contains('3 existing UTF-8 byte(s)'),
                )
                .having(
                  (error) => error.remedy,
                  'remedy',
                  allOf(
                    contains('allowNotesReplacement: true'),
                    contains('--allow-notes-replacement'),
                  ),
                ),
          ),
        );
        expect(refusedRunner.calls, [
          ['query', 'id=tg-1', '--all', '--json', '--limit', '0'],
        ]);

        final allowedRunner = FakeBdRunner(
          queuedReplies: [
            BdReply(
              stdout: _beads(const [Bead(id: 'tg-1', notes: existing)]),
            ),
            const BdReply(stdout: '{"schema_version":1,"data":{}}'),
            BdReply(
              stdout: _beads(const [Bead(id: 'tg-1', notes: replacement)]),
            ),
          ],
        );
        await BdCliService(
          allowedRunner,
        ).update('tg-1', notes: replacement, allowNotesReplacement: true);
        final mutation = allowedRunner.calls.singleWhere(
          (call) => call.first == 'update',
        );
        expect(mutation, containsAllInOrder(['--notes', replacement]));
        expect(mutation, isNot(contains('--append-notes')));
        expect(allowedRunner.calls.map((call) => call.first), [
          'query',
          'update',
          'query',
        ]);
        expect(allowedRunner.calls.first, [
          'query',
          'id=tg-1',
          '--all',
          '--json',
          '--limit',
          '0',
        ]);
        expect(allowedRunner.calls.last, allowedRunner.calls.first);
      },
    );

    test(
      'ProcessBdRunner discovers proxied mode once from its workspace',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'bd_guardrail_mode_',
        );
        addTearDown(() => root.delete(recursive: true));
        final beadsDir = Directory('${root.path}/.beads')..createSync();
        File('${beadsDir.path}/metadata.json').writeAsStringSync(
          jsonEncode({'dolt_mode': 'proxied-server', 'dolt_database': 'test'}),
        );
        final service = BdCliService(
          ProcessBdRunner(
            workspaceRoot: root.path,
            executable: 'must-not-run',
            environment: const {},
          ),
        );

        await expectLater(
          service.applyGraph(
            const GraphApplyPlan(commitMessage: 'wisp'),
            ephemeral: true,
          ),
          throwsA(isA<BdGuardrailRefused>()),
        );
      },
    );

    test(
      'missing, duplicate, and unreadable notes targets refuse before update',
      () async {
        final cases = <BdReply>[
          BdReply(stdout: _beads()),
          BdReply(
            stdout: _beads(const [Bead(id: 'tg-1'), Bead(id: 'tg-1')]),
          ),
          const BdReply(exitCode: 1, stderr: 'store unavailable'),
        ];
        for (final reply in cases) {
          final runner = FakeBdRunner(queuedReplies: [reply]);
          await expectLater(
            BdCliService(
              runner,
            ).update('tg-1', notes: 'replacement', allowNotesReplacement: true),
            throwsA(
              isA<BdGuardrailRefused>()
                  .having((error) => error.call, 'call', [
                    'bd',
                    'query',
                    'id=tg-1',
                    '--all',
                    '--json',
                    '--limit',
                    '0',
                  ])
                  .having(
                    (error) => error.remedy,
                    'remedy',
                    contains('bd query id=tg-1 --all --json --limit 0'),
                  ),
            ),
          );
          expect(runner.calls.map((call) => call.first), ['query']);
          expect(runner.calls.where((call) => call.first == 'update'), isEmpty);
        }
      },
    );

    test(
      'append remains append and never runs replacement preflight',
      () async {
        final runner = FakeBdRunner(
          queuedReplies: [
            const BdReply(stdout: '{"schema_version":1,"data":{}}'),
          ],
        );

        await BdCliService(
          runner,
        ).update('tg-1', appendNotes: 'more', verifyTextRoundTrip: false);

        expect(runner.calls, hasLength(1));
        expect(
          runner.calls.single,
          containsAllInOrder(['--append-notes', 'more']),
        );
        expect(runner.calls.single, isNot(contains('--notes')));
      },
    );

    test(
      'argv NUL refuses create, update, and close with exact diagnostics',
      () async {
        final runner = FakeBdRunner();
        final operations = <Future<void> Function()>[
          () async {
            await BdCliService(runner).create(title: 'bad\u0000title');
          },
          () => BdCliService(runner).update('tg-1', notes: 'bad\u0000notes'),
          () => BdCliService(runner).close('tg-1', reason: 'bad\u0000reason'),
        ];

        for (final operation in operations) {
          await expectLater(
            operation(),
            throwsA(
              isA<BeadTextRefused>()
                  .having((error) => error.call.first, 'binary', 'bd')
                  .having((error) => error.call, 'call', isNotEmpty)
                  .having((error) => error.offset, 'offset', 3)
                  .having(
                    (error) => error.remedy,
                    'remedy',
                    contains('Remove'),
                  ),
            ),
          );
        }
        expect(runner.calls, isEmpty);
      },
    );
  });
}

String _beads([List<Bead> beads = const []]) => jsonEncode({
  'schema_version': 1,
  'data': [for (final bead in beads) bead.toJson()],
});
