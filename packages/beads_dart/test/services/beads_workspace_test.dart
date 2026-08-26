import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('BeadsWorkspace.discover (hermetic temp dirs)', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('grid_ws_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    void writeBeads(Map<String, String> files) {
      final beads = Directory(p.join(tmp.path, '.beads'))..createSync();
      files.forEach((name, content) {
        File(p.join(beads.path, name)).writeAsStringSync(content);
      });
    }

    test(
      'passes workspace-scoped context to an injected endpoint resolver',
      () {
        writeBeads({
          'metadata.json':
              '{"dolt_mode":"server","dolt_database":"rezi","backend":"dolt"}',
        });
        const endpoint = DoltEndpoint(
          host: 'store.internal',
          port: 4407,
          database: 'rezi',
          user: 'reader',
          password: 'secret',
        );
        final resolver = _FakeEndpointResolver(
          const EndpointResolution.resolved(endpoint),
        );

        final ws = BeadsWorkspace.discover(
          start: tmp.path,
          endpointResolver: resolver,
        );

        expect(ws, isNotNull);
        expect(ws!.mode, DoltMode.unknown);
        expect(ws.endpoint, same(endpoint));
        expect(ws.endpointDiagnostic, isNull);
        expect(resolver.lastRequest!.root, tmp.absolute.path);
        expect(resolver.lastRequest!.beadsDir, p.join(tmp.path, '.beads'));
        expect(resolver.lastRequest!.doltMode, 'server');
        expect(resolver.lastRequest!.database, 'rezi');
      },
    );

    test('proxied-server mode resolves the PROXY endpoint from proxy.pid + '
        'the beads_dart secret', () {
      final doltDir = Directory(p.join(tmp.path, '.beads', 'dolt'))
        ..createSync(recursive: true);
      File(p.join(tmp.path, '.beads', 'metadata.json')).writeAsStringSync(
        '{"dolt_mode":"proxied-server","dolt_database":"tranquility",'
        '"backend":"dolt"}',
      );
      File(
        p.join(doltDir.path, 'proxy.pid'),
      ).writeAsStringSync('{"pid":4732,"port":65101,"upstream_id":"abc"}');
      File(
        p.join(doltDir.path, 'beads_dart.secret'),
      ).writeAsStringSync('s3cret\n');

      final ws = BeadsWorkspace.discover(start: tmp.path);
      expect(ws, isNotNull);
      expect(ws!.mode, DoltMode.proxiedServer);
      expect(ws.database, 'tranquility');
      expect(ws.endpoint, isNotNull);
      expect(ws.endpoint!.host, '127.0.0.1');
      expect(ws.endpoint!.port, 65101, reason: 'the PROXY port, not the child');
      expect(ws.endpoint!.user, 'beads_dart');
      expect(ws.endpoint!.password, 's3cret', reason: 'secret is trimmed');
      expect(ws.endpoint!.hasCredential, isTrue);
    });

    test('proxied-server mode honors the sidecar root_path (relative, '
        'resolved against .beads/ — the bd rule)', () {
      final beadsDir = Directory(p.join(tmp.path, '.beads'))..createSync();
      final proxyRoot = Directory(p.join(beadsDir.path, 'proxieddb'))
        ..createSync();
      File(p.join(beadsDir.path, 'metadata.json')).writeAsStringSync(
        '{"dolt_mode":"proxied-server","dolt_database":"tg"}',
      );
      File(
        p.join(beadsDir.path, 'proxied_server_client_info.json'),
      ).writeAsStringSync('{"root_path": "proxieddb", "idle_timeout": -1}');
      File(
        p.join(proxyRoot.path, 'proxy.pid'),
      ).writeAsStringSync('{"pid":9,"port":50001}');
      File(
        p.join(proxyRoot.path, 'beads_dart.secret'),
      ).writeAsStringSync('tgsecret');

      final ws = BeadsWorkspace.discover(start: tmp.path);
      expect(ws!.mode, DoltMode.proxiedServer);
      expect(ws.endpoint, isNotNull);
      expect(ws.endpoint!.port, 50001);
      expect(ws.endpoint!.password, 'tgsecret');
    });

    test('proxied-server mode honors an ABSOLUTE sidecar root_path '
        '(the worktree shape: sidecar points at the substation root)', () {
      final mainRoot = Directory(p.join(tmp.path, 'mainproxy'))..createSync();
      final beadsDir = Directory(p.join(tmp.path, '.beads'))..createSync();
      File(p.join(beadsDir.path, 'metadata.json')).writeAsStringSync(
        '{"dolt_mode":"proxied-server","dolt_database":"tg"}',
      );
      File(
        p.join(beadsDir.path, 'proxied_server_client_info.json'),
      ).writeAsStringSync('{"root_path": "${mainRoot.path}"}');
      File(
        p.join(mainRoot.path, 'proxy.pid'),
      ).writeAsStringSync('{"pid":9,"port":50002}');
      File(
        p.join(mainRoot.path, 'beads_dart.secret'),
      ).writeAsStringSync('wsecret');

      final ws = BeadsWorkspace.discover(start: tmp.path);
      expect(ws!.endpoint, isNotNull);
      expect(ws.endpoint!.port, 50002);
      expect(ws.endpoint!.password, 'wsecret');
    });

    group('proxied-server endpoint failures are observable', () {
      for (final sidecarCase in <String, ({String payload, String diagnostic})>{
        'malformed JSON': (
          payload: 'not json',
          diagnostic: 'is not readable JSON (FormatException).',
        ),
        'non-object JSON': (
          payload: '[]',
          diagnostic: 'must contain a JSON object.',
        ),
        'non-string root_path': (
          payload: '{"root_path":42}',
          diagnostic: 'root_path must be a string.',
        ),
      }.entries) {
        test('sidecar ${sidecarCase.key} has a distinct diagnostic', () {
          writeBeads({
            'metadata.json':
                '{"dolt_mode":"proxied-server","dolt_database":"tg"}',
            'proxied_server_client_info.json': sidecarCase.value.payload,
          });
          final sidecar = File(
            p.join(tmp.path, '.beads', 'proxied_server_client_info.json'),
          );

          final ws = BeadsWorkspace.discover(start: tmp.path)!;

          expect(ws.endpoint, isNull);
          expect(
            ws.endpointDiagnostic,
            'Cannot resolve proxied-server SQL endpoint: ${sidecar.path} '
            '${sidecarCase.value.diagnostic}',
          );
        });
      }

      test('missing proxy.pid has a distinct diagnostic', () {
        writeBeads({
          'metadata.json':
              '{"dolt_mode":"proxied-server","dolt_database":"tg"}',
        });
        final pidFile = File(p.join(tmp.path, '.beads', 'dolt', 'proxy.pid'));

        final ws = BeadsWorkspace.discover(start: tmp.path)!;

        expect(ws.endpoint, isNull);
        expect(
          ws.endpointDiagnostic,
          'Cannot resolve proxied-server SQL endpoint: ${pidFile.path} is '
          "missing; start bd's proxy for this workspace.",
        );
      });

      for (final pidCase in <String, ({String payload, String diagnostic})>{
        'non-object JSON': (
          payload: '[]',
          diagnostic: 'must contain a JSON object.',
        ),
        'out-of-range port': (
          payload: '{"pid":1,"port":65536}',
          diagnostic: 'has no TCP port between 1 and 65535.',
        ),
      }.entries) {
        test('proxy.pid ${pidCase.key} has a distinct diagnostic', () {
          writeBeads({
            'metadata.json':
                '{"dolt_mode":"proxied-server","dolt_database":"tg"}',
          });
          final doltDir = Directory(p.join(tmp.path, '.beads', 'dolt'))
            ..createSync();
          final pidFile = File(p.join(doltDir.path, 'proxy.pid'))
            ..writeAsStringSync(pidCase.value.payload);

          final ws = BeadsWorkspace.discover(start: tmp.path)!;

          expect(ws.endpoint, isNull);
          expect(
            ws.endpointDiagnostic,
            'Cannot resolve proxied-server SQL endpoint: ${pidFile.path} '
            '${pidCase.value.diagnostic}',
          );
        });
      }
    });

    for (final secretCase in <String, String?>{
      'missing': null,
      'empty': '\n',
    }.entries) {
      test('proxied-server ${secretCase.key} secret is observable', () {
        final doltDir = Directory(p.join(tmp.path, '.beads', 'dolt'))
          ..createSync(recursive: true);
        File(p.join(tmp.path, '.beads', 'metadata.json')).writeAsStringSync(
          '{"dolt_mode":"proxied-server","dolt_database":"tranquility"}',
        );
        File(
          p.join(doltDir.path, 'proxy.pid'),
        ).writeAsStringSync('{"pid":1,"port":65101}');
        final secret = secretCase.value;
        if (secret != null) {
          File(
            p.join(doltDir.path, 'beads_dart.secret'),
          ).writeAsStringSync(secret);
        }

        final ws = BeadsWorkspace.discover(start: tmp.path)!;
        expect(ws.endpoint, isNull);
        expect(ws.endpointDiagnostic, contains('beads_dart.secret'));
        expect(ws.endpointDiagnostic, contains('0600'));
      });
    }

    test('malformed proxy.pid exposes a path-specific diagnostic', () {
      final doltDir = Directory(p.join(tmp.path, '.beads', 'dolt'))
        ..createSync(recursive: true);
      File(p.join(tmp.path, '.beads', 'metadata.json')).writeAsStringSync(
        '{"dolt_mode":"proxied-server","dolt_database":"tranquility"}',
      );
      final pidFile = File(p.join(doltDir.path, 'proxy.pid'))
        ..writeAsStringSync('not json');
      File(p.join(doltDir.path, 'beads_dart.secret')).writeAsStringSync('x');

      final ws = BeadsWorkspace.discover(start: tmp.path)!;
      expect(ws.endpoint, isNull);
      expect(ws.endpointDiagnostic, contains(pidFile.path));
      expect(ws.endpointDiagnostic, contains('readable JSON'));
    });

    for (final modeCase in <String, DoltMode>{
      'direct': DoltMode.direct,
      'shared-server': DoltMode.unknown,
    }.entries) {
      test('${modeCase.key} mode exposes its CLI-fallback diagnostic', () {
        writeBeads({
          'metadata.json':
              '{"dolt_mode":"${modeCase.key}","dolt_database":"tg"}',
        });

        final ws = BeadsWorkspace.discover(start: tmp.path)!;
        expect(ws.mode, modeCase.value);
        expect(ws.endpoint, isNull);
        expect(ws.endpointDiagnostic, contains(modeCase.key));
        expect(ws.endpointDiagnostic, contains('bd CLI read path'));
      });
    }

    test('returns null when no .beads/ exists anywhere up-tree', () {
      final isolated = Directory.systemTemp.createTempSync('grid_none_');
      addTearDown(() => isolated.deleteSync(recursive: true));
      expect(BeadsWorkspace.discover(start: isolated.path), isNull);
    });
  });
}

final class _FakeEndpointResolver implements EndpointResolver {
  _FakeEndpointResolver(this.resolution);

  final EndpointResolution resolution;
  EndpointResolutionRequest? lastRequest;

  @override
  EndpointResolution resolve(EndpointResolutionRequest request) {
    lastRequest = request;
    return resolution;
  }
}
