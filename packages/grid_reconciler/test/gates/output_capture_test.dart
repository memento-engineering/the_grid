import 'dart:convert';

import 'package:grid_reconciler/src/convergence/gate_outcome.dart';
import 'package:grid_reconciler/src/convergence/go_duration.dart';
import 'package:grid_reconciler/src/gates/condition_env.dart';
import 'package:grid_reconciler/src/gates/gate_runner_service.dart';
import 'package:grid_reconciler/src/gates/output_capture.dart';
import 'package:test/test.dart';

import 'support/fake_process_runner.dart';

/// Byte-only truncation + bounded capture (gates-exec.md §6,
/// conformance-gate-tests §3.3 capture rows + §5 gap 10).
void main() {
  group('truncateOutput (capture.go:47-69)', () {
    test('under the limit → not truncated, decoded as-is', () {
      final r = truncateOutput(utf8.encode('hello'), maxOutputBytes);
      expect(r.text, 'hello');
      expect(r.truncated, isFalse);
    });

    test('exactly at the limit → not truncated', () {
      final data = List<int>.filled(maxOutputBytes, 0x61); // 4096 × 'a'
      final r = truncateOutput(data, maxOutputBytes);
      expect(r.text.length, maxOutputBytes);
      expect(r.truncated, isFalse);
    });

    test('over the limit (5096 ASCII) → trimmed to ≤4096, truncated', () {
      final data = List<int>.filled(5096, 0x30); // '0'
      final r = truncateOutput(data, maxOutputBytes);
      expect(r.text.length, lessThanOrEqualTo(maxOutputBytes));
      expect(r.truncated, isTrue);
    });

    test('maxBytes <= 0 → empty input not truncated, non-empty truncated', () {
      expect(truncateOutput(const <int>[], 0), (text: '', truncated: false));
      expect(truncateOutput(utf8.encode('x'), 0), (text: '', truncated: true));
    });

    test('UTF-8 rune-boundary backoff: a 4-byte rune is never split', () {
      // Fill with 4094 ASCII then a 4-byte rune (😀 = F0 9F 98 80) straddling
      // the 4096 boundary: bytes 4094..4097. Truncation must back off to 4094.
      final bytes = <int>[
        ...List<int>.filled(4094, 0x61),
        ...utf8.encode('\u{1F600}'),
        ...List<int>.filled(10, 0x62),
      ];
      final r = truncateOutput(bytes, maxOutputBytes);
      expect(r.truncated, isTrue);
      // The emoji must be wholly present or wholly absent — never a partial
      // rune. Decoding the result must not yield a replacement char from a
      // split rune at the seam.
      expect(r.text.endsWith('a'), isTrue);
      expect(r.text.contains('\u{FFFD}'), isFalse);
    });
  });

  group('BoundedByteSink (capture.go:17-43)', () {
    test('retains up to maxBytes, flags overflow, discards the rest', () {
      final sink = BoundedByteSink(4);
      sink.add(<int>[1, 2, 3]);
      sink.add(<int>[4, 5, 6]); // 4 retained, 5/6 dropped.
      expect(sink.bytes, <int>[1, 2, 3, 4]);
      expect(sink.overflowed, isTrue);
    });

    test('exact fill does not overflow', () {
      final sink = BoundedByteSink(3)..add(<int>[1, 2, 3]);
      expect(sink.overflowed, isFalse);
    });
  });

  group('runner truncation wiring', () {
    GateRunnerService runner(FakeProcessRunner fake) => GateRunnerService(
      processRunner: fake,
      ambientEnvironment: const <String, String>{},
      lookPathDir: fakeLookPath(const <String, String>{}),
      tempDir: '/tmp',
    );

    test('over-limit stdout → pass, stdout ≤ 4096B, Truncated true', () async {
      final fake = FakeProcessRunner()
        ..stub(
          '/s.sh',
          FakeRun.exitedBytes(0, stdoutBytes: List<int>.filled(5096, 0x30)),
        );
      final result = await runner(fake).runOnce(
        scriptPath: '/s.sh',
        env: const ConditionEnv(cityPath: '/c'),
        timeout: const GoDuration(5000000000),
      );

      expect(result.outcome, GateOutcome.pass);
      expect(result.stdout.length, lessThanOrEqualTo(maxOutputBytes));
      expect(result.truncated, isTrue);
    });

    test('stream overflow flag alone sets Truncated (capture.go:31)', () async {
      final fake = FakeProcessRunner()
        ..stub(
          '/s.sh',
          FakeRun.exitedBytes(
            0,
            stdoutBytes: const <int>[0x6f, 0x6b],
            stdoutOverflowed: true,
          ),
        );
      final result = await runner(fake).runOnce(
        scriptPath: '/s.sh',
        env: const ConditionEnv(cityPath: '/c'),
        timeout: const GoDuration(5000000000),
      );

      expect(result.truncated, isTrue);
    });

    test('normal small output is not truncated', () async {
      final fake = FakeProcessRunner()
        ..stub(
          '/s.sh',
          FakeRun.pass(stdout: 'stdout-data', stderr: 'stderr-data'),
        );
      final result = await runner(fake).runOnce(
        scriptPath: '/s.sh',
        env: const ConditionEnv(cityPath: '/c'),
        timeout: const GoDuration(5000000000),
      );

      expect(result.stdout, contains('stdout-data'));
      expect(result.stderr, contains('stderr-data'));
      expect(result.truncated, isFalse);
    });
  });
}
