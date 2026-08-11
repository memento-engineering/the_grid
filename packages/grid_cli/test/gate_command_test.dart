import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/src/gate_command.dart';
import 'package:grid_cli/src/station_command_client.dart';
import 'package:test/test.dart';

/// Offline proofs for the resident-door `grid gate` client.
///
/// Ported from the pre-door suite: list rendering, empty and re-gated display,
/// completed/refused/unavailable outcomes, CLI arity and absolute-root guards,
/// rationale requirements, and raw grade parsing. Removed with the retired
/// second-process path: direct `GridStateStore` export/write assertions,
/// state-prefix CLI guards, and CLI-side bead/gate/ownership/F-lane checks;
/// those resident semantics are covered by station_command_handler_test.dart.
void main() {
  const fixture =
      "literal `cmd` and \$(cmd) and \$VAR and 'single'\n  trailing  ";
  group('grid gate ls resident door', () {
    test('list renders all resident rows sorted', () async {
      final output = <String>[];
      final client = FakeClient(
        StationCommandCompleted({
          'gates': [
            {'id': 'g-2', 'createdAt': '2026-01-01T00:00:00Z'},
            {'id': 'g-1', 'createdAt': '2026-01-01T00:00:00Z'},
          ],
        }),
      );
      expect(
        await runGateLs(
          gridRoot: '/grid',
          client: client,
          out: output.add,
          now: DateTime.utc(2026, 1, 1),
        ),
        0,
      );
      expect(
        output.join('\n').indexOf('g-1'),
        lessThan(output.join('\n').indexOf('g-2')),
      );
      expect(client.method, 'grid/gate/ls');
    });

    test('empty resident list is explicit', () async {
      final output = <String>[];
      final code = await runGateLs(
        gridRoot: '/grid',
        client: FakeClient(const StationCommandCompleted({'gates': []})),
        out: output.add,
      );
      expect(code, 0);
      expect(output.single, contains('no open gates'));
    });

    test('re-gated row uses reset age and marker', () async {
      final output = <String>[];
      final code = await runGateLs(
        gridRoot: '/grid',
        client: FakeClient(
          const StationCommandCompleted({
            'gates': [
              {
                'id': 'g-1',
                'createdAt': '2026-07-01T12:00:00Z',
                'regatedAt': '2026-07-07T11:59:00Z',
                'regateCount': 3,
              },
            ],
          }),
        ),
        out: output.add,
        now: DateTime.utc(2026, 7, 7, 12),
      );
      expect(code, 0);
      expect(
        output.join('\n'),
        allOf(contains('age 1m'), contains('re-gated 3x')),
      );
    });

    for (final result in <StationCommandResult>[
      const StationCommandRefused('resident refused'),
      const StationCommandUnavailable('station.lock is absent'),
    ]) {
      test('resident list refusal is loud for ${result.runtimeType}', () async {
        final errors = <String>[];
        expect(
          await runGateLs(
            gridRoot: '/grid',
            client: FakeClient(result),
            err: errors.add,
          ),
          64,
        );
        expect(errors.single, isNotEmpty);
      });
    }
  });

  group('grid gate resolve parsing', () {
    test('--rationale-file preserves shell-sensitive text exactly', () async {
      final temp = await Directory.systemTemp.createTemp('grid-gate-text-');
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${temp.path}/rationale.txt');
      await file.writeAsString(fixture, encoding: utf8, flush: true);
      final client = FakeClient(const StationCommandCompleted({}));
      final runner = CommandRunner<int>('grid', 'test')
        ..addCommand(GateCommand(client: client));

      expect(
        await runner.run([
          'gate',
          'resolve',
          'g-1',
          '--grid-root',
          '/grid',
          '--grade',
          'critic=A',
          '--rationale-file',
          file.path,
        ]),
        0,
      );
      expect(client.params!['rationale'], fixture);
    });

    test('--rationale and --rationale-file refuse before dispatch', () async {
      final client = FakeClient(const StationCommandCompleted({}));
      final runner = CommandRunner<int>('grid', 'test')
        ..addCommand(GateCommand(client: client));
      expect(
        await runner.run(const [
          'gate',
          'resolve',
          'g-1',
          '--grid-root',
          '/grid',
          '--rationale',
          fixture,
          '--rationale-file',
          '-',
        ]),
        64,
      );
      expect(client.calls, 0);
    });

    test('resolve parses grades and sends typed map', () async {
      final client = FakeClient(const StationCommandCompleted({}));
      expect(
        await runGateResolve(
          gridRoot: '/grid',
          gateId: 'g-1',
          grades: const ['critic=a'],
          rationale: 'reviewed',
          client: client,
          out: (_) {},
        ),
        0,
      );
      expect(client.params!['grades'], {'critic': 'A'});
    });

    test('malformed pair refuses before dispatch', () async {
      final client = FakeClient(const StationCommandCompleted({}));
      final errors = <String>[];
      expect(
        await runGateResolve(
          gridRoot: '/grid',
          gateId: 'g-1',
          grades: const ['critic'],
          rationale: 'reviewed',
          client: client,
          err: errors.add,
        ),
        64,
      );
      expect(errors.single, contains('<lane>=<A-F>'));
      expect(client.calls, 0);
    });

    test('invalid letter refuses before dispatch', () async {
      final client = FakeClient(const StationCommandCompleted({}));
      final errors = <String>[];
      expect(
        await runGateResolve(
          gridRoot: '/grid',
          gateId: 'g-1',
          grades: const ['critic=Z'],
          rationale: 'reviewed',
          client: client,
          err: errors.add,
        ),
        64,
      );
      expect(errors.single, contains('grade A–F'));
      expect(client.calls, 0);
    });

    test('duplicate grade refuses before dispatch', () async {
      final client = FakeClient(const StationCommandCompleted({}));
      final errors = <String>[];
      expect(
        await runGateResolve(
          gridRoot: '/grid',
          gateId: 'g-1',
          grades: const ['critic=A', 'critic=B'],
          rationale: 'x',
          client: client,
          err: errors.add,
        ),
        64,
      );
      expect(errors.single, contains('duplicate --grade lane "critic"'));
      expect(client.calls, 0);
    });

    test('grade without rationale refuses before dispatch', () async {
      final client = FakeClient(const StationCommandCompleted({}));
      final errors = <String>[];
      expect(
        await runGateResolve(
          gridRoot: '/grid',
          gateId: 'g-1',
          grades: const ['critic=A'],
          client: client,
          err: errors.add,
        ),
        64,
      );
      expect(errors.single, contains('requires --rationale'));
      expect(client.calls, 0);
    });

    test('resident resolve refusal is loud', () async {
      final errors = <String>[];
      expect(
        await runGateResolve(
          gridRoot: '/grid',
          gateId: 'g-1',
          client: FakeClient(const StationCommandRefused('no gate g-1')),
          err: errors.add,
        ),
        64,
      );
      expect(errors.single, contains('no gate g-1'));
    });
  });

  group('grid gate command guards', () {
    test('ls missing or relative root never dispatches', () async {
      for (final args in <List<String>>[
        ['gate', 'ls'],
        ['gate', 'ls', '--grid-root', 'relative'],
      ]) {
        final client = FakeClient(const StationCommandCompleted({}));
        final runner = CommandRunner<int>('grid', 'test')
          ..addCommand(GateCommand(client: client));
        expect(await runner.run(args), 64);
        expect(client.calls, 0);
      }
    });

    test('resolve arity and root guards never dispatch', () async {
      for (final args in <List<String>>[
        ['gate', 'resolve', '--grid-root', '/grid'],
        ['gate', 'resolve', 'g-1', 'g-2', '--grid-root', '/grid'],
        ['gate', 'resolve', 'g-1'],
        ['gate', 'resolve', 'g-1', '--grid-root', 'relative'],
      ]) {
        final client = FakeClient(const StationCommandCompleted({}));
        final runner = CommandRunner<int>('grid', 'test')
          ..addCommand(GateCommand(client: client));
        expect(await runner.run(args), 64);
        expect(client.calls, 0);
      }
    });
  });
}

final class FakeClient extends StationCommandClient {
  FakeClient(this.result);

  final StationCommandResult result;
  int calls = 0;
  String? method;
  Map<String, Object?>? params;

  @override
  Future<StationCommandResult> send({
    required String gridRoot,
    required String method,
    required Map<String, Object?> params,
  }) async {
    calls++;
    this.method = method;
    this.params = params;
    return result;
  }
}
