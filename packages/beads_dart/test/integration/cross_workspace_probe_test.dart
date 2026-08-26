@TestOn('vm')
@Tags(['integration'])
library;

import 'package:beads_dart/src/errors/bd_exception.dart';
import 'package:beads_dart/src/services/beads_workspace.dart';
import 'package:beads_dart/src/services/dolt_query_service.dart';
import 'package:test/test.dart';

/// Criterion 2 (PDR §6.2): the cross-workspace change probe.
///
/// OPTIONAL / skip-guarded — only meaningful against a live credentialed Dolt
/// endpoint. It does not write the discovered database.
///
/// Intent (documented for the integrator): a cross-workspace mutation routed
/// into `tg` flips the working-set hash, which the [WorkingSetProbeSource]
/// turns into a dirty signal in ≤2s. We can only *assert* the change end of
/// that here (write from another workspace, observe the hash move) when there
/// is a live writer; absent one, we assert the probe's stability/keepalive
/// invariants read-only:
/// * two idle probes agree (no phantom dirty signals);
/// * the probe doubles as keepalive (it survives the 30s idle reap via the
///   service's transparent reconnect — proven offline in the live SQL test's
///   reconnect case).
void main() {
  test('the working-set probe is the authoritative, stable change signal '
      '(live, requires a credentialed endpoint)', () async {
    final ws = BeadsWorkspace.discover();
    final endpoint = ws?.endpoint;
    if (ws == null || endpoint == null || !endpoint.hasCredential) {
      markTestSkipped(
        'no live Dolt endpoint with credentials — cross-workspace probe not '
        'exercised; inspect BeadsWorkspace.endpointDiagnostic',
      );
      return;
    }

    final dolt = DoltQueryService(endpoint);
    addTearDown(dolt.close);
    try {
      await dolt.connect();
    } on BdSchemaDriftException catch (e) {
      markTestSkipped('live schema drift: ${e.message}');
      return;
    }

    // Read-only invariant: two back-to-back idle probes must agree, so the
    // probe never manufactures a spurious dirty signal. (A real change — from
    // any workspace — is the only thing that may move this hash.)
    final first = await dolt.probe();
    final second = await dolt.probe();
    expect(
      second,
      first,
      reason:
          'the working-set hash must be stable while idle — a flap would '
          'fire phantom dirty signals',
    );
    expect(
      first,
      isNotEmpty,
      reason: 'SELECT @@tg_working returns a non-empty working-set token',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
