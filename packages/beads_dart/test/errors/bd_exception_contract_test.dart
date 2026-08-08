import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

const guardMismatchEnvelope =
    '{"schema_version":1,"data":{"error":"guard mismatch",'
    '"guard_mismatch":true}}';
const partialFailureStderr =
    'Error updating tg-missing: no issue found\n'
    '{"schema_version":1,"data":{"error":"1 of 3 issues failed to update",'
    '"failed":[{"id":"tg-missing","error":"no issue found"}]}}\n';
const readyRefusalStderr = 'Error: --ready cannot be combined with --status\n';

void main() {
  test(
    'exit 13 guard mismatch is typed and unmarked exit 13 stays generic',
    () {
      final guard = BdException.fromOutput(
        command: const [
          'bd',
          'update',
          'tg-1',
          '--if-status',
          'open',
          '--json',
        ],
        exitCode: 13,
        stdout: guardMismatchEnvelope,
        stderr: '',
      );
      expect(guard, isA<BdGuardMismatch>());

      final unmarked = BdException.fromOutput(
        command: const ['bd', 'update', 'tg-1', '--json'],
        exitCode: 13,
        stdout: '{"schema_version":1,"data":{"error":"update failed"}}',
        stderr: '',
      );
      expect(unmarked, isA<BdCommandFailed>());
    },
  );

  test('multi-ID partial failure parses the final stderr-line report', () {
    final partial = BdException.fromOutput(
      command: const ['bd', 'update', 'tg-1', 'tg-missing', 'tg-2', '--json'],
      exitCode: 1,
      stdout: '{"schema_version":1,"data":[]}',
      stderr: partialFailureStderr,
    );
    expect(
      partial,
      isA<BdUpdatePartialFailure>()
          .having((e) => e.failures.length, 'failure count', 1)
          .having((e) => e.failures.single.id, 'failed id', 'tg-missing')
          .having(
            (e) => e.failures.single.error,
            'per-id error',
            'no issue found',
          ),
    );

    final malformed = BdException.fromOutput(
      command: const ['bd', 'update', 'tg-1', 'tg-2', '--json'],
      exitCode: 1,
      stdout: '{"schema_version":1,"data":[]}',
      stderr: 'Error updating tg-2\n{malformed}\n',
    );
    expect(malformed, isA<BdCommandFailed>());
  });

  test('ready refusal is usage while unrelated exit 2 stays generic', () {
    final usage = BdException.fromOutput(
      command: const ['bd', 'list', '--ready', '--status', 'open', '--json'],
      exitCode: 2,
      stdout: '',
      stderr: readyRefusalStderr,
    );
    expect(usage, isA<BdUsageException>());

    final unrelated = BdException.fromOutput(
      command: const ['bd', 'show', 'tg-1', '--json'],
      exitCode: 2,
      stdout: '',
      stderr: 'Error: invalid invocation\n',
    );
    expect(unrelated, isA<BdCommandFailed>());
  });
}
