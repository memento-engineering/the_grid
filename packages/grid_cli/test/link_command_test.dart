// tg-xh5d (`the_grid#the-grid-is-a-beads-controller`): `link` is SUGAR over
// `bd dep add <from> external:<project>:<capability>` — it labels the target
// `export:<target>`, writes the row, and mints NOTHING.
//
// tg-6t0h: `link migrate` is the ONE PASS that converts every authored link
// bead into that row and closes the receipt, and `unlink` is GONE with the
// bead it used to close.
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
        name: 'the_grid',
        prefix: 'tg',
        store: SubstationWorkStore(root: tgRoot.path),
      ),
      LinkEndpointStore(
        name: 'power_station',
        prefix: 'pow',
        store: SubstationWorkStore(root: powRoot.path),
      ),
    ];
    state = _FakeStore([], customTypes: const ['link']);
    tg = _FakeStore(
      [_bead('tg-q9k', status: BeadStatus.open)],
      customTypes: const [],
      externalProjects: 'power_station=../power_station',
    );
    pow = _FakeStore([
      _bead('pow-60g', status: BeadStatus.open),
    ], customTypes: const []);
    stores = {stateStore.runtimeDir: state, tgRoot.path: tg, powRoot.path: pow};
    factory = (workspace) => BdCliService(stores[workspace.root]!);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('link labels the target and writes ONE external dep row, minting '
      'nothing anywhere', () async {
    final written = <String>[];
    expect(
      await runLink(
        arguments: _linkArgs(['tg-q9k', '--blocked-by', 'pow-60g']),
        endpoints: endpoints,
        bdFactory: factory,
        out: written.add,
      ),
      0,
    );
    expect(
      written.single,
      'tg-q9k --blocked-by external:power_station:pow-60g',
    );
    expect(pow.calls.where((call) => call.first == 'label').single, [
      'label',
      'add',
      'pow-60g',
      'export:pow-60g',
      '--json',
      '--actor',
      'grid-controller',
    ]);
    expect(tg.calls.where((call) => call.first == 'dep').single, [
      'dep',
      'add',
      'tg-q9k',
      'external:power_station:pow-60g',
      '--type',
      'blocks',
      '--json',
      '--actor',
      'grid-controller',
    ]);
    for (final store in [state, tg, pow]) {
      expect(
        store.calls.where((call) => call.first == 'create'),
        isEmpty,
        reason: 'the link verb mints no bead',
      );
    }
    expect(state.calls, isEmpty, reason: 'the state store is never touched');
  });

  test(
    'a target that already exports its capability is not re-labelled',
    () async {
      pow.beads[0] = pow.beads[0].copyWith(labels: const ['export:pow-60g']);
      expect(
        await runLink(
          arguments: _linkArgs(['tg-q9k', '--blocked-by', 'pow-60g']),
          endpoints: endpoints,
          bdFactory: factory,
          out: (_) {},
        ),
        0,
      );
      expect(pow.calls.where((call) => call.first == 'label'), isEmpty);
      expect(tg.calls.where((call) => call.first == 'dep'), hasLength(1));
    },
  );

  test(
    'a SAME-store blocker is refused — bd dep add already blocks it',
    () async {
      tg.beads.add(_bead('tg-other'));
      final errors = <String>[];
      expect(
        await runLink(
          arguments: _linkArgs(['tg-q9k', '--blocked-by', 'tg-other']),
          endpoints: endpoints,
          bdFactory: factory,
          err: errors.add,
        ),
        64,
      );
      expect(errors.single, contains('bd dep add tg-q9k tg-other'));
      expect(tg.calls, isEmpty);
      expect(pow.calls, isEmpty);
    },
  );

  test('a bd store whose external_projects omits the target project is '
      'reported LOUDLY, and the row is still wired', () async {
    tg.externalProjects = '';
    final errors = <String>[];
    expect(
      await runLink(
        arguments: _linkArgs(['tg-q9k', '--blocked-by', 'pow-60g']),
        endpoints: endpoints,
        bdFactory: factory,
        out: (_) {},
        err: errors.add,
      ),
      0,
    );
    expect(errors.single, contains('external_projects'));
    expect(errors.single, contains('power_station'));
    expect(tg.calls.where((call) => call.first == 'dep'), hasLength(1));
  });

  test('an endpoint outside the configured roster refuses before any store '
      'call', () async {
    final errors = <String>[];
    expect(
      await runLink(
        arguments: _linkArgs(['tg-q9k', '--blocked-by', 'other-1']),
        endpoints: endpoints,
        bdFactory: factory,
        err: errors.add,
      ),
      64,
    );
    expect(errors.single, contains('other-1'));
    expect(tg.calls, isEmpty);
    expect(pow.calls, isEmpty);
  });

  test('an unobservable target refuses before the dependency row', () async {
    final errors = <String>[];
    expect(
      await runLink(
        arguments: _linkArgs(['tg-q9k', '--blocked-by', 'pow-999']),
        endpoints: endpoints,
        bdFactory: factory,
        err: errors.add,
      ),
      1,
    );
    expect(errors.single, contains('pow-999'));
    expect(pow.calls.where((call) => call.first == 'label'), isEmpty);
    expect(tg.calls.where((call) => call.first == 'dep'), isEmpty);
  });

  test(
    '--blocked-by is required, and --json is accepted only by link ls',
    () async {
      final errors = <String>[];
      expect(
        await runLink(
          arguments: _linkArgs(['tg-q9k']),
          endpoints: endpoints,
          bdFactory: factory,
          err: errors.add,
        ),
        64,
      );
      expect(
        await runLink(
          arguments: _linkArgs(['tg-q9k', '--blocked-by', 'pow-60g', '--json']),
          endpoints: endpoints,
          bdFactory: factory,
          err: errors.add,
        ),
        64,
      );
      expect(errors, hasLength(2));
      expect(tg.calls, isEmpty);
    },
  );

  test('link ls lists the external rows with their edge state, human and '
      'JSON', () async {
    tg.dependencies.addAll(const [
      BeadDependency(
        issueId: 'tg-q9k',
        dependsOnId: 'external:power_station:pow-60g',
      ),
      BeadDependency(
        issueId: 'tg-q9k',
        dependsOnId: 'external:dashboard:dash-1',
      ),
      BeadDependency(issueId: 'tg-q9k', dependsOnId: 'tg-local'),
    ]);
    final human = <String>[];
    expect(
      await runLink(
        arguments: _linkArgs(['ls']),
        endpoints: endpoints,
        bdFactory: factory,
        out: human.add,
      ),
      0,
    );
    expect(human, hasLength(2));
    expect(human.first, contains('external:dashboard:dash-1'));
    expect(human.first, contains('UNARMED'));
    expect(human.last, contains('external:power_station:pow-60g'));
    expect(human.last, contains('PENDING'));

    pow.beads[0] = pow.beads[0].copyWith(
      status: BeadStatus.closed,
      labels: const ['export:pow-60g', 'provides:pow-60g'],
    );
    final json = <String>[];
    expect(
      await runLink(
        arguments: _linkArgs(['ls', '--json']),
        endpoints: endpoints,
        bdFactory: factory,
        out: json.add,
      ),
      0,
    );
    final rows = (jsonDecode(json.single) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final shipped = rows.singleWhere(
      (row) => row['to'] == 'external:power_station:pow-60g',
    );
    expect(shipped['from'], 'tg-q9k');
    expect(shipped['project'], 'power_station');
    expect(shipped['edgeState'], contains('SHIPPED'));
  });

  // tg-xh5d RULING 2026-09-13 (2): `link ls` lists the external rows from the
  // SAME read the frontier takes them from. bd's RESOLVING reads answer with
  // the issue record a dependency points at, so a listing built on `bd dep
  // list` would print an empty roster over a store full of edges.
  test('link ls lists from the RECORD surface, and refuses when it stops '
      'carrying rows', () async {
    tg.dependencies.add(
      const BeadDependency(
        issueId: 'tg-q9k',
        dependsOnId: 'external:power_station:pow-60g',
      ),
    );

    final human = <String>[];
    expect(
      await runLink(
        arguments: _linkArgs(['ls']),
        endpoints: endpoints,
        bdFactory: factory,
        out: human.add,
      ),
      0,
    );
    expect(human.single, contains('external:power_station:pow-60g'));
    expect(
      tg.calls.any(
        (call) =>
            call.take(2).join(' ') ==
            'query '
                '${BdCliService.allStatusesQuery}',
      ),
      isTrue,
      reason: 'the listing rides the frontier\'s own broad graph read',
    );

    // A bd whose record surface stops carrying rows must not read as "no
    // external blockers": the verb reports the refusal and exits non-zero.
    tg.dropRecordDependencies = true;
    final errors = <String>[];
    expect(
      await runLink(
        arguments: _linkArgs(['ls']),
        endpoints: endpoints,
        bdFactory: factory,
        err: errors.add,
      ),
      1,
    );
    expect(errors.single, contains('grid link ls'));
    expect(
      errors.single,
      contains('no bd surface carried its `external:` dependency rows'),
    );
  });

  test('link ls reads SHIPPED the way the FRONTIER does — a fan-in capability '
      'is not a bead id', () async {
    tg.dependencies.add(
      const BeadDependency(
        issueId: 'tg-q9k',
        dependsOnId: 'external:power_station:release-gate',
      ),
    );
    // The NAMED (fan-in) form: a container bead whose own id is NOT the
    // capability ships it. Resolving the capability as a bead id would render
    // this PENDING while the frontier admits the consumer.
    pow.beads[0] = pow.beads[0].copyWith(
      status: BeadStatus.closed,
      labels: const ['export:release-gate', 'provides:release-gate'],
    );
    final human = <String>[];
    expect(
      await runLink(
        arguments: _linkArgs(['ls']),
        endpoints: endpoints,
        bdFactory: factory,
        out: human.add,
      ),
      0,
    );
    expect(human.single, contains('SHIPPED'));

    // An OPEN bead carrying provides: is `bd ship --force` — not shipped.
    pow.beads[0] = pow.beads[0].copyWith(status: BeadStatus.open);
    human.clear();
    expect(
      await runLink(
        arguments: _linkArgs(['ls']),
        endpoints: endpoints,
        bdFactory: factory,
        out: human.add,
      ),
      0,
    );
    expect(human.single, contains('PENDING (unshipped)'));
  });

  test('link ls accepts nothing but --json', () async {
    final errors = <String>[];
    expect(
      await runLink(
        arguments: _linkArgs(['ls', '--blocked-by', 'pow-60g']),
        endpoints: endpoints,
        bdFactory: factory,
        err: errors.add,
      ),
      64,
    );
    expect(errors.single, contains('only --json'));
  });

  test('hyphenated roster prefixes resolve their own endpoints', () async {
    final inferRoot = Directory('${temp.path}/swift_infer')
      ..createSync(recursive: true);
    final trainRoot = Directory('${temp.path}/swift_train')
      ..createSync(recursive: true);
    Directory('${inferRoot.path}/.beads').createSync();
    Directory('${trainRoot.path}/.beads').createSync();
    final infer = _FakeStore(
      [_bead('swift-infer-097')],
      customTypes: const [],
      externalProjects: 'swift_train=../swift_train',
    );
    final train = _FakeStore([_bead('swift-train-042')], customTypes: const []);
    stores[inferRoot.path] = infer;
    stores[trainRoot.path] = train;
    final written = <String>[];
    expect(
      await runLink(
        arguments: _linkArgs([
          'swift-infer-097',
          '--blocked-by',
          'swift-train-042',
        ]),
        endpoints: [
          LinkEndpointStore(
            name: 'swift_infer',
            prefix: 'swift-infer',
            store: SubstationWorkStore(root: inferRoot.path),
          ),
          LinkEndpointStore(
            name: 'swift_train',
            prefix: 'swift-train',
            store: SubstationWorkStore(root: trainRoot.path),
          ),
        ],
        bdFactory: factory,
        out: written.add,
      ),
      0,
    );
    expect(
      written.single,
      'swift-infer-097 --blocked-by external:swift_train:swift-train-042',
    );
  });

  group('link migrate — the ONE PASS (tg-6t0h)', () {
    setUp(() {
      tg.beads.add(_bead('tg-second'));
      pow.beads.add(_bead('pow-closed', status: BeadStatus.closed));
      state.beads.addAll([
        _link('houston-l1', 'tg-q9k', 'pow-60g'),
        _link('houston-l2', 'tg-second', 'pow-closed'),
        _link('houston-l3', 'pow-60g', 'tg-q9k'),
      ]);
    });

    test('three open links become three external rows, three export labels '
        'and three closed link beads, in ONE command', () async {
      final written = <String>[];
      final errors = <String>[];
      expect(
        await runLink(
          arguments: _migrateArgs(['migrate', '--grid-root', temp.path]),
          endpoints: endpoints,
          bdFactory: factory,
          out: written.add,
          err: errors.add,
        ),
        0,
      );
      expect(errors, isEmpty);

      expect(
        tg.calls
            .where((call) => call.first == 'dep' && call[1] == 'add')
            .map((call) => call.sublist(2, 4)),
        [
          ['tg-q9k', 'external:power_station:pow-60g'],
          ['tg-second', 'external:power_station:pow-closed'],
        ],
      );
      expect(
        pow.calls
            .where((call) => call.first == 'dep' && call[1] == 'add')
            .map((call) => call.sublist(2, 4)),
        [
          ['pow-60g', 'external:the_grid:tg-q9k'],
        ],
      );
      expect(
        {
          for (final bead in [...tg.beads, ...pow.beads])
            if (bead.labels.isNotEmpty) bead.id: bead.labels,
        },
        {
          'tg-q9k': ['export:tg-q9k'],
          'pow-60g': ['export:pow-60g'],
          'pow-closed': ['export:pow-closed', 'provides:pow-closed'],
        },
      );
      expect(state.beads.every((bead) => bead.isClosed), isTrue);
      expect(written.last, contains('3 link bead(s) migrated'));

      // The existing-row read is scoped PER STORE, not per LINK: a bd spawn
      // per link per surface is the CLI-spawn loop this repo refuses, and the
      // pass runs over a hundred receipts. Two calls at most — this pass's own
      // scoped read, plus `externalDepRows`' control, which spawns only on a
      // store whose record surface returned no rows at all.
      for (final store in [tg, pow]) {
        expect(
          store.calls
              .where((call) => call.first == 'dep' && call[1] == 'list')
              .length,
          lessThanOrEqualTo(2),
        );
      }
    });

    test('each close reason NAMES the row the link became', () async {
      expect(
        await runLink(
          arguments: _migrateArgs(['migrate', '--grid-root', temp.path]),
          endpoints: endpoints,
          bdFactory: factory,
          out: (_) {},
        ),
        0,
      );
      final closes = state.calls.where((call) => call.first == 'close');
      expect(closes, hasLength(3));
      final first = closes.first;
      expect(first[1], 'houston-l1');
      final reason = first[first.indexOf('--reason') + 1];
      expect(reason, contains('tg-q9k'));
      expect(reason, contains('external:power_station:pow-60g'));
    });

    test('a CLOSED target is SHIPPED so the consumer unblocks', () async {
      expect(
        await runLink(
          arguments: _migrateArgs(['migrate', '--grid-root', temp.path]),
          endpoints: endpoints,
          bdFactory: factory,
          out: (_) {},
        ),
        0,
      );
      expect(
        pow.calls.where((call) => call.first == 'ship').map((call) => call[1]),
        ['pow-closed'],
        reason: 'only the CLOSED target is shippable; bd refuses an open one',
      );
    });

    test(
      '--dry-run prints the plan and leaves every store byte-identical',
      () async {
        final before = {
          for (final entry in stores.entries)
            entry.key: [...entry.value.beads, ...entry.value.dependencies],
        };
        final written = <String>[];
        expect(
          await runLink(
            arguments: _migrateArgs([
              'migrate',
              '--grid-root',
              temp.path,
              '--dry-run',
            ]),
            endpoints: endpoints,
            bdFactory: factory,
            out: written.add,
          ),
          0,
        );
        expect(written.last, contains('DRY RUN'));
        expect(written.last, contains('3 link bead(s) planned'));
        expect(
          written.where((line) => line.contains('external:')),
          isNotEmpty,
          reason: 'the plan names each row it would write',
        );
        for (final store in stores.values) {
          expect(store.mutationCalls, isEmpty);
        }
        expect({
          for (final entry in stores.entries)
            entry.key: [...entry.value.beads, ...entry.value.dependencies],
        }, before);
      },
    );

    test('a SECOND run reports zero links and writes nothing', () async {
      expect(
        await runLink(
          arguments: _migrateArgs(['migrate', '--grid-root', temp.path]),
          endpoints: endpoints,
          bdFactory: factory,
          out: (_) {},
        ),
        0,
      );
      for (final store in stores.values) {
        store.calls.clear();
      }
      final written = <String>[];
      expect(
        await runLink(
          arguments: _migrateArgs(['migrate', '--grid-root', temp.path]),
          endpoints: endpoints,
          bdFactory: factory,
          out: written.add,
        ),
        0,
      );
      expect(written.single, contains('0 open link beads'));
      for (final store in stores.values) {
        expect(store.mutationCalls, isEmpty);
      }
    });

    test('an INTERRUPTED pass finishes on a re-run without duplicating a row '
        'or a label', () async {
      // The shape a crash between the row write and the close leaves behind.
      tg.beads[0] = tg.beads[0].copyWith(labels: const []);
      pow.beads[0] = pow.beads[0].copyWith(labels: const ['export:pow-60g']);
      tg.dependencies.add(
        const BeadDependency(
          issueId: 'tg-q9k',
          dependsOnId: 'external:power_station:pow-60g',
        ),
      );
      expect(
        await runLink(
          arguments: _migrateArgs(['migrate', '--grid-root', temp.path]),
          endpoints: endpoints,
          bdFactory: factory,
          out: (_) {},
        ),
        0,
      );
      expect(
        tg.dependencies
            .where((dep) => dep.dependsOnId == 'external:power_station:pow-60g')
            .length,
        1,
      );
      expect(
        pow.calls.where(
          (call) => call.first == 'label' && call[2] == 'pow-60g',
        ),
        isEmpty,
      );
      expect(state.beads.every((bead) => bead.isClosed), isTrue);
    });

    test('a link this pass cannot author is left OPEN and reported, and the '
        'verb exits 1', () async {
      state.beads
        ..add(_bead('houston-l4', type: GridIssueTypes.link))
        ..add(_link('houston-l5', 'tg-q9k', 'dashboard-1'))
        ..add(_link('houston-l6', 'tg-q9k', 'pow-999'));
      final errors = <String>[];
      expect(
        await runLink(
          arguments: _migrateArgs(['migrate', '--grid-root', temp.path]),
          endpoints: endpoints,
          bdFactory: factory,
          out: (_) {},
          err: errors.add,
        ),
        1,
      );
      expect(errors.length, 4);
      expect(errors[0], contains('houston-l4'));
      expect(errors[1], contains('dashboard-1'));
      expect(errors[2], contains('pow-999'));
      expect(errors.last, contains('3 link bead(s) left OPEN'));
      for (final id in ['houston-l4', 'houston-l5', 'houston-l6']) {
        expect(
          state.beads.firstWhere((bead) => bead.id == id).isClosed,
          isFalse,
        );
      }
      // The three WELL-FORMED links still migrated in the same pass.
      for (final id in ['houston-l1', 'houston-l2', 'houston-l3']) {
        expect(
          state.beads.firstWhere((bead) => bead.id == id).isClosed,
          isTrue,
        );
      }
    });

    test('a SAME-STORE link becomes a plain local dep row, no capability '
        'at all', () async {
      state.beads.clear();
      state.beads.add(_link('houston-l9', 'tg-q9k', 'tg-second'));
      expect(
        await runLink(
          arguments: _migrateArgs(['migrate', '--grid-root', temp.path]),
          endpoints: endpoints,
          bdFactory: factory,
          out: (_) {},
        ),
        0,
      );
      expect(tg.dependencies.single.dependsOnId, 'tg-second');
      expect(tg.calls.where((call) => call.first == 'label'), isEmpty);
      expect(state.beads.single.isClosed, isTrue);
    });

    test('--grid-root is required', () async {
      final errors = <String>[];
      expect(
        await runLink(
          arguments: _migrateArgs(['migrate']),
          endpoints: endpoints,
          bdFactory: factory,
          err: errors.add,
        ),
        64,
      );
      expect(errors.single, contains('--grid-root'));
      for (final store in stores.values) {
        expect(store.calls, isEmpty);
      }
    });

    test('a state store without the link type migrates nothing', () async {
      state.customTypes = const [];
      final written = <String>[];
      expect(
        await runLink(
          arguments: _migrateArgs(['migrate', '--grid-root', temp.path]),
          endpoints: endpoints,
          bdFactory: factory,
          out: written.add,
        ),
        0,
      );
      expect(written.single, contains('0 open link beads'));
      expect(state.mutationCalls, isEmpty);
    });
  });

  test('the link verb centralizes its bd surface — no bead writes at all', () {
    final source = File('lib/src/link_command.dart').readAsStringSync();
    final link = source.substring(
      source.indexOf('Future<int> runLink('),
      source.indexOf('class _StoreProbes {'),
    );
    expect(link, isNot(contains('.create(')));
    expect(link, isNot(contains('createLink(')));
    expect(link, isNot(contains('StationBeadWriter')));
    expect(link, isNot(contains('GridIssueTypes.link')));
    expect(link, contains('.depAdd('));
    expect(link, contains('.addLabels('));
  });

  test('the HARD CUT: unlink and the link-bead enforcement it served are '
      'gone from the tree (tg-6t0h)', () {
    final source = File('lib/src/link_command.dart').readAsStringSync();
    expect(source, isNot(contains('UnlinkCommand')));
    expect(source, isNot(contains('runUnlink')));
    expect(source, isNot(contains('StationBeadWriter')));
    expect(
      File('lib/grid_cli.dart').readAsStringSync(),
      isNot(contains('nlink')),
    );
    for (final path in const [
      '../grid_engine/lib/src/domain/cross_link.dart',
      '../grid_engine/lib/src/bridge/block_guard.dart',
    ]) {
      expect(
        File(path).existsSync(),
        isFalse,
        reason: '$path is the retired link-bead enforcement',
      );
    }
  });
}

ArgResults _linkArgs(List<String> args) => _parser().parse(args);

ArgResults _migrateArgs(List<String> args) => _parser().parse(args);

/// The EXACT parser `LinkCommand` registers — one spelling, so a test can
/// never exercise a flag surface the composed verb does not have.
ArgParser _parser() => ArgParser()
  ..addOption('blocked-by')
  ..addFlag('json', negatable: false)
  ..addOption('grid-root')
  ..addFlag('dry-run', negatable: false);

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

Bead _link(
  String id,
  String from,
  String to, {
  BeadStatus status = BeadStatus.open,
}) => _bead(
  id,
  status: status,
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
    this.externalProjects = '',
  });

  final List<Bead> beads;
  final List<BeadDependency> dependencies = [];

  /// Fakes a bd whose RECORD surface stopped carrying dependency rows — the
  /// shape the CLI read path must REFUSE rather than read as "no external
  /// blockers".
  bool dropRecordDependencies = false;
  List<Object> customTypes;
  String externalProjects;
  final List<List<String>> calls = [];

  /// Every call that WRITES. `dep list` is a READ that happens to share bd's
  /// `dep` verb, so it is excluded — a dry run reads freely and writes never.
  List<List<String>> get mutationCalls => calls
      .where(
        (call) =>
            const {
              'create',
              'update',
              'close',
              'label',
              'dep',
              'ship',
            }.contains(call.first) &&
            !(call.first == 'dep' && call[1] == 'list'),
      )
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
          'core_types': const ['task'],
          if (customTypes.isNotEmpty) 'custom_types': customTypes,
        });
      case 'config':
        return _envelope({
          'key': 'external_projects',
          'value': externalProjects,
        });
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
        // The BROAD graph read is bd's RECORD surface: every bead record
        // carries its dependency ROWS, which is the only bd read that returns
        // an `external:` row at all (tg-xh5d). `dropRecordDependencies` fakes
        // a bd that stopped carrying them.
        if (expression == BdCliService.allStatusesQuery) {
          return _listEnvelope([
            for (final bead in beads)
              {
                ...bead.toJson(),
                if (!dropRecordDependencies)
                  'dependencies': [
                    for (final dep in dependencies)
                      if (dep.issueId == bead.id) dep.toJson(),
                  ],
              },
          ]);
        }
        // The two scoped expressions the verb authors: an id lookup, and the
        // LABEL scan that answers "is this capability shipped?" the way the
        // frontier answers it.
        final match = switch (expression.split('=')) {
          ['id', final String id] => (Bead bead) => bead.id == id,
          ['label', final String label] => (Bead bead) => bead.labels.contains(
            label,
          ),
          _ => throw StateError('unexpected bd query: $args'),
        };
        return _listEnvelope(
          beads.where(match).map((bead) => bead.toJson()).toList(),
        );
      case 'dep':
        if (args[1] == 'list') {
          final ids = args.sublist(2, args.indexOf('--json')).toSet();
          return _listEnvelope([
            for (final dep in dependencies)
              if (ids.contains(dep.issueId)) dep.toJson(),
          ]);
        }
        dependencies.add(
          BeadDependency(issueId: args[2], dependsOnId: args[3]),
        );
        return _envelope({'id': args[2]});
      case 'label':
        final index = beads.indexWhere((bead) => bead.id == args[2]);
        beads[index] = beads[index].copyWith(
          labels: [
            ...beads[index].labels,
            ...args.sublist(3, args.indexOf('--json')),
          ],
        );
        return _envelope({'id': args[2]});
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
      case 'ship':
        // bd finds the issue carrying `export:<capability>`, validates that it
        // is CLOSED, and adds `provides:<capability>`.
        final index = beads.indexWhere(
          (bead) => bead.labels.contains('export:${args[1]}'),
        );
        if (index < 0 || !beads[index].isClosed) {
          throw StateError('bd ship: nothing shippable for ${args[1]}');
        }
        beads[index] = beads[index].copyWith(
          labels: [...beads[index].labels, 'provides:${args[1]}'],
        );
        return _envelope({'id': beads[index].id});
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
