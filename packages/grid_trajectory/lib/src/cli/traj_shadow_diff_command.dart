/// `traj shadow-diff` — the §9 shadow comparator.
///
/// The comparator is a DELIVERABLE, not a posture: it runs per round, emits a
/// typed mismatch report keyed `(session, field, legacy_value, fold_value,
/// seq)`, and a stage cut without N clean runs on record cannot proceed.
///
/// The strategy is injected two ways: a fixed [ShadowCompare], or a
/// [ShadowCompareFactory] that sees the parsed grid home and opens the LEGACY
/// ledger beside the trajectory store (grid_cli composes the real Family-1
/// comparator, `AttemptLifecycleShadow`, this way). With neither, the
/// [UncomparableShadow] default compares NOTHING and says so rather than
/// reporting a clean run it did not earn.
library;

import 'dart:io';

import 'package:args/args.dart' show ArgResults;
import 'package:args/command_runner.dart';
import 'package:meta/meta.dart';

import 'shadow_accounting.dart';
import 'traj_flags.dart';
import 'trajectory_reader.dart';

/// §9's allow-list split. Only [unexplained] blocks a stage cut; the NAMED
/// gaps are adjudicated once by the operator.
///
/// The naming is the point (stage1-wiring §2.3): a gap that has a name is
/// counted, attributed, and argued about once; a gap that does not is silent
/// and gets read as agreement. Every class below is a shape the design states
/// the shadow window WILL produce — none of them is an escape hatch for a
/// mismatch nobody understood.
enum ShadowMismatchClass {
  unexplained('unexplained'),

  /// A crash between the legacy write and the trajectory append. The
  /// recorder appends only after legacy success (§2.3), so the shadow never
  /// leads the incumbent — but it can lag it by exactly one crash.
  nonAtomicCrash('non_atomic_crash'),

  /// **stop-races-spawn** (§2.3, r2 minor 16). A teardown deregisters a
  /// session while the spawner is suspended; the provider kills the process
  /// and returns with no `sessionStarted` and no supervision armed
  /// (`subprocess_provider.dart:268-279` says so verbatim). A real process
  /// incarnation ran and died having emitted zero events, so it produced zero
  /// records — and with no attempt row there is no obligation, so the tick
  /// will never notice either. Counted and named here rather than left as an
  /// unexplained mismatch it would otherwise masquerade as.
  stopRacesSpawn('stop_races_spawn');

  const ShadowMismatchClass(this.wire);

  /// Snake_case on the wire, matching the DDL's vocabulary — the report is
  /// the artifact a stage cut is adjudicated on, and a Stage-1 comparator
  /// parses it.
  final String wire;

  /// True for every class that is NOT [unexplained] — the §9 allow-list.
  bool get isNamedGap => this != ShadowMismatchClass.unexplained;
}

/// One typed mismatch, keyed exactly as §9 orders the report.
@immutable
class ShadowMismatch {
  const ShadowMismatch({
    required this.sessionId,
    required this.field,
    required this.legacyValue,
    required this.foldValue,
    required this.seq,
    this.stepPath,
    this.classification = ShadowMismatchClass.unexplained,
  });

  final String sessionId;

  /// The step coordinate, for lanes keyed per step (`StepTransitionShadow`).
  /// Null on session-keyed lanes — §9's key is `(session, field, …)` and the
  /// step family simply needs one more coordinate to name its subject, not a
  /// different report.
  final String? stepPath;

  final String field;
  final String? legacyValue;
  final String? foldValue;

  /// The trajectory `seq` the fold value was read at — the report's cursor
  /// back into `traj show`.
  final int? seq;
  final ShadowMismatchClass classification;
}

/// One session's comparison outcome. `incomplete` is a THIRD state, not a
/// clean run with zero mismatches: the fold could not see the session's whole
/// record stream, so its head is not the head the log supports and neither
/// agreement nor divergence was established. A run carrying one cannot count
/// toward the §9 cut criterion.
@immutable
class ShadowCompareResult {
  /// A comparison that actually happened — [mismatches] is the whole story.
  const ShadowCompareResult(this.mismatches) : incompleteReason = null;

  /// A comparison that could NOT happen: [reason] says what was missing.
  /// Never carries mismatches — for ONE strategy, an unearned zero and an
  /// unearned divergence are the same lie.
  const ShadowCompareResult.incomplete(String reason)
    : incompleteReason = reason,
      mismatches = const [];

  /// Several INDEPENDENT lanes, some of which compared and some of which
  /// could not (`CompositeShadow`). Lane A's divergence stays earned when
  /// lane B could not read — they fold different record families over
  /// different oracles — so the mismatches are reported AND the run is
  /// disqualified. The single-strategy ban above still holds: a lane that
  /// folds a prefix must return [ShadowCompareResult.incomplete] for itself.
  const ShadowCompareResult.partial(this.mismatches, String reason)
    : incompleteReason = reason;

  final List<ShadowMismatch> mismatches;

  /// Why this session was not comparable — null on a real comparison.
  final String? incompleteReason;

  bool get isIncomplete => incompleteReason != null;
}

/// The legacy-vs-fold comparison, injected so a composing runner fills it in
/// without touching the verb.
abstract interface class ShadowCompare {
  /// The shared fields this strategy compares. EMPTY means there is no oracle
  /// yet and the verb must report [unavailableReason] instead of claiming a
  /// clean run.
  Set<String> get comparableFields;

  /// Why nothing can be compared — null once [comparableFields] is non-empty.
  String? get unavailableReason;

  /// The outcome for one session's [records] — the COMPLETE `seq`-ordered
  /// stream, or a stream the reader marked truncated, which a strategy that
  /// folds must refuse as [ShadowCompareResult.incomplete]. Scoped to [round]
  /// when the operator named one.
  Future<ShadowCompareResult> compare({
    required String sessionId,
    required SubjectRecords records,
    int? round,
  });
}

/// Stage 0's strategy: the legacy path is still the sole writer, so there is
/// no second value to compare against.
@immutable
class UncomparableShadow implements ShadowCompare {
  const UncomparableShadow();

  @override
  Set<String> get comparableFields => const {};

  @override
  String get unavailableReason =>
      'no legacy dual-write is wired yet — the dual-read (read P1, fall '
      'through to the existing bead reader) arms with the Stage 1 cut, so no '
      'shared field has an oracle to compare against';

  @override
  Future<ShadowCompareResult> compare({
    required String sessionId,
    required SubjectRecords records,
    int? round,
  }) async => const ShadowCompareResult([]);
}

/// §9's stated non-shadowable facts, printed so a clean run is not overread.
const String unshadowableFacts =
    'attempt_id, commit digests, per-effect intent/ack ordering, provenance '
    'markers, incarnation identity';

/// Builds the strategy FOR a grid home — the seam a composing runner
/// (grid_cli) uses to open the legacy ledger beside the trajectory store at
/// run time, after `--state-workspace` is parsed. A home without a readable
/// ledger must yield a strategy with empty [ShadowCompare.comparableFields]
/// and a reason, never a throw: degrading gracefully is the verb's contract.
typedef ShadowCompareFactory = Future<ShadowCompare> Function(String gridHome);

/// The verb.
class TrajShadowDiffCommand extends Command<int> {
  /// Creates the comparator verb with an optional injected opener and
  /// strategy.
  TrajShadowDiffCommand({
    TrajectoryOpener? open,
    ShadowCompare compare = const UncomparableShadow(),
    ShadowCompareFactory? compareFor,
    ShadowAccountingSource? accountingFor,
  }) : _open = open ?? openTrajectoryReader,
       _compare = compare,
       _compareFor = compareFor,
       _accountingFor = accountingFor {
    addGridHomeOption(argParser);
    argParser
      ..addMultiOption(
        'session',
        help:
            'A session id to compare; repeatable. Omitted scopes the run to '
            'every session present in the log.',
      )
      ..addOption('round', help: 'Restrict the comparison to one round.')
      ..addOption(
        'limit',
        help:
            'Ceiling on the COMPLETE per-session read (default '
            '$completeReadCeiling). Not a window: a session whose stream '
            'reaches it is reported incomplete, never folded.',
      )
      ..addOption(
        'dropped',
        help:
            "This round's dropped-append count, read off the station's "
            '/status trajectory block. Any drop disqualifies the round from '
            'the clean-round criterion; supplying nothing leaves accounting '
            'UNKNOWN, which does not count either.',
      )
      ..addOption(
        'suppressed',
        help:
            "This round's suppressed-append count from /status (appends "
            'short-circuited after a fenced-out/halted/degraded latch). '
            'Disqualifies on the same grounds as --dropped.',
      );
  }

  final TrajectoryOpener _open;
  final ShadowCompare _compare;
  final ShadowCompareFactory? _compareFor;
  final ShadowAccountingSource? _accountingFor;

  @override
  final String name = 'shadow-diff';

  @override
  final String description =
      'Compare the legacy session disposition against the trajectory fold and '
      'report typed mismatches (the §9 stage-cut evidence).';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      stderr.writeln(
        'traj shadow-diff: unexpected argument '
        '"${argResults!.rest.first}"; sessions are named with --session.',
      );
      return 64;
    }
    final gridHome = gridHomeFrom(argResults!, stderr.writeln, 'shadow-diff');
    if (gridHome == null) return 64;
    final limit = positiveIntFrom(
      argResults!,
      'limit',
      stderr.writeln,
      'shadow-diff',
      fallback: completeReadCeiling,
    );
    if (limit == null) return 64;
    int? round;
    final rawRound = argResults!.option('round');
    if (rawRound != null) {
      round = int.tryParse(rawRound);
      if (round == null || round < 0) {
        stderr.writeln(
          'traj shadow-diff: --round must be a non-negative integer '
          '(got "$rawRound").',
        );
        return 64;
      }
    }
    // Non-NEGATIVE, not positive: `--dropped 0` is the operator ASSERTING a
    // clean round off /status, which is the whole point of the flag, so
    // positiveIntFrom's rule is wrong here.
    final dropped = _countFrom(argResults!, 'dropped');
    if (dropped == null && argResults!.option('dropped') != null) return 64;
    final suppressed = _countFrom(argResults!, 'suppressed');
    if (suppressed == null && argResults!.option('suppressed') != null) {
      return 64;
    }
    return runTrajShadowDiff(
      gridHome: gridHome,
      open: _open,
      compare: _compare,
      compareFor: _compareFor,
      accounting: dropped == null && suppressed == null
          ? null
          : ShadowRunAccounting(
              dropped: dropped ?? 0,
              suppressed: suppressed ?? 0,
            ),
      accountingFor: _accountingFor,
      sessions: argResults!.multiOption('session'),
      round: round,
      limit: limit,
    );
  }

  /// A non-negative count option, or null when absent OR malformed — the
  /// caller distinguishes the two by re-reading the raw option, and the
  /// refusal is written here so both counters share one wording.
  int? _countFrom(ArgResults args, String option) {
    final raw = args.option(option);
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null || value < 0) {
      stderr.writeln(
        'traj shadow-diff: --$option must be a non-negative integer '
        '(got "$raw").',
      );
      return null;
    }
    return value;
  }
}

/// Runs the comparator and prints the §9 report.
///
/// Exits 1 only on an UNEXPLAINED mismatch (the stage cut is blocked) or an
/// unreachable server. An unbootstrapped grid home, an empty log, "nothing is
/// comparable yet", a session the reader could not hand over WHOLE, and a run
/// whose append accounting is dirty or unknown are all exit-0 runs that do not
/// count toward the cut criterion. Those last two are the reason a
/// zero-mismatch run can still be non-counting: an unread session was never
/// shown clean, and a dropped append is a record the comparator could not
/// have missed agreeing with (§2.5/§3).
Future<int> runTrajShadowDiff({
  required String gridHome,
  required TrajectoryOpener open,
  ShadowCompare compare = const UncomparableShadow(),
  ShadowCompareFactory? compareFor,
  ShadowRunAccounting? accounting,
  ShadowAccountingSource? accountingFor,
  List<String> sessions = const [],
  int? round,
  int limit = completeReadCeiling,
  void Function(String)? out,
  void Function(String)? err,
}) async {
  final void Function(String) write = out ?? stdout.writeln;
  final void Function(String) writeErr = err ?? stderr.writeln;
  write('traj shadow-diff — legacy/fold comparator (schema §9)');
  // The factory outranks the fixed strategy: it sees the parsed grid home,
  // so it can open the LEGACY ledger beside the trajectory store — the real
  // compare when both exist, a reasoned degrade when the ledger is absent.
  if (compareFor != null) compare = await compareFor(gridHome);
  // The operator's /status numbers outrank a composed source: the flag is the
  // §4 operating loop's own instrument, and a runner reading a DIFFERENT
  // station's harness must never quietly overwrite what the operator read.
  accounting ??= accountingFor == null ? null : await accountingFor(gridHome);

  final opened = await open(gridHome);
  switch (opened) {
    case TrajectoryUnavailable(:final message):
      writeErr('traj shadow-diff: $message');
      return 1;
    case TrajectoryNotBootstrapped(:final message):
      write('  $message');
      _writeLimits(write, compare);
      _writeAccounting(write, accounting);
      write(
        '  result: nothing compared — this run does NOT count toward the '
        '3-clean-round cut criterion.',
      );
      return 0;
    case TrajectoryOpened(:final reader):
      try {
        final scope = sessions.isEmpty
            ? await reader.sessions(limit: limit)
            : sessions;
        write(
          '  scope: ${scope.isEmpty ? 'no sessions in the log' : scope.join(', ')}'
          '${round == null ? '' : ' · round $round'}',
        );
        _writeLimits(write, compare);
        _writeAccounting(write, accounting);

        final mismatches = <ShadowMismatch>[];
        final incomplete = <String>[];
        for (final sessionId in scope) {
          // The COMPLETE stream, never the `traj show` window: the strategy
          // folds what it is handed, so handing it a cut stream would buy a
          // clean report the log does not support.
          final records = await reader.allRecordsForSubject(
            sessionId,
            ceiling: limit,
          );
          final result = await compare.compare(
            sessionId: sessionId,
            records: records,
            round: round,
          );
          mismatches.addAll(result.mismatches);
          if (result.incompleteReason case final String reason) {
            incomplete.add('$sessionId — $reason');
          }
        }

        if (compare.comparableFields.isEmpty) {
          write(
            '  result: nothing compared — this run does NOT count toward the '
            '3-clean-round cut criterion.',
          );
          return 0;
        }
        for (final session in incomplete) {
          write('  INCOMPLETE: $session');
        }
        final unexplained = mismatches
            .where(
              (row) => row.classification == ShadowMismatchClass.unexplained,
            )
            .length;
        if (mismatches.isNotEmpty) _writeMismatches(write, mismatches);
        _writeNamedGaps(write, mismatches);

        // Everything that poisons the RUN rather than one session, listed so
        // the operator sees WHICH rule fired. An incomplete read never
        // established its session clean; a dropped or suppressed append is a
        // record the fold could not have disagreed with, so its absence must
        // not be spent as agreement (§2.5/§3).
        final disqualifiers = <String>[
          if (incomplete.isNotEmpty)
            '${incomplete.length} session'
                '${incomplete.length == 1 ? '' : 's'} read INCOMPLETE',
          // Short here on purpose: the accounting LINE above already carries
          // the full instruction, and repeating it verbatim in the verdict
          // buries the other disqualifiers beside it.
          if (accounting == null)
            'append accounting UNKNOWN'
          else if (accounting.disqualification case final String reason)
            reason,
        ];
        final tally = mismatches.isEmpty
            ? '0 mismatches over ${scope.length} session'
                  '${scope.length == 1 ? '' : 's'}'
            : '${mismatches.length} mismatch'
                  '${mismatches.length == 1 ? '' : 'es'}, $unexplained '
                  'unexplained';
        final verdict = switch ((disqualifiers.isEmpty, mismatches.isEmpty)) {
          _ when unexplained > 0 =>
            ' — the stage cut is BLOCKED; the fold is presumed wrong until '
                'shown otherwise.',
          (false, _) =>
            ' — ${disqualifiers.join('; ')}; this run does NOT count toward '
                'the 3-clean-round cut criterion.',
          (true, true) =>
            ' — one clean run toward the criterion of 3 consecutive.',
          (true, false) => ' — allow-listed only; the operator adjudicates.',
        };
        write('  result: $tally$verdict');
        return unexplained == 0 ? 0 : 1;
      } finally {
        await reader.close();
      }
  }
}

/// What the run can and cannot certify — printed on every path so a clean
/// report is never overread.
void _writeLimits(void Function(String) write, ShadowCompare compare) {
  write('  strategy: ${compare.runtimeType}');
  write(
    '  compares: '
    '${compare.comparableFields.isEmpty ? 'nothing yet' : (compare.comparableFields.toList()..sort()).join(', ')}',
  );
  final reason = compare.unavailableReason;
  if (reason != null) write('  cannot compare yet: $reason');
  write('  never shadowable (§9): $unshadowableFacts.');
}

/// The round's append accounting — printed on every path that reaches the log
/// (§4's operating loop: the per-round report carries the drop count).
void _writeAccounting(
  void Function(String) write,
  ShadowRunAccounting? accounting,
) {
  if (accounting == null) {
    write('  append accounting: UNKNOWN — $unknownAccountingReason.');
    return;
  }
  final reason = accounting.disqualification;
  write(
    '  append accounting: ${accounting.summary}'
    '${reason == null ? ' — clean' : ' — DISQUALIFYING ($reason)'}',
  );
}

/// The §4 evidence pack's named-gap counts. Printed only when a gap actually
/// occurred: an always-present "0, 0" line trains the eye to skip it.
void _writeNamedGaps(
  void Function(String) write,
  List<ShadowMismatch> mismatches,
) {
  final counts = <String, int>{};
  for (final row in mismatches) {
    if (!row.classification.isNamedGap) continue;
    counts[row.classification.wire] =
        (counts[row.classification.wire] ?? 0) + 1;
  }
  if (counts.isEmpty) return;
  final keys = counts.keys.toList()..sort();
  write(
    '  named gaps: ${keys.map((key) => '$key ${counts[key]}').join(', ')} '
    '(allow-listed; adjudicated once, never silently dropped)',
  );
}

void _writeMismatches(
  void Function(String) write,
  List<ShadowMismatch> mismatches,
) {
  // The step_path column appears only when a lane that keys on it produced a
  // row — a permanently empty column is a column nobody reads.
  final withPath = mismatches.any((row) => row.stepPath != null);
  write(
    '  ${'session'.padRight(24)}'
    '${withPath ? 'step_path'.padRight(24) : ''}${'field'.padRight(20)}'
    '${'legacy_value'.padRight(20)}${'fold_value'.padRight(20)}seq',
  );
  for (final row in mismatches) {
    write(
      '  ${row.sessionId.padRight(24)}'
      '${withPath ? (row.stepPath ?? '-').padRight(24) : ''}'
      '${row.field.padRight(20)}'
      '${(row.legacyValue ?? '-').padRight(20)}'
      '${(row.foldValue ?? '-').padRight(20)}'
      '${row.seq ?? '-'}  [${row.classification.wire}]',
    );
  }
}
