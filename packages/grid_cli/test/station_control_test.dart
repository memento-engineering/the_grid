import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/src/station_control.dart';
import 'package:grid_cli/src/hooks_resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// RS-4 (D-C2, `docs/SCRATCH-resident-station.md` §3): `StationControl` — the
/// read-only, loopback-only HTTP control surface. Real HTTP round-trips over
/// an ephemeral port; NO live stores, NO real `claude`/`git`/`bd`. What this
/// file locks (the acceptance criteria):
///
///  (a) `GET /healthz` → 200 `{ok:true}`; `GET /status` → the shape-asserted
///      [StationStatus] payload; missing/wrong bearer → 401; an unknown path
///      → 404; a non-GET method → 405;
///  (b) the bind is loopback-only (127.0.0.1);
///  (e) dispose releases the port;
///  the `view` getter is called fresh per request — never polled, never
///  cached (the no-requery proof lives at the wiring layer, station_control_
///  wiring_test.dart; this file proves the HTTP layer never calls `view`
///  itself except in direct response to a request).
void main() {
  group('StationControl — HTTP round-trips', () {
    test('(b) binds loopback-only (127.0.0.1), not 0.0.0.0', () async {
      final control = await StationControl.start(
        port: 0,
        token: 't',
        view: _sampleStatus,
      );
      addTearDown(control.dispose);

      expect(InternetAddress(Uri.parse(control.url).host).isLoopback, isTrue);
      expect(Uri.parse(control.url).host, '127.0.0.1');
    });

    test('GET /healthz with a valid bearer → 200 {ok:true}', () async {
      final control = await StationControl.start(
        port: 0,
        token: 'secret-token',
        view: _sampleStatus,
      );
      addTearDown(control.dispose);

      final response = await _get(
        control.url,
        '/healthz',
        token: 'secret-token',
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(jsonDecode(response.body), {'ok': true});
    });

    test('GET /status with a valid bearer → 200, shape-asserted', () async {
      final control = await StationControl.start(
        port: 0,
        token: 'secret-token',
        view: () => StationStatus(
          substation: 'tgdog',
          stateStore: '/tmp/tgdog-state',
          workRoot: '/tmp/root',
          dryRun: true,
          pid: 4242,
          startedAt: DateTime.utc(2026, 7, 2),
          version: 'test-vm',
          ready: 3,
          mounted: 2,
          liveSessions: 1,
          lastSyncAt: null,
        ),
      );
      addTearDown(control.dispose);

      final response = await _get(
        control.url,
        '/status',
        token: 'secret-token',
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], contains('application/json'));
      final body = jsonDecode(response.body) as Map<String, Object?>;

      expect(body.keys, containsAll(<String>['station', 'process', 'work']));
      final station = body['station'] as Map<String, Object?>;
      expect(station, {
        'substation': 'tgdog',
        'stateStore': '/tmp/tgdog-state',
        'workRoot': '/tmp/root',
        'dryRun': true,
      });
      final process = body['process'] as Map<String, Object?>;
      expect(process['pid'], 4242);
      expect(process['version'], 'test-vm');
      expect(process['startedAt'], isA<String>());
      expect(process['uptimeSeconds'], isA<int>());
      final work = body['work'] as Map<String, Object?>;
      expect(work, {
        'ready': 3,
        'mounted': 2,
        'liveSessions': 1,
        'lastSyncAt': null,
        'perSubstation': <Object?>[],
      });
    });

    test('missing Authorization header → 401', () async {
      final control = await StationControl.start(
        port: 0,
        token: 'secret-token',
        view: _sampleStatus,
      );
      addTearDown(control.dispose);

      final response = await _get(control.url, '/healthz');
      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('wrong bearer token → 401 (healthz gets NO free pass)', () async {
      final control = await StationControl.start(
        port: 0,
        token: 'secret-token',
        view: _sampleStatus,
      );
      addTearDown(control.dispose);

      final response = await _get(control.url, '/healthz', token: 'nope');
      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('an unknown path → 404 (with a valid bearer)', () async {
      final control = await StationControl.start(
        port: 0,
        token: 'secret-token',
        view: _sampleStatus,
      );
      addTearDown(control.dispose);

      final response = await _get(
        control.url,
        '/mutate',
        token: 'secret-token',
      );
      expect(response.statusCode, HttpStatus.notFound);
    });

    test('a non-GET method on a real route → 405', () async {
      final control = await StationControl.start(
        port: 0,
        token: 'secret-token',
        view: _sampleStatus,
      );
      addTearDown(control.dispose);

      final response = await _post(
        control.url,
        '/status',
        token: 'secret-token',
      );
      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });

    test('dispose releases the bound port — a fresh bind on the SAME port '
        'succeeds afterward', () async {
      final control = await StationControl.start(
        port: 0,
        token: 't',
        view: _sampleStatus,
      );
      final boundPort = Uri.parse(control.url).port;

      await control.dispose();

      final rebind = await StationControl.start(
        port: boundPort,
        token: 't',
        view: _sampleStatus,
      );
      addTearDown(rebind.dispose);
      expect(Uri.parse(rebind.url).port, boundPort);
    });

    test('the view getter is called exactly once per /status request — '
        'never polled in the background', () async {
      var calls = 0;
      final control = await StationControl.start(
        port: 0,
        token: 't',
        view: () {
          calls++;
          return _sampleStatus();
        },
      );
      addTearDown(control.dispose);

      await _get(control.url, '/status', token: 't');
      expect(calls, 1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(calls, 1, reason: 'no background timer/poll ever calls view()');
      await _get(control.url, '/status', token: 't');
      expect(calls, 2);
      // /healthz never touches the view at all.
      await _get(control.url, '/healthz', token: 't');
      expect(calls, 2);
    });

    test('authenticated GET /hooks resolves encoded query parameters and '
        'returns exact JSON', () async {
      final resolver = _FakeHooksResolver();
      final control = await StationControl.start(
        port: 0,
        token: 't',
        view: _sampleStatus,
        hooksResolver: resolver,
      );
      addTearDown(control.dispose);
      final uri = Uri(
        path: '/hooks',
        queryParameters: {
          'event': 'pre commit/+',
          'worktree': '/tmp/a worktree',
        },
      );

      final response = await _get(control.url, uri.toString(), token: 't');

      expect(resolver.calls, [
        (event: 'pre commit/+', worktree: '/tmp/a worktree'),
      ]);
      expect(response.statusCode, HttpStatus.ok);
      expect(jsonDecode(response.body), {
        'event': 'pre commit/+',
        'worktree': '/tmp/a worktree',
        'substation': 'alpha',
        'contributions': [
          {
            'id': 'format',
            'source': 'dart',
            'run': 'dart format',
            'select': '*.dart',
            'mode': 'fix',
            'timeout_ms': 1000,
          },
        ],
      });
    });

    test('hooks bearer and method refusals do not invoke resolver', () async {
      final resolver = _FakeHooksResolver();
      final control = await StationControl.start(
        port: 0,
        token: 't',
        view: _sampleStatus,
        hooksResolver: resolver,
      );
      addTearDown(control.dispose);

      expect(
        (await _get(control.url, '/hooks?event=x&worktree=/tmp/w')).statusCode,
        HttpStatus.unauthorized,
      );
      expect(
        (await _post(
          control.url,
          '/hooks?event=x&worktree=/tmp/w',
          token: 't',
        )).statusCode,
        HttpStatus.methodNotAllowed,
      );
      expect(resolver.calls, isEmpty);
    });

    test('missing hook query values return 400', () async {
      final control = await StationControl.start(
        port: 0,
        token: 't',
        view: _sampleStatus,
      );
      addTearDown(control.dispose);

      expect(
        (await _get(
          control.url,
          '/hooks?worktree=/tmp/w',
          token: 't',
        )).statusCode,
        HttpStatus.badRequest,
      );
      expect(
        (await _get(
          control.url,
          '/hooks?event=pre-commit',
          token: 't',
        )).statusCode,
        HttpStatus.badRequest,
      );
    });

    test('outside hook worktree returns 404', () async {
      final fixture = await Directory.systemTemp.createTemp('hooks-http-');
      addTearDown(() => fixture.delete(recursive: true));
      final root = await Directory(p.join(fixture.path, 'root')).create();
      final outside = await Directory(p.join(fixture.path, 'outside')).create();
      final control = await _controlWith(
        HooksResolver(
          substations: [HookSubstation(substation: 'alpha', root: root.path)],
        ),
      );
      addTearDown(control.dispose);

      final response = await _hooksGet(control, outside.path);
      expect(response.statusCode, HttpStatus.notFound);
    });

    test('malformed hook YAML returns 500', () async {
      final fixture = await Directory.systemTemp.createTemp('hooks-http-');
      addTearDown(() => fixture.delete(recursive: true));
      final root = await Directory(p.join(fixture.path, 'root')).create();
      final worktree = await Directory(p.join(root.path, 'work')).create();
      final manifest = await File(
        p.join(fixture.path, 'asset.yaml'),
      ).writeAsString('hooks: not-a-list\n');
      final control = await _controlWith(
        HooksResolver(
          substations: [
            HookSubstation(
              substation: 'alpha',
              root: root.path,
              manifests: [HookManifest(source: 'asset', path: manifest.path)],
            ),
          ],
        ),
      );
      addTearDown(control.dispose);

      final response = await _hooksGet(control, worktree.path);
      expect(response.statusCode, HttpStatus.internalServerError);
    });

    test('owning substation with no matching hook returns 200 and an empty '
        'list', () async {
      final fixture = await Directory.systemTemp.createTemp('hooks-http-');
      addTearDown(() => fixture.delete(recursive: true));
      final root = await Directory(p.join(fixture.path, 'root')).create();
      final worktree = await Directory(p.join(root.path, 'work')).create();
      final manifest = await File(
        p.join(fixture.path, 'asset.yaml'),
      ).writeAsString('hooks: []\n');
      final control = await _controlWith(
        HooksResolver(
          substations: [
            HookSubstation(
              substation: 'alpha',
              root: root.path,
              manifests: [HookManifest(source: 'asset', path: manifest.path)],
            ),
          ],
        ),
      );
      addTearDown(control.dispose);

      final response = await _hooksGet(control, worktree.path);
      expect(response.statusCode, HttpStatus.ok);
      expect(jsonDecode(response.body), {
        'event': 'pre-commit',
        'worktree': worktree.path,
        'substation': 'alpha',
        'contributions': <Object?>[],
      });
    });
  });
}

Future<StationControl> _controlWith(HooksResolver resolver) =>
    StationControl.start(
      port: 0,
      token: 't',
      view: _sampleStatus,
      hooksResolver: resolver,
    );

Future<_Response> _hooksGet(StationControl control, String worktree) => _get(
  control.url,
  Uri(
    path: '/hooks',
    queryParameters: {'event': 'pre-commit', 'worktree': worktree},
  ).toString(),
  token: 't',
);

StationStatus _sampleStatus() => StationStatus(
  substation: 'tgdog',
  stateStore: null,
  workRoot: null,
  dryRun: true,
  pid: 1,
  startedAt: DateTime.utc(2026, 7, 2),
  version: 'test-vm',
  ready: 0,
  mounted: 0,
  liveSessions: 0,
  lastSyncAt: null,
);

Future<_Response> _get(String base, String path, {String? token}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('$base$path'));
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final response = await request.close();
    final body = await response.transform(const Utf8Decoder()).join();
    return _Response(
      response.statusCode,
      body,
      response.headers.value(HttpHeaders.contentTypeHeader),
    );
  } finally {
    client.close(force: true);
  }
}

Future<_Response> _post(String base, String path, {String? token}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$base$path'));
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final response = await request.close();
    final body = await response.transform(const Utf8Decoder()).join();
    return _Response(
      response.statusCode,
      body,
      response.headers.value(HttpHeaders.contentTypeHeader),
    );
  } finally {
    client.close(force: true);
  }
}

class _Response {
  _Response(this.statusCode, this.body, String? contentType)
    : headers = {if (contentType != null) 'content-type': contentType};

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

class _FakeHooksResolver extends HooksResolver {
  final List<({String event, String worktree})> calls = [];

  @override
  Future<HooksResponse> resolve({
    required String event,
    required String worktree,
  }) async {
    calls.add((event: event, worktree: worktree));
    return HooksResponse(
      event: event,
      worktree: worktree,
      substation: 'alpha',
      contributions: const [
        HookContribution(
          id: 'format',
          source: 'dart',
          run: 'dart format',
          select: '*.dart',
          mode: HookMode.fix,
          timeoutMs: 1000,
        ),
      ],
    );
  }
}
