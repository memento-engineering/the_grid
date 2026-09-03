import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart' show GridIssueTypes;

/// `grid watch --until` exit code: the armed predicate held.
const int kWatchUntilSatisfied = 0;

/// `grid watch --until` exit code: [WatchUntil.timeout] expired first.
///
/// Distinct from [kWatchUntilSatisfied] on purpose — a caller must be able to
/// tell "the condition happened" from "I gave up" without parsing prose.
const int kWatchUntilTimedOut = 2;

/// `grid watch --until` exit code: the event stream broke its own ordering
/// contract (a ready delta before the baseline). `EX_SOFTWARE`.
const int kWatchUntilBrokenStream = 70;

/// The gate-bead metadata key naming the session an open gate blocks.
///
/// A bare literal at every other reader too (`StationBeadWriter.createGate`,
/// `StationJoinBridge._attachGateState`, `StationCommandHandler._rework`) —
/// there is no shared constant to import, and minting one would have to be
/// threaded through three packages, so this reader matches the house shape.
const String kGateBlocksKey = 'blocks';

/// The CLOSED set of `--until` literals, in help order.
const List<String> kWatchPredicateLiterals = <String>[
  'gate-open',
  'gate-closed',
  'session-terminal',
  'bead-status=<status>',
  'ready-count=0',
];

/// One terminating condition an operator arms with `grid watch --until`.
///
/// A CLOSED set of five named predicates — deliberately not an expression
/// language. Each is resolvable from the [GraphEvent]s `grid watch` already
/// decodes (ADR-0001 Decision 5's sealed set), and each is a TRANSITION: it
/// answers "did this happen while I was watching", not "is this true now".
sealed class WatchPredicate {
  /// Const base so every variant is a compile-time value.
  const WatchPredicate();

  /// The exact literal an operator passes to `--until`.
  String get literal;
}

/// A `type=gate` bead BECAME open, in the sense the park-predicate decision
/// fixes: an open `type=gate` bead whose `blocks` metadata names a session.
final class UntilGateOpen extends WatchPredicate {
  /// Creates the gate-open predicate.
  const UntilGateOpen();

  @override
  String get literal => 'gate-open';
}

/// An open gate CEASED to be open — closed, or hard-deleted out of existence.
final class UntilGateClosed extends WatchPredicate {
  /// Creates the gate-closed predicate.
  const UntilGateClosed();

  @override
  String get literal => 'gate-closed';
}

/// A `type=session` bead reached its terminal (closed) state.
final class UntilSessionTerminal extends WatchPredicate {
  /// Creates the session-terminal predicate.
  const UntilSessionTerminal();

  @override
  String get literal => 'session-terminal';
}

/// Some bead REACHED [status].
final class UntilBeadStatus extends WatchPredicate {
  /// Creates the bead-status predicate for [status].
  const UntilBeadStatus(this.status);

  /// The status a bead must reach for this predicate to hold.
  final BeadStatus status;

  @override
  String get literal => 'bead-status=${status.wire}';
}

/// The ready set emptied.
final class UntilReadyCountZero extends WatchPredicate {
  /// Creates the ready-count-zero predicate.
  const UntilReadyCountZero();

  @override
  String get literal => 'ready-count=0';
}

/// A LOUD refusal of an illegal `--until`/`--timeout`/`--for-seconds`
/// combination, or of a literal outside the closed set. Carries the exact
/// operator message `grid watch` prints before exiting 64.
class WatchUntilRefusal implements Exception {
  /// Creates a refusal carrying [message].
  const WatchUntilRefusal(this.message);

  /// The operator-facing reason.
  final String message;

  @override
  String toString() => 'WatchUntilRefusal: $message';
}

/// Parses a `--until` [literal] into its predicate.
///
/// Throws [WatchUntilRefusal] (LOUD; never a null return) for anything outside
/// the closed set. The guard is load-bearing rather than decorative: an
/// unparsed typo would run the watch to its deadline and exit
/// [kWatchUntilTimedOut], which is precisely the "I gave up" answer the exit
/// contract exists to distinguish from a real one.
WatchPredicate parseWatchPredicate(String literal) => switch (literal) {
  'gate-open' => const UntilGateOpen(),
  'gate-closed' => const UntilGateClosed(),
  'session-terminal' => const UntilSessionTerminal(),
  'ready-count=0' => const UntilReadyCountZero(),
  _ =>
    literal.startsWith('bead-status=')
        ? _parseBeadStatus(literal.substring('bead-status='.length))
        : throw WatchUntilRefusal(
            'unknown --until predicate "$literal". The set is CLOSED: '
            '${kWatchPredicateLiterals.join(', ')}.',
          ),
};

WatchPredicate _parseBeadStatus(String wire) {
  final status = BeadStatus(wire);
  if (!status.isBuiltIn) {
    throw WatchUntilRefusal(
      '--until bead-status="$wire" names no built-in bead status. The seven '
      'are: ${BeadStatus.builtIns.map((s) => s.wire).join(', ')}. A custom '
      'workspace status still DECODES fine on the read path (BeadStatus is an '
      'open extension type) — it is refused HERE so an operator typo cannot '
      'masquerade as a timeout.',
    );
  }
  return UntilBeadStatus(status);
}

/// The validated `--until` arming: the predicate plus the deadline bounding it.
class WatchUntil {
  /// Creates an arming from [predicate] and [timeout].
  const WatchUntil({required this.predicate, required this.timeout});

  /// The condition that ends the watch.
  final WatchPredicate predicate;

  /// The bound after which the watch gives up with [kWatchUntilTimedOut].
  final Duration timeout;
}

/// Validates `grid watch`'s three duration/termination flags as ONE unit.
///
/// Returns null when `--until` was not passed — that is how the verb's
/// pre-existing modes (block until Ctrl-C, or `--for-seconds N`) stay exactly
/// as they were. Throws [WatchUntilRefusal] for every illegal combination:
/// the flags are a mode selector, and a half-armed selector would silently
/// pick a mode the operator did not ask for.
WatchUntil? armWatchUntil({
  String? until,
  String? timeout,
  String? forSeconds,
}) {
  if (until == null) {
    if (timeout != null) {
      throw const WatchUntilRefusal(
        '--timeout only bounds --until, and --until was not passed. Pass '
        '--until <predicate> too, or drop --timeout (--for-seconds N runs for '
        'a fixed span and always exits 0).',
      );
    }
    return null;
  }
  if (forSeconds != null) {
    throw const WatchUntilRefusal(
      '--until and --for-seconds are mutually exclusive: --for-seconds runs a '
      'fixed span and always exits 0, --until blocks on a condition and exits '
      '2 when it does not hold in time. Pass exactly one.',
    );
  }
  if (timeout == null) {
    throw const WatchUntilRefusal(
      '--until requires --timeout <seconds>. An unbounded --until would block '
      'the operator seat forever, and the timeout exit code (2) is what tells '
      '"condition met" from "gave up".',
    );
  }
  final seconds = int.tryParse(timeout);
  if (seconds == null || seconds <= 0) {
    throw WatchUntilRefusal(
      '--timeout must be a positive whole number of seconds — got "$timeout".',
    );
  }
  return WatchUntil(
    predicate: parseWatchPredicate(until),
    timeout: Duration(seconds: seconds),
  );
}

/// Folds the typed event stream into the single question `--until` asks: has
/// the armed predicate held YET?
///
/// STATEFUL by necessity — [UntilReadyCountZero] is a fold of the baseline
/// ready count plus every subsequent delta — so ONE evaluator serves exactly
/// ONE watch, and [accepts] is called once per event, in arrival order.
class PredicateEvaluator {
  /// Creates an evaluator for [predicate].
  PredicateEvaluator(this.predicate);

  /// The armed condition.
  final WatchPredicate predicate;

  /// The running ready count, seeded by the baseline `SnapshotInitialized`.
  /// Null until that baseline arrives.
  int? _readyCount;

  /// Whether [event] satisfies [predicate].
  bool accepts(GraphEvent event) => switch (predicate) {
    UntilGateOpen() => _gateOpened(event),
    UntilGateClosed() => _gateStoppedBeingOpen(event),
    UntilSessionTerminal() => _sessionReachedTerminal(event),
    UntilBeadStatus(:final status) => _statusReached(event, status),
    UntilReadyCountZero() => _readyCountReachedZero(event),
  };

  /// The park-predicate shape, quantified existentially over sessions instead
  /// of naming one: an OPEN `type=gate` bead whose `blocks` metadata NAMES a
  /// session. Never cursor state, never a boolean flag.
  static bool _isOpenGate(Bead bead) {
    if (bead.issueType != GridIssueTypes.gate || bead.isClosed) return false;
    final blocks = bead.metadata[kGateBlocksKey];
    return blocks is String && blocks.isNotEmpty;
  }

  static bool _gateOpened(GraphEvent event) => switch (event) {
    BeadCreated(:final bead) => _isOpenGate(bead),
    BeadReopened(:final after) => _isOpenGate(after),
    // The mint is `bd create -t gate` carrying NO metadata, then a merge
    // `bd update --set-metadata blocks=… node=…`, so the `blocks` stamp
    // routinely lands on a SECOND event. Fire only on the EDGE into the open
    // shape, so a later unrelated field change on an already-open gate cannot
    // re-fire it.
    BeadUpdated(:final before, :final after) =>
      _isOpenGate(after) && !_isOpenGate(before),
    BeadClosed() ||
    BeadDeleted() ||
    SnapshotInitialized() ||
    DependencyAdded() ||
    DependencyRemoved() ||
    ReadySetChanged() => false,
  };

  static bool _gateStoppedBeingOpen(GraphEvent event) => switch (event) {
    // `diffSnapshots` emits BeadClosed only on a real !closed→closed edge, so
    // `before` being an open gate IS the transition.
    BeadClosed(:final before) => _isOpenGate(before),
    // A hard `bd delete` ends the gate's EXISTENCE, and existence is what the
    // park decision makes the evidence — so deletion ends the park too.
    BeadDeleted(:final bead) => _isOpenGate(bead),
    BeadCreated() ||
    BeadUpdated() ||
    BeadReopened() ||
    SnapshotInitialized() ||
    DependencyAdded() ||
    DependencyRemoved() ||
    ReadySetChanged() => false,
  };

  /// A session reaches terminal by being CLOSED. Which disposition that close
  /// carries (done | held | voided) is a separate read the operator makes
  /// AFTER this returns, so the predicate is deliberately
  /// disposition-agnostic.
  static bool _sessionReachedTerminal(GraphEvent event) => switch (event) {
    BeadClosed(:final after) => after.issueType == GridIssueTypes.session,
    BeadCreated() ||
    BeadUpdated() ||
    BeadReopened() ||
    BeadDeleted() ||
    SnapshotInitialized() ||
    DependencyAdded() ||
    DependencyRemoved() ||
    ReadySetChanged() => false,
  };

  /// Any bead REACHING [target] — the resulting bead carries it and the prior
  /// state did not. Unscoped by bead id on purpose: `bead-status=<status>` is
  /// the whole literal the closed set defines.
  static bool _statusReached(GraphEvent event, BeadStatus target) =>
      switch (event) {
        BeadCreated(:final bead) => bead.status == target,
        BeadUpdated(:final before, :final after) =>
          after.status == target && before.status != target,
        BeadClosed(:final before, :final after) =>
          after.status == target && before.status != target,
        BeadReopened(:final before, :final after) =>
          after.status == target && before.status != target,
        BeadDeleted() ||
        SnapshotInitialized() ||
        DependencyAdded() ||
        DependencyRemoved() ||
        ReadySetChanged() => false,
      };

  bool _readyCountReachedZero(GraphEvent event) {
    switch (event) {
      case SnapshotInitialized(:final readyCount):
        _readyCount = readyCount;
        return readyCount == 0;
      case ReadySetChanged(:final entered, :final exited):
        final baseline = _readyCount;
        if (baseline == null) {
          throw StateError(
            '--until ready-count=0: a ReadySetChanged arrived before the '
            'baseline SnapshotInitialized, so there is no count to fold. '
            'diffSnapshots emits the baseline first by contract (a null '
            '`before` yields exactly one SnapshotInitialized); this stream '
            'did not.',
          );
        }
        final next = baseline - exited.length + entered.length;
        _readyCount = next;
        return next == 0;
      case BeadCreated():
      case BeadUpdated():
      case BeadClosed():
      case BeadReopened():
      case BeadDeleted():
      case DependencyAdded():
      case DependencyRemoved():
        return false;
    }
  }
}

/// Watches [events] for the first event satisfying [evaluator], rendering
/// EVERY event through [render] as it arrives — so the satisfying event is the
/// LAST line written, and a caller reading `--json` learns the reason from the
/// same NDJSON stream it was already parsing.
///
/// Subscribes SYNCHRONOUSLY (before the first suspension), so a caller may arm
/// this ahead of `GridControllerRuntime.start()` and still see the baseline
/// `SnapshotInitialized` — the only ready count the stream carries.
///
/// Completes with [kWatchUntilSatisfied] when the predicate holds, or with
/// [kWatchUntilTimedOut] when [timeout] expires first. Completes with the
/// [StateError] [PredicateEvaluator.accepts] raises when the stream breaks its
/// own ordering contract; the caller maps that to [kWatchUntilBrokenStream].
Future<int> awaitPredicate({
  required Stream<GraphEvent> events,
  required PredicateEvaluator evaluator,
  required Duration timeout,
  required void Function(GraphEvent event) render,
}) {
  final done = Completer<int>();
  final timer = Timer(timeout, () {
    if (!done.isCompleted) done.complete(kWatchUntilTimedOut);
  });
  final subscription = events.listen((event) {
    if (done.isCompleted) return;
    render(event);
    final bool satisfied;
    try {
      satisfied = evaluator.accepts(event);
    } on StateError catch (error) {
      done.completeError(error);
      return;
    }
    if (satisfied) done.complete(kWatchUntilSatisfied);
  });
  return done.future.whenComplete(() async {
    timer.cancel();
    await subscription.cancel();
  });
}
