import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/molecule_schema.dart';
import 'package:test/test.dart';

/// tg-eli phase 1 — molecule crash-recovery PARITY for wedge detection.
///
/// `sampleWedge` was flat-only (`session.cursor.values`), so a molecule
/// session's step state — its own `grid.step.*` beads, projected by
/// `projectMoleculeCursor` — was INVISIBLE: a grid of actively-running
/// molecule sessions read as `live > 0, running == 0` (a FALSE wedge), and a
/// molecule-only stall carried no gated evidence. These tests pin the
/// molecule arm of the sample; the flat arm keeps its own tests in
/// wedge_test.dart untouched (phase 2 retires it).
void main() {
  final t0 = DateTime.utc(2026, 7, 19, 10);

  group('sampleWedge — molecule sessions contribute their step state', () {
    test(
      'a RUNNING molecule step is an active stage → NOT stalled (this exact '
      'grid read as a false wedge while the sampler was flat-blind)',
      () {
        final sample = sampleWedge(
          _join({
            'tg-m1': _molecule([
              _step('tgdog-s1', 'tg-m1/build', state: StepState.running),
            ]),
          }),
          now: t0,
        );
        expect(sample.live, 1);
        expect(sample.running, 1);
        expect(sample.gated, 0);
        expect(sample.isStalled, isFalse);
      },
    );

    test(
      'a molecule session parked at a gate counts as gated → the wedge CAN '
      'fire on a molecule-only stall',
      () {
        final sample = sampleWedge(
          _join({
            'tg-m1': _molecule([
              _step(
                'tgdog-s1',
                'tg-m1/build',
                state: StepState.complete,
                closed: true,
              ),
              _step('tgdog-s2', 'tg-m1/spec_review', state: StepState.gated),
            ]),
          }),
          now: t0,
        );
        expect(sample.live, 1);
        expect(sample.running, 0);
        expect(sample.gated, 1);
        expect(sample.isStalled, isTrue);
        expect(sample.reason, contains('parked at a gate'));
      },
    );

    test(
      'a failed molecule step with a FUTURE cooldown is forward progress (a '
      'restart is scheduled) → NOT stalled; once the cooldown LAPSES, it IS',
      () {
        final cooling = _join({
          'tg-m1': _molecule([
            _step(
              'tgdog-s1',
              'tg-m1/build',
              state: StepState.failed,
              cooldownUntil: t0.add(const Duration(seconds: 30)),
            ),
          ]),
        });
        final now = sampleWedge(cooling, now: t0);
        expect(now.cooling, 1);
        expect(now.isStalled, isFalse);
        final later = sampleWedge(
          cooling,
          now: t0.add(const Duration(minutes: 1)),
        );
        expect(later.cooling, 0);
        expect(later.isStalled, isTrue);
      },
    );

    test(
      'a stale SUPERSEDED incarnation still stamped `running` is NOT an '
      'active stage — only the ACTIVE successor counts (A52: the prior '
      "round's corpse cannot mask the stall)",
      () {
        final sample = sampleWedge(
          _join({
            'tg-m1': _molecule(
              [
                _step('tgdog-s1', 'tg-m1/build', state: StepState.running),
                _step('tgdog-s2', 'tg-m1/build', state: StepState.gated),
              ],
              dependencies: const [
                BeadDependency(
                  issueId: 'tgdog-s2',
                  dependsOnId: 'tgdog-s1',
                  type: DependencyType.supersedes,
                ),
              ],
            ),
          }),
          now: t0,
        );
        expect(sample.running, 0);
        expect(sample.gated, 1);
        expect(sample.isStalled, isTrue);
      },
    );

    test(
      'the model split is the EXPLICIT discriminator, never inferred from '
      'bucket contents: a molecule pour that crashed before its first step '
      'bead landed (isMolecule, zero beads) samples down the molecule arm — '
      'an honest stall that can ripen — even past a poisoned flat cursor',
      () {
        // The populated flat cursor is a TRIPWIRE, not a legal state (a
        // molecule session never writes `grid.cursor.*` — the drain
        // guarantee): an implementation picking the arm off
        // `moleculeBeads.isNotEmpty` (the inference session_projection.dart's
        // `isMolecule` doc forbids) would fall through to the flat read here
        // and let the phantom `running` mask the stall.
        final sample = sampleWedge(
          _join({
            'tg-m1': _molecule(
              const [],
              cursor: const {
                'tg-m1/build': NodeCursor(state: StepState.running),
              },
            ),
          }),
          now: t0,
        );
        expect(sample.live, 1);
        expect(sample.running, 0);
        expect(sample.isStalled, isTrue);
      },
    );

    test(
      '…and the discriminator cuts BOTH ways: a flat session (isMolecule '
      'false) samples its flat cursor even with step-bead NOISE in its '
      'molecule bucket — the bucket cannot manufacture progress',
      () {
        // The mirror tripwire: `moleculeBeads` is non-empty on a FLAT session
        // (equally illegal — the join buckets steps only under a molecule
        // session). A bucket-inferring implementation would read the noisy
        // step's `running` and miss the flat gate stall.
        final sample = sampleWedge(
          _join({
            'tg-1': SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-x',
              cursor: const {
                'tg-1/spec_review': NodeCursor(state: StepState.gated),
              },
              moleculeBeads: [
                _step('tgdog-s9', 'tg-1/build', state: StepState.running),
              ],
            ),
          }),
          now: t0,
        );
        expect(sample.live, 1);
        expect(sample.running, 0);
        expect(sample.gated, 1);
        expect(sample.isStalled, isTrue);
        expect(sample.reason, contains('parked at a gate'));
      },
    );
  });

  group('NEGATIVE CONTROL — terminal molecule state never trips the alarm', () {
    test(
      'all-terminal molecule steps (complete + a positive-terminal ready '
      'daemon) contribute NO running, NO gated, NO cooling',
      () {
        final sample = sampleWedge(_join({'tg-m1': _allTerminal()}), now: t0);
        expect(sample.live, 1);
        expect(sample.running, 0);
        expect(sample.gated, 0);
        expect(sample.cooling, 0);
        // Parity with the flat model's ready-daemon semantic: a live session
        // whose every step is a positive terminal is genuinely not advancing.
        // In practice the window is momentary — the terminal step's completion
        // closes the session bead within a flush, far under the threshold.
        expect(sample.isStalled, isTrue);
      },
    );

    test(
      'an all-terminal molecule beside flowing work never wedges the grid '
      '(no phantom running to mask, no phantom gate to alarm)',
      () {
        final sample = sampleWedge(
          _join({'tg-m1': _allTerminal(), 'tg-1': _flatRunning()}),
          now: t0,
        );
        expect(sample.live, 2);
        expect(sample.running, 1);
        expect(sample.gated, 0);
        expect(sample.isStalled, isFalse);
      },
    );

    test(
      'a TERMINAL molecule session never counts at all → no false wedge from '
      'a finished round',
      () {
        final sample = sampleWedge(
          _join({'tg-m1': _allTerminal(terminal: true)}),
          now: t0,
        );
        expect(sample.live, 0);
        expect(sample.isStalled, isFalse);
        expect(sample.reason, 'no live session');
      },
    );
  });

  group('sampleWedge — mixed flat + molecule sessions SUM into one sample', () {
    test('running and gated counts add across both models', () {
      final sample = sampleWedge(
        _join({
          'tg-1': _flatRunning(),
          'tg-2': _flatGated(),
          'tg-m1': _molecule([
            _step('tgdog-s1', 'tg-m1/build', state: StepState.running),
          ]),
          'tg-m2': _molecule([
            _step('tgdog-s2', 'tg-m2/spec_review', state: StepState.gated),
          ]),
        }),
        now: t0,
      );
      expect(sample.live, 4);
      expect(sample.running, 2);
      expect(sample.gated, 2);
      expect(sample.isStalled, isFalse);
    });

    test(
      '…and when EVERY session across BOTH models is parked, the union is a '
      'total stall',
      () {
        final sample = sampleWedge(
          _join({
            'tg-1': _flatGated(),
            'tg-m1': _molecule([
              _step('tgdog-s1', 'tg-m1/spec_review', state: StepState.gated),
            ]),
            'tg-m2': _molecule([
              _step('tgdog-s2', 'tg-m2/spec_review', state: StepState.gated),
            ]),
          }),
          now: t0,
        );
        expect(sample.live, 3);
        expect(sample.running, 0);
        expect(sample.gated, 3);
        expect(sample.isStalled, isTrue);
        expect(sample.reason, contains('ALL 3'));
      },
    );
  });

  group('WedgeMonitor — the latch sees molecule stalls end-to-end', () {
    test(
      'a molecule-only stall sustained past the threshold → Wedged, '
      'station.wedged flares once; the step advancing to running unwedges',
      () {
        final clock = _FakeClock(t0);
        final timers = _FakeTimers();
        final transport = _FakeTransport();
        var steps = [
          _step('tgdog-s1', 'tg-m1/spec_review', state: StepState.gated),
        ];
        final monitor = WedgeMonitor(
          latest: () => _join({'tg-m1': _molecule(steps)}),
          threshold: const Duration(minutes: 10),
          pollInterval: const Duration(seconds: 30),
          transport: transport,
          clock: () => clock.now,
          scheduleTimer: timers.schedule,
        );
        addTearDown(monitor.dispose);

        monitor.start();
        expect(monitor.state, isA<Stalling>());
        expect(transport.flares, isEmpty);

        clock.advance(const Duration(minutes: 10));
        timers.fireAll();
        expect(monitor.state, isA<Wedged>());
        expect(transport.names, ['station.wedged']);
        expect(transport.flares.single.data['gated'], '1');

        // The step bead advances to `running` — the very next poll unwedges.
        steps = [
          _step('tgdog-s1', 'tg-m1/spec_review', state: StepState.running),
        ];
        clock.advance(const Duration(seconds: 30));
        timers.fireAll();
        expect(monitor.state, isA<Flowing>());
        expect(transport.names, ['station.wedged', 'station.unwedged']);
      },
    );
  });
}

JoinedSnapshot _join(Map<String, SessionProjection> sessions) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: const [],
    dependencies: const [],
    readyIds: const [],
    capturedAt: DateTime.utc(2026, 7, 19),
  ),
  sessionsByWorkBead: sessions,
);

/// A molecule-model session: the EXPLICIT `isMolecule` discriminator plus its
/// own bucketed `type=step` beads — the flat `cursor` stays EMPTY by
/// construction (the drain guarantee: a molecule session never writes
/// `grid.cursor.*`) unless a test plants one as an inference TRIPWIRE.
SessionProjection _molecule(
  List<Bead> steps, {
  List<BeadDependency> dependencies = const [],
  bool terminal = false,
  CircuitCursor cursor = const {},
}) => SessionProjection(
  workBeadId: 'tg-m',
  sessionId: 'tgdog-m',
  isTerminal: terminal,
  isMolecule: true,
  cursor: cursor,
  moleculeBeads: steps,
  moleculeDependencies: dependencies,
);

/// One `type=step` bead carrying its fine state under `grid.step.*` — mirrors
/// molecule_codec_test.dart's builder.
Bead _step(
  String id,
  String nodePath, {
  StepState? state,
  DateTime? cooldownUntil,
  bool closed = false,
}) => Bead(
  id: id,
  issueType: IssueType.step,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {
    MoleculeStepKeys.path: nodePath,
    if (state != null) MoleculeStepKeys.state: state.name,
    if (cooldownUntil != null)
      MoleculeStepKeys.cooldownUntil: cooldownUntil.toUtc().toIso8601String(),
  },
);

/// ALL-terminal steps: a closed `complete` step plus a `ready` daemon — both
/// POSITIVE TERMINALS, never an active stage and never a gate.
SessionProjection _allTerminal({bool terminal = false}) => _molecule([
  _step('tgdog-s1', 'tg-m/build', state: StepState.complete, closed: true),
  _step('tgdog-s2', 'tg-m/serve', state: StepState.ready),
], terminal: terminal);

SessionProjection _flatRunning() => const SessionProjection(
  workBeadId: 'tg-x',
  sessionId: 'tgdog-x',
  cursor: {'tg-x/build': NodeCursor(state: StepState.running)},
);

SessionProjection _flatGated() => const SessionProjection(
  workBeadId: 'tg-x',
  sessionId: 'tgdog-x',
  cursor: {'tg-x/spec_review': NodeCursor(state: StepState.gated)},
);

/// A hand-driven clock (Fakes, not mocks) — mirrors wedge_test.dart.
class _FakeClock {
  _FakeClock(this.now);
  DateTime now;
  void advance(Duration d) => now = now.add(d);
}

/// A hand-driven timer seam matching `StationDriver`'s — mirrors
/// wedge_test.dart.
class _FakeTimers {
  final List<void Function()> _callbacks = [];

  Timer schedule(Duration _, void Function() callback) {
    _callbacks.add(callback);
    return _FakeTimer(() => _callbacks.remove(callback));
  }

  void fireAll() {
    final due = List<void Function()>.from(_callbacks);
    _callbacks.clear();
    for (final callback in due) {
      callback();
    }
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this._onCancel);
  final void Function() _onCancel;
  var _active = true;

  @override
  void cancel() {
    _active = false;
    _onCancel();
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

/// The recording sink — the SHIPPED emit-only D-8 seam, faked.
class _FakeTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  List<String> get names => [for (final f in flares) f.name];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));
}
