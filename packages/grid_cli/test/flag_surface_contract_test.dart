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

  test('the link verb registers only the flags it still honours', () {
    // tg-xh5d: `link` is sugar over `bd dep add`, so the link-bead flags
    // (--prefix, --grid-root, --reason, --actor) are GONE — the roster
    // resolves prefixes, bd owns the audit trail, and nothing is minted.
    final link = LinkCommand(endpoints: _endpointRoster());
    expect(link.argParser.options.keys.toSet()..remove('help'), {
      'blocked-by',
      'json',
    });
    expect(link.description, contains('bd dep add'));
    expect(
      UnlinkCommand(
        stateStorePrefix: 'state',
        endpoints: _endpointRoster(),
      ).argParser.options['prefix']!.help,
      'Repeatable; must include the state prefix and, for <from> <to>, '
      'every endpoint prefix.',
    );
  });

  test(
    'an endpoint outside the roster refuses before any store access',
    () async {
      final refusal = await _runLinkRefusal(from: 'unknown-1', to: 'pow-60g');

      expect(refusal.code, 64);
      expect(refusal.storeAccesses, 0);
      expect(refusal.errors.single, contains('unknown-1'));
      expect(refusal.errors.single, contains('tg, pow'));
    },
  );

  test('the refusal names the endpoint, never an arming flag', () async {
    final refusal = await _runLinkRefusal(from: 'tg-q9k', to: 'other-1');

    expect(refusal.errors.single, isNot(contains('--prefix')));
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
    name: 'the_grid',
    prefix: 'tg',
    store: SubstationWorkStore(root: '/work/the_grid'),
  ),
  LinkEndpointStore(
    name: 'power_station',
    prefix: 'pow',
    store: SubstationWorkStore(root: '/work/power_station'),
  ),
];

Future<({int code, List<String> errors, int storeAccesses})> _runLinkRefusal({
  required String from,
  required String to,
}) async {
  final errors = <String>[];
  var storeAccesses = 0;
  final command = LinkCommand(endpoints: _endpointRoster());
  final arguments = command.argParser.parse([from, '--blocked-by', to]);
  final code = await runLink(
    arguments: arguments,
    endpoints: command.endpoints,
    out: (_) {},
    err: errors.add,
    bdFactory: (_) {
      storeAccesses++;
      throw StateError('an endpoint refusal opened a store');
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
