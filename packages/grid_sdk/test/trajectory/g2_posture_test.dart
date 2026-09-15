import 'package:grid_engine/grid_engine.dart' show DualReadMode;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('G2 defaults off and does not require a G1 certificate', () {
    const config = TrajectoryConfig();
    expect(config.g2Posture, G2Posture.off);
    expect(config.g1CertificatePassed, isNull);
    expect(config.g2G1PrerequisiteRefusal, isNull);
  });

  test(
    'shadow and cut both accept only the complete resolved prerequisite',
    () {
      for (final posture in [G2Posture.shadow, G2Posture.cut]) {
        final config = TrajectoryConfig(
          discipline: TrajectoryDiscipline.cut,
          g2Posture: posture,
          g1CertificatePassed: true,
        );
        expect(config.mode, TrajectoryConfigMode.required);
        expect(config.dualRead, DualReadMode.primary);
        expect(config.g2G1PrerequisiteRefusal, isNull);
      }
    },
  );

  test('certificate failures distinguish missing from uncertified', () {
    for (final posture in [G2Posture.shadow, G2Posture.cut]) {
      final missing = TrajectoryConfig(g2Posture: posture);
      expect(
        missing.g2G1PrerequisiteRefusal,
        isA<G2G1PrerequisiteRefused>()
            .having((value) => value.posture, 'posture', posture)
            .having((value) => value.field, 'field', 'g1Certificate')
            .having((value) => value.expected, 'expected', 'certified')
            .having((value) => value.actual, 'actual', 'missing'),
      );
      final uncertified = TrajectoryConfig(
        g2Posture: posture,
        g1CertificatePassed: false,
      );
      expect(
        uncertified.g2G1PrerequisiteRefusal,
        isA<G2G1PrerequisiteRefused>().having(
          (value) => value.actual,
          'actual',
          'uncertified',
        ),
      );
    }
  });

  test('mismatches are reported in deterministic field order', () {
    final discipline = const TrajectoryConfig(
      mode: TrajectoryConfigMode.required,
      dualRead: DualReadMode.primary,
      g2Posture: G2Posture.shadow,
      g1CertificatePassed: true,
    ).g2G1PrerequisiteRefusal!;
    expect(
      (discipline.field, discipline.expected, discipline.actual),
      ('discipline', 'cut', 'shadow'),
    );

    final mode = const TrajectoryConfig(
      discipline: TrajectoryDiscipline.cut,
      mode: TrajectoryConfigMode.auto,
      g2Posture: G2Posture.shadow,
      g1CertificatePassed: true,
    ).g2G1PrerequisiteRefusal!;
    expect(mode.field, 'mode');
    expect(mode.expected, 'required');
    expect(mode.actual, 'auto');

    final dualRead = const TrajectoryConfig(
      discipline: TrajectoryDiscipline.cut,
      dualRead: DualReadMode.observe,
      g2Posture: G2Posture.cut,
      g1CertificatePassed: true,
    ).g2G1PrerequisiteRefusal!;
    expect(dualRead.field, 'dualRead');
    expect(dualRead.expected, 'primary');
    expect(dualRead.actual, 'observe');
  });

  test('explicit cut contradictions stay visible behind resolved values', () {
    const config = TrajectoryConfig(
      discipline: TrajectoryDiscipline.cut,
      mode: TrajectoryConfigMode.disabled,
      dualRead: DualReadMode.off,
      g2Posture: G2Posture.cut,
      g1CertificatePassed: true,
    );
    expect(config.mode, TrajectoryConfigMode.required);
    expect(config.dualRead, DualReadMode.primary);
    expect(config.g2G1PrerequisiteRefusal!.field, 'mode');
    expect(config.g2G1PrerequisiteRefusal!.actual, 'disabled');
  });

  test('cloning preserves G2 inputs while rollback resolutions force off', () {
    const source = TrajectoryConfig(
      discipline: TrajectoryDiscipline.cut,
      g2Posture: G2Posture.shadow,
      g1CertificatePassed: true,
    );
    final cloned = source.withAppendedObligationQueries(const []);
    expect(cloned.g2Posture, G2Posture.shadow);
    expect(cloned.g1CertificatePassed, isTrue);

    expect(source.asDisabled.g2Posture, G2Posture.off);
    expect(source.resolveForAssembly(dryRun: true).g2Posture, G2Posture.off);
    final breakGlass = source.resolveForAssembly(
      dryRun: false,
      breakGlassReason: 'operator rollback',
    );
    expect(breakGlass.g2Posture, G2Posture.off);
    expect(breakGlass.g1CertificatePassed, isTrue);
    expect(breakGlass.g2G1PrerequisiteRefusal, isNull);
  });
}
