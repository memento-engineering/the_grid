import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/src/station_control.dart';
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
  });
}

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
