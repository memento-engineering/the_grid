// tg-7gm (`docs/SCRATCH-grid-alignment.md` §6 amendment): the multi-root
// `--root <name>=<path>[@head]` grammar — repeatable, name-keyed registration,
// with the bare `--root <path>` single-root shorthand kept back-compatible.
// Zero I/O — pure flag parsing.
import 'package:args/args.dart';
import 'package:grid_cli/src/station_runner.dart';
import 'package:test/test.dart';

ArgParser _parser() {
  final parser = ArgParser();
  addStationFlags(parser);
  return parser;
}

void main() {
  group('RootSpec.parse', () {
    test('a bare path (no "=") registers under defaultName', () {
      final entry = RootSpec.parse('/tmp/root', defaultName: 'tgdog');
      expect(entry.key, 'tgdog');
      expect(entry.value.path, '/tmp/root');
      expect(entry.value.head, isNull);
    });

    test('"<name>=<path>" registers under the explicit name', () {
      final entry = RootSpec.parse(
        'power_station=/tmp/power',
        defaultName: 'tgdog',
      );
      expect(entry.key, 'power_station');
      expect(entry.value.path, '/tmp/power');
      expect(entry.value.head, isNull);
    });

    test('"<name>=<path>@<head>" carries the per-root head', () {
      final entry = RootSpec.parse(
        'power_station=/tmp/power@feature-x',
        defaultName: 'tgdog',
      );
      expect(entry.key, 'power_station');
      expect(entry.value.path, '/tmp/power');
      expect(entry.value.head, 'feature-x');
    });

    test('an empty name before "=" throws FormatException', () {
      expect(
        () => RootSpec.parse('=/tmp/power', defaultName: 'tgdog'),
        throwsFormatException,
      );
    });

    test('an empty path after "=" throws FormatException', () {
      expect(
        () => RootSpec.parse('power_station=', defaultName: 'tgdog'),
        throwsFormatException,
      );
    });

    test('an empty bare value throws FormatException', () {
      expect(
        () => RootSpec.parse('', defaultName: 'tgdog'),
        throwsFormatException,
      );
    });
  });

  group('StationArgs.from — the --root grammar', () {
    test(
      'no --root at all: an EMPTY roots map (dry-run\'s unconstrained default)',
      () {
        final args = StationArgs.from(
          _parser().parse(['--substation', 'tgdog']),
        );
        expect(args.roots, isEmpty);
      },
    );

    test('a bare --root <path> is the single-root shorthand — registers under '
        'the FIRST --substation (back-compatible)', () {
      final args = StationArgs.from(
        _parser().parse(['--substation', 'tgdog', '--root', '/tmp/root']),
      );
      expect(args.roots, {'tgdog': const RootSpec(path: '/tmp/root')});
    });

    test('repeatable --root <name>=<path> registers MULTIPLE named roots', () {
      final args = StationArgs.from(
        _parser().parse([
          '--substation',
          'tg',
          '--root',
          'tg=/tmp/the_grid',
          '--root',
          'power_station=/tmp/power_station',
        ]),
      );
      expect(args.roots, {
        'tg': const RootSpec(path: '/tmp/the_grid'),
        'power_station': const RootSpec(path: '/tmp/power_station'),
      });
    });

    test(
      'a per-root "@head" overrides the global --head for THAT root only',
      () {
        final args = StationArgs.from(
          _parser().parse([
            '--substation',
            'tg',
            '--root',
            'tg=/tmp/the_grid',
            '--root',
            'power_station=/tmp/power_station@feature-x',
            '--head',
            'main',
          ]),
        );
        expect(args.roots['tg']!.head, isNull);
        expect(args.roots['power_station']!.head, 'feature-x');
        expect(args.head, 'main');
      },
    );

    test(
      'registering the SAME name twice throws FormatException (a config '
      'defect the operator should see immediately, not silently overwrite)',
      () {
        expect(
          () => StationArgs.from(
            _parser().parse([
              '--substation',
              'tg',
              '--root',
              'tg=/tmp/a',
              '--root',
              'tg=/tmp/b',
            ]),
          ),
          throwsFormatException,
        );
      },
    );
  });

  group('StationArgs(rootPath: ...) — the deprecated back-compat alias '
      '(tg-7gm rework r2)', () {
    test('a bare rootPath-only construction folds into `roots` under the '
        'FIRST substation\'s name — space_station\'s up_command still '
        'compiles + behaves unchanged until it migrates', () {
      const args = StationArgs(
        substations: {'tgdog'},
        rootPath: '/tmp/legacy-root',
      );
      expect(args.roots, {'tgdog': const RootSpec(path: '/tmp/legacy-root')});
    });

    test(
      'an explicit `roots` entry under the same name wins over rootPath',
      () {
        const args = StationArgs(
          substations: {'tgdog'},
          roots: {'tgdog': RootSpec(path: '/tmp/explicit')},
          rootPath: '/tmp/legacy-root',
        );
        expect(args.roots, {'tgdog': const RootSpec(path: '/tmp/explicit')});
      },
    );

    test('rootPath is folded ALONGSIDE an explicit `roots` entry under a '
        'DIFFERENT name — both survive', () {
      const args = StationArgs(
        substations: {'tgdog'},
        roots: {'power_station': RootSpec(path: '/tmp/power')},
        rootPath: '/tmp/legacy-root',
      );
      expect(args.roots, {
        'power_station': const RootSpec(path: '/tmp/power'),
        'tgdog': const RootSpec(path: '/tmp/legacy-root'),
      });
    });

    test('no rootPath, no roots: unchanged (empty)', () {
      const args = StationArgs(substations: {'tgdog'});
      expect(args.roots, isEmpty);
    });

    test(
      'the deprecated `rootPath` getter reads back the raw value unfolded',
      () {
        const args = StationArgs(
          substations: {'tgdog'},
          rootPath: '/tmp/legacy-root',
        );
        expect(args.rootPath, '/tmp/legacy-root');
      },
    );
  });
}
