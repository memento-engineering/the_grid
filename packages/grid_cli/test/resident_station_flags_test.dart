import 'dart:io';

import 'package:args/args.dart';
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

ArgParser parser() {
  final parser = ArgParser();
  residentStationFlags(
    parser,
    codedNames: const ['grid'],
    harnessAllowList: const {'claude', 'codex'},
  );
  return parser;
}

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('resident-flags-'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('safe defaults and every value parse', () {
    final other = Directory('${temp.path}/other')..createSync();
    final args = parser().parse([
      '--grid-home',
      temp.path,
      '--substation',
      'other@oth=${other.path}',
      '--harness',
      'codex',
      '--build-harness',
      'claude',
      '--model',
      'build-model',
      '--grader-model',
      'grade-model',
      '--max-agents',
      '7',
      '--control-port',
      '42',
      '--for-seconds',
      '3',
    ]);
    final config = residentStationConfigFrom(
      args,
      stationName: 'lunar',
      codedNames: const {'grid'},
    );
    expect(config.gridHome, temp.path);
    expect(config.dryRun, isTrue);
    expect(config.controlPort, 42);
    expect(config.runFor, const Duration(seconds: 3));
    expect(config.harness, 'codex');
    expect(config.buildHarness, 'claude');
    expect(config.model, 'build-model');
    expect(config.graderModel, 'grade-model');
    expect(config.maxAgents, 7);
    expect(config.appended.single.name, 'other');
    expect(config.appended.single.prefix, 'oth');
  });

  test('equal aliases are accepted and conflicts refused', () {
    final equal = parser().parse([
      '--grid-home',
      temp.path,
      '--state-workspace',
      temp.path,
    ]);
    expect(
      residentStationConfigFrom(
        equal,
        stationName: 'lunar',
        codedNames: const {},
      ).gridHome,
      temp.path,
    );
    final conflict = parser().parse([
      '--grid-home',
      temp.path,
      '--state-workspace',
      '${temp.path}/other',
    ]);
    expect(
      () => residentStationConfigFrom(
        conflict,
        stationName: 'lunar',
        codedNames: const {},
      ),
      throwsFormatException,
    );
  });

  test('append values are absolute, unique, well formed, and append-only', () {
    for (final value in [
      'missing-equals',
      '=${temp.path}',
      'new@=${temp.path}',
      'new=relative',
      'new@one@two=${temp.path}',
    ]) {
      expect(
        () => residentStationConfigFrom(
          parser().parse(['--grid-home', temp.path, '--substation', value]),
          stationName: 'lunar',
          codedNames: const {'grid'},
        ),
        throwsFormatException,
        reason: value,
      );
    }
    for (final values in [
      ['grid=${temp.path}'],
      ['new=${temp.path}', 'new=${temp.path}'],
    ]) {
      expect(
        () => residentStationConfigFrom(
          parser().parse([
            '--grid-home',
            temp.path,
            for (final value in values) ...['--substation', value],
          ]),
          stationName: 'lunar',
          codedNames: const {'grid'},
        ),
        throwsFormatException,
      );
    }
  });

  test('invalid numeric values and relative home refuse', () {
    for (final pair in [
      ['--grid-home', 'relative'],
      ['--control-port', 'nope'],
      ['--for-seconds', '0'],
      ['--max-agents', '-1'],
    ]) {
      expect(
        () => residentStationConfigFrom(
          parser().parse(['--grid-home', temp.path, ...pair]),
          stationName: 'lunar',
          codedNames: const {},
        ),
        throwsFormatException,
      );
    }
  });

  test('the resident surface has no bead option', () {
    expect(parser().options, isNot(contains('bead')));
  });

  test('public barrel constructs all resident commands', () {
    final up = ResidentUpCommand(
      stationName: 'lunar',
      delegateFactory:
          ({
            required config,
            required wiring,
            required provisioner,
            required gitOps,
            required prOpener,
          }) => throw StateError('compile witness only'),
      codedRoster: ({required gridHome}) => const [],
      harnessAllowList: const {'safe'},
      validateHarness: (_) => null,
      resolver: _Resolver(),
      registry: _Registry(),
    );
    final down = ResidentDownCommand(stationName: 'lunar');
    final status = ResidentStatusCommand(stationName: 'lunar');

    expect((up.name, down.name, status.name), ('up', 'down', 'status'));
  });
}
