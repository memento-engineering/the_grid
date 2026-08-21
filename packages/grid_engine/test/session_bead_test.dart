import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

void main() {
  group('projectSession (the read half of the contract)', () {
    test('work-terminal composed metadata projects completion and reason', () {
      final projection = projectSession(
        Bead(
          id: 'tgdog-work-terminal',
          issueType: GridIssueTypes.session,
          metadata: sessionWorkTerminalMetadata(),
        ),
      );
      expect(projection.completed, isTrue);
      expect(projection.workTerminalReason, kWorkTerminalReasonWorkBeadClosed);
    });

    test('work-terminal reason alone is diagnostic, not completion', () {
      final projection = projectSession(
        Bead(
          id: 'tgdog-work-terminal-reason-only',
          issueType: GridIssueTypes.session,
          metadata: const {
            SessionBeadKeys.workTerminalReason:
                kWorkTerminalReasonWorkBeadClosed,
          },
        ),
      );
      expect(projection.completed, isFalse);
      expect(projection.workTerminalReason, kWorkTerminalReasonWorkBeadClosed);
    });

    test('projects work-bead linkage, identity, terminal; a legacy '
        'grid.cursor.* key is inert (tg-eli phase 2: the flat cursor '
        'projection retired — cursor stays empty)', () {
      final session = Bead(
        id: 'tgdog-9a',
        issueType: GridIssueTypes.session,
        status: BeadStatus.open,
        metadata: const {
          'rig': 'tgdog',
          'work_bead': 'genesis-7r9',
          'grid.cursor.genesis-7r9/agent.state': 'complete',
          // The legacy scalar identity fence (kept for the restart reconciler).
          'pgid': '4242',
          'pid': '4243',
          'token': 'deadbeef',
        },
      );

      final p = projectSession(session);
      expect(p.workBeadId, 'genesis-7r9');
      expect(p.sessionId, 'tgdog-9a');
      expect(p.cursor, isEmpty);
      expect(p.isTerminal, isFalse);
      expect(p.pgid, 4242);
      expect(p.pid, 4243);
      expect(p.token, 'deadbeef');
    });

    test(
      'a freshly minted session (no cursor keys) projects an empty cursor',
      () {
        final session = Bead(
          id: 'tgdog-1',
          issueType: GridIssueTypes.session,
          metadata: const {'work_bead': 'genesis-q8h'},
        );
        final p = projectSession(session);
        expect(p.cursor, isEmpty);
        expect(p.pgid, isNull);
        expect(p.token, isNull);
      },
    );

    test('a closed session bead is terminal (the unmount signal); a legacy '
        'grid.cursor.* key is inert', () {
      final session = Bead(
        id: 'tgdog-2',
        issueType: GridIssueTypes.session,
        status: BeadStatus.closed,
        metadata: const {
          'work_bead': 'genesis-q8h',
          'grid.cursor.genesis-q8h/land.state': 'complete',
        },
      );
      final p = projectSession(session);
      expect(p.isTerminal, isTrue);
      expect(p.cursor, isEmpty);
    });
  });

  group('node-path key codec (tg-6e4j — bd metadata-key charset)', () {
    // bd's server-side atomic merge validates metadata keys against
    // [a-zA-Z_][a-zA-Z0-9_.]* — the charset every emitted key must fit.
    final bdKeyCharset = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_.]*$');

    test('encode maps /, - and _ into the accepted charset, reversibly', () {
      const paths = [
        'pow-1rn.3/spec_review/intake',
        'tg-1/review/test-coverage',
        'genesis-7r9/land',
        'tg-burn/follower',
        'lenny-749o/code_review/route',
        'a__h/b-c_d', // pathological underscore/hyphen adjacency
      ];
      for (final path in paths) {
        final encoded = encodeNodePathKey(path);
        expect(decodeNodePathKey(encoded), path, reason: path);
        expect(
          bdKeyCharset.hasMatch('x$encoded'),
          isTrue,
          reason: 'encoded "$encoded" must fit bd\'s key charset',
        );
      }
      expect(
        encodeNodePathKey('pow-1rn.3/spec_review/intake'),
        'pow_h1rn.3_sspec_ureview_sintake',
      );
    });

    test('every keyFor emission is a valid bd metadata key', () {
      for (final path in [
        'pow-1rn.3/spec_review/intake',
        'tg-1/review/test-coverage',
        'tg-burn/follower',
      ]) {
        final key = ResultKeys.keyFor(path, ResultKeys.grade);
        expect(bdKeyCharset.hasMatch(key), isTrue, reason: key);
      }
    });

    test('decode is lenient on RAW legacy paths (historical beads): unknown '
        'escape pairs pass through, so pre-encoding keys read unchanged', () {
      expect(
        decodeNodePathKey('tg-1/review/test-coverage'),
        'tg-1/review/test-coverage',
      );
      expect(
        decodeNodePathKey('bead/spec_review/intake'),
        'bead/spec_review/intake',
      );
    });

    test('projectCircuitResults decodes encoded keys and still reads legacy '
        'raw keys, bucketing both under RAW node paths', () {
      final session = Bead(
        id: 'tgdog-c',
        issueType: GridIssueTypes.session,
        metadata: <String, dynamic>{
          // The new (encoded) shape.
          ...nodeResultMetadata('pow-1rn.3/spec_review/intake', {
            'verdict': 'driveable',
          }),
          // A historical bead's raw pre-encoding key.
          'grid.result.tg-1/review/coherence.grade': 'B',
        },
      );
      final results = projectCircuitResults(session);
      expect(results['pow-1rn.3/spec_review/intake']!['verdict'], 'driveable');
      expect(results['tg-1/review/coherence']!['grade'], 'B');
    });
  });

  group('write payloads (the write half of the contract)', () {
    test(
      'startedIdentityMetadata stringifies the scalar pgid/pid/token fence',
      () {
        expect(startedIdentityMetadata(pgid: 7, pid: 8, token: 'cafe'), {
          'pgid': '7',
          'pid': '8',
          'token': 'cafe',
        });
      },
    );

    test('nodeResultMetadata namespaces the payload under grid.result. with '
        'the node path ENCODED into bd\'s key charset (tg-6e4j); a null/empty '
        'payload writes nothing', () {
      expect(
        nodeResultMetadata('genesis-7r9/land', {'pr_url': 'https://x/pull/3'}),
        {'grid.result.genesis_h7r9_sland.pr_url': 'https://x/pull/3'},
      );
      expect(nodeResultMetadata('genesis-7r9/land', null), isEmpty);
      expect(nodeResultMetadata('genesis-7r9/land', const {}), isEmpty);
    });

    test('operatorRulingMetadata (tg-i08) stamps grade + operator-ruling '
        'transport + rationale under grid.result.<lane>, round-trippable by the '
        'route\'s sibling read', () {
      final ruling = operatorRulingMetadata(
        'tg-1/review/test-coverage',
        grade: 'A',
        rationale: 'critic cd\'d; verdict was A — transport-F false gate',
        evidenceSession: 'tgdog-9',
      );
      expect(ruling, {
        'grid.result.tg_h1_sreview_stest_hcoverage.grade': 'A',
        'grid.result.tg_h1_sreview_stest_hcoverage.transport':
            'operator-ruling',
        'grid.result.tg_h1_sreview_stest_hcoverage.rationale':
            'critic cd\'d; verdict was A — transport-F false gate',
        'grid.result.tg_h1_sreview_stest_hcoverage.evidence_session': 'tgdog-9',
      });
      expect(kOperatorRulingTransport, 'operator-ruling');
      // The route re-reads it through projectCircuitResults → resultOf().
      final session = Bead(
        id: 'tgdog-9',
        issueType: GridIssueTypes.session,
        metadata: <String, dynamic>{'work_bead': 'tg-1', ...ruling},
      );
      final results = projectCircuitResults(session);
      expect(results['tg-1/review/test-coverage']!['grade'], 'A');
      expect(
        results['tg-1/review/test-coverage']!['transport'],
        'operator-ruling',
      );
    });

    test('only operator rulings atomically override molecule step results', () {
      const lane = 'tg-1/review/test-coverage';
      final stepResults = <String, Map<String, String>>{
        lane: {
          ResultKeys.grade: 'F',
          ResultKeys.transport: 'reported',
          ResultKeys.rationale: 'critic transport failed',
        },
        'tg-1/review/coherence': {ResultKeys.grade: 'A'},
      };
      final ordinarySession = <String, Map<String, String>>{
        lane: {ResultKeys.grade: 'A', ResultKeys.transport: 'reported'},
      };

      expect(
        mergeOperatorRulings(stepResults, ordinarySession)[lane],
        stepResults[lane],
      );

      final session = Bead(
        id: 'tgdog-s',
        issueType: GridIssueTypes.session,
        metadata: operatorRulingMetadata(
          lane,
          grade: 'A',
          rationale: 'operator inspected the lane',
          evidenceSession: 'tgdog-s',
        ),
      );
      final sessionResults = projectCircuitResults(session);
      final merged = mergeOperatorRulings(stepResults, sessionResults);

      expect(merged[lane], {
        ResultKeys.grade: 'A',
        ResultKeys.transport: kOperatorRulingTransport,
        ResultKeys.rationale: 'operator inspected the lane',
        ResultKeys.evidenceSession: 'tgdog-s',
      });
      expect(merged['tg-1/review/coherence'], {ResultKeys.grade: 'A'});
      expect(stepResults[lane], {
        ResultKeys.grade: 'F',
        ResultKeys.transport: 'reported',
        ResultKeys.rationale: 'critic transport failed',
      });
      expect(sessionResults[lane], {
        ResultKeys.grade: 'A',
        ResultKeys.transport: kOperatorRulingTransport,
        ResultKeys.rationale: 'operator inspected the lane',
        ResultKeys.evidenceSession: 'tgdog-s',
      });
    });

    test('a grid.result.* key is never misread as cursor state — cursor '
        'stays empty (tg-eli phase 2: the flat projection retired, so a '
        'grid.result.* key has nothing left to collide with)', () {
      final merged = <String, dynamic>{
        'work_bead': 'genesis-7r9',
        ...nodeResultMetadata('genesis-7r9/land', {
          'pr_url': 'https://x/pull/9',
        }),
      };
      final session = Bead(
        id: 'tgdog-9',
        issueType: GridIssueTypes.session,
        metadata: merged,
      );
      final p = projectSession(session);
      expect(p.cursor, isEmpty);
      expect(p.results['genesis-7r9/land']!['pr_url'], 'https://x/pull/9');
    });

    test('a legacy grid.cursor.* key on a historical bead is INERT — ignored, '
        'never parsed, never crashes (tg-eli phase 2 drain guarantee)', () {
      final merged = <String, dynamic>{
        'rig': 'tgdog',
        'work_bead': 'genesis-7r9',
        'grid.cursor.genesis-7r9/agent.state': 'complete',
        'grid.cursor.genesis-7r9/verify.state': 'failed',
        ...startedIdentityMetadata(pgid: 99, pid: 100, token: 'fade'),
      };
      final session = Bead(
        id: 'tgdog-3',
        issueType: GridIssueTypes.session,
        metadata: merged,
      );
      final p = projectSession(session);
      expect(p.cursor, isEmpty);
      expect(p.pgid, 99);
      expect(p.token, 'fade');
      expect(p.workBeadId, 'genesis-7r9');
    });
  });

  group('rework verdict evidence', () {
    Bead session(String id, {Map<String, String> metadata = const {}}) => Bead(
      id: id,
      issueType: GridIssueTypes.session,
      metadata: {SessionBeadKeys.model: kSessionModelMolecule, ...metadata},
    );

    Bead step(
      String capability,
      Map<String, String> result, {
      Map<String, String> extra = const {},
    }) => Bead(
      id: 'step-$capability',
      issueType: GridIssueTypes.step,
      metadata: {
        MoleculeStepKeys.capability: capability,
        ...extra,
        ...nodeResultMetadata('work/review/$capability', result),
      },
    );

    test('production review capabilities charge at every grade', () {
      for (final capability in ['spec-critic', 'critic']) {
        for (final grade in ['A', 'B', 'C', 'D', 'E', 'F']) {
          expect(
            reworkVerdictEvidence(
              session: session('round'),
              steps: [
                step(capability, {ResultKeys.grade: grade}),
              ],
            ).reachedVerdict,
            isTrue,
            reason: '$capability $grade',
          );
        }
      }
    });

    test('readiness and discovery escalation are free regardless of grade', () {
      for (final capability in ['readiness', 'discovery']) {
        final evidence = reworkVerdictEvidence(
          session: session('round'),
          steps: [
            step(capability, {
              ResultKeys.grade: 'A',
              ResultKeys.routeVerdict: kRouteVerdictEscalate,
            }),
          ],
        );
        expect(evidence.reachedVerdict, isFalse);
        expect(evidence.freeReason, 'pre-dispatch route escalation');
      }
    });

    test(
      'capability identity, route advance, and ruling ownership classify',
      () {
        expect(
          reworkVerdictEvidence(
            session: session('round'),
            steps: [
              step(
                'arbitrary',
                {ResultKeys.grade: 'F'},
                extra: {MoleculeStepKeys.swarm: 'committee'},
              ),
            ],
          ).reachedVerdict,
          isFalse,
        );
        expect(
          reworkVerdictEvidence(
            session: session('round'),
            steps: [
              step('route', {ResultKeys.routeVerdict: kRouteVerdictAdvance}),
            ],
          ).reachedVerdict,
          isTrue,
        );
        for (final owner in ['round', 'prior', '']) {
          final ruling = operatorRulingMetadata(
            'work/review/coherence',
            grade: 'A',
            rationale: 'inspected',
            evidenceSession: owner,
          );
          expect(
            reworkVerdictEvidence(
              session: session('round', metadata: ruling),
              steps: const [],
            ).reachedVerdict,
            owner == 'round',
            reason: 'owner=$owner',
          );
        }
      },
    );

    test('legacy flat session grades remain verdict evidence', () {
      final legacy = Bead(
        id: 'legacy',
        metadata: nodeResultMetadata('work/review/coherence', {
          ResultKeys.grade: 'F',
        }),
      );
      expect(
        reworkVerdictEvidence(session: legacy, steps: const []).reachedVerdict,
        isTrue,
      );
    });
  });
}
