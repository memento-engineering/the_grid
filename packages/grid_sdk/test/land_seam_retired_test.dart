// tg-6gn — the `--land` ARMING SEAM is retired.
//
// Landing is no longer a station-level armed boolean threaded into every
// substation: a substation BINDS a `DeliveryMethod` on its `ServiceBundle`, and
// binding NONE is the commit-only posture (M5 D-4a). "Is landing armed?" became
// "which delivery method did this substation bind?", and none is a valid answer.
// ADR-0006 D3's policy is PRESERVED, not amended: the asset's bound method still
// pushes and opens a PR, and nothing auto-merges (the three landing MODES are a
// separate, deferred bead, which also carries the D3 amendment).
//
// If `buildLandOps` (or any other `armed:`-shaped land factory) reappears in
// grid_sdk, the flag came back. `ghRunner`/`GitOps`/`GhPrOpener` deliberately
// STAY exported — the asset's delivery method constructs them itself.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('grid_sdk names no --land arming seam', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'sanity: the lib dir was found');

    final dartFiles = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(dartFiles, isNotEmpty, reason: 'sanity: the sources were found');

    final hits = [
      for (final f in dartFiles)
        if (f.readAsStringSync().contains('buildLandOps')) f.path,
    ];
    expect(
      hits,
      isEmpty,
      reason:
          'the --land arming seam is retired: delivery is per-substation config '
          'on the ServiceBundle, not a station-level boolean:\n  '
          '${hits.join('\n  ')}',
    );
  });
}
