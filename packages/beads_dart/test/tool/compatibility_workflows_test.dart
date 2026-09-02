import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final packageDir = Directory.current.absolute;
  final root = packageDir.parent.parent;
  File repoFile(String path) => File('${root.path}/$path');
  String read(String path) => repoFile(path).readAsStringSync();
  dynamic workflow(String path) => loadYaml(read(path));

  test('shared runner contract', () {
    final runner = read('tool/bd_compatibility/run.sh');
    const selected = [
      'test/integration/cross_workspace_probe_test.dart',
      'test/integration/no_sql_no_hooks_test.dart',
      'test/integration/reactive_lifecycle_test.dart',
      'test/integration/sql_cli_equivalence_test.dart',
      'test/integration/wisp_snapshot_test.dart',
    ];
    for (final path in selected) {
      expect(runner, contains(path));
    }
    expect(runner, isNot(contains('ready_work_differential_test.dart')));
    expect(runner, contains('upstream_protocol_replay_test.dart'));
    expect(runner, contains('BD_PROTOCOL_ROOT='));
    expect(runner, contains('BD_JSON_ENVELOPE=1'));
    expect(runner, contains('BD_NON_INTERACTIVE=1'));
    expect(runner, contains('[[ \$# -eq 2 ]]'));
    expect(runner, contains('[[ "\$upstream_dir" = /*'));
    expect(runner, contains('[[ "\$bd_bin" = /* && -x'));

    final policy = loadYaml(read('packages/beads_dart/bd_compatibility.yaml'));
    final forkPatches = policy['fork_patches'] as YamlMap;
    final patch = forkPatches['graph_apply_parent_cycle_skip'] as YamlMap;
    expect(patch['repository'], 'nicholasspencer/beads');
    expect(patch['base_sha'], 'f9fe4ef2a6d3d90b52f1b62df15a5b2c0833c82b');
    expect(patch['ref'], 'grid-v1.0.5-graph-apply-parent-cycle-skip.1');
    expect(
      patch['fixture_set'],
      '2026-09-01-bd-grid-v1.0.5-graph-apply-parent-cycle-skip.1',
    );
    final receipt = read(patch['resolved_sha_receipt'] as String);
    expect(receipt, contains('grid-v1.0.5-graph-apply-parent-cycle-skip.1'));
    expect(
      RegExp(r'resolved SHA:\*\* `[0-9a-f]{40}`').hasMatch(receipt),
      isTrue,
    );
    expect(receipt, contains('BD_JSON_ENVELOPE=1'));
    expect(policy['floor'], 'v1.0.5');
    // No release embargo: a publish is never gated on what bd has RELEASED,
    // because this package ships candidates against bd's candidates.
    expect(policy, isNot(contains('day_one_wait_through')));
  });

  test('drift workflow contract', () {
    final yaml = workflow('.github/workflows/bd-drift.yml') as YamlMap;
    final source = read('.github/workflows/bd-drift.yml');
    expect(yaml['on']['schedule'].single['cron'], '17 9 * * *');
    expect(yaml['on'], contains('workflow_dispatch'));
    expect(yaml['permissions']['contents'], 'read');
    expect(yaml['concurrency']['group'], 'bd-drift');
    expect(yaml['jobs'].length, 1);
    expect(yaml['jobs']['compatibility']['runs-on'], 'ubuntu-latest');
    expect(source, contains('repository: gastownhall/beads'));
    expect(source, contains('ref: main'));
    expect(source, contains('id: upstream'));
    expect(source, contains('rev-parse HEAD'));
    expect(source, contains('subosito/flutter-action@v2'));
    expect(source, contains('actions/setup-go@v5'));
    expect(source, contains('releases/latest/download/install.sh | sudo bash'));
    expect(source, contains('CGO_ENABLED=1 go build -tags gms_pure_go'));
    expect(source, contains('tool/bd_compatibility/run.sh'));
    expect(source, contains("failure() && github.event_name == 'schedule'"));
    expect(source, contains('steps.upstream.outputs.upstream_sha'));
    expect(RegExp('BEADS_DOLT_PASSWORD').allMatches(source).length, 2);
  });

  group('drift filing', () {
    late Directory temp;
    late File calls;
    late File fake;
    final sha = 'a' * 40;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('bd-drift-test-');
      calls = File('${temp.path}/calls.json');
      fake = File('${temp.path}/bd')
        ..writeAsStringSync('''#!/usr/bin/env bash
printf '%s\n%s\n' "\${BD_JSON_ENVELOPE:-}" "\${BD_NON_INTERACTIVE:-}" > "\$CALLS_FILE"
for arg in "\$@"; do
  printf '%s\n' "\$arg" >> "\$CALLS_FILE"
done
''')
        ..setLastModifiedSync(DateTime.now());
      Process.runSync('chmod', ['+x', fake.path]);
    });

    tearDown(() => temp.deleteSync(recursive: true));

    Future<ProcessResult> invoke(String candidate, String url) => Process.run(
      repoFile('tool/bd_compatibility/file_drift.sh').path,
      [candidate, url],
      environment: {
        ...Platform.environment,
        'BD_BIN': fake.path,
        'CALLS_FILE': calls.path,
      },
    );

    test('creates one ready work item', () async {
      final result = await invoke(sha, 'https://ci.example/runs/7');
      expect(result.exitCode, 0);
      final record = calls.readAsLinesSync();
      expect(record[0], '1');
      expect(record[1], '1');
      final argv = record.skip(2).toList();
      expect(argv.first, 'create');
      expect(argv, containsAllInOrder(['--type', 'task', '--priority', '1']));
      expect(argv, containsAllInOrder(['--status', 'open']));
      expect(argv, containsAllInOrder(['--labels', 'bd-drift,ready']));
      expect(argv, containsAllInOrder(['--external-ref', 'bd-upstream:$sha']));
      expect(
        argv,
        containsAllInOrder(['--actor', 'grid-controller', '--json']),
      );
      expect(argv.join(' '), contains('https://ci.example/runs/7'));
    });

    test('rejects malformed SHA without calling bd', () async {
      final result = await invoke('ABC', 'https://ci.example/runs/7');
      expect(result.exitCode, 64);
      expect(calls.existsSync(), isFalse);
    });

    test('rejects non-HTTPS URL without calling bd', () async {
      final result = await invoke(sha, 'http://ci.example/runs/7');
      expect(result.exitCode, 64);
      expect(calls.existsSync(), isFalse);
    });
  });

  group('release gate', () {
    List<String> refs({
      required String package,
      required String floor,
      required String latest,
    }) {
      if (package != 'beads_dart') return ['none'];
      final semver = RegExp(r'^v[0-9]+\.[0-9]+\.[0-9]+$');
      if (![floor, latest].every(semver.hasMatch)) {
        throw const FormatException('malformed semver');
      }
      // The matrix is the whole gate: floor + upstream's latest release. No
      // comparison between them can refuse a publish.
      return {floor, latest}.toList()..sort();
    }

    test('enforces release policy variants', () {
      expect(
        refs(package: 'beads_dart', floor: 'v1.0.5', latest: 'v1.3.0'),
        ['v1.0.5', 'v1.3.0'],
      );
      expect(
        refs(package: 'beads_dart', floor: 'v1.3.0', latest: 'v1.3.0'),
        ['v1.3.0'],
      );
      expect(
        () => refs(package: 'beads_dart', floor: '1.0.5', latest: 'v1.3.0'),
        throwsFormatException,
      );
      // An upstream latest OLDER than anything this package targets is not a
      // refusal — it is just the other end of the matrix. This is the case the
      // removed embargo turned into a failed release.
      for (final latest in ['v1.1.0', 'v1.2.2']) {
        expect(
          refs(package: 'beads_dart', floor: 'v1.0.5', latest: latest),
          ['v1.0.5', latest],
        );
      }
      expect(refs(package: 'grid_cli', floor: 'bad', latest: 'bad'), ['none']);
    });

    test('has compatibility matrix before publication', () {
      final yaml = workflow('.github/workflows/publish.yml') as YamlMap;
      final source = read('.github/workflows/publish.yml');
      expect(yaml['jobs']['parse']['outputs'], contains('bd_refs'));
      expect(yaml['jobs'], contains('bd-compatibility'));
      expect(yaml['jobs']['bd-compatibility']['strategy']['fail-fast'], false);
      expect(source, contains('fromJSON(needs.parse.outputs.bd_refs)'));
      expect(source, contains('repos/gastownhall/beads/releases/latest'));
      expect(source, contains('[\$floor,\$latest]|unique'));
      expect(source, isNot(contains('day_one_wait_through')));
      expect(source, contains('There is NO release embargo here'));
      expect(yaml['jobs']['publish']['needs'], ['parse', 'bd-compatibility']);
      // The bd-compatibility job gates at the JOB level (a declared action that
      // fails to resolve kills a job at setup regardless of step-level ifs), and
      // the publish job must tolerate the resulting skip for non-beads_dart tags.
      expect(
        yaml['jobs']['bd-compatibility']['if'],
        contains("needs.parse.outputs.package == 'beads_dart'"),
      );
      expect(source, contains("needs.bd-compatibility.result == 'skipped'"));
    });
  });

  test('hermetic rail contract', () {
    final rails =
        read('.github/workflows/bd-drift.yml') +
        read('.github/workflows/publish.yml');
    for (final forbidden in [
      'BEADS_DB',
      'DOLT_ENDPOINT',
      'FLEET_PATH',
      'DATABASE_URL',
    ]) {
      expect(rails, isNot(contains(forbidden)));
    }
    expect(
      read('tool/bd_compatibility/run.sh'),
      contains('dirname "\$bd_bin"'),
    );
    expect(rails, contains('setup-dolt'));
  });

  test('version policy documentation', () {
    final skill = read('.claude/skills/grid-porting/SKILL.md');
    final fixtures = read('.claude/skills/grid-porting/references/fixtures.md');
    expect(skill, contains('## The Version Policy'));
    expect(skill, contains('forbids a repository-wide bd pin'));
    expect(skill, contains('`--ref <main-or-tag>`'));
    expect(skill, contains('40-character SHA'));
    expect(fixtures, contains('independently resolved 40-character SHA'));
    expect(fixtures, contains('executable resolved from the requested ref'));
    for (final legacy in [
      'owns the version-pin record',
      'One recorded pin',
      'The Pinned Upstream',
    ]) {
      expect('$skill\n$fixtures', isNot(contains(legacy)));
    }
  });

  test('ADR-0002 supersession', () {
    final adr = read(
      'docs/adr/ADR-0002-package-topology-and-domain-projections.md',
    );
    expect(adr, contains('pinned against bd 1.0.5'));
    expect(adr, contains('Supersession stamp 2026-08-08'));
    expect(adr, contains('A54'));
    expect(adr, contains('fulfills and supersedes only'));
    expect(
      adr,
      contains('ADR-0001 Decision 4 shape-probe mechanism remains Pending'),
    );
    expect(adr, contains('scheduled drift CI'));
    expect(adr, contains('release gating'));
    expect(adr, contains('docs/SCRATCH-bd-repin.md'));
    expect(adr, contains('packages/beads_dart/bd_compatibility.yaml'));
  });
}
