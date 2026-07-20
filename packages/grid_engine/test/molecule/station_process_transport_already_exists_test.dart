// tg-090 regression (defect D5): the SessionAlreadyExists swallow. For a
// session that ALREADY existed, `SessionStarted` fired before this
// incarnation subscribed and never re-fires — the pre-fix spawner swallowed
// the throw and kept awaiting `started.future` forever (no
// AllocationStarted, no state=running stamp, no timeout). The fixed spawner
// resolves the handle from the transport's SYNCHRONOUS surface
// (`identityOf` for a live session, `terminalOf` for an already-dead one)
// or fails the acquire LOUD — never an unbounded silent wait.
//
// Fully offline (Fakes, not mocks).
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _name = 'tgdog-s/tg-1/lease';
const _config = RuntimeConfig(workDir: '/tmp/tg-1', command: 'sh');

class _JobCap extends ProcessCapability {
  const _JobCap();

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => _config;

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };
}

ProcessLeaseRequest _request(
  FakeRuntimeProvider transport,
  AllocationSink sink,
) => ProcessLeaseRequest(
  stepBeadId: 'tgdog-step-exists',
  capability: const _JobCap(),
  allocation: AllocationContext(
    treeContext: FakeTreeContext(),
    args: stepArgs('tg-1/lease'),
    transport: transport,
    address: const AllocationAddress('tgdog-s', 'tg-1/lease'),
    env: const {'GRID_INSTANCE_TOKEN': 'tok-exists'},
    sink: sink,
  ),
);

void main() {
  test(
    'an already-LIVE session resolves the handle from the synchronous '
    'surface (identityOf) instead of hanging',
    () async {
      final transport = FakeRuntimeProvider();
      addTearDown(transport.close);
      // The pre-existing incarnation: live before this acquire subscribes,
      // so no SessionStarted will ever reach it.
      await transport.start(_name, _config);
      transport.identities[_name] = (pid: 77, pgid: 88);
      transport.throwOnStart = SessionAlreadyExists(_name);

      final reports = <AllocationReport>[];
      final handle =
          await stationProcessSpawner(
            _request(transport, reports.add),
            FakeTreeContext(),
            stepArgs('tg-1/lease'),
          ).timeout(const Duration(seconds: 2));

      expect(handle.pid, 77);
      expect(handle.pgid, 88);
      expect(handle.token, 'tok-exists');
      expect(
        reports.whereType<AllocationStarted>().single.pid,
        77,
        reason: 'the host still persists state=running',
      );
      await handle.events?.close();
    },
  );

  test(
    'an already-DEAD session fails the acquire LOUD from the retained '
    'terminal — a supervised failure, never an unbounded wait',
    () async {
      final transport = FakeRuntimeProvider();
      addTearDown(transport.close);
      await transport.start(_name, _config);
      // The prior incarnation ended before this acquire ran; its terminal is
      // retained state on the transport.
      transport.emit(const Exited(name: _name, exitCode: 0, inferred: true));
      transport.throwOnStart = SessionAlreadyExists(_name);

      await expectLater(
        stationProcessSpawner(
          _request(transport, (_) {}),
          FakeTreeContext(),
          stepArgs('tg-1/lease'),
        ).timeout(const Duration(seconds: 2)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('already ended'),
          ),
        ),
      );
    },
  );

  test(
    'neither a live identity nor a retained terminal: acquire still fails '
    'LOUD rather than waiting on a SessionStarted that never re-fires',
    () async {
      final transport = FakeRuntimeProvider();
      addTearDown(transport.close);
      transport.throwOnStart = SessionAlreadyExists(_name);

      await expectLater(
        stationProcessSpawner(
          _request(transport, (_) {}),
          FakeTreeContext(),
          stepArgs('tg-1/lease'),
        ).timeout(const Duration(seconds: 2)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('never re-fire'),
          ),
        ),
      );
    },
  );
}
