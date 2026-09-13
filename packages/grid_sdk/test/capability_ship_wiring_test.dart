// tg-xh5d WHAT #2 — the ship-on-close capability needs a PRODUCER in the
// resident, not only a writer method with a unit test. Two rails carry it:
// `StationBeadWriter.close` ships whatever the station itself closes, and the
// post-flush settle ships whatever an OPERATOR closed by hand. Unwired, an
// `external:` row authored by `link` blocks its consumer forever unless a
// human runs `bd ship` — the frontier half ships inert.
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
          'a bead an operator closed by hand ships the next time the station '
          'observes the close, and a flush is that observation',
    );
    expect(
      afterFlush,
      contains('_handler.settleRosterDrains'),
      reason: 'the drain settle keeps its place on the same rail',
    );
  });

  // tg-xh5d RULING 2026-09-13 (3): the ship observer STANDS, suppressed under
  // --dry-run. `bd ship` publishes a capability to every other store's
  // frontier, which is exactly the class of outcome a dry run withholds.
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

  test('the settle ships through the work store WRITER, not a second path', () {
    final src = File(
      'lib/src/command/station_command_handler.dart',
    ).readAsStringSync();
    final settle = src.substring(
      src.indexOf('Future<void> _settleCapabilityExports()'),
      src.indexOf('Future<GridCommandResult> call('),
    );

    expect(settle, contains('unshippedExports('));
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
  });
}
