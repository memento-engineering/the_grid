import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/recording_bd_runner.dart';

/// Tests for the teardown replay's TRIGGER QUERY and its shared disposition
/// derivation (tg-tlea).
void main() {
  late RecordingBdRunner runner;
  late StationBeadWriter writer;

  setUp(() {
    runner = RecordingBdRunner();
    writer = StationBeadWriter(
      bd: BdCliService(runner),
      reader: runner,
      ownership: BeadOwnershipPredicate({'tgdog'}),
    );
  });

  Bead session(
    String id, {
    bool closed = false,
    Map<String, dynamic> metadata = const {'grid.outcome': 'complete'},
  }) => Bead(
    id: id,
    issueType: GridIssueTypes.session,
    status: closed ? BeadStatus.closed : BeadStatus.open,
    metadata: {'rig': 'tgdog', ...metadata},
  );

  test('the trigger is ONE server-side metadata-filtered query — never a walk '
      'of every owned session filtered in Dart', () async {
    runner.exportBeads = [session('tgdog-sess1')];

    await writer.sessionsAwaitingTeardown();

    final probe = runner.openBeadCalls.single;
    expect(probe.types, {GridIssueTypes.session});
    expect(
      probe.metadataAll,
      {'grid.outcome': 'complete'},
      reason:
          'a Dart-side filter would reintroduce exactly the unbounded '
          'boot pass RestartReconciler documents itself refusing to do',
    );
  });

  test(
    'a session with no completion marker is not in the trigger set',
    () async {
      runner.exportBeads = [session('tgdog-sess1', metadata: const {})];

      expect(await writer.sessionsAwaitingTeardown(), isEmpty);
    },
  );

  test('a CLOSED session is excluded — its teardown finished', () async {
    runner.exportBeads = [session('tgdog-sess1', closed: true)];

    expect(await writer.sessionsAwaitingTeardown(), isEmpty);
  });

  group('sessionDispositionOfMetadata — the ONE shared derivation', () {
    test('a human marker means HELD, whichever marker it is', () {
      expect(
        sessionDispositionOfMetadata(const {'grid.escalation': 'exhausted'}),
        GateSweepSessionDisposition.held,
      );
      expect(
        sessionDispositionOfMetadata(const {'grid.rework_declined': 'op'}),
        GateSweepSessionDisposition.held,
      );
    });

    test('a human marker OUTRANKS the completion marker', () {
      expect(
        sessionDispositionOfMetadata(const {
          'grid.outcome': 'complete',
          'grid.escalation': 'exhausted',
        }),
        GateSweepSessionDisposition.held,
        reason: 'the escalation path preserves its evidence for the human',
      );
    });

    test('the completion marker alone means DONE', () {
      expect(
        sessionDispositionOfMetadata(const {'grid.outcome': 'complete'}),
        GateSweepSessionDisposition.done,
      );
    });

    test('neither marker means VOIDED', () {
      expect(
        sessionDispositionOfMetadata(const {}),
        GateSweepSessionDisposition.voided,
      );
    });
  });
}
