// W7 (tg-zfek Stage 1) — the worktree `.grid` mtime scanner, liveness surface
// (a) of stage1-wiring §2.3.
//
// Real directories throughout: the scanner's whole job is filesystem truth, so
// a faked filesystem would test nothing. The last group is the design's
// explicit W7 acceptance item — the scan's I/O cost measured against N
// CONCURRENT worktree dirs, asserted against the axis that matters (quality
// M4): the ISOLATE STALL the scan imposes, since it runs on the station's one
// isolate beside every engine build — not merely its wall-clock share of the
// 30 s tick period.
import 'dart:async';
import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Builds `<root>/<name>/.grid/telemetry/*.usage.json` — the shape a live
/// round actually writes. With [newestAt] every file gets an explicit mtime,
/// the last one landing exactly on [newestAt].
Directory _worktree(
  Directory root,
  String name, {
  int files = 3,
  DateTime? newestAt,
}) {
  final worktree = Directory(p.join(root.path, name))..createSync();
  final telemetry = Directory(p.join(worktree.path, '.grid', 'telemetry'))
    ..createSync(recursive: true);
  for (var i = 0; i < files; i++) {
    final file = File(p.join(telemetry.path, '${name}_$i.usage.json'))
      ..writeAsStringSync('{"turns": $i}');
    if (newestAt != null) {
      file.setLastModifiedSync(
        newestAt.subtract(Duration(minutes: files - 1 - i)),
      );
    }
  }
  return worktree;
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('w7-scanner'));
  tearDown(() => root.deleteSync(recursive: true));

  group('the beat', () {
    test(
      'is the NEWEST file mtime anywhere under the worktree .grid',
      () async {
        final newest = DateTime.utc(2026, 8, 31, 9, 30);
        final worktree = _worktree(root, 'tg-aaa', newestAt: newest);
        // An older sibling in another subdir must not win.
        final critique = Directory(p.join(worktree.path, '.grid', 'critique'))
          ..createSync(recursive: true);
        File(p.join(critique.path, 'coherence.json'))
          ..writeAsStringSync('{}')
          ..setLastModifiedSync(DateTime.utc(2026, 8, 30));

        final scan = await const WorktreePulseScanner().scan([worktree.path]);

        expect(scan.beats[worktree.path], newest);
        expect(scan.cost.scanned, 1);
      },
    );

    test('is ABSENT for a worktree with no .grid — the detector reads that as '
        'unknown, never as lost', () async {
      final bare = Directory(p.join(root.path, 'tg-bare'))..createSync();

      final scan = await const WorktreePulseScanner().scan([bare.path]);

      expect(scan.beats, isEmpty);
      expect(scan.cost.worktrees, 1);
      expect(scan.cost.scanned, 0);
    });

    test('is ABSENT for a worktree reaped out from under the scan — a missing '
        'path is the ordinary case, not an error', () async {
      final worktree = _worktree(root, 'tg-gone');
      final path = worktree.path;
      worktree.deleteSync(recursive: true);

      final scan = await const WorktreePulseScanner().scan([path]);

      expect(scan.beats, isEmpty);
      expect(scan.cost.scanned, 0);
    });

    test('is ABSENT for an EMPTY .grid (a provisioned worktree that has not '
        'written yet)', () async {
      final worktree = Directory(p.join(root.path, 'tg-empty'))..createSync();
      Directory(p.join(worktree.path, '.grid')).createSync();

      final scan = await const WorktreePulseScanner().scan([worktree.path]);

      expect(scan.beats, isEmpty);
      // It WAS walked — "scanned, found nothing" is a different fact from
      // "there was nothing to walk".
      expect(scan.cost.scanned, 1);
      expect(scan.cost.entries, 0);
    });

    test('collapses duplicate paths — several attempts of one session share '
        'one worktree', () async {
      final worktree = _worktree(root, 'tg-dup');

      final scan = await const WorktreePulseScanner().scan([
        worktree.path,
        worktree.path,
        worktree.path,
      ]);

      expect(scan.cost.worktrees, 1);
      expect(scan.cost.entries, 4); // the telemetry dir + its three files
    });
  });

  group('I/O cost against N concurrent worktrees (§6 W7: in budget)', () {
    test('one pass over 32 live worktrees stats exactly their entries, stays '
        'in budget, and never stalls the isolate for the walk', () async {
      const worktrees = 32;
      const filesEach = 24; // what a full round leaves under .grid/telemetry
      final paths = [
        for (var i = 0; i < worktrees; i++)
          _worktree(root, 'tg-load-$i', files: filesEach).path,
      ];

      // The stall probe: a 5 ms heartbeat riding the SAME event loop as the
      // scan. A synchronous recursive walk (the old listSync/statSync shape)
      // would freeze it for the whole walk; the async scanner must keep every
      // gap at syscall scale. The bound is loose for CI filesystems and still
      // two orders of magnitude under the walk a sync scan of a big tree
      // costs.
      final gaps = <Duration>[];
      var last = DateTime.now();
      final probe = Timer.periodic(const Duration(milliseconds: 5), (_) {
        final now = DateTime.now();
        gaps.add(now.difference(last));
        last = now;
      });
      final WorktreeScan scan;
      try {
        scan = await const WorktreePulseScanner().scan(paths);
      } finally {
        probe.cancel();
      }

      expect(scan.beats.length, worktrees);
      expect(scan.cost.worktrees, worktrees);
      expect(scan.cost.scanned, worktrees);
      // The cost model, pinned: one walk per worktree, one stat per entry —
      // the telemetry dir plus its files, no re-walks.
      expect(scan.cost.entries, worktrees * (filesEach + 1));
      // The wall-clock budget: small against the 30 s tick interval, loose
      // against CI filesystem variance. The measured local number for this
      // shape is single-digit milliseconds.
      expect(
        scan.cost.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason: 'scan cost for $worktrees worktrees: ${scan.cost}',
      );
      // The stall budget — the in-budget assertion the adjudication asks for:
      // the longest event-loop gap the scan imposed.
      final maxGap = gaps.fold(Duration.zero, (a, b) => a > b ? a : b);
      expect(
        maxGap,
        lessThan(const Duration(milliseconds: 250)),
        reason:
            'max isolate stall during the scan: ${maxGap.inMilliseconds}ms '
            '(cost: ${scan.cost})',
      );
      printOnFailure('${scan.cost} maxStall=${maxGap.inMilliseconds}ms');
    });

    test('scales with entries, not with worktrees stat-ing each other — a '
        'worktree with no .grid adds nothing to the walk', () async {
      final live = _worktree(root, 'tg-live', files: 5);
      final bare = [
        for (var i = 0; i < 24; i++)
          (Directory(p.join(root.path, 'tg-bare-$i'))..createSync()).path,
      ];

      final scan = await const WorktreePulseScanner().scan([
        live.path,
        ...bare,
      ]);

      expect(scan.cost.worktrees, 25);
      expect(scan.cost.scanned, 1);
      expect(scan.cost.entries, 6);
    });
  });
}
