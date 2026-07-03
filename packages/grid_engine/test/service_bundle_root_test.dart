// ServiceBundle.sourceControlFor — the per-bead root SELECTOR resolution
// (tg-7gm, `SCRATCH-grid-alignment.md` §6 amendment). Pure, zero I/O.
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

class _SourceControl implements SourceControl {
  const _SourceControl(this.label);
  final String label;

  @override
  String workspaceFor(String beadId) => '/$label/$beadId';

  @override
  String branchFor(String beadId) => 'grid/$beadId';

  @override
  String get baseBranch => 'main';

  @override
  bool get canLand => false;

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {}

  @override
  Future<void> commitAll({
    required String workspaceDir,
    required String message,
  }) async {}

  @override
  Future<void> push({
    required String workspaceDir,
    required String remote,
    required String branch,
  }) async {}

  @override
  Future<PrRef?> openPr({
    required String workspaceDir,
    required String branch,
    required String baseBranch,
    required String title,
  }) async => null;
}

void main() {
  group('ServiceBundle.sourceControlFor', () {
    test('null rootName resolves to the substation DEFAULT', () {
      const services = ServiceBundle(
        sourceControl: _SourceControl('default'),
        sourceControlsByRoot: {
          'power_station': _SourceControl('power_station'),
        },
      );
      expect(services.sourceControlFor(null), isA<_SourceControl>());
      expect(
        (services.sourceControlFor(null)! as _SourceControl).label,
        'default',
      );
    });

    test(
      'a REGISTERED extra root name resolves to that root\'s SourceControl',
      () {
        const services = ServiceBundle(
          sourceControl: _SourceControl('default'),
          sourceControlsByRoot: {
            'power_station': _SourceControl('power_station'),
          },
        );
        final sc =
            services.sourceControlFor('power_station')! as _SourceControl;
        expect(sc.label, 'power_station');
      },
    );

    test('an UNREGISTERED root name falls back to the default (defensive — the '
        'mount-boundary gate is the real enforcement point)', () {
      const services = ServiceBundle(sourceControl: _SourceControl('default'));
      final sc = services.sourceControlFor('nowhere')! as _SourceControl;
      expect(sc.label, 'default');
    });

    test(
      'no default and no match resolves to null (the offline no-source-control shape)',
      () {
        const services = ServiceBundle();
        expect(services.sourceControlFor('anything'), isNull);
        expect(services.sourceControlFor(null), isNull);
      },
    );
  });
}
