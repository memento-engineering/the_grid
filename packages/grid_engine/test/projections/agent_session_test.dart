import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

Bead _firstBead(String fixture) {
  final env = BdEnvelope.parse(fixtureText(fixture));
  return Bead.fromJson(env.dataList.first);
}

List<Bead> _allBeads(String fixture) {
  final env = BdEnvelope.parse(fixtureText(fixture));
  return [for (final json in env.dataList) Bead.fromJson(json)];
}

void main() {
  group('AgentSession.project against hq-session-sample.json (ga-dvt2)', () {
    test('maps the session.* metadata namespace to typed getters', () {
      final bead = _firstBead('hq-session-sample.json');
      final result = AgentSession.project(bead);
      expect(result.isOk, isTrue);
      final session = result.valueOrNull!;

      expect(session.id, 'ga-dvt2');
      expect(session.title, 'lenny/pack.critique-1');
      // durable identity comes from metadata.agent_name.
      expect(session.agentName, 'lenny/pack.critique-1');
      expect(session.metadata.alias, 'lenny/pack.critique-1');
      expect(session.metadata.command, startsWith('claude '));
      expect(session.metadata.continuationEpoch, 1);
      expect(session.metadata.lifecycleState, 'drained');
      expect(session.metadata.template, 'lenny/pack.critique-1');
      expect(session.metadata.provider, 'claude');
      expect(session.metadata.poolManaged, isTrue);
    });

    test('closed bead projects to SessionState.closed with close fields', () {
      final session = AgentSession.project(
        _firstBead('hq-session-sample.json'),
      ).valueOrNull!;
      expect(session.state, SessionState.closed);
      expect(session.isClosed, isTrue);
      expect(session.isOpen, isFalse);
      expect(session.closeReason, contains('session drained'));
      expect(session.closedAt, isNotNull);
    });

    test('unknown metadata keys are preserved verbatim in raw', () {
      final session = AgentSession.project(
        _firstBead('hq-session-sample.json'),
      ).valueOrNull!;
      // session_key is not a typed getter but must survive in raw.
      expect(
        session.metadata.raw['session_key'],
        'ee774ef7-9703-496a-a101-1a9320fb1ddb',
      );
      expect(session.metadata.raw['work_dir'], isNotEmpty);
    });

    test('all three sample sessions project without error', () {
      for (final bead in _allBeads('hq-session-sample.json')) {
        final result = AgentSession.project(bead);
        expect(result.isOk, isTrue, reason: 'failed on ${bead.id}');
      }
    });
  });

  group('AgentSession.project decode failures', () {
    test(
      'a non-session bead returns a typed ProjectionError, never throws',
      () {
        const bead = Bead(id: 'x', issueType: IssueType.message);
        final result = AgentSession.project(bead);
        expect(result.isOk, isFalse);
        final error = result.errorOrNull!;
        expect(error.beadId, 'x');
        expect(error.projection, 'AgentSession');
        expect(error.issueType, 'message');
      },
    );

    test('open status projects to SessionState.open', () {
      const bead = Bead(id: 's', issueType: IssueType.session);
      final session = AgentSession.project(bead).valueOrNull!;
      expect(session.state, SessionState.open);
      expect(session.isOpen, isTrue);
    });

    test('agentName falls back to title when metadata.agent_name absent', () {
      const bead = Bead(id: 's', title: 'pack.x', issueType: IssueType.session);
      expect(AgentSession.project(bead).valueOrNull!.agentName, 'pack.x');
    });
  });
}
