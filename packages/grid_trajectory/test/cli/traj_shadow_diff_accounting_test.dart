/// The round-disqualification gating (stage1-wiring §2.5/§3): a run whose
/// append accounting is dirty — or simply absent — cannot mint a clean round,
/// however clean the comparison itself came out.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';

const String _session = 'tranquility-5xk';

class _AgreeingCompare implements ShadowCompare {
  const _AgreeingCompare([this.mismatches = const []]);

  final List<ShadowMismatch> mismatches;

  @override
  Set<String> get comparableFields => const {'status', 'outcome'};

  @override
  String? get unavailableReason => null;

  @override
  Future<ShadowCompareResult> compare({
    required String sessionId,
    required SubjectRecords records,
    int? round,
    ShadowCorroboration corroboration = const ShadowCorroboration.none(),
  }) async => ShadowCompareResult(mismatches);
}

TrajectoryEnvelope _row(int seq) => envelope(
  recordType: 'attempt.note',
  family: TrajectoryFamily.attempt,
  seq: seq,
  sessionId: _session,
  payload: {'body': 'n$seq', 'channel': 'operator', 'note_ordinal': seq},
);

Future<(int, String)> _run({
  ShadowRunAccounting? accounting,
  ShadowAccountingSource? accountingFor,
  ShadowCompare compare = const _AgreeingCompare(),
}) async {
  final out = <String>[];
  final code = await runTrajShadowDiff(
    gridHome: '/grid',
    open: openerFor(TrajectoryOpened(ScriptedReader([_row(1)]))),
    compare: compare,
    accounting: accounting,
    accountingFor: accountingFor,
    out: out.add,
    err: out.add,
  );
  return (code, out.join('\n'));
}

final class _ByteConsumer implements StreamConsumer<List<int>> {
  final _bytes = <int>[];

  String get text => utf8.decode(_bytes);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _bytes.addAll(chunk);
    }
  }

  @override
  Future<void> close() async {}
}

final class _RecordingSink implements Stdout {
  _RecordingSink(_ByteConsumer consumer) : _sink = IOSink(consumer);

  final IOSink _sink;

  @override
  Encoding get encoding => _sink.encoding;
  @override
  set encoding(Encoding value) => _sink.encoding = value;
  @override
  String lineTerminator = '\n';
  @override
  Future<void> get done => _sink.done;
  @override
  bool get hasTerminal => false;
  @override
  int get terminalColumns => 80;
  @override
  int get terminalLines => 24;
  @override
  bool get supportsAnsiEscapes => false;
  @override
  IOSink get nonBlocking => _sink;
  @override
  void add(List<int> data) => _sink.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _sink.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _sink.addStream(stream);
  @override
  Future<void> close() => _sink.close();
  @override
  Future<void> flush() => _sink.flush();
  @override
  void write(Object? object) => _sink.write(object);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _sink.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _sink.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _sink.writeln(object);
}

Future<({int? code, String stderr, String stdout})> _runCommand({
  List<String> flags = const [],
  ShadowCompare compare = const _AgreeingCompare(),
  ShadowAccountingSource? accountingFor,
}) async {
  final stdoutBytes = _ByteConsumer();
  final stdoutSink = _RecordingSink(stdoutBytes);
  final stderrBytes = _ByteConsumer();
  final stderrSink = _RecordingSink(stderrBytes);
  final runner = CommandRunner<int>('grid', 'test')
    ..addCommand(
      TrajCommand(
        open: openerFor(TrajectoryOpened(ScriptedReader([_row(1)]))),
        compare: compare,
        accountingFor: accountingFor,
      ),
    );
  final code = await IOOverrides.runZoned(
    () => runner.run([
      'traj',
      'shadow-diff',
      '--state-workspace',
      '/tmp',
      ...flags,
    ]),
    stdout: () => stdoutSink,
    stderr: () => stderrSink,
  );
  await Future.wait([stdoutSink.flush(), stderrSink.flush()]);
  return (code: code, stderr: stderrBytes.text, stdout: stdoutBytes.text);
}

void main() {
  group('accounting observations', () {
    test('observed zero remains distinct from a missing counter', () {
      const accounting = ShadowRunAccounting(dropped: 0, suppressed: null);

      expect(accounting.dropped, 0);
      expect(accounting.suppressed, isNull);
      expect(accounting.isComplete, isFalse);
    });

    test('both observed counters make complete accounting', () {
      const accounting = ShadowRunAccounting(
        dropped: 0,
        suppressed: 0,
        mode: 'live',
        epoch: 7,
      );

      expect(accounting.isComplete, isTrue);
      expect(accounting.disqualification, isNull);
      expect(
        accounting.summary,
        'dropped: 0, suppressed: 0, mode: live, epoch: 7',
      );
    });

    test('partial summaries name the missing observation and disqualify', () {
      const missingSuppressed = ShadowRunAccounting(
        dropped: 3,
        suppressed: null,
      );
      const missingDropped = ShadowRunAccounting(dropped: null, suppressed: 4);

      expect(missingSuppressed.summary, 'dropped: 3, suppressed: NOT SUPPLIED');
      expect(missingDropped.summary, 'dropped: NOT SUPPLIED, suppressed: 4');
      expect(missingSuppressed.disqualification, 'append accounting UNKNOWN');
      expect(missingDropped.disqualification, 'append accounting UNKNOWN');
    });

    test(
      'complete positive counters retain their disqualification wording',
      () {
        const accounting = ShadowRunAccounting(dropped: 2, suppressed: 3);

        expect(
          accounting.disqualification,
          '2 dropped and 3 suppressed appends',
        );
      },
    );
  });

  group('the disqualification rule', () {
    test('zero drops is the clean round', () async {
      final (code, text) = await _run(
        accounting: const ShadowRunAccounting(
          dropped: 0,
          suppressed: 0,
          mode: 'live',
        ),
      );
      expect(code, 0);
      expect(text, contains('append accounting: dropped: 0, suppressed: 0'));
      expect(text, contains('— clean'));
      expect(text, contains('one clean run toward the criterion'));
    });

    test('ANY dropped append disqualifies a zero-mismatch run', () async {
      final (code, text) = await _run(
        accounting: const ShadowRunAccounting(dropped: 1, suppressed: 0),
      );
      // Not a blocked cut — nothing diverged — but emphatically not a clean
      // round: the drop is a record the comparison could not have missed.
      expect(code, 0);
      expect(text, contains('DISQUALIFYING (1 dropped append)'));
      expect(text, contains('does NOT count toward the 3-clean-round'));
      expect(text, isNot(contains('one clean run')));
    });

    test('suppressed appends disqualify on the same grounds', () async {
      final (code, text) = await _run(
        accounting: const ShadowRunAccounting(
          dropped: 0,
          suppressed: 4,
          mode: 'halted',
        ),
      );
      expect(code, 0);
      expect(text, contains('4 suppressed appends'));
      expect(text, contains('the recorder was latched'));
      expect(text, isNot(contains('one clean run')));
    });

    test('both counters are named in one reason', () async {
      final (_, text) = await _run(
        accounting: const ShadowRunAccounting(dropped: 2, suppressed: 3),
      );
      expect(text, contains('2 dropped and 3 suppressed appends'));
    });

    test('UNKNOWN accounting does not count either', () async {
      final (code, text) = await _run();
      expect(code, 0);
      expect(text, contains('append accounting: UNKNOWN'));
      expect(text, contains('--dropped'));
      expect(text, isNot(contains('one clean run')));
    });

    test('an unexplained mismatch still BLOCKS, whatever the '
        'accounting says', () async {
      final (code, text) = await _run(
        accounting: const ShadowRunAccounting(dropped: 9, suppressed: 0),
        compare: const _AgreeingCompare([
          ShadowMismatch(
            sessionId: _session,
            field: 'outcome',
            legacyValue: 'failed',
            foldValue: 'succeeded',
            seq: 12,
          ),
        ]),
      );
      expect(code, 1);
      expect(text, contains('BLOCKED'));
    });

    test('named gaps are counted by class in the report', () async {
      final (code, text) = await _run(
        accounting: const ShadowRunAccounting(dropped: 0, suppressed: 0),
        compare: const _AgreeingCompare([
          ShadowMismatch(
            sessionId: _session,
            field: 'presence',
            legacyValue: 'present',
            foldValue: null,
            seq: null,
            classification: ShadowMismatchClass.nonAtomicCrash,
          ),
          ShadowMismatch(
            sessionId: _session,
            stepPath: 'build',
            field: 'step_attempt',
            legacyValue: 'ran',
            foldValue: null,
            seq: 4,
            classification: ShadowMismatchClass.stopRacesSpawn,
          ),
          ShadowMismatch(
            sessionId: _session,
            stepPath: 'review',
            field: 'step_attempt',
            legacyValue: 'ran',
            foldValue: null,
            seq: 5,
            classification: ShadowMismatchClass.stopRacesSpawn,
          ),
        ]),
      );
      expect(code, 0);
      expect(
        text,
        contains('named gaps: non_atomic_crash 1, stop_races_spawn 2'),
      );
      // The step lane's coordinate has a column of its own once a lane that
      // keys on it produced a row.
      expect(text, contains('step_path'));
      expect(text, contains('build'));
      expect(text, contains('operator adjudicates'));
    });
  });

  group('the accounting SOURCE seam', () {
    test('a composed source sees the parsed grid home', () async {
      final homes = <String>[];
      final (code, text) = await _run(
        accountingFor: (gridHome) async {
          homes.add(gridHome);
          return const ShadowRunAccounting(dropped: 0, suppressed: 0, epoch: 7);
        },
      );
      expect(code, 0);
      expect(homes, ['/grid']);
      expect(text, contains('epoch: 7'));
      expect(text, contains('one clean run'));
    });

    test("the operator's flag outranks the source", () async {
      final (_, text) = await _run(
        accounting: const ShadowRunAccounting(dropped: 5, suppressed: 0),
        accountingFor: (_) async =>
            const ShadowRunAccounting(dropped: 0, suppressed: 0),
      );
      expect(text, contains('5 dropped appends'));
    });

    test('a source returning null leaves accounting unknown', () async {
      final (_, text) = await _run(accountingFor: (_) async => null);
      expect(text, contains('append accounting: UNKNOWN'));
    });
  });

  group('the flag surface', () {
    test(
      '--dropped alone stays partial and outranks a composed source',
      () async {
        var sourceCalls = 0;
        final result = await _runCommand(
          flags: const ['--dropped', '0', '--epoch', '1'],
          accountingFor: (_) async {
            sourceCalls++;
            return const ShadowRunAccounting(dropped: 0, suppressed: 0);
          },
        );

        expect(result.code, 0);
        expect(sourceCalls, 0);
        expect(const LineSplitter().convert(result.stderr), const [
          'traj shadow-diff: --suppressed not supplied: accounting UNKNOWN, '
              'round not counted',
        ]);
        expect(
          result.stdout,
          contains(
            'append accounting: UNKNOWN — dropped: 0, '
            'suppressed: NOT SUPPLIED',
          ),
        );
        expect(result.stdout, contains('append accounting UNKNOWN'));
        expect(result.stdout, contains('accounting known for 0'));
        expect(result.stdout, isNot(contains('suppressed: 0')));
        expect(result.stdout, isNot(contains('— clean')));
        expect(result.stdout, isNot(contains('one clean run')));
      },
    );

    test('--suppressed alone stays partial and preserves its value', () async {
      final result = await _runCommand(
        flags: const ['--suppressed', '7', '--epoch', '1'],
      );

      expect(result.code, 0);
      expect(const LineSplitter().convert(result.stderr), const [
        'traj shadow-diff: --dropped not supplied: accounting UNKNOWN, '
            'round not counted',
      ]);
      expect(
        result.stdout,
        contains(
          'append accounting: UNKNOWN — dropped: NOT SUPPLIED, '
          'suppressed: 7',
        ),
      );
      expect(result.stdout, contains('append accounting UNKNOWN'));
      expect(result.stdout, contains('accounting known for 0'));
      expect(result.stdout, isNot(contains('dropped: 0')));
      expect(result.stdout, isNot(contains('— clean')));
      expect(result.stdout, isNot(contains('one clean run')));
    });

    test('partial accounting keeps a mismatch-derived exit 1', () async {
      final result = await _runCommand(
        flags: const ['--dropped', '0'],
        compare: const _AgreeingCompare([
          ShadowMismatch(
            sessionId: _session,
            field: 'outcome',
            legacyValue: 'failed',
            foldValue: 'succeeded',
            seq: 12,
          ),
        ]),
      );

      expect(result.code, 1);
      expect(result.stdout, contains('BLOCKED'));
      expect(result.stdout, isNot(contains('one clean run')));
    });

    test('both observed zero counters retain the clean verdict', () async {
      final result = await _runCommand(
        flags: const ['--dropped', '0', '--suppressed', '0'],
      );

      expect(result.code, 0);
      expect(result.stderr, isEmpty);
      expect(
        result.stdout,
        contains('append accounting: dropped: 0, suppressed: 0 — clean'),
      );
      expect(result.stdout, contains('one clean run toward the criterion'));
    });

    test('neither flag retains the NOT SUPPLIED unknown report', () async {
      final result = await _runCommand();

      expect(result.code, 0);
      expect(result.stderr, isEmpty);
      expect(result.stdout, contains('append accounting NOT SUPPLIED'));
      expect(result.stdout, contains('append accounting UNKNOWN'));
      expect(result.stdout, isNot(contains('one clean run')));
    });

    test('a negative --dropped is refused', () async {
      final result = await _runCommand(flags: const ['--dropped', '-1']);

      expect(result.code, 64);
      expect(const LineSplitter().convert(result.stderr), const [
        'traj shadow-diff: --dropped must be a non-negative integer '
            '(got "-1").',
      ]);
    });

    test('a non-numeric --suppressed is refused', () async {
      final result = await _runCommand(flags: const ['--suppressed', 'lots']);

      expect(result.code, 64);
      expect(const LineSplitter().convert(result.stderr), const [
        'traj shadow-diff: --suppressed must be a non-negative integer '
            '(got "lots").',
      ]);
    });
  });
}
