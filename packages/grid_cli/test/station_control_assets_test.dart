import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/grid_cli.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('offline command and station route return the same records', () async {
    final temp = await Directory.systemTemp.createTemp('station-assets-');
    addTearDown(() => temp.delete(recursive: true));
    await File(p.join(temp.path, 'marker')).writeAsString('present');
    final resolver = _resolver(temp.path);
    final control = await _start(resolver);
    addTearDown(control.dispose);
    final commandOutput = <String>[];

    final code = await runAssetCatalog(
      resolver: resolver,
      substation: 'earth',
      json: true,
      out: commandOutput.add,
      err: fail,
    );
    final response = await _request(
      control.url,
      'GET',
      '/assets?substation=earth',
      token: 'token',
    );
    final direct = await resolver.resolve(substation: 'earth');

    expect(code, 0);
    expect(response.statusCode, HttpStatus.ok);
    expect(jsonDecode(commandOutput.single), direct.toJson());
    expect(jsonDecode(response.body), direct.toJson());
  });

  test('catalog request returns ordered unknown entries and counts', () async {
    final resolver = _resolver(Directory.systemTemp.path);
    final control = await _start(resolver);
    addTearDown(control.dispose);

    final response = await _request(
      control.url,
      'GET',
      '/assets',
      token: 'token',
    );

    expect(response.statusCode, HttpStatus.ok);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['substation'], isNull);
    expect(body['counts'], {
      'total': 2,
      'resolved': 0,
      'excluded': 0,
      'unknown': 2,
    });
    expect(
      [for (final asset in body['assets'] as List) asset['id']],
      ['guide', 'build'],
    );
  });

  test(
    'assets bearer and GET-only refusals invoke no resolver or command',
    () async {
      final resolver = _RecordingAssetResolver(Directory.systemTemp.path);
      final commands = _Commands();
      final control = await _start(resolver, commands: commands);
      addTearDown(control.dispose);

      expect(
        (await _request(control.url, 'GET', '/assets')).statusCode,
        HttpStatus.unauthorized,
      );
      for (final method in ['POST', 'PUT', 'PATCH', 'DELETE']) {
        expect(
          (await _request(
            control.url,
            method,
            '/assets?substation=earth',
            token: 'token',
          )).statusCode,
          HttpStatus.methodNotAllowed,
        );
      }
      expect(resolver.calls, isEmpty);
      expect(commands.calls, isEmpty);
    },
  );

  test('unknown substation propagates resolver 404 and error shape', () async {
    final control = await _start(_resolver(Directory.systemTemp.path));
    addTearDown(control.dispose);

    final response = await _request(
      control.url,
      'GET',
      '/assets?substation=missing',
      token: 'token',
    );

    expect(response.statusCode, HttpStatus.notFound);
    expect(jsonDecode(response.body), {'error': 'unknown substation: missing'});
  });

  test('blank substation propagates resolver 400', () async {
    final control = await _start(_resolver(Directory.systemTemp.path));
    addTearDown(control.dispose);

    final response = await _request(
      control.url,
      'GET',
      '/assets?substation=',
      token: 'token',
    );

    expect(response.statusCode, HttpStatus.badRequest);
    expect(jsonDecode(response.body), {
      'error': 'substation must be non-empty',
    });
  });
}

AssetCatalogResolver _resolver(String root) => AssetCatalogResolver(
  registry: _registry(),
  substations: [AssetCatalogSubstation(substation: 'earth', root: root)],
);

GridAssetRegistry _registry() => GridAssetRegistry([
  GridAssetPackDefinition(
    package: 'alpha_assets',
    assets: [
      const GridAssetDefinition(
        assetKey: AssetKey(
          package: 'alpha_assets',
          kind: AssetKind.resource,
          id: 'guide',
        ),
        description: 'Human guide',
        artifacts: [],
      ),
    ],
  ),
  GridAssetPackDefinition(
    package: 'beta_assets',
    assets: [
      const GridAssetDefinition(
        assetKey: AssetKey(
          package: 'beta_assets',
          kind: AssetKind.skill,
          id: 'build',
        ),
        description: 'Build procedure',
        artifacts: [],
        selector: RequiresPath('marker'),
      ),
    ],
  ),
]);

Future<StationControl> _start(
  AssetCatalogResolver resolver, {
  _Commands? commands,
}) => StationControl.start(
  port: 0,
  token: 'token',
  view: _status,
  commandHandler: commands ?? _Commands(),
  assetCatalogResolver: resolver,
);

StationStatus _status() => StationStatus(
  substation: 'test',
  stateStore: null,
  workRoot: null,
  dryRun: true,
  pid: 1,
  startedAt: DateTime.utc(2026, 9, 4),
  version: 'test',
  ready: 0,
  mounted: 0,
  liveSessions: 0,
  lastSyncAt: null,
);

Future<({int statusCode, String body})> _request(
  String base,
  String method,
  String path, {
  String? token,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse('$base$path'));
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final response = await request.close();
    return (
      statusCode: response.statusCode,
      body: await response.transform(const Utf8Decoder()).join(),
    );
  } finally {
    client.close(force: true);
  }
}

final class _RecordingAssetResolver extends AssetCatalogResolver {
  _RecordingAssetResolver(String root)
    : super(
        registry: _registry(),
        substations: [AssetCatalogSubstation(substation: 'earth', root: root)],
      );

  final calls = <String?>[];

  @override
  Future<AssetCatalogReport> resolve({String? substation}) {
    calls.add(substation);
    return super.resolve(substation: substation);
  }
}

final class _Commands implements GridCommandHandler {
  final calls = <GridCommandRequest>[];

  @override
  Future<GridCommandResult> call(GridCommandRequest request) async {
    calls.add(request);
    return const GridCommandResult.completed(message: 'ok');
  }
}
