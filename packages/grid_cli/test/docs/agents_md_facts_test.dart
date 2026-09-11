import 'dart:io';

import 'package:test/test.dart';

void main() {
  // AGENTS.md is this repo's single source of agent instruction and CLAUDE.md
  // imports it (memento-engineering#agent-instructions-have-one-source). The
  // facts below moved with the content; only the filename changed.
  test('AGENTS.md records current proxied-server and coexistence facts', () {
    final claudeMd = File('../../AGENTS.md').readAsStringSync();

    expect(claudeMd, contains('Dolt **`proxied-server` mode**'));
    expect(
      claudeMd,
      contains('.beads/metadata.json` selects the mode and database'),
    );
    expect(claudeMd, contains('<proxy-root>/beads_dart.secret'));
    expect(claudeMd, contains('idle_timeout: -1'));
    expect(claudeMd, contains("the_grid's file-watch signal is advisory"));
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

  test('CLAUDE.md carries no content of its own — it imports AGENTS.md', () {
    final claudeMd = File('../../CLAUDE.md').readAsStringSync();

    // The decision permits an @AGENTS.md directive or a symlink; this repo
    // uses the directive, which survives a Windows clone where a symlink does
    // not. Anything else means the two files have started to drift, which is
    // the exact defect the decision was recorded to end.
    expect(claudeMd, contains('@AGENTS.md'));
    expect(
      claudeMd.length,
      lessThan(600),
      reason: 'a pointer, never a second copy of the guidance',
    );
  });
}
