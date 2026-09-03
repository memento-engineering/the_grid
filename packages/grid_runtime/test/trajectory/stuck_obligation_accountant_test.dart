// W7 (tg-zfek Stage 1) — schema §5's N-consecutive-failure accounting
// (stage1-wiring §2.4 obligation 4), driven by real tick-pass telemetry values.
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

final class _CapturingSink implements TrajectoryRecordSink {
  final List<TrajectoryRecord> enqueued = [];

  @override
  bool accepting = true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => enqueued.add(record);
}

TrajectoryTickPass _pass({
  List<TickRefusal> refusals = const [],
  TickPassDisposition disposition = TickPassDisposition.ran,
}) => TrajectoryTickPass(
  startedAt: DateTime.utc(2026, 8, 31, 12),
  disposition: disposition,
  queriesRun: 3,
  refusals: refusals,
);

TickRefusal _refusal(String query, [String reason = 'store unavailable']) =>
    TickRefusal(
      kind: TickRefusalKind.queryFailed,
      query: query,
      reason: reason,
    );

void main() {
  late _CapturingSink sink;
  late StationTrajectoryRecorder recorder;
  late List<({String name, Map<String, String> data})> flares;
  late StuckObligationAccountant accountant;

  setUp(() {
    sink = _CapturingSink();
    recorder = StationTrajectoryRecorder(sink: sink);
    flares = [];
    accountant = StuckObligationAccountant(
      recorder: recorder,
      station: 'tranquility',
      onFlare: (name, data) => flares.add((name: name, data: data)),
    );
  });

  test('files nothing before N — four refusing passes are a streak, not an '
      'alarm', () {
    for (var i = 0; i < kStuckObligationThreshold - 1; i++) {
      accountant.observe(_pass(refusals: [_refusal('liveness-detector')]));
    }

    expect(sink.enqueued, isEmpty);
    expect(flares, isEmpty);
    expect(accountant.streaks, {'liveness-detector': 4});
  });

  test('files the note AND flares on the Nth consecutive refusing pass', () {
    for (var i = 0; i < kStuckObligationThreshold; i++) {
      accountant.observe(
        _pass(refusals: [_refusal('liveness-detector', 'connection closed')]),
      );
    }

    expect(sink.enqueued, hasLength(1));
    final note = sink.enqueued.single as AttemptNote;
    expect(note.channel, kObligationStuckChannel);
    expect(note.sessionId, stationNoteSubject('tranquility'));
    expect(note.body, contains('liveness-detector'));
    expect(note.body, contains('5 consecutive ticks'));
    expect(note.body, contains('connection closed'));
    expect(note.body, contains('stays open'));

    expect(flares, hasLength(1));
    expect(flares.single.name, 'trajectory.obligationStuck');
    expect(flares.single.data['obligation'], 'liveness-detector');
    expect(flares.single.data['streak'], '5');
  });

  test('re-files only after another N — a stuck obligation is loud, not '
      'spammy', () {
    for (var i = 0; i < kStuckObligationThreshold * 2; i++) {
      accountant.observe(_pass(refusals: [_refusal('liveness-detector')]));
    }

    expect(sink.enqueued, hasLength(2));
    // The ordinal is service-minted per subject and never repeats — the
    // note's idem key is `note:<subject>:<ordinal>`, so a repeat would be a
    // SILENT dedupe. The values themselves are the recorder's to choose (a
    // cold cache mints from epoch-µs rather than restarting at 1, so a
    // capped entry can never re-mint a key the log already holds); what this
    // suite pins is that the second note is a second key, and later.
    final ordinals = [
      for (final note in sink.enqueued) (note as AttemptNote).noteOrdinal,
    ];
    expect(ordinals[1], ordinals[0] + 1);
    expect(ordinals.toSet(), hasLength(2));
  });

  test('a clean pass RESETS the streak — consecutive means consecutive', () {
    for (var i = 0; i < 4; i++) {
      accountant.observe(_pass(refusals: [_refusal('liveness-detector')]));
    }
    accountant.observe(_pass());
    accountant.observe(_pass(refusals: [_refusal('liveness-detector')]));

    expect(sink.enqueued, isEmpty);
    expect(accountant.streaks, {'liveness-detector': 1});
  });

  test('counts each obligation separately', () {
    for (var i = 0; i < kStuckObligationThreshold; i++) {
      accountant.observe(
        _pass(
          refusals: [
            _refusal('liveness-detector'),
            if (i.isEven) _refusal('worktree-reaped-backfill'),
          ],
        ),
      );
    }

    expect(sink.enqueued, hasLength(1));
    expect(
      (sink.enqueued.single as AttemptNote).body,
      contains('liveness-detector'),
    );
  });

  test('a pass that never RAN holds the streak — a fenced-out tick is no '
      'evidence about any obligation', () {
    for (var i = 0; i < 4; i++) {
      accountant.observe(_pass(refusals: [_refusal('liveness-detector')]));
    }
    accountant.observe(
      _pass(disposition: TickPassDisposition.skippedFencedOut),
    );
    accountant.observe(_pass(disposition: TickPassDisposition.skippedHalted));

    expect(accountant.streaks, {'liveness-detector': 4});
    expect(sink.enqueued, isEmpty);

    accountant.observe(_pass(refusals: [_refusal('liveness-detector')]));
    expect(sink.enqueued, hasLength(1));
  });

  test('never throws into the tick: a throwing flare transport is swallowed, '
      'and a latched sink only skips', () {
    final noisy = StuckObligationAccountant(
      recorder: StationTrajectoryRecorder.disabled(),
      station: 'tranquility',
      onFlare: (_, __) => throw StateError('transport is down'),
    );

    for (var i = 0; i < kStuckObligationThreshold; i++) {
      expect(
        () => noisy.observe(_pass(refusals: [_refusal('liveness-detector')])),
        returnsNormally,
      );
    }
  });
}
