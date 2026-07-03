import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_cli/src/station_runner.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// RS-1 (D-R2, `docs/SCRATCH-resident-station.md`): SIGTERM/SIGHUP join
/// `driveStation`'s graceful shutdown path. Fakes, not mocks — the signal seam
/// is exercised with an injected `StreamController<ProcessSignal>`; NO live
/// stores, NO real `claude`/`git`/`bd`. What this file locks:
///
///  (a) SIGTERM triggers EXACTLY the shutdown sequence SIGINT does (identical
///      observable order: tree teardown → sources shutdown; exit 0);
///  (b) SIGHUP behaves as SIGTERM (terminate — no reload semantics);
///  (c) double-signal safe: shutdown runs ONCE, later signals are ignored with
///      one loud `already shutting down` line, no unhandled errors;
///  (d) the signal subscription stays live THROUGH shutdown (a repeat signal
///      during teardown is absorbed, not default-killed) and is cancelled
///      after, so the VM can exit — proven in-process (hasListener) and by a
///      process-level smoke: a real OS SIGTERM drains a `dart run` child
///      booting a dry station, exit 0 within a bounded wait + the banner.
void main() {
  group('driveStation — the injected termination-signal seam', () {
    test('SIGTERM triggers the graceful shutdown: exit 0, sources shut down, '
        'the shutdown banner, the subscription cancelled', () async {
      final h = _SignalHarness();
      addTearDown(h.dispose);

      final run = h.drive();
      await _settle();
      h.signals.add(ProcessSignal.sigterm);

      final code = await run.timeout(const Duration(seconds: 10));
      expect(code, 0);
      expect(h.sourceShutdowns, 1, reason: 'the graceful path ran');
      expect(
        h.lines.where((l) => l.contains('grid run: shutting down…')),
        hasLength(1),
        reason: 'the shutdown banner printed once',
      );
      expect(
        h.signals.hasListener,
        isFalse,
        reason: 'the signal subscription is cancelled post-shutdown',
      );
    });

    test(
      'SIGHUP behaves as SIGTERM (terminate — no reload semantics)',
      () async {
        final h = _SignalHarness();
        addTearDown(h.dispose);

        final run = h.drive();
        await _settle();
        h.signals.add(ProcessSignal.sighup);

        final code = await run.timeout(const Duration(seconds: 10));
        expect(code, 0);
        expect(h.sourceShutdowns, 1);
        expect(h.lines.join('\n'), contains('grid run: shutting down…'));
        expect(h.signals.hasListener, isFalse);
      },
    );

    test(
      'SIGINT and SIGTERM drive the IDENTICAL observable shutdown sequence '
      'over a mounted bead (tree teardown → sources shutdown; exit 0)',
      () async {
        Future<({int code, List<String> order, List<String> lines})> runWith(
          ProcessSignal signal,
        ) async {
          final h = _SignalHarness();
          addTearDown(h.dispose);

          final run = h.drive();
          h.pushWork(Bead(id: 'tgdog-w1', title: 'resident work'));
          await _settle();
          // A bounded poll, not a second fixed pump: under heavier CPU
          // contention (more concurrent test files/isolates competing for
          // scheduler time) a fixed microtask-turn count can undershoot
          // before the mount→spawn chain settles, even though it always
          // completes well within this bound.
          await _untilProviderStarted(h.provider);
          expect(
            h.provider.starts,
            hasLength(1),
            reason: 'the ready bead mounted + would-spawn BEFORE the signal',
          );

          h.signals.add(signal);
          final code = await run.timeout(const Duration(seconds: 10));
          return (code: code, order: h.order, lines: h.lines);
        }

        final viaInt = await runWith(ProcessSignal.sigint);
        final viaTerm = await runWith(ProcessSignal.sigterm);

        expect(viaInt.code, 0);
        expect(viaTerm.code, 0);
        expect(
          viaTerm.order,
          viaInt.order,
          reason: 'SIGTERM runs EXACTLY the sequence SIGINT does (a)',
        );
        expect(
          viaInt.order,
          containsAllInOrder(<String>['provider.stop', 'sources.shutdown']),
          reason: 'ordering unchanged: the tree tears down BEFORE the sources',
        );
        expect(
          viaTerm.lines.where((l) => l.contains('shutting down')),
          hasLength(1),
        );
      },
    );

    test('double-signal safe: shutdown runs once, ONE loud already-shutting-'
        'down line, exit 0', () async {
      final h = _SignalHarness();
      addTearDown(h.dispose);

      final run = h.drive();
      await _settle();
      h.signals
        ..add(ProcessSignal.sigterm)
        ..add(ProcessSignal.sigint);

      final code = await run.timeout(const Duration(seconds: 10));
      expect(code, 0);
      expect(h.sourceShutdowns, 1, reason: 'shutdown is never re-entered');
      expect(
        h.lines.where((l) => l.contains('already shutting down')),
        hasLength(1),
        reason: 'the later signal is ignored with one LOUD line',
      );
      expect(
        h.lines.where((l) => l.contains('grid run: shutting down…')),
        hasLength(1),
      );
    });

    test('a signal arriving DURING shutdown is absorbed loudly (the '
        'subscription outlives shutdown, then cancels)', () async {
      final release = Completer<void>();
      final entered = Completer<void>();
      final h = _SignalHarness(
        sourcesShutdownGate: () async {
          entered.complete();
          await release.future;
        },
      );
      addTearDown(h.dispose);

      final run = h.drive();
      await _settle();
      h.signals.add(ProcessSignal.sigterm);
      await entered.future.timeout(const Duration(seconds: 10));

      // Mid-shutdown: the subscription must still be live to absorb this —
      // with it cancelled, a real repeat signal would default-kill the process.
      expect(h.signals.hasListener, isTrue);
      h.signals.add(ProcessSignal.sighup);
      await _settle();
      expect(
        h.lines.where((l) => l.contains('already shutting down')),
        hasLength(1),
      );
      expect(h.sourceShutdowns, 1, reason: 'shutdown never re-entered');

      release.complete();
      final code = await run.timeout(const Duration(seconds: 10));
      expect(code, 0);
      expect(h.signals.hasListener, isFalse, reason: 'cancelled post-shutdown');
    });
  });

  group('terminationSignals — the default binding', () {
    test('a real SIGHUP to this process is delivered through the merged '
        'stream (the watch intercepts the default terminate)', () async {
      final received = Completer<ProcessSignal>();
      final subscription = terminationSignals().listen((signal) {
        if (!received.isCompleted) received.complete(signal);
      });
      await _settle(); // the OS watches are armed on listen

      Process.killPid(pid, ProcessSignal.sighup);
      final signal = await received.future.timeout(const Duration(seconds: 10));
      expect(signal, ProcessSignal.sighup);
      await subscription.cancel();
    });
  });

  group('process-level smoke — a real OS SIGTERM drains a resident child', () {
    test(
      'the dry-station child exits 0 within a bounded wait + prints the '
      'shutdown banner (main RETURNS: a leaked subscription would hang it)',
      timeout: const Timeout(Duration(minutes: 2)),
      () async {
        final child = await Process.start(
          Platform.resolvedExecutable,
          ['tool/signal_smoke_target.dart'],
          workingDirectory: Directory.current.path, // package root
        );
        final out = StringBuffer();
        final err = StringBuffer();
        final armed = Completer<void>();
        child.stdout.transform(utf8.decoder).listen((chunk) {
          out.write(chunk);
          if (!armed.isCompleted && out.toString().contains('SMOKE_ARMED')) {
            armed.complete();
          }
        });
        child.stderr.transform(utf8.decoder).listen(err.write);

        try {
          // Bounded boot: the child compiles + parks, then announces the
          // moment driveStation's (real) signal watches are attached.
          await armed.future.timeout(const Duration(seconds: 90));
        } on TimeoutException {
          child.kill(ProcessSignal.sigkill);
          fail('the child never armed.\nstdout: $out\nstderr: $err');
        }

        expect(child.kill(ProcessSignal.sigterm), isTrue);
        final code = await child.exitCode.timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            child.kill(ProcessSignal.sigkill);
            fail(
              'the child did not exit after SIGTERM — the graceful path '
              'hung or a signal subscription leaked.\n'
              'stdout: $out\nstderr: $err',
            );
          },
        );
        expect(code, 0, reason: 'graceful drain.\nstderr: $err');
        expect(out.toString(), contains('grid run: shutting down…'));
      },
    );
  });
}

/// Pumps the microtask/event queue a few turns so the kernel's batched flush,
/// stream deliveries, and the park→listen chain all settle.
Future<void> _settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A bounded poll (not a fixed pump) for the mount→spawn chain to record its
/// first start — robust to CPU-scheduling variance across concurrent test
/// isolates, where a fixed microtask-turn count can occasionally undershoot.
Future<void> _untilProviderStarted(_RecordingProvider provider) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (provider.starts.isEmpty && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// The offline signal harness: a composed dry station (the lib's OWN dry git
/// service + a recording provider + a canned bd runner behind the chokepoint)
/// parked by [drive] on an injected signal stream — nothing live anywhere.
class _SignalHarness {
  _SignalHarness({Future<void> Function()? sourcesShutdownGate})
    : _sourcesShutdownGate = sourcesShutdownGate;

  static const StationArgs args = StationArgs(
    substations: {'tgdog'},
    stateSubstation: 'tgdog',
    dryRun: true,
  );

  final Future<void> Function()? _sourcesShutdownGate;

  /// The injected signal seam (what a test sends "signals" through).
  final StreamController<ProcessSignal> signals =
      StreamController<ProcessSignal>();

  /// Every `out` line driveStation wrote (banner + shutdown + loud ignores).
  final List<String> lines = <String>[];

  /// The observable shutdown sequence: `provider.stop` (tree teardown) and
  /// `sources.shutdown`, in occurrence order.
  final List<String> order = <String>[];

  int sourceShutdowns = 0;

  final _FakeSnapshotSource work = _FakeSnapshotSource();
  late final _RecordingProvider provider = _RecordingProvider(
    onStop: () => order.add('provider.stop'),
  );

  late final StationSources sources = StationSources(
    work: work,
    shutdown: () async {
      sourceShutdowns++;
      order.add('sources.shutdown');
      await _sourcesShutdownGate?.call();
    },
  );

  /// Composes the dry station and parks it (run-forever) on [signals].
  Future<int> drive() {
    final writer = StationBeadWriter(
      bd: BdCliService(_CannedBdRunner()),
      ownership: BeadOwnershipPredicate(const {'tgdog'}),
    );
    final wiring = composeStation(
      work: work,
      state: const EmptySnapshotSource(),
      stationServices: StationServices(
        provider: provider,
        writer: writer,
        stateSubstation: 'tgdog',
      ),
      substations: const [
        SubstationConfig(substationId: 'tgdog', ownedSubstations: {'tgdog'}),
      ],
      git: buildDryTreeGitService(),
      workRoot: const RootCheckout(
        path: '',
        defaultBranch: 'main',
        substation: 'tgdog',
      ),
      groups: _FakeProcessGroupController(),
      freshnessBarrier: () async {},
      resolver: const FormulaResolver(_markerFormulaFor),
      registry: DefaultCapabilityRegistry(
        capabilities: const {_markerStep: _MarkerCap()},
        formulas: const {'marker': _markerFormula},
      ),
    );
    return driveStation(
      wiring: wiring,
      sources: sources,
      args: args,
      out: lines.add,
      signals: signals.stream,
    );
  }

  /// Pushes [bead] as ready owned work (the mount trigger).
  void pushWork(Bead bead) {
    work.push(
      GraphSnapshot.fromParts(
        beads: [bead],
        dependencies: const [],
        readyIds: {bead.id},
        capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
  }

  Future<void> dispose() async {
    await work.close();
    await provider.close();
    await signals.close();
  }
}

// --- a minimal never-live asset (mirrors run_command_tree_test's marker) ----

const String _markerStep = 'marker';

const Formula _markerFormula = Formula(
  id: 'marker',
  terminalStepId: _markerStep,
  steps: [
    CapabilityStep(
      stepId: _markerStep,
      capabilityId: _markerStep,
      kind: StepKind.job,
    ),
  ],
);

Formula _markerFormulaFor(Bead bead) => _markerFormula;

class _MarkerCap extends ProcessCapability {
  const _MarkerCap();

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => RuntimeConfig(
    workDir: context.getInheritedSeedOfExactType<Workspace>()!.workspaceDir,
    command: 'sh',
    args: const ['-c', 'true'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => StepSignal.none;
}

/// A fake [SnapshotSource] — a broadcast controller + a settable current
/// (seed-then-follow, like the real change-gated runtime).
class _FakeSnapshotSource implements SnapshotSource {
  final StreamController<GraphSnapshot> _controller =
      StreamController<GraphSnapshot>.broadcast();
  GraphSnapshot? _current;

  void push(GraphSnapshot snapshot) {
    _current = snapshot;
    _controller.add(snapshot);
  }

  @override
  Stream<GraphSnapshot> get snapshots => _controller.stream;

  @override
  GraphSnapshot? get current => _current;

  Future<void> close() => _controller.close();
}

/// A recording, no-op [RuntimeProvider]: spawns are recorded (never real) and
/// each stop reports through [onStop] so a test can order the tree teardown
/// against the sources shutdown.
class _RecordingProvider implements RuntimeProvider {
  _RecordingProvider({required this.onStop});

  final void Function() onStop;

  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();
  final List<String> starts = <String>[];
  final Set<String> _running = <String>{};

  @override
  Future<void> start(String name, RuntimeConfig config) async {
    if (_running.contains(name)) throw SessionAlreadyExists(name);
    starts.add(name);
    _running.add(name);
  }

  @override
  Future<void> stop(String name) async {
    onStop();
    _running.remove(name);
  }

  @override
  Future<void> interrupt(String name) async {}

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  @override
  Stream<String> output(String name) => const Stream<String>.empty();

  @override
  bool isRunning(String name) => _running.contains(name);

  @override
  bool processAlive(String name) => _running.contains(name);

  @override
  String peek(String name, int lines) => '';

  @override
  List<String> listRunning(String prefix) =>
      _running.where((n) => n.startsWith(prefix)).toList(growable: false);

  @override
  DateTime? lastActivity(String name) => null;

  @override
  RuntimeCapabilities get capabilities => RuntimeCapabilities.subprocess;

  Future<void> close() => _events.close();
}

/// A fake [ProcessGroupController] — never reached (the dry git service finds
/// no survivors), but required to construct the RestartReconciler.
class _FakeProcessGroupController implements ProcessGroupController {
  @override
  int currentGroupId() => 99999;

  @override
  bool processAlive(int pid) => false;

  @override
  Future<int?> resolvePgid(int pid) async => null;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) => false;
}

/// A canned [BdRunner] (Fakes, not mocks): returns an OWNED session id so the
/// chokepoint's mint runs end-to-end; no real `bd` anywhere.
class _CannedBdRunner implements BdRunner {
  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    final sub = args.isNotEmpty ? args.first : '';
    final id = sub == 'create'
        ? 'tgdog-sess1'
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
