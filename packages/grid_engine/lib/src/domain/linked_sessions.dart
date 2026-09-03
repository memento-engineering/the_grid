/// The rule for a work bead's MANY linked session rows (tg-83k1).
///
/// The join publishes ONE [SessionProjection] per `work_bead` key, and A48 left
/// the multi-row pick as last-writer-wins on the premise that the void retire
/// preserves the single-key invariant. It preserves it only for rows the retire
/// itself created: twin mints and hand-closed rounds accumulate outside it, and
/// then a `done` twin can outrank a `voided` one and strand a ready bead
/// forever, silently.
///
/// This file authors the ONE ordering and the ONE verdict both the join bridge
/// and the mount boundary read, so the frontier and `grid rework` can never
/// disagree about which row is current.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'session_disposition.dart';
import 'session_projection.dart';

part 'linked_sessions.freezed.dart';

/// Orders [linked] so `.first` is the row the join publishes.
///
/// An OPEN row outranks every terminal one (never abandon a running agent); a
/// BLOCKING terminal (`done` / `held`) outranks a `voided` dead key (landed work
/// and human-held rounds win over a re-mint candidate); within one rank the
/// NEWEST row wins.
///
/// Total and deterministic: `closedAt`, then `startedAt` (a null instant sorts
/// oldest), then the session id descending — so a projection carrying no
/// timestamps at all still orders identically on every rebuild.
List<SessionProjection> orderLinkedSessions(
  Iterable<SessionProjection> linked,
) {
  final rows = linked.toList();
  rows.sort((a, b) {
    final byRank = _rankOf(a).compareTo(_rankOf(b));
    if (byRank != 0) return byRank;
    final byClosed = _newestFirst(a.closedAt, b.closedAt);
    if (byClosed != 0) return byClosed;
    final byStarted = _newestFirst(a.startedAt, b.startedAt);
    if (byStarted != 0) return byStarted;
    return (b.sessionId ?? '').compareTo(a.sessionId ?? '');
  });
  return List<SessionProjection>.unmodifiable(rows);
}

int _rankOf(SessionProjection row) {
  final disposition = sessionDispositionOf(row);
  if (!row.isTerminal && disposition is! PausedSession) return 0;
  return disposition.blocksMount ? 1 : 2;
}

int _newestFirst(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

/// What a work bead's linked session rows MEAN for the mount boundary — a
/// freezed SEALED union, so every consumer's dispatch is exhaustive (ADR-0001
/// Decision 1's house style).
@freezed
sealed class LinkedSessionVerdict with _$LinkedSessionVerdict {
  /// No session row links this work bead — MINT the first round.
  const factory LinkedSessionVerdict.none() = NoLinkedSession;

  /// An OPEN row is present — ADOPT it. [rivals] are the OTHER open rows: a
  /// genuine twin mint with two live agents, which the engine never
  /// auto-resolves (demoting one would hide a running process). Reported LOUD
  /// and left for a human.
  const factory LinkedSessionVerdict.adopt({
    required SessionProjection session,
    required List<SessionProjection> rivals,
  }) = AdoptLinkedSession;

  /// The published row BLOCKS (A48 `done` / `held`, or an operator-paused open
  /// session). Nothing is demoted and nothing is minted: landed work must not
  /// re-run, an escalation must not loop, and a park must preserve its cursor.
  const factory LinkedSessionVerdict.blocked({
    required SessionProjection session,
  }) = BlockedLinkedSession;

  /// Every linked row is a terminal, NON-BLOCKING dead key — RE-MINT.
  /// [session] is the published one; it rides down to `SessionScope`, which
  /// owns the retire and its fail-closed liveness fence. [surplus] are the
  /// older rows the frontier demotes so the join goes single-valued again.
  const factory LinkedSessionVerdict.remint({
    required SessionProjection session,
    required List<SessionProjection> surplus,
  }) = RemintLinkedSession;

  const LinkedSessionVerdict._();

  /// The row the join publishes for this work bead — null only for
  /// [NoLinkedSession].
  SessionProjection? get winner => switch (this) {
    NoLinkedSession() => null,
    AdoptLinkedSession(:final session) => session,
    BlockedLinkedSession(:final session) => session,
    RemintLinkedSession(:final session) => session,
  };
}

/// The verdict for [linked] — pure, total, no I/O and no circuit. Orders
/// internally, so a caller may pass rows in any order.
LinkedSessionVerdict linkedSessionVerdictOf(
  Iterable<SessionProjection> linked,
) {
  final ordered = orderLinkedSessions(linked);
  if (ordered.isEmpty) return const LinkedSessionVerdict.none();
  final winner = ordered.first;
  final rest = ordered.skip(1).toList(growable: false);
  final disposition = sessionDispositionOf(winner);
  if (!winner.isTerminal && disposition is! PausedSession) {
    return LinkedSessionVerdict.adopt(
      session: winner,
      rivals: rest.where((row) => !row.isTerminal).toList(growable: false),
    );
  }
  if (disposition.blocksMount) {
    return LinkedSessionVerdict.blocked(session: winner);
  }
  // The ordering puts every blocking terminal ahead of every voided one, so a
  // NON-BLOCKING winner proves every remaining row is a dead key too.
  return LinkedSessionVerdict.remint(session: winner, surplus: rest);
}
