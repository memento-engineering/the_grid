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
