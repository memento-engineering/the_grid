import 'dart:io';

import 'package:grid_cli/src/hooks_resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory fixture;
  late Directory root;
  late Directory worktree;

  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('hooks-resolver-');
    root = await Directory(p.join(fixture.path, 'root')).create();
    worktree = await Directory(p.join(root.path, 'worktree')).create();
  });

  tearDown(() => fixture.delete(recursive: true));

  test('one matching event among multiple entries and manifests', () async {
    final first = await _manifest(fixture, 'first.yaml', '''
hooks:
  - event: pre-commit
    id: format
    run: dart format
    select: "*.dart"
    mode: fix
    timeout_ms: 1500
  - event: post-commit
    id: announce
    run: notify
    select: "*"
    mode: notify
    timeout_ms: 500
''');
    final second = await _manifest(fixture, 'second.yaml', '''
hooks:
  - event: pre-push
    id: test
    run: dart test
    select: test/**
    mode: gate
    timeout_ms: 30000
''');
    final response = await _resolver(root, [
      HookManifest(source: 'formatter', path: first.path),
      HookManifest(source: 'tests', path: second.path),
    ]).resolve(event: 'pre-commit', worktree: worktree.path);

    expect(response.toJson(), {
      'event': 'pre-commit',
      'worktree': worktree.path,
      'substation': 'alpha',
      'contributions': [
        {
          'id': 'format',
          'source': 'formatter',
          'run': 'dart format',
          'select': '*.dart',
          'mode': 'fix',
          'timeout_ms': 1500,
        },
      ],
    });
  });

  test('declaration order is preserved across manifests', () async {
    final first = await _manifest(fixture, 'first.yaml', _hooks('one', 'two'));
    final second = await _manifest(fixture, 'second.yaml', _hooks('three'));
    final response = await _resolver(root, [
      HookManifest(source: 'a', path: first.path),
      HookManifest(source: 'b', path: second.path),
    ]).resolve(event: 'pre-commit', worktree: worktree.path);

    expect(response.contributions.map((contribution) => contribution.id), [
      'one',
      'two',
      'three',
    ]);
  });

  test('empty and missing hooks produce no contributions', () async {
    final empty = await _manifest(fixture, 'empty.yaml', 'hooks: []\n');
    final missing = await _manifest(fixture, 'missing.yaml', 'name: asset\n');
    final response = await _resolver(root, [
      HookManifest(source: 'empty', path: empty.path),
      HookManifest(source: 'missing', path: missing.path),
    ]).resolve(event: 'pre-commit', worktree: worktree.path);

    expect(response.contributions, isEmpty);
  });

  test('outside path is refused', () async {
    final outside = await Directory(p.join(fixture.path, 'outside')).create();
    await expectLater(
      _resolver(root).resolve(event: 'pre-commit', worktree: outside.path),
      _throwsStatus(404),
    );
  });

  test(
    'symlink path whose target is strictly under root is accepted',
    () async {
      final link = Link(p.join(fixture.path, 'linked-worktree'));
      await link.create(worktree.path);

      final response = await _resolver(
        root,
      ).resolve(event: 'pre-commit', worktree: link.path);
      expect(response.substation, 'alpha');
      expect(response.worktree, link.path);
    },
  );

  test('relative and blank worktrees are refused', () async {
    for (final value in ['', '  ', 'relative/worktree']) {
      await expectLater(
        _resolver(root).resolve(event: 'pre-commit', worktree: value),
        _throwsStatus(400),
      );
    }
  });

  test('blank events are refused', () async {
    await expectLater(
      _resolver(root).resolve(event: '  ', worktree: worktree.path),
      _throwsStatus(400),
    );
  });

  test('ambiguous nested configured roots are refused', () async {
    final nested = await Directory(p.join(root.path, 'nested')).create();
    final nestedWorktree = await Directory(
      p.join(nested.path, 'work'),
    ).create();
    final resolver = HooksResolver(
      substations: [
        HookSubstation(substation: 'outer', root: root.path),
        HookSubstation(substation: 'inner', root: nested.path),
      ],
    );

    await expectLater(
      resolver.resolve(event: 'pre-commit', worktree: nestedWorktree.path),
      _throwsStatus(500),
    );
  });

  test('malformed entry fields mode and timeout produce status 500', () async {
    final documents = <String>[
      'hooks: [not-a-map]',
      _hook(id: ''),
      _hook(run: ''),
      _hook(select: ''),
      _hook(mode: 'unknown'),
      _hook(timeout: 0),
      _hook(timeout: '"100"'),
    ];
    for (var index = 0; index < documents.length; index++) {
      final manifest = await _manifest(
        fixture,
        'malformed-$index.yaml',
        documents[index],
      );
      await expectLater(
        _resolver(root, [
          HookManifest(source: 'bad', path: manifest.path),
        ]).resolve(event: 'pre-commit', worktree: worktree.path),
        _throwsStatus(500),
      );
    }
  });
}

HooksResolver _resolver(
  Directory root, [
  List<HookManifest> manifests = const <HookManifest>[],
]) => HooksResolver(
  substations: [
    HookSubstation(substation: 'alpha', root: root.path, manifests: manifests),
  ],
);

Future<File> _manifest(Directory fixture, String name, String contents) =>
    File(p.join(fixture.path, name)).writeAsString(contents);

String _hooks(String first, [String? second]) =>
    '''
hooks:
  - event: pre-commit
    id: "$first"
    run: "run hook"
    select: "*"
    mode: gate
    timeout_ms: 100
${second == null ? '' : '''  - event: pre-commit
    id: "$second"
    run: "run hook"
    select: "*"
    mode: gate
    timeout_ms: 100
'''}''';

String _hook({
  String id = 'hook',
  String run = 'run hook',
  String select = '*',
  String mode = 'gate',
  Object timeout = 100,
}) =>
    '''
hooks:
  - event: pre-commit
    id: "$id"
    run: "$run"
    select: "$select"
    mode: $mode
    timeout_ms: $timeout
''';

Matcher _throwsStatus(int status) => throwsA(
  isA<HooksResolutionException>().having(
    (error) => error.statusCode,
    'statusCode',
    status,
  ),
);
