import 'dart:async';

import 'package:grid_cli/src/code_run_command.dart';
import 'package:grid_cli/src/run_command.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// Offline proofs for `grid run` (M3-BUILD-ORDER Track 7) — Fakes, not mocks,
/// no live state, no real `claude`, no real `git`, NO `bd` writes to the live
/// `tg` workspace. The DoD this file locks:
///
///  1. **one source of truth** — the `--substation`/`--owner` allow-set flows to BOTH
///     the M2 `OwnsSubstations` convergence gate AND the dispatch
///     `BeadOwnershipPredicate` from one shared `Set<String>` (they cannot
///     drift);
///  2. **--dry-run smoke** — a dry run with an OWNED ready bead performs ZERO
///     spawns and ZERO bd writes (observe-only), the safe default;
///  3. **--dry-run is the safe default** — flag parsing defaults to dry-run; a
///     non-dry run with no root is refused;
///  4. **provider default** — `--provider` defaults to subprocess.
void main() {
  group('CodeRunCommand flag parsing (via the StationRunCommand base)', () {
    test('--dry-run is the SAFE DEFAULT (true when unspecified)', () {
      final cmd = CodeRunCommand();
      final parsed = cmd.argParser.parse(['--substation', 'tgdog']);
      expect(parsed.flag('dry-run'), isTrue);
    });

    test('--provider defaults to subprocess', () {
      final cmd = CodeRunCommand();
      final parsed = cmd.argParser.parse(['--substation', 'tgdog']);
      expect(parsed.option('provider'), 'subprocess');
      expect(
        RuntimeProviderKind.parse(parsed.option('provider')),
        RuntimeProviderKind.subprocess,
      );
    });

    test('--substation and --owner both feed the one allow-set', () {
      final cmd = CodeRunCommand();
      final parsed = cmd.argParser.parse([
        '--substation',
        'tgdog',
        '--owner',
        'other',
      ]);
      final substations = <String>{
        ...parsed.multiOption('substation'),
        ...parsed.multiOption('owner'),
      };
      expect(substations, {'tgdog', 'other'});
    });

    test('--no-dry-run is the explicit live-arm opt-in', () {
      final cmd = CodeRunCommand();
      final parsed = cmd.argParser.parse(['--substation', 'tgdog', '--no-dry-run']);
      expect(parsed.flag('dry-run'), isFalse);
    });

    test('the CODE ASSET carries the opinion, not the framework: the trio + a '
        'git-SourceControl servicesFor live on CodeRunCommand', () {
      final cmd = CodeRunCommand();
      // The trio is the command's (the composer requires it, defaults nothing).
      expect(cmd.resolver, isNotNull);
      expect(cmd.registry.formula('code'), isNotNull,
          reason: 'the code registry (agent/review/land) rides the command');
      // servicesFor builds the git SourceControl from the live wiring.
      final services = cmd.servicesFor!((
        git: StationGitService(
          runner: FakeGitRunner(),
          prOpener: _FakePrOpener(),
        ),
        workRoot: const RootCheckout(
          path: '/tmp/r',
          defaultBranch: 'main',
          substation: 'tgdog',
        ),
        gitOps: null,
        prOpener: null,
      ));
      expect(services.sourceControl, isNotNull,
          reason: 'the code asset supplies provisioning source control');
      expect(services.sourceControl!.canLand, isFalse,
          reason: 'land ops null (not armed) → commit-only posture');
    });
  });

  group('runGrid live-arm gating (no live state)', () {
    test('a non-dry run with no --root is refused (exit 64, no composition)',
        () async {
      final errs = <String>[];
      final code = await runGrid(
        substations: {'tgdog'},
        dryRun: false, // ask for the LIVE arm…
        // …but supply no root → must be refused before any composition.
        out: (_) {},
        err: errs.add,
        runForever: false,
      );
      expect(code, 64);
      expect(errs.join('\n'), contains('requires --root'));
    });

    test('an empty allow-set is refused (exit 64)', () async {
      final errs = <String>[];
      final code = await runGrid(
        substations: const {},
        dryRun: true,
        out: (_) {},
        err: errs.add,
        runForever: false,
      );
      expect(code, 64);
      expect(errs.join('\n'), contains('--substation/--owner is required'));
    });

    test('a live run with --root but NO --state-workspace is refused (exit 64) '
        '— sessions must never default into the read --workspace', () async {
      final errs = <String>[];
      final code = await runGrid(
        substations: {'genesis'},
        dryRun: false,
        rootPath: '/tmp/some-root', // root supplied → past the root guard…
        // …but no --state-workspace → must be refused before composition.
        out: (_) {},
        err: errs.add,
        runForever: false,
      );
      expect(code, 64);
      expect(errs.join('\n'), contains('requires --state-workspace'));
    });
  });

  group('composeRun — one source of truth for ownership', () {
    test('the SAME allow-set feeds both OwnsSubstations and BeadOwnershipPredicate',
        () async {
      final h = _Harness(substations: {'tgdog'}, dryRun: true);
      final wiring = h.compose();
      addTearDown(() async {
        await wiring.dispose();
        await h.dispose();
      });

      // Both gates accept the owned rig and reject a foreign one — the parity
      // that proves they were seeded from the identical allow-set.
      final owned = _convergence('tgdog-c1', substation: 'tgdog');
      final foreign = _convergence('gascity-c1', substation: 'gascity');
      expect(wiring.ownsSubstations.owns(owned), isTrue);
      expect(wiring.ownsSubstations.owns(foreign), isFalse);

      expect(wiring.beadOwnership.owns(Bead(id: 'tgdog-w1', title: 't')), isTrue);
      expect(
        wiring.beadOwnership.owns(Bead(id: 'gascity-w1', title: 't')),
        isFalse,
      );

      // The shared set carries exactly the configured substations.
      expect(wiring.allowSet, {'tgdog'});
      expect(wiring.beadOwnership.substations, {'tgdog'});
    });
  });

  group('composeRun — --dry-run smoke (ZERO spawns, ZERO bd writes)', () {
    test('an OWNED ready bead is observed read-only: no spawn, no bd write',
        () async {
      final h = _Harness(substations: {'tgdog'}, dryRun: true);
      final wiring = h.compose();
      addTearDown(() async {
        await wiring.dispose();
        await h.dispose();
      });

      // Stage an OWNED ready bead, then start the loop.
      h.source.addReady(Bead(id: 'tgdog-work1', title: 'do the thing'));
      await wiring.start();
      await _settle();

      // The dispatcher SAW it (read-only observation), but did NOT dispatch it.
      expect(wiring.dispatcher.inFlight, 0, reason: 'dry-run spawns nothing');

      // ZERO spawns.
      expect(h.provider.starts, isEmpty, reason: 'dry-run starts no agent');

      // ZERO bd writes — the RecordingBdRunner saw no `bd` invocation at all.
      expect(h.bdRunner.calls, isEmpty, reason: 'dry-run writes no bead');

      // ZERO git worktree adds.
      expect(
        h.gitRunner.calls.where(
          (c) => c.length >= 2 && c[0] == 'worktree' && c[1] == 'add',
        ),
        isEmpty,
      );
    });

    test('a non-owned ready bead is also never dispatched (read-only)',
        () async {
      final h = _Harness(substations: {'tgdog'}, dryRun: true);
      final wiring = h.compose();
      addTearDown(() async {
        await wiring.dispose();
        await h.dispose();
      });

      h.source.addReady(Bead(id: 'gascity-x', title: 'gc work'));
      await wiring.start();
      await _settle();

      expect(wiring.dispatcher.inFlight, 0);
      expect(wiring.dispatcher.observedNonOwned, contains('gascity-x'));
      expect(h.provider.starts, isEmpty);
      expect(h.bdRunner.calls, isEmpty);
    });

    test('dry-run wires the reconciler observe-only (no convergence writes)',
        () async {
      final h = _Harness(substations: {'tgdog'}, dryRun: true);
      final wiring = h.compose();
      addTearDown(() async {
        await wiring.dispose();
        await h.dispose();
      });

      await wiring.start();
      await _settle();

      // The reconciler ran its startup recovery pass but actuated nothing
      // (OwnsNothing gate in dry-run); the bd runner saw no write.
      expect(h.bdRunner.calls, isEmpty);
    });
  });

  group('buildAgentConfig — the live dogfood prompt contract (A36)', () {
    DispatchRequest req(Bead bead) => DispatchRequest(
          bead: bead,
          substation: 'genesis',
          sessionBeadId: 'genesis-sess1',
          worktree: const BeadWorktree(
            beadId: 'genesis-q8h',
            path: '/clone/.grid/worktrees/genesis/genesis-q8h',
            branch: 'grid/genesis-q8h',
          ),
        );

    test('carries the full bead (not title-only) + the local-first trailer', () {
      final cfg = buildAgentConfig(
        req(Bead(
          id: 'genesis-q8h',
          title: 'a first-class Key type',
          description: 'Add ValueKey<T> and ObjectKey; deliberately no GlobalKey.',
          design: 'An abstract Key on the spine with equality/hashCode.',
          acceptanceCriteria: 'Seed.key accepts a typed Key; reconcile matches.',
          notes: 'Pairs with multi-child reconcile.',
        )),
      );
      expect(cfg.command, 'claude');
      // The token never rides argv; `-p` is the only non-flag arg.
      expect(cfg.args.first, '--dangerously-skip-permissions');
      final prompt = cfg.args.last;
      // The load-bearing instructions reach the agent…
      expect(prompt, contains('Add ValueKey<T> and ObjectKey'));
      expect(prompt, contains('## Design'));
      expect(prompt, contains('## Acceptance criteria'));
      expect(prompt, contains('Pairs with multi-child reconcile'));
      // …and the arm-#1 safety trailer is non-negotiable.
      expect(prompt, contains('grid/genesis-q8h'));
      expect(prompt, contains('COMMIT'));
      expect(prompt, contains('Do NOT push and do NOT open a pull request'));
      expect(cfg.workDir, '/clone/.grid/worktrees/genesis/genesis-q8h');
      expect(cfg.env['GRID_BEAD_ID'], 'genesis-q8h');
    });

    test('a bead with only a title still gets a usable prompt + the trailer', () {
      final cfg = buildAgentConfig(req(Bead(id: 'genesis-7r9', title: 'multi-child')));
      final prompt = cfg.args.last;
      expect(prompt, contains('multi-child'));
      expect(prompt, isNot(contains('## Task'))); // no description section
      expect(prompt, contains('Do NOT push and do NOT open a pull request'));
    });
  });
}

/// Pumps the microtask/event queue a few turns so broadcast-stream delivery and
/// the per-bead queues settle (mirrors the M2/M3 test settle points).
Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A minimal owned/foreign [Convergence] carrying just the rig the gate reads.
Convergence _convergence(String id, {required String substation}) => Convergence(
      id: id,
      title: id,
      status: BeadStatus.open,
      metadata: ConvergenceMetadata.decode({'convergence.rig': substation}),
    );

/// The offline harness: a fake ready-work source, a fake convergence source, a
/// fake runtime provider, a fake git runner, and a recording bd runner — so
/// `composeRun` runs end-to-end with NO live `tg`, NO real `claude`, NO real
/// `git`, NO real `bd`.
class _Harness {
  _Harness({required this.substations, required this.dryRun});

  final Set<String> substations;
  final bool dryRun;

  final FakeReadyWorkSource source = FakeReadyWorkSource();
  final FakeConvergenceSource convergence = FakeConvergenceSource();
  final FakeRuntimeProvider provider = FakeRuntimeProvider();
  final FakeGitRunner gitRunner = FakeGitRunner();
  final RecordingBdRunner bdRunner = RecordingBdRunner();

  RunWiring compose() => composeRun(
        bd: BdCliService(bdRunner),
        substations: substations,
        dryRun: dryRun,
        rootCheckout: RootCheckout(
          path: '/tmp/grid-test-root',
          defaultBranch: 'main',
          substation: substations.isEmpty ? '' : substations.first,
        ),
        readyWorkSource: source,
        convergenceSource: convergence,
        provider: provider,
        gitService: StationGitService(
          runner: gitRunner,
          prOpener: _FakePrOpener(),
        ),
      );

  Future<void> dispose() async {
    await source.close();
    await convergence.close();
    await provider.close();
  }
}

// =============================================================================
// Fakes (Fakes, not mocks) — local copies of the grid_runtime test fakes so the
// grid_cli suite is self-contained (the grid_runtime test/ dir is not on the
// import path).
// =============================================================================

class FakeReadyWorkSource implements ReadyWorkSource {
  final StreamController<GraphEvent> _events =
      StreamController<GraphEvent>.broadcast();
  final Map<String, Bead> _beads = {};

  void addReady(Bead bead) => _beads[bead.id] = bead;

  void fireReady(Set<String> entered, {Set<String> exited = const {}}) =>
      _events.add(GraphEvent.readySetChanged(entered: entered, exited: exited));

  @override
  Stream<GraphEvent> get events => _events.stream;

  @override
  List<Bead> get readyBeads => _beads.values.toList(growable: false);

  @override
  Bead? bead(String id) => _beads[id];

  Future<void> close() => _events.close();
}

class FakeConvergenceSource implements ConvergenceSource {
  final StreamController<GraphEvent> _events =
      StreamController<GraphEvent>.broadcast();
  final StreamController<GraphSnapshot> _snapshots =
      StreamController<GraphSnapshot>.broadcast();

  final GraphSnapshot _current = GraphSnapshot.fromParts(
    beads: const [],
    dependencies: const [],
    readyIds: const [],
    capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  Stream<GraphEvent> get events => _events.stream;

  @override
  Stream<GraphSnapshot> get snapshots => _snapshots.stream;

  @override
  GraphSnapshot? get current => _current;

  @override
  List<Convergence> get convergences => projectConvergences(_current);

  @override
  Convergence? convergence(String id) {
    for (final c in convergences) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> close() async {
    await _events.close();
    await _snapshots.close();
  }
}

class FakeRuntimeProvider implements RuntimeProvider {
  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();

  final List<({String name, RuntimeConfig config})> starts = [];
  final List<String> stops = [];
  final Set<String> _running = {};

  @override
  Future<void> start(String name, RuntimeConfig config) async {
    if (_running.contains(name)) throw SessionAlreadyExists(name);
    starts.add((name: name, config: config));
    _running.add(name);
  }

  @override
  Future<void> stop(String name) async {
    stops.add(name);
    _running.remove(name);
  }

  @override
  Future<void> interrupt(String name) async {}

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  @override
  Stream<String> output(String name) => const Stream.empty();

  @override
  bool isRunning(String name) => _running.contains(name);

  @override
  bool processAlive(String name) => _running.contains(name);

  @override
  String peek(String name, int lines) => '';

  @override
  List<String> listRunning(String prefix) =>
      _running.where((n) => n.startsWith(prefix)).toList();

  @override
  DateTime? lastActivity(String name) => null;

  @override
  RuntimeCapabilities get capabilities => RuntimeCapabilities.subprocess;

  Future<void> close() => _events.close();
}

class FakeGitRunner implements GitRunner {
  final List<List<String>> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    return const GitRunResult(exitCode: 0, output: '');
  }
}

class _FakePrOpener implements PrOpener {
  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async =>
      PullRequestResult.opened(
        PullRequestRef(url: 'https://example.test/pr/1', number: 1),
      );
}

/// A recording [BdRunner] (Fakes, not mocks): records every `bd` invocation so
/// a test can assert ZERO writes in dry-run. Returns a canned envelope so the
/// chokepoint runs end-to-end with no real `bd`.
class RecordingBdRunner implements BdRunner {
  RecordingBdRunner({String createdId = 'tgdog-sess1'}) : _createdId = createdId;

  final String _createdId;
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    calls.add(List<String>.unmodifiable(args));
    final sub = args.isNotEmpty ? args.first : '';
    final id = sub == 'create'
        ? _createdId
        : (args.length >= 2 ? args[1] : '');
    return Future<BdResult>.value(
      BdResult(
        exitCode: 0,
        stdout: '{"schema_version":1,"data":{"id":"$id"}}',
        stderr: '',
      ),
    );
  }
}
