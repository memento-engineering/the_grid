/// The reentrant authoring SDK surface (ADR-0008 D2/D4 / M4-P1 §2).
///
/// The value-types + opaque interfaces an author composes — `Formula` /
/// `FormulaStep` / the cursor / the pure frontier predicate, and (Wave 3) the
/// `Capability` / `Service` interfaces. Fenced under `lib/src/sdk/` so the
/// package split into the public `the_grid` package over the now-private
/// `grid_engine` (ADR-0008 D1, deferred) is a move, not a rewrite. The author
/// NEVER touches a `Seed` — that is what holds the four derailment-invariants AT
/// DEPTH by construction.
library;

export 'cursor.dart';
export 'formula.dart';
export 'frontier.dart';
