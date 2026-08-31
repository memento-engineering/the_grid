/// Lane composition: the union of what was compared, the carry-through of
/// what could not be, and the rule that one lane's short read never hides
/// another lane's earned divergence.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

class _Lane implements ShadowCompare {
  _Lane(
    this.fields, {
    this.mismatches = const [],
    this.incomplete,
    this.reason,
  });

  final Set<String> fields;
  final List<ShadowMismatch> mismatches;
  final String? incomplete;
  final String? reason;
  final calls = <String>[];

  @override
  Set<String> get comparableFields => fields;

  @override
  String? get unavailableReason => reason;

  @override
  Future<ShadowCompareResult> compare({
    required String sessionId,
    required SubjectRecords records,
    int? round,
  }) async {
    calls.add('$sessionId/${round ?? '-'}');
    if (incomplete case final String why) {
      return ShadowCompareResult.incomplete(why);
    }
    return ShadowCompareResult(mismatches);
  }
}

ShadowMismatch _mismatch(String field) => ShadowMismatch(
  sessionId: 's',
  field: field,
  legacyValue: 'a',
  foldValue: 'b',
  seq: 1,
);

const _records = SubjectRecords(records: []);

void main() {
  test('comparableFields is the union of the lanes', () {
    final composite = CompositeShadow([
      _Lane({'status', 'outcome'}),
      _Lane({'step_state'}),
    ]);
    expect(composite.comparableFields, {'status', 'outcome', 'step_state'});
    expect(composite.unavailableReason, isNull);
  });

  test('every lane sees the same session and round', () async {
    final a = _Lane({'status'});
    final b = _Lane({'step_state'});
    await CompositeShadow([
      a,
      b,
    ]).compare(sessionId: 's', records: _records, round: 4);
    expect(a.calls, ['s/4']);
    expect(b.calls, ['s/4']);
  });

  test('mismatches from every lane are unioned in lane order', () async {
    final result = await CompositeShadow([
      _Lane({'status'}, mismatches: [_mismatch('status')]),
      _Lane({'step_state'}, mismatches: [_mismatch('step_state')]),
    ]).compare(sessionId: 's', records: _records);
    expect(result.mismatches.map((row) => row.field), ['status', 'step_state']);
    expect(result.isIncomplete, isFalse);
  });

  test('a dark lane is carried as a reason but does not darken the run', () {
    final composite = CompositeShadow([
      _Lane({'status'}),
      _Lane(const {}, reason: 'no ledger for steps here'),
    ]);
    expect(composite.comparableFields, {'status'});
    expect(composite.unavailableReason, contains('some lanes are dark'));
    expect(composite.unavailableReason, contains('no ledger for steps here'));
  });

  test('ALL lanes dark reports the reasons alone', () {
    final composite = CompositeShadow([
      _Lane(const {}, reason: 'a is dark'),
      _Lane(const {}, reason: 'b is dark'),
    ]);
    expect(composite.comparableFields, isEmpty);
    // Each fragment names its lane — a bare reason list would leave the
    // operator guessing which half of the window is unarmed.
    expect(composite.unavailableReason, '_Lane: a is dark; _Lane: b is dark');
  });

  test("one lane's short read disqualifies the session WITHOUT hiding "
      "another lane's mismatches", () async {
    final result = await CompositeShadow([
      _Lane({'status'}, mismatches: [_mismatch('status')]),
      _Lane({'step_state'}, incomplete: 'the stream was cut at 1 row'),
    ]).compare(sessionId: 's', records: _records);
    // Both facts survive: the divergence is reported AND the run cannot
    // count. Collapsing either one would be the same lie in one direction or
    // the other.
    expect(result.mismatches.single.field, 'status');
    expect(result.isIncomplete, isTrue);
    expect(result.incompleteReason, contains('cut at 1 row'));
  });
}
