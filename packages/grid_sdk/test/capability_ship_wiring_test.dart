// tg-xh5d WHAT #2 — publish-on-close needs a PRODUCER in the
// resident, not only a writer method with a unit test. Two rails carry it:
// `StationBeadWriter.close` publishes whatever the station itself closes, and
// the post-flush settle publishes what an OPERATOR closed by hand. Unwired, an
// `external:` row authored by `link` blocks its consumer forever.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('the post-flush rail drives the capability-export settle', () {
    final src = File('lib/src/work/work_assembly.dart').readAsStringSync();
    final afterFlush = src.substring(
      src.indexOf('void afterFlush()'),
      src.indexOf('Future<void> _settleGuarded('),
    );

    expect(
      afterFlush,
      contains('unawaited(_settlePostFlushGuarded())'),
      reason: 'the onFlushed hook must reach the settles',
    );
    expect(
      afterFlush,
      contains('_handler.settleCapabilityExports'),
      reason:
          'a bead an operator closed by hand publishes when the station '
          'observes the close, and a flush is that observation',
    );
    expect(
      afterFlush,
      contains('_handler.settleRosterDrains'),
      reason: 'the drain settle keeps its place on the same rail',
    );
  });

  // tg-xh5d RULING 2026-09-13 (3): publication remains suppressed under
  // --dry-run because it changes every other store's frontier.
  test('the capability settle is suppressed under --dry-run', () {
    final src = File('lib/src/work/work_assembly.dart').readAsStringSync();
    final settle = src.substring(
      src.indexOf('Future<void> _settlePostFlushGuarded()'),
      src.indexOf('Future<void> _settleGuarded('),
    );

    final gate = settle.indexOf('if (_dryRun) return;');
    final drain = settle.indexOf('_handler.settleRosterDrains');
    final ship = settle.indexOf('_handler.settleCapabilityExports');

    expect(gate, greaterThan(-1), reason: 'a dry run publishes no capability');
    expect(
      gate,
      lessThan(ship),
      reason: 'the gate must precede the ship, not follow it',
    );
    expect(
      drain,
      lessThan(gate),
      reason:
          'the drain settle is NOT a publication and keeps running dry — only '
          'the ship is withheld',
    );
  });

  test(
    'the settle publishes through the work store WRITER, not a second path',
    () {
      final src = File(
        'lib/src/command/station_command_handler.dart',
      ).readAsStringSync();
      final settle = src.substring(
        src.indexOf('Future<void> _settleCapabilityExports()'),
        src.indexOf('Future<GridCommandResult> call('),
      );

      expect(settle, contains('unshippedExports('));
      expect(settle, contains('healableExternalDepTargets('));
      expect(
        settle,
        contains('store.writer.shipExports('),
        reason:
            'one ship path: the chokepoint that ships on close ships on '
            'observation too',
      );
      expect(
        settle,
        isNot(contains('.ship(')),
        reason: 'the handler must not spell `bd ship` itself',
      );
    },
  );

  test('the bridge owns no external-dependency healer or publication path', () {
    for (final path in const [
      '../grid_engine/lib/src/bridge/federated_snapshot_source.dart',
      'lib/src/work/work_assembly.dart',
    ]) {
      final src = File(path).readAsStringSync();
      for (final forbidden in const [
        'ExternalDepHeal',
        'providesLabel(',
        '--add-label',
        '.addLabels(',
        '.shipExports(',
        'external.shipped',
      ]) {
        expect(src, isNot(contains(forbidden)), reason: '$path: $forbidden');
      }
    }
  });
}
