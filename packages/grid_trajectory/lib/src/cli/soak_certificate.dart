/// The §W2.5 SOAK CERTIFICATE — pure, I/O-free, over decoded rows.
///
/// `docs/design/trajectory/cut-wiring.md` §W2.5 states the certificate as a
/// table a human reads off "the LAST round-summary note of each boot whose
/// `passes > 1`". A runbook with no oracle is why no soak has ever been
/// certified, so the machine-checkable half of that table is folded HERE and
/// turned into PASS/FAIL rows; `traj certify` only reads the log and prints
/// what this file decides.
///
/// Four rules carry the honesty of the result, each one a shape §W2.5 warns
/// about by name:
///
///   * **THE GOVERNING NOTE IS THE LAST `passes > 1` NOTE** — a `passes: 1`
///     row is the boot walk, written before the comparator has counted
///     anything, and summing the notes double-counts the cumulative counters.
///     A boot with no such note certifies NOTHING; it does not certify clean.
///   * **AN ABSENT COUNTER IS NOT A ZERO** — a boot whose summary predates the
///     §W2.5 instrument carries no `miss_post_epoch_total`, and reading that
///     as 0 is exactly the unearned green the doc's read-rule correction was
///     written to kill. Absence FAILS the row it gates.
///   * **THE CUMULATIVE TWINS GATE, THE GAUGES ARE REPORTED** — `miss_post_epoch`
///     and `p2_miss` are per-pass gauges zeroed on every join emission, so a
///     boot in which fifty post-epoch sessions fell back certifies clean if the
///     last pass happens to be quiet. Only the deduped cumulative twins gate.
///   * **EVERY TABLE ROW WITH A GATE VALUE GATES** — the two STRUCTURAL ZEROS
///     (`null_started_at = 0` and a non-null `first_epoch_claimed_at`) are not
///     reportable beside the gate: `classifyDualReadMiss` returns `legacyEra`
///     for EVERY miss when the epoch anchor is null, so a boot without it
///     prints `miss_post_epoch_total 0` that it never earned. The scoped lag
///     and cardinality twins, the three append-loss counters ("a lossy boot
///     certifies nothing") and an empty `health_transitions` gate for the same
///     reason: a row demoted to REPORTED is a row that cannot fail, and a
///     certificate whose signal cannot fail is a runbook with extra steps.
///   * **ONLY A ROUND-SCOPE NOTE IS A ROUND** — a boot emits one BOOT-FINAL
///     summary at the clean-down fixpoint, carrying the whole boot's
///     cumulative pass count and riding the sessionId of the boot's LAST
///     terminal session (lunar epoch 72's read `passes 150`). Counted as a
///     round it scores that one seat again off a note that summarises every
///     round of the boot, so `shape-coverage` counts ONLY round-scope notes
///     (RULING 2026-09-13, governor, wave A verify). That same boot-final
///     note still GOVERNS `posture` and `clean`: it is the last `passes > 1`
///     note and it carries the cumulative twins.
///
/// One row does NOT track the doc: `shape-coverage` here is tg-2gt1's
/// redefinition — one round with `passes > 1` per ruling seat — and §W2.5's
/// own EVENT checklist (a rework, a void, an escalation or decline, a
/// gate-park + re-arm, a deliberate bounce) rides [kCertificateHumanItems]
/// unclaimed, because nothing in the trajectory log decides "deliberate".
///
/// Leaf discipline (decision `the_grid#grid-trajectory-leaf-package`): the note
/// channel and the counter keys are RE-EXPRESSED here, never imported from
/// `grid_engine`, exactly as `committee_report.dart` re-expresses the step
/// result keys.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import '../codec/codec_registry.dart';
import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';

/// The `attempt.note` channel the durable round summaries ride (§0.4).
const String kRoundSummaryNoteChannel = 'dual-read-round-summary';

/// §0.4's PER-ROUND summary scope — the ONLY note `shape-coverage` counts.
///
/// `_emitTerminalSummaries` (`grid_engine`, `dual_read_pass.dart`) writes one
/// note at every session TERMINAL: one round, one note. The RULING
/// (2026-09-13, governor, wave A verify) names that scope `round`; §0.4's
/// producer spells it `session-terminal` and spells the other one
/// [kBootFinalSummaryScope]. The ruling's operative clause is "never the
/// BOOT-FINAL note", and NOTHING in the tree emits the literal `round`, so
/// gating on that string would score zero rounds on every real boot and fail
/// the row forever — the "soak is always a blocker" shape this verb exists to
/// kill. The constant is therefore stated against the producer; if an emitter
/// ever does write `round`, this is the one line that moves.
const String kRoundSummaryScope = 'session-terminal';

/// §0.4's BOOT-FINAL summary scope — one note at the clean-down fixpoint,
/// riding the sessionId of the boot's LAST terminal session and carrying the
/// WHOLE boot's cumulative counters (`dual_read_pass.dart`, `finish`).
///
/// It GOVERNS `posture` and `clean` and is never a round.
const String kBootFinalSummaryScope = 'boot-final';

/// The seats Q1 scoped the soak to (`wave-2-flip-scope-soak-and-kill-date`).
///
/// A target is matched against the record's `substation` either exactly or as
/// its leading segment, so the ruling's `butane` covers the roster's
/// `butane_flutter` without the ruling having to spell a repo name.
const Set<String> kSoakTargetSeats = {'lenny', 'butane'};

/// The counters the `clean` row GATES, in print order.
///
/// Every §W2.5 table row that carries a GATE VALUE and is a scalar in the
/// round summary is here:
///
///   * the two cut-signal twins (`miss_post_epoch_total`, `p2_miss_total`) —
///     "replaces `fallbacks = 0`";
///   * `null_started_at` — a STRUCTURAL ZERO: a null `startedAt` classifies a
///     post-epoch miss as legacy-era, so one of these makes the cut signal
///     above smaller than the boot earned;
///   * the two in-window unexplained-divergence twins, one per axis;
///   * the scoped cardinality and lag rows — in-window on purpose (epoch 50
///     measured `retirement_lag_open 63` on legacy shapes that will never
///     heal, so the UNSCOPED rows are unreachable and would make the
///     certificate unissuable);
///   * the three append-loss counters — §W2.5's "a lossy boot certifies
///     nothing".
///
/// The two NON-scalar gate values gate too, in the rows that own them:
/// `first_epoch_claimed_at` (must not be null) below in `clean`, and
/// `health_transitions` (must be empty) in `posture`, beside `health: live`.
const List<String> kCertificateGatingCounters = [
  'miss_post_epoch_total',
  'p2_miss_total',
  'null_started_at',
  'unexplained_divergences_in_window',
  'step_unexplained_divergences_in_window',
  'cardinality_breaches_in_window',
  'terminal_lag_open_in_window',
  'retirement_lag_open_in_window',
  'step_lag_open',
  'append_drops',
  'append_suppressed',
  'append_refused_testimony',
];

/// The counters printed BESIDE the gate — §W2.5's "reported, never gating"
/// list, plus the `historical` residue the doc reports next to each scoped
/// twin so an operator can see what the window excluded.
const List<String> kCertificateReportedCounters = [
  'soak_window_epoch',
  'miss_post_epoch',
  'p2_miss',
  'miss_legacy_era',
  'fallbacks',
  'p1_orphan',
  'unexplained_divergences_historical',
  'step_unexplained_divergences_historical',
  'cardinality_breaches_historical',
  'terminal_lag_open_historical',
  'retirement_lag_open_historical',
  'append_ack_p99_ms',
];

/// §W2.5's EPOCH ANCHOR (`clean`, structural): an unseeded snapshot classifies
/// EVERY miss legacy-era, so a boot without this timestamp prints a
/// `miss_post_epoch_total` of 0 that is zero BY CONSTRUCTION. The doc refuses
/// certification outright on it rather than reporting it beside the gate.
const String kEpochAnchorKey = 'first_epoch_claimed_at';

/// §W2.5's health row (`posture`): `live` at boot-final AND no latch during
/// the boot. A boot that degraded and recovered reads `live` at the end and
/// served something other than the fold in the middle, so the final reading
/// alone cannot carry the row.
///
/// The doc states the gate as "`health_transitions` empty"; the PRODUCER makes
/// that unreachable and the gate is stated against what it actually emits.
/// `_noteHealth` (`dual_read_pass.dart`) records the FIRST health it observes
/// as a bare state name and every later change as `<from>-><to>`, so a
/// perfectly healthy boot carries `['live']`, never `[]`. Gating on empty
/// would fail every boot forever — the "soak is always a blocker" shape this
/// verb exists to kill — so the gate is: every state NAMED anywhere in the
/// list is [kLiveHealth]. No edge, no non-live state, and a bare `live` is
/// the ordinary healthy reading rather than a transition.
const String kHealthTransitionsKey = 'health_transitions';

/// The one snapshot health a certified boot may ever have witnessed.
const String kLiveHealth = 'live';

/// The state names [kHealthTransitionsKey] entry [entry] mentions —
/// `live` for a bare first observation, both sides for a `<from>-><to>` edge.
List<String> healthStatesIn(String entry) => entry.split('->');

/// W2-B's observe-form counter (§W2.5's last table row). Absent from every
/// summary until W2-B lands, which is why its row is informational until it
/// appears.
const String kWouldRefuseCounter = 'barrier_would_refuse';

/// The certificate items this verb CANNOT check — printed with their state
/// unknown so a reader is never told the verb claimed them.
///
/// The first four are the human half of `lunar_station-bzt`'s evidence pack;
/// the fifth is machine-checkable but not from the trajectory database alone —
/// `traj shadow-diff` needs the legacy ledger beside it. The last two are
/// §W2.5 table rows this verb deliberately does not claim: the doc's EVENT
/// shape checklist (the `shape-coverage` ROW measures tg-2gt1's seat
/// redefinition instead) and the per-field in-window divergence row.
const List<String> kCertificateHumanItems = [
  'break-glass drill on a scratch grid home (boot cut with a cut-era session '
      'open, break-glass in, verify the void and every stamp)',
  'restore drill on a scratch grid home (the quiesced void-and-redrive '
      'runbook end to end, zero re-drive of completed work)',
  'one `traj show` lifecycle sample read by the operator',
  'the Q5/Q10 `gated`-and-`ready` amendment and the Q6 '
      'inferred-versus-reconstructed amendment, both RULED',
  '`traj shadow-diff` per counted boot — `lost_append` and in-window '
      '`unexplained` both 0 (offline: needs the legacy ledger, so this verb '
      'never runs it)',
  'the §W2.5 EVENT shape checklist across the counted boots — at least one '
      'rework, one void, one escalation or decline, one gate-park + re-arm '
      'cycle, and one deliberate bounce (NOT the `shape-coverage` row above, '
      'which is tg-2gt1\'s seat redefinition: one round-scope summary with '
      'passes > 1 per ruling seat; nothing in the log decides "deliberate")',
  'the §W2.5 per-field in-window divergence row (`isTerminal`, `completed`, '
      '`humanHeld`, `closedAt`, `disposition`, `fences`) — the gate above '
      'reads the `unexplained` twin, which carves out the adjudicated classes '
      'the table\'s own incumbent rule excepts, so the raw per-field map is '
      'neither gated nor read here',
];

/// PASS, FAIL, or — for the items the verb refuses to claim — UNKNOWN.
enum CertificateStatus {
  pass('PASS'),
  fail('FAIL'),
  unknown('UNKNOWN');

  const CertificateStatus(this.wire);

  /// The word printed in the row and carried in `--json`.
  final String wire;
}

/// The machine-checkable certificate items, in print order.
enum CertificateRow {
  posture('posture'),
  clean('clean'),
  shapeCoverage('shape-coverage'),
  wouldRefuse('would-refuse'),
  consecutive('consecutive');

  const CertificateRow(this.wire);

  /// The row's name in the table and in `--json`.
  final String wire;
}

/// One decoded `dual-read-round-summary` note.
@immutable
class RoundSummaryNote {
  /// Creates a decoded note.
  const RoundSummaryNote({
    required this.seq,
    required this.sessionId,
    required this.body,
  });

  /// The trajectory `seq` the note was appended at — the ordering the
  /// "LAST note" rule uses, and the operator's cursor back into `traj show`.
  final int seq;

  final String sessionId;

  /// The note's decoded JSON body.
  final Map<String, Object?> body;

  /// [kRoundSummaryScope] or [kBootFinalSummaryScope] (§0.4), or null on a
  /// body that declared no scope.
  String? get scope => stringOf('scope');

  /// This note summarises ONE ROUND — the only shape `shape-coverage` counts
  /// (RULING 2026-09-13, governor, wave A verify).
  ///
  /// A [kBootFinalSummaryScope] note is not one, and neither is a note that
  /// declared no scope at all: an undeclared scope is not evidence of a
  /// round, exactly as an absent counter is not a zero.
  bool get isRoundScoped => scope == kRoundSummaryScope;

  /// The comparator's pass count — the read rule's discriminator.
  int get passes => intOf('passes') ?? 0;

  /// An integer counter, or null when the summary does not carry the key.
  /// Absence is never a zero here; the caller decides what it means.
  int? intOf(String key) => switch (body[key]) {
    final int value => value,
    final num value => value.toInt(),
    final String value => int.tryParse(value),
    _ => null,
  };

  bool? boolOf(String key) => switch (body[key]) {
    final bool value => value,
    _ => null,
  };

  String? stringOf(String key) => switch (body[key]) {
    final String value => value,
    _ => null,
  };

  /// A list-valued row (`health_transitions`), or null when the summary does
  /// not carry the key — absence is not an empty list, for the same reason an
  /// absent counter is not a zero.
  List<Object?>? listOf(String key) => switch (body[key]) {
    final List<Object?> value => value,
    _ => null,
  };
}

/// One counted boot's window, as the verb read it.
@immutable
class BootWindow {
  /// Creates a window over one claimed epoch.
  const BootWindow({
    required this.epoch,
    required this.station,
    required this.records,
    this.substationOf = const <String, String>{},
    this.truncated = false,
  });

  final int epoch;
  final String station;

  /// Every row the reader returned for this `boot_epoch`, `seq`-ordered.
  final List<TrajectoryEnvelope> records;

  /// Session → substation the CALLER resolved outside this window, with a
  /// second bounded read per session ([sessionsNeedingWiderRead]).
  ///
  /// It is not an optimisation. Round-summary notes carry no substation of
  /// their own (`ck_substation` demands one only when `work_bead_id` is set),
  /// so a session whose `attempt.session.started` landed in an EARLIER epoch
  /// is unattributable from this window alone — and a bounce mid-round is
  /// routine, so scoring seat coverage off the window would score it off a
  /// join artifact.
  final Map<String, String> substationOf;

  /// The read was CUT SHORT — the governing note may simply not be in hand,
  /// so nothing this window says can certify a boot.
  final bool truncated;

  /// The same window with [resolved] folded into [substationOf].
  BootWindow withSubstations(Map<String, String> resolved) => BootWindow(
    epoch: epoch,
    station: station,
    records: records,
    substationOf: <String, String>{...substationOf, ...resolved},
    truncated: truncated,
  );
}

/// What one counted boot proved.
@immutable
class BootEvidence {
  /// Creates the folded evidence for one boot.
  const BootEvidence({
    required this.epoch,
    required this.station,
    required this.recordsRead,
    required this.truncated,
    required this.summaries,
    required this.seatRounds,
    required this.offSeatRounds,
    required this.unjoinedRounds,
    required this.nonRoundNotes,
    this.governing,
  });

  final int epoch;
  final String station;
  final int recordsRead;
  final bool truncated;

  /// Round-summary notes seen in this epoch, whatever their pass count.
  final int summaries;

  /// The LAST note with `passes > 1` — the boot's governing evidence, and
  /// null when the boot never produced one.
  final RoundSummaryNote? governing;

  /// Rounds with `passes > 1` per target seat, keyed by the RULING's name.
  final Map<String, int> seatRounds;

  /// Rounds with `passes > 1` that WERE attributed to a substation — one the
  /// ruling did not scope the soak to. An ordinary fact about a busy station,
  /// never a join failure, and counted apart from one for exactly that reason.
  final int offSeatRounds;

  /// Rounds with `passes > 1` whose session NO record in the log attributed
  /// to a substation, in this window or outside it — the real join failure.
  final int unjoinedRounds;

  /// Summaries with `passes > 1` that `shape-coverage` did NOT count because
  /// they are not [RoundSummaryNote.isRoundScoped] — the boot-final note, and
  /// any note that declared no scope.
  ///
  /// Reported, never gating: the ruling excludes them from the count, and a
  /// reader who cannot see the exclusion is left wondering where a round
  /// went. [governing] is normally one of them.
  final int nonRoundNotes;

  /// The measured numbers, gating first, absent keys carried as null so a
  /// reader can tell "zero" from "never emitted".
  Map<String, Object?> get counters => <String, Object?>{
    for (final key in kCertificateGatingCounters) key: governing?.intOf(key),
    for (final key in kCertificateReportedCounters) key: governing?.intOf(key),
    kWouldRefuseCounter: governing?.intOf(kWouldRefuseCounter),
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'epoch': epoch,
    'station': station,
    'records_read': recordsRead,
    'truncated': truncated,
    'round_summaries': summaries,
    'governing_seq': governing?.seq,
    'governing_session_id': governing?.sessionId,
    'governing_scope': governing?.scope,
    'passes': governing?.passes,
    'mode': governing?.stringOf('mode'),
    'discipline': governing?.stringOf('discipline'),
    'health': governing?.stringOf('health'),
    kHealthTransitionsKey: governing?.listOf(kHealthTransitionsKey),
    'overlay_engaged': governing?.boolOf('overlay_engaged'),
    'overlay_disengaged_for_boot': governing?.boolOf(
      'overlay_disengaged_for_boot',
    ),
    'step_axis_engaged': governing?.boolOf('step_axis_engaged'),
    kEpochAnchorKey: governing?.stringOf(kEpochAnchorKey),
    'counters': counters,
    'seat_rounds': Map<String, int>.from(seatRounds),
    'off_seat_rounds': offSeatRounds,
    'unjoined_rounds': unjoinedRounds,
    'non_round_notes': nonRoundNotes,
  };
}

/// One PASS/FAIL row of the certificate.
@immutable
class CertificateItem {
  /// Creates a row.
  const CertificateItem({
    required this.row,
    required this.status,
    required this.detail,
    this.failures = const [],
  });

  final CertificateRow row;
  final CertificateStatus status;

  /// The one-line measured summary printed beside the verdict.
  final String detail;

  /// Every reason the row failed, each naming its epoch — a FAIL that does
  /// not say which boot broke it sends the operator back to the runbook.
  final List<String> failures;

  Map<String, Object?> toJson() => <String, Object?>{
    'row': row.wire,
    'status': status.wire,
    'detail': detail,
    'failures': failures,
  };
}

/// The whole certificate: the rows, the boots they were measured on, and the
/// items the verb refuses to claim.
@immutable
class SoakCertificate {
  /// Creates a certificate.
  const SoakCertificate({
    required this.requestedBoots,
    required this.claimedEpochs,
    required this.boots,
    required this.items,
    required this.seats,
    this.insufficient = false,
  });

  /// `--boots N`.
  final int requestedBoots;

  /// Every epoch the `traj_epoch` ledger holds, ascending.
  final List<int> claimedEpochs;

  /// The counted boots, oldest first. Empty when [insufficient].
  final List<BootEvidence> boots;

  /// The five machine-checkable rows, in [CertificateRow] order.
  final List<CertificateItem> items;

  /// The seats the shape-coverage row was scoped to.
  final List<String> seats;

  /// Fewer than [requestedBoots] boots exist — nothing was measured and the
  /// verb exits 3 rather than reporting rows it could not earn.
  final bool insufficient;

  /// Every row passed.
  bool get certified =>
      !insufficient &&
      items.every((item) => item.status == CertificateStatus.pass);

  /// 0 certified · 2 a row failed · 3 fewer than N boots exist.
  int get exitCode => insufficient ? 3 : (certified ? 0 : 2);

  Map<String, Object?> toJson() => <String, Object?>{
    'verb': 'traj certify',
    'boots_requested': requestedBoots,
    'boots_counted': boots.length,
    'claimed_epochs': claimedEpochs,
    'seats': seats,
    'insufficient': insufficient,
    'certified': certified,
    'exit_code': exitCode,
    'rows': [for (final item in items) item.toJson()],
    'boots': [for (final boot in boots) boot.toJson()],
    'checklist': [
      for (final item in kCertificateHumanItems)
        <String, Object?>{
          'item': item,
          'status': CertificateStatus.unknown.wire,
        },
    ],
  };
}

/// The epochs `--boots [count]` counts: the ledger's most recent [count]
/// claims, oldest first. Short of [count] claims it returns them all and the
/// caller reports the shortfall.
List<int> countedEpochs(List<int> claimed, int count) {
  final ordered = [...claimed]..sort();
  if (ordered.length <= count) return ordered;
  return ordered.sublist(ordered.length - count);
}

/// Session → substation as this window can see it: every attribution the
/// window's own records carry, then the ones the caller resolved outside it.
///
/// In-window first: a session's own epoch is the closest evidence, and the
/// wider read exists only to cover what the window cannot reach.
Map<String, String> substationsIn(BootWindow window) {
  final resolved = <String, String>{};
  for (final envelope in window.records) {
    final session = envelope.sessionId;
    final substation = envelope.substation;
    if (session == null || substation == null) continue;
    resolved.putIfAbsent(session, () => substation);
  }
  for (final entry in window.substationOf.entries) {
    resolved.putIfAbsent(entry.key, () => entry.value);
  }
  return resolved;
}

/// The sessions whose `passes > 1` round summaries this window cannot
/// attribute on its own — what the caller hands to a second bounded read
/// before folding, so a session mounted in an earlier epoch is scored on the
/// seat it actually ran on rather than as a join failure.
Set<String> sessionsNeedingWiderRead(BootWindow window) {
  final known = substationsIn(window);
  final pending = <String>{};
  for (final envelope in window.records) {
    final note = roundSummaryOf(envelope);
    if (note == null || note.passes <= 1) continue;
    // Only a round-scope note is counted (RULING 2026-09-13), so only a
    // round-scope note is worth a second read: attributing the boot-final
    // note would buy a seat nothing scores.
    if (!note.isRoundScoped) continue;
    if (known.containsKey(note.sessionId)) continue;
    pending.add(note.sessionId);
  }
  return pending;
}

/// Folds one boot's window into its evidence.
BootEvidence foldBootEvidence(
  BootWindow window, {
  Set<String> seats = kSoakTargetSeats,
}) {
  final substationOf = substationsIn(window);

  final notes = <RoundSummaryNote>[];
  for (final envelope in window.records) {
    final note = roundSummaryOf(envelope);
    if (note != null) notes.add(note);
  }
  notes.sort((left, right) => left.seq.compareTo(right.seq));

  RoundSummaryNote? governing;
  final seatRounds = <String, int>{for (final seat in seats) seat: 0};
  var offSeat = 0;
  var unjoined = 0;
  var nonRound = 0;
  for (final note in notes) {
    if (note.passes <= 1) continue;
    governing = note;
    // THE RULING (2026-09-13, governor, wave A verify): only a round-scope
    // note is a round. The boot-final note carries the boot's cumulative pass
    // count on the LAST terminal session's id, so counting it scores that one
    // seat again off a summary of every round in the boot. It still governs
    // above — the counters are exactly what it is for.
    if (!note.isRoundScoped) {
      nonRound++;
      continue;
    }
    final substation = substationOf[note.sessionId];
    if (substation == null) {
      unjoined++;
      continue;
    }
    final seat = seatFor(substation, seats);
    if (seat == null) {
      offSeat++;
    } else {
      seatRounds[seat] = (seatRounds[seat] ?? 0) + 1;
    }
  }

  return BootEvidence(
    epoch: window.epoch,
    station: window.station,
    recordsRead: window.records.length,
    truncated: window.truncated,
    summaries: notes.length,
    governing: governing,
    seatRounds: seatRounds,
    offSeatRounds: offSeat,
    unjoinedRounds: unjoined,
    nonRoundNotes: nonRound,
  );
}

/// The round summary [envelope] carries, or null when it is not one.
///
/// A body that is not a JSON object is not a summary: the note channel is
/// shared with hand-written journalling, and half-parsing one would invent
/// counters nobody wrote.
RoundSummaryNote? roundSummaryOf(TrajectoryEnvelope envelope) {
  final record = TrajectoryCodec.decode(envelope);
  if (record is! AttemptNote) return null;
  if (record.channel != kRoundSummaryNoteChannel) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(record.body);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  return RoundSummaryNote(
    seq: envelope.seq ?? 0,
    sessionId: record.sessionId,
    body: decoded.cast<String, Object?>(),
  );
}

/// The target seat [substation] belongs to, or null.
///
/// Exact match first, then the leading segment — the ruling says `butane` and
/// the roster says `butane_flutter`.
String? seatFor(String? substation, Set<String> seats) {
  if (substation == null) return null;
  for (final seat in seats) {
    if (substation == seat || substation.startsWith('${seat}_')) return seat;
  }
  return null;
}

/// Folds the certificate over the counted [windows].
///
/// [claimedEpochs] is the WHOLE `traj_epoch` ledger, ascending: the
/// `consecutive` row is about the ledger, not about the windows handed in.
SoakCertificate foldSoakCertificate({
  required int requestedBoots,
  required List<int> claimedEpochs,
  required List<BootWindow> windows,
  Set<String> seats = kSoakTargetSeats,
}) {
  final ledger = [...claimedEpochs]..sort();
  final seatList = seats.toList()..sort();
  if (ledger.length < requestedBoots) {
    return SoakCertificate(
      requestedBoots: requestedBoots,
      claimedEpochs: ledger,
      boots: const [],
      items: const [],
      seats: seatList,
      insufficient: true,
    );
  }
  final boots = [
    for (final window in windows) foldBootEvidence(window, seats: seats),
  ]..sort((left, right) => left.epoch.compareTo(right.epoch));

  final posture = _posture(boots);
  final clean = _clean(boots);
  final coverage = _shapeCoverage(boots, seatList);
  final wouldRefuse = _wouldRefuse(boots);
  final consecutive = _consecutive(boots, ledger, requestedBoots, [
    posture,
    clean,
    coverage,
    wouldRefuse,
  ]);
  return SoakCertificate(
    requestedBoots: requestedBoots,
    claimedEpochs: ledger,
    boots: boots,
    items: [posture, clean, coverage, wouldRefuse, consecutive],
    seats: seatList,
  );
}

CertificateItem _posture(List<BootEvidence> boots) {
  final failures = <String>[];
  for (final boot in boots) {
    final governing = boot.governing;
    if (governing == null) {
      failures.add(_noGoverningNote(boot));
      continue;
    }
    final mode = governing.stringOf('mode');
    if (mode != 'primary') {
      failures.add(
        'epoch ${boot.epoch}: mode ${mode ?? 'absent'}, not primary',
      );
    }
    // The cut is a SINGLE lever (ruling Q2): `discipline: cut` resolves the
    // dual read to `primary` and the config mode to `required`, and no emitter
    // stamps the discipline on the summary today. The served posture above is
    // therefore the observable; a summary that ever DOES carry the stamp is
    // held to it rather than ignored.
    final discipline = governing.stringOf('discipline');
    if (discipline != null && discipline != 'cut') {
      failures.add('epoch ${boot.epoch}: discipline $discipline, not cut');
    }
    if (governing.boolOf('overlay_engaged') != true) {
      failures.add(
        'epoch ${boot.epoch}: overlay_engaged is not true — the boot rode '
        'legacy and certifies nothing',
      );
    }
    if (governing.boolOf('overlay_disengaged_for_boot') == true) {
      failures.add('epoch ${boot.epoch}: the overlay disengaged for the boot');
    }
    final health = governing.stringOf('health');
    if (health != 'live') {
      failures.add(
        'epoch ${boot.epoch}: health ${health ?? 'absent'}, not live',
      );
    }
    // The SECOND half of §W2.5's health row: "`live` at boot-final;
    // `health_transitions` empty". A boot that latched degraded and recovered
    // reads `live` at the end and served something other than the fold in the
    // middle, so the final reading alone cannot carry the row.
    final transitions = governing.listOf(kHealthTransitionsKey);
    if (transitions == null) {
      failures.add(
        'epoch ${boot.epoch}: $kHealthTransitionsKey absent from the round '
        'summary — an absent row is not an unlatched one',
      );
    } else {
      final latched = <String>{};
      for (final entry in transitions) {
        final text = entry is String ? entry : '$entry';
        if (healthStatesIn(text).any((state) => state != kLiveHealth)) {
          latched.add(text);
        }
      }
      if (latched.isNotEmpty) {
        failures.add(
          'epoch ${boot.epoch}: $kHealthTransitionsKey ${latched.join(', ')} '
          '— the snapshot was not $kLiveHealth throughout the boot',
        );
      }
    }
  }
  return CertificateItem(
    row: CertificateRow.posture,
    status: failures.isEmpty ? CertificateStatus.pass : CertificateStatus.fail,
    detail: failures.isEmpty
        ? '${boots.length}/${boots.length} boots served mode=primary with the '
              'overlay engaged and health live throughout'
        : '${failures.length} posture failure'
              '${failures.length == 1 ? '' : 's'}',
    failures: failures,
  );
}

CertificateItem _clean(List<BootEvidence> boots) {
  final failures = <String>[];
  for (final boot in boots) {
    if (boot.truncated) {
      failures.add(
        'epoch ${boot.epoch}: the window read was truncated at '
        '${boot.recordsRead} records — a prefix certifies nothing',
      );
    }
    final governing = boot.governing;
    if (governing == null) {
      failures.add(_noGoverningNote(boot));
      continue;
    }
    // THE EPOCH ANCHOR FIRST — every counter below is unreadable without it.
    // `classifyDualReadMiss` returns `legacyEra` for EVERY miss when
    // `firstEpochClaimedAt` is null, so `miss_post_epoch_total` stays 0 for
    // the whole boot no matter what fell back. §W2.5 refuses certification
    // outright on this one; it is not a class to report beside the gate.
    final anchor = governing.stringOf(kEpochAnchorKey);
    if (anchor == null || anchor.isEmpty) {
      failures.add(
        'epoch ${boot.epoch}: $kEpochAnchorKey is null — an unseeded snapshot '
        'classifies every miss legacy-era, so the cut signal is 0 by '
        'construction and this boot certifies nothing',
      );
    }
    for (final key in kCertificateGatingCounters) {
      final value = governing.intOf(key);
      if (value == null) {
        failures.add(
          'epoch ${boot.epoch}: $key absent from the round summary — an '
          'absent counter is not a zero',
        );
      } else if (value != 0) {
        failures.add('epoch ${boot.epoch}: $key = $value');
      }
    }
  }
  return CertificateItem(
    row: CertificateRow.clean,
    status: failures.isEmpty ? CertificateStatus.pass : CertificateStatus.fail,
    detail: failures.isEmpty
        ? '${kCertificateGatingCounters.length} gating counters 0 on every '
              'counted boot (${kCertificateGatingCounters.join(', ')}), '
              '$kEpochAnchorKey set'
        : '${failures.length} clean failure'
              '${failures.length == 1 ? '' : 's'}',
    failures: failures,
  );
}

CertificateItem _shapeCoverage(List<BootEvidence> boots, List<String> seats) {
  final totals = <String, int>{for (final seat in seats) seat: 0};
  var offSeat = 0;
  var unjoined = 0;
  var nonRound = 0;
  for (final boot in boots) {
    for (final entry in boot.seatRounds.entries) {
      totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
    }
    offSeat += boot.offSeatRounds;
    unjoined += boot.unjoinedRounds;
    nonRound += boot.nonRoundNotes;
  }
  final failures = <String>[
    for (final seat in seats)
      if ((totals[seat] ?? 0) == 0)
        'seat $seat: no round-scope ($kRoundSummaryScope) summary with '
            'passes > 1 across the counted boots',
  ];
  final measured = [
    for (final seat in seats) '$seat ${totals[seat] ?? 0}',
  ].join(', ');
  return CertificateItem(
    row: CertificateRow.shapeCoverage,
    status: failures.isEmpty ? CertificateStatus.pass : CertificateStatus.fail,
    detail:
        'round-scope summaries with passes > 1: $measured'
        '${offSeat == 0 ? '' : ', $offSeat on other substations'}'
        '${unjoined == 0 ? '' : ', $unjoined unjoined (no record in the log '
                  'names the session\'s substation)'}'
        '${nonRound == 0 ? '' : ', $nonRound non-round summar'
                  '${nonRound == 1 ? 'y' : 'ies'} excluded '
                  '($kBootFinalSummaryScope is not a round)'}',
    failures: failures,
  );
}

CertificateItem _wouldRefuse(List<BootEvidence> boots) {
  final measured = <int, int>{};
  for (final boot in boots) {
    final value = boot.governing?.intOf(kWouldRefuseCounter);
    if (value != null) measured[boot.epoch] = value;
  }
  if (measured.isEmpty) {
    // W2-B's observe form has not landed: there is no counter to gate, and
    // inventing a failure out of its absence would block the certificate on a
    // build item the bead puts out of scope.
    return const CertificateItem(
      row: CertificateRow.wouldRefuse,
      status: CertificateStatus.pass,
      detail:
          '$kWouldRefuseCounter not emitted on any counted boot — W2-B\'s '
          'observe form has not landed; informational',
    );
  }
  // REPORTED, NOT GATING (cut-wiring §W2.5, the `barrier_would_refuse` row;
  // and the engine's own accounting comment). The barrier's observe form
  // counts how many candidates it WOULD have refused this boot — routine
  // operator re-arms onto a surviving worktree are exactly that — and the
  // table lists the counter so the reader sees it, not so the certificate
  // breaks on it. A non-zero value is printed with its epoch and never
  // becomes a failure; measured 2026-09-14 on lunar epoch 77 (= 2) as a
  // consecutive-run break that the table does not authorise.
  return CertificateItem(
    row: CertificateRow.wouldRefuse,
    status: CertificateStatus.pass,
    detail:
        '${[for (final entry in measured.entries) 'epoch ${entry.key} ${entry.value}'].join(', ')}'
        ' — reported, not gating (cut-wiring §W2.5)',
  );
}

CertificateItem _consecutive(
  List<BootEvidence> boots,
  List<int> ledger,
  int requestedBoots,
  List<CertificateItem> rows,
) {
  final failures = <String>[];
  final counted = [for (final boot in boots) boot.epoch];
  final tail = ledger.sublist(ledger.length - requestedBoots);
  if (counted.length != requestedBoots || !_sameOrder(counted, tail)) {
    failures.add(
      'the counted boots ${_epochList(counted)} are not the ledger\'s '
      '$requestedBoots most recent claims ${_epochList(tail)}',
    );
  }
  for (final row in rows) {
    for (final failure in row.failures) {
      failures.add('${row.row.wire} fails — $failure; the run restarts there');
    }
  }
  return CertificateItem(
    row: CertificateRow.consecutive,
    status: failures.isEmpty ? CertificateStatus.pass : CertificateStatus.fail,
    detail: failures.isEmpty
        ? 'epochs ${_epochList(counted)} are the ledger\'s $requestedBoots '
              'most recent claims and every row passes on each'
        : '${failures.length} break'
              '${failures.length == 1 ? '' : 's'} in the run of '
              '$requestedBoots',
    failures: failures,
  );
}

String _noGoverningNote(BootEvidence boot) =>
    'epoch ${boot.epoch}: no round summary with passes > 1 '
    '(${boot.summaries} summar${boot.summaries == 1 ? 'y' : 'ies'} in the '
    'epoch) — the boot certifies nothing';

String _epochList(List<int> epochs) => epochs.join(', ');

bool _sameOrder(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
