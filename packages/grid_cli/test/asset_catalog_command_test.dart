import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

import 'support/recording_stdout.dart';

void main() {
  test(
    'human rendering is ordered and names state and deciding source',
    () async {
      final output = <String>[];

      final code = await runAssetCatalog(
        resolver: _resolver(Directory.systemTemp.path),
        out: output.add,
        err: fail,
      );

      expect(code, 0);
      expect(output, [
        'asset-catalog — substation=none total=2 resolved=0 excluded=0 '
            'unknown=2',
        'UNKNOWN  alpha_assets/resource/guide  visibility=private '
            'audience=human selector={"kind":"always_applies"} '
            'decided-by=nothing — Human guide',
        'UNKNOWN  beta_assets/skill/build  visibility=public audience=agent '
            'selector={"kind":"requires_path","path":"marker"} '
            'decided-by=nothing — Build procedure',
      ]);
    },
  );

  test('JSON mode emits exactly one report object', () async {
    final output = <String>[];
    final resolver = _resolver(Directory.systemTemp.path);
    final expected = await resolver.resolve(substation: 'earth');

    final code = await runAssetCatalog(
      resolver: resolver,
      substation: 'earth',
      json: true,
      out: output.add,
      err: fail,
    );

    expect(code, 0);
    expect(output, hasLength(1));
    expect(jsonDecode(output.single), expected.toJson());
  });

  test('AssetCatalogCommand parses --substation and --json offline', () async {
    final outConsumer = ByteConsumer();
    final errConsumer = ByteConsumer();
    final outSink = RecordingStdout(outConsumer);
    final errSink = RecordingStdout(errConsumer);
    final resolver = _resolver(Directory.systemTemp.path);
    final runner = CommandRunner<int>('grid', 'test')
      ..addCommand(AssetCatalogCommand(resolver: resolver));

    final code = await IOOverrides.runZoned(
      () => runner.run(['asset-catalog', '--substation', 'earth', '--json']),
      stdout: () => outSink,
      stderr: () => errSink,
    );
    await outSink.flush();
    await errSink.flush();

    expect(code, 0);
    expect(
      jsonDecode(outConsumer.text.trim()),
      (await resolver.resolve(substation: 'earth')).toJson(),
    );
    expect(errConsumer.text, isEmpty);
  });

  test('resolution refusals return 64 with one loud diagnostic', () async {
    final output = <String>[];
    final errors = <String>[];

    final code = await runAssetCatalog(
      resolver: const AssetCatalogResolver(),
      substation: 'missing',
      json: true,
      out: output.add,
      err: errors.add,
    );

    expect(code, 64);
    expect(output, isEmpty);
    expect(errors, ['grid asset-catalog: unknown substation: missing']);
  });

  test('--json is non-negatable', () async {
    final runner = CommandRunner<int>('grid', 'test')
      ..addCommand(AssetCatalogCommand(resolver: const AssetCatalogResolver()));

    await expectLater(
      runner.run(['asset-catalog', '--no-json']),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('Cannot negate option "--no-json"'),
        ),
      ),
    );
  });
}

AssetCatalogResolver _resolver(String root) => AssetCatalogResolver(
  registry: GridAssetRegistry([
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
          audience: AssetAudience.human,
          visibility: AssetVisibility.private,
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
  ]),
  substations: [AssetCatalogSubstation(substation: 'earth', root: root)],
);
