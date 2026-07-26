import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';
import 'package:test/test.dart';

void main() {
  final startedAt = DateTime.utc(2026, 7, 25, 12);

  test('round-trips all fields and tolerates unknown keys', () {
    final record = StationLockRecord(
      pid: 1,
      pgid: 2,
      startedAt: startedAt,
      controlUrl: 'http://localhost:42',
      token: 'secret',
      vmServiceUri: 'http://localhost:43/x',
    );
    expect(
      StationLockRecord.fromJson({...record.toJson(), 'future': true}).toJson(),
      record.toJson(),
    );
  });

  test('omits optional fields', () {
    expect(
      StationLockRecord(pid: 1, pgid: 2, startedAt: startedAt).toJson().keys,
      ['pid', 'pgid', 'startedAt'],
    );
  });

  test('copy helpers preserve the other advertisement', () {
    final base = StationLockRecord(
      pid: 1,
      pgid: 2,
      startedAt: startedAt,
      vmServiceUri: 'http://vm',
    );
    final controlled = base.withControl(
      controlUrl: 'http://control',
      token: 'secret',
    );
    expect(controlled.vmServiceUri, 'http://vm');
    final withVm = controlled.withVmService('http://new-vm');
    expect(withVm.controlUrl, 'http://control');
    expect(withVm.token, 'secret');
    expect(withVm.vmServiceUri, 'http://new-vm');
  });
}
