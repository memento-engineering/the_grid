// Wire-key parity guard (DESIGN-tg-pm6.md §4, R1).
//
// `StationBeadWriter` (packages/grid_runtime/lib/src/lifecycle/
// station_bead_writer.dart) hand-retypes the `grid.circuit.*`/`grid.step.*`
// metadata-key literals as its own `static const String` fields — it CANNOT
// import `MoleculeCircuitKeys`/`MoleculeStepKeys` from this package because
// the dependency arc runs grid_engine → grid_runtime (grid_engine's pubspec
// depends on grid_runtime, never the reverse; grid_runtime cannot depend
// back on grid_engine without a cycle). Today that "kept wire-identical to
// them" claim (station_bead_writer.dart:147-159) is prose only — nothing
// forces the two literal sets to stay equal if one side is edited alone.
// This package sits on top of both, so it is the one place a same-value
// assertion can be authored without introducing a new dependency edge.
//
// Also asserts the disjointness half of the same invariant
// (molecule_schema.dart:119-131): `LeaseKeys`' `grid.lease.*` namespace is a
// vendor-owned lease surface that must never collide with the writer's keys.
import 'package:grid_engine/src/molecule/molecule_schema.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('StationBeadWriter molecule-key literals match MoleculeCircuitKeys/MoleculeStepKeys', () {
    test('grid.circuit.* pair (session, crumb)', () {
      expect(StationBeadWriter.moleculeSessionKey, MoleculeCircuitKeys.session);
      expect(StationBeadWriter.moleculeCrumbKey, MoleculeCircuitKeys.crumb);
    });

    test('grid.step.* pair (session, crumb, path, state, startedAt, finishedAt, durationMs, failureReason)', () {
      expect(StationBeadWriter.stepSessionKey, MoleculeStepKeys.session);
      expect(StationBeadWriter.stepCrumbKey, MoleculeStepKeys.crumb);
      expect(StationBeadWriter.stepPathKey, MoleculeStepKeys.path);
      expect(StationBeadWriter.stepStateKey, MoleculeStepKeys.state);
      expect(StationBeadWriter.stepStartedAtKey, MoleculeStepKeys.startedAt);
      expect(StationBeadWriter.stepFinishedAtKey, MoleculeStepKeys.finishedAt);
      expect(StationBeadWriter.stepDurationMsKey, MoleculeStepKeys.durationMs);
      expect(StationBeadWriter.stepFailureReasonKey, MoleculeStepKeys.failureReason);
    });

    test('grid.circuit.* and grid.step.* namespaces stay distinct by design', () {
      expect(StationBeadWriter.moleculeSessionKey, isNot(StationBeadWriter.stepSessionKey));
      expect(StationBeadWriter.moleculeCrumbKey, isNot(StationBeadWriter.stepCrumbKey));
    });

    test('LeaseKeys namespace does not overlap any StationBeadWriter key', () {
      final writerKeys = <String>{
        StationBeadWriter.startedAtKey,
        StationBeadWriter.closedAtKey,
        StationBeadWriter.rigKey,
        StationBeadWriter.gateRegateCountKey,
        StationBeadWriter.gateRegatedAtKey,
        StationBeadWriter.moleculeSessionKey,
        StationBeadWriter.moleculeCrumbKey,
        StationBeadWriter.stepSessionKey,
        StationBeadWriter.stepCrumbKey,
        StationBeadWriter.stepPathKey,
        StationBeadWriter.stepStateKey,
        StationBeadWriter.stepStartedAtKey,
        StationBeadWriter.stepFinishedAtKey,
        StationBeadWriter.stepDurationMsKey,
        StationBeadWriter.stepFailureReasonKey,
      };

      final leaseKeys = <String>{
        LeaseKeys.pgid,
        LeaseKeys.pid,
        LeaseKeys.token,
      };

      expect(writerKeys.intersection(leaseKeys), isEmpty);
      for (final key in writerKeys) {
        expect(
          key.startsWith(LeaseKeys.prefix),
          isFalse,
          reason: '$key must not fall under the vendor-owned ${LeaseKeys.prefix} namespace',
        );
      }
    });
  });
}
