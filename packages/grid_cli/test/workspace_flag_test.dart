// tg-nsj (`docs/SCRATCH-multi-root-federation.md` §4 + the
// `SCRATCH-grid-alignment.md` §4 rescope to LOCAL stores only): the
// federated `--workspace <name>=<path>` grammar — repeatable, name-keyed
// registration, mirroring `--root` (D-M2/D-F4), with the bare
// `--workspace <path>` single-store shorthand kept back-compatible. Zero
// I/O — pure flag parsing.
import 'package:args/args.dart';
import 'package:grid_cli/src/station_runner.dart';
import 'package:test/test.dart';

ArgParser _parser() {
  final parser = ArgParser();
  addStationFlags(parser);
  return parser;
}

void main() {
  group('parseWorkspaceSpec', () {
    test('a bare path (no "=") registers under defaultName', () {
      final entry = parseWorkspaceSpec('/tmp/ws', defaultName: 'tgdog');
      expect(entry.key, 'tgdog');
      expect(entry.value, '/tmp/ws');
    });

    test('"<name>=<path>" registers under the explicit name', () {
      final entry = parseWorkspaceSpec(
        'butane_flutter=/tmp/butane',
        defaultName: 'tgdog',
      );
      expect(entry.key, 'butane_flutter');
      expect(entry.value, '/tmp/butane');
    });

    test('an empty name before "=" throws FormatException', () {
      expect(
        () => parseWorkspaceSpec('=/tmp/butane', defaultName: 'tgdog'),
        throwsFormatException,
      );
    });

    test('an empty path after "=" throws FormatException', () {
      expect(
        () => parseWorkspaceSpec('butane_flutter=', defaultName: 'tgdog'),
        throwsFormatException,
      );
    });

    test('an empty bare value throws FormatException', () {
      expect(
        () => parseWorkspaceSpec('', defaultName: 'tgdog'),
        throwsFormatException,
      );
    });
  });

  group('StationArgs.from — the --workspace grammar', () {
    test('no --workspace at all: an EMPTY workspaces map (implicit '
        'cwd-discovery — unchanged pre-federation default)', () {
      final args = StationArgs.from(_parser().parse(['--substation', 'tgdog']));
      expect(args.workspaces, isEmpty);
    });

    test('a bare --workspace <path> is the single-store shorthand — registers '
        'under the FIRST --substation (back-compatible)', () {
      final args = StationArgs.from(
        _parser().parse(['--substation', 'tgdog', '--workspace', '/tmp/ws']),
      );
      expect(args.workspaces, {'tgdog': '/tmp/ws'});
    });

    test('repeatable --workspace <name>=<path> registers MULTIPLE named stores '
        '— the office-grid example (tg + butane_flutter + dash)', () {
      final args = StationArgs.from(
        _parser().parse([
          '--substation',
          'tg',
          '--substation',
          'butane_flutter',
          '--substation',
          'dash',
          '--workspace',
          'tg=/tmp/the_grid',
          '--workspace',
          'butane_flutter=/tmp/butane_flutter',
          '--workspace',
          'dash=/tmp/.dashboard',
        ]),
      );
      expect(args.workspaces, {
        'tg': '/tmp/the_grid',
        'butane_flutter': '/tmp/butane_flutter',
        'dash': '/tmp/.dashboard',
      });
    });

    test(
      'registering the SAME name twice throws FormatException (a config '
      'defect the operator should see immediately, not silently overwrite)',
      () {
        expect(
          () => StationArgs.from(
            _parser().parse([
              '--substation',
              'tg',
              '--workspace',
              'tg=/tmp/a',
              '--workspace',
              'tg=/tmp/b',
            ]),
          ),
          throwsFormatException,
        );
      },
    );
  });

  group('StationArgs(workspacePath: ...) — the deprecated back-compat alias '
      '(tg-nsj, mirroring rootPath)', () {
    test('a bare workspacePath-only construction folds into `workspaces` '
        'under the FIRST substation\'s name', () {
      const args = StationArgs(
        substations: {'tgdog'},
        workspacePath: '/tmp/legacy-ws',
      );
      expect(args.workspaces, {'tgdog': '/tmp/legacy-ws'});
    });

    test('an explicit `workspaces` entry under the same name wins over '
        'workspacePath', () {
      const args = StationArgs(
        substations: {'tgdog'},
        workspaces: {'tgdog': '/tmp/explicit'},
        workspacePath: '/tmp/legacy-ws',
      );
      expect(args.workspaces, {'tgdog': '/tmp/explicit'});
    });

    test('no workspacePath, no workspaces: unchanged (empty)', () {
      const args = StationArgs(substations: {'tgdog'});
      expect(args.workspaces, isEmpty);
    });

    test('the deprecated `workspacePath` getter reads back the raw value '
        'unfolded', () {
      const args = StationArgs(
        substations: {'tgdog'},
        workspacePath: '/tmp/legacy-ws',
      );
      expect(args.workspacePath, '/tmp/legacy-ws');
    });
  });
}
