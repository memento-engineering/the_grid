import 'go_scalars.dart';

/// A normalized agent verdict for `convergence.agent_verdict`.
///
/// An **open-set** extension type over the wire string (the codebase rule for
/// values gc consumes verbatim): the canonical values are closed in
/// `metadata.go:105-109`, but gc never validates the stored string — it
/// normalizes on read with [normalize], which maps anything unknown to
/// [block].
extension type const Verdict(String wire) {
  /// metadata.go:106 — `VerdictApprove = "approve"`.
  static const approve = Verdict('approve');

  /// metadata.go:107 — `VerdictApproveWithRisks = "approve-with-risks"`.
  static const approveWithRisks = Verdict('approve-with-risks');

  /// metadata.go:108 — `VerdictBlock = "block"`.
  static const block = Verdict('block');

  /// Port of `convergence.NormalizeVerdict` (metadata.go:121-138): lowercase,
  /// trim whitespace, map past-tense forms (metadata.go:113-119), pass the
  /// three canonical values through, and collapse everything else — including
  /// the empty string — to [block].
  ///
  /// **Trim is [goTrimSpace], NOT `String.trim()`** — Dart's trim strips
  /// U+FEFF (BOM), Go's `strings.TrimSpace` does not, and the verdict gates
  /// the gate path's iterate-vs-terminate branch (handler.go:317-324): a
  /// BOM-prefixed `approve` written via `bd meta set` (the only
  /// agent-writable channel, acl.go:10-13) must normalize to [block]
  /// exactly as in gc.
  ///
  /// **Lowercase residual, pinned not ported:** Go `strings.ToLower` is the
  /// Unicode SIMPLE case mapping; the Dart VM's `toLowerCase` agrees on
  /// every outcome-relevant rune (it is also simple-mapping —
  /// `'İ'.toLowerCase() == 'i'`, `'ß'.toUpperCase() == 'ß'`; pinned in
  /// go_scalars_test.dart against go1.26.4). U+0130 is additionally
  /// pre-mapped to `i` here so the one rune whose FULL lowercase diverges
  /// (`i` + combining dot, e.g. under dart2js) cannot flip a
  /// `approve-wİth-risks`-class input away from gc's outcome. Every other
  /// simple-vs-full difference (the final-sigma context rule) lowers to
  /// non-ASCII on both sides and can never reach the all-ASCII
  /// canonical/past-tense table.
  static Verdict normalize(String raw) {
    final v = goTrimSpace(raw).replaceAll('\u0130', 'i').toLowerCase();
    if (v.isEmpty) return block;
    final mapped = _pastTense[v];
    if (mapped != null) return mapped;
    return switch (v) {
      'approve' || 'approve-with-risks' || 'block' => Verdict(v),
      _ => block,
    };
  }
}

/// metadata.go:113-119 — `pastTenseMap`.
const _pastTense = <String, Verdict>{
  'approved': Verdict.approve,
  'blocked': Verdict.block,
  'approve-with-risk': Verdict.approveWithRisks,
  'approved-with-risks': Verdict.approveWithRisks,
  'approved-with-risk': Verdict.approveWithRisks,
};
