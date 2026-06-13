import 'package:grid_reconciler/src/gates/condition_env.dart';
import 'package:test/test.dart';

import 'support/fake_process_runner.dart';

/// The subprocess env contract — every var with its exact name + value
/// (gates-exec.md §1, conformance-gate-tests §3.3 `TestConditionEnvEnviron*`).
/// Built over the injected seams (no real `PATH`/`os.Getenv`).
void main() {
  // A fixed lookPath: bd/gc resolve to /tools, the rest miss.
  final lookPath = fakeLookPath(const <String, String>{
    'bd': '/tools',
    'gc': '/tools',
  });

  Map<String, String> environ(
    ConditionEnv env, {
    Map<String, String> ambient = const <String, String>{},
    String tempDir = '/tmp',
  }) => env.environ(ambient: ambient, lookPathDir: lookPath, tempDir: tempDir);

  group('always-present whitelist', () {
    final env = environ(
      const ConditionEnv(
        beadId: 'bead-123',
        iteration: 3,
        cityPath: '/home/test/city',
        wispId: 'wisp-456',
        docPath: '/docs/review.md',
        moleculeDir: '/home/test/city/.gc/molecules/root-xyz',
        artifactDir: '/tmp/artifacts',
        iterationDurationMs: 1500,
        cumulativeDurationMs: 4500,
        maxIterations: 10,
        agentVerdict: 'approve',
        agentProvider: 'anthropic',
        agentModel: 'claude-3',
      ),
    );

    test('PATH is conditionPATH() with the resolved tool dir first', () {
      // /tools (bd, deduped) then SafePATH.
      expect(env['PATH'], '/tools:/usr/local/bin:/usr/bin:/bin');
    });

    test('HOME = cityPath (sandbox), TMPDIR = tempDir', () {
      expect(env['HOME'], '/home/test/city');
      expect(env['TMPDIR'], '/tmp');
    });

    test('BEADS_DIR = <cityPath>/.beads', () {
      expect(env['BEADS_DIR'], '/home/test/city/.beads');
    });

    test('convergence identity vars', () {
      expect(env['GC_BEAD_ID'], 'bead-123');
      expect(env['GC_ITERATION'], '3');
      expect(env['GC_WISP_ID'], 'wisp-456');
      expect(env['GC_MAX_ITERATIONS'], '10');
    });

    test('duration vars are decimal ms', () {
      expect(env['GC_ITERATION_DURATION_MS'], '1500');
      expect(env['GC_CUMULATIVE_DURATION_MS'], '4500');
    });

    test('city + runtime-dir vars', () {
      expect(env['GC_CITY'], '/home/test/city');
      expect(env['GC_CITY_PATH'], '/home/test/city');
      expect(env['GC_CITY_RUNTIME_DIR'], '/home/test/city/.gc/runtime');
    });

    test(
      'GC_CONTROL_DISPATCHER_TRACE_DEFAULT companion var (runtime.go:130)',
      () {
        // Canonical reconciler path: no ambient anchor → trace under
        // <cityPath>/.gc/runtime/control-dispatcher-trace.log.
        expect(
          env['GC_CONTROL_DISPATCHER_TRACE_DEFAULT'],
          '/home/test/city/.gc/runtime/control-dispatcher-trace.log',
        );
      },
    );

    test(
      'city runtime quad keeps gc append order (gates-exec.md §1a 11-14)',
      () {
        // The slice order is the de-facto fixture contract (§1e ⚠ordering):
        // GC_CITY, GC_CITY_PATH, GC_CITY_RUNTIME_DIR,
        // GC_CONTROL_DISPATCHER_TRACE_DEFAULT, contiguous and in this order.
        final keys = env.keys.toList();
        expect(
          keys.sublist(
            keys.indexOf('GC_CITY'),
            keys.indexOf('GC_CONTROL_DISPATCHER_TRACE_DEFAULT') + 1,
          ),
          <String>[
            'GC_CITY',
            'GC_CITY_PATH',
            'GC_CITY_RUNTIME_DIR',
            'GC_CONTROL_DISPATCHER_TRACE_DEFAULT',
          ],
        );
      },
    );

    test('optional vars present when non-empty', () {
      expect(env['GC_DOC_PATH'], '/docs/review.md');
      expect(env['GC_AGENT_VERDICT'], 'approve');
      expect(env['GC_AGENT_PROVIDER'], 'anthropic');
      expect(env['GC_AGENT_MODEL'], 'claude-3');
      expect(env['GC_MOLECULE_DIR'], '/home/test/city/.gc/molecules/root-xyz');
      expect(env['GC_ARTIFACT_DIR'], '/tmp/artifacts');
    });

    test('GC_CONTROLLER_TOKEN is never present (security sandbox)', () {
      expect(env.containsKey('GC_CONTROLLER_TOKEN'), isFalse);
    });
  });

  group('absent ≠ empty (TestConditionEnvEnvironOptionalEmpty)', () {
    final env = environ(
      const ConditionEnv(
        beadId: 'bead-789',
        iteration: 1,
        cityPath: '/city',
        wispId: 'wisp-abc',
      ),
    );

    test('empty optionals are OMITTED, not emitted as empty strings', () {
      for (final key in const <String>[
        'GC_DOC_PATH',
        'GC_AGENT_VERDICT',
        'GC_AGENT_PROVIDER',
        'GC_AGENT_MODEL',
        'GC_MOLECULE_DIR',
        'GC_ARTIFACT_DIR',
        'GC_STORE_PATH',
        'GC_WORK_DIR',
      ]) {
        expect(env.containsKey(key), isFalse, reason: '$key must be absent');
      }
    });

    test('GC_BEAD_ID and PATH still present', () {
      expect(env['GC_BEAD_ID'], 'bead-789');
      expect(env['PATH'], isNotEmpty);
    });
  });

  group('HOME sandbox (§5 gap 7)', () {
    test('empty cityPath → HOME = tempDir', () {
      final env = environ(
        const ConditionEnv(beadId: 'b', wispId: 'w'),
        tempDir: '/var/folders/zz',
      );
      expect(env['HOME'], '/var/folders/zz');
    });
  });

  group(
    'StorePath override (TestConditionEnvEnvironUsesStorePathForBeadsDir)',
    () {
      final env = environ(
        const ConditionEnv(
          beadId: 'bead-store',
          iteration: 1,
          cityPath: '/city',
          storePath: '/rig',
        ),
      );

      test('BEADS_DIR uses StorePath, GC_CITY stays the city', () {
        expect(env['BEADS_DIR'], '/rig/.beads');
        expect(env['GC_STORE_PATH'], '/rig');
        expect(env['GC_CITY'], '/city');
      });
    },
  );

  group('GC_WORK_DIR emission (§5 gap 8)', () {
    test('WorkDir set → GC_WORK_DIR present', () {
      final env = environ(
        const ConditionEnv(
          beadId: 'b',
          cityPath: '/city',
          wispId: 'w',
          workDir: '/city/work',
        ),
      );
      expect(env['GC_WORK_DIR'], '/city/work');
    });
  });

  group('working-directory precedence (WorkDir > StorePath > CityPath)', () {
    test('all three set → WorkDir wins (§5 gap 9)', () {
      const env = ConditionEnv(
        cityPath: '/city',
        storePath: '/rig',
        workDir: '/work',
      );
      expect(env.workingDirectory, '/work');
    });

    test('storePath set, no workDir → StorePath', () {
      const env = ConditionEnv(cityPath: '/city', storePath: '/rig');
      expect(env.workingDirectory, '/rig');
    });

    test('only cityPath → CityPath', () {
      const env = ConditionEnv(cityPath: '/city');
      expect(env.workingDirectory, '/city');
    });
  });

  group(
    'Dolt/Beads ambient passthrough (TestConditionEnvEnvironPreservesDolt)',
    () {
      test('connection vars flow from ambient to child', () {
        final env = environ(
          const ConditionEnv(beadId: 'b', cityPath: '/city', wispId: 'w'),
          ambient: const <String, String>{
            'BEADS_DOLT_SERVER_PORT': '33061',
            'GC_DOLT_HOST': '127.0.0.1',
            'GC_DOLT_PASSWORD': 'secret',
          },
        );
        expect(env['BEADS_DOLT_SERVER_PORT'], '33061');
        expect(env['GC_DOLT_HOST'], '127.0.0.1');
        expect(env['GC_DOLT_PASSWORD'], 'secret');
      });

      test('unset ambient connection vars are not emitted', () {
        final env = environ(
          const ConditionEnv(beadId: 'b', cityPath: '/city', wispId: 'w'),
        );
        expect(env.containsKey('GC_DOLT_PASSWORD'), isFalse);
      });

      test('GC_INTEGRATION_REAL_BD passes through when ambient-set', () {
        final env = environ(
          const ConditionEnv(beadId: 'b', cityPath: '/city', wispId: 'w'),
          ambient: const <String, String>{
            'GC_INTEGRATION_REAL_BD': '/tmp/test-real-bd',
          },
        );
        expect(env['GC_INTEGRATION_REAL_BD'], '/tmp/test-real-bd');
      });
    },
  );

  group('conditionPATH (TestConditionPATHUsesResolvedToolDirs, §5 gap 13)', () {
    test('resolved tool dir comes first, deduped, then SafePATH', () {
      final path = conditionPath(
        fakeLookPath(const <String, String>{'bd': '/tools', 'gc': '/tools'}),
      );
      expect(path, '/tools:/usr/local/bin:/usr/bin:/bin');
    });

    test('no tools on PATH → result == SafePATH', () {
      final path = conditionPath(fakeLookPath(const <String, String>{}));
      expect(path, safePath);
    });

    test('a tool dir that is also in SafePATH appears once (dedup)', () {
      final path = conditionPath(
        fakeLookPath(const <String, String>{'bd': '/usr/bin'}),
      );
      expect(path, '/usr/bin:/usr/local/bin:/bin');
    });
  });
}
