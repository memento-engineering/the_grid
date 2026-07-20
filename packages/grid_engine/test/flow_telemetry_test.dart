// FT-1 (tg-pez) — capture-only flow telemetry: per-step timing, failure reasons,
// and the session/projection surfacing.
//
// The engine stamps step timing (startedAt/finishedAt/durationMs) + the failure
// diagnostic (failureReason) MERGED into each transition's SINGLE chokepoint
// write — no extra write traffic, no behavior change, no orchestration read.
//
// tg-eli phase 2 — the molecule model is the only circuit engine, so the
// per-step write rides the STEP bead's own `stepBeadMetadata`/
// `projectMoleculeCursor` codec (`molecule_codec.dart`) — the SAME telemetry
// fields, keyed `grid.step.*` (`MoleculeStepKeys`) instead of the retired flat
// `grid.cursor.{nodePath}.*`. This suite proves: the pure codec's telemetry
// fields (UTC / null-omission / truncation / round-trip through
// `projectMoleculeCursor`), the host stamping under an ADVANCING clock
// (startedAt < finishedAt, durationMs consistency, one merged write to the
// STEP bead), the failureReason round-trip (mutation-resistant), and the
// fail-safe omission.
//
// Zero I/O — fakes + the recording chokepoint + an injected clock.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
import 'package:grid_engine/src/molecule/molecule_codec.dart' show stepBeadMetadata;
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'package:grid_engine/testing.dart';

// --- capabilities ------------------------------------------------------------

/// A one-shot process that completes on `Exited(0)`, fails otherwise.
class _CompletingProcess extends ProcessCapability {
  const _CompletingProcess();
  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => RuntimeConfig(
    workDir: context.getInheritedSeedOfExactType<Workspace>()!.workspaceDir,
    command: 'sh',
    args: const ['-c', 'echo hi'],
    lifecycle: Lifecycle.oneTurn,
  );
  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };
}

/// A service that returns a fixed outcome (Ok/Failed/Gate) — the failure-reason
/// carrier.
class _ServiceCap extends ServiceCapability {
  const _ServiceCap(this.outcome);
  final StepOutcome outcome;
  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async => outcome;
}

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// The circuit the mounted `agent` step belongs to (`StepMount.circuit` — the
/// graph a Rewind would resolve siblings against; tg-o90).
const _circuit = Circuit(
  id: 'code',
  terminalStepId: 'agent',
  steps: [CapabilityStep(stepId: 'agent', capabilityId: 'agent')],
);

StepMount _mount({String nodePath = 'tg-1/agent', NodeCursor node = const NodeCursor()}) =>
    StepMount(
      step: const CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
      nodePath: nodePath,
      circuit: _circuit,
      circuitPath: nodePath.contains('/')
          ? nodePath.substring(0, nodePath.lastIndexOf('/'))
          : '',
      session: const SessionHandle('tgdog-s'),
      node: node,
      key: ValueKey('$nodePath#${node.restartCount}.${node.rewindCount}'),
    );

/// The step bead id [InheritedCircuit.beadIdByNodePath] resolves `tg-1/agent`
/// to across this suite — every host write targets THIS bead (R5b).
const _stepBeadId = 'tgdog-step1';

/// An [InheritedCircuit] wired for `tg-1/agent` — a molecule session ambient to
/// the mounted host, so `CapabilityHost` can resolve its own write target
/// instead of refusing loud (tg-eli phase 2: there is no flat session-bead
/// fallback any more).
final _moleculeCircuit = InheritedCircuit(
  root: BeadPathKey(const ['tg-1', 'tgdog-s', _stepBeadId]),
  beadIdByNodePath: const {'tg-1/agent': _stepBeadId},
  cursor: const {},
);

/// Mounts a bare [CapabilityHost] whose clock is the injected [nowFn] (an
/// [advancingClock] in the timing tests) so the host's kick + terminal read
/// distinct instants. A [ProcessCapability] additionally needs an ambient
/// [ProcessLeaseVendor] (tg-h4u): [SelfManagedProcessVendor] wraps the SAME
/// real transport (`stationProcessSpawner`/`stationProcessDispatcher`) the
/// production vendor uses, so `fakes.provider.emit(...)` drives it exactly as
/// it drove the retired flat `ProcessAllocation`.
({TreeOwner owner, Fakes fakes}) _host(
  Capability cap, {
  required DateTime Function() nowFn,
  StepMount? mount,
}) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  Seed tree = CapabilityHost(capability: cap, mount: mount ?? _mount());
  tree = InheritedSeed<InheritedCircuit>(value: _moleculeCircuit, child: tree);
  if (cap is ProcessCapability) {
    tree = InheritedSeed<ProcessLeaseVendor>(
      value: const SelfManagedProcessVendor(
        spawn: stationProcessSpawner,
        dispatch: stationProcessDispatcher,
      ),
      child: tree,
    );
  }
  owner.mountRoot(
    InheritedSeed<StationServices>(
      value: fakes.ctx,
      child: InheritedSeed<CapabilityRegistry>(
        value: RecordingCapabilityRegistry(nowFn: nowFn),
        child: InheritedSeed<ServiceBundle>(
          value: const ServiceBundle(),
          child: InheritedSeed<Workspace>(
            value: testWorkspace('tg-1'),
            child: tree,
          ),
        ),
      ),
    ),
  );
  return (owner: owner, fakes: fakes);
}

/// A HISTORICAL flat `type=session` bead — only used by the `projectSession`
/// group below, which reads the session's OWN lifecycle stamps
/// (`started_at`/`closed_at`), a concern orthogonal to per-step cursor state
/// and untouched by the molecule migration.
Bead _sessionBead(Map<String, dynamic> metadata, {bool closed = false}) => Bead(
  id: 'tgdog-s',
  issueType: IssueType.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: metadata,
);

/// A `type=step` bead at [path] carrying [extra] wire metadata — the fixture
/// [projectMoleculeCursor] reads back (mirrors `molecule_codec_test.dart`'s own
/// `_stepBead`).
Bead _stepBead(String path, {Map<String, String> extra = const {}}) => Bead(
  id: 'tgdog-step-${path.replaceAll('/', '-')}',
  issueType: IssueType.step,
  metadata: {MoleculeStepKeys.path: path, ...extra},
);

void main() {
  group('FT-1 codec — stepBeadMetadata (the pure builder, telemetry fields)', () {
    test('writes the per-step telemetry keys with ISO-8601 UTC timestamps', () {
      final meta = stepBeadMetadata(
        NodeCursor(
          state: StepState.complete,
          startedAt: DateTime.utc(2026, 6, 1, 10),
          finishedAt: DateTime.utc(2026, 6, 1, 10, 0, 2),
          durationMs: 2000,
          failureReason: 'boom',
        ),
      );
      expect(meta[MoleculeStepKeys.startedAt], '2026-06-01T10:00:00.000Z');
      expect(meta[MoleculeStepKeys.finishedAt], '2026-06-01T10:00:02.000Z');
      expect(meta[MoleculeStepKeys.durationMs], '2000');
      expect(meta[MoleculeStepKeys.failureReason], 'boom');
    });

    test('a LOCAL DateTime is normalized to UTC on the wire', () {
      final local = DateTime(2026, 6, 1, 10); // local
      final meta = stepBeadMetadata(
        NodeCursor(state: StepState.running, startedAt: local),
      );
      expect(
        meta[MoleculeStepKeys.startedAt],
        local.toUtc().toIso8601String(),
      );
      expect(meta[MoleculeStepKeys.startedAt], endsWith('Z'));
    });

    test('every null telemetry field is OMITTED — the fail-safe posture (only '
        'the always-present state/restartCount survive an empty NodeCursor)', () {
      final empty = stepBeadMetadata(const NodeCursor(state: StepState.pending));
      expect(empty.keys, unorderedEquals([
        MoleculeStepKeys.state,
        MoleculeStepKeys.restartCount,
      ]));
      // A start with no finish yet: only startedAt joins the always-present pair.
      final partial = stepBeadMetadata(
        NodeCursor(state: StepState.pending, startedAt: DateTime.utc(2026)),
      );
      expect(partial.keys, containsAll([MoleculeStepKeys.startedAt]));
      expect(
        partial.keys,
        isNot(anyOf(
          contains(MoleculeStepKeys.finishedAt),
          contains(MoleculeStepKeys.durationMs),
          contains(MoleculeStepKeys.failureReason),
        )),
      );
    });

    test('failureReason is truncated to kMaxReasonChars (500)', () {
      final long = 'x' * 600;
      final meta = stepBeadMetadata(
        NodeCursor(state: StepState.failed, failureReason: long),
      );
      expect(meta[MoleculeStepKeys.failureReason], hasLength(kMaxReasonChars));
      expect(meta[MoleculeStepKeys.failureReason], 'x' * 500);
      // A short reason is untouched.
      expect(
        stepBeadMetadata(
          NodeCursor(state: StepState.failed, failureReason: 'short'),
        )[MoleculeStepKeys.failureReason],
        'short',
      );
    });
  });

  group('FT-1 codec — round-trip through projectMoleculeCursor', () {
    test('a step bead carrying telemetry round-trips (write → project)', () {
      final node = NodeCursor(
        state: StepState.complete,
        restartCount: 2,
        startedAt: DateTime.utc(2026, 6, 1, 10),
        finishedAt: DateTime.utc(2026, 6, 1, 10, 0, 5),
        durationMs: 5000,
        failureReason: 'partial',
      );
      final bead = _stepBead('b/step', extra: stepBeadMetadata(node));
      final back = projectMoleculeCursor([bead]).cursor['b/step']!;
      expect(back.startedAt, DateTime.utc(2026, 6, 1, 10));
      expect(back.finishedAt, DateTime.utc(2026, 6, 1, 10, 0, 5));
      expect(back.durationMs, 5000);
      expect(back.failureReason, 'partial');
      // The whole value survives (typed surfacing — acceptance (e)); pgid/pid/
      // token stay null (LeaseKeys is a namespace this codec never reads) and
      // rewindCount is the freezed default (derived, never persisted, item 7).
      expect(back, node.copyWith(rewindCount: 0));
    });

    test('a step bead with NO telemetry keys projects null fields (never '
        'throws)', () {
      final bead = _stepBead(
        'b/step',
        extra: const {MoleculeStepKeys.state: 'complete'},
      );
      final back = projectMoleculeCursor([bead]).cursor['b/step']!;
      expect(back.startedAt, isNull);
      expect(back.finishedAt, isNull);
      expect(back.durationMs, isNull);
      expect(back.failureReason, isNull);
    });
  });

  group('FT-1 codec — projectSession surfaces the session lifecycle stamps', () {
    test('started_at / closed_at project as typed DateTime?', () {
      final session = projectSession(
        _sessionBead(
          const {
            'rig': 'tgdog',
            'work_bead': 'tg-1',
            'started_at': '2026-06-01T10:00:00.000Z',
            'closed_at': '2026-06-01T10:05:00.000Z',
          },
          closed: true,
        ),
      );
      expect(session.startedAt, DateTime.utc(2026, 6, 1, 10));
      expect(session.closedAt, DateTime.utc(2026, 6, 1, 10, 5));
    });

    test('an open/legacy session has null stamps', () {
      final session = projectSession(
        _sessionBead(const {'rig': 'tgdog', 'work_bead': 'tg-1'}),
      );
      expect(session.startedAt, isNull);
      expect(session.closedAt, isNull);
    });
  });

  group('FT-1 host — timing under an ADVANCING clock (one merged write)', () {
    test('a clean complete stamps startedAt < finishedAt + a consistent '
        'durationMs, all in ONE chokepoint write to the STEP bead', () async {
      final h = _host(const _CompletingProcess(), nowFn: advancingClock());
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();
      // The `running` write (SessionStarted) already carried startedAt; clear so
      // index 0 below is unambiguously the TERMINAL write.
      h.fakes.provider.emit(
        const SessionStarted(name: 'tgdog-s/tg-1/agent', pid: 1, pgid: 2),
      );
      await _pump();
      h.fakes.runner.calls.clear();

      h.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0));
      await _pump();

      // EXACTLY ONE write for the terminal transition (the merge discipline).
      final updates = h.fakes.runner.callsFor('update');
      expect(updates, hasLength(1));
      expect(updates.single[1], _stepBeadId);
      final meta = h.fakes.runner.metadataOfUpdate(0);
      expect(meta[MoleculeStepKeys.state], 'complete');

      final started = DateTime.parse(meta[MoleculeStepKeys.startedAt] as String);
      final finished = DateTime.parse(meta[MoleculeStepKeys.finishedAt] as String);
      expect(started.isBefore(finished), isTrue, reason: 'startedAt < finishedAt');
      final duration = int.parse(meta[MoleculeStepKeys.durationMs] as String);
      // durationMs is EXACTLY finishedAt - startedAt (consistency).
      expect(duration, finished.difference(started).inMilliseconds);
      // The advancing clock steps 1s between the host's kick and the terminal.
      expect(duration, 1000);
    });

    test('the SAME startedAt captured at the kick is durable on the running '
        'write AND re-stamped on the terminal', () async {
      final h = _host(const _CompletingProcess(), nowFn: advancingClock());
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();
      h.fakes.provider.emit(
        const SessionStarted(name: 'tgdog-s/tg-1/agent', pid: 1, pgid: 2),
      );
      await _pump();
      final runningStart =
          h.fakes.runner.metadataOfUpdate(0)[MoleculeStepKeys.startedAt];
      expect(runningStart, isNotNull);

      h.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0));
      await _pump();
      final terminalStart =
          h.fakes.runner.metadataOfUpdate(1)[MoleculeStepKeys.startedAt];
      // The kick instant is captured ONCE and re-used — not re-read at the
      // terminal (a mutation re-reading the clock for startedAt would drift).
      expect(terminalStart, runningStart);
    });
  });

  group('FT-1 host — failureReason persists (mutation-resistant round-trip)', () {
    test('a ServiceCapability Failed(reason) persists the truncated reason on '
        'the failed write, and it survives a project round-trip', () async {
      final h = _host(
        const _ServiceCap(Failed('the harness refused: exit 42')),
        nowFn: advancingClock(),
      );
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      final updates = h.fakes.runner.callsFor('update');
      expect(updates.single[1], _stepBeadId);
      final meta = h.fakes.runner.metadataOfUpdate(0);
      expect(meta[MoleculeStepKeys.state], 'failed');
      expect(
        meta[MoleculeStepKeys.failureReason],
        'the harness refused: exit 42',
      );
      // Round-trip: the persisted write projects back into a NodeCursor whose
      // failureReason is intact (a mutation dropping the write, or reading the
      // wrong key, loses it here).
      final bead = _stepBead('tg-1/agent', extra: meta.cast<String, String>());
      final node = projectMoleculeCursor([bead]).cursor['tg-1/agent']!;
      expect(node.state, StepState.failed);
      expect(node.failureReason, 'the harness refused: exit 42');
      expect(node.startedAt, isNotNull);
      expect(node.finishedAt, isNotNull);
    });

    test('an oversized failure reason is truncated to 500 chars on the wire',
        () async {
      final h = _host(
        _ServiceCap(Failed('E' * 900)),
        nowFn: advancingClock(),
      );
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();
      final reason = h.fakes.runner
          .metadataOfUpdate(0)[MoleculeStepKeys.failureReason] as String;
      expect(reason, hasLength(500));
    });

    test('a bare failure (empty AllocationFailed.reason) omits failureReason '
        'but still advances the cursor (fail-safe)', () async {
      // A ServiceCapability failing with an EMPTY reason — the diagnostic-free
      // shape `_persistFailure`'s default guards against (the molecule-routed
      // ProcessCapability dispatcher always supplies a fixed diagnostic on a
      // process death, so this fail-safe is exercised through the service path
      // instead).
      final h = _host(const _ServiceCap(Failed('')), nowFn: advancingClock());
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();
      final meta = h.fakes.runner.metadataOfUpdate(0);
      // The transition still landed (state advanced) — telemetry never blocks it.
      expect(meta[MoleculeStepKeys.state], 'failed');
      // …but with no reason, the key is OMITTED (never a bogus empty string).
      expect(meta.containsKey(MoleculeStepKeys.failureReason), isFalse);
    });
  });
}
