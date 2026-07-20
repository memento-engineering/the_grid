import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

/// tg-jwh — wedge detection: the station computes + exposes a WEDGE state and
/// flares it LOUD (ADR-0008 D9's flare primitive, through the shipped
/// `ExplorationTransport` sink), distinct from a routine gate-open.
///
/// Post tg-eli phase 2 the sampler reads ONLY molecule step state, so the
/// session fixtures here are MOLECULE projections (isMolecule + `type=step`
/// beads); the predicate/monitor semantics under test are model-independent
/// and unchanged.
void main() {
  final t0 = DateTime.utc(2026, 7, 12, 10);

  group('sampleWedge — the pure derivation', () {
    test('all live sessions gated, none running → stalled', () {
      final sample = sampleWedge(
        _join({'tg-1': _gated(), 'tg-2': _gated()}),
        now: t0,
      );
      expect(sample.live, 2);
      expect(sample.running, 0);
      expect(sample.gated, 2);
      expect(sample.isStalled, isTrue);
      expect(sample.reason, contains('ALL 2'));
    });

    test('ONE gate while other work runs → NOT stalled (a routine gate-open is '
        'not a wedge)', () {
      final sample = sampleWedge(
        _join({'tg-1': _gated(), 'tg-2': _running()}),
        now: t0,
      );
      expect(sample.running, 1);
      expect(sample.gated, 1);
      expect(sample.isStalled, isFalse);
    });

    test(
      'a failed node with a FUTURE cooldown is forward progress (a restart is '
      'scheduled) → NOT stalled',
      () {
        final cooling = _join({
          'tg-1': _cooling(until: t0.add(const Duration(seconds: 30))),
        });
        final now = sampleWedge(cooling, now: t0);
        expect(now.cooling, 1);
        expect(now.isStalled, isFalse);
        // …but once the cooldown has LAPSED and nothing re-keyed, it IS a stall.
        final later = sampleWedge(
          cooling,
          now: t0.add(const Duration(minutes: 1)),
        );
        expect(later.cooling, 0);
        expect(later.isStalled, isTrue);
      },
    );

    test(
      'a rewind wave (A47: state=pending) is not "running" → stalled only if it '
      'never re-mounts',
      () {
        final sample = sampleWedge(_join({'tg-1': _pending()}), now: t0);
        expect(sample.running, 0);
        expect(
          sample.isStalled,
          isTrue,
          reason:
              'the THRESHOLD is what makes a momentary pending wave safe — '
              'not the predicate',
        );
      },
    );

    test(
      'a ZOMBIE running node reads as an ACTIVE STAGE — which is exactly why the '
      'stall was INVISIBLE for hours; reaping it to `pending` lets the station '
      'finally see the truth',
      () {
        // BEFORE the reap: the corpse still reads `running`, so the station calls
        // itself healthy and `station.wedged` can NEVER fire, no matter how long
        // the stall lasts.
        final zombie = _join({'pow-77g': _running()});
        expect(sampleWedge(zombie, now: t0).running, 1);
        expect(sampleWedge(zombie, now: t0).isStalled, isFalse);
        expect(
          sampleWedge(zombie, now: t0.add(const Duration(hours: 2))).isStalled,
          isFalse,
          reason: 'two hours on it STILL reports flowing — the observed silence',
        );

        // AFTER the reap: `pending` is not an active stage. In the happy case the
        // re-mounted step writes `running` within a flush (far under the wedge
        // threshold, so no false alarm); if it never re-mounts, the stall is
        // VISIBLE and the alarm can finally ripen.
        final reaped = _join({'pow-77g': _pending()});
        expect(sampleWedge(reaped, now: t0).running, 0);
        expect(sampleWedge(reaped, now: t0).isStalled, isTrue);
      },
    );

    test('terminal sessions never count; no live session → never stalled', () {
      final sample = sampleWedge(
        _join({'tg-1': _gated(terminal: true)}),
        now: t0,
      );
      expect(sample.live, 0);
      expect(sample.isStalled, isFalse);
      expect(sample.reason, 'no live session');
      expect(sampleWedge(_join({}), now: t0).isStalled, isFalse);
    });
  });

  group('WedgeMonitor — the sustain latch + the LOUD rising-edge flare', () {
    late _FakeClock clock;
    late _FakeTimers timers;
    late _FakeTransport transport;
    late Map<String, SessionProjection> sessions;
    late WedgeMonitor monitor;

    WedgeMonitor build({ExplorationTransport? sink}) => WedgeMonitor(
      latest: () => _join(sessions),
      threshold: const Duration(minutes: 10),
      pollInterval: const Duration(seconds: 30),
      transport: sink ?? transport,
      clock: () => clock.now,
      scheduleTimer: timers.schedule,
    );

    setUp(() {
      clock = _FakeClock(t0);
      timers = _FakeTimers();
      transport = _FakeTransport();
      sessions = {'tg-1': _gated(), 'tg-2': _gated()};
      monitor = build();
      addTearDown(() => monitor.dispose());
    });

    test('start() samples a baseline and arms the poll timer on a STALL', () {
      monitor.start();
      expect(monitor.state, isA<Stalling>());
      expect(timers.pending, 1);
      expect(transport.flares, isEmpty, reason: 'a fresh stall is not a wedge');
    });

    test(
      'a FLOWING station arms NO timer at all — the wall clock is only watched '
      'while a stall could ripen (and a cooling node is never stalled, so the '
      "backoff timer and this one can't both be armed)",
      () {
        sessions = {'tg-1': _running()};
        monitor.start();
        expect(monitor.state, isA<Flowing>());
        expect(timers.pending, 0);

        // …and a station that RESUMES lets its poll timer lapse.
        sessions = {'tg-1': _gated()};
        monitor.poll();
        expect(timers.pending, 1);
        sessions = {'tg-1': _running()};
        monitor.poll();
        expect(timers.pending, 0);
      },
    );

    test(
      'NO false wedge below the threshold — a between-stages gap stays Stalling',
      () {
        monitor.start();
        clock.advance(const Duration(minutes: 9, seconds: 59));
        timers.fireAll();
        final state = monitor.state;
        expect(state, isA<Stalling>());
        expect((state as Stalling).since, t0);
        expect(state.isWedged, isFalse);
        expect(state.toJson()['wedged'], isFalse);
        expect(transport.flares, isEmpty);
      },
    );

    test(
      'sustained past the threshold → Wedged, and station.wedged flares EXACTLY '
      'ONCE (never per-poll)',
      () {
        monitor.start();
        clock.advance(const Duration(minutes: 10));
        timers.fireAll();

        final state = monitor.state;
        expect(state, isA<Wedged>());
        expect((state as Wedged).since, t0);
        expect(state.toJson()['wedged'], isTrue);
        expect(state.toJson()['since'], t0.toIso8601String());
        expect(state.toJson()['reason'], contains('parked at a gate'));

        expect(transport.flares, hasLength(1));
        expect(transport.flares.single.name, 'station.wedged');
        expect(transport.flares.single.data['gated'], '2');
        expect(transport.flares.single.data['since'], t0.toIso8601String());

        // Twenty more polls while still wedged: still ONE flare.
        for (var i = 0; i < 20; i++) {
          clock.advance(const Duration(seconds: 30));
          timers.fireAll();
        }
        expect(monitor.state, isA<Wedged>());
        expect(
          transport.flares,
          hasLength(1),
          reason: 'LOUD once per episode, not spammy — the whole point',
        );
      },
    );

    test(
      'any running session clears the wedge (one station.unwedged), and a NEW '
      'episode flares again',
      () {
        monitor.start();
        clock.advance(const Duration(minutes: 10));
        timers.fireAll();
        expect(transport.names, ['station.wedged']);

        sessions['tg-1'] = _running();
        clock.advance(const Duration(seconds: 30));
        timers.fireAll();
        expect(monitor.state, isA<Flowing>());
        expect(monitor.state.toJson()['wedged'], isFalse);
        expect(transport.names, ['station.wedged', 'station.unwedged']);

        // Re-wedge: a fresh stall, a fresh threshold, a second flare. The
        // ENTRY into the new stall is detected by the flush that wrote it
        // (`StationDriver.afterFlush` → `poll`), which re-arms the timer that
        // then carries the stall past the threshold.
        sessions['tg-1'] = _gated();
        clock.advance(const Duration(seconds: 30));
        monitor.poll();
        expect(monitor.state, isA<Stalling>());
        clock.advance(const Duration(minutes: 10));
        timers.fireAll();
        expect(transport.names, [
          'station.wedged',
          'station.unwedged',
          'station.wedged',
        ]);
      },
    );

    test(
      'a throwing transport never breaks the poll (the swallow convention)',
      () {
        monitor.dispose();
        monitor = build(sink: _ThrowingTransport());
        monitor.start();
        clock.advance(const Duration(minutes: 10));
        expect(timers.fireAll, returnsNormally);
        expect(
          monitor.state,
          isA<Wedged>(),
          reason: 'the state still advances even though the sink threw',
        );
      },
    );

    test('a null transport still computes the state (flares to nobody — the '
        'offline posture of every engine flare today)', () {
      monitor.dispose();
      monitor = WedgeMonitor(
        latest: () => _join(sessions),
        threshold: const Duration(minutes: 10),
        clock: () => clock.now,
        scheduleTimer: timers.schedule,
      );
      monitor.start();
      clock.advance(const Duration(minutes: 10));
      timers.fireAll();
      expect(monitor.state, isA<Wedged>());
    });

    test('dispose cancels the poll timer', () {
      monitor.start();
      expect(timers.pending, 1);
      monitor.dispose();
      expect(timers.pending, 0);
    });
  });

  group(
    'derailment-invariant 1 — the wedge NEVER subscribes to a pipeline',
    () {
      test('positive control: the scan reads real wedge source', () {
        expect(_src('src/domain/wedge.dart'), contains('sampleWedge'));
        expect(
          _src('src/kernel/wedge_monitor.dart'),
          contains('class WedgeMonitor'),
        );
      });

      test('no listen / no notifier / no SnapshotSource in either file', () {
        for (final path in [
          'src/domain/wedge.dart',
          'src/kernel/wedge_monitor.dart',
        ]) {
          final source = _src(path);
          expect(
            source,
            isNot(contains('.listen(')),
            reason: '$path subscribes',
          );
          expect(
            source,
            isNot(contains('JoinedSnapshotNotifier')),
            reason: path,
          );
          expect(source, isNot(contains('SnapshotSource')), reason: path);
          expect(source, isNot(contains('.snapshots')), reason: path);
        }
      });
    },
  );
}

String _src(String relative) {
  final libUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:grid_engine/grid_engine.dart'),
  );
  return File.fromUri(libUri!.resolve(relative)).readAsStringSync();
}

JoinedSnapshot _join(Map<String, SessionProjection> sessions) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: const [],
    dependencies: const [],
    readyIds: const [],
    capturedAt: DateTime.utc(2026, 7, 12),
  ),
  sessionsByWorkBead: sessions,
);

/// One `type=step` bead carrying its fine state under `grid.step.*` — the
/// molecule sampling substrate (mirrors wedge_molecule_test.dart's builder).
Bead _step(
  String nodePath, {
  required StepState state,
  DateTime? cooldownUntil,
}) => Bead(
  id: 'tgdog-step-${nodePath.replaceAll('/', '-')}',
  issueType: IssueType.step,
  status: BeadStatus.open,
  metadata: {
    MoleculeStepKeys.path: nodePath,
    MoleculeStepKeys.state: state.name,
    if (cooldownUntil != null)
      MoleculeStepKeys.cooldownUntil: cooldownUntil.toUtc().toIso8601String(),
  },
);

SessionProjection _molecule(List<Bead> steps, {bool terminal = false}) =>
    SessionProjection(
      workBeadId: 'tg-x',
      sessionId: 'tgdog-x',
      isTerminal: terminal,
      isMolecule: true,
      moleculeBeads: steps,
    );

SessionProjection _gated({bool terminal = false}) => _molecule([
  _step('tg-x/spec_review', state: StepState.gated),
], terminal: terminal);

SessionProjection _running() =>
    _molecule([_step('tg-x/build', state: StepState.running)]);

SessionProjection _pending() =>
    _molecule([_step('tg-x/build', state: StepState.pending)]);

SessionProjection _cooling({required DateTime until}) => _molecule([
  _step('tg-x/build', state: StepState.failed, cooldownUntil: until),
]);

/// A hand-driven clock (Fakes, not mocks).
class _FakeClock {
  _FakeClock(this.now);
  DateTime now;
  void advance(Duration d) => now = now.add(d);
}

/// A hand-driven timer seam matching `StationDriver`'s: records the one-shot the
/// monitor re-arms and fires it on demand — no real wall-clock wait.
class _FakeTimers {
  final List<void Function()> _callbacks = [];

  int get pending => _callbacks.length;

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

/// A sink that throws — the station must not care.
class _ThrowingTransport implements ExplorationTransport {
  @override
  void flare(String name, Map<String, String> data) =>
      throw StateError('sink down');
}
