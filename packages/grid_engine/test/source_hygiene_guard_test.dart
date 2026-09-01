/// A structural guard on the SOURCE ITSELF: no Dart file under `lib/` may
/// carry a raw NUL byte (r12).
///
/// This is not style. A literal U+0000 in a source file makes `file` classify
/// the whole file as binary `data`, and it makes plain `grep` return NOTHING
/// for that file — silently. Several guards in this very directory work by
/// reading and grepping sources; a NUL blinds them, and it blinds every
/// review and sweep besides. The escape (backslash-u-0000) has the identical string
/// value and none of the consequences, so the only cost of this rule is
/// remembering it — which is what this test is for.
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('no lib/ source carries a raw NUL byte — the escape, always', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.readAsBytesSync().contains(0)) offenders.add(entity.path);
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a literal U+0000 makes `grep` silently skip the file and every '
          'source-reading guard in this suite blind to it — write \\u0000',
    );
  });
}
