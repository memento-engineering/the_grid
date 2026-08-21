import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_engine/grid_engine.dart' show GridIssueTypes;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late GridStateStore stateStore;
  late List<LinkEndpointStore> endpoints;
  late _FakeStore state;
  late _FakeStore tg;
  late _FakeStore pow;
  late Map<String, _FakeStore> stores;
  late BdCliService Function(BeadsWorkspace) factory;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('grid-link-test-');
    stateStore = GridStateStore.forGridRoot(temp.path);
    Directory(stateStore.beadsDir).createSync(recursive: true);
    final tgRoot = Directory('${temp.path}/the_grid')
      ..createSync(recursive: true);
    final powRoot = Directory('${temp.path}/power_station')
      ..createSync(recursive: true);
    Directory('${tgRoot.path}/.beads').createSync();
    Directory('${powRoot.path}/.beads').createSync();
    endpoints = [
      LinkEndpointStore(
        prefix: 'tg',
        store: SubstationWorkStore(root: tgRoot.path),
      ),
      LinkEndpointStore(
        prefix: 'pow',
        store: SubstationWorkStore(root: powRoot.path),
      ),
    ];
    state = _FakeStore(
      [],
      customTypes: const ['link'],
      createdId: 'houston-link2',
    );
    tg = _FakeStore([
      _bead('tg-q9k', status: BeadStatus.open),
    ], customTypes: const []);
    pow = _FakeStore([
      _bead('pow-60g', status: BeadStatus.closed),
    ], customTypes: const []);
    stores = {stateStore.runtimeDir: state, tgRoot.path: tg, powRoot.path: pow};
    factory = (workspace) => BdCliService(stores[workspace.root]!);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('--reason-file preserves text and collisions precede probing', () async {
    const fixture =
        "literal `cmd` and \$(cmd) and \$VAR and 'single'\n  trailing  ";
    final reasonFile = File('${temp.path}/reason.txt');
    await reasonFile.writeAsString(fixture, encoding: utf8, flush: true);
    expect(
      await runLink(
        arguments: _linkArgs([
          'tg-q9k',
          '--blocked-by',
          'pow-60g',
          '--grid-root',
          temp.path,
          '--prefix',
          'tg',
          '--prefix',
          'pow',
          '--actor',
          'specify',
          '--reason-file',
          reasonFile.path,
        ]),
        stateStorePrefix: 'houston',
        endpoints: endpoints,
        bdFactory: factory,
      ),
      0,
    );
    final update = state.calls.where((call) => call.first == 'update').single;
    expect(update, contains('grid.link.reason=$fixture'));

    final calls = state.calls.length;
    expect(
      await runLink(
        arguments: _linkArgs([
          'tg-q9k',
          '--blocked-by',
          'pow-60g',
          '--grid-root',
          temp.path,
          '--prefix',
          'tg',
          '--prefix',
          'pow',
          '--actor',
          'specify',
          '--reason',
          fixture,
          '--reason-file',
          reasonFile.path,
        ]),
        stateStorePrefix: 'houston',
        endpoints: endpoints,
        bdFactory: factory,
      ),
      64,
    );
    expect(state.calls, hasLength(calls));
  });

  test('mint then list reports metadata and endpoint statuses', () async {
    final minted = <String>[];
    final code = await runLink(
      arguments: _linkArgs([
        'tg-q9k',
        '--blocked-by',
        'pow-60g',
        '--grid-root',
        temp.path,
        '--prefix',
        'houston',
        '--prefix',
        'tg',
        '--prefix',
        'pow',
        '--actor',
        'specify',
        '--reason',
        'waits on power',
      ]),
      stateStorePrefix: 'houston',
      endpoints: endpoints,
      bdFactory: factory,
      out: minted.add,
    );
    expect(code, 0);
    expect(minted, ['houston-link2']);
    expect(
      state.beads.single.metadata,
      containsPair('grid.link.from', 'tg-q9k'),
    );
    expect(
      state.beads.single.metadata,
      containsPair('grid.link.to', 'pow-60g'),
    );
    expect(
      state.calls.where((call) => call.isNotEmpty && call.first == 'update'),
      everyElement(isNot(contains('--metadata'))),
    );

    state.beads.add(_link('houston-link1', 'tg-missing', 'pow-missing'));
    final lines = <String>[];
    final listed = await runLink(
      arguments: _linkArgs(['ls', '--grid-root', temp.path]),
      stateStorePrefix: 'houston',
      endpoints: endpoints,
      bdFactory: factory,
      out: lines.add,
    );
    expect(listed, 0);
    expect(lines, [
      'houston-link1 tg-missing [unobserved] --blocked-by '
          'pow-missing [unobserved]',
      'houston-link2 tg-q9k [open] --blocked-by pow-60g [closed]',
    ]);
    for (final store in [state, tg, pow]) {
      expect(store.calls.where((call) => call.first == 'export'), isEmpty);
      expect(
        store.calls.where((call) => call.first == 'list'),
        everyElement(
          predicate<List<String>>(
            (call) =>
                call.length == 8 &&
                call[1] == '-t' &&
                call[3] == '--status' &&
                call[5] == '--json' &&
                call[6] == '--limit' &&
                call[7] == '0',
          ),
        ),
      );
    }
  });

  test(
    'unlink by pair closes through the writer and removes listing',
    () async {
      state.beads.add(_link('houston-link1', 'tg-q9k', 'pow-60g'));
      final code = await runUnlink(
        arguments: _unlinkArgs([
          'tg-q9k',
          'pow-60g',
          '--grid-root',
          temp.path,
          '--prefix',
          'houston',
          '--prefix',
          'tg',
          '--prefix',
          'pow',
          '--actor',
          'operator',
          '--reason',
          'landed',
        ]),
        stateStorePrefix: 'houston',
        endpoints: endpoints,
        bdFactory: factory,
      );
      expect(code, 0);
      expect(state.beads.single.status, BeadStatus.closed);
      final close = state.calls.where((call) => call.first == 'close').single;
      expect(close, containsAllInOrder(['--actor', 'grid-controller']));
      expect(
        close,
        containsAllInOrder(['--reason', 'landed (unlink actor: operator)']),
      );
    },
  );

  test(
    'unlink by id refuses wrong type and closes an owned open link',
    () async {
      state.beads.add(_bead('houston-task1'));
      final before = state.mutationCalls.length;
      expect(
        await runUnlink(
          arguments: _unlinkArgs([
            'houston-task1',
            '--grid-root',
            temp.path,
            '--prefix',
            'houston',
            '--actor',
            'operator',
            '--reason',
            'done',
          ]),
          stateStorePrefix: 'houston',
          endpoints: endpoints,
          bdFactory: factory,
        ),
        1,
      );
      expect(state.mutationCalls, hasLength(before));

      state.beads.add(_link('houston-link1', 'tg-q9k', 'pow-60g'));
      expect(
        await runUnlink(
          arguments: _unlinkArgs([
            'houston-link1',
            '--grid-root',
            temp.path,
            '--prefix',
            'houston',
            '--actor',
            'operator',
            '--reason',
            'done',
          ]),
          stateStorePrefix: 'houston',
          endpoints: endpoints,
          bdFactory: factory,
        ),
        0,
      );
    },
  );

  test('link and unlink accept configured hyphenated prefixes', () async {
    final inferRoot = Directory('${temp.path}/swift_infer')
      ..createSync(recursive: true);
    final trainRoot = Directory('${temp.path}/swift_train')
      ..createSync(recursive: true);
    Directory('${inferRoot.path}/.beads').createSync();
    Directory('${trainRoot.path}/.beads').createSync();
    final infer = _FakeStore([_bead('swift-infer-097')], customTypes: const []);
    final train = _FakeStore([_bead('swift-train-042')], customTypes: const []);
    final hyphenatedEndpoints = [
      LinkEndpointStore(
        prefix: 'swift-infer',
        store: SubstationWorkStore(root: inferRoot.path),
      ),
      LinkEndpointStore(
        prefix: 'swift-train',
        store: SubstationWorkStore(root: trainRoot.path),
      ),
    ];
    stores[inferRoot.path] = infer;
    stores[trainRoot.path] = train;
    state.createdIdOverride = 'tranquility-state-link1';

    expect(
      await runLink(
        arguments: _linkArgs([
          'swift-infer-097',
          '--blocked-by',
          'swift-train-042',
          '--grid-root',
          temp.path,
          '--prefix',
          'swift-infer',
          '--prefix',
          'swift-train',
          '--actor',
          'specify',
          '--reason',
          'waits',
        ]),
        stateStorePrefix: 'tranquility-state',
        endpoints: hyphenatedEndpoints,
        bdFactory: factory,
      ),
      0,
    );
    expect(
      await runUnlink(
        arguments: _unlinkArgs([
          'tranquility-state-link1',
          '--grid-root',
          temp.path,
          '--prefix',
          'tranquility-state',
          '--actor',
          'operator',
          '--reason',
          'done',
        ]),
        stateStorePrefix: 'tranquility-state',
        endpoints: hyphenatedEndpoints,
        bdFactory: factory,
      ),
      0,
    );
  });

  test(
    'unrostered and unarmed prefixes refuse before writes or reads',
    () async {
      for (final target in ['other-1', 'pow-60g']) {
        final before = state.calls.length;
        final armed = target.startsWith('other') ? ['tg', 'other'] : ['tg'];
        expect(
          await runLink(
            arguments: _linkArgs([
              'tg-q9k',
              '--blocked-by',
              target,
              '--grid-root',
              temp.path,
              for (final prefix in armed) ...['--prefix', prefix],
              '--actor',
              'specify',
              '--reason',
              'waits',
            ]),
            stateStorePrefix: 'houston',
            endpoints: endpoints,
            bdFactory: factory,
          ),
          64,
        );
        expect(state.calls, hasLength(before));
      }
    },
  );

  test('missing link custom type refuses before mutations', () async {
    state.customTypes = const [];
    final before = state.mutationCalls.length;
    expect(
      await runLink(
        arguments: _linkArgs([
          'tg-q9k',
          '--blocked-by',
          'pow-60g',
          '--grid-root',
          temp.path,
          '--prefix',
          'tg',
          '--prefix',
          'pow',
          '--actor',
          'specify',
          '--reason',
          'waits',
        ]),
        stateStorePrefix: 'houston',
        endpoints: endpoints,
        bdFactory: factory,
      ),
      1,
    );
    expect(state.mutationCalls, hasLength(before));
  });

  test('a store with no custom types lists zero links, not an error', () async {
    // The 0.5.0-rc.1 regression pair, measured against space_station's state
    // store on 2026-08-05: (1) `bd types --json` omits an empty group, so a
    // store with no custom types has NO `custom_types` key and _probeReader
    // threw BdParseException on it; (2) when discovery did succeed, the
    // scoped `list -t link` read that replaced the whole-store export is
    // REFUSED by bd for an unregistered type ("invalid issue type"), where
    // the export had simply found nothing. No link type ⇒ no link beads ⇒ an
    // empty listing, exit 0.
    state.customTypes = const [];
    final lines = <String>[];
    final errors = <String>[];
    expect(
      await runLink(
        arguments: _linkArgs(['ls', '--grid-root', temp.path]),
        stateStorePrefix: 'houston',
        endpoints: endpoints,
        bdFactory: factory,
        out: lines.add,
        err: errors.add,
      ),
      0,
    );
    expect(lines, isEmpty);
    expect(errors, isEmpty);
    // The refusable scoped read must never be issued against the store.
    expect(
      state.calls.where((call) => call.first == 'list' && call[2] == 'link'),
      isEmpty,
    );
  });

  test('link discovery accepts string and name-map type entries', () async {
    state.customTypes = <Object>[
      'session',
      {'name': 'link'},
    ];
    final lines = <String>[];
    expect(
      await runLink(
        arguments: _linkArgs(['ls', '--grid-root', temp.path]),
        stateStorePrefix: 'houston',
        endpoints: endpoints,
        bdFactory: factory,
        out: lines.add,
      ),
      0,
    );
    expect(lines, isEmpty);
    expect(
      state.calls.where((call) => call.first == 'list' && call[2] == 'link'),
      hasLength(1),
    );
  });

  test(
    'unlink by pair on a store without the link type finds nothing',
    () async {
      state.customTypes = const [];
      final errors = <String>[];
      expect(
        await runUnlink(
          arguments: _unlinkArgs([
            'tg-q9k',
            'pow-60g',
            '--grid-root',
            temp.path,
            '--prefix',
            'houston',
            '--prefix',
            'tg',
            '--prefix',
            'pow',
            '--actor',
            'operator',
            '--reason',
            'landed',
          ]),
          stateStorePrefix: 'houston',
          endpoints: endpoints,
          bdFactory: factory,
          err: errors.add,
        ),
        1,
      );
      // A clean "found 0" refusal — not a BdParseException, not a bd type
      // refusal from a scoped read the store cannot answer.
      expect(errors.single, contains('found 0'));
      expect(
        state.calls.where((call) => call.first == 'list' && call[2] == 'link'),
        isEmpty,
      );
      expect(state.mutationCalls, isEmpty);
    },
  );

  test('malformed type discovery fails without mutations or export', () async {
    state.malformedTypes = true;
    final errors = <String>[];
    final before = state.mutationCalls.length;
    expect(
      await runLink(
        arguments: _linkArgs(['ls', '--grid-root', temp.path]),
        stateStorePrefix: 'houston',
        endpoints: endpoints,
        bdFactory: factory,
        err: errors.add,
      ),
      1,
    );
    expect(errors.single, contains('type discovery'));
    expect(state.mutationCalls, hasLength(before));
    expect(state.calls.where((call) => call.first == 'export'), isEmpty);
  });

  test('command source has no raw mutation path', () {
    final source = File('lib/src/link_command.dart').readAsStringSync();
    expect(source, isNot(contains('.create(')));
    expect(source, isNot(contains('.update(')));
    expect(
      RegExp(r'\.close\(').allMatches(source).length,
      RegExp(r'writer\.close\(').allMatches(source).length,
    );
    expect(source, contains('writer.createLink('));
  });
}

ArgResults _linkArgs(List<String> args) => _parser(blockedBy: true).parse(args);

ArgResults _unlinkArgs(List<String> args) => _parser().parse(args);

ArgParser _parser({bool blockedBy = false}) {
  final parser = ArgParser()
    ..addOption('grid-root')
    ..addMultiOption('prefix')
    ..addOption('reason')
    ..addOption('reason-file')
    ..addOption('actor');
  if (blockedBy) parser.addOption('blocked-by');
  return parser;
}

Bead _bead(
  String id, {
  BeadStatus status = BeadStatus.open,
  IssueType type = IssueType.task,
  Map<String, dynamic> metadata = const {},
}) => Bead(
  id: id,
  title: id,
  issueType: type,
  status: status,
  metadata: metadata,
);

Bead _link(String id, String from, String to) => _bead(
  id,
  type: GridIssueTypes.link,
  metadata: {
    'rig': 'houston',
    'grid.link.from': from,
    'grid.link.to': to,
    'grid.link.type': 'blocks',
  },
);

class _FakeStore implements BdRunner {
  _FakeStore(
    this.beads, {
    required this.customTypes,
    this.createdId = 'unused',
  });

  final List<Bead> beads;
  List<Object> customTypes;
  final String createdId;
  String? createdIdOverride;
  final List<List<String>> calls = [];
  bool malformedTypes = false;

  List<List<String>> get mutationCalls => calls
      .where((call) => const {'create', 'update', 'close'}.contains(call.first))
      .toList();

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    switch (args.first) {
      case 'types':
        if (malformedTypes) {
          return _envelope({'core_types': 'task', 'custom_types': customTypes});
        }
        // Real `bd types --json` OMITS an empty group — a store with no
        // custom types carries no `custom_types` key at all. The fake mirrors
        // that shape so every test runs against what bd actually emits.
        return _envelope({
          'core_types': const ['task'],
          if (customTypes.isNotEmpty) 'custom_types': customTypes,
        });
      case 'export':
        return BdResult(
          exitCode: 1,
          stdout: '',
          stderr: 'Error: export is not supported in proxied-server mode',
        );
      case 'list':
        final type = args[2];
        final status = args[4];
        return _listEnvelope(
          beads
              .where(
                (bead) =>
                    bead.issueType.wire == type && bead.status.wire == status,
              )
              .map((bead) => bead.toJson())
              .toList(),
        );
      case 'query':
        final expression = args[1];
        if (!expression.startsWith('id=')) {
          throw StateError('unexpected bd query: $args');
        }
        final id = expression.substring('id='.length);
        return _listEnvelope(
          beads
              .where((bead) => bead.id == id)
              .map((bead) => bead.toJson())
              .toList(),
        );
      case 'create':
        final effectiveCreatedId = createdIdOverride ?? createdId;
        beads.add(
          _bead(
            effectiveCreatedId,
            type: GridIssueTypes.link,
            metadata: const {'rig': 'houston'},
          ),
        );
        return _envelope({'id': effectiveCreatedId});
      case 'update':
        final index = beads.indexWhere((bead) => bead.id == args[1]);
        final metadata = <String, dynamic>{};
        for (var i = 0; i < args.length - 1; i++) {
          if (args[i] != '--set-metadata') continue;
          final assignment = args[i + 1];
          final separator = assignment.indexOf('=');
          if (separator < 0) continue;
          metadata[assignment.substring(0, separator)] = assignment.substring(
            separator + 1,
          );
        }
        beads[index] = beads[index].copyWith(
          metadata: {...beads[index].metadata, ...metadata},
        );
        return _envelope({'id': args[1]});
      case 'close':
        final index = beads.indexWhere((bead) => bead.id == args[1]);
        beads[index] = beads[index].copyWith(status: BeadStatus.closed);
        return _envelope({'id': args[1]});
      default:
        throw StateError('unexpected bd call: $args');
    }
  }

  BdResult _envelope(Map<String, dynamic> data) => BdResult(
    exitCode: 0,
    stdout: jsonEncode({'schema_version': 1, 'data': data}),
    stderr: '',
  );

  BdResult _listEnvelope(List<Map<String, dynamic>> data) => BdResult(
    exitCode: 0,
    stdout: jsonEncode({'schema_version': 1, 'data': data}),
    stderr: '',
  );
}
