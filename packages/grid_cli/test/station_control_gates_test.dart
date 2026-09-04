import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// RS-4 (ADR-0014 D-C2/D-C4): `StationControl` has read-only HTTP/WS routes
/// and one fenced, scoped mutation route, never a bd writer or re-query trigger.
/// Source gates over
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
          contains("'/assets'"),
          contains("'/stream'"),
        ),
        reason:
            'the scoped control surface must name every route — proves '
            'the scan reads real bytes, not an empty/moved file '
            '(vacuousness control)',
      );
    });

    test('gate 1: POST is matched only for the fenced /command route', () {
      // ignore: prefer_single_quotes
      expect(source, contains("request.method == 'POST'"));
      // ignore: prefer_single_quotes
      expect(source, contains("request.uri.path == _commandPath"));
      for (final verb in ['PUT', 'DELETE', 'PATCH']) {
        expect(source, isNot(contains("'$verb'")));
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

    test('gate 4: the only routed paths include the scoped command door', () {
      final routePaths = RegExp(
        r"'(/[a-zA-Z0-9_-]*)'",
      ).allMatches(source).map((m) => m.group(1)!).toSet();
      expect(routePaths, {
        '/healthz',
        '/status',
        '/hooks',
        '/assets',
        '/stream',
        '/command',
      });
    });

    test(
      'gate 5: fenced command authority carries the ratified D-C4 stamp',
      () {
        expect(source, contains('the control plane cannot be a WORK trigger'));
        expect(
          source,
          contains('operator one-shots ARE control-plane requests'),
        );
        expect(source, contains('Nico-ratified 2026-07-24'));
      },
    );
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
