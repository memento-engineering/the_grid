import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';
import 'package:test/test.dart';

void main() {
  final startedAt = DateTime.utc(2026, 7, 25, 12);

  test('round-trips every lifecycle phase and tolerates unknown keys', () {
    for (final phase in StationLifecyclePhase.values) {
      final record = StationLockRecord(
        pid: 1,
        pgid: 2,
        startedAt: startedAt,
        phase: phase,
        controlUrl: 'http://localhost:42',
        token: 'secret',
        vmServiceUri: 'http://localhost:43/x',
      );
      expect(
        StationLockRecord.fromJson({
          ...record.toJson(),
          'future': true,
        }).toJson(),
        record.toJson(),
      );
      expect(record.toJson()['phase'], phase.name);
    }
  });

  test('emits phase and omits absent advertisement fields', () {
    expect(
      StationLockRecord(pid: 1, pgid: 2, startedAt: startedAt).toJson().keys,
      ['pid', 'pgid', 'startedAt', 'phase'],
    );
  });

  test('legacy JSON without phase reads as live', () {
    final record = StationLockRecord.fromJson(<String, Object?>{
      'pid': 1,
      'pgid': 2,
      'startedAt': startedAt.toIso8601String(),
    });

    expect(record.phase, StationLifecyclePhase.live);
  });

  test('wrong-type and unknown phases are malformed', () {
    Map<String, Object?> json(Object? phase) => <String, Object?>{
      'pid': 1,
      'pgid': 2,
      'startedAt': startedAt.toIso8601String(),
      'phase': phase,
    };

    expect(() => StationLockRecord.fromJson(json(null)), throwsFormatException);
    expect(() => StationLockRecord.fromJson(json(7)), throwsFormatException);
    expect(
      () => StationLockRecord.fromJson(json('booting')),
      throwsFormatException,
    );
  });

  test('copy helpers preserve phase and every unrelated field', () {
    final base = StationLockRecord(
      pid: 1,
      pgid: 2,
      startedAt: startedAt,
      phase: StationLifecyclePhase.acquired,
      vmServiceUri: 'http://vm',
    );
    final controlled = base.withControl(
      controlUrl: 'http://control',
      token: 'secret',
    );
    expect(controlled.phase, StationLifecyclePhase.acquired);
    expect(controlled.vmServiceUri, 'http://vm');
    final withVm = controlled.withVmService('http://new-vm');
    expect(withVm.phase, StationLifecyclePhase.acquired);
    expect(withVm.controlUrl, 'http://control');
    expect(withVm.token, 'secret');
    expect(withVm.vmServiceUri, 'http://new-vm');
    final releasing = withVm.withPhase(StationLifecyclePhase.releasing);
    expect(releasing.phase, StationLifecyclePhase.releasing);
    expect(releasing.pid, withVm.pid);
    expect(releasing.pgid, withVm.pgid);
    expect(releasing.startedAt, withVm.startedAt);
    expect(releasing.controlUrl, withVm.controlUrl);
    expect(releasing.token, withVm.token);
    expect(releasing.vmServiceUri, withVm.vmServiceUri);
  });
}
