import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('README rework', () {
    test('README rework flags exactly match ReworkCommand parser options', () {
      final command = ReworkCommand(client: _FakeStationCommandClient());
      final section = _readmeSection('grid rework');
      final documentedFlags = RegExp(
        r'--([a-z][a-z0-9-]*)',
      ).allMatches(section).map((match) => match.group(1)!).toSet();

      final registeredFlags = command.argParser.options.keys.toSet()
        ..remove('help'); // `args` injects universal help on every Command.

      expect(documentedFlags, registeredFlags);
    });

    test('README rework example dispatches through ReworkCommand', () async {
      final example = _normalizedShellExample(_readmeSection('grid rework'));
      final tokens = example.split(' ');
      expect(tokens.first, 'grid');

      final client = _FakeStationCommandClient();
      final runner = CommandRunner<int>('grid', 'test')
        ..addCommand(ReworkCommand(client: client));

      expect(await runner.run(tokens.skip(1).toList()), 0);
      expect(client.requests.map((request) => request.method), ['grid/rework']);
    });
  });

  test(
    'link and unlink prefix help states the complete repeatable contract',
    () {
      final endpoints = _endpointRoster();
      final link = LinkCommand(stateStorePrefix: 'state', endpoints: endpoints);
      final unlink = UnlinkCommand(
        stateStorePrefix: 'state',
        endpoints: endpoints,
      );

      expect(
        link.argParser.options['prefix']!.help,
        'Repeatable; must include every endpoint prefix named by <from-bead> '
        'and --blocked-by.',
      );
      expect(
        unlink.argParser.options['prefix']!.help,
        'Repeatable; must include the state prefix and, for <from> <to>, '
        'every endpoint prefix.',
      );
    },
  );

  test('missing configured endpoint prefix names the --prefix remedy before '
      'store access', () async {
    final refusal = await _runLinkRefusal(
      from: 'tg-q9k',
      to: 'pow-60g',
      prefixes: const ['tg'],
    );

    expect(refusal.code, 64);
    expect(refusal.storeAccesses, 0);
    expect(refusal.errors, [
      'grid link: endpoint "pow-60g" uses configured prefix "pow"; '
          'pass another --prefix pow.',
    ]);
  });

  test('endpoint prefix refusals distinguish all three causes', () async {
    final noPrefix = await _runLinkRefusal(
      from: 'unknown-1',
      to: 'pow-60g',
      prefixes: const ['tg'],
    );
    final unrostered = await _runLinkRefusal(
      from: 'other-1',
      to: 'pow-60g',
      prefixes: const ['other'],
    );
    final omitted = await _runLinkRefusal(
      from: 'tg-q9k',
      to: 'pow-60g',
      prefixes: const ['tg'],
    );

    expect(noPrefix.errors, [
      'grid link: endpoint "unknown-1" has no prefix matching the configured '
          'endpoint roster or any supplied --prefix.',
    ]);
    expect(unrostered.errors, [
      'grid link: endpoint "other-1" uses supplied --prefix "other", but '
          '"other" is not in the configured endpoint roster.',
    ]);
    expect(omitted.errors, [
      'grid link: endpoint "pow-60g" uses configured prefix "pow"; '
          'pass another --prefix pow.',
    ]);
    expect(
      [noPrefix, unrostered, omitted].map((refusal) => refusal.code),
      everyElement(64),
    );
    expect(
      [noPrefix, unrostered, omitted].map((refusal) => refusal.storeAccesses),
      everyElement(0),
    );
  });

  test('missing --prefix refusal never says unarmed', () async {
    final refusal = await _runLinkRefusal(
      from: 'tg-q9k',
      to: 'pow-60g',
      prefixes: const ['tg'],
    );

    expect(refusal.errors.single, isNot(contains('unarmed')));
  });
}

String _readmeSection(String heading) {
  final lines = File('README.md').readAsLinesSync();
  final start = lines.indexWhere(
    (line) => line.startsWith('## ') && line.contains(heading),
  );
  if (start < 0) throw StateError('README section not found: $heading');
  final relativeEnd = lines
      .skip(start + 1)
      .toList()
      .indexWhere((line) => line.startsWith('## '));
  final end = relativeEnd < 0 ? lines.length : start + 1 + relativeEnd;
  return lines.sublist(start, end).join('\n');
}

String _normalizedShellExample(String section) {
  final match = RegExp(r'```sh\s*\n([\s\S]*?)\n```').firstMatch(section);
  if (match == null) throw StateError('README shell example not found');
  return match.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<LinkEndpointStore> _endpointRoster() => [
  LinkEndpointStore(
    prefix: 'tg',
    store: SubstationWorkStore(root: '/work/the_grid'),
  ),
  LinkEndpointStore(
    prefix: 'pow',
    store: SubstationWorkStore(root: '/work/power_station'),
  ),
];

Future<({int code, List<String> errors, int storeAccesses})> _runLinkRefusal({
  required String from,
  required String to,
  required List<String> prefixes,
}) async {
  final errors = <String>[];
  var storeAccesses = 0;
  final command = LinkCommand(
    stateStorePrefix: 'state',
    endpoints: _endpointRoster(),
  );
  final arguments = command.argParser.parse([
    from,
    '--blocked-by',
    to,
    '--grid-root',
    '/grid-home',
    for (final prefix in prefixes) ...['--prefix', prefix],
    '--reason',
    'dependency',
    '--actor',
    'operator',
  ]);
  final code = await runLink(
    arguments: arguments,
    stateStorePrefix: 'state',
    endpoints: command.endpoints,
    out: (_) {},
    err: errors.add,
    bdFactory: (_) {
      storeAccesses++;
      throw StateError('endpoint refusal opened the state store');
    },
  );
  return (code: code, errors: errors, storeAccesses: storeAccesses);
}

final class _FakeStationCommandClient extends StationCommandClient {
  final requests =
      <({String gridRoot, String method, Map<String, Object?> params})>[];

  @override
  Future<StationCommandResult> send({
    required String gridRoot,
    required String method,
    required Map<String, Object?> params,
  }) async {
    requests.add((gridRoot: gridRoot, method: method, params: params));
    return const StationCommandCompleted({});
  }
}
