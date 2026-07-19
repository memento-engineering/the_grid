// FT-1 (tg-pez) — capture-only flow telemetry: per-step timing, failure reasons,
// and the session/projection surfacing.
//
// The engine stamps step timing (startedAt/finishedAt/durationMs) + the failure
// diagnostic (failureReason) MERGED into each transition's SINGLE chokepoint
// write — no extra write traffic, no behavior change, no orchestration read.
// This suite proves: the pure codec (key set / UTC / null-omission / truncation
// / round-trip), the host stamping under an ADVANCING clock (startedAt <
// finishedAt, durationMs consistency, one merged write), the failureReason
// round-trip (mutation-resistant), and the fail-safe omission.
//
// Zero I/O — fakes + the recording chokepoint + an injected clock.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
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

/// Mounts a bare [CapabilityHost] whose clock is the injected [nowFn] (an
/// [advancingClock] in the timing tests) so the host's kick + terminal read
/// distinct instants.
({TreeOwner owner, Fakes fakes}) _host(
  Capability cap, {
  required DateTime Function() nowFn,
  StepMount? mount,
}) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  owner.mountRoot(
    InheritedSeed<StationServices>(
      value: fakes.ctx,
      child: InheritedSeed<CapabilityRegistry>(
        value: RecordingCapabilityRegistry(nowFn: nowFn),
        child: InheritedSeed<ServiceBundle>(
          value: const ServiceBundle(),
          child: InheritedSeed<Workspace>(
            value: testWorkspace('tg-1'),
            child: CapabilityHost(capability: cap, mount: mount ?? _mount()),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, fakes: fakes);
}

Bead _sessionBead(Map<String, dynamic> metadata, {bool closed = false}) => Bead(
  id: 'tgdog-s',
  issueType: IssueType.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: metadata,
);

void main() {
  group('FT-1 codec — nodeTelemetryMetadata (the pure builder)', () {
    test('writes the flat per-node keys with ISO-8601 UTC timestamps', () {
      final meta = nodeTelemetryMetadata(
        'tg-1/agent',
        startedAt: DateTime.utc(2026, 6, 1, 10),
        finishedAt: DateTime.utc(2026, 6, 1, 10, 0, 2),
        durationMs: 2000,
        failureReason: 'boom',
      );
      expect(meta, {
        'grid.cursor.tg-1/agent.startedAt': '2026-06-01T10:00:00.000Z',
        'grid.cursor.tg-1/agent.finishedAt': '2026-06-01T10:00:02.000Z',
        'grid.cursor.tg-1/agent.durationMs': '2000',
        'grid.cursor.tg-1/agent.failureReason': 'boom',
      });
    });

    test('a LOCAL DateTime is normalized to UTC on the wire', () {
      final local = DateTime(2026, 6, 1, 10); // local
      final meta = nodeTelemetryMetadata('p', startedAt: local);
      expect(
        meta['grid.cursor.p.startedAt'],
        local.toUtc().toIso8601String(),
      );
      expect(meta['grid.cursor.p.startedAt'], endsWith('Z'));
    });

    test('every null field is OMITTED — the fail-safe posture (empty in → empty '
        'out; never a bogus value)', () {
      expect(nodeTelemetryMetadata('p'), isEmpty);
      // Only the set fields appear (a start with no finish yet).
      expect(
        nodeTelemetryMetadata('p', startedAt: DateTime.utc(2026)).keys,
        ['grid.cursor.p.startedAt'],
      );
    });

    test('failureReason is truncated to kMaxReasonChars (500)', () {
      final long = 'x' * 600;
      final meta = nodeTelemetryMetadata('p', failureReason: long);
      expect(meta['grid.cursor.p.failureReason'], hasLength(kMaxReasonChars));
      expect(meta['grid.cursor.p.failureReason'], 'x' * 500);
      // A short reason is untouched.
      expect(
        nodeTelemetryMetadata('p', failureReason: 'short')['grid.cursor.p.failureReason'],
        'short',
      );
    });
  });

  group('FT-1 codec — round-trip through the cursor projection', () {
    test('a NodeCursor carrying telemetry round-trips (write → project)', () {
      final node = NodeCursor(
        state: StepState.complete,
        restartCount: 2,
        startedAt: DateTime.utc(2026, 6, 1, 10),
        finishedAt: DateTime.utc(2026, 6, 1, 10, 0, 5),
        durationMs: 5000,
        failureReason: 'partial',
      );
      final meta = nodeCursorMetadata('b/step', node);
      final back = projectCircuitCursor(_sessionBead(meta))['b/step']!;
      expect(back.startedAt, DateTime.utc(2026, 6, 1, 10));
      expect(back.finishedAt, DateTime.utc(2026, 6, 1, 10, 0, 5));
      expect(back.durationMs, 5000);
      expect(back.failureReason, 'partial');
      // The whole value survives (typed surfacing — acceptance (e)).
      expect(back, node);
    });

    test('a legacy cursor with NO telemetry keys projects null fields (never '
        'throws)', () {
      final back = projectCircuitCursor(
        _sessionBead(const {'grid.cursor.b/step.state': 'complete'}),
      )['b/step']!;
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
        'durationMs, all in ONE chokepoint write', () async {
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
      expect(h.fakes.runner.callsFor('update'), hasLength(1));
      final meta = h.fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.cursor.tg-1/agent.state'], 'complete');

      final started = DateTime.parse(meta['grid.cursor.tg-1/agent.startedAt'] as String);
      final finished = DateTime.parse(meta['grid.cursor.tg-1/agent.finishedAt'] as String);
      expect(started.isBefore(finished), isTrue, reason: 'startedAt < finishedAt');
      final duration = int.parse(meta['grid.cursor.tg-1/agent.durationMs'] as String);
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
          h.fakes.runner.metadataOfUpdate(0)['grid.cursor.tg-1/agent.startedAt'];
      expect(runningStart, isNotNull);

      h.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0));
      await _pump();
      final terminalStart =
          h.fakes.runner.metadataOfUpdate(1)['grid.cursor.tg-1/agent.startedAt'];
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

      final meta = h.fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.cursor.tg-1/agent.state'], 'failed');
      expect(
        meta['grid.cursor.tg-1/agent.failureReason'],
        'the harness refused: exit 42',
      );
      // Round-trip: the persisted write projects back into a NodeCursor whose
      // failureReason is intact (a mutation dropping the write, or reading the
      // wrong key, loses it here).
      final node = projectCircuitCursor(_sessionBead(meta))['tg-1/agent']!;
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
          .metadataOfUpdate(0)['grid.cursor.tg-1/agent.failureReason'] as String;
      expect(reason, hasLength(500));
    });

    test('a bare process death (empty AllocationFailed.reason) omits '
        'failureReason but still advances the cursor (fail-safe)', () async {
      final h = _host(const _CompletingProcess(), nowFn: advancingClock());
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();
      // A non-zero exit → interpretEvent failed → AllocationFailed('') (no
      // diagnostic).
      h.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 1));
      await _pump();
      final meta = h.fakes.runner.metadataOfUpdate(0);
      // The transition still landed (state advanced) — telemetry never blocks it.
      expect(meta['grid.cursor.tg-1/agent.state'], 'failed');
      // …but with no reason, the key is OMITTED (never a bogus empty string).
      expect(meta.containsKey('grid.cursor.tg-1/agent.failureReason'), isFalse);
    });
  });
}
