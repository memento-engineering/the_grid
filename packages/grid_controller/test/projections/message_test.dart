import 'package:grid_controller/grid_controller.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

Bead _firstBead(String fixture) {
  final env = BdEnvelope.parse(fixtureText(fixture));
  return Bead.fromJson(env.dataList.first);
}

void main() {
  group('Message.project against hq-message-sample.json (ga-wisp-y9uqd9)', () {
    test('maps recipient=assignee, sender=metadata.from, thread label', () {
      final bead = _firstBead('hq-message-sample.json');
      final message = Message.project(bead).valueOrNull!;

      expect(message.id, 'ga-wisp-y9uqd9');
      expect(message.title, 'Dolt health advisory [MEDIUM]');
      expect(message.recipient, 'mayor');
      expect(message.sender, 'controller');
      expect(message.threadId, 'thread-067ce293d2d4');
      expect(message.body, contains('Latency'));
    });

    test('open + addressed message is unread; not archived', () {
      final message = Message.project(
        _firstBead('hq-message-sample.json'),
      ).valueOrNull!;
      expect(message.archived, isFalse);
      expect(message.isUnread, isTrue);
    });

    test('unknown metadata keys preserved in raw', () {
      final message = Message.project(
        _firstBead('hq-message-sample.json'),
      ).valueOrNull!;
      expect(message.metadata.raw['from'], 'controller');
    });
  });

  group('Message semantics', () {
    test('closing = archiving: closed bead is archived and not unread', () {
      const bead = Bead(
        id: 'm',
        issueType: IssueType.message,
        assignee: 'mayor',
        status: BeadStatus.closed,
      );
      final message = Message.project(bead).valueOrNull!;
      expect(message.archived, isTrue);
      expect(message.isUnread, isFalse);
    });

    test('open message with no recipient is not unread', () {
      const bead = Bead(id: 'm', issueType: IssueType.message);
      expect(Message.project(bead).valueOrNull!.isUnread, isFalse);
    });

    test('threadId is null when no thread:<id> label present', () {
      const bead = Bead(
        id: 'm',
        issueType: IssueType.message,
        labels: ['other:x'],
      );
      expect(Message.project(bead).valueOrNull!.threadId, isNull);
    });

    test('a non-message bead returns a typed ProjectionError', () {
      const bead = Bead(id: 'x', issueType: IssueType.session);
      final result = Message.project(bead);
      expect(result.isOk, isFalse);
      expect(result.errorOrNull!.projection, 'Message');
      expect(result.errorOrNull!.issueType, 'session');
    });
  });
}
