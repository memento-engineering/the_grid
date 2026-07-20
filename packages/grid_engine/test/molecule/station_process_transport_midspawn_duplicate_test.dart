// tg-090 repair round 1 — the MID-SPAWN duplicate-acquire window.
//
// `SubprocessProvider.start` reserves the session name SYNCHRONOUSLY, then
// awaits the spawner before stamping `pid` — so between the reservation and
// the stamp there is a real window where the session is genuinely alive but
// BOTH synchronous surfaces (`identityOf`, `terminalOf`) report null. A
// duplicate acquire racing into that window (a re-fired ready event — the
// exact race the original code's comment called expected/handled) must WAIT
// for the `SessionStarted` its own already-open subscription WILL receive
// when the spawn lands — not fail the acquire LOUD for a session that was
// never dead (the over-correction the round-1 verifier confirmed with a
// gated-spawner probe against a real SubprocessProvider; this test is that
// probe, kept).
//
// The D5 posture is kept: a reservation that VANISHES with no event (the
// in-flight spawn failed) and a transport that can never stamp an identity
// still fail LOUD, never an unbounded silent wait.
//
// Fully offline (Fakes, not mocks): a real SubprocessProvider over a gated
// fake spawner + a fake process-group controller.
import 'dart:async';
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _name = 'tgdog-s/tg-1/lease';

class _JobCap extends ProcessCapability {
  const _JobCap();

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) =>
      const RuntimeConfig(workDir: '/tmp/tg-1', command: 'sh');

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };
}

ProcessLeaseRequest _request(RuntimeProvider transport) => ProcessLeaseRequest(
  stepBeadId: 'tgdog-step-midspawn',
  capability: const _JobCap(),
  allocation: AllocationContext(
    treeContext: FakeTreeContext(),
    args: stepArgs('tg-1/lease'),
    transport: transport,
    address: const AllocationAddress('tgdog-s', 'tg-1/lease'),
    env: const {'GRID_INSTANCE_TOKEN': 'tok-midspawn'},
    sink: (_) {},
  ),
);

/// A spawner whose spawn parks on [gate] — holding the provider inside the
/// reserved-but-pid-unset window — and signals [entered] once it is there.
class _GatedSpawner implements SubprocessSpawner {
  final Completer<void> gate = Completer<void>();
  final Completer<void> entered = Completer<void>();

  @override
  Future<SpawnedProcess> spawn({
    required String executable,
    required List<String> args,
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    entered.complete();
    await gate.future;
    return _FakeSpawned(4242);
  }
}

class _FakeSpawned implements SpawnedProcess {
  _FakeSpawned(this.pid);

  @override
  final int pid;

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Future<int>? get exitCode => null;
}

class _FakeGroups implements ProcessGroupController {
  @override
  Future<int?> resolvePgid(int pid) async => pid;

  @override
  bool processAlive(int pid) => true;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) => true;

  @override
  int currentGroupId() => 999999;
}

SubprocessProvider _provider(_GatedSpawner spawner) => SubprocessProvider(
  spawner: spawner,
  groupController: _FakeGroups(),
  parentEnvironment: const {},
  agentDeadline: null,
);

void main() {
  test('a duplicate acquire racing an IN-FLIGHT spawn of the same name '
      '(reserved, pid not yet stamped) resolves once the spawn lands — '
      'never a LOUD failure for a session that was never dead', () async {
    final spawner = _GatedSpawner();
    final provider = _provider(spawner);
    addTearDown(provider.dispose);

    // The ORIGINAL acquire: its spawn parks mid-flight — the name is
    // reserved, `identityOf`/`terminalOf` both report null.
    final first = stationProcessSpawner(
      _request(provider),
      FakeTreeContext(),
      stepArgs('tg-1/lease'),
    );
    await spawner.entered.future;
    expect(provider.isRunning(_name), isTrue, reason: 'reserved');
    expect(provider.identityOf(_name), isNull, reason: 'pid not stamped');
    expect(provider.terminalOf(_name), isNull);

    // The DUPLICATE acquire races into the window: its own `start` throws
    // SessionAlreadyExists while the original spawn is still gated.
    final second = stationProcessSpawner(
      _request(provider),
      FakeTreeContext(),
      stepArgs('tg-1/lease'),
    );
    // Let the duplicate reach and handle SessionAlreadyExists.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // The spawn LANDS: `SessionStarted` fires and BOTH acquires resolve.
    spawner.gate.complete();
    final h1 = await first.timeout(const Duration(seconds: 5));
    final h2 = await second.timeout(const Duration(seconds: 5));

    expect(h1.pid, 4242);
    expect(h2.pid, 4242, reason: 'the duplicate bound the SAME live group');
    expect(h2.pgid, 4242);
    expect(h2.token, 'tok-midspawn');
    await h1.events?.close();
    await h2.events?.close();
  });

  test('a duplicate acquire racing an in-flight spawn that FAILS (the '
      'reservation vanishes with no event) still fails LOUD — never an '
      'unbounded silent wait', () async {
    final spawner = _GatedSpawner();
    final provider = _provider(spawner);
    addTearDown(provider.dispose);

    final first = stationProcessSpawner(
      _request(provider),
      FakeTreeContext(),
      stepArgs('tg-1/lease'),
    );
    await spawner.entered.future;

    final second = stationProcessSpawner(
      _request(provider),
      FakeTreeContext(),
      stepArgs('tg-1/lease'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // The original spawn EXPLODES: the provider deregisters the name and
    // rethrows — no event will ever fire for it.
    spawner.gate.completeError(StateError('spawn exploded'));

    await expectLater(
      first,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('spawn exploded'),
        ),
      ),
    );
    await expectLater(
      second.timeout(const Duration(seconds: 5)),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('vanished'),
        ),
      ),
    );
  });

  test('a transport that holds the name but can NEVER stamp an identity (the '
      'dry-run duplicate shape) fails LOUD at the reservation deadline — the '
      'D5 posture, kept bounded', () async {
    // FakeRuntimeProvider with no staged identity: isRunning true forever,
    // identityOf/terminalOf null forever.
    final transport = FakeRuntimeProvider();
    addTearDown(transport.close);
    await transport.start(
      _name,
      const RuntimeConfig(workDir: '/tmp/tg-1', command: 'sh'),
    );
    transport.throwOnStart = SessionAlreadyExists(_name);

    await expectLater(
      stationProcessSpawner(
        _request(transport),
        FakeTreeContext(),
        stepArgs('tg-1/lease'),
        reservationDeadline: const Duration(milliseconds: 200),
        reservationPollPeriod: const Duration(milliseconds: 20),
      ).timeout(const Duration(seconds: 5)),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('neither an identity nor a terminal'),
        ),
      ),
    );
  });
}
