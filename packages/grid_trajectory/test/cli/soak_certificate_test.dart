/// The §W2.5 certificate FOLD — pure, over decoded rows: the epoch selection,
/// the seat rule, what counts as a round summary, and the consecutive guard.
library;

import 'dart:convert';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';
import 'soak_certificate_fixture.dart';

BootWindow _window(int epoch, List<TrajectoryEnvelope> rows) => BootWindow(
  epoch: epoch,
  station: 'lunar',
  records: [
    for (final row in rows)
      if (row.bootEpoch == epoch) row,
  ],
);

void main() {
  group('countedEpochs', () {
    test('takes the ledger tail, oldest first', () {
      expect(countedEpochs(const [48, 49, 50, 51, 52], 3), [50, 51, 52]);
    });

    test('sorts a ledger handed over out of order', () {
      expect(countedEpochs(const [52, 48, 51], 2), [51, 52]);
    });

    test('hands back everything when the ledger is short', () {
      expect(countedEpochs(const [50, 51], 3), [50, 51]);
    });
  });

  group('seatFor', () {
    test('matches a substation exactly', () {
      expect(seatFor('lenny', kSoakTargetSeats), 'lenny');
    });

    test('matches the ruling name as a leading segment', () {
      expect(seatFor('butane_flutter', kSoakTargetSeats), 'butane');
    });

    test('never matches a different substation or a null', () {
      expect(seatFor('the_grid', kSoakTargetSeats), isNull);
      expect(seatFor('butanes', kSoakTargetSeats), isNull);
      expect(seatFor(null, kSoakTargetSeats), isNull);
    });
  });

  group('roundSummaryOf', () {
    test('decodes a summary note', () {
      final note = roundSummaryOf(
        summaryNote(
          seq: 7,
          epoch: 50,
          sessionId: 'tranquility-1',
          body: summaryBody(passes: 4),
        ),
      );
      expect(note, isNotNull);
      expect(note!.seq, 7);
      expect(note.passes, 4);
      expect(note.intOf('miss_post_epoch_total'), 0);
      expect(note.intOf('nothing_wrote_this'), isNull);
      expect(note.boolOf('overlay_engaged'), isTrue);
      expect(note.stringOf('mode'), 'primary');
    });

    test('ignores another channel on the same note record', () {
      final row = envelope(
        recordType: 'attempt.note',
        family: TrajectoryFamily.attempt,
        seq: 3,
        sessionId: 'tranquility-1',
        payload: <String, Object?>{
          'body': jsonEncode(summaryBody()),
          'channel': 'break-glass',
          'note_ordinal': 3,
        },
      );
      expect(roundSummaryOf(row), isNull);
    });

    test('ignores a body that is not a JSON object', () {
      final row = envelope(
        recordType: 'attempt.note',
        family: TrajectoryFamily.attempt,
        seq: 3,
        sessionId: 'tranquility-1',
        payload: <String, Object?>{
          'body': 'terminal-reconcile, by hand',
          'channel': kRoundSummaryNoteChannel,
          'note_ordinal': 3,
        },
      );
      expect(roundSummaryOf(row), isNull);
    });

    test('ignores a record that is not a note at all', () {
      expect(
        roundSummaryOf(
          envelope(
            recordType: 'attempt.terminal',
            family: TrajectoryFamily.attempt,
            seq: 4,
            sessionId: 'tranquility-1',
          ),
        ),
        isNull,
      );
    });
  });

  group('foldBootEvidence', () {
    test('attributes a round to the seat its session ran on', () {
      final rows = seededBoots(epochs: const [50]);
      final evidence = foldBootEvidence(_window(50, rows));
      expect(evidence.seatRounds, {'lenny': 1, 'butane': 1});
      expect(evidence.unattributedRounds, 0);
      expect(evidence.summaries, 2);
      expect(evidence.governing?.sessionId, 'tranquility-50-butane');
    });

    test('counts a round whose session no record attributed', () {
      final rows = [
        summaryNote(
          seq: 1,
          epoch: 50,
          sessionId: 'tranquility-orphan',
          body: summaryBody(),
        ),
      ];
      final evidence = foldBootEvidence(_window(50, rows));
      expect(evidence.unattributedRounds, 1);
      expect(evidence.seatRounds, {'lenny': 0, 'butane': 0});
    });
  });

  group('the consecutive row', () {
    test('refuses windows that are not the ledger tail', () {
      final rows = seededBoots(epochs: const [50, 51, 52]);
      final certificate = foldSoakCertificate(
        requestedBoots: 3,
        claimedEpochs: const [50, 51, 52, 53],
        windows: [
          for (final epoch in const [50, 51, 52]) _window(epoch, rows),
        ],
      );
      expect(certificate.exitCode, 2);
      final consecutive = certificate.items.firstWhere(
        (item) => item.row == CertificateRow.consecutive,
      );
      expect(consecutive.status, CertificateStatus.fail);
      expect(
        consecutive.failures.first,
        contains('are not the ledger\'s 3 most recent claims'),
      );
    });

    test('a truncated window certifies nothing', () {
      final rows = seededBoots();
      final certificate = foldSoakCertificate(
        requestedBoots: 3,
        claimedEpochs: const [50, 51, 52],
        windows: [
          _window(50, rows),
          _window(51, rows),
          BootWindow(
            epoch: 52,
            station: 'lunar',
            records: [
              for (final row in rows)
                if (row.bootEpoch == 52) row,
            ],
            truncated: true,
          ),
        ],
      );
      expect(certificate.exitCode, 2);
      final clean = certificate.items.firstWhere(
        (item) => item.row == CertificateRow.clean,
      );
      expect(
        clean.failures.first,
        contains('epoch 52: the window read was truncated'),
      );
    });
  });
}
