import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// RS-4 (D-C2, `docs/SCRATCH-resident-station.md` §3): `StationControl` is
/// READ-ONLY BY CONSTRUCTION — a GET-only, exact-match route table, never a
/// bd writer, never a re-query trigger. Source gates over
/// `lib/src/station_control.dart`, with a positive control so a path/glob
/// regression cannot make the negative gates pass vacuously (mirrors
/// `grid_engine/test/effect_layer_gates_test.dart`).
void main() {
  group('StationControl source gates (RS-4, D-C2)', () {
    final source = _stationControlSource();

    test('positive control: the scan sees real StationControl source', () {
      expect(source, isNotEmpty);
      expect(
        source,
        allOf(
          contains("'/healthz'"),
          contains("'/status'"),
          contains("'/hooks'"),
        ),
        reason:
            'the GET-only control surface must name every route — proves '
            'the scan reads real bytes, not an empty/moved file '
            '(vacuousness control)',
      );
    });

    test('gate 1: no mutation HTTP verb is ever matched against (GET-only, '
        'by construction)', () {
      for (final verb in ['POST', 'PUT', 'DELETE', 'PATCH']) {
        expect(
          source,
          isNot(contains("'$verb'")),
          reason:
              'StationControl never tests for $verb — there is no route '
              'a mutation method could reach',
        );
      }
    });

    test('gate 2: never imports or names the bd write chokepoint', () {
      expect(source, isNot(contains('StationBeadWriter')));
      expect(source, isNot(contains('BdCliService')));
      expect(source, isNot(contains('BdRunner')));
      expect(
        source,
        isNot(contains("import 'station_lock.dart'")),
        reason:
            'the control surface never touches the lock file itself — '
            'it only reports the URL the CALLER already wrote there',
      );
    });

    test('gate 3: never triggers a re-query', () {
      expect(source, isNot(contains('.requery(')));
      expect(source, isNot(contains('requery()')));
    });

    test('gate 4: no mutation endpoint exists — the ONLY routed paths are '
        '/healthz, /status, and /hooks', () {
      final routePaths = RegExp(
        r"'(/[a-zA-Z0-9_-]*)'",
      ).allMatches(source).map((m) => m.group(1)!).toSet();
      expect(routePaths, {'/healthz', '/status', '/hooks'});
    });
  });
}

/// The `StationControl` source, resolved via the package URI (CWD-independent
/// — mirrors the effect-layer gate's own resolution style).
String _stationControlSource() {
  final libUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:grid_cli/grid_cli.dart'),
  );
  final file = File.fromUri(libUri!.resolve('src/station_control.dart'));
  return file.readAsStringSync();
}
