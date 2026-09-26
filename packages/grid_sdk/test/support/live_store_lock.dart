// The live proxied-store tests' OWN serialisation (tg-ejzb).
//
// Two concurrent lanes each running `substation_attach_live_test.dart` start
// two sets of `bd init --proxied-server` / `bd dolt start` at once, and the
// review/route code-validation lane hard-blocked two unrelated beads on the
// resulting `invalid connection` / missing `proxy.pid` failures. The decision
// the_grid#hermetic-guard-is-the-live-tests-own-default puts a live test's
// safety default IN the test: a guard an invoker can turn off is not a guard,
// so this is neither an `integration` exclusion nor a lane scheduling rule —
// the live tests carry no tag and run in every default lane, serialised here.
//
// Modelled on `packages/grid_cli/lib/src/station_lock.dart` (pid-liveness
// arbitration, a loud line for every record it removes) — NOT imported:
// grid_cli depends on grid_sdk, and this file must not invert that arc. It is
// test support, so its shape differs where a station lock's must not:
//
// * FAIR. The lock is a FIFO QUEUE of ticket files in one directory, ordered
//   by arrival (a zero-padded microsecond stamp, then pid, then a random
//   suffix). A waiter holds the lock when its ticket is the oldest live one,
//   so N lanes wait N-1 holds at most — never an unbounded, luck-of-the-
//   backoff wait behind a lane that keeps re-acquiring first.
// * NO TORN RECORDS. Liveness is read from the ticket's NAME (the pid is part
//   of it), never from its contents, so a half-written record cannot stall the
//   queue.
// * SELF-HEALING. A ticket whose pid is dead is pruned with a loud line; a
//   ticket older than [kLiveStoreHoldBound] — longer than any live test's own
//   timeout, so no legitimate hold reaches it — is ABANDONED (an isolate the
//   runner gave up on inside a process that lives on) and is pruned too.
// * DEGRADES, NEVER FAILS. Past [kLiveStoreLockPatience] a starved waiter
//   logs a loud line naming the holder and runs its body UNSERIALISED rather
//   than throwing: a hard failure here would re-create the very lane block
//   this lock exists to remove, and the product-side bounded readiness wait
//   (`awaitProxiedStoreEndpoint`) still guards the known race.
// * A waiter only ever deletes ITS OWN ticket, or a ticket its liveness rules
//   PROVE stale. The unit tests run against their own temp directory
//   ([withLiveStoreLock]'s `directory:`) and never touch the machine-wide
//   queue a live test in another process may be holding.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// How long a waiter queues before it DEGRADES to running unserialised (with
/// a loud line) instead of waiting on. Generous: a live-store hold measures
/// ~25 s, so this covers a dozen lanes queued ahead.
const Duration kLiveStoreLockPatience = Duration(minutes: 5);

/// The age past which a LIVE pid's ticket is presumed abandoned and pruned.
/// It must exceed every live test's own `timeout:` (8 minutes), so no hold the
/// runner still honours is ever pruned out from under its holder.
const Duration kLiveStoreHoldBound = Duration(minutes: 10);

/// The settle a waiter re-lists through after it first sees itself at the
/// head, so a peer whose stamp was taken a beat before ours but whose ticket
/// landed a beat after is seen before we start.
const Duration _kHeadSettle = Duration(milliseconds: 50);

/// The machine-wide queue directory every live proxied-store test shares.
///
/// A FIXED path, deliberately NOT `Directory.systemTemp`: that follows
/// `TMPDIR`, which differs per session, sandbox and lane runner, and two
/// processes with different `TMPDIR`s would each queue in their own directory
/// and never see each other — exactly the concurrent lanes this lock is for.
/// `/tmp` is the one directory every POSIX process on the machine shares; the
/// system temp is only the fallback where `/tmp` does not exist.
String liveStoreLockDirectory() {
  const shared = '/tmp';
  final base = !Platform.isWindows && Directory(shared).existsSync()
      ? shared
      : Directory.systemTemp.path;
  return p.join(base, 'grid_sdk-live-store-tests.queue');
}

/// Runs [body] while holding the live-store lock, so two holders — two
/// processes, or two isolates of one — never bootstrap or tear down proxied bd
/// stores at once.
///
/// [directory] defaults to the machine-wide [liveStoreLockDirectory]; a unit
/// test passes its own temp directory. [patience] bounds how long this waiter
/// queues before degrading (see the file header); [holdBound] is the age past
/// which a live pid's ticket is pruned as abandoned. Never throws for a busy
/// lock: a starved waiter runs its body unserialised, loudly. [log] receives
/// every loud line (stderr by default).
Future<T> withLiveStoreLock<T>(
  Future<T> Function() body, {
  String? directory,
  Duration patience = kLiveStoreLockPatience,
  Duration holdBound = kLiveStoreHoldBound,
  void Function(String line)? log,
}) async {
  final queue = Directory(directory ?? liveStoreLockDirectory());
  final void Function(String) out = log ?? stderr.writeln;
  final ticket = await _enqueue(queue);
  try {
    await _awaitHead(
      queue,
      ticket,
      patience: patience,
      holdBound: holdBound,
      log: out,
    );
    return await body();
  } finally {
    _deleteQuietly(ticket);
  }
}

final Random _random = Random();

/// Creates this waiter's ticket at the tail of [queue].
Future<File> _enqueue(Directory queue) async {
  await queue.create(recursive: true);
  for (;;) {
    final stamp = DateTime.now().microsecondsSinceEpoch.toString().padLeft(
      20,
      '0',
    );
    final suffix = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    final ticket = File(p.join(queue.path, '$stamp-$pid-$suffix.ticket'));
    try {
      await ticket.create(exclusive: true);
      return ticket;
    } on PathExistsException {
      // A same-microsecond, same-suffix collision: draw again.
    }
  }
}

/// Waits until [ticket] is the oldest live ticket in [queue], pruning dead and
/// abandoned tickets on the way, or until [patience] elapses — then returns
/// anyway, after a loud line naming who is still ahead.
Future<void> _awaitHead(
  Directory queue,
  File ticket, {
  required Duration patience,
  required Duration holdBound,
  required void Function(String) log,
}) async {
  final mine = p.basename(ticket.path);
  final waited = Stopwatch()..start();
  var backoff = const Duration(milliseconds: 50);
  var settled = false;
  for (;;) {
    final ahead = _liveTicketsAhead(
      queue,
      mine,
      holdBound: holdBound,
      log: log,
    );
    if (ahead.isEmpty) {
      if (settled) return;
      settled = true;
      await Future<void>.delayed(_kHeadSettle);
      continue;
    }
    settled = false;
    if (waited.elapsed >= patience) {
      log(
        'live-store lock: DEGRADED after waiting ${waited.elapsed.inSeconds}s '
        'in ${queue.path} — ${ahead.length} ticket(s) still ahead, the head '
        'held by pid ${_pidOf(ahead.first)} (${ahead.first}); running '
        'UNSERIALISED rather than failing the lane',
      );
      return;
    }
    await Future<void>.delayed(backoff);
    backoff *= 2;
    if (backoff > const Duration(milliseconds: 500)) {
      backoff = const Duration(milliseconds: 500);
    }
  }
}

/// The live tickets that sort before [mine], oldest first. Prunes — loudly —
/// a ticket whose pid is dead, or one older than [holdBound].
List<String> _liveTicketsAhead(
  Directory queue,
  String mine, {
  required Duration holdBound,
  required void Function(String) log,
}) {
  final names = <String>[
    for (final entity in queue.listSync())
      if (entity is File && entity.path.endsWith('.ticket'))
        p.basename(entity.path),
  ]..sort();
  final ahead = <String>[];
  final now = DateTime.now().microsecondsSinceEpoch;
  for (final name in names) {
    if (name.compareTo(mine) >= 0) break;
    final holder = _pidOf(name);
    final stamp = _stampOf(name);
    if (holder == null || stamp == null) {
      // Not a ticket this code wrote; never ours to judge or delete.
      continue;
    }
    if (holder != pid && !_pidAlive(holder)) {
      log(
        'live-store lock: PRUNING stale ticket $name in ${queue.path} (pid '
        '$holder is dead — its process exited without releasing)',
      );
      _deleteQuietly(File(p.join(queue.path, name)));
      continue;
    }
    final age = Duration(microseconds: now - stamp);
    if (age > holdBound) {
      log(
        'live-store lock: PRUNING abandoned ticket $name in ${queue.path} '
        '(pid $holder alive but the ticket is ${age.inSeconds}s old, past the '
        '${holdBound.inSeconds}s hold bound no live test reaches)',
      );
      _deleteQuietly(File(p.join(queue.path, name)));
      continue;
    }
    ahead.add(name);
  }
  return ahead;
}

int? _stampOf(String name) => int.tryParse(name.split('-').first);

int? _pidOf(String name) {
  final parts = name.split('-');
  return parts.length < 3 ? null : int.tryParse(parts[1]);
}

void _deleteQuietly(File file) {
  try {
    file.deleteSync();
  } on Object {
    // Already gone — a peer pruned it, or it was never created.
  }
}

/// SIGWINCH is a harmless liveness probe (the same probe the live test's
/// fence uses).
bool _pidAlive(int candidate) =>
    Process.killPid(candidate, ProcessSignal.sigwinch);
