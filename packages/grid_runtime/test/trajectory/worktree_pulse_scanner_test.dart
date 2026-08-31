// W7 (tg-zfek Stage 1) — the worktree `.grid` mtime scanner, liveness surface
// (a) of stage1-wiring §2.3.
//
// Real directories throughout: the scanner's whole job is filesystem truth, so
// a faked filesystem would test nothing. The last group is the design's
// explicit W7 acceptance item — the scan's I/O cost measured against N
// CONCURRENT worktree dirs, asserted in budget against the 30 s tick interval.
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
    test('is the NEWEST file mtime anywhere under the worktree .grid', () {
      final newest = DateTime.utc(2026, 8, 31, 9, 30);
      final worktree = _worktree(root, 'tg-aaa', newestAt: newest);
      // An older sibling in another subdir must not win.
      final critique = Directory(p.join(worktree.path, '.grid', 'critique'))
        ..createSync(recursive: true);
      File(p.join(critique.path, 'coherence.json'))
        ..writeAsStringSync('{}')
        ..setLastModifiedSync(DateTime.utc(2026, 8, 30));

      final scan = const WorktreePulseScanner().scan([worktree.path]);

      expect(scan.beats[worktree.path], newest);
      expect(scan.cost.scanned, 1);
    });

    test('is ABSENT for a worktree with no .grid — the detector reads that as '
        'unknown, never as lost', () {
      final bare = Directory(p.join(root.path, 'tg-bare'))..createSync();

      final scan = const WorktreePulseScanner().scan([bare.path]);

      expect(scan.beats, isEmpty);
      expect(scan.cost.worktrees, 1);
      expect(scan.cost.scanned, 0);
    });

    test('is ABSENT for a worktree reaped out from under the scan — a missing '
        'path is the ordinary case, not an error', () {
      final worktree = _worktree(root, 'tg-gone');
      final path = worktree.path;
      worktree.deleteSync(recursive: true);

      final scan = const WorktreePulseScanner().scan([path]);

      expect(scan.beats, isEmpty);
      expect(scan.cost.scanned, 0);
    });

    test('is ABSENT for an EMPTY .grid (a provisioned worktree that has not '
        'written yet)', () {
      final worktree = Directory(p.join(root.path, 'tg-empty'))..createSync();
      Directory(p.join(worktree.path, '.grid')).createSync();

      final scan = const WorktreePulseScanner().scan([worktree.path]);

      expect(scan.beats, isEmpty);
      // It WAS walked — "scanned, found nothing" is a different fact from
      // "there was nothing to walk".
      expect(scan.cost.scanned, 1);
      expect(scan.cost.entries, 0);
    });

    test('collapses duplicate paths — several attempts of one session share '
        'one worktree', () {
      final worktree = _worktree(root, 'tg-dup');

      final scan = const WorktreePulseScanner().scan([
        worktree.path,
        worktree.path,
        worktree.path,
      ]);

      expect(scan.cost.worktrees, 1);
      expect(scan.cost.entries, 4); // the telemetry dir + its three files
    });
  });

  group('I/O cost against N concurrent worktrees (§6 W7: in budget)', () {
    test('one pass over 32 live worktrees stats exactly their entries and '
        'costs a small fraction of the 30 s tick', () {
      const worktrees = 32;
      const filesEach = 24; // what a full round leaves under .grid/telemetry
      final paths = [
        for (var i = 0; i < worktrees; i++)
          _worktree(root, 'tg-load-$i', files: filesEach).path,
      ];

      final scan = const WorktreePulseScanner().scan(paths);

      expect(scan.beats.length, worktrees);
      expect(scan.cost.worktrees, worktrees);
      expect(scan.cost.scanned, worktrees);
      // The cost model, pinned: one walk per worktree, one stat per entry —
      // the telemetry dir plus its files, no re-walks.
      expect(scan.cost.entries, worktrees * (filesEach + 1));
      // The budget: the scan runs INSIDE a tick pass on the harness's serial
      // lane, so it must be small against the 30 s tick interval. The bound is
      // deliberately loose (CI filesystems vary by an order of magnitude) and
      // still 15x under the interval; the measured local number for this shape
      // is single-digit milliseconds.
      expect(
        scan.cost.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason: 'scan cost for $worktrees worktrees: ${scan.cost}',
      );
      printOnFailure('${scan.cost}');
    });

    test('scales with entries, not with worktrees stat-ing each other — a '
        'worktree with no .grid adds nothing to the walk', () {
      final live = _worktree(root, 'tg-live', files: 5);
      final bare = [
        for (var i = 0; i < 24; i++)
          (Directory(p.join(root.path, 'tg-bare-$i'))..createSync()).path,
      ];

      final scan = const WorktreePulseScanner().scan([live.path, ...bare]);

      expect(scan.cost.worktrees, 25);
      expect(scan.cost.scanned, 1);
      expect(scan.cost.entries, 6);
    });
  });
}
