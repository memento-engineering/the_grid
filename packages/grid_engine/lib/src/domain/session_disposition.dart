/// The DISPOSITION of a work bead's joined session (I-10, tg-4rw) — the pure
/// answer to "what does this session bead MEAN for this work?", read by BOTH
/// ends of the mount decision: `WorkList` (does the bead mount?) and
/// `SessionScope` (adopt, or mint?).
///
/// A40's positive-terminal-only unmount reads EVERY closed session as "the work
/// is done". Three different things close a session, and only two of them mean
/// that:
///
/// - the engine closed it at a **positive terminal** — blocking is correct AND
///   load-bearing: the work source is read-only (A37), so a landed bead stays
///   open + ready, and the closed session is the only latch that stops a
///   resident station re-driving finished work forever;
/// - the engine closed it on **breaker exhaustion** (`grid.escalation`) —
///   blocking is correct: a human owns it, and an auto re-mint would loop
///   escalate → close → re-mint → fail → escalate, spawning agents forever;
/// - somebody closed it **mid-flight**, with an in-flight cursor and no marker
///   (I-10, 2026-07-03: an operator-closed orphan session, cursor `state=running`)
///   — blocking is WRONG. A dead key blocked real work for 62 minutes, silently;
///   the operator's only recovery was a hand re-key + a station restart.
///
/// So a closed session is DISPOSITIONED, never blanket-blocking: it is `done`,
/// `held`, or a `voided` DEAD KEY — never adoptable AND never blocking. The
/// engine's own evidence for `done` is the durable `grid.outcome=complete` marker
/// its close path stamps (`sessionCompleteMetadata`); cursor shape alone cannot
/// carry it (a session closed BETWEEN steps has every WRITTEN node `complete`
/// while the circuit is nowhere near its terminal), and the mount boundary has no
/// circuit to ask. The cursor fallback exists only for LEGACY beads closed before
/// the marker shipped.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../sdk/allocation.dart';
import '../sdk/circuit.dart';
import 'session_projection.dart';

part 'session_disposition.freezed.dart';

/// What a work bead's joined session means — a freezed SEALED union, so every
/// consumer's dispatch is exhaustive (ADR-0001 Decision 1).
@freezed
sealed class SessionDisposition with _$SessionDisposition {
  /// No session bead joins this work bead (or the projection names none) — the
  /// first round: MINT.
  const factory SessionDisposition.none() = NoSession;

  /// An OPEN session — the live round: ADOPT it (never a second mint).
  const factory SessionDisposition.live() = LiveSession;

  /// CLOSED at a positive terminal — the work is DONE. Never re-mount, never
  /// re-mint: this is the latch that keeps landed work from being re-driven.
  const factory SessionDisposition.done() = DoneSession;

  /// CLOSED carrying a HUMAN marker (escalation / declined rework) — a human owns
  /// this round. Never re-mount, never re-mint; say WHY once, LOUD.
  const factory SessionDisposition.held({required String reason}) = HeldSession;

  /// CLOSED mid-flight, no human marker, the cursor not a positive terminal — a
  /// DEAD KEY: never adoptable AND never blocking. The bead mounts; the scope
  /// retires the dead key and mints a fresh round, LOUD.
  const factory SessionDisposition.voided({required String reason}) =
      VoidedSession;

  const SessionDisposition._();

  /// Whether this session BLOCKS its work bead from mounting — the single
  /// predicate `WorkList` gates on (exhaustive: a new arm is a compile error,
  /// never a silently-mounting default).
  bool get blocksMount => switch (this) {
    DoneSession() || HeldSession() => true,
    NoSession() || LiveSession() || VoidedSession() => false,
  };
}

/// Dispositions [session] — pure, total, no I/O and no circuit (the mount
/// boundary has neither). Order matters: a human marker outranks everything, the
/// engine's own DONE evidence outranks the cursor, and only then does an
/// in-flight cursor void the key.
SessionDisposition sessionDispositionOf(SessionProjection? session) {
  if (session == null) return const SessionDisposition.none();
  if (!session.isTerminal) {
    // A projection that names no session bead has nothing to adopt (a synthetic
    // row) — mint, exactly as the pre-I-10 adopt guard did (`session_scope.dart`
    // initState: `existing != null && existing.isNotEmpty`).
    final id = session.sessionId ?? '';
    return id.isEmpty
        ? const SessionDisposition.none()
        : const SessionDisposition.live();
  }
  if (session.humanHeld) {
    return const SessionDisposition.held(
      reason:
          'closed carrying a human marker (escalation / declined rework) — a '
          'human owns this round; the grid never re-drives it',
    );
  }
  if (session.completed) return const SessionDisposition.done();
  final inFlight = <String>[
    for (final entry in session.cursor.entries)
      if (!entry.value.isPositiveTerminal)
        '${entry.key}=${entry.value.state.name}',
  ]..sort();
  // LEGACY (pre-`grid.outcome`): a non-empty cursor whose every node reached a
  // positive terminal is a finished round. An EMPTY cursor is NOT — nothing ever
  // ran, so there is nothing to preserve.
  if (session.cursor.isNotEmpty && inFlight.isEmpty) {
    return const SessionDisposition.done();
  }
  return SessionDisposition.voided(
    reason: inFlight.isEmpty
        ? 'closed with an EMPTY cursor — no step ever ran'
        : 'closed with ${inFlight.length} node(s) still in flight: '
              '${inFlight.join(', ')}',
  );
}

/// The process fences a VOIDED [session] still records — every `running`/`ready`
/// node's `pgid`+`pid`+`token`, deduped by pgid, falling back to the legacy
/// scalar session fence when no per-node target exists. What the re-mint must
/// prove DEAD before it spawns again (fail-closed: never double-run a survivor).
///
/// Deliberately parallel to `RestartReconciler`'s live-group scan, not shared
/// with it: the reconciler needs each group's `nodePath` + `NodeCursor` to hand
/// the composer's adopt proof, while the mint decision needs only the identity
/// triple. Same rule, two shapes.
List<AdoptFence> staleFences(SessionProjection session) {
  final fences = <AdoptFence>[];
  final seen = <int>{};
  session.cursor.forEach((_, node) {
    final live =
        node.state == StepState.running || node.state == StepState.ready;
    final pgid = node.pgid;
    final pid = node.pid;
    if (live && pgid != null && pid != null && seen.add(pgid)) {
      fences.add(AdoptFence(pgid: pgid, pid: pid, token: node.token));
    }
  });
  if (fences.isEmpty) {
    final pgid = session.pgid;
    final pid = session.pid;
    if (pgid != null && pid != null) {
      fences.add(AdoptFence(pgid: pgid, pid: pid, token: session.token));
    }
  }
  return fences;
}
