// M6 Track D — the COMPUTE domain's value types + capacity predicate.
//
// Pure value-type round-trips (the payloads moved out of the kind-agnostic
// federation core, ADR-0011 D3) + the domain-owned declare-and-check capacity
// predicate. Zero I/O.
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

void main() {
  group('compute payloads round-trip', () {
    test('DispatchCommand JSON round-trip (command/args/workdir)', () {
      const cmd = DispatchCommand(
        command: 'echo',
        args: ['hi', 'there'],
        workdir: '/w',
      );
      final back = DispatchCommand.fromJson(cmd.toJson());
      expect(back.command, 'echo');
      expect(back.args, ['hi', 'there']);
      expect(back.workdir, '/w');
    });

    test('DispatchCommand omits a null workdir + defaults args to empty', () {
      const cmd = DispatchCommand(command: 'uname');
      expect(cmd.toJson().containsKey('workdir'), isFalse);
      final back = DispatchCommand.fromJson(cmd.toJson());
      expect(back.args, isEmpty);
      expect(back.workdir, isNull);
    });

    test('CommandResult JSON round-trip + ok', () {
      const r = CommandResult(
        exitCode: 0,
        stdout: 'out',
        stderr: '',
        durationMs: 7,
      );
      final back = CommandResult.fromJson(r.toJson());
      expect(back.exitCode, 0);
      expect(back.stdout, 'out');
      expect(back.durationMs, 7);
      expect(back.ok, isTrue);
      expect(
        const CommandResult(
          exitCode: 2,
          stdout: '',
          stderr: 'boom',
          durationMs: 1,
        ).ok,
        isFalse,
      );
    });
  });

  group('computeHasCapacity — the domain capacity predicate (ADR-0011 D3)', () {
    test('grantable iff the compute kind AND a slot is free', () {
      expect(computeHasCapacity(kind: kComputeKind, available: 1), isTrue);
      expect(computeHasCapacity(kind: kComputeKind, available: 5), isTrue);
    });

    test('denies when no slot is free', () {
      expect(computeHasCapacity(kind: kComputeKind, available: 0), isFalse);
    });

    test('denies a non-compute kind even with capacity', () {
      expect(computeHasCapacity(kind: 'gpu', available: 3), isFalse);
      expect(computeHasCapacity(kind: 'agent-slot', available: 3), isFalse);
    });
  });
}
