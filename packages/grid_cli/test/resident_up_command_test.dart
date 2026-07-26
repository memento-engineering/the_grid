import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_engine/grid_engine.dart' show SessionProjection, StepMount;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

class _Resolver implements SessionResolver {
  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      throw UnimplementedError();
}

class _Registry implements CapabilityRegistry {
  @override
  Circuit? circuit(String circuitId) => null;

  @override
  Seed host(StepMount mount) => throw UnimplementedError();

  @override
  DateTime now() => DateTime.utc(2026);
}

void main() {
  test('harness validation precedes store and delegate work', () async {
    final home = Directory.systemTemp.createTempSync('resident-up-');
    addTearDown(() => home.deleteSync(recursive: true));
    var delegateCalls = 0;
    var validations = 0;
    final command = ResidentUpCommand(
      stationName: 'lunar',
      delegateFactory:
          ({
            required config,
            required wiring,
            required provisioner,
            required gitOps,
            required prOpener,
          }) {
            delegateCalls++;
            throw UnimplementedError();
          },
      codedRoster: ({required gridHome}) => const [],
      harnessAllowList: const {'safe'},
      validateHarness: (name) {
        validations++;
        return 'not configured';
      },
      resolver: _Resolver(),
      registry: _Registry(),
    );
    final runner = CommandRunner<int>('lunar', 'test')..addCommand(command);
    expect(await runner.run(['up', '--grid-home', home.path]), 64);
    expect(validations, 1);
    expect(delegateCalls, 0);
  });

  test('safe dry-run is the parser default and no bead option exists', () {
    final command = ResidentUpCommand(
      stationName: 'lunar',
      delegateFactory:
          ({
            required config,
            required wiring,
            required provisioner,
            required gitOps,
            required prOpener,
          }) => throw UnimplementedError(),
      codedRoster: ({required gridHome}) => const [],
      harnessAllowList: const {'safe'},
      validateHarness: (_) => null,
      resolver: _Resolver(),
      registry: _Registry(),
    );
    expect(command.argParser.defaultFor('dry-run'), isTrue);
    expect(command.argParser.options, isNot(contains('bead')));
  });

  test('assembly never references a builtin environment registry', () {
    final source = File('lib/src/resident_up_command.dart').readAsStringSync();
    expect(source, isNot(contains('buildBuiltinEnvironmentRegistry')));
  });
}
