/// The §W2.5 SOAK CERTIFICATE — pure, I/O-free, over decoded rows.
///
/// `docs/design/trajectory/cut-wiring.md` §W2.5 states the certificate as a
/// table a human reads off "the LAST round-summary note of each boot whose
/// `passes > 1`". A runbook with no oracle is why no soak has ever been
/// certified, so the machine-checkable half of that table is folded HERE and
/// turned into PASS/FAIL rows; `traj certify` only reads the log and prints
/// what this file decides.
///
/// Three rules carry the honesty of the result, each one a shape §W2.5 warns
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

/// The seats Q1 scoped the soak to (`wave-2-flip-scope-soak-and-kill-date`).
///
/// A target is matched against the record's `substation` either exactly or as
/// its leading segment, so the ruling's `butane` covers the roster's
/// `butane_flutter` without the ruling having to spell a repo name.
const Set<String> kSoakTargetSeats = {'lenny', 'butane'};

/// The counters the `clean` row GATES, in print order.
///
/// The two miss twins are §W2.5's cut signal ("replaces `fallbacks = 0`"); the
/// two unexplained twins are the in-window divergence rows of the same table.
/// Every one of them is `cumulative` in the round summary's own
/// `counter_semantics` map.
const List<String> kCertificateGatingCounters = [
  'miss_post_epoch_total',
  'p2_miss_total',
  'unexplained_divergences_in_window',
  'step_unexplained_divergences_in_window',
];

/// The counters printed BESIDE the gate — §W2.5's "reported, never gating"
/// list plus the table rows this verb does not gate on.
const List<String> kCertificateReportedCounters = [
  'soak_window_epoch',
  'miss_post_epoch',
  'p2_miss',
  'miss_legacy_era',
  'null_started_at',
  'fallbacks',
  'p1_orphan',
  'cardinality_breaches_in_window',
  'terminal_lag_open_in_window',
  'retirement_lag_open_in_window',
  'step_lag_open',
  'append_drops',
  'append_suppressed',
  'append_refused_testimony',
  'append_ack_p99_ms',
];

/// W2-B's observe-form counter (§W2.5's last table row). Absent from every
/// summary until W2-B lands, which is why its row is informational until it
/// appears.
const String kWouldRefuseCounter = 'barrier_would_refuse';

/// The certificate items this verb CANNOT check — printed with their state
/// unknown so a reader is never told the verb claimed them.
///
/// The first four are the human half of `lunar_station-bzt`'s evidence pack;
/// the fifth is machine-checkable but not from the trajectory database alone —
/// `traj shadow-diff` needs the legacy ledger beside it.
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

  /// `boot-final` or `session-terminal` (§0.4), or null on a body that
  /// declared no scope.
  String? get scope => stringOf('scope');

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
}

/// One counted boot's window, as the verb read it.
@immutable
class BootWindow {
  /// Creates a window over one claimed epoch.
  const BootWindow({
    required this.epoch,
    required this.station,
    required this.records,
    this.truncated = false,
  });

  final int epoch;
  final String station;

  /// Every row the reader returned for this `boot_epoch`, `seq`-ordered.
  final List<TrajectoryEnvelope> records;

  /// The read was CUT SHORT — the governing note may simply not be in hand,
  /// so nothing this window says can certify a boot.
  final bool truncated;
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
    required this.unattributedRounds,
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

  /// Rounds with `passes > 1` whose session no record attributed to a
  /// substation — counted, never silently dropped.
  final int unattributedRounds;

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
    'overlay_engaged': governing?.boolOf('overlay_engaged'),
    'overlay_disengaged_for_boot': governing?.boolOf(
      'overlay_disengaged_for_boot',
    ),
    'step_axis_engaged': governing?.boolOf('step_axis_engaged'),
    'first_epoch_claimed_at': governing?.stringOf('first_epoch_claimed_at'),
    'counters': counters,
    'seat_rounds': Map<String, int>.from(seatRounds),
    'unattributed_rounds': unattributedRounds,
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

/// Folds one boot's window into its evidence.
BootEvidence foldBootEvidence(
  BootWindow window, {
  Set<String> seats = kSoakTargetSeats,
}) {
  final substationOf = <String, String>{};
  for (final envelope in window.records) {
    final session = envelope.sessionId;
    final substation = envelope.substation;
    if (session == null || substation == null) continue;
    substationOf.putIfAbsent(session, () => substation);
  }

  final notes = <RoundSummaryNote>[];
  for (final envelope in window.records) {
    final note = roundSummaryOf(envelope);
    if (note != null) notes.add(note);
  }
  notes.sort((left, right) => left.seq.compareTo(right.seq));

  RoundSummaryNote? governing;
  final seatRounds = <String, int>{for (final seat in seats) seat: 0};
  var unattributed = 0;
  for (final note in notes) {
    if (note.passes <= 1) continue;
    governing = note;
    final seat = seatFor(substationOf[note.sessionId], seats);
    if (seat == null) {
      unattributed++;
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
    unattributedRounds: unattributed,
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
  }
  return CertificateItem(
    row: CertificateRow.posture,
    status: failures.isEmpty ? CertificateStatus.pass : CertificateStatus.fail,
    detail: failures.isEmpty
        ? '${boots.length}/${boots.length} boots served mode=primary with the '
              'overlay engaged and health live'
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
        ? kCertificateGatingCounters.map((key) => '$key 0').join(', ')
        : '${failures.length} clean failure'
              '${failures.length == 1 ? '' : 's'}',
    failures: failures,
  );
}

CertificateItem _shapeCoverage(List<BootEvidence> boots, List<String> seats) {
  final totals = <String, int>{for (final seat in seats) seat: 0};
  var unattributed = 0;
  for (final boot in boots) {
    for (final entry in boot.seatRounds.entries) {
      totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
    }
    unattributed += boot.unattributedRounds;
  }
  final failures = <String>[
    for (final seat in seats)
      if ((totals[seat] ?? 0) == 0)
        'seat $seat: no round with passes > 1 across the counted boots',
  ];
  final measured = [
    for (final seat in seats) '$seat ${totals[seat] ?? 0}',
  ].join(', ');
  return CertificateItem(
    row: CertificateRow.shapeCoverage,
    status: failures.isEmpty ? CertificateStatus.pass : CertificateStatus.fail,
    detail:
        'rounds with passes > 1: $measured'
        '${unattributed == 0 ? '' : ' ($unattributed unattributed)'}',
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
  final failures = <String>[
    for (final entry in measured.entries)
      if (entry.value != 0)
        'epoch ${entry.key}: $kWouldRefuseCounter = ${entry.value}',
  ];
  return CertificateItem(
    row: CertificateRow.wouldRefuse,
    status: failures.isEmpty ? CertificateStatus.pass : CertificateStatus.fail,
    detail: [
      for (final entry in measured.entries) 'epoch ${entry.key} ${entry.value}',
    ].join(', '),
    failures: failures,
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
