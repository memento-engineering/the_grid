/// `traj certify` — argv refusals, the three exit codes, the PASS/FAIL rows,
/// the one JSON object, and the checklist the verb never claims.
library;

import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';
import 'soak_certificate_fixture.dart';

CommandRunner<int> _runner(TrajectoryOpen open) =>
    CommandRunner<int>('grid', 'test')
      ..addCommand(TrajCommand(open: openerFor(open)));

/// Runs the verb over a scripted log and hands back its lines and exit code.
Future<(int, List<String>)> _certify({
  List<int> epochs = const [50, 51, 52],
  Map<int, Map<String, Object?>> dirty = const {},
  List<TrajectoryEnvelope>? rows,
  List<EpochClaim>? claims,
  int boots = 3,
  Set<String> seats = kSoakTargetSeats,
  bool asJson = false,
}) async {
  final lines = <String>[];
  final reader = ScriptedReader(
    rows ?? seededBoots(epochs: epochs, dirty: dirty),
    epochs: claims ?? seededClaims(epochs),
  );
  final code = await runTrajCertify(
    gridHome: '/tmp/grid',
    open: openerFor(TrajectoryOpened(reader)),
    boots: boots,
    seats: seats,
    asJson: asJson,
    out: lines.add,
    err: lines.add,
  );
  expect(reader.closed, isTrue, reason: 'the reader is always closed');
  return (code, lines);
}

/// The status the table printed for [row].
String _statusOf(List<String> lines, String row) {
  final line = lines.firstWhere(
    (candidate) => candidate.trimLeft().startsWith(row),
    orElse: () => '',
  );
  expect(line, isNotEmpty, reason: 'no $row row in:\n${lines.join('\n')}');
  return line.contains('PASS')
      ? 'PASS'
      : line.contains('FAIL')
      ? 'FAIL'
      : 'UNKNOWN';
}

void main() {
  group('argument parsing', () {
    CommandRunner<int> runner() =>
        _runner(const TrajectoryNotBootstrapped('absent'));

    test('refuses a missing grid home', () async {
      expect(await runner().run(['traj', 'certify']), 64);
    });

    test('refuses a positional argument', () async {
      expect(
        await runner().run([
          'traj',
          'certify',
          'tg-aaa',
          '--state-workspace',
          '/tmp',
        ]),
        64,
      );
    });

    test('refuses a non-positive --boots', () async {
      expect(
        await runner().run([
          'traj',
          'certify',
          '--state-workspace',
          '/tmp',
          '--boots',
          '0',
        ]),
        64,
      );
    });
  });

  group('open dispositions', () {
    test('an unbootstrapped home has counted no boot — exit 3', () async {
      final lines = <String>[];
      final code = await runTrajCertify(
        gridHome: '/tmp',
        open: openerFor(const TrajectoryNotBootstrapped('not bootstrapped')),
        out: lines.add,
      );
      expect(code, 3);
      expect(lines.single, contains('no boot has been counted'));
    });

    test('an unreachable server is a refusal — exit 1', () async {
      final lines = <String>[];
      final code = await runTrajCertify(
        gridHome: '/tmp',
        open: openerFor(const TrajectoryUnavailable('connection refused')),
        err: lines.add,
      );
      expect(code, 1);
      expect(lines.single, contains('connection refused'));
    });
  });

  group('AC-1 — three clean primary epochs certify', () {
    test('exits 0 and prints PASS on all five rows', () async {
      final (code, lines) = await _certify();
      expect(code, 0);
      for (final row in CertificateRow.values) {
        expect(
          _statusOf(lines, row.wire),
          'PASS',
          reason: '${row.wire} in:\n${lines.join('\n')}',
        );
      }
      expect(lines.join('\n'), contains('counted boots: epoch 50, 51, 52'));
    });

    test(
      'reads the LAST note with passes > 1, never a passes:1 walk',
      () async {
        final rows = seededBoots()
          ..addAll([
            for (final epoch in const [50, 51, 52])
              summaryNote(
                seq: 90 + epoch % 10,
                epoch: epoch,
                sessionId: 'tranquility-$epoch-lenny',
                // The boot walk: one pass, and every counter still zero because
                // the comparator has not counted anything yet. Summed in, it
                // would read as evidence; the read rule discards it.
                body: summaryBody(passes: 1, scope: 'boot-final'),
              ),
          ]);
        final (code, lines) = await _certify(rows: rows);
        expect(code, 0);
        expect(lines.join('\n'), contains('passes 12'));
      },
    );
  });

  group('AC-2 — a dirty counter fails the clean row', () {
    test('p2_miss_total = 1 exits 2 and names the epoch and the row', () async {
      final (code, lines) = await _certify(
        dirty: const {
          51: {'p2_miss_total': 1},
        },
      );
      expect(code, 2);
      expect(_statusOf(lines, 'clean'), 'FAIL');
      expect(lines.join('\n'), contains('epoch 51: p2_miss_total = 1'));
      // The run of three restarts at that boot — the consecutive row says so
      // rather than passing beside a failed clean row.
      expect(_statusOf(lines, 'consecutive'), 'FAIL');
      expect(_statusOf(lines, 'posture'), 'PASS');
    });

    test('miss_post_epoch_total = 1 fails the same way', () async {
      final (code, lines) = await _certify(
        dirty: const {
          50: {'miss_post_epoch_total': 1},
        },
      );
      expect(code, 2);
      expect(lines.join('\n'), contains('epoch 50: miss_post_epoch_total = 1'));
    });

    test('an ABSENT gating counter is not a zero', () async {
      final rows = seededBoots(epochs: const [50, 51]);
      final preInstrument = summaryBody()..remove('miss_post_epoch_total');
      rows.addAll(seededRound(epoch: 52, seq: 40, seat: 'lenny'));
      rows.addAll(
        seededRound(epoch: 52, seq: 42, seat: 'butane', body: preInstrument),
      );
      final (code, lines) = await _certify(rows: rows);
      expect(code, 2);
      expect(
        lines.join('\n'),
        contains('epoch 52: miss_post_epoch_total absent'),
      );
    });

    test('a boot with no passes > 1 note certifies nothing', () async {
      final rows = seededBoots(epochs: const [50, 51])
        ..addAll(
          seededRound(
            epoch: 52,
            seq: 40,
            seat: 'lenny',
            body: summaryBody(passes: 1),
          ),
        );
      final (code, lines) = await _certify(rows: rows);
      expect(code, 2);
      expect(_statusOf(lines, 'posture'), 'FAIL');
      expect(
        lines.join('\n'),
        contains('epoch 52: no round summary with passes > 1'),
      );
    });

    test('a boot that rode legacy fails the posture row', () async {
      final (code, lines) = await _certify(
        dirty: const {
          52: {'overlay_engaged': false},
        },
      );
      expect(code, 2);
      expect(_statusOf(lines, 'posture'), 'FAIL');
      expect(
        lines.join('\n'),
        contains('epoch 52: overlay_engaged is not true'),
      );
    });

    test('mode observe fails the posture row', () async {
      final (code, lines) = await _certify(
        dirty: const {
          50: {'mode': 'observe'},
        },
      );
      expect(code, 2);
      expect(lines.join('\n'), contains('epoch 50: mode observe, not primary'));
    });

    test('a seat with no round fails the shape-coverage row', () async {
      final rows = <TrajectoryEnvelope>[];
      var seq = 1;
      for (final epoch in const [50, 51, 52]) {
        rows.addAll(seededRound(epoch: epoch, seq: seq, seat: 'lenny'));
        seq += 2;
      }
      final (code, lines) = await _certify(rows: rows);
      expect(code, 2);
      expect(_statusOf(lines, 'shape-coverage'), 'FAIL');
      expect(
        lines.join('\n'),
        contains('seat butane: no round with passes > 1'),
      );
    });

    test('a would-refuse count above zero fails its row', () async {
      final (code, lines) = await _certify(
        dirty: const {
          51: {'barrier_would_refuse': 2},
        },
      );
      expect(code, 2);
      expect(_statusOf(lines, 'would-refuse'), 'FAIL');
      expect(lines.join('\n'), contains('epoch 51: barrier_would_refuse = 2'));
    });

    test(
      'W2-B unbuilt leaves would-refuse informational, not failed',
      () async {
        final (code, lines) = await _certify();
        expect(code, 0);
        expect(_statusOf(lines, 'would-refuse'), 'PASS');
        expect(lines.join('\n'), contains('has not landed; informational'));
      },
    );
  });

  group('AC-3 — fewer than N boots', () {
    test('two epochs against --boots 3 exits 3 and measures nothing', () async {
      final (code, lines) = await _certify(epochs: const [50, 51]);
      expect(code, 3);
      expect(lines.join('\n'), contains('only 2 boot epochs are claimed'));
      expect(lines.join('\n'), isNot(contains('PASS')));
    });

    test('an empty ledger exits 3', () async {
      final (code, _) = await _certify(rows: const [], claims: const []);
      expect(code, 3);
    });

    test('--boots 2 over those same two epochs certifies', () async {
      final (code, lines) = await _certify(epochs: const [50, 51], boots: 2);
      expect(code, 0);
      expect(_statusOf(lines, 'consecutive'), 'PASS');
    });
  });

  group('AC-4 — --json', () {
    test('parses and carries the measured numbers per row per boot', () async {
      final (code, lines) = await _certify(asJson: true);
      expect(code, 0);
      final parsed = jsonDecode(lines.join('\n')) as Map<String, Object?>;
      expect(parsed['exit_code'], 0);
      expect(parsed['certified'], isTrue);
      expect(parsed['boots_counted'], 3);
      expect(parsed['seats'], ['butane', 'lenny']);

      final rows = (parsed['rows']! as List).cast<Map<String, Object?>>();
      expect(
        [for (final row in rows) row['row']],
        [for (final row in CertificateRow.values) row.wire],
      );
      expect([for (final row in rows) row['status']], everyElement('PASS'));

      final boots = (parsed['boots']! as List).cast<Map<String, Object?>>();
      expect([for (final boot in boots) boot['epoch']], [50, 51, 52]);
      for (final boot in boots) {
        expect(boot['mode'], 'primary');
        expect(boot['overlay_engaged'], isTrue);
        expect(boot['passes'], 12);
        expect(boot['station'], 'lunar');
        final counters = boot['counters']! as Map<String, Object?>;
        for (final key in kCertificateGatingCounters) {
          expect(counters[key], 0, reason: key);
        }
        expect(counters['append_ack_p99_ms'], 31);
        // Never emitted yet — carried as null so a reader can tell "zero"
        // from "the instrument does not exist".
        expect(counters.containsKey('barrier_would_refuse'), isTrue);
        expect(counters['barrier_would_refuse'], isNull);
        expect(boot['seat_rounds'], {'butane': 1, 'lenny': 1});
      }
    });

    test('a failed row carries its failures in the JSON', () async {
      final (code, lines) = await _certify(
        asJson: true,
        dirty: const {
          51: {'p2_miss_total': 1},
        },
      );
      expect(code, 2);
      final parsed = jsonDecode(lines.join('\n')) as Map<String, Object?>;
      final rows = (parsed['rows']! as List).cast<Map<String, Object?>>();
      final clean = rows.firstWhere((row) => row['row'] == 'clean');
      expect(clean['status'], 'FAIL');
      expect(
        (clean['failures']! as List).single,
        contains('epoch 51: p2_miss_total = 1'),
      );
    });
  });

  group('AC-5 — the human-only items', () {
    test('print as an unknown checklist, never as PASS', () async {
      final (_, lines) = await _certify();
      final text = lines.join('\n');
      expect(text, contains('human-only certificate items'));
      expect(text, contains('state UNKNOWN, never claimed by this verb'));
      for (final item in kCertificateHumanItems) {
        final line = lines.firstWhere(
          (candidate) => candidate.contains(item.split('(').first.trim()),
          orElse: () => '',
        );
        expect(line, startsWith('    [?] '), reason: item);
        expect(line, isNot(contains('PASS')));
      }
    });

    test('ride the JSON as UNKNOWN too', () async {
      final (_, lines) = await _certify(asJson: true);
      final parsed = jsonDecode(lines.join('\n')) as Map<String, Object?>;
      final checklist = (parsed['checklist']! as List)
          .cast<Map<String, Object?>>();
      expect(checklist, hasLength(kCertificateHumanItems.length));
      expect([
        for (final item in checklist) item['status'],
      ], everyElement('UNKNOWN'));
    });

    test('the checklist prints even when nothing could be measured', () async {
      final (code, lines) = await _certify(epochs: const [50]);
      expect(code, 3);
      expect(lines.join('\n'), contains('human-only certificate items'));
    });
  });

  group('the group composes the verb', () {
    test('traj certify runs through the command runner', () async {
      final reader = ScriptedReader(
        seededBoots(),
        epochs: seededClaims(const [50, 51, 52]),
      );
      final code = await _runner(
        TrajectoryOpened(reader),
      ).run(['traj', 'certify', '--state-workspace', '/tmp']);
      expect(code, 0);
      expect(reader.closed, isTrue);
    });
  });
}
