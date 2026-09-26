// The live proxied-store tests' OWN serialisation (tg-ejzb).
//
// Two concurrent lanes each running `substation_attach_live_test.dart` start
// two sets of `bd init --proxied-server` / `bd dolt start` at once, and the
// review/route code-validation lane hard-blocked two unrelated beads on the
// resulting `invalid connection` / missing `proxy.pid` failures. The decision
// the_grid#hermetic-guard-is-the-live-tests-own-default puts a live test's
// safety default IN the test: a guard an invoker can turn off is not a guard,
// so this is neither an `integration` exclusion nor a lane scheduling rule.
//
// Modelled on `packages/grid_cli/lib/src/station_lock.dart` (exclusive-create
// claim, pid-liveness arbitration, loud steal of a dead holder, bounded hold on
// an unreadable record) — NOT imported: grid_cli depends on grid_sdk, and this
// file must not invert that arc. It is test support, so it also differs where
// a station lock must not: a record unreadable past the hold window is stolen
// (a torn test lock has no supervisor behind it), and a live holder is WAITED
// on up to a bounded deadline rather than refused.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The default bound on waiting for another process to release the lock —
/// generous enough for a whole run of the live suite ahead of us, and the
/// test's own `timeout:` must exceed it.
const Duration kLiveStoreLockWait = Duration(minutes: 5);

/// The unreadable-record hold: a claim that stays EMPTY or torn this long has
/// no writer behind it (the claimant publishes right after the create).
const Duration kLiveStoreLockHold = Duration(seconds: 2);

/// The lock path shared by every process on this machine.
String liveStoreLockPath() =>
    p.join(Directory.systemTemp.path, 'grid_sdk-live-store-tests.lock');

/// Runs [body] while holding the machine-wide live-store lock, so two
/// processes never bootstrap or tear down proxied bd stores at once.
///
/// Waits up to [within] for a LIVE holder to release; a dead holder's record
/// is stolen with a loud line; an unreadable record is re-read through
/// [kLiveStoreLockHold] and then stolen. Throws a [TimeoutException] naming
/// the lock and its holder when [within] passes — the test then fails loudly
/// instead of racing.
Future<T> withLiveStoreLock<T>(
  Future<T> Function() body, {
  Duration within = kLiveStoreLockWait,
  void Function(String line)? log,
}) async {
  final file = File(liveStoreLockPath());
  final void Function(String) out = log ?? stderr.writeln;
  await _acquire(file, within: within, log: out);
  try {
    return await body();
  } finally {
    await _release(file);
  }
}

Future<void> _acquire(
  File file, {
  required Duration within,
  required void Function(String) log,
}) async {
  final waited = Stopwatch()..start();
  var backoff = const Duration(milliseconds: 100);
  var unreadableSince = Stopwatch();
  for (;;) {
    try {
      await file.create(exclusive: true);
    } on PathExistsException {
      final holder = _readHolder(file);
      if (holder == null) {
        if (!file.existsSync()) continue; // released under us; retry at once
        if (!unreadableSince.isRunning) unreadableSince.start();
        if (unreadableSince.elapsed >= kLiveStoreLockHold) {
          log(
            'live-store lock: STEALING unreadable ${file.path} (stayed '
            'unreadable for ${unreadableSince.elapsedMilliseconds}ms — a torn '
            'test lock has no writer behind it)',
          );
          _deleteQuietly(file);
          unreadableSince = Stopwatch();
        }
      } else {
        unreadableSince = Stopwatch();
        // A holder in THIS process is a live holder too: `dart test` runs
        // suites as isolates of one process, so two live files in one run
        // share a pid and must still take turns.
        if (!_pidAlive(holder.pid)) {
          log(
            'live-store lock: STEALING stale ${file.path} (pid ${holder.pid} '
            'dead — the previous test process exited without releasing)',
          );
          _deleteQuietly(file);
          continue;
        }
        if (waited.elapsed >= within) {
          throw TimeoutException(
            'live-store lock: ${file.path} is still held by pid '
            '${holder.pid} (since ${holder.since.toIso8601String()}) after '
            'waiting ${waited.elapsed.inSeconds}s — refusing to start a '
            'second live proxied-store test beside it',
            within,
          );
        }
      }
      await Future<void>.delayed(backoff);
      backoff *= 2;
      if (backoff > const Duration(seconds: 1)) {
        backoff = const Duration(seconds: 1);
      }
      continue;
    }
    // The claim is ours: publish who holds it, at once.
    file.writeAsStringSync(
      jsonEncode({'pid': pid, 'since': DateTime.now().toIso8601String()}),
    );
    return;
  }
}

Future<void> _release(File file) async {
  final holder = _readHolder(file);
  if (holder != null && holder.pid != pid) {
    // Never a same-process check beyond the pid: two isolates of one process
    // cannot both hold the claim, so a same-pid record is ours.
    stderr.writeln(
      'live-store lock: NOT releasing ${file.path} — held by pid '
      '${holder.pid}, not this process ($pid)',
    );
    return;
  }
  _deleteQuietly(file);
}

({int pid, DateTime since})? _readHolder(File file) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded case {
      'pid': final int holderPid,
      'since': final String since,
    } when holderPid > 0) {
      return (pid: holderPid, since: DateTime.parse(since));
    }
  } on Object {
    // Absent, empty, or mid-write: the caller decides how long to hold.
  }
  return null;
}

void _deleteQuietly(File file) {
  try {
    file.deleteSync();
  } on Object {
    // Already gone — another waiter stole or the holder released.
  }
}

/// SIGWINCH is a harmless liveness probe (the same probe the live test's
/// fence uses).
bool _pidAlive(int candidate) =>
    Process.killPid(candidate, ProcessSignal.sigwinch);
