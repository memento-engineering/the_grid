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
      expect(lines.first, contains('no boot has been counted'));
      // …and the UNKNOWN checklist under it (AC-5): see the sibling test.
      expect(lines.join('\n'), contains('human-only certificate items'));
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

  group('AC-1 — every §W2.5 row with a gate value GATES', () {
    // The false-green shape this group exists to kill: a table row that is
    // only REPORTED cannot fail, so a boot dirty in exactly that row still
    // exits 0. One case per gating counter, driven off the list itself, so a
    // counter demoted back to reported shows up here as a test that stops
    // failing rather than as a silent certificate.
    for (final counter in kCertificateGatingCounters) {
      test('$counter = 1 on one boot exits 2 and names it', () async {
        final (code, lines) = await _certify(
          dirty: {
            51: {counter: 1},
          },
        );
        expect(code, 2);
        expect(_statusOf(lines, 'clean'), 'FAIL');
        expect(lines.join('\n'), contains('epoch 51: $counter = 1'));
      });

      test('$counter absent from the summary is not a zero', () async {
        final body = summaryBody()..remove(counter);
        final rows = seededBoots(epochs: const [50, 51])
          ..addAll(seededRound(epoch: 52, seq: 40, seat: 'lenny'))
          ..addAll(seededRound(epoch: 52, seq: 42, seat: 'butane', body: body));
        final (code, lines) = await _certify(rows: rows);
        expect(code, 2);
        expect(lines.join('\n'), contains('epoch 52: $counter absent'));
      });
    }

    test('a null epoch anchor refuses certification outright', () async {
      // `classifyDualReadMiss` returns `legacyEra` for EVERY miss when the
      // anchor is null, so `miss_post_epoch_total 0` beside it is zero BY
      // CONSTRUCTION — the exact unearned green the row exists to refuse.
      final (code, lines) = await _certify(
        dirty: const {
          50: {'first_epoch_claimed_at': null},
        },
      );
      expect(code, 2);
      expect(_statusOf(lines, 'clean'), 'FAIL');
      expect(
        lines.join('\n'),
        contains('epoch 50: first_epoch_claimed_at is null'),
      );
      expect(lines.join('\n'), contains('0 by construction'));
    });

    test('an absent epoch anchor fails the same way', () async {
      final body = summaryBody()..remove('first_epoch_claimed_at');
      final rows = seededBoots(epochs: const [50, 51])
        ..addAll(seededRound(epoch: 52, seq: 40, seat: 'lenny'))
        ..addAll(seededRound(epoch: 52, seq: 42, seat: 'butane', body: body));
      final (code, lines) = await _certify(rows: rows);
      expect(code, 2);
      expect(
        lines.join('\n'),
        contains('epoch 52: first_epoch_claimed_at is null'),
      );
    });

    test('a health latch during the boot fails the posture row', () async {
      // `health: live` at boot-final is the LAST reading; a boot that latched
      // degraded and recovered served something else in the middle.
      final (code, lines) = await _certify(
        dirty: const {
          52: {
            'health_transitions': ['live->degraded', 'degraded->live'],
          },
        },
      );
      expect(code, 2);
      expect(_statusOf(lines, 'posture'), 'FAIL');
      expect(lines.join('\n'), contains('was not live throughout the boot'));
    });

    test('a bare live first observation is NOT a latch', () async {
      // `_noteHealth` writes the first health it sees as a bare state name, so
      // `['live']` is what a perfectly healthy boot carries. Gating on an
      // EMPTY list would fail every boot forever — the blocker shape this verb
      // exists to kill — so the gate is "no state but live, ever".
      final (code, lines) = await _certify(
        dirty: const {
          50: {
            'health_transitions': ['live'],
          },
        },
      );
      expect(code, 0, reason: lines.join('\n'));
      expect(_statusOf(lines, 'posture'), 'PASS');
    });

    test('a boot that never started live fails the posture row', () async {
      final (code, lines) = await _certify(
        dirty: const {
          51: {
            'health_transitions': ['compromised'],
          },
        },
      );
      expect(code, 2);
      expect(_statusOf(lines, 'posture'), 'FAIL');
      expect(lines.join('\n'), contains('was not live throughout the boot'));
    });

    test('an absent health_transitions row is not an unlatched one', () async {
      final body = summaryBody()..remove('health_transitions');
      final rows = seededBoots(epochs: const [50, 51])
        ..addAll(seededRound(epoch: 52, seq: 40, seat: 'lenny'))
        ..addAll(seededRound(epoch: 52, seq: 42, seat: 'butane', body: body));
      final (code, lines) = await _certify(rows: rows);
      expect(code, 2);
      expect(_statusOf(lines, 'posture'), 'FAIL');
      expect(lines.join('\n'), contains('health_transitions absent'));
    });
  });

  group('AC-1 — shape coverage joins across the boot window', () {
    /// Three boots of lenny rounds plus ONE butane round whose session was
    /// mounted in the previous epoch — the bounce-mid-round shape.
    List<TrajectoryEnvelope> carried() {
      final rows = <TrajectoryEnvelope>[];
      var seq = 1;
      for (final epoch in const [50, 51, 52]) {
        rows.addAll(seededRound(epoch: epoch, seq: seq, seat: 'lenny'));
        seq += 2;
      }
      rows.addAll(
        seededCarriedRound(
          startedEpoch: 51,
          epoch: 52,
          seq: seq,
          seat: 'butane',
        ),
      );
      return rows;
    }

    test('a session mounted in an earlier epoch still names its seat', () async {
      final reader = ScriptedReader(
        carried(),
        epochs: seededClaims(const [50, 51, 52]),
      );
      final lines = <String>[];
      final code = await runTrajCertify(
        gridHome: '/tmp/grid',
        open: openerFor(TrajectoryOpened(reader)),
        out: lines.add,
        err: lines.add,
      );
      expect(code, 0, reason: lines.join('\n'));
      expect(_statusOf(lines, 'shape-coverage'), 'PASS');
      expect(lines.join('\n'), contains('butane 1, lenny 3'));
      expect(lines.join('\n'), isNot(contains('unjoined')));
      // The second, bounded read the join needs — and only for the session the
      // window could not attribute.
      expect(reader.subjectsRead, contains('tranquility-51-butane-carried'));
    });

    test('a fully attributed window reads no session at all', () async {
      final reader = ScriptedReader(
        seededBoots(),
        epochs: seededClaims(const [50, 51, 52]),
      );
      final lines = <String>[];
      final code = await runTrajCertify(
        gridHome: '/tmp/grid',
        open: openerFor(TrajectoryOpened(reader)),
        out: lines.add,
      );
      expect(code, 0);
      expect(reader.subjectsRead, ['traj_epoch']);
    });

    test(
      'a session no record anywhere names is UNJOINED, not off-seat',
      () async {
        final rows = <TrajectoryEnvelope>[];
        var seq = 1;
        for (final epoch in const [50, 51, 52]) {
          rows.addAll(seededRound(epoch: epoch, seq: seq, seat: 'lenny'));
          seq += 2;
        }
        rows.add(
          summaryNote(
            seq: seq,
            epoch: 52,
            sessionId: 'tranquility-orphan',
            body: summaryBody(),
          ),
        );
        final (code, lines) = await _certify(rows: rows);
        expect(code, 2);
        expect(_statusOf(lines, 'shape-coverage'), 'FAIL');
        expect(lines.join('\n'), contains('1 unjoined'));
      },
    );

    test('a round on a non-target substation reads as off-seat', () async {
      final rows = seededBoots()
        ..addAll(seededRound(epoch: 52, seq: 40, seat: 'the_grid'));
      final (code, lines) = await _certify(rows: rows);
      expect(code, 0, reason: lines.join('\n'));
      expect(lines.join('\n'), contains('1 on other substations'));
      expect(lines.join('\n'), isNot(contains('unjoined')));
    });
  });

  group('AC-1 — only a round-scope summary is a round (RULING 2026-09-13)', () {
    /// The live shape: each boot's last note is the BOOT-FINAL summary, riding
    /// the last terminal session's id with the boot's cumulative pass count.
    List<TrajectoryEnvelope> withBootFinals({int passes = 150}) =>
        seededBoots()..addAll([
          for (final epoch in const [50, 51, 52])
            summaryNote(
              seq: 900 + epoch,
              epoch: epoch,
              sessionId: 'tranquility-$epoch-lenny',
              body: summaryBody(passes: passes, scope: kBootFinalSummaryScope),
            ),
        ]);

    test('the boot-final note scores no seat and is reported apart', () async {
      final (code, lines) = await _certify(rows: withBootFinals());
      final text = lines.join('\n');
      expect(code, 0, reason: text);
      expect(_statusOf(lines, 'shape-coverage'), 'PASS');
      // Three boots x one round per seat — NOT four for lenny.
      expect(text, contains('butane 3, lenny 3'));
      expect(text, contains('3 non-round summaries excluded'));
      // And it still GOVERNS: the counters come off it, cumulative passes and
      // all.
      expect(text, contains('passes 150'));
      expect(text, contains('($kBootFinalSummaryScope, session'));
    });

    test(
      'a boot whose ONLY passes>1 note is boot-final certifies no round',
      () async {
        // The false green the ruling kills: the boot measures clean and
        // posture fine off the boot-final note, and covers NO seat.
        final rows = <TrajectoryEnvelope>[
          for (final epoch in const [50, 51, 52]) ...[
            envelope(
              recordType: 'attempt.session.started',
              family: TrajectoryFamily.attempt,
              seq: 900 + epoch * 2,
              bootEpoch: epoch,
              sessionId: 'tranquility-$epoch-lenny',
              workBeadId: 'lenny-1',
              substation: 'lenny',
              attemptId: 'attempt-$epoch-lenny',
            ),
            summaryNote(
              seq: 901 + epoch * 2,
              epoch: epoch,
              sessionId: 'tranquility-$epoch-lenny',
              body: summaryBody(passes: 150, scope: kBootFinalSummaryScope),
            ),
          ],
        ];
        final (code, lines) = await _certify(rows: rows);
        final text = lines.join('\n');
        expect(code, 2, reason: text);
        expect(_statusOf(lines, 'shape-coverage'), 'FAIL');
        expect(_statusOf(lines, 'clean'), 'PASS');
        expect(_statusOf(lines, 'posture'), 'PASS');
        expect(text, contains('no round-scope ($kRoundSummaryScope) summary'));
        expect(text, contains('butane 0, lenny 0'));
      },
    );

    test('a boot-final note is never given a second read', () async {
      // Its session is deliberately unattributable in-window; nothing scores
      // it, so nothing pays for it.
      final rows = seededBoots()
        ..add(
          summaryNote(
            seq: 999,
            epoch: 52,
            sessionId: 'tranquility-51-lenny-bounced',
            body: summaryBody(scope: kBootFinalSummaryScope),
          ),
        );
      final reader = ScriptedReader(
        rows,
        epochs: seededClaims(const [50, 51, 52]),
      );
      final lines = <String>[];
      final code = await runTrajCertify(
        gridHome: '/tmp/grid',
        open: openerFor(TrajectoryOpened(reader)),
        out: lines.add,
        err: lines.add,
      );
      expect(code, 0, reason: lines.join('\n'));
      expect(reader.subjectsRead, ['traj_epoch']);
      expect(lines.join('\n'), isNot(contains('unjoined')));
    });
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

    test(
      'an attempt-less void terminal needs no clean-row exemption',
      () async {
        final rows = seededBoots()
          ..add(
            envelope(
              recordType: 'attempt.terminal',
              family: TrajectoryFamily.attempt,
              seq: 99,
              bootEpoch: 51,
              sessionId: 'tranquility-void',
              outcome: TerminalOutcome.lost,
              provenance: TrajectoryProvenance.reconstructed,
              payload: const {
                'heal_basis': 'terminal-reconcile',
                'reason':
                    'terminal-reconcile: the ledger void-closed this pre-spawn '
                    'session before any attempt started',
              },
            ),
          );

        final (code, lines) = await _certify(rows: rows);

        expect(code, 0);
        expect(_statusOf(lines, 'clean'), 'PASS');
        expect(lines.join('\n'), contains('p2_miss_total 0'));
        expect(lines.join('\n'), isNot(contains('void exemption')));
      },
    );

    test('the EXPLAINED retired-round population is REPORTED, never gating '
        '(tg-af76)', () async {
      // The Q9 shape: legacy retired the round, the fold keeps that head open
      // by design, and its nodes are counted beside the gate so an operator
      // can see what the window excluded. A boot carrying 37 of them is still
      // a CLEAN boot.
      final (code, lines) = await _certify(
        dirty: const {
          51: {'p2_miss_total': 0, 'p2_miss_retired_round_total': 37},
        },
      );
      expect(code, 0);
      expect(_statusOf(lines, 'clean'), 'PASS');
      // Printed on the boot's REPORTED line — beside the gate, never in it.
      final carrying = lines
          .where((line) => line.contains('p2_miss_retired_round_total 37'))
          .toList();
      expect(
        carrying,
        hasLength(1),
        reason:
            'the excluded population must be printed once:\n'
            '${lines.join('\n')}',
      );
      expect(carrying.single.trimLeft(), startsWith('reported'));
      expect(
        lines.where((line) => line.trimLeft().startsWith('gating')).join('\n'),
        isNot(contains('p2_miss_retired_round_total')),
      );
    });

    test('an explained population never buys a pass for a REAL p2 miss '
        '(tg-af76)', () async {
      // The false green the row exists to refuse: a large explained count
      // beside a single unexplained miss is still a failed boot.
      final (code, lines) = await _certify(
        dirty: const {
          51: {'p2_miss_total': 1, 'p2_miss_retired_round_total': 37},
        },
      );
      expect(code, 2);
      expect(_statusOf(lines, 'clean'), 'FAIL');
      expect(lines.join('\n'), contains('epoch 51: p2_miss_total = 1'));
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
        contains(
          'seat butane: no round-scope ($kRoundSummaryScope) summary with '
          'passes > 1',
        ),
      );
    });

    test('a would-refuse count above zero is REPORTED, never a failure '
        '(tg-9foi)', () async {
      // §W2.5 lists `barrier_would_refuse` as reported-not-gating, and the
      // engine's own accounting says the same: the barrier's observe form
      // counts candidates it WOULD have refused, and a routine operator re-arm
      // onto a surviving worktree is exactly that. Certify had drifted to
      // failing on non-zero, which broke the consecutive run on a boot the
      // table never authorised breaking.
      final (code, lines) = await _certify(
        dirty: const {
          51: {'barrier_would_refuse': 2},
        },
      );
      expect(code, 0);
      expect(_statusOf(lines, 'would-refuse'), 'PASS');
      final row = lines.firstWhere(
        (line) => line.trimLeft().startsWith('would-refuse'),
        orElse: () => '',
      );
      // The VALUE is still printed with its epoch — reported means visible.
      expect(row, contains('epoch 51 2'));
      expect(row, contains('reported, not gating'));
      // …and it contributes NO break to the run of three: `_consecutive`
      // folds every row's failures into its own, so a row that fails silently
      // restarts the run.
      expect(_statusOf(lines, 'consecutive'), 'PASS');
      expect(
        lines.firstWhere(
          (line) => line.trimLeft().startsWith('consecutive'),
          orElse: () => '',
        ),
        isNot(contains('would-refuse')),
      );
      expect(_statusOf(lines, 'clean'), 'PASS');
    });

    test(
      'W2-B unbuilt leaves would-refuse informational, not failed',
      () async {
        final (code, lines) = await _certify();
        expect(code, 0);
        expect(_statusOf(lines, 'would-refuse'), 'PASS');
        expect(lines.join('\n'), contains('has not landed; informational'));
        // The ABSENT case keeps its own wording — it is not the reported one.
        expect(lines.join('\n'), isNot(contains('reported, not gating')));
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
        expect(boot['off_seat_rounds'], 0);
        expect(boot['unjoined_rounds'], 0);
        expect(boot['non_round_notes'], 0);
        // The two structural gate values ride the JSON as themselves, never
        // as a counter that happens to read 0.
        expect(boot['health_transitions'], ['live']);
        expect(boot['first_epoch_claimed_at'], '2026-09-06T00:00:00.000Z');
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

    test('the checklist prints on an unbootstrapped grid home too', () async {
      // The other exit-3: a line on its own reads as "the verb found nothing
      // wrong", which is the opposite of what it measured.
      final lines = <String>[];
      final code = await runTrajCertify(
        gridHome: '/tmp',
        open: openerFor(const TrajectoryNotBootstrapped('not bootstrapped')),
        out: lines.add,
      );
      expect(code, 3);
      expect(lines.join('\n'), contains('no boot has been counted'));
      expect(lines.join('\n'), contains('human-only certificate items'));
      expect(lines.join('\n'), isNot(contains('PASS')));
    });

    test('the doc\'s EVENT shape checklist is one of them', () async {
      // The `shape-coverage` ROW is tg-2gt1's seat redefinition; §W2.5's own
      // checklist (a rework, a void, an escalation, a gate-park, a bounce) is
      // not measured anywhere and must never read as covered by it.
      final (_, lines) = await _certify();
      final text = lines.join('\n');
      expect(text, contains('EVENT shape checklist'));
      expect(text, contains('one deliberate bounce'));
      expect(text, contains('per-field in-window divergence row'));
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
