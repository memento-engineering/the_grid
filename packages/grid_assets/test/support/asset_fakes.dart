// Code-asset test support — the helpers that reference the moved `code`
// opinions (`kCodeFormula`/`buildCodeRegistry`), which do NOT belong in the
// engine's testing lib. Re-exports `package:grid_engine/testing.dart` so a
// moved test gets the SAME shared engine fakes (a drop-in for the old
// `support/engine_fakes.dart`), plus the `code` resolver below. Pure-Dart: no
// live tg/gc/claude/git/network.
export 'package:grid_engine/testing.dart';

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
// Imported (not just re-exported) so this library can USE the shared fakes
// (`stateSubstation`, etc.) in its own committee helpers.
import 'package:grid_engine/testing.dart';
import 'package:grid_assets/grid_assets.dart';

/// The live `code` resolver (all work → the `code` formula) for the integrated
/// acceptance tests — pair it with [buildCodeRegistry] as the ambient
/// `CapabilityRegistry`. Mirrors `composeRunTree`'s production wiring.
const FormulaResolver kCodeResolver = FormulaResolver(_codeFormula);
Formula _codeFormula(Bead bead) => kCodeFormula;

/// The committee-wired `code` formula's node paths (relative to the work bead),
/// in declaration order — `agent` → the four `review/<critic>` lanes → `review/route`
/// → `land`. The drive helpers + acceptance tests key the cursor off these.
const String kAgentNode = 'agent';
const List<String> kCriticNodes = [
  'review/code-validation',
  'review/spec-adherence',
  'review/regression-risk',
  'review/test-coverage',
];
const String kRouteNode = 'review/route';
const String kLandNode = 'land';

/// A STATE session bead for the COMMITTEE-wired `code` formula (M5 Track E):
/// marks each relative path in [completed] `complete` in the per-node cursor AND
/// attaches each grade in [grades] (relative nodePath → letter) under
/// `grid.result.*` — so a mounted `route` reads its siblings' grades through the
/// threaded `SiblingView` (D-5). [closed] marks the session terminal.
///
/// Paths are RELATIVE to [workBeadId] (e.g. `'review/route'`); the helper prefixes
/// the bead id, matching the engine's `<beadId>/<...>` cursor keying.
Bead committeeSession({
  String id = 'tgdog-sess1',
  String workBeadId = 'tg-1',
  Set<String> completed = const {},
  Set<String> gated = const {},
  Map<String, String> grades = const {},
  bool closed = false,
}) => Bead(
  id: id,
  issueType: IssueType.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    SessionBeadKeys.workBead: workBeadId,
    for (final step in completed)
      ...nodeStateMetadata('$workBeadId/$step', StepState.complete),
    for (final step in gated)
      ...nodeStateMetadata('$workBeadId/$step', StepState.gated),
    for (final entry in grades.entries)
      ...nodeResultMetadata('$workBeadId/${entry.key}', {'grade': entry.value}),
  },
);
