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

import 'package:args/command_runner.dart';
import 'package:meta/meta.dart';

import 'traj_flags.dart';
import 'trajectory_reader.dart';

/// §9's allow-list split. Only [unexplained] blocks a stage cut; the
/// non-atomic-crash class (a crash between the legacy write and the trajectory
/// append) is adjudicated once by the operator.
enum ShadowMismatchClass {
  unexplained('unexplained'),
  nonAtomicCrash('non_atomic_crash');

  const ShadowMismatchClass(this.wire);

  /// Snake_case on the wire, matching the DDL's vocabulary — the report is
  /// the artifact a stage cut is adjudicated on, and a Stage-1 comparator
  /// parses it.
  final String wire;
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
    this.classification = ShadowMismatchClass.unexplained,
  });

  final String sessionId;
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
  /// Never carries mismatches — an unearned zero and an unearned divergence
  /// are the same lie.
  const ShadowCompareResult.incomplete(String reason)
    : incompleteReason = reason,
      mismatches = const [];

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
  }) : _open = open ?? openTrajectoryReader,
       _compare = compare,
       _compareFor = compareFor {
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
      );
  }

  final TrajectoryOpener _open;
  final ShadowCompare _compare;
  final ShadowCompareFactory? _compareFor;

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
    return runTrajShadowDiff(
      gridHome: gridHome,
      open: _open,
      compare: _compare,
      compareFor: _compareFor,
      sessions: argResults!.multiOption('session'),
      round: round,
      limit: limit,
    );
  }
}

/// Runs the comparator and prints the §9 report.
///
/// Exits 1 only on an UNEXPLAINED mismatch (the stage cut is blocked) or an
/// unreachable server. An unbootstrapped grid home, an empty log, "nothing is
/// comparable yet", and a session the reader could not hand over WHOLE are all
/// exit-0 runs that do not count toward the cut criterion — the last of those
/// is printed as `INCOMPLETE` and is the reason a zero-mismatch run can still
/// be non-counting.
Future<int> runTrajShadowDiff({
  required String gridHome,
  required TrajectoryOpener open,
  ShadowCompare compare = const UncomparableShadow(),
  ShadowCompareFactory? compareFor,
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

  final opened = await open(gridHome);
  switch (opened) {
    case TrajectoryUnavailable(:final message):
      writeErr('traj shadow-diff: $message');
      return 1;
    case TrajectoryNotBootstrapped(:final message):
      write('  $message');
      _writeLimits(write, compare);
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
        // An incomplete session poisons the RUN, not just itself: the cut
        // criterion is "N consecutive clean runs", and a run that could not
        // read a session whole never established that session clean.
        final counts = incomplete.isEmpty;
        final tally = mismatches.isEmpty
            ? '0 mismatches over ${scope.length} session'
                  '${scope.length == 1 ? '' : 's'}'
            : '${mismatches.length} mismatch'
                  '${mismatches.length == 1 ? '' : 'es'}, $unexplained '
                  'unexplained';
        final verdict = switch ((counts, mismatches.isEmpty, unexplained)) {
          (true, true, _) =>
            ' — one clean run toward the criterion of 3 consecutive.',
          (false, _, 0) =>
            ' — ${incomplete.length} session'
                '${incomplete.length == 1 ? '' : 's'} read INCOMPLETE; this '
                'run does NOT count toward the 3-clean-round cut criterion.',
          (_, _, 0) => ' — allow-listed only; the operator adjudicates.',
          _ =>
            ' — the stage cut is BLOCKED; the fold is presumed wrong until '
                'shown otherwise.',
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

void _writeMismatches(
  void Function(String) write,
  List<ShadowMismatch> mismatches,
) {
  write(
    '  ${'session'.padRight(24)}${'field'.padRight(20)}'
    '${'legacy_value'.padRight(20)}${'fold_value'.padRight(20)}seq',
  );
  for (final row in mismatches) {
    write(
      '  ${row.sessionId.padRight(24)}${row.field.padRight(20)}'
      '${(row.legacyValue ?? '-').padRight(20)}'
      '${(row.foldValue ?? '-').padRight(20)}'
      '${row.seq ?? '-'}  [${row.classification.wire}]',
    );
  }
}
