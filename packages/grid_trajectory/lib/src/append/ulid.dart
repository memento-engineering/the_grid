/// ULID minting for `record_id` / `attempt_id`-class CHAR(26) identities.
library;

import 'dart:math';

const String _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

final Random _random = Random.secure();

/// A 26-char Crockford-base32 ULID: 48-bit millisecond timestamp + 80 random
/// bits. Lexicographic order tracks mint time, which is all the schema asks
/// of `record_id` (`seq` carries the real order).
String mintUlid({DateTime? now}) {
  var millis = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
  final chars = List<int>.filled(26, 0);
  for (var i = 9; i >= 0; i--) {
    chars[i] = _crockford.codeUnitAt(millis & 0x1f);
    millis >>= 5;
  }
  for (var i = 10; i < 26; i++) {
    chars[i] = _crockford.codeUnitAt(_random.nextInt(32));
  }
  return String.fromCharCodes(chars);
}
