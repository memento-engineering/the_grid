/// The reentrant authoring SDK surface (ADR-0008 D2/D4 / M4-P1 §2).
///
/// The value-types + opaque interfaces an author composes — `Circuit` /
/// `CircuitStep` / the cursor / the pure frontier predicate, and (Wave 3) the
/// `Capability` / `Service` interfaces. Fenced under `lib/src/sdk/` so the
/// package split into the public `the_grid` package over the now-private
/// `grid_engine` (ADR-0008 D1, deferred) is a move, not a rewrite. The author
/// NEVER touches a `Seed` — that is what holds the four derailment-invariants AT
/// DEPTH by construction.
///
/// [federation_protocol.dart] + [capability_facts.dart] are the TRANSPORT-FREE
/// federation contracts (ADR-0011, the honesty-pass D-A9/D-B5 split,
/// 2026-07-03) — power_station's `federated_grid_assets` supplies the transport
/// impls over these same types. [claim.dart] is the pure D-A3 claim predicate
/// over them (AL-6a, D-B5 hook #1) — an asset claim capability's whole input;
/// still no transport, no bus.
library;

export 'allocation.dart';
export 'capability_facts.dart';
export 'claim.dart';
export 'cursor.dart';
export 'circuit.dart';
export 'federation_protocol.dart';
export 'frontier.dart';
export 'lease.dart';
