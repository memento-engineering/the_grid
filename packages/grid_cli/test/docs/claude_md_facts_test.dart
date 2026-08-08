import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('CLAUDE.md records current proxied-server and coexistence facts', () {
    final claudeMd = File('../../CLAUDE.md').readAsStringSync();

    expect(claudeMd, contains('Dolt **`proxied-server` mode**'));
    expect(
      claudeMd,
      contains('.beads/metadata.json` selects the mode and database'),
    );
    expect(claudeMd, contains('<proxy-root>/beads_dart.secret'));
    expect(claudeMd, contains('idle_timeout: -1'));
    expect(
      claudeMd,
      contains("the_grid's file-watch signal is advisory"),
    );
    expect(
      claudeMd,
      contains('single-writer-per-bead as a disjoint ownership partition'),
    );
    expect(claudeMd, contains('strictly read-only'));

    expect(claudeMd, isNot(contains('34947')));
    expect(claudeMd, isNot(contains('GT_ROOT')));
    expect(claudeMd, isNot(contains('gc owns them')));
    expect(claudeMd, isNot(contains('reaps idle connections at 30s')));
  });
}
