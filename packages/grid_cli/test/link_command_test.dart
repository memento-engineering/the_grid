import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_cli/grid_cli.dart';
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
    expect(state.exportCount, 1);
    expect(tg.exportCount, 1);
    expect(pow.exportCount, 1);
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
  type: IssueType.link,
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
  List<String> customTypes;
  final String createdId;
  final List<List<String>> calls = [];
  int exportCount = 0;

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
        return _envelope({
          'core_types': <String>[],
          'custom_types': customTypes,
        });
      case 'export':
        exportCount++;
        return BdResult(
          exitCode: 0,
          stdout: beads.map((bead) => jsonEncode(bead.toJson())).join('\n'),
          stderr: '',
        );
      case 'create':
        beads.add(
          _bead(
            createdId,
            type: IssueType.link,
            metadata: const {'rig': 'houston'},
          ),
        );
        return _envelope({'id': createdId});
      case 'update':
        final index = beads.indexWhere((bead) => bead.id == args[1]);
        final metadataIndex = args.indexOf('--metadata');
        final metadata =
            jsonDecode(args[metadataIndex + 1]) as Map<String, dynamic>;
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
}
