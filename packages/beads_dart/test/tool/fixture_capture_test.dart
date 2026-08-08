import 'dart:io';

import 'package:test/test.dart';

import '../../tool/capture_upstream_fixtures.dart' as capture_tool;
import '../support/fake_bd_runner.dart';

File repoFile(String path) => File('../../$path');

BdReply ok(String body) => BdReply(stdout: body);

BdReply error(String body) => BdReply(exitCode: 1, stdout: body);

List<BdReply> successQueue() => [
  ok('list\n'),
  ok('statuses\n'),
  ok('types\n'),
  error('{"error":true}\n'),
  ok('session\n'),
  ok('message\n'),
  ok('molecule\n'),
  ok('ready\n'),
  ok('{"revision":1}\n'),
  ok('${List.generate(30, (i) => '{"id":$i}').join('\n')}\n'),
];

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fixture_capture_test.');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('A57 records ref naming while ADR-0001 remains historical', () {
    final register = repoFile(
      'docs/adr/ADR-0000-ai-decision-register.md',
    ).readAsStringSync();
    final ratified = repoFile(
      'docs/adr/ADR-0001-technical-foundations.md',
    ).readAsStringSync();
    expect(register, contains('## A57 (2026-08-08)'));
    expect(register, contains('fixtures/upstream/<date>-bd-<ref>/'));
    expect(register, contains('D-BD1'));
    expect(register, contains('40-character lowercase hexadecimal commit SHA'));
    expect(register, contains('**Status:** Pending'));
    expect(ratified, contains('fixtures/upstream/<date>-bd-<version>/'));
    expect(ratified, isNot(contains('<date>-bd-<ref>')));
  });

  test('captures exact bytes, argv, provenance, and 25 export lines', () async {
    final grid = FakeBdRunner(
      queuedReplies: [
        ok('list\n'),
        ok('statuses\n'),
        ok('types\n'),
        error('{"error":true}\n'),
      ],
    );
    final export = List.generate(30, (i) => '{"id":$i}').join('\n');
    final sample = FakeBdRunner(
      queuedReplies: [
        ok('session\n'),
        ok('message\n'),
        ok('molecule\n'),
        ok('ready\n'),
        ok('{"revision":1}\n'),
        ok('$export\n'),
      ],
    );
    final dir =
        await capture_tool.FixtureCapture(
          gridRunner: grid,
          sampleRunner: sample,
        ).capture(
          ref: 'main',
          sha: 'a' * 40,
          date: DateTime.utc(2026, 8, 8),
          executable: '/tmp/bd',
          sampleId: 'fx-show',
          outputRoot: temp,
        );
    expect(grid.calls, [
      ['list', '--json', '--all', '--limit', '0'],
      ['statuses', '--json'],
      ['types', '--json'],
      ['dep', 'list', 'tg-nonexistent', '--json'],
    ]);
    expect(sample.calls[4], ['show', 'fx-show', '--json']);
    expect(
      File('${dir.path}/fx-show-sample.json').readAsStringSync(),
      '{"revision":1}\n',
    );
    expect(
      File('${dir.path}/fx-export-sample.jsonl').readAsLinesSync(),
      hasLength(25),
    );
    final readme = File('${dir.path}/README.md').readAsStringSync();
    expect(
      readme,
      allOf(
        contains('`main`'),
        contains('`${'a' * 40}`'),
        contains('`/tmp/bd`'),
        contains('BD_JSON_ENVELOPE=1'),
      ),
    );
  });

  test('rejects malformed ref and SHA before runner calls', () async {
    final grid = FakeBdRunner(), sample = FakeBdRunner();
    final capture = capture_tool.FixtureCapture(
      gridRunner: grid,
      sampleRunner: sample,
    );
    await expectLater(
      () => capture.capture(
        ref: '../main',
        sha: 'a' * 40,
        date: DateTime.utc(2026),
        executable: 'bd',
        sampleId: 'fx',
        outputRoot: temp,
      ),
      throwsFormatException,
    );
    await expectLater(
      () => capture.capture(
        ref: 'main',
        sha: 'A' * 40,
        date: DateTime.utc(2026),
        executable: 'bd',
        sampleId: 'fx',
        outputRoot: temp,
      ),
      throwsFormatException,
    );
    expect(grid.calls, isEmpty);
    expect(sample.calls, isEmpty);
  });

  test('refuses an existing target without mutation or runner calls', () async {
    final target = Directory('${temp.path}/2026-08-08-bd-main')..createSync();
    final sentinel = File('${target.path}/sentinel')..writeAsStringSync('keep');
    final grid = FakeBdRunner(), sample = FakeBdRunner();
    await expectLater(
      () => capture_tool.FixtureCapture(gridRunner: grid, sampleRunner: sample)
          .capture(
            ref: 'main',
            sha: 'a' * 40,
            date: DateTime.utc(2026, 8, 8),
            executable: 'bd',
            sampleId: 'fx',
            outputRoot: temp,
          ),
      throwsStateError,
    );
    expect(sentinel.readAsStringSync(), 'keep');
    expect([...grid.calls, ...sample.calls], isEmpty);
  });

  test(
    'unexpected failure removes staging and reports command detail',
    () async {
      final grid = FakeBdRunner(
        queuedReplies: [const BdReply(exitCode: 7, stderr: 'boom')],
      );
      final capture = capture_tool.FixtureCapture(
        gridRunner: grid,
        sampleRunner: FakeBdRunner(),
      );
      await expectLater(
        () => capture.capture(
          ref: 'main',
          sha: 'a' * 40,
          date: DateTime.utc(2026, 8, 8),
          executable: 'bd',
          sampleId: 'fx',
          outputRoot: temp,
        ),
        throwsA(
          allOf(
            isA<StateError>(),
            predicate(
              (e) =>
                  '$e'.contains('list --json --all --limit 0') &&
                  '$e'.contains('7') &&
                  '$e'.contains('boom'),
            ),
          ),
        ),
      );
      expect(
        Directory('${temp.path}/2026-08-08-bd-main').existsSync(),
        isFalse,
      );
      expect(
        Directory('${temp.path}/2026-08-08-bd-main.staging').existsSync(),
        isFalse,
      );
    },
  );

  test('error fixture requires nonzero stdout-only result', () async {
    Future<void> rejects(BdReply reply) async {
      final grid = FakeBdRunner(
        queuedReplies: [ok('list'), ok('statuses'), ok('types'), reply],
      );
      await expectLater(
        () =>
            capture_tool.FixtureCapture(
              gridRunner: grid,
              sampleRunner: FakeBdRunner(),
            ).capture(
              ref: 'v1.2.0',
              sha: 'b' * 40,
              date: DateTime.utc(2026, 8, 9),
              executable: 'bd',
              sampleId: 'fx',
              outputRoot: temp,
            ),
        throwsStateError,
      );
    }

    await rejects(ok('{"error":true}'));
    await rejects(const BdReply(exitCode: 1, stdout: ''));
    await rejects(const BdReply(exitCode: 1, stdout: '{}', stderr: 'noise'));
  });
}
