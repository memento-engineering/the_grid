import 'dart:convert';

import 'package:grid_cli/src/event_renderer.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

final _at = DateTime.utc(2026, 6, 11, 6, 45, 50, 784);

Bead _bead(String id, {String title = 'title'}) =>
    Bead(id: id, title: title, issueType: IssueType.molecule);

void main() {
  group('EventRenderer human output', () {
    final r = EventRenderer(json: false);

    test('BeadCreated line carries id, title, type, and reaction latency', () {
      final line = r.render(
        BeadCreated(_bead('tg-1', title: 'tron lives')),
        reaction: const Duration(milliseconds: 213),
        at: _at,
      );
      expect(line, contains('BeadCreated'));
      expect(line, contains('tg-1'));
      expect(line, contains('tron lives'));
      expect(line, contains('[molecule]'));
      expect(line, contains('(reacted 213ms)'));
      expect(line, startsWith('06:45:50.784'));
    });

    test('ReadySetChanged shows sorted entered/exited sets', () {
      final line = r.render(
        const ReadySetChanged(entered: {'b', 'a'}, exited: {'c'}),
        reaction: const Duration(milliseconds: 100),
        at: _at,
      );
      expect(line, contains('+[a, b]'));
      expect(line, contains('-[c]'));
    });

    test('no reaction tag when latency is null (baseline)', () {
      final line = r.render(
        const SnapshotInitialized(beadCount: 3, readyCount: 1),
        at: _at,
      );
      expect(line, contains('SnapshotInitialized — 3 beads, 1 ready'));
      expect(line, isNot(contains('reacted')));
    });
  });

  group('EventRenderer NDJSON output', () {
    final r = EventRenderer(json: true);

    test('emits a parseable record with ts, reactionMs, and event', () {
      final line = r.render(
        BeadClosed(before: _bead('tg-9'), after: _bead('tg-9')),
        reaction: const Duration(milliseconds: 88),
        at: _at,
      );
      final decoded = jsonDecode(line) as Map<String, dynamic>;
      expect(decoded['reactionMs'], 88);
      expect(decoded['ts'], _at.toIso8601String());
      expect((decoded['event'] as Map)['type'], 'beadClosed');
      expect((decoded['event'] as Map)['id'], 'tg-9');
    });
  });
}
