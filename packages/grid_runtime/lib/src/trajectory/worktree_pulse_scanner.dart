/// The worktree `.grid` mtime scanner — liveness surface (a) of stage1-wiring
/// §2.3's r2 major 11.
///
/// The design names TWO real surfaces for the liveness detector and rules out
/// the rest: `RuntimeEvent.activityChanged` has no production emitter, and the
/// wedge monitor reads BEAD state, not liveness. What tells the truth about a
/// dead session is the standing operational finding this file implements — the
/// file mtimes under a session's `<worktree>/.grid`: a live round rewrites its
/// discovery/critique/telemetry artifacts every minute or two, and a frozen
/// newest-mtime IS the diagnosis.
///
/// **Read-only, always.** The scanner stats; it never creates, writes, or
/// removes anything (§2.4: nothing that writes bd or the filesystem arms in the
/// shadow window). A missing worktree, a missing `.grid`, or an unreadable
/// entry yields NO beat — never an exception into the tick.
///
/// **The cost is budgeted, not assumed** (§6's W7 row): every scan returns its
/// own [WorktreeScanCost] — worktrees visited, entries stat'ed, elapsed — so
/// the tick's I/O against N concurrent worktrees is a measured number in the
/// tests and an observable one in production.
library;

import 'dart:io' as io;

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The per-worktree state directory the scanner reads. `.grid` inside the
/// worktree — the SESSION's artifacts, not the grid home's store.
const String kWorktreeStateDirName = '.grid';

/// One scan's measured cost — the in-budget check's raw material.
@immutable
final class WorktreeScanCost {
  const WorktreeScanCost({
    required this.worktrees,
    required this.scanned,
    required this.entries,
    required this.elapsed,
  });

  /// Paths handed in.
  final int worktrees;

  /// Paths that actually had a `.grid` directory to walk.
  final int scanned;

  /// Filesystem entries stat'ed across the whole scan — the term that grows
  /// with N concurrent worktrees, and the one a budget is written against.
  final int entries;

  final Duration elapsed;

  @override
  String toString() =>
      'WorktreeScanCost(worktrees: $worktrees, scanned: $scanned, '
      'entries: $entries, elapsed: ${elapsed.inMilliseconds}ms)';
}

/// A scan's beats plus its cost.
@immutable
final class WorktreeScan {
  const WorktreeScan({required this.beats, required this.cost});

  /// worktree path → newest mtime under its `.grid`. A path with no `.grid`,
  /// an empty one, or one that cannot be read is ABSENT — the detector reads
  /// absence as "no beat observed", which is `unknown`, never `lost`.
  final Map<String, DateTime> beats;

  final WorktreeScanCost cost;
}

/// Walks each live worktree's `.grid` and reports the newest file mtime.
class WorktreePulseScanner {
  /// The scanner reads ONLY the paths it is handed — they come from P6's
  /// `worktree` column, which the station itself wrote — so it needs no root
  /// and holds no state.
  const WorktreePulseScanner();

  /// Scans [worktrees] (duplicates collapse) and returns the newest `.grid`
  /// mtime per path.
  WorktreeScan scan(Iterable<String> worktrees) {
    final watch = Stopwatch()..start();
    final unique = <String>{...worktrees};
    final beats = <String, DateTime>{};
    var scanned = 0;
    var entries = 0;
    for (final worktree in unique) {
      final directory = io.Directory(p.join(worktree, kWorktreeStateDirName));
      final List<io.FileSystemEntity> listing;
      try {
        if (!directory.existsSync()) continue;
        listing = directory.listSync(recursive: true, followLinks: false);
      } on io.FileSystemException {
        // A worktree reaped mid-scan is the ordinary case, not an error: no
        // beat, and the detector's unknown rule takes it from there.
        continue;
      }
      scanned += 1;
      DateTime? newest;
      for (final entry in listing) {
        entries += 1;
        if (entry is! io.File) continue;
        final DateTime modified;
        try {
          modified = entry.statSync().modified;
        } on io.FileSystemException {
          continue;
        }
        if (newest == null || modified.isAfter(newest)) newest = modified;
      }
      if (newest != null) beats[worktree] = newest.toUtc();
    }
    watch.stop();
    return WorktreeScan(
      beats: Map<String, DateTime>.unmodifiable(beats),
      cost: WorktreeScanCost(
        worktrees: unique.length,
        scanned: scanned,
        entries: entries,
        elapsed: watch.elapsed,
      ),
    );
  }
}
